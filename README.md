# NESTang - NES for Sipeed Tang FPGA Boards 

<p align="right">
  <a title="Releases" href="https://github.com/nand2mario/nestang/releases"><img src="https://img.shields.io/github/commits-since/nand2mario/nestang/latest.svg?longCache=true&style=flat-square&logo=git&logoColor=fff"></a>
</p>

<img src="doc/images/nestang0.8rc.jpg" width=400>

NESTang is an open source project to recreate the Nintendo Entertainment System (NES) with Sipeed Tang FPGA boards, including Sipeed [Tang Primer 25K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html), [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) and [Tang Primer 20K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html).

Main features,

- 720p HDMI output with sound.
- Cycle accurate gameplay quality has been achieved since the NES circuits have been almost entirely replicated.
- Rom loading from MicroSD cards with an easy-to-use menu system.
- Playstation 2 controllers support and experimental USB gamepads support.

## Pick a Board

You need either the Sipeed Tang Primer 25K or Tang Nano 20K FPGA board to run the latest NESTang.

* The Tang Primer 25K is the latest small-form-factor, modular FPGA board from Sipeed. If you want more memory and extensibility, choose Primer 25K. You need to get the [main Primer 25K dock board](https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html), [DVI PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_DVI), [TF Card PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_TF-CARD), [DS2x2 PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_DS2x2) and a [Tang SDRAM](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#TANG-40P-MODULE).
* The Tang Nano 20K is a tiny and popular FPGA dongle. The board also features 8MB of FPGA-gaming-friendly SDRAM memory. Be sure to get the [Tang Nano 20K Retro Gaming Kit](https://www.amazon.com/GW2AR-18-Computer-Debugger-Multiple-Emulator/dp/B0C5XLBQ6C), as it contains the necessary controllers and adapters.

## Installation

A [step-by-step instructions](https://github.com/nand2mario/snestang/blob/main/doc/installation.md) is available for installation. Here are quick instructions for the more experienced,

* Tang Primer 25K needs 4 modules: Tang sdram, DVI, Dualshock2, SD and a pair of dualshock controllers. Currently these should cost ~$60 in total. Tang Nano 20K just needs controller adapters. Check [instructions]([doc/installation.md](https://github.com/nand2mario/snestang/blob/main/doc/installation.md)) for how to connect the modules / adapters.
* Download a NESTang release from [github](https://github.com/nand2mario/nestang/releases). The bitstream (`nestang_*.fs`) should be written to flash at address 0. The firmware (`firmware.bin`) should be written to 0x500000 (5MB).
* A MicroSD card to hold ROMs.
* Connect one or two DualShock2 controllers to the DS2 pmod. Or you can connect one USB gamepad to use the [experimental USB gamepad support](doc/usb_gamepad.md). The board only has one USB port. So use DS2 if you want two players.
* Insert the MicroSD card, connect an HDMI monitor or TV, and enjoy your games.

Version 0.4 also supports [tang primer 20k](doc/primer20k.md).

## Development

If you want to generate the bitstream from source, see [Build Instructions](https://nand2mario.github.io/nestang-doc/dev/build_bitstream/). The recommended Gowin IDE version is 1.9.9 commercial (requires a free license).

[Usb_hid_host](https://github.com/nand2mario/usb_hid_host) was development so NESTang could support USB gamepads. Follow the link if you want to use it for your FPGA projects. It supports keyboards and mice too.

## Next steps

See NESTang [changes.md](CHANGES.md).

Here are what I may work on when I get time. No promise though. Suggestions and pull requests are welcome!
* Cheats support.
* Saves and loads.

## Special Thanks

* [fpganes](https://github.com/strigeus/fpganes) by Ludvig Strigeus.
* [hdl-util/hdmi](https://github.com/hdl-util/hdmi) by Sameer Puri.
* [NES for Tang Nano 9K](https://github.com/hi631/tang-nano-9K) by hi631

nand2mario (`nand2mario at outlook.com`)

Since 2022.9
