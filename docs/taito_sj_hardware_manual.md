# Taito System SJ Hardware Reference Manual

**Version:** 0.1 (draft)
**Audience:** Developers targeting original Taito System SJ arcade hardware or emulated/FPGA implementations

---

## Table of Contents

1. [Overview](#1-overview)
2. [CPU and Clock](#2-cpu-and-clock)
3. [Memory Map](#3-memory-map)
4. [VRAM and Tile System](#4-vram-and-tile-system)
5. [Tilemap Layers](#5-tilemap-layers)
6. [Palette System](#6-palette-system)
7. [Scroll Registers](#7-scroll-registers)
8. [Column Scroll](#8-column-scroll)
9. [Hardware Control Registers](#9-hardware-control-registers)
10. [Input Registers](#10-input-registers)
11. [Sound – AY-3-8910](#11-sound--ay-3-8910)
12. [Sprites](#12-sprites)
13. [Watchdog](#13-watchdog)
14. [MCU Communication](#14-mcu-communication)

---

## 1. Overview

The Taito System SJ is a Z80-based arcade hardware platform used by Taito Corporation from 1981 to 1984. It features a tile-based display system with three independently scrollable tilemap layers, a three-bitplane colour system with a 9-bit RGB palette, hardware sprites with collision detection, and AY-3-8910 sound.

### Sound Hardware

The system uses a total of four AY-3-8910 sound chips — one on the main board driven directly by the main Z80, and three on a dedicated sound board with its own Z80 processor and 16KB of ROM. This provides 12 independent sound channels.

### Games

The following titles ran on the Taito System SJ hardware:

| Year | Title | Notes |
|------|-------|-------|
| 1981 | Space Seeker | |
| 1981 | Space Cruiser | |
| 1982 | Jungle King / Jungle Hunt | Released as Jungle King in Japan, Jungle Hunt in the US |
| 1982 | Pirate Pete | US variant of Jungle Hunt |
| 1982 | Alpine Ski | |
| 1982 | Adventure Canoe | |
| 1982 | Time Tunnel | |
| 1982 | Wild Western | |
| 1982 | Front Line | Uses MC68705 MCU |
| 1983 | Elevator Action | Uses MC68705 MCU |
| 1983 | The Tin Star | Uses MC68705 MCU |
| 1983 | Water Ski | |
| 1983 | Bio Attack | |
| 1983 | High Way Race | |
| 1984 | Sea Fighter Poseidon | Uses MC68705 MCU |
| 1984 | Kick Start: Wheelie King | Uses MC68705 MCU; only game to use SCRAM |

---

## 2. CPU and Clock

### Main CPU

- **CPU:** Zilog Z80A @ 4MHz
- **Interrupts:** Mode 1 (`IM 1`) — INT vector fixed at `$0038`
- **Interrupt frequency:** Once per video frame (approximately 60Hz)
- **Watchdog:** Must be serviced every frame or hardware resets

### Sound CPU

- **CPU:** Zilog Z80A @ 3MHz
- **Program:** Dedicated sound ROM (`$0000–$3FFF`)

---

## 3. Memory Map

| Lower   | Upper   | Size | Description |
|---------|---------|------|-------------|
| `$0000` | `$7FFF` | 32KB | Program ROM |
| `$8000` | `$87FF` | 2KB | Work RAM |
| `$8800` | `$8FFF` | 2KB | MCU communication area (see MCU section) |
| `$9000` | `$97FF` | 2KB | VRAM bitplane 0, bank 0 (tiles 0–255) |
| `$9800` | `$9FFF` | 2KB | VRAM bitplane 1, bank 0 (tiles 0–255) |
| `$A000` | `$A7FF` | 2KB | VRAM bitplane 2, bank 0 (tiles 0–255) |
| `$A800` | `$AFFF` | 2KB | VRAM bitplane 0, bank 1 (tiles 256–511) |
| `$B000` | `$B7FF` | 2KB | VRAM bitplane 1, bank 1 (tiles 256–511) |
| `$B800` | `$BFFF` | 2KB | VRAM bitplane 2, bank 1 (tiles 256–511) |
| `$C000` | `$C3FF` | 1KB | General purpose R/W RAM (used by some games for sprite collision data) |
| `$C400` | `$CFFF` | 3KB | Tilemap RAM (3 layers × 1KB) |
| `$D000` | `$D05F` | 96B | Column scroll RAM (SCRRQ) — 32 bytes per tilemap |
| `$D060` | `$D0FF` | 160B | Unused |
| `$D100` | `$D1FF` | 256B | Sprite RAM (64 sprites × 4 bytes) |
| `$D200` | `$D27F` | 128B | Palette RAM (64 entries × 2 bytes) |
| `$D300` |         | 1B | PRIORITY — layer priority register |
| `$D400` | `$D403` | 4B | Hit bus read registers |
| `$D404` | `$D407` | 4B | EXRHR — external ROM data read (auto-incrementing) |
| `$D408` | `$D40D` | 6B | Input registers |
| `$D40E` | `$D40F` | 2B | AY-3-8910 #0 register access |
| `$D500` |         | 1B | SPH1 — tilemap 1 horizontal scroll |
| `$D501` |         | 1B | SPV1 — tilemap 1 vertical scroll |
| `$D502` |         | 1B | SPH2 — tilemap 2 horizontal scroll |
| `$D503` |         | 1B | SPV2 — tilemap 2 vertical scroll |
| `$D504` |         | 1B | SPH3 — tilemap 3 horizontal scroll |
| `$D505` |         | 1B | SPV3 — tilemap 3 vertical scroll |
| `$D506` |         | 1B | SMD12 — tilemap 1 and 2 mode register |
| `$D507` |         | 1B | SMD3 — tilemap 3 and sprite mode register |
| `$D508` |         | 1B | HTCLR — hit bus clear |
| `$D509` |         | 1B | EXROM1 — external ROM address low byte |
| `$D50A` |         | 1B | EXROM2 — external ROM address high byte |
| `$D50B` |         | 1B | EPORT2 — single bit signal to sound CPU |
| `$D50C` |         | 1B | EPORT1 — sound command register |
| `$D50D` |         | 1B | TIME RESET — watchdog |
| `$D50E` |         | 1B | COIN LOCK / SOUND STOP / BANK SEL |
| `$D50F` |         | 1B | EXPORT — to priority PAL |
| `$D600` |         | 1B | SOFF — display control register |
| `$D800` | `$DFFF` | 2KB | SCRAM — additional RAM (Kick Start: Wheelie King only) |

> **Note:** VRAM is write-only from the Z80. Reads from VRAM are not supported. Work RAM (`$8000–$87FF`) is confirmed readable and writable on all revisions.

---

## 4. VRAM and Tile System

### Bitplanes

VRAM is organised as three independent bitplanes. Each bitplane stores one bit per pixel for each tile. For a given pixel in a given tile, the three bitplane bits combine to form a 3-bit colour index (0–7) that selects a palette entry.

Each tile is 8×8 pixels. One tile in one bitplane occupies 8 bytes (one byte per row, one bit per pixel).

**Tile address formula:**

```
bitplane_base + (tile_index × 8) + row
```

| Bitplane | Bank 0 base | Bank 1 base |
|----------|-------------|-------------|
| Plane 0 | `$9000` | `$A800` |
| Plane 1 | `$9800` | `$B000` |
| Plane 2 | `$A000` | `$B800` |

### Tile Banks

- **Bank 0:** Tiles 0–255 (`$xx00–$xxFF` × 8)
- **Bank 1:** Tiles 256–511 — only present on hardware revisions with the additional VRAM

### Tile Index to VRAM Address

To load tile N in a given bitplane:

```
address = plane_base + (N × 8)
```

Example: tile 10, bitplane 0 → `$9000 + (10 × 8)` = `$9050`

---

## 5. Tilemap Layers

The System SJ has three independently scrollable tilemap layers, each 32×32 tiles (256×256 pixels).

| Layer | Tilemap base | Default use |
|-------|-------------|-------------|
| 1 | `$C400` | Background / overlay (SMD12 lower nibble) |
| 2 | `$C800` | Foreground / text (SMD12 upper nibble) |
| 3 | `$CC00` | Foreground / text (SMD3 lower nibble) |

> **Note:** `$C000–$C3FF` is confirmed R/W on all hardware revisions. Some games (e.g. Bio Attack) use this region for sprite collision detection data.

Each tilemap entry is a single byte — the tile index to display at that position. The tilemap is laid out as 32 consecutive bytes per row, 32 rows (1024 bytes total per layer).

**Tilemap address formula:**

```
layer_base + (row × 32) + column
```

---

## 6. Palette System

### Overview

The palette contains 64 entries, each 16 bits (2 bytes), stored at `$D200–$D27F`. Each entry encodes the actual display colour for one palette index.

### Colour Selection

For each pixel, the display hardware combines two values to select a palette entry:

- **MDx** — 3-bit palette bank for the active tilemap layer (x = 1, 2 or 3), set via SMD12 or SMD3
- **SNx** — 3-bit colour index formed from the three bitplane pixel values at that position (x = 1, 2 or 3)

The resulting 6-bit value selects one of the 64 palette entries:

```
palette_index = { MDx[2:0], SNx[2:0] }
```

Each tilemap layer has its own independent MDx value, so each layer can use a different group of 8 palette entries simultaneously.

### SNx Bit Values

The three bitplane values at each pixel form SNx:

| SNx | Plane 2 bit | Plane 1 bit | Plane 0 bit |
|-----|-------------|-------------|-------------|
| 0 | 0 | 0 | 0 |
| 1 | 0 | 0 | 1 |
| 2 | 0 | 1 | 0 |
| 3 | 0 | 1 | 1 |
| 4 | 1 | 0 | 0 |
| 5 | 1 | 0 | 1 |
| 6 | 1 | 1 | 0 |
| 7 | 1 | 1 | 1 |

SNx=0 (all bitplanes zero) is transparent. The 7 non-zero values select 7 distinct palette entries under the current MDx setting.

### SMD12 Register (`$D506`)

Sets MD1 (tilemap 1) and MD2 (tilemap 2) palette banks. See [SMD12](#smd12-d506) in the Hardware Control Registers section for the full bit decode.

Example: `SMD12 = $25` → MD1 = 5, MD2 = 2 → tilemap 1 uses palette entries 40–47, tilemap 2 uses entries 16–23.

### Palette Entry Format

Each palette entry occupies 2 bytes in the CPU address space but the palette RAM (93419 chip) is only 9 bits wide. The 9 bits are written as follows:

| Byte | Address | Bits used | Description |
|------|---------|-----------|-------------|
| Low  | even    | D7:D0 | Lower 8 bits of palette entry |
| High | odd     | D0 only | Bit 8 of palette entry (upper bit) |

The 9 bits encode RGB intensity as three 3-bit fields:

| Bits | Field | Intensity levels |
|------|-------|-----------------|
| 2:0 | Blue  | 0–7 |
| 5:3 | Green | 0–7 |
| 8:6 | Red   | 0–7 |

Each channel has 8 intensity levels (0 = off, 7 = full brightness). When writing a palette entry, write the low byte first (bits 7:0 = Green bits 2:0 and Blue bits 2:0) then the high byte (bit 0 only = Red bit 2).

---

## 7. Scroll Registers

Each layer has independent horizontal and vertical scroll registers.

| Register | Address | Layer |
|----------|---------|-------|
| SPH1 | `$D500` | Layer 1 horizontal |
| SPV1 | `$D501` | Layer 1 vertical |
| SPH2 | `$D502` | Layer 2 horizontal |
| SPV2 | `$D503` | Layer 2 vertical |
| SPH3 | `$D504` | Layer 3 horizontal |
| SPV3 | `$D505` | Layer 3 vertical |

> **Note:** Only layers 1–3 have confirmed scroll registers. The function of any registers for `$C000` is unknown.

### Scroll Register Format

Each scroll register is one byte:

| Bits | Description |
|------|-------------|
| 7:3 | Coarse scroll (tile position, 5 bits) |
| 2:0 | Fine scroll (pixel offset within tile, 3 bits) |


---

## 8. Column Scroll

The column scroll RAM at `$D000–$D0FF` (256 bytes, control signal: SCRRQ) provides per-column vertical scrolling of the tilemap layers.

Each byte specifies a vertical pixel offset for one 8-pixel-wide column of the display. With a 256-pixel-wide display there are 32 columns, so only 32 of the 256 bytes are used (one per column).

| RAM offset | Column | Display X pixels |
|------------|--------|-----------------|
| `$D000` | 0 | 0–7 |
| `$D001` | 1 | 8–15 |
| `$D002` | 2 | 16–23 |
| … | … | … |
| `$D01F` | 31 | 248–255 |

The RAM is organised as 32 bytes per tilemap layer, one byte per 8-pixel-wide column:

| Range | Tilemap |
|-------|---------|
| `$D000–$D01F` | Tilemap 1 (layer 1, `$C400`) |
| `$D020–$D03F` | Tilemap 2 (layer 2, `$C800`) |
| `$D040–$D05F` | Tilemap 3 (layer 3, `$CC00`) |
| `$D060–$D0FF` | Unused |

Each byte is a vertical pixel offset for the corresponding column of that tilemap. Writing N to an entry shifts that column vertically by N pixels. The three tilemaps are controlled independently, allowing different ripple effects on each layer simultaneously.

## 9. Hardware Control Registers

### SOFF — Display Control (`$D600`)

Controls sprite and tilemap layer visibility and global display flip.

| Bit | Name | Description |
|-----|------|-------------|
| 7 | OBJOFF | 1 = sprites enabled, 0 = sprites disabled |
| 6 | SN3OFF | 1 = tilemap 3 enabled, 0 = disabled |
| 5 | SN2OFF | 1 = tilemap 2 enabled, 0 = disabled |
| 4 | SN1OFF | 1 = tilemap 1 enabled, 0 = disabled |
| 3 | — | Unused |
| 2 | OBJEX | Sprite RAM bank select (0 = bank 0, 1 = bank 1) |
| 1 | VINV | Global vertical flip |
| 0 | HINV | Global horizontal flip |

Setting `SOFF = $F0` enables all layers and sprites with no flip.

### PRIORITY — Layer Priority (`$D300`)

5-bit register (bits 4:0) that feeds a 256×4 priority PROM. The PROM determines which layer is displayed at each pixel based on which layers are active (non-transparent) at that position.

Bits 0–3 of PRY address bits A4–A7 of the PROM. Bit 4 selects between the two output bits. Address bits A0–A3 are driven by a mask of inactive layers in order OBJ–SCN1–SCN2–SCN3. The 2-bit PROM output selects which layer to display.

### SMD12 (`$D506`)

Controls palette bank and VRAM bank selection independently for tilemaps 1 and 2. The register is split into two nibbles:

| Bit | Name | Description |
|-----|------|-------------|
| 0 | MD11 | Palette bank bit 0 for tilemap 1 (layer 1, `$C400`) |
| 1 | MD12 | Palette bank bit 1 for tilemap 1 |
| 2 | MD13 | Palette bank bit 2 for tilemap 1 |
| 3 | CCH1 | VRAM bank for tilemap 1 (0 = bank 0 tiles 0–255, 1 = bank 1 tiles 256–511) |
| 4 | MD21 | Palette bank bit 0 for tilemap 2 (layer 2, `$C800`) |
| 5 | MD22 | Palette bank bit 1 for tilemap 2 |
| 6 | MD23 | Palette bank bit 2 for tilemap 2 |
| 7 | CCH2 | VRAM bank for tilemap 2 (0 = bank 0, 1 = bank 1) |

The 3-bit MD1x field for each tilemap combines with the 3-bit SN1 pixel value to form the 6-bit palette index (see [Palette System](#6-palette-system)).

**Example:** `SMD12 = $25` = `0010 0101`
- Tilemap 1: MD11–MD13 = 5, CCH1 = 0 (palette bank 5, VRAM bank 0)
- Tilemap 2: MD21–MD23 = 2, CCH2 = 0 (palette bank 2, VRAM bank 0)

### SMD3 (`$D507`)

Controls palette bank and VRAM bank for tilemap 3, and the palette bank for sprites.

| Bit | Name | Description |
|-----|------|-------------|
| 0 | MD31 | Palette bank bit 0 for tilemap 3 (layer 3, `$CC00`) |
| 1 | MD32 | Palette bank bit 1 for tilemap 3 |
| 2 | MD33 | Palette bank bit 2 for tilemap 3 |
| 3 | CCH3 | VRAM bank for tilemap 3 (0 = bank 0, 1 = bank 1) |
| 4 | MD01 | Sprite palette bank bit 0 |
| 5 | MD02 | Sprite palette bank bit 1 |
| 7:6 | — | Unused |

Unlike tilemaps which use 3-bit colour data (SN1), sprites use **4-bit colour data**, giving 16 palette entries per sprite. The 2-bit MD0x field combines with the sprite's 4-bit colour value to form the full 6-bit palette index:

```
sprite_palette_index = { MD02, MD01, sprite_4bit_colour }
```

This selects one of 64 palette entries — the same palette RAM used by the tilemaps.

**Example:** `SMD3 = $04` = `0000 0100`
- Tilemap 3: MD31–MD33 = 4, CCH3 = 0 (palette bank 4, VRAM bank 0)
- Sprites: MD01–MD02 = 0 (sprite colours map to palette entries 0–15)

### HTCLR (`$D508`)

Writing to this register clears and resets the **hit bus** — the hardware collision detection system between tilemap layers and sprites. All four hit registers are reset to `$00` simultaneously.

### Hit Bus

The hit bus provides hardware collision detection between the three tilemap layers (SCN1–SCN3) and sprites (OBJ). It operates at pixel level during active display and accumulates results into four read-back registers.

#### Hit Registers (read via `ADDR_ED[1:0]`)

| ADDR_ED[1:0] | Register | Description |
|------|----------|-------------|
| `%00` | H0X | Layer 1 (SCN1) horizontal hit columns |
| `%01` | H1X | Layer 2 (SCN2) horizontal hit columns |
| `%10` | H2X | Layer 3 (SCN3) horizontal hit columns |
| `%11` | HOBJ | Layer/sprite collision flags |

#### H0X, H1X, H2X — Sprite Collision Registers

Each register is an 8-bit mask indicating which sprites within a group of 8 have collided with a previous sprite. Bit N set means sprite N within that group collided.

| Register | Address | Sprites covered |
|----------|---------|-----------------|
| H0X | `$D400` | Sprites 0–7 |
| H1X | `$D401` | Sprites 8–15 |
| H2X | `$D402` | Sprites 16–23 |

```
bit N set = sprite pixel present at horizontal column (N mod 8) for that layer
```

#### HOBJ — Collision Flag Register

Bit-field recording which layer/layer and sprite/layer combinations had overlapping active pixels during the current frame. Pixel signals are active-low; NOR logic detects simultaneous activity.

| Bit | Name | Collision |
|-----|------|-----------|
| 7:6 | — | Always 0 |
| 5 | S23 | Tilemap 2 ∩ Tilemap 3 |
| 4 | S13 | Tilemap 1 ∩ Tilemap 3 |
| 3 | S12 | Tilemap 1 ∩ Tilemap 2 |
| 2 | OB3 | Sprite ∩ Tilemap 3 |
| 1 | OB2 | Sprite ∩ Tilemap 2 |
| 0 | OB1 | Sprite ∩ Tilemap 1 |

#### Usage

1. Write to `HTCLR` (`$D508`) at the start of each frame to clear all hit registers
2. Allow the hardware to accumulate collision data during active display
3. Read H0X, H1X, H2X for horizontal position of sprite/layer hits
4. Read HOBJ for layer-vs-layer and sprite-vs-layer collision flags

#### Pixel Activity Detection

A pixel is considered active (non-transparent) when any of its 3 colour bits are non-zero. Colour index 0 (all bitplanes zero) is transparent for both tilemap layers and sprites.

Collision detection operates on active pixels only — a pixel at colour index 0 is ignored for hit detection purposes regardless of which layer it belongs to.

#### Register Read Address

The hit registers are read from `$D400–$D403`, selected by address bits A[1:0].

### EXROM — External ROM to VRAM Transfer

The EXROM mechanism allows the Z80 to read graphics ROM data and copy it into VRAM. This is the primary method for loading tile graphics into VRAM at runtime.

**Procedure:**
1. Write the starting ROM address low byte to EXROM1 (`$D509`)
2. Write the starting ROM address high byte to EXROM2 (`$D50A`)
3. Read from EXRHR (`$D404–$D407`) — each read returns the byte at the current ROM address and automatically increments an internal counter
4. Write the returned byte to the appropriate VRAM address
5. Repeat steps 3–4 for each subsequent byte — no address update needed due to auto-increment

This allows sequential tile data to be streamed from ROM into VRAM efficiently with a simple read/write loop.

### COIN LOCK / SOUND STOP / BANK SEL (`$D50E`)

| Bit | Name | Description |
|-----|------|-------------|
| 0 | COIN LOCK | Coin lockout |
| 1 | SOUND STOP | Mute sound output |
| 7 | BANK SEL | Program ROM bank select (switches banked ROM at `$6000–$7FFF`) |
| 6:2 | — | Unused |

### EXPORT (`$D50F`)

5-bit output register (bits 4:0) connected to an optional PAL that provides copy protection in Alpine Ski. This PAL is not present on most board revisions.


---

## 10. Input Registers

All input registers are read-only and active-low (0 = pressed/active, 1 = released/inactive).

| Name | Address | Description |
|------|---------|-------------|
| IN0 | `$D408` | Player 1 joystick and buttons |
| IN1 | `$D409` | Player 2 joystick and buttons |
| DS.A | `$D40A` | DIP switch A |
| IN3 | `$D40B` | Coin and start inputs |
| IN4 | `$D40C` | Secondary controls (game-specific) |
| IN5 | `$D40D` | Sound CPU status (bits 7:4 from AY #2 port A) |
| DS.B | AY #0 port A | DIP switch B |
| DS.C | AY #0 port B | DIP switch C |

IN0, IN1, DS.A, IN3, IN4 and IN5 are read directly from the main data bus. DS.B and DS.C are read via the I/O ports of AY-3-8910 #0 (the main board AY chip).

### IN0 / IN1 — Player Joystick Inputs

| Bit | Input |
|-----|-------|
| 0 | Left |
| 1 | Right |
| 2 | Down |
| 3 | Up |
| 4 | Button 1 |
| 5 | Button 2 |

### IN3 — Coin and Start Inputs

| Bit | Input |
|-----|-------|
| 7 | Player 2 Start |
| 6 | Player 1 Start |
| 5 | Coin 1 |
| 4 | Coin 2 |
| 3:0 | Unused |

### IN4 — Secondary Controls

Used in games with a second directional input such as Front Line, The Tin Star and Wild Western where a second joystick controls gun direction.

| Bit | Input |
|-----|-------|
| 4 | Service button |
| 3 | Gun Up |
| 2 | Gun Down |
| 1 | Gun Right |
| 0 | Gun Left |

### IN5 — Sound CPU Status

Bits 7:4 carry the upper nibble of AY-3-8910 #2 port A from the sound board:

| Bit | Source |
|-----|--------|
| 7 | AY #2 IOA bit 7 |
| 6 | AY #2 IOA bit 6 |
| 5 | AY #2 IOA bit 5 |
| 4 | AY #2 IOA bit 4 |
| 3:0 | Not used for sound status |

---

## 11. Sound – AY-3-8910

The Taito System SJ uses four AY-3-8910 sound chips in total, providing 12 independent sound channels across two boards.

### Architecture

| Board | CPU | ROM | RAM | AY chips | Channels |
|-------|-----|-----|-----|----------|----------|
| Main board | Z80A (shared) | — | — | 1 × AY-3-8910 | 3 |
| Sound board | Z80A (dedicated) | 16KB | 1KB | 3 × AY-3-8910 | 9 |

### Main Board AY Chip

The main board AY-3-8910 is memory-mapped via two consecutive addresses:

| Address | Function |
|---------|----------|
| `$D40E` | Write AY register number (address latch) |
| `$D40F` | Write AY register value |

**Write sequence:**

```asm
ld      a, reg_number
ld      ($D40E), a      ; latch register address
ld      a, value
ld      ($D40F), a      ; write value
```

I/O ports 14 and 15 of the main board AY are used for input registers D408 and D409. The upper nibble of D40D (bits 7:4) carries status from the sound CPU via AY-3-8910 #2 port A.

### AY-3-8910 Register Map (all chips)

| Register | Name | Description |
|----------|------|-------------|
| 0–1 | TonA | Channel A tone period (12-bit, lo/hi) |
| 2–3 | TonB | Channel B tone period |
| 4–5 | TonC | Channel C tone period |
| 6 | Noise | Noise period (5-bit) |
| 7 | Mixer | Tone/noise enable per channel (active low) |
| 8 | AmplA | Channel A amplitude / envelope enable |
| 9 | AmplB | Channel B amplitude / envelope enable |
| 10 | AmplC | Channel C amplitude / envelope enable |
| 11–12 | Env | Envelope period (16-bit) |
| 13 | EnvTp | Envelope shape |
| 14–15 | I/O | I/O ports |

### Sound Board

The sound board is a self-contained unit with its own Z80A processor:

- **ROM:** 16KB (`$0000–$3FFF`) — four 4KB ROMs (ROM1–ROM4)
- **RAM:** 1KB (`$4000–$43FF`)
- **Sound chips:** 3 × AY-3-8910 (9 channels)
- **Command input:** EPORT1 latch at `$5000`

#### Sound Board Memory Map

| Lower   | Upper   | Size | Description |
|---------|---------|------|-------------|
| `$0000` | `$0FFF` | 4KB | Sound ROM 1 |
| `$1000` | `$1FFF` | 4KB | Sound ROM 2 |
| `$2000` | `$2FFF` | 4KB | Sound ROM 3 |
| `$3000` | `$3FFF` | 4KB | Sound ROM 4 |
| `$4000` | `$43FF` | 1KB | Sound RAM |
| `$4800` |         | 2B | AY-3-8910 #1 register access |
| `$4802` |         | 2B | AY-3-8910 #2 register access |
| `$4804` |         | 2B | AY-3-8910 #3 register access |
| `$5000` |         | 1B | EPORT1 command latch (read clears DB3 flag) |
| `$5001` |         | 1B | Status register |

Each sound board AY chip follows the same even/odd addressing scheme as the main board:

| Offset | Function |
|--------|----------|
| Even (`$4800`, `$4802`, `$4804`) | Write AY register number |
| Odd (`$4801`, `$4803`, `$4805`) | Write AY register value |

#### Sound Board `$5001` Status Register

| Bit | Description |
|-----|-------------|
| 7:4 | Always 1 |
| 3 | DB3 — set when main Z80 writes to EPORT1 (`$D50C`), cleared when sound Z80 reads `$5000` |
| 2 | DB2 — EPORT2 latch: main Z80 data bus bit 0 captured via `$D50B` |
| 1:0 | Always 1 |

The sound Z80 polls bit 3 to detect a pending command, reads `$5000` to retrieve it (simultaneously clearing bit 3), and uses bit 2 for the single-bit EPORT2 channel.

### Main → Sound Board Communication

| Main Z80 address | Name | Description |
|-----------------|------|-------------|
| `$D50B` | EPORT2 | Latches bit 0 of the main Z80 data bus into a single-bit latch |
| `$D50C` | EPORT1 | Writes an 8-bit command visible to the sound Z80 at `$5000` |

**EPORT1** is the primary command channel. Writing a byte to `$D50C` on the main board makes it available at `$5000` on the sound board and sets the pending flag in `$5001` bit 3.

**EPORT2** provides a secondary single-bit signal. Writing to `$D50B` captures bit 0 of the data bus; this appears at `$5001` bit 2 on the sound board. It is used in some games (e.g. Jungle Hunt) to signal the sound CPU to disable music during attract mode.

> **Note:** The sound board interrupt handling and command set vary per game and are not documented here.

## 12. Sprites

The System SJ supports 64 hardware sprites, each 16×16 pixels, with hardware double-buffered line rendering, per-sprite horizontal and vertical flip, and a global flip capability.

### Sprite RAM

Sprite attributes are stored in a 256-byte RAM at `$D100–$D1FF` (64 sprites × 4 bytes). The Z80 writes sprite records in sequential byte order, but the hardware scrambles the storage order internally for the renderer.

**Z80 write order (bytes 0–3 at `$D1xx`):**

| Z80 offset | Field |
|------------|-------|
| +0 | X position |
| +1 | Y position |
| +2 | Attributes |
| +3 | Tile code |

### Sprite Attributes Byte

| Bit | Name | Description |
|-----|------|-------------|
| 0 | — | Not yet confirmed |
| 1 | OBJ_CINV | Horizontal flip |
| 2 | — | Vertical flip |
| 3 | OMD | Colour mode (bit 3 of 4-bit sprite colour, affects palette entry) |
| 7:4 | — | Not yet fully documented |

### Sprite Colour

Sprites use a 4-bit colour value formed from OMD (bit 3) and the 3 bitplane pixel values (bits 2:0):

```
OB[3:0] = { OMD, bitplane_2, bitplane_1, bitplane_0 }
```

This 4-bit value combines with MD01/MD02 from SMD3 to form the 6-bit palette index (see [SMD3](#smd3-d507)).

Colour index 0 (all bitplane bits zero) is transparent.

### Sprite Size and VRAM Addressing

Each sprite is **16×16 pixels**, composed of four 8×8 tile quadrants arranged as a 2×2 grid. The tile code points to the top-left tile; the remaining three tiles follow sequentially in VRAM:

```
Tile N   | Tile N+1      <- top row    (left | right)
Tile N+2 | Tile N+3      <- bottom row (left | right)
```

Sprites share the same VRAM as the tilemaps. The tile code is 7 bits, giving access to tiles 0–127 in bank 0 or 128–255 in bank 1 (selected by OBJ_CINV / CCH bit in attributes).

The sprite tile code is 7 bits. The hardware automatically selects the correct 8-row block (upper or lower) based on the vertical position and flip flag, and the correct 8-pixel horizontal half based on the horizontal position and flip flag.

### Y Range Detection

A sprite is considered in range for a scanline when the sum of its Y position and the current scanline counter (plus 1) does not overflow into the upper 4 bits. In practice this means a sprite at Y position N is visible on scanlines N through N+15 (16 scanlines for a 16-pixel-tall sprite).

### Double-Buffered Line Rendering

Two 256×4-bit line buffers (LBUF1, LBUF2) are used in a ping-pong arrangement, alternating each scanline. One buffer is filled by the sprite hardware while the other is read out to the display. Horizontal flip is implemented by inverting the line buffer address.

### Enabling Sprites

Sprites are enabled by clearing bit 7 (OBJOFF) of the SOFF register (`$D600`). See [SOFF](#soff-display-control-d600) in the Hardware Control Registers section for the full bit decode.

Setting `SOFF = $F0` enables all tilemap layers and sprites with no flip.

### HITOB Signal

The sprite renderer outputs `HITOB`, which feeds the hit bus:

```
HITOB = (sprite pixel transparent) OR (line buffer pixel transparent)
```

`HITOB` is LOW only when both the current sprite pixel and the line buffer value at that position are non-zero (active). This LOW pulse is what the hit bus shift register detects as a collision event (see [Hit Bus](#hit-bus)).

---

## 13. Watchdog

The watchdog timer resets the hardware if not serviced within one frame period.

**Watchdog register:** `$D50D`

Write any value to reset the watchdog. This must be done once per frame, typically at the start of the interrupt handler:

```asm
INT_HANDLER:
        push    af
        xor     a
        ld      (TIME_RESET), a     ; TIME_RESET EQU $D50D
        ; ... rest of handler
```

Failure to service the watchdog within the timeout period causes a hardware reset.

---

## 14. MCU Communication

Some Taito SJ board revisions include a Motorola MC68705P3 microcontroller for copy protection and game logic. The MCU address space is mapped at `$8800–$8FFF` on the main Z80 bus, though not all of this range is used by every game.

### Handshake Protocol

Communication between the Z80 and MCU uses two addresses:

| Address | Direction | Description |
|---------|-----------|-------------|
| `$8800` | R/W | Data exchange latch between Z80 and MCU |
| `$8801` | R/W | Handshake / IRQ control |

A jumper on the board selects whether writing to `$8800` automatically triggers an interrupt on the MCU, or whether the interrupt must be explicitly triggered by a separate write to `$8801`.

Reading `$8801` from the Z80 returns status flags:
- Bit 0: the MC68705 has read the data written by the Z80
- Bit 1: the MC68705 has written data for the Z80 to read

### Address Range

The MCU region extends from `$8800` to `$8FFF`. Some hardware variants make use of additional addresses within this range beyond the basic `$8800`/`$8801` handshake registers.

### MC68705P3 Notes

- The P3 and P5 variants are functionally identical — only the bootstrap ROM differs
- Port C is at register `$02` (not `$04` as incorrectly documented in some sources)
- The MCU communicates with the Z80 through Port B signals and the shared latch
- The MCU ROM varies between game titles — Front Line, Elevator Action, The Tin Star, and Sea Fighter Poseidon each have unique MCU ROMs

> **Note:** On board revisions without the MCU populated, this address range may be unused or partially decoded.

---

*End of document — work in progress*
