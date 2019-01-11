vlib work

vlog "../cluster_clock_gating.sv"
vlog "../regfile.sv" +incdir+ "../test.svh"
vlog "../read_operands.sv" +incdir+ "../test.svh"
vsim -voptargs="+acc" -t 1ps -lib work read_operands_testbench


do read_wave.do

view wave
view structure
view signals

run -all

