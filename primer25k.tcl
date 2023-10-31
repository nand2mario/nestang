
set dev "primer25k"
add_file src/tang_primer_25k/config.sv
add_file src/tang_primer_25k/gowin_pll_27.v
add_file src/tang_primer_25k/gowin_pll_hdmi.v
add_file src/tang_primer_25k/gowin_pll_usb.v
add_file -type cst "src/tang_primer_25k/nestang.cst"
add_file -type sdc "src/tang_primer_25k/nestang.sdc"

set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -multi_boot 1

source build.tcl