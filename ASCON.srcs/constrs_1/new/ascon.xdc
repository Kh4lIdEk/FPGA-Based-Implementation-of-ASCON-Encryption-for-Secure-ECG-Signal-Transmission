############################
# On-board leds             #
############################
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {Baud_o[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {Baud_o[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {Baud_o[2]}]
#set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33} [get_ports {Baud_o[3]}]

####
# ----------------------------------------------------------------------------
# User PUSH Switches - Bank 35
# ----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {Baud_i[0]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {Baud_i[1]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports {Baud_i[2]}]
#resetb_i
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports reset_i]

## Clock signal 125 MHz

set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports clock_i]
#create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clock_i }];

#UART PMODA pin jap1-> RTS jan1-> Tx_o jap2-> Rx_o
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports RTS_o]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports Tx_o]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports Rx_i]

