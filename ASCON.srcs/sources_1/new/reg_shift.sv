`timescale 1 ns / 1 ps


module reg_shift
  import uart_pkg::*;
(
    input logic clock_i, 
    input logic resetb_i,
    input logic en_i,  
    input logic init_i,
    input  logic [7 : 0]        nonce_i,
    output logic [127 : 0]      nonce_o  
);
    logic [127:0] nonce_s; 
    
    always_ff@(posedge clock_i or negedge resetb_i) begin
    if (resetb_i == 1'b0) nonce_s <= '0;
       else if (en_i)
                nonce_s <= init_i ? '0 : {nonce_s[119:0], nonce_i};
        end
    
    assign nonce_o = nonce_s;
    
endmodule: reg_shift