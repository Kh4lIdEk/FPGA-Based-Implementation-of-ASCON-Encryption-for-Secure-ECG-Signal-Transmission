module sbox (
    input  logic [4:0] sbox_i,
    output logic [4:0] sbox_o
);

  always @(sbox_i) begin
    case (sbox_i)
      5'h00: sbox_o = 5'h04;
      5'h01: sbox_o = 5'h0B;
      5'h02: sbox_o = 5'h1F;
      5'h03: sbox_o = 5'h14;
      5'h04: sbox_o = 5'h1A;
      5'h05: sbox_o = 5'h15;
      5'h06: sbox_o = 5'h09;
      5'h07: sbox_o = 5'h02;
      5'h08: sbox_o = 5'h1B;
      5'h09: sbox_o = 5'h05;
      5'h0A: sbox_o = 5'h08;
      5'h0B: sbox_o = 5'h12;
      5'h0C: sbox_o = 5'h1D;
      5'h0D: sbox_o = 5'h03;
      5'h0E: sbox_o = 5'h06;
      5'h0F: sbox_o = 5'h1C;
      5'h10: sbox_o = 5'h1E;
      5'h11: sbox_o = 5'h13;
      5'h12: sbox_o = 5'h07;
      5'h13: sbox_o = 5'h0E;
      5'h14: sbox_o = 5'h00;
      5'h15: sbox_o = 5'h0D;
      5'h16: sbox_o = 5'h11;
      5'h17: sbox_o = 5'h18;
      5'h18: sbox_o = 5'h10;
      5'h19: sbox_o = 5'h0C;
      5'h1A: sbox_o = 5'h01;
      5'h1B: sbox_o = 5'h19;
      5'h1C: sbox_o = 5'h16;
      5'h1D: sbox_o = 5'h0A;
      5'h1E: sbox_o = 5'h0F;
      5'h1F: sbox_o = 5'h17;
    endcase  // case (sbox_i)
  end

endmodule : sbox

