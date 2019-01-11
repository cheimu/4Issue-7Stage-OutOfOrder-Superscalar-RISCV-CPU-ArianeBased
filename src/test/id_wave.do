onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /id_stage_testbench/clk_i
add wave -noupdate /id_stage_testbench/fetch_entry_i_0
add wave -noupdate /id_stage_testbench/fetch_entry_i_1
add wave -noupdate /id_stage_testbench/fetch_entry_i_2
add wave -noupdate /id_stage_testbench/fetch_entry_i_3
add wave -noupdate /id_stage_testbench/fetch_entry_valid_i_0
add wave -noupdate /id_stage_testbench/fetch_entry_valid_i_1
add wave -noupdate /id_stage_testbench/fetch_entry_valid_i_2
add wave -noupdate /id_stage_testbench/fetch_entry_valid_i_3
add wave -noupdate /id_stage_testbench/decoded_instr_ack_o_0
add wave -noupdate /id_stage_testbench/decoded_instr_ack_o_1
add wave -noupdate /id_stage_testbench/decoded_instr_ack_o_2
add wave -noupdate /id_stage_testbench/decoded_instr_ack_o_3
add wave -noupdate /id_stage_testbench/issue_entry_o_0
add wave -noupdate /id_stage_testbench/issue_entry_o_1
add wave -noupdate /id_stage_testbench/issue_entry_o_2
add wave -noupdate /id_stage_testbench/issue_entry_o_3
add wave -noupdate /id_stage_testbench/issue_entry_valid_o_0
add wave -noupdate /id_stage_testbench/issue_entry_valid_o_1
add wave -noupdate /id_stage_testbench/issue_entry_valid_o_2
add wave -noupdate /id_stage_testbench/issue_entry_valid_o_3
add wave -noupdate /id_stage_testbench/is_ctrl_flow_o_0
add wave -noupdate /id_stage_testbench/is_ctrl_flow_o_1
add wave -noupdate /id_stage_testbench/is_ctrl_flow_o_2
add wave -noupdate /id_stage_testbench/is_ctrl_flow_o_3
add wave -noupdate /id_stage_testbench/issue_instr_ack_i_0
add wave -noupdate /id_stage_testbench/issue_instr_ack_i_1
add wave -noupdate /id_stage_testbench/issue_instr_ack_i_2
add wave -noupdate /id_stage_testbench/issue_instr_ack_i_3
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {125 ps} 0}
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
WaveRestoreZoom {0 ps} {825 ps}
