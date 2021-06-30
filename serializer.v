module serializer 
#(
	parameter D = 8,  // data bitwidth
	parameter S = 8	  // serialization ratio
)
(
	input high_speed_clock,
	input [D*S-1:0] data_in,
	output reg [D-1:0] data_out
);

always @(posedge high_speed_clock)
begin
	data_out <= data_in[0 +: D];
end

endmodule
