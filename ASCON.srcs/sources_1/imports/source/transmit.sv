`timescale 1ns / 1ps

module transmit
  import uart_pkg::*;
(
    input  logic                clock_i,   //main clock
    input  logic                resetb_i,  //asynchronous reset active low
    input  logic [NDBits-1 : 0] Din_i,     //data to transmit
    input  logic                LD_i,      //load the word to transmit
    input  logic                top_Tx_i,  //Tx clock
    output logic                TxBusy_o,  //Tx busy
    output logic                Tx_o       //Tx to RS 232
);

  //signals for tx_register
  logic [NDBits+1:0] Tx_Reg_s;  //tx temp register
  logic [NDBits+1:0] data_reg_s;
  logic init_reg_s;
  logic en_reg_s;

  //signals for dcounter
  logic init_cpt_s;
  logic en_cpt_s;
  logic [3:0] value_s;
  logic [3:0] cpt_s;

  //signals for reg_sel
  logic sel_reg_s;
  logic [NDBits-1:0] data_out_reg_s;

  //signals for FSM
  typedef enum {
    idle,
    load_0,
    load_1,
    shift_0,
    shift_1,
    stop
  } state_t;
  state_t current_state;
  state_t next_state;

  txbit_dcounter txbit_dcounter_1 (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .init_i(init_cpt_s),
      .value_i(value_s),
      .en_i(en_cpt_s),
      .cpt_o(cpt_s)
  );

  tx_reg tx_register (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .data_i(data_reg_s),
      .init_i(init_reg_s),
      .en_i(en_reg_s),
      .data_o(Tx_Reg_s)
  );

  reg_sel tx_sel (
      .clock_i(clock_i),
      .resetb_i(resetb_i),
      .data_i(Din_i),
      .sel_i(sel_reg_s),
      .data_o(data_out_reg_s)
  );

  //start of FSM
  //sequential process
  always_ff @(posedge clock_i, negedge resetb_i) begin : seq_0
    if (resetb_i == 1'b0) begin
      current_state <= idle;
    end else begin
      current_state <= next_state;
    end
  end : seq_0

  //first combinatorial process transitions
  always_comb begin : comb_0
    case (current_state)
      idle:
      if (LD_i == 1'b1) begin
        next_state = load_0;
      end else next_state = idle;
      load_0:  next_state = load_1;
      load_1:
      if (top_Tx_i == 1'b1) begin
        next_state = shift_0;
      end else begin
        next_state = load_1;
      end
      shift_0:
      if (top_Tx_i == 1'b1) begin
        next_state = shift_1;
      end else begin
        next_state = shift_0;
      end
      shift_1:
      if (cpt_s == 4'd1) begin
        next_state = stop;
      end else begin
        next_state = shift_0;
      end
      stop:
      if (top_Tx_i == 1'b1) begin
        next_state = idle;
      end else begin
        next_state = stop;
      end
      default: next_state = idle;
    endcase
  end : comb_0

  //second combinatorial process outputs computation
  always_comb begin : comb_1
    case (current_state)
      idle: begin
        TxBusy_o = 1'b0;
        Tx_o = 1'b1;
        init_reg_s = 1'b0;
        en_reg_s = 1'b0;
        data_reg_s = '1;
        init_cpt_s = 1'b0;
        en_cpt_s = 1'b0;
        value_s = 4'd15;
        sel_reg_s = 1'b1;
      end
      load_0: begin
        TxBusy_o = 1'b1;
        Tx_o = 1'b1;
        init_reg_s = 1'b1;
        en_reg_s = 1'b1;
        data_reg_s = {1'b1, data_out_reg_s, 1'b0};  //add parity here later
        init_cpt_s = 1'b1;
        en_cpt_s = 1'b1;
        value_s = NDBits + 1;
        sel_reg_s = 1'b0;
      end
      load_1: begin
        TxBusy_o = 1'b1;
        Tx_o = 1'b1;
        init_reg_s = 1'b0;
        en_reg_s = 1'b0;
        data_reg_s = '1;
        init_cpt_s = 1'b0;
        en_cpt_s = 1'b0;
        value_s = 4'd15;
        sel_reg_s = 1'b0;
      end
      shift_0: begin
        TxBusy_o = 1'b1;
        Tx_o = Tx_Reg_s[0];
        init_reg_s = 1'b0;
        en_reg_s = 1'b0;
        data_reg_s = '1;
        init_cpt_s = 1'b0;
        en_cpt_s = 1'b0;
        value_s = 4'd15;
        sel_reg_s = 1'b0;
      end
      shift_1: begin
        TxBusy_o = 1'b1;
        Tx_o = Tx_Reg_s[0];
        init_reg_s = 1'b0;
        en_reg_s = 1'b1;
        data_reg_s = '1;
        init_cpt_s = 1'b0;
        en_cpt_s = 1'b1;
        value_s = 4'd15;
        sel_reg_s = 1'b0;
      end
      stop: begin
        TxBusy_o = 1'b1;
        Tx_o = Tx_Reg_s[0];
        init_reg_s = 1'b0;
        en_reg_s = 1'b0;
        data_reg_s = '1;
        init_cpt_s = 1'b0;
        en_cpt_s = 1'b0;
        value_s = 4'd15;
        sel_reg_s = 1'b0;
      end
      default: begin
        TxBusy_o = 1'b0;
        Tx_o = Tx_Reg_s[0];
        init_reg_s = 1'b0;
        en_reg_s = 1'b0;
        data_reg_s = '1;
        init_cpt_s = 1'b0;
        en_cpt_s = 1'b0;
        value_s = 4'd15;
        sel_reg_s = 1'b0;
      end
    endcase
  end : comb_1
endmodule : transmit
