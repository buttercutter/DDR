// `define USE_x16 1
// `define HIGH_SPEED 1
// `define TDQS 1

`define RAM_SIZE_1GB
//`define RAM_SIZE_4GB


module test_ddr3_memory_controller
#(
	parameter CLK_PERIOD = 20,  // host clock period in ns
	
	`ifdef RAM_SIZE_1GB
		parameter ADDRESS_BITWIDTH = 13,
	`else
		parameter ADDRESS_BITWIDTH = 15,
	`endif
	
	parameter BANK_ADDRESS_BITWIDTH = 4,  // 4'b1000 (8 or eight) banks
	
	`ifdef USE_x16
		parameter DQ_BITWIDTH = 16  // bitwidth for each piece of data
	`else
		parameter DQ_BITWIDTH = 8  // bitwidth for each piece of data
	`endif
)
(
	input clk,
	input reset,
	output done,
	
	// these are to be fed into external DDR3 memory
	output [ADDRESS_BITWIDTH-1:0] address,
	output [BANK_ADDRESS_BITWIDTH-1:0] bank_address,
	output ck, // CK
	output ck_n, // CK#
	output ck_en, // CKE
	output cs_n, // chip select signal
	// output reg odt, // on-die termination
	output ras_n, // RAS#
	output cas_n, // CAS#
	output we_n, // WE#
	output reset_n,
	
	inout [DQ_BITWIDTH-1:0] dq, // Data input/output
`ifdef USE_x16
	output udm, // input data mask, to be asserted HIGH during data write activities into RAM
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


reg [BANK_ADDRESS_BITWIDTH+ADDRESS_BITWIDTH-1:0] i_user_data_address;  // the DDR memory address for which the user wants to write/read the data
reg [DQ_BITWIDTH-1:0] i_user_data;  // data for which the user wants to write/read to/from DDR
wire [DQ_BITWIDTH-1:0] o_user_data;  // the requested data from DDR RAM after read operation

reg write_enable, read_enable;

assign done = (o_user_data == {DQ_BITWIDTH{1'b1}});

always @(posedge clk)
begin
	if(reset) 
	begin
		i_user_data_address <= 0;
		i_user_data <= 0;
		write_enable <= 0;
		read_enable <= 0;
	end
	
	else begin
		i_user_data_address <= i_user_data_address + 1;
		i_user_data <= i_user_data + 1;
		write_enable <= 1;
		read_enable <= 1;
	end
end


ddr3_memory_controller ddr3
(
	// these are FPGA internal signals
	.clk(clk),
	.reset(reset),
	.write_enable(write_enable),  // write to DDR memory
	.read_enable(read_enable),  // read from DDR memory
	.i_user_data_address(i_user_data_address),  // the DDR memory address for which the user wants to write/read the data
	.i_user_data(i_user_data),  // data for which the user wants to write/read to/from DDR
	.o_user_data(o_user_data),  // the requested data from DDR RAM after read operation
	
	// these are to be fed into external DDR3 memory
	.address(address),
	.bank_address(bank_address),
	.ck(ck), // CK
	.ck_n(ck_n), // CK#
	.ck_en(ck_en), // CKE
	.cs_n(cs_n), // chip select signal
	// output reg odt, // on-die termination
	.ras_n(ras_n), // RAS#
	.cas_n(cas_n), // CAS#
	.we_n(we_n), // WE#
	.reset_n(reset_n),
	
	.dq(dq), // Data input/output
`ifdef USE_x16
	.udm(udm), // input data mask, to be asserted HIGH during data write activities into RAM
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

endmodule
