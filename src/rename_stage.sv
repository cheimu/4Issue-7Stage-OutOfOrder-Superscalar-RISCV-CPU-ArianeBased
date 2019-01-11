import ariane_pkg::*;
 
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
    logic [31:0][PYH_RES_BIT:0]						     free_nr_buffer_n, free_nr_buffer_q;
    logic [31:0][PYH_RES_BIT-1:0]						 read_ptr_buffer_n, read_ptr_buffer_q;
    logic [31:0][PYH_RES_BIT-1:0]						 wr_ptr_buffer_q, wr_ptr_buffer_n;
    logic [PYH_RES_BIT-1:0]                        		 read_pointer_n, read_pointer_q;
    logic [PYH_RES_BIT-1:0]                        		 write_pointer_n, write_pointer_q;
    logic [2:0]											 valid_branch;
    logic [2:0]                                          valid_commit;
	
    assign rename_instr_ack_0_o = (free_num_q +valid_commit>=4) && decoded_entry_valid_0_i && (valid_branch+history_num_q <= 32)&& (issue_instr_ack_0_i || !issue_q[0].is_valid);
    assign rename_instr_ack_1_o = (free_num_q +valid_commit>=4) && decoded_entry_valid_1_i && (valid_branch+history_num_q <= 32)&& (issue_instr_ack_0_i || !issue_q[1].is_valid);
    assign rename_instr_ack_2_o = (free_num_q +valid_commit>=4) && decoded_entry_valid_2_i && (valid_branch+history_num_q <= 32)&& (issue_instr_ack_0_i || !issue_q[2].is_valid);
    assign rename_instr_ack_3_o = (free_num_q +valid_commit>=4) && decoded_entry_valid_3_i && (valid_branch+history_num_q <= 32)&& (issue_instr_ack_0_i || !issue_q[3].is_valid);
    
	always@(*)
	begin
		valid_branch = 0;
		valid_commit = 0;
		if (decoded_entry_0_i.decoded.bp.valid)
			valid_branch=valid_branch+1;
		if (decoded_entry_1_i.decoded.bp.valid)
			valid_branch=valid_branch+1;
		if (decoded_entry_2_i.decoded.bp.valid)
			valid_branch=valid_branch+1;
		if (decoded_entry_3_i.decoded.bp.valid)
			valid_branch=valid_branch+1;
	    if (commit_valid_i[0])
	       valid_commit = valid_commit+1;
	    if (commit_valid_i[1])
            valid_commit = valid_commit+1;
	    if (commit_valid_i[2])
            valid_commit = valid_commit+1;
	    if (commit_valid_i[3])
            valid_commit = valid_commit+1;
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
		valid_instruction_o=0;
		issue_n = issue_q;
		wr_ptr_buffer_n = wr_ptr_buffer_q;
		read_ptr_buffer_n = read_ptr_buffer_q;
		free_nr_buffer_n = free_nr_buffer_q;
		
		if (rename_instr_ack_0_o)
		begin
			issue_n[0].is_valid = decoded_entry_valid_0_i;
			issue_n[0].is_control = is_ctrl_flow_0_i;
			issue_n[0].sbe = decoded_entry_0_i.decoded;
			issue_n[1].is_valid = decoded_entry_valid_1_i;
			issue_n[1].is_control = is_ctrl_flow_1_i;
			issue_n[1].sbe = decoded_entry_0_i.decoded;
			issue_n[2].is_valid = decoded_entry_valid_2_i;
			issue_n[2].is_control = is_ctrl_flow_2_i;
			issue_n[2].sbe = decoded_entry_0_i.decoded;
			issue_n[3].is_valid = decoded_entry_valid_3_i;
			issue_n[3].is_control = is_ctrl_flow_3_i;
			issue_n[3].sbe = decoded_entry_0_i.decoded;
			issue_n[0].sbe.is_included = decoded_entry_0_i.valid;
			issue_n[1].sbe.is_included = decoded_entry_1_i.valid;
			issue_n[2].sbe.is_included = decoded_entry_2_i.valid;
			issue_n[3].sbe.is_included = decoded_entry_3_i.valid;
		end
        
        // mis-prediction handlings
		if (resolved_branch_valid_i && is_mispredict_i)
		begin
			// assign free_n and lookup_table_n values in buffer
			// and flush history table
			read_pointer_n = read_ptr_buffer_q[rename_index_i];
			write_pointer_n = wr_ptr_buffer_q[rename_index_i];
			free_num_n = free_nr_buffer_q[rename_index_i];
			lookup_table_n = lookup_buffer_q[rename_index_i];
			free_n = free_buffer_q[rename_index_i];
			history_num_n = 0;
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
        
		
		// TODO:: pass valid bit forward
		// resolved branch is correct or resolved branch is not valid
		if ((resolved_branch_valid_i && !is_mispredict_i) || !resolved_branch_valid_i)
		begin
			// translation
			if (rename_instr_ack_0_o)
			begin
				if (decoded_entry_0_i.decoded.is_included)
				begin
					// rs translation
					issue_n[0].sbe = decoded_entry_0_i.decoded;        
					issue_n[0].sbe.rs1 = lookup_table_n[decoded_entry_0_i.decoded.rs1[ISA_RES_BIT-1:0]];
					issue_n[0].sbe.rs2 = lookup_table_n[decoded_entry_0_i.decoded.rs2[ISA_RES_BIT-1:0]];
					// rd translation & look up
					if (decoded_entry_0_i.decoded.rd != 0)
					begin
						issue_n[0].sbe.freed_register = lookup_table_n[decoded_entry_0_i.decoded.rd[ISA_RES_BIT-1:0]];
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
					if (decoded_entry_0_i.decoded.fu == CTRL_FLOW)
					begin
						issue_n[0].sbe.rename_index = history_pointer_n;
						lookup_buffer_n[history_pointer_n] = lookup_table_n;
						free_buffer_n[history_pointer_n] = free_n;
						wr_ptr_buffer_n[history_pointer_n] = write_pointer_n;
						read_ptr_buffer_n[history_pointer_n] = read_pointer_n;
						free_nr_buffer_n[history_pointer_n] = free_num_n;
						history_pointer_n = history_pointer_n+1;
					end
					free_num_n = free_num_n-1;
				end
				
			    if (decoded_entry_1_i.decoded.is_included)
				begin
					// rs translation
					issue_n[1].sbe = decoded_entry_1_i.decoded;        
					issue_n[1].sbe.rs1 = lookup_table_n[decoded_entry_1_i.decoded.rs1[ISA_RES_BIT-1:0]];
					issue_n[1].sbe.rs2 = lookup_table_n[decoded_entry_1_i.decoded.rs2[ISA_RES_BIT-1:0]];
					// rd translation & look up
					if (decoded_entry_1_i.decoded.rd != 0)
					begin
						issue_n[1].sbe.freed_register = lookup_table_n[decoded_entry_1_i.decoded.rd[ISA_RES_BIT-1:0]];
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
					if (decoded_entry_1_i.decoded.fu == CTRL_FLOW)
					begin
						issue_n[1].sbe.rename_index = history_pointer_n;
						lookup_buffer_n[history_pointer_n] = lookup_table_n;
						free_buffer_n[history_pointer_n] = free_n;
						wr_ptr_buffer_n[history_pointer_n] = write_pointer_n;
						read_ptr_buffer_n[history_pointer_n] = read_pointer_n;
						free_nr_buffer_n[history_pointer_n] = free_num_n;
						history_pointer_n = history_pointer_n+1;
					end			
					free_num_n = free_num_n-1; 
				 end
			    if (decoded_entry_2_i.decoded.is_included)
				    begin
					// rs translation
					issue_n[2].sbe = decoded_entry_2_i.decoded;        
					issue_n[2].sbe.rs1 = lookup_table_n[decoded_entry_2_i.decoded.rs1[ISA_RES_BIT-1:0]];
					issue_n[2].sbe.rs2 = lookup_table_n[decoded_entry_2_i.decoded.rs2[ISA_RES_BIT-1:0]];
					// rd translation & look up
					if (decoded_entry_2_i.decoded.rd != 0)
					begin
						issue_n[2].sbe.freed_register = lookup_table_n[decoded_entry_2_i.decoded.rd[ISA_RES_BIT-1:0]];
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
					if (decoded_entry_2_i.decoded.fu == CTRL_FLOW)
					begin
						issue_n[2].sbe.rename_index = history_pointer_n;
						lookup_buffer_n[history_pointer_n] = lookup_table_n;
						wr_ptr_buffer_n[history_pointer_n] = write_pointer_n;
						read_ptr_buffer_n[history_pointer_n] = read_pointer_n;
						free_nr_buffer_n[history_pointer_n] = free_num_n;						
						free_buffer_n[history_pointer_n] = free_n;
						history_pointer_n = history_pointer_n+1;
					end					  
					free_num_n = free_num_n-1;				  
				  end
			    if (decoded_entry_3_i.decoded.is_included)
				begin
					// rs translation
					issue_n[3].sbe = decoded_entry_3_i.decoded;        
					issue_n[3].sbe.rs1 = lookup_table_n[decoded_entry_3_i.decoded.rs1[ISA_RES_BIT-1:0]];
					issue_n[3].sbe.rs2 = lookup_table_n[decoded_entry_3_i.decoded.rs2[ISA_RES_BIT-1:0]];
					// rd translation & look up
					if (decoded_entry_3_i.decoded.rd != 0)
					begin
						issue_n[3].sbe.freed_register = lookup_table_n[decoded_entry_3_i.decoded.rd[ISA_RES_BIT-1:0]];
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
					if (decoded_entry_3_i.decoded.fu == CTRL_FLOW)
					begin
						issue_n[3].sbe.rename_index = history_pointer_n;
						lookup_buffer_n[history_pointer_n] = lookup_table_n;
						free_buffer_n[history_pointer_n] = free_n;
						wr_ptr_buffer_n[history_pointer_n] = write_pointer_n;
						read_ptr_buffer_n[history_pointer_n] = read_pointer_n;
						free_nr_buffer_n[history_pointer_n] = free_num_n;
						history_pointer_n = history_pointer_n+1;
					end					   
					free_num_n = free_num_n-1;
				end
			end
		end
    end
    
    always@(*)
    begin
    	valid_instruction_o = 3'b0;
    	if (decoded_entry_valid_0_i && decoded_entry_0_i.decoded.is_included)
    		valid_instruction_o = valid_instruction_o + 3'b1;
    	if (decoded_entry_valid_1_i && decoded_entry_1_i.decoded.is_included)
    		valid_instruction_o = valid_instruction_o + 3'b1;
    	if (decoded_entry_valid_2_i && decoded_entry_2_i.decoded.is_included)
    		valid_instruction_o = valid_instruction_o + 3'b1;
    	if (decoded_entry_valid_3_i && decoded_entry_3_i.decoded.is_included)
    		valid_instruction_o = valid_instruction_o + 3'b1;
    end


    // sequential process
    generate
    genvar i;
    for (i=0; i<NUM_OF_ISA_RES;i=i+1)
    begin
        always@(posedge clk_i)
            if (!rst_ni)
            begin
				if (i != 0)
					lookup_table_q[i] <= i - 1;
				else
					lookup_table_q[i] <= 127;
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
				free_q[j] <= j + 31;
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
			read_ptr_buffer_q <= '{default:0};
			wr_ptr_buffer_q <= '{default:0};
			free_nr_buffer_q <= '{default:0};
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
			read_ptr_buffer_q <= read_ptr_buffer_n;
			wr_ptr_buffer_q <= wr_ptr_buffer_n;
			free_nr_buffer_q <= free_num_n;
		end
    end       
endmodule