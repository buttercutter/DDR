///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2009 Xilinx, Inc.
// This design is confidential and proprietary of Xilinx, All Rights Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /   Vendor: Xilinx
// \   \   \/    Version: 1.1
//  \   \        Filename: serdes_1_to_n_data_ddr_s8_diff.v
//  /   /        Date Last Modified:  February 5 2010
// /___/   /\    Date Created: September 1 2009
// \   \  /  \
//  \___\/\___\
// 
//Device: 	Spartan 6
//Purpose:  	D-bit generic 1:n data receiver module with differential inputs for DDR systems
// 		Takes in 1 bit of differential data and deserialises this to n bits
// 		data is received LSB first
//		Serial input words
//		Line0     : 0,   ...... DS-(S+1)
// 		Line1 	  : 1,   ...... DS-(S+2)
// 		Line(D-1) : .           .
// 		Line(D)   : D-1, ...... DS
// 		Parallel output word
//		DS, DS-1 ..... 1, 0
//
//		Includes state machine to control CAL and the phase detector
//		Data inversion can be accomplished via the RX_SWAP_MASK parameter if required
//Reference:
//    
//Revision History:
//    Rev 1.0 - First created (nicks)
//    Rev 1.1 - Modified (nicks)
//		- phase detector state machine moved down in the hierarchy to line up with the version in coregen, will need adding to ISE project
//
///////////////////////////////////////////////////////////////////////////////
//
//  Disclaimer: 
//
//		This disclaimer is not a license and does not grant any rights to the materials 
//              distributed herewith. Except as otherwise provided in a valid license issued to you 
//              by Xilinx, and to the maximum extent permitted by applicable law: 
//              (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND WITH ALL FAULTS, 
//              AND XILINX HEREBY DISCLAIMS ALL WARRANTIES AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, 
//              INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-INFRINGEMENT, OR 
//              FITNESS FOR ANY PARTICULAR PURPOSE; and (2) Xilinx shall not be liable (whether in contract 
//              or tort, including negligence, or under any other theory of liability) for any loss or damage 
//              of any kind or nature related to, arising under or in connection with these materials, 
//              including for any direct, or any indirect, special, incidental, or consequential loss 
//              or damage (including loss of data, profits, goodwill, or any type of loss or damage suffered 
//              as a result of any action brought by a third party) even if such damage or loss was 
//              reasonably foreseeable or Xilinx had been advised of the possibility of the same.
//
//  Critical Applications:
//
//		Xilinx products are not designed or intended to be fail-safe, or for use in any application 
//		requiring fail-safe performance, such as life-support or safety devices or systems, 
//		Class III medical devices, nuclear facilities, applications related to the deployment of airbags,
//		or any other applications that could lead to death, personal injury, or severe property or 
//		environmental damage (individually and collectively, "Critical Applications"). Customer assumes 
//		the sole risk and liability of any use of Xilinx products in Critical Applications, subject only 
//		to applicable laws and regulations governing limitations on product liability.
//
//  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS PART OF THIS FILE AT ALL TIMES.
//
//////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

module serdes_1_to_n_data_ddr_s8_diff (use_phase_detector, datain_p, datain_n, rxioclkp, rxioclkn, rxserdesstrobe, reset, gclk, bitslip, debug_in, data_out, debug) ;

parameter integer 	S = 8 ;   		// Parameter to set the serdes factor 1..8
parameter integer 	D = 16 ;		// Set the number of inputs and outputs
parameter         	DIFF_TERM = "TRUE" ; 	// Parameter to enable internal differential termination

input 			use_phase_detector ;	// '1' enables the phase detcetor logic
input 	[D-1:0]		datain_p ;		// Input from LVDS receiver pin
input 	[D-1:0]		datain_n ;		// Input from LVDS receiver pin
input 			rxioclkp ;		// IO Clock network
input 			rxioclkn ;		// IO Clock network
input 			rxserdesstrobe ;	// Parallel data capture strobe
input 			reset ;			// Reset line
input 			gclk ;			// Global clock
input 			bitslip ;		// Bitslip control line
input 	[1:0]		debug_in ;		// Debug Inputs
output 	[(D*S)-1:0]	data_out ;		// Output data
output 	[3*D+5:0] 	debug ;			// Debug bus, 3D+5 = 3 lines per input (from inc, mux and ce) + 6, leave nc if debug not required

wire 	[D-1:0]		ddly_m;     		// Master output from IODELAY1
wire 	[D-1:0]		ddly_s;     		// Slave output from IODELAY1
wire 	[D-1:0]		rx_data_in ;		//
wire 	[D-1:0]		rx_data_in_fix ;	//
wire 	[D-1:0]		cascade ;		//
wire 	[D-1:0]		pd_edge ;		//
wire 	[D-1:0]		busy_data ;		//
wire			cal_data_slave ;	//
wire			cal_data_master ;	//
wire			rst_data ;		//
wire 	[D-1:0]		inc_data ;		//
wire 	[D-1:0]		ce_data ;		//
wire 	[D-1:0]		valid_data ;		//
wire 	[D-1:0]		incdec_data ;		//
wire	[(8*D)-1:0] 	mdataout ;		//

parameter [D-1:0] RX_SWAP_MASK = 16'h0000 ;	// pinswap mask for input bits (0 = no swap (default), 1 = swap). Allows inputs to be connected the wrong way round to ease PCB routing.

phase_detector #(
	.D		      	(D)) 			// Set the number of inputs
pd_state_machine (
	.use_phase_detector 	(use_phase_detector),
	.busy			(busy_data),
	.valid 			(valid_data),	
	.inc_dec 		(incdec_data),	
	.reset 			(reset),	
	.gclk 			(gclk),		
	.debug_in		(debug_in),		
	.cal_master		(cal_data_master),
	.cal_slave 		(cal_data_slave),	
	.rst_out 		(rst_data),
	.ce 			(ce_data),
	.inc			(inc_data),
	.debug			(debug)) ;

genvar i ;					
genvar j ;

generate
for (i = 0 ; i <= (D-1) ; i = i+1)
begin : loop0

assign rx_data_in_fix[i] = rx_data_in[i] ^ RX_SWAP_MASK[i] ;	// Invert signals as required

IBUFDS #(
	.DIFF_TERM 		(DIFF_TERM)) 
data_in (
	.I    			(datain_p[i]),
	.IB       		(datain_n[i]),
	.O         		(rx_data_in[i]));

IODELAY2 #(
	.DATA_RATE      	("DDR"), 		// <SDR>, DDR
	.IDELAY_VALUE  		(0), 			// {0 ... 255}
	.IDELAY2_VALUE 		(0), 			// {0 ... 255}
	.IDELAY_MODE  		("NORMAL" ), 		// NORMAL, PCI
	.ODELAY_VALUE  		(0), 			// {0 ... 255}
	.IDELAY_TYPE   		("DIFF_PHASE_DETECTOR"),// "DEFAULT", "DIFF_PHASE_DETECTOR", "FIXED", "VARIABLE_FROM_HALF_MAX", "VARIABLE_FROM_ZERO"
	.COUNTER_WRAPAROUND 	("WRAPAROUND" ), 	// <STAY_AT_LIMIT>, WRAPAROUND
	.DELAY_SRC     		("IDATAIN" ), 		// "IO", "IDATAIN", "ODATAIN"
	.SERDES_MODE   		("MASTER")) 		// <NONE>, MASTER, SLAVE
iodelay_m (
	.IDATAIN  		(rx_data_in_fix[i]), 	// data from primary IOB
	.TOUT     		(), 			// tri-state signal to IOB
	.DOUT     		(), 			// output data to IOB
	.T        		(1'b1), 		// tri-state control from OLOGIC/OSERDES2
	.ODATAIN  		(1'b0), 		// data from OLOGIC/OSERDES2
	.DATAOUT  		(ddly_m[i]), 		// Output data 1 to ILOGIC/ISERDES2
	.DATAOUT2 		(),	 		// Output data 2 to ILOGIC/ISERDES2
	.IOCLK0   		(rxioclkp), 		// High speed clock for calibration
	.IOCLK1   		(rxioclkn), 		// High speed clock for calibration
	.CLK      		(gclk), 		// Fabric clock (GCLK) for control signals
	.CAL      		(cal_data_master),	// Calibrate control signal
	.INC      		(inc_data[i]), 		// Increment counter
	.CE       		(ce_data[i]), 		// Clock Enable
	.RST      		(rst_data),		// Reset delay line
	.BUSY      		()) ; 			// output signal indicating sync circuit has finished / calibration has finished

IODELAY2 #(
	.DATA_RATE      	("DDR"), 		// <SDR>, DDR
	.IDELAY_VALUE  		(0), 			// {0 ... 255}
	.IDELAY2_VALUE 		(0), 			// {0 ... 255}
	.IDELAY_MODE  		("NORMAL" ), 		// NORMAL, PCI
	.ODELAY_VALUE  		(0), 			// {0 ... 255}
	.IDELAY_TYPE   		("DIFF_PHASE_DETECTOR"),// "DEFAULT", "DIFF_PHASE_DETECTOR", "FIXED", "VARIABLE_FROM_HALF_MAX", "VARIABLE_FROM_ZERO"
	.COUNTER_WRAPAROUND 	("WRAPAROUND" ), 	// <STAY_AT_LIMIT>, WRAPAROUND
	.DELAY_SRC     		("IDATAIN" ), 		// "IO", "IDATAIN", "ODATAIN"
	.SERDES_MODE   		("SLAVE")) 		// <NONE>, MASTER, SLAVE
iodelay_s (
	.IDATAIN 		(rx_data_in_fix[i]), 	// data from primary IOB
	.TOUT     		(), 			// tri-state signal to IOB
	.DOUT     		(), 			// output data to IOB
	.T        		(1'b1), 		// tri-state control from OLOGIC/OSERDES2
	.ODATAIN  		(1'b0), 		// data from OLOGIC/OSERDES2
	.DATAOUT  		(ddly_s[i]), 		// Output data 1 to ILOGIC/ISERDES2
	.DATAOUT2 		(),	 		// Output data 2 to ILOGIC/ISERDES2
	.IOCLK0   		(rxioclkp), 		// High speed clock for calibration
	.IOCLK1   		(rxioclkn), 		// High speed clock for calibration
	.CLK      		(gclk), 		// Fabric clock (GCLK) for control signals
	.CAL      		(cal_data_slave),	// Calibrate control signal
	.INC      		(inc_data[i]), 		// Increment counter
	.CE       		(ce_data[i]), 		// Clock Enable
	.RST      		(rst_data),		// Reset delay line
	.BUSY      		(busy_data[i])) ;	// output signal indicating sync circuit has finished / calibration has finished

ISERDES2 #(
	.DATA_WIDTH     	(S), 			// SERDES word width.  This should match the setting is BUFPLL
	.DATA_RATE      	("DDR"), 		// <SDR>, DDR
	.BITSLIP_ENABLE 	("TRUE"), 		// <FALSE>, TRUE
	.SERDES_MODE    	("MASTER"), 		// <DEFAULT>, MASTER, SLAVE
	.INTERFACE_TYPE 	("RETIMED")) 		// NETWORKING, NETWORKING_PIPELINED, <RETIMED>
iserdes_m (
	.D       		(ddly_m[i]),
	.CE0     		(1'b1),
	.CLK0    		(rxioclkp),
	.CLK1    		(rxioclkn),
	.IOCE    		(rxserdesstrobe),
	.RST     		(reset),
	.CLKDIV  		(gclk),
	.SHIFTIN 		(pd_edge[i]),
	.BITSLIP 		(bitslip),
	.FABRICOUT 		(),
	.Q4  			(mdataout[(8*i)+7]),
	.Q3  			(mdataout[(8*i)+6]),
	.Q2  			(mdataout[(8*i)+5]),
	.Q1  			(mdataout[(8*i)+4]),
	.DFB  			(),
	.CFB0 			(),
	.CFB1 			(),
	.VALID    		(valid_data[i]),
	.INCDEC   		(incdec_data[i]),
	.SHIFTOUT 		(cascade[i]));

ISERDES2 #(
	.DATA_WIDTH     	(S), 			// SERDES word width.  This should match the setting is BUFPLL
	.DATA_RATE      	("DDR"), 		// <SDR>, DDR
	.BITSLIP_ENABLE 	("TRUE"), 		// <FALSE>, TRUE
	.SERDES_MODE    	("SLAVE"), 		// <DEFAULT>, MASTER, SLAVE
	.INTERFACE_TYPE 	("RETIMED")) 		// NETWORKING, NETWORKING_PIPELINED, <RETIMED>
iserdes_s (
	.D       		(ddly_s[i]),
	.CE0     		(1'b1),
	.CLK0    		(rxioclkp),
	.CLK1    		(rxioclkn),
	.IOCE    		(rxserdesstrobe),
	.RST     		(reset),
	.CLKDIV  		(gclk),
	.SHIFTIN 		(cascade[i]),
	.BITSLIP 		(bitslip),
	.FABRICOUT 		(),
	.Q4  			(mdataout[(8*i)+3]),
	.Q3  			(mdataout[(8*i)+2]),
	.Q2  			(mdataout[(8*i)+1]),
	.Q1  			(mdataout[(8*i)+0]),
	.DFB  			(),
	.CFB0 			(),
	.CFB1 			(),
	.VALID 			(),
	.INCDEC 		(),
	.SHIFTOUT 		(pd_edge[i]));

// Assign received data bits to correct place in data word, and invert as necessary using information from the data mask

for (j = 7 ; j >= (8-S) ; j = j-1)			// j is for serdes factor
begin : loop2
assign data_out[((D*(j+S-8))+i)] = mdataout[(8*i)+j] ;
end
end
endgenerate

endmodule
