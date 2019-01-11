
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
// Date: 19.04.2017
// Description: Instantiation of all functional units residing in the execute stage

import ariane_pkg::*;

module ex_stage #(
        parameter int          ASID_WIDTH       = 1,
        parameter logic [63:0] CACHE_START_ADDR = 64'h4000_0000,
        parameter int unsigned AXI_ID_WIDTH     = 10,
        parameter int unsigned AXI_USER_WIDTH   = 1
    )(
    input  logic                                   clk_i,    // Clock
    input  logic                                   rst_ni,   // Asynchronous reset active low
    input  logic                                   flush_i,

	input logic  [3:0]								    valid_i,
    input  fu_t  [3:0]                                  fu_i,
    input  fu_op [3:0]                                  operator_i,
    input  logic [3:0][63:0]                            operand_a_i,
    input  logic [3:0][63:0]                            operand_b_i,
    input  logic [3:0][63:0]                            imm_i,
    input  logic [3:0][TRANS_ID_BITS-1:0]               trans_id_i,
    input  logic [3:0][63:0]                            pc_i,                  // PC of current instruction
    input  logic [3:0]                                  is_compressed_instr_i, // we need to know if this was a compressed instruction
                                                                          // in order to calculate the next PC on a mis-predict
    // ALU 2
    output logic [1:0]                                  alu_ready_o,           // FU is ready
    output logic [1:0]                                  alu_valid_o,           // ALU result is valid
    output logic [1:0]                                  alu_branch_res_o,      // Branch comparison result
    output logic [1:0][63:0]                            alu_result_o,
    output logic [1:0][TRANS_ID_BITS-1:0]               alu_trans_id_o,        // ID of scoreboard entry at which to write back
    output exception_t[1:0]                             alu_exception_o,
    // Branches and Jumps
    output logic                                   branch_ready_o,
    output logic                                   branch_valid_o,        // the calculated branch target is valid
    output logic [63:0]                            branch_result_o,       // branch target address out
    input  branchpredict_sbe_t                     branch_predict_i,      // branch prediction in
    output logic [4:0]							   rename_index_o,
	input  logic [4:0]							   rename_index_i,
	output logic [TRANS_ID_BITS-1:0]               branch_trans_id_o,
    output exception_t                             branch_exception_o,    // branch unit detected an exception
    output branchpredict_t                         resolved_branch_o,     // the branch engine uses the write back from the ALU
    output logic                                   resolve_branch_o,      // to ID signaling that we resolved the branch
    // LSU
    output logic                                   lsu_ready_o,           // FU is ready
    output logic                                   lsu_valid_o,           // Output is valid
    output logic [63:0]                            lsu_result_o,
    output logic [TRANS_ID_BITS-1:0]               lsu_trans_id_o,
    input  logic                                   lsu_commit_i,
    output logic                                   lsu_commit_ready_o,    // commit queue is ready to accept another commit request
    output exception_t                             lsu_exception_o,
    output logic                                   no_st_pending_o,
    // CSR
    output logic                                   csr_ready_o,
    output logic [TRANS_ID_BITS-1:0]               csr_trans_id_o,
    output logic [63:0]                            csr_result_o,
    output logic                                   csr_valid_o,
    output logic [11:0]                            csr_addr_o,
    input  logic                                   csr_commit_i,
    // MULT
    output logic                                   mult_ready_o,      // FU is ready
    output logic [TRANS_ID_BITS-1:0]               mult_trans_id_o,
    output logic [63:0]                            mult_result_o,
    output logic                                   mult_valid_o,

    // Memory Management
    input  logic                                   enable_translation_i,
    input  logic                                   en_ld_st_translation_i,
    input  logic                                   flush_tlb_i,
    input  logic                                   fetch_req_i,
    output logic                                   fetch_gnt_o,
    output logic                                   fetch_valid_o,
    input  logic [63:0]                            fetch_vaddr_i,
    output logic [127:0]                            fetch_rdata_o,
    output exception_t                             fetch_ex_o,
    input  priv_lvl_t                              priv_lvl_i,
    input  priv_lvl_t                              ld_st_priv_lvl_i,
    input  logic                                   sum_i,
    input  logic                                   mxr_i,
    input  logic [43:0]                            satp_ppn_i,
    input  logic [ASID_WIDTH-1:0]                  asid_i,

    // Performance counters
    output logic                                   itlb_miss_o,
    output logic                                   dtlb_miss_o,
    output logic                                   dcache_miss_o,

    output logic [63:0]                            instr_if_address_o,
    output logic                                   instr_if_data_req_o,
    output logic [3:0]                             instr_if_data_be_o,
    input  logic                                   instr_if_data_gnt_i,
    input  logic                                   instr_if_data_rvalid_i,
    input  logic [127:0]                           instr_if_data_rdata_i,

    // DCache interface
    input  logic                                   dcache_en_i,
    input  logic                                   flush_dcache_i,
    output logic                                   flush_dcache_ack_o,
    // for testing purpose
	AXI_BUS.Master                                 data_if,
    AXI_BUS.Master                                 bypass_if
);


	/* 0 alu_0
	 * 1 alu_1
	 * 2 branch
	 * 3 mult 
	 * 4 lsu
	 * 5 csr
	*/
	logic [5:0][63:0] operand_a, operand_b;
	logic [5:0][TRANS_ID_BITS-1:0] trans_id;
	fu_op [5:0] op;              
	logic [5:0] is_compressed, valid;
	logic [5:0][63:0] pc;
    logic [5:0][63:0] imm;
	fu_t  [5:0] fu;
	logic       branch_comp_res;
	
	
	// operand assignment 
	always@(*)
	begin
		automatic logic [1:0] alu_cnt;
		alu_cnt = 2'b10;
		operand_a = '{default:0};
		operand_b = '{default:0};
		trans_id = '{default:0};
		op = '{default:ADD};
		is_compressed = 6'b0;
		valid = 6'b0;
		pc = '{default:0};
		imm = '{default:0};
		fu = '{default:NONE};
		rename_index_o = '0;
		for (int unsigned i=0;i<4;i++)
		begin
			if (valid_i[i])
			begin
				unique case (fu_i[i])
					ALU:
					begin
						if (alu_cnt == 2'b10)
						begin
							operand_a[0] = operand_a_i[i];
							operand_b[0] = operand_b_i[i];
							op[0] = operator_i[i];
							valid[0] = 1'b1;
							trans_id[0] = trans_id_i[i];
							alu_cnt--;
						end
						else 
						begin
							operand_a[1] = operand_a_i[i];
							operand_b[1] = operand_b_i[i];
							op[1] = operator_i[i];
							valid[1] = 1'b1;
							imm[1] = imm_i[i];
							trans_id[1] = trans_id_i[i];
							alu_cnt--;
						end
					end
					CTRL_FLOW:
					begin
						operand_a[2] = operand_a_i[i];
						operand_b[2] = operand_b_i[i];
						op[2] = operator_i[i];
						valid[2] = 1'b1;
						pc[2] = pc_i[i];
						rename_index_o = rename_index_i;
						is_compressed[2] = is_compressed_instr_i[i];
						trans_id[2] = trans_id_i[i];	
					end
					MULT:
					begin	
						operand_a[3] = operand_a_i[i];
						operand_b[3] = operand_b_i[i];
						op[3] = operator_i[i];
						valid[3] = 1'b1;
						pc[3] = pc_i[i];
						is_compressed[3] = is_compressed_instr_i[i];
						trans_id[3] = trans_id_i[i];
					end	
					LOAD, STORE:
					begin
						operand_a[4] = operand_a_i[i];
						operand_b[4] = operand_b_i[i];
						op[4] = operator_i[i];
						valid[4] = 1'b1;
						pc[4] = pc_i[i];
						is_compressed[4] = is_compressed_instr_i[i];
						trans_id[4] = trans_id_i[i];
					end
					CSR:
					begin
						operand_a[5] = operand_a_i[i];
						operand_b[5] = operand_b_i[i];
						op[5] = operator_i[i];
						valid[5] = 1'b1;
						pc[5] = pc_i[i];
						is_compressed[5] = is_compressed_instr_i[i];
						trans_id[5] = trans_id_i[i];
					end	
					default:;
				endcase
			end
		end
	end
	
    // -----
    // ALU 1 2
    // -----
    alu alu_0_i (
		.trans_id_i(trans_id[0]),
        .alu_valid_i(valid[0]),
        .operator_i(op[0]),
        .operand_a_i(operand_a[0]),
        .operand_b_i(operand_b[0]),
        .result_o(alu_result_o[0]),
        .alu_branch_res_o(alu_branch_res_o[0]),
        .alu_valid_o(alu_valid_o[0]),
        .alu_ready_o(alu_ready_o[0]),
        .alu_trans_id_o(alu_trans_id_o[0])
    );
	
	
	
	alu alu_1_i (
		.trans_id_i(trans_id[1]),
        .alu_valid_i(valid[1]),
        .operator_i(op[1]),
        .operand_a_i(operand_a[1]),
        .operand_b_i(operand_b[1]),
        .result_o(alu_result_o[1]),
        .alu_branch_res_o(alu_branch_res_o[1]),
        .alu_valid_o(alu_valid_o[1]),
        .alu_ready_o(alu_ready_o[1]),
        .alu_trans_id_o(alu_trans_id_o[1])
    );
    
	
	
	
	alu alu_branch_i (
		.trans_id_i(trans_id[2]),
        .alu_valid_i(valid[2]),
        .operator_i(op[2]),
        .operand_a_i(operand_a[2]),
        .operand_b_i(operand_b[2]),
        .result_o(),
        .alu_branch_res_o(branch_comp_res),
        .alu_valid_o(),
        .alu_ready_o(),
        .alu_trans_id_o()
    );

    // --------------------
    // Branch Engine
    // --------------------
    branch_unit branch_unit_i (
		 //.fu_valid_i          ( alu_valid_i || lsu_valid_i || csr_valid_i || mult_valid_i), // any functional unit is valid, check that there is no accidental mis-predict
		.trans_id_i(trans_id[2]),
		.operator_i(op[2]),             // comparison operation to perform
		.operand_a_i(operand_a[2]),            // contains content of RS 1
		.operand_b_i(operand_b[2]),            // contains content of RS 2
		.imm_i(imm[2]),                  // immediate to add to PC
		.pc_i(pc[2]),                   // PC of instruction
		.is_compressed_instr_i(is_compressed[2]),
		.fu_valid_i(1'b0),             // any functional unit is valid, check that there is no accidental mis-predict
		.branch_valid_i(valid[2]),
		.branch_comp_res_i(branch_comp_res),      // branch comparison result from ALU
		.*
    );

    // ----------------
    // Multiplication
    // ----------------
    mult i_mult (
		.trans_id_i(trans_id[3]),
		.mult_valid_i(valid[3]),
		.operator_i(op[3]),
		.operand_a_i(operand_a[3]),
		.operand_b_i(operand_b[3]),
		.result_o(mult_result_o),
		.*
    );

    // ----------------
    // Load-Store Unit
    // ----------------
    lsu #(
        .CACHE_START_ADDR ( CACHE_START_ADDR ),
        .AXI_ID_WIDTH     ( AXI_ID_WIDTH     ),
        .AXI_USER_WIDTH   ( AXI_USER_WIDTH   )
    ) lsu_i (
        .commit_i       ( lsu_commit_i       ),
        .commit_ready_o ( lsu_commit_ready_o ),
		.fu_i(fu[4]),            
		.operator_i(op[4]),
		.operand_a_i(operand_a[4]),
		.operand_b_i(operand_b[4]),
		.imm_i(imm[4]),
		.lsu_valid_i(valid[4]),              // Input is valid
		.trans_id_i(trans_id[4]),	
        .*
    );

    // -----
    // CSR
    // -----
    // CSR address buffer
    csr_buffer csr_buffer_i (
        .commit_i ( csr_commit_i  ),
		.operator_i(op[5]),
		.operand_a_i(operand_a[5]),
		.operand_b_i(operand_b[5]),
		.trans_id_i(trans_id[5]),
		.csr_valid_i(valid[5]),
        .*
    );
endmodule
