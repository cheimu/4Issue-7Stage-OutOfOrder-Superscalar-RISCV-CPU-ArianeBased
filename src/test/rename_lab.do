vlib work


vlog "rename_stage.sv"

vsim -voptargs="+acc" -t 1ps -lib work rename_testbench


do rename_wave.do

view wave
view structure
view signals

run -all

