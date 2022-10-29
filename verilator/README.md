This is a Verilator-driven graphical simulation of nestang. Should be useful in debugging game / mapper support, among other things.

To run the simulation:

```
./setup.sh `pwd`/..
hexdump -ve '1/1 "%02x\n"' game.nes > game.nes.hex
# change INES_SIZE in nes_tang20k.v to reflect size of game.nes
make sim
```

You need to set up verilator / libsdl2 with something like:

```
# Linux
sudo apt install verilator libsdl2-dev

# Mac
brew install verilator sdl2
```

For an overview of verilator, see: https://www.itsembedded.com/dhd/verilator_2/
