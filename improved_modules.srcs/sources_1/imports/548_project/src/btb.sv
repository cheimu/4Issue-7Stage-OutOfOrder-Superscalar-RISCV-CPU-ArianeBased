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
// Description: Branch Target Buffer implementation
//
// Copyright (C) 2017 ETH Zurich, University of Bologna
// All rights reserved.

import ariane_pkg::*;

module btb #(
    parameter int NR_ENTRIES = 1024,
    parameter int BITS_SATURATION_COUNTER = 2,
    parameter int BATCH_OFFSET = 2
    )
    (
    input  logic               clk_i,                     // Clock
    input  logic               rst_ni,                    // Asynchronous reset active low
    input  logic               flush_i,                   // flush the btb

    input  logic [63:0]        vpc_i,                     // virtual PC from IF stage
    input  branchpredict_t     branch_predict_i,          // a mis-predict happened -> update data structure
    output logic [1:0]         which_branch_taken_o,
    output branchpredict_sbe_t branch_predict_o           // branch prediction for issuing to the pipeline
);
    // number of bits which are not used for indexing
    localparam OFFSET = 2;
    localparam ANTIALIAS_BITS = 8;
    // number of bits we should use for prediction
    localparam PREDICTION_BITS = $clog2(NR_ENTRIES) + OFFSET;

    // typedef for all branch target entries
    // we may want to try to put a tag field that fills the rest of the PC in-order to mitigate aliasing effects
    struct packed {
        logic                                   valid;
        logic [63:0]                            target_address;
        logic [BITS_SATURATION_COUNTER-1:0]     saturation_counter;
        logic                                   is_lower_16;
        logic [ANTIALIAS_BITS-1:0]              anti_alias; // store some more PC information to prevent aliasing
    } btb_n [NR_ENTRIES-1:0], btb_q [NR_ENTRIES-1:0];

    logic [$clog2(NR_ENTRIES)-1:0]          index, update_pc, cur_index;
    logic [ANTIALIAS_BITS-1:0]              anti_alias_index, anti_alias_update_pc;
    logic [BITS_SATURATION_COUNTER-1:0]     saturation_counter;

    // get actual index positions
    // we ignore the 0th bit since all instructions are aligned on
    // a half word boundary
    assign update_pc = branch_predict_i.pc[PREDICTION_BITS - 1:OFFSET];
    
    // index of which blocks of table we are looking at
	assign cur_index = vpc_i[PREDICTION_BITS - 1:OFFSET];
    assign index     = {vpc_i[PREDICTION_BITS - 1:OFFSET + BATCH_OFFSET], 2'b00};
    // anti-alias portion of PCs
    assign anti_alias_update_pc = branch_predict_i.pc[PREDICTION_BITS + ANTIALIAS_BITS - 1:PREDICTION_BITS];
    assign anti_alias_index = vpc_i[PREDICTION_BITS + ANTIALIAS_BITS - 1:PREDICTION_BITS];

   // update batch prediction
    /*
    assign branch_predict_o.valid           = (btb_q[index].anti_alias == anti_alias_index) ? btb_q[index].valid :  1'b0;
    assign branch_predict_o.predict_taken   = btb_q[index].saturation_counter[BITS_SATURATION_COUNTER-1];
    assign branch_predict_o.predict_address = btb_q[index].target_address;
    assign branch_predict_o.is_lower_16     = btb_q[index].is_lower_16;
    */
    integer i;
    always_comb begin : prediction_results
        // default assignments
        branch_predict_o.valid = 0;
        which_branch_taken_o = 0;
        branch_predict_o.predict_taken = 0;
        branch_predict_o.is_lower_16 = 0;
        which_branch_taken_o = 0;  
        for (i=3;i>=0;i=i-1)
        begin
			if (cur_index <= index+i)
			begin
				// check whether it is a valid prediction
				if (btb_q[index+i].anti_alias == anti_alias_index)
				begin
					branch_predict_o.valid = btb_q[index+i].valid;
				end
				// first valid taken branch
				if ((btb_q[index+i].anti_alias == anti_alias_index) && btb_q[index+i].valid && btb_q[index+i].saturation_counter[BITS_SATURATION_COUNTER-1])
				begin
					branch_predict_o.predict_taken   = btb_q[index+i].saturation_counter[BITS_SATURATION_COUNTER-1];
					branch_predict_o.predict_address = btb_q[index+i].target_address;
					branch_predict_o.is_lower_16     = btb_q[index+i].is_lower_16;
					which_branch_taken_o = i;
				end
			end
        end
    end
    
    // -------------------------
    // Update Branch Prediction
    // -------------------------
    // update on a mis-predict
    always_comb begin : update_branch_predict
        btb_n              = btb_q;
        saturation_counter = btb_q[update_pc].saturation_counter;
        if (branch_predict_i.valid) begin

            btb_n[update_pc].valid = 1'b1;
            btb_n[update_pc].anti_alias = anti_alias_update_pc;
            // update saturation counter
            // first check if counter is already saturated in the positive regime e.g.: branch taken
            if (saturation_counter == {BITS_SATURATION_COUNTER{1'b1}}) begin
                // we can safely decrease it
                if (~branch_predict_i.is_taken)
                    btb_n[update_pc].saturation_counter = saturation_counter - 1;
            // then check if it saturated in the negative regime e.g.: branch not taken
            end else if (saturation_counter == {BITS_SATURATION_COUNTER{1'b0}}) begin
                // we can safely increase it
                if (branch_predict_i.is_taken)
                    btb_n[update_pc].saturation_counter = saturation_counter + 1;
            end else begin // otherwise we are not in any boundaries and can decrease or increase it
                if (branch_predict_i.is_taken)
                    btb_n[update_pc].saturation_counter = saturation_counter + 1;
                else
                    btb_n[update_pc].saturation_counter = saturation_counter - 1;
            end
            // the target address is simply updated
            btb_n[update_pc].target_address = branch_predict_i.target_address;
            // as is the information whether this was a compressed branch
            btb_n[update_pc].is_lower_16    = branch_predict_i.is_lower_16;
            // check if we should invalidate this entry, this happens in case we predicted a branch
            // where actually none-is (aliasing)
            if (branch_predict_i.clear) begin
                btb_n[update_pc].valid = 1'b0;
            end
        end
    end

    // sequential process
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(~rst_ni) begin
            // Bias the branches to be taken upon first arrival
            for (int i = 0; i < NR_ENTRIES; i++)
                btb_q[i] <= '{default: 0};
                for (int unsigned i = 0; i < NR_ENTRIES; i++)
                    btb_q[i].saturation_counter <= 2'b0;
        end else begin
            // evict all entries
            if (flush_i) begin
                for (int i = 0; i < NR_ENTRIES; i++) begin
                    btb_q[i].valid              <=  1'b0;
                    btb_q[i].saturation_counter <= '{default: 0};
                end
            end else begin
                btb_q <=  btb_n;
            end

        end
    end
endmodule

module btb_testbench;
    logic clk, rst, flush;
	logic[63:0] pc;
    branchpredict_t     branch_predict_up;          // a mis-predict happened -> update data structure
	logic [1:0] which;
	branchpredict_sbe_t branch_predict;           // branch prediction for issuing to the pipeline

	btb dut (
	.clk_i(clk),
	.rst_ni(rst),
	.flush_i(flush),
	.vpc_i(pc),
	.branch_predict_i(branch_predict_up),          
    .which_branch_taken_o(which),
    .branch_predict_o(branch_predict)
	);
    
	parameter CLOCK_PERIOD=1000;
     initial begin
     clk <= 0;
     forever #(CLOCK_PERIOD/2) clk <= ~clk;
     end
     integer i;
     // Set up the inputs to the design. Each line is a clock cycle.
     initial begin
     rst <= 0;@(posedge clk);
	 rst <= 1; pc = 0;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 0; branch_predict_up.pc = 0;branch_predict_up.target_address = 4;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 0; branch_predict_up.pc = 0;branch_predict_up.target_address = 4;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 0; branch_predict_up.pc = 0;branch_predict_up.target_address = 4;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 4;branch_predict_up.target_address = 1000;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 4;branch_predict_up.target_address = 1000;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 4;branch_predict_up.target_address = 1000;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 8;branch_predict_up.target_address = 1010;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 8;branch_predict_up.target_address = 1010;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 8;branch_predict_up.target_address = 1010;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 12;branch_predict_up.target_address = 1111;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 12;branch_predict_up.target_address = 1111;@(posedge clk);
	 branch_predict_up.valid = 1;branch_predict_up.is_mispredict = 1; branch_predict_up.is_taken = 1; branch_predict_up.pc = 12;branch_predict_up.target_address = 1111;@(posedge clk);
	 pc=8;@(posedge clk);
	 pc=12;@(posedge clk);
	 @(posedge clk);
     $stop; // End the simulation.
     end
endmodule

