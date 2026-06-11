`timescale 1 ns / 1 ps


module a_data_reg_shift
  import uart_pkg::*;
(
    input logic                 clock_i, 
    input logic                 resetb_i,
    input logic                 en_i,  
    input logic                 init_i,
    input  logic    [7 : 0]     a_data_i,
    output logic    [63 : 0]    a_data_o  
);
    logic [63:0] a_data_s;
    
    always_ff@(posedge clock_i or negedge resetb_i) begin
    if (resetb_i == 1'b0) a_data_s <= '0;
        else if (en_i)
                a_data_s <= init_i ? '0 : {a_data_s[55:0], a_data_i};
        end
    
    assign a_data_o = a_data_s;
    
endmodule: a_data_reg_shift