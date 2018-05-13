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
    
    input logic flush_i,

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
    input logic [PYH_RES_BIT-1:0][3:0]              commit_register                   
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
    
    
    // first bit is valid bit
    logic [PYH_RES_BIT-1:0][NUM_OF_ISA_RES-1:0]    lookup_table_n, lookup_table_q;
    logic [PYH_RES_BIT-1:0][NUM_OF_PYH_RES-1:0]    free_n, free_q;
    logic [PYH_RES_BIT:0]                          free_num_n, free_num_q;
    logic [PYH_RES_BIT-1:0]                        read_pointer_n, read_pointer_q;
    logic [PYH_RES_BIT-1:0]                        write_pointer_n, write_pointer_q;
    
    assign rename_instr_ack_0_o = (free_num_q >= 4 || commit_valid_i == 4'b1111) && decoded_entry_valid_0_i && station_ready_i;
    assign rename_instr_ack_1_o = (free_num_q >= 4 || commit_valid_i == 4'b1111) && decoded_entry_valid_1_i && station_ready_i;
    assign rename_instr_ack_2_o = (free_num_q >= 4 || commit_valid_i == 4'b1111) && decoded_entry_valid_2_i && station_ready_i;
    assign rename_instr_ack_3_o = (free_num_q >= 4 || commit_valid_i == 4'b1111) && decoded_entry_valid_3_i && station_ready_i;
    
    always@(*)
    begin
        // default assignment
        logic free_num;
        free_num  = free_num_q;
        lookup_table_n = lookup_table_q;
        free_n = free_q;
        free_num_n = free_num_q;
        read_pointer_n = read_pointer_q;
        write_pointer_n = write_pointer_q;
        
        issue_n[0].is_valid = decoded_entry_valid_0_i;
        issue_n[0].is_control = is_ctrl_flow_0_i;
        issue_n[1].is_valid = decoded_entry_valid_1_i;
        issue_n[1].is_control = is_ctrl_flow_1_i;
        issue_n[2].is_valid = decoded_entry_valid_2_i;
        issue_n[2].is_control = is_ctrl_flow_2_i;
        issue_n[3].is_valid = decoded_entry_valid_3_i;
        issue_n[3].is_control = is_ctrl_flow_3_i;
        
        // commit first
        if (commit_valid_i[0])
        begin
            free_n[write_pointer_n] = commit_register[0];
            free_num = free_num + 1;
            write_pointer_n = write_pointer_n+1;
        end
        
        if (commit_valid_i[1])
        begin
            free_n[write_pointer_n] = commit_register[1];
            write_pointer_n = write_pointer_n+1;
            free_num = free_num + 1;
        end
        if (commit_valid_i[2])
        begin
            free_n[write_pointer_n] = commit_register[2];
            write_pointer_n = write_pointer_n+1;
            free_num = free_num + 1;
        end
        
        if (commit_valid_i[3])
        begin
            free_n[write_pointer_n] = commit_register[2];
            write_pointer_n = write_pointer_n+1;
            free_num = free_num + 1;
        end
        
        // translation
        if (rename_instr_ack_0_o)
        begin
            if (decoded_entry_0_i.valid)
            begin
                // rs translation
                issue_n[0].sbe = decoded_entry_0_i.decoded;        
                issue_n[0].sbe.rs1 = lookup_table_q[issue_entry_0_o.rs1];
                issue_n[0].sbe.rs2 = lookup_table_q[issue_entry_0_o.rs2];
                // rd translation & look up
                lookup_table_n[issue_entry_0_o.rd] = free_n[read_pointer_n];
                read_pointer_n=read_pointer_n+1;
                issue_n[0].sbe.rd = lookup_table_n[issue_entry_0_o.rd];
            end
            
           if (decoded_entry_1_i.valid)
             begin
                 // rs translation
                 issue_n[1].sbe = decoded_entry_1_i.decoded;        
                 issue_n[1].sbe.rs1 = lookup_table_q[issue_entry_1_o.rs1];
                 issue_n[1].sbe.rs2 = lookup_table_q[issue_entry_1_o.rs2];
                 // rd translation & look up
                 lookup_table_n[issue_entry_1_o.rd] = free_n[read_pointer_n];
                 read_pointer_n=read_pointer_n+1;
                 issue_n[1].sbe.rd = lookup_table_n[issue_entry_1_o.rd];
             end
           if (decoded_entry_2_i.valid)
              begin
                  // rs translation
                  issue_n[2].sbe = decoded_entry_2_i.decoded;        
                  issue_n[2].sbe.rs1 = lookup_table_q[issue_entry_2_o.rs1];
                  issue_n[2].sbe.rs2 = lookup_table_q[issue_entry_2_o.rs2];
                  // rd translation & look up
                  lookup_table_n[issue_entry_2_o.rd] = free_n[read_pointer_n];
                  read_pointer_n=read_pointer_n+1;
                  issue_n[2].sbe.rd = lookup_table_n[issue_entry_2_o.rd];
              end
           if (decoded_entry_3_i.valid)
               begin
                   // rs translation
                   issue_n[3].sbe = decoded_entry_0_i.decoded;        
                   issue_n[3].sbe.rs1 = lookup_table_q[issue_entry_3_o.rs1];
                   issue_n[3].sbe.rs2 = lookup_table_q[issue_entry_3_o.rs2];
                   // rd translation & look up
                   lookup_table_n[issue_entry_3_o.rd] = free_n[read_pointer_n];
                   read_pointer_n=read_pointer_n+1;
                   issue_n[3].sbe.rd = lookup_table_n[issue_entry_3_o.rd];
               end
            free_num = free_num-4;
        end
        free_num_n = free_num;
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
                free_q[i] <= 32+i;
            end
            else
            begin
                free_q[i] <= free_n[i];
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
            write_pointer_q <= 32;
            read_pointer_q <= 0;
        end
        else 
        begin    
            issue_q <= issue_n;
            free_num_q <= free_num_n;
            write_pointer_q <= write_pointer_n;
            read_pointer_q <= read_pointer_n; 
        end
    end       
endmodule
