onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /if_testbench/clk_i
add wave -noupdate -radix unsigned /if_testbench/fetch_address_i
add wave -noupdate /if_testbench/if_busy_o
add wave -noupdate -radix unsigned /if_testbench/branch_predict_i
add wave -noupdate -radix unsigned /if_testbench/brach_predict_to_fifo_i
add wave -noupdate -radix unsigned /if_testbench/which_branch_taken_i
add wave -noupdate -radix unsigned /if_testbench/instr_req_o
add wave -noupdate -radix unsigned /if_testbench/instr_addr_o
add wave -noupdate -radix unsigned /if_testbench/instr_gnt_i
add wave -noupdate -radix unsigned /if_testbench/instr_rvalid_i
add wave -noupdate -radix unsigned /if_testbench/instr_rdata_i
add wave -noupdate -radix unsigned /if_testbench/instr_ex_i
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/rdata_i
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/mem_n
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/mem_q
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/read_pointer_n
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/read_pointer_q
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/write_pointer_n
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/write_pointer_q
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/fetch_entry_0_o
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/fetch_entry_valid_0_o
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/fetch_entry_1_o
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/fetch_entry_valid_1_o
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/fetch_entry_2_o
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/fetch_entry_valid_2_o
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/fetch_entry_3_o
add wave -noupdate -radix unsigned /if_testbench/dut/i_fetch_fifo/fetch_entry_valid_3_o
add wave -noupdate /if_testbench/dut/i_fifo/mem_n
add wave -noupdate /if_testbench/dut/i_fifo/mem_q
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {7924 ps} 0}
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
WaveRestoreZoom {4646 ps} {11238 ps}
