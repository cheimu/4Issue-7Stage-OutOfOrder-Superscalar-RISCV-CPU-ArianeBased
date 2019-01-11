import ariane_pkg::*;


module ariane #(
        parameter logic [63:0] CACHE_START_ADDR = 64'h4000_0000, // address on which to decide whether the request is cache-able or not
        parameter int unsigned AXI_ID_WIDTH     = 10,            // minimum 1
        parameter int unsigned AXI_USER_WIDTH   = 1              // minimum 1
    )(
    input logic clk_i,
    input logic rst_ni,
    input  logic                           test_en_i,              // enable all clock gates for testing

    input  logic                           flush_dcache_i,         // external request to flush data cache
    output logic                           flush_dcache_ack_o,     // finished data cache flush
    // CPU Control Signals
    input  logic                           fetch_enable_i,         // start fetching data
    // Core ID, Cluster ID and boot address are considered more or less static
    input  logic [63:0]                    boot_addr_i,            // reset boot address
    input  logic [ 3:0]                    core_id_i,              // core id in a multicore environment (reflected in a CSR)
    input  logic [ 5:0]                    cluster_id_i,           // PULP specific if core is used in a clustered environment
    // Instruction memory interface
    AXI_BUS.Master                         instr_if,
    // Data memory interface
    AXI_BUS.Master                         data_if,                // data cache refill port
    AXI_BUS.Master                         bypass_if,              // bypass axi port (disabled cache or uncacheable access)
    // Interrupt inputs
    input  logic [1:0]                     irq_i,                  // level sensitive IR lines, mip & sip
    input  logic                           ipi_i,                  // inter-processor interrupts
    output logic                           sec_lvl_o,              // current privilege level out
    // Timer facilities
    input  logic [63:0]                    time_i,                 // global time (most probably coming from an RTC)
    input  logic                           time_irq_i,             // timer interrupt in
    // Debug Interface
    input  logic                           debug_req_i,
    output logic                           debug_gnt_o,
    output logic                           debug_rvalid_o,
    input  logic [15:0]                    debug_addr_i,
    input  logic                           debug_we_i,
    input  logic [63:0]                    debug_wdata_i,
    output logic [63:0]                    debug_rdata_o,
    output logic                           debug_halted_o,
    input  logic                           debug_halt_i,
    input  logic                           debug_resume_i
);
    // ------------------------------------------
    // Global Signals
    // Signals connecting more than one module
    // ------------------------------------------
    priv_lvl_t                priv_lvl;
    logic                     fetch_enable;
    exception_t               ex_commit; // exception from commit stage
    branchpredict_t           resolved_branch;
    logic [63:0]              pc_commit;
    logic                     eret;
    logic [3:0]               commit_ack;

    // rename stage <----> reservation station
    logic [3:0] issue_entry_valid_rename_rs;
    logic [3:0] is_control_flow_rename_rs;
    logic issue_instr_ack_rs_rename;
    scoreboard_entry_t [3:0] instr_rename_rs;
    logic [2:0] valid_instr_num_rename_rs;
    
    // --------------
    // PCGEN <-> IF
    // --------------
    logic [63:0]              fetch_address_pcgen_if;
    branchpredict_sbe_t       branch_predict_pcgen_if;
    logic                     if_ready_if_pcgen;
    logic                     fetch_valid_pcgen_if;
    logic [1:0]               which_branch_taken_pcgen_if;
    branchpredict_sbe_t [3:0] branch_predicts_pcgen_if;
    logic                     resolved_branch_valid;
    // --------------
    // IF <-> ID
    // --------------
    fetch_entry_t[3:0]           fetch_entry_if_id;       // fetch entry containing all relevant data for the ID stage
    logic [3:0]                  fetch_entry_valid_if_id; // instruction in IF is valid
    logic [3:0]                  fetch_ack_if_id;         // ID acknowledged this instruction   
    
    // --------------
    // ID <-> RENAME
    // --------------   
    logic [3:0]                 decoded_entry_valid_id_rename;
    logic [3:0]                 decoded_entry_ack_rename_id;
    logic [3:0]                 is_control_id_rename;
    decoded_entry_t [3:0]       decoded_entry_id_rename;
    // --------------
    // RS <-> RENAME
    // --------------       
    logic                [NR_WB_PORTS-1:0][6:0]commit_register_rs_rename;
    logic                [NR_WB_PORTS-1:0]commit_register_valid_rs_rename;
    // --------------
    // RS <-> read_op
    // --------------           
    
    scoreboard_entry_t  [3:0]                                       issue_instr_rs_rd;
    logic               [3:0]                                       issue_instr_valid_rs_rd;
    logic               [3:0]                                       issue_ack_rd_rs;
    logic               [NR_FU-2:0][1:0]                            fu_status_rd_rs;
        
    logic               [NR_WB_PORTS-1:0][6:0]                        rs1_addr;
    logic               [NR_WB_PORTS-1:0][63:0]                       rs1_data_rs_rd;
    logic               [NR_WB_PORTS-1:0]                             rs1_forward_valid_rs_rd;
    
    logic               [NR_WB_PORTS-1:0][6:0]                        rs2_addr_rs_rd;
    logic               [NR_WB_PORTS-1:0][63:0]                       rs2_data_rs_rd;
    logic               [NR_WB_PORTS-1:0]                             rs2_forward_valid_rs_rd; 
   
    logic               [4:0]                                         rename_index_rd_rename;
    
    // IF <-> EX
    // --------------
    logic                     fetch_req_if_ex;
    logic                     fetch_gnt_ex_if;
    logic                     fetch_valid_ex_if;
    logic [127:0]              fetch_rdata_ex_if;
    exception_t               fetch_ex_ex_if;
    logic [63:0]              fetch_vaddr_if_ex;
    // --------------
    // ISSUE <-> EX
    // --------------
    logic [NR_WB_PORTS-1:0][63:0]              imm_id_ex;
    logic [NR_WB_PORTS-1:0][TRANS_ID_BITS-1:0] trans_id_id_ex;
    fu_t  [NR_WB_PORTS-1:0]   fu_id_ex;
    fu_op [NR_WB_PORTS-1:0]                   operator_id_ex;
    logic [NR_WB_PORTS-1:0][63:0]              operand_a_id_ex;
    logic [NR_WB_PORTS-1:0][63:0]              operand_b_id_ex;
    logic [NR_WB_PORTS-1:0][63:0]              pc_id_ex;
    logic [NR_WB_PORTS-1:0]                   is_compressed_instr_id_ex;
    // ALU
    logic [1:0]                    alu_ready_ex_id;
    logic [1:0][TRANS_ID_BITS-1:0] alu_trans_id_ex_id;
    logic [1:0]                    alu_valid_ex_id;
    logic [1:0][63:0]              alu_result_ex_id;
    logic                     alu_branch_res_ex_id;
    exception_t [1:0]               alu_exception_ex_id;
    // Branches and Jumps
    logic                     branch_ready_ex_id;
    logic [TRANS_ID_BITS-1:0] branch_trans_id_ex_id;
    logic [63:0]              branch_result_ex_id;
    exception_t               branch_exception_ex_id;
    logic                     branch_valid_ex_id;
    logic                     branch_valid_id_ex;

    branchpredict_sbe_t       branch_predict_id_ex;
    logic                     resolve_branch_ex_id;
    // LSU
    logic [TRANS_ID_BITS-1:0] lsu_trans_id_ex_id;
    logic                     lsu_valid_id_ex;
    logic [63:0]              lsu_result_ex_id;
    logic                     lsu_ready_ex_id;
    logic                     lsu_valid_ex_id;
    exception_t               lsu_exception_ex_id;
    // MULT
    logic                     mult_ready_ex_id;
    logic                     mult_valid_id_ex;
    logic [TRANS_ID_BITS-1:0] mult_trans_id_ex_id;
    logic [63:0]              mult_result_ex_id;
    logic                     mult_valid_ex_id;
    // CSR
    logic                     csr_ready_ex_id;
    logic                     csr_valid_id_ex;
    logic [TRANS_ID_BITS-1:0] csr_trans_id_ex_id;
    logic [63:0]              csr_result_ex_id;
    logic                     csr_valid_ex_id;  
    // --------------
    // Debug <-> *
    // --------------
    logic [63:0]              pc_debug_pcgen;
    logic                     set_pc_debug;

    logic                     gpr_req_debug_issue;
    logic [4:0]               gpr_addr_debug_issue;
    logic                     gpr_we_debug_issue;
    logic [63:0]              gpr_wdata_debug_issue;
    logic [63:0]              gpr_rdata_debug_issue;

    logic                     csr_req_debug_csr;
    logic [11:0]              csr_addr_debug_csr;
    logic                     csr_we_debug_csr;
    logic [63:0]              csr_wdata_debug_csr;
    logic [63:0]              csr_rdata_debug_csr;  
    
    logic [3:0]               valid_rd_ex;
    // -------
    // rs -> commit
    // -------
    scoreboard_entry_t[3:0]        commit_instr_id_commit;
    logic [3:0] commit_instr_valid_rs_commit;
    
    logic [3:0][6:0]               waddr_a_commit_id;
    logic [3:0][63:0]              wdata_a_commit_id;
    logic [3:0]                    we_a_commit_id;  

    // --------------
    // EX <-> COMMIT
    // --------------
    // CSR Commit
    logic                     csr_commit_commit_ex;
    // LSU Commit
    logic                     lsu_commit_commit_ex;
    logic                     lsu_commit_ready_ex_commit;
    logic                     no_st_pending_ex_commit;  
    // --------------
    // EX <-> COMMIT
    // --------------
    logic                     enable_translation_csr_ex;
    logic                     en_ld_st_translation_csr_ex;
    priv_lvl_t                ld_st_priv_lvl_csr_ex;
    logic                     sum_csr_ex;
    logic                     mxr_csr_ex;
    logic [43:0]              satp_ppn_csr_ex;
    logic [0:0]               asid_csr_ex;
    logic [11:0]              csr_addr_ex_csr;
    fu_op                     csr_op_commit_csr;
    logic [63:0]              csr_wdata_commit_csr;
    logic [63:0]              csr_rdata_csr_commit;
    exception_t               csr_exception_csr_commit;
    logic                     tvm_csr_id;
    logic                     tw_csr_id;
    logic                     tsr_csr_id;
    logic                     dcache_en_csr_nbdcache;
    logic [11:0]              addr_csr_perf;
    logic [63:0]              data_csr_perf, data_perf_csr;
    logic                     we_csr_perf;
    // --------------
    // PCGEN <-> CSR
    // --------------
    logic [63:0]              trap_vector_base_commit_pcgen;
    logic [63:0]              epc_commit_pcgen;
    // --------------
    // CTRL <-> *
    // --------------
    logic                     flush_bp_ctrl_pcgen;
    logic                     flush_ctrl_pcgen;
    logic                     flush_csr_ctrl;
    logic                     flush_unissued_instr_ctrl_id;
    logic                     flush_ctrl_if;
    logic                     flush_ctrl_id;
    logic                     flush_ctrl_ex;
    logic                     flush_tlb_ctrl_ex;
    logic                     fence_i_commit_controller;
    logic                     fence_commit_controller;
    logic                     sfence_vma_commit_controller;
    logic                     halt_ctrl;
    logic                     halt_debug_ctrl;
    logic                     halt_csr_ctrl;
    logic                     flush_dcache_ctrl_ex;
    logic                     flush_dcache_ack_ex_ctrl;
 
    // ICache <-> *
    // ----------------
    logic [63:0]             instr_if_address;
    logic                    instr_if_data_req;    // fetch request
    logic [3:0]              instr_if_data_be;
    logic                    instr_if_data_gnt;    // fetch request
    logic                    instr_if_data_rvalid; // fetch data
    logic [127:0]            instr_if_data_rdata;

    logic                    flush_icache_ctrl_icache;
    logic                    bypass_icache_csr_icache;
    logic                    flush_icache_ack_icache_ctrl;
    
    assign fetch_enable = fetch_enable_i;
    pcgen_stage pcgen_stage_i (
        .fetch_enable_i        ( fetch_enable                   ),
        .flush_i               ( flush_ctrl_pcgen               ),
        .flush_bp_i            ( flush_bp_ctrl_pcgen            ),
        .if_ready_i            ( ~if_ready_if_pcgen             ),
        .resolved_branch_i     ( resolved_branch                ),
        .fetch_address_o       ( fetch_address_pcgen_if         ),
        .fetch_valid_o         ( fetch_valid_pcgen_if           ),
        .branch_predict_o      ( branch_predict_pcgen_if        ),
        .boot_addr_i           ( boot_addr_i                    ),
        .pc_commit_i           ( pc_commit                      ),
        .epc_i                 ( epc_commit_pcgen               ),
        .eret_i                ( eret                           ),
        .trap_vector_base_i    ( trap_vector_base_commit_pcgen  ),
        .ex_valid_i            ( ex_commit.valid                ),
        .debug_pc_i            ( pc_debug_pcgen                 ),
        .debug_set_pc_i        ( set_pc_debug                   ),
        .branch_predict_to_fifo_o(branch_predicts_pcgen_if),
        .which_branch_taken_o(which_branch_taken_pcgen_if),
        .*
    );  
    
    // if Stage
    if_stage if_stage_i (
        .flush_i( flush_ctrl_if),
        .if_busy_o(if_ready_if_pcgen),           // is the IF stage busy fetching instructions?
        .halt_i(halt_ctrl),
        // fetch direction from PC Gen
        .fetch_address_i(fetch_address_pcgen_if),     // TODO: use fetch_address and which branch to decided which instructions are valid to be  put into queue
        .fetch_valid_i(fetch_valid_pcgen_if),       // the fetch address is valid
        .branch_predict_i(branch_predict_pcgen_if),    // TODO: make into an array of four
        .brach_predict_to_fifo_i(branch_predicts_pcgen_if),
        .which_branch_taken_i(which_branch_taken_pcgen_if),// indicacte whether which instructions are taken
        // I$ Interface
        .instr_req_o(fetch_req_if_ex),
        .instr_addr_o(fetch_vaddr_if_ex),
        .instr_gnt_i(fetch_gnt_ex_if),
        .instr_rvalid_i(fetch_valid_ex_if),
        .instr_rdata_i(instr_if_data_rdata),         // instruction input (4 instructions at a time)
        .instr_ex_i(fetch_ex_ex_if),            // Instruction fetch exception(), valid if rvalid is one
        // Output of IF Pipeline stage -> Dual Port Fetch FIFO
        // output port 0
        .fetch_entry_0_o(fetch_entry_if_id[0]),       // fetch entry containing all relevant data for the ID stage
        .fetch_entry_valid_0_o(fetch_entry_valid_if_id[0]), // instruction in IF is valid
        .fetch_ack_0_i(fetch_ack_if_id[0]),         // ID acknowledged this instruction
        // output port 1
        .fetch_entry_1_o(fetch_entry_if_id[1]),       // fetch entry containing all relevant data for the ID stage
        .fetch_entry_valid_1_o(fetch_entry_valid_if_id[1]), // instruction in IF is valid
        .fetch_ack_1_i(fetch_ack_if_id[1]),          // ID acknowledged this instruction
        // output port 2
        .fetch_entry_2_o(fetch_entry_if_id[2]),       // fetch entry containing all relevant data for the ID stage
        .fetch_entry_valid_2_o(fetch_entry_valid_if_id[2]), // instruction in IF is valid
        .fetch_ack_2_i(fetch_ack_if_id[2]),          // ID acknowledged this instruction   
        // output port 3
        .fetch_entry_3_o(fetch_entry_if_id[3]),       // fetch entry containing all relevant data for the ID stage
        .fetch_entry_valid_3_o(fetch_entry_valid_if_id[3]), // instruction in IF is valid
        .fetch_ack_3_i(fetch_ack_if_id[3]),          // ID acknowledged this instruction    
        .*
    );
    
    id_stage id_stage_i (
        // if 
        .flush_i                    ( flush_ctrl_if                   ),
   
        .fetch_entry_i_0(fetch_entry_if_id[0]),

        .fetch_entry_i_1(fetch_entry_if_id[1]),

        .fetch_entry_i_2(fetch_entry_if_id[2]),

        .fetch_entry_i_3(fetch_entry_if_id[3]),
        .fetch_entry_valid_i_0(fetch_entry_valid_if_id[0]),
        .fetch_entry_valid_i_1(fetch_entry_valid_if_id[1]),
        .fetch_entry_valid_i_2(fetch_entry_valid_if_id[2]),
        .fetch_entry_valid_i_3(fetch_entry_valid_if_id[3]),
        .decoded_instr_ack_o_0(fetch_ack_if_id[0]),
        .decoded_instr_ack_o_1(fetch_ack_if_id[1]),
        .decoded_instr_ack_o_2(fetch_ack_if_id[2]),
        .decoded_instr_ack_o_3(fetch_ack_if_id[3]), // acknowledge the instruction (fetch entry)
        // to rename
        .issue_entry_o_0(decoded_entry_id_rename[0]),
        .issue_entry_o_1(decoded_entry_id_rename[1]),
        .issue_entry_o_2(decoded_entry_id_rename[2]),
        .issue_entry_o_3(decoded_entry_id_rename[3]),   // a decoded instruction
        .issue_entry_valid_o_0(decoded_entry_valid_id_rename[0]), // issue entry is valid
        .issue_entry_valid_o_1(decoded_entry_valid_id_rename[1]),
        .issue_entry_valid_o_2(decoded_entry_valid_id_rename[2]),
        .issue_entry_valid_o_3(decoded_entry_valid_id_rename[3]),
        .is_ctrl_flow_o_0(is_control_id_rename[0]),      // the instruction we issue is a ctrl flow instructions
        .is_ctrl_flow_o_1(is_control_id_rename[1]),
        .is_ctrl_flow_o_2(is_control_id_rename[2]),
        .is_ctrl_flow_o_3(is_control_id_rename[3]),
        .issue_instr_ack_i_0(decoded_entry_ack_rename_id[0]),   // issue stage acknowledged sampling of instructions
        .issue_instr_ack_i_1(decoded_entry_ack_rename_id[1]),
        .issue_instr_ack_i_2(decoded_entry_ack_rename_id[2]),
        .issue_instr_ack_i_3(decoded_entry_ack_rename_id[3]),
        // from CSR file
        .priv_lvl_i_0(priv_lvl),          // current privilege level
        .priv_lvl_i_1(priv_lvl),
        .priv_lvl_i_2(priv_lvl),
        .priv_lvl_i_3(priv_lvl),
        .tvm_i_0(tvm_csr_id),
        .tvm_i_1(tvm_csr_id),
        .tvm_i_2(tvm_csr_id),
        .tvm_i_3(tvm_csr_id),
        .tw_i_0(tw_csr_id),
        .tw_i_1(tw_csr_id),
        .tw_i_2(tw_csr_id),
        .tw_i_3(tw_csr_id),
        .tsr_i_0(tsr_csr_id),
        .tsr_i_1(tsr_csr_id),
        .tsr_i_2(tsr_csr_id),
        .tsr_i_3(tsr_csr_id),
        .*
    );
    
    
    rename_stage rename (   
        // misprediction & prediction handlings
        .is_mispredict_i(resolved_branch.is_mispredict),
        .rename_index_i(rename_index_rd_rename),
        .resolved_branch_valid_i(branch_valid_ex_id),
        
        // from ID 4 entries at on
        .decoded_entry_0_i(decoded_entry_id_rename[0]),
        .decoded_entry_valid_0_i(decoded_entry_valid_id_rename[0]),
        .rename_instr_ack_0_o(decoded_entry_ack_rename_id[0]),
        .is_ctrl_flow_0_i(is_control_id_rename[0]),

        .decoded_entry_1_i(decoded_entry_id_rename[1]),
        .decoded_entry_valid_1_i(decoded_entry_valid_id_rename[1]),
        .rename_instr_ack_1_o(decoded_entry_ack_rename_id[1]),
        .is_ctrl_flow_1_i(is_control_id_rename[1]),

        .decoded_entry_2_i(decoded_entry_id_rename[2]),
        .decoded_entry_valid_2_i(decoded_entry_valid_id_rename[2]),
        .rename_instr_ack_2_o(decoded_entry_ack_rename_id[2]),
        .is_ctrl_flow_2_i(is_control_id_rename[2]),

        .decoded_entry_3_i(decoded_entry_id_rename[3]),
        .decoded_entry_valid_3_i(decoded_entry_valid_id_rename[3]),
        .rename_instr_ack_3_o(decoded_entry_ack_rename_id[3]),
        .is_ctrl_flow_3_i(is_control_id_rename[3]),

        // to reservation station
        .issue_entry_0_o(instr_rename_rs[0]),       // a decoded instruction
        .issue_entry_valid_0_o(issue_entry_valid_rename_rs[0]), // issue entry is valid
        .is_ctrl_flow_0_o(is_control_flow_rename_rs[0]),      // the instruction we issue is a ctrl flow instructions
        .issue_instr_ack_0_i(issue_instr_ack_rs_rename),
        
        .issue_entry_1_o(instr_rename_rs[1]),       // a decoded instruction
        .issue_entry_valid_1_o(issue_entry_valid_rename_rs[1]), // issue entry is valid
        .is_ctrl_flow_1_o(is_control_flow_rename_rs[1]),      // the instruction we issue is a ctrl flow instructions
        .issue_instr_ack_1_i(issue_instr_ack_rs_rename),
             
        .issue_entry_2_o(instr_rename_rs[2]),       // a decoded instruction
        .issue_entry_valid_2_o(issue_entry_valid_rename_rs[2]), // issue entry is valid
        .is_ctrl_flow_2_o(is_control_flow_rename_rs[2]),      // the instruction we issue is a ctrl flow instructions
        .issue_instr_ack_2_i(issue_instr_ack_rs_rename),
        .issue_entry_3_o(instr_rename_rs[3]),       // a decoded instruction
        .issue_entry_valid_3_o(issue_entry_valid_rename_rs[3]), // issue entry is valid
        .is_ctrl_flow_3_o(is_control_flow_rename_rs[3]),      // the instruction we issue is a ctrl flow instructions
        .issue_instr_ack_3_i(issue_instr_ack_rs_rename),
        .valid_instruction_o(valid_instr_num_rename_rs),        
        //from commit
        .commit_valid_i(commit_register_valid_rs_rename),
        .commit_register(commit_register_rs_rename),
        .*
    );  
    
    
    reservation_station rs(
        // to rename stage
        .issue_entry_i(instr_rename_rs),       // a decoded instruction
        .issue_entry_valid_i(issue_entry_valid_rename_rs[0]), // issue entry is valid
        .is_ctrl_flow_i(is_control_flow_rename_rs),      // the instruction we issue is a ctrl flow instructions
        .issue_instr_ack_o(issue_instr_ack_rs_rename),
        
        .valid_instruction_num_i(valid_instr_num_rename_rs),
        
         // write-back ports
        .trans_id_i({alu_trans_id_ex_id[0], alu_trans_id_ex_id[1], lsu_trans_id_ex_id, csr_trans_id_ex_id, branch_trans_id_ex_id, mult_trans_id_ex_id}),  // transaction ID at which to write the result back
        .wdata_i({alu_result_ex_id[0], alu_result_ex_id[1], lsu_result_ex_id, csr_result_ex_id, branch_result_ex_id, mult_result_ex_id}),     // write data in
        .ex_i({{$bits(exception_t){1'b0}}, {$bits(exception_t){1'b0}}, lsu_exception_ex_id, {$bits(exception_t){1'b0}}, branch_exception_ex_id, {$bits(exception_t){1'b0}}}),        // exception from a functional unit (e.g.: ld/st exception, divide by zero)
        .wb_valid_i({alu_valid_ex_id[0], alu_valid_ex_id[1], lsu_valid_ex_id, csr_valid_ex_id, branch_valid_ex_id, mult_valid_ex_id}),   // data in is valid
        .flush_i(flush_ctrl_id),
        .flush_unissued_i(flush_unissued_instr_ctrl_id),
        // commit ports
        .commit_instr_o(commit_instr_id_commit),
        .commit_valid_o(commit_instr_valid_rs_commit),
        .commit_ack_i(commit_ack),
         
         // to rename 
        .commit_register_o(commit_register_rs_rename),
        .commit_register_valid_o(commit_register_valid_rs_rename),       
        // to read_op stage
        .issue_instr_o(issue_instr_rs_rd),
        .issue_instr_valid_o(issue_instr_valid_rs_rd),
        .issue_ack_i(issue_ack_rd_rs),
        .rs1_data_o(rs1_data_rs_rd),
        .rs1_forward_valid_o(rs1_forward_valid_rs_rd),  
        .rs2_data_o(rs2_data_rs_rd),
        .rs2_forward_valid_o(rs2_forward_valid_rs_rd),      
        .resolved_branch_valid_i(resolved_branch.valid),
        .is_mis_predict_i(resolved_branch.is_mispredict),
        
        .fu_status_i(fu_status_rd_rs),
        .*
    );
    
    
    issue_read_operands issue_read (
        .issue_instr_i(issue_instr_rs_rd),
        .issue_instr_valid_i(issue_instr_valid_rs_rd),
        .issue_ack_o(issue_ack_rd_rs),
        .fu_status_o(fu_status_rd_rs),
        .flush_i                    ( flush_ctrl_id                   ),
        .rs1_addr({issue_instr_rs_rd[3].rs1, issue_instr_rs_rd[2].rs1, issue_instr_rs_rd[1].rs1, issue_instr_rs_rd[0].rs1}),
        .rs1_data(rs1_data_rs_rd),
        .rs1_forward_valid(rs1_forward_valid_rs_rd),

        .rs2_addr({issue_instr_rs_rd[3].rs2, issue_instr_rs_rd[2].rs2, issue_instr_rs_rd[1].rs2, issue_instr_rs_rd[0].rs2}),
        .rs2_data(rs2_data_rs_rd),
        .rs2_forward_valid(rs2_forward_valid_rs_rd), 

        .rename_index_o(rename_index_rd_rename),
        .debug_gpr_req_i            ( gpr_req_debug_issue             ),
        .debug_gpr_addr_i           ( gpr_addr_debug_issue            ),
        .debug_gpr_we_i             ( gpr_we_debug_issue              ),
        .debug_gpr_wdata_i          ( gpr_wdata_debug_issue           ),
        .debug_gpr_rdata_o          ( gpr_rdata_debug_issue           ),
        // To FU(), just single issue for now
        .valid_o(valid_rd_ex),
        .fu_o(fu_id_ex),
        .operator_o(operator_id_ex),
        .operand_a_o(operand_a_id_ex),
        .operand_b_o(operand_b_id_ex),
        .imm_o(imm_id_ex),           // output immediate for the LSU
        .trans_id_o(trans_id_id_ex),
        .pc_o(pc_id_ex),
        .is_compressed_instr_o(is_compressed_instr_id_ex),
        // ALU 1
        .alu_ready_i(alu_ready_ex_id),      // FU is ready
        // Branches and Jumps
        .branch_ready_i(branch_ready_ex_id),
        .branch_predict_o(branch_predict_id_ex),
        // LSU
        .lsu_ready_i(lsu_ready_ex_id),      // FU is ready
        // MULT
        .mult_ready_i(mult_ready_ex_id),      // FU is ready
        // CSR
        .csr_ready_i(csr_ready_ex_id),      // FU is ready

        // commit port
        .waddr_a_i(waddr_a_commit_id),
        .wdata_a_i(wdata_a_commit_id),
        .we_a_i(we_a_commit_id),    
        .*
    );
    
    ex_stage ex_stage_i (
        .valid_i(valid_rd_ex),
        .fu_i(fu_id_ex),
        .operator_i(operator_id_ex),
        .operand_a_i(operand_a_id_ex),
        .operand_b_i(operand_b_id_ex),
        .imm_i(imm_id_ex),
        .trans_id_i(trans_id_id_ex),
        .pc_i(pc_id_ex),                  // PC of current instruction
        .is_compressed_instr_i(is_compressed_instr_id_ex), // we need to know if this was a compressed instruction
        .flush_i                ( flush_ctrl_ex                          ),
        .rename_index_i(),                                                              // in order to calculate the next PC on a mis-predict
        // ALU 2
        .alu_ready_o(alu_ready_ex_id),           // FU is ready
        .alu_valid_o(alu_valid_ex_id),           // ALU result is valid
        .alu_branch_res_o(),      // Branch comparison result
        .alu_result_o(alu_result_ex_id),
        .alu_trans_id_o(alu_trans_id_ex_id),        // ID of scoreboard entry at which to write back
        .alu_exception_o(alu_exception_ex_id),
        // Branches and Jumps
        .branch_ready_o(branch_ready_ex_id),
        .branch_valid_o(branch_valid_ex_id),        // the calculated branch target is valid
        .branch_result_o(branch_result_ex_id),       // branch target address out
        .branch_predict_i(branch_predict_id_ex),      // branch prediction in
        .rename_index_o(),
        
        .branch_trans_id_o(branch_trans_id_ex_id),
        .branch_exception_o(branch_exception_ex_id),    // branch unit detected an exception
        .resolved_branch_o(resolved_branch),     // the branch engine uses the write back from the ALU
        .resolve_branch_o(resolved_branch_valid),      // to ID signaling that we resolved the branch
        // LSU
        .lsu_ready_o(lsu_ready_ex_id),           // FU is ready
        .lsu_valid_o(lsu_valid_ex_id),           // Output is valid
        .lsu_result_o(lsu_result_ex_id),
        .lsu_trans_id_o(lsu_trans_id_ex_id),
        .lsu_commit_i(lsu_commit_commit_ex),
        .lsu_commit_ready_o(lsu_commit_ready_ex_commit),    // commit queue is ready to accept another commit request
        .lsu_exception_o(lsu_exception_ex_id),
        .no_st_pending_o(no_st_pending_ex_commit),
        // CSR
        .csr_ready_o(csr_ready_ex_id),
        .csr_trans_id_o(csr_trans_id_ex_id),
        .csr_result_o(csr_result_ex_id),
        .csr_valid_o(csr_valid_ex_id),
        .csr_addr_o(),
        .csr_commit_i(),
        // MULT
        .mult_ready_o(mult_ready_ex_id),      // FU is ready
        .mult_trans_id_o(mult_trans_id_ex_id),
        .mult_result_o(mult_result_ex_id),
        .mult_valid_o(mult_valid_ex_id),

        // Memory Management
        .enable_translation_i(1'b0),
        .en_ld_st_translation_i(1'b0),
        .flush_tlb_i(flush_tlb_ctrl_ex),
        .fetch_req_i(fetch_req_if_ex),
        .fetch_gnt_o(fetch_gnt_ex_if),
        .fetch_valid_o(fetch_valid_ex_if),
        .fetch_vaddr_i(fetch_vaddr_if_ex),
        .fetch_rdata_o(fetch_rdata_ex_if),
        .fetch_ex_o(fetch_ex_ex_if),
        .priv_lvl_i(priv_lvl),
        .ld_st_priv_lvl_i(ld_st_priv_lvl_csr_ex),
        .sum_i(sum_csr_ex),
        .mxr_i(mxr_csr_ex),
        .satp_ppn_i(satp_ppn_csr_ex),
        .asid_i(asid_csr_ex),

        // Performance counters
        .itlb_miss_o(),
        .dtlb_miss_o(),
        .dcache_miss_o(),

        .instr_if_address_o(instr_if_address),
        .instr_if_data_req_o(instr_if_data_req),
        .instr_if_data_be_o(instr_if_data_be),
        .instr_if_data_gnt_i(instr_if_data_gnt),
        .instr_if_data_rvalid_i(instr_if_data_rvalid),
        .instr_if_data_rdata_i(instr_if_data_rdata),

        // DCache interface
        .dcache_en_i(dcache_en_csr_nbdcache),
        .flush_dcache_i(flush_dcache_ctrl_ex | flush_dcache_i),
        .flush_dcache_ack_o(flush_dcache_ack_ex_ctrl), 
        .*
        // for testing purpose
        
    );
    
    commit_stage commit_stage_i (
        .exception_o(ex_commit),        // take exception to controller
        .halt_i(halt_ctrl),
        // from scoreboard
        .commit_instr_i(commit_instr_id_commit),     // the instruction we want to commit
        .commit_instr_valid_i(commit_instr_valid_rs_commit),     // it is possible that some instruction included are not ready
        .commit_ack_o(commit_ack),       // acknowledge that we are indeed committing

        // to register file
        .waddr_a_o(waddr_a_commit_id),          // register file write address
        .wdata_a_o(wdata_a_commit_id),          // register file write data
        .we_a_o(we_a_commit_id),             // register file write enable

        // to CSR file and PC Gen (because on certain CSR instructions we'll need to flush the whole pipeline)
        .pc_o(pc_commit),
        // to/from CSR file
        .csr_op_o(csr_op_commit_csr),           // decoded CSR operation
        .csr_wdata_o(csr_wdata_commit_csr),        // data to write to CSR
        .csr_rdata_i(csr_rdata_csr_commit),        // data to read from CSR
        .csr_exception_i(csr_exception_csr_commit),    // exception or interrupt occurred in CSR stage (the same as commit)
        // commit signals to ex
        .commit_lsu_o(lsu_commit_commit_ex),       // commit the pending store
        .commit_lsu_ready_i(lsu_commit_ready_ex_commit), // commit buffer of LSU is ready
        .no_st_pending_i(no_st_pending_ex_commit),    // there is no store pending
        .commit_csr_o(csr_commit_commit_ex),       // commit the pending CSR instruction
        .fence_i_o(fence_i_commit_controller),          // flush I$ and pipeline
        .fence_o(fence_commit_controller),            // flush D$ and pipeline
        .sfence_vma_o(sfence_vma_commit_controller),        // flush TLBs and pipeline  
        .*
    );
    
    icache i_cache (
       .clk_i               ( clk_i                          ),
       .rst_n               ( rst_ni                         ),
       .test_en_i           ( test_en_i                      ),
       .fetch_req_i         ( instr_if_data_req              ),
       .fetch_addr_i        ( {instr_if_address[55:2], 2'b0} ),
       .fetch_gnt_o         ( instr_if_data_gnt              ),
       .fetch_rvalid_o      ( instr_if_data_rvalid           ),
       .fetch_rdata_o       ( instr_if_data_rdata            ),
       .axi                 ( instr_if                       ),
       .bypass_icache_i     ( ~bypass_icache_csr_icache      ),
       .cache_is_bypassed_o (                                ),
       .flush_icache_i      ( flush_icache_ctrl_icache       ),
       .cache_is_flushed_o  ( flush_icache_ack_icache_ctrl   ),
       .flush_set_ID_req_i  ( 1'b0                           ),
       .flush_set_ID_addr_i ( '0                             ),
       .flush_set_ID_ack_o  (                                )  
    );
    
    
    controller controller_i (
        // flush ports
        .flush_bp_o             ( flush_bp_ctrl_pcgen           ),
        .flush_pcgen_o          ( flush_ctrl_pcgen              ),
        .flush_unissued_instr_o ( flush_unissued_instr_ctrl_id  ),
        .flush_if_o             ( flush_ctrl_if                 ),
        .flush_id_o             ( flush_ctrl_id                 ),
        .flush_ex_o             ( flush_ctrl_ex                 ),
        .flush_tlb_o            ( flush_tlb_ctrl_ex             ),
        .flush_dcache_o         ( flush_dcache_ctrl_ex          ),
        .flush_dcache_ack_i     ( flush_dcache_ack_ex_ctrl      ),

        .halt_csr_i             ( halt_csr_ctrl                 ),
        .halt_debug_i           ( halt_debug_ctrl               ),
        .debug_set_pc_i         ( set_pc_debug                  ),
        .halt_o                 ( halt_ctrl                     ),
        // control ports
        .eret_i                 ( eret                          ),
        .ex_valid_i             ( ex_commit.valid               ),
        .flush_csr_i            ( flush_csr_ctrl                ),
        .resolved_branch_i      ( resolved_branch               ),
        .fence_i_i              ( fence_i_commit_controller     ),
        .fence_i                ( fence_commit_controller       ),
        .sfence_vma_i           ( sfence_vma_commit_controller  ),

        .flush_icache_o         ( flush_icache_ctrl_icache      ),
        .flush_icache_ack_i     ( flush_icache_ack_icache_ctrl  ),
        .*
    );
    
    csr_regfile csr_reg (
        .flush_o                ( flush_csr_ctrl                ),
        .halt_csr_o             ( halt_csr_ctrl                 ),
        .debug_csr_req_i        ( csr_req_debug_csr             ),
        .debug_csr_addr_i       ( csr_addr_debug_csr            ),
        .debug_csr_we_i         ( csr_we_debug_csr              ),
        .debug_csr_wdata_i      ( csr_wdata_debug_csr           ),
        .debug_csr_rdata_o      ( csr_rdata_debug_csr           ),
        .commit_ack_i           ( commit_ack                    ),
        .ex_i                   ( ex_commit                     ),
        .csr_op_i               ( csr_op_commit_csr             ),
        .csr_addr_i             ( csr_addr_ex_csr               ),
        .csr_wdata_i            ( csr_wdata_commit_csr          ),
        .csr_rdata_o            ( csr_rdata_csr_commit          ),
        .pc_i                   ( pc_commit                     ),
        .csr_exception_o        ( csr_exception_csr_commit      ),
        .epc_o                  ( epc_commit_pcgen              ),
        .eret_o                 ( eret                          ),
        .trap_vector_base_o     ( trap_vector_base_commit_pcgen ),
        .priv_lvl_o             ( priv_lvl                      ),
        .ld_st_priv_lvl_o       ( ld_st_priv_lvl_csr_ex         ),
        .en_translation_o       ( enable_translation_csr_ex     ),
        .en_ld_st_translation_o ( en_ld_st_translation_csr_ex   ),
        .sum_o                  ( sum_csr_ex                    ),
        .mxr_o                  ( mxr_csr_ex                    ),
        .satp_ppn_o             ( satp_ppn_csr_ex               ),
        .asid_o                 ( asid_csr_ex                   ),
        .tvm_o                  ( tvm_csr_id                    ),
        .tw_o                   ( tw_csr_id                     ),
        .tsr_o                  ( tsr_csr_id                    ),
        .dcache_en_o            ( dcache_en_csr_nbdcache        ),
        .icache_en_o            ( bypass_icache_csr_icache      ),
        .perf_addr_o            ( addr_csr_perf                 ),
        .perf_data_o            ( data_csr_perf                 ),
        .perf_data_i            ( data_perf_csr                 ),
        .perf_we_o              ( we_csr_perf                   ),
        .*
    );
    



    `ifdef VTRACE
    // mock tracer for Verilator, to be used with spike-dasm
    int f;
    logic [63:0] cycles;
    int unissued;
    int wb;
    initial begin
        f = $fopen("./out/ariane.trace.dasm", "w");
    end

    always_ff @(posedge clk_i)
        if (~rst_ni)
            cycles <= 0;
        else
            cycles <= cycles + 1;
    always@(*)
    begin
        wb = 0;
        unissued = 0;
        for (int unsigned i=0;i<16;i++)
            if (rs.instruction_queue_q[i].valid) 
                unissued++;  
    end

    // BEGIN your answer h1wb
    always_ff @(posedge clk_i) begin : print_signals

        $fwrite(f, "current pc: 0x%h next pc: 0x%h \n", pcgen_stage_i.npc_q, pcgen_stage_i.npc_n);
        
        if (if_stage_i.full ||!if_stage_i.fifo_ready)
            $fwrite(f, "fifo full\n");            
        if (if_ready_if_pcgen)
            $fwrite(f,"if is not ready\n");

        if (i_cache.fetch_req_i && i_cache.fetch_rvalid_o)
        begin
            $fwrite(f ,"cache granted%h\n", i_cache.fetch_rdata_o);
        end

        if (if_stage_i.i_fetch_fifo.valid_i)
        begin
            $fwrite(f, "fifoed %h\n", if_stage_i.instr_rdata_i);
            $fwrite(f, "fifoed2%h\n", i_cache.fetch_rdata_o);
        end
        if (fetch_entry_valid_if_id[0])
        begin
            $fwrite(f, "fetch valid once\n");
            $fwrite(f ,"fetched address 0x%h\n", fetch_entry_if_id[0].address);
            $fwrite(f ,"fetched 0x%h\n", fetch_entry_if_id[0].instruction);
        end
        if (fetch_ack_if_id[0])
            $fwrite(f," id ack once\n");
        if (decoded_entry_valid_id_rename[0])
            $fwrite(f,"decoded valid once\n");
        if (decoded_entry_ack_rename_id[0])
            $fwrite(f, "rename ack\n");

        if (i_cache.refill_r_valid_from_comp)
        begin
            $fwrite(f, "refilled 0xh%h\n", i_cache.refill_r_rdata_from_comp);
            $fwrite(f, "pre %h\n", i_cache.i_icache_controller_private.previous_r);

        end
        $fwrite(f, "write back status %h \n", rs.wb_valid_i);
        if (id_stage_i.decoded_instr_ack_o_0)
            $fwrite(f, "sig\n");
        $fwrite(f ,"fetch valid status %h\n", fetch_entry_valid_if_id);
        $fwrite(f ,"fifo status %h\n", if_stage_i.i_fetch_fifo.status_cnt_q);
        $fwrite(f, "fetch ack status %h\n", {if_stage_i.fetch_ack_0_i, if_stage_i.fetch_ack_1_i, if_stage_i.fetch_ack_2_i, if_stage_i.fetch_ack_3_i} );
        $fwrite(f, "id ack status %h\n", {id_stage_i.fetch_entry_valid_i_0, id_stage_i.fetch_entry_valid_i_1, id_stage_i.fetch_entry_valid_i_2, id_stage_i.fetch_entry_valid_i_3} );
        $fwrite(f, "id issue status %h\n", {id_stage_i.issue_q_0.valid, id_stage_i.issue_q_1.valid, id_stage_i.issue_q_2.valid, id_stage_i.issue_q_3.valid} );
        $fwrite(f, "incoming %d\n", rename.valid_instruction_o);

    
        $fwrite(f, "re %d\n", rs.instruction_num_q);
        $fwrite(f, "issued %d\n", unissued);
        $fwrite(f, "issue ack %h\n", issue_ack_rd_rs);
        $fwrite(f, "fu status %b\n", fu_status_rd_rs);

        $fwrite(f, "commit status%b\n", commit_ack);
        $fwrite(f, "issue pointer %h\n", rs.issue_pointer);
        $fwrite(f ,"issue valid %h\n", rs.issue_valid);
        $fwrite(f, "instruction status %d\n", rs.instr_status);
        $fwrite(f, "unissed using fu\n");
        


        for (int unsigned j=0; j<16;j++)
        begin
            if (rs.instruction_queue_q[j].valid && !rs.instruction_queue_q[j].issued)
                $fwrite(f, "fu using is %d bloking %d rd %d rs1 %d rs2 %d rename index %d\n", rs.instruction_queue_q[j].sbe.fu, rs.instruction_queue_q[j].num_of_branch_block, rs.instruction_queue_q[j].sbe.rd, rs.instruction_queue_q[j].sbe.rs1, rs.instruction_queue_q[j].sbe.rs2, rs.instruction_queue_q[j].sbe.rename_index);
        end

        $fwrite(f,"rename table using ");           
         for (int unsigned i=0;i<32;i++)
            $fwrite(f, "%d ", rename.lookup_table_q[i]);
        $fwrite(f, "\n");
        $fwrite(f, "next five free reg is %d  %d %d %d %d\n", rename.free_q[rename.read_pointer_q], rename.free_q[rename.read_pointer_q+1], rename.free_q[rename.read_pointer_q+2], rename.free_q[rename.read_pointer_q+3], rename.free_q[rename.read_pointer_q + 4]);


        $fwrite(f, "uncomited using fu\n");
        for (int unsigned j=0; j<16;j++)
        begin
            if (rs.instruction_queue_q[j].valid && rs.instruction_queue_q[j].issued)
                $fwrite(f, "fu using is %d blocking %d\n", rs.instruction_queue_q[j].sbe.fu, rs.instruction_queue_q[j].num_of_commit_block);
        end        

        if (commit_stage_i.exception_o.valid)
            $fwrite(f, "valid ex\n");

        $fwrite(f, "valid instr sta %h\n", {decoded_entry_id_rename[0].decoded.is_included, decoded_entry_id_rename[1].decoded.is_included, decoded_entry_id_rename[2].decoded.is_included, decoded_entry_id_rename[3].decoded.is_included});
        
        if (resolved_branch_valid && resolved_branch.is_mispredict)
        begin
            $fwrite(f, "mis prediction rename index %d new lookup table are below\n", rename.rename_index_i);
            for (int unsigned i=0;i<32;i++)
                $fwrite(f, "%d ", rename.lookup_table_n[i]);
            $fwrite(f, "\n");

            $fwrite(f, "operand a %d, operand_b %d, operator %d branch result %d\n", ex_stage_i.operand_a[2], ex_stage_i.operand_b[2], ex_stage_i.op[2], ex_stage_i.branch_comp_res);
        end

        if (commit_ack != 4'b0)
        begin
            $fwrite(f, "reg we is %h\n", issue_read.we);
        end

        if (issue_read.we != 4'b0)
        begin
            $fwrite(f, "writing %h  data %d, %d, %d, %d\n", issue_read.we,issue_read.wdata[3], issue_read.wdata[2], issue_read.wdata[1], issue_read.wdata[0]);
            $fwrite(f, "addresses are %d, %d, %d, %d\n", issue_read.waddr[3], issue_read.waddr[2], issue_read.waddr[1], issue_read.waddr[0]);
        end

        

        for (int unsigned i = 0; i < 4; i++)
        begin
            if (rename.issue_q[i].is_valid && rename.issue_q[i].sbe.bp.valid)
                $fwrite(f ,"saved index is %d", rename.issue_q[i].sbe.rename_index);
        end
        
        if (rename.history_pointer_n != rename.history_pointer_q)
        begin
            $fwrite(f, "rename saved %h\n", rename.history_pointer_n);
        end

        if (rename.rename_instr_ack_0_o)
        begin
            $fwrite(f, "rds translated %d, %d, %d, %d\n", rename.issue_entry_0_o.rd, rename.issue_entry_1_o.rd, rename.issue_entry_2_o.rd, rename.issue_entry_3_o.rd);
        end

        if (ex_stage_i.valid[2])
        begin
            $fwrite(f, "opa %h, opb %h\n", ex_stage_i.operand_a[2], ex_stage_i.operand_b[2]);
        end
        $fwrite(f, "refile enable %h\n", issue_read.we);
        $fwrite(f, "reg file content\n");
        for (int unsigned i=0;i<128;i++)
        begin
            $fwrite(f ,"%d ", issue_read.regfile_i.mem[i]);
        end
        $fwrite(f, "\n");
        // some frontend exploration
        /*
        if (pcgen_stage_i.npc_q == pcgen_stage_i.npc_n) begin
            $fwrite(f, "frontend stall caused by ");
            if (i_icache.fetch_req_i && !i_icache.i_icache_controller_private.fetch_gnt_o)
            begin
                $fwrite(f, "icache miss fetching 0x%h", if_stage_i.instr_addr_o);
            end
            if (i_icache.fetch_req_i && i_icache.i_icache_controller_private.fetch_gnt_o && if_stage_i.is_waiting_gnt)
                $fwrite(f, "cache access fetching 0x%h", if_stage_i.instr_addr_o);
            
            if (if_stage_i.full)
                $fwrite(f, "address fifo full ");
            
            if (!if_stage_i.fifo_ready)
                $fwrite(f, "fetch fifo full ");
            
            if (if_stage_i.is_wait_aborted_request)
            begin
                $fwrite(f, "waited aborted request ");
            end
            
            if (if_stage_i.is_wait_aborted)
                $fwrite(f, "wait aboted ");
            $fwrite(f, "\n");
        end
        */
    end
    // END your answer h1wb

    final begin
        $fclose(f);
    end
    `endif



    
endmodule 