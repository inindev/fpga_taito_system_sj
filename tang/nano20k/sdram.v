// Single-master SDRAM controller for the Tang Nano 20K embedded 64 Mbit SDRAM
// (GW2AR-18 SIP: 32-bit data, 4 banks x 2K rows x 256 columns x 32 bits = 8 MB).
//
// Written for the Taito System SJ port. Command encodings and mode register value are the
// standard SDR SDRAM ones.
//
// Every access is one self-contained auto-precharge transaction:
//
//   edge  E0  host rd/wr seen in IDLE      -> ACTIVATE  (bank, row)
//   edge  E1                               -> READ/WRITE with A10=1 (auto precharge)
//   edge  E4  read data captured in dq_r (I/O block register)
//   edge  E5  byte select -> dout, data_ready (1 cycle pulse), back to IDLE, busy drops
//
// so a transaction occupies 5 clk cycles and the next ACTIVATE can be issued
// 6 clk cycles after the previous one. Burst length 1, CAS latency 2.
//
//   T_RCD = 1 cycle  (ACT -> RD/WR)
//   T_RP  = 1 cycle  (auto-precharge hidden inside the T_RC window)
//   T_RC  = 5 cycles (ACT -> next ACT), >= 63 ns at any clk <= 66 MHz; at 32 MHz it is 156 ns
//
// SDRAM clock: the top level drives the SDRAM clock pin with ~clk (through an ODDR), so the
// chip samples every command/data at the middle of a clk cycle (half a cycle of setup). The
// chip sees READ at E1.5; with CL=2 the data is valid from about E3.5 + tAC until E4.5 + tOH,
// and is registered at E4.
//
// Address map of the 23-bit byte address:
//     [22:21] bank   [20:10] row (11 bits)   [9:2] column (8 bits)   [1:0] byte in 32-bit word
// Byte enables are done with DQM (write) and a byte mux (read).
//
// Refresh: AUTO REFRESH is issued from IDLE when the internal timer expires (every
// REFRESH_CYCLES clk cycles, default 400 = 12.5 us @ 32 MHz; 2048 rows need a refresh command
// at most every 31 us). busy is raised as soon as a refresh is pending so a well-behaved host
// never has a pulse in flight when the refresh starts. If a host pulse and a refresh are both
// pending in IDLE, the host access goes first.
//
// Host port protocol:
//   rd / wr : 1-cycle pulse, only when busy == 0. addr / din must be valid in that cycle.
//   data_ready : 1-cycle pulse, dout valid in the same cycle (reads only).
//   busy : 1 during init, during a transaction, and while a refresh is pending/running.
//
// `resetn` restarts the 200 us power-up wait and init sequence. top.sv drives it with the
// system reset, released once after power-up.
//
// FPGA notes: single clock domain, no clock gating, DQ tristate through one assign.

module sdram #(
    parameter integer CLK_HZ         = 32_000_000,
    parameter integer REFRESH_CYCLES = 400
) (
    input             clk,          // clkm_32MHZ (<= 66 MHz)
    input             resetn,

    // host port
    input             rd,
    input             wr,
    input      [22:0] addr,
    input      [7:0]  din,
    output reg [7:0]  dout,
    output            busy,
    output reg        data_ready,

    // SDRAM pins
    inout      [31:0] sdram_dq,
    output reg [10:0] sdram_a,
    output reg [1:0]  sdram_ba,
    output reg [3:0]  sdram_dqm,
    output            sdram_cs_n,
    output            sdram_ras_n,
    output            sdram_cas_n,
    output            sdram_we_n,
    output            sdram_cke
);

    // {CS#, RAS#, CAS#, WE#}
    localparam [3:0] CMD_NOP    = 4'b0111;
    localparam [3:0] CMD_ACTIVE = 4'b0011;
    localparam [3:0] CMD_READ   = 4'b0101;
    localparam [3:0] CMD_WRITE  = 4'b0100;
    localparam [3:0] CMD_PRE    = 4'b0010;
    localparam [3:0] CMD_REF    = 4'b0001;
    localparam [3:0] CMD_MRS    = 4'b0000;

    // CAS latency 2, burst length 1, sequential: A[6:4]=010 -> 0x020
    localparam [10:0] MODE_REG = 11'b000_0010_0000;

    localparam integer INIT_WAIT = (CLK_HZ / 1000) * 200 / 1000;   // 200 us

    reg [3:0] cmd = CMD_NOP;
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = cmd;
    assign sdram_cke = 1'b1;

    reg         dq_oen = 1'b1;          // 0 = FPGA drives DQ
    reg  [31:0] dq_out;
    assign sdram_dq = dq_oen ? 32'hzzzz_zzzz : dq_out;

    // DQ is registered on every edge with nothing between pad and register, so the
    // register goes into the I/O block (build.tcl: -ireg_in_iob) and the input timing does not
    // depend on placement. The byte select is done one cycle later, from dq_r.
    reg  [31:0] dq_r;
    always @(posedge clk) dq_r <= sdram_dq;

    // ------------------------------------------------------------------ init
    reg [14:0] init_cnt = 0;
    reg        init_wait_done = 1'b0;
    reg [3:0]  ic = 0;
    reg        init_run = 1'b0;
    reg        init_done = 1'b0;

    // ------------------------------------------------------------------ transaction
    localparam [1:0] OP_RD = 2'd0, OP_WR = 2'd1, OP_REF = 2'd2;

    reg        busy_r = 1'b0;
    reg [2:0]  step = 0;                // 0 = idle
    reg [1:0]  op;
    reg [22:0] addr_l;
    reg [7:0]  din_l;

    reg        ref_pend = 1'b0;
    reg [9:0]  ref_cnt = 0;

    assign busy = busy_r | ref_pend | ~init_done;

    always @(posedge clk) begin
        // defaults
        cmd        <= CMD_NOP;
        sdram_dqm  <= 4'b1111;
        dq_oen     <= 1'b1;
        data_ready <= 1'b0;

        if (!resetn) begin
            init_cnt       <= 0;
            init_wait_done <= 1'b0;
            init_run       <= 1'b0;
            init_done      <= 1'b0;
            ic             <= 0;
            busy_r         <= 1'b0;
            step           <= 0;
            ref_pend       <= 1'b0;
            ref_cnt        <= 0;
        end else begin
            // refresh timer
            if (ref_cnt == REFRESH_CYCLES - 1) begin
                ref_pend <= 1'b1;
                ref_cnt  <= 0;
            end else begin
                ref_cnt <= ref_cnt + 1'b1;
            end

            if (!init_done) begin
                // ---------------- power-up sequence
                ref_pend <= 1'b0;
                if (!init_wait_done) begin
                    if (init_cnt == INIT_WAIT) begin
                        init_wait_done <= 1'b1;
                        init_run       <= 1'b1;
                        ic             <= 0;
                    end else
                        init_cnt <= init_cnt + 1'b1;
                end else if (init_run) begin
                    ic <= ic + 1'b1;
                    case (ic)
                        4'd0:  begin cmd <= CMD_PRE; sdram_a <= 11'h400; sdram_ba <= 2'b00; end
                        4'd2:  cmd <= CMD_REF;
                        4'd6:  cmd <= CMD_REF;
                        4'd10: begin cmd <= CMD_MRS; sdram_a <= MODE_REG; sdram_ba <= 2'b00; end
                        4'd13: begin init_run <= 1'b0; init_done <= 1'b1; ref_cnt <= 0; end
                        default: ;
                    endcase
                end
            end else if (step == 0) begin
                // ---------------- IDLE
                if (rd | wr) begin
                    op      <= wr ? OP_WR : OP_RD;
                    addr_l  <= addr;
                    din_l   <= din;
                    cmd     <= CMD_ACTIVE;
                    sdram_ba <= addr[22:21];
                    sdram_a  <= addr[20:10];
                    busy_r  <= 1'b1;
                    step    <= 3'd1;
                end else if (ref_pend) begin
                    op       <= OP_REF;
                    cmd      <= CMD_REF;
                    ref_pend <= 1'b0;
                    ref_cnt  <= 0;
                    busy_r   <= 1'b1;
                    step     <= 3'd1;
                end
            end else begin
                // ---------------- inside a transaction
                step <= step + 1'b1;
                case (step)
                    3'd1: begin
                        case (op)
                            OP_RD: begin
                                cmd       <= CMD_READ;
                                sdram_a   <= {1'b1, 2'b00, addr_l[9:2]};   // A10 = auto precharge
                                sdram_ba  <= addr_l[22:21];
                                sdram_dqm <= 4'b0000;
                            end
                            OP_WR: begin
                                cmd       <= CMD_WRITE;
                                sdram_a   <= {1'b1, 2'b00, addr_l[9:2]};
                                sdram_ba  <= addr_l[22:21];
                                sdram_dqm <= ~(4'b0001 << addr_l[1:0]);
                                dq_out    <= {din_l, din_l, din_l, din_l};
                                dq_oen    <= 1'b0;
                            end
                            default: ;
                        endcase
                    end
                    3'd5: begin
                        // dq_r holds the word sampled at the step 4 edge, 3 edges after the
                        // READ command edge
                        if (op == OP_RD) begin
                            case (addr_l[1:0])
                                2'd0: dout <= dq_r[7:0];
                                2'd1: dout <= dq_r[15:8];
                                2'd2: dout <= dq_r[23:16];
                                2'd3: dout <= dq_r[31:24];
                            endcase
                            data_ready <= 1'b1;
                        end
                        step   <= 0;
                        busy_r <= 1'b0;
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule
