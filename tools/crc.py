#!/usr/bin/python3

import sys

def usage():
    print('USB CRC calculator')
    print('  crc.py -5 <byte0> <byte1>       calculate CRC-5-USB of {byte0[0:7], byte1[0:2]} (11 bits)')
    print('  crc.py -16 <byte0> ... <byte_n> calculcate CRC-16 of these bytes')
    print('All bytes should be in hex')
    exit(0)

if len(sys.argv) < 2 or sys.argv[1] != '-5' and sys.argv[1] != '-16':
    usage()

def crc5(data):
    # x^5 + x^2 + 1
    polynomial = 0b00101
    # USB crc5 is initialized to all 1
    register = 0b11111      

    if len(data) != 2 and len(data) != 3:
        usage()

    for d in range(len(data)):
        byte = data[d]
        bits = range(8) if d < len(data)-1 else range(3)
        # print(bits)
        for i in bits:
            bit = (byte >> i) & 1
            xor_flag = (register >> 4) & 1
            register = (register << 1) & 0b11111
            if bit ^ xor_flag:
                register ^= polynomial

    # USB crc5 is inversed at output time
    return 0b11111-register

def crc16(data):
    return 0

bs = []

for i in range(2, len(sys.argv)):
    bs.append(int(sys.argv[i], 16))

# bs = [0b10101010, 0b01010101, 0b11110000]
print("data={}".format(bs))

if sys.argv[1] == '-5':
    # actually printed from MSB to LSB
    print("crc5={:05b}".format(crc5(bs)))
else:
    print("crc16={}".format(crc16(bs)))




