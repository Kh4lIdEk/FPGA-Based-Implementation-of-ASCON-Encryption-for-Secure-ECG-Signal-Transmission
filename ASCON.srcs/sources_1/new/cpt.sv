`timescale 1 ns / 1 ps

module cpt
  import ascon_pack::*;
(
    input  logic         clock_i,
    input  logic         reset_i,
    input  logic         init_cpt_i,
    input  logic         en_cpt_i,
    output logic [4 : 0] data_o
);

  logic [4:0] cpt_s;

always_ff @(posedge clock_i or negedge reset_i) begin
    if (!reset_i)
        cpt_s <= 5'b00000;
    else if (en_cpt_i) begin
        if (init_cpt_i)
            cpt_s <= 5'b00000;
        else
            cpt_s <= cpt_s + 5'b00001;
    end
end

assign data_o = cpt_s;

endmodule