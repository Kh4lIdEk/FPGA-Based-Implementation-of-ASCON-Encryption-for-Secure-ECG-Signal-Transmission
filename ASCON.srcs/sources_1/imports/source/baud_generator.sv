module baud_generator
  import uart_pkg::*;
(
    input logic clock_i,  //main clock
    input logic resetb_i,  //asynchronous reset active low
    input logic clrDiv_i,  // synchronize RX
    input logic [2:0] baud_i,
    output logic Top16_o,  //sub clock from global clock depending on baud rate
    output logic top_Tx_o,  //tx clock
    output logic top_Rx_o  //rx clock
);
  shortint divisor_s = 5208;  // range 0 to 5208 baud division
  shortint div16_s = 5208;  // range 0 to 5208 baud division
  logic    top16_s;  //sub_clock
  shortint clkDiv_s = 16;  // range 0 to 16 clockdiv counter
  shortint rxDiv_s = 7;  // range 0 to 7 clockdiv counter

  always_ff @(posedge clock_i, negedge resetb_i) begin : P0
    if (resetb_i == 1'b0) divisor_s <= '0;
    else begin
      //25MHz
      /*
                case (baud_i)
                 3'b000 : divisor_s <= 16'd13; //115200
                 3'b001 : divisor_s <= 16'd27; //57600
                 3'b010 : divisor_s <= 16'd40; //38400
                 3'b011 : divisor_s <= 16'd81; //19200
                 3'b100 : divisor_s <= 16'd162; //9600
                 3'b101 : divisor_s <= 16'd325; //4800
                 3'b110 : divisor_s <= 16'd651; //2400
                 3'b111 : divisor_s <= 16'd1302; //1200
                 default: divisor_s <= 16'd13;
                endcase
                */
      //50MHz
      case (baud_i)
        3'b000:  divisor_s <= 16'd27;  //115200
        3'b001:  divisor_s <= 16'd54;  //57600
        3'b010:  divisor_s <= 16'd81;  //38400
        3'b011:  divisor_s <= 16'd162;  //19200
        3'b100:  divisor_s <= 16'd325;  //9600
        3'b101:  divisor_s <= 16'd651;  //4800
        3'b110:  divisor_s <= 16'd1302;  //2400
        3'b111:  divisor_s <= 16'd2604;  //1200
        default: divisor_s <= 16'd27;
      endcase
      /**/
      //100MHz
      /*
                case (baud_i)
                 3'b000 : divisor_s <= 16'd54; //115200
                 3'b001 : divisor_s <= 16'd108; //57600
                 3'b010 : divisor_s <= 16'd162; //38400
                 3'b011 : divisor_s <= 16'd325; //19200
                 3'b100 : divisor_s <= 16'd651; //9600
                 3'b101 : divisor_s <= 16'd1302; //4800
                 3'b110 : divisor_s <= 16'd2604; //2400
                 3'b111 : divisor_s <= 16'd5208; //1200
                 default: divisor_s <= 16'd54;
                endcase
                */
    end
  end : P0
  /*
purpose: Clk16 clock generation
  -- type   : sequential
  -- inputs : clock_i, resetb_i, Divisor_s
  -- outputs: top16_s
*/
  always_ff @(posedge clock_i, negedge resetb_i) begin : P1
    if (resetb_i == 1'b0) begin
      top16_s <= 1'b0;
      div16_s <= '0;
    end else begin
      if (div16_s == divisor_s) begin
        div16_s <= '0;
        top16_s <= 1'b1;
      end else begin
        div16_s <= div16_s + 1;
        top16_s <= 1'b0;
      end
    end
  end : P1

  /*
purpose: Tx clock generation
type   : sequential
inputs : clock_i, resetb_i, top16_s, ClockDiv_s
outputs: top_Tx_o
*/
  always_ff @(posedge clock_i, negedge resetb_i) begin : P2
    if (resetb_i == 1'b0) begin
      top_Tx_o <= 1'b0;
      clkDiv_s <= '0;
    end else begin
      if (top16_s == 1'b1) begin
        if (clkDiv_s == 15) begin
          clkDiv_s <= '0;
          top_Tx_o <= 1'b1;
        end else begin
          clkDiv_s <= clkDiv_s + 1;
          top_Tx_o <= 1'b0;
        end
      end else begin
        clkDiv_s <= clkDiv_s;
        top_Tx_o <= 1'b0;
      end
    end
  end : P2

  /*
purpose: Rx sampling Clock Generation
type   : sequential
inputs : clock_i, resetb_i, ClkDiv_s, top16_s, RxDiv_s
outputs: top_Rx_o
*/
  always_ff @(posedge clock_i, negedge resetb_i) begin : P3
    if (resetb_i == 1'b0) begin
      top_Rx_o <= 1'b0;
      rxDiv_s  <= '0;
    end else begin
      if (clrDiv_i == 1'b1) begin
        top_Rx_o <= 1'b0;
        rxDiv_s  <= '0;
      end else if (top16_s == 1'b1) begin
        if (rxDiv_s == 7) begin
          rxDiv_s  <= '0;
          top_Rx_o <= 1'b1;
        end else begin
          rxDiv_s  <= rxDiv_s + 1;
          top_Rx_o <= 1'b0;
        end
      end else begin
        rxDiv_s  <= rxDiv_s;
        top_Rx_o <= 1'b0;
      end
    end
  end : P3

  assign Top16_o = top16_s;

endmodule : baud_generator
