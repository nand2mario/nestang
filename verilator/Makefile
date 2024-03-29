N=nestang_top
D=../src
SRCS=$D/verilator/config.sv $D/verilator/sdram_sim.v $D/apu.v $D/cart.sv $D/compat.v $D/dpram.v \
	$D/EEPROM_24C0x.sv $D/nestang_top.sv $D/nes.v $D/ppu.v \
	$D/t65/T65_Pack.v $D/t65/T65_ALU.v $D/t65/T65_MCode.v $D/t65/T65.v \
	$D/game_loader.v $D/game_data.v \
	$D/mappers/generic.sv $D/mappers/iir_filter.v $D/mappers/JYCompany.sv $D/mappers/misc.sv \
	$D/mappers/MMC1.sv $D/mappers/MMC2.sv $D/mappers/MMC3.sv $D/mappers/MMC5.sv $D/mappers/Namco.sv \
	$D/mappers/Sachen.sv $D/mappers/Sunsoft.sv

DEPS=
INCLUDES=-I$D -I$D/tang_nano_20k
CFLAGS_SDL=$(shell sdl2-config --cflags) -O3
LIBS_SDL=$(shell sdl2-config --libs)

.PHONY: build sim verilate clean gtkwave
	
build: ./obj_dir/V$N

verilate: ./obj_dir/V$N.cpp

./obj_dir/V$N.cpp: sim_main.cpp $(SRCS) $(DEPS)
	@echo
	@echo "### VERILATE ####"
	mkdir -p obj_dir
	verilator --top-module $N -Wno-WIDTHEXPAND -Wno-CASEOVERLAP --trace-fst -cc -O3 --exe -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" $(INCLUDES) $(SRCS) sim_main.cpp

./obj_dir/V$N: verilate
	@echo
	@echo "### BUILDING SIM ###"
	make -C obj_dir -f V$N.mk V$N
	cp -a $D/roms obj_dir
	cp -a $D/assets/*.txt obj_dir

sim: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION ###"
	@cd obj_dir && ./V$N -c 400000000

trace: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (trace) ###"
	@cd obj_dir && ./V$N -t -c 10000000 -s 0

clean:
	rm -rf obj_dir
