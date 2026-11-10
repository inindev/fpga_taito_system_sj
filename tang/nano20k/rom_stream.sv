// rom_stream.sv - ROM image loader for the Taito System SJ Tang Nano 20K port (TangCore).
//
// The TangCore BL616 firmware reads the game's ROM zip from the USB drive, builds the image a
// MiSTer MRA builds and sends it over the UART. iosys_bl616 hands it over byte by byte:
// rom_loading goes 0 -> 1, then every image byte comes as rom_do with a one-clock rom_do_valid
// (offset 0 first), then rom_loading goes 1 -> 0. iosys passes every byte of the stream
// unchanged (no header is stripped). Byte n of the image is handled as follows:
//
//   * n < 0x1C000 (main 32K, bank 32K, gfx 32K, sound 16K) is written byte by byte into the
//     8 MB SDRAM through the sdram.v host port;
//   * 0x1C000 <= n < 0x1E000 (layer PROM, MCU ROM, extra ROM) is written into the core's small
//     on-chip ROMs through the core's existing dn_addr/dn_data/dn_wr port, with dn_addr = n;
//   * bytes from 0x1E000 on are ignored (nothing in the core is there).
//
// The core is held in reset (top.sv) from the start of a load until `loaded`.
//
// ---------------------------------------------------------------------------------------
// ROM image layout: MRA order, i.e. the image a MiSTer MRA builds (see releases/*.mra and the
// layout comment at the top of rtl/rom_loader.sv). Image offset = MiSTer ioctl address.
//
//   0x00000 + 0x8000  eprom_0   main CPU         -> SDRAM id 0
//   0x08000 + 0x8000  eprom_1   banked CPU       -> SDRAM id 1
//   0x10000 + 0x8000  eprom_2   graphics         -> SDRAM id 2
//   0x18000 + 0x4000  eprom_3   sound            -> SDRAM id 3
//   0x1C000 + 0x0100  eprom_4   layer PROM       -> dn_*
//   0x1C100 + 0x0700  padding                    -> dn_* (lands in eprom_mcu, overwritten below)
//   0x1C800 + 0x0800  eprom_mcu MCU ROM          -> dn_*
//   0x1D000 + 0x1000  extra_rom                  -> dn_* (only some games, e.g. Front Line)
//
// Elevator Action sends 0x1D000 bytes, games with an extra ROM 0x1E000.
//
// SDRAM physical map: ids 0..3 sit at the same addresses as in the image. id 3 is at
// ID3_BASE = 0x18000 because eprom_2 is 32 KB (widthad_a(15) in rom_loader.sv, 15-bit
// EXT_ROM_ADDR in TaitoSJCore.v), so 0x10000..0x17FFF belongs to id 2. top.sv uses the same
// base (BASE_ID3) for the read side so both agree.
//
// ---------------------------------------------------------------------------------------
// dn_* windows for the small ROMs, as decoded by the selector module in rtl/rom_loader.sv:
//
//     ioctl_addr < 0x1C000        nothing selected (eprom_0..eprom_3 live in SDRAM)
//     ioctl_addr < 0x1C100        ep4_cs  eprom_4 (layer PROM), index = ioctl_addr[7:0]
//     ioctl_addr < 0x1D000        ep5_cs  eprom_mcu, index = ioctl_addr[10:0]
//     otherwise                   ep6_cs  extra_rom, index = ioctl_addr[11:0]
//
// eprom_mcu's byte 0 is therefore at 0x1C800 (low 11 bits 0), which is where the MRA puts it.
//
// ---------------------------------------------------------------------------------------
// Timing: at 2 Mbaud a byte arrives at most every 5 us (160 clocks at 32 MHz). Handling one
// takes at most about 20 clocks (an SDRAM write, waiting out a refresh, or a dn_* write), so
// one byte of buffer is enough.
//
// dn_* are produced in the clk (32 MHz) domain. dn_wr is held for 8 clk cycles with
// dn_addr/dn_data stable 2 cycles before and 4 cycles after, so top.sv can bring them to
// the core's 48 MHz domain with plain synchronisers. The core is in reset meanwhile.
//
// `loaded` is 1 once a load has ended (rom_loading 1 -> 0) with at least MIN_SIZE bytes and
// everything written; it drops when the next load starts. `short_load` is 1 when the last
// load ended with fewer bytes (the core then stays in reset).

module rom_stream #(
    parameter [22:0]   ID3_BASE = 23'h18000,
    parameter [17:0]   MIN_SIZE = 18'h1D000     // smallest image that runs (no extra ROM)
) (
    input  logic        clk,            // clkm_32MHZ, the iosys_bl616 clock
    input  logic        resetn,         // system reset (top.sv), released once after power-up

    // from iosys_bl616
    input  logic        loading,        // rom_loading != 0
    input  logic [7:0]  rom_do,
    input  logic        rom_do_valid,

    // SDRAM host port (write only)
    output logic        sd_wr,
    output logic [22:0] sd_addr,
    output logic [7:0]  sd_din,
    input  logic        sd_busy,

    // core download port
    output logic [24:0] dn_addr,
    output logic [7:0]  dn_data,
    output logic        dn_wr,

    output logic        loaded,
    output logic        short_load
);

    localparam [17:0] SDRAM_END = 18'h1C000;      // below: SDRAM, from here: small ROMs
    localparam [17:0] IMAGE_END = 18'h1E000;      // from here: ignored

    typedef enum logic [1:0] { S_IDLE, S_PUT, S_SD_END, S_DN } state_t;
    state_t state;

    logic        loading_r;
    logic [17:0] n;                 // index of the next byte to arrive (saturates)
    logic [17:0] idx;               // index of the byte being handled
    logic [7:0]  rx;
    logic        full;              // rx holds a byte not yet handled
    logic [3:0]  dn_cnt;

    // image index -> SDRAM byte address (only valid for idx < 0x1C000)
    function automatic [22:0] sdram_phys(input [17:0] i);
        if (i < 18'h18000) sdram_phys = {5'b0, i};
        else               sdram_phys = ID3_BASE + {5'b0, i - 18'h18000};
    endfunction

    always_ff @(posedge clk) begin
        sd_wr     <= 1'b0;
        loading_r <= loading;

        if (!resetn) begin
            state      <= S_IDLE;
            loading_r  <= 1'b0;
            n          <= '0;
            full       <= 1'b0;
            dn_wr      <= 1'b0;
            dn_addr    <= '0;
            dn_data    <= '0;
            loaded     <= 1'b0;
            short_load <= 1'b0;
        end else begin
            // end of a load, once the last byte is written
            if (!loading && loading_r) begin
                short_load <= n < MIN_SIZE;
            end
            if (!loading && !loading_r && state == S_IDLE && !full && n != 0 && !short_load)
                loaded <= 1'b1;

            case (state)
            S_IDLE: if (full) state <= S_PUT;

            // route byte idx to its destination
            S_PUT: begin
                if (idx >= IMAGE_END) begin
                    full  <= 1'b0;
                    state <= S_IDLE;
                end else if (idx < SDRAM_END) begin
                    if (!sd_busy) begin
                        sd_wr   <= 1'b1;
                        sd_addr <= sdram_phys(idx);
                        sd_din  <= rx;
                        state   <= S_SD_END;
                    end
                end else begin
                    dn_addr <= {7'b0, idx};         // image offset = ioctl address
                    dn_data <= rx;
                    dn_cnt  <= '0;
                    state   <= S_DN;
                end
            end

            // sd_wr is a registered pulse (default 0 above); one idle cycle, then done
            S_SD_END: begin
                full  <= 1'b0;
                state <= S_IDLE;
            end

            // dn_addr/dn_data stable for 2 clks, dn_wr for 8, then 4 more stable clks
            S_DN: begin
                dn_cnt <= dn_cnt + 1'b1;
                if (dn_cnt == 4'd1)  dn_wr <= 1'b1;
                if (dn_cnt == 4'd9)  dn_wr <= 1'b0;
                if (dn_cnt == 4'd13) begin
                    full  <= 1'b0;
                    state <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
            endcase

            // After the state machine, so that a byte arriving as the previous one finishes
            // is kept. Start of a load: restart at image offset 0, the core goes back into reset.
            if (loading && !loading_r) begin
                n      <= '0;
                full   <= 1'b0;
                loaded <= 1'b0;
            end else if (rom_do_valid && loading) begin
                rx   <= rom_do;
                idx  <= n;
                full <= 1'b1;
                if (n != 18'h3FFFF) n <= n + 1'b1;
            end
        end
    end

endmodule
