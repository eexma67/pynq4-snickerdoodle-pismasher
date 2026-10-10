# Build the PYNQ base overlay for snickerdoodle black on piSmasher 4.1.
# Produces base.bit, base.hwh and base.xsa next to this script.

set here [file normalize [file dirname [info script]]]
set proj_dir ${here}/build

create_project -force base ${proj_dir} -part xc7z020clg400-3

source ${here}/src/base_bd.tcl
create_bd_design base
create_root_design ""

# FCLK2 is unused; krtkl's 150 MHz request lands on 153.8 MHz, which PYNQ
# cannot reproduce when it reprograms the clocks, so use 100 MHz.
set_property CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {100} [get_bd_cells processing_system7_0]

# HWH metadata for PYNQ is generated with the block design.
validate_bd_design
save_bd_design

set bd_file [get_files base.bd]
# Global synthesis: concurrent out-of-context IP runs crash Vivado 2025.2
# (SIGBUS at start-up) on this host.
set_property synth_checkpoint_mode None ${bd_file}
make_wrapper -files ${bd_file} -top
add_files -norecurse ${proj_dir}/base.gen/sources_1/bd/base/hdl/base_wrapper.v
set_property top base_wrapper [current_fileset]

add_files -fileset constrs_1 -norecurse ${here}/src/piSmasher_4.1.xdc

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation failed"
}

file copy -force ${proj_dir}/base.runs/impl_1/base_wrapper.bit ${here}/base.bit
file copy -force ${proj_dir}/base.gen/sources_1/bd/base/hw_handoff/base.hwh ${here}/base.hwh
write_hw_platform -fixed -include_bit -force ${here}/base.xsa
