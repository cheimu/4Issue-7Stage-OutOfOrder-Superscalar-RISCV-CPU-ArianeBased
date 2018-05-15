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
// Date: 05.05.2017
// Description: Buffer to hold CSR address, this acts like a functional unit
//              to the scoreboard.

import ariane_pkg::*;

module csr_buffer (
    input  logic                          clk_i,          // Clock
    input  logic                          rst_ni,         // Asynchronous reset active low
    input  logic                          flush_i,

    input  fu_op [3:0]                    operator_i,
    input  logic [3:0][63:0]              operand_a_i,
    input  logic [3:0][63:0]              operand_b_i,
    input  logic [3:0][TRANS_ID_BITS-1:0] trans_id_i,     // transaction id, needed for WB

    output logic [3:0]                    csr_ready_o,    // FU is ready e.g. not busy
    input  logic [3:0]                    csr_valid_i,    // Input is valid
    output logic [3:0][TRANS_ID_BITS-1:0] csr_trans_id_o, // ID of scoreboard entry at which to write back
    output logic [3:0][63:0]              csr_result_o,
    output logic [3:0]                    csr_valid_o,    // transaction id for which the output is the requested one
    input  logic [3:0]                    commit_i,       // commit the pending CSR OP

    // to CSR file
    output logic  [3:0][11:0]             csr_addr_o      // CSR address to commit stage
);
    // this is a single entry store buffer for the address of the CSR
    // which we are going to need in the commit stage
    struct packed {
        logic [11:0] csr_address;
        logic        valid;
    } csr_reg_n[3:0], csr_reg_q[3:0];

    // control logic, scoreboard signals
    assign csr_trans_id_o[3:0] = trans_id_i[3:0];
    // CSR instructions for this post buffer are single cycle
    assign csr_valid_o[3:0]    = csr_valid_i[3:0];
    assign csr_result_o[3:0]   = operand_a_i[3:0];
    assign csr_addr_o[3:0]     = csr_reg_q.csr_address[3:0];

    // write logic
    always_comb begin : write
        csr_reg_n[3:0]  = csr_reg_q[3:0];
        // by default we are ready
        csr_ready_o[3:0] = 4'b1111;
        // if we have a valid uncomiited csr req or are just getting one WITHOUT a commit in, we are not ready
        if ((csr_reg_q.valid[3] || csr_valid_i[3]) && ~commit_i[3])
            csr_ready_o[3] = 1'b0;
	if ((csr_reg_q.valid[2] || csr_valid_i[2]) && ~commit_i[2])
            csr_ready_o[2] = 1'b0;
	if ((csr_reg_q.valid[1] || csr_valid_i[3]) && ~commit_i[1])
            csr_ready_o[1] = 1'b0;
	if ((csr_reg_q.valid[0] || csr_valid_i[0]) && ~commit_i[0])
            csr_ready_o[0] = 1'b0;
        // if we got a valid from the scoreboard
        // store the CSR address
        if (csr_valid_i[3]) begin
            csr_reg_n[3].csr_address = operand_b_i[3][11:0];
            csr_reg_n[3].valid       = 1'b1;
        end
	if (csr_valid_i[2]) begin
            csr_reg_n[2].csr_address = operand_b_i[2][11:0];
            csr_reg_n[2].valid       = 1'b1;
        end
	if (csr_valid_i[1]) begin
            csr_reg_n[1].csr_address = operand_b_i[1][11:0];
            csr_reg_n[1].valid       = 1'b1;
        end
	if (csr_valid_i[0]) begin
            csr_reg_n[0].csr_address = operand_b_i[0][11:0];
            csr_reg_n[0].valid       = 1'b1;
        end
        // if we get a commit and no new valid instruction -> clear the valid bit
        if (commit_i[3] && ~csr_valid_i[3]) begin
            csr_reg_n[3].valid       = 1'b0;
        end
	if (commit_i[2] && ~csr_valid_i[2]) begin
            csr_reg_n[2].valid       = 1'b0;
        end
 	if (commit_i[1] && ~csr_valid_i[1]) begin
            csr_reg_n[1].valid       = 1'b0;
        end
	if (commit_i[0] && ~csr_valid_i[0]) begin
            csr_reg_n[0].valid       = 1'b0;
        end
        // clear the buffer if we flushed
        if (flush_i)
            csr_reg_n[3:0].valid       = 4'b0;
    end
    // sequential process
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(~rst_ni) begin
            csr_reg_q[3:0] <= '{default: 0};
        end else begin
            csr_reg_q[3:0] <= csr_reg_n[3:0];
        end
    end

endmodule
