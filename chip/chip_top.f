// =====================================================================
// chip_top.f -- filelist for the merged chip netlist
//
// Order matters only in that the digital macro is a gate-level netlist
// whose cells are defined by the ICS55 models that follow it.
//
// Pass the defines on the command line:
//     +define+CHIP_SIM +define+CHIP_SIM_POR_NS=20000
// =====================================================================

// ---- chip-level structural netlist and macro views -------------------
../rtl/chip_top.v
../rtl/t2f_afe.v
../rtl/t2f_inbuf.v
../rtl/clkgen.v
../rtl/por.v
../rtl/pad_signal.v

// ---- digital macro: hardened ICS55 netlist ---------------------------
// (gunzip pnr/ics55/netlist/temp_sensor_block_route.v.gz first)
temp_sensor_block_route.v
