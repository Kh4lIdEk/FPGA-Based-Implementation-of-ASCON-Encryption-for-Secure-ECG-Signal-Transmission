`timescale 1ns / 1ps

module ascon_top
  import uart_pkg::*;
(
    input  logic       clock_i,
    input  logic       reset_i,
    input  logic       Rx_i,
    input  logic [2:0] Baud_i,
    output logic       Tx_o,
    output logic [2:0] Baud_o,
    output logic       RTS_o
);

  logic clock_50MHZ_s;
  logic resetb_s;

  assign Baud_o   = ~Baud_i;
  assign resetb_s = ~reset_i;

  // ===========================================================================
  // SIGNAUX INTERNES
  // ===========================================================================
  // UART
  logic       RXErr_s, RXRdy_s, TxBusy_s;
  logic       rdata_ld_s;
  logic [7:0] rdata_s, Dout_s;
  assign RTS_o = RXRdy_s;

  // ASCON
  logic [127:0] key_s, nonce_s;
  logic [63:0]  ad_s;
  logic         start_ascon_s;

  logic init_cpt_mux_s, en_cpt_mux_s;
  logic associate_data_s, finalisation_s, data_valid_s, init_s;
  logic end_associate_s, end_tag_s, end_initialisation_s, end_cipher_s;
  logic [127:0] tag_s;
  logic [63:0]  cipher_s, data_s;
  logic [4:0]   cpt_s;
  
  // LE SIGNAL CLÉ POUR L'ÉCRITURE DU CIPHER (Impulsion d'1 cycle)
  logic en_reg_ascon_s; 

  // BRAM Port A: UART FSM + ASCON result writes
  logic        fsm_bram_ena;
  logic [0:0]  fsm_bram_wea;
  logic [5:0]  fsm_bram_addra;
  logic [63:0] fsm_bram_dina;
  logic [63:0] bram_douta_A;

  logic        bram_ena_A;
  logic [0:0]  bram_wea_A;
  logic [5:0]  bram_addra_A;
  logic [63:0] bram_dina_A;

  // BRAM Port B: Read-only wave feed for ASCON
  logic [5:0]  bram_addrb;
  logic [63:0] bram_doutb;

  // ===========================================================================
  // LOGIQUE DE LECTURE (PORT B)
  // ===========================================================================
  logic [4:0] next_cpt;
  assign next_cpt   = init_cpt_mux_s ? 5'd0 : (en_cpt_mux_s  ? cpt_s + 5'd1 : cpt_s);
  
  assign bram_addrb = (next_cpt > 5'd0) ? (6'(next_cpt) - 6'd1) : 6'd0;
  assign data_s     = (cpt_s == 5'd0) ? ad_s : bram_doutb;

  // ===========================================================================
  // LOGIQUE D'ÉCRITURE CIPHER
  // ===========================================================================
  logic [5:0] cipher_write_ptr;
  always_ff @(posedge clock_50MHZ_s or negedge resetb_s) begin
    if (!resetb_s)
      cipher_write_ptr <= 6'd32;
    else if (start_ascon_s)
      cipher_write_ptr <= 6'd32;
    // On incrémente UNIQUEMENT sur l'impulsion de 1 cycle de la FSM !
    else if (en_reg_ascon_s && (cipher_write_ptr <= 6'd54))
      cipher_write_ptr <= cipher_write_ptr + 6'd1;
  end

  // ===========================================================================
  // SÉCURISATION ET ÉCRITURE DU TAG (Anti-Glitch & Latch Immédiat)
  // ===========================================================================
  logic tag_r1, tag_r2;
  logic safe_tag_rising;
  logic [1:0] tag_wait;
  logic [127:0] latched_tag;
  logic tag_write_en, tag_word_sel, tag_write_done;

  // 1. Double registre anti-glitch pour end_tag_s
  always_ff @(posedge clock_50MHZ_s or negedge resetb_s) begin
    if (!resetb_s) {tag_r1, tag_r2} <= 2'b00;
    else           {tag_r1, tag_r2} <= {end_tag_s, tag_r1};
  end
  assign safe_tag_rising = tag_r1 & ~tag_r2;

  // 2. Latch immédiat de la donnée sécurisée
  always_ff @(posedge clock_50MHZ_s or negedge resetb_s) begin
    if (!resetb_s) latched_tag <= '0;
    else if (safe_tag_rising) latched_tag <= tag_s;
  end

  // 3. Ligne à retard pour l'écriture BRAM
  always_ff @(posedge clock_50MHZ_s or negedge resetb_s) begin
    if (!resetb_s) tag_wait <= 2'b00;
    else           tag_wait <= {tag_wait[0], safe_tag_rising};
  end

  // 4. Séquenceur d'écriture en 2 mots de 64 bits
  always_ff @(posedge clock_50MHZ_s or negedge resetb_s) begin
    if (!resetb_s) begin
      tag_write_en   <= 1'b0;
      tag_word_sel   <= 1'b0;
      tag_write_done <= 1'b0;
    end else begin
      tag_write_done <= 1'b0;

      if (tag_wait[1]) begin
        tag_write_en <= 1'b1;
        tag_word_sel <= 1'b0;
      end else if (tag_write_en && !tag_word_sel) begin
        tag_word_sel <= 1'b1;
      end else if (tag_write_en && tag_word_sel) begin
        tag_write_en   <= 1'b0;
        tag_write_done <= 1'b1;
      end
    end
  end

  // ===========================================================================
  // STICKY BIT (Mécanisme Robuste pour UART)
  // ===========================================================================
  logic ascon_done_flag;
  
  always_ff @(posedge clock_50MHZ_s or negedge resetb_s) begin
    if (!resetb_s) begin
      ascon_done_flag <= 1'b0;
    end else begin
      if (start_ascon_s)       ascon_done_flag <= 1'b0; // Acquittement
      else if (tag_write_done) ascon_done_flag <= 1'b1; // Devient persistant
    end
  end

  // ===========================================================================
  // ARBITRE PORT A (TAG > CIPHER > UART) & ASSERTIONS
  // ===========================================================================
  logic        ascon_req;
  logic [5:0]  ascon_addr;
  logic [63:0] ascon_data;

  always_comb begin
    ascon_req  = 1'b0;
    ascon_addr = 6'd0;
    ascon_data = 64'd0;

    if (tag_write_en) begin
      ascon_req  = 1'b1;
      ascon_addr = tag_word_sel ? 6'd56 : 6'd55;
      ascon_data = tag_word_sel ? latched_tag[63:0] : latched_tag[127:64];
    // On écrit le Cipher UNIQUEMENT sur l'impulsion de 1 cycle de la FSM !
    end else if (en_reg_ascon_s && (cipher_write_ptr <= 6'd54)) begin
      ascon_req  = 1'b1;
      ascon_addr = cipher_write_ptr;
      ascon_data = cipher_s;
    end
  end

  assign bram_ena_A   = ascon_req | fsm_bram_ena;
  assign bram_wea_A   = ascon_req ? 1'b1        : fsm_bram_wea;
  assign bram_addra_A = ascon_req ? ascon_addr  : fsm_bram_addra;
  assign bram_dina_A  = ascon_req ? ascon_data  : fsm_bram_dina;

  // Pragma de simulation pour garantir l'absence de collision
  always_ff @(posedge clock_50MHZ_s) begin
    if (resetb_s && ascon_req && fsm_bram_wea) begin
      $error("FATAL BRAM COLLISION: ASCON and UART FSM attempted to write to Port A simultaneously at time %0t", $time);
    end
  end

  // ===========================================================================
  // INSTANCIATIONS
  // ===========================================================================
  clk_sys clk_50 (
    .clk_out1(clock_50MHZ_s),
    .reset   (reset_i),
    .clk_in1 (clock_i)
  );

  blk_mem_gen_1 ram_i (
    .clka  (clock_50MHZ_s),
    .ena   (bram_ena_A),
    .wea   (bram_wea_A),
    .addra (bram_addra_A),
    .dina  (bram_dina_A),
    .douta (bram_douta_A),
    .clkb  (clock_50MHZ_s),
    .enb   (1'b1),
    .web   (1'b0),
    .addrb (bram_addrb),
    .dinb  (64'd0),
    .doutb (bram_doutb)
  );

  uart_core uart_core_0 (
    .clock_i  (clock_50MHZ_s),
    .resetb_i (resetb_s),
    .Din_i    (rdata_s),
    .LD_i     (rdata_ld_s),
    .Rx_i     (Rx_i),
    .Baud_i   (Baud_i),
    .RXErr_o  (RXErr_s),
    .RXRdy_o  (RXRdy_s),
    .Dout_o   (Dout_s),
    .Tx_o     (Tx_o),
    .TxBusy_o (TxBusy_s)
  );

  fsm_uart fsm_uart_0 (
    .clock_i      (clock_50MHZ_s),
    .resetb_i     (resetb_s),
    .RXErr_i      (RXErr_s),
    .RXRdy_i      (RXRdy_s),
    .TxBusy_i     (TxBusy_s),
    .RxData_i     (Dout_s),
    .CipherRdy_i  (ascon_done_flag),
    .TxByte_o     (rdata_s),
    .Key_o        (key_s),
    .Nonce_o      (nonce_s),
    .Ad_o         (ad_s),
    .Start_ascon_o(start_ascon_s),
    .Load_o       (rdata_ld_s),
    .bram_ena_o   (fsm_bram_ena),
    .bram_wea_o   (fsm_bram_wea),
    .bram_addra_o (fsm_bram_addra),
    .bram_dina_o  (fsm_bram_dina),
    .bram_douta_i (bram_douta_A)
  );

  ascon ASCON (
    .clock_i              (clock_50MHZ_s),
    .reset_i              (reset_i),
    .init_i               (init_s),
    .associate_data_i     (associate_data_s),
    .finalisation_i       (finalisation_s),
    .data_i               (data_s),
    .data_valid_i         (data_valid_s),
    .key_i                (key_s),
    .nonce_i              (nonce_s),
    .end_associate_o      (end_associate_s),
    .cipher_o             (cipher_s),
    .cipher_valid_o       (),
    .tag_o                (tag_s),
    .end_tag_o            (end_tag_s),
    .end_initialisation_o (end_initialisation_s),
    .end_cipher_o         (end_cipher_s)
  );

  fsm_ascon fsm (
    .clock_i              (clock_50MHZ_s),
    .reset_i              (resetb_s),
    .start_i              (start_ascon_s),
    .end_associate_i      (end_associate_s),
    .end_cipher_i         (end_cipher_s),
    .end_tag_i            (end_tag_s),
    .end_initialisation_i (end_initialisation_s),
    .counter_i            (cpt_s),
    .en_cpt_o             (en_cpt_mux_s),
    .init_cpt_o           (init_cpt_mux_s),
    .init_o               (init_s),
    .associate_data_o     (associate_data_s),
    .finalisation_o       (finalisation_s),
    .data_valid_o         (data_valid_s),
    .init_reg_o           (),
    .en_reg_ascon_o       (en_reg_ascon_s)
  );

  cpt compteur_fsm (
    .clock_i    (clock_50MHZ_s),
    .reset_i    (resetb_s),
    .en_cpt_i   (en_cpt_mux_s | init_cpt_mux_s),
    .init_cpt_i (init_cpt_mux_s),
    .data_o     (cpt_s)
  );

endmodule : ascon_top