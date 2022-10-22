
## Version history for NESTang - an NES emulator for Tang Primer 20K

v0.4, 10/22/2022 - Linux loader
- New Linux loader for loading ROMs and connect gamepads.  Tested on MangoPi MQ-Quad. Should also work on other ARM SBC boards.
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
* Needs a MiSTer SDRAM module. See [here](https://github.com/nand2mario/nestang/blob/3e79993cb50d348ecec3a7860ad9d4c9c64ea319/doc/wiring.md) for wiring instructions.