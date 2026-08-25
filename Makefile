# =====================================================================
# temp-sensor-chip Makefile
#
# Targets:
#   make sim-analog      full analog front-end sweep (ngspice)
#   make sim-analog-quick  single-point smoke test
#   make sim-rtl         iverilog RTL simulations (tb_i2c, tb_top)
#   make sim-rtl-verilator  verilator lint + sim
#   make model           generate t2f_model.v + calibration params
#   make synth           yosys synthesis to sky130_fd_sc_hd
#   make container-cmd   run a command inside the IIC-OSIC-TOOLS container
#   make clean
# =====================================================================

RTL     := rtl/i2c_slave.v rtl/temp_engine.v rtl/temp_regs.v rtl/temp_sensor_top.v
TB      := tb/i2c_master_model.v tb/t2f_model.v
IVERILOG := iverilog

.PHONY: sim-analog sim-analog-quick sim-rtl sim-rtl-verilator model synth clean container-cmd

# ---------------------------------------------------------------------
# Analog (ngspice, run inside the IIC-OSIC-TOOLS container)
# ---------------------------------------------------------------------
sim-analog:
	python3 scripts/run_analog.py --corners tt,ss,ff

sim-analog-quick:
	python3 scripts/run_analog.py --quick --corners tt

# ---------------------------------------------------------------------
# Digital RTL (iverilog; verilator also available in the container)
# ---------------------------------------------------------------------
sim-rtl: sim-rtl-i2c sim-rtl-top

sim-rtl-i2c:
	$(IVERILOG) -g2012 -Itb -o build/tb_i2c.out $(RTL) tb/i2c_master_model.v tb/tb_i2c.v
	vvp build/tb_i2c.out

sim-rtl-top:
	$(IVERILOG) -g2012 -Itb -o build/tb_top.out $(RTL) $(TB) tb/tb_top.v
	vvp build/tb_top.out

sim-rtl-verilator:
	verilator --lint-only -Wall -Wno-fatal rtl/temp_sensor_top.v rtl/i2c_slave.v rtl/temp_engine.v rtl/temp_regs.v

# ---------------------------------------------------------------------
# Calibration model from analog characterization
# ---------------------------------------------------------------------
model: analog/sim/results_tt.csv
	python3 scripts/gen_t2f_model.py

# ---------------------------------------------------------------------
# Synthesis (yosys -> sky130_fd_sc_hd netlist)
# ---------------------------------------------------------------------
synth:
	bash syn/run_synth.sh

# ---------------------------------------------------------------------
# Container helper:  make container-cmd CMD="make sim-rtl"
# ---------------------------------------------------------------------
container-cmd:
	bash scripts/run_in_container.sh "$(CMD)"

clean:
	rm -rf build analog/sim/_tb_* analog/sim/log_* analog/sim/*.csv analog/sim/*.png syn/out
