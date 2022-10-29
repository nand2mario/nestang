
CFLAGS_SDL=$(shell sdl2-config --cflags) -O3
LIBS_SDL=$(shell sdl2-config --libs)

.PHONY: build sim verilate clean
	
build: ./obj_dir/VNES_Tang20k

verilate: ./obj_dir/VNES_Tang20k.cpp

./obj_dir/VNES_Tang20k.cpp: sim_main.cpp hdl/*.v
	@echo
	@echo "### VERILATE ####"
	mkdir -p obj_dir
	cd obj_dir; ln -sf ../game.nes.hex .; ln -sf ../hdl/src/*.txt .
	# verilator --top-module NES_Tang20k --trace -cc -O3 -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" hdl/*.v --exe sim_main.cpp
	verilator --top-module NES_Tang20k -cc -O3 --exe -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" hdl/*.v sim_main.cpp

./obj_dir/VNES_Tang20k: verilate
	@echo
	@echo "### BUILDING SIM ###"
	make -C obj_dir -f VNES_Tang20k.mk VNES_Tang20k

sim: ./obj_dir/VNES_Tang20k
	@echo
	@echo "### SIMULATION ###"
	@cd obj_dir && ./VNES_Tang20k

clean:
	rm -rf obj_dir