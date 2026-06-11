`timescale 1ns / 1ps
//Description: counter for transmit one byte
module txbit_dcounter
  import uart_pkg::*;
(
    input  logic       clock_i,   //main clock
    input  logic       resetb_i,  //asynchronous reset active low
    input  logic       en_i,
    input  logic       init_i,
    input  logic [3:0] value_i,
    output logic [3:0] cpt_o
);
  logic [3:0] cpt_s;

  always_ff @(posedge clock_i or negedge resetb_i) begin : seq_0
    if (resetb_i == 1'b0) cpt_s <= '1;
    else begin
      if (en_i == 1'b1) begin
        if (init_i == 1'b1) begin
          cpt_s <= value_i;
        end else begin
          cpt_s <= cpt_s - 1;
        end
      end else begin
        cpt_s <= cpt_s;
      end
    end
  end : seq_0
  assign cpt_o = cpt_s;

endmodule : txbit_dcounter
