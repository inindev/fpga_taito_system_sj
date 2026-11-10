module hit_bus(
	input clkm_48MHZ,	//real clock
	input clkm_6MHZ,	//clock enable (1 pulse in 8 clkm_48MHZ cycles)
	input clkb_6MHZ,	//clock enable
	input OBJ,
	input SCN1,
	input SCN2,
	input SCN3,
	input HTCLR,
	input HLP0,
	input HLP1,
	input HLP2,	
	input HITOB,
	input HTRRQ,
	input [4:0] syncbus_HM,  //HBL=[4],128HM=[3],64HM=[2],32HM=[1],16HM=[0]
	input [1:0] ADDR_ED,
	output [7:0] HIT_DATA
);

//	PH <= ({PH[6:0],!(&HPIX[2:1])});

//for clock low all the time:
//reset going low sets all outputs low
//preset going high transfers all active high inputs to outputs , lows are not, so this is basically an OR
reg HITON;
wire [7:0] HD;
reg  [7:0] H0X, H1X, H2X, HOBJ;
reg  [15:0] HITREG;

always @(posedge clkm_48MHZ) if (clkm_6MHZ) begin
	HITREG<={HITREG[14:0],HITOB};
	HITON<=!(&HITREG[14:0]);
end

assign HD = HITON ? (8'h01 << syncbus_HM[2:0]) : 8'h00; 
	
// HTCLR arrives registered on the CPU clock; one more register on clkm_48MHZ.
// The clear is synchronous and has priority over hit accumulation.
reg HITCLEAR = 1'b0;
always @(posedge clkm_48MHZ) HITCLEAR <= !HTCLR;

always @(posedge clkm_48MHZ) begin
	if (HITCLEAR) HOBJ <= 8'b00000000;
	else if (clkb_6MHZ) HOBJ <= HOBJ|({2'b00,!(SCN2|SCN3),!(SCN3|SCN1),!(SCN2|SCN1),!(OBJ|SCN3),!(OBJ|SCN2),!(OBJ|SCN1)});
end

// HLP0..2 are 1-cycle pulses (already ANDed with the 6MHz enable in sync_bus): use them as enables, not clocks.
always @(posedge clkm_48MHZ) begin
	if (HITCLEAR)  begin H0X <= 8'b00000000; H1X <= 8'b00000000; H2X <= 8'b00000000; end
	else begin
		if (HLP0) H0X <= H0X|HD;
		if (HLP1) H1X <= H1X|HD;
		if (HLP2) H2X <= H2X|HD;
	end
end

wire [7:0] hit_data_array [3:0];

assign hit_data_array[0] = H0X;
assign hit_data_array[1] = H1X;
assign hit_data_array[2] = H2X;
assign hit_data_array[3] = HOBJ;

assign HIT_DATA = hit_data_array[ADDR_ED[1:0]];

endmodule

