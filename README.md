# NESTang - an NES emulator for Tang Primer 20K

<p align="right">
  <a title="Releases" href="https://github.com/nand2mario/nestang/releases"><img src="https://img.shields.io/github/commits-since/nand2mario/nestang/latest.svg?longCache=true&style=flat-square&logo=git&logoColor=fff"></a>
</p>

<img src="doc/images/nestang0.5.jpg" width=400>

NESTang is a Nintendo Entertainment System emulator for the affordable Sipeed Tang [Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/) and [Primer 20K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html) FPGA boards. The core logic comes from [fpganes](https://github.com/strigeus/fpganes). I added SDRAM/DDR3 and HDMI interfaces and other things.

This is still a work in progress. Here's what works.

* Majority of games I tested work.
* 720p HDMI video and sound output.
* Cycle accurate emulation quality as we nearly recreated the NES circuits.
* Game loading through MicroSD cards (Tang Nano 20K only) or Windows/Linux loader program.
* Playstation 2 controller interface (Tang Nano 20K only), or controllers connected through PC.

## Setup for Tang Nano 20K

With the release of Tang Nano 20K in March 2023, running NESTang has been greatly simplified. And it runs more stable as the board has SDRAM memory, which are more friendly to FPGAs than DDR memory. You need,
* The Tang Nano 20K board.
* Sipeed ps2 controller adapter, connected to pin 15-20 of the board.
* Playstation controller (wired or wireless) connected to the adapter.
* HDMI connection to a monitor.
* Program [NESTang 0.5](https://github.com/nand2mario/nestang/releases) to the board with [openFPGALoader](https://github.com/trabucayre/openFPGALoader) or Gowin programmer.
* A MicroSD card for holding ROMs. I've tried several old 8GB cards and they all work. Use `tools/nes2img.py` python program to convert a .nes ROM file to .img file. This script requires Python >=3.7 and needs the Pillow package (install with `pip3 install pillow`).  Then burn that image to the sd card with any sd tool (e.g. [Balena Etcher](https://www.balena.io/etcher)).
* Insert MicroSD and power up the board, and enjoy your game!

## Setup for Tang Primer 20K

If you have Tang Primer 20K instead (get the nano if you don't have any board). Then here's what you need.
* Sipeed Tang Primer 20K (starting at $30).
* Muse-Lab HDMI PMod if you got the lite version of Tang: [aliexpress](https://www.aliexpress.com/item/3256804122775243.html) or [taobao](https://item.taobao.com/item.htm?id=671021594308). The dock version already has HDMI so you are fine. [Wiring instructions](doc/wiring.md) for lite version.

Then it's time to enjoy some NES games，
* Download [NESTang 0.4](https://github.com/nand2mario/nestang/releases/tag/v0.4), as later versions currently only support Tang Nano 20K.
* Start **Gowin Programmer**, and program `nestang-lite.fs` or `nestang-dock.fs` depending on which board you have. If you see a colorful NES palette, then your setup is working. 
* Connect your game controller/controllers to your PC. I use a pair of old Xbox 360 controllers.
* Run `loader.exe -c COM4 games\rom.nes` (replace COM4 with your port number) to load the game `rom.nes` and run it. If it complains about missing DLLs, install [Microsoft Visual C++ Redistributable package](https://aka.ms/vs/17/release/vc_redist.x64.exe).
* Press the left button (LB) to call out the in-game OSD menu. There you can load other games in the `games` directory.
* If it didn't work, `loader.exe -r game.nes` will print messages from the core.

Hurrah! and enjoy.

For 0.4, there's also a Linux loader program in addition to Windows. See [Linux loader](doc/linux.md)

## Development

If you want to generate the bitstream from source, see [Build Instructions](doc/build.md).

Quite some time was spent on getting a low-latency (90ns) [DDR3 controller](https://github.com/nand2mario/ddr3-tang-primer-20k) to work for Tang Primer 20K. You may find that useful too.

## Next steps

See NESTang [changes.md](CHANGES.md).

Here are what I may work on when I get time. No promise though. Suggestions and pull requests are welcome!
* Support more games.
* An enclosure?
* Cheats support.
* Saves and loads.

## Special Thanks

* [fpganes](https://github.com/strigeus/fpganes) by Ludvig Strigeus.
* [hdl-util/hdmi](https://github.com/hdl-util/hdmi) by Sameer Puri.

nand2mario (`nand2mario at outlook.com`)

Since 2022.9
