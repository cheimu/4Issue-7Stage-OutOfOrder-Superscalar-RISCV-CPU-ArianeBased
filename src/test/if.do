vlib work

vlog "../if_stage.sv" +incdir+ "../test.svh"
vlog "../fifo.sv" +incdir+ "../test.svh"

vsim -voptargs="+acc" -t 1ps -lib work if_testbench


do if_wave.do

view wave
view structure
view signals

run -all

