/* Copyright (C) 2017 ETH Zurich, University of Bologna
 * All rights reserved.
 *
 * This code is under development and not yet released to the public.
 * Until it is released, the code is under the copyright of ETH Zurich and
 * the University of Bologna, and may contain confidential and/or unpublished
 * work. Any reuse/redistribution is strictly forbidden without written
 * permission from ETH Zurich.
 *
 * Bug fixes and contributions will eventually be released under the
 * SolderPad open hardware license in the context of the PULP platform
 * (http://www.pulp-platform.org), under the copyright of ETH Zurich and the
 * University of Bologna.
 */

module axi2per_res_channel #(
    parameter int unsigned  PER_ADDR_WIDTH = 32,
    parameter int unsigned  PER_DATA_WIDTH = 32,
    parameter int unsigned  PER_ID_WIDTH   = 5,
    parameter int unsigned  AXI_ADDR_WIDTH = 32,
    parameter int unsigned  AXI_DATA_WIDTH = 64,
    parameter int unsigned  AXI_USER_WIDTH = 6,
    parameter int unsigned  AXI_ID_WIDTH   = 3
)(
    input  logic                      clk_i,
    input  logic                      rst_ni,

    // PERIPHERAL INTERCONNECT MASTER
    //***************************************
    //RESPONSE CHANNEL
    input logic                       per_master_r_valid_i,
    input logic                       per_master_r_opc_i,
    input logic [PER_DATA_WIDTH-1:0]  per_master_r_rdata_i,

    // AXI4 MASTER
    //***************************************
    // READ DATA CHANNEL
    output logic                      axi_slave_r_valid_o,
    output logic [AXI_DATA_WIDTH-1:0] axi_slave_r_data_o,
    output logic [1:0]                axi_slave_r_resp_o,
    output logic                      axi_slave_r_last_o,
    output logic [AXI_ID_WIDTH-1:0]   axi_slave_r_id_o,
    output logic [AXI_USER_WIDTH-1:0] axi_slave_r_user_o,
    input  logic                      axi_slave_r_ready_i,

    // WRITE RESPONSE CHANNEL
    output logic                      axi_slave_b_valid_o,
    output logic [1:0]                axi_slave_b_resp_o,
    output logic [AXI_ID_WIDTH-1:0]   axi_slave_b_id_o,
    output logic [AXI_USER_WIDTH-1:0] axi_slave_b_user_o,
    input  logic                      axi_slave_b_ready_i,

    // CONTROL SIGNALS
    input logic                       trans_req_i,
    input logic                       trans_we_i,
    input logic [AXI_ID_WIDTH-1:0]    trans_id_i,
    input logic [AXI_ADDR_WIDTH-1:0]  trans_add_i,
    output logic                      trans_r_valid_o
);

    logic [AXI_DATA_WIDTH-1:0] s_axi_slave_r_data;

    logic [PER_DATA_WIDTH-1:0] s_per_master_r_data;

    logic                      s_trans_we_buf;
    logic [AXI_ID_WIDTH-1:0]   s_trans_id_buf;
    logic                      s_trans_add_alignment;  //0 --> aligned to 64bit, 1--> not aligned to 64bit

    enum logic  { TRANS_IDLE, TRANS_PENDING } CS, NS;

    // UPDATE THE STATE
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (rst_ni == 1'b0) begin
            CS <= TRANS_IDLE;
        end else begin
            CS <= NS;
        end
    end

    // COMPUTE NEXT STATE
    always_comb begin

        axi_slave_r_valid_o = '0;
        axi_slave_r_data_o  = '0;
        axi_slave_r_last_o  = '0;
        axi_slave_r_id_o    = '0;

        axi_slave_b_valid_o = '0;
        axi_slave_b_id_o    = '0;

        trans_r_valid_o     = '0;

        NS                  = TRANS_IDLE;

        case(CS)
            TRANS_IDLE: begin
                if ( per_master_r_valid_i == 1'b1 ) // RESPONSE VALID FROM PERIPHERAL INTERCONNECT
              begin
                 if ((s_trans_we_buf == 1'b1 && axi_slave_r_ready_i == 1'b1) || // READ OPERATION & THE AXI READ BUFFER IS ABLE TO ACCEPT A TRANSACTION
                    // THE AXI WRITE RESPONSE BUFFER IS ABLE TO ACCEPT A TRANSACTION
                    (s_trans_we_buf == 1'b0 && axi_slave_b_ready_i == 1'b1)) begin
                        NS = TRANS_PENDING;
                    end
                end
            end

            TRANS_PENDING: begin
                // THE AXI READ BUFFER IS ABLE TO ACCEPT A TRANSACTION
                if (s_trans_we_buf == 1'b1 &&  axi_slave_r_ready_i == 1'b1) begin // READ OPERATION

                    axi_slave_r_valid_o = 1'b1;
                    axi_slave_r_last_o  = 1'b1;
                    axi_slave_r_data_o  = s_axi_slave_r_data;
                    axi_slave_r_id_o    = s_trans_id_buf;

                    trans_r_valid_o     = 1'b1;

                    NS = TRANS_IDLE;
                // THE AXI WRITE RESPONSE BUFFER IS ABLE TO ACCEPT A TRANSACTION
                end else if (trans_we_i == 1'b0 && axi_slave_b_ready_i == 1'b1) begin
                   axi_slave_b_valid_o = 1'b1;
                   axi_slave_b_id_o    = s_trans_id_buf;

                   trans_r_valid_o     = 1'b1;

                   NS = TRANS_IDLE;
                end else begin
                    NS = TRANS_PENDING;
                end
            end
        endcase
    end

    // STORES REQUEST ADDRESS BIT 2 TRANSFER TYPE AND THE ID WHEN A REQUEST OCCURS ON THE REQ CHANNEL
    always_ff @ (posedge clk_i, negedge rst_ni) begin
        if (rst_ni == 1'b0) begin
            s_trans_we_buf        <= '0;
            s_trans_add_alignment <= 1'b0;
            s_trans_id_buf        <= '0;
        end else begin
            if (trans_req_i) begin
                s_trans_we_buf        <= trans_we_i;
                s_trans_add_alignment <= trans_add_i[2];
                s_trans_id_buf        <= trans_id_i;
            end
        end
    end

    // STORES RDATA WHEN RVALID SIGNAL IS ASSERTED
    always_ff @ (posedge clk_i, negedge rst_ni) begin
        if (rst_ni == 1'b0) begin
            s_per_master_r_data <= '0;
        end else begin
            if(per_master_r_valid_i == 1'b1) begin
                s_per_master_r_data <= per_master_r_rdata_i;
            end
        end
    end

    // SELECT MSB OR LSBS OF DATA
    always_comb begin
        if (PER_DATA_WIDTH == 32) begin
            if (s_trans_add_alignment == 1'b0) begin
                s_axi_slave_r_data = {32'b0,s_per_master_r_data};
            end else begin
                s_axi_slave_r_data = {s_per_master_r_data,32'b0};
            end
        end else if (PER_DATA_WIDTH == 64) begin
            s_axi_slave_r_data = s_per_master_r_data;
        end
    end

    // UNUSED SIGNALS
    assign axi_slave_r_resp_o = '0;
    assign axi_slave_r_user_o = '0;
    assign axi_slave_b_resp_o = '0;
    assign axi_slave_b_user_o = '0;

endmodule
