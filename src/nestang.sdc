// NES clocks
create_clock -name sys_clk -period 20 [get_nets {sys_clk}]       // 50 Mhz
create_clock -name fclk -period 15.51 [get_nets {fclk}]          // 64.4737 Mhz
create_generated_clock -name clk -source [get_nets {fclk}] -divide_by 3 [get_nets {clk}] // 21.4912 Mhz

// HDMI clocks
create_clock -name hclk5 -period 2.6936 [get_nets {hclk5}]       // 371.25 Mhz

// NES/iosys to SDRAM, 3 fclk cycles
set_multicycle_path 3 -end -setup -from [get_clocks {clk}] -to [get_clocks {fclk}]
set_multicycle_path 2 -end -hold -from [get_clocks {clk}] -to [get_clocks {fclk}]

// SDRAM to NES/iosys, 2 fclk cycles
set_multicycle_path 2 -start -setup -from [get_clocks {fclk}] -to [get_clocks {clk}]
set_multicycle_path 1 -start -hold -from [get_clocks {fclk}] -to [get_clocks {clk}]

# report_timing -hold -from_clock [get_clocks {clk*}] -to_clock [get_clocks {clk*}] -max_paths 25 -max_common_paths 1
# report_timing -setup -from_clock [get_clocks {clk*}] -to_clock [get_clocks {clk*}] -max_paths 25 -max_common_paths 1
