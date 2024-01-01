N=nestang_top
D=../src
SRCS=$D/tang_nano_20k/config.sv $D/apu.v $D/compat.v $D/cpu.v $D/hw_sound.v $D/MicroCode.v \
	$D/mmu.v $D/nestang_top.sv $D/nes.v $D/ppu.v $D/memory_controller.v $D/game_loader.v \
	$D/game_data.v

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
	verilator --top-module $N --trace -cc -O3 --exe -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" $(INCLUDES) $(SRCS) sim_main.cpp

./obj_dir/V$N: verilate
	@echo
	@echo "### BUILDING SIM ###"
	make -C obj_dir -f V$N.mk V$N
	cp -a *.hex obj_dir
	cp -a $D/*.txt obj_dir

sim: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION ###"
	@cd obj_dir && ./V$N

clean:
	rm -rf obj_dir