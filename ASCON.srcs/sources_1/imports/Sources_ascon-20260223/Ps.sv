module Ps
  import ascon_pack::*;
(
    input  type_state Ps_in_i,
    output type_state Ps_out_o
);

  genvar i;  // index for generate
  generate
    for (i = 0; i < 64; i = i + 1) begin : generate_sbox
      sbox sbox_u (
          .sbox_i({Ps_in_i[0][i], Ps_in_i[1][i], Ps_in_i[2][i], Ps_in_i[3][i], Ps_in_i[4][i]}),
          .sbox_o({Ps_out_o[0][i], Ps_out_o[1][i], Ps_out_o[2][i], Ps_out_o[3][i], Ps_out_o[4][i]})
      );
    end  // for (i=0; i<64 ; i=i+1)
  endgenerate

endmodule : Ps

