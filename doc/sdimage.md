
# NESTang SD Card Image Format

nand2mario, 2023.3

The nes2img.py script packs multiple [ines](https://www.nesdev.org/wiki/INES) rom images into 
an SD card image. This files describes how this image file is layed out.

The so-called "SD card image" is simply a sequence of 512-byte "sectors" in the following
structure. The format is designed for easy parsing and processing by hardware, as NESTang aims
to runs on plain FPGAs, not SoCs. For example, menu screens are stored as bitmaps so we
can take advantage of the existing framebuffer and do not need to render text.

```
        +----------------+
     .--| Meta Sector 0  |  1 sector
     |  +----------------+
     |  | Menu Bitmap 0  |  120 sectors
     |  +----------------+
  .--+--| Meta Sector 1  |  1 sector
  |  |  +----------------+
  |  |  | Menu Bitmap 1  |  120 sectors
  |  |  +----------------+
  |  |  |      ...       |
  |  |  +----------------+
  |  +->| NES image 0    |  variable # of sectors
  |  |  +----------------+
  |  `->| NES image 1    |
  |     +----------------+
  |     |      ...       |
  |     +----------------+
  `---->| NES image 20   |
        +----------------+
        |      ...       |
        +----------------+
```

Each "meta sector" contains meta data about up to 20 ines roms. It is followed by a corresponding
menu bitmap that is displayed for the user to choose among these roms. The whole SD image can
contain any number of meta sectors so there can be multiple screens of roms to choose from.

Detailed layout of the **meta sector** is as follows. All multi-byte
integers are **little-endian**.
* 16B (bytes) header
    * 4B magic, ascii of "TANG"
    * 3B prev_meta_sector, sector number of the previous meta sector.
    * 3B next_meta_sector, sector number of the next meta sector.
    * 1B num_items, number of menu items on this screen, 1 to 20
    * 1B background_color, in NES color (0 to 63)
    * 1B foreground_color, in NES color (0 to 63)
    * 3B not used
* Up to 20 menu items, each 8 bytes
    * 1B cursor_x, cursor x position of the menu item, 0 to 255
    * 1B cursor_y, cursor y position of the menu item, 0 to 239
    * 3B rom_start_sector, starting sector number of the corresponding rom
    * 3B rom_length, length in bytes of the rom

Format of the **menu bitmap**:
* This is a simple full screen (256x240) bitmap of the menu screen in NES color, one byte per pixel.
  Since each sector is 512 bytes, holding 2 lines of pixels, therefore the whole image takes in total
  120 sectors (60KB).

Format of **NES image**:
* These are just raw ines roms stored in whole 512-byte sectors.

