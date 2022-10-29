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
ln -sf $DIR/src/apu.v hdl
ln -sf $DIR/src/compat.v hdl
ln -sf $DIR/src/cpu.v hdl
ln -sf $DIR/src/hw_sound.v hdl
ln -sf $DIR/src/MicroCode.v hdl
ln -sf $DIR/src/mmu.v hdl
ln -sf $DIR/src/nes_tang20k.v hdl
ln -sf $DIR/src/nes.v hdl
ln -sf $DIR/src/ppu.v hdl
ln -sf $DIR/src/memory_controller.v hdl
ln -sf $DIR/src/game_loader.v hdl
ln -sf $DIR/src hdl/src

echo "hdl/ directory setup done."

if [ ! -f game.nes.hex ]; then
    echo "You need game.nes.hex ROM file to do simulation. To generate from .nes files: "
    echo '  hexdump -ve '"'"'1/1 "%02x\\n'"'"' game.nes > game.nes.hex'
fi
