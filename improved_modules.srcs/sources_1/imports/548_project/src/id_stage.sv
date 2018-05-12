// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 15.04.2017
// Description: Description: Instruction decode, contains the logic for decode,
//              issue and read operands.

/*typedef struct packed {
		scoreboard_entry_t decoded;
		logic 			   valid;
	} decoded_entry_t;*/
import ariane_pkg::*;

module id_stage (
    input  logic                                     clk_i,     // Clock
    input  logic                                     rst_ni,    // Asynchronous reset active low

    input  logic                                     flush_i,
    // from IF
    input  fetch_entry_t                             fetch_entry_i_0,
	input  fetch_entry_t                             fetch_entry_i_1,
	input  fetch_entry_t                             fetch_entry_i_2,
	input  fetch_entry_t                             fetch_entry_i_3,
    input  logic                                     fetch_entry_valid_i_0,
	input  logic                                     fetch_entry_valid_i_1,
	input  logic                                     fetch_entry_valid_i_2,
	input  logic                                     fetch_entry_valid_i_3,
    output logic                                     decoded_instr_ack_o_0,
	output logic                                     decoded_instr_ack_o_1,
	output logic                                     decoded_instr_ack_o_2,
	output logic                                     decoded_instr_ack_o_3,	// acknowledge the instruction (fetch entry)

    // to ID
    output decoded_entry_t                        	 issue_entry_o_0,
	output decoded_entry_t                       	 issue_entry_o_1,
	output decoded_entry_t                       	 issue_entry_o_2,
	output decoded_entry_t                       	 issue_entry_o_3,	// a decoded instruction
    output logic                                     issue_entry_valid_o_0, // issue entry is valid
	output logic                                     issue_entry_valid_o_1,
	output logic                                     issue_entry_valid_o_2,
	output logic                                     issue_entry_valid_o_3,
    output logic                                     is_ctrl_flow_o_0,      // the instruction we issue is a ctrl flow instructions
	output logic                                     is_ctrl_flow_o_1,
	output logic                                     is_ctrl_flow_o_2,
	output logic                                     is_ctrl_flow_o_3,
    input  logic                                     issue_instr_ack_i_0,   // issue stage acknowledged sampling of instructions
	input  logic                                     issue_instr_ack_i_1,
	input  logic                                     issue_instr_ack_i_2,
	input  logic                                     issue_instr_ack_i_3,
    // from CSR file
    input  priv_lvl_t                                priv_lvl_i_0,          // current privilege level
	input  priv_lvl_t                                priv_lvl_i_1,
	input  priv_lvl_t                                priv_lvl_i_2,
	input  priv_lvl_t                                priv_lvl_i_3,
    input  logic                                     tvm_i_0,
	input  logic                                     tvm_i_1,
	input  logic                                     tvm_i_2,
	input  logic                                     tvm_i_3,
    input  logic                                     tw_i_0,
	input  logic                                     tw_i_1,
	input  logic                                     tw_i_2,
	input  logic                                     tw_i_3,
    input  logic                                     tsr_i_0,
	input  logic                                     tsr_i_1,
	input  logic                                     tsr_i_2,
	input  logic                                     tsr_i_3,
);
    // register stage
    struct packed {
        logic            valid;
        scoreboard_entry_t sbe;
        logic            is_ctrl_flow;

    } issue_n, issue_q;

    logic                is_control_flow_instr_0;
	logic                is_control_flow_instr_1;
	logic                is_control_flow_instr_2;
	logic                is_control_flow_instr_3;
	
    decoded_entry_t      decoded_instruction_0;
	decoded_entry_t      decoded_instruction_1;
	decoded_entry_t      decoded_instruction_2;
	decoded_entry_t      decoded_instruction_3;

    fetch_entry_t        fetch_entry_0;
	fetch_entry_t        fetch_entry_1;
	fetch_entry_t        fetch_entry_2;
	fetch_entry_t        fetch_entry_3;
	
    logic                is_illegal_0;
    logic                [31:0] instruction_0;
    logic                is_compressed_0;
    logic                fetch_ack_i_0;
    logic                fetch_entry_valid_0;
	logic                is_illegal_1;
    logic                [31:0] instruction_1;
    logic                is_compressed_1;
    logic                fetch_ack_i_1;
    logic                fetch_entry_valid_1;
	logic                is_illegal_2;
    logic                [31:0] instruction_2;
    logic                is_compressed_2;
    logic                fetch_ack_i_2;
    logic                fetch_entry_valid_2;
	logic                is_illegal_3;
    logic                [31:0] instruction_3;
    logic                is_compressed_3;
    logic                fetch_ack_i_3;
    logic                fetch_entry_valid_3;

    // ---------------------------------------------------------
    // 1. Re-align instructions
    // ---------------------------------------------------------
    instr_realigner instr_realigner_i_0	(
        .fetch_entry_0_i         ( fetch_entry_i_0               ),
        .fetch_entry_valid_0_i   ( fetch_entry_valid_i_0         ),
        .fetch_ack_0_o           ( decoded_instr_ack_o_0         ),

        .fetch_entry_o           ( fetch_entry_0                 ),
        .fetch_entry_valid_o     ( fetch_entry_valid_0           ),
        .fetch_ack_i             ( fetch_ack_i_0                 ),
        .*
    );
	instr_realigner instr_realigner_i_1 (
        .fetch_entry_0_i         ( fetch_entry_i_1               ),
        .fetch_entry_valid_0_i   ( fetch_entry_valid_i_1         ),
        .fetch_ack_0_o           ( decoded_instr_ack_o_1         ),

        .fetch_entry_o           ( fetch_entry_1                 ),
        .fetch_entry_valid_o     ( fetch_entry_valid_1           ),
        .fetch_ack_i             ( fetch_ack_i_1                 ),
        .*
    );
	instr_realigner instr_realigner_i_2 (
        .fetch_entry_0_i         ( fetch_entry_i_2               ),
        .fetch_entry_valid_0_i   ( fetch_entry_valid_i_2         ),
        .fetch_ack_0_o           ( decoded_instr_ack_o_2         ),

        .fetch_entry_o           ( fetch_entry_2                 ),
        .fetch_entry_valid_o     ( fetch_entry_valid_2           ),
        .fetch_ack_i             ( fetch_ack_i_2                 ),
        .*
    );
	instr_realigner instr_realigner_i_3 (
        .fetch_entry_0_i         ( fetch_entry_i_3               ),
        .fetch_entry_valid_0_i   ( fetch_entry_valid_i_3         ),
        .fetch_ack_0_o           ( decoded_instr_ack_o_3         ),

        .fetch_entry_o           ( fetch_entry_3                 ),
        .fetch_entry_valid_o     ( fetch_entry_valid_3           ),
        .fetch_ack_i             ( fetch_ack_i_3                 ),
        .*
    );
    // ---------------------------------------------------------
    // 2. Check if they are compressed and expand in case they are
    // ---------------------------------------------------------
    compressed_decoder compressed_decoder_i_0 (
        .instr_i                 ( fetch_entry_0.instruction     ),
        .instr_o                 ( instruction_0                 ),
        .illegal_instr_o         ( is_illegal_0                  ),
        .is_compressed_o         ( is_compressed_0               )

    );
	compressed_decoder compressed_decoder_i_1 (
        .instr_i                 ( fetch_entry_1.instruction     ),
        .instr_o                 ( instruction_1                 ),
        .illegal_instr_o         ( is_illegal_1                  ),
        .is_compressed_o         ( is_compressed_1               )

    );
	compressed_decoder compressed_decoder_i_2 (
        .instr_i                 ( fetch_entry_2.instruction     ),
        .instr_o                 ( instruction_2                 ),
        .illegal_instr_o         ( is_illegal_2                  ),
        .is_compressed_o         ( is_compressed_2               )

    );
	compressed_decoder compressed_decoder_i_3 (
        .instr_i                 ( fetch_entry_3.instruction     ),
        .instr_o                 ( instruction_3                 ),
        .illegal_instr_o         ( is_illegal_3                  ),
        .is_compressed_o         ( is_compressed_3               )

    );
    // ---------------------------------------------------------
    // 3. Decode and emit instruction to issue stage
    // ---------------------------------------------------------
    decoder decoder_i_0 (
        .pc_i                    ( fetch_entry_0.address         ),
        .is_compressed_i         ( is_compressed_0               ),
        .instruction_i           ( instruction_0                 ),
        .branch_predict_i        ( fetch_entry_0.branch_predict  ),
        .is_illegal_i            ( is_illegal_0                  ),
        .ex_i                    ( fetch_entry_0.ex              ),
        .instruction_o           ( decoded_instruction_0         ),
        .is_control_flow_instr_o ( is_control_flow_instr_0       ),
        .priv_lvl_i              ( priv_lvl_i_0                  ),              // current privilege level
		.tvm_i                   ( tvm_i_0                       ),                   // trap virtual memory
		.tw_i                    ( tw_i_0                        ),                    // timeout wait
		.tsr_i                   ( tsr_i_0                       ),                   // trap sret
    );
	decoder decoder_i_1 (
        .pc_i                    ( fetch_entry_1.address         ),
        .is_compressed_i         ( is_compressed_1               ),
        .instruction_i           ( instruction_1                 ),
        .branch_predict_i        ( fetch_entry_1.branch_predict  ),
        .is_illegal_i            ( is_illegal_1                  ),
        .ex_i                    ( fetch_entry_1.ex              ),
        .instruction_o           ( decoded_instruction_1         ),
        .is_control_flow_instr_o ( is_control_flow_instr_1       ),
        .priv_lvl_i              ( priv_lvl_i_1                  ),              // current privilege level
		.tvm_i                   ( tvm_i_1                       ),                   // trap virtual memory
		.tw_i                    ( tw_i_1                        ),                    // timeout wait
		.tsr_i                   ( tsr_i_1                       ),                   // trap sret
    );
	decoder decoder_i_2 (
        .pc_i                    ( fetch_entry_2.address         ),
        .is_compressed_i         ( is_compressed_2               ),
        .instruction_i           ( instruction_2                 ),
        .branch_predict_i        ( fetch_entry_2.branch_predict  ),
        .is_illegal_i            ( is_illegal_2                  ),
        .ex_i                    ( fetch_entry_2.ex              ),
        .instruction_o           ( decoded_instruction_2         ),
        .is_control_flow_instr_o ( is_control_flow_instr_2       ),
        .priv_lvl_i              ( priv_lvl_i_2                  ),              // current privilege level
		.tvm_i                   ( tvm_i_2                       ),                   // trap virtual memory
		.tw_i                    ( tw_i_2                        ),                    // timeout wait
		.tsr_i                   ( tsr_i_2                       ),                   // trap sret
    );
	decoder decoder_i_3 (
        .pc_i                    ( fetch_entry_3.address         ),
        .is_compressed_i         ( is_compressed_3               ),
        .instruction_i           ( instruction_3                 ),
        .branch_predict_i        ( fetch_entry_3.branch_predict  ),
        .is_illegal_i            ( is_illegal_3                  ),
        .ex_i                    ( fetch_entry_3.ex              ),
        .instruction_o           ( decoded_instruction_3         ),
        .is_control_flow_instr_o ( is_control_flow_instr_3       ),
        .priv_lvl_i              ( priv_lvl_i_3                  ),              // current privilege level
		.tvm_i                   ( tvm_i_3                       ),                   // trap virtual memory
		.tw_i                    ( tw_i_3                        ),                    // timeout wait
		.tsr_i                   ( tsr_i_3                       ),                   // trap sret
    );
	assign issue_entry_o_0.valid = fetch_entry_i_0.valid;
	assign issue_entry_o_1.valid = fetch_entry_i_1.valid;
	assign issue_entry_o_2.valid = fetch_entry_i_2.valid;
	assign issue_entry_o_3.valid = fetch_entry_i_3.valid;
    // ------------------
    // Pipeline Register
    // ------------------
    assign issue_entry_o_0 = issue_q_0.sbe;
	assign issue_entry_o_1 = issue_q_1.sbe;
	assign issue_entry_o_2 = issue_q_2.sbe;
	assign issue_entry_o_3 = issue_q_3.sbe;
	
    assign issue_entry_valid_o_0 = issue_q_0.valid;
	assign issue_entry_valid_o_1 = issue_q_1.valid;
	assign issue_entry_valid_o_2 = issue_q_2.valid;
	assign issue_entry_valid_o_3 = issue_q_3.valid;
	
    assign is_ctrl_flow_o_0 = issue_q_0.is_ctrl_flow;
	assign is_ctrl_flow_o_1 = issue_q_1.is_ctrl_flow;
	assign is_ctrl_flow_o_2 = issue_q_2.is_ctrl_flow;
	assign is_ctrl_flow_o_3 = issue_q_3.is_ctrl_flow;

    always_comb begin
        issue_n_0     = issue_q_0;
		issue_n_1     = issue_q_1;
		issue_n_2     = issue_q_2;
		issue_n_3     = issue_q_3;
		
        fetch_ack_i_0 = 1'b0;
		fetch_ack_i_1 = 1'b0;
		fetch_ack_i_2 = 1'b0;
		fetch_ack_i_3 = 1'b0;

        // Clear the valid flag if issue has acknowledged the instruction
        if (issue_instr_ack_i_0)
            issue_n.valid_0 = 1'b0;
		if (issue_instr_ack_i_0)
            issue_n.valid_1 = 1'b0;
		if (issue_instr_ack_i_0)
            issue_n.valid_2 = 1'b0;
		if (issue_instr_ack_i_0)
            issue_n.valid_3 = 1'b0;
			

        // if we have a space in the register and the fetch is valid, go get it
        // or the issue stage is currently acknowledging an instruction, which means that we will have space
        // for a new instruction
        if ((!issue_q_0.valid || issue_instr_ack_i_0) && fetch_entry_valid_0) begin
            fetch_ack_i_0 = 1'b1;
            issue_n_0 = {1'b1, decoded_instruction_0, is_control_flow_instr_0};
        end
		if ((!issue_q_1.valid || issue_instr_ack_i_1) && fetch_entry_valid_1) begin
            fetch_ack_i_1 = 1'b1;
            issue_n_1 = {1'b1, decoded_instruction_1, is_control_flow_instr_1};
        end
		if ((!issue_q_2.valid || issue_instr_ack_i_2) && fetch_entry_valid_2) begin
            fetch_ack_i_2 = 1'b1;
            issue_n_2 = {1'b1, decoded_instruction_2, is_control_flow_instr_2};
        end
		if ((!issue_q_3.valid || issue_instr_ack_i_3) && fetch_entry_valid_3) begin
            fetch_ack_i_3 = 1'b1;
            issue_n_3 = {1'b1, decoded_instruction_3, is_control_flow_instr_3};
        end

        // invalidate the pipeline register on a flush
        if (flush_i) begin
            issue_n_0.valid = 1'b0;
			issue_n_1.valid = 1'b0;
			issue_n_2.valid = 1'b0;
			issue_n_3.valid = 1'b0;
		endmodule
    end
    // -------------------------
    // Registers (ID <-> Issue)
    // -------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(~rst_ni) begin
            issue_q_0 <= '0;
			issue_q_1 <= '0;
			issue_q_2 <= '0;
			issue_q_3 <= '0;
        end else begin
            issue_q_0 <= issue_n_0;
			issue_q_1 <= issue_n_1;
			issue_q_2 <= issue_n_2;
			issue_q_3 <= issue_n_3;
        end
    end

endmodule
