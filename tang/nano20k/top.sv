// top.sv - Taito System SJ on the Sipeed Tang Nano 20K (GW2AR-LV18QN88C8/I7), TangCore core
//
//   27 MHz crystal (pin 4)
//     |-- gowin_pll_game : 96 MHz VCO tap -> CLKOUTD 48 MHz (clkm_48MHZ), CLKOUTD3 32 MHz (clkm_32MHZ)
//     '-- gowin_pll_hdmi : 371.25 MHz -> CLKDIV/5 -> 74.25 MHz pixel clock
//
//   BL616 (UART) <-> iosys_bl616 (32 MHz): menu overlay, ROM stream, gamepads, DIP switches, volume
//   iosys rom_do --> rom_stream --+--> SDRAM (eprom_0..3, 114688 bytes)
//                                 '--> dn_addr/dn_data/dn_wr -> core (eprom_4, eprom_mcu, extra_rom)
//   core rom_req/rom_ack  <-- arbiter (this file) --> sdram.v
//   core RED/GREEN/BLUE   --> linebuf (+ menu overlay) --> hdmi (720p60, audio)
//
// The core is held in reset from power-up until a ROM has been loaded, and again for every new
// load. While it is in reset rom_stream owns the SDRAM bus and the dn_* port; once it runs, the
// core's rom_req/rom_ack port owns the bus.
//
// Gamepads (SNES layout, 1 = pressed: R L X A RT LT DN UP START SELECT Y B, bits 11..0): USB
// gamepads on the BL616 (iosys hid1/hid2), SNES pads (pins 25-30) and DualShock pads (pins 17-20,
// 52, 53, 71, 72), as in nestang's Nano 20K build. The board has one set of player controls
// (P1CONTROLS; the second player of an alternating game uses the same ones), so both pads drive
// it:
//   D-pad: joystick    B or Y: fire (button 1)    A or X: jump (button 2)    SELECT: coin A
//   START: 1P start on pad 1, 2P start on pad 2   R: 2P start (either pad)
//   board button S1: coin A and 1P start together
// While the menu is shown (not the volume strip) the game is paused (the core's pause input,
// as on MiSTer) and gets no buttons.

module top (
    input  logic        sys_clk,                // 27 MHz, pin 4
    input  logic        s1,                     // board button S1, active high (pin 88)
    output logic [1:0]  led,                    // active low

    // UART to the BL616
    input  logic        UART_RXD,
    output logic        UART_TXD,

    // SNES controllers
    output logic        joy1_strb,
    output logic        joy1_clk,
    input  logic        joy1_data,
    output logic        joy2_strb,
    output logic        joy2_clk,
    input  logic        joy2_data,

    // DualShock controllers
    output logic        ds_clk,
    input  logic        ds_miso,
    output logic        ds_mosi,
    output logic        ds_cs,
    output logic        ds_clk2,
    input  logic        ds_miso2,
    output logic        ds_mosi2,
    output logic        ds_cs2,

    // onboard parts
    output logic        pa_en,                  // audio amp enable: held off
    output logic        ws2812,                 // RGB LED: sent "off" once at power-up

    // embedded SDRAM (no pin constraints: placed by the tool)
    output logic        O_sdram_clk,
    output logic        O_sdram_cke,
    output logic        O_sdram_cs_n,
    output logic        O_sdram_cas_n,
    output logic        O_sdram_ras_n,
    output logic        O_sdram_wen_n,
    inout  logic [31:0] IO_sdram_dq,
    output logic [10:0] O_sdram_addr,
    output logic [1:0]  O_sdram_ba,
    output logic [3:0]  O_sdram_dqm,

    // HDMI
    output logic        tmds_clk_n,
    output logic        tmds_clk_p,
    output logic [2:0]  tmds_d_n,
    output logic [2:0]  tmds_d_p
);

    // SDRAM byte address of each ROM image. Must match rom_stream (ID3_BASE).
    localparam [22:0] BASE_ID0 = 23'h00000;
    localparam [22:0] BASE_ID1 = 23'h08000;
    localparam [22:0] BASE_ID2 = 23'h10000;
    localparam [22:0] BASE_ID3 = 23'h18000;     // after the 32 KB id 2 image (0x10000-0x17FFF)

    localparam integer CLK32_HZ = 32_000_000;   // iosys, controllers, SDRAM

    // ------------------------------------------------------------------ clocks
    logic clkm_48MHZ, clkm_32MHZ;
    logic hclk5, hclk;
    logic sys_resetn = 1'b0;            // see "resets" below

    gowin_pll_game u_pll_game (
        .clkin   (sys_clk),
        .clkout  (),                    // 96 MHz, not used
        .clkoutd (clkm_48MHZ),
        .clkoutd3(clkm_32MHZ),
        .lock    ()
    );

    gowin_pll_hdmi u_pll_hdmi (
        .clkin (sys_clk),
        .clkout(hclk5),
        .lock  ()
    );

    CLKDIV #(.DIV_MODE(5)) u_div5 (
        .CLKOUT(hclk),
        .HCLKIN(hclk5),
        .RESETN(sys_resetn),
        .CALIB (1'b0)
    );

    // SDRAM clock = ~clkm_32MHZ, made by an ODDR in the I/O block (low after the rising
    // edge, high after the falling edge) so its delay does not depend on placement.
    ODDR u_sdram_clk (
        .Q0 (O_sdram_clk),
        .Q1 (),
        .D0 (1'b0),
        .D1 (1'b1),
        .TX (1'b0),
        .CLK(clkm_32MHZ)
    );

    // ------------------------------------------------------------------ onboard parts
    // Keep the onboard audio amp off (MAX98357A SD_MODE, low = shutdown)
    assign pa_en = 1'b0;

    // Turn the onboard WS2812 RGB LED off: it can latch a colour from noise while the FPGA
    // configures. At 27 MHz (sys_clk): hold low 8192 cycles (303 us, a reset), send 24 zero bits
    // (34 cycles = 1.26 us each, high for 8 = 296 ns), then stay low. From nestang_top.sv.
    logic [12:0] ws_rst = 13'd0;
    logic [5:0]  ws_ph  = 6'd0;
    logic [4:0]  ws_bit = 5'd0;
    logic        ws_done = 1'b0;
    logic        ws_out  = 1'b0;
    always_ff @(posedge sys_clk) begin
        ws_out <= 1'b0;
        if (!ws_done) begin
            if (ws_rst != 13'h1fff)
                ws_rst <= ws_rst + 13'd1;
            else begin
                ws_out <= ws_ph < 6'd8;
                if (ws_ph != 6'd33)
                    ws_ph <= ws_ph + 6'd1;
                else begin
                    ws_ph <= 6'd0;
                    if (ws_bit == 5'd23)
                        ws_done <= 1'b1;
                    else
                        ws_bit <= ws_bit + 5'd1;
                end
            end
        end
    end
    assign ws2812 = ws_out;

    // ------------------------------------------------------------------ resets
    // One system reset, released once 65535 clocks (about 2 ms) after power-up and never asserted
    // again, as in the monitor core and snestang. The PLL lock outputs are not used.
    logic [15:0] resetcnt = 16'hffff;
    always_ff @(posedge clkm_32MHZ) begin
        resetcnt <= resetcnt == 0 ? 16'd0 : resetcnt - 16'd1;
        if (resetcnt == 0)
            sys_resetn <= 1'b1;
    end

    // ------------------------------------------------------------------ iosys (BL616 link)
    logic        overlay, osd_strip;
    logic [7:0]  overlay_x, overlay_y;
    logic [14:0] overlay_color;
    logic [15:0] hid1, hid2;
    logic [11:0] joy1_snes, joy2_snes, joy1_ds2, joy2_ds2;
    logic [7:0]  rom_loading;
    logic [7:0]  rom_do;
    logic        rom_do_valid;
    logic [31:0] core_config;
    logic [3:0]  volume;

    iosys_bl616 #(
        .FREQ      (CLK32_HZ),
        .CORE_ID   (7),
        .COLOR_LOGO(15'b11100_01111_00101)      // BGR5, Taito blue
    ) u_iosys (
        .clk           (clkm_32MHZ),
        .hclk          (hclk),
        .resetn        (sys_resetn),
        .overlay       (overlay),
        .osd_strip     (osd_strip),
        .overlay_x     (overlay_x),
        .overlay_y     (overlay_y),
        .overlay_color (overlay_color),
        .joy1          (joy1_snes | joy1_ds2),  // the board's own pads, for the menu
        .joy2          (joy2_snes | joy2_ds2),
        .hid1          (hid1),
        .hid2          (hid2),
        .rom_loading   (rom_loading),
        .rom_do        (rom_do),
        .rom_do_valid  (rom_do_valid),
        .mgmt_address  (),
        .mgmt_read     (),
        .mgmt_readdata (16'h0000),
        .mgmt_write    (),
        .mgmt_writedata(),
        .fdd_request   (2'b00),
        .kbd_data      (),
        .kbd_data_valid(),
        .core_config   (core_config),
        .volume        (volume),
        .uart_rx       (UART_RXD),
        .uart_tx       (UART_TXD)
    );

    wire menu_32 = overlay & ~osd_strip;        // menu shown: game paused, no buttons

    // DIP switches and PCB type from the firmware (iosys command 0x03). core_config is a
    // clkm_32MHZ register; one more register here so the core's many uses do not load it.
    //   [7:0] DIP1, [15:8] DIP2, [23:16] DIP3, [31:24] pcb (the MRA's <rom index="1"> byte)
    logic [31:0] cfg = 32'h0;
    always_ff @(posedge clkm_32MHZ) cfg <= core_config;

    // ------------------------------------------------------------------ gamepads
    controller_snes #(.FREQ(CLK32_HZ)) u_joy1_snes (
        .clk(clkm_32MHZ), .resetn(sys_resetn), .buttons(joy1_snes),
        .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data)
    );
    controller_snes #(.FREQ(CLK32_HZ)) u_joy2_snes (
        .clk(clkm_32MHZ), .resetn(sys_resetn), .buttons(joy2_snes),
        .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data)
    );
    controller_ds2 #(.FREQ(CLK32_HZ)) u_joy1_ds2 (
        .clk(clkm_32MHZ), .snes_buttons(joy1_ds2),
        .ds_clk(ds_clk), .ds_miso(ds_miso), .ds_mosi(ds_mosi), .ds_cs(ds_cs)
    );
    controller_ds2 #(.FREQ(CLK32_HZ)) u_joy2_ds2 (
        .clk(clkm_32MHZ), .snes_buttons(joy2_ds2),
        .ds_clk(ds_clk2), .ds_miso(ds_miso2), .ds_mosi(ds_mosi2), .ds_cs(ds_cs2)
    );

    // All sources of each pad, SNES layout, 1 = pressed
    wire [11:0] pad1 = joy1_snes | joy1_ds2 | hid1[11:0];
    wire [11:0] pad2 = joy2_snes | joy2_ds2 | hid2[11:0];
    wire [11:0] pads = pad1 | pad2;

    // Player controls, 1 = pressed, in the core's P1CONTROLS order (TaitoSJCore.v)
    logic [10:0] ctl_32;
    always_ff @(posedge clkm_32MHZ) begin
        ctl_32[0]  <= pads[7];                  // right
        ctl_32[1]  <= pads[6];                  // left
        ctl_32[2]  <= pads[5];                  // down
        ctl_32[3]  <= pads[4];                  // up
        ctl_32[4]  <= pads[0] | pads[1];        // button 1 (fire): B, Y
        ctl_32[5]  <= pads[8] | pads[9];        // button 2 (jump): A, X
        ctl_32[6]  <= pads[2];                  // coin A: SELECT
        ctl_32[7]  <= pad1[3];                  // 1P start: START on pad 1
        ctl_32[8]  <= 1'b0;                     // coin B
        ctl_32[9]  <= pad2[3] | pads[11];       // 2P start: START on pad 2, R
        ctl_32[10] <= 1'b0;                     // service
        if (menu_32) ctl_32 <= '0;
    end

    // ------------------------------------------------------------------ ROM loading
    logic        st_wr, loaded, short_load;
    logic [22:0] st_addr;
    logic [7:0]  st_din;
    logic [24:0] sdn_addr;
    logic [7:0]  sdn_data;
    logic        sdn_wr;
    logic        sd_busy, sd_data_ready;
    logic [7:0]  sd_dout;
    wire         loading = rom_loading != 8'd0;

    rom_stream u_stream (
        .clk         (clkm_32MHZ),
        .resetn      (sys_resetn),
        .loading     (loading),
        .rom_do      (rom_do),
        .rom_do_valid(rom_do_valid),
        .sd_wr       (st_wr),
        .sd_addr     (st_addr),
        .sd_din      (st_din),
        .sd_busy     (sd_busy),
        .dn_addr     (sdn_addr),
        .dn_data     (sdn_data),
        .dn_wr       (sdn_wr),
        .loaded      (loaded),
        .short_load  (short_load)
    );

    // core reset: released 16 clocks after a complete load, asserted again as soon as the next
    // load starts (loading is checked directly so the core stops before the first byte)
    logic [4:0] core_rst_cnt;
    logic       core_rst_n;
    always_ff @(posedge clkm_32MHZ) begin
        if (!sys_resetn || !loaded || loading) begin
            core_rst_cnt <= '0;
            core_rst_n   <= 1'b0;
        end else if (!core_rst_cnt[4]) begin
            core_rst_cnt <= core_rst_cnt + 1'b1;
        end else
            core_rst_n <= 1'b1;
    end

    // dn_* into the 48 MHz domain. addr/data are stable around dn_wr (see rom_stream), wr goes
    // through a 2-flop synchroniser and addr/data through 2 plain stages so they stay aligned.
    // dn_wr is held ~12 core clocks, i.e. the core's BRAM sees the same byte written several
    // times, which is harmless.
    logic [24:0] dn_addr_a, dn_addr;
    logic [7:0]  dn_data_a, dn_data;
    logic        dn_wr_a,   dn_wr;
    always_ff @(posedge clkm_48MHZ) begin
        dn_addr_a <= sdn_addr;  dn_addr <= dn_addr_a;
        dn_data_a <= sdn_data;  dn_data <= dn_data_a;
        dn_wr_a   <= sdn_wr;    dn_wr   <= dn_wr_a;
    end

    // core reset into the 48 MHz domain is only used through RESET_n below (registered here)
    logic [1:0] core_rst48_sr = 2'b00;
    always_ff @(posedge clkm_48MHZ)
        core_rst48_sr <= {core_rst48_sr[0], core_rst_n};
    wire core_resetn_48 = core_rst48_sr[1];

    // ------------------------------------------------------------------ SDRAM + arbiter
    logic        core_rom_req;
    logic [1:0]  core_rom_id;
    logic [14:0] core_rom_addr;
    logic [7:0]  core_rom_q;
    logic        core_rom_ack;

    logic [22:0] rom_base;
    always_comb
        case (core_rom_id)
            2'd0:    rom_base = BASE_ID0;
            2'd1:    rom_base = BASE_ID1;
            2'd2:    rom_base = BASE_ID2;
            default: rom_base = BASE_ID3;
        endcase
    wire [22:0] rom_phys = rom_base + {8'b0, core_rom_addr};

    // One read outstanding at a time. A returning beat is acknowledged only if rom_req is
    // still asserted for the same {id, addr} that was issued; otherwise it is dropped.
    // rom_ack is a registered pulse so rom_q (also registered) and the ack coincide.
    logic        rd_r, pend, ack_r, ack_d;
    logic [16:0] snap;
    logic [22:0] rd_addr;
    logic [7:0]  q_r;

    always_ff @(posedge clkm_32MHZ) begin
        rd_r  <= 1'b0;
        ack_r <= 1'b0;
        ack_d <= ack_r;
        if (!core_rst_n) begin
            pend <= 1'b0;
        end else if (!pend) begin
            // ack_r/ack_d: hold off for the cycles in which the core is still dropping rom_req
            if (core_rom_req && !sd_busy && !ack_r && !ack_d) begin
                rd_r    <= 1'b1;
                pend    <= 1'b1;
                snap    <= {core_rom_id, core_rom_addr};
                rd_addr <= rom_phys;
            end
        end else if (sd_data_ready) begin
            pend <= 1'b0;
            if (core_rom_req && snap == {core_rom_id, core_rom_addr}) begin
                ack_r <= 1'b1;
                q_r   <= sd_dout;
            end
        end
    end

    assign core_rom_ack = ack_r;
    assign core_rom_q   = q_r;

    // While the core is in reset the loader owns the bus, otherwise the core's reads. A read
    // still in the controller when a load starts finishes first: the loader waits for !sd_busy.
    wire        sd_rd_i   = core_rst_n ? rd_r : 1'b0;
    wire        sd_wr_i   = core_rst_n ? 1'b0 : st_wr;
    wire [22:0] sd_addr_i = core_rst_n ? rd_addr : st_addr;

    sdram u_sdram (
        .clk        (clkm_32MHZ),
        .resetn     (sys_resetn),
        .rd         (sd_rd_i),
        .wr         (sd_wr_i),
        .addr       (sd_addr_i),
        .din        (st_din),
        .dout       (sd_dout),
        .busy       (sd_busy),
        .data_ready (sd_data_ready),
        .sdram_dq   (IO_sdram_dq),
        .sdram_a    (O_sdram_addr),
        .sdram_ba   (O_sdram_ba),
        .sdram_dqm  (O_sdram_dqm),
        .sdram_cs_n (O_sdram_cs_n),
        .sdram_ras_n(O_sdram_ras_n),
        .sdram_cas_n(O_sdram_cas_n),
        .sdram_we_n (O_sdram_wen_n),
        .sdram_cke  (O_sdram_cke)
    );

    // ------------------------------------------------------------------ inputs (48 MHz)
    // Gamepad controls and the menu state into the core's 48 MHz clock (two flops, the first
    // *_meta; see sj.sdc).
    logic [10:0] ctl_meta = '0, ctl_48 = '0;
    logic        pause_meta = 1'b0, pause_48 = 1'b0;
    always_ff @(posedge clkm_48MHZ) begin
        {ctl_48, ctl_meta}     <= {ctl_meta, ctl_32};
        {pause_48, pause_meta} <= {pause_meta, menu_32};
    end

    // S1 is active high.
    logic [1:0] s1_sr = 2'b00;
    always_ff @(posedge clkm_48MHZ) s1_sr <= {s1_sr[0], s1};

    // Debounce: s1_db takes the synchronised level only after it has differed from s1_db for
    // 2^S1_DB_BITS consecutive clocks; any bounce back restarts the count.
    //   S1_DB_BITS = $clog2(48 MHz * 10 ms) = $clog2(480000) = 19
    //   -> 2^19 / 48 MHz = 10.9 ms stable time (and press/release latency).
    localparam integer CORE_HZ    = 48_000_000;
    localparam integer S1_DB_BITS = $clog2(CORE_HZ / 100);
    logic [S1_DB_BITS-1:0] s1_cnt = '0;
    logic                  s1_db  = 1'b0;
    always_ff @(posedge clkm_48MHZ) begin
        if (s1_sr[1] == s1_db)
            s1_cnt <= '0;
        else if (&s1_cnt) begin
            s1_db  <= s1_sr[1];
            s1_cnt <= '0;
        end else
            s1_cnt <= s1_cnt + 1'b1;
    end

    // P1CONTROLS is active low in the core (off = 1; MiSTer's Arcade-TaitoSJ.sv passes
    // ~joystick), so idle is all ones. S1 adds coin A (bit 6) and 1P start (bit 7). Bit 11
    // (MiSTer's pause button) and the gun bits 12-15 stay released.
    logic [15:0] p1controls = 16'hFFFF;
    always_ff @(posedge clkm_48MHZ)
        p1controls <= ~{5'b0, ctl_48[10:8], ctl_48[7] | s1_db, ctl_48[6] | s1_db, ctl_48[5:0]};

    // ------------------------------------------------------------------ core
    logic [2:0]  red, green, blue;
    logic        core_pix_clk, hs, vs, hblank, vblank;
    logic signed [15:0] audio_l, audio_r;

    logic [20:0] phase_delta;
    logic        phase_sample;
    logic        vid_hold;

    taitosj_fpga u_core (
        .clkm_48MHZ   (clkm_48MHZ),
        .clkm_32MHZ   (clkm_32MHZ),
        .pcb          (cfg[31:24]),         // e.g. Elevator Action: 04 (bit 2 = MCU fitted)
        .RED          (red),
        .GREEN        (green),
        .BLUE         (blue),
        .core_pix_clk (core_pix_clk),
        .H_SYNC       (hs),
        .V_SYNC       (vs),
        .H_BLANK      (hblank),
        .V_BLANK      (vblank),
        .RESET_n      (core_resetn_48),
        .vid_hold     (vid_hold),
        .pause        (pause_48),
        .P1CONTROLS   (p1controls),
        .DIP1         (cfg[7:0]),
        .DIP2         (cfg[15:8]),
        .DIP3         (cfg[23:16]),
        .DBG_SPR_FIRST(5'd0),
        .DBG_SPR_LAST (5'd31),
        .dn_addr      (dn_addr),
        .dn_wr        (dn_wr),
        .dn_data      (dn_data),
        .audio_l      (audio_l),
        .audio_r      (audio_r),
        .hs_address   (16'h0000),
        .hs_data_out  (),
        .hs_data_in   (8'h00),
        .hs_write     (1'b0),
        .rom_req      (core_rom_req),
        .rom_id       (core_rom_id),
        .rom_addr     (core_rom_addr),
        .rom_q        (core_rom_q),
        .rom_ack      (core_rom_ack)
    );

    // ------------------------------------------------------------------ video
    logic [10:0] cx, frame_width;
    logic [9:0]  cy, frame_height;
    logic [23:0] rgb;
    logic [2:0]  tmds;

    linebuf u_linebuf (
        .clk_cap      (clkm_48MHZ),
        .pix_en       (core_pix_clk),
        .r_in         (red),
        .g_in         (green),
        .b_in         (blue),
        .h_blank      (hblank),
        .v_blank      (vblank),
        .clk_pix      (hclk),
        .cx           (cx),
        .cy           (cy),
        .frame_width  (frame_width),
        .frame_height (frame_height),
        .rgb          (rgb),
        .phase_delta  (phase_delta),
        .phase_sample (phase_sample),
        .overlay      (overlay),
        .osd_strip    (osd_strip),
        .overlay_x    (overlay_x),
        .overlay_y    (overlay_y),
        .overlay_color(overlay_color)
    );

    // One-time phase align, then a fixed 720p frame. The core's pixel enable is
    // exactly 60 Hz, so holding the video phases for this long puts core line 0
    // 400 us before HDMI row 24 and it stays there.
    logic        aligned = 1'b0;
    logic        hold_lvl = 1'b0;
    logic [21:0] hold_h = 22'd0;
    localparam [20:0] PHASE_TARGET = 21'd29700;    // 400 us at 74.25 MHz
    localparam [20:0] PHASE_FRAME  = 21'd1237500;  // one 720p frame
    always_ff @(posedge hclk) begin
        if (phase_sample && !aligned) begin
            aligned <= 1'b1;
            hold_lvl <= 1'b1;
            if (phase_delta > PHASE_TARGET)
                hold_h <= {1'b0, phase_delta} - PHASE_TARGET;
            else
                hold_h <= PHASE_FRAME - PHASE_TARGET + phase_delta;
        end else if (hold_h != 0) begin
            hold_h <= hold_h - 22'd1;
        end else
            hold_lvl <= 1'b0;
    end
    logic [1:0] hold_sync = 2'b00;
    always_ff @(posedge clkm_48MHZ)
        hold_sync <= {hold_sync[0], hold_lvl};
    assign vid_hold = hold_sync[1];


    // ------------------------------------------------------------------ audio
    // 48 kHz timing from 74.25 MHz: toggle clk_audio at 96 kHz with a fractional accumulator
    // (96000 / 74250000 per clock), so clk_audio rises at exactly 48 kHz on average.
    // audio_en_48k is a 1-clock enable on each rising edge of clk_audio; audio_sample_word
    // is updated there. The core's audio (48 MHz domain) is brought over with a 2-flop
    // synchroniser plus a "two reads agree" filter so all 16 bits come from one sample.
    // The two AY groups (audio_l, audio_r) are then mixed to mono and sent on both HDMI
    // channels, as the MiSTer core does (AUDIO_MIX = 3, 100% mix).
    localparam integer HCLK_HZ = 74_250_000;
    logic [31:0] aud_acc;
    wire  [31:0] aud_acc_n = aud_acc + 32'd96000;
    logic        clk_audio, audio_en_48k;

    always_ff @(posedge hclk) begin
        audio_en_48k <= 1'b0;
        if (aud_acc_n >= HCLK_HZ) begin
            aud_acc   <= aud_acc_n - HCLK_HZ;
            clk_audio <= ~clk_audio;
            if (!clk_audio) audio_en_48k <= 1'b1;
        end else
            aud_acc <= aud_acc_n;
    end

    logic [15:0] al_meta, al_s1, al_s2, al_ok;
    logic [15:0] ar_meta, ar_s1, ar_s2, ar_ok;
    always_ff @(posedge hclk) begin
        al_meta <= audio_l; al_s1 <= al_meta; al_s2 <= al_s1; if (al_s1 == al_s2) al_ok <= al_s1;
        ar_meta <= audio_r; ar_s1 <= ar_meta; ar_s2 <= ar_s1; if (ar_s1 == ar_s2) ar_ok <= ar_s1;
    end

    // mono = (L + R) / 2: signed 17-bit sum (sign extended, cannot overflow), then [16:1] is
    // the arithmetic divide by 2, which always fits back in 16 bits.
    wire [16:0] audio_sum  = {al_ok[15], al_ok} + {ar_ok[15], ar_ok};
    wire [15:0] audio_mono = audio_sum[16:1];

    logic [15:0] audio_sample_word [1:0];
    always_ff @(posedge hclk) begin
        if (audio_en_48k) begin
            audio_sample_word[0] <= audio_mono;
            audio_sample_word[1] <= audio_mono;
        end
    end

    // ------------------------------------------------------------------ HDMI
    hdmi #(
        .VIDEO_ID_CODE     (4),
        .DVI_OUTPUT        (0),
        .VIDEO_REFRESH_RATE(60.0),
        .IT_CONTENT        (1),
        .AUDIO_RATE        (48000),
        .AUDIO_BIT_WIDTH   (16),
        .START_X           (0),
        .START_Y           (0)
    ) u_hdmi (
        .clk_pixel_x5      (hclk5),
        .clk_pixel         (hclk),
        .clk_audio         (clk_audio),
        .reset             (1'b0),
        .rgb               (rgb),
        .audio_sample_word (audio_sample_word),
        .volume            (volume),        // iosys master volume, synchronised in hdmi.sv
        .tmds              (tmds),
        .tmds_clock        (),
        .cx                (cx),
        .cy                (cy),
        .frame_width       (frame_width),
        .frame_height      (frame_height),
        .screen_width      (),
        .screen_height     ()
    );

    ELVDS_OBUF tmds_bufds [3:0] (
        .I ({hclk, tmds}),
        .O ({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

    // ------------------------------------------------------------------ LEDs (active low)
    //   led[0] on = a ROM is loaded and the core runs
    //   led[1] on = a ROM is loading, or the last load ended short (core held in reset)
    assign led[0] = ~core_rst_n;
    assign led[1] = ~(loading | short_load);

endmodule
