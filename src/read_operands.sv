import ariane_pkg::*;

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
   
	output logic 				[4:0]					rename_index_o,
    
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
    input  logic				                                            	   branch_ready_i,
    output branchpredict_sbe_t                          branch_predict_o,
    // LSU
    input  logic 	   			                                   lsu_ready_i,      // FU is ready
    // MULT
    input  logic 				                                  mult_ready_i,      // FU is ready
    // CSR
    input  logic 				                                  csr_ready_i,      // FU is ready
    
	// commit port
    input  logic 				[NR_WB_PORTS-1:0][6:0]                             waddr_a_i,
    input  logic 				[NR_WB_PORTS-1:0][63:0]                            wdata_a_i,
    input  logic 				[NR_WB_PORTS-1:0]                                  we_a_i
    // committing instruction instruction
    // from scoreboard
    // input  scoreboard_entry     commit_instr_i,
    // output logic                commit_ack_o
);
    logic [NR_WB_PORTS-1:0][63:0] operand_a_regfile, operand_b_regfile;  // operands coming from regfile

    // output flipflop (ID <-> EX)
    logic [NR_WB_PORTS-1:0][63:0] operand_a_n, operand_a_q,
								  operand_b_n, operand_b_q,
                                  imm_n, imm_q;

	logic [NR_WB_PORTS-1:0] valid_n, valid_q;
	branchpredict_sbe_t   bp_n;	
    logic [NR_WB_PORTS-1:0][TRANS_ID_BITS-1:0] trans_id_n, trans_id_q;
    fu_op [NR_WB_PORTS-1:0] operator_q, operator_n; // operation to perform
    fu_t  [NR_WB_PORTS-1:0] fu_q, fu_n; // functional unit to use
	logic [4:0]				rename_index_q, rename_index_n;
 
    // ID <-> EX registers
    assign operand_a_o    = operand_a_q;
    assign operand_b_o    = operand_b_q;
    assign fu_o           = fu_q;
    assign operator_o     = operator_q;
    assign trans_id_o     = trans_id_q;
    assign imm_o          = imm_q;
	assign valid_o   	  = valid_q;
	assign rename_index_o = rename_index_q;
	
	// valid & acknowledge bit assignment
    always_comb begin : unit_busy
		valid_n = 4'b0;
		issue_ack_o = 4'b0;
		bp_n = '0;
		rename_index_n = '0;
		for (int unsigned i = 0; i < NR_WB_PORTS; i+=1) begin        
			unique case (issue_instr_i[i].fu)
				ALU:
				begin
					if (alu_ready_i != 2'b0 && issue_instr_valid_i[i])
					begin
						valid_n[i] = 1'b1;
						issue_ack_o[i] = 1'b1;
					end
				end
				CTRL_FLOW:
				begin
					if (issue_instr_valid_i[i] && branch_ready_i != 1'b0)
					begin
						valid_n[i] = 1'b1;
						bp_n = issue_instr_i[i].bp;
						issue_ack_o[i] = 1'b1;
						rename_index_n = issue_instr_i[i].rename_index;
					end
				end
				MULT:
				begin
					if (mult_ready_i != 1'b0 && issue_instr_valid_i[i])
					begin
						valid_n[i] = 1'b1;
						issue_ack_o[i] = 1'b1;
					end
				end
				LOAD, STORE:
				begin
					if (lsu_ready_i != 1'b0 && issue_instr_valid_i[i])
					begin
						valid_n[i] = 1'b1;
						issue_ack_o[i] = 1'b1;
					end
				end
				CSR:
				begin
					if (csr_ready_i != 1'b0 && issue_instr_valid_i[i])
					begin
						valid_n[i] = 1'b1;
						issue_ack_o[i] = 1'b1;
					end	
				end
				default:;
			endcase
		end
    end
    
     
    // Forwarding/Output MUX
    always_comb begin : forwarding_operand_select
        // default is regfile
        operand_a_n = operand_a_regfile;
        operand_b_n = operand_b_regfile;
        // immediates are the third operands in the store case
		for (int unsigned i=0; i < NR_WB_PORTS; i+=1) begin
			imm_n[i]      = issue_instr_i[i].result;
			trans_id_n[i] = issue_instr_i[i].trans_id;
			fu_n[i]       = issue_instr_i[i].fu;
			operator_n[i] = issue_instr_i[i].op;
		end
        // or should we forward
		for (int unsigned i=0; i < NR_WB_PORTS; i+=1) begin
			if (rs1_forward_valid[i]) begin
				operand_a_n[i]  = rs1_data[i];
			end

			if (rs2_forward_valid[i]) begin
				operand_b_n[i]  = rs2_data[i];
			end

			// use the PC as operand a
			if (issue_instr_i[i].use_pc) begin
				operand_a_n[i] = issue_instr_i[i].pc;
			end

			// use the zimm as operand a
			if (issue_instr_i[i].use_zimm) begin
				// zero extend operand a
				operand_a_n[i] = {57'b0, issue_instr_i[i].rs1};
			end
			// or is it an immediate (including PC), this is not the case for a store and control flow instructions
			if (issue_instr_i[i].use_imm && (issue_instr_i[i].fu != STORE) && (issue_instr_i[i].fu != CTRL_FLOW)) begin
				operand_b_n[i] = issue_instr_i[i].result;
			end
		end
    end
	
	
	// function unit status out
    always_comb begin : unit_valid		
		fu_status_o = '{default:0};
		if (alu_ready_i[0])
			fu_status_o[1] = fu_status_o[1] + 1;
			
		if (alu_ready_i[1])
			fu_status_o[1] = fu_status_o[1] + 1;
		
		fu_status_o[0] = {1'b0, lsu_ready_i};
		fu_status_o[2] = {1'b0, branch_ready_i};
		fu_status_o[3] = {1'b0, mult_ready_i};
		fu_status_o[4] = {1'b0, csr_ready_i};
		
        if (flush_i) begin
			fu_status_o[0] = 2'b1;
			fu_status_o[1] = 2'b10;
			fu_status_o[2] = 2'b1;
			fu_status_o[3] = 2'b1;
			fu_status_o[4] = 2'b1;
        end
    end

    // --------------------
    // Debug Multiplexers
    // --------------------
    logic [NR_WB_PORTS-1:0][6:0]    raddr_a,raddr_b, waddr;
    logic [NR_WB_PORTS-1:0][63:0]   wdata;
    logic [NR_WB_PORTS-1:0]         we;

    always_comb begin
        // get the address from the issue stage by default
        // read port
        debug_gpr_rdata_o = operand_a_regfile;
        raddr_a           = rs1_addr;
        raddr_b           = rs2_addr;
        // write port
        waddr             = waddr_a_i;
        wdata             = wdata_a_i;
        we                = we_a_i;
        // we've got a debug request in
        if (debug_gpr_req_i) begin
            raddr_a = debug_gpr_addr_i;
            waddr   = debug_gpr_addr_i;
            wdata   = debug_gpr_wdata_i;
            we     = debug_gpr_we_i;
        end
    end

    // ----------------------
    // Integer Register File
    // ----------------------
    regfile #(
        .DATA_WIDTH     ( 64                 )
    )
    regfile_i (
        // Clock and Reset
        .clk            ( clk_i                                ),
        .rst_n          ( rst_ni                               ),
        .test_en_i      ( test_en_i                            ),

        .raddr_a_i      ( rs1_addr[NR_WB_PORTS-1:0]            ),
        .rdata_a_o      ( operand_a_regfile[NR_WB_PORTS-1:0]   ),

        .raddr_b_i      ( rs2_addr[NR_WB_PORTS-1:0]        ),
        .rdata_b_o      ( operand_b_regfile[NR_WB_PORTS-1:0]   ),

        .waddr_a_i      ( waddr[NR_WB_PORTS-1:0]               ),
        .wdata_a_i      ( wdata[NR_WB_PORTS-1:0]               ),
        .we_a_i         ( we[NR_WB_PORTS-1:0]                  )
    );

    // ----------------------
    // Registers (ID <-> EX)
    // ----------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(~rst_ni) begin
			valid_q								   <= 4'b0;
            operand_a_q           <= '{default:0};
            operand_b_q         <= '{default:0};
            imm_q           <= '{default:0};
            fu_q                  <= '{default:NONE};
            operator_q            <= '{default:ADD};
            trans_id_q            <= '{default:0};
            pc_o                  <= '{default:0};
            is_compressed_instr_o <= '0;
            branch_predict_o			           <= '{default: 0};
			rename_index_q        <= '{default:0};
        end else begin
			valid_q				  <= valid_n;
            operand_a_q           <= operand_a_n;
            operand_b_q           <= operand_b_n;
            imm_q                 <= imm_n;
            fu_q                  <= fu_n;
            operator_q            <= operator_n;
            trans_id_q            <= trans_id_n;
            pc_o[3]             <= issue_instr_i[3].pc;
            pc_o[2]             <= issue_instr_i[2].pc;
            pc_o[1]             <= issue_instr_i[1].pc;
            pc_o[0]             <= issue_instr_i[0].pc;
            is_compressed_instr_o[3] <= issue_instr_i[3].is_compressed;
            is_compressed_instr_o[2] <= issue_instr_i[2].is_compressed;
            is_compressed_instr_o[1] <= issue_instr_i[1].is_compressed;
            is_compressed_instr_o[0] <= issue_instr_i[0].is_compressed;
            branch_predict_o      <= bp_n;
			rename_index_q        <= rename_index_n;  
        end
    end
endmodule