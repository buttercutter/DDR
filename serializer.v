module serializer 
#(
	parameter D = 8,  // data bitwidth
	parameter S = 8	  // serialization ratio
)
(
	input reset,
	input high_speed_clock,
	input [D*S-1:0] data_in,
	output reg [D-1:0] data_out
);

reg [$clog2(S)-1:0] serialization_ratio;

always @(posedge high_speed_clock)
begin
	if(reset) serialization_ratio <= 0;

	else serialization_ratio <= serialization_ratio + 1;
end

always @(posedge high_speed_clock)
begin
	data_out <= data_in[serialization_ratio*D +: D];
end

endmodule
