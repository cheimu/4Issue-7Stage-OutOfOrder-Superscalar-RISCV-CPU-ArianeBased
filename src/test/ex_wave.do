onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /ex_testbench/valid_i
add wave -noupdate -radix unsigned /ex_testbench/fu_i
add wave -noupdate -radix unsigned /ex_testbench/operator_i
add wave -noupdate -radix unsigned /ex_testbench/operand_a_i
add wave -noupdate -radix unsigned /ex_testbench/operand_b_i
add wave -noupdate -radix unsigned /ex_testbench/imm_i
add wave -noupdate -radix unsigned /ex_testbench/trans_id_i
add wave -noupdate -radix unsigned /ex_testbench/pc_i
add wave -noupdate -radix unsigned /ex_testbench/is_compressed_instr_i
add wave -noupdate -radix unsigned /ex_testbench/dut/operand_a
add wave -noupdate -radix unsigned /ex_testbench/dut/operand_b
add wave -noupdate -radix unsigned /ex_testbench/dut/trans_id
add wave -noupdate -radix unsigned /ex_testbench/dut/op
add wave -noupdate -radix unsigned /ex_testbench/dut/is_compressed
add wave -noupdate -radix unsigned /ex_testbench/dut/valid
add wave -noupdate -radix unsigned /ex_testbench/dut/pc
add wave -noupdate -radix unsigned /ex_testbench/dut/imm
add wave -noupdate -radix unsigned /ex_testbench/dut/fu
add wave -noupdate -radix unsigned /ex_testbench/alu_ready_o
add wave -noupdate -radix unsigned /ex_testbench/alu_valid_i
add wave -noupdate -radix unsigned /ex_testbench/alu_valid_o
add wave -noupdate -radix unsigned /ex_testbench/alu_branch_res_o
add wave -noupdate -radix unsigned -childformat {{{/ex_testbench/alu_result_o[1]} -radix unsigned} {{/ex_testbench/alu_result_o[0]} -radix decimal}} -expand -subitemconfig {{/ex_testbench/alu_result_o[1]} {-radix unsigned} {/ex_testbench/alu_result_o[0]} {-radix decimal}} /ex_testbench/alu_result_o
add wave -noupdate -radix unsigned /ex_testbench/alu_trans_id_o
add wave -noupdate -radix unsigned /ex_testbench/alu_exception_o
add wave -noupdate -radix unsigned /ex_testbench/branch_ready_o
add wave -noupdate -radix unsigned /ex_testbench/branch_valid_i
add wave -noupdate -radix unsigned /ex_testbench/branch_valid_o
add wave -noupdate -radix unsigned /ex_testbench/branch_result_o
add wave -noupdate -radix unsigned /ex_testbench/branch_predict_i
add wave -noupdate -radix unsigned /ex_testbench/branch_trans_id_o
add wave -noupdate -radix unsigned /ex_testbench/branch_exception_o
add wave -noupdate -radix unsigned /ex_testbench/resolved_branch_o
add wave -noupdate -radix unsigned /ex_testbench/resolve_branch_o
add wave -noupdate -radix unsigned /ex_testbench/lsu_ready_o
add wave -noupdate -radix unsigned /ex_testbench/lsu_valid_i
add wave -noupdate -radix unsigned /ex_testbench/lsu_valid_o
add wave -noupdate -radix unsigned /ex_testbench/lsu_result_o
add wave -noupdate -radix unsigned /ex_testbench/lsu_trans_id_o
add wave -noupdate -radix unsigned /ex_testbench/lsu_commit_i
add wave -noupdate -radix unsigned /ex_testbench/lsu_commit_ready_o
add wave -noupdate -radix unsigned /ex_testbench/lsu_exception_o
add wave -noupdate -radix unsigned /ex_testbench/no_st_pending_o
add wave -noupdate -radix unsigned /ex_testbench/csr_ready_o
add wave -noupdate -radix unsigned /ex_testbench/csr_valid_i
add wave -noupdate -radix unsigned /ex_testbench/csr_trans_id_o
add wave -noupdate -radix unsigned /ex_testbench/csr_result_o
add wave -noupdate -radix unsigned /ex_testbench/csr_valid_o
add wave -noupdate -radix unsigned /ex_testbench/csr_addr_o
add wave -noupdate -radix unsigned /ex_testbench/csr_commit_i
add wave -noupdate -radix unsigned /ex_testbench/mult_ready_o
add wave -noupdate -radix unsigned /ex_testbench/mult_valid_i
add wave -noupdate -radix unsigned /ex_testbench/mult_trans_id_o
add wave -noupdate -radix unsigned /ex_testbench/mult_result_o
add wave -noupdate -radix unsigned /ex_testbench/mult_valid_o
add wave -noupdate -radix unsigned /ex_testbench/enable_translation_i
add wave -noupdate -radix unsigned /ex_testbench/en_ld_st_translation_i
add wave -noupdate -radix unsigned /ex_testbench/flush_tlb_i
add wave -noupdate -radix unsigned /ex_testbench/fetch_req_i
add wave -noupdate -radix unsigned /ex_testbench/fetch_gnt_o
add wave -noupdate -radix unsigned /ex_testbench/fetch_valid_o
add wave -noupdate -radix unsigned /ex_testbench/fetch_vaddr_i
add wave -noupdate -radix unsigned /ex_testbench/fetch_rdata_o
add wave -noupdate -radix unsigned /ex_testbench/fetch_ex_o
add wave -noupdate -radix unsigned /ex_testbench/priv_lvl_i
add wave -noupdate -radix unsigned /ex_testbench/ld_st_priv_lvl_i
add wave -noupdate -radix unsigned /ex_testbench/sum_i
add wave -noupdate -radix unsigned /ex_testbench/mxr_i
add wave -noupdate -radix unsigned /ex_testbench/satp_ppn_i
add wave -noupdate -radix unsigned /ex_testbench/asid_i
add wave -noupdate -radix unsigned /ex_testbench/itlb_miss_o
add wave -noupdate -radix unsigned /ex_testbench/dtlb_miss_o
add wave -noupdate -radix unsigned /ex_testbench/dcache_miss_o
add wave -noupdate -radix unsigned /ex_testbench/instr_if_address_o
add wave -noupdate -radix unsigned /ex_testbench/instr_if_data_req_o
add wave -noupdate -radix unsigned /ex_testbench/instr_if_data_be_o
add wave -noupdate -radix unsigned /ex_testbench/instr_if_data_gnt_i
add wave -noupdate -radix unsigned /ex_testbench/instr_if_data_rvalid_i
add wave -noupdate -radix unsigned /ex_testbench/instr_if_data_rdata_i
add wave -noupdate -radix unsigned /ex_testbench/dcache_en_i
add wave -noupdate -radix unsigned /ex_testbench/flush_dcache_i
add wave -noupdate -radix unsigned /ex_testbench/flush_dcache_ack_o
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2105 ps} 0}
quietly wave cursor active 1
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
WaveRestoreZoom {1718 ps} {2542 ps}
