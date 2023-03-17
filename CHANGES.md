
## Version history for NESTang - an NES emulator for Tang Primer 20K

v0.5 - The Tang Nano 20k release
- This release only supports the new Tang Nano 20K board.
- Direct controller support. Playstation 2 controllers (wired or wireless) can be directly 
  connected to the board through a Sipeed adapter.
- SD card support. Now games can be loaded through a MicroSD card. Use tools/nes2img.py to
  generate the SD card image. A simple menu system allows easy navigation. Press S1 button
  on the board to return to menu. 
- This is the first NESTang version that can operate standalone (without a PC). It is much 
  easier to use. At the same time, game loading and controlling through the PC loader is 
  still supported.

v0.4, 10/22/2022 - Linux loader
- New Linux loader for loading ROMs and connect gamepads.  Tested on MangoPi MQ-Quad. Should 
  also work on other ARM SBC boards.
- Use the correct 8:7 pixel aspect ratio for better fidelity. See https://www.nesdev.org/wiki/Overscan. 

v0.3, 10/15/2022 - Supporting the dock 
- Support the newly released Tang Primer 20K dock. The HDMI module is no longer needed!
- Press LB to use the in-game menu to load ROMs.

v0.2.0, 10/7/2022 - The DDR3 release
* Switch to on-board DDR3 for main memory.

v0.1.0, 9/15/2022 - Initial release
* 720p HDMI video and sound output.
* PC-side loader program for game loading and controller input.
* Cycle accurate emulation quality.
* Needs a MiSTer SDRAM module. See [here](https://github.com/nand2mario/nestang/blob/3e79993cb50d348ecec3a7860ad9d4c9c64ea319/doc/wiring.md) 
  for wiring instructions.