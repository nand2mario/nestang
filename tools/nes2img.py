#!/usr/bin/python3

# Script to pack .nes rom file as an SDCard image
# usage:
#   pack.py x.nes
#   sudo dd if=x.img of=/dev/disk4 bs=512

import sys

if len(sys.argv) != 3:
    print('Packing nes roms as sdcard images. Usage:')
    print('  nes2img.py x.nes x.img')
    print('Then you can write it to a card with dd or Balena Etcher:')
    print('  sudo dd if=x.img of=/dev/diskx bs=512')
    exit(1)

NES=sys.argv[1]
IMG=sys.argv[2]

# print('{} {}'.format(NES, IMG))
with open(NES, 'rb') as nes_file:
    contents = nes_file.read()

l = len(contents)
print('len={}'.format(l))
header = len(contents).to_bytes(512, 'little')

with open(IMG, 'wb') as img_file:
    img_file.write(header)
    img_file.write(contents)
    # 0-pad the final sector
    if l % 512 != 0:
        pad = bytes(512-l%512)
        img_file.write(pad)

print("Done.")