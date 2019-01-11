vlib work

vlog "../reservation_station.sv" +incdir+ "../test.svh"

vsim -voptargs="+acc" -t 1ps -lib work reservation_testbench


do reserve_wave.do

view wave
view structure
view signals

run -all

