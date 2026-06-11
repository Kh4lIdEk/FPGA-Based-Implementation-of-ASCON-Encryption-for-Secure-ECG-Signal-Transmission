// ASCON Pc transformation
import ascon_pack::*;

module Pc (
    input  type_state       Pc_in_i,
    input  logic      [3:0] Round_i,
    output type_state       Pc_out_o
);

  type_const round_constant;

  assign round_constant = {
    8'hF0, 8'hE1, 8'hD2, 8'hC3, 8'hB4, 8'hA5, 8'h96, 8'h87, 8'h78, 8'h69, 8'h5A, 8'h4B
  };
  logic [7:0] Cr_s;

  assign Cr_s              = round_constant[Round_i];
  assign Pc_out_o[0]       = Pc_in_i[0];
  assign Pc_out_o[1]       = Pc_in_i[1];
  assign Pc_out_o[2][63:8] = Pc_in_i[2][63:8];
  assign Pc_out_o[2][7:0]  = Pc_in_i[2][7:0] ^ Cr_s;
  assign Pc_out_o[3]       = Pc_in_i[3];
  assign Pc_out_o[4]       = Pc_in_i[4];

endmodule

