onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /cache_control_testbench/WAY_SIZE
add wave -noupdate -radix unsigned /cache_control_testbench/CACHE_SIZE
add wave -noupdate -radix unsigned /cache_control_testbench/CACHE_LINE
add wave -noupdate /cache_control_testbench/NB_WAYS
add wave -noupdate /cache_control_testbench/SCM_NUM_ROWS
add wave -noupdate /cache_control_testbench/SCM_TAG_ADDR_WIDTH
add wave -noupdate -radix unsigned /cache_control_testbench/clk_i
add wave -noupdate -radix unsigned /cache_control_testbench/fetch_req_i
add wave -noupdate -radix unsigned /cache_control_testbench/fetch_addr_i
add wave -noupdate -radix unsigned /cache_control_testbench/fetch_gnt_o
add wave -noupdate -radix unsigned /cache_control_testbench/fetch_rvalid_o
add wave -noupdate -radix unsigned /cache_control_testbench/fetch_rdata_o
add wave -noupdate -radix unsigned -childformat {{{/cache_control_testbench/DATA_req_o[3]} -radix unsigned} {{/cache_control_testbench/DATA_req_o[2]} -radix unsigned} {{/cache_control_testbench/DATA_req_o[1]} -radix unsigned} {{/cache_control_testbench/DATA_req_o[0]} -radix unsigned}} -expand -subitemconfig {{/cache_control_testbench/DATA_req_o[3]} {-radix unsigned} {/cache_control_testbench/DATA_req_o[2]} {-radix unsigned} {/cache_control_testbench/DATA_req_o[1]} {-radix unsigned} {/cache_control_testbench/DATA_req_o[0]} {-radix unsigned}} /cache_control_testbench/DATA_req_o
add wave -noupdate -radix unsigned /cache_control_testbench/DATA_we_o
add wave -noupdate -radix unsigned /cache_control_testbench/DATA_addr_o
add wave -noupdate -radix unsigned /cache_control_testbench/DATA_rdata_i
add wave -noupdate -radix unsigned /cache_control_testbench/DATA_wdata_o
add wave -noupdate -radix unsigned /cache_control_testbench/TAG_req_o
add wave -noupdate -radix unsigned /cache_control_testbench/TAG_addr_o
add wave -noupdate -radix unsigned /cache_control_testbench/TAG_rdata_i
add wave -noupdate -radix unsigned -childformat {{{/cache_control_testbench/TAG_wdata_o[43]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[42]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[41]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[40]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[39]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[38]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[37]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[36]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[35]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[34]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[33]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[32]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[31]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[30]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[29]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[28]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[27]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[26]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[25]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[24]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[23]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[22]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[21]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[20]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[19]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[18]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[17]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[16]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[15]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[14]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[13]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[12]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[11]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[10]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[9]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[8]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[7]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[6]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[5]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[4]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[3]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[2]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[1]} -radix unsigned} {{/cache_control_testbench/TAG_wdata_o[0]} -radix unsigned}} -subitemconfig {{/cache_control_testbench/TAG_wdata_o[43]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[42]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[41]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[40]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[39]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[38]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[37]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[36]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[35]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[34]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[33]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[32]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[31]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[30]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[29]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[28]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[27]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[26]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[25]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[24]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[23]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[22]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[21]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[20]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[19]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[18]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[17]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[16]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[15]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[14]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[13]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[12]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[11]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[10]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[9]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[8]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[7]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[6]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[5]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[4]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[3]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[2]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[1]} {-radix unsigned} {/cache_control_testbench/TAG_wdata_o[0]} {-radix unsigned}} /cache_control_testbench/TAG_wdata_o
add wave -noupdate -radix unsigned /cache_control_testbench/TAG_we_o
add wave -noupdate -radix unsigned /cache_control_testbench/refill_req_o
add wave -noupdate -radix unsigned /cache_control_testbench/refill_gnt_i
add wave -noupdate -radix unsigned /cache_control_testbench/refill_type_o
add wave -noupdate -radix unsigned /cache_control_testbench/refill_addr_o
add wave -noupdate -radix unsigned /cache_control_testbench/refill_r_valid_i
add wave -noupdate -radix unsigned /cache_control_testbench/refill_r_data_i
add wave -noupdate -radix unsigned /cache_control_testbench/refill_r_last_i
add wave -noupdate /cache_control_testbench/dut/CS
add wave -noupdate /cache_control_testbench/dut/NS
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {140215 ps} 0}
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
WaveRestoreZoom {119451 ps} {145819 ps}
