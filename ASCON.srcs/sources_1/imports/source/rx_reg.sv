`timescale 1ns / 1ps
//Description: register for receive
module rx_reg
  import uart_pkg::*;
(
    input  logic              clock_i,   //main clock
    input  logic              resetb_i,  //asynchronous reset active low
    input  logic              data_i,
    input  logic              en_i,
    input  logic              init_i,
    output logic [NDBits-1:0] data_o
);
  logic [NDBits-1:0] data_s;

  always_ff @(posedge clock_i or negedge resetb_i) begin : seq_0
    if (resetb_i == 1'b0) data_s <= '0;
    else begin
      if (en_i == 1'b1) begin
        if (init_i == 1'b1) begin
          data_s <= '0;
        end else begin
          data_s <= {data_i, data_s[NDBits-1:1]};
        end
      end else begin
        data_s <= data_s;
      end
    end
  end : seq_0
  assign data_o = data_s;

endmodule : rx_reg
