
add_file -type verilog "src/MicroCode.v"
add_file -type verilog "src/apu.v"
add_file -type verilog "src/autofire.v"
add_file -type verilog "src/compat.v"
add_file -type verilog "src/config.sv"
add_file -type verilog "src/cpu.v"
add_file -type verilog "src/dualshock_controller.v"
add_file -type verilog "src/game_loader.v"
add_file -type verilog "src/gowin_clkdiv/gowin_clkdiv.v"
add_file -type verilog "src/gowin_rpll_hdmi/gowin_rpll.v"
add_file -type verilog "src/gowin_rpll_nes/gowin_rpll.v"
add_file -type verilog "src/gowin_rpll_usb.v"
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
add_file -type verilog "src/hw_sound.v"
add_file -type verilog "src/hw_uart.v"
add_file -type verilog "src/memory_controller.v"
add_file -type verilog "src/mmu.v"
add_file -type verilog "src/nes.v"
add_file -type verilog "src/nes2hdmi.sv"
add_file -type verilog "src/nes_tang20k.v"
add_file -type verilog "src/ppu.v"
add_file -type verilog "src/sd_file_list_reader.v"
add_file -type verilog "src/sd_loader.v"
add_file -type verilog "src/sd_reader.sv"
add_file -type verilog "src/sdcmd_ctrl.sv"
add_file -type verilog "src/sdram.v"
add_file -type verilog "src/uart_tx_V2.v"
add_file -type verilog "src/usb_hid_host.v"
add_file -type verilog "src/usb_hid_host_rom.v"
add_file -type cst "src/nestang.cst"
add_file -type sdc "src/nestang.sdc"

add_file -type gao -disable "src/nes.gao"
add_file -type cst -disable "src/nestang_dock.cst"

if {$dev eq "nano20k"} {
    set_device GW2AR-LV18QN88C8/I7 -device_version C
} elseif {$dev eq "primer25k"} {
    set_device GW5A-LV25MG121NC1/I0 -device_version A
}

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name nestang
set_option -top_module NES_Tang20k
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -use_sspi_as_gpio 1

run all
