`timescale 1ns / 1ps
// ============================================================
// fsm_uart_tb.sv  -  Auto-verifying testbench for fsm_uart
// ============================================================
// Clock  : 100 MHz (10 ns period)
// BRAM   : synchrone, latence lecture 1 cycle (fidèle Xilinx)
// TxBusy : simulé - reste haut 5 cycles après chaque Load_o
//
// Commandes testées :
//   K  - clé 128 bits         → Key_o     + ACK "OK\n"
//   N  - nonce 128 bits       → Nonce_o   + ACK
//   A  - associated data 64b  → Ad_o      + ACK
//   W  - 23 mots wave → BRAM  → mem[0..22]+ ACK
//   G  - start ASCON           → Start_ascon_o + ACK
//   C  - 23 mots cipher        → 184 octets TX  + ACK
//   T  - 2 mots tag            → 16 octets TX   + ACK
//
// Timing clé :
//   idle_keyX / idle_nonceX / idle_assoc_dataX :
//     RXRdy_i=1 déclenche trans_receive (en_trans_s=1).
//     data_converted_s stable dans idle_key1.
//     FSM revient dans idle_keyX après 3 cycles.
//     → attente minimale 8 posedge entre octets.
//
//   ACK "OK\n" :
//     Le 'O' peut être émis PENDANT le dernier send_byte.
//     tx_wp cumulatif → wait_tx() surveille le total pour
//     éviter de manquer l'impulsion.
// ============================================================
module fsm_uart_tb;

  // ─── Ports DUT ────────────────────────────────────────────
  logic         clock_i, resetb_i, RXErr_i, RXRdy_i, TxBusy_i;
  logic [7:0]   RxData_i;
  logic         CipherRdy_i;
  logic [7:0]   TxByte_o;
  logic [127:0] Key_o, Nonce_o;
  logic [63:0]  Ad_o;
  logic         Start_ascon_o, Load_o;
  logic         bram_ena_o;
  logic [0:0]   bram_wea_o;
  logic [5:0]   bram_addra_o;
  logic [63:0]  bram_dina_o, bram_douta_i;

  // ─── DUT ──────────────────────────────────────────────────
  fsm_uart dut (
    .clock_i      (clock_i),
    .resetb_i     (resetb_i),
    .RXErr_i      (RXErr_i),
    .RXRdy_i      (RXRdy_i),
    .TxBusy_i     (TxBusy_i),
    .RxData_i     (RxData_i),
    .CipherRdy_i  (CipherRdy_i),
    .TxByte_o     (TxByte_o),
    .Key_o        (Key_o),
    .Nonce_o      (Nonce_o),
    .Ad_o         (Ad_o),
    .Start_ascon_o(Start_ascon_o),
    .Load_o       (Load_o),
    .bram_ena_o   (bram_ena_o),
    .bram_wea_o   (bram_wea_o),
    .bram_addra_o (bram_addra_o),
    .bram_dina_o  (bram_dina_o),
    .bram_douta_i (bram_douta_i)
  );

  // ─── Horloge 100 MHz ─────────────────────────────────────
  initial clock_i = 1'b0;
  always  #5 clock_i = ~clock_i;

  // ─── VCD ─────────────────────────────────────────────────
  initial begin
    $dumpfile("fsm_uart_tb.vcd");
    $dumpvars(0, fsm_uart_tb);
  end

  // ─── Modèle BRAM synchrone (latence 1 cycle, Xilinx-like) ─
  // Mémoire 64 × 64 bits.
  //   Zones : wave  = 0..22, cipher = 32..54, tag = 55..56
  // Lecture : bram_douta_i valide 1 cycle après (ena=1, addr).
  // Écriture directe autorisée dans initial (pas de conflit si
  //          bram_ena_o=0 au moment de l'écriture).
  logic [63:0] mem [0:63];

  always_ff @(posedge clock_i) begin
    if (bram_ena_o) begin
      if (bram_wea_o[0]) mem[bram_addra_o] <= bram_dina_o;
      bram_douta_i <= mem[bram_addra_o];
    end
  end

  // ─── Simulateur TxBusy : haut 5 cycles après Load_o ──────
  // La FSM attend wait_xxx_high (TxBusy=1) puis wait_xxx_low
  // (TxBusy=0) pour chaque octet émis.
  // 5 cycles donne : send(1cy) → high(1cy) → wait_low(5cy) ≈
  //   10 cy/octet, cohérent avec le pipeline FSM.
  integer tx_timer;
  always_ff @(posedge clock_i or negedge resetb_i) begin
    if (!resetb_i) begin
      TxBusy_i <= 1'b0;
      tx_timer  <= 0;
    end else if (Load_o && !TxBusy_i) begin
      TxBusy_i <= 1'b1;
      tx_timer  <= 5;
    end else if (tx_timer > 1) begin
      tx_timer  <= tx_timer - 1;
    end else if (tx_timer == 1) begin
      tx_timer  <= 0;
      TxBusy_i  <= 1'b0;
    end
  end

  // ─── Capture globale des octets émis via Load_o ───────────
  // tx_log[n] = n-ième octet vu sur TxByte_o quand Load_o=1.
  // tx_wp = index d'écriture courant (jamais remis à zéro
  //         entre commandes → comparaison via wp_base capturé
  //         avant chaque commande).
  logic [7:0] tx_log [0:1023];
  integer     tx_wp;

  always_ff @(posedge clock_i or negedge resetb_i) begin
    if (!resetb_i) tx_wp <= 0;
    else if (Load_o) begin
      tx_log[tx_wp] <= TxByte_o;
      tx_wp         <= tx_wp + 1;
    end
  end

  always @(posedge clock_i) begin
    if (Load_o)
    $display("[%0t ns] TX = %02h", $time, TxByte_o);
  end
  // ─── Capture sticky de Start_ascon_o ──────────────────────
  logic start_seen;
  always_ff @(posedge clock_i or negedge resetb_i) begin
    if (!resetb_i)      start_seen <= 1'b0;
    else if (Start_ascon_o) start_seen <= 1'b1;
  end

  // ─── Compteur d'erreurs global ────────────────────────────
  integer errors;

  // ─── Variables partagées (déclarées au module pour iverilog) ─
  integer i, j, wp_base, fail_cnt, tto;
  logic [7:0] wb;       // octet de travail (wave, comparaisons)
  logic [7:0] got_b, exp_b;

  // ─── Valeurs de référence ─────────────────────────────────
  logic [127:0] key_ref;
  logic [127:0] nonce_ref;
  logic [63:0]  ad_ref;
  logic [63:0]  cipher_ref [0:22];
  logic [63:0]  tag_ref    [0:1];

  // =============================================================
  // Tâches de stimulus
  // =============================================================

  // Envoie un octet sur RxData_i avec une impulsion RXRdy_i
  // d'un cycle.  Attente 8 posedge ensuite pour laisser la FSM
  // traiter (idle_keyX → ... → idle_keyX = 3 cycles minimum).
  // Pour la commande 'W', le 8e octet de chaque mot déclenche
  // aussi l'écriture BRAM (2 cycles extra) → 8 cycles suffit.
  task automatic send_byte;
    input [7:0] b;
    begin
      @(negedge clock_i);
      RxData_i = b;
      RXRdy_i  = 1'b1;
      @(negedge clock_i);
      RXRdy_i  = 1'b0;
      repeat(8) @(posedge clock_i);
    end
  endtask

  // Envoie une commande ASCII.
  // Attend d'abord que TxBusy_i=0 (ACK précédent terminé),
  // puis envoie l'octet commande, puis 6 cycles de garde.
  // La FSM lit RxData_i directement dans get_cmd (sans
  // trans_receive), donc RxData_i doit être stable au cycle
  // suivant le posedge où RXRdy_i est vu.
  task automatic send_cmd;
    input [7:0] cmd;
    begin
      $display("\n[%0t ns] === CMD: 0x%02h ===", $time, cmd);
      while (TxBusy_i) @(posedge clock_i);
      repeat(2) @(posedge clock_i);
      @(negedge clock_i);
      RxData_i = cmd;
      RXRdy_i  = 1'b1;
      @(negedge clock_i);
      RXRdy_i  = 1'b0;
      repeat(6) @(posedge clock_i);
    end
  endtask

  // Envoie un mot de 64 bits, MSB en premier
  task automatic send_64;
    input [63:0] w;
    integer k;
    begin
      for (k = 7; k >= 0; k = k - 1)
        send_byte(w[k*8 +: 8]);
    end
  endtask

  // Envoie un mot de 128 bits, MSB en premier
  task automatic send_128;
    input [127:0] w;
    integer k;
    begin
      for (k = 15; k >= 0; k = k - 1)
        send_byte(w[k*8 +: 8]);
    end
  endtask

  // Attend que tx_wp atteigne 'target' (timeout 8000 cycles).
  // Un posedge supplémentaire est ajouté pour la phase NBA.
  // Utilisation du compteur cumulatif tx_wp : la valeur
  // wp_base capturée avant la commande sert de référence.
  // RXRdy 'O' peut être émis AVANT que send_128 retourne ;
  // comme wait_tx surveille le cumulatif, il ne rate rien.
  task automatic wait_tx;
    input integer target;
    begin
      tto = 0;
      while (tx_wp < target && tto < 8000) begin
        @(posedge clock_i);
        tto = tto + 1;
      end
      @(posedge clock_i);   // stabilisation NBA
      if (tto >= 8000)
        $display("  [WARN] wait_tx(%0d) timeout  tx_wp=%0d", target, tx_wp);
    end
  endtask

  // =============================================================
  // Stimulus principal
  // =============================================================
  initial begin
    // ─── Initialisation des références ──────────────────────
    key_ref   = 128'h8A55114D1CB6A9A2BE263D4D7AECAAFF;
    nonce_ref = 128'h4ED0EC0B98C529B7C8CDDF37BCD0284A;
    ad_ref    = 64'h4120746F20428000;

    cipher_ref[0]  = 64'h2014293975F92C24;
    cipher_ref[1]  = 64'h277A15BF4F42C62E;
    cipher_ref[2]  = 64'hB56550BA5A29870E;
    cipher_ref[3]  = 64'hEE6DBFA9F0AFF0DC;
    cipher_ref[4]  = 64'hCA71887F6DD732C6;
    cipher_ref[5]  = 64'h7FF241C5144E58B6;
    cipher_ref[6]  = 64'hD730AF639D60790F;
    cipher_ref[7]  = 64'hFF5DA70DA06295B8;
    cipher_ref[8]  = 64'h637C849B9D55BD2F;
    cipher_ref[9]  = 64'hE312CB7FE1E7626F;
    cipher_ref[10] = 64'h12BDF5520F47E6A0;
    cipher_ref[11] = 64'h74E75AA85A95DB94;
    cipher_ref[12] = 64'h6F43F6A11EA7D258;
    cipher_ref[13] = 64'h4CD5873DD722432A;
    cipher_ref[14] = 64'h752000D1955C1DE0;
    cipher_ref[15] = 64'hFB7DDD638E1E2048;
    cipher_ref[16] = 64'h5B8FD4D926FEA205;
    cipher_ref[17] = 64'h7B79E3405B92D26D;
    cipher_ref[18] = 64'h0F652F1DE997CC61;
    cipher_ref[19] = 64'h70F999F789B8A488;
    cipher_ref[20] = 64'h6419D5FA646B63AC;
    cipher_ref[21] = 64'hF15C4D23D5E35B71;
    cipher_ref[22] = 64'h33CE50163B6B262A;

    tag_ref[0] = 64'hE23931733902C7CA;
    tag_ref[1] = 64'h084E9B4DA1E50CEF;

    // ─── Initialisation entrées ──────────────────────────────
    resetb_i    = 1'b0;
    RXErr_i     = 1'b0;
    RXRdy_i     = 1'b0;
    RxData_i    = 8'h00;
    CipherRdy_i = 1'b0;
    errors      = 0;

    for (i = 0; i < 64; i = i+1) mem[i] = 64'd0;

    repeat(10) @(posedge clock_i);
    resetb_i = 1'b1;
    repeat(5)  @(posedge clock_i);

    $display("============================================================");
    $display("  fsm_uart_tb - protocole ASCON-UART (7 commandes)");
    $display("============================================================");

    // ─────────────────────────────────────────────────────────
    // TEST 1 : Commande K - chargement clé 128 bits
    //
    // Attend : Key_o == key_ref  +  ACK "OK\n" (3 octets TX)
    // L'ACK peut commencer pendant le dernier send_byte ; on
    // utilise wait_tx(wp_base+3) pour attendre les 3 impulsions.
    // ─────────────────────────────────────────────────────────
    $display("\n[TEST 1] Commande K - cle 128 bits");
    wp_base = tx_wp;
    send_cmd(8'h4B);        // 'K'
    send_128(key_ref);
    wait_tx(wp_base + 3);   // "OK\n"

    if (Key_o === key_ref)
      $display("  [PASS] Key_o = %032h", Key_o);
    else begin
      $display("  [FAIL] Key_o  got %032h", Key_o);
      $display("                exp %032h", key_ref);
      errors = errors + 1;
    end

    if (tx_log[wp_base]   == 8'h4F &&
        tx_log[wp_base+1] == 8'h4B &&
        tx_log[wp_base+2] == 8'h0A)
      $display("  [PASS] ACK = \"OK\\n\"");
    else begin
      $display("  [FAIL] ACK: %02h %02h %02h  (exp 4F 4B 0A)",
               tx_log[wp_base], tx_log[wp_base+1], tx_log[wp_base+2]);
      errors = errors + 1;
    end

    // ─────────────────────────────────────────────────────────
    // TEST 2 : Commande N - nonce 128 bits
    // ─────────────────────────────────────────────────────────
    $display("\n[TEST 2] Commande N - nonce 128 bits");
    wp_base = tx_wp;
    send_cmd(8'h4E);        // 'N'
    send_128(nonce_ref);
    wait_tx(wp_base + 3);

    if (Nonce_o === nonce_ref)
      $display("  [PASS] Nonce_o = %032h", Nonce_o);
    else begin
      $display("  [FAIL] Nonce_o got %032h", Nonce_o);
      $display("                exp %032h", nonce_ref);
      errors = errors + 1;
    end

    if (tx_log[wp_base]   == 8'h4F &&
        tx_log[wp_base+1] == 8'h4B &&
        tx_log[wp_base+2] == 8'h0A)
      $display("  [PASS] ACK = \"OK\\n\"");
    else begin
      $display("  [FAIL] ACK: %02h %02h %02h",
               tx_log[wp_base], tx_log[wp_base+1], tx_log[wp_base+2]);
      errors = errors + 1;
    end

    // ─────────────────────────────────────────────────────────
    // TEST 3 : Commande A - associated data 64 bits
    // ─────────────────────────────────────────────────────────
    $display("\n[TEST 3] Commande A - associated data 64 bits");
    wp_base = tx_wp;
    send_cmd(8'h41);        // 'A'
    send_64(ad_ref);
    wait_tx(wp_base + 3);

    if (Ad_o === ad_ref)
      $display("  [PASS] Ad_o = %016h", Ad_o);
    else begin
      $display("  [FAIL] Ad_o  got %016h  exp %016h", Ad_o, ad_ref);
      errors = errors + 1;
    end

    if (tx_log[wp_base]   == 8'h4F &&
        tx_log[wp_base+1] == 8'h4B &&
        tx_log[wp_base+2] == 8'h0A)
      $display("  [PASS] ACK = \"OK\\n\"");
    else begin
      $display("  [FAIL] ACK: %02h %02h %02h",
               tx_log[wp_base], tx_log[wp_base+1], tx_log[wp_base+2]);
      errors = errors + 1;
    end

    // ─────────────────────────────────────────────────────────
    // TEST 4 : Commande W - 23 mots wave → BRAM[0..22]
    //
    // Valeur wave[i] = {8{(i+1)[7:0]}} :
    //   wave[0] = 64'h0101010101010101
    //   wave[1] = 64'h0202020202020202
    //   ...
    //   wave[22]= 64'h1717171717171717
    //
    // La FSM écrit dans la BRAM après chaque 8e octet reçu.
    // On lit mem[] directement (pas de BRAM IP requise).
    // ─────────────────────────────────────────────────────────
    $display("\n[TEST 4] Commande W - 23x64 bits wave -> BRAM[0..22]");
    wp_base = tx_wp;
    send_cmd(8'h57);        // 'W'
    for (i = 0; i < 23; i = i+1) begin
      wb = (i + 1) & 8'hFF;
      send_64({wb, wb, wb, wb, wb, wb, wb, wb});
    end
    wait_tx(wp_base + 3);

    fail_cnt = 0;
    for (i = 0; i < 23; i = i+1) begin
      wb = (i + 1) & 8'hFF;
      if (mem[i] !== {wb, wb, wb, wb, wb, wb, wb, wb}) begin
        $display("  [FAIL] mem[%02d] got %016h  exp %016h",
                 i, mem[i], {wb, wb, wb, wb, wb, wb, wb, wb});
        fail_cnt = fail_cnt + 1;
        errors   = errors   + 1;
      end
    end
    if (fail_cnt == 0)
      $display("  [PASS] BRAM[0..22] = 23 mots wave corrects");

    if (tx_log[wp_base]   == 8'h4F &&
        tx_log[wp_base+1] == 8'h4B &&
        tx_log[wp_base+2] == 8'h0A)
      $display("  [PASS] ACK = \"OK\\n\"");
    else begin
      $display("  [FAIL] ACK: %02h %02h %02h",
               tx_log[wp_base], tx_log[wp_base+1], tx_log[wp_base+2]);
      errors = errors + 1;
    end

    // ─────────────────────────────────────────────────────────
    // TEST 5 : Commande G - démarrage ASCON
    //
    // La FSM entre dans start_ascon (Start_ascon_o=1, 1 cycle)
    // puis wait_end_ascon (attend CipherRdy_i=1).
    // On attend 10 cycles avant de lever CipherRdy_i.
    // Après CipherRdy → wait_idle_o → ACK "OK\n".
    // ─────────────────────────────────────────────────────────
    $display("\n[TEST 5] Commande G - start ASCON + CipherRdy");
    wp_base = tx_wp;
    send_cmd(8'h47);        // 'G'
    repeat(10) @(posedge clock_i);
    CipherRdy_i = 1'b1;
    @(posedge clock_i);
    CipherRdy_i = 1'b0;
    wait_tx(wp_base + 3);

    if (start_seen)
      $display("  [PASS] Start_ascon_o pulse detecte");
    else begin
      $display("  [FAIL] Start_ascon_o jamais asserte");
      errors = errors + 1;
    end

    if (tx_log[wp_base]   == 8'h4F &&
        tx_log[wp_base+1] == 8'h4B &&
        tx_log[wp_base+2] == 8'h0A)
      $display("  [PASS] ACK = \"OK\\n\"");
    else begin
      $display("  [FAIL] ACK: %02h %02h %02h",
               tx_log[wp_base], tx_log[wp_base+1], tx_log[wp_base+2]);
      errors = errors + 1;
    end

    // ─────────────────────────────────────────────────────────
    // TEST 6 : Commande C - retransmission 23 mots cipher
    //
    // Précharge : mem[32..54] = cipher_ref[0..22]
    //             mem[55..56] = tag_ref[0..1]
    //             (la commande T le lira aussi)
    //
    // La FSM lit chaque mot via BRAM (2 cycles latence),
    // puis émet 8 octets MSB first.
    //   tx_log[wp_base + i*8 + j] = cipher_ref[i][(7-j)*8 +: 8]
    //
    // Attente : 23×8 = 184 octets + 3 ACK = 187 Load_o pulses.
    // ─────────────────────────────────────────────────────────
    $display("\n[TEST 6] Commande C - 23 mots cipher (184 octets)");
    for (i = 0; i < 23; i = i+1) mem[32+i] = cipher_ref[i];
    mem[55] = tag_ref[0];
    mem[56] = tag_ref[1];

    wp_base = tx_wp;
    send_cmd(8'h43);        // 'C'
    wait_tx(wp_base + 187); // 184 data + 3 ACK

    fail_cnt = 0;
    for (i = 0; i < 23; i = i+1) begin
      for (j = 0; j < 8; j = j+1) begin
        got_b = tx_log[wp_base + i*8 + j];
        exp_b = cipher_ref[i][(7-j)*8 +: 8]; // MSB first
        if (got_b !== exp_b) begin
          $display("  [FAIL] C[%02d] byte[%0d]  got %02h  exp %02h",
                   i, j, got_b, exp_b);
          fail_cnt = fail_cnt + 1;
          errors   = errors   + 1;
        end
      end
    end
    if (fail_cnt == 0)
      $display("  [PASS] 184 octets cipher retransmis fidèlement");

    if (tx_log[wp_base+184] == 8'h4F &&
        tx_log[wp_base+185] == 8'h4B &&
        tx_log[wp_base+186] == 8'h0A)
      $display("  [PASS] ACK = \"OK\\n\" (apres cipher)");
    else begin
      $display("  [FAIL] ACK cipher: %02h %02h %02h",
               tx_log[wp_base+184], tx_log[wp_base+185], tx_log[wp_base+186]);
      errors = errors + 1;
    end

    // ─────────────────────────────────────────────────────────
    // TEST 7 : Commande T - retransmission tag (2 mots = 16 B)
    //
    // La FSM lit mem[55] et mem[56] (tag_ref[0..1]).
    // Émet 16 octets MSB first + ACK "OK\n".
    //   tx_log[wp_base + 0..7]  = tag_ref[0] MSB→LSB
    //   tx_log[wp_base + 8..15] = tag_ref[1] MSB→LSB
    //   tx_log[wp_base + 16..18]= "OK\n"
    //
    // Attente : 2×8 = 16 octets + 3 ACK = 19 Load_o pulses.
    // ─────────────────────────────────────────────────────────
    $display("\n[TEST 7] Commande T - tag 2x64 bits (16 octets)");
    wp_base = tx_wp;
    send_cmd(8'h54);        // 'T'
    wait_tx(wp_base + 19);  // 16 data + 3 ACK

    fail_cnt = 0;
    for (i = 0; i < 2; i = i+1) begin
      for (j = 0; j < 8; j = j+1) begin
        got_b = tx_log[wp_base + i*8 + j];
        exp_b = tag_ref[i][(7-j)*8 +: 8];
        if (got_b !== exp_b) begin
          $display("  [FAIL] T[%0d] byte[%0d]  got %02h  exp %02h",
                   i, j, got_b, exp_b);
          fail_cnt = fail_cnt + 1;
          errors   = errors   + 1;
        end
      end
    end
    if (fail_cnt == 0)
      $display("  [PASS] 16 octets tag retransmis fidèlement");

    if (tx_log[wp_base+16] == 8'h4F &&
        tx_log[wp_base+17] == 8'h4B &&
        tx_log[wp_base+18] == 8'h0A)
      $display("  [PASS] ACK = \"OK\\n\" (apres tag)");
    else begin
      $display("  [FAIL] ACK tag: %02h %02h %02h",
               tx_log[wp_base+16], tx_log[wp_base+17], tx_log[wp_base+18]);
      errors = errors + 1;
    end

    // ─────────────────────────────────────────────────────────
    // Résumé
    // ─────────────────────────────────────────────────────────
    $display("\n============================================================");
    if (errors == 0)
      $display("  TOUS LES TESTS PASSENT  -  0 ECHEC");
    else
      $display("  %0d ECHEC(S) DETECTE(S)", errors);
    $display("============================================================");
    $finish;
  end

endmodule
