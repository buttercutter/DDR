// Credit : https://github.com/MartinGeisse/esdk2/blob/master/simsyn/orange-crab/src/mahdl/name/martingeisse/esdk/riscv/orange_crab/ddr3/RamController.mahdl


// Unable to simulate loopback transaction (write some data into RAM, then read those data back from RAM)
// because the verilog simulation model provided by Micron
// https://www.micron.com/products/dram/ddr3-sdram/part-catalog/mt41k64m16tw-107
// does not yet support modelling of DLL off mode

// Once this code supports DLL on mode, formal verification will proceed with using Micron simulation model


`define USE_x16 1
// `define HIGH_SPEED 1
// `define TDQS 1

//`define RAM_SIZE_1GB
`define RAM_SIZE_2GB
//`define RAM_SIZE_4GB

// for internal logic analyzer
`define USE_ILA 1

// for lattice ECP5 FPGA
//`define LATTICE 1

// for Xilinx Spartan-6 FPGA
`define XILINX 1


`ifndef XILINX
localparam NUM_OF_DDR_STATES = 20;

// https://www.systemverilog.io/understanding-ddr4-timing-parameters
// TIME_INITIAL_CK_INACTIVE = 24999;
localparam MAX_TIMING = 24999;  // just for initial development stage, will refine the value later
`endif


// https://www.systemverilog.io/ddr4-basics
module ddr3_memory_controller
#(
	parameter CLK_PERIOD = 20,  // host clock period in ns
	
	`ifdef RAM_SIZE_1GB
		parameter ADDRESS_BITWIDTH = 14,
		
	`elsif RAM_SIZE_2GB
		parameter ADDRESS_BITWIDTH = 15,
		
	`elsif RAM_SIZE_4GB
		parameter ADDRESS_BITWIDTH = 16,
	`endif
	
	parameter BANK_ADDRESS_BITWIDTH = 3,  //  8 banks, and $clog2(8) = 3
	
	`ifdef USE_x16
		parameter DQ_BITWIDTH = 16  // bitwidth for each piece of data
	`else
		parameter DQ_BITWIDTH = 8  // bitwidth for each piece of data
	`endif
)
(
	// these are FPGA internal signals
	input clk,
	input reset,
	input write_enable,  // write to DDR memory
	input read_enable,  // read from DDR memory
	input [BANK_ADDRESS_BITWIDTH+ADDRESS_BITWIDTH-1:0] i_user_data_address,  // the DDR memory address for which the user wants to write/read the data
	input [DQ_BITWIDTH-1:0] i_user_data,  // data for which the user wants to write/read to/from DDR
	output reg [DQ_BITWIDTH-1:0] o_user_data,  // the requested data from DDR RAM after read operation
	
	// these are to be fed into external DDR3 memory
	output reg [ADDRESS_BITWIDTH-1:0] address,
	output reg [BANK_ADDRESS_BITWIDTH-1:0] bank_address,
	output ck, // CK
	output ck_n, // CK#
	output reg ck_en, // CKE
	output reg cs_n, // chip select signal
	// output reg odt, // on-die termination
	output reg ras_n, // RAS#
	output reg cas_n, // CAS#
	output reg we_n, // WE#
	output reg reset_n,
	
	inout [DQ_BITWIDTH-1:0] dq, // Data input/output
	
// Xilinx ILA could not probe port IO of IOBUF primitive, but could probe rest of the ports (ports I, O, and T)
`ifdef USE_ILA
	output [DQ_BITWIDTH-1:0] dq_w,  // port I
	input [DQ_BITWIDTH-1:0] dq_r,  // port O
	
	`ifndef XILINX
	output reg [$clog2(NUM_OF_DDR_STATES)-1:0] main_state,
	output reg [$clog2(MAX_TIMING)-1:0] wait_count,
	`else
	output reg [4:0] main_state,
	output reg [14:0] wait_count,
	`endif
`endif

`ifdef USE_x16
	output ldm,  // lower-byte data mask, to be asserted HIGH during data write activities into RAM
	output udm, // upper-byte data mask, to be asserted HIGH during data write activities into RAM
	inout ldqs, // lower byte data strobe
	inout ldqs_n,
	inout udqs, // upper byte data strobe
	inout udqs_n
`else
	inout dqs, // Data strobe
	inout dqs_n,
	
	// driven to high-Z if TDQS termination function is disabled 
	// according to TN-41-06: DDR3 Termination Data Strobe (TDQS)
	// Please as well look at TN-41-04: DDR3 Dynamic On-Die Termination Operation 
	`ifdef TDQS
	inout tdqs, // Termination data strobe, but can act as data-mask (DM) when TDQS function is disabled
	`else
	output tdqs,
	`endif
	inout tdqs_n
`endif
);

// When writes are done on bus with a data-width > 8, you are doing a single write for multiple bytes and 
// then need to be able to indicate which bytes are valid and need to be updated in memory, 
// which bytes should be ignored. That's the purpose of DM.
// It is allowed to have DM always pulled low (some boards are wired like this) but will make you loose 
// the byte granularity on writes, your granularity is then on DRAM's burst words.
// DM is just here to have byte granularity on the write accesses 
// (ie you only want to update some bytes of the DRAM word)

`ifndef USE_x16
	`ifndef TDQS
	assign tdqs = 0;  // acts as DM
	`endif
`endif

/*
reg previous_clk_en;
always @(posedge clk) 
begin
	if(reset) previous_clk_en <= 0;
	
	previous_clk_en <= clk_en;
end
*/


//wire A10 = address[10];
//wire A12 = address[12];


// Commands truth table extracted from Micron specification document
/*
localparam MRS = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (~we_n);
localparam REF = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (we_n);
localparam PRE = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (cas_n) & (~we_n) & (~A10);
localparam PREA = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (~we_n) & (A10);
localparam ACT = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (cas_n) & (we_n);
localparam WR = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (~we_n) & (~A10);
localparam WRS4 = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (~we_n) & (~A12) & (~A10);
localparam WRS8 = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (~we_n) & (A12) & (~A10);
localparam WRAP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (~we_n) & (A10);
localparam WRAPS4 = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (~we_n) & (~A12) & (A10);
localparam WRAPS8 = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (~we_n) & (A12) & (A10);
localparam RD = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (we_n) & (~A10);
localparam RDS4 = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (we_n) & (~A12) & (~A10);
localparam RDS8 = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (we_n) & (A12) & (~A10);
localparam RDAP = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (we_n) & (A10);
localparam RDAPS4 = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (we_n) & (~A12) & (A10);
localparam RDAPS8 = (previous_clk_en) & (ck_en) & (~cs_n) & (~ras_n) & (~cas_n) & (we_n) & (A12) & (A10);
localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
localparam DES = (previous_clk_en) & (ck_en) & (cs_n);
localparam PDE = (previous_clk_en) & (~ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
localparam PDX = (~previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
localparam ZQCL = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (~we_n) & (A10);
localparam ZQCS = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (~we_n) & (~A10);
*/


`ifndef USE_ILA
	`ifndef XILINX
	reg [$clog2(NUM_OF_DDR_STATES)-1:0] main_state;
	`else
	reg [4:0] main_state;
	`endif
`endif


`ifndef USE_ILA
	`ifndef XILINX
	reg [$clog2(MAX_TIMING)-1:0] wait_count;  // for the purpose of calculating DDR timing parameters such as tXPR, tRFC, ...
	`else
	// $clog2(24999) = 15
	reg [14:0] wait_count;  // for the purpose of calculating DDR timing parameters such as tXPR, tRFC, ...
	`endif
`endif


localparam STATE_RESET = 0;
localparam STATE_RESET_FINISH = 1;
localparam STATE_ZQ_CALIBRATION = 2;
localparam STATE_IDLE = 4;
localparam STATE_ACTIVATE = 5;
localparam STATE_WRITE = 6;
localparam STATE_WRITE_AP = 7;
localparam STATE_WRITE_DATA = 8;
localparam STATE_READ = 9;
localparam STATE_READ_AP = 10;
localparam STATE_READ_DATA = 11;
localparam STATE_PRECHARGE = 12;
localparam STATE_REFRESH = 13;
localparam STATE_WRITE_LEVELLING = 14;
localparam STATE_INIT_CLOCK_ENABLE = 15;
localparam STATE_INIT_MRS_2 = 16;
localparam STATE_INIT_MRS_3 = 17;
localparam STATE_INIT_MRS_1 = 18;
localparam STATE_INIT_MRS_0 = 19;


`ifndef HIGH_SPEED

// Purposes of Clock divider:
// 1. for developing correct logic first before making the DDR memory controller works in higher frequency,
// 2. to perform 90 degree phase shift on DQ signal with relative to DQS signal during data writing stage
// 3. to perform 180 degree phase shift (DDR mechanism of both DQS and DQ signals need to work on 
//	  both posedge and negedge clk) for the next consecutive data

// See https://i.imgur.com/dnDwZul.png or 
// https://www.markimicrowave.com/blog/top-7-ways-to-create-a-quadrature-90-phase-shift/
// See https://i.imgur.com/ZnBuofE.png or
// https://patentimages.storage.googleapis.com/0e/94/46/6fdcafc946e940/US5297181.pdf#page=3
// Will use digital PLL or https://stackoverflow.com/a/50172237/8776167 in later stage of the project

// See https://www.edaplayground.com/x/gXC for waveform simulation of the clock divider
reg clk_slow;
localparam DIVIDE_RATIO = 4;
localparam DIVIDE_RATIO_HALVED = (DIVIDE_RATIO >> 1);

`ifndef XILINX
reg [($clog2(DIVIDE_RATIO_HALVED)-1):0] counter;
`else
reg [1:0] counter;
`endif

reg counter_reset;

always @(posedge clk)
begin
	if(reset) counter_reset <= 0;

`ifndef XILINX	
	else counter_reset <= (counter == DIVIDE_RATIO_HALVED[0 +: $clog2(DIVIDE_RATIO >> 1)] - 1'b1);
`else
	else counter_reset <= (counter == DIVIDE_RATIO_HALVED[0 +: 1] - 1'b1);
`endif
end

always @(posedge clk)
begin
	if(reset) counter <= 0;
	
	else if(counter_reset) counter <= 1;
	
	else counter <= counter + 1;
end

always @(posedge clk)
begin
	if(reset) clk_slow <= 0;
	
	else if(counter_reset)
	  	clk_slow <= ~clk_slow;
end

assign ck = clk_slow;
assign ck_n = ~clk_slow;

wire clk90_slow_is_at_high = (~clk_slow && counter_reset) || (clk_slow && ~counter_reset);
wire clk90_slow_is_at_low = (clk_slow && counter_reset) || (~clk_slow && ~counter_reset);
wire clk90_slow_posedge = (~clk_slow && counter_reset);
// wire clk180_slow = ~clk_slow;  // simply inversion of the clk_slow signal will give 180 degree phase shift


// outgoing signals to RAM
wire dqs_w;
wire dqs_n_w;
`ifndef USE_ILA
	wire [DQ_BITWIDTH-1:0] dq_w;  // the output data stream is NOT serialized
`endif

// incoming signals from RAM
wire dqs_r;
wire dqs_n_r;
`ifndef USE_ILA
	wire [DQ_BITWIDTH-1:0] dq_r;  // the input data stream is NOT serialized
`endif


// phase-shift dqs_w and dqs_n_w signals by 90 degree with reference to clk_slow before sending to RAM
assign dqs_w = clk90_slow_is_at_high;
assign dqs_n_w = clk90_slow_is_at_low;
assign dq_w = i_user_data;  // the input data stream of 'i_user_data' is NOT serialized


	`ifdef FORMAL

	initial assume(reset);
/*	
	reg reset_extended;
	
	always @(posedge clk)
	begin
		if(reset) reset_extended <= 1;
		
		else reset_extended <= reset;
	end
	
	always @(posedge clk)  // reset extender
	begin
		if(($past(reset) == 1) && (reset_extended) && (!$past(reset_extended))) assume(reset);
	end
*/

	assign dqs = (((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA)) ? dqs_w : 1'b0;  // dqs strobe with 0 value will not sample dq

	assign dqs_r = dqs;  // only for formal modelling of tri-state logic

	assign dqs_n = (((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA)) ? dqs_n_w : 1'b0;  // dqs strobe with 0 value will not sample dq

	assign dqs_n_r = dqs_n;  // only for formal modelling of tri-state logic

	assign dq = (((wait_count > TIME_WL) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA)) ? dq_w : 1'b0;  // dq value of 0 is don't care (needs dqs strobe)

	assign dq_r = dq;  // only for formal modelling of tri-state logic


	// phase-shift the incoming dqs_r and dqs_n_r signals by 90 degree with reference to clk_slow
	// the reason is to sample at the middle of incoming `dq_r` signal
	reg [($clog2(DIVIDE_RATIO_HALVED)-1):0] dqs_counter;

	wire dqs_rising_edge = (dqs_r & ~dqs_n_r);
	wire dqs_falling_edge = (~dqs_r & dqs_n_r);

	always @(posedge clk)
	begin
		if(reset) dqs_counter <= 0;
		
		else begin
			if(dqs_rising_edge | dqs_falling_edge) dqs_counter <= 1;
			
			else if(dqs_counter > 0) 
				dqs_counter <= dqs_counter + 1;
		end
	end

	wire dqs_r_phase_shifted = (dqs_counter == DIVIDE_RATIO_HALVED[0 +: $clog2(DIVIDE_RATIO >> 1)]);
	wire dqs_n_r_phase_shifted = ~dqs_r_phase_shifted;

	always @(posedge clk)
	begin
		if(reset) o_user_data <= 0;

		else if(dqs_r_phase_shifted & ~dqs_n_r_phase_shifted)
		begin
			o_user_data <= dq_r;  // 'dq_r' is sampled at its middle (thanks to 90 degree phase shift on dqs_r)
		end
	end

	reg first_clock_had_passed;
	initial first_clock_had_passed = 0;
	
	always @(posedge clk)
	begin
		if(reset) first_clock_had_passed <= 0;
		
		else first_clock_had_passed <= 1;
	end

	always @(posedge clk)
	begin
		if(first_clock_had_passed)
		begin
			// cover(main_state == STATE_RESET_FINISH);
			// cover(main_state == STATE_INIT_CLOCK_ENABLE);
			// cover(main_state == STATE_INIT_MRS_2);
			// cover(main_state == STATE_INIT_MRS_3);
			// cover(main_state == STATE_ZQ_CALIBRATION);
			// cover(main_state == STATE_READ_DATA);  // to obtain a RAM read transaction waveform
			cover(main_state == STATE_WRITE_DATA);  // to obtain a RAM write transaction waveform
		end
	end

	always @(posedge clk)
	begin
		if(((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA))
		begin
			assert(dqs == dqs_w);
		end
		
		else assert(dqs == dqs_r);
	end

	always @(posedge clk)
	begin
		if(((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA))
		begin
			assert(dqs_n == dqs_n_w);
		end
		
		else assert(dqs_n == dqs_n_r);
	end

	always @(posedge clk)
	begin
		if(((wait_count > TIME_WL) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA))
		begin
			assert(dq == dq_w);
		end
		
		else assert(dq == dq_r);
	end

	`else

	// See https://www.micron.com/-/media/client/global/documents/products/technical-note/dram/tn4605.pdf#page=7
	// for an overview on Preamble and Postamble
	// will use DQS preamble bit to emulate 'oe' input signal as described in the intel documentation
	// See https://www.intel.com/content/www/us/en/programmable/support/support-resources/design-examples/design-software/verilog/ver_bidirec.html
	// inout ports cannot be declared as reg, since they can be used as either input port (as wire) or 
	// output port (as reg or wire)
	// we cannot read and write inout port simultaneously, hence kept highZ for reading.

	// For WRITE, we have to phase-shift DQS by 90 degrees and output the phase-shifted DQS to RAM

	`ifdef USE_x16
		assign udqs = ldqs;  // DQS strobes, this statement just uses all available x16 bandwidth
		assign ldqs
	`else
		assign dqs 
	`endif
				= (((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA)) ? clk90_slow_is_at_high : 1'bz;
								 
	`ifdef USE_x16
		assign udqs_n = ldqs_n;  // DQS strobes, this statement just uses all available x16 bandwidth
		assign ldqs_n
	`else
		assign dqs_n
	`endif
				= (((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
					(main_state == STATE_WRITE_DATA)) ? clk90_slow_is_at_low : 1'bz;
			  

	// phase-shift the incoming dqs and dqs_n signals by 90 degree with reference to clk_slow
	// the reason is to sample at the middle of incoming `dq` signal
`ifndef XILINX
	reg [($clog2(DIVIDE_RATIO_HALVED)-1):0] dqs_counter;
`else
	reg [1:0] dqs_counter;
`endif

	`ifdef USE_x16
		wire dqs_rising_edge = (ldqs & ~ldqs_n) || (udqs & ~udqs_n);
		wire dqs_falling_edge = (~ldqs & ldqs_n) || (udqs & ~udqs_n);
	`else
		wire dqs_rising_edge = (dqs & ~dqs_n);
		wire dqs_falling_edge = (~dqs & dqs_n);
	`endif

	always @(posedge clk)
	begin
		if(reset) dqs_counter <= 0;
		
		else begin
			if(dqs_rising_edge | dqs_falling_edge) dqs_counter <= 1;
			
			else if(dqs_counter > 0) 
				dqs_counter <= dqs_counter + 1;
		end
	end

`ifndef XILINX
	wire dqs_phase_shifted = (dqs_counter == DIVIDE_RATIO_HALVED[0 +: $clog2(DIVIDE_RATIO >> 1)]);
`else
	wire dqs_phase_shifted = (dqs_counter == DIVIDE_RATIO_HALVED[0 +: 2]);
`endif
	wire dqs_n_phase_shifted = ~dqs_phase_shifted;

	always @(posedge clk)
	begin
		if(reset) o_user_data <= 0;

		else if(dqs_phase_shifted & ~dqs_n_phase_shifted)
		begin
			o_user_data <= dq;  // 'dq' is sampled at its middle (thanks to 90 degree phase shift on dqs)
		end
	end

	`endif

`else

	`ifdef LATTICE

	// look for BB primitive in this lattice document :
	// http://www.latticesemi.com/-/media/LatticeSemi/Documents/UserManuals/EI/FPGALibrariesReferenceGuide33.ashx?document_id=50790

	// we cannot have tristate signal inside the logic of an ECP5. tristates only work at the I/O boundary.
	// So, need to split up the read/write signals and have logic to handle these as two separate paths 
	// that meet at the I/O boundary at the BB primitive.

	TRELLIS_IO BB_dqs (
		.B(dqs),
		.I(dqs_w),
		.T(((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA)),
		.O(dqs_r)
	);

	TRELLIS_IO BB_dqs_n (
		.B(dqs_n),
		.I(dqs_n_w),
		.T(((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA)),
		.O(dqs_n_r)
	);

	generate
	genvar dq_index;  // to indicate the bit position of DQ signal

	for(dq_index = 0; dq_index < DQ_BITWIDTH; dq_index = dq_index + 1)
	begin : dq_tristate_io

		TRELLIS_IO BB_dq (
			.B(dq[dq_index]),
			.I(dq_w[dq_index]),
			.T(((wait_count > TIME_WL) && (main_state == STATE_WRITE_AP)) || 
					  (main_state == STATE_WRITE_DATA)),
			.O(dq_r[dq_index])
		);
	end

	endgenerate

	`endif
	
	`ifdef XILINX
	
	// https://www.xilinx.com/support/documentation/sw_manuals/xilinx14_7/spartan6_hdl.pdf#page=126
	
	IOBUF IO_dqs (
		.IO(dqs),
		.I(dqs_w),
		.T(((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA)),
		.O(dqs_r)
	);

	IOBUF IO_dqs_n (
		.IO(dqs_n),
		.I(dqs_n_w),
		.T(((wait_count > TIME_WL-TIME_TWPRE) && (main_state == STATE_WRITE_AP)) || 
				  (main_state == STATE_WRITE_DATA)),
		.O(dqs_n_r)
	);

	generate
	genvar dq_index;  // to indicate the bit position of DQ signal

	for(dq_index = 0; dq_index < DQ_BITWIDTH; dq_index = dq_index + 1)
	begin : dq_tristate_io

		IOBUF IO_dq (
			.IO(dq[dq_index]),
			.I(dq_w[dq_index]),
			.T(((wait_count > TIME_WL) && (main_state == STATE_WRITE_AP)) || 
					  (main_state == STATE_WRITE_DATA)),
			.O(dq_r[dq_index])
		);
	end

	endgenerate
			
	`endif

`endif


// just to avoid https://github.com/YosysHQ/yosys/issues/2718
`ifndef XILINX
	localparam FIXED_POINT_BITWIDTH = $clog2(MAX_TIMING);
`else
	localparam FIXED_POINT_BITWIDTH = 15;
`endif


`ifdef FORMAL

// just to make the cover() spends lesser time to complete
localparam TIME_INITIAL_RESET_ACTIVE = 2;
localparam TIME_INITIAL_CK_INACTIVE = 2;
localparam TIME_TZQINIT = 2;
localparam TIME_WL = 2;
localparam TIME_CWL = 2;
localparam TIME_TBURST = 2;
localparam TIME_TXPR = 2;
localparam TIME_TMRD = 2;
localparam TIME_TMOD = 2;
localparam TIME_TRFC = 2;

`else

`ifndef XILINX
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_INITIAL_RESET_ACTIVE = $ceil(200000/CLK_PERIOD);  // 200μs = 200000ns, After the power is stable, RESET# must be LOW for at least 200µs to begin the initialization process.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_INITIAL_CK_INACTIVE = $ceil(500000/CLK_PERIOD)-1;  // 500μs = 500000ns, After RESET# transitions HIGH, wait 500µs (minus one clock) with CKE LOW.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRFC = $ceil(110/CLK_PERIOD);  // minimum 110ns, Delay between the REFRESH command and the next valid command, except DES
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TXPR = $ceil(120/CLK_PERIOD);  // https://i.imgur.com/SAqPZzT.png, min. (greater of(10ns+tRFC = 120ns, 5 clocks))
`else
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_INITIAL_RESET_ACTIVE = 10000;  // 200μs = 200000ns, After the power is stable, RESET# must be LOW for at least 200µs to begin the initialization process.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_INITIAL_CK_INACTIVE = 24999;  // 500μs = 500000ns, After RESET# transitions HIGH, wait 500µs (minus one clock) with CKE LOW.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRFC = 6;  // minimum 110ns, Delay between the REFRESH command and the next valid command, except DES
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TXPR = 6;  // https://i.imgur.com/SAqPZzT.png, min. (greater of(10ns+tRFC = 120ns, 5 clocks))
`endif

localparam TIME_TZQINIT = 512;  // tZQINIT = 512 clock cycles, ZQCL command calibration time for POWER-UP and RESET operation
localparam TIME_WL = 6;  // Since DLL is disable, only CL=6 is supported.  Since AL=0 for simplicity and RL=AL+CL , WL=6
localparam TIME_CWL = 6;  // Since DLL is disable, only CWL=6 is supported.  Since AL=0 for simplicity and WL=AL+CWL , WL=6
localparam TIME_TBURST = 8;  // each read or write commands will work on 8 different pieces of consecutive data.  In other words, burst length is 8
localparam TIME_TMRD = 4;  // tMRD = 4 clock cycles, Time MRS to MRS command Delay
localparam TIME_TMOD = 12;  // tMOD = 12 clock cycles, Time MRS to non-MRS command Delay

`endif

`ifndef XILINX
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRP = $rtoi($ceil(13.91/CLK_PERIOD));  // minimum 13.91ns, Precharge time. The banks have to be precharged and idle for tRP before a REFRESH command can be applied
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRCD = $rtoi($ceil(13.91/CLK_PERIOD));  // minimum 13.91ns, Time RAS-to-CAS delay, ACT to RD/WR
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TWR = $ceil(15/CLK_PERIOD);  // Minimum 15ns, Write recovery time is the time interval between the end of a write data burst and the start of a precharge command.  It allows sense amplifiers to restore data to cells.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TFAW = $ceil(50/CLK_PERIOD);  // Minimum 50ns, Why Four Activate Window, not Five or Eight Activate Window ?  For limiting high current drain over the period of tFAW time interval
`else
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRP = 1;  // minimum 13.91ns, Precharge time. The banks have to be precharged and idle for tRP before a REFRESH command can be applied
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRCD = 1;  // minimum 13.91ns, Time RAS-to-CAS delay, ACT to RD/WR
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TWR = 1;  // Minimum 15ns, Write recovery time is the time interval between the end of a write data burst and the start of a precharge command.  It allows sense amplifiers to restore data to cells.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TFAW = 3;  // Minimum 50ns, Why Four Activate Window, not Five or Eight Activate Window ?  For limiting high current drain over the period of tFAW time interval
`endif

localparam TIME_TRPRE = 1;  // this is for read pre-amble. It is the time between when the data strobe goes from non-valid (HIGH) to valid (LOW, initial drive level).
localparam TIME_TRPST = 1;  // this is for read post-amble. It is the time from when the last valid data strobe to when the strobe goes to HIGH, non-drive level.
localparam TIME_TWPRE = 1;  // this is for write pre-amble. It is the time between when the data strobe goes from non-valid (HIGH) to valid (LOW, initial drive level).
localparam TIME_TWPST = 1;  // this is for write post-amble. It is the time from when the last valid data strobe to when the strobe goes to HIGH, non-drive level.

localparam ADDRESS_FOR_MODE_REGISTER_0 = 0;
localparam ADDRESS_FOR_MODE_REGISTER_1 = 1;
localparam ADDRESS_FOR_MODE_REGISTER_2 = 2;
localparam ADDRESS_FOR_MODE_REGISTER_3 = 3;

localparam A10 = 10;  // address bit for auto-precharge option
localparam A12 = 12;  // address bit for burst-chop option

// for STATE_IDLE transition into STATE_REFRESH
localparam MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED = 8;  // 9 commands. one executed immediately, 8 more enqueued.
localparam LOW_REFRESH_QUEUE_THRESHOLD = 3;

`ifndef XILINX
reg [$clog2(MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED):0] refresh_Queue;
`else
reg [3:0] refresh_Queue;
`endif

wire low_Priority_Refresh_Request = (refresh_Queue != MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED);
wire high_Priority_Refresh_Request = (refresh_Queue <= LOW_REFRESH_QUEUE_THRESHOLD);

// to propagate 'write_enable' and 'read_enable' signals during STATE_IDLE to STATE_WRITE and STATE_READ
reg write_is_enabled;
reg read_is_enabled;

`ifdef USE_x16
	 assign ldm = (main_state == STATE_WRITE_DATA);
	 assign udm = (main_state == STATE_WRITE_DATA);
`endif


always @(posedge clk)  // will switch to using always @(posedge clk90) in later stage of the project
begin
	if(reset) main_state <= STATE_RESET;

`ifdef HIGH_SPEED
	else if(clk90)  // no need for slower clk90_slow signal in high operating frequency mode
`else
	else if(clk90_slow_posedge)
`endif
	begin
		wait_count <= wait_count + 1;

		// https://i.imgur.com/VUdYasX.png
		// See https://www.systemverilog.io/ddr4-initialization-and-calibration
		case(main_state)
		
			// reset active, wait for 200us, reset inactive, wait for 500us, CKE=1, 
			// then, wait for tXPR = 10ns + tRFC = 10ns + 110ns (tRFC of 1GB memory = 110ns), 
			// Then the MRS commands begin.
			
			STATE_RESET :  // https://i.imgur.com/ePuqhsY.png
			begin
				ck_en <= 0;
			
				if(wait_count > TIME_INITIAL_RESET_ACTIVE-1)
				begin
					reset_n <= 1;  // reset inactive
					main_state <= STATE_RESET_FINISH;
					wait_count <= 0;
				end
				
				else begin
					reset_n <= 0;  // reset active
					main_state <= STATE_RESET;
				end
			end
			
			STATE_RESET_FINISH :
			begin
				// The clock must be present and valid for at least 10ns (and a minimum of five clocks) 
				// and ODT must be driven LOW at least tIS prior to CKE being registered HIGH.
				
				if(wait_count > TIME_INITIAL_CK_INACTIVE-1)
				begin
					ck_en <= 1;  // CK active
					main_state <= STATE_INIT_CLOCK_ENABLE;
					wait_count <= 0;
				end
				
				else begin
					ck_en <= 0;  // CK inactive
					main_state <= STATE_RESET_FINISH;
				end				
			end
			
			STATE_INIT_CLOCK_ENABLE :
			begin
				ck_en <= 1;  // CK active
			
				if(wait_count > TIME_TXPR-1)
				begin
					main_state <= STATE_INIT_MRS_2;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_2;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_INIT_CLOCK_ENABLE;
				end				
			end
			
			STATE_INIT_MRS_2 :
			begin
				ck_en <= 1;
				cs_n <= 0;
				ras_n <= 0;
				cas_n <= 0;
				we_n <= 0;

	            // CWL=5; ASR disabled; SRT=normal; dynamic ODT disabled
	            address <= 0;
	                        			
				if(wait_count > TIME_TMRD-1)
				begin
					main_state <= STATE_INIT_MRS_3;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_3;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_INIT_MRS_2;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_2;
				end		
			end

			STATE_INIT_MRS_3 :
			begin
				ck_en <= 1;
				cs_n <= 0;
				ras_n <= 0;
				cas_n <= 0;
				we_n <= 0;
				
				// MPR disabled
				address <= 0;
				
				if(wait_count > TIME_TMRD-1)
				begin
					main_state <= STATE_INIT_MRS_1;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_1;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_INIT_MRS_3;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_3;
				end		
			end
			
			STATE_INIT_MRS_1 :
			begin
				ck_en <= 1;
				cs_n <= 0;
				ras_n <= 0;
				cas_n <= 0;
				we_n <= 0;

				// disable DLL; 34ohm output driver; no additive latency (AL); write leveling disabled;
	            // termination resistors disabled; TDQS disabled; output enabled
	            // Note: Write leveling : See https://i.imgur.com/mKY1Sra.png
	            // Note: AL can be used somehow to save a few cycles when you ACTIVATE multiple banks
	            //       interleaved, but since this is really high-end optimisation, 
	            //       it is set to value of 0 for now.
	            // 		 See https://blog.csdn.net/xingqingly/article/details/48997879 and
	            //       https://application-notes.digchip.com/024/24-19971.pdf for more context on AL
	            address <= 3;
	                        			
				if(wait_count > TIME_TMRD-1)
				begin
					main_state <= STATE_INIT_MRS_0;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_0;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_INIT_MRS_1;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_1;
				end	
			end

			STATE_INIT_MRS_0 :
			begin
				ck_en <= 1;
				cs_n <= 0;
				ras_n <= 0;
				cas_n <= 0;
				we_n <= 0;	

	            // fixed burst length 8; sequential burst; CL=5; DLL reset yes
	            // write recovery=5; precharge PD: DLL off
	            
	            // write recovery: WR(cycles) = roundup ( tWR (ns)/ tCK (ns) )
	            // tWR sets the number of clock cycles between the completion of a valid write operation and
	            // before an active bank can be precharged
	            
	            // DLL reset: see https://www.issi.com/WW/pdf/EN-I002-Clock%20Consideration_QUAD&DDR2.pdf
	            // when initialising the RAM for the first time, the memory controller's clock outputs are
	            // usually disabled, so the RAM is "running" at 0 Hz (it's not running)
	            // after enabling the clock outputs, the DLL in the RAM needs to "lock" to the clock signal. 
	            // A DLL reset "unlocks" the DLL, so that it can lock again to the current clock speed.
	            // If you enable "DLL reset" in MR0, then you must wait for tDLLK before using any functions 
	            // that require the DLL (read commands or ODT synchronous operations)
	            // The DLL is used to generate DQS.  For read commands, the DRAM drives DQ and DQS pins, and 
	            // uses the DLL to maintain a 90 degrees phase shift between DQ and DQS
	            // tDLLK (512) cycles of clock input are required to lock the DLL.
	            
	            // CL=5 is not supported with the DLL disabled according to the Micron spec.
	            // The Micron spec says something about DQSCK "starting earlier" with the DLL off and 
	            // this seems to mean that we actually have CL=4 when CL=5 is configured.  
	            // See https://i.imgur.com/iuS45ld.png where tDQSCK starts AL + CL - 1 cycles 
	            // after the READ command. 

				address <= 'b0001100010000;
				
				if(wait_count > TIME_TMOD-1)
				begin
					main_state <= STATE_ZQ_CALIBRATION;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_INIT_MRS_0;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_0;
				end				
			end
			
			STATE_ZQ_CALIBRATION :  // https://i.imgur.com/n4VU0MF.png
			begin
				ck_en <= 1;
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 0;	
				address[10] <= 1;
	
				if(wait_count > TIME_TZQINIT-1)
				begin
					main_state <= STATE_IDLE;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_ZQ_CALIBRATION;
				end					
			end
			
			STATE_IDLE :
			begin
				// for simplicity, idle state coding will only transit to STATE_ACTIVATE and STATE_REFRESH
				// will implement state transition to STATE_WRITE_LEVELLING and STATE_SELF_REFRESH later
			
				// Rationale behind the priority encoder logic coding below:
				// We can queue up to 8 REFRESH commands inside the RAM. 
				// If 8 are queued, no more are needed (both request signals are false). 
				// If 4-7 are queued, there's a low-priority request.
				// If 0-3 are queued there's a high priority request. 
				// So READ/WRITE normally go first and refreshes are done while no READ/WRITE are pending, 
				// unless there is a danger that the queue underflows, 
				// in which case it becomes a high-priority request and READ/WRITE have to wait.  
				// So, in summary, it is to overcome the performance penalty due to refresh lockout at the 
				// higher densities
				
				if(refresh_Queue == 0)
					refresh_Queue <= MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED;
				
	            if (high_Priority_Refresh_Request)
	            begin
					// need to do PRECHARGE before REFRESH, see tRP

					ck_en <= 1;
					cs_n <= 0;			
					ras_n <= 0;
					cas_n <= 1;
					we_n <= 0;
					address[10] <= 0;
	                main_state <= STATE_PRECHARGE;
	                
	                wait_count <= 0;
	            end
	            
	            else if (write_enable | read_enable)
	            begin
	            	ck_en <= 1;
	            	cs_n <= 0;
	            	ras_n <= 0;
	            	cas_n <= 1;
	            	we_n <= 1;
	                main_state <= STATE_ACTIVATE;
	                
	                if(write_enable) write_is_enabled <= 1;
	                if(read_enable) read_is_enabled <= 1;
	                
	                wait_count <= 0;
	            end
	            
	            else if (low_Priority_Refresh_Request)
	            begin
					// need to do PRECHARGE before REFRESH, see tRP

					ck_en <= 1;
					cs_n <= 0;			
					ras_n <= 0;
					cas_n <= 1;
					we_n <= 0;
					address[10] <= 0;
	                main_state <= STATE_PRECHARGE;
	                
	                wait_count <= 0;
				end
				
				else main_state <= STATE_IDLE;
				
			end
			
			STATE_ACTIVATE :
			begin
				ck_en <= 1;
				cs_n <= 0;			
				ras_n <= 0;
				cas_n <= 1;
				we_n <= 1;
				
				// need to make sure that 'i_user_data_address' remains unchanged for at least tRRD
				// because according to the definition of tRAS and tRC, it is legal within the same bank, 
				// to issue either ACTIVATE or REFRESH when bank is idle, and PRECHARGE when a row is open
				// So, we have to keep track of what state each bank is in and which row is currently active
				
				// will implement multiple consecutive ACT commands (TIME_RRD) in later stage of project
				// However, tRRD mentioned "Time ACT to ACT, different banks, no PRE between" ?
				
				bank_address <= i_user_data_address[ADDRESS_BITWIDTH +: BANK_ADDRESS_BITWIDTH];
				
				address <= 	// column address
						   	{
						   		i_user_data_address[(A12+1) +: (ADDRESS_BITWIDTH-A12-1)],
						   		
						   		1'b1,  // A12 : no burst-chop
								i_user_data_address[A10+1], 
								1'b1,  // use auto-precharge, but it is don't care in this state
								i_user_data_address[A10-1:0]
							};

				// auto-precharge (AP) is easier for now. In the end it will be manually precharging 
				// (since many read/write commands may use the same row) but for now, simple is better	
						
				if(wait_count > TIME_TRCD-1)
				begin
					if(write_is_enabled)  // write operation has higher priority
					begin
						write_is_enabled <= 0;
						main_state <= STATE_WRITE_AP;
						wait_count <= 0;
					end
						
					else if(read_is_enabled) 
					begin
						read_is_enabled <= 0;
						main_state <= STATE_READ_AP;
						wait_count <= 0;
					end
				end
				
				else begin
					main_state <= STATE_ACTIVATE;
				end				
			end
						
			STATE_WRITE :
			begin
				address[10] <= 0;  // do not use auto-precharge
			end
						
			STATE_WRITE_AP :
			begin
				// https://www.systemverilog.io/understanding-ddr4-timing-parameters#write
				// will implement multiple consecutive WRITE commands (TIME_TCCD) in later stage of project
			
				ck_en <= 1;
				cs_n <= 0;			
				ras_n <= 1;
				cas_n <= 0;
				we_n <= 0;
				
				address <= 	// column address
						   	{
						   		i_user_data_address[(A12+1) +: (ADDRESS_BITWIDTH-A12-1)],
						   		
						   		1'b1,  // A12 : no burst-chop
								i_user_data_address[A10+1], 
								1'b1,  // A10 : use auto-precharge
								i_user_data_address[A10-1:0]
							};
				
				if(wait_count > TIME_CWL-1)
				begin
					main_state <= STATE_WRITE_DATA;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_WRITE_AP;
				end		
			end
			
			STATE_WRITE_DATA :
			begin							
				if(wait_count > (TIME_TBURST + TIME_TWPST)-1)
				begin
					main_state <= STATE_IDLE;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_WRITE_DATA;
				end					
			end
						
			STATE_READ :
			begin
			
			end
					
			STATE_READ_AP :
			begin
				ck_en <= 1;
				cs_n <= 0;			
				ras_n <= 0;
				cas_n <= 0;
				we_n <= 1;
				
				address <= 	// column address
						   	{
						   		i_user_data_address[(A12+1) +: (ADDRESS_BITWIDTH-A12-1)],
						   		
						   		1'b1,  // A12 : no burst-chop
								i_user_data_address[A10+1], 
								1'b1,  // A10 : use auto-precharge
								i_user_data_address[A10-1:0]
							};
				
				if(wait_count > TIME_WL-1)
				begin
					main_state <= STATE_READ_DATA;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_READ_AP;
				end						
			end

			STATE_READ_DATA :
			begin
				// See https://patents.google.com/patent/US7911857B1/en for pre-amble detection circuit
				// For read, we get the unshifted DQS from the RAM and have to phase-shift it ourselves before 
				// using it as a clock strobe signal to sample (or capture) DQ signal
			
				if(wait_count > (TIME_TBURST + TIME_TRPST)-1)
				begin
					main_state <= STATE_IDLE;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_READ_DATA;
				end					
			end
						
			STATE_PRECHARGE :
			begin
				// need to do PRECHARGE before REFRESH, see tRP

				ck_en <= 1;
				cs_n <= 0;			
				ras_n <= 1;
				cas_n <= 0;
				we_n <= 0;
				address[10] <= 0;
				
				if(wait_count > TIME_TRP-1)
				begin
					main_state <= STATE_REFRESH;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_PRECHARGE;
				end				
			end
						
			STATE_REFRESH :
			begin
				// https://www.systemverilog.io/understanding-ddr4-timing-parameters#refresh
				
				// As for why the maximum absolute interval between any REFRESH command and the next REFRESH
				// command is nine times the maximum average interval refresh rate (9x tREFI), we are allowed 
				// to deviate from sending refresh to a DRAM chip by up to 9x the nominal period in a chain of 
				// up to 8 refresh commands that are queued to the chip to ensure the data held doesn't decay.
				// So we can send a spree of refresh commands, then wait some time (9x the nominal period) 
				// then send another spree because that works out to about the nominal period and the refresh
				// scheduler in the DRAM will do the rest
				
				// the max active -> precharge delay (tRAS) is also 9*tREFI, as we need to be precharged to 
				// issue a refresh, so if we leave the precharge command any later, the max refresh constraints 
				// would not be obeyed anymore

				ck_en <= 1;
				cs_n <= 0;
				ras_n <= 0;
				cas_n <= 0;
				we_n <= 1;
				
				if(refresh_Queue > 0)
					refresh_Queue <= refresh_Queue -1;
				
				if(wait_count > TIME_TRFC-1)
				begin
					main_state <= STATE_IDLE;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_REFRESH;
				end
			end
						
			STATE_WRITE_LEVELLING :
			begin
			
			end
			
			default : main_state <= STATE_IDLE;
			
		endcase
	end
end

endmodule
