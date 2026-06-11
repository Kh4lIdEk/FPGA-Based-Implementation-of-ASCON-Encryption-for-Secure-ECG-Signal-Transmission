package uart_pkg;
  const logic even = 1'b0;  //parity type
                            //1'b0 = even
                            //1'b1 = odd
  const logic parity = 1'b0;  //1'b0 no parity
                              //1'b1 with parity
                              //enable parity
 // const logic NDBits = 8;  //number of data bits
	localparam NDBits = 8;
  const logic debug = 1'b0;  //debug constant

endpackage : uart_pkg
