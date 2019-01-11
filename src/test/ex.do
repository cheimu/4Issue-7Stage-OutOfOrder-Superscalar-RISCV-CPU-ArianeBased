vlib work

vlog "../ex_stage.sv" +incdir+ "../test.svh"

vsim -voptargs="+acc" -t 1ps -lib work ex_testbench


do ex_wave.do

view wave
view structure
view signals

run -all

