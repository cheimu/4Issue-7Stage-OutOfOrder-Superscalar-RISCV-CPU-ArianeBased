module icache_testbench;
	localparam FETCH_ADDR_WIDTH = 56;
	localparam FETCH_DATA_WIDTH = 128;
	localparam ID_WIDTH = 4;
	localparam AXI_DATA_WIDTH = 64;
	logic                            clk_i;
	logic                            rst_n;
	logic                            test_en_i;
	// interface with processor
	logic                           fetch_req_i;
	logic [FETCH_ADDR_WIDTH-1:0]    fetch_addr_i;
	logic                           fetch_gnt_o;
	logic                           fetch_rvalid_o;
	logic [FETCH_DATA_WIDTH-1:0]    fetch_rdata_o;

	// AXI_BUS.Master                         axi,                 // refill port

	logic                           bypass_icache_i;
	logic                           cache_is_bypassed_o;
	logic                           flush_icache_i;
	logic                           cache_is_flushed_o;
	logic                           flush_set_ID_req_i;
	logic [FETCH_ADDR_WIDTH-1:0]    flush_set_ID_addr_i;
	logic                           flush_set_ID_ack_o;
	
	
	logic                                  refill_req_to_comp;
    logic                                  refill_type_to_comp;
    logic                                  refill_gnt_from_comp;
    logic [FETCH_ADDR_WIDTH-1:0]           refill_addr_to_comp;
    logic [ID_WIDTH-1:0]                   refill_ID_to_comp;

    logic                                  refill_r_valid_from_comp;
    logic                                  refill_r_last_from_comp;
    logic [AXI_DATA_WIDTH-1:0]             refill_r_rdata_from_comp;
    logic [ID_WIDTH-1:0]                   refill_r_ID_from_comp;

	
	icache dut(
		.*
	);
	
	parameter CLOCK_PERIOD=1000;
	initial begin
		clk_i <= 0;
		forever #(CLOCK_PERIOD/2) clk_i <= ~clk_i;
	end
	
	initial
	begin
	rst_n <= 1'b0;bypass_icache_i<=1'b0;flush_icache_i<=1'b0;flush_set_ID_req_i <= 1'b0; @(posedge clk_i);
	rst_n <= 1'b1;fetch_req_i<=1'b1;fetch_addr_i<= 56'h60;@(posedge clk_i);
	repeat(127)
	begin
	@(posedge clk_i);
	end
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	refill_gnt_from_comp<= 1'b1;@(posedge clk_i);
	refill_gnt_from_comp <= 1'b1;refill_r_valid_from_comp <= 1'b1; refill_r_rdata_from_comp<= 64'hfc;refill_r_last_from_comp<= 1'b0;@(posedge clk_i);
	refill_r_last_from_comp <= 1'b1;refill_r_rdata_from_comp <= 64'h132433d;@(posedge clk_i);
	refill_gnt_from_comp <= 1'b0;refill_r_last_from_comp <= 1'b0;refill_r_rdata_from_comp <= 64'h93949;  @(posedge clk_i);
	refill_r_last_from_comp <= 1'b0;refill_r_rdata_from_comp <= 64'h93949;@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	@(posedge clk_i);
	$stop;
	end
	
endmodule