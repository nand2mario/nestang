# Setup verilator simulation for nes
# 
# This runs under WSL. Make sure you've installed verilator with 
#     sudo apt install verilator

if [ "$1" == "" ]; then
    echo "./setup.sh <dir for nestang>"
    exit;
fi

DIR=$1

mkdir -p hdl
ln -s $DIR/src/apu.v hdl
ln -s $DIR/src/compat.v hdl
ln -s $DIR/src/cpu.v hdl
ln -s $DIR/src/hw_sound.v hdl
ln -s $DIR/src/hw_uart.v hdl
ln -s $DIR/src/MicroCode.v hdl
ln -s $DIR/src/mmu.v hdl
ln -s $DIR/src/nes_tang20k.v hdl
ln -s $DIR/src/nes.v hdl
ln -s $DIR/src/ppu.v hdl
ln -s $DIR/src/sdram.v hdl

mkdir -p obj_dir
ln -s $DIR/src/oam_palette.txt obj_dir
ln -s $DIR/src/*.hex obj_dir


echo "Setup done."
