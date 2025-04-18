if {$argc == 0} {
    puts "Usage: $argv0 <device> <controller>"
    puts "          device: nano20k, primer25k, mega60k, mega138k, console60k, console138k"
    puts "      controller: snes, ds2"
    puts "Note: nano20k supports both controllers simultaneously, so build with just: gw_sh build.tcl nano20k"
    exit 1
}

set dev [lindex $argv 0]
if {$argc == 2} {
    set controller [lindex $argv 1]
} else {
    set controller "ds2"
}

# process $dev and $controller
if {$dev eq "nano20k"} {
    set_device GW2AR-LV18QN88C8/I7 -device_version C
    add_file src/boards/nano20k.v
    add_file -type cst "src/boards/nano20k.cst"
    add_file -type verilog "src/pllr/gowin_pll_hdmi.v"
    add_file -type verilog "src/pllr/gowin_pll_nes.v"
    add_file -type sdc "src/boards/nano20k.sdc"
    # nano20k supports both controllers simultaneously
    set_option -output_base_name nestang_${dev}
} elseif {$dev eq "primer25k"} {
    set_device GW5A-LV25MG121NC1/I0 -device_version A
    if {$controller eq "snes"} {
        add_file src/boards/primer25k_snescontroller.v
        add_file -type cst "src/boards/primer25k_snescontroller.cst"
    } elseif {$controller eq "ds2"} {
        add_file src/boards/primer25k.v
        add_file -type cst "src/boards/primer25k.cst"
    } else {
        error "Unknown controller $controller"
    }
    add_file -type verilog "src/plla/gowin_pll_27.v"
    add_file -type verilog "src/plla/gowin_pll_hdmi.v"
    add_file -type verilog "src/plla/gowin_pll_nes.v"
    add_file -type verilog "src/plla/pll_12.v"
    add_file -type verilog "src/usb_hid_host.v"
    add_file -type sdc "src/nestang.sdc"
    set_option -output_base_name nestang_${dev}_${controller}
} elseif {$dev eq "mega60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    if {$controller eq "snes"} {
        add_file src/boards/mega60k_snescontroller.v
        add_file -type cst "src/boards/mega60k_snescontroller.cst"
    } elseif {$controller eq "ds2"} {
        add_file src/boards/mega60k.v
        add_file -type cst "src/boards/mega60k.cst"
    } else {
        error "Unknown controller $controller"
    }
    # mega60k uses the same PLL as primer25k
    add_file -type verilog "src/plla/gowin_pll_27.v"
    add_file -type verilog "src/plla/gowin_pll_hdmi.v"
    add_file -type verilog "src/plla/gowin_pll_nes.v"
    add_file -type sdc "src/nestang.sdc"
    set_option -output_base_name nestang_${dev}_${controller}
} elseif {$dev eq "mega138k"} {
    set_device GW5AST-LV138PG484AC1/I0 -device_version B
    if {$controller eq "snes"} {
        add_file src/boards/mega138k_snescontroller.v
        add_file -type cst "src/boards/mega138k_snescontroller.cst"
    } elseif {$controller eq "ds2"} {
        add_file src/boards/mega138k.v
        # pin-to-pin compatible with mega60k
        add_file -type cst "src/boards/mega60k.cst"
    } else {
        error "Unknown controller $controller"
    }
    # GW5AST-138B uses a different PLL as GW5AT-60B
    add_file -type verilog "src/pll/gowin_pll_27.v"
    add_file -type verilog "src/pll/gowin_pll_hdmi.v"
    add_file -type verilog "src/pll/gowin_pll_nes.v"
    add_file -type sdc "src/nestang.sdc"
    set_option -output_base_name nestang_${dev}_${controller}
} elseif {$dev eq "console60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    if {$controller eq "snes"} {
        add_file src/boards/console60k_snescontroller.v
        add_file -type cst "src/boards/console60k_snescontroller.cst"
    } elseif {$controller eq "ds2"} {
        add_file src/boards/console60k.v
        add_file -type cst "src/boards/console.cst"
    } else {
        error "Unknown controller $controller"
    }
    # mega60k uses the same PLL as primer25k
    add_file -type verilog "src/plla/gowin_pll_27.v"
    add_file -type verilog "src/plla/gowin_pll_hdmi.v"
    add_file -type verilog "src/plla/gowin_pll_nes.v"
    add_file -type verilog "src/plla/pll_12.v"
    add_file -type verilog "src/usb_hid_host.v"
    add_file -type sdc "src/nestang.sdc"
    set_option -output_base_name nestang_${dev}_${controller}
} elseif {$dev eq "console138k"} {
    set_device GW5AST-LV138PG484AC1/I0 -device_version B
    add_file src/boards/console138k.v
    add_file -type cst "src/boards/console.cst"
    add_file -type verilog "src/pll/gowin_pll_27.v"
    add_file -type verilog "src/pll/gowin_pll_hdmi.v"
    add_file -type verilog "src/pll/gowin_pll_nes.v"
    add_file -type verilog "src/pll/pll_12.v"
    add_file -type verilog "src/usb_hid_host.v"
    add_file -type sdc "src/nestang.sdc"
    set_option -output_base_name nestang_${dev}_${controller}
} else {
    error "Unknown device $dev"
}

add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"
add_file -type verilog "src/apu.v"
add_file -type verilog "src/autofire.v"
add_file -type verilog "src/cart.sv"
add_file -type verilog "src/compat.v"
add_file -type verilog "src/controller_snes.v"
add_file -type verilog "src/controller_ds2.sv"
add_file -type verilog "src/dpram.v"
add_file -type verilog "src/dualshock_controller.v"
add_file -type verilog "src/EEPROM_24C0x.sv"
add_file -type verilog "src/game_loader.v"
add_file -type verilog "src/hdmi2/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi2/audio_info_frame.sv"
add_file -type verilog "src/hdmi2/audio_sample_packet.sv"
add_file -type verilog "src/hdmi2/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi2/hdmi.sv"
add_file -type verilog "src/hdmi2/packet_assembler.sv"
add_file -type verilog "src/hdmi2/packet_picker.sv"
add_file -type verilog "src/hdmi2/serializer.sv"
add_file -type verilog "src/hdmi2/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi2/tmds_channel.sv"
add_file -type verilog "src/mappers/generic.sv"
add_file -type verilog "src/mappers/iir_filter.v"
add_file -type verilog "src/mappers/JYCompany.sv"
add_file -type verilog "src/mappers/misc.sv"
add_file -type verilog "src/mappers/MMC1.sv"
add_file -type verilog "src/mappers/MMC2.sv"
add_file -type verilog "src/mappers/MMC3.sv"
add_file -type verilog "src/mappers/MMC5.sv"
add_file -type verilog "src/mappers/Namco.sv"
add_file -type verilog "src/mappers/Sachen.sv"
add_file -type verilog "src/mappers/Sunsoft.sv"
add_file -type verilog "src/nes.v"
add_file -type verilog "src/nes2hdmi.sv"
add_file -type verilog "src/nestang_top.sv"
add_file -type verilog "src/ppu.v"
add_file -type verilog "src/sdram_nes.v"
add_file -type verilog "src/t65/T65.v"
add_file -type verilog "src/t65/T65_ALU.v"
add_file -type verilog "src/t65/T65_MCode.v"
add_file -type verilog "src/t65/T65_Pack.v"
add_file -type verilog "src/uart_tx_V2.v"

set_option -synthesis_tool gowinsynthesis
set_option -top_module nestang_top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -use_mspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -multi_boot 1
set_option -place_option 2

run all
