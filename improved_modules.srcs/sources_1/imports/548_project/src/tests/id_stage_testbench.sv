`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/20/2018 12:06:16 AM
// Design Name: 
// Module Name: dma_testbench
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



module btb_testbench;
    reg clk, rst;
	reg[7:0] X;
	reg[6:0] W;
	wire [14:0] RES;
	
	btb dut (
	.clk_i(clk),
	.rst_ni(rst),
	.flush_i(),
	.vpc_i()
	);
    
	parameter CLOCK_PERIOD=1000;
     initial begin
     clk <= 0;
     forever #(CLOCK_PERIOD/2) clk <= ~clk;
     end
     integer i;
     // Set up the inputs to the design. Each line is a clock cycle.
     initial begin
     rst <= 1;@(posedge clk);
	 rst <= 0; X = 4; W = 5; @(posedge clk);
	 @(posedge clk);
	 @(posedge clk);
	 @(posedge clk);
	 @(posedge clk);
	 @(posedge clk);
     $stop; // End the simulation.
     end
endmodule
