`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/20/2018 12:06:16 AM
// Design Name: 
// Module Name: id_stage_testbench
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



module id_stage_testbench;
    logic                                     clk_i,     // Clock
    logic                                     rst_ni,    // Asynchronous reset active low

    logic                                     flush_i,
    // from IF
   
    logic                                     fetch_entry_valid_i_0,
	logic                                     fetch_entry_valid_i_1,
	logic                                     fetch_entry_valid_i_2,
	logic                                     fetch_entry_valid_i_3,
    logic                                     decoded_instr_ack_o_0,
	logic                                     decoded_instr_ack_o_1,
	logic                                     decoded_instr_ack_o_2,
	logic                                     decoded_instr_ack_o_3,	// acknowledge the instruction (fetch entry)

    // to ID
    decoded_entry_t                        	  issue_entry_o_0,
	decoded_entry_t                       	  issue_entry_o_1,
	decoded_entry_t                       	  issue_entry_o_2,
	decoded_entry_t                       	  issue_entry_o_3,	// a decoded instruction
    logic                                     issue_entry_valid_o_0, // issue entry is valid
	logic                                     issue_entry_valid_o_1,
	logic                                     issue_entry_valid_o_2,
	logic                                     issue_entry_valid_o_3,
    logic                                     is_ctrl_flow_o_0,      // the instruction we issue is a ctrl flow instructions
	logic                                     is_ctrl_flow_o_1,
	logic                                     is_ctrl_flow_o_2,
	logic                                     is_ctrl_flow_o_3,
    logic                                     issue_instr_ack_i_0,   // issue stage acknowledged sampling of instructions
	logic                                     issue_instr_ack_i_1,
	logic                                     issue_instr_ack_i_2,
	logic                                     issue_instr_ack_i_3,
    // from CSR file
    priv_lvl_t                                priv_lvl_i_0,          // current privilege level
	priv_lvl_t                                priv_lvl_i_1,
	priv_lvl_t                                priv_lvl_i_2,
	priv_lvl_t                                priv_lvl_i_3,
    logic                                     tvm_i_0,
	logic                                     tvm_i_1,
	logic                                     tvm_i_2,
	logic                                     tvm_i_3,
    logic                                     tw_i_0,
	logic                                     tw_i_1,
	logic                                     tw_i_2,
	logic                                     tw_i_3,
    logic                                     tsr_i_0,
	logic                                     tsr_i_1,
	logic                                     tsr_i_2,
	logic                                     tsr_i_3,
	
	id_stage dut(.*);
    
	parameter CLOCK_PERIOD=1000;
     initial begin
     clk_i <= 0;
     forever #(CLOCK_PERIOD/2) clk_i <= ~clk_i;
     end
     integer i;
     // Set up the inputs to the design. Each line is a clock cycle.
     initial begin
     rst_ni <= 0;@(posedge clk_i);
	 rst_ni <= 1;@(posedge clk_i);
	 @(posedge clk_i);
	 @(posedge clk_i);
	 @(posedge clk_i);
	 @(posedge clk_i);
	 @(posedge clk_i);
     $stop; // End the simulation.
     end
endmodule
