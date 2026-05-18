## Zybo Z7-10 Constraints File for RV32I + Stride Prefetcher
## Target: XC7Z010-1CLG400C

## ============================================================================
## Clock (125 MHz system clock)
## ============================================================================
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 8.000 -name sys_clk_pin -waveform {0.000 4.000} -add [get_ports clk]
create_generated_clock -name sys_clk -source [get_ports clk] -divide_by 2 [get_pins clk_div_reg/Q]

## ============================================================================
## Reset (active-low, active when pressed → active-low)
## Button BTN0
## ============================================================================
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports rst_n]

## ============================================================================
## Slide Switches
## ============================================================================
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {sw[3]}]

## ============================================================================
## LEDs
## ============================================================================
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {led[3]}]


create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_div_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 32 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {dbg_pc[0]} {dbg_pc[1]} {dbg_pc[2]} {dbg_pc[3]} {dbg_pc[4]} {dbg_pc[5]} {dbg_pc[6]} {dbg_pc[7]} {dbg_pc[8]} {dbg_pc[9]} {dbg_pc[10]} {dbg_pc[11]} {dbg_pc[12]} {dbg_pc[13]} {dbg_pc[14]} {dbg_pc[15]} {dbg_pc[16]} {dbg_pc[17]} {dbg_pc[18]} {dbg_pc[19]} {dbg_pc[20]} {dbg_pc[21]} {dbg_pc[22]} {dbg_pc[23]} {dbg_pc[24]} {dbg_pc[25]} {dbg_pc[26]} {dbg_pc[27]} {dbg_pc[28]} {dbg_pc[29]} {dbg_pc[30]} {dbg_pc[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 1 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list evt_hit_w]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list evt_pf_w]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_div_BUFG]
