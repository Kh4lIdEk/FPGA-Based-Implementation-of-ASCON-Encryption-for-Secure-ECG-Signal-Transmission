`timescale 1 ns / 1 ps


module key_reg_shift
  import uart_pkg::*;
(
    input logic clock_i, 
    input logic resetb_i,
    input logic en_i,  
    input logic init_i,
    input  logic [7 : 0]        key_i,
    output logic [127 : 0]      key_o  
);
    logic [127:0] key_s;
    
    always_ff@(posedge clock_i or negedge resetb_i) begin
    if (resetb_i == 1'b0) key_s <= '0;
       else if (en_i)
                key_s <= init_i ? '0 : {key_s[119:0], key_i};
        end

    assign key_o = key_s;

endmodule: key_reg_shift