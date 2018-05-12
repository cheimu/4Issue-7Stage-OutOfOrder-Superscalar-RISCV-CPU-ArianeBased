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
// Author: Florian Zaruba, ETH Zurich
// Date: 15.04.2017
// Description: Description: Instruction decode, contains the logic for decode,
//              issue and read operands.

//include "../include/ariane_pkg.sv";
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

    localparam logic [63:0] ISA_CODE = (1 <<  2)  // C - Compressed extension
                                     | (1 <<  8)  // I - RV32I/64I/128I base ISA
                                     | (1 << 12)  // M - Integer Multiply/Divide extension
                                     | (0 << 13)  // N - User level interrupts supported
                                     | (1 << 18)  // S - Supervisor mode implemented
                                     | (1 << 20)  // U - User mode implemented
                                     | (0 << 23)  // X - Non-standard extensions present
                                     | (1 << 63); // RV64

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

    localparam EXC_OFF_RST      = 8'h80;

    // ---------------
    // EX Stage
    // ---------------
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

    // ----------------------
    // Extract Bytes from Op
    // ----------------------
    // TODO: Add atomics
    function automatic logic [1:0] extract_transfer_size (fu_op op);
        case (op)
            LD, SD:      return 2'b11;
            LW, LWU, SW: return 2'b10;
            LH, LHU, SH: return 2'b01;
            LB, SB, LBU: return 2'b00;
            default:     return 2'b11;
        endcase
    endfunction

    typedef struct packed {
        logic                     valid;
        logic [63:0]              vaddr;
        logic [63:0]              data;
        logic [7:0]               be;
        fu_t                      fu;
        fu_op                     operator;
        logic [TRANS_ID_BITS-1:0] trans_id;
    } lsu_ctrl_t;
    // ---------------
    // IF/ID Stage
    // ---------------
    // store the decompressed instruction
    typedef struct packed {
        logic [63:0]        address;              // the address of the instructions from below
        logic [31:0]        instruction;          // instruction word
        branchpredict_sbe_t branch_predict;       // this field contains branch prediction information regarding the forward branch path
        exception_t         ex;                   // this field contains exceptions which might have happened earlier, e.g.: fetch exceptions
		logic 				valid;				  // this field contains whether the fetch entry in buffer is valid
	} fetch_entry_t;

    // ---------------
    // ID/EX/WB Stage
    // ---------------
    typedef struct packed {
        logic [63:0]              pc;            // PC of instruction
        logic [TRANS_ID_BITS-1:0] trans_id;      // this can potentially be simplified, we could index the scoreboard entry
                                                 // with the transaction id in any case make the width more generic
        fu_t                      fu;            // functional unit to use
        fu_op                     op;            // operation to perform in each functional unit
        logic [4:0]               rs1;           // register source address 1
        logic [4:0]               rs2;           // register source address 2
        logic [4:0]               rd;            // register destination address
        logic [63:0]              result;        // for unfinished instructions this field also holds the immediate
        logic                     valid;         // is the result valid
        logic                     use_imm;       // should we use the immediate as operand b?
        logic                     use_zimm;      // use zimm as operand a
        logic                     use_pc;        // set if we need to use the PC as operand a, PC from exception
        exception_t               ex;            // exception has occurred
        branchpredict_sbe_t       bp;            // branch predict scoreboard data structure
        logic                     is_compressed; // signals a compressed instructions, we need this information at the commit stage if
                                                 // we want jump accordingly e.g.: +4, +2
    } scoreboard_entry_t;
	
	typedef struct packed {
		scoreboard_entry_t sbe;
		logic 			   valid;
	} decoded_entry_t;

    // --------------------
    // Instruction Types
    // --------------------
    typedef struct packed {
        logic [31:25] funct7;
        logic [24:20] rs2;
        logic [19:15] rs1;
        logic [14:12] funct3;
        logic [11:7]  rd;
        logic [6:0]   opcode;
    } rtype_t;

    typedef struct packed {
        logic [31:20] imm;
        logic [19:15] rs1;
        logic [14:12] funct3;
        logic [11:7]  rd;
        logic [6:0]   opcode;
    } itype_t;

    typedef struct packed {
        logic [31:25] imm;
        logic [24:20] rs2;
        logic [19:15] rs1;
        logic [14:12] funct3;
        logic [11:7]  imm0;
        logic [6:0]   opcode;
    } stype_t;

    typedef struct packed {
        logic [31:12] funct3;
        logic [11:7]  rd;
        logic [6:0]   opcode;
    } utype_t;

    typedef union packed {
        logic [31:0]   instr;
        rtype_t        rtype;
        itype_t        itype;
        stype_t        stype;
        utype_t        utype;
    } instruction_t;

    // --------------------
    // Opcodes
    // --------------------
    localparam OPCODE_SYSTEM    = 7'h73;
    localparam OPCODE_FENCE     = 7'h0f;
    localparam OPCODE_OP        = 7'h33;
    localparam OPCODE_OP32      = 7'h3B;
    localparam OPCODE_OPIMM     = 7'h13;
    localparam OPCODE_OPIMM32   = 7'h1B;
    localparam OPCODE_STORE     = 7'h23;
    localparam OPCODE_LOAD      = 7'h03;
    localparam OPCODE_BRANCH    = 7'h63;
    localparam OPCODE_JALR      = 7'h67;
    localparam OPCODE_JAL       = 7'h6f;
    localparam OPCODE_AUIPC     = 7'h17;
    localparam OPCODE_LUI       = 7'h37;
    localparam OPCODE_AMO       = 7'h2F;
    // --------------------
    // Atomics
    // --------------------

    typedef enum logic [3:0] {
        AMO_NONE, AMO_LR, AMO_SC, AMO_SWAP, AMO_ADD, AMO_AND, AMO_OR, AMO_XOR, AMO_MAX, AMO_MAXU, AMO_MIN, AMO_MINU
    } amo_t;

    // --------------------
    // Privilege Spec
    // --------------------
    typedef enum logic[1:0] {
      PRIV_LVL_M = 2'b11,
      PRIV_LVL_S = 2'b01,
      PRIV_LVL_U = 2'b00
    } priv_lvl_t;

    // memory management, pte
    typedef struct packed {
        logic [9:0]  reserved;
        logic [43:0] ppn;
        logic [1:0]  rsw;
        logic d;
        logic a;
        logic g;
        logic u;
        logic x;
        logic w;
        logic r;
        logic v;
    } pte_t;

    // Bits required for representation of physical address space as 4K pages
    // (e.g. 27*4K == 39bit address space).
    localparam PPN4K_WIDTH = 38;

    // ----------------------
    // Exception Cause Codes
    // ----------------------
    localparam logic [63:0] INSTR_ADDR_MISALIGNED = 0;
    localparam logic [63:0] INSTR_ACCESS_FAULT    = 1;
    localparam logic [63:0] ILLEGAL_INSTR         = 2;
    localparam logic [63:0] BREAKPOINT            = 3;
    localparam logic [63:0] LD_ADDR_MISALIGNED    = 4;
    localparam logic [63:0] LD_ACCESS_FAULT       = 5;
    localparam logic [63:0] ST_ADDR_MISALIGNED    = 6;
    localparam logic [63:0] ST_ACCESS_FAULT       = 7;
    localparam logic [63:0] ENV_CALL_UMODE        = 8;  // environment call from user mode
    localparam logic [63:0] ENV_CALL_SMODE        = 9;  // environment call from supervisor mode
    localparam logic [63:0] ENV_CALL_MMODE        = 11; // environment call from machine mode
    localparam logic [63:0] INSTR_PAGE_FAULT      = 12; // Instruction page fault
    localparam logic [63:0] LOAD_PAGE_FAULT       = 13; // Load page fault
    localparam logic [63:0] STORE_PAGE_FAULT      = 15; // Store page fault

    localparam logic [63:0] S_SW_INTERRUPT        = (1 << 63) | 1;
    localparam logic [63:0] M_SW_INTERRUPT        = (1 << 63) | 3;
    localparam logic [63:0] S_TIMER_INTERRUPT     = (1 << 63) | 5;
    localparam logic [63:0] M_TIMER_INTERRUPT     = (1 << 63) | 7;
    localparam logic [63:0] S_EXT_INTERRUPT       = (1 << 63) | 9;
    localparam logic [63:0] M_EXT_INTERRUPT       = (1 << 63) | 11;

    // ----------------------
    // Performance Counters
    // ----------------------
    localparam logic [11:0] PERF_L1_ICACHE_MISS = 12'h0;     // L1 Instr Cache Miss
    localparam logic [11:0] PERF_L1_DCACHE_MISS = 12'h1;     // L1 Data Cache Miss
    localparam logic [11:0] PERF_ITLB_MISS      = 12'h2;     // ITLB Miss
    localparam logic [11:0] PERF_DTLB_MISS      = 12'h3;     // DTLB Miss
    localparam logic [11:0] PERF_LOAD           = 12'h4;     // Loads
    localparam logic [11:0] PERF_STORE          = 12'h5;     // Stores
    localparam logic [11:0] PERF_EXCEPTION      = 12'h6;     // Taken exceptions
    localparam logic [11:0] PERF_EXCEPTION_RET  = 12'h7;     // Exception return
    localparam logic [11:0] PERF_BRANCH_JUMP    = 12'h8;     // Software change of PC
    localparam logic [11:0] PERF_CALL           = 12'h9;     // Procedure call
    localparam logic [11:0] PERF_RET            = 12'hA;     // Procedure Return
    localparam logic [11:0] PERF_MIS_PREDICT    = 12'hB;     // Branch mis-predicted

    // -----
    // CSRs
    // -----
    typedef enum logic [11:0] {
        // Supervisor Mode CSRs
        CSR_SSTATUS        = 12'h100,
        CSR_SIE            = 12'h104,
        CSR_STVEC          = 12'h105,
        CSR_SCOUNTEREN     = 12'h106,
        CSR_SSCRATCH       = 12'h140,
        CSR_SEPC           = 12'h141,
        CSR_SCAUSE         = 12'h142,
        CSR_STVAL          = 12'h143,
        CSR_SIP            = 12'h144,
        CSR_SATP           = 12'h180,
        // Machine Mode CSRs
        CSR_MSTATUS        = 12'h300,
        CSR_MISA           = 12'h301,
        CSR_MEDELEG        = 12'h302,
        CSR_MIDELEG        = 12'h303,
        CSR_MIE            = 12'h304,
        CSR_MTVEC          = 12'h305,
        CSR_MCOUNTEREN     = 12'h306,
        CSR_MSCRATCH       = 12'h340,
        CSR_MEPC           = 12'h341,
        CSR_MCAUSE         = 12'h342,
        CSR_MTVAL          = 12'h343,
        CSR_MIP            = 12'h344,
        CSR_MVENDORID      = 12'hF11,
        CSR_MARCHID        = 12'hF12,
        CSR_MIMPID         = 12'hF13,
        CSR_MHARTID        = 12'hF14,
        CSR_MCYCLE         = 12'hB00,
        CSR_MINSTRET       = 12'hB02,
        CSR_DCACHE         = 12'h701,
        CSR_ICACHE         = 12'h700,
        // Counters and Timers
        CSR_CYCLE          = 12'hC00,
        CSR_TIME           = 12'hC01,
        CSR_INSTRET        = 12'hC02,
        // Performance counters
        CSR_L1_ICACHE_MISS = PERF_L1_ICACHE_MISS + 12'hC03,
        CSR_L1_DCACHE_MISS = PERF_L1_DCACHE_MISS + 12'hC03,
        CSR_ITLB_MISS      = PERF_ITLB_MISS      + 12'hC03,
        CSR_DTLB_MISS      = PERF_DTLB_MISS      + 12'hC03,
        CSR_LOAD           = PERF_LOAD           + 12'hC03,
        CSR_STORE          = PERF_STORE          + 12'hC03,
        CSR_EXCEPTION      = PERF_EXCEPTION      + 12'hC03,
        CSR_EXCEPTION_RET  = PERF_EXCEPTION_RET  + 12'hC03,
        CSR_BRANCH_JUMP    = PERF_BRANCH_JUMP    + 12'hC03,
        CSR_CALL           = PERF_CALL           + 12'hC03,
        CSR_RET            = PERF_RET            + 12'hC03,
        CSR_MIS_PREDICT    = PERF_MIS_PREDICT    + 12'hC03
    } csr_reg_t;

    // decoded CSR address
    typedef struct packed {
        logic [1:0]  rw;
        priv_lvl_t   priv_lvl;
        logic  [7:0] address;
    } csr_addr_t;

    typedef union packed {
        csr_reg_t   address;
        csr_addr_t  csr_decode;
    } csr_t;

    // ----------------------
    // Debug Unit
    // ----------------------
    typedef enum logic [15:0] {
        DBG_CTRL     = 16'h0,
        DBG_HIT      = 16'h8,
        DBG_IE       = 16'h10,
        DBG_CAUSE    = 16'h18,

        BP_CTRL0     = 16'h80,
        BP_DATA0     = 16'h88,
        BP_CTRL1     = 16'h90,
        BP_DATA1     = 16'h98,
        BP_CTRL2     = 16'hA0,
        BP_DATA2     = 16'hA8,
        BP_CTRL3     = 16'hB0,
        BP_DATA3     = 16'hB8,
        BP_CTRL4     = 16'hC0,
        BP_DATA4     = 16'hC8,
        BP_CTRL5     = 16'hD0,
        BP_DATA5     = 16'hD8,
        BP_CTRL6     = 16'hE0,
        BP_DATA6     = 16'hE8,
        BP_CTRL7     = 16'hF0,
        BP_DATA7     = 16'hF8,

        DBG_NPC      = 16'h2000,
        DBG_PPC      = 16'h2008,
        DBG_GPR      = 16'h4??,

        // CSRs 0x4000-0xBFFF
        DBG_CSR_U0   = 16'h8???,
        DBG_CSR_U1   = 16'h9???,
        DBG_CSR_S0   = 16'hA???,
        DBG_CSR_S1   = 16'hB???,
        DBG_CSR_H0   = 16'hC???,
        DBG_CSR_H1   = 16'hD???,
        DBG_CSR_M0   = 16'hE???,
        DBG_CSR_M1   = 16'hF???
    } debug_reg_t;

    // ----------------------
    // Arithmetic Functions
    // ----------------------
    function automatic logic [63:0] sext32 (logic [31:0] operand);
        return {{32{operand[31]}}, operand[31:0]};
    endfunction

module id_stage (
    input  logic                                     clk_i,     // Clock
    input  logic                                     rst_ni,    // Asynchronous reset active low

    input  logic                                     flush_i,
    // from IF
    input  fetch_entry_t                       fetch_entry_i_0,

	input  fetch_entry_t                       fetch_entry_i_1,

	input  fetch_entry_t                       fetch_entry_i_2,

	input  fetch_entry_t                       fetch_entry_i_3,
    input  logic                                     fetch_entry_valid_i_0,
	input  logic                                     fetch_entry_valid_i_1,
	input  logic                                     fetch_entry_valid_i_2,
	input  logic                                     fetch_entry_valid_i_3,
    output logic                                     decoded_instr_ack_o_0,
	output logic                                     decoded_instr_ack_o_1,
	output logic                                     decoded_instr_ack_o_2,
	output logic                                     decoded_instr_ack_o_3,	// acknowledge the instruction (fetch entry)
    // to ID
    output decoded_entry_t                        	 issue_entry_o_0,
	output decoded_entry_t                       	 issue_entry_o_1,
	output decoded_entry_t                       	 issue_entry_o_2,
	output decoded_entry_t                       	 issue_entry_o_3,	// a decoded instruction
    output logic                                     issue_entry_valid_o_0, // issue entry is valid
	output logic                                     issue_entry_valid_o_1,
	output logic                                     issue_entry_valid_o_2,
	output logic                                     issue_entry_valid_o_3,
    output logic                                     is_ctrl_flow_o_0,      // the instruction we issue is a ctrl flow instructions
	output logic                                     is_ctrl_flow_o_1,
	output logic                                     is_ctrl_flow_o_2,
	output logic                                     is_ctrl_flow_o_3,
    input  logic                                     issue_instr_ack_i_0,   // issue stage acknowledged sampling of instructions
	input  logic                                     issue_instr_ack_i_1,
	input  logic                                     issue_instr_ack_i_2,
	input  logic                                     issue_instr_ack_i_3,
    // from CSR file
    input  priv_lvl_t                                priv_lvl_i_0,          // current privilege level
	input  priv_lvl_t                                priv_lvl_i_1,
	input  priv_lvl_t                                priv_lvl_i_2,
	input  priv_lvl_t                                priv_lvl_i_3,
    input  logic                                     tvm_i_0,
	input  logic                                     tvm_i_1,
	input  logic                                     tvm_i_2,
	input  logic                                     tvm_i_3,
    input  logic                                     tw_i_0,
	input  logic                                     tw_i_1,
	input  logic                                     tw_i_2,
	input  logic                                     tw_i_3,
    input  logic                                     tsr_i_0,
	input  logic                                     tsr_i_1,
	input  logic                                     tsr_i_2,
	input  logic                                     tsr_i_3
);
    // register stage
    struct packed {
        logic            valid;
        scoreboard_entry_t sbe;
        logic            is_ctrl_flow;

    } issue_n_0,issue_n_1,issue_n_2,issue_n_3, issue_q_0, issue_q_1, issue_q_2, issue_q_3;

    logic                is_control_flow_instr_0;
	logic                is_control_flow_instr_1;
	logic                is_control_flow_instr_2;
	logic                is_control_flow_instr_3;
	
    decoded_entry_t      decoded_instruction_0;
	decoded_entry_t      decoded_instruction_1;
	decoded_entry_t      decoded_instruction_2;
	decoded_entry_t      decoded_instruction_3;

    fetch_entry_t        fetch_entry_0;
	fetch_entry_t        fetch_entry_1;
	fetch_entry_t        fetch_entry_2;
	fetch_entry_t        fetch_entry_3;
	
    logic                is_illegal_0;
    logic                [31:0] instruction_0;
    logic                is_compressed_0;
    logic                fetch_ack_i_0;
    logic                fetch_entry_valid_0;
	logic                is_illegal_1;
    logic                [31:0] instruction_1;
    logic                is_compressed_1;
    logic                fetch_ack_i_1;
    logic                fetch_entry_valid_1;
	logic                is_illegal_2;
    logic                [31:0] instruction_2;
    logic                is_compressed_2;
    logic                fetch_ack_i_2;
    logic                fetch_entry_valid_2;
	logic                is_illegal_3;
    logic                [31:0] instruction_3;
    logic                is_compressed_3;
    logic                fetch_ack_i_3;
    logic                fetch_entry_valid_3;

    // ---------------------------------------------------------
    // 1. Re-align instructions
    // ---------------------------------------------------------
    instr_realigner instr_realigner_i_0	(
        .fetch_entry_0_i         ( fetch_entry_i_0               ),
        .fetch_entry_valid_0_i   ( fetch_entry_valid_i_0         ),
        .fetch_ack_0_o           ( decoded_instr_ack_o_0         ),

        .fetch_entry_o           ( fetch_entry_0                 ),
        .fetch_entry_valid_o     ( fetch_entry_valid_0           ),
        .fetch_ack_i             ( fetch_ack_i_0                 ),
        .*
    );
	instr_realigner instr_realigner_i_1 (
        .fetch_entry_0_i         ( fetch_entry_i_1               ),
        .fetch_entry_valid_0_i   ( fetch_entry_valid_i_1         ),
        .fetch_ack_0_o           ( decoded_instr_ack_o_1         ),

        .fetch_entry_o           ( fetch_entry_1                 ),
        .fetch_entry_valid_o     ( fetch_entry_valid_1           ),
        .fetch_ack_i             ( fetch_ack_i_1                 ),
        .*
    );
	instr_realigner instr_realigner_i_2 (
        .fetch_entry_0_i         ( fetch_entry_i_2               ),
        .fetch_entry_valid_0_i   ( fetch_entry_valid_i_2         ),
        .fetch_ack_0_o           ( decoded_instr_ack_o_2         ),

        .fetch_entry_o           ( fetch_entry_2                 ),
        .fetch_entry_valid_o     ( fetch_entry_valid_2           ),
        .fetch_ack_i             ( fetch_ack_i_2                 ),
        .*
    );
	instr_realigner instr_realigner_i_3 (
        .fetch_entry_0_i         ( fetch_entry_i_3               ),
        .fetch_entry_valid_0_i   ( fetch_entry_valid_i_3         ),
        .fetch_ack_0_o           ( decoded_instr_ack_o_3         ),

        .fetch_entry_o           ( fetch_entry_3                 ),
        .fetch_entry_valid_o     ( fetch_entry_valid_3           ),
        .fetch_ack_i             ( fetch_ack_i_3                 ),
        .*
    );
    // ---------------------------------------------------------
    // 2. Check if they are compressed and expand in case they are
    // ---------------------------------------------------------
    compressed_decoder compressed_decoder_i_0 (
        .instr_i                 ( fetch_entry_0.instruction     ),
        .instr_o                 ( instruction_0                 ),
        .illegal_instr_o         ( is_illegal_0                  ),
        .is_compressed_o         ( is_compressed_0               )

    );
	compressed_decoder compressed_decoder_i_1 (
        .instr_i                 ( fetch_entry_1.instruction     ),
        .instr_o                 ( instruction_1                 ),
        .illegal_instr_o         ( is_illegal_1                  ),
        .is_compressed_o         ( is_compressed_1               )

    );
	compressed_decoder compressed_decoder_i_2 (
        .instr_i                 ( fetch_entry_2.instruction     ),
        .instr_o                 ( instruction_2                 ),
        .illegal_instr_o         ( is_illegal_2                  ),
        .is_compressed_o         ( is_compressed_2               )

    );
	compressed_decoder compressed_decoder_i_3 (
        .instr_i                 ( fetch_entry_3.instruction     ),
        .instr_o                 ( instruction_3                 ),
        .illegal_instr_o         ( is_illegal_3                  ),
        .is_compressed_o         ( is_compressed_3               )

    );
    // ---------------------------------------------------------
    // 3. Decode and emit instruction to issue stage
    // ---------------------------------------------------------
    decoder decoder_i_0 (
        .pc_i                    ( fetch_entry_0.address         ),
        .is_compressed_i         ( is_compressed_0               ),
        .instruction_i           ( instruction_0                 ),
        .branch_predict_i        ( fetch_entry_0.branch_predict  ),
        .is_illegal_i            ( is_illegal_0                  ),
        .ex_i                    ( fetch_entry_0.ex              ),
        .instruction_o           ( decoded_instruction_0         ),
        .is_control_flow_instr_o ( is_control_flow_instr_0       ),
        .priv_lvl_i              ( priv_lvl_i_0                  ),              // current privilege level
		.tvm_i                   ( tvm_i_0                       ),                   // trap virtual memory
		.tw_i                    ( tw_i_0                        ),                    // timeout wait
		.tsr_i                   ( tsr_i_0                       )                   // trap sret
    );
	decoder decoder_i_1 (
        .pc_i                    ( fetch_entry_1.address         ),
        .is_compressed_i         ( is_compressed_1               ),
        .instruction_i           ( instruction_1                 ),
        .branch_predict_i        ( fetch_entry_1.branch_predict  ),
        .is_illegal_i            ( is_illegal_1                  ),
        .ex_i                    ( fetch_entry_1.ex              ),
        .instruction_o           ( decoded_instruction_1         ),
        .is_control_flow_instr_o ( is_control_flow_instr_1       ),
        .priv_lvl_i              ( priv_lvl_i_1                  ),              // current privilege level
		.tvm_i                   ( tvm_i_1                       ),                   // trap virtual memory
		.tw_i                    ( tw_i_1                        ),                    // timeout wait
		.tsr_i                   ( tsr_i_1                       )                   // trap sret
    );
	decoder decoder_i_2 (
        .pc_i                    ( fetch_entry_2.address         ),
        .is_compressed_i         ( is_compressed_2               ),
        .instruction_i           ( instruction_2                 ),
        .branch_predict_i        ( fetch_entry_2.branch_predict  ),
        .is_illegal_i            ( is_illegal_2                  ),
        .ex_i                    ( fetch_entry_2.ex              ),
        .instruction_o           ( decoded_instruction_2         ),
        .is_control_flow_instr_o ( is_control_flow_instr_2       ),
        .priv_lvl_i              ( priv_lvl_i_2                  ),              // current privilege level
		.tvm_i                   ( tvm_i_2                       ),                   // trap virtual memory
		.tw_i                    ( tw_i_2                        ),                    // timeout wait
		.tsr_i                   ( tsr_i_2                       )                   // trap sret
    );
	decoder decoder_i_3 (
        .pc_i                    ( fetch_entry_3.address         ),
        .is_compressed_i         ( is_compressed_3               ),
        .instruction_i           ( instruction_3                 ),
        .branch_predict_i        ( fetch_entry_3.branch_predict  ),
        .is_illegal_i            ( is_illegal_3                  ),
        .ex_i                    ( fetch_entry_3.ex              ),
        .instruction_o           ( decoded_instruction_3         ),
        .is_control_flow_instr_o ( is_control_flow_instr_3       ),
        .priv_lvl_i              ( priv_lvl_i_3                  ),              // current privilege level
		.tvm_i                   ( tvm_i_3                       ),                   // trap virtual memory
		.tw_i                    ( tw_i_3                        ),                    // timeout wait
		.tsr_i                   ( tsr_i_3                       )                  // trap sret
    );
	assign issue_entry_o_0.valid = fetch_entry_0.valid;
	assign issue_entry_o_1.valid = fetch_entry_1.valid;
	assign issue_entry_o_2.valid = fetch_entry_2.valid;
	assign issue_entry_o_3.valid = fetch_entry_3.valid;
    // ------------------
    // Pipeline Register
    // ------------------
    assign issue_entry_o_0.sbe = issue_q_0.sbe;
	assign issue_entry_o_1.sbe = issue_q_1.sbe;
	assign issue_entry_o_2.sbe = issue_q_2.sbe;
	assign issue_entry_o_3.sbe = issue_q_3.sbe;
	
    assign issue_entry_valid_o_0 = issue_q_0.valid;
	assign issue_entry_valid_o_1 = issue_q_1.valid;
	assign issue_entry_valid_o_2 = issue_q_2.valid;
	assign issue_entry_valid_o_3 = issue_q_3.valid;
	
    assign is_ctrl_flow_o_0 = issue_q_0.is_ctrl_flow;
	assign is_ctrl_flow_o_1 = issue_q_1.is_ctrl_flow;
	assign is_ctrl_flow_o_2 = issue_q_2.is_ctrl_flow;
	assign is_ctrl_flow_o_3 = issue_q_3.is_ctrl_flow;

    always_comb begin
        issue_n_0     = issue_q_0;
		issue_n_1     = issue_q_1;
		issue_n_2     = issue_q_2;
		issue_n_3     = issue_q_3;
		
        fetch_ack_i_0 = 1'b0;
		fetch_ack_i_1 = 1'b0;
		fetch_ack_i_2 = 1'b0;
		fetch_ack_i_3 = 1'b0;

        // Clear the valid flag if issue has acknowledged the instruction
        if (issue_instr_ack_i_0)
            issue_n_0.valid = 1'b0;
		if (issue_instr_ack_i_0)
            issue_n_1.valid = 1'b0;
		if (issue_instr_ack_i_0)
            issue_n_2.valid = 1'b0;
		if (issue_instr_ack_i_0)
            issue_n_3.valid = 1'b0;
			

        // if we have a space in the register and the fetch is valid, go get it
        // or the issue stage is currently acknowledging an instruction, which means that we will have space
        // for a new instruction
        if ((!issue_q_0.valid || issue_instr_ack_i_0) && fetch_entry_valid_0) begin
            fetch_ack_i_0 = 1'b1;
            issue_n_0 = {1'b1, decoded_instruction_0, is_control_flow_instr_0};
        end
		if ((!issue_q_1.valid || issue_instr_ack_i_1) && fetch_entry_valid_1) begin
            fetch_ack_i_1 = 1'b1;
            issue_n_1 = {1'b1, decoded_instruction_1, is_control_flow_instr_1};
        end
		if ((!issue_q_2.valid || issue_instr_ack_i_2) && fetch_entry_valid_2) begin
            fetch_ack_i_2 = 1'b1;
            issue_n_2 = {1'b1, decoded_instruction_2, is_control_flow_instr_2};
        end
		if ((!issue_q_3.valid || issue_instr_ack_i_3) && fetch_entry_valid_3) begin
            fetch_ack_i_3 = 1'b1;
            issue_n_3 = {1'b1, decoded_instruction_3, is_control_flow_instr_3};
        end

        // invalidate the pipeline register on a flush
        if (flush_i) begin
            issue_n_0.valid = 1'b0;
			issue_n_1.valid = 1'b0;
			issue_n_2.valid = 1'b0;
			issue_n_3.valid = 1'b0;
		end
    end
    // -------------------------
    // Registers (ID <-> Issue)
    // -------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(~rst_ni) begin
            issue_q_0 <= '0;
			issue_q_1 <= '0;
			issue_q_2 <= '0;
			issue_q_3 <= '0;
        end else begin
            issue_q_0 <= issue_n_0;
			issue_q_1 <= issue_n_1;
			issue_q_2 <= issue_n_2;
			issue_q_3 <= issue_n_3;
        end
    end

endmodule

module decoder (
    input  logic [63:0]        pc_i,                    // PC from IF
    input  logic               is_compressed_i,         // is a compressed instruction
    input  logic               is_illegal_i,            // illegal compressed instruction
    input  logic [31:0]        instruction_i,           // instruction from IF
    input  branchpredict_sbe_t branch_predict_i,
    input  exception_t         ex_i,                    // if an exception occured in if
    // From CSR
    input  priv_lvl_t          priv_lvl_i,              // current privilege level
    input  logic               tvm_i,                   // trap virtual memory
    input  logic               tw_i,                    // timeout wait
    input  logic               tsr_i,                   // trap sret
    output decoded_entry_t     instruction_o,           // scoreboard entry to scoreboard
    output logic               is_control_flow_instr_o  // this instruction will change the control flow
);
    logic illegal_instr;
    // this instruction is an environment call (ecall), it is handled like an exception
    logic ecall;
    // this instruction is a software break-point
    logic ebreak;
    instruction_t instr;
    assign instr = instruction_t'(instruction_i);
    // --------------------
    // Immediate select
    // --------------------
    enum logic[3:0] {
        NOIMM, PCIMM, IIMM, SIMM, SBIMM, BIMM, UIMM, JIMM
    } imm_select;

    logic [63:0] imm_i_type;
    logic [11:0] imm_iz_type;
    logic [63:0] imm_s_type;
    logic [63:0] imm_sb_type;
    logic [63:0] imm_u_type;
    logic [63:0] imm_uj_type;
    logic [63:0] imm_z_type;
    logic [63:0] imm_s2_type;
    logic [63:0] imm_bi_type;
    logic [63:0] imm_s3_type;
    logic [63:0] imm_vs_type;
    logic [63:0] imm_vu_type;

    always_comb begin : decoder

        imm_select                  = NOIMM;
        is_control_flow_instr_o     = 1'b0;
        illegal_instr               = 1'b0;
        instruction_o.sbe.pc            = pc_i;
        instruction_o.sbe.fu            = NONE;
        instruction_o.sbe.op            = ADD;
        instruction_o.sbe.rs1           = 5'b0;
        instruction_o.sbe.rs2           = 5'b0;
        instruction_o.sbe.rd            = 5'b0;
        instruction_o.sbe.use_pc        = 1'b0;
        instruction_o.sbe.trans_id      = 5'b0;
        instruction_o.sbe.is_compressed = is_compressed_i;
        instruction_o.sbe.use_zimm      = 1'b0;
        instruction_o.sbe.bp            = branch_predict_i;
        ecall                       = 1'b0;
        ebreak                      = 1'b0;

        if (~ex_i.valid) begin
            case (instr.rtype.opcode)
                OPCODE_SYSTEM: begin
                    instruction_o.sbe.fu  = CSR;
                    instruction_o.sbe.rs1 = instr.itype.rs1;
                    instruction_o.sbe.rd  = instr.itype.rd;

                    unique case (instr.itype.funct3)
                        3'b000: begin
                            // check if the RD and and RS1 fields are zero, this may be reset for the SENCE.VMA instruction
                            if (instr.itype.rs1 != '0 || instr.itype.rd != '0)
                                illegal_instr = 1'b1;
                            // decode the immiediate field
                            case (instr.itype.imm)
                                // ECALL -> inject exception
                                12'b0: ecall  = 1'b1;
                                // EBREAK -> inject exception
                                12'b1: ebreak = 1'b1;
                                // SRET
                                12'b100000010: begin
                                    instruction_o.sbe.op = SRET;
                                    // check privilege level, SRET can only be executed in S and M mode
                                    // we'll just decode an illegal instruction if we are in the wrong privilege level
                                    if (priv_lvl_i == PRIV_LVL_U) begin
                                        illegal_instr = 1'b1;
                                        //  do not change privilege level if this is an illegal instruction
                                        instruction_o.sbe.op = ADD;
                                    end
                                    // if we are in S-Mode and Trap SRET (tsr) is set -> trap on illegal instruction
                                    if (priv_lvl_i == PRIV_LVL_S && tsr_i) begin
                                        illegal_instr = 1'b1;
                                        //  do not change privilege level if this is an illegal instruction
                                       instruction_o.sbe.op = ADD;
                                    end
                                end
                                // MRET
                                12'b1100000010: begin
                                    instruction_o.sbe.op = MRET;
                                    // check privilege level, MRET can only be executed in M mode
                                    // otherwise we decode an illegal instruction
                                    if (priv_lvl_i inside {PRIV_LVL_U, PRIV_LVL_S})
                                        illegal_instr = 1'b1;
                                end
                                // WFI
                                12'b1_0000_0101: begin
                                    instruction_o.sbe.op = WFI;
                                    // if timeout wait is set, trap on an illegal instruction in S Mode
                                    // (after 0 cycles timeout)
                                    if (priv_lvl_i == PRIV_LVL_S && tw_i) begin
                                        illegal_instr = 1'b1;
                                        instruction_o.sbe.op = ADD;
                                    end
                                    // we don't support U mode interrupts so WFI is illegal in this context
                                    if (priv_lvl_i == PRIV_LVL_U) begin
                                        illegal_instr = 1'b1;
                                        instruction_o.sbe.op = ADD;
                                    end
                                end
                                // SFENCE.VMA
                                default: begin
                                    if (instr.instr[31:25] == 7'b1001) begin
                                        // Reset illegal instruction here, this is the only type
                                        // of instruction which needs those kind of fields
                                        illegal_instr    = 1'b0;
                                        instruction_o.sbe.op = SFENCE_VMA;
                                        // check TVM flag and intercept SFENCE.VMA call if necessary
                                        if (priv_lvl_i == PRIV_LVL_S && tvm_i)
                                            illegal_instr = 1'b1;
                                    end
                                end
                            endcase
                        end
                        // atomically swaps values in the CSR and integer register
                        3'b001: begin// CSRRW
                            imm_select = IIMM;
                            instruction_o.sbe.op = CSR_WRITE;
                        end
                        // atomically set values in the CSR and write back to rd
                        3'b010: begin// CSRRS
                            imm_select = IIMM;
                            // this is just a read
                            if (instr.itype.rs1 == 5'b0)
                                instruction_o.sbe.op = CSR_READ;
                            else
                                instruction_o.sbe.op = CSR_SET;
                        end
                        // atomically clear values in the CSR and write back to rd
                        3'b011: begin// CSRRC
                            imm_select = IIMM;
                            // this is just a read
                            if (instr.itype.rs1 == 5'b0)
                                instruction_o.sbe.op = CSR_READ;
                            else
                                instruction_o.sbe.op = CSR_CLEAR;
                        end
                        // use zimm and iimm
                        3'b101: begin// CSRRWI
                            instruction_o.sbe.rs1 = instr.itype.rs1;
                            imm_select = IIMM;
                            instruction_o.sbe.use_zimm = 1'b1;
                            instruction_o.sbe.op = CSR_WRITE;
                        end
                        3'b110: begin// CSRRSI
                            instruction_o.sbe.rs1 = instr.itype.rs1;
                            imm_select = IIMM;
                            instruction_o.sbe.use_zimm = 1'b1;
                            // this is just a read
                            if (instr.itype.rs1 == 5'b0)
                                instruction_o.sbe.op = CSR_READ;
                            else
                                instruction_o.sbe.op = CSR_SET;
                        end
                        3'b111: begin// CSRRCI
                            instruction_o.sbe.rs1 = instr.itype.rs1;
                            imm_select = IIMM;
                            instruction_o.sbe.use_zimm = 1'b1;
                            // this is just a read
                            if (instr.itype.rs1 == 5'b0)
                                instruction_o.sbe.op = CSR_READ;
                            else
                                instruction_o.sbe.op = CSR_CLEAR;
                        end
                        default: illegal_instr = 1'b1;
                    endcase
                end
                // Memory ordering instructions
                OPCODE_FENCE: begin
                    instruction_o.sbe.fu  = CSR;
                    instruction_o.sbe.rs1 = '0;
                    instruction_o.sbe.rs2 = '0;
                    instruction_o.sbe.rd  = '0;

                    case (instr.stype.funct3)
                        // FENCE
                        // Currently implemented as a whole DCache flush boldly ignoring other things
                        3'b000: instruction_o.sbe.op  = FENCE;
                        // FENCE.I
                        3'b001: begin
                            if (instr.instr[31:20] != '0)
                                illegal_instr = 1'b1;
                            instruction_o.sbe.op  = FENCE_I;
                        end
                        default: illegal_instr = 1'b1;
                    endcase

                    if (instr.stype.rs1 != '0 || instr.stype.imm0 != '0 || instr.instr[31:28] != '0)
                        illegal_instr = 1'b1;
                end

                // --------------------------
                // Reg-Reg Operations
                // --------------------------
                OPCODE_OP: begin
                    instruction_o.sbe.fu  = (instr.rtype.funct7 == 7'b000_0001) ? MULT : ALU;
                    instruction_o.sbe.rs1 = instr.rtype.rs1;
                    instruction_o.sbe.rs2 = instr.rtype.rs2;
                    instruction_o.sbe.rd  = instr.rtype.rd;

                    unique case ({instr.rtype.funct7, instr.rtype.funct3})
                        {7'b000_0000, 3'b000}: instruction_o.sbe.op = ADD;   // Add
                        {7'b010_0000, 3'b000}: instruction_o.sbe.op = SUB;   // Sub
                        {7'b000_0000, 3'b010}: instruction_o.sbe.op = SLTS;  // Set Lower Than
                        {7'b000_0000, 3'b011}: instruction_o.sbe.op = SLTU;  // Set Lower Than Unsigned
                        {7'b000_0000, 3'b100}: instruction_o.sbe.op = XORL;  // Xor
                        {7'b000_0000, 3'b110}: instruction_o.sbe.op = ORL;   // Or
                        {7'b000_0000, 3'b111}: instruction_o.sbe.op = ANDL;  // And
                        {7'b000_0000, 3'b001}: instruction_o.sbe.op = SLL;   // Shift Left Logical
                        {7'b000_0000, 3'b101}: instruction_o.sbe.op = SRL;   // Shift Right Logical
                        {7'b010_0000, 3'b101}: instruction_o.sbe.op = SRA;   // Shift Right Arithmetic
                        // Multiplications
                        {7'b000_0001, 3'b000}: instruction_o.sbe.op = MUL;
                        {7'b000_0001, 3'b001}: instruction_o.sbe.op = MULH;
                        {7'b000_0001, 3'b010}: instruction_o.sbe.op = MULHSU;
                        {7'b000_0001, 3'b011}: instruction_o.sbe.op = MULHU;
                        {7'b000_0001, 3'b100}: instruction_o.sbe.op = DIV;
                        {7'b000_0001, 3'b101}: instruction_o.sbe.op = DIVU;
                        {7'b000_0001, 3'b110}: instruction_o.sbe.op = REM;
                        {7'b000_0001, 3'b111}: instruction_o.sbe.op = REMU;
                        default: begin
                            illegal_instr = 1'b1;
                        end
                    endcase
                end

                // --------------------------
                // 32bit Reg-Reg Operations
                // --------------------------
                OPCODE_OP32: begin
                    instruction_o.sbe.fu  = (instr.rtype.funct7 == 7'b000_0001) ? MULT : ALU;
                    instruction_o.sbe.rs1 = instr.rtype.rs1;
                    instruction_o.sbe.rs2 = instr.rtype.rs2;
                    instruction_o.sbe.rd  = instr.rtype.rd;

                        unique case ({instr.rtype.funct7, instr.rtype.funct3})
                            {7'b000_0000, 3'b000}: instruction_o.sbe.op = ADDW; // addw
                            {7'b010_0000, 3'b000}: instruction_o.sbe.op = SUBW; // subw
                            {7'b000_0000, 3'b001}: instruction_o.sbe.op = SLLW; // sllw
                            {7'b000_0000, 3'b101}: instruction_o.sbe.op = SRLW; // srlw
                            {7'b010_0000, 3'b101}: instruction_o.sbe.op = SRAW; // sraw
                            // Multiplications
                            {7'b000_0001, 3'b000}: instruction_o.sbe.op = MULW;
                            {7'b000_0001, 3'b100}: instruction_o.sbe.op = DIVW;
                            {7'b000_0001, 3'b101}: instruction_o.sbe.op = DIVUW;
                            {7'b000_0001, 3'b110}: instruction_o.sbe.op = REMW;
                            {7'b000_0001, 3'b111}: instruction_o.sbe.op = REMUW;
                            default: illegal_instr = 1'b1;
                        endcase
                end
                // --------------------------------
                // Reg-Immediate Operations
                // --------------------------------
                OPCODE_OPIMM: begin
                    instruction_o.sbe.fu  = ALU;
                    imm_select = IIMM;
                    instruction_o.sbe.rs1 = instr.itype.rs1;
                    instruction_o.sbe.rd  = instr.itype.rd;

                    unique case (instr.itype.funct3)
                        3'b000: instruction_o.sbe.op = ADD;   // Add Immediate
                        3'b010: instruction_o.sbe.op = SLTS;  // Set to one if Lower Than Immediate
                        3'b011: instruction_o.sbe.op = SLTU;  // Set to one if Lower Than Immediate Unsigned
                        3'b100: instruction_o.sbe.op = XORL;  // Exclusive Or with Immediate
                        3'b110: instruction_o.sbe.op = ORL;   // Or with Immediate
                        3'b111: instruction_o.sbe.op = ANDL;  // And with Immediate

                        3'b001: begin
                          instruction_o.sbe.op = SLL;  // Shift Left Logical by Immediate
                          if (instr.instr[31:26] != 6'b0)
                            illegal_instr = 1'b1;
                        end

                        3'b101: begin
                            if (instr.instr[31:26] == 6'b0)
                                instruction_o.sbe.op = SRL;  // Shift Right Logical by Immediate
                            else if (instr.instr[31:26] == 6'b010_000)
                                instruction_o.sbe.op = SRA;  // Shift Right Arithmetically by Immediate
                            else
                                illegal_instr = 1'b1;
                        end
                    endcase
                end

                // --------------------------------
                // 32 bit Reg-Immediate Operations
                // --------------------------------
                OPCODE_OPIMM32: begin
                    instruction_o.sbe.fu  = ALU;
                    imm_select = IIMM;
                    instruction_o.sbe.rs1 = instr.itype.rs1;
                    instruction_o.sbe.rd  = instr.itype.rd;

                    unique case (instr.itype.funct3)
                        3'b000: instruction_o.sbe.op = ADDW;  // Add Immediate

                        3'b001: begin
                          instruction_o.sbe.op = SLLW;  // Shift Left Logical by Immediate
                          if (instr.instr[31:25] != 7'b0)
                              illegal_instr = 1'b1;
                        end

                        3'b101: begin
                            if (instr.instr[31:25] == 7'b0)
                                instruction_o.sbe.op = SRLW;  // Shift Right Logical by Immediate
                            else if (instr.instr[31:25] == 7'b010_0000)
                                instruction_o.sbe.op = SRAW;  // Shift Right Arithmetically by Immediate
                            else
                                illegal_instr = 1'b1;
                        end

                        default: illegal_instr = 1'b1;
                    endcase
                end
                // --------------------------------
                // LSU
                // --------------------------------
                OPCODE_STORE: begin
                    instruction_o.sbe.fu  = STORE;
                    imm_select = SIMM;
                    instruction_o.sbe.rs1  = instr.stype.rs1;
                    instruction_o.sbe.rs2  = instr.stype.rs2;
                    // determine store size
                    unique case (instr.stype.funct3)
                        3'b000: instruction_o.sbe.op  = SB;
                        3'b001: instruction_o.sbe.op  = SH;
                        3'b010: instruction_o.sbe.op  = SW;
                        3'b011: instruction_o.sbe.op  = SD;
                        default: illegal_instr = 1'b1;
                    endcase
                end

                OPCODE_LOAD: begin
                    instruction_o.sbe.fu  = LOAD;
                    imm_select = IIMM;
                    instruction_o.sbe.rs1 = instr.itype.rs1;
                    instruction_o.sbe.rd  = instr.itype.rd;
                    // determine load size and signed type
                    unique case (instr.itype.funct3)
                        3'b000: instruction_o.sbe.op  = LB;
                        3'b001: instruction_o.sbe.op  = LH;
                        3'b010: instruction_o.sbe.op  = LW;
                        3'b100: instruction_o.sbe.op  = LBU;
                        3'b101: instruction_o.sbe.op  = LHU;
                        3'b110: instruction_o.sbe.op  = LWU;
                        3'b011: instruction_o.sbe.op  = LD;
                        default: illegal_instr = 1'b1;
                    endcase
                end

                `ifdef ENABLE_ATOMICS
                OPCODE_AMO: begin
                    // we are going to use the load unit for AMOs
                    instruction_o.sbe.fu  = LOAD;
                    instruction_o.sbe.rd  = instr.stype.imm0;
                    instruction_o.sbe.rs1 = instr.itype.rs1;
                    // words
                    if (instr.stype.funct3 == 3'h2) begin
                        unique case (instr.instr[31:27])
                            5'h0:  instruction_o.sbe.op = AMO_ADDW;
                            5'h1:  instruction_o.sbe.op = AMO_SWAPW;
                            5'h2:  instruction_o.sbe.op = AMO_LRW;
                            5'h3:  instruction_o.sbe.op = AMO_SCW;
                            5'h4:  instruction_o.sbe.op = AMO_XORW;
                            5'h8:  instruction_o.sbe.op = AMO_ORW;
                            5'hC:  instruction_o.sbe.op = AMO_ANDW;
                            5'h10: instruction_o.sbe.op = AMO_MINW;
                            5'h14: instruction_o.sbe.op = AMO_MAXW;
                            5'h18: instruction_o.sbe.op = AMO_MINWU;
                            5'h1C: instruction_o.sbe.op = AMO_MAXWU;
                            default: illegal_instr = 1'b1;
                        endcase
                    // double words
                    end else if (instr.stype.funct3 == 3'h3) begin
                        unique case (instr.instr[31:27])
                            5'h0:  instruction_o.sbe.op = AMO_ADDD;
                            5'h1:  instruction_o.sbe.op = AMO_SWAPD;
                            5'h2:  instruction_o.sbe.op = AMO_LRD;
                            5'h3:  instruction_o.sbe.op = AMO_SCD;
                            5'h4:  instruction_o.sbe.op = AMO_XORD;
                            5'h8:  instruction_o.sbe.op = AMO_ORD;
                            5'hC:  instruction_o.sbe.op = AMO_ANDD;
                            5'h10: instruction_o.sbe.op = AMO_MIND;
                            5'h14: instruction_o.sbe.op = AMO_MAXD;
                            5'h18: instruction_o.sbe.op = AMO_MINDU;
                            5'h1C: instruction_o.sbe.op = AMO_MAXDU;
                            default: illegal_instr = 1'b1;
                        endcase
                    end else begin
                        illegal_instr = 1'b1;
                    end
                end
                `endif

                // --------------------------------
                // Control Flow Instructions
                // --------------------------------
                OPCODE_BRANCH: begin
                    imm_select              = SBIMM;
                    instruction_o.sbe.fu        = CTRL_FLOW;
                    instruction_o.sbe.rs1       = instr.stype.rs1;
                    instruction_o.sbe.rs2       = instr.stype.rs2;

                    is_control_flow_instr_o = 1'b1;

                    case (instr.stype.funct3)
                        3'b000: instruction_o.sbe.op = EQ;
                        3'b001: instruction_o.sbe.op = NE;
                        3'b100: instruction_o.sbe.op = LTS;
                        3'b101: instruction_o.sbe.op = GES;
                        3'b110: instruction_o.sbe.op = LTU;
                        3'b111: instruction_o.sbe.op = GEU;
                        default: begin
                            is_control_flow_instr_o = 1'b0;
                            illegal_instr           = 1'b1;
                        end
                    endcase
                end
                // Jump and link register
                OPCODE_JALR: begin
                    instruction_o.sbe.fu        = CTRL_FLOW;
                    instruction_o.sbe.op        = JALR;
                    instruction_o.sbe.rs1       = instr.itype.rs1;
                    imm_select              = IIMM;
                    instruction_o.sbe.rd        = instr.itype.rd;
                    is_control_flow_instr_o = 1'b1;
                    // invalid jump and link register -> reserved for vector encoding
                    if (instr.itype.funct3 != 3'b0)
                        illegal_instr = 1'b1;
                end
                // Jump and link
                OPCODE_JAL: begin
                    instruction_o.sbe.fu        = CTRL_FLOW;
                    imm_select              = JIMM;
                    instruction_o.sbe.rd        = instr.utype.rd;
                    is_control_flow_instr_o = 1'b1;
                end

                OPCODE_AUIPC: begin
                    instruction_o.sbe.fu     = ALU;
                    imm_select           = UIMM;
                    instruction_o.sbe.use_pc = 1'b1;
                    instruction_o.sbe.rd     = instr.utype.rd;
                end

                OPCODE_LUI: begin
                    imm_select           = UIMM;
                    instruction_o.sbe.fu     = ALU;
                    instruction_o.sbe.rd     = instr.utype.rd;
                end

                default: illegal_instr = 1'b1;
            endcase
        end
    end
    // --------------------------------
    // Sign extend immediate
    // --------------------------------
    always_comb begin : sign_extend
        imm_i_type  = { {52 {instruction_i[31]}}, instruction_i[31:20] };
        imm_iz_type = {  52'b0, instruction_i[31:20] };
        imm_s_type  = { {52 {instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7] };
        imm_sb_type = { {51 {instruction_i[31]}}, instruction_i[31], instruction_i[7], instruction_i[30:25], instruction_i[11:8], 1'b0 };
        imm_u_type  = { {32 {instruction_i[31]}}, instruction_i[31:12], 12'b0 }; // JAL, AUIPC, sign extended to 64 bit
        imm_uj_type = { {44 {instruction_i[31]}}, instruction_i[19:12], instruction_i[20], instruction_i[30:21], 1'b0 };
        imm_s2_type = { 59'b0, instruction_i[24:20] };
        imm_bi_type = { {59{instruction_i[24]}}, instruction_i[24:20] };
        imm_s3_type = { 59'b0, instruction_i[29:25] };
        imm_vs_type = { {58 {instruction_i[24]}}, instruction_i[24:20], instruction_i[25] };
        imm_vu_type = { 58'b0, instruction_i[24:20], instruction_i[25] };

        // NOIMM, PCIMM, IIMM, SIMM, BIMM, BIMM, UIMM, JIMM
        // select immediate
        case (imm_select)
            PCIMM: begin
                instruction_o.sbe.result = pc_i;
                instruction_o.sbe.use_imm = 1'b1;
            end
            IIMM: begin
                instruction_o.sbe.result = imm_i_type;
                instruction_o.sbe.use_imm = 1'b1;
            end
            SIMM: begin
                instruction_o.sbe.result = imm_s_type;
                instruction_o.sbe.use_imm = 1'b1;
            end
            SBIMM: begin
                instruction_o.sbe.result = imm_sb_type;
                instruction_o.sbe.use_imm = 1'b1;
            end
            BIMM: begin
                instruction_o.sbe.result = imm_bi_type;
                instruction_o.sbe.use_imm = 1'b1;
            end
            UIMM: begin
                instruction_o.sbe.result = imm_u_type;
                instruction_o.sbe.use_imm = 1'b1;
            end
            JIMM: begin
                instruction_o.sbe.result = imm_uj_type;
                instruction_o.sbe.use_imm = 1'b1;
            end
            default: begin
                instruction_o.sbe.result = 64'b0;
                instruction_o.sbe.use_imm = 1'b0;
            end
        endcase
    end

    // ---------------------
    // Exception handling
    // ---------------------
    always_comb begin : exception_handling
        instruction_o.sbe.ex      = ex_i;
        instruction_o.sbe.valid   = ex_i.valid;
        // look if we didn't already get an exception in any previous
        // stage - we should not overwrite it as we retain order regarding the exception
        if (~ex_i.valid) begin
            // if we didn't already get an exception save the instruction here as we may need it
            // in the commit stage if we got a access exception to one of the CSR registers
            instruction_o.sbe.ex.tval  = instruction_i;
            // instructions which will throw an exception are marked as valid
            // e.g.: they can be committed anytime and do not need to wait for any functional unit
            // check here if we decoded an invalid instruction or if the compressed decoder already decoded
            // a invalid instruction
            if (illegal_instr || is_illegal_i) begin
                instruction_o.sbe.valid    = 1'b1;
                instruction_o.sbe.ex.valid = 1'b1;
                // we decoded an illegal exception here
                instruction_o.sbe.ex.cause = ILLEGAL_INSTR;
            // we got an ecall, set the correct cause depending on the current privilege level
            end else if (ecall) begin
                // this instruction has already executed
                instruction_o.sbe.valid    = 1'b1;
                // this exception is valid
                instruction_o.sbe.ex.valid = 1'b1;
                // depending on the privilege mode, set the appropriate cause
                case (priv_lvl_i)
                    PRIV_LVL_M: instruction_o.sbe.ex.cause = ENV_CALL_MMODE;
                    PRIV_LVL_S: instruction_o.sbe.ex.cause = ENV_CALL_SMODE;
                    PRIV_LVL_U: instruction_o.sbe.ex.cause = ENV_CALL_UMODE;
                    default:; // this should not happen
                endcase
            end else if (ebreak) begin
                // this instruction has already executed
                instruction_o.sbe.valid    = 1'b1;
                // this exception is valid
                instruction_o.sbe.ex.valid = 1'b1;
                // set breakpoint cause
                instruction_o.sbe.ex.cause = BREAKPOINT;
            end
        end
    end
endmodule

module id_stage_testbench;
    logic                                     clk_i;     // Clock
    logic                                     rst_ni;    // Asynchronous reset active low

    logic                                     flush_i;
    // from IF
   fetch_entry_t                             fetch_entry_i_0;

	fetch_entry_t                             fetch_entry_i_1;

	fetch_entry_t                             fetch_entry_i_2;

	fetch_entry_t                             fetch_entry_i_3;
    logic                                     fetch_entry_valid_i_0;
	logic                                     fetch_entry_valid_i_1;
	logic                                     fetch_entry_valid_i_2;
	logic                                     fetch_entry_valid_i_3;
    logic                                     decoded_instr_ack_o_0;
	logic                                     decoded_instr_ack_o_1;
	logic                                     decoded_instr_ack_o_2;
	logic                                     decoded_instr_ack_o_3;	// acknowledge the instruction (fetch entry)

    // to ID
    decoded_entry_t                        	  issue_entry_o_0;
	decoded_entry_t                       	  issue_entry_o_1;
	decoded_entry_t                       	  issue_entry_o_2;
	decoded_entry_t                       	  issue_entry_o_3;	// a decoded instruction
    logic                                     issue_entry_valid_o_0; // issue entry is valid
	logic                                     issue_entry_valid_o_1;
	logic                                     issue_entry_valid_o_2;
	logic                                     issue_entry_valid_o_3;
    logic                                     is_ctrl_flow_o_0;      // the instruction we issue is a ctrl flow instructions
	logic                                     is_ctrl_flow_o_1;
	logic                                     is_ctrl_flow_o_2;
	logic                                     is_ctrl_flow_o_3;
    logic                                     issue_instr_ack_i_0;   // issue stage acknowledged sampling of instructions
	logic                                     issue_instr_ack_i_1;
	logic                                     issue_instr_ack_i_2;
	logic                                     issue_instr_ack_i_3;
    // from CSR file
    priv_lvl_t                                priv_lvl_i_0;          // current privilege level
	priv_lvl_t                                priv_lvl_i_1;
	priv_lvl_t                                priv_lvl_i_2;
	priv_lvl_t                                priv_lvl_i_3;
    logic                                     tvm_i_0;
	logic                                     tvm_i_1;
	logic                                     tvm_i_2;
	logic                                     tvm_i_3;
    logic                                     tw_i_0;
	logic                                     tw_i_1;
	logic                                     tw_i_2;
	logic                                     tw_i_3;
    logic                                     tsr_i_0;
	logic                                     tsr_i_1;
	logic                                     tsr_i_2;
	logic                                     tsr_i_3;
	
	id_stage dut(.*);
    
	parameter CLOCK_PERIOD=1000;
     initial begin
     clk_i <= 0;
     forever #(CLOCK_PERIOD/2) clk_i <= ~clk_i;
     end
     integer i;
     // Set up the inputs to the design. Each line is a clock cycle.
     initial begin
     rst_ni <= 0;@(posedge clk_i);
	 rst_ni <= 1;@(posedge clk_i);
	 @(posedge clk_i);
	 @(posedge clk_i);
	 @(posedge clk_i);
	 @(posedge clk_i);
	 @(posedge clk_i);
     $stop; // End the simulation.
     end
endmodule

