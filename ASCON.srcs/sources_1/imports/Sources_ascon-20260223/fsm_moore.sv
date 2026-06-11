// Moore FSM for ASCON
import ascon_pack::*;

module fsm_moore (
    // inputs/outpus/ declaration
    input  logic       clock_i,
    input  logic       resetb_i,
    input  logic       init_i,
    input  logic       data_valid_i,
    input  logic [3:0] round_i,
    input  logic       associate_data_i,
    input  logic       finalisation_i,
    // round counter 
    output logic       init_a_o,
    output logic       init_b_o,
    output logic       enable_round_o,
    // enable input data
    output logic       enable_data_o,
    // enable xor signals 
    output logic       en_xor_lsb_begin_o,
    output logic       en_xor_data_begin_o,
    output logic       en_xor_key_begin_o,
    output logic       en_xor_key_end_o,
    // enable register signals
    output logic       en_reg_state_o,
    output logic       en_cipher_o,
    output logic       en_tag_o,
    // outputs
    output logic       end_associate_o,
    output logic       cipher_valid_o,
    output logic       end_tag_o,
    output logic       end_init_o,
    output logic       end_cipher_o
);

  // state list
  typedef enum {
    idle,
    conf_init,
    start_init,
    init,
    end_init,
    idle_next,
    idle_da,
    conf_da,  //jbr
    start_da,
    da,
    end_da,
    conf_first_cipher,  //jbr
    first_cipher,
    idle_cipher,
    conf_cipher,  //jbr
    start_cipher,
    cipherP0,
    cipher,
    end_cipher,
    conf_tag,
    start_tag,
    tagP0,
    tag,
    end_tag,
    wait_restart,
    idle_restart
  } State_t;

  // Present and futur states declaration
  State_t Ep, Ef;

  // sequential process
  always_ff @(posedge clock_i, negedge resetb_i) begin
    if (resetb_i == 1'b0) begin
      Ep <= idle;
    end else begin
      Ep <= Ef;
    end
  end

  // First combinatorial process (Next state computation)
  always_comb begin
    case (Ep)
      idle:
      if (init_i == 1'b1) Ef = conf_init;
      else Ef = idle;
      conf_init: Ef = start_init;
      start_init: Ef = init;
      init:
      if (round_i == 4'hA) Ef = end_init;
      else Ef = init;
      end_init: Ef = idle_next;
      idle_next:
      if (data_valid_i == 1'b1) begin
        if (associate_data_i == 1'b1) Ef = conf_da;  //Ef = start_da;
        else Ef = conf_cipher;  //Ef = start_cipher;
      end else Ef = idle_next;
      idle_da:
      if (data_valid_i == 1'b1) begin
        if (associate_data_i == 1'b1) Ef = conf_da;  //Ef = start_da;
        else Ef = conf_first_cipher;  //Ef = first_cipher;
      end else Ef = idle_da;
      conf_da: Ef = start_da;  //jbr
      start_da: Ef = da;
      da:
      if (round_i == 4'hA) Ef = end_da;
      else Ef = da;
      end_da: Ef = idle_da;
      idle_cipher:
      if (data_valid_i == 1'b1) begin
        if (finalisation_i == 1'b1) Ef = conf_tag;
        else Ef = conf_cipher;  //Ef = start_cipher;
      end else Ef = idle_cipher;
      conf_first_cipher: Ef = first_cipher;  //jbr
      first_cipher: Ef = cipherP0;
      conf_cipher: Ef = start_cipher;  //jbr
      start_cipher: Ef = cipherP0;
      cipherP0: Ef = cipher;
      cipher:
      if (round_i == 4'hA) Ef = end_cipher;
      else Ef = cipher;
      end_cipher: Ef = idle_cipher;
      // 	idle_tag:
      //		if (data_valid_i == 1'b1) 
      //                    Ef = start_tag;
      //                else
      //                   Ef = idle_tag;
      conf_tag: Ef = start_tag;
      start_tag: Ef = tagP0;
      tagP0: Ef = tag;
      tag:
      if (round_i == 4'hA) Ef = end_tag;
      else Ef = tag;
      end_tag: Ef = wait_restart;
      wait_restart:
      if (init_i == 1'b0) Ef = idle_restart;
      else Ef = wait_restart;
      idle_restart:
      if (init_i == 1'b1) Ef = start_init;
      else Ef = idle_restart;
      default: Ef = idle;
    endcase
  end


  // Second combinatorial process (Fix outputs)
  always_comb begin

    case (Ep)
      idle: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b0;
        enable_data_o       = 1'b0;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;

      end
      conf_init: begin
        init_a_o            = 1'b1;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b0;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      start_init: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b0;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      init: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      end_init: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b0;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b1;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      conf_da: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b1;  //
        enable_round_o      = 1'b1;  //
        enable_data_o       = 1'b1;  //
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      idle_next: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;  //jbr
        enable_round_o      = 1'b0;  //jbr
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b1;
        end_cipher_o        = 1'b0;
      end
      idle_da: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;  //jbr
        enable_round_o      = 1'b0;  //jbr
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b1;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      start_da: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b1;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      da: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      end_da: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b0;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      idle_cipher: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;  //jbr
        enable_round_o      = 1'b0;  //jbr
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b1;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b1;
      end
      conf_first_cipher: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b1;  //
        enable_round_o      = 1'b1;  //
        enable_data_o       = 1'b1;  //
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      first_cipher: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b1;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b1;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b1;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      conf_cipher: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b1;  //
        enable_round_o      = 1'b1;  //
        enable_data_o       = 1'b1;  //
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      start_cipher: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b1;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b1;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      cipherP0: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b1;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      cipher: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b1;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      end_cipher: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b0;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b1;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      conf_tag: begin
        init_a_o            = 1'b1;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;  //jbr
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      start_tag: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b1;
        en_xor_key_begin_o  = 1'b1;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b1;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      tagP0: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b1;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      tag: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b1;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      end_tag: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b0;
        enable_data_o       = 1'b1;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b1;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b1;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b1;
        cipher_valid_o      = 1'b1;  //jbr
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      wait_restart: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b0;
        enable_data_o       = 1'b0;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b1;  //jbr
        end_tag_o           = 1'b1;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      idle_restart: begin
        init_a_o            = 1'b1;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b1;
        enable_data_o       = 1'b0;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b1;  //jbr
        end_tag_o           = 1'b1;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
      default: begin
        init_a_o            = 1'b0;
        init_b_o            = 1'b0;
        enable_round_o      = 1'b0;
        enable_data_o       = 1'b0;
        en_xor_data_begin_o = 1'b0;
        en_xor_key_begin_o  = 1'b0;
        en_xor_key_end_o    = 1'b0;
        en_xor_lsb_begin_o  = 1'b0;
        en_reg_state_o      = 1'b0;
        en_cipher_o         = 1'b0;
        en_tag_o            = 1'b0;
        cipher_valid_o      = 1'b0;
        end_tag_o           = 1'b0;
        end_associate_o     = 1'b0;
        end_init_o          = 1'b0;
        end_cipher_o        = 1'b0;
      end
    endcase
  end
endmodule : fsm_moore

