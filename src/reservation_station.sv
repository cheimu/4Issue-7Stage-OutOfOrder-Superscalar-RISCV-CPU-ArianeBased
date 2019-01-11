import ariane_pkg::*;
  
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
    input  logic                 												  flush_i,
    input  logic                 												  flush_unissued_i,
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
    
    localparam PYH_RES_NUM = 128;
    
    typedef struct packed{
        scoreboard_entry_t                      sbe;
        logic                                   issued; // 0 for unissued instruction
        logic                                   valid; // 1 for uncommited instruction  0 for commited instruction
        logic                                   is_branch;
        logic[$clog2(BUFFER_SIZE):0]            num_of_branch_block;
		logic									is_commit_barrier;
		logic[$clog2(BUFFER_SIZE):0]		    num_of_commit_block; // if there is any ld/st csr uncommited do not commit this instruction
    } inst_queue_t;
    
    
    
    fu_t               [PYH_RES_NUM-1:0]                    		rd_clobber;
    inst_queue_t       [BUFFER_SIZE-1:0]                            instruction_queue_n, instruction_queue_q;
    logic              [$clog2(BUFFER_SIZE):0]                      instruction_num_n, instruction_num_q;
	logic			   [BUFFER_SIZE*2-1:0][7:0]						free_reg_commit_buffer_n, free_reg_commit_buffer_q;
	logic			   [127:0]										free_reg_clobber;
	logic              [$clog2(BUFFER_SIZE*2)-1:0]                  free_reg_buffer_write_pointer;
    logic              [3:0][$clog2(BUFFER_SIZE)-1:0]               free_place;
    logic              [3:0][$clog2(BUFFER_SIZE)-1:0]               commit_pointer;
    logic 			   [3:0][$clog2(BUFFER_SIZE):0]	   				issue_pointer;
	logic 			   [3:0]								        issue_valid;
	
    // brach clobber process
    logic              [$clog2(BUFFER_SIZE):0]                      branch_num_n, branch_num_q;
	logic 			   [$clog2(BUFFER_SIZE):0]					    commit_barrier_num_n, commit_barrier_num_q;
    logic              [NR_WB_PORTS-1:0]                            issue_instr_valid_n, issue_instr_valid_q;  
    logic [3:0]                                                     branch_ready_incoming;

	// to read operands
    logic [BUFFER_SIZE+NR_WB_PORTS-1:0][6:0]                        rs1_addr;
    logic [BUFFER_SIZE+NR_WB_PORTS-1:0][63:0]                       rs1_data;
    logic [BUFFER_SIZE+NR_WB_PORTS-1:0]                             rs1_forward_valid;
	
    logic [BUFFER_SIZE+NR_WB_PORTS-1:0][6:0]                        rs2_addr;
    logic [BUFFER_SIZE+NR_WB_PORTS-1:0][63:0]                       rs2_data;
    logic [BUFFER_SIZE+NR_WB_PORTS-1:0]                             rs2_forward_valid;  
    logic [BUFFER_SIZE+NR_WB_PORTS-1:0]                             instr_status;

	logic 															station_ready;
    // output valid instruction to issue also depends on input
    assign issue_instr_valid_o = issue_valid;
        
    assign station_ready = (instruction_num_q + valid_instruction_num_i) <= BUFFER_SIZE && valid_instruction_num_i > 0; 
    assign issue_instr_ack_o = station_ready && issue_entry_valid_i && !(is_mis_predict_i && resolved_branch_valid_i);

    // commit port assignments
    assign commit_instr_o[0] = instruction_queue_q[commit_pointer[0]].sbe;
    assign commit_instr_o[1] = instruction_queue_q[commit_pointer[1]].sbe;
    assign commit_instr_o[2] = instruction_queue_q[commit_pointer[2]].sbe;
    assign commit_instr_o[3] = instruction_queue_q[commit_pointer[3]].sbe;
	
	// to read operands
	assign rs1_data_o[0] = rs1_data[issue_pointer[0]]; 
    assign rs1_forward_valid_o[0] = rs1_forward_valid[issue_pointer[0]];
	assign rs2_data_o[0] = rs2_data[issue_pointer[0]]; 
    assign rs2_forward_valid_o[0] = rs2_forward_valid[issue_pointer[0]];
	
	assign rs1_data_o[1] = rs1_data[issue_pointer[1]]; 
    assign rs1_forward_valid_o[1] = rs1_forward_valid[issue_pointer[1]];
	assign rs2_data_o[1] = rs2_data[issue_pointer[1]]; 
    assign rs2_forward_valid_o[1] = rs2_forward_valid[issue_pointer[1]];
	
	assign rs1_data_o[2] = rs1_data[issue_pointer[2]]; 
    assign rs1_forward_valid_o[2] = rs1_forward_valid[issue_pointer[2]];
	assign rs2_data_o[2] = rs2_data[issue_pointer[2]];	
    assign rs2_forward_valid_o[2] = rs2_forward_valid[issue_pointer[2]];
	
	assign rs1_data_o[3] = rs1_data[issue_pointer[3]]; 
    assign rs1_forward_valid_o[3] = rs1_forward_valid[issue_pointer[3]];
	assign rs2_data_o[3] = rs2_data[issue_pointer[3]]; 
    assign rs2_forward_valid_o[3] = rs2_forward_valid[issue_pointer[3]];
	
	// rs1 & rs2 assignments
    always@(*)
    begin
        for (int unsigned j=0;j<BUFFER_SIZE+NR_WB_PORTS;j++)
        begin
            if (j<BUFFER_SIZE)
            begin
                rs1_addr[j] = instruction_queue_q[j].sbe.rs1;
                rs2_addr[j] = instruction_queue_q[j].sbe.rs2;
            end
            else
            begin
                rs1_addr[j] = issue_entry_i[j - BUFFER_SIZE].rs1;
                rs2_addr[j] = issue_entry_i[j - BUFFER_SIZE].rs2;
            end
        end
    end
    
	// free reg buffer pointer compute
	always@(*)
	begin
		free_reg_buffer_write_pointer = '0;
		for (int unsigned j=0;j<BUFFER_SIZE*2;j++)
			if (!free_reg_commit_buffer_q[j][7])
				free_reg_buffer_write_pointer = j[$clog2(BUFFER_SIZE*2)-1:0];
	end
	
	// write instructions and commit instructions will all happens here
    always@(*) begin
		// default assignments
        automatic logic [1:0] slot;
		automatic logic [3:0][$clog2(BUFFER_SIZE)-1:0] incoming_place;
		automatic logic [$clog2(BUFFER_SIZE):0]        commit_barrier_num;
		automatic logic [2:0]						   commit_reg_cnt;
		commit_reg_cnt = 3'b0;
        slot = 0;
        branch_num_n = branch_num_q;
        instruction_queue_n = instruction_queue_q;
        instruction_num_n = instruction_num_q;
		branch_ready_incoming = 4'b0000;
		commit_barrier_num = commit_barrier_num_q;
		incoming_place = '{default:0};
		free_reg_commit_buffer_n = free_reg_commit_buffer_q;
		commit_register_valid_o = '0;
		commit_register_o = '{default:0};
		issue_instr_o = '{default:0};

        // branch commit must happen in advance  
        if (resolved_branch_valid_i)
        begin
            if (is_mis_predict_i)
                branch_num_n = 0;
            else if (!is_mis_predict_i && branch_num_n !=0)
                branch_num_n = branch_num_n - 1;
         
            for (int unsigned j=0;j<BUFFER_SIZE;j++)
			begin
				if (!is_mis_predict_i)
				begin
					// decrement branch counter if we have a right prediction
					if (instruction_queue_q[j].valid && instruction_queue_q[j].num_of_branch_block > 0)
						instruction_queue_n[j].num_of_branch_block = (instruction_queue_n[j].num_of_branch_block) - 1;  
				end
				else
				begin
					// invalidate this entry if this entry comes after mis-prediction
					if (instruction_queue_q[j].valid && instruction_queue_q[j].num_of_branch_block > 0)
					begin
						instruction_queue_n[j].valid = 1'b0;
						instruction_queue_n[j].sbe.valid = 1'b0;
						instruction_queue_n[j].issued = 1'b0;						
						instruction_queue_n[j].num_of_branch_block = 'b0;
						instruction_num_n = (instruction_num_n == '0) ? '0 :instruction_num_n - 1;						
					end
				end
			end
		end
        
        // put instructions into instruction buffer
        if (issue_instr_ack_o)
        begin
            for (int unsigned j=0;j<NR_WB_PORTS;j++)
            begin
                // update
                if (issue_entry_i[j].is_included)
                begin
                    instruction_queue_n[free_place[slot]].sbe = issue_entry_i[j];
                    instruction_queue_n[free_place[slot]].sbe.valid = 1'b0;
                    instruction_queue_n[free_place[slot]].sbe.trans_id = free_place[slot];
					incoming_place[j] = free_place[slot];
                    instruction_queue_n[free_place[slot]].issued = 1'b0;
                    instruction_queue_n[free_place[slot]].valid = 1'b1;
                    instruction_queue_n[free_place[slot]].is_branch = is_ctrl_flow_i[j];
                    instruction_queue_n[free_place[slot]].num_of_branch_block = branch_num_n;
                    instruction_queue_n[free_place[slot]].num_of_commit_block = commit_barrier_num;
                    instruction_queue_n[free_place[slot]].is_commit_barrier = 1'b0;
					branch_ready_incoming[j] = branch_num_n == 0;
                    
					if (is_ctrl_flow_i[j]) 
                        branch_num_n = branch_num_n + 1;    
                    // ld/st/csr 
					if (issue_entry_i[j].fu == LOAD || issue_entry_i[j].fu == STORE || issue_entry_i[j].fu == CSR)
					begin
						commit_barrier_num = commit_barrier_num + 1;
						instruction_queue_n[free_place[slot]].is_commit_barrier = 1'b1;
					end
					slot = slot+1;
					instruction_num_n = instruction_num_n + 1;
				end
			end
		end
       
		// loop through all issue pointers
		for (int unsigned j=0; j<NR_WB_PORTS;j++)
		begin
			if (issue_valid[j])
			begin
				// in reservation station
				if (issue_pointer[j] < BUFFER_SIZE)
				begin
					instruction_queue_n[issue_pointer[j]].issued =1'b1;
					issue_instr_o[j] = instruction_queue_q[issue_pointer[j]].sbe;
				end
				else
				begin
					instruction_queue_n[incoming_place[issue_pointer[j] - BUFFER_SIZE]].issued = 1'b1;
					issue_instr_o[j] = issue_entry_i[issue_pointer[j] - BUFFER_SIZE];
					issue_instr_o[j].trans_id = incoming_place[issue_pointer[j] - BUFFER_SIZE];
				end
			end
		end
	    
        // write back
        for (int unsigned j=0;j<NR_FU;j++)
        begin
            if (wb_valid_i[j] && instruction_queue_q[trans_id_i[j]].issued && instruction_queue_q[trans_id_i[j]].valid)
            begin
                instruction_queue_n[trans_id_i[j]].sbe.valid = 1'b1;
                instruction_queue_n[trans_id_i[j]].sbe.result = wdata_i[j];
                // write exception back if valid
                if (ex_i[j].valid)
                    instruction_queue_n[trans_id_i[j]].sbe.ex = ex_i[j];
            end 
        end
        
        // commit
        for (int unsigned j=0;j<NR_WB_PORTS;j++)
        begin
            if (commit_ack_i[j])
            begin
                instruction_num_n = (instruction_num_n == '0) ? '0 : instruction_num_n - 1;
                // finish issuing
                instruction_queue_n[commit_pointer[j]].issued = 1'b0;
                // invalidate write back data
                instruction_queue_n[commit_pointer[j]].sbe.valid = 1'b0;
                // a new empty space
                instruction_queue_n[commit_pointer[j]].valid = 1'b0;
				
				// commit barrier removal
				if (instruction_queue_q[commit_pointer[j]].is_commit_barrier)
					commit_barrier_num = commit_barrier_num - 1;
				for (int unsigned k=0; k<BUFFER_SIZE;k++)
				begin
					if (instruction_queue_q[commit_pointer[j]].is_commit_barrier && instruction_queue_n[k].num_of_commit_block != 0)
						instruction_queue_n[k].num_of_commit_block = instruction_queue_n[k].num_of_commit_block - 1;
				end
				
				// free register 
				if (!free_reg_clobber[instruction_queue_q[commit_pointer[j]].sbe.freed_register] && instruction_queue_q[commit_pointer[j]].sbe.freed_register != 127)
				begin
					commit_register_o[commit_reg_cnt[1:0]] = instruction_queue_q[commit_pointer[j]].sbe.freed_register;
					commit_register_valid_o[commit_reg_cnt[1:0]] = 1'b1;
					commit_reg_cnt = commit_reg_cnt + 1;
				end
				else
				begin
					free_reg_commit_buffer_n[free_reg_buffer_write_pointer] = {1'b1, instruction_queue_q[commit_pointer[j]].sbe.freed_register};
				end
            end
        end

		// free register buffer commit
		for (int unsigned j=0;j<BUFFER_SIZE*2;j++)
		begin
			if (!free_reg_clobber[free_reg_commit_buffer_q[j][6:0]] && free_reg_commit_buffer_q[j][7] && commit_reg_cnt < 3'b100 && free_reg_commit_buffer_q[j][6:0] != 127)
			begin
				commit_register_o[commit_reg_cnt[1:0]] = free_reg_commit_buffer_q[j][6:0];
				commit_register_valid_o[commit_reg_cnt[1:0]] = 1'b1;
				free_reg_commit_buffer_n[j][7] = 1'b0;
				commit_reg_cnt = commit_reg_cnt + 1;
			end
		end
		
		for (int unsigned j = 0; j<BUFFER_SIZE-1;j++)
		begin
			if (flush_i)
			begin
				instruction_queue_n[j] = '0;
				instruction_num_n = '0;
				branch_num_n = '0;
				commit_barrier_num_n = '0;
			end
			else if (flush_unissued_i && ~instruction_queue_q[j].issued)
			begin
				if (commit_barrier_num > 0 && instruction_queue_q[j].is_commit_barrier)
					commit_barrier_num = commit_barrier_num - 1;
				if (branch_num_n > 0 && instruction_queue_q[j].sbe.fu == CTRL_FLOW)
					branch_num_n = branch_num_n - 1;
				instruction_queue_n[j] = '0;
                instruction_num_n = (instruction_num_n == '0) ? '0 : instruction_num_n - 1;
			end
		end
		commit_barrier_num_n = commit_barrier_num;
    end
	
	// find valid instruction to commit
	always@(*)
	begin
	   automatic logic[2:0] commit_cnt;
	   commit_cnt = 0;
	   commit_pointer = '{default:0};
	   commit_valid_o = 4'b0;
	   
	   for (int unsigned j=0; j<BUFFER_SIZE;j=j+1)
	   begin
	       // we define a valid commit instruction as a
	       // valid issued instruction whose result has already been written back and whose commit barrier is zero 
	       if (instruction_queue_q[j].valid && instruction_queue_q[j].issued && instruction_queue_q[j].sbe.valid && commit_cnt<3'b100 
			&& instruction_queue_q[j].num_of_commit_block == '0)
	       begin
	           commit_pointer[commit_cnt[1:0]] = j[$clog2(BUFFER_SIZE)-1:0];
	           commit_valid_o[commit_cnt[1:0]] = 1'b1;
	           commit_cnt=commit_cnt+1;
	       end
	   end
	end
	

    // operands availability check
    always@(*)
    begin
        automatic logic [BUFFER_SIZE+NR_WB_PORTS-1:0] r1_valid;
        automatic logic [BUFFER_SIZE+NR_WB_PORTS-1:0] r2_valid;
		r1_valid = 20'b0;
        r2_valid = 20'b0;
        instr_status = 20'b0;
        for (int unsigned j = 0; j<BUFFER_SIZE+NR_WB_PORTS;j++)
        begin
            if (j<BUFFER_SIZE)
            begin
                if (instruction_queue_q[j].valid && !instruction_queue_q[j].issued)
                begin
                    if (rd_clobber[instruction_queue_q[j].sbe.rs1] == NONE)
                        r1_valid[j] = 1'b1;
                    if (rd_clobber[instruction_queue_q[j].sbe.rs2] == NONE)
                        r2_valid[j] = 1'b1;
        
					// r1 use zimm
					if (instruction_queue_q[j].sbe.use_zimm)
						r1_valid[j] = 1'b1;
						
					// r2 use imm
					if (instruction_queue_q[j].sbe.use_imm)
						r2_valid[j] = 1'b1;
					
                    if (~instruction_queue_q[j].sbe.use_zimm && rd_clobber[instruction_queue_q[j].sbe.rs1] != NONE)
                    begin
                    // check if the clobbering instruction is not a CSR instruction, CSR instructions can only
                    // be fetched through the register file since they can't be forwarded
                    // the operand is available, forward it
                        if (rs1_forward_valid[j] && rd_clobber[instruction_queue_q[j].sbe.rs1] != CSR)
							r1_valid[j] = 1'b1;
					end
                    
                    if (~instruction_queue_q[j].sbe.use_imm && rd_clobber[instruction_queue_q[j].sbe.rs2] != NONE) 
                    begin
                        // the operand is available, forward it
                        if (rs2_forward_valid[j] && rd_clobber[instruction_queue_q[j].sbe.rs2] != CSR)
                            r2_valid[j] = 1'b1;
                    end
                end 
            end
            else
            begin
                if (issue_entry_valid_i && issue_entry_i[j-BUFFER_SIZE].is_included)
                begin
                    if (rd_clobber[issue_entry_i[j-BUFFER_SIZE].rs1] == NONE)
                        r1_valid[j] = 1'b1;
						
                    if (rd_clobber[issue_entry_i[j-BUFFER_SIZE].rs2] == NONE)
                        r2_valid[j] = 1'b1;
					
					// r1 use zimm
					if (issue_entry_i[j-BUFFER_SIZE].use_zimm)
						r1_valid[j] = 1'b1;
					
					
					// r2 use imm
					if (issue_entry_i[j-BUFFER_SIZE].use_imm)
						r2_valid[j] = 1'b1;
					
					// r1 forwarding
                    if (~issue_entry_i[j-BUFFER_SIZE].use_zimm && rd_clobber[issue_entry_i[j-BUFFER_SIZE].rs1] != NONE)
                    begin
                    // check if the clobbering instruction is not a CSR instruction, CSR instructions can only
                    // be fetched through the register file since they can't be forwarded
                    // the operand is available, forward it
                        if (rs1_forward_valid[j] && rd_clobber[issue_entry_i[j-BUFFER_SIZE].rs1] != CSR)
                            r1_valid[j] = 1'b1;
                    end
                    
					// r2 forwarding
                    if (~issue_entry_i[j-BUFFER_SIZE].use_imm && rd_clobber[issue_entry_i[j-BUFFER_SIZE].rs2] != NONE) 
                    begin
                        // the operand is available, forward it
                        if (rs2_forward_valid[j] && rd_clobber[issue_entry_i[j-BUFFER_SIZE].rs2] != CSR)
                            r2_valid[j] = 1'b1;
					end 
                end                
            end
            instr_status[j] = r1_valid[j] & r2_valid[j];
        end
    end

	// find four instruction to issue in buffer
	always@(*)
	begin
		automatic logic [2:0] issue_slot;
		automatic logic [1:0] alu, lsu, cr, branch, mul;
		lsu = fu_status_i[0];
		alu = fu_status_i[1];
		branch = fu_status_i[2];
		mul = fu_status_i[3];
		cr = fu_status_i[4];
		issue_slot = 3'b0;
		issue_pointer = '{default:0};
		issue_valid = 4'b0000;
		for (int unsigned j=0;j < BUFFER_SIZE+NR_WB_PORTS;j++)
		begin
			if (j < BUFFER_SIZE)
			begin
				// no dependencies & function unit is ready
				if (instruction_queue_q[j].valid && !instruction_queue_q[j].issued && instr_status[j] && instruction_queue_q[j].num_of_branch_block == '0)
				begin
					unique case (instruction_queue_q[j].sbe.fu)
						NONE:
						begin
							if (issue_slot <= 3'b011)
							begin
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						ALU:
						begin
							if (alu != 0 && issue_slot <= 3'b011)
							begin
								alu--;
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						CTRL_FLOW:
						begin
							if (branch != 0 && issue_slot <= 3'b011)
							begin
								branch--;
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end					
						MULT:
						begin
							if (mul != 0 && issue_slot <= 3'b011)
							begin
								mul--;
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						LOAD, STORE:
						begin
							if (lsu != 0 && issue_slot <= 3'b011)
							begin
								lsu--;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						CSR:
						begin
							if (cr != 0 && issue_slot <= 3'b011)
							begin
								cr--;
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						default:
						begin
							if (issue_slot <= 3'b011)
							begin
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
					endcase
				end
			end
			else 
			begin
				// no dependencies & function unit is ready
				if (issue_entry_i[j-BUFFER_SIZE].is_included && instr_status[j] && branch_ready_incoming[j-BUFFER_SIZE] && issue_entry_valid_i)
				begin
					unique case (issue_entry_i[j-BUFFER_SIZE].fu)
						NONE:
						begin
							if (issue_slot <= 3'b011)
							begin
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						ALU:
						begin
							if (alu != 0 && issue_slot <= 3'b011)
							begin
								alu--;
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						CTRL_FLOW:
						begin
							if (branch != 0 && issue_slot <= 3'b011)
							begin
								branch--;
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end					
						MULT:
						begin
							if (mul != 0 && issue_slot <= 3'b011)
							begin
								mul--;
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						LOAD, STORE:
						begin
							if (lsu != 0 && issue_slot <= 3'b011)
							begin
								lsu--;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						CSR:
						begin
							if (cr != 0 && issue_slot <= 3'b011)
							begin
								cr--;
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
						default:
						begin
							if (issue_slot <= 3'b011)
							begin
								issue_valid[issue_slot[1:0]] = 1'b1;
								issue_pointer[issue_slot[1:0]] = j[$clog2(BUFFER_SIZE):0];
								issue_slot = issue_slot + 1;
							end
						end
					endcase
				end
			end
		end
	end
	
	// forwarding
	always@(*)
	begin
	   rs1_data = '{default:64'b0};
	   rs2_data = '{default:64'b0};
	   rs1_forward_valid = 20'b0;
	   rs2_forward_valid = 20'b0;
	
	    // forwarding
        for (int unsigned j = 0; j < BUFFER_SIZE+NR_WB_PORTS; j++) 
        begin
            for (int unsigned k=0; k<BUFFER_SIZE;k++)
            begin        
                // only consider this entry if it is valid
                if (instruction_queue_q[k].issued && instruction_queue_q[k].valid && instruction_queue_q[k].sbe.valid) 
                begin
					// look at the appropriate fields and look whether there was an
					// instruction that wrote the rd field before, first for RS1 and then for RS2
					// rs1
					if (instruction_queue_q[k].sbe.rd == rs1_addr[j]) 
					begin
					   rs1_data[j]       = instruction_queue_q[k].sbe.result;
					   rs1_forward_valid[j]   = 1'b1;
					end

					// rs2
					if (instruction_queue_q[k].sbe.rd == rs2_addr[j])
					begin
					   rs2_data[j]       = instruction_queue_q[k].sbe.result;
					   rs2_forward_valid[j]   = 1'b1;
					end
                end
            end
            // forwarding
            for (int unsigned k=0;k<NR_FU;k++)
            begin
                if (instruction_queue_q[trans_id_i[k]].sbe.rd == rs1_addr[j] && wb_valid_i[k] && ~ex_i[k].valid) 
				begin
                    rs1_data[j] = wdata_i[k];
                    rs1_forward_valid[j] = wb_valid_i[k];
                    //break;
                end
                if (instruction_queue_q[trans_id_i[k]].sbe.rd == rs2_addr[j] && wb_valid_i[k] && ~ex_i[k].valid) 
				begin
                    rs2_data[j] = wdata_i[k];
                    rs2_forward_valid[j] = wb_valid_i[k];
                    //break;
                end
            end     
        end	
		
        // do not read 128th register
        for (int unsigned j=0;j<BUFFER_SIZE+NR_WB_PORTS;j++)
        begin
            if (rs1_addr[j] == 127)
                rs1_forward_valid[j]=1'b0;
            if (rs2_addr[j] == 127)
                rs2_forward_valid[j]=1'b0;
        end
	end
	
	// find free slots in instruction  buffers
	always@(*)
	begin
		automatic logic [2:0]	which;
	   free_place = '{default:0};
	   which = 0;
	   if (issue_instr_ack_o)
	   begin
           for(int unsigned j=0; j<BUFFER_SIZE;j++)
           begin
               if (!instruction_queue_q[j].valid && which < 3'b100)
               begin
                   free_place[which] = j[$clog2(BUFFER_SIZE)-1:0];
                   which = which+1;
               end
           end
        end
	end
	
	// rd clobber process
    always@(*) 
    begin
        rd_clobber = '{default: NONE};
        // check for all valid entries and set the clobber register accordingly
        for (int unsigned j = 0; j < BUFFER_SIZE+NR_WB_PORTS; j++)
		begin
			if (j<BUFFER_SIZE)
			begin
				if (instruction_queue_q[j].valid)
				begin
					// output the functional unit which is going to clobber this register
					rd_clobber[instruction_queue_q[j].sbe.rd] = instruction_queue_q[j].sbe.fu;
				end
			end
			else
			begin
				if (issue_entry_i[j-BUFFER_SIZE].is_included)
				begin
					// output the functional unit which is going to clobber this register
					rd_clobber[issue_entry_i[j-BUFFER_SIZE].rd] = issue_entry_i[j-BUFFER_SIZE].fu;
				end				
			end
        end
        // the 127th register is always free
        rd_clobber[127] = NONE;
    end   

	// free reg commit clobber process
	always@(*)
	begin
		free_reg_clobber = '0;
		for (int unsigned j=0;j<BUFFER_SIZE;j++)
		begin
			if (instruction_queue_q[j].valid && !instruction_queue_q[j].issued)
			begin
				if (!instruction_queue_q[j].sbe.use_zimm)
					free_reg_clobber[instruction_queue_q[j].sbe.rs1] = 1'b1;
				if (!instruction_queue_q[j].sbe.use_imm)
					free_reg_clobber[instruction_queue_q[j].sbe.rs2] = 1'b1;
			end
		end
	end
	
	// sequential process
    always@(posedge clk_i)
    begin
        if  (!rst_ni)
        begin
			commit_barrier_num_q <= '0;
            branch_num_q <= 0;
			instruction_queue_q <= '{default:0};
            instruction_num_q <= '{default:0};
			free_reg_commit_buffer_q <= '{default:0};
        end
        else
        begin
			commit_barrier_num_q <= commit_barrier_num_n;
            branch_num_q <= branch_num_n;
            instruction_queue_q <= instruction_queue_n;
            instruction_num_q <= instruction_num_n;
			free_reg_commit_buffer_q <= free_reg_commit_buffer_n;
        end
    end
endmodule