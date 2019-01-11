// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author:         Antonio Pullini - pullinia@iis.ee.ethz.ch
//
// Additional contributions by:
//                 Sven Stucki - svstucki@student.ethz.ch
//                 Markus Wegmann - markus.wegmann@technokrat.ch
//
// Design Name:    RISC-V register file
// Project Name:   zero-riscy
// Language:       SystemVerilog
//
// Description:    Register file with 31 or 15x 32 bit wide registers.
//                 Register 127 is fixed to 0. This register file is based on
//                 latches and is thus smaller than the flip-flop based RF.
//

module regfile
#(
  parameter DATA_WIDTH    = 64,
  parameter integer NR_WB_PORTS = 4
)
(
  // Clock and Reset
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   test_en_i,

  //Read port R1
  input  logic [NR_WB_PORTS-1:0][6:0]             raddr_a_i,
  output logic [NR_WB_PORTS-1:0][DATA_WIDTH-1:0]  rdata_a_o,

  //Read port R2
  input  logic [NR_WB_PORTS-1:0][6:0]             raddr_b_i,
  output logic [NR_WB_PORTS-1:0][DATA_WIDTH-1:0]  rdata_b_o,


  // Write port W1
  input  logic [NR_WB_PORTS-1:0][6:0]              waddr_a_i,
  input  logic [NR_WB_PORTS-1:0][DATA_WIDTH-1:0]   wdata_a_i,
  input  logic [NR_WB_PORTS-1:0]                   we_a_i

);


  localparam    ADDR_WIDTH = 7;
  localparam    NUM_WORDS  = 2**ADDR_WIDTH;

  logic [DATA_WIDTH-1:0]      mem[NUM_WORDS];

  logic  [NR_WB_PORTS-1:0][NUM_WORDS-1:0]                     waddr_onehot_a;
   

  logic [NR_WB_PORTS-1:0][NUM_WORDS-1:0]          mem_clocks;
  logic [NR_WB_PORTS-1:0][DATA_WIDTH-1:0]        wdata_a_q;


  // Write port W1
  logic [NR_WB_PORTS-1:0][ADDR_WIDTH-1:0]     raddr_a_int, raddr_b_int, waddr_a_int;
  assign raddr_a_int = raddr_a_i;
  assign raddr_b_int = raddr_b_i;
  assign waddr_a_int = waddr_a_i;
  always_comb begin: bypass_a
  for(int unsigned i = 0; i < NR_WB_PORTS; i+=1) begin: write_a
    if(we_a_i[i]) begin 
      if (raddr_a_i[i] == 7'b1111111) begin
        rdata_a_o[i] = 0;
      end else if (raddr_a_i[i] == waddr_a_i[i]) begin 
        rdata_a_o[i] = wdata_a_i[i];
      end else begin
        rdata_a_o[i] = mem[raddr_a_int[i]];
      end
    end else begin
      rdata_a_o[i] = mem[raddr_a_int[i]];
    end
  end
  end
  
  always_comb begin: bypass_b
  for(int unsigned i = 0; i < NR_WB_PORTS; i+=1) begin: write_b
    if(we_a_i[i]) begin 
      if (raddr_b_i[i] == 7'b1111111) begin
        rdata_b_o[i] = 0;
      end else if (raddr_b_i[i] == waddr_a_i[i]) begin 
        rdata_b_o[i] = wdata_a_i[i];
      end else begin
        rdata_b_o[i] = mem[raddr_b_int[i]];
      end
    end else begin
      rdata_b_o[i] = mem[raddr_b_int[i]];
    end
  end
  end


  logic [NR_WB_PORTS-1:0]clk_int;

  //-----------------------------------------------------------------------------
  //-- READ : Read address decoder RAD
  //-----------------------------------------------------------------------------
  /*
  assign rdata_a_o[3] = mem[raddr_a_int[3]];
  assign rdata_b_o[3] = mem[raddr_b_int[3]];

  assign rdata_a_o[2] = mem[raddr_a_int[2]];
  assign rdata_b_o[2] = mem[raddr_b_int[2]];

  assign rdata_a_o[1] = mem[raddr_a_int[1]];
  assign rdata_b_o[1] = mem[raddr_b_int[1]];

  assign rdata_a_o[0] = mem[raddr_a_int[0]];
  assign rdata_b_o[0] = mem[raddr_b_int[0]];
  */


  //-----------------------------------------------------------------------------
  // WRITE : SAMPLE INPUT DATA
  //---------------------------------------------------------------------------

  cluster_clock_gating CG_WE_GLOBAL_3
  (
    .clk_i     ( clk             ),
    .en_i      ( we_a_i[3]          ),
    .test_en_i ( test_en_i       ),
    .clk_o     ( clk_int[3]         )
  );
  cluster_clock_gating CG_WE_GLOBAL_2
  (
    .clk_i     ( clk             ),
    .en_i      ( we_a_i[2]          ),
    .test_en_i ( test_en_i       ),
    .clk_o     ( clk_int[2]         )
  );
cluster_clock_gating CG_WE_GLOBAL_1
  (
    .clk_i     ( clk             ),
    .en_i      ( we_a_i[1]          ),
    .test_en_i ( test_en_i       ),
    .clk_o     ( clk_int[1]         )
  );
cluster_clock_gating CG_WE_GLOBAL_0
  (
    .clk_i     ( clk             ),
    .en_i      ( we_a_i[0]          ),
    .test_en_i ( test_en_i       ),
    .clk_o     ( clk_int[0]         )
  );

  // use clk_int here, since otherwise we don't want to write anything anyway
  always_ff @(posedge clk_int[3], negedge rst_n) begin : sample_waddr_3
    if (~rst_n) begin
      wdata_a_q[3]   <= '0;
    end else begin
      if (we_a_i[3])
        wdata_a_q[3] <= wdata_a_i[3];
    end
  end
  always_ff @(posedge clk_int[2], negedge rst_n) begin : sample_waddr_2
    if (~rst_n) begin
      wdata_a_q[2]   <= '0;
    end else begin
      if (we_a_i[2])
        wdata_a_q[2] <= wdata_a_i[2];
    end
  end
always_ff @(posedge clk_int[1], negedge rst_n) begin : sample_waddr_1
    if (~rst_n) begin
      wdata_a_q[1]   <= '0;
    end else begin
      if (we_a_i[1])
        wdata_a_q[1] <= wdata_a_i[1];
    end
  end
always_ff @(posedge clk_int[0], negedge rst_n) begin : sample_waddr_0
    if (~rst_n) begin
      wdata_a_q[0]   <= '0;
    end else begin
      if (we_a_i[0])
        wdata_a_q[0] <= wdata_a_i[0];
    end
  end

  //-----------------------------------------------------------------------------
  // WRITE : Write Address Decoder (WAD), combinatorial process
  //-----------------------------------------------------------------------------
  always_comb begin : p_WADa
    for (int unsigned i = 0; i < NUM_WORDS - 1; i++) begin : p_WordItera_3
      if ( (we_a_i[3] == 1'b1 ) && (waddr_a_int[3] == i[6:0]) )
        waddr_onehot_a[3][i] = 1'b1;
      else
        waddr_onehot_a[3][i] = 1'b0;
    end
   for (int unsigned i = 0; i < NUM_WORDS-1; i++) begin : p_WordItera_2
      if ( (we_a_i[2] == 1'b1 ) && (waddr_a_int[2] == i[6:0]) )
        waddr_onehot_a[2][i] = 1'b1;
      else
        waddr_onehot_a[2][i] = 1'b0;
    end
   for (int unsigned i = 0; i < NUM_WORDS-1; i++) begin : p_WordItera_1
      if ( (we_a_i[1] == 1'b1 ) && (waddr_a_int[1] == i[6:0]) )
        waddr_onehot_a[1][i] = 1'b1;
      else
        waddr_onehot_a[1][i] = 1'b0;
    end
   for (int unsigned i = 0; i < NUM_WORDS-1; i++) begin : p_WordItera_0
      if ( (we_a_i[0] == 1'b1 ) && (waddr_a_int[0] == i[6:0]) )
        waddr_onehot_a[0][i] = 1'b1;
      else
        waddr_onehot_a[0][i] = 1'b0;
    end
  end


  //-----------------------------------------------------------------------------
  // WRITE : Clock gating (if integrated clock-gating cells are available)
  //-----------------------------------------------------------------------------
  genvar x;
  generate
    for (x = 0; x < NUM_WORDS - 1; x++) begin : CG_CELL_WORD_ITER_3
      cluster_clock_gating CG_Inst
      (
        .clk_i     ( clk_int[3]                               ),
        .en_i      ( waddr_onehot_a[3][x]                     ),
        .test_en_i ( test_en_i                             ),
        .clk_o     ( mem_clocks[3][x]                         )
      );
    end
  for (x = 0; x < NUM_WORDS; x++) begin : CG_CELL_WORD_ITER_2
      cluster_clock_gating CG_Inst
      (
        .clk_i     ( clk_int[2]                               ),
        .en_i      ( waddr_onehot_a[2][x]                     ),
        .test_en_i ( test_en_i                             ),
        .clk_o     ( mem_clocks[2][x]                         )
      );
    end
   for (x = 0; x < NUM_WORDS; x++) begin : CG_CELL_WORD_ITER_1
      cluster_clock_gating CG_Inst
      (
        .clk_i     ( clk_int[1]                               ),
        .en_i      ( waddr_onehot_a[1][x]                     ),
        .test_en_i ( test_en_i                             ),
        .clk_o     ( mem_clocks[1][x]                         )
      );
    end
   for (x = 0; x < NUM_WORDS; x++) begin : CG_CELL_WORD_ITER_0
      cluster_clock_gating CG_Inst
      (
        .clk_i     ( clk_int[0]                               ),
        .en_i      ( waddr_onehot_a[0][x]                     ),
        .test_en_i ( test_en_i                             ),
        .clk_o     ( mem_clocks[0][x]                         )
      );
    end
  endgenerate

  //-----------------------------------------------------------------------------
  // WRITE : Write operation
  //-----------------------------------------------------------------------------
  // Generate M = WORDS sequential processes, each of which describes one
  // word of the memory. The processes are synchronized with the clocks
  // ClocksxC(i), i = 0, 1, ..., M-1
  // Use active low, i.e. transparent on low latches as storage elements
  // Data is sampled on rising clock edge

  always_latch begin : latch_wdata
    // Note: The assignment has to be done inside this process or Modelsim complains about it
    mem[NUM_WORDS - 1] = '0;

 
    for (int unsigned k = 0; k < NUM_WORDS - 1; k++) begin : w_WordIter_normal
  if (mem_clocks[3][k] == 1'b1) begin
            mem[k] = wdata_a_q[3];
        end 
  if (mem_clocks[2][k] == 1'b1) begin
            mem[k] = wdata_a_q[2];
        end
  if (mem_clocks[1][k] == 1'b1) begin
            mem[k] = wdata_a_q[1];
        end
  if (mem_clocks[0][k] == 1'b1) begin
            mem[k] = wdata_a_q[0];
        end
    end
  end


endmodule