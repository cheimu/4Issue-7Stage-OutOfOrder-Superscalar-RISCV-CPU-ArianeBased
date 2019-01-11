`include "../test.svh";

module ex_testbench;

	localparam int          ASID_WIDTH       = 1;
	localparam logic [63:0] CACHE_START_ADDR = 64'h4000_0000;
	localparam int unsigned AXI_ID_WIDTH     = 10;
	localparam int unsigned AXI_USER_WIDTH   = 1;
	
	logic                                   clk_i;    // Clock
	logic                                   rst_ni;   // Asynchronous reset active low
	logic                                   flush_i;

	logic  [3:0]								    valid_i;
	fu_t  [3:0]                                  fu_i;
	fu_op [3:0]                                  operator_i;
	logic [3:0][63:0]                            operand_a_i;
	logic [3:0][63:0]                            operand_b_i;
	logic [3:0][63:0]                            imm_i;
	logic [3:0][TRANS_ID_BITS-1:0]               trans_id_i;
	logic [3:0][63:0]                            pc_i;                  // PC of current instruction
	logic [3:0]                                  is_compressed_instr_i; // we need to know if this was a compressed instruction
																	  // in order to calculate the next PC on a mis-predict
	// ALU 2
	logic [1:0]                                  alu_ready_o;           // FU is ready
	logic [1:0]                                  alu_valid_i;           //  is valid
	logic [1:0]                                  alu_valid_o;           // ALU result is valid
	logic [1:0]                                  alu_branch_res_o;      // Branch comparison result
	logic [1:0][63:0]                            alu_result_o;
	logic [1:0][TRANS_ID_BITS-1:0]               alu_trans_id_o;        // ID of scoreboard entry at which to write back
	exception_t[1:0]                             alu_exception_o;
	// Branches and Jumps
	logic                                   branch_ready_o;
	logic                                   branch_valid_i;        // we are using the branch unit
	logic                                   branch_valid_o;        // the calculated branch target is valid
	logic [63:0]                            branch_result_o;       // branch target address out
	branchpredict_sbe_t                     branch_predict_i;      // branch prediction in
	logic [TRANS_ID_BITS-1:0]               branch_trans_id_o;
	exception_t                             branch_exception_o;    // branch unit detected an exception
	branchpredict_t                         resolved_branch_o;     // the branch engine uses the write back from the ALU
	logic                                   resolve_branch_o;      // to ID signaling that we resolved the branch
	// LSU
	logic                                   lsu_ready_o;           // FU is ready
	logic                                   lsu_valid_i;           //  is valid
	logic                                   lsu_valid_o;           //  is valid
	logic [63:0]                            lsu_result_o;
	logic [TRANS_ID_BITS-1:0]               lsu_trans_id_o;
	logic                                   lsu_commit_i;
	logic                                   lsu_commit_ready_o;    // commit queue is ready to accept another commit request
	exception_t                             lsu_exception_o;
	logic                                   no_st_pending_o;
	// CSR
	logic                                   csr_ready_o;
	logic                                   csr_valid_i;
	logic [TRANS_ID_BITS-1:0]               csr_trans_id_o;
	logic [63:0]                            csr_result_o;
	logic                                   csr_valid_o;
	logic [11:0]                            csr_addr_o;
	logic                                   csr_commit_i;
	// MULT
	logic                                   mult_ready_o;      // FU is ready
	logic                                   mult_valid_i;      // Output is valid
	logic [TRANS_ID_BITS-1:0]               mult_trans_id_o;
	logic [63:0]                            mult_result_o;
	logic                                   mult_valid_o;

	// Memory Management
	logic                                   enable_translation_i;
	logic                                   en_ld_st_translation_i;
	logic                                   flush_tlb_i;
	logic                                   fetch_req_i;
	logic                                   fetch_gnt_o;
	logic                                   fetch_valid_o;
	logic [63:0]                            fetch_vaddr_i;
	logic [63:0]                            fetch_rdata_o;
	exception_t                             fetch_ex_o;
	priv_lvl_t                              priv_lvl_i;
	priv_lvl_t                              ld_st_priv_lvl_i;
	logic                                   sum_i;
	logic                                   mxr_i;
	logic [43:0]                            satp_ppn_i;
	logic [ASID_WIDTH-1:0]                  asid_i;

	// Performance counters
	logic                                   itlb_miss_o;
	logic                                   dtlb_miss_o;
	logic                                   dcache_miss_o;

	logic [63:0]                            instr_if_address_o;
	logic                                   instr_if_data_req_o;
	logic [3:0]                             instr_if_data_be_o;
	logic                                   instr_if_data_gnt_i;
	logic                                   instr_if_data_rvalid_i;
	logic [63:0]                            instr_if_data_rdata_i;

	// DCache interface
	logic                                   dcache_en_i;
	logic                                   flush_dcache_i;
	logic                                   flush_dcache_ack_o;

	ex_stage dut
	(
		.*
	);
	
	parameter CLOCK_PERIOD=1000;
	initial begin
		clk_i <= 0;
		forever #(CLOCK_PERIOD/2) clk_i <= ~clk_i;
	end
	
	integer i;
	// Set up the inputs to the design. Each line is a clock cycle.
	initial begin
	rst_ni<=0;@(posedge clk_i);
    $stop; // End the simulation.
    end
endmodule 