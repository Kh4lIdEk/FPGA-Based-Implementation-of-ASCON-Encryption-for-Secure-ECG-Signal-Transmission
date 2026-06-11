`timescale 1ns / 1ps

module receive
  import uart_pkg::*;
(
    input  logic              clock_i,   //main clock
    input  logic              resetb_i,  //asynchronous reset active low
    input  logic              Rx_i,      //RX to RS232
    input  logic              Top16_i,
    input  logic              top_Rx_i,  //Rx clock
    output logic              RXRdy_o,   //RX ready
    output logic              RXErr_o,   //RX error
    output logic [NDBits-1:0] Dout_o,    //data received
    output logic              ClrDiv_o   //synchronize rx
);
  //signals for rx_reg
  logic [NDBits-1:0] rx_reg_s;  // data received
  logic en_reg_s;  //enable register
  logic init_reg_s;  //init register

  //signals for rxbit_dcounter
  logic [3:0] rx_cpt_s;  //counter value received
  logic en_cpt_s;  //enable counter
  logic init_cpt_s;  //init counter

  //signals for reg_sel
  logic sel_s;

  // signals for the finit state machine
  typedef enum {
    Idle,
    Start_Rx0,
    Start_Rx1,
    Edge_Rx,
    Shift_Rx0,
    Shift_Rx1,
    Stop_Rx0,
    Stop_Rx1,
    Stop_Rx2,
    Rx_OVF
  } state_t;  //fsm state

  state_t etat_p, etat_f;

  rx_reg rx_register (
      .data_i(Rx_i),
      .resetb_i(resetb_i),
      .clock_i(clock_i),
      .en_i(en_reg_s),
      .init_i(init_reg_s),
      .data_o(rx_reg_s)
  );

  rxbit_dcounter rx_counter (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .init_i(init_cpt_s),
      .en_i(en_cpt_s),
      .cpt_o(rx_cpt_s)
  );

  reg_sel rx_sel (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .data_i(rx_reg_s),
      .sel_i(sel_s),
      .data_o(Dout_o)
  );

  //FSM start
  //sequential process
  always_ff @(posedge clock_i or negedge resetb_i) begin : seq_0
    if (resetb_i == 1'b0) begin
      etat_p <= Idle;
    end else begin
      etat_p <= etat_f;
    end
  end : seq_0

  //first combinatorial process transitions
  always_comb begin : comb_0
    case (etat_p)
      Idle:
      if (Top16_i == 1'b1) begin
        if (Rx_i == 1'b0) begin
          etat_f = Start_Rx0;
        end else begin
          etat_f = Idle;
        end
      end else begin
        etat_f = Idle;
      end
      Start_Rx0: etat_f = Start_Rx1;
      Start_Rx1:
      if (top_Rx_i == 1'b1) begin  //wait on first data bit
        if (Rx_i == 1'b1) begin
          etat_f = Rx_OVF;  //framing error
        end else begin
          etat_f = Edge_Rx;
        end
      end else begin
        etat_f = Start_Rx1;
      end
      Edge_Rx:
      if (top_Rx_i == 1'b1) begin
        if (rx_cpt_s == 4'b0) begin
          etat_f = Stop_Rx0;
        end else begin
          etat_f = Shift_Rx0;
        end
      end else begin
        etat_f = Edge_Rx;
      end
      Shift_Rx0:
      if (top_Rx_i == 1'b1) begin  //sample data
        etat_f = Shift_Rx1;
      end else begin
        etat_f = Shift_Rx0;
      end
      Shift_Rx1: etat_f = Edge_Rx;
      Stop_Rx0:
      if (top_Rx_i == 1'b1) begin  //during stop bit
        etat_f = Stop_Rx1;
      end else begin
        etat_f = Stop_Rx0;
      end
      Stop_Rx1:  etat_f = Stop_Rx2;
      Stop_Rx2:  etat_f = Idle;
      Rx_OVF:  //overflow or error
      if (Rx_i == 1'b1) begin
        etat_f = Idle;
      end else begin
        etat_f = Rx_OVF;
      end
      default:   etat_f = Idle;
    endcase
  end : comb_0

  always_comb begin : comb_1
    case (etat_p)
      Idle: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
      Start_Rx0: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b1;
        en_cpt_s = 1'b1;
        init_cpt_s = 1'b1;
        en_reg_s = 1'b1;
        init_reg_s = 1'b1;
        sel_s = 1'b0;
      end
      Start_Rx1: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
      Edge_Rx: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
      Shift_Rx0: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
      Shift_Rx1: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b1;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b1;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
      Stop_Rx0: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
      Stop_Rx1: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b1;
      end
      Stop_Rx2: begin
        RXRdy_o = 1'b1;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
      Rx_OVF: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b1;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
      default: begin
        RXRdy_o = 1'b0;
        RXErr_o = 1'b0;
        ClrDiv_o = 1'b0;
        en_cpt_s = 1'b0;
        init_cpt_s = 1'b0;
        en_reg_s = 1'b0;
        init_reg_s = 1'b0;
        sel_s = 1'b0;
      end
    endcase
  end : comb_1

endmodule : receive
