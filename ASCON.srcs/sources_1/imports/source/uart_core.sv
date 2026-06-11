`timescale 1ns / 1ps

module uart_core
  import uart_pkg::*;
(
    input  logic                clock_i,   //main clock
    input  logic                resetb_i,  //asynchronous reset active low
    input  logic [NDBits-1 : 0] Din_i,     //data to transmit
    input  logic                LD_i,      //load the word to transmit
    input  logic                Rx_i,      //RX to RS232
    input  logic [         2:0] Baud_i,    //baud selection
    output logic                RXRdy_o,   //RX ready
    output logic                RXErr_o,   //RX error
    output logic [  NDBits-1:0] Dout_o,    //data out (received)
    output logic                Tx_o,      //Tx to RS 232
    output logic                TxBusy_o
);

  //intermediate signals
  logic top16_s;
  logic top_Rx_s;
  logic top_Tx_s;
  logic clrDiv_s;

  //baud_generator instance
  baud_generator baud_generator_0 (
      .clock_i (clock_i),
      .resetb_i(resetb_i),
      .clrDiv_i(clrDiv_s),
      .baud_i  (Baud_i),
      .Top16_o (top16_s),
      .top_Tx_o(top_Tx_s),
      .top_Rx_o(top_Rx_s)
  );

  //transmitter instance
  transmit transmit_0 (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .Din_i(Din_i),
      .LD_i(LD_i),
      .top_Tx_i(top_Tx_s),
      .TxBusy_o(TxBusy_o),
      .Tx_o(Tx_o)
  );

  //receiver instance
  receive receive_0 (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .Rx_i(Rx_i),
      .Top16_i(top16_s),
      .top_Rx_i(top_Rx_s),
      .RXRdy_o(RXRdy_o),
      .RXErr_o(RXErr_o),
      .Dout_o(Dout_o),
      .ClrDiv_o(clrDiv_s)
  );
endmodule : uart_core
