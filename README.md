# [Taito System SJ](https://www.system16.com/hardware.php?id=634)

A port of the MiSTer Taito System SJ core to the Sipeed Tang Nano 20K, with HDMI output, as a
<a href="https://github.com/nand2mario/tangcore">TangCore</a> core: the TangCore BL616 firmware
loads it from the USB drive and sends it the game's ROMs.

<p>Thank you to the following members of the MiSTer community: Boogermann, misterretrowolf, Sorgelig, & Jotego.</p>

<p>The Taito System SJ was manufactured by Taito in 1982.   The Taito System SJ featured hardware specifications that were relatively advanced for its time and can run several games.  The most recognizable games in the collection are Elevator Action and Jungle King.  </p>

<strong>Main CPU :</strong> Zilog Z80 CPU running at 4 MHz for running game logic and an AY8910 @ 1.5Mhz.  
<strong>Audio CPU:</strong> Zilog Z80 CPU running at 3 MHz for coordinating sound effects controlling 3 additional AY8910s @ 1.5Mhz. 
<strong>MCU:</strong> 68705 MCU running @ 750Hz used for protection. 
<strong>Video resolution:</strong> 256x224 @ 59.2Hz  
<strong>Video Hardware:</strong> 3 seperate independantly scrollable tile maps and adjustable priorities, a 4th layer is dedicated to 'objects' (sprites).   

<h2>Compatible Platforms</h2>
<li>Sipeed Tang Nano 20K with the TangCore firmware (HDMI, 1280x720 at 60 Hz)</li>

<h2>Building</h2>
<p><code>gw_sh build.tcl nano20k</code> in this folder (Gowin 1.9.11.03) writes the core to <code>impl/pnr/taitosj_nano20k.bin</code>.
See <a href="tang/nano20k/BUILD.md">tang/nano20k/BUILD.md</a> for the build, where the core and the ROM zip go on the USB drive,
the controls and how the port works.</p>

<h2>Compatible Games</h2>
<blockquote>
<p dir="auto"><strong>ROMs NOT INCLUDED:</strong> By using this core you agree to provide your own roms.</p>
</blockquote>

<p>Games supported by the original MiSTer core. On the Tang Nano 20K port only Elevator Action has been tested. The .mra files in <code>releases/</code> are kept as the ROM layout reference for each game.</p>

<li>Adventure Canoe</li>
<li>Alpine Ski</li>
<li>Bio Attack</li>
<li>Elevator Action (MCU) - tested on the Tang Nano 20K port</li>
<li>Front Line (MCU)</li>
<li>High Way Race</li>
<li>Jungle Hunt</li>
<li>Jungle King</li>
<li>Pirate Pete</li>
<li>Sea Fighter Poseidon (MCU)</li>
<li>Space Cruiser</li>
<li>Space Seeker</li>
<li>The Tin Star (MCU)</li>
<li>Time Tunnel</li>
<li>Water Ski</li>
<li>Wild Western</li>

<h2>Not Working</h2>
<li>Kick Start Wheelie King</li>

<h2>Issues</h2>
<li>Scroll RAM not implemented</li>
<li>Tang Nano 20K port: the game runs at 60 Hz instead of 59.19 Hz, about 1.4% fast</li>

<h2>Credits</h2>
<li>Original core: the MiSTer Taito System SJ core and the MiSTer community members named above</li>
<li>Z80: T80 core; AY-3-8910: JT49 by Jotego (both in <code>modules/</code>)</li>
<li>TangCore IO system (<code>tang/nano20k/iosys/</code>) and the SNES/DualShock pad modules: nand2mario's TangCore and NESTang</li>
<li>HDMI encoder: hdl-util HDMI by Sameer Puri (MIT OR Apache-2.0, in <code>tang/nano20k/hdmi/</code>)</li>
