`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/12/2018 12:30:42 PM
// Design Name: 
// Module Name: rename_stage
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//import ariane_pkg::*;

    timeunit      1ns;
    timeprecision 1ps;

    // ---------------
    // Global Config
    // ---------------
    localparam NR_SB_ENTRIES = 8; // number of scoreboard entries
    localparam TRANS_ID_BITS = $clog2(NR_SB_ENTRIES); // depending on the number of scoreboard entries we need that many bits
                                                      // to uniquely identify the entry in the scoreboard
    localparam NR_WB_PORTS   = 5;
    localparam ASID_WIDTH    = 1;
    localparam BTB_ENTRIES   = 8;
    localparam BITS_SATURATION_COUNTER = 2;

    // ---------------
    // Fetch Stage
    // ---------------
    // Only use struct when signals have same direction
    // exception
    typedef struct packed {
         logic [63:0] cause; // cause of exception
         logic [63:0] tval;  // additional information of causing exception (e.g.: instruction causing it),
                             // address of LD/ST fault
         logic        valid;
    } exception_t;

    // branch-predict
    // this is the struct we get back from ex stage and we will use it to update
    // all the necessary data structures
    typedef struct packed {
        logic [63:0] pc;              // pc of predict or mis-predict
        logic [63:0] target_address;  // target address at which to jump, or not
        logic        is_mispredict;   // set if this was a mis-predict
        logic        is_taken;        // branch is taken
        logic        is_lower_16;     // branch instruction is compressed and resides
                                      // in the lower 16 bit of the word
        logic        valid;           // prediction with all its values is valid
        logic        clear;           // invalidate this entry
		logic [8:0]  rename_index;
    } branchpredict_t;

    // branchpredict scoreboard entry
    // this is the struct which we will inject into the pipeline to guide the various
    // units towards the correct branch decision and resolve
    typedef struct packed {
        logic [63:0] predict_address; // target address at which to jump, or not
        logic        predict_taken;   // branch is taken
        logic        is_lower_16;     // branch instruction is compressed and resides
                                      // in the lower 16 bit of the word
        logic        valid;           // this is a valid hint
    } branchpredict_sbe_t;

    typedef enum logic[3:0] {
        NONE, LOAD, STORE, ALU, CTRL_FLOW, MULT, CSR
    } fu_t;
	 typedef enum logic [6:0] { // basic ALU op
                               ADD, SUB, ADDW, SUBW,
                               // logic operations
                               XORL, ORL, ANDL,
                               // shifts
                               SRA, SRL, SLL, SRLW, SLLW, SRAW,
                               // comparisons
                               LTS, LTU, GES, GEU, EQ, NE,
                               // jumps
                               JALR,
                               // set lower than operations
                               SLTS, SLTU,
                               // CSR functions
                               MRET, SRET, ECALL, WFI, FENCE, FENCE_I, SFENCE_VMA, CSR_WRITE, CSR_READ, CSR_SET, CSR_CLEAR,
                               // LSU functions
                               LD, SD, LW, LWU, SW, LH, LHU, SH, LB, SB, LBU,
                               // Atomic Memory Operations
                               AMO_LRW, AMO_LRD, AMO_SCW, AMO_SCD,
                               AMO_SWAPW, AMO_ADDW, AMO_ANDW, AMO_ORW, AMO_XORW, AMO_MAXW, AMO_MAXWU, AMO_MINW, AMO_MINWU,
                               AMO_SWAPD, AMO_ADDD, AMO_ANDD, AMO_ORD, AMO_XORD, AMO_MAXD, AMO_MAXDU, AMO_MIND, AMO_MINDU,
                               // Multiplications
                               MUL, MULH, MULHU, MULHSU, MULW,
                               // Divisions
                               DIV, DIVU, DIVW, DIVUW, REM, REMU, REMW, REMUW
                             } fu_op;
	

    localparam EXC_OFF_RST      = 8'h80;

    typedef struct packed {
        logic [63:0]              pc;            // PC of instruction
        logic [TRANS_ID_BITS-1:0] trans_id;      // this can potentially be simplified, we could index the scoreboard entry
                                                 // with the transaction id in any case make the width more generic
        fu_t                      fu;            // functional unit to use
        fu_op                     op;            // operation to perform in each functional unit
        logic [7:0]               rs1;           // register source address 1
        logic [7:0]               rs2;           // register source address 2
        logic [7:0]               rd;            // register destination address
        logic [63:0]              result;        // for unfinished instructions this field also holds the immediate
        logic                     valid;         // is the result valid
        logic                     use_imm;       // should we use the immediate as operand b?
        logic                     use_zimm;      // use zimm as operand a
        logic                     use_pc;        // set if we need to use the PC as operand a, PC from exception
        exception_t               ex;            // exception has occurred
        branchpredict_sbe_t       bp;            // branch predict scoreboard data structure
        logic                     is_compressed; // signals a compressed instructions, we need this information at the commit stage if
                                                 // we want jump accordingly e.g.: +4, +2
		logic [8:0]				  rename_index;					  
	} scoreboard_entry_t;
	
	typedef struct packed {
		scoreboard_entry_t decoded;
		logic 			   valid;
	} decoded_entry_t;


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
    
    // from reservation station
    input logic                                     station_ready_i,
    
    //from commit
    input logic [3:0]                               commit_valid_i,
    input logic [3:0][PYH_RES_BIT-1:0]              commit_register                   
);
    
    struct packed {
        scoreboard_entry_t sbe;
        logic              is_control;
        logic              is_valid;
    }[3:0]issue_n, issue_q;
    
    assign issue_entry_0_o = issue_q[0].sbe;
    assign issue_entry_valid_0_o = issue_q[0].is_valid;
    assign is_ctrl_flow_0_o = issue_q[0].is_control;
    assign issue_entry_1_o = issue_q[1].sbe;
    assign issue_entry_valid_1_o = issue_q[1].is_valid;
    assign is_ctrl_flow_1_o = issue_q[1].is_control;
    assign issue_entry_2_o = issue_q[2].sbe;
    assign issue_entry_valid_2_o = issue_q[2].is_valid;
    assign is_ctrl_flow_2_o = issue_q[2].is_control;
    assign issue_entry_3_o = issue_q[3].sbe;
    assign issue_entry_valid_3_o = issue_q[3].is_valid;
    assign is_ctrl_flow_3_o = issue_q[3].is_control;
    
    
	// history tables
	logic [4:0]											 history_pointer_n, history_pointer_q;
	logic [4:0]											 history_num_n, history_num_q;
    logic [NUM_OF_ISA_RES-1:0][PYH_RES_BIT-1:0]    		 lookup_table_n, lookup_table_q;
    logic [31:0][NUM_OF_ISA_RES-1:0][PYH_RES_BIT-1:0]    lookup_buffer_n, lookup_buffer_q;

    logic [NUM_OF_PYH_RES-1:0][PYH_RES_BIT-1:0]    		 free_n, free_q;
    logic [31:0][NUM_OF_PYH_RES-1:0][PYH_RES_BIT-1:0]    free_buffer_n, free_buffer_q;

    logic [PYH_RES_BIT:0]                          		 free_num_n, free_num_q;
    logic [PYH_RES_BIT-1:0]                        		 read_pointer_n, read_pointer_q;
    logic [PYH_RES_BIT-1:0]                        		 write_pointer_n, write_pointer_q;
    logic [2:0]											 valid_branch;
    assign rename_instr_ack_0_o = (free_num_q >= 4 || commit_valid_i == 4'b1111) && decoded_entry_valid_0_i && station_ready_i && (valid_branch+history_num_q <= 32);
    assign rename_instr_ack_1_o = (free_num_q >= 4 || commit_valid_i == 4'b1111) && decoded_entry_valid_1_i && station_ready_i && (valid_branch+history_num_q <= 32);
    assign rename_instr_ack_2_o = (free_num_q >= 4 || commit_valid_i == 4'b1111) && decoded_entry_valid_2_i && station_ready_i && (valid_branch+history_num_q <= 32);
    assign rename_instr_ack_3_o = (free_num_q >= 4 || commit_valid_i == 4'b1111) && decoded_entry_valid_3_i && station_ready_i && (valid_branch+history_num_q <= 32);
    
	always@(*)
	begin
		valid_branch = 0;
		if (decoded_entry_0_i.decoded.bp.valid)
			valid_branch=valid_branch+1;
		if (decoded_entry_1_i.decoded.bp.valid)
			valid_branch=valid_branch+1;
		if (decoded_entry_2_i.decoded.bp.valid)
			valid_branch=valid_branch+1;
		if (decoded_entry_3_i.decoded.bp.valid)
			valid_branch=valid_branch+1;
	end
	
	
    always@(*)
    begin
        // default assignment
        lookup_table_n = lookup_table_q;
        free_n = free_q;
        free_num_n = free_num_q;
        read_pointer_n = read_pointer_q;
        write_pointer_n = write_pointer_q;
        history_pointer_n = history_pointer_q;
		lookup_buffer_n = lookup_buffer_q;
		free_buffer_n = free_buffer_q;
		history_num_n = history_num_q;
		
        issue_n[0].is_valid = decoded_entry_valid_0_i;
        issue_n[0].is_control = is_ctrl_flow_0_i;
        issue_n[1].is_valid = decoded_entry_valid_1_i;
        issue_n[1].is_control = is_ctrl_flow_1_i;
        issue_n[2].is_valid = decoded_entry_valid_2_i;
        issue_n[2].is_control = is_ctrl_flow_2_i;
        issue_n[3].is_valid = decoded_entry_valid_3_i;
        issue_n[3].is_control = is_ctrl_flow_3_i;
        
        // mis-prediction handlings
		if (resolved_branch_valid_i && is_mispredict_i)
		begin
			// assign free_n and lookup_table_n values in buffer
			// and flush history table
			lookup_table_n = lookup_buffer_q[rename_index_i];
			free_n = free_buffer_q[rename_index_i];
			free_buffer_n = '{default:0};
			lookup_buffer_n = '{default:0};
		end
		else if (resolved_branch_valid_i && !is_mispredict_i)
		begin
			history_num_n = history_num_n - 1;
		end
		
		
		// commit first
        if (commit_valid_i[0])
        begin
            free_n[write_pointer_n] = commit_register[0];
            free_num_n = free_num_n + 1;
            write_pointer_n = write_pointer_n+1;
        end
        
        if (commit_valid_i[1])
        begin
            free_n[write_pointer_n] = commit_register[1];
            write_pointer_n = write_pointer_n+1;
            free_num_n = free_num_n + 1;
        end
        
        if (commit_valid_i[2])
        begin
            free_n[write_pointer_n] = commit_register[2];
            write_pointer_n = write_pointer_n+1;
            free_num_n = free_num_n + 1;
        end
        
        if (commit_valid_i[3])
        begin
            free_n[write_pointer_n] = commit_register[3];
            write_pointer_n = write_pointer_n+1;
            free_num_n = free_num_n + 1;
        end
        
		// resolved branch is correct or resolved branch is not valid
		if ((resolved_branch_valid_i && !is_mispredict_i) || !resolved_branch_valid_i)
		begin
			// translation
			if (rename_instr_ack_0_o)
			begin
				if (decoded_entry_0_i.valid)
				begin
					// rs translation
					issue_n[0].sbe = decoded_entry_0_i.decoded;        
					issue_n[0].sbe.rs1 = lookup_table_n[decoded_entry_0_i.decoded.rs1[ISA_RES_BIT-1:0]];
					issue_n[0].sbe.rs2 = lookup_table_n[decoded_entry_0_i.decoded.rs2[ISA_RES_BIT-1:0]];
					// rd translation & look up
					if (decoded_entry_0_i.decoded.rd != 31)
					begin
						lookup_table_n[decoded_entry_0_i.decoded.rd[ISA_RES_BIT-1:0]] = free_n[read_pointer_n];
						read_pointer_n=read_pointer_n+1;
						issue_n[0].sbe.rd = lookup_table_n[decoded_entry_0_i.decoded.rd[ISA_RES_BIT-1:0]];
					end
					else 
					begin
						// always zero
						issue_n[0].sbe.rd = 127;
					end
					// if this instruction is a branch save free list and lookup table
					if (decoded_entry_0_i.decoded.bp.valid)
					begin
						lookup_buffer_n[history_pointer_n] = lookup_table_n;
						free_buffer_n[history_pointer_n] = free_n;
						history_pointer_n = history_pointer_n+1;
					end
					free_num_n = free_num_n-1;
				end
				
			    if (decoded_entry_1_i.valid)
				begin
					// rs translation
					issue_n[1].sbe = decoded_entry_1_i.decoded;        
					issue_n[1].sbe.rs1 = lookup_table_n[decoded_entry_1_i.decoded.rs1[ISA_RES_BIT-1:0]];
					issue_n[1].sbe.rs2 = lookup_table_n[decoded_entry_1_i.decoded.rs2[ISA_RES_BIT-1:0]];
					// rd translation & look up
					if (decoded_entry_1_i.decoded.rd != 31)
					begin
					lookup_table_n[decoded_entry_1_i.decoded.rd[ISA_RES_BIT-1:0]] = free_n[read_pointer_n];
					read_pointer_n=read_pointer_n+1;
					issue_n[1].sbe.rd = lookup_table_n[decoded_entry_1_i.decoded.rd[ISA_RES_BIT-1:0]];
					end
					else 
					begin
					 // always zero
					 issue_n[1].sbe.rd = 127;
					end
					// if this instruction is a branch save free list and lookup table
					if (decoded_entry_1_i.decoded.bp.valid)
					begin
						lookup_buffer_n[history_pointer_n] = lookup_table_n;
						free_buffer_n[history_pointer_n] = free_n;
						history_pointer_n = history_pointer_n+1;
					end			
					free_num_n = free_num_n-1; 
				 end
			    if (decoded_entry_2_i.valid)
				    begin
					// rs translation
					issue_n[2].sbe = decoded_entry_2_i.decoded;        
					issue_n[2].sbe.rs1 = lookup_table_n[decoded_entry_2_i.decoded.rs1[ISA_RES_BIT-1:0]];
					issue_n[2].sbe.rs2 = lookup_table_n[decoded_entry_2_i.decoded.rs2[ISA_RES_BIT-1:0]];
					// rd translation & look up
					if (decoded_entry_2_i.decoded.rd != 31)
					begin
					  lookup_table_n[decoded_entry_2_i.decoded.rd[ISA_RES_BIT-1:0]] = free_n[read_pointer_n];
					  read_pointer_n=read_pointer_n+1;
					  issue_n[2].sbe.rd = lookup_table_n[decoded_entry_2_i.decoded.rd[ISA_RES_BIT-1:0]];
					end
					else 
					begin
					  // always zero
					  issue_n[2].sbe.rd = 127;
					end
					// if this instruction is a branch save free list and lookup table
					if (decoded_entry_2_i.decoded.bp.valid)
					begin
						lookup_buffer_n[history_pointer_n] = lookup_table_n;
						free_buffer_n[history_pointer_n] = free_n;
						history_pointer_n = history_pointer_n+1;
					end					  
					free_num_n = free_num_n-1;				  
				  end
			    if (decoded_entry_3_i.valid)
				begin
					// rs translation
					issue_n[3].sbe = decoded_entry_3_i.decoded;        
					issue_n[3].sbe.rs1 = lookup_table_n[decoded_entry_3_i.decoded.rs1[ISA_RES_BIT-1:0]];
					issue_n[3].sbe.rs2 = lookup_table_n[decoded_entry_3_i.decoded.rs2[ISA_RES_BIT-1:0]];
					// rd translation & look up
					if (decoded_entry_0_i.decoded.rd != 31)
					begin
					   lookup_table_n[decoded_entry_3_i.decoded.rd[ISA_RES_BIT-1:0]] = free_n[read_pointer_n];
					   read_pointer_n=read_pointer_n+1;
					   issue_n[3].sbe.rd = lookup_table_n[decoded_entry_3_i.decoded.rd[ISA_RES_BIT-1:0]];
					end
					else 
					begin
					   // always zero
					   issue_n[3].sbe.rd = 127;
					end
					// if this instruction is a branch save free list and lookup table
					if (decoded_entry_3_i.decoded.bp.valid)
					begin
						lookup_buffer_n[history_pointer_n] = lookup_table_n;
						free_buffer_n[history_pointer_n] = free_n;
						history_pointer_n = history_pointer_n+1;
					end					   
					free_num_n = free_num_n-1;
				end
			end
		end
    end
    
    // sequential process
    generate
    genvar i;
    for (i=0; i<NUM_OF_ISA_RES;i=i+1)
    begin
        always@(posedge clk_i)
            if (!rst_ni)
            begin
                lookup_table_q[i] <= i;
            end
            else
            begin
                lookup_table_q[i] <= lookup_table_n[i];
            end
    end
    endgenerate
    
    generate
    genvar j;
    for (j=0; j<NUM_OF_PYH_RES;j=j+1)
    begin
        always@(posedge clk_i)
            if (!rst_ni)
            begin
                free_q[j] <= 32+j;
            end
            else
            begin
                free_q[j] <= free_n[j];
            end
    end
    endgenerate
    // pipeline register
    always@(posedge clk_i)
    begin
        if (!rst_ni)
        begin
            issue_q <= '{default:0};
            free_num_q <= 128-32;
            write_pointer_q <= 96;
            read_pointer_q <= 0;
			history_pointer_q <= 0;
			free_buffer_q <= '{default:0};
			lookup_buffer_q <= '{default:0};
			history_num_q <= 0;
        end
        else 
        begin    
            issue_q <= issue_n;
            free_num_q <= free_num_n;
            write_pointer_q <= write_pointer_n;
            read_pointer_q <= read_pointer_n;
			history_pointer_q <= history_pointer_n;
			lookup_buffer_q <= lookup_buffer_n;
			free_buffer_q <= free_buffer_n;
			history_num_q <= history_num_n;
		end
    end       
endmodule

module rename_testbench;
    logic clk;
    logic rst;
	logic is_mispredict_i;
	logic [4:0] rename_index_i;
	logic resolved_branch_valid_i;
    // from ID 4 entries at on
    decoded_entry_t   decoded_entry_0_i;
    logic             decoded_entry_valid_0_i;
    logic             is_ctrl_flow_0_i;
    decoded_entry_t   decoded_entry_1_i;
    logic             decoded_entry_valid_1_i;
    logic             is_ctrl_flow_1_i;
    decoded_entry_t   decoded_entry_2_i;
    logic             decoded_entry_valid_2_i;
    logic             is_ctrl_flow_2_i;
    decoded_entry_t   decoded_entry_3_i;
    logic             decoded_entry_valid_3_i;
    logic             is_ctrl_flow_3_i;
    // to reservation station
    logic                                     issue_instr_ack_0_i;
    logic                                     issue_instr_ack_1_i;     
    logic                                     issue_instr_ack_2_i;
    logic                                     issue_instr_ack_3_i;
   
    // from reservation station
    logic                                     station_ready_i;
    
    //from commit
    logic [3:0]                               commit_valid_i;
    logic [6:0][3:0]              			  commit_register; 

	rename_stage dut(
    .clk_i(clk),
    .rst_ni(rst),
    .is_mispredict_i(is_mispredict_i),
	.rename_index_i(rename_index_i),
	.resolved_branch_valid_i(resolved_branch_valid_i),

    // from ID 4 entries at on
    .decoded_entry_0_i(decoded_entry_0_i),
    .decoded_entry_valid_0_i(decoded_entry_valid_0_i),
    .rename_instr_ack_0_o(),
    .is_ctrl_flow_0_i(is_ctrl_flow_0_i),

    .decoded_entry_1_i(decoded_entry_1_i),
    .decoded_entry_valid_1_i(decoded_entry_valid_1_i),
    .rename_instr_ack_1_o(),
    .is_ctrl_flow_1_i(is_ctrl_flow_1_i),

    .decoded_entry_2_i(decoded_entry_2_i),
    .decoded_entry_valid_2_i(decoded_entry_valid_2_i),
    .rename_instr_ack_2_o(),
    .is_ctrl_flow_2_i(is_ctrl_flow_2_i),

    .decoded_entry_3_i(decoded_entry_3_i),
    .decoded_entry_valid_3_i(decoded_entry_valid_3_i),
    .rename_instr_ack_3_o(),
    .is_ctrl_flow_3_i(is_ctrl_flow_3_i),

    // to reservation station
    .issue_entry_0_o(),       // a decoded instruction
    .issue_entry_valid_0_o(), // issue entry is valid
    .is_ctrl_flow_0_o(),      // the instruction we issue is a ctrl flow instructions
    .issue_instr_ack_0_i(issue_instr_ack_0_i),
    
    .issue_entry_1_o(),       // a decoded instruction
    .issue_entry_valid_1_o(), // issue entry is valid
    .is_ctrl_flow_1_o(),      // the instruction we issue is a ctrl flow instructions
    .issue_instr_ack_1_i(issue_instr_ack_1_i),
         
    .issue_entry_2_o(),       // a decoded instruction
    .issue_entry_valid_2_o(), // issue entry is valid
    .is_ctrl_flow_2_o(),      // the instruction we issue is a ctrl flow instructions
    .issue_instr_ack_2_i(issue_instr_ack_2_i),
    .issue_entry_3_o(),       // a decoded instruction
    .issue_entry_valid_3_o(), // issue entry is valid
    .is_ctrl_flow_3_o(),      // the instruction we issue is a ctrl flow instructions
    .issue_instr_ack_3_i(issue_instr_ack_3_i),
    
    // from reservation station
    .station_ready_i(station_ready_i),
    
    //from commit
    .commit_valid_i(commit_valid_i),
    .commit_register(commit_register)                   
);
	
	parameter CLOCK_PERIOD=1000;
     initial begin
     clk <= 0;
     forever #(CLOCK_PERIOD/2) clk <= ~clk;
     end
     integer i;
     // Set up the inputs to the design. Each line is a clock cycle.
     initial begin
     rst<=0;@(posedge clk);
	 rst<=1;@(posedge clk);
	 is_mispredict_i<=0;
	 decoded_entry_valid_0_i<=1;
	 decoded_entry_0_i.decoded.rs1<=1; 
	 decoded_entry_0_i.decoded.rs2<=1;
	 decoded_entry_0_i.decoded.rd<=5;
	 decoded_entry_0_i.valid<=1;
	 station_ready_i<=1;
	 resolved_branch_valid_i<=0;
	 decoded_entry_0_i.decoded.bp.valid<=0;
	 decoded_entry_valid_1_i<=1;
	 decoded_entry_1_i.decoded.rs1<=1; 
	 decoded_entry_1_i.decoded.rs2<=1;
	 decoded_entry_1_i.decoded.rd<=5;
	 decoded_entry_1_i.valid<=1;
	 decoded_entry_1_i.decoded.bp.valid<=1;
	 decoded_entry_valid_2_i<=1;
	 decoded_entry_2_i.decoded.rs1<=1; 
	 decoded_entry_2_i.decoded.rs2<=1;
	 decoded_entry_2_i.decoded.rd<=5;
	 decoded_entry_2_i.valid<=1;
	 decoded_entry_2_i.decoded.bp.valid<=0;
	 decoded_entry_valid_3_i<=1;
	 decoded_entry_3_i.decoded.rs1<=1; 
	 decoded_entry_3_i.decoded.rs2<=1;
	 decoded_entry_3_i.decoded.rd<=5;
	 decoded_entry_3_i.valid<=1;
	 decoded_entry_3_i.decoded.bp.valid<=1;
	 @(posedge clk);
	 commit_valid_i<= 4'b1111;
	 commit_register<= {7'b100000, 7'b100001, 7'b100010,7'b100011};
	 is_mispredict_i<=0;
	 decoded_entry_valid_0_i<=1;
	 decoded_entry_0_i.decoded.rs1<=1; 
	 decoded_entry_0_i.decoded.rs2<=1;
	 decoded_entry_0_i.decoded.rd<=5;
	 decoded_entry_0_i.valid<=1;
	 station_ready_i<=1;
	 resolved_branch_valid_i<=0;
	 decoded_entry_0_i.decoded.bp.valid<=0;
	 decoded_entry_valid_1_i<=1;
	 decoded_entry_1_i.decoded.rs1<=1; 
	 decoded_entry_1_i.decoded.rs2<=1;
	 decoded_entry_1_i.decoded.rd<=5;
	 decoded_entry_1_i.valid<=1;
	 decoded_entry_1_i.decoded.bp.valid<=0;
	 decoded_entry_valid_2_i<=1;
	 decoded_entry_2_i.decoded.rs1<=1; 
	 decoded_entry_2_i.decoded.rs2<=1;
	 decoded_entry_2_i.decoded.rd<=5;
	 decoded_entry_2_i.valid<=1;
	 decoded_entry_2_i.decoded.bp.valid<=0;
	 decoded_entry_valid_3_i<=1;
	 decoded_entry_3_i.decoded.rs1<=1; 
	 decoded_entry_3_i.decoded.rs2<=1;
	 decoded_entry_3_i.decoded.rd<=5;
	 decoded_entry_3_i.valid<=1;
	 decoded_entry_3_i.decoded.bp.valid<=0;
	 @(posedge clk);
	 commit_valid_i<= 4'b1011;
	 commit_register<= {7'b100000, 7'b100001, 7'b100010,7'b100011};
	 is_mispredict_i<=0;
	 decoded_entry_valid_0_i<=1;
	 decoded_entry_0_i.decoded.rs1<=5; 
	 decoded_entry_0_i.decoded.rs2<=5;
	 decoded_entry_0_i.decoded.rd<=5;
	 decoded_entry_0_i.valid<=1;
	 station_ready_i<=1;
	 resolved_branch_valid_i<=0;
	 decoded_entry_0_i.decoded.bp.valid<=0;
	 decoded_entry_valid_1_i<=1;
	 decoded_entry_1_i.decoded.rs1<=3; 
	 decoded_entry_1_i.decoded.rs2<=2;
	 decoded_entry_1_i.decoded.rd<=6;
	 decoded_entry_1_i.valid<=1;
	 decoded_entry_1_i.decoded.bp.valid<=0;
	 decoded_entry_valid_2_i<=1;
	 decoded_entry_2_i.decoded.rs1<=6; 
	 decoded_entry_2_i.decoded.rs2<=6;
	 decoded_entry_2_i.decoded.rd<=5;
	 decoded_entry_2_i.valid<=1;
	 decoded_entry_2_i.decoded.bp.valid<=0;
	 decoded_entry_valid_3_i<=1;
	 decoded_entry_3_i.decoded.rs1<=5; 
	 decoded_entry_3_i.decoded.rs2<=5;
	 decoded_entry_3_i.decoded.rd<=5;
	 decoded_entry_3_i.valid<=1;
	 decoded_entry_3_i.decoded.bp.valid<=0;
	 @(posedge clk);
	 repeat(40)
	 @(posedge clk);
     $stop; // End the simulation.
     end
endmodule 

