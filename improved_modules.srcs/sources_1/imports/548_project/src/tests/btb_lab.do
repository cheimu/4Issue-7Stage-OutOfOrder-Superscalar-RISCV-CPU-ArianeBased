vlib work


vlog "../btb.sv"
vlog "../../include/ariane_pkg.sv"

vsim -voptargs="+acc" -t 1ps -lib work btb_testbench


do btb_wave.do

view wave
view structure
view signals

run -all

