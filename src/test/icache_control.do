vlib work


vlog "cache_control_testbench.sv" +incdir+ "../test.svh"
vlog "../lfsr.sv"
vsim -voptargs="+acc" -t 1ps -lib work cache_control_testbench


do cache_wave.do

view wave
view structure
view signals

run -all

