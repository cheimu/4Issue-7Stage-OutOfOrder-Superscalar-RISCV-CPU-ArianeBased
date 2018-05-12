vlib work


vlog "../id_stage.sv"
vlog "../instr_realigner.sv"
vlog "../compressed_decoder.sv"
vlog "../decoder.sv"
vlog "../../include/ariane_pkg.sv"

vsim -voptargs="+acc" -t 1ps -lib work id_stage_testbench


do id_stage.do

view wave
view structure
view signals

run -all

