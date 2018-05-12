vlib work


vlog "../icache.sv"
vlog "../../include/ariane_pkg.sv"

vsim -voptargs="+acc" -t 1ps -lib work icache_testbench


do icache.do

view wave
view structure
view signals

run -all

