# NESTang - NES for Sipeed Tang FPGA Boards 

<p align="right">
  <a title="Releases" href="https://github.com/nand2mario/nestang/releases"><img src="https://img.shields.io/github/commits-since/nand2mario/nestang/latest.svg?longCache=true&style=flat-square&logo=git&logoColor=fff"></a>
</p>

<img src="doc/images/nestang0.8rc.jpg" width=400>

NESTang is an open source project to recreate the Nintendo Entertainment System (NES) with Sipeed Tang FPGA boards, including Sipeed [Tang Primer 25K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html), [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) and [Tang Primer 20K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html).

Main features,

- 720p HDMI output with sound.
- Cycle accurate gameplay quality has been achieved since the NES circuits have been almost entirely replicated.
- Rom loading from MicroSD cards with an easy-to-use menu system, powered by a RISC-V softcore.
- Extensive mapper support including MMC5, Namco and more.
- NES/SNES controllers, or DS2 controllers.

Also check out [SNESTang](https://github.com/nand2mario/snestang) and [GBATang](https://github.com/nand2mario/gbatang). 

## Getting the parts

You need either the Sipeed Tang Primer 25K or Tang Nano 20K FPGA board to run the latest NESTang.

* If you choose the Primer 25K, get the [main Primer 25K dock board](https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html), [DVI PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_DVI), [TF Card PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_TF-CARD), [DS2x2 PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_DS2x2) and a [Tang SDRAM](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#TANG-40P-MODULE).
* For the Tang Nano 20K, we suggest the [Tang Nano 20K Retro Gaming Kit](https://www.amazon.com/GW2AR-18-Computer-Debugger-Multiple-Emulator/dp/B0C5XLBQ6C), as it contains the necessary controllers and adapters.

## Installation

A [step-by-step instructions](https://github.com/nand2mario/snestang/blob/main/doc/installation.md) is available. Here are quick instructions for the more experienced,

* Assemble the board and modules: [result for the primer 25k](https://github.com/nand2mario/snestang/raw/main/doc/images/primer25k_setup.jpg), and [nano 20k](https://github.com/nand2mario/snestang/raw/main/doc/images/nano20k_setup.jpg).
* Download a NESTang release from [github](https://github.com/nand2mario/nestang/releases). The bitstream (`nestang_*.fs`) should be written to flash at address 0. The firmware (`firmware.bin`) should be written to 0x500000 (5MB). See this [screenshot](https://github.com/nand2mario/snestang/blob/main/doc/images/programmer_firmware.png) for how to do it.
* Put your ROM files onto a MicroSD Card (exFAT or FAT32 file system). Insert the card, connect an HDMI monitor or TV, and enjoy your games.

Version 0.4 also supports [tang primer 20k](doc/primer20k.md).

## Development

If you want to generate the bitstream from source, see [Build Instructions](https://nand2mario.github.io/nestang-doc/dev/build_bitstream/). Make sure you use the Gowin IDE version 1.9.9 commercial (requires a free license).

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
