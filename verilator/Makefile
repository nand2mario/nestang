
.PHONY: build sim verilate
	

build: ./obj_dir/VNES_Tang20k

verilate: sim_main.cpp hdl/*.v
	@echo
	@echo "### VERILATE ####"
	verilator --top-module NES_Tang20k --trace -cc hdl/*.v --exe sim_main.cpp

./obj_dir/VNES_Tang20k: verilate
	@echo
	@echo "### BUILDING SIM ###"
	make -C obj_dir -f VNES_Tang20k.mk VNES_Tang20k

sim: ./obj_dir/VNES_Tang20k
	@echo
	@echo "### SIMULATION ###"
	@echo "This will take some time..."
	@cd obj_dir && ./VNES_Tang20k
