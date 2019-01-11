vlib work

vlog "../reservation_station.sv"  +incdir+ ../test.svh
vlog "../rename_stage.sv"  +incdir+ ../test.svh
vlog "../ariane.sv" +incdir+ ../test.svh

vsim -voptargs="+acc" -t 1ps -lib work combine_testbench


do combine_wave.do

view wave
view structure
view signals

run -all

