onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /pc_testbench/CLOCK_PERIOD
add wave -noupdate -radix unsigned /pc_testbench/clk_i
add wave -noupdate -radix unsigned /pc_testbench/fetch_enable_i
add wave -noupdate -radix unsigned /pc_testbench/if_ready_i
add wave -noupdate -radix unsigned /pc_testbench/resolved_branch_i
add wave -noupdate -radix unsigned /pc_testbench/fetch_address_o
add wave -noupdate -radix unsigned /pc_testbench/fetch_valid_o
add wave -noupdate -radix unsigned /pc_testbench/which_branch_taken_o
add wave -noupdate -radix unsigned /pc_testbench/branch_predict_o
add wave -noupdate -radix unsigned /pc_testbench/branch_predict_to_fifo_o
add wave -noupdate -radix unsigned -childformat {{{/pc_testbench/dut/btb_i/btb_n[7]} -radix unsigned} {{/pc_testbench/dut/btb_i/btb_n[6]} -radix unsigned} {{/pc_testbench/dut/btb_i/btb_n[5]} -radix unsigned} {{/pc_testbench/dut/btb_i/btb_n[4]} -radix unsigned} {{/pc_testbench/dut/btb_i/btb_n[3]} -radix unsigned} {{/pc_testbench/dut/btb_i/btb_n[2]} -radix unsigned} {{/pc_testbench/dut/btb_i/btb_n[1]} -radix unsigned} {{/pc_testbench/dut/btb_i/btb_n[0]} -radix unsigned}} -expand -subitemconfig {{/pc_testbench/dut/btb_i/btb_n[7]} {-height 15 -radix unsigned} {/pc_testbench/dut/btb_i/btb_n[6]} {-height 15 -radix unsigned} {/pc_testbench/dut/btb_i/btb_n[5]} {-height 15 -radix unsigned} {/pc_testbench/dut/btb_i/btb_n[4]} {-height 15 -radix unsigned} {/pc_testbench/dut/btb_i/btb_n[3]} {-height 15 -radix unsigned} {/pc_testbench/dut/btb_i/btb_n[2]} {-height 15 -radix unsigned} {/pc_testbench/dut/btb_i/btb_n[1]} {-height 15 -radix unsigned} {/pc_testbench/dut/btb_i/btb_n[0]} {-height 15 -radix unsigned}} /pc_testbench/dut/btb_i/btb_n
add wave -noupdate -radix unsigned /pc_testbench/dut/btb_i/btb_q
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {124 ps} 0}
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
