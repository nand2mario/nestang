# NESTang - an NES emulator for Tang Primer 20K

<p align="right">
  <a title="Releases" href="https://github.com/nand2mario/nestang/releases"><img src="https://img.shields.io/github/commits-since/nand2mario/nestang/latest.svg?longCache=true&style=flat-square&logo=git&logoColor=fff"></a>
</p>

<img src="doc/images/setup.jpg" width=400>

NESTang is a Nintendo Entertainment System emulator for the affordable [Sipeed Tang Primer 20K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html) FPGA board. The core logic comes from [fpganes](https://github.com/strigeus/fpganes). I added DDR3 and HDMI interfaces and other things.

This is still a work in progress. Here's what works.

* Majority of games I tested work.
* 720p HDMI video and sound output.
* PC-side loader program for game loading and controller input.
* Cycle accurate emulation quality as we nearly recreated the NES circuits.
* ~~Needs a MiSTer SDRAM module. Similar to [MiSTer](https://misterfpga.org/), SDRAM is needed for its low access latency required by emulation.~~ (since v0.2 the SDRAM is no longer needed! :smiley:)

## Setup

Interested? Here's what you need:

* Sipeed Tang Primer 20K (starting at $30).
* Muse-Lab HDMI PMod if you got the lite version of Tang: [aliexpress](https://www.aliexpress.com/item/3256804122775243.html) or [taobao](https://item.taobao.com/item.htm?id=671021594308). The dock version already has HDMI so you are fine. [Wiring instructions](doc/wiring.md) for lite version.

Then it's time to enjoy some NES games，
* Download the latest [NESTang release](https://github.com/nand2mario/nestang/releases/).
* Start **Gowin Programmer**, and program `nestang-lite.fs` or `nestang-doc.fs` depending which board you have. If you see a colorful NES palette, then your setup is working. 
* Connect your game controller/controllers to your PC. I use a pair of old Xbox 360 controllers.
* Run `loader.exe -c COM4 games\rom.nes` (replace COM4 with your port number) to load the game `rom.nes` and run it. If it complains about missing DLLs, install [Microsoft Visual C++ Redistributable package](https://aka.ms/vs/17/release/vc_redist.x64.exe).
* Press the left button (LB) to call out the in game OSD menu. There you can load other games in the `games` directory.
* If it didn't work, `loader.exe -r game.nes` will print messages from the core.

Hurrah! and enjoy.

If you want to generate the bitstream from source, see [Build Instructions](doc/build.md).

## Next steps

See NESTang [changes.md](CHANGES.md).

Here are what I may work on when I get time. No promise though. Suggestions and pull requests are welcome!
* A way to work without a PC.
* Support more games.
* An enclosure?
* Cheats support.
* Saves and loads.

## Special Thanks

* [fpganes](https://github.com/strigeus/fpganes) by Ludvig Strigeus.
* [hdl-util/hdmi](https://github.com/hdl-util/hdmi) by Sameer Puri.

nand2mario
2022.9
