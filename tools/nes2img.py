#!/usr/bin/python3

# Script to pack .nes rom files, along with a menu image
# as an SDCard image. SD card is read by sd_loader.v

import sys
import os
from importlib.resources import files,as_file      # to read back.png
from PIL import Image
from myfont import FONT
from nescolor import image2nes
from functools import cmp_to_key
import re

BACKGROUND=13   # cursor background: black 
FOREGROUND=55   # cursor foreground: bright yellow
COLOR=56        # bright text: yellow
COLOR_DARK=4    # dark text:   purple
META_MENU_SECTORS=121   # 1 meta-sector + 120 menu image

print("Since 0.7, nes2img.py is NO LONGER NEEDED. Just format your MicroSD card as FAT32. See https://github.com/nand2mario/nestang/README.md. This script will be removed later.\n")

if len(sys.argv) < 3:
    print('Packing nes roms as an sdcard image. Usage:')
    print('  nes2img.py -o x.img x.nes y.nes ...')
    print('Then you can write it to a card with dd or Balena Etcher:')
    print('  sudo dd if=x.img of=/dev/diskx bs=512')
    exit(1)

NES=[]
IMG=''
SORT = False
BIN=''      # print background image as binary

i = 1
while i < len(sys.argv):
    if sys.argv[i] == '-o':
        IMG=sys.argv[i+1]
        i+=1
    elif sys.argv[i] == '-b':
        BIN=sys.argv[i+1]
        i+=1
    elif sys.argv[i] == '-s':
        SORT = True
    else:
        NES.append(sys.argv[i])
    i+=1

def writeBackBinary():
    png = os.path.join(os.path.dirname(__file__), 'back.png')
    with Image.open(png) as im:
        img = image2nes(im)
    # find bounding box of logo
    l=256
    r=0
    t=240
    b=0
    with open(BIN, 'w') as bin_file:
        for i in range(240):        # print image for debug
            for j in range(256):
                bin_file.write('{:06b}\n'.format(img[i][j]))
                if img[i][j] != 13:
                    l = min(j, l)
                    r = max(j, r)
                    t = min(i, t)
                    b = max(i, b)
    print('left={}, right={}, top={}, bottom={}'.format(l, r, t, b))
    for y in range(t, b+1):
        for x in range(l, r+1):
            print('{}'.format('1' if img[y][x] == 4 else '0'), end='')
        print('')

if BIN != '':       # Just write background as binary file
    writeBackBinary()
    print('Done.')
    exit(0)

# numbers first, then alphabetical order
def compare(a, b):
    am = re.search('^[0-9]+', a)
    bm = re.search('^[0-9]+', b)
    if am != None and bm == None:
        return -1
    elif am == None and bm != None:
        return 1
    elif am != None and bm != None:
        A = int(am.group())
        B = int(bm.group())
        if A != B:
            return -1 if A < B else (1 if A > B else 0)
        else:
            return -1 if a < b else (1 if a > b else 0)
    else:
        return -1 if a < b else (1 if a > b else 0)

if SORT:
    NES.sort(key=cmp_to_key(compare))

for x in NES:
    print(x)

pages = (len(NES) + 19) // 20
print('Number of menu pages: {}'.format(pages))

if IMG=='' or NES==[]:
    print('nes2img.py -o x.img x.nes y.nes ...')
    exit(1)

start = []                          # start sector of each ROM
length = []                         # length of each ROM
sector = pages * META_MENU_SECTORS  # initial start sector of ROMs
for i in range(len(NES)):
    f = NES[i]
    filesize = os.path.getsize(f)
    n = filesize // 512
    if filesize % 512 != 0:
        n+=1
    start.append(sector)
    length.append(filesize)
    sector += n

# print a string on img
# row (0-29), col (0-31)
def text(img, row, col, str, color):
    for i in range(len(str)):
        a = ord(str[i])
        if a > 127:
            a = 63      # ?
        if i + col >= 32:
            break
        y = row*8
        x = (col+i)*8
        for j in range(8):
            for k in range(8):
                if FONT[a][j] & (1 << k):
                    img[y+j][x+k] = color

# id: 0-based index of menu page
def writeMetaAndMenu(img_file, id):
    meta = bytearray(512)       # meta sector
    rng = range(id*20, min(id*20+20, len(NES)))

    # read in background file
    png = os.path.join(os.path.dirname(__file__), 'back.png')
    with Image.open(png) as im:
        img = image2nes(im)

    prev = 0 if id == 0 else id-1
    next = id + 1 if id < pages-1 else id
    meta[0:4] = b'TANG'
    meta[4:7] = (prev*META_MENU_SECTORS).to_bytes(3, 'little')        # previous meta sector
    meta[7:10] = (next*META_MENU_SECTORS).to_bytes(3, 'little')       # next meta sector
    meta[10] = len(rng)
    meta[11] = BACKGROUND
    meta[12] = FOREGROUND

    for i in rng:
        j = 16+8*(i-rng[0])
        meta[j] = 0             # col = 2
        meta[j+1] = 40 + 8*(i-rng[0])    # row = 5+i
        meta[j+2:j+5] = start[i].to_bytes(3, 'little')
        meta[j+5:j+8] = length[i].to_bytes(3, 'little')

    # Meta sector
    img_file.write(meta)        # write meta sector

    # Menu image
    for i in rng:
        name = os.path.basename(NES[i])
        if name.endswith('.nes'):
            name = name[:len(name)-4]
        if len(name) > 29:
            name = name[:29]
        text(img, (i-rng[0])+5, 2, name, COLOR)
    text(img, 27, 29, '{}'.format(id+1), COLOR_DARK)
    for i in range(240):        # write menu image to sd 
        img_file.write(bytearray(img[i]))

img_file = open(IMG, 'wb')

# 1. Meta sectors and menu images
for id in range(pages):
    writeMetaAndMenu(img_file, id)

# 2. ROMs
for i in range(len(NES)):
    # print('{} {}'.format(NES, IMG))
    with open(NES[i], 'rb') as nes_file:
        contents = nes_file.read()
    img_file.write(contents)
    # 0-pad the final sector
    l = len(contents)
    if l % 512 != 0:
        pad = bytes(512 - l % 512)
        img_file.write(pad)

img_file.close()

print("Done.")