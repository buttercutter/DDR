// Credit : https://github.com/MartinGeisse/esdk2/blob/master/simsyn/orange-crab/src/mahdl/name/martingeisse/esdk/riscv/orange_crab/ddr3/RamController.mahdl


// Will simulate loopback transaction (write some data into RAM, then read those data back from RAM)
// with the verilog simulation model provided by Micron
// https://www.micron.com/products/dram/ddr3-sdram/part-catalog/mt41j128m16jt-125
// Later, formal verification will proceed with using Micron simulation model


`define MICRON_SIM 1  // micron simulation model

`define USE_x16 1

// `define TDQS 1

//`define RAM_SIZE_1GB
`define RAM_SIZE_2GB
//`define RAM_SIZE_4GB

`ifndef FORMAL
	`ifndef MICRON_SIM
	
		// for internal logic analyzer
		`define USE_ILA 1
		
		// for lattice ECP5 FPGA
		//`define LATTICE 1

		// for Xilinx Spartan-6 FPGA
		`define XILINX 1
		
		`define HIGH_SPEED 1  // Minimum DDR3-1600 operating frequency >= 303MHz
				
	`endif
`endif

`ifndef XILINX
/* verilator lint_off VARHIDDEN */
localparam NUM_OF_DDR_STATES = 20;

// https://www.systemverilog.io/understanding-ddr4-timing-parameters
// TIME_INITIAL_CK_INACTIVE = 152068;
localparam MAX_TIMING = 152068;  // just for initial development stage, will refine the value later
/* verilator lint_on VARHIDDEN */
`endif

// write data to RAM and then read them back from RAM
`define LOOPBACK 1


`ifdef MICRON_SIM
	localparam PERIOD_MARGIN = 10;  // 10ps margin
	localparam MAXIMUM_CK_PERIOD = 3300-PERIOD_MARGIN;  // 3300ps which is defined by Micron simulation model
	localparam PICO_TO_NANO_CONVERSION_FACTOR = 1000;  // 1ns = 1000ps
`endif


// https://www.systemverilog.io/ddr4-basics
module ddr3_memory_controller
#(
	parameter DIVIDE_RATIO = 4,  // master 'clk' signal is divided by 4 for DDR outgoing 'ck' signal, it is for 90 degree phase shift purpose.
	
	`ifdef MICRON_SIM
		// host clock period in ns
		parameter CLK_PERIOD = $itor(MAXIMUM_CK_PERIOD/DIVIDE_RATIO)/$itor(PICO_TO_NANO_CONVERSION_FACTOR),  // clock period of 'clk' = 0.825ns , clock period of 'ck' = 3.3s
	`else
		parameter CLK_PERIOD = 20,  // 20ns
	`endif
	
	parameter CK_PERIOD = (CLK_PERIOD*DIVIDE_RATIO),
	
	// for STATE_IDLE transition into STATE_REFRESH
	// tREFI = 65*tRFC calculated using info from Micron dataheet, so tREFI > 8 * tRFC
	// So it is entirely possible to do all 8 refresh commands inside one tREFI cycle 
	// since each refresh command will take tRFC cycle to finish
	// See also https://www.systemverilog.io/understanding-ddr4-timing-parameters#refresh
	/* verilator lint_off VARHIDDEN */
	parameter MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED = 8,  // 9 commands. one executed immediately, 8 more enqueued.
	/* verilator lint_on VARHIDDEN */
	
	`ifdef USE_x16
		parameter DQS_BITWIDTH = 2,
	
		`ifdef RAM_SIZE_1GB
			parameter ADDRESS_BITWIDTH = 13,
			
		`elsif RAM_SIZE_2GB
			parameter ADDRESS_BITWIDTH = 14,
			
		`elsif RAM_SIZE_4GB
			parameter ADDRESS_BITWIDTH = 15,
		`endif
	`else
		parameter DQS_BITWIDTH = 1,	
		
		`ifdef RAM_SIZE_1GB
			parameter ADDRESS_BITWIDTH = 14,
			
		`elsif RAM_SIZE_2GB
			parameter ADDRESS_BITWIDTH = 15,
			
		`elsif RAM_SIZE_4GB
			parameter ADDRESS_BITWIDTH = 16,
		`endif
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
	input [DQ_BITWIDTH-1:0] data_to_ram,  // data for which the user wants to write to DDR
	output reg [DQ_BITWIDTH-1:0] data_from_ram,  // the requested data from DDR RAM after read operation
	`ifndef XILINX
		input [$clog2(MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED):0] user_desired_extra_read_or_write_cycles,  // for the purpose of postponing refresh commands
	`else
		input [3:0] user_desired_extra_read_or_write_cycles,  // for the purpose of postponing refresh commands
	`endif
	
	`ifndef HIGH_SPEED
		output clk_slow_posedge,  // for dq phase shifting purpose
		output clk180_slow_posedge,  // for dq phase shifting purpose
	`endif
	
	
	// these are to be fed into external DDR3 memory
	output reg [ADDRESS_BITWIDTH-1:0] address,
	output reg [BANK_ADDRESS_BITWIDTH-1:0] bank_address,
	output ck, // CK
	output ck_n, // CK#
	output reg ck_en, // CKE
	output reg cs_n, // chip select signal
	output reg odt, // on-die termination
	output reg ras_n, // RAS#
	output reg cas_n, // CAS#
	output reg we_n, // WE#
	output reg reset_n,
	
	inout [DQ_BITWIDTH-1:0] dq, // Data input/output

`ifdef MICRON_SIM
	output reg [$clog2(NUM_OF_DDR_STATES)-1:0] main_state,
`endif
	
// Xilinx ILA could not probe port IO of IOBUF primitive, but could probe rest of the ports (ports I, O, and T)
`ifdef USE_ILA
	output [DQ_BITWIDTH-1:0] dq_w,  // port I
	output [DQ_BITWIDTH-1:0] dq_r,  // port O

	output low_Priority_Refresh_Request,
	output high_Priority_Refresh_Request,

	// to propagate 'write_enable' and 'read_enable' signals during STATE_IDLE to STATE_WRITE and STATE_READ
	output reg write_is_enabled,
	output reg read_is_enabled,
	
	`ifndef XILINX
	output reg [$clog2(NUM_OF_DDR_STATES)-1:0] main_state,
	output reg [$clog2(MAX_TIMING)-1:0] wait_count,
	output reg [$clog2(MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED):0] refresh_Queue,
	output reg [($clog2(DIVIDE_RATIO_HALVED)-1):0] dqs_counter,
	`else
	output reg [4:0] main_state,
	output reg [14:0] wait_count,
	output reg [3:0] refresh_Queue,
	output reg [1:0] dqs_counter,
	`endif
	
	output dqs_rising_edge,
	output dqs_falling_edge,
`endif

`ifdef USE_x16
	output ldm,  // lower-byte data mask, to be asserted HIGH during data write activities into RAM
	output udm, // upper-byte data mask, to be asserted HIGH during data write activities into RAM
	inout ldqs, // lower byte data strobe
	inout ldqs_n,
	inout udqs, // upper byte data strobe
	inout udqs_n
`else
	inout [DQS_BITWIDTH-1:0] dqs, // Data strobe
	inout [DQS_BITWIDTH-1:0] dqs_n,
	
	// driven to high-Z if TDQS termination function is disabled 
	// according to TN-41-06: DDR3 Termination Data Strobe (TDQS)
	// Please as well look at TN-41-04: DDR3 Dynamic On-Die Termination Operation 
	`ifdef TDQS
	inout [DQS_BITWIDTH-1:0] tdqs, // Termination data strobe, but can act as data-mask (DM) when TDQS function is disabled
	`else
	output [DQS_BITWIDTH-1:0] tdqs,
	`endif
	inout [DQS_BITWIDTH-1:0] tdqs_n
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
localparam RD = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (we_n) & (~A10);
localparam RDS4 = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (we_n) & (~A12) & (~A10);
localparam RDS8 = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (we_n) & (A12) & (~A10);
localparam RDAP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (we_n) & (A10);
localparam RDAPS4 = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (we_n) & (~A12) & (A10);
localparam RDAPS8 = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (~cas_n) & (we_n) & (A12) & (A10);
localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
localparam DES = (previous_clk_en) & (ck_en) & (cs_n);
localparam PDE = (previous_clk_en) & (~ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
localparam PDX = (~previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
localparam ZQCL = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (~we_n) & (A10);
localparam ZQCS = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (~we_n) & (~A10);
*/


`ifndef USE_ILA
	`ifndef MICRON_SIM
		`ifndef XILINX
		reg [$clog2(NUM_OF_DDR_STATES)-1:0] main_state;
		`else
		reg [4:0] main_state;
		`endif
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


// just to avoid https://github.com/YosysHQ/yosys/issues/2718
`ifndef XILINX
	localparam FIXED_POINT_BITWIDTH = $clog2(MAX_TIMING);
`else
	localparam FIXED_POINT_BITWIDTH = 17;
`endif


`ifdef FORMAL

// just to make the cover() spends lesser time to complete
localparam TIME_INITIAL_RESET_ACTIVE = 2;
localparam TIME_INITIAL_CK_INACTIVE = 2;
localparam TIME_TZQINIT = 2;
localparam TIME_RL = 2;
localparam TIME_WL = 2;
localparam TIME_TBURST = 2;
localparam TIME_TXPR = 2;
localparam TIME_TMRD = 2;
localparam TIME_TMOD = 2;
localparam TIME_TRFC = 2;
localparam TIME_TREFI = 2;

`else

`ifndef XILINX
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_INITIAL_RESET_ACTIVE = $ceil(200000/CK_PERIOD);  // 200μs = 200000ns, After the power is stable, RESET# must be LOW for at least 200µs to begin the initialization process.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_INITIAL_CK_INACTIVE = $ceil(500000/CK_PERIOD)-1;  // 500μs = 500000ns, After RESET# transitions HIGH, wait 500µs (minus one clock) with CKE LOW.

`ifdef RAM_SIZE_1GB
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRFC = $ceil(110/CK_PERIOD);  // minimum 110ns, Delay between the REFRESH command and the next valid command, except DES
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TXPR = $ceil((10+110)/CK_PERIOD);  // https://i.imgur.com/SAqPZzT.png, min. (greater of(10ns+tRFC = 120ns, 5 clocks))

`elsif RAM_SIZE_2GB
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRFC = $ceil(160/CK_PERIOD);
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TXPR = $ceil((10+160)/CK_PERIOD);  // https://i.imgur.com/SAqPZzT.png, min. (greater of(10ns+tRFC = 170ns, 5 clocks))

`elsif RAM_SIZE_4GB
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRFC = $ceil(260/CK_PERIOD);
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TXPR = $ceil((10+260)/CK_PERIOD);  // https://i.imgur.com/SAqPZzT.png, min. (greater of(10ns+tRFC = 270ns, 5 clocks))
`endif

localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TREFI = $ceil(7800/CK_PERIOD);  // 7.8μs = 7800ns, Maximum average periodic refresh
`else
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_INITIAL_RESET_ACTIVE = 10000;  // 200μs = 200000ns, After the power is stable, RESET# must be LOW for at least 200µs to begin the initialization process.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_INITIAL_CK_INACTIVE = 24999;  // 500μs = 500000ns, After RESET# transitions HIGH, wait 500µs (minus one clock) with CKE LOW.

`ifdef RAM_SIZE_1GB
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRFC = 6;  // minimum 110ns, Delay between the REFRESH command and the next valid command, except DES
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TXPR = 6;  // https://i.imgur.com/SAqPZzT.png, min. (greater of(10ns+tRFC = 120ns, 5 clocks))

`elsif RAM_SIZE_2GB
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRFC = 8;
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TXPR = 9;  // https://i.imgur.com/SAqPZzT.png, min. (greater of(10ns+tRFC = 170ns, 5 clocks))

`elsif RAM_SIZE_4GB
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRFC = 13;
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TXPR = 14;  // https://i.imgur.com/SAqPZzT.png, min. (greater of(10ns+tRFC = 270ns, 5 clocks))
`endif

localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TREFI = 390;  // 7.8μs = 7800ns, Maximum average periodic refresh
`endif

localparam TIME_TZQINIT = 512;  // tZQINIT = 512 clock cycles, ZQCL command calibration time for POWER-UP and RESET operation
localparam TIME_RL = 5;  // if DLL is disable, only CL=6 is supported.  Since AL=0 for simplicity and RL=AL+CL , RL=5
localparam TIME_WL = 5;  // if DLL is disable, only CWL=6 is supported.  Since AL=0 for simplicity and WL=AL+CWL , WL=5
localparam TIME_TBURST = 4;  // each read or write commands will work on 8 different pieces of consecutive data.  In other words, burst length is 8, and tburst = burst_length/2 with double data rate mechanism
localparam TIME_TMRD = 4;  // tMRD = 4 clock cycles, Time MRS to MRS command Delay
localparam TIME_TMOD = 12;  // tMOD = 12 clock cycles, Time MRS to non-MRS command Delay

`endif

`ifndef XILINX
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRP = $rtoi($ceil(13.91/CK_PERIOD));  // minimum 13.91ns, Precharge time. The banks have to be precharged and idle for tRP before a REFRESH command can be applied
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRCD = $rtoi($ceil(13.91/CK_PERIOD));  // minimum 13.91ns, Time RAS-to-CAS delay, ACT to RD/WR
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TWR = $ceil(15/CK_PERIOD);  // Minimum 15ns, Write recovery time is the time interval between the end of a write data burst and the start of a precharge command.  It allows sense amplifiers to restore data to cells.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TFAW = $ceil(50/CK_PERIOD);  // Minimum 50ns, Why Four Activate Window, not Five or Eight Activate Window ?  For limiting high current drain over the period of tFAW time interval
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TIS = $rtoi($ceil(0.195/CLK_PERIOD));  // Minimum 195ps, setup time
`else
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRP = 1;  // minimum 13.91ns, Precharge time. The banks have to be precharged and idle for tRP before a REFRESH command can be applied
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TRCD = 1;  // minimum 13.91ns, Time RAS-to-CAS delay, ACT to RD/WR
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TWR = 1;  // Minimum 15ns, Write recovery time is the time interval between the end of a write data burst and the start of a precharge command.  It allows sense amplifiers to restore data to cells.
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TFAW = 3;  // Minimum 50ns, Why Four Activate Window, not Five or Eight Activate Window ?  For limiting high current drain over the period of tFAW time interval
localparam [FIXED_POINT_BITWIDTH-1:0] TIME_TIS = 1;  // Minimum 195ps, setup time
`endif

localparam TIME_TDAL = TIME_TWR + TIME_TRP;  // Auto precharge write recovery + precharge time
localparam TIME_TRPRE = 1;  // this is for read pre-amble. It is the time between when the data strobe goes from non-valid (HIGH) to valid (LOW, initial drive level).
localparam TIME_TRPST = 1;  // this is for read post-amble. It is the time from when the last valid data strobe to when the strobe goes to HIGH, non-drive level.
localparam TIME_TWPRE = 1;  // this is for write pre-amble. It is the time between when the data strobe goes from non-valid (HIGH) to valid (LOW, initial drive level).
localparam TIME_TWPST = 1;  // this is for write post-amble. It is the time from when the last valid data strobe to when the strobe goes to HIGH, non-drive level.


localparam ADDRESS_FOR_MODE_REGISTER_0 = 0;
localparam ADDRESS_FOR_MODE_REGISTER_1 = 1;
localparam ADDRESS_FOR_MODE_REGISTER_2 = 2;
localparam ADDRESS_FOR_MODE_REGISTER_3 = 3;


// Mode register 0 (MR0) settings
localparam MR0 = 2'b00;  // Mode register set 0
localparam PRECHARGE_PD = 1'b1;  // DLL on
localparam WRITE_RECOVERY = 3'b001;   // WR = 5
localparam DLL_RESET = 1'b1;
localparam CAS_LATENCY_46 = 3'b001;
localparam CAS_LATENCY_2 = 1'b0;
localparam CAS_LATENCY = {CAS_LATENCY_46, CAS_LATENCY_2};  // CL = 5
localparam READ_BURST_TYPE = 1'b0;  // sequential burst
localparam BURST_LENGTH = 2'b0;  // Fixed BL8
							
// Mode register 1 (MR1) settings
localparam MR1 = 2'b01;  // Mode register set 1
localparam Q_OFF = 1'b0;  // Output enabled
localparam TDQS = 1'b0;  // TDQS disabled (x8 configuration only)
localparam RTT_9 = 1'b0;
localparam RTT_6 = 1'b0;
localparam RTT_2 = 1'b0;
localparam RTT = {RTT_9, RTT_6, RTT_2};  // on-die termination resistance value
localparam WL = 1'b0;  // Write levelling disabled
localparam ODS_5 = 1'b0;
localparam ODS_2 = 1'b1;
localparam ODS = {ODS_5, ODS_2};  // Output drive strength set at 34 ohm
localparam AL = 2'b0;  // Additive latency disabled
localparam DLL_EN = 1'b0;  // DLL is enabled


localparam A10 = 10;  // address bit for auto-precharge option
localparam A12 = 12;  // address bit for burst-chop option

localparam HIGH_REFRESH_QUEUE_THRESHOLD = 4;


`ifndef USE_ILA
	wire [DQ_BITWIDTH-1:0] dq_w;  // the output data stream is NOT serialized
`endif

`ifndef USE_ILA
	wire [DQ_BITWIDTH-1:0] dq_r;  // the input data stream is NOT serialized
`endif

// incoming signals from RAM
`ifdef USE_x16
	wire ldqs_r;
	wire ldqs_n_r;
	wire udqs_r;
	wire udqs_n_r;
`else
	wire dqs_r;
	wire dqs_n_r;
`endif

// outgoing signals to RAM
`ifdef USE_x16
	wire ldqs_w;
	wire ldqs_n_w;
	wire udqs_w;
	wire udqs_n_w;	
`else
	wire dqs_w;
	wire dqs_n_w;
`endif
	
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
		else counter_reset <= (counter == DIVIDE_RATIO_HALVED[0 +: $clog2(DIVIDE_RATIO_HALVED)] - 1'b1);
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
	wire clk90_slow_posedge = (clk_slow && counter_reset);
	assign clk_slow_posedge = (clk_slow && ~counter_reset);
	wire clk_slow_negedge = (~clk_slow && ~counter_reset);
	wire clk180_slow = ~clk_slow;  // simply inversion of the clk_slow signal will give 180 degree phase shift
	assign clk180_slow_posedge = clk_slow_negedge;

	`ifdef USE_x16
		assign ldqs_w = clk_slow;
		assign ldqs_n_w = ~clk_slow;
		assign udqs_w = clk_slow;
		assign udqs_n_w = ~clk_slow;		
	`else
		assign dqs_w = clk_slow;
		assign dqs_n_w = ~clk_slow;
	`endif

`else

	`ifdef XILINX
		  pll instance_name
		   (// Clock in ports
			.clk(clk),      // IN
			// Clock out ports
			.ck(ck),     // OUT
			.ck_90(ck_90),     // OUT, for dq phase shifting purpose
			.ck_180(ck_180),     // OUT
			// Status and control signals
			.reset(reset),// IN
			.locked(locked));      // OUT	
	`endif

`endif

`ifdef USE_x16
	wire [(DQ_BITWIDTH >> 1)-1:0] ldq;
	wire [(DQ_BITWIDTH >> 1)-1:0] udq;
	wire [(DQ_BITWIDTH >> 1)-1:0] ldq_w = data_to_ram[0 +: (DQ_BITWIDTH >> 1)];
	wire [(DQ_BITWIDTH >> 1)-1:0] udq_w = data_to_ram[(DQ_BITWIDTH >> 1) +: (DQ_BITWIDTH >> 1)];
	assign dq_w = {udq_w, ldq_w};
`else
	assign dq_w = data_to_ram;  // input data stream of 'data_to_ram' is NOT serialized
`endif

// See https://www.micron.com/-/media/client/global/documents/products/technical-note/dram/tn4605.pdf#page=7
// for an overview on DQS Preamble and Postamble bits


// For WRITE, we have to phase-shift DQS by 90 degrees and output the phase-shifted DQS to RAM		  

// phase-shifts the incoming dqs and dqs_n signals by 90 degrees
// with reference to outgoing 'ck' DDR signal
// the reason is to sample at the middle of incoming `dq` signal
`ifndef USE_ILA
	`ifndef XILINX
		reg [($clog2(DIVIDE_RATIO_HALVED)-1):0] dqs_counter;
	`else
		reg [1:0] dqs_counter;
	`endif
`endif

`ifndef HIGH_SPEED
reg dqs_is_at_high_previously;
reg dqs_is_at_low_previously;
`endif

`ifndef USE_ILA
	`ifdef USE_x16
		wire dqs_is_at_high = (ldqs_r & ~ldqs_n_r) || (udqs_r & ~udqs_n_r);
		wire dqs_is_at_low = (~ldqs_r & ldqs_n_r) || (~udqs_r & udqs_n_r);
	`else
		wire dqs_is_at_high = (dqs & ~dqs_n);
		wire dqs_is_at_low = (~dqs & dqs_n);
	`endif
	
	wire dqs_rising_edge = (dqs_is_at_low_previously && dqs_is_at_high);
	wire dqs_falling_edge = (dqs_is_at_high_previously && dqs_is_at_low);
`else
	`ifdef USE_x16
		assign dqs_is_at_high = (ldqs_r & ~ldqs_n_r) || (udqs_r & ~udqs_n_r);
		assign dqs_is_at_low = (~ldqs_r & ldqs_n_r) || (~udqs_r & udqs_n_r);
	`else
		assign dqs_is_at_high = (dqs & ~dqs_n);
		assign dqs_is_at_low = (~dqs & dqs_n);
	`endif
	
	assign dqs_rising_edge = (dqs_is_at_low_previously && dqs_is_at_high);
	assign dqs_falling_edge = (dqs_is_at_high_previously && dqs_is_at_low);
`endif


`ifndef HIGH_SPEED

	always @(posedge clk) dqs_is_at_high_previously <= dqs_is_at_high;
	always @(posedge clk) dqs_is_at_low_previously <= dqs_is_at_low;

	always @(posedge clk)
	begin
		if(reset) dqs_counter <= 0;
		
		else begin
			// Due to PCB trace layout and high-speed DDR signal transmission,
			// there is no alignment to any generic clock signal that we can depend upon,
			// especially when data is coming back from the SDRAM chip.
			// Thus, we could only depend upon incoming `DQS` signal to sample 'DQ' signal
			if(dqs_rising_edge | dqs_falling_edge) dqs_counter <= 1;
			
			else if(dqs_counter > 0) 
				dqs_counter <= dqs_counter + 1;
		end
	end

	`ifndef XILINX
	wire dqs_phase_shifted = (dqs_counter == DIVIDE_RATIO_HALVED[0 +: $clog2(DIVIDE_RATIO_HALVED)]);
	`else
	wire dqs_phase_shifted = (dqs_counter == DIVIDE_RATIO_HALVED[0 +: 2]);
	`endif
	wire dqs_n_phase_shifted = ~dqs_phase_shifted;

	always @(posedge clk)
	begin
		if(reset) data_from_ram <= 0;

		// 'dq_r' is sampled at its middle (thanks to 90 degree phase shift on dqs)
		else if(dqs_phase_shifted & ~dqs_n_phase_shifted)
		begin
			`ifdef XILINX
				data_from_ram <= dq_r;
				
			`elsif LATTICE
				data_from_ram <= dq_r;
							
			`else  // Micron DDR3 simulation model
				data_from_ram <= dq;
			`endif		
		end
	end

`else
	`ifdef XILINX
		`ifdef USE_x16
		
			// DDR Data Reception Using Two BUFIO2s
			// See Figure 6 of https://www.xilinx.com/support/documentation/application_notes/xapp1064.pdf#page=5
			
			// why need IOSERDES primitives ?
			// because you want a memory transaction rate much higher than the main clock frequency 
			// and you don't want to require a very high main clock frequency
			
			// send a write of 8w bits to the memory controller, 
			// which is similar to bundling multiple transactions into one wider one,
			// and the memory controller issues 8 writes of w bits to the memory, 
			// where w is the data width of your memory interface. (w == DQ_BITWIDTH)
			// This literally means SERDES_RATIO=8 
			localparam SERDES_RATIO = 8;
			
			wire rxioclkp_ldqs;
			wire rxioclkn_ldqs;
			wire rx_serdesstrobe_ldqs;
			
			wire rxioclkp_udqs;
			wire rxioclkn_udqs;
			wire rx_serdesstrobe_udqs;
			
			wire gclk;
			
			wire [(DQ_BITWIDTH >> 1)-1:0] ldq_n_r = ~ldq;
			wire [(DQ_BITWIDTH >> 1)-1:0] udq_n_r = ~udq;
			
			serdes_1_to_n_clk_ddr_s8_diff #(.D(DQ_BITWIDTH))
			ldqs_serdes
			(
				.clkin_p(ldqs_r),
				.clkin_n(ldqs_n_r),
				.rxioclkp(rxioclkp_ldqs),
				.rxioclkn(rxioclkn_ldqs),
				.rx_serdesstrobe(rx_serdesstrobe_ldqs),
				.rx_bufg_x1(gclk)
			)
			
			serdes_1_to_n_data_ddr_s8_diff #(.D(DQ_BITWIDTH), .S(SERDES_RATIO))
			ldq_serdes
			(
				.use_phase_detector(1'b1),
				.datain_p(ldq),
				.datain_n(ldq_n_r),
				.rxioclkp(rxioclkp_ldqs),
				.rxioclkn(rxioclkn_ldqs),
				.rxserdesstrobe(rx_serdesstrobe_ldqs),
				.reset(reset),
				.gclk(gclk),
				.bitslip(1'b1),
				.debug_in(2'b00),
				.data_out(data_from_ram[0 +: (DQ_BITWIDTH >> 1)]),
				.debug(debug_ldq_serdes)
			)
			
			serdes_1_to_n_clk_ddr_s8_diff #(.D(DQ_BITWIDTH))
			udqs_serdes
			(
				.clkin_p(udqs_r),
				.clkin_n(udqs_n_r),
				.rxioclkp(rxioclkp_udqs),
				.rxioclkn(rxioclkn_udqs),
				.rx_serdesstrobe(rx_serdesstrobe_udqs),
				.rx_bufg_x1(gclk)
			)
			
			serdes_1_to_n_data_ddr_s8_diff #(.D(DQ_BITWIDTH), .S(SERDES_RATIO))
			udq_serdes
			(
				.use_phase_detector(1'b1),
				.datain_p(udq),
				.datain_n(udq_n_r),
				.rxioclkp(rxioclkp_udqs),
				.rxioclkn(rxioclkn_udqs),
				.rxserdesstrobe(rx_serdesstrobe_udqs),
				.reset(reset),
				.gclk(gclk),
				.bitslip(1'b1),
				.debug_in(2'b00),
				.data_out(data_from_ram[(DQ_BITWIDTH >> 1) +: (DQ_BITWIDTH >> 1)]),
				.debug(debug_udq_serdes)
			)		
		`endif
	`endif
`endif


`ifdef LATTICE

// look for BB primitive in this lattice document :
// http://www.latticesemi.com/-/media/LatticeSemi/Documents/UserManuals/EI/FPGALibrariesReferenceGuide33.ashx?document_id=50790

// we cannot have tristate signal inside the logic of an ECP5. tristates only work at the I/O boundary.
// So, need to split up the read/write signals and have logic to handle these as two separate paths 
// that meet at the I/O boundary at the BB primitive.

`ifndef USE_x16

	TRELLIS_IO BB_dqs (
		.B(dqs),
		.I(dqs_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(dqs_r)
	);

	TRELLIS_IO BB_dqs_n (
		.B(dqs_n),
		.I(dqs_n_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(dqs_n_r)
	);

`else  // DQS strobes, the following IOBUF instantiations just use all available x16 bandwidth

	TRELLIS_IO BB_ldqs (
		.B(ldqs),
		.I(ldqs_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(ldqs_r)
	);

	TRELLIS_IO BB_ldqs_n (
		.B(ldqs_n),
		.I(ldqs_n_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(ldqs_n_r)
	);

	TRELLIS_IO BB_udqs (
		.B(udqs),
		.I(udqs_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(udqs_r)
	);

	TRELLIS_IO BB_udqs_n (
		.B(udqs_n),
		.I(udqs_n_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(udqs_n_r)
	);
`endif

generate
genvar dq_index;  // to indicate the bit position of DQ signal

for(dq_index = 0; dq_index < DQ_BITWIDTH; dq_index = dq_index + 1)
begin : dq_tristate_io

	TRELLIS_IO BB_dq (
		.B(dq[dq_index]),
		.I(dq_w[dq_index]),
		.T(((wait_count > TIME_RL) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(dq_r[dq_index])
	);
end

endgenerate

`endif

`ifdef XILINX

// https://www.xilinx.com/support/documentation/sw_manuals/xilinx14_7/spartan6_hdl.pdf#page=126

`ifndef USE_x16

	IOBUF IO_dqs (
		.IO(dqs),
		.I(dqs_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(dqs_r)
	);

	IOBUF IO_dqs_n (
		.IO(dqs_n),
		.I(dqs_n_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(dqs_n_r)
	);

`else  // DQS strobes, the following IOBUF instantiations just use all available x16 bandwidth
	
	IOBUF IO_ldqs (
		.IO(ldqs),
		.I(ldqs_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(ldqs_r)
	);

	IOBUF IO_ldqs_n (
		.IO(ldqs_n),
		.I(ldqs_n_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(ldqs_n_r)
	);

	IOBUF IO_udqs (
		.IO(udqs),
		.I(udqs_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(udqs_r)
	);

	IOBUF IO_udqs_n (
		.IO(udqs_n),
		.I(udqs_n_w),
		.T(((wait_count > TIME_RL-TIME_TRPRE) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(udqs_n_r)
	);

`endif

generate
genvar dq_index;  // to indicate the bit position of DQ signal

for(dq_index = 0; dq_index < DQ_BITWIDTH; dq_index = dq_index + 1)
begin : dq_tristate_io

	IOBUF IO_dq (
		.IO(dq[dq_index]),
		.I(dq_w[dq_index]),
		.T(((wait_count > TIME_RL) && (main_state == STATE_READ_AP)) || 
				  (main_state == STATE_READ_DATA)),
		.O(dq_r[dq_index])
	);
end

endgenerate
		
`endif


`ifdef MICRON_SIM
	`ifndef USE_x16
	
	assign dqs = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
				  (main_state == STATE_WRITE_DATA)) ? 
					dqs_w : {DQS_BITWIDTH{1'bz}};  // dqs value of 1'bz is for input

	// assign dqs_r = dqs;  // only for formal modelling of tri-state logic

	assign dqs_n = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
					(main_state == STATE_WRITE_DATA)) ? 
					dqs_n_w : {DQS_BITWIDTH{1'bz}};  // dqs value of 1'bz is for input

	// assign dqs_n_r = dqs_n;  // only for formal modelling of tri-state logic

	assign dq = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
				 (main_state == STATE_WRITE_DATA)) ? 
					dq_w : {DQ_BITWIDTH{1'bz}};  // dq value of 1'bz is for input

	// assign dq_r = dq;  // only for formal modelling of tri-state logic
	
	`else
	
	assign ldqs = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
				   (main_state == STATE_WRITE_DATA)) ? 
					ldqs_w : {(DQS_BITWIDTH >> 1){1'bz}};  // dqs value of 1'bz is for input

	// assign ldqs_r = ldqs;  // only for formal modelling of tri-state logic

	assign ldqs_n = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
					 (main_state == STATE_WRITE_DATA)) ? 
					ldqs_n_w : {(DQS_BITWIDTH >> 1){1'bz}};  // dqs value of 1'bz is for input

	// assign ldqs_n_r = ldqs_n;  // only for formal modelling of tri-state logic

	assign ldq = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
				  (main_state == STATE_WRITE_DATA)) ? 
					ldq_w : {(DQ_BITWIDTH >> 1){1'bz}};  // dq value of 1'bz is for input

	// assign ldq_r = ldq;  // only for formal modelling of tri-state logic	


	assign udqs = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
				   (main_state == STATE_WRITE_DATA)) ? 
	 				udqs_w : {(DQS_BITWIDTH >> 1){1'bz}};  // dqs value of 1'bz is for input

	// assign udqs_r = udqs;  // only for formal modelling of tri-state logic

	assign udqs_n = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
					 (main_state == STATE_WRITE_DATA)) ? 
					udqs_n_w : {(DQS_BITWIDTH >> 1){1'bz}};  // dqs value of 1'bz is for input

	// assign udqs_n_r = udqs_n;  // only for formal modelling of tri-state logic

	assign udq = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
				  (main_state == STATE_WRITE_DATA)) ? 
	 				udq_w : {(DQ_BITWIDTH >> 1){1'bz}};  // dq value of 1'bz is for input

	// assign udq_r = udq;  // only for formal modelling of tri-state logic
	
	
	assign dq = {udq, ldq};
	assign dqs = {udqs, ldqs};
	assign dqs_n = {udqs_n, ldqs_n};		
	`endif
`endif


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

	assign dqs = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
				  (main_state == STATE_WRITE_DATA)) ? 
					dqs_w : {DQS_BITWIDTH{1'bz}};  // dqs value of 1'bz is for input

	assign dqs_r = dqs;  // only for formal modelling of tri-state logic

	assign dqs_n = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
					(main_state == STATE_WRITE_DATA)) ? 
					dqs_n_w : {DQS_BITWIDTH{1'bz}};  // dqs value of 1'bz is for input

	assign dqs_n_r = dqs_n;  // only for formal modelling of tri-state logic

	assign dq = ((main_state == STATE_WRITE) || (main_state == STATE_WRITE_AP) || 
				 (main_state == STATE_WRITE_DATA)) ? 
					dq_w : {DQ_BITWIDTH{1'bz}};  // dq value of 1'bz is for input

	assign dq_r = dq;  // only for formal modelling of tri-state logic


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
			cover(main_state == STATE_READ_DATA);  // to obtain a RAM read transaction waveform
			cover(main_state == STATE_WRITE_DATA);  // to obtain a RAM write transaction waveform
		end
	end

	always @(posedge clk)
	begin
		if(((wait_count > TIME_WL-TIME_TWPRE) && 
		    ((main_state == STATE_WRITE_AP) || (main_state == STATE_WRITE_AP))) || 
				  (main_state == STATE_WRITE_DATA))
		begin
			assert(dqs == dqs_w);
		end
		
		else assert(dqs == dqs_r);
	end

	always @(posedge clk)
	begin
		if(((wait_count > TIME_WL-TIME_TWPRE) && 
		    ((main_state == STATE_WRITE_AP) || (main_state == STATE_WRITE_AP))) || 
				  (main_state == STATE_WRITE_DATA))
		begin
			assert(dqs_n == dqs_n_w);
		end
		
		else assert(dqs_n == dqs_n_r);
	end

	always @(posedge clk)
	begin
		if(((wait_count > TIME_WL) && 
		    ((main_state == STATE_WRITE_AP) || (main_state == STATE_WRITE_AP))) || 
				  (main_state == STATE_WRITE_DATA))
		begin
			assert(dq == dq_w);
		end
		
		else assert(dq == dq_r);
	end
	
`endif


`ifndef USE_ILA
	`ifndef XILINX
	reg [$clog2(MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED):0] refresh_Queue;
	`else
	reg [3:0] refresh_Queue;
	`endif
`endif


// It is not a must that all 8 postponed REF-commands have to be executed inside a single tREFI
`ifdef USE_ILA
	assign low_Priority_Refresh_Request = (refresh_Queue != MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED);
	assign high_Priority_Refresh_Request = (refresh_Queue >= HIGH_REFRESH_QUEUE_THRESHOLD);
`else
	wire low_Priority_Refresh_Request = (refresh_Queue != MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED);
	wire high_Priority_Refresh_Request = (refresh_Queue >= HIGH_REFRESH_QUEUE_THRESHOLD);
`endif

`ifndef USE_ILA
	// to propagate 'write_enable' and 'read_enable' signals during STATE_IDLE to STATE_WRITE and STATE_READ
	reg write_is_enabled;
	reg read_is_enabled;
`endif

`ifdef USE_x16
	 assign ldm = (main_state != STATE_WRITE_DATA);
	 assign udm = (main_state != STATE_WRITE_DATA);
`endif


`ifndef XILINX
reg [$clog2(MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED*TIME_TREFI)-1:0] postponed_refresh_timing_count;
reg [$clog2(TIME_TREFI)-1:0] refresh_timing_count;
`else
reg [11:0] postponed_refresh_timing_count;
reg [8:0] refresh_timing_count;
`endif

wire extra_read_or_write_cycles_had_passed  // to allow burst read or write operations to proceed first
		= (postponed_refresh_timing_count == 
`ifndef XILINX
				user_desired_extra_read_or_write_cycles*TIME_TREFI[0 +: $clog2(TIME_TREFI)]);  // for verilator warning
`else
				user_desired_extra_read_or_write_cycles*TIME_TREFI[0 +: 9]);
`endif

wire it_is_time_to_do_refresh_now  // tREFI is the "average" interval between REFRESH commands
`ifndef XILINX
		= (refresh_timing_count == TIME_TREFI[0 +: $clog2(TIME_TREFI)]);  // for verilator warning
`else
		= (refresh_timing_count == TIME_TREFI[0 +: 9]);
`endif


// will switch to using always @(posedge clk90_slow) in later stage of project
always @(posedge clk)
begin
	if(reset) 
	begin
		main_state <= STATE_RESET;
		ck_en <= 0;
		cs_n <= 1;			
		ras_n <= 1;
		cas_n <= 1;
		we_n <= 1;
		address <= 0;
		bank_address <= 0;
		wait_count <= 0;
		refresh_Queue <= 0;
		postponed_refresh_timing_count <= 0;
		refresh_timing_count <= 0;
	end

`ifdef HIGH_SPEED
	else
`else
	// DDR signals are 90 degrees phase-shifted in advance
	// with reference to outgoing 'ck' (clk_slow) signal to DDR RAM
	// such that all outgoing DDR signals are sampled in the middle of during posedge(ck)
	// For more info, see the initialization sequence : https://i.imgur.com/JClPQ6G.png
	
	// since clocked always block only updates the new data at the next clock cycle, 
	// clk90_slow_posedge is used instead of clk180_slow_posedge to produce a new data 
	// that is 180 degree phase-shifted, for which the data will be sampled in the middle by 'clk_slow' ('ck')
	// Since DIVIDE_RATIO=4, so in half clock period for 'clk' signal, there are 2 'clk' cycles
	// Therefore, clk90_slow_posedge is 1 'clk' cycle in advance/early with comparison to clk180_slow_posedge
	// The purpose of doing so is to have larger setup and hold timing margin for positive edge of clk_slow,
	// while still obeying DDR3 datasheet specifications
	else if(clk90_slow_posedge)  // generates new data at 180 degrees before positive edge of clk_slow
`endif
	begin
		if(write_enable) write_is_enabled <= 1;
		if(read_enable) read_is_enabled <= 1;
	
		wait_count <= wait_count + 1;

		if(extra_read_or_write_cycles_had_passed) postponed_refresh_timing_count <= 0;
			
		else postponed_refresh_timing_count <= postponed_refresh_timing_count + 1;

		if(it_is_time_to_do_refresh_now) refresh_timing_count <= 0;
			
		else refresh_timing_count <= refresh_timing_count + 1;


		// defaults the command signals high & only pulse low for the 1 clock when need to issue a command.
		cs_n <= 1;			
		ras_n <= 1;
		cas_n <= 1;
		we_n <= 1;
		
						
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
				// ODT must be driven LOW at least tIS prior to CKE being registered HIGH.
				// For tIS, see https://i.imgur.com/kiJI0pY.png or 
				// the section "Command and Address Setup, Hold, and Derating" inside
				// https://media-www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr3/2gb_ddr3_sdram.pdf#page=99
				// as well as the JESD79-3F DDR3 SDRAM Standard which adds further derating which means
				// another 25 ps to account for the earlier reference point
				
				odt <= 0;  // tIs = 195ps (170ps+25ps) , this does not affect anything at low speed testing mode
				
				if(wait_count > TIME_INITIAL_CK_INACTIVE-1)
				begin
					ck_en <= 1;  // CK active
					main_state <= STATE_INIT_CLOCK_ENABLE;
					wait_count <= 0;
				end

				else if(wait_count > TIME_INITIAL_CK_INACTIVE-TIME_TIS-1)  // setup timing of 'ck_en' with respect to 'ck'
				begin
					ck_en <= 1;  // CK active at tIs prior to TIME_INITIAL_CK_INACTIVE
					main_state <= STATE_RESET_FINISH;
					
					// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
					cs_n <= 0;
					ras_n <= 1;
					cas_n <= 1;
					we_n <= 1;				
				end
						
				else begin
					if(ck_en) ck_en <= 1;  // continue to be active after first transition to active logic high
					
					else ck_en <= 0;  // CK inactive
			
					main_state <= STATE_RESET_FINISH;
				end			
			end
			
			STATE_INIT_CLOCK_ENABLE :
			begin
				ck_en <= 1;  // CK active

				// The clock must be present and valid for at least 10ns (and a minimum of five clocks)			
				if(wait_count > TIME_TXPR-1)
				begin
					// prepare necessary parameters for next state
					main_state <= STATE_INIT_MRS_2;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_2;
		            address <= 0;  // CWL=5; ASR disabled; SRT=normal; dynamic ODT disabled					
					
					wait_count <= 0;
					
					// no more NOP command in next 'ck' cycle, transition to MR2 command
					cs_n <= 0;
					ras_n <= 0;
					cas_n <= 0;
					we_n <= 0;					
				end
				
				else begin
					main_state <= STATE_INIT_CLOCK_ENABLE;
				end				
			end
			
			STATE_INIT_MRS_2 :
			begin
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating MRS command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;	

	            // CWL=5; ASR disabled; SRT=normal; dynamic ODT disabled
	            address <= 0;
	                        			
				if(wait_count > TIME_TMRD-1)
				begin
					// prepare necessary parameters for next state				
					main_state <= STATE_INIT_MRS_3;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_3;
					address <= 0;  // MPR disabled					
					
					wait_count <= 0;
					
					// no more NOP command in next 'ck' cycle, transition to MR3 command
					cs_n <= 0;
					ras_n <= 0;
					cas_n <= 0;
					we_n <= 0;						
				end
				
				else begin
					main_state <= STATE_INIT_MRS_2;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_2;
				end		
			end

			STATE_INIT_MRS_3 :
			begin
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating MRS command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;	
				
				// MPR disabled
				address <= 0;
				
				if(wait_count > TIME_TMRD-1)
				begin
					// prepare necessary parameters for next state				
					main_state <= STATE_INIT_MRS_1;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_1;

					`ifdef USE_x16
					
						`ifdef RAM_SIZE_1GB
							address <= {Q_OFF, TDQS, 1'b0, RTT_9, 1'b0, WL, RTT_6, ODS_5, AL, RTT_2, ODS_2, DLL_EN};
							
						`elsif RAM_SIZE_2GB
							address <= {1'b0, Q_OFF, TDQS, 1'b0, RTT_9, 1'b0, WL, RTT_6, ODS_5, AL, RTT_2, ODS_2, DLL_EN};
							
						`elsif RAM_SIZE_4GB
							address <= {2'b0, Q_OFF, TDQS, 1'b0, RTT_9, 1'b0, WL, RTT_6, ODS_5, AL, RTT_2, ODS_2, DLL_EN};
						`endif
					`else
						
						`ifdef RAM_SIZE_1GB
							address <= {1'b0, Q_OFF, TDQS, 1'b0, RTT_9, 1'b0, WL, RTT_6, ODS_5, AL, RTT_2, ODS_2, DLL_EN};
							
						`elsif RAM_SIZE_2GB
							address <= {2'b0, Q_OFF, TDQS, 1'b0, RTT_9, 1'b0, WL, RTT_6, ODS_5, AL, RTT_2, ODS_2, DLL_EN};
							
						`elsif RAM_SIZE_4GB
							address <= {MR1[0], 2'b0, Q_OFF, TDQS, 1'b0, RTT_9, 1'b0, WL, RTT_6, ODS_5, AL, RTT_2, ODS_2, DLL_EN};
						`endif
					`endif
					
					wait_count <= 0;
					
					// no more NOP command in next 'ck' cycle, transition to MR1 command
					cs_n <= 0;
					ras_n <= 0;
					cas_n <= 0;
					we_n <= 0;						
				end
				
				else begin
					main_state <= STATE_INIT_MRS_3;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_3;
				end		
			end
			
			STATE_INIT_MRS_1 :
			begin
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating MRS command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;	

				// enable DLL; 34ohm output driver; no additive latency (AL); write leveling disabled;
	            // termination resistors disabled; TDQS disabled; output enabled
	            // Note: Write leveling : See https://i.imgur.com/mKY1Sra.png
	            // Note: AL can be used somehow to save a few cycles when you ACTIVATE multiple banks
	            //       interleaved, but since this is really high-end optimisation, 
	            //       it is set to value of 0 for now.
	            // 		 See https://blog.csdn.net/xingqingly/article/details/48997879 and
	            //       https://application-notes.digchip.com/024/24-19971.pdf for more context on AL
	            // address <= {1'b0, MR1, 2'b0, Q_OFF, TDQS, 1'b0, RTT_9, 1'b0, WL, RTT_6, ODS_5, AL, RTT_2, ODS_2, DLL_EN};
	                        			
				if(wait_count > TIME_TMRD-1)
				begin
					// prepare necessary parameters for next state				
					main_state <= STATE_INIT_MRS_0;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_0;

					`ifdef USE_x16
					
						`ifdef RAM_SIZE_1GB
							address <= {PRECHARGE_PD, WRITE_RECOVERY, DLL_RESET, 1'b0, CAS_LATENCY_46, 
									READ_BURST_TYPE, CAS_LATENCY_2, BURST_LENGTH};
							
						`elsif RAM_SIZE_2GB
							address <= {1'b0, PRECHARGE_PD, WRITE_RECOVERY, DLL_RESET, 1'b0, CAS_LATENCY_46, 
									READ_BURST_TYPE, CAS_LATENCY_2, BURST_LENGTH};
							
						`elsif RAM_SIZE_4GB
							address <= {2'b0, PRECHARGE_PD, WRITE_RECOVERY, DLL_RESET, 1'b0, CAS_LATENCY_46, 
									READ_BURST_TYPE, CAS_LATENCY_2, BURST_LENGTH};
						`endif
					`else
						
						`ifdef RAM_SIZE_1GB
							address <= {1'b0, PRECHARGE_PD, WRITE_RECOVERY, DLL_RESET, 1'b0, CAS_LATENCY_46, 
									READ_BURST_TYPE, CAS_LATENCY_2, BURST_LENGTH};
							
						`elsif RAM_SIZE_2GB
							address <= {2'b0, PRECHARGE_PD, WRITE_RECOVERY, DLL_RESET, 1'b0, CAS_LATENCY_46, 
									READ_BURST_TYPE, CAS_LATENCY_2, BURST_LENGTH};
							
						`elsif RAM_SIZE_4GB
							address <= {MR0[0], 2'b0, PRECHARGE_PD, WRITE_RECOVERY, DLL_RESET, 1'b0, CAS_LATENCY_46, 
									READ_BURST_TYPE, CAS_LATENCY_2, BURST_LENGTH};
						`endif
					`endif
							
					wait_count <= 0;
					
					// no more NOP command in next 'ck' cycle, transition to MR0 command
					cs_n <= 0;
					ras_n <= 0;
					cas_n <= 0;
					we_n <= 0;						
				end
				
				else begin
					main_state <= STATE_INIT_MRS_1;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_1;
				end	
			end

			STATE_INIT_MRS_0 :
			begin
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating MRS command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;	

	            // fixed burst length 8; sequential burst; CL=5; DLL reset yes
	            // write recovery=5; precharge PD: DLL on
	            
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

				//address <= {1'b0, MR0, 2'b0, PRECHARGE_PD, WRITE_RECOVERY, DLL_RESET, 1'b0, CAS_LATENCY_46, 
				//			READ_BURST_TYPE, CAS_LATENCY_2, BURST_LENGTH};
				
				if(wait_count > TIME_TMOD-1)
				begin
					main_state <= STATE_ZQ_CALIBRATION;
					wait_count <= 0;
					
					// no more NOP command in next 'ck' cycle, transition to ZQCL command
					cs_n <= 0;
					ras_n <= 1;
					cas_n <= 1;
					we_n <= 0;	
					address[A10] <= 1;					
				end
				
				else begin
					main_state <= STATE_INIT_MRS_0;
					bank_address <= ADDRESS_FOR_MODE_REGISTER_0;
				end				
			end
			
			STATE_ZQ_CALIBRATION :  // https://i.imgur.com/n4VU0MF.png
			begin
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating ZQCL command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;	
	
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
				// We can queue (or postpone) up to maximum 8 REFRESH commands inside the RAM. 
				// If 8 are queued, there's a high priority request. 
				// If 4-7 are queued, there's a low-priority request.
				// If 0-3 are queued, no more are needed (both request signals are false).
				// So READ/WRITE normally go first and refreshes are done while no READ/WRITE are pending, 
				// unless there is a danger that the queue underflows, 
				// in which case it becomes a high-priority request and READ/WRITE have to wait.  
				// So, in summary, it is to overcome the performance penalty due to refresh lockout at the 
				// higher densities
				
				if((refresh_Queue == 0) && 
				   (user_desired_extra_read_or_write_cycles <= MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED))
				begin
					refresh_Queue <= user_desired_extra_read_or_write_cycles;
				end	
				
	            if ((extra_read_or_write_cycles_had_passed & high_Priority_Refresh_Request) ||
	            	((user_desired_extra_read_or_write_cycles == 0) & it_is_time_to_do_refresh_now))
	            begin
					// need to do PRECHARGE before REFRESH, see tRP

					ck_en <= 1;
					cs_n <= 0;			
					ras_n <= 0;
					cas_n <= 1;
					we_n <= 0;
					address[A10] <= 0;
	                main_state <= STATE_PRECHARGE;
	                
	                wait_count <= 0;
	            end
	            
	            else if (write_is_enabled | read_is_enabled)
	            begin
	            	ck_en <= 1;
	            	cs_n <= 0;
	            	ras_n <= 0;
	            	cas_n <= 1;
	            	we_n <= 1;
	                main_state <= STATE_ACTIVATE;
	                
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
					address[A10] <= 0;
	                main_state <= STATE_PRECHARGE;
	                
	                wait_count <= 0;
				end
				
				else main_state <= STATE_IDLE;
				
			end
			
			STATE_ACTIVATE :
			begin
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating ACT command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
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
						// no more NOP command in next 'ck' cycle, transition to WRAP command
						ck_en <= 1;
						cs_n <= 0;			
						ras_n <= 1;
						cas_n <= 0;
						we_n <= 0;
						
						`ifdef LOOPBACK
							// for data loopback, auto-precharge will close the bank, 
							// which means read operation could not proceeed without reopening the bank
							address[A10] <= 0;
							main_state <= STATE_WRITE;
						`else
							address[A10] <= 1;
							main_state <= STATE_WRITE_AP;
						`endif
						
						wait_count <= 0;
					end
						
					else if(read_is_enabled) 
					begin
						// no more NOP command in next 'ck' cycle, transition to RDAP command
						ck_en <= 1;
						cs_n <= 0;			
						ras_n <= 1;
						cas_n <= 0;
						we_n <= 1;
						address[A10] <= 1;
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
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating ACT command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;
				
				address <= 	// column address
						   	{
						   		i_user_data_address[(A12+1) +: (ADDRESS_BITWIDTH-A12-1)],
						   		
						   		1'b1,  // A12 : no burst-chop
								i_user_data_address[A10+1], 
								1'b1,  // A10 : use auto-precharge
								i_user_data_address[A10-1:0]
							};
				
				if(wait_count > (TIME_WL-TIME_TWPRE)-1)
				begin
					main_state <= STATE_WRITE_DATA;
					wait_count <= 0;
				end
				
				else begin
					main_state <= STATE_WRITE;
				end							
			end
						
			STATE_WRITE_AP :
			begin
				// https://www.systemverilog.io/understanding-ddr4-timing-parameters#write
				// will implement multiple consecutive WRITE commands (TIME_TCCD) in later stage of project
			
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating ACT command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;	
								
				address <= 	// column address
						   	{
						   		i_user_data_address[(A12+1) +: (ADDRESS_BITWIDTH-A12-1)],
						   		
						   		1'b1,  // A12 : no burst-chop
								i_user_data_address[A10+1], 
								1'b1,  // A10 : use auto-precharge
								i_user_data_address[A10-1:0]
							};
				
				if(wait_count > (TIME_WL-TIME_TWPRE)-1)
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
				ck_en <= 1;

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating ACT command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;				
							
				if(wait_count > (TIME_TBURST+TIME_TDAL)-1)
				begin
					`ifdef LOOPBACK
						// no more NOP command in next 'ck' cycle, transition to RDAP command
						ck_en <= 1;
						cs_n <= 0;			
						ras_n <= 1;
						cas_n <= 0;
						we_n <= 1;
						address[A10] <= 1;
						main_state <= STATE_READ_AP;
						wait_count <= 0;					
					`else
						main_state <= STATE_IDLE;
						wait_count <= 0;
					`endif
				end

				else if(wait_count > TIME_TBURST-1)
				begin
					main_state <= STATE_WRITE_DATA;
					write_is_enabled <= 0;
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

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating ACT command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;	
				
				address <= 	// column address
						   	{
						   		i_user_data_address[(A12+1) +: (ADDRESS_BITWIDTH-A12-1)],
						   		
						   		1'b1,  // A12 : no burst-chop
								i_user_data_address[A10+1], 
								1'b1,  // A10 : use auto-precharge
								i_user_data_address[A10-1:0]
							};
				
				if(wait_count > TIME_RL-1)
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

				else if(wait_count > TIME_TBURST-1)
				begin
					main_state <= STATE_READ_DATA;
					read_is_enabled <= 0;
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
				address[A10] <= 0;
				
				if(wait_count > TIME_TRP-1)
				begin
					main_state <= STATE_REFRESH;
					wait_count <= 0;
					
					// no more NOP command in next 'ck' cycle, transition to REF command
					ck_en <= 1;
					cs_n <= 0;
					ras_n <= 0;
					cas_n <= 0;
					we_n <= 1;					
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

				// localparam NOP = (previous_clk_en) & (ck_en) & (~cs_n) & (ras_n) & (cas_n) & (we_n);
				// only a single, non-repeating ACT command is executed, and followed by NOP commands
				cs_n <= 0;
				ras_n <= 1;
				cas_n <= 1;
				we_n <= 1;	

				if(refresh_Queue > 0)
					refresh_Queue <= refresh_Queue - 1;  // a countdown trigger for precharge/refresh operation
				
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
