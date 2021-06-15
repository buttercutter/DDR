///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2009 Xilinx, Inc.
// This design is confidential and proprietary of Xilinx, All Rights Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /   Vendor: Xilinx
// \   \   \/    Version: 1.0
//  \   \        Filename: clock_generator_ddr_s8_diff.v
//  /   /        Date Last Modified:  November 5 2009
// /___/   /\    Date Created: September 1 2009
// \   \  /  \
//  \___\/\___\
// 
//Device: 	Spartan 6
//Purpose:  	BUFIO2 Based DDR clock generator. Takes in a differential clock 
//		and instantiates two sets of 2 BUFIO2s, one for each half bank
//Reference:
//    
//Revision History:
//    Rev 1.0 - First created (nicks)
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

module clock_generator_ddr_s8_diff (clkin_p, clkin_n, ioclkap, ioclkan, serdesstrobea, ioclkbp, ioclkbn, serdesstrobeb, gclk) ;

parameter integer S = 8 ;   			// Parameter to set the serdes factor 1..8
parameter         DIFF_TERM = "TRUE" ;	 	// Parameter to enable internal differential termination

input		clkin_p, clkin_n ;		// differential clock input
output		ioclkap ;			// A P ioclock from BUFIO2
output		ioclkan ;			// A N ioclock from BUFIO2
output		serdesstrobea ;			// A serdes strobe from BUFIO2
output		ioclkbp ;			// B P ioclock from BUFIO2 - leave open if not required
output		ioclkbn ;			// B N ioclock from BUFIO2 - leave open if not required
output		serdesstrobeb ;			// B serdes strobe from BUFIO2 - leave open if not required
output		gclk ;				// global clock output from BUFIO2

wire 		clkint ;			// 
wire    	gclk_int ;      		// 
wire    	freqgen_in_p ;      		// 
wire 		tx_bufio2_x1 ;			// 

assign gclk = gclk_int ;

IBUFGDS #(
	.DIFF_TERM 		(DIFF_TERM)) 
clk_iob_in (
	.I    			(clkin_p),
	.IB       		(clkin_n),
	.O         		(freqgen_in_p));

BUFIO2 #(
      .DIVIDE			(S),              		// The DIVCLK divider divide-by value; default 1
      .I_INVERT			("FALSE"),               	//
      .DIVIDE_BYPASS		("FALSE"),               	//
      .USE_DOUBLER		("TRUE"))               		
bufio2_inst1 (              
      .I			(freqgen_in_p),  		// Input source clock 0 degrees
      .IOCLK			(ioclkap),        		// Output Clock for IO
      .DIVCLK			(tx_bufio2_x1),                	// Output Divided Clock
      .SERDESSTROBE		(serdesstrobea)) ;           	// Output SERDES strobe (Clock Enable)
                                
BUFIO2 #(                       
      .I_INVERT			("TRUE"),               		
      .DIVIDE_BYPASS		("FALSE"),               	//
      .USE_DOUBLER		("FALSE"))               	//
bufio2_inst2 (                   
      .I			(freqgen_in_p),               	// N_clk input from IDELAY
      .IOCLK			(ioclkan),        		// Output Clock
      .DIVCLK			(),                		// Output Divided Clock
      .SERDESSTROBE		()) ;           		// Output SERDES strobe (Clock Enable)
                                
BUFIO2 #(                       
      .DIVIDE			(S),              		// The DIVCLK divider divide-by value; default 1
      .I_INVERT			("FALSE"),               	//
      .DIVIDE_BYPASS		("FALSE"),               	//
      .USE_DOUBLER		("TRUE"))               		//
bufio2_inst3 (            
      .I			(freqgen_in_p),  		// Input source clock 0 degrees
      .IOCLK			(ioclkbp),        		// Output Clock for IO
      .DIVCLK			(),                		// Output Divided Clock
      .SERDESSTROBE		(serdesstrobeb)) ;           	// Output SERDES strobe (Clock Enable)
                                
BUFIO2 #(                       
      .I_INVERT			("TRUE"),               		
      .DIVIDE_BYPASS		("FALSE"),               	//
      .USE_DOUBLER		("FALSE"))               	//
bufio2_inst4  (                
      .I			(freqgen_in_p),               	// N_clk input from IDELAY
      .IOCLK			(ioclkbn),        		// Output Clock
      .DIVCLK			(),                		// Output Divided Clock
      .SERDESSTROBE		()) ;           		// Output SERDES strobe (Clock Enable)

BUFG bufg_tx (.I (tx_bufio2_x1), .O (gclk_int)) ;

endmodule
