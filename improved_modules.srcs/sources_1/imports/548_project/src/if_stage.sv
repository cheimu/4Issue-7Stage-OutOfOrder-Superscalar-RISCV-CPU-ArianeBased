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
// Date: 14.05.2017
// Description: Instruction fetch stage

import ariane_pkg::*;


typedef struct packed {
    logic [63:0]        address;
    logic               which_branch_taken;
    branchpredict_sbe_t branch_predict_to_fifo_0;
    branchpredict_sbe_t branch_predict_to_fifo_1;
    branchpredict_sbe_t branch_predict_to_fifo_2;
    branchpredict_sbe_t branch_predict_to_fifo_3;
    branchpredict_sbe_t branchpredict;
} address_fifo_t;

module if_stage (
    input  logic                   clk_i,               // Clock
    input  logic                   rst_ni,              // Asynchronous reset active low
    // control signals
    input  logic                   flush_i,
    output logic                   if_busy_o,           // is the IF stage busy fetching instructions?
    input  logic                   halt_i,
    // fetch direction from PC Gen
    input  logic [63:0]            fetch_address_i,     // TODO: use fetch_address and which branch to decided which instructions are valid to be  put into queue
    input  logic                   fetch_valid_i,       // the fetch address is valid
    input  branchpredict_sbe_t     branch_predict_i,    // TODO: make into an array of four
    input  branchpredict_sbe_t     brach_predict_to_fifo_i [3:0],
    input  logic [1:0]             which_branch_taken_i,// indicacte whether which instructions are taken
    // I$ Interface
    output logic                   instr_req_o,
    output logic [63:0]            instr_addr_o,
    input  logic                   instr_gnt_i,
    input  logic                   instr_rvalid_i,
    input  logic [127:0]           instr_rdata_i,         // instruction input (4 instructions at a time)
    input  exception_t             instr_ex_i,            // Instruction fetch exception, valid if rvalid is one
    // Output of IF Pipeline stage -> Dual Port Fetch FIFO
    // output port 0
    output fetch_entry_t           fetch_entry_0_o,       // fetch entry containing all relevant data for the ID stage
    output logic                   fetch_entry_valid_0_o, // instruction in IF is valid
    input  logic                   fetch_ack_0_i,         // ID acknowledged this instruction
    // output port 1
    output fetch_entry_t           fetch_entry_1_o,       // fetch entry containing all relevant data for the ID stage
    output logic                   fetch_entry_valid_1_o, // instruction in IF is valid
    input  logic                   fetch_ack_1_i,          // ID acknowledged this instruction
    // output port 2
    output fetch_entry_t           fetch_entry_2_o,       // fetch entry containing all relevant data for the ID stage
    output logic                   fetch_entry_valid_2_o, // instruction in IF is valid
    input  logic                   fetch_ack_2_i,          // ID acknowledged this instruction   
    // output port 3
    output fetch_entry_t           fetch_entry_3_o,       // fetch entry containing all relevant data for the ID stage
    output logic                   fetch_entry_valid_3_o, // instruction in IF is valid
    input  logic                   fetch_ack_3_i          // ID acknowledged this instruction
);

    enum logic [2:0] {IDLE, WAIT_GNT, WAIT_RVALID, WAIT_ABORTED, WAIT_ABORTED_REQUEST } CS, NS;
    logic [63:0]        instr_addr_n, instr_addr_q, fetch_address;
    branchpredict_sbe_t branchpredict_n, branchpredict_q;
    // Control signals
    address_fifo_t      push_data, pop_data;
    logic               fifo_valid, fifo_ready;
    logic               pop_empty; // pop the address queue in case of a flush, empty signal
    // Address queue status signals
    logic               empty, full, single_element;

    // We are busy if:
    // 1. we are either waiting for a grant
    // 2. or if the FIFO is full
    // 3. We are waiting for the current request to be aborted e.g.: we are waiting for the address queue to be empty
    // 4. the address queue is full (then we can handle any transaction anymore which we will commit to the memory hierarchy)
    // And all this is not true if we just flushed. That is the case that we unconditionally have to take the new PC on a flush
    // as the PC Gen stage is expecting this.
    assign if_busy_o = ((CS == WAIT_GNT) || !fifo_ready || (CS == WAIT_ABORTED_REQUEST) || full) && (CS != WAIT_ABORTED);
    assign fetch_address = {fetch_address_i[63:2], 2'b0};

    // --------------------------------------------------
    // Instruction Fetch FSM
    // Deals with Instruction Memory / Instruction Cache
    // --------------------------------------------------
    always_comb begin : instr_fetch_fsm

        NS            = CS;
        instr_req_o   = 1'b0;
        instr_addr_o  = fetch_address;
        push_data     = { fetch_address_i, which_branch_taken_i, brach_predict_to_fifo_i[0], brach_predict_to_fifo_i[1], brach_predict_to_fifo_i[2], brach_predict_to_fifo_i[3], branch_predict_i };
        fifo_valid    = instr_rvalid_i;
        pop_empty     = instr_rvalid_i; // only pop the address queue

        // get new data by default
        branchpredict_n = branch_predict_i;
        instr_addr_n    = fetch_address_i;

        case (CS)
            // we are idling, and can accept a new request
            IDLE: begin
                // check if we have space in the FIFOs and we want to do a request
                if (fifo_ready && fetch_valid_i && !full) begin
                    instr_req_o = 1'b1;
                    // did we get a grant?
                    if (instr_gnt_i)
                        // Yes, so wait for the rvalid
                        NS = WAIT_RVALID;
                    else
                        // No, so wait for it
                        NS = WAIT_GNT;
                end
            end

            // we sent a request but did not yet get a grant
            WAIT_GNT: begin
                instr_addr_o = {instr_addr_q[63:2], 2'b0};
                instr_req_o  = 1'b1;

                branchpredict_n = branchpredict_q;
                instr_addr_n    = instr_addr_q;

                if (instr_gnt_i) begin
                    // push the old data
                    push_data = { instr_addr_q, branchpredict_q };
                    // we have one outstanding rvalid: wait for it
                    if (flush_i)
                        NS = WAIT_ABORTED;
                    else
                        NS = WAIT_RVALID;
                end
            end

            WAIT_RVALID: begin
                instr_addr_o = fetch_address;

                // prepare for next request, we've got one if the fetch_valid_i is high
                // we can take it if both queues have still places left to store the request
                if (fifo_ready && fetch_valid_i && !full) begin

                    instr_req_o = 1'b1;

                    if (instr_gnt_i) begin
                        // we have one outstanding rvalid -> wait for it
                        NS = WAIT_RVALID;
                    end else begin
                        NS = WAIT_GNT; // lets wait for the grant
                    end
                end else begin
                    // go back to IDLE
                    NS = IDLE;
                end

            end
            // we save a potential new request here
            WAIT_ABORTED: begin
                // abort the current rvalid, we don't want it anymore
                fifo_valid = 1'b0;
                // we've got a new fetch here, the fetch FIFO is for sure empty as we just flushed it, but we still need to
                // wait for the address queue to be emptied
                if (fetch_valid_i && empty) begin
                    // re-do the request
                    if (instr_gnt_i)
                        NS = WAIT_RVALID;
                    else
                        NS = WAIT_GNT;
                end else if (fetch_valid_i) // the fetch is valid but the queue is not empty wait for it
                    NS = WAIT_ABORTED_REQUEST;
                else if (empty) // the fetch is not valid and the queue is empty we are back to normal operation
                    NS = IDLE;
            end

            // our last request was aborted, but we didn't yet get a rvalid
            WAIT_ABORTED_REQUEST: begin
                // abort the current rvalid, we don't want it anymore
                fifo_valid = 1'b0;
                // save request data
                branchpredict_n = branchpredict_q;
                instr_addr_n    = instr_addr_q;
                // here we wait for the queue to be empty, we do not make any new requests
                if (empty) // do the new request
                    NS = WAIT_GNT;
            end
        endcase
        // -------------
        // Flush
        // -------------
        if (flush_i) begin
            // if the address queue is empty this case is simple: just go back to idle
            // also if there is just a single element in the queue and we are commiting we can skip
            // waiting for all rvalids as the queue will be empty in the next cycle anyway
            if (empty && !(instr_req_o && instr_gnt_i))
                NS = IDLE;
            // if it wasn't empty we need to wait for all outstanding rvalids until we can make any further requests
            else
                NS = WAIT_ABORTED;
        end

        // -------------
        // Halt
        // -------------
        // halt the instruction interface if we halt the core:
        // the idea behind this is mainly in the case of an fence.i. For that instruction we need to flush both private caches
        // now it could be the case that the icache flush finishes earlier than the dcache flush (most likely even). In that case
        // a fetch can return stale data so we need to wait for the dcache flush to finish before making any new request.
        // The solution is to check if the core is halted and in that case do not make any new request.
        if (halt_i)
            instr_req_o = 1'b0;
    end

    // ---------------------------------
    // Address and Branch-predict Queue
    // ---------------------------------
    fifo #(
        .dtype            ( address_fifo_t          ),
        .DEPTH            ( 2                       )  // right now we support two outstanding transactions
    ) i_fifo (
        .flush_i          ( 1'b0                    ), // do not flush, we need to keep track of all outstanding rvalids
        .full_o           ( full                    ), // the address buffer is full
        .empty_o          ( empty                   ), // ...or empty
        .single_element_o ( single_element          ), // just a single element in the queue
        .data_i           ( push_data               ),
        .push_i           ( instr_gnt_i             ), // if we got a grant push the address and data
        .data_o           ( pop_data                ), // data we send to the fetch_fifo, along with the instr data which comes from memory
        .pop_i            ( fifo_valid || pop_empty ), // pop the data if we say that the fetch is valid
        .*
    );

    // ---------------------------------
    // Fetch FIFO
    // consumes addresses and rdata
    // ---------------------------------
    fetch_fifo i_fetch_fifo (
        .branch_predict_i   ( pop_data               ),
        .ex_i               ( instr_ex_i             ),
        .addr_i             ( pop_data.address       ),
        .rdata_i            ( instr_rdata_i          ),
        .valid_i            ( fifo_valid             ),
        .ready_o            ( fifo_ready             ),
        .*
    );

    //-------------
    // Registers
    //-------------
    always_ff @(posedge clk_i, negedge rst_ni) begin
      if (~rst_ni) begin
            CS              <= IDLE;
            instr_addr_q    <= '0;
            branchpredict_q <= '{default: 0};
        end else begin
            CS              <= NS;
            instr_addr_q    <= instr_addr_n;
            branchpredict_q <= branchpredict_n;
        end
    end
    //-------------
    // Assertions
    //-------------
    `ifndef SYNTHESIS
    `ifndef VERILATOR
        // there should never be a grant when there was no request
        assert property (
          @(posedge clk_i) (instr_gnt_i) |-> (instr_req_o) )
        else $warning("There was a grant without a request");
    `endif
    `endif
endmodule


module fetch_fifo
(
    input  logic                   clk_i,
    input  logic                   rst_ni,
    // control signals
    input  logic                   flush_i,    // clears the contents of the FIFO -> quasi reset
    // branch prediction at addr_i address, as this is an address and not PC it can be the case
    // that we have two compressed instruction (or one compressed instruction and one unaligned instruction) so we
    // only predict on one entry and discard (or keep) the other depending on its position and prediction.
    // input port
    input  address_fifo_t          branch_predict_i,
    input  exception_t             ex_i,              // fetch exception in
    input  logic [63:0]            addr_i,
    input  logic [127:0]           rdata_i,
    input  logic                   valid_i,
    output logic                   ready_o,
    // Four-Port Fetch FIFO
    // output port 0
    output fetch_entry_t           fetch_entry_0_o,
    output logic                   fetch_entry_valid_0_o,
    input  logic                   fetch_ack_0_i,
    // output port 1
    output fetch_entry_t           fetch_entry_1_o,
    output logic                   fetch_entry_valid_1_o,
    input  logic                   fetch_ack_1_i,
     // output port 2
    output fetch_entry_t           fetch_entry_2_o,
    output logic                   fetch_entry_valid_2_o,
    input  logic                   fetch_ack_2_i,
    // output port 3
    output fetch_entry_t           fetch_entry_3_o,
    output logic                   fetch_entry_valid_3_o,
    input  logic                   fetch_ack_3_i
);

    localparam int unsigned DEPTH = 16; // must be a power of two
    // status signals
    logic full, empty;

    fetch_entry_t                 mem_n[DEPTH-1:0], mem_q[DEPTH-1:0];
    logic [$clog2(DEPTH)-1:0]     read_pointer_n,   read_pointer_q;
    logic [$clog2(DEPTH)-1:0]     write_pointer_n,  write_pointer_q;
    logic [$clog2(DEPTH)-1:0]     status_cnt_n,     status_cnt_q; // this integer will be truncated by the synthesis tool
    logic [1:0]                   num_of_valid_fetched_instruction;
    // num of valid fetched instructions
    assign num_of_valid_fetched_instruction = (branch_predict_i.branchpredict.is_taken && branch_predict_i.branchpredict.valid)? (branch_predict_i.which_branch_taken - addr_i[3:2] + 1) : (4 - addr_i[3:2]);

    assign ready_o = (status_cnt_q < DEPTH-4);
    assign full = (status_cnt_q == DEPTH);
    assign empty = (status_cnt_q == '0);

    // downsizings are ignored
    /*
    logic [31:0] in_rdata;
    // downsize from 64 bit to 32 bit, simply ignore half of the incoming data
    always_comb begin : downsize
        // take the upper half
        if (addr_i[2])
            in_rdata = rdata_i[63:32];
        // take the lower half of the instruction
        else
            in_rdata = rdata_i[31:0];
    end
    */
    
    integer i;
    // only write valid instructions into buffer
    always_comb begin : fetch_fifo_logic
        // counter
        automatic logic [$clog2(DEPTH)-1:0] status_cnt;
        automatic logic [$clog2(DEPTH)-1:0] write_pointer;
        automatic logic [$clog2(DEPTH)-1:0] read_pointer;
        status_cnt    = status_cnt_q;
        write_pointer = write_pointer_q;
        read_pointer  = read_pointer_q;

        mem_n = mem_q;

        // -------------
        // Input Port
        // -------------
        if (valid_i) begin
            status_cnt = status_cnt + 4;
            // new input data
            // make sure instructions that are not in range is marked as invalid
            mem_n[write_pointer_q] = {{addr_i[63:4], 4'b0}, rdata_i[127:96], branch_predict_i.branch_predict_to_fifo_0, ex_i, (addr_i[3:2] <= 0 && (addr_i[3:2] + num_of_valid_fetched_instruction))> 0};
            write_pointer++;
            mem_n[write_pointer_q] = {{addr_i[63:4], 4'b100}, rdata_i[95:64], branch_predict_i.branch_predict_to_fifo_0, ex_i, (addr_i[3:2] <= 2'b1 && (addr_i[3:2] + num_of_valid_fetched_instruction))> 2'b1};
            write_pointer++;
            mem_n[write_pointer_q] = {{addr_i[63:4], 4'b1000}, rdata_i[63:32], branch_predict_i.branch_predict_to_fifo_0, ex_i, (addr_i[3:2] <= 2'b10 && (addr_i[3:2] + num_of_valid_fetched_instruction))> 2'b10};
            write_pointer++;
            mem_n[write_pointer_q] = {{addr_i[63:4], 4'b1100}, rdata_i[31:0], branch_predict_i.branch_predict_to_fifo_0, ex_i, (addr_i[3:2] <= 2'b11 && (addr_i[3:2] + num_of_valid_fetched_instruction))> 2'b11};
            write_pointer++;
        end


        // Increased # of read ports for if_stages
                
        // -------------
        // Fetch Port 0
        // -------------
        fetch_entry_valid_0_o = (status_cnt_q >= 1);
        fetch_entry_0_o = mem_q[read_pointer_q];

        if (fetch_ack_0_i) begin
            read_pointer++;
            status_cnt--;
        end

        // -------------
        // Fetch Port 1
        // -------------
        fetch_entry_valid_1_o = (status_cnt_q >= 2);
        fetch_entry_1_o = mem_q[read_pointer_q + 1'b1];

        if (fetch_ack_1_i) begin
            read_pointer++;
            status_cnt--;
        end
        // -------------
        // Fetch Port 2
        // -------------
        fetch_entry_valid_2_o = (status_cnt_q >= 3);
        fetch_entry_2_o = mem_q[read_pointer_q + 2'b10];

        if (fetch_ack_2_i) begin
            read_pointer++;
            status_cnt--;
        end

        // -------------
        // Fetch Port 3
        // -------------
        fetch_entry_valid_3_o = (status_cnt_q >= 4);
        fetch_entry_3_o = mem_q[read_pointer_q + 2'b11];

        if (fetch_ack_3_i) begin
            read_pointer++;
            status_cnt--;
        end

        write_pointer_n = write_pointer;
        status_cnt_n    = status_cnt;
        read_pointer_n  = read_pointer;

        if (flush_i) begin
            status_cnt_n    = '0;
            write_pointer_n = 'b0;
            read_pointer_n  = 'b0;
        end

    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            status_cnt_q              <= '{default: 0};
            mem_q                     <= '{default: 0};
            read_pointer_q            <= '{default: 0};
            write_pointer_q           <= '{default: 0};
        end else begin
            status_cnt_q              <= status_cnt_n;
            mem_q                     <= mem_n;
            read_pointer_q            <= read_pointer_n;
            write_pointer_q           <= write_pointer_n;
        end
    end
    //-------------
    // Assertions
    //-------------
    `ifndef SYNTHESIS
    `ifndef VERILATOR
    // Make sure we don't overflow the queue
    assert property (@(posedge clk_i) ((full && !flush_i) |-> ##1 !empty)) else $error("Fetch FIFO Overflowed");
    assert property (@(posedge clk_i) (flush_i || (status_cnt_q - status_cnt_n) <= 2 || (status_cnt_q - status_cnt_n) >= -2)) else $error("Fetch FIFO over- or underflowed");
    assert property (@(posedge clk_i) (valid_i |-> !full)) else $error("Got a valid signal, although the queue is not ready to accept a new request");
    `endif
    `endif
endmodule
