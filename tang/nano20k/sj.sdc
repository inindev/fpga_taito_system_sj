// Timing constraints for Taito System SJ on the Tang Nano 20K.
//
// Only the real clocks are declared. clk48 and clk32 come from the same PLL VCO
// (768 MHz / 16 and / 24), so paths between them are timed as related clocks.

// 27 MHz board oscillator
create_clock -name clk27 -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}]

// Game PLL: 48 MHz core clock (clkm_48MHZ) and 32 MHz CPU/SDRAM clock (clkm_32MHZ)
create_generated_clock -name clk48 -source [get_ports {sys_clk}] -master_clock clk27 -multiply_by 16 -divide_by 9 [get_pins {u_pll_game/rpll_inst/CLKOUTD}]
create_generated_clock -name clk32 -source [get_ports {sys_clk}] -master_clock clk27 -multiply_by 32 -divide_by 27 [get_pins {u_pll_game/rpll_inst/CLKOUTD3}]

// HDMI PLL: 371.25 MHz serial clock, divided by 5 to the 74.25 MHz pixel clock
create_generated_clock -name hclk5 -source [get_ports {sys_clk}] -master_clock clk27 -multiply_by 55 -divide_by 4 [get_pins {u_pll_hdmi/rpll_inst/CLKOUT}]
create_generated_clock -name hclk -source [get_pins {u_pll_hdmi/rpll_inst/CLKOUT}] -master_clock hclk5 -divide_by 5 [get_pins {u_div5/CLKOUT}]

// Clock crossings: a register named *_meta is the first stage of a synchronizer (iosys's
// UART input; in top.sv the gamepad controls and the menu state into clk48; in linebuf.sv
// overlay/osd_strip and in top.sv the audio samples into hclk). The path into it crosses
// clocks on purpose. Gowin uses only one .sdc, so the line has to be here.
set_false_path -to [get_regs {*_meta*}]
