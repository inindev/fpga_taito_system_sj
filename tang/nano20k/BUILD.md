# Taito System SJ on the Sipeed Tang Nano 20K

A port of the MiSTer Taito System SJ core to the Sipeed Tang Nano 20K (GW2AR-LV18QN88C8/I7),
as a [TangCore](https://github.com/nand2mario/tangcore) core. The TangCore BL616 firmware loads
the core from the USB drive, shows the menu and sends the game's ROMs to the core over its UART.
Video and sound go out over the HDMI port at 1280x720, 60 Hz.

## Status

- Elevator Action runs on the board, with picture and sound over HDMI.
- The core is set up for Elevator Action only. Other games are untested.

## Files

All under `tang/nano20k/` unless noted.

| File | Purpose |
|---|---|
| `build.tcl` (repository root) | `gw_sh` build script |
| `top.sv` | Top level: PLLs, iosys, ROM loading, SDRAM arbiter, core, gamepads, video, audio, HDMI, LEDs |
| `rom_stream.sv` | Writes the ROM image from the firmware into SDRAM and the core's small on-chip ROMs |
| `sdram.v` | Controller for the GW2AR's embedded 8 MB SDRAM (32 MHz, one access at a time) |
| `linebuf.sv` | 32-line video ring buffer, 5x/3x scaling to 1280x720, menu overlay |
| `gowin_pll_game.v` | Game PLL: 27 MHz in, 48 MHz and 32 MHz out |
| `gowin_pll_hdmi.v` | HDMI PLL: 27 MHz in, 371.25 MHz out (divided by 5 to 74.25 MHz in `top.sv`) |
| `nano20k.cst` | Pin constraints (clock, S1, LEDs, HDMI, UART, gamepads). The SDRAM is placed by the tool |
| `sj.sdc` | Timing constraints |
| `iosys/` | TangCore IO system: `iosys_bl616.v`, `textdisp.v`, `uart_fixed.v` (copies of `fpga_tangcore/common/iosys`, kept in step by `scripts/sync_common.sh`) and `gowin_dpb_menu.v` (menu font and this core's logo, written by `scripts/font_glyphs.py`) |
| `controller_snes.v`, `controller_ds2.sv`, `dualshock_controller.v` | SNES and DualShock pads on the board's pins, from TangCore's nestang |
| `hdmi/` | HDMI encoder from hdl-util by Sameer Puri, MIT OR Apache-2.0 (licence files in `hdmi/`). Local changes are listed at the top of `hdmi/hdmi.sv` |
| `rtl/dpram_dc.v` | Dual-port RAM for the core, written so Gowin can map it to block RAM |

The core itself is in `rtl/`. The Z80 (T80) and AY-3-8910 (JT49) sources are in `modules/`.

## Build

You need the Gowin IDE or its command-line `gw_sh`, version 1.9.11.03. The Education edition
works. From the repository root:

```sh
/path/to/gowin/IDE/bin/gw_sh build.tcl nano20k
```

The core is written to `impl/pnr/taitosj_nano20k.bin` (and `.fs`). Reports are in
`impl/gwsynthesis/` and `impl/pnr/`.

On a Linux machine without a display, `gw_sh` can fail to start with a Qt "xcb" error. Set
`QT_QPA_PLATFORM=offscreen` before running it.

`sj.sdc` declares the four real clocks (27 MHz input, 48 and 32 MHz game, 74.25 MHz HDMI).
Without it the tool times the core's gated signals as 100 MHz clocks and the 48 MHz clock
fails. It also has `set_false_path -to [get_regs {*_meta*}]`: a register named `*_meta` is the
first flop of a synchroniser (iosys's UART input, the gamepad and menu state into the 48 MHz
clock, the menu state and audio into the HDMI clock). Gowin uses only one `.sdc`, so the line
is in this one. Check `impl/pnr/taitosj_nano20k_tr_content.html` ("Max Frequency Summary")
after a change.

The report still lists failing paths between the 32 and 48 MHz clocks and from the core's
CPU write strobes (gated clocks such as `SOFF`, `EXRHR`). These come from the original core:
CPU bus signals that are stable for many cycles, timed by the tool as single-cycle paths.

The design must not depend on placement. Two things here exist for that reason, keep them
when changing the code:

- `build.tcl` puts registers that connect straight to a pin into the I/O blocks
  (`-ireg_in_iob`, `-oreg_in_iob`, `-ioreg_in_iob`). `sdram.v` registers the 32-bit DQ bus
  with nothing in front of the register, and `top.sv` drives the SDRAM clock from an ODDR.
  Without this, some placements read bad bytes from SDRAM (white screen or stray sprite
  pixels).
- The CPU ports of the video RAMs (graphics planes, tile map, scroll, colour) and the OBJ
  RAM run on the 48 MHz clock, the same as the video read ports, with one-cycle write
  pulses (`wr_pulse` in `rtl/TaitoSJ_ram.v`). A block RAM with two clocks can return a bad
  byte when both ports hit the same address on close edges.

A quick check after a change: build with `-place_option` 0, 1 and 2 (`build.tcl` uses 2) and
run the demo on each. All three should be free of stray pixels.

## Installing on the TangCore USB drive

| Path on the drive | What |
|---|---|
| `cores/nano20k/taitosj.bin` | The core: `impl/pnr/taitosj_nano20k.bin` renamed |
| `arcade/*.mra` | The games: the `.mra` files from `releases/` (and, if you want them, `releases/_alt/` as `arcade/_alt/`) |
| `arcade/mame/elevator.zip` | Your MAME ROM sets, e.g. Elevator Action |

ROMs are not included. You need your own MAME ROM set for each game, named as in the MRA's
`<rom zip=...>`. The main menu's "Arcade" entry lists `arcade/`; choose a game's `.mra`. As
on MiSTer, the firmware reads the MRA (`<rbf>TaitoSJ</rbf>` selects this core), builds the ROM
image from the zip (the ROM files in the order the MRA gives, with its padding), and sends it
to the core together with the MRA's DIP switch defaults and PCB byte.

## ROM loading

The core is TangCore core ID 7. `iosys_bl616` receives the firmware's commands over the UART
(2 Mbaud) and hands the ROM image to `rom_stream.sv` byte by byte, from image offset 0, between
`rom_loading` going 0 -> 1 and 1 -> 0. Image layout (offset):

| Offset | Size | Contents | Goes to |
|---|---|---|---|
| 0x00000 | 32 KB | Main CPU program | SDRAM |
| 0x08000 | 32 KB | Main CPU program, banked | SDRAM |
| 0x10000 | 32 KB | Graphics | SDRAM |
| 0x18000 | 16 KB | Sound CPU program (8 KB of ROM and 8 KB of padding for Elevator Action) | SDRAM |
| 0x1C000 | 256 B | Layer PROM | block RAM (`dn_*` port) |
| 0x1C100 | 1792 B | Padding | (overwritten) |
| 0x1C800 | 2 KB | MCU ROM | block RAM |
| 0x1D000 | 4 KB | Extra ROM (only some games, e.g. Front Line) | block RAM |

For Elevator Action the image is 0x1D000 bytes (118784), about 0.6 s at 2 Mbaud. Bytes from
0x1E000 on are ignored. The core is held in reset from power-up until a load has ended with at
least 0x1D000 bytes, and again during every new load. `rom_stream.sv` and `rtl/rom_loader.sv`
have the details.

The firmware also sends a 32-bit core configuration (iosys `core_config`), which the core uses
as: bits 7-0 DIP1, 15-8 DIP2, 23-16 DIP3 (MRA switch bytes 1, 2 and 3), 31-24 the PCB byte (the
value in `<rom index="1">` of the MRA: Elevator Action 04, Front Line 05). For Elevator Action
the MRA defaults are DIP 7F, 00, FF: upright cabinet, 1 coin 1 credit. The meaning of each bit
is in the `<switches>` block of the game's MRA.

## Controls

Gamepads: USB gamepads through the BL616 firmware, and SNES and DualShock pads on the pins
TangCore's nestang uses. The board has one set of player controls (the second
player of an alternating game uses the same ones), so pad 1 and pad 2 both drive it.

| Pad | Game |
|---|---|
| D-pad | Joystick (8 ways) |
| B or Y | Fire (button 1) |
| A or X | Jump (button 2) |
| SELECT | Coin |
| START on pad 1 | 1P start |
| START on pad 2, or R on either pad | 2P start |
| Board button S1 | Coin and 1P start together (debounced, about 11 ms) |

The firmware opens its menu with the key combination chosen in its options. While the menu is
shown the game is paused and gets no buttons.
The volume (firmware options) sets the HDMI audio level.

## LEDs

Both LEDs are active low (on when the pin is driven low).

| LED | On means |
|---|---|
| LED0 (pin 15) | A ROM is loaded and the core is running |
| LED1 (pin 16) | A ROM is loading, or the last load ended with fewer than 0x1D000 bytes (the core stays in reset) |

## Other games

The core takes the DIP switches and the PCB byte from the firmware, so the image layout above
is the same for every game; a game with an extra ROM sends 0x1E000 bytes. None of the other
games have been tried. The firmware loads any of the MRAs in `releases/`, given its zip. Vertical
games such as Front Line are not rotated.

## How it works

**ROMs.** While the core is in reset, `rom_stream.sv` writes the main, banked, graphics and
sound ROMs into SDRAM as the bytes arrive, and the layer PROM, MCU ROM and extra ROM into block
RAM through the core's `dn_*` download port. The large ROMs do not fit in the GW2AR-18's block
RAM next to the core. When the core runs, `rom_ext_arb` in `rtl/rom_loader.sv` fetches ROM
bytes from SDRAM one at a time, with a one-byte cache. The main and sound Z80s are held with
`WAIT_n` until their byte arrives.

**Video.** The original board runs at 6 MHz pixel clock, 384 x 264 pixels per frame, which is
59.19 Hz. A full frame buffer does not fit in block RAM, so the core is retimed to exactly
60 Hz instead: on the 48 MHz clock most pixels take 8 clocks and 43 of every 396 take 7, which
gives 6.08256 MHz (`pixph`/`pacc` in `rtl/TaitoSJCore.v`). That matches 720p60 exactly, so the
core's frame keeps a fixed phase against the HDMI frame. After the first frame, `top.sv` holds
the core's video timing once (`vid_hold`) so that core line 0 starts 400 us before HDMI picture
row 24. From then on a 32-line ring buffer (`linebuf.sv`) is enough. Each pixel is shown 5 times
across and each line 3 times down, so the 256 x 224 picture fills 1280 x 672, with black bars
of 24 lines at the top and bottom.

The trade-off: the game runs about 1.4% faster than on the original board (60 Hz instead of
59.19 Hz). The sound chip clocks are not changed.

**Menu.** The firmware's menu (iosys `textdisp`, 256 x 224 pixels) is drawn on the same grid as
the game, 5x across and 3x down, over the game dimmed to a quarter. The volume bar is a strip
of it over the running game, as in the other TangCore cores.

**Audio.** The two AY-3-8910 groups from the core are mixed to mono and sent on both HDMI audio
channels at 48 kHz, 16 bit, as the MiSTer core does with its 100% mix setting, then scaled by
the firmware's master volume in `hdmi.sv`.

**Clocks.** 48 MHz and 32 MHz for the core (32 MHz also for SDRAM, ROM loading, iosys and the
gamepads), 74.25 MHz and 371.25 MHz for HDMI. The main Z80 runs on the 32 MHz clock; the
video, sound and the CPU write ports of the video RAMs run on 48 MHz.

**SDRAM.** One access at a time, CAS latency 2, auto precharge, 5 clocks per access at
32 MHz. Read data is taken from I/O block registers and the byte is selected one clock later.

## Known limitations

- Only Elevator Action has been tried. Other games are untested.
- No screen rotation for vertical games.
- No high score saving.
- Game speed is about 1.4% above the original (see "Video").
