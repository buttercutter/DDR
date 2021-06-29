module deserializer
#(
	parameter D = 8,  // data bitwidth
	parameter S = 8	  // deserialization ratio
)
(
	input high_speed_clock,
	input [D-1:0] data_in,
	output reg [D*S-1:0] data_out
);

always @(posedge high_speed_clock)
begin
	 
	// new incoming data are inserted at most-significant-bits (MSB) position
	// The oldest data at least-significant-bits (LSB) position will be removed/dropped
	// all old data are shifted to the right such that the new data has enough space to fill in at MSB position

	data_out <= {data_in, data_out[D +: D*(S-1)]};
end

endmodule
