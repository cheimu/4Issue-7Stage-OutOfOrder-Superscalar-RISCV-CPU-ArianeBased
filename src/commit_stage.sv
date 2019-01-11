
import ariane_pkg::*;

//import ariane_pkg::*;

module commit_stage #(
		parameter integer NR_WB_PORTS = 4
)		
(
    input  logic                clk_i,
    input  logic                halt_i,             // request to halt the core
    input  logic                flush_dcache_i,     // request to flush dcache -> also flush the pipeline

    output exception_t          exception_o,        // take exception to controller

    // from scoreboard
    input  scoreboard_entry_t [NR_WB_PORTS-1:0]  commit_instr_i,     // the instruction we want to commit
    input  logic 		      [NR_WB_PORTS-1:0]  commit_instr_valid_i,	 // it is possible that some instruction included are not ready
    output logic              [NR_WB_PORTS-1:0]  commit_ack_o,       // acknowledge that we are indeed committing

    // to register file
    output  logic[NR_WB_PORTS-1:0][6:0]          waddr_a_o,          // register file write address
    output  logic[NR_WB_PORTS-1:0][63:0]         wdata_a_o,          // register file write data
    output  logic[NR_WB_PORTS-1:0]               we_a_o,             // register file write enable

    // to CSR file and PC Gen (because on certain CSR instructions we'll need to flush the whole pipeline)
    output logic [NR_WB_PORTS-1:0][63:0]         pc_o,
    // to/from CSR file
    output fu_op                csr_op_o,           // decoded CSR operation
    output logic [63:0]         csr_wdata_o,        // data to write to CSR
    input  logic [63:0]         csr_rdata_i,        // data to read from CSR
    input  exception_t          csr_exception_i,    // exception or interrupt occurred in CSR stage (the same as commit)
    // commit signals to ex
    output logic                commit_lsu_o,       // commit the pending store
    input  logic                commit_lsu_ready_i, // commit buffer of LSU is ready
    input  logic                no_st_pending_i,    // there is no store pending
    output logic                commit_csr_o,       // commit the pending CSR instruction
    output logic                fence_i_o,          // flush I$ and pipeline
    output logic                fence_o,            // flush D$ and pipeline
    output logic                sfence_vma_o        // flush TLBs and pipeline
);

    assign waddr_a_o[0] = commit_instr_i[0].rd;
	assign waddr_a_o[1] = commit_instr_i[1].rd;
	assign waddr_a_o[2] = commit_instr_i[2].rd;
	assign waddr_a_o[3] = commit_instr_i[3].rd;
	
    assign pc_o[0]      = commit_instr_i[0].pc;
	assign pc_o[1]      = commit_instr_i[1].pc;
	assign pc_o[2]      = commit_instr_i[2].pc;
	assign pc_o[3]      = commit_instr_i[3].pc;
	
    

    // -------------------
    // Commit Instruction
    // -------------------
    // write register file or commit instruction in LSU or CSR Buffer
	logic [1:0] csr_instr_index;
	logic csr_flag;
	logic [1:0] record;
	logic normal_ex;
    always_comb begin : commit
		// default assignments
		
		commit_ack_o                  = 0;
		we_a_o                        = 0;
		commit_lsu_o                  = 0;
		commit_csr_o                  = 0;
		wdata_a_o[0]                  = commit_instr_i[0].result;
		wdata_a_o[1]                  = commit_instr_i[1].result;
		wdata_a_o[2]                  = commit_instr_i[2].result;
		wdata_a_o[3]                  = commit_instr_i[3].result;
		csr_op_o                      = ADD; // this corresponds to a CSR NOP
		csr_wdata_o                   = 0;
		fence_i_o                     = 1'b0;
		fence_o                       = 1'b0;
		sfence_vma_o                  = 1'b0;
		csr_flag                      = 0;
        // we will not commit the instruction if we took an exception
        // but we do not commit the instruction if we requested a halt
	 
		for (int unsigned i = 0; i < NR_WB_PORTS; i+=1) begin	
			if (commit_instr_i[i].valid && !halt_i && commit_instr_valid_i[i]) begin
				commit_ack_o[i] = 1'b1;
				// register will be the all zero register.
				// and also acknowledge the instruction, this is mainly done for the instruction tracer
				// as it will listen on the instruction ack signal. For the overall result it does not make any
				// difference as the whole pipeline is going to be flushed anyway.
				if ((normal_ex && i != record) || (!normal_ex)) begin
					// we can definitely write the register file
					// if the instruction is not committing anything the destination
					we_a_o[i]       = 1'b1;

					// check whether the instruction we retire was a store
					// do not commit the instruction if we got an exception since the store buffer will be cleared
					// by the subsequent flush triggered by an exception
					if (commit_instr_i[i].fu == STORE) begin
						// if LSU is already inside one of four instr, we don't acknowledge the others
						if (commit_lsu_o) 
							commit_ack_o[i] = 1'b0;
						// check if the LSU is ready to accept another commit entry (e.g.: a non-speculative store)
						if (commit_lsu_ready_i)
							commit_lsu_o = 1'b1;
						else // if the LSU buffer is not ready - do not commit, wait
							commit_ack_o[i] = 1'b0;
					end
				 end
			
			

				// ---------
				// CSR Logic
				// ---------
				// check whether the instruction we retire was a CSR instruction
				if (commit_instr_i[i].fu == CSR) begin
					// write the CSR file
					csr_flag     = 1;
					csr_instr_index = i;
					commit_csr_o = 1'b1;
					wdata_a_o[i] = csr_rdata_i;
					csr_op_o     = commit_instr_i[i].op;
					csr_wdata_o  = commit_instr_i[i].result;
				end
				// ------------------
				// SFENCE.VMA Logic
				// ------------------
				// check if this instruction was a SFENCE_VMA
				if (commit_instr_i[i].op == SFENCE_VMA) begin
					// no store pending so we can flush the TLBs and pipeline
					sfence_vma_o = no_st_pending_i;
					// wait for the store buffer to drain until flushing the pipeline
					commit_ack_o[i] = no_st_pending_i;
				end
				// ------------------
				// FENCE.I Logic
				// ------------------
				// Fence synchronizes data and instruction streams. That means that we need to flush the private icache
				// and the private dcache. This is the most expensive instruction.
				if (commit_instr_i[i].op == FENCE_I || (flush_dcache_i && commit_instr_i[i].fu != STORE)) begin
					commit_ack_o[i] = no_st_pending_i;
					// tell the controller to flush the I$
					fence_i_o = no_st_pending_i;
				end
				// ------------------
				// FENCE Logic
				// ------------------
				if (commit_instr_i[i].op == FENCE) begin
					commit_ack_o[i] = no_st_pending_i;
					// tell the controller to flush the D$
					fence_o = no_st_pending_i;
				end
			end
		end
    end
    
	
    // -----------------------------
    // Exception & Interrupt Logic
    // -----------------------------
    // here we know for sure that we are taking the exception

    always_comb begin : exception_handling
        // Multiple simultaneous interrupts and traps at the same privilege level are handled in the following decreasing
        // priority order: external interrupts, software interrupts, timer interrupts, then finally any synchronous traps. (1.10 p.30)
        // interrupts are correctly prioritized in the CSR reg file, exceptions are prioritized here
        exception_o.valid = 1'b0;
        exception_o.cause = 64'b0;
        exception_o.tval  = 64'b0;
		record = 0;
        // we need a valid instruction in the commit stage, otherwise we might loose the PC in case of interrupts as they
        // can happen anywhere in the execution flow and might just happen between two legal instructions - the PC would then
        // be outdated. The solution here is to defer any exception/interrupt until we get a valid PC again (from where we cane
        // resume execution afterwards).
		for (int unsigned i = 0; i < NR_WB_PORTS-1; i+=1) begin
			if(commit_instr_valid_i[i] && commit_instr_i[i].valid && commit_instr_i[i].ex.valid) begin
				normal_ex = 1;
				record = i;
			end else begin
				normal_ex = 0;
			end
		end
		
		if (normal_ex) begin
			exception_o = commit_instr_i[record].ex;
		end
		
		
		// ------------------------
		// check for CSR exception
		// ------------------------
		if (csr_exception_i.valid && !csr_exception_i.cause[63]) begin
			exception_o      = csr_exception_i;
			// if no earlier exception happened the commit instruction will still contain
			// the instruction data from the ID stage. If a earlier exception happened we don't care
			// as we will overwrite it anyway in the next IF bl
			exception_o.tval = commit_instr_i[csr_instr_index].ex.tval;
		end
		// ------------------------
		// Earlier Exceptions
		// ------------------------
		// but we give precedence to exceptions which happened earlier
		//if (commit_instr_i[record].ex.valid) begin
		//	exception_o = commit_instr_i[record].ex;
		//end
		// ------------------------
		// Interrupts
		// ------------------------
		// check for CSR interrupts (e.g.: normal interrupts which get triggered here)
		// by putting interrupts here we give them precedence over any other exception
		if (csr_exception_i.valid && csr_exception_i.cause[63]) begin
			exception_o = csr_exception_i;
			exception_o.tval = commit_instr_i[csr_instr_index].ex.tval;
		end
	

        // If we halted the processor don't take any exceptions
        if (halt_i) begin
            exception_o.valid = 1'b0;
        end
    end
endmodule