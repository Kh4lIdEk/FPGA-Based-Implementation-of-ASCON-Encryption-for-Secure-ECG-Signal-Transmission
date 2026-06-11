`timescale 1ns / 1ps

module fsm_uart
  import uart_pkg::*;
(
    input  logic          clock_i,
    input  logic          resetb_i,
    input  logic          RXErr_i,
    input  logic          RXRdy_i,
    input  logic          TxBusy_i,
    input  logic [   7:0] RxData_i,
    input  logic          CipherRdy_i,
    input  logic [63:0]   bram_douta_i,
    output logic [   7:0] TxByte_o,
    output logic [ 127:0] Key_o,
    output logic [ 127:0] Nonce_o,
    output logic [  63:0] Ad_o,
    output logic          Start_ascon_o,
    output logic          Load_o,
    output logic          bram_ena_o,
    output logic [0:0]    bram_wea_o,
    output logic [5:0]    bram_addra_o,
    output logic [63:0]   bram_dina_o
);

  logic [7:0] key_reg_s, nonce_reg_s, ad_reg_s;
  logic init_key_s, en_key_s, init_nonce_s, en_nonce_s, init_ad_s, en_ad_s;
  
  logic        bram_ena_s;
  logic [0:0]  bram_wea_s;
  logic [5:0]  bram_addra_s;
  logic [63:0] buffer_64;
  logic [3:0]  byte_cnt;
  
  logic set_addr_wave, set_addr_cipher, set_addr_tag, inc_addr;
  logic clear_byte_cnt, inc_byte_cnt, load_rx_byte, load_tx_word, shift_tx_byte;
  
  logic [8:0] cpt_s;
  logic en_cpt_s, init_c8_s, init_c16_s;
  
  logic [7:0] data_converted_s;
  logic en_trans_s;

  assign bram_ena_o   = bram_ena_s;
  assign bram_wea_o   = bram_wea_s;
  assign bram_addra_o = bram_addra_s;
  assign bram_dina_o  = buffer_64;

  typedef enum logic [6:0] {
    init, idle_cmd, get_cmd,
    init_key,
    idle_key0, idle_key1,
    get_key0, get_key1,
    flush_key,
    init_nonce,
    idle_nonce0, idle_nonce1,
    get_nonce0, get_nonce1,
    flush_nonce,
    init_assoc_data,
    idle_assoc_data_0, idle_assoc_data_1,
    get_assoc_data_0, get_assoc_data_1,
    flush_assoc_data,
    init_wave,
    rx_wave_idle, rx_wave_get, rx_wave_check, rx_wave_write, rx_wave_next, 
    start_ascon, wait_end_ascon,
    init_send_cipher,
    tx_cipher_req, tx_cipher_wait, tx_cipher_load, tx_cipher_wait_idle,
    tx_cipher_send, tx_cipher_wait_high,
    tx_cipher_shift, tx_cipher_check,
    send_cipher_done,
    init_send_tag,
    tx_tag_req, tx_tag_wait, tx_tag_load, tx_tag_wait_idle,
    tx_tag_send, tx_tag_wait_high,
    tx_tag_shift, tx_tag_check,
    send_tag_done,
    wait_idle_o, starto, wait_o_high, wait_o_low, startk, wait_k_high, wait_k_low, startlf, wait_lf_high, wait_lf_low
  } state_t;

  state_t etat_f, etat_p;

  key_reg_shift key_reg_0 (
    .clock_i(clock_i),
    .resetb_i(resetb_i),
    .key_i(key_reg_s),
    .en_i(en_key_s),
    .init_i(init_key_s),
    .key_o(Key_o)
    );
    
  reg_shift nonce_reg (
    .clock_i(clock_i),
    .resetb_i(resetb_i),
    .nonce_i(nonce_reg_s),
    .en_i(en_nonce_s),
    .init_i(init_nonce_s),
    .nonce_o(Nonce_o)
    );
    
  a_data_reg_shift assoc_data_reg (
    .clock_i(clock_i),
    .resetb_i(resetb_i),
    .a_data_i(ad_reg_s),
    .en_i(en_ad_s),
    .init_i(init_ad_s),
    .a_data_o(Ad_o)
    );
    
  main_decounter fsm_dcounter_0 (
    .clock_i(clock_i),
    .resetb_i(resetb_i),
    .en_i(en_cpt_s),
    .init_cpt_ad_8_i(init_c8_s),
    .init_cpt_key_nonce_16_i(init_c16_s),
    .data_o(cpt_s)
    );
    
  trans_receive trans_receive_0 (
    .clock_i(clock_i),
    .resetb_i(resetb_i),
    .RxData_i(RxData_i),
    .en_i(en_trans_s),
    .data_converted_o(data_converted_s)
    );
  
  always_ff @(posedge clock_i or negedge resetb_i) begin
    if (!resetb_i) begin
      buffer_64 <= '0; byte_cnt <= '0; bram_addra_s <= '0;
    end else begin
      if (clear_byte_cnt)      byte_cnt <= '0;
      else if (inc_byte_cnt)   byte_cnt <= byte_cnt + 4'd1;

      if (set_addr_wave)        bram_addra_s <= 6'd0;       
      else if (set_addr_cipher) bram_addra_s <= 6'd32;      
      else if (set_addr_tag)    bram_addra_s <= 6'd55;     
      else if (inc_addr)        bram_addra_s <= bram_addra_s + 6'd1;

      if (load_rx_byte)        buffer_64 <= {buffer_64[55:0], data_converted_s};   
      else if (load_tx_word)   buffer_64 <= bram_douta_i;                          
      else if (shift_tx_byte)  buffer_64 <= {buffer_64[55:0], 8'h00};              
    end
  end
  
  always_ff @(posedge clock_i, negedge resetb_i) begin : seq_0
    if (!resetb_i) etat_p <= init;
    else           etat_p <= etat_f;
  end : seq_0

  always_comb begin : comb_0
    etat_f = etat_p; 
    case (etat_p)
      init:     etat_f = idle_cmd;
      idle_cmd: etat_f = (RXRdy_i == 1'b1) ? get_cmd : idle_cmd;
      get_cmd: begin
        if (!TxBusy_i) begin
          case (RxData_i)
            8'h4B, 8'h6B: etat_f = init_key;
            8'h41, 8'h61: etat_f = init_assoc_data;
            8'h57, 8'h77: etat_f = init_wave;
            8'h4E, 8'h6E: etat_f = init_nonce;
            8'h47, 8'h67: etat_f = start_ascon;
            8'h43, 8'h63: etat_f = init_send_cipher;
            8'h54, 8'h74: etat_f = init_send_tag;
            default:      etat_f = idle_cmd;
          endcase
        end else etat_f = idle_cmd;
      end

      init_key:  etat_f = idle_key0;
      idle_key0: etat_f = (RXRdy_i == 1'b1) ? idle_key1 : idle_key0;
      idle_key1: etat_f = get_key0;
      get_key0:  etat_f = get_key1;
      get_key1:  etat_f = (cpt_s == 9'h1) ? flush_key : idle_key0;
      flush_key: etat_f = wait_idle_o;

      init_nonce:  etat_f = idle_nonce0;
      idle_nonce0: etat_f = (RXRdy_i == 1'b1) ? idle_nonce1 : idle_nonce0;
      idle_nonce1: etat_f = get_nonce0;
      get_nonce0:  etat_f = get_nonce1;
      get_nonce1:  etat_f = (cpt_s == 9'h1) ? flush_nonce : idle_nonce0;
      flush_nonce: etat_f = wait_idle_o;

      init_assoc_data:   etat_f = idle_assoc_data_0;
      idle_assoc_data_0: etat_f = (RXRdy_i == 1'b1) ? idle_assoc_data_1 : idle_assoc_data_0;
      idle_assoc_data_1: etat_f = get_assoc_data_0;
      get_assoc_data_0:  etat_f = get_assoc_data_1;
      get_assoc_data_1:  etat_f = (cpt_s == 9'h1) ? flush_assoc_data : idle_assoc_data_0;
      flush_assoc_data:  etat_f = wait_idle_o;

      init_wave:     etat_f = rx_wave_idle;
      rx_wave_idle:  etat_f = (RXRdy_i) ? rx_wave_get : rx_wave_idle;
      rx_wave_get:   etat_f = rx_wave_check;
      rx_wave_check: etat_f = (byte_cnt == 4'd8) ? rx_wave_write : rx_wave_idle;
      rx_wave_write: etat_f = rx_wave_next;
      rx_wave_next: begin
        if (bram_addra_s[5] == 1'b0) begin 
            if (bram_addra_s == 6'd22) etat_f = wait_idle_o;
            else                       etat_f = rx_wave_idle;
        end else etat_f = init; 
      end
      
      start_ascon:    etat_f = wait_end_ascon;
      wait_end_ascon: etat_f = (CipherRdy_i == 1'b1) ? wait_idle_o : wait_end_ascon;

      init_send_cipher:    etat_f = tx_cipher_req;
      tx_cipher_req:       etat_f = tx_cipher_wait;
      tx_cipher_wait:      etat_f = tx_cipher_load; 
      tx_cipher_load:      etat_f = tx_cipher_wait_idle;
      tx_cipher_wait_idle: etat_f = (!TxBusy_i) ? tx_cipher_send : tx_cipher_wait_idle;
      tx_cipher_send:      etat_f = tx_cipher_wait_high;
      tx_cipher_wait_high: etat_f = (TxBusy_i) ? tx_cipher_shift : tx_cipher_wait_high;
      tx_cipher_shift:     etat_f = tx_cipher_check;
      tx_cipher_check:     etat_f = (byte_cnt == 4'd8) ? send_cipher_done : tx_cipher_wait_idle;
      send_cipher_done: begin
        if (bram_addra_s[5] == 1'b1) begin
            if (bram_addra_s == 6'd54) etat_f = wait_idle_o; 
            else                       etat_f = tx_cipher_req;
        end else etat_f = init;
      end
      
      init_send_tag:    etat_f = tx_tag_req;
      tx_tag_req:       etat_f = tx_tag_wait;
      tx_tag_wait:      etat_f = tx_tag_load;
      tx_tag_load:      etat_f = tx_tag_wait_idle;
      tx_tag_wait_idle: etat_f = (!TxBusy_i) ? tx_tag_send : tx_tag_wait_idle;
      tx_tag_send:      etat_f = tx_tag_wait_high;
      tx_tag_wait_high: etat_f = (TxBusy_i) ? tx_tag_shift : tx_tag_wait_high;
      tx_tag_shift:     etat_f = tx_tag_check;
      tx_tag_check:     etat_f = (byte_cnt == 4'd8) ? send_tag_done : tx_tag_wait_idle;
      send_tag_done: begin
        if (bram_addra_s[5] == 1'b1) begin
            if (bram_addra_s == 6'd56) etat_f = wait_idle_o; 
            else                       etat_f = tx_tag_req;
        end else etat_f = init;
      end
      
      wait_idle_o:  etat_f = (!TxBusy_i) ? starto : wait_idle_o;
      starto:       etat_f = wait_o_high;
      wait_o_high:  etat_f = (TxBusy_i) ? wait_o_low : wait_o_high;
      wait_o_low:   etat_f = (!TxBusy_i) ? startk : wait_o_low;
      startk:       etat_f = wait_k_high;
      wait_k_high:  etat_f = (TxBusy_i) ? wait_k_low : wait_k_high;
      wait_k_low:   etat_f = (!TxBusy_i) ? startlf : wait_k_low;
      startlf:      etat_f = wait_lf_high;
      wait_lf_high: etat_f = (TxBusy_i) ? wait_lf_low : wait_lf_high;
      wait_lf_low:  etat_f = (!TxBusy_i) ? idle_cmd : wait_lf_low;
      default:      etat_f = init;
    endcase
  end : comb_0

  always_comb begin : comb_1
    TxByte_o            = 8'h00;
    Start_ascon_o       = 1'b0;
    Load_o              = 1'b0;
    key_reg_s           = 8'h00;
    init_key_s          = 1'b0;
    en_key_s            = 1'b0;
    nonce_reg_s         = 8'h00;
    init_nonce_s        = 1'b0;
    en_nonce_s          = 1'b0;
    ad_reg_s            = 8'h00;
    init_ad_s           = 1'b0;
    en_ad_s             = 1'b0;
    en_cpt_s            = 1'b0;
    init_c8_s           = 1'b0;
    init_c16_s          = 1'b0;
    en_trans_s          = 1'b0;
    bram_ena_s          = 1'b0;
    bram_wea_s          = 1'b0;
    clear_byte_cnt      = 1'b0;
    inc_byte_cnt        = 1'b0;
    set_addr_wave       = 1'b0;
    set_addr_cipher     = 1'b0;
    set_addr_tag        = 1'b0;
    inc_addr            = 1'b0;
    load_rx_byte        = 1'b0;
    load_tx_word        = 1'b0;
    shift_tx_byte       = 1'b0;

    case (etat_p)
      init, idle_cmd, get_cmd: begin end 
      init_key: 
        begin 
            init_key_s = 1'b1;
            en_key_s = 1'b1;
            en_cpt_s = 1'b1;
            init_c16_s = 1'b1;
            end
            
      idle_key0: en_trans_s = 1'b1;
      
      get_key0:
        begin 
        key_reg_s = data_converted_s;
        en_key_s = 1'b1;
        end
        
      get_key1: en_cpt_s = 1'b1;
      
      idle_key1, flush_key: begin end

      init_nonce:
        begin 
        init_nonce_s = 1'b1;
        en_nonce_s = 1'b1;
        en_cpt_s = 1'b1;
        init_c16_s = 1'b1;
        end
        
      idle_nonce0: en_trans_s = 1'b1;
      
      get_nonce0: 
        begin nonce_reg_s = data_converted_s;
        en_nonce_s = 1'b1;
        end
        
      get_nonce1: en_cpt_s = 1'b1;
      
      idle_nonce1, flush_nonce: begin end

      init_assoc_data: 
        begin 
        init_ad_s = 1'b1;
        en_ad_s = 1'b1;
        en_cpt_s = 1'b1;
        init_c8_s = 1'b1;
        end
        
      idle_assoc_data_0: en_trans_s = 1'b1;
      
      get_assoc_data_0:
      begin 
        ad_reg_s = data_converted_s;
        en_ad_s = 1'b1;
        end
        
      get_assoc_data_1: en_cpt_s = 1'b1;
      
      idle_assoc_data_1, flush_assoc_data: begin end

      init_wave: 
        begin 
        set_addr_wave = 1'b1;
        clear_byte_cnt = 1'b1;
        end
        
      rx_wave_idle: en_trans_s = 1'b1;
      
      rx_wave_get: 
        begin load_rx_byte = 1'b1;
        inc_byte_cnt = 1'b1;
        end
        
      rx_wave_check: begin end
      
      rx_wave_write: 
        begin bram_wea_s = 1'b1;
        bram_ena_s = 1'b1;
        end
        
      rx_wave_next: 
      begin inc_addr = 1'b1;
      clear_byte_cnt = 1'b1;
      end

      start_ascon: Start_ascon_o = 1'b1;
      
      wait_end_ascon: begin end

      init_send_cipher:
        begin set_addr_cipher = 1'b1;
        clear_byte_cnt = 1'b1;
        end
        
      tx_cipher_req: bram_ena_s = 1'b1;
      
      tx_cipher_wait: bram_ena_s = 1'b1;
      
      tx_cipher_load: load_tx_word = 1'b1;
      
      tx_cipher_wait_idle: begin end
      
      tx_cipher_send: 
        begin TxByte_o = buffer_64[63:56];
        Load_o = 1'b1;
        end
        
      tx_cipher_wait_high: begin end
      
      tx_cipher_shift:
        begin 
        shift_tx_byte = 1'b1;
        inc_byte_cnt = 1'b1;
        end
        
      tx_cipher_check: begin end
      
      send_cipher_done:
        begin 
        inc_addr = 1'b1;
        clear_byte_cnt = 1'b1;
        end

      init_send_tag:
        begin set_addr_tag = 1'b1;
        clear_byte_cnt = 1'b1;
        end
        
      tx_tag_req: bram_ena_s = 1'b1;
      
      tx_tag_wait: bram_ena_s = 1'b1;
      
      tx_tag_load: load_tx_word = 1'b1;
      
      tx_tag_wait_idle: begin end
      
      tx_tag_send:
        begin 
        TxByte_o = buffer_64[63:56];
        Load_o = 1'b1;
        end
        
      tx_tag_wait_high: begin end
      
      tx_tag_shift:
      begin
      shift_tx_byte = 1'b1;
      inc_byte_cnt = 1'b1;
      end
      
      tx_tag_check: begin end
      
      send_tag_done: 
      begin
      inc_addr = 1'b1;
      clear_byte_cnt = 1'b1;
      end

      wait_idle_o: begin end
      
      starto:
      begin 
      TxByte_o = 8'h4F;
      Load_o = 1'b1;
      end
      
      wait_o_high, wait_o_low: begin end
      
      startk: 
        begin 
        TxByte_o = 8'h4B;
        Load_o = 1'b1;
        end
        
      wait_k_high, wait_k_low: begin end
      
      startlf: 
        begin 
        TxByte_o = 8'h0A;
        Load_o = 1'b1;
        end
        
      wait_lf_high, wait_lf_low: begin end
      
      default: begin end
    endcase
  end : comb_1
endmodule : fsm_uart