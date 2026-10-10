# Build the "calc" overlay: the snickerdoodle/piSmasher base design plus an
# AXI-Lite integer calculator (calc_axi) on M_AXI_GP0.
# Produces calc.bit, calc.hwh and calc.xsa next to this script.

set here [file normalize [file dirname [info script]]]
set base_dir [file normalize ${here}/../boards/Snickerdoodle_piSmasher/base]
set proj_dir ${here}/build

create_project -force calc ${proj_dir} -part xc7z020clg400-3
add_files -norecurse ${here}/src/calc_axi.v

# Same block design as the base overlay (Ethernet, HDMI, audio), so the PL
# Ethernet path keeps working while this overlay is loaded.
source ${base_dir}/src/base_bd.tcl
create_bd_design calc
create_root_design ""
set_property CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {100} [get_bd_cells processing_system7_0]

# GP0 moves from the 200 MHz Ethernet clock (FCLK3, nothing else on GP0) to
# its own 100 MHz clock (FCLK2) for the calculator.
disconnect_bd_net [get_bd_nets processing_system7_0_FCLK_CLK3] \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]

create_bd_cell -type ip -vlnv [pynq_latest_vlnv proc_sys_reset] rst_calc
create_bd_cell -type ip -vlnv [pynq_latest_vlnv smartconnect] axi_smc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_smc]
create_bd_cell -type module -reference calc_axi calc_0

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK2] \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
    [get_bd_pins rst_calc/slowest_sync_clk] \
    [get_bd_pins axi_smc/aclk] \
    [get_bd_pins calc_0/s_axi_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET2_N] [get_bd_pins rst_calc/ext_reset_in]
connect_bd_net [get_bd_pins rst_calc/interconnect_aresetn] [get_bd_pins axi_smc/aresetn]
connect_bd_net [get_bd_pins rst_calc/peripheral_aresetn] [get_bd_pins calc_0/s_axi_aresetn]
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins calc_0/s_axi]

assign_bd_address -offset 0x43C00000 -range 64K [get_bd_addr_segs calc_0/s_axi/reg0]

validate_bd_design
save_bd_design

set bd_file [get_files calc.bd]
# Global synthesis: concurrent out-of-context IP runs crash Vivado 2025.2
# (SIGBUS at start-up) on this host.
set_property synth_checkpoint_mode None ${bd_file}
make_wrapper -files ${bd_file} -top
add_files -norecurse ${proj_dir}/calc.gen/sources_1/bd/calc/hdl/calc_wrapper.v
set_property top calc_wrapper [current_fileset]

add_files -fileset constrs_1 -norecurse ${base_dir}/src/piSmasher_4.1.xdc

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation failed"
}

open_run impl_1
report_utilization -cells [get_cells -hier -filter {ORIG_REF_NAME == calc_axi || REF_NAME == calc_axi}] \
    -file ${here}/calc_utilization.rpt
report_timing_summary -file ${here}/calc_timing.rpt

file copy -force ${proj_dir}/calc.runs/impl_1/calc_wrapper.bit ${here}/calc.bit
file copy -force ${proj_dir}/calc.gen/sources_1/bd/calc/hw_handoff/calc.hwh ${here}/calc.hwh
write_hw_platform -fixed -include_bit -force ${here}/calc.xsa
