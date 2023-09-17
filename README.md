# NESTang - FPGA NES with Sipeed Tang Nano 20K and Primer 20K Boards

<p align="right">
  <a title="Releases" href="https://github.com/nand2mario/nestang/releases"><img src="https://img.shields.io/github/commits-since/nand2mario/nestang/latest.svg?longCache=true&style=flat-square&logo=git&logoColor=fff"></a>
</p>

<img src="doc/images/nestang0.5.jpg" width=400>

NESTang is an open source project to recreate the Nintendo Entertainment System (NES) with modern affordable FPGA boards including Sipeed [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) and [Primer 20K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html). The main logic comes from [fpganes](https://github.com/strigeus/fpganes), to which I have added SDRAM/DDR3 and HDMI interfaces, among other features.

Main features,

- HDMI output with a resolution of 720p and sound capabilities.
- Cycle accurate gameplay quality has been achieved since the NES circuits have been almost entirely replicated.
- Game loading via MicroSD cards (for Tang Nano 20K only) or Windows/Linux loader program.
- Playstation 2 controller or USB gamepads (for Tang Nano 20K only) or interfacing with controllers connected through a PC.

## Setup for Tang Nano 20K

The best way to experience NESTang is with the Tang Nano 20K (Retro Game Kit version), which cost $38 last time I checked. The board features FPGA-friendly SDRAM memory. And the kit includes the necessary controller adapters and a pair of controllers. Here's what you need to run NESTang:

* The Tang Nano 20K board.
* Sipeed ps2 controller adapters connected to the board's pin 15-20 on both sides. Releases since 0.6 also support [USB gamepads](doc/usb_gamepad.md).
* Playstation or USB controllers connected to the adapters.
* HDMI cable to connect the board to a monitor.
* Latest NESTang program downloaded from [github](https://github.com/nand2mario/nestang/releases) and transferred to the board using either [openFPGALoader](https://github.com/trabucayre/openFPGALoader) or Gowin programmer.
* A MicroSD card to hold ROMs. For >= 0.7, just format the SD card in FAT32 (the card should be [<=32GB](https://answers.microsoft.com/en-us/windows/forum/all/format-a-sandisk-extreme-64gb-micro-sd-card-to/ff51be64-75b9-435f-9d39-92299b9d006e)) and place all .nes roms in the root dir.
  * For <= 0.6: The `tools/nes2img.py` python program can be used to convert .nes ROM files to an .img file. Ensure that you have Python version 3.7 or higher, and then install the Pillow package using `pip3 install pillow`. You can then use an SD imaging tool such as [Balena Etcher](https://www.balena.io/etcher) to burn the newly created image onto the MicroSD card.
* Insert the MicroSD card and power up the board to start playing your favorite games!

## Setup for Tang Primer 20K

If you own a Tang Primer 20K board, you can also run NESTang. The following components are required:

* Sipeed Tang Primer 20K board
* Muse-Lab HDMI PMod if you got the "lite" version of Tang board. You can purchase it from [aliexpress](https://www.aliexpress.com/item/3256804122775243.html) or [taobao](https://item.taobao.com/item.htm?id=671021594308). The "dock" version of the board already has an HDMI port, so there is no need for this component. The wiring instructions for the "lite" version can be found in the [doc/wiring.md](doc/wiring.md) file.

Follow the instructions below:

* Download [NESTang 0.4](https://github.com/nand2mario/nestang/releases/tag/v0.4) since later versions only support Tang Nano 20K.
* Launch the **Gowin Programmer** application and program either the `nestang-lite.fs` or `nestang-dock.fs` file, depending on your specific board. If your setup is correctly configured, a colorful NES palette should be displayed. 
* Connect your game controller/controllers to your PC. I use a pair of old Xbox 360 controllers.
* Use the command `loader.exe -c COM4 games\rom.nes` (replace COM4 with your port number) to load the game `rom.nes`. If the game does not load, install [Microsoft Visual C++ Redistributable package](https://aka.ms/vs/17/release/vc_redist.x64.exe) to resolve any missing DLL errors.
* Press the left button (LB) to open the in-game OSD menu, from where you can load other games located in the `games` directory.
* If the game does not load, run `loader.exe -r game.nes` to generate error messages from the core.

Congratulations! Now you can enjoy all your favorite NES games. For version 0.4, a Linux loader program is also available. See [Linux loader](doc/linux.md) for details.

## Development

If you want to generate the bitstream from source, see [Build Instructions](https://nand2mario.github.io/nestang-doc/dev/build_bitstream/).

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
