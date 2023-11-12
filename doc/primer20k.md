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