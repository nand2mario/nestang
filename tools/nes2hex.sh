#/usr/bin/bash

if [ "$1" == "" ]; then
    echo "Usage: nes2hex.sh <x.nes>"
    exit
fi

HEX="${1/.nes/.hex}"

hexdump -v -e '/1 "%02x\n"' $1 > $HEX

echo $HEX generated
