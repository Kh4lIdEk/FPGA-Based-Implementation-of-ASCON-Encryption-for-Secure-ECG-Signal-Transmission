// Permutation ASCON
// ASCON package declaration
import ascon_pack::*;
module Permutation (
    input  logic              clock_i,
    input  logic              resetb_i,
    input  logic              enable_i,
    input  logic              select_i,
    input  logic      [  3:0] round_i,
    input  type_state         state_i,
    input  logic              enable_begin_lsb_i,   //active xor avec LSB en fin de DA
    input  logic              enable_begin_data_i,  //active xor donnée associée ou plaintext
    input  logic              enable_begin_key_i,   //active xor avec cle pour la finalisation
    input  logic      [ 63:0] data_i,
    input  logic              enable_end_key_i,     //active xor avec cle en fin initialisation
    input  logic      [127:0] key_i,
    input  logic              enable_tag_i,
    output logic      [127:0] tag_o,
    input  logic              enable_cipher_i,
    output logic      [ 63:0] cipher_o
);

  type_state output_mux_s;
  type_state output_state_register_s;
  type_state output_xor_begin_s;
  type_state output_xor_end_s;
  type_state output_pc_s;
  type_state output_ps_s;
  type_state output_pl_s;

  // mux_state instance declaration
  mux_state mux_instance (
      .sel_i  (select_i),
      .data1_i(state_i),
      .data2_i(output_state_register_s),
      .data_o (output_mux_s)
  );

  // xor begin
  xor_begin_perm xor_begin (
      .en_xor_lsb_i(enable_begin_lsb_i),  //active xor avec LSB en fin de DA
      .en_xor_data_i(enable_begin_data_i),  //active xor donnée associée ou plaintext
      .en_xor_key_i(enable_begin_key_i),  //active xor avec cle pour la finalisation
      .key_i(key_i),
      .data_i(data_i),
      .state_i(output_mux_s),
      .state_o(output_xor_begin_s)
  );


  // save cipher 
  register_w_en #(64) UCipher (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .en_i(enable_cipher_i),
      .data_i(output_xor_begin_s[0]),
      .data_o(cipher_o)
  );

  // Pc instance declaration
  Pc Pc_instance (
      .Pc_in_i (output_xor_begin_s),
      .Round_i (round_i),
      .Pc_out_o(output_pc_s)
  );

  // Ps instance declaration
  Ps Ps_instance (
      .Ps_in_i (output_pc_s),
      .Ps_out_o(output_ps_s)
  );

  // Pl instance declaration
  Pl Pl_instance (
      .Pl_in_i (output_ps_s),
      .Pl_out_o(output_pl_s)
  );

  // Xor end
  xor_end_perm xor_end (
      .en_xor_key_i(enable_end_key_i),  //active xor avec cle en fin initialisation
      .key_i(key_i),
      .state_i(output_pl_s),
      .state_o(output_xor_end_s)
  );

  // state_register instance declaration
  state_register_w_en state_register_instance (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .en_i(enable_i),
      .data_i(output_xor_end_s),
      .data_o(output_state_register_s)
  );

  register_w_en #(128) UTag (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .en_i(enable_tag_i),
      .data_i({output_xor_end_s[3], output_xor_end_s[4]}),
      .data_o(tag_o)
  );

endmodule

