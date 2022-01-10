`define HIGH_SPEED 1  // Minimum DDR3-1600 operating frequency >= 303MHz
`define MICRON_SIM 1  // micron simulation model
`define TESTBENCH 1  // for both micron simulation model and Xilinx ISIM simulator
`define VIVADO 1  // for 7-series and above

`define USE_x16 1
`define USE_SERDES 1

// `define TDQS 1

//`define RAM_SIZE_1GB
`define RAM_SIZE_2GB
//`define RAM_SIZE_4GB

`ifndef FORMAL
	`ifdef HIGH_SPEED
		
		// for internal logic analyzer
		//`define USE_ILA 1
		
		// for lattice ECP5 FPGA
		//`define LATTICE 1

		// for Xilinx Spartan-6 FPGA
		`define XILINX 1

		// for Altera MAX-10 FPGA
		//`define ALTERA 1
				
	`endif
`endif

`ifdef MICRON_SIM
// follows Micron simulation model
`timescale 1ps / 1ps  // time-unit = 1 ps, precision = 1 ps
`endif

// write data to RAM and then read them back from RAM
`define LOOPBACK 1
`ifdef LOOPBACK
	`ifndef FORMAL
		`ifndef MICRON_SIM	
			// data loopback requires ILA capability to check data integrity
			//`define USE_ILA 1
		`endif
	`endif
`endif


module test_ddr3_memory_controller
#(
	parameter NUM_OF_WRITE_DATA = 32,  // 32 pieces of data are to be written to DRAM
	parameter NUM_OF_READ_DATA = 32,  // 32 pieces of data are to be read from DRAM
	parameter DATA_BURST_LENGTH = 8,  // eight data transfers per burst activity, please modify MR0 setting if none other than BL8

	`ifdef USE_SERDES
		// why 8 ? because of FPGA development board is using external 50 MHz crystal
		// and the minimum operating frequency for Micron DDR3 memory is 303MHz
		parameter SERDES_RATIO = 8,
	`endif

	parameter PICO_TO_NANO_CONVERSION_FACTOR = 1000,  // 1ns = 1000ps

	`ifndef HIGH_SPEED
		parameter PERIOD_MARGIN = 10,  // 10ps margin
		parameter MAXIMUM_CK_PERIOD = 3300-PERIOD_MARGIN,  // 3300ps which is defined by Micron simulation model	
		parameter DIVIDE_RATIO = 4,  // master 'clk' signal is divided by 4 for DDR outgoing 'ck' signal, it is for 90 degree phase shift purpose.
		
		// host clock period in ns
		// clock period of 'clk' = 0.8225ns , clock period of 'ck' = 3.3ns
		parameter CLK_PERIOD = $itor(MAXIMUM_CK_PERIOD/DIVIDE_RATIO)/$itor(PICO_TO_NANO_CONVERSION_FACTOR),
	`else
		parameter CLK_PERIOD = 20,  // 20ns, 50MHz
		parameter CLK_PLL_PERIOD = 12,  // 12ns, 83.333MHz
	`endif
		
	`ifdef TESTBENCH		
		`ifndef MICRON_SIM
			parameter PERIOD_MARGIN = 10,  // 10ps margin
			parameter MAXIMUM_CK_PERIOD = 3300-PERIOD_MARGIN,  // 3300ps which is defined by Micron simulation model		
			parameter DIVIDE_RATIO = 4,  // master 'clk' signal is divided by 4 for DDR outgoing 'ck' signal, it is for 90 degree phase shift purpose.		
		`endif
	`endif

	`ifdef HIGH_SPEED
		parameter CK_PERIOD = 3,  // 333.333MHz from PLL, 1/333.333MHz = 3ns
	`else
		parameter CK_PERIOD = (CLK_PERIOD*DIVIDE_RATIO),
	`endif

	`ifdef USE_x16
		parameter DM_BITWIDTH = 2,
		parameter DQS_BITWIDTH = 2,
	
		`ifdef RAM_SIZE_1GB
			parameter ADDRESS_BITWIDTH = 13,
			
		`elsif RAM_SIZE_2GB
			parameter ADDRESS_BITWIDTH = 14,
			
		`elsif RAM_SIZE_4GB
			parameter ADDRESS_BITWIDTH = 15,
		`endif
	`else
		parameter DM_BITWIDTH = 1,
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
`ifndef MICRON_SIM	
	// these are FPGA internal signals
	input clk,
	input resetn,  // negation polarity due to pull-down tact switch
	output done,  // finished DDR write and read operations in loopback mechaism
	output led_test,  // just to test whether bitstream works or not

	// these are to be fed into external DDR3 memory
	output [ADDRESS_BITWIDTH-1:0] address,
	output [BANK_ADDRESS_BITWIDTH-1:0] bank_address,
	output ck, // CK
	output ck_n, // CK#
	output ck_en, // CKE
	output cs_n, // chip select signal
	output odt, // on-die termination
	output ras_n, // RAS#
	output cas_n, // CAS#
	output we_n, // WE#
	output reset_n,
	
	inout [DQ_BITWIDTH-1:0] dq, // Data input/output
	
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
`endif
);


`ifdef HIGH_SPEED
// for clk_serdes clock domain
wire clk_serdes;  // 83.333MHz with 45 phase shift
wire ck_180;  // 333.333MHz with 180 phase shift
wire locked_previous;
wire need_to_assert_reset;
`endif


/* verilator lint_off VARHIDDEN */
localparam NUM_OF_DDR_STATES = 23;

// TIME_TZQINIT = 512
// See also 'COUNTER_INCREMENT_VALUE' on why some of the large timing variables are not used in this case
localparam MAX_WAIT_COUNT = 512;
/* verilator lint_on VARHIDDEN */

// https://www.systemverilog.io/understanding-ddr4-timing-parameters
// TIME_INITIAL_CK_INACTIVE
localparam MAX_TIMING = (500000/CLK_PLL_PERIOD);  // just for initial development stage, will refine the value later

localparam STATE_WAIT_AFTER_MPR = 20;
localparam STATE_IDLE = 24;
localparam STATE_ACTIVATE = 5;
localparam STATE_WRITE = 6;
localparam STATE_WRITE_AP = 7;
localparam STATE_WRITE_DATA = 8;
localparam STATE_READ_DATA = 3;  // smaller value to solve setup timing issue due to lesser comparison hardware

wire [$clog2(NUM_OF_DDR_STATES)-1:0] main_state_clk_serdes;
reg [$clog2(NUM_OF_DDR_STATES)-1:0] previous_main_state_clk_serdes;

always @(posedge clk_serdes) previous_main_state_clk_serdes <= main_state_clk_serdes;


wire [$clog2(MAX_WAIT_COUNT):0] wait_count_clk_serdes;


// for STATE_IDLE transition into STATE_REFRESH
parameter MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED = 8;  // 9 commands. one executed immediately, 8 more enqueued.

`ifndef MICRON_SIM
	assign led_test = resetn;  // because of light LED polarity, '1' will turn off LED, '0' will turn on LED
`else

	wire done;  // finished DDR write and read operations in loopback mechaism

	// these are to be fed into external DDR3 memory
	wire [ADDRESS_BITWIDTH-1:0] address;
	wire [BANK_ADDRESS_BITWIDTH-1:0] bank_address;
	wire ck; // CK
	wire ck_n; // CK#
	wire ck_en; // CKE
	wire cs_n; // chip select signal
	wire odt; // on-die termination
	wire ras_n; // RAS#
	wire cas_n; // CAS#
	wire we_n; // WE#
	wire reset_n;

	wire [DQ_BITWIDTH-1:0] dq; // Data input/output

	`ifdef USE_x16
		wire ldm;  // lower-byte data mask, to be asserted HIGH during data write activities into RAM
		wire udm; // upper-byte data mask, to be asserted HIGH during data write activities into RAM
		wire [(DQS_BITWIDTH >> 1)-1:0] ldqs; // lower byte data strobe
		wire [(DQS_BITWIDTH >> 1)-1:0] ldqs_n;
		wire [(DQS_BITWIDTH >> 1)-1:0] udqs; // upper byte data strobe
		wire [(DQS_BITWIDTH >> 1)-1:0] udqs_n;
		
		wire [DM_BITWIDTH-1:0]  dm = {udm, ldm};
		// wire [DQS_BITWIDTH-1:0] dqs = {udqs, ldqs};
		// wire [DQS_BITWIDTH-1:0] dqs_n = {udqs_n, ldqs_n};
	`else
		wire [DQS_BITWIDTH-1:0] dqs; // Data strobe
		wire [DQS_BITWIDTH-1:0] dqs_n;
		
		// driven to high-Z if TDQS termination function is disabled 
		// according to TN-41-06: DDR3 Termination Data Strobe (TDQS)
		// Please as well look at TN-41-04: DDR3 Dynamic On-Die Termination Operation 
		`ifdef TDQS
		wire [DQS_BITWIDTH-1:0] tdqs; // Termination data strobe, but can act as data-mask (DM) when TDQS function is disabled
		`else
		wire [DQS_BITWIDTH-1:0] tdqs;
		`endif
		wire [DQS_BITWIDTH-1:0] tdqs_n;
	`endif

`endif

`ifdef TESTBENCH
	// Micron simulation model is using `timescale 1ps / 1ps
	// duration for each bit = 1 * timescale = 1 * 1ps  = 1ps
	// but the following coding is also for Xilinx ISIM simulator

	// reset for at least 3 CLKIN clock cycles (requirement by Xilinx PLL IP core)
	localparam RESET_TIMING = 3 * CLK_PERIOD;
	localparam STOP_TIMING =  900_000;  // 900us = 900_000ns

	// clock and reset signals generation for simulation testbench
	reg clk_sim;
	reg resetn_sim;

	initial begin
		$dumpfile("ddr3.vcd");
		$dumpvars(0, test_ddr3_memory_controller);
		
		clk_sim <= 1'b0;
		resetn_sim <= 1'b1;
		@(posedge clk_sim);

		resetn_sim <= 1'b0;  // asserts master reset signal

		repeat((RESET_TIMING/CLK_PERIOD)+1) @(posedge clk_sim);  // +1 because of division usually uses floor()
		
		resetn_sim <= 1'b1;  // releases master reset signal
		
		repeat(STOP_TIMING/CLK_PERIOD) @(posedge clk_sim);  // minimum runtime
		
		$stop;
	end

	// note that sensitive list is omitted in always block
	// therefore always-block run forever
	// clock period = 20ns , frequency = 50MHz
	always #((CLK_PERIOD*PICO_TO_NANO_CONVERSION_FACTOR)/2) clk_sim = ~clk_sim;  // clock edge transition every half clock cycle period

	wire reset = ~resetn_sim;  // just for convenience of verilog syntax
`else
	wire reset = ~resetn;  // just for convenience of verilog syntax
`endif


wire [$clog2(MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED):0] user_desired_extra_read_or_write_cycles;  // for the purpose of postponing refresh commands

assign user_desired_extra_read_or_write_cycles = MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED;


// phase-shift dq_w, dq_n_w signals by 90 degree with reference to clk_slow ('ck') before sending to RAM
// such that dq signals are sampled right at its middle by dqs signals
// the purpose is for dq signal integrity at high speed PCB trace
`ifndef HIGH_SPEED
wire clk_slow_posedge;  // for dq phase shifting purpose
wire clk180_slow_posedge;  // for dq phase shifting purpose
`endif

`ifdef TESTBENCH
wire ck_90;  // for dq phase shifting purpose
wire ck_270;

wire [DQ_BITWIDTH-1:0] dq_iobuf_enable;
wire udqs_iobuf_enable;
wire ldqs_iobuf_enable;

wire data_read_is_ongoing;
`endif


reg [BANK_ADDRESS_BITWIDTH+ADDRESS_BITWIDTH-1:0] i_user_data_address;  // the DDR memory address for which the user wants to write/read the data

`ifdef USE_SERDES
	reg [DQ_BITWIDTH*SERDES_RATIO-1:0] data_to_ram;  // data for which the user wants to write/read to/from DDR
	wire [DQ_BITWIDTH*SERDES_RATIO-1:0] data_from_ram;  // the requested data from DDR RAM after read operation
`else 
	// TWO pieces of data bundled together due to double-data-rate requirement of DQ signal
	reg  [(DQ_BITWIDTH << 1)-1:0] data_to_ram;  // data to be written to DDR RAM
	wire [(DQ_BITWIDTH << 1)-1:0] data_from_ram;  // the requested data being read from DDR RAM
`endif

reg write_enable, read_enable;
reg done_writing, done_reading;
	
`ifdef LOOPBACK

	reg [DQ_BITWIDTH-1:0] test_data;

	assign done = (done_writing & done_reading);  // finish a data loopback transaction

	localparam STARTING_VALUE_OF_TEST_DATA = 5;  // starts from 5

	`ifdef USE_SERDES
	genvar data_write_index;
	generate
		for(data_write_index = 0; data_write_index < SERDES_RATIO;
			data_write_index = data_write_index + 1)
		begin: data_write_loop
	`endif
		`ifdef HIGH_SPEED
			`ifdef USE_SERDES
				always @(posedge clk_serdes)
			`else
				always @(posedge ck_180)  // positive edge of ck_180 is right after WRITE operation starts
			`endif
		`else
			`ifdef TESTBENCH			
				always @(posedge clk_sim)
			`else
				always @(posedge clk)
			`endif
		`endif
			begin
				if(reset)
				begin
					`ifdef USE_SERDES
						data_to_ram[DQ_BITWIDTH*data_write_index +: DQ_BITWIDTH] <= 0;
					`else
						data_to_ram <= 0;
					`endif
				end
				
				else if(
				`ifndef HIGH_SPEED
					// Since this is always block which updates new data in next clock cycle,
					// and DIVIDE_RATIO=4 which means there are 2 'clk' cycles in each half period of a 'clk_slow' cycle,
					// the following immediate single line of code will update new data 
					// both at 90 degrees before and after positive edge of 'ck'
					(clk180_slow_posedge | clk_slow_posedge) &&
				`endif
					(~done_writing) &&
                    // write operation has higher priority in loopback mechanism
                    (((previous_main_state_clk_serdes == STATE_WAIT_AFTER_MPR) && (main_state_clk_serdes == STATE_IDLE)) ||
                     (main_state_clk_serdes == STATE_ACTIVATE) ||
					`ifdef LOOPBACK
					 	(main_state_clk_serdes == STATE_WRITE) ||
					`else
						(main_state_clk_serdes == STATE_WRITE_AP) ||
					`endif
					 (main_state_clk_serdes == STATE_WRITE_DATA)))  // starts preparing for DRAM write operation
				begin					
					`ifdef USE_SERDES							
						`ifdef USE_x16
							data_to_ram[DQ_BITWIDTH*data_write_index +: DQ_BITWIDTH] <= 
										{test_data + data_write_index + 1, test_data + data_write_index};
						`else
							data_to_ram[DQ_BITWIDTH*data_write_index +: DQ_BITWIDTH] <= 
										test_data + data_write_index;
						`endif											
					`else
						`ifdef USE_x16
							data_to_ram <= {test_data+1, test_data};
						`else
							data_to_ram <= test_data;
						`endif
					`endif
				end
				
				else if((done_writing) && (main_state_clk_serdes == STATE_READ_DATA)) begin  // read operation

				end
			end
			
	`ifdef USE_SERDES
		end
	endgenerate		
	`endif


	// such that DQ output signal will have unique value every DQS cycle
	// this is due to double-data-rate nature of DQ
	localparam UNIQUE_DQ_OUTPUT = 2;
	
	`ifdef HIGH_SPEED
		`ifdef USE_SERDES
			always @(posedge clk_serdes)
		`else
			always @(posedge ck_180)  // positive edge of ck_180 is right after WRITE operation starts
		`endif
	`else
		`ifdef TESTBENCH			
			always @(posedge clk_sim)
		`else
			always @(posedge clk)
		`endif
	`endif
	begin
		if(reset)
		begin
			i_user_data_address <= 0;
			test_data <= STARTING_VALUE_OF_TEST_DATA;

			write_enable <= 1;  // writes data first
			read_enable <= 0;
			done_writing <= 0;
			done_reading <= 0;
		end
		
		else if(
		`ifndef HIGH_SPEED
			// Since this is always block which updates new data in next clock cycle,
			// and DIVIDE_RATIO=4 which means there are 2 'clk' cycles in each half period of a 'clk_slow' cycle,
			// the following immediate single line of code will update new data 
			// both at 90 degrees before and after positive edge of 'ck'
			(clk180_slow_posedge | clk_slow_posedge) &&
		`endif
			(~done_writing) &&
			// write operation has higher priority in loopback mechanism
			(((previous_main_state_clk_serdes == STATE_WAIT_AFTER_MPR) && (main_state_clk_serdes == STATE_IDLE)) ||
			 (main_state_clk_serdes == STATE_ACTIVATE) ||
			`ifdef LOOPBACK
			 	(main_state_clk_serdes == STATE_WRITE) ||
			`else
				(main_state_clk_serdes == STATE_WRITE_AP) ||
			`endif
			 (main_state_clk_serdes == STATE_WRITE_DATA)))  // starts preparing for DRAM write operation
		begin
			i_user_data_address <= i_user_data_address + 1;
			
			`ifdef USE_SERDES
				test_data <= test_data + SERDES_RATIO;
			`else
				test_data <= test_data + UNIQUE_DQ_OUTPUT;
			`endif
			
			write_enable <= (test_data < (STARTING_VALUE_OF_TEST_DATA+NUM_OF_WRITE_DATA-DATA_BURST_LENGTH));  // writes up to 'NUM_OF_WRITE_DATA' pieces of data
			read_enable <= (test_data >= (STARTING_VALUE_OF_TEST_DATA+NUM_OF_WRITE_DATA-DATA_BURST_LENGTH));  // starts the readback operation
			done_writing <= (test_data >= (STARTING_VALUE_OF_TEST_DATA+NUM_OF_WRITE_DATA-DATA_BURST_LENGTH));  // stops writing since readback operation starts
			done_reading <= 0;
			
			if(test_data >= (STARTING_VALUE_OF_TEST_DATA+NUM_OF_WRITE_DATA-1))  // finished writing data
			begin
				i_user_data_address <= 0;  // read from the first piece of data written
				read_enable <= 1;  // prepare to read data
			end
		end
		
		else if((done_writing) && (main_state_clk_serdes == STATE_READ_DATA))  // read operation
		begin
			i_user_data_address <= i_user_data_address + 1;
			
			//test_data <= 0;  // not related to DDR read operation, only for DDR write operation
			write_enable <= 0;
			
			if(done) read_enable <= 0;  // already finished reading all data
			
			else read_enable <= 1;
			
			done_writing <= done_writing;
			
			if(data_from_ram[0 +: DQ_BITWIDTH] >=
			  	 (STARTING_VALUE_OF_TEST_DATA+NUM_OF_READ_DATA-1))		
			begin
				done_reading <= 1;
			end
		end
	end
	
`endif


`ifdef USE_ILA

	wire [DQ_BITWIDTH-1:0] dq_r;  // port O of IOBUF primitive
	wire [DQ_BITWIDTH-1:0] dq_w;  // port I of IOBUF primitive

	wire low_Priority_Refresh_Request;
	wire high_Priority_Refresh_Request;

	// to propagate 'write_enable' and 'read_enable' signals during STATE_IDLE to STATE_WRITE and STATE_READ
	wire write_is_enabled;
	wire read_is_enabled;
	
	wire dqs_rising_edge;
	wire dqs_falling_edge;

    wire [$clog2(MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED):0] refresh_Queue;
    wire [($clog2(DIVIDE_RATIO_HALVED)-1):0] dqs_counter;
		
	`ifdef XILINX
	
		// Added to solve https://forums.xilinx.com/t5/Vivado-Debug-and-Power/Chipscope-ILA-Please-ensure-that-all-the-pins-used-in-the/m-p/1237451
		wire [35:0] CONTROL0;
		wire [35:0] CONTROL1;
		wire [35:0] CONTROL2;
		wire [35:0] CONTROL3;
		wire [35:0] CONTROL4;
		wire [35:0] CONTROL5;
									
		icon icon_inst (
			.CONTROL0(CONTROL0), // INOUT BUS [35:0]
			.CONTROL1(CONTROL1), // INOUT BUS [35:0]
			.CONTROL2(CONTROL2), // INOUT BUS [35:0]
			.CONTROL3(CONTROL3), // INOUT BUS [35:0]
			.CONTROL4(CONTROL4), // INOUT BUS [35:0]
			.CONTROL5(CONTROL5)  // INOUT BUS [35:0]	
		);
		
		ila_1_bit ila_write_enable (
			.CONTROL(CONTROL0), // INOUT BUS [35:0]
			.CLK(clk), // IN
			.TRIG0(write_enable) // IN BUS [0:0]
		);

		ila_1_bit ila_done (
			.CONTROL(CONTROL1), // INOUT BUS [35:0]
			.CLK(clk), // IN
			.TRIG0(done) // IN BUS [0:0]
		);
		
		ila_1_bit ila_ck_n (
			.CONTROL(CONTROL2), // INOUT BUS [35:0]
			.CLK(clk), // IN
			.TRIG0(ck_n) // IN BUS [0:0]
		);

		ila_16_bits ila_dq_w (
			.CONTROL(CONTROL3), // INOUT BUS [35:0]
			.CLK(clk), // IN
			.TRIG0(dq_w) // IN BUS [15:0]
		);

		ila_16_bits ila_states_and_commands (
			.CONTROL(CONTROL4), // INOUT BUS [35:0]
			.CLK(clk), // IN
			.TRIG0({low_Priority_Refresh_Request, high_Priority_Refresh_Request,
					write_is_enabled, read_is_enabled, write_enable, read_enable, 
				   	main_state_clk_serdes, ck_en, cs_n, ras_n, cas_n, we_n}) // IN BUS [15:0]
		);

		ila_64_bits ila_states_and_wait_count (
			.CONTROL(CONTROL5), // INOUT BUS [35:0]
			.CLK(clk), // IN
			.TRIG0({data_to_ram, data_from_ram, low_Priority_Refresh_Request, high_Priority_Refresh_Request,
			 		write_enable, read_enable, dqs_counter, dqs_rising_edge, dqs_falling_edge, 
					main_state_clk_serdes, wait_count_clk_serdes, refresh_Queue}) // IN BUS [63:0]
		);

	`else
	
		// https://github.com/promach/internal_logic_analyzer
		
		localparam DIVIDE_RATIO_HALVED = (DIVIDE_RATIO >> 1);
		
	`endif
`endif


ddr3_memory_controller 
#(
	.NUM_OF_WRITE_DATA(NUM_OF_WRITE_DATA),
	.NUM_OF_READ_DATA(NUM_OF_READ_DATA),
	.DATA_BURST_LENGTH(DATA_BURST_LENGTH),
	
	.MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED(MAX_NUM_OF_REFRESH_COMMANDS_POSTPONED)
	`ifdef USE_SERDES
		, .SERDES_RATIO(SERDES_RATIO)
	`endif
)
ddr3_control
(
	// these are FPGA internal signals
	`ifdef TESTBENCH
		.clk(clk_sim),
	`else
		.clk(clk),
	`endif
	
	.reset(reset),  // reset for entire system
	.write_enable(write_enable),  // write to DDR memory
	.read_enable(read_enable),  // read from DDR memory
	.i_user_data_address(i_user_data_address),  // the DDR memory address for which the user wants to write/read the data
	.data_to_ram(data_to_ram),  // data for which the user wants to write to DDR RAM
	.data_from_ram(data_from_ram),  // the requested data from DDR RAM after read operation
	.user_desired_extra_read_or_write_cycles(user_desired_extra_read_or_write_cycles),  // for the purpose of postponing refresh commands
	
	`ifndef HIGH_SPEED
		.clk_slow_posedge(clk_slow_posedge),  // for dq phase shifting purpose
		.clk180_slow_posedge(clk180_slow_posedge),  // for dq phase shifting purpose
	`endif
	
	// these are to be fed into external DDR3 memory
	.address(address),
	.bank_address(bank_address),
	
	`ifdef HIGH_SPEED
		.ck_obuf(ck), // CK
		.ck_n_obuf(ck_n), // CK#
	`else
		.ck(ck), // CK
		.ck_n(ck_n), // CK#	
	`endif

	`ifdef TESTBENCH
		.ck_90(ck_90),
		.ck_270(ck_270),
		
		.dq_iobuf_enable(dq_iobuf_enable),
		.udqs_iobuf_enable(udqs_iobuf_enable),
		.ldqs_iobuf_enable(ldqs_iobuf_enable),
		
		.data_read_is_ongoing(data_read_is_ongoing),
	`endif
	
	`ifdef HIGH_SPEED
		.clk_serdes(clk_serdes),  // 83.333MHz with 45 phase shift
		.ck_180(ck_180),  // 333.333MHz with 180 phase shift
		.locked_previous(locked_previous),
		.need_to_assert_reset(need_to_assert_reset),
	`endif
		
	.ck_en(ck_en), // CKE
	.cs_n(cs_n), // chip select signal
	.odt(odt), // on-die termination
	.ras_n(ras_n), // RAS#
	.cas_n(cas_n), // CAS#
	.we_n(we_n), // WE#
	.reset_n(reset_n),  // reset only for RAM
	
	.dq(dq), // Data input/output

	.main_state_clk_serdes(main_state_clk_serdes),
	.wait_count_clk_serdes(wait_count_clk_serdes),
	
`ifdef USE_ILA
	.dq_w(dq_w),
	.dq_r(dq_r),
	.low_Priority_Refresh_Request(low_Priority_Refresh_Request),
	.high_Priority_Refresh_Request(high_Priority_Refresh_Request),
	.write_is_enabled(write_is_enabled),
	.read_is_enabled(read_is_enabled),
	.refresh_Queue(refresh_Queue),
	.dqs_counter(dqs_counter),
	.dqs_rising_edge(dqs_rising_edge),
	.dqs_falling_edge(dqs_falling_edge),
`endif

`ifdef USE_x16
	.ldm(ldm), // lower-byte data mask, to be asserted HIGH during data write activities into RAM
	.udm(udm), // upper-byte data mask, to be asserted HIGH during data write activities into RAM
	.ldqs(ldqs), // lower byte data strobe
	.ldqs_n(ldqs_n),
	.udqs(udqs), // upper byte data strobe
	.udqs_n(udqs_n)
`else
	.dqs(dqs), // Data strobe
	.dqs_n(dqs_n),
	
	// driven to high-Z if TDQS termination function is disabled 
	// according to TN-41-06: DDR3 Termination Data Strobe (TDQS)
	// Please as well look at TN-41-04: DDR3 Dynamic On-Die Termination Operation 
	.tdqs(tdqs), // Termination data strobe, but can act as data-mask (DM) when TDQS function is disabled

	.tdqs_n(tdqs_n)
`endif
);


`ifdef MICRON_SIM
// Micron simulation model

ddr3 mem(
    .rst_n(reset_n),
    .ck(ck),
    .ck_n(ck_n),
    .cke(ck_en),
    .cs_n(cs_n),
    .ras_n(ras_n),
    .cas_n(cas_n),
    .we_n(we_n),
    .dm_tdqs(dm),
    .ba(bank_address),
    .addr(address),
    .dq(dq),
    .dqs({udqs, ldqs}),
    .dqs_n({udqs_n, ldqs_n}),
    .tdqs_n(tdqs_n),
    .odt(odt)
);

`elsif TESTBENCH

	// to emulate DQS and DQ signals coming out from DDR3 RAM
	wire [DQ_BITWIDTH-1:0] test_dq_w;
	reg [DQ_BITWIDTH-1:0] test_dq_w_d0;
	reg [DQ_BITWIDTH-1:0] test_dq_w_d1;
	wire [DQS_BITWIDTH-1:0] test_dqs_w;

	always @(posedge ck_90)
	begin
		if(~reset_n | ~(|dq_iobuf_enable)) test_dq_w_d1 <= 1;
		
		else if(data_read_is_ongoing) test_dq_w_d1 <= test_dq_w_d0 + 1;
	end
	
	always @(posedge ck_270)
	begin
		if(~reset_n | ~(|dq_iobuf_enable)) test_dq_w_d0 <= 0;
		
		else if(data_read_is_ongoing) test_dq_w_d0 <= test_dq_w_d1 + 1;
	end
		
	// DQS and DQ signals are of double-data-rate signals

	`ifdef XILINX

		genvar test_dq_index;
		generate
		
			for(test_dq_index = 0; test_dq_index < DQ_BITWIDTH; test_dq_index = test_dq_index + 1)
			begin: test_dq_io
				
				IOBUF IO_test_dq (
					.IO(dq[test_dq_index]),
					.I(test_dq_w[test_dq_index]),
					.T(~dq_iobuf_enable[test_dq_index]),	
					.O()  // no need to connect since the code is only emulating DDR3 RAM emitting out DQ bit
				);


				ODDR2 #(
					.DDR_ALIGNMENT("NONE"),  // Sets output alignment to "NONE", "C0" or "C1"
					.INIT(1'b0),  // Sets initial state of the Q output to 1'b0 or 1'b1
					.SRTYPE("SYNC")  // Specifies "SYNC" or "ASYNC" set/reset
				)
				ODDR2_test_dq_w(
					.Q(test_dq_w[test_dq_index]),  // 1-bit DDR output data
					.C0(ck_90),  // 1-bit clock input
					.C1(ck_270),  // 1-bit clock input
					.CE(1'b1),  // 1-bit clock enable input
					.D0(test_dq_w_d1[test_dq_index]),    // 1-bit DDR data input (associated with C0)
					.D1(test_dq_w_d0[test_dq_index]),    // 1-bit DDR data input (associated with C1)			
					.R(reset),    // 1-bit reset input
					.S(1'b0)     // 1-bit set input
				);			
			end
		
		endgenerate


		`ifdef USE_x16
		
			IOBUF IO_test_udqs (
				.IO(udqs),
				.I(test_dqs_w[1]),
				.T(~udqs_iobuf_enable),
				.O()  // no need to connect since the code is only emulating DDR3 RAM emitting out DQS strobe
			);

			IOBUF IO_test_ldqs (
				.IO(ldqs),
				.I(test_dqs_w[0]),
				.T(~ldqs_iobuf_enable),
				.O()  // no need to connect since the code is only emulating DDR3 RAM emitting out DQS strobe
			);

		`else
		
			IOBUF IO_test_dqs (
				.IO(dqs),
				.I(test_dqs_w),
				.T(~dqs_iobuf_enable),
				.O()  // no need to connect since the code is only emulating DDR3 RAM emitting out DQS strobe
			);
			
		`endif
								
		genvar test_dqs_index;
		generate
		
			for(test_dqs_index = 0; test_dqs_index < DQS_BITWIDTH; test_dqs_index = test_dqs_index + 1)
			begin: test_dqs_io
							
				ODDR2 #(
					.DDR_ALIGNMENT("NONE"),  // Sets output alignment to "NONE", "C0" or "C1"
					.INIT(1'b0),  // Sets initial state of the Q output to 1'b0 or 1'b1
					.SRTYPE("SYNC")  // Specifies "SYNC" or "ASYNC" set/reset
				)
				ODDR2_test_dqs_w(
					.Q(test_dqs_w[test_dqs_index]),  // 1-bit DDR output data
					.C0(ck_90),  // 1-bit clock input
					.C1(ck_270),  // 1-bit clock input
					.CE(1'b1),  // 1-bit clock enable input
					.D0(1'b1),    // 1-bit DDR data input (associated with C0)
					.D1(1'b0),    // 1-bit DDR data input (associated with C1)			
					.R(1'b0),    // 1-bit reset input
					.S(1'b0)     // 1-bit set input
				);			
			end
			
		endgenerate
		
	`endif
	
`endif

endmodule


