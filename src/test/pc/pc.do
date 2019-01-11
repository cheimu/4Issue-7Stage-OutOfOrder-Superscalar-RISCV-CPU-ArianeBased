vlib work

vlog "../../pcgen_stage.sv" +incdir+ "../../test.svh"
vlog "../../btb.sv" +incdir+ "../../test.svh"

vsim -voptargs="+acc" -t 1ps -lib work pc_testbench


do pc_wave.do

view wave
view structure
view signals

run -all

