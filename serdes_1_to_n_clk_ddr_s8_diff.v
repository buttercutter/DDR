///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2009 Xilinx, Inc.
// This design is confidential and proprietary of Xilinx, All Rights Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /   Vendor: Xilinx
// \   \   \/    Version: 1.1
//  \   \        Filename: serdes_1_to_n_clk_ddr_s8_diff.v
//  /   /        Date Last Modified:  January 5 2011
// /___/   /\    Date Created: September 1 2009
// \   \  /  \
//  \___\/\___\
// 
//Device: 	Spartan 6
//Purpose:  	1-bit generic 1:n DDR clock receiver module for serdes factors 
//		from 2 to 8 with differential inputs
// 		Instantiates necessary BUFIO2 clock buffers
//Reference:
//    
//Revision History:
//    Rev 1.0 - First created (nicks)
//    Rev 1.1 - Small changes (nicks)
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

module serdes_1_to_n_clk_ddr_s8_diff (clkin_p, clkin_n, rxioclkp, rxioclkn, rx_serdesstrobe, rx_bufg_x1) ;

parameter integer S = 8 ;   		// Parameter to set the serdes factor 1..8
parameter         DIFF_TERM = "TRUE" ; 	// Parameter to enable internal differential termination

input 		clkin_p ;		// Input from LVDS receiver pin
input 		clkin_n ;		// Input from LVDS receiver pin
output 		rxioclkp ;		// IO Clock network
output 		rxioclkn ;		// IO Clock network
output 		rx_serdesstrobe ;	// Parallel data capture strobe
output 		rx_bufg_x1 ;		// Global clock output

wire 		ddly_m;     		// Master output from IODELAY1
wire 		ddly_s;     		// Slave output from IODELAY1
wire		rx_clk_in ;		//
wire		iob_data_in_p ;		//
wire		iob_data_in_n ;		//

parameter  	RX_SWAP_CLK  = 1'b0 ;	// pinswap mask for input clock (0 = no swap (default), 1 = swap). Allows input to be connected the wrong way round to ease PCB routing.

// There are already IOBUF primitives before 'clkin_n' and 'clkin_p' signals are passed into this verilog module
wire rx_clk_in_n =  clkin_n;
wire rx_clk_in_p =  clkin_p;

/*
IBUFDS_DIFF_OUT #(
	.DIFF_TERM 		(DIFF_TERM)) 
iob_clk_in (
	.I    			(clkin_p),
	.IB       		(clkin_n),
	.OB         		(rx_clk_in_n),
	.O         		(rx_clk_in_p)) ;
*/
	
assign iob_data_in_p = rx_clk_in_p ^ RX_SWAP_CLK ;		// Invert clock as required
assign iob_data_in_n = rx_clk_in_n ^ RX_SWAP_CLK ;		// Invert clock as required

//		IODELAY for the differential inputs.

IODELAY2 #(
	.DATA_RATE      	("SDR"), 			// <SDR>, DDR
	.SIM_TAPDELAY_VALUE	(49),  				// nominal tap delay (sim parameter only)
	.IDELAY_VALUE  		(0), 				// {0 ... 255}
	.IDELAY2_VALUE 		(0), 				// {0 ... 255}
	.ODELAY_VALUE  		(0), 				// {0 ... 255}
	.IDELAY_MODE   		("NORMAL"), 			// "NORMAL", "PCI"
	.SERDES_MODE   		("MASTER"), 			// <NONE>, MASTER, SLAVE
	.IDELAY_TYPE   		("FIXED"), 			// "DEFAULT", "DIFF_PHASE_DETECTOR", "FIXED", "VARIABLE_FROM_HALF_MAX", "VARIABLE_FROM_ZERO"
	.COUNTER_WRAPAROUND 	("STAY_AT_LIMIT"), 		// <STAY_AT_LIMIT>, WRAPAROUND
	.DELAY_SRC     		("IDATAIN")) 			// "IO", "IDATAIN", "ODATAIN"
iodelay_m (
	.IDATAIN  		(iob_data_in_p), 		// data from master IOB
	.TOUT     		(), 				// tri-state signal to IOB
	.DOUT     		(), 				// output data to IOB
	.T        		(1'b1), 			// tri-state control from OLOGIC/OSERDES2
	.ODATAIN  		(1'b0), 			// data from OLOGIC/OSERDES2
	.DATAOUT  		(ddly_m), 			// Output data 1 to ILOGIC/ISERDES2
	.DATAOUT2 		(),	 			// Output data 2 to ILOGIC/ISERDES2
	.IOCLK0   		(1'b0), 			// High speed clock for calibration
	.IOCLK1   		(1'b0), 			// High speed clock for calibration
	.CLK      		(1'b0), 			// Fabric clock (GCLK) for control signals
	.CAL      		(1'b0), 			// Calibrate enable signal
	.INC      		(1'b0), 			// Increment counter
	.CE       		(1'b0), 			// Clock Enable
	.RST      		(1'b0), 			// Reset delay line to 1/2 max in this case
	.BUSY      		()) ;  				// output signal indicating sync circuit has finished / calibration has finished

IODELAY2 #(
	.DATA_RATE      	("SDR"), 			// <SDR>, DDR
	.SIM_TAPDELAY_VALUE	(49),  				// nominal tap delay (sim parameter only)
	.IDELAY_VALUE  		(0), 				// {0 ... 255}
	.IDELAY2_VALUE 		(0), 				// {0 ... 255}
	.ODELAY_VALUE  		(0), 				// {0 ... 255}
	.IDELAY_MODE   		("NORMAL"), 			// "NORMAL", "PCI"
	.SERDES_MODE   		("SLAVE"), 			// <NONE>, MASTER, SLAVE
	.IDELAY_TYPE   		("FIXED"), 			// "DEFAULT", "DIFF_PHASE_DETECTOR", "FIXED", "VARIABLE_FROM_HALF_MAX", "VARIABLE_FROM_ZERO"
	.COUNTER_WRAPAROUND 	("STAY_AT_LIMIT"), 		// <STAY_AT_LIMIT>, WRAPAROUND
	.DELAY_SRC     		("IDATAIN")) 			// "IO", "IDATAIN", "ODATAIN"
iodelay_s (
	.IDATAIN 		(iob_data_in_n), 		// data from slave IOB
	.TOUT     		(), 				// tri-state signal to IOB
	.DOUT     		(), 				// output data to IOB
	.T        		(1'b1), 			// tri-state control from OLOGIC/OSERDES2
	.ODATAIN  		(1'b0), 			// data from OLOGIC/OSERDES2
	.DATAOUT 		(ddly_s), 			// Output data 1 to ILOGIC/ISERDES2
	.DATAOUT2 		(),	 			// Output data 2 to ILOGIC/ISERDES2
	.IOCLK0    		(1'b0), 			// High speed clock for calibration
	.IOCLK1   		(1'b0), 			// High speed clock for calibration
	.CLK      		(1'b0), 			// Fabric clock (GCLK) for control signals
	.CAL      		(1'b0), 			// Calibrate control signal, never needed as the slave supplies the clock input to the PLL
	.INC      		(1'b0), 			// Increment counter
	.CE       		(1'b0), 			// Clock Enable
	.RST      		(1'b0), 			// Reset delay line
	.BUSY      		()) ;				// output signal indicating sync circuit has finished / calibration has finished

BUFG	bufg_pll_x1 (.I(rx_bufio2_x1), .O(rx_bufg_x1) ) ;

BUFIO2_2CLK #(
      .DIVIDE			(S))                		// The DIVCLK divider divide-by value; default 1
bufio2_2clk_inst (
      .I			(ddly_m),  			// Input source clock 0 degrees
      .IB			(ddly_s),  			// Input source clock 0 degrees
      .IOCLK			(rxioclkp),        		// Output Clock for IO
      .DIVCLK			(rx_bufio2_x1),                	// Output Divided Clock
      .SERDESSTROBE		(rx_serdesstrobe)) ;           	// Output SERDES strobe (Clock Enable)

BUFIO2 #(
      .I_INVERT			("FALSE"),               	//
      .DIVIDE_BYPASS		("FALSE"),               	//
      .USE_DOUBLER		("FALSE"))               	//
bufio2_inst (
      .I			(ddly_s),               	// N_clk input from IDELAY
      .IOCLK			(rxioclkn),        		// Output Clock
      .DIVCLK			(),                		// Output Divided Clock
      .SERDESSTROBE		()) ;           		// Output SERDES strobe (Clock Enable)
      
endmodule
