module deserializer
#(
	parameter D = 8,  // data bitwidth
	parameter S = 8	  // deserialization ratio
)
(
	input reset,
	input high_speed_clock,
	input [D-1:0] data_in,
	output reg [D*S-1:0] data_out
);

reg [$clog2(S)-1:0] deserialization_ratio;

always @(posedge high_speed_clock)
begin
	if(reset) deserialization_ratio <= 0;

	else deserialization_ratio <= deserialization_ratio + 1;
end

always @(posedge high_speed_clock)
begin
	// time to switch to new set of data

	if(deserialization_ratio == S) data_out <= {{D*(S-1){1'b0}}, data_in};  // value of 0 is don't care here
	 
	 
	// new incoming data are inserted at most-significant-bits (MSB) position
	// The oldest data at least-significant-bits (LSB) position will be removed/dropped
	// all old data are shifted to the right such that the new data has enough space to fill in at MSB position

	else data_out <= {data_in, data_out[D +: D*(S-1)]};
end

endmodule
