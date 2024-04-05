#/usr/bin/python3

import sys

if len(sys.argv) == 1:
    print("Tang Nano 20K PLL parameter calculator.")
    print("Usage: pll.pl <MHZ>")
    exit(1)

mhz=float(sys.argv[1])

# VCO frequency: odiv * mhz should be in [500Mhz, 1250Mhz]
for odiv in [1,2,4,8,16,32,64]:
    if mhz * odiv >= 500 and mhz * odiv <= 1250:
        break

diff=mhz
for i in range(0,9):
    for fb in range(0,63):
        f=27*(fb+1)/(i+1)
        if abs(f-mhz) < diff:
            diff=abs(f-mhz)
            idiv = i
            fbdiv = fb

f=27*(fbdiv+1)/(idiv+1)
print("fbdiv={}, idiv={}, odiv={}".format(fbdiv, idiv, odiv))
print("f={}, deviation={:.3f}%".format(f, 100.0*(f-mhz)/mhz))