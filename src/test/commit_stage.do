vlib work


vlog "../commit_stage.sv" +incdir+ "../test.svh"

vsim -voptargs="+acc" -t 1ps -lib work commit_stage_testbench


do commit_stage_wave.do

view wave
view structure
view signals

run -all
