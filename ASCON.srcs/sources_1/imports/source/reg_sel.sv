`timescale 1ns / 1ps
//Description: register with enable
module reg_sel
  import uart_pkg::*;
(
    input  logic              clock_i,   //main clock
    input  logic              resetb_i,  //asynchronous reset active low
    input  logic [NDBits-1:0] data_i,
    input  logic              sel_i,
    output logic [NDBits-1:0] data_o
);
  logic [NDBits-1:0] data_s;

  always_ff @(posedge clock_i or negedge resetb_i) begin : seq_0
    if (resetb_i == 1'b0) data_s <= '0;
    else begin
      if (sel_i == 1'b1) begin
        data_s <= data_i;
      end else begin
        data_s <= data_s;
      end
    end
  end : seq_0
  assign data_o = data_s;

endmodule : reg_sel
