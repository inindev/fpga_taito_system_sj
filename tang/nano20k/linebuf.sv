// linebuf.sv - core video capture and 5x/3x scan-out into 1280x720 for the Tang Nano 20K.
//
// CAPTURE (clk_cap = clkm_48MHZ). When the core's pixel enable (core_pix_clk, a 1-clock pulse
// every 7 or 8 clocks of the 48 MHz clock) has been seen, the 3:3:3 pixel is written into a
// 32-line ring at {line[4:0], x} if H_BLANK and V_BLANK are both low. The core changes RED/GREEN/BLUE on the
// rising edge of that same pulse, so the sample is taken one 48 MHz clock after the pulse
// (pix_d) to stay clear of the update. The line counter is parked at -1 in V_BLANK and
// advances at the start of each active line (H_BLANK falling), where x also restarts.
// H_BLANK/V_BLANK are active HIGH (TaitoSJ_sync_bus.v: HBL = !HPIX[8], VBL = &VPIX[7:5]);
// active picture = 256 x 224. fs_tgl toggles at the first pixel of line 0.
//
// SCAN-OUT (clk_pix = 74.25 MHz). Pixel x is repeated 5 times (256*5 = 1280) and every stored
// line is shown 3 times (224*3 = 672 lines); lines 0..23 and 696..719 are black (letterbox).
// rgb is produced with a lead of 3 clocks against cx/cy (BRAM read register, game pixel
// register, menu mix register), so counters are re-armed when cx == frame_width-4.
//
// MENU (TangCore overlay). iosys_bl616's textdisp draws a 256x224 picture; it is shown on the
// same 256x224 grid as the game, scaled the same way (5x across, 3x down). overlay_x/overlay_y
// are the source pixel being read (xx/yy), so they step every 5 clocks (textdisp needs at
// least 3) and textdisp returns overlay_color 2 clocks after a step, in the same clock as the
// game pixel register; the third stage mixes the two. xx runs on through the horizontal blank
// and is 73 (odd) at the re-arm, so overlay_x always toggles bit 0 when it goes back to 0,
// which is how textdisp sees a new pixel.
//   overlay & !osd_strip: menu pixels (non-zero colour) over the game, dimmed to 1/4
//   overlay &  osd_strip: the volume bar strip, text columns 8-23 of rows 23-24 (source
//                         pixels 64-191, lines 184-199): lit pixels white on a band 2 source
//                         pixels wider all round, where the game is dimmed to 1/8 with a green
//                         tint; the rest of the game is untouched
// overlay and osd_strip come from the iosys clock and are brought in with two flops each.
//
// FRAME ALIGNMENT. The core's pixel enable averages exactly 60 Hz per frame, the same rate
// as the fixed 720p60 output, so the two frames keep a constant phase once set. At the start
// of picture row 0 (cy == VSTART) the scan-out measures phase_delta = time since the core
// started line 0 of its latest frame (74.25 MHz clocks) and pulses phase_sample. top.sv uses
// the first sample for a one-time alignment: it holds the core's video phases (vid_hold) for
// long enough that core line 0 then starts 400 us before HDMI row 24, and leaves it there.
// The core writes a line in 63.1 us (264 lines per frame) and the reader shows one in 66.7 us
// (3 x 22.2 us HDMI lines), so the writer's lead grows from ~400 us at the top of the picture
// to ~1190 us at the bottom. The 32-line ring holds about 2 ms of core lines, so the reader
// never overtakes the writer and the writer never laps the reader.
//
// Storage is 32 x 256 x 9 bit instead of a full frame: a 256x224x9 frame store needs 36 of the
// 46 block RAMs (measured with gw_sh) and the core already uses 21.

module linebuf (
    // capture
    input  logic        clk_cap,
    input  logic        pix_en,
    input  logic [2:0]  r_in,
    input  logic [2:0]  g_in,
    input  logic [2:0]  b_in,
    input  logic        h_blank,
    input  logic        v_blank,

    // scan-out
    input  logic        clk_pix,
    input  logic [10:0] cx,
    input  logic [9:0]  cy,
    input  logic [10:0] frame_width,
    input  logic [9:0]  frame_height,
    output logic [23:0] rgb,
    output logic [20:0] phase_delta,   // 74.25 MHz clocks since core line 0, at picture start
    output logic        phase_sample,  // 1-cycle pulse on that measurement

    // menu overlay (iosys_bl616)
    input  logic        overlay,       // iosys clock domain
    input  logic        osd_strip,     // iosys clock domain
    output logic [7:0]  overlay_x,     // clk_pix domain
    output logic [7:0]  overlay_y,
    input  logic [14:0] overlay_color  // BGR5, 2 clocks after overlay_x/overlay_y
);

    localparam integer VSTART = 24;            // (720 - 672) / 2
    localparam integer SRC_H  = 224;

    // ----------------------------------------------------------------- capture
    (* syn_ramstyle = "block_ram" *)
    logic [8:0] mem [0:8191];

    logic        pix_d = 1'b0, hb_d = 1'b0;
    logic [7:0]  wx = 8'd0, wy = 8'd0;
    logic        wen = 1'b0;
    logic [12:0] waddr = 13'd0;
    logic [8:0]  wdata = 9'd0;
    logic        fs_tgl = 1'b0;

    // First active pixel of a line = h_blank low while it was high at the previous pixel.
    wire [7:0] wy_n = hb_d ? wy + 1'b1 : wy;
    wire [7:0] wx_n = hb_d ? 8'd0      : wx;

    always_ff @(posedge clk_cap) begin
        pix_d <= pix_en;
        wen   <= 1'b0;
        if (pix_d) begin
            hb_d <= h_blank;
            if (v_blank) begin
                wy <= 8'hFF;                    // so that the first active line becomes row 0
                wx <= 8'd0;
            end else if (h_blank) begin
                wx <= 8'd0;
            end else begin
                wy <= wy_n;
                if (wx_n != 8'd255) wx <= wx_n + 1'b1;
                if (wy_n < SRC_H) begin
                    wen   <= 1'b1;
                    waddr <= {wy_n[4:0], wx_n};
                    wdata <= {r_in, g_in, b_in};
                end
                if (hb_d && wy_n == 8'd0) fs_tgl <= ~fs_tgl;   // line 0 starts
            end
        end
    end

    always_ff @(posedge clk_cap)
        if (wen) mem[waddr] <= wdata;

    // ----------------------------------------------------------------- phase measurement
    logic [2:0]  fs_s = 3'b000;
    logic [20:0] ts = 21'd0, ts_in = 21'd0;
    wire         fs_pulse = fs_s[2] ^ fs_s[1];

    always_ff @(posedge clk_pix) begin
        fs_s <= {fs_s[1:0], fs_tgl};
        ts   <= ts + 1'b1;
        if (fs_pulse) ts_in <= ts;
    end

    wire [20:0] delta = ts - ts_in;
    logic seen_fs = 1'b0;
    always_ff @(posedge clk_pix) begin
        if (fs_pulse) seen_fs <= 1'b1;
        phase_sample <= (cx == 11'd0 && cy == VSTART && seen_fs);
        if (cx == 11'd0 && cy == VSTART)
            phase_delta <= delta;
    end

    // ----------------------------------------------------------------- scan-out
    logic [10:0] pcnt = 11'd0;   // pixel position that will be on screen 3 clocks from now
    logic [2:0]  xsub = 3'd0;
    logic [7:0]  xx   = 8'd0;
    logic [7:0]  yy   = 8'd0;
    logic [1:0]  ysub = 2'd0;
    logic        vact = 1'b0;
    wire  [9:0]  cyn  = (cy == frame_height - 1'b1) ? 10'd0 : cy + 1'b1;

    always_ff @(posedge clk_pix) begin
        if (cx == frame_width - 4) begin
            pcnt <= 11'd0;
            xsub <= 3'd0;
            xx   <= 8'd0;
            // vertical state for the line that starts 3 clocks from now
            if (cyn == VSTART) begin
                vact <= 1'b1;
                yy   <= 8'd0;
                ysub <= 2'd0;
            end else if (vact) begin
                if (ysub == 2'd2) begin
                    if (yy == SRC_H - 1) vact <= 1'b0;
                    else begin
                        yy   <= yy + 1'b1;
                        ysub <= 2'd0;
                    end
                end else
                    ysub <= ysub + 1'b1;
            end
        end else begin
            pcnt <= pcnt + 1'b1;
            if (xsub == 3'd4) begin
                xsub <= 3'd0;
                xx   <= xx + 1'b1;
            end else
                xsub <= xsub + 1'b1;
        end
    end

    assign overlay_x = xx;
    assign overlay_y = yy;

    // BRAM read (registered), game pixel register, menu mix register
    logic [8:0]  q    = 9'd0;
    logic        act0 = 1'b0, act1 = 1'b0;
    logic [7:0]  x0, y0, x1, y1;
    logic [23:0] game = 24'h000000;
    wire  [12:0] raddr = {yy[4:0], xx};

    always_ff @(posedge clk_pix) begin
        q    <= mem[raddr];
        act0 <= vact && (pcnt < 11'd1280);
        x0   <= xx;
        y0   <= yy;
        act1 <= act0;
        x1   <= x0;
        y1   <= y0;
        if (act0)
            game <= {q[8:6], q[8:6], q[8:7],     // R
                     q[5:3], q[5:3], q[5:4],     // G
                     q[2:0], q[2:0], q[2:1]};    // B
        else
            game <= 24'h000000;
    end

    // overlay and osd_strip into clk_pix (the first flop of each is *_meta, see sj.sdc)
    logic ovl_meta = 1'b0, ovl_s = 1'b0, strip_meta = 1'b0, strip_s = 1'b0;
    always_ff @(posedge clk_pix) begin
        {ovl_s, ovl_meta}     <= {ovl_meta, overlay};
        {strip_s, strip_meta} <= {strip_meta, osd_strip};
    end

    wire strip_win = x1 >= 8'd64 && x1 < 8'd192 && y1 >= 8'd184 && y1 < 8'd200;
    wire band_win  = x1 >= 8'd62 && x1 < 8'd194 && y1 >= 8'd182 && y1 < 8'd202;
    wire lit       = overlay_color != 15'd0;

    // BGR5 to RGB888, low bits repeated so that 31 becomes 255
    wire [23:0] menu_rgb = {overlay_color[4:0],   overlay_color[4:2],
                            overlay_color[9:5],   overlay_color[9:7],
                            overlay_color[14:10], overlay_color[14:12]};

    always_ff @(posedge clk_pix) begin
        if (ovl_s && !strip_s)
            rgb <= act1 && lit ? menu_rgb
                 : {2'b0, game[23:18], 2'b0, game[15:10], 2'b0, game[7:2]};
        else if (ovl_s && act1 && band_win)
            rgb <= strip_win && lit ? 24'hFFFFFF
                 : {3'b000, game[23:19], 3'b010, game[15:11], 3'b000, game[7:3]};
        else
            rgb <= game;
    end

endmodule
