vlib work


vlog "../id_stage.sv"  +incdir+ ../test.svh
vlog "../instr_realigner.sv"  +incdir+ ../test.svh
vlog "../compressed_decoder.sv"  +incdir+ ../test.svh

vsim -voptargs="+acc" -t 1ps -lib work id_stage_testbench


do id_wave.do

view wave
view structure
view signals

run -all

