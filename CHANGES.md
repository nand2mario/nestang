
## Version history for NESTang - an NES emulator for Tang Primer 20K

v0.8rc, 10/31/2023 - The Tang Primer 25k release
- This releases supports the new Tang Primer 25k, along with Tang Nano 20k.
- For primer 25k, set up the memory module, hdmi pmod, dualshock2 pmod and microsd pmod as shown in [here](doc/images/primer25k_setup.jpg).
- The primer 25k build supports the on-board USB-A port for P1, and the dualshock2 ports for P1 and P2.
- For developers - the code base has been refactored to support both boards. Use `gw_sh nano20k.tcl` to build for nano 20k, and `gw_sh primer25k.tcl` to build for primer 25k.

v0.7, 9/18/2023 - FAT32 MicroSD
- This release only supports Tang Nano 20K.
- FAT32 MicroSD support. We have switched to FAT32 format for rom loading from MicroSD cards. Simply format your card in FAT32 and place all roms in the root directory.

v0.6, 8/20/2023 - USB gamepads
- This release only supports Tang Nano 20K.
- USB gamepad support. In addition to playstation 2 controllers, now low-speed USB gamepads can be connected to the board. USB connectors and a bit circuitry is needed. See [usb_gamepad.md](doc/usb_gamepad.md)

v0.5, 6/4/2023 - The Tang Nano 20k release
- This release only supports the new Tang Nano 20K board.
- Direct controller support. Playstation 2 controllers (wired or wireless) can be directly 
  connected to the board through a Sipeed adapter.
- SD card support. Now games can be loaded through a MicroSD card. Use tools/nes2img.py to
  generate the SD card image. A simple menu system allows easy navigation. Press S1 button
  on the board to return to menu. 
- This is the first NESTang version that can operate standalone (without a PC). It is much 
  easier to use. At the same time, game loading and controlling through the PC loader is 
  still supported.
- Other changes: 
  1. Fixed a bug where there's no sound on some TVs.
  2. PS2 controller supports auto-fire buttons (square and triangle buttons)

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