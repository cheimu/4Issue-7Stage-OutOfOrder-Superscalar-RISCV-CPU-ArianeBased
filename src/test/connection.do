vlib work


vlog "connection.sv" +incdir+ "../test.svh"
vlog "../ariane.sv" +incdir+ "../test.svh"
vsim -voptargs="+acc" -t 1ps -lib work ariane


do connection_wave.do

view wave
view structure
view signals

run -all

