// Dual-clock RAM for the GW2AR-18.
// Write-through, not read-before-write: this device rejects BSRAM WRITE_MODE
// read-before-write (PA2122). Each port returns the byte just written on its
// own clock, and otherwise returns the stored byte.
//
// Unconnected port inputs default to 0. Several MiSTer instances leave port B
// commented out; a floating write clock makes Gowin reject the RAM.
module dpram_dc #(
	parameter widthad_a     = 8,
	parameter width_a       = 8,
	parameter instance_name = "NONE"
)
(
	input  wire [widthad_a-1:0] address_a,
	input  wire [widthad_a-1:0] address_b = {widthad_a{1'b0}},
	input  wire                 clock_a,
	input  wire                 clock_b   = 1'b0,
	input  wire [width_a-1:0]   data_a    = {width_a{1'b0}},
	input  wire [width_a-1:0]   data_b    = {width_a{1'b0}},
	input  wire                 wren_a    = 1'b0,
	input  wire                 wren_b    = 1'b0,
	output reg  [width_a-1:0]   q_a,
	output reg  [width_a-1:0]   q_b
);

	reg [width_a-1:0] mem [0:(1<<widthad_a)-1];

	always @(posedge clock_a) begin
		if (wren_a) begin
			mem[address_a] <= data_a;
			q_a <= data_a;
		end else begin
			q_a <= mem[address_a];
		end
	end

	always @(posedge clock_b) begin
		if (wren_b) begin
			mem[address_b] <= data_b;
			q_b <= data_b;
		end else begin
			q_b <= mem[address_b];
		end
	end

endmodule
