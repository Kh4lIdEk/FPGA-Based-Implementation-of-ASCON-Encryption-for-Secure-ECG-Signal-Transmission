`timescale 1ns / 1ps
// ============================================================
// ascon_top_tb_xsim.sv  -  Testbench ASCON_TOP pour Vivado/XSim
// ============================================================
// CORRECTIONS APPLIQUÉES (vs version précédente) :
//
//  FIX 1 - clock_i : 50 MHz → 125 MHz  [CRITIQUE / CAUSE RACINE]
//  FIX 2 - localparam real → localparam integer  [XSim]
//  FIX 3 - always #4  (littéral entier)  [XSim]
//  FIX 4 - wait_rx timeout adapté à 125 MHz
//  FIX 5 - Variable hors du named-initial-block  [XSim]
//  FIX 6 - Suppression du mot-clé 'automatic'  [XSim]
// ============================================================

module ascon_top_tb;

  localparam integer CLK_HALF_NS = 4;      // 125 MHz  →  FIX 1+3
  localparam integer BIT_NS      = 8960;   // 448 × 20 ns @ 50 MHz interne  →  FIX 2
  localparam integer HALF_BIT_NS = 4480;

  logic        clock_i, reset_i, Rx_i;
  logic [2:0]  Baud_i;
  logic        Tx_o;
  logic [2:0]  Baud_o;
  logic        RTS_o;

  ascon_top dut (
    .clock_i (clock_i), .reset_i (reset_i), .Rx_i (Rx_i),
    .Baud_i  (Baud_i),  .Tx_o    (Tx_o),    .Baud_o (Baud_o), .RTS_o (RTS_o)
  );

  // FIX 1+3 : 125 MHz, littéral entier
  initial clock_i = 1'b0;
  always  #4 clock_i = ~clock_i;

  // FIX 5 : variable au niveau module
  logic [7:0] rx_log [0:4095];
  integer     rx_wp;
  logic [7:0] rx_capture_got;

  // FIX 6 : sans 'automatic'
  task capture_uart_byte;
    output [7:0] b;
    integer k;
    begin
      @(negedge Tx_o);
      #(HALF_BIT_NS + BIT_NS);
      b = 8'h00;
      for (k = 0; k < 8; k = k+1) begin
        b[k] = Tx_o;
        if (k < 7) #(BIT_NS);
      end
      #(HALF_BIT_NS);
    end
  endtask

  initial begin : rx_capture_thread
    rx_wp = 0;
    wait (reset_i === 1'b1);
    wait (reset_i === 1'b0);
    repeat(100) @(posedge clock_i);
    forever begin
      capture_uart_byte(rx_capture_got);
      rx_log[rx_wp] = rx_capture_got;
      rx_wp = rx_wp + 1;
    end
  end

  // FIX 4+6 : timeout 10M cycles × 8 ns = 80 ms sim
  task wait_rx;
    input integer target;
    integer t;
    begin
      t = 0;
      while (rx_wp < target && t < 10_000_000) begin
        @(posedge clock_i);
        t = t + 1;
      end
      repeat(10) @(posedge clock_i);
      if (t >= 10_000_000)
        $display("  [WARN] wait_rx(%0d) TIMEOUT  rx_wp=%0d", target, rx_wp);
    end
  endtask

  // FIX 2+6 : integer delays, sans 'automatic'
  task uart_send_byte;
    input [7:0] b;
    integer k;
    begin
      $display("[%0t ns] TX: 0x%02h", $time, b);
      Rx_i = 1'b0;
      #(BIT_NS);
      for (k = 0; k < 8; k = k+1) begin
        Rx_i = b[k];
        #(BIT_NS);
      end
      Rx_i = 1'b1;
      #(BIT_NS);
    end
  endtask

  task uart_send_64;
    input [63:0] w;
    integer k;
    begin
      for (k = 7; k >= 0; k = k-1)
        uart_send_byte(w[k*8 +: 8]);
    end
  endtask

  task uart_send_128;
    input [127:0] w;
    integer k;
    begin
      for (k = 15; k >= 0; k = k-1)
        uart_send_byte(w[k*8 +: 8]);
    end
  endtask

  integer errors, i, j, rx_base, fail_cnt;
  logic [7:0] got_b, exp_b;
  logic [127:0] key_ref, nonce_ref;
  logic [63:0]  ad_ref;
  logic [63:0]  cipher_ref [0:22];
  logic [63:0]  tag_ref    [0:1];

  task check_ack;
    input integer base;
    begin
      if (rx_log[base]   == 8'h4F &&
          rx_log[base+1] == 8'h4B &&
          rx_log[base+2] == 8'h0A)
        $display("  [PASS] ACK = \"OK\\n\"");
      else begin
        $display("  [FAIL] ACK: %02h %02h %02h  (attendu 4F 4B 0A)",
                 rx_log[base], rx_log[base+1], rx_log[base+2]);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    key_ref   = 128'h8A55114D1CB6A9A2BE263D4D7AECAAFF;
    nonce_ref = 128'h4ED0EC0B98C529B7C8CDDF37BCD0284A;
    ad_ref    = 64'h4120746F20428000;
    cipher_ref[0]  = 64'h2014293975F92C24; cipher_ref[1]  = 64'h277A15BF4F42C62E;
    cipher_ref[2]  = 64'hB56550BA5A29870E; cipher_ref[3]  = 64'hEE6DBFA9F0AFF0DC;
    cipher_ref[4]  = 64'hCA71887F6DD732C6; cipher_ref[5]  = 64'h7FF241C5144E58B6;
    cipher_ref[6]  = 64'hD730AF639D60790F; cipher_ref[7]  = 64'hFF5DA70DA06295B8;
    cipher_ref[8]  = 64'h637C849B9D55BD2F; cipher_ref[9]  = 64'hE312CB7FE1E7626F;
    cipher_ref[10] = 64'h12BDF5520F47E6A0; cipher_ref[11] = 64'h74E75AA85A95DB94;
    cipher_ref[12] = 64'h6F43F6A11EA7D258; cipher_ref[13] = 64'h4CD5873DD722432A;
    cipher_ref[14] = 64'h752000D1955C1DE0; cipher_ref[15] = 64'hFB7DDD638E1E2048;
    cipher_ref[16] = 64'h5B8FD4D926FEA205; cipher_ref[17] = 64'h7B79E3405B92D26D;
    cipher_ref[18] = 64'h0F652F1DE997CC61; cipher_ref[19] = 64'h70F999F789B8A488;
    cipher_ref[20] = 64'h6419D5FA646B63AC; cipher_ref[21] = 64'hF15C4D23D5E35B71;
    cipher_ref[22] = 64'h33CE50163B6B262A;
    tag_ref[0] = 64'hE23931733902C7CA;
    tag_ref[1] = 64'h084E9B4DA1E50CEF;

    errors  = 0;
    Rx_i    = 1'b1;
    Baud_i  = 3'b000;
    reset_i = 1'b0;
    repeat(10) @(posedge clock_i);
    reset_i = 1'b1;
    $display("[%0t ns] Reset asserted  (clock_i = 125 MHz)", $time);
    repeat(200) @(posedge clock_i);
    reset_i = 1'b0;
    $display("[%0t ns] Reset released - attente PLL lock (2000 cycles)...", $time);
    repeat(2000) @(posedge clock_i);    // 2000 × 8 ns = 16 µs → PLL stable
    $display("[%0t ns] Debut stimulation UART", $time);

    $display("==========================================================");
    $display("  ASCON_TOP TB  -  clock_i=125MHz  /  int=50MHz  /  8N1");
    $display("  BIT_NS=%0d ns (448 cyc @ 50 MHz interne)", BIT_NS);
    $display("==========================================================");

    // TEST 1 : K
    $display("\n[TEST 1] Commande K - cle 128 bits");
    rx_base = rx_wp;
    uart_send_byte(8'h4B);
    uart_send_128(key_ref);
    wait_rx(rx_base + 3);
    check_ack(rx_base);

    // TEST 2 : N
    $display("\n[TEST 2] Commande N - nonce 128 bits");
    rx_base = rx_wp;
    uart_send_byte(8'h4E);
    uart_send_128(nonce_ref);
    wait_rx(rx_base + 3);
    check_ack(rx_base);

    // TEST 3 : A
    $display("\n[TEST 3] Commande A - associated data 64 bits");
    rx_base = rx_wp;
    uart_send_byte(8'h41);
    uart_send_64(ad_ref);
    wait_rx(rx_base + 3);
    check_ack(rx_base);

    // TEST 4 : W - wave ECG réelle
    $display("\n[TEST 4] Commande W - 23x64 bits wave ECG");
    rx_base = rx_wp;
    uart_send_byte(8'h57);
    uart_send_64(64'h5A5B5B5A5A5A5A5A); uart_send_64(64'h59554E4A4C4F5455);
    uart_send_64(64'h5351535456575857); uart_send_64(64'h5A5A595756595B5A);
    uart_send_64(64'h5554545252504F4F); uart_send_64(64'h4C4C4D4D4A494444);
    uart_send_64(64'h4747464442434140); uart_send_64(64'h3B36383E44494947);
    uart_send_64(64'h4746464443424345); uart_send_64(64'h4745444546474A49);
    uart_send_64(64'h4745484F58697C92); uart_send_64(64'hAECEEDFFFFE3B47C);
    uart_send_64(64'h471600041729363C); uart_send_64(64'h3F3E40414141403F);
    uart_send_64(64'h3F403F3E3B3A3B3E); uart_send_64(64'h3D3E3C393C414646);
    uart_send_64(64'h46454447464A4C4F); uart_send_64(64'h4C505555524F5155);
    uart_send_64(64'h595C5A595A5C5C5B); uart_send_64(64'h5959575351504F4F);
    uart_send_64(64'h53575A5C5A5B5D5E); uart_send_64(64'h6060615F605F5E5A);
    uart_send_64(64'h5857545252800000);
    wait_rx(rx_base + 3);
    check_ack(rx_base);

    // TEST 5 : G
    $display("\n[TEST 5] Commande G - start ASCON");
    rx_base = rx_wp;
    uart_send_byte(8'h47);
    wait_rx(rx_base + 3);
    check_ack(rx_base);

    // TEST 6 : C
    $display("\n[TEST 6] Commande C - cipher 23x64 bits (184 octets)");
    rx_base = rx_wp;
    uart_send_byte(8'h43);
    wait_rx(rx_base + 187);
    fail_cnt = 0;
    for (i = 0; i < 23; i = i+1)
      for (j = 0; j < 8; j = j+1) begin
        got_b = rx_log[rx_base + i*8 + j];
        exp_b = cipher_ref[i][(7-j)*8 +: 8];
        if (got_b !== exp_b) begin
          $display("  [FAIL] C[%02d][%0d] got=%02h exp=%02h", i, j, got_b, exp_b);
          fail_cnt = fail_cnt + 1; errors = errors + 1;
        end
      end
    if (fail_cnt == 0) $display("  [PASS] 184 octets cipher corrects");
    else               $display("  [FAIL] %0d incorrects", fail_cnt);
    check_ack(rx_base + 184);

    // TEST 7 : T
    $display("\n[TEST 7] Commande T - tag 2x64 bits (16 octets)");
    rx_base = rx_wp;
    uart_send_byte(8'h54);
    wait_rx(rx_base + 19);
    fail_cnt = 0;
    for (i = 0; i < 2; i = i+1)
      for (j = 0; j < 8; j = j+1) begin
        got_b = rx_log[rx_base + i*8 + j];
        exp_b = tag_ref[i][(7-j)*8 +: 8];
        if (got_b !== exp_b) begin
          $display("  [FAIL] T[%0d][%0d] got=%02h exp=%02h", i, j, got_b, exp_b);
          fail_cnt = fail_cnt + 1; errors = errors + 1;
        end
      end
    if (fail_cnt == 0) $display("  [PASS] 16 octets tag corrects");
    else               $display("  [FAIL] %0d incorrects", fail_cnt);
    check_ack(rx_base + 16);

    $display("\n==========================================================");
    if (errors == 0) $display("  TOUS LES TESTS PASSENT  -  0 ECHEC");
    else             $display("  %0d ECHEC(S) DETECTE(S)", errors);
    $display("==========================================================");
    $finish;
  end

endmodule
