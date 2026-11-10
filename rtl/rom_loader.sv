//============================================================================
// 
//  SD card ROM loader and ROM selector for MISTer.
//  Copyright (C) 2019 Kitrinx (aka Rysha)
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//	 the rights to use, copy, modify, merge, publish, distribute, sublicense,
//	 and/or sell copies of the Software, and to permit persons to whom the 
//	 Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//	 all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//	 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//	 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//	 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//	 DEALINGS IN THE SOFTWARE.
//
//============================================================================

// Rom layout for Taito System SJ (the ROM image in MRA order):
// 0x00000 - 0x07FFF = eprom_0   - Main CPU program, 32 KB
// 0x08000 - 0x0FFFF = eprom_1   - Main CPU program, banked, 32 KB
// 0x10000 - 0x17FFF = eprom_2   - Graphics, 32 KB
// 0x18000 - 0x1BFFF = eprom_3   - Sound CPU program, 16 KB
//                                 (eprom_0..eprom_3 are held in SDRAM)
// 0x1C000 - 0x1C0FF = eprom_4   - Layer PROM, 256 bytes
// 0x1C100 - 0x1C7FF =             padding (zeros; decoded as MCU, then overwritten)
// 0x1C800 - 0x1CFFF = eprom_mcu - MCU ROM, 2 KB
// 0x1D000 - 0x1DFFF = extra_rom - Extra ROM, 4 KB (Front Line and others; optional)


module selector
(
	input logic [24:0] ioctl_addr,
	output logic ep4_cs, ep5_cs, ep6_cs
);

	always_comb begin
		{ep4_cs, ep5_cs, ep6_cs} = 0;

		// Below 'h1C000 are eprom_0..eprom_3 (main, banked, graphics, sound). They live in
		// SDRAM, written by the board boot FSM, so they need no select here.
		if (ioctl_addr >= 'h1C000) begin
			if     (ioctl_addr < 'h1C100) ep4_cs = 1; // 0x0100 8    - Layer PROM
			//padding from 'h1C100 to h1C7FF
			else if(ioctl_addr < 'h1D000) ep5_cs = 1; // 0x0F00 12   - MCU

			else ep6_cs = 1; // Extra ROM (FrontLine)
		end

	end
endmodule

////////////
// EPROMS //
////////////

//
// Large ROMs (eprom_0 .. eprom_3) are no longer BRAM loaded through dn_*.
// They are served from external SDRAM through a request port on taitosj_fpga:
//   rom_req / rom_id / rom_addr / rom_q / rom_ack   (all clkm_32MHZ domain)
//   id 0 = eprom_0 (main program), 1 = eprom_1 (banked program),
//   id 2 = eprom_2 (external graphics), 3 = eprom_3 (sound program, bit 14 of rom_addr = 0)
// The board boot FSM writes SDRAM directly while the core is in reset, so the selector
// only decodes the small ROMs above 'h1C000.
// eprom_4, eprom_mcu and extra_rom below are still BRAM written by the dn_* bus.
//

// -----------------------------------------------------------------------------
// rom_ext_arb : clkm_32MHZ side. One outstanding request at a time.
//   * main client (CPU / graphics ROM / MCU DMA prefetch) is level based, with a
//     one-entry {id,addr} tag cache; priority over the sound client.
//   * sound client is a toggle handshake from the clkm_48MHZ domain.
//   * rom_req/rom_id/rom_addr come from registers and are stable while rom_req is high.
//     rom_req is additionally masked in the cycle rom_ack is high, so it never overlaps
//     the ack cycle as a second request.
// -----------------------------------------------------------------------------
module rom_ext_arb
(
	input  logic        clk,        // clkm_32MHZ
	input  logic        rst_n,

	// main client
	input  logic        m_want,
	input  logic [1:0]  m_id,
	input  logic [14:0] m_addr,
	output logic        m_hit,      // m_data is the byte for {m_id,m_addr}
	output logic [7:0]  m_data,

	// sound client (toggle handshake)
	input  logic        s_req_tgl,  // from clkm_48MHZ domain
	input  logic [13:0] s_req_addr, // stable while a request is pending
	output logic        s_ack_tgl,  // to clkm_48MHZ domain
	output logic [7:0]  s_data,     // stable until the next sound ack

	// external ROM port
	output logic        rom_req,
	output logic [1:0]  rom_id,
	output logic [14:0] rom_addr,
	input  logic [7:0]  rom_q,
	input  logic        rom_ack
);

	logic [1:0]  s_req_sync;
	logic        req_r, who_snd;
	logic [1:0]  id_r;
	logic [14:0] addr_r;
	logic        m_valid;
	logic [16:0] m_tag;

	always_ff @(posedge clk) s_req_sync <= {s_req_sync[0], s_req_tgl};

	wire s_pend = (s_req_sync[1] != s_ack_tgl);

	assign m_hit    = m_valid & (m_tag == {m_id, m_addr});
	assign rom_req  = req_r & ~rom_ack;
	assign rom_id   = id_r;
	assign rom_addr = addr_r;

	always_ff @(posedge clk) begin
		if (!rst_n) begin
			req_r     <= 1'b0;
			who_snd   <= 1'b0;
			m_valid   <= 1'b0;
			s_ack_tgl <= 1'b0;
		end else if (req_r) begin
			if (rom_ack) begin
				req_r <= 1'b0;
				if (who_snd) begin
					s_data    <= rom_q;
					s_ack_tgl <= ~s_ack_tgl;
				end else begin
					m_data  <= rom_q;
					m_tag   <= {id_r, addr_r};
					m_valid <= 1'b1;
				end
			end
		end else begin
			if (m_want & ~m_hit) begin
				req_r   <= 1'b1;
				who_snd <= 1'b0;
				id_r    <= m_id;
				addr_r  <= m_addr;
			end else if (s_pend) begin
				req_r   <= 1'b1;
				who_snd <= 1'b1;
				id_r    <= 2'd3;
				addr_r  <= {1'b0, s_req_addr};
			end
		end
	end
endmodule

// -----------------------------------------------------------------------------
// eprom_3 : sound ROM client, runs on the sound CPU clock domain (clkm_48MHZ).
//   NEED   : sound CPU is reading the ROM right now (address presented, RD/MREQ active)
//   STALL_n: low while NEED and the byte for ADDR is not yet available -> feeds WAIT_n
//   DATA   : byte for ADDR (valid whenever STALL_n is high or NEED is low and tag matches)
// -----------------------------------------------------------------------------
module eprom_3 //sound ROM
(
	input  logic        CLK,        // clkm_48MHZ
	input  logic        RST_n,
	input  logic        NEED,
	input  logic [13:0] ADDR,
	output logic [7:0]  DATA,
	output logic        STALL_n,

	output logic        REQ_TGL,    // toggles to request a byte
	output logic [13:0] REQ_ADDR,   // held until the ack is seen
	input  logic        ACK_TGL,    // from clkm_32MHZ domain
	input  logic [7:0]  ACK_DATA
);
	logic [1:0]  ack_sync;
	logic        ack_seen, valid;
	logic [13:0] tag;

	wire hit  = valid & (tag == ADDR);
	wire pend = (REQ_TGL != ack_seen);
	wire ack  = (ack_sync[1] != ack_seen);

	assign STALL_n = ~(NEED & ~hit);

	always_ff @(posedge CLK) begin
		ack_sync <= {ack_sync[0], ACK_TGL};
		if (!RST_n) begin
			REQ_TGL  <= 1'b0;
			ack_seen <= ack_sync[1];   // follow the (reset) ack toggle so both sides re-align
			valid    <= 1'b0;
		end else if (ack) begin
			ack_seen <= ack_sync[1];
			DATA     <= ACK_DATA;
			tag      <= REQ_ADDR;
			valid    <= 1'b1;
		end else if (NEED & ~hit & ~pend) begin
			REQ_TGL  <= ~REQ_TGL;
			REQ_ADDR <= ADDR;
		end
	end
endmodule


module eprom_4 //layer ROM
(
	input logic        CLK,
	input logic        CLK_DL,
	input logic [7:0] ADDR,
	input logic [24:0] ADDR_DL,
	input logic [7:0]  DATA_IN,
	input logic        CS_DL,
	input logic        WR,
	output logic [7:0] DATA
);
	dpram_dc #(.widthad_a(8)) eprom_4
	(
		.clock_a(CLK),
		.address_a(ADDR[7:0]),
		.q_a(DATA[7:0]),

		.clock_b(CLK_DL),
		.address_b(ADDR_DL[7:0]),
		.data_b(DATA_IN),
		.wren_b(WR & CS_DL)
	);
endmodule

module eprom_mcu
(
	input logic        CLK,
	input logic        CLK_DL,
	input logic [10:0] ADDR,
	input logic [24:0] ADDR_DL,
	input logic [7:0]  DATA_IN,
	input logic        CS_DL,
	input logic        WR,
	output logic [7:0] DATA
);
	dpram_dc #(.widthad_a(11)) eprom_mcu
	(
		.clock_a(CLK),
		.address_a(ADDR[10:0]),
		.q_a(DATA[7:0]),

		.clock_b(CLK_DL),
		.address_b(ADDR_DL[10:0]),
		.data_b(DATA_IN),
		.wren_b(WR & CS_DL)
	);
endmodule


module extra_rom
(
	input logic        CLK,
	input logic        CLK_DL,
	input logic [11:0] ADDR,
	input logic [24:0] ADDR_DL,
	input logic [7:0]  DATA_IN,
	input logic        CS_DL,
	input logic        WR,
	output logic [7:0] DATA
);
	dpram_dc #(.widthad_a(12)) extra_rom
	(
		.clock_a(CLK),
		.address_a(ADDR[11:0]),
		.q_a(DATA[7:0]),

		.clock_b(CLK_DL),
		.address_b(ADDR_DL[11:0]),
		.data_b(DATA_IN),
		.wren_b(WR & CS_DL)
	);
endmodule





