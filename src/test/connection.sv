`include "../test.svh";

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
    input  branchpredict_sbe_t[3:0]brach_predict_to_fifo_i,
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
endmodule

module pcgen_stage (
    input  logic               clk_i,              // Clock
    input  logic               rst_ni,             // Asynchronous reset active low
    // control signals
    input  logic               flush_i,            // flush request for PCGEN
    input  logic               flush_bp_i,         // flush branch prediction
    input  logic               fetch_enable_i,
    input  logic               if_ready_i,
    input  branchpredict_t     resolved_branch_i,  // from controller signaling a branch_predict -> update BTB
    // to IF
    output logic [63:0]        fetch_address_o,    // new PC (address because we do not distinguish instructions)
    output logic               fetch_valid_o,      // the PC (address) is valid
	output logic [1:0]		   which_branch_taken_o, // which instruction get a branch
	output branchpredict_sbe_t branch_predict_o,   // pass on the information if this is speculative
	output branchpredict_sbe_t[3:0] branch_predict_to_fifo_o , // pass branch prediction to fetch fifo
    // global input
    input  logic [63:0]        boot_addr_i,
    // from commit
    input  logic [63:0]        pc_commit_i,        // PC of instruction in commit stage
    // CSR input
    input  logic [63:0]        epc_i,              // exception PC which we need to return to
    input  logic               eret_i,             // return from exception
    input  logic [63:0]        trap_vector_base_i, // base of trap vector
    input  logic               ex_valid_i,         // exception is valid - from commit
    // Debug
    input  logic [63:0]        debug_pc_i,         // PC from debug stage
    input  logic               debug_set_pc_i      // Set PC request from debug
);
endmodule
module id_stage (
    input  logic                                     clk_i,     // Clock
    input  logic                                     rst_ni,    // Asynchronous reset active low

    input  logic                                     flush_i,
    // from IF
    input  fetch_entry_t                       fetch_entry_i_0,

	input  fetch_entry_t                       fetch_entry_i_1,

	input  fetch_entry_t                       fetch_entry_i_2,

	input  fetch_entry_t                       fetch_entry_i_3,
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
	input  logic                                     tsr_i_3
);
endmodule

module reservation_station #(
    parameter integer BUFFER_SIZE=16
)
(
    // to rename stage
    input  logic                                           						  clk_i,
    input  logic                                            					  rst_ni,
    input  scoreboard_entry_t    [NR_WB_PORTS-1:0]                            	  issue_entry_i,       // a decoded instruction
    input  logic                                            					  issue_entry_valid_i, // issue entry is valid
    input  logic       			 [NR_WB_PORTS-1:0]                   		      is_ctrl_flow_i,      // the instruction we issue is a ctrl flow instructions
    output logic                                            				      issue_instr_ack_o,
    
    input  logic				 [2:0]                                       	  valid_instruction_num_i,
    
	output logic 				 [NR_WB_PORTS-1:0][6:0]							  commit_register_o,
	output logic		         [NR_WB_PORTS-1:0]								  commit_register_valid_o,
	
    // write-back ports
    input logic 			     [NR_FU-1:0][$clog2(BUFFER_SIZE)-1:0]       	  trans_id_i,  // transaction ID at which to write the result back
    input logic 			     [NR_FU-1:0][63:0]                          	  wdata_i,     // write data in
    input exception_t            [NR_FU-1:0]                                	  ex_i,        // exception from a functional unit (e.g.: ld/st exception, divide by zero)
    input logic                  [NR_FU-1:0]                                	  wb_valid_i,   // data in is valid
    
    // commit ports
    output scoreboard_entry_t    [NR_WB_PORTS-1:0]             				      commit_instr_o,
    output logic                 [NR_WB_PORTS-1:0]             				      commit_valid_o,
    input  logic                 [NR_WB_PORTS-1:0]             					  commit_ack_i,
 	
    input  logic                                             					  resolved_branch_valid_i,
    input  logic                                             					  is_mis_predict_i,
    
    // to read operands interface
    output scoreboard_entry_t    [NR_WB_PORTS-1:0]                                issue_instr_o,
    output logic                 [NR_WB_PORTS-1:0]                                issue_instr_valid_o,
    input  logic                 [NR_WB_PORTS-1:0]                                issue_ack_i,
    input logic [4:0][1:0] 														  fu_status_i,

    output logic [NR_WB_PORTS-1:0][63:0]                       	    			  rs1_data_o,
    output logic [NR_WB_PORTS-1:0]                           		    		  rs1_forward_valid_o,	
    output logic [NR_WB_PORTS-1:0][63:0]        		                		  rs2_data_o,
    output logic [NR_WB_PORTS-1:0]                       		        		  rs2_forward_valid_o	
);
endmodule

module issue_read_operands #(
	parameter integer BUFFER_SIZE = 16,
    parameter integer NR_WB_PORTS = 4
)
(
    input  logic                                   clk_i,    // Clock
    input  logic                                   rst_ni,   // Asynchronous reset active low
    input  logic                                   test_en_i,
    // flush
    input  logic                                   flush_i,
    // coming from Debug
    input  logic                                   debug_gpr_req_i,
    input  logic 				[4:0]                             debug_gpr_addr_i,
    input  logic                                   debug_gpr_we_i,
    input  logic 				[63:0]                            debug_gpr_wdata_i,
    output logic 				[63:0]                            debug_gpr_rdata_o,
	
    // coming from scoreboard
    input  scoreboard_entry_t 	[3:0]                     issue_instr_i,
    input  logic  				[3:0]                                 issue_instr_valid_i,
    output logic  				[3:0]                                 issue_ack_o,
    output logic  				[NR_FU-2:0][1:0] 						    fu_status_o,
	    
    input logic 				[NR_WB_PORTS-1:0][6:0]                        rs1_addr,
    input logic 				[NR_WB_PORTS-1:0][63:0]                       rs1_data,
    input logic 				[NR_WB_PORTS-1:0]                             rs1_forward_valid,
    
    input logic 				[NR_WB_PORTS-1:0][6:0]                        rs2_addr,
    input logic 				[NR_WB_PORTS-1:0][63:0]                       rs2_data,
    input logic 				[NR_WB_PORTS-1:0]                             rs2_forward_valid, 
   
	output logic 				[8:0]					rename_index_o,
    
    // To FU, just single issue for now
	output logic 				[NR_WB_PORTS-1:0]			    valid_o,
    output fu_t                 [NR_WB_PORTS-1:0]               fu_o,
    output fu_op                [NR_WB_PORTS-1:0]               operator_o,
    output logic 				[NR_WB_PORTS-1:0][63:0]                            operand_a_o,
    output logic 				[NR_WB_PORTS-1:0][63:0]                            operand_b_o,
    output logic 				[NR_WB_PORTS-1:0][63:0]                            imm_o,           // output immediate for the LSU
    output logic 				[NR_WB_PORTS-1:0][TRANS_ID_BITS-1:0]               trans_id_o,
    output logic 				[NR_WB_PORTS-1:0][63:0]                            pc_o,
    output logic                [NR_WB_PORTS-1:0]               			       is_compressed_instr_o,
    // ALU 1
    input  logic  				[1:0]       			                           alu_ready_i,      // FU is ready
    // Branches and Jumps
    input  logic				[1:0]                                        	   branch_ready_i,
    output branchpredict_sbe_t                          branch_predict_o,
    // LSU
    input  logic 	   			[1:0]                                   lsu_ready_i,      // FU is ready
    // MULT
    input  logic 				[1:0]                                  mult_ready_i,      // FU is ready
    // CSR
    input  logic 				[1:0]                                  csr_ready_i,      // FU is ready
    
	// commit port
    input  logic 				[NR_WB_PORTS-1:0][6:0]                             waddr_a_i,
    input  logic 				[NR_WB_PORTS-1:0][63:0]                            wdata_a_i,
    input  logic 				[NR_WB_PORTS-1:0]                                  we_a_i
    // committing instruction instruction
    // from scoreboard
    // input  scoreboard_entry     commit_instr_i,
    // output logic                commit_ack_o
);
endmodule

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
    output logic [8:0]							   rename_index_o,
	input  logic [8:0]							   rename_index_i,
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
    output logic [63:0]                            fetch_rdata_o,
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
    input  logic [63:0]                            instr_if_data_rdata_i,

    // DCache interface
    input  logic                                   dcache_en_i,
    input  logic                                   flush_dcache_i,
    output logic                                   flush_dcache_ack_o
    // for testing purpose
	//AXI_BUS.Master                                 data_if,
    //AXI_BUS.Master                                 bypass_if
);
endmodule

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
endmodule

module csr_regfile #(
    parameter int ASID_WIDTH = 1
)(
    input  logic                  clk_i,                      // Clock
    input  logic                  rst_ni,                     // Asynchronous reset active low
    input  logic [63:0]           time_i,                     // Platform Timer
    input  logic                  time_irq_i,                 // Timer threw a interrupt

    // send a flush request out if a CSR with a side effect has changed (e.g. written)
    output logic                  flush_o,
    output logic                  halt_csr_o,                 // halt requested
    // Debug CSR Port
    input  logic                  debug_csr_req_i,            // Request from debug to read the CSR regfile
    input  logic [11:0]           debug_csr_addr_i,           // Address of CSR
    input  logic                  debug_csr_we_i,             // Is it a read or write?
    input  logic [63:0]           debug_csr_wdata_i,          // Data to write
    output logic [63:0]           debug_csr_rdata_o,          // Read data
    // commit acknowledge
    input  logic                  commit_ack_i,               // Commit acknowledged a instruction -> increase instret CSR
    // Core and Cluster ID
    input  logic  [3:0]           core_id_i,                  // Core ID is considered static
    input  logic  [5:0]           cluster_id_i,               // Cluster ID is considered static
    input  logic  [63:0]          boot_addr_i,                // Address from which to start booting, mtvec is set to the same address
    // we are taking an exception
    input exception_t             ex_i,                       // We've got an exception from the commit stage, take its

    input  fu_op                  csr_op_i,                   // Operation to perform on the CSR file
    input  logic  [11:0]          csr_addr_i,                 // Address of the register to read/write
    input  logic  [63:0]          csr_wdata_i,                // Write data in
    output logic  [63:0]          csr_rdata_o,                // Read data out
    input  logic  [63:0]          pc_i,                       // PC of instruction accessing the CSR
    output exception_t            csr_exception_o,            // attempts to access a CSR without appropriate privilege
                                                              // level or to write  a read-only register also
                                                              // raises illegal instruction exceptions.
    // Interrupts/Exceptions
    output logic  [63:0]          epc_o,                      // Output the exception PC to PC Gen, the correct CSR (mepc, sepc) is set accordingly
    output logic                  eret_o,                     // Return from exception, set the PC of epc_o
    output logic  [63:0]          trap_vector_base_o,         // Output base of exception vector, correct CSR is output (mtvec, stvec)
    output priv_lvl_t             priv_lvl_o,                 // Current privilege level the CPU is in
    // MMU
    output logic                  en_translation_o,           // enable VA translation
    output logic                  en_ld_st_translation_o,     // enable VA translation for load and stores
    output priv_lvl_t             ld_st_priv_lvl_o,           // Privilege level at which load and stores should happen
    output logic                  sum_o,
    output logic                  mxr_o,
    output logic [43:0]           satp_ppn_o,
    output logic [ASID_WIDTH-1:0] asid_o,
    // external interrupts
    input  logic [1:0]            irq_i,                      // external interrupt in
    input  logic                  ipi_i,                      // inter processor interrupt -> connected to machine mode sw
    // Visualization Support
    output logic                  tvm_o,                      // trap virtual memory
    output logic                  tw_o,                       // timeout wait
    output logic                  tsr_o,                      // trap sret
    // Caches
    output logic                  icache_en_o,                // L1 ICache Enable
    output logic                  dcache_en_o,                // L1 DCache Enable
    // Performance Counter
    output logic  [11:0]          perf_addr_o,                // address to performance counter module
    output logic  [63:0]          perf_data_o,                // write data to performance counter module
    input  logic  [63:0]          perf_data_i,                // read data from performance counter module
    output logic                  perf_we_o
);
endmodule

module controller (
    input  logic            clk_i,
    input  logic            rst_ni,
    output logic            flush_bp_o,             // Flush branch prediction data structures
    output logic            flush_pcgen_o,          // Flush PC Generation Stage
    output logic            flush_if_o,             // Flush the IF stage
    output logic            flush_unissued_instr_o, // Flush un-issued instructions of the scoreboard
    output logic            flush_id_o,             // Flush ID stage
    output logic            flush_ex_o,             // Flush EX stage
    output logic            flush_icache_o,         // Flush ICache
    input  logic            flush_icache_ack_i,     // Acknowledge the whole ICache Flush
    output logic            flush_dcache_o,         // Flush DCache
    input  logic            flush_dcache_ack_i,     // Acknowledge the whole DCache Flush
    output logic            flush_tlb_o,            // Flush TLBs

    input  logic            halt_csr_i,             // Halt request from CSR (WFI instruction)
    input  logic            halt_debug_i,           // Halt request from debug
    input  logic            debug_set_pc_i,         // Debug wants to set the PC
    output logic            halt_o,                 // Halt signal to commit stage
    input  logic            eret_i,                 // Return from exception
    input  logic            ex_valid_i,             // We got an exception, flush the pipeline
    input  branchpredict_t  resolved_branch_i,      // We got a resolved branch, check if we need to flush the front-end
    input  logic            flush_csr_i,            // We got an instruction which altered the CSR, flush the pipeline
    input  logic            fence_i_i,              // fence.i in
    input  logic            fence_i,                // fence in
    input  logic            sfence_vma_i            // We got an instruction to flush the TLBs and pipeline
);
endmodule


module rename_stage#(
  parameter integer NUM_OF_PYH_RES = 128,
  parameter integer NUM_OF_ISA_RES = 32,
  parameter integer PYH_RES_BIT = $clog2(NUM_OF_PYH_RES),
  parameter integer ISA_RES_BIT = $clog2(NUM_OF_ISA_RES)
)
(
    input logic clk_i,
    input logic rst_ni,
    
	// misprediction & prediction handlings
	input logic is_mispredict_i,
	input logic [4:0] rename_index_i,
	input logic resolved_branch_valid_i,
	
    // from ID 4 entries at on
    input decoded_entry_t   decoded_entry_0_i,
    input logic             decoded_entry_valid_0_i,
    output logic            rename_instr_ack_0_o,
    input logic             is_ctrl_flow_0_i,

    input decoded_entry_t   decoded_entry_1_i,
    input logic             decoded_entry_valid_1_i,
    output logic            rename_instr_ack_1_o,
    input logic             is_ctrl_flow_1_i,

    input decoded_entry_t   decoded_entry_2_i,
    input logic             decoded_entry_valid_2_i,
    output logic            rename_instr_ack_2_o,
    input logic             is_ctrl_flow_2_i,

    input decoded_entry_t   decoded_entry_3_i,
    input logic             decoded_entry_valid_3_i,
    output logic            rename_instr_ack_3_o,
    input logic             is_ctrl_flow_3_i,

    // to reservation station
    output scoreboard_entry_t                        issue_entry_0_o,       // a decoded instruction
    output logic                                     issue_entry_valid_0_o, // issue entry is valid
    output logic                                     is_ctrl_flow_0_o,      // the instruction we issue is a ctrl flow instructions
    input  logic                                     issue_instr_ack_0_i,
    
    output scoreboard_entry_t                        issue_entry_1_o,       // a decoded instruction
    output logic                                     issue_entry_valid_1_o, // issue entry is valid
    output logic                                     is_ctrl_flow_1_o,      // the instruction we issue is a ctrl flow instructions
    input  logic                                     issue_instr_ack_1_i,
         
    output scoreboard_entry_t                        issue_entry_2_o,       // a decoded instruction
    output logic                                     issue_entry_valid_2_o, // issue entry is valid
    output logic                                     is_ctrl_flow_2_o,      // the instruction we issue is a ctrl flow instructions
    input  logic                                     issue_instr_ack_2_i,
    output scoreboard_entry_t                        issue_entry_3_o,       // a decoded instruction
    output logic                                     issue_entry_valid_3_o, // issue entry is valid
    output logic                                     is_ctrl_flow_3_o,      // the instruction we issue is a ctrl flow instructions
    input  logic                                     issue_instr_ack_3_i,
    
    output logic [2:0]                               valid_instruction_o,
    
    //from commit
    input logic [3:0]                                commit_valid_i,
    input logic [3:0][PYH_RES_BIT-1:0]               commit_register                   
);
endmodule