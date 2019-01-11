vlib work


vlog "../icache.sv"
vlog "icache_testbench.sv"
vlog "../bsg_mem_1r1w_sync_synth.sv"

vsim -voptargs="+acc" -t 1ps -lib work icache_testbench


do icache_wave.do

view wave
view structure
view signals

run -all

