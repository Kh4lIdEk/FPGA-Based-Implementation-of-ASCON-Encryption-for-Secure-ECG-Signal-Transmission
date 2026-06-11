`timescale 1ns / 1ps
// ASCON128 Module
import ascon_pack::*;

module ascon (
    // inputs
    input  logic         clock_i,
    input  logic         reset_i,
    input  logic         init_i,
    input  logic         associate_data_i,
    input  logic         finalisation_i,
    input  logic [ 63:0] data_i,
    input  logic         data_valid_i,
    input  logic [127:0] key_i,
    input  logic [127:0] nonce_i,
    // outputs
    output logic         end_associate_o,
    output logic [ 63:0] cipher_o,
    output logic         cipher_valid_o,
    output logic [127:0] tag_o,
    output logic         end_tag_o,
    output logic         end_initialisation_o,
    output logic         end_cipher_o
);

  // Internal signals declaration
  logic enable_round_s;
  logic init_round_p12_s;
  logic init_round_p6_s;
  logic [3:0] round_s;
  logic selectData_s;
  logic enable_state_register_s;
  logic enable_tag_s;
  logic enable_cipher_s;
  logic enable_xor_data_begin_s;
  logic enable_xor_key_begin_s;
  logic enable_xor_key_end_s;
  logic enable_xor_lsb_begin_s;
  logic resetb_s;

  type_state permutation_input_s;

  assign resetb_s = ~reset_i;

  // ASCON FSM instance declaration
  fsm_moore U0 (
      .clock_i(clock_i),
      .resetb_i(resetb_s),
      .init_i(init_i),
      .data_valid_i(data_valid_i),
      .round_i(round_s),
      .associate_data_i(associate_data_i),
      .finalisation_i(finalisation_i),
      // round counter 
      .init_a_o(init_round_p12_s),
      .init_b_o(init_round_p6_s),
      .enable_round_o(enable_round_s),
      // enable input data
      .enable_data_o(selectData_s),
      // enable xor signals 
      .en_xor_lsb_begin_o(enable_xor_lsb_begin_s),
      .en_xor_data_begin_o(enable_xor_data_begin_s),
      .en_xor_key_begin_o(enable_xor_key_begin_s),
      .en_xor_key_end_o(enable_xor_key_end_s),
      // enable register signals
      .en_reg_state_o(enable_state_register_s),
      .en_cipher_o(enable_cipher_s),
      .en_tag_o(enable_tag_s),
      // outputs
      .cipher_valid_o(cipher_valid_o),
      .end_associate_o(end_associate_o),
      .end_tag_o(end_tag_o),
      .end_init_o(end_initialisation_o),
      .end_cipher_o(end_cipher_o)
  );

  // Round counter instanciation
  compteur_double_init U2 (
      .clock_i(clock_i),
      .resetb_i(resetb_s),
      .en_i(enable_round_s),
      .init_a_i(init_round_p12_s),
      .init_b_i(init_round_p6_s),
      .data_o(round_s)
  );

  assign permutation_input_s[0] = 64'h80400c0600000000;  // X0 <- IV
  assign permutation_input_s[1] = key_i[127:64];  // X1 <- MSB Key
  assign permutation_input_s[2] = key_i[63:0];  // X2 <- LSB Key
  assign permutation_input_s[3] = nonce_i[127:64];  // X3 <- MSB Nonce
  assign permutation_input_s[4] = nonce_i[63:0];  // X4 <- LSB Nonce

  // Permutation instance
  Permutation U3 (
      .clock_i(clock_i),
      .resetb_i(resetb_s),
      .enable_i(enable_state_register_s),
      .select_i(selectData_s),
      .round_i(round_s),
      .state_i(permutation_input_s),
      .enable_begin_lsb_i(enable_xor_lsb_begin_s),  //active xor avec LSB en fin de DA
      .enable_begin_data_i(enable_xor_data_begin_s),  //active xor donnée associée ou plaintext
      .enable_begin_key_i(enable_xor_key_begin_s),  //active xor avec cle pour la finalisation
      .data_i(data_i),
      .enable_end_key_i(enable_xor_key_end_s),  //active xor avec cle en fin initialisation
      .key_i(key_i),
      .enable_tag_i(enable_tag_s),
      .tag_o(tag_o),
      .enable_cipher_i(enable_cipher_s),
      .cipher_o(cipher_o)
  );

  // the "macro" to dump signals
  /*`ifdef COCOTB_SIM
  initial begin
    $dumpfile("ascon.vcd");
    $dumpvars(0, ascon);
    //#1;
  end
`endif*/

endmodule
