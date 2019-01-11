onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /commit_stage_testbench/clk_i
add wave -noupdate /commit_stage_testbench/halt_i
add wave -noupdate /commit_stage_testbench/flush_dcache_i
add wave -noupdate -subitemconfig {{/commit_stage_testbench/commit_instr_i[3]} {-childformat {{rs1 -radix decimal} {rs2 -radix decimal} {rd -radix decimal} {result -radix decimal}} -expand} {/commit_stage_testbench/commit_instr_i[3].rs1} {-radix decimal} {/commit_stage_testbench/commit_instr_i[3].rs2} {-radix decimal} {/commit_stage_testbench/commit_instr_i[3].rd} {-radix decimal} {/commit_stage_testbench/commit_instr_i[3].result} {-radix decimal}} /commit_stage_testbench/commit_instr_i
add wave -noupdate /commit_stage_testbench/commit_instr_valid_i
add wave -noupdate /commit_stage_testbench/commit_ack_o
add wave -noupdate /commit_stage_testbench/commit_lsu_ready_i
add wave -noupdate /commit_stage_testbench/commit_lsu_o
add wave -noupdate /commit_stage_testbench/exception_o
add wave -noupdate -radix decimal /commit_stage_testbench/waddr_a_o
add wave -noupdate -radix decimal /commit_stage_testbench/wdata_a_o
add wave -noupdate /commit_stage_testbench/we_a_o
add wave -noupdate -radix decimal /commit_stage_testbench/pc_o
add wave -noupdate -radix decimal /commit_stage_testbench/csr_rdata_i
add wave -noupdate /commit_stage_testbench/csr_exception_i
add wave -noupdate /commit_stage_testbench/csr_op_o
add wave -noupdate -radix decimal /commit_stage_testbench/csr_wdata_o
add wave -noupdate /commit_stage_testbench/no_st_pending_i
add wave -noupdate /commit_stage_testbench/fence_i_o
add wave -noupdate /commit_stage_testbench/fence_o
add wave -noupdate /commit_stage_testbench/sfence_vma_o
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {1 ns}

