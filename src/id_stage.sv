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

import ariane_pkg::*;

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
        instruction_o.decoded.pc            = pc_i;
        instruction_o.decoded.fu            = NONE;
        instruction_o.decoded.op            = ADD;
        instruction_o.decoded.rs1           = 7'b0;
        instruction_o.decoded.rs2           = 7'b0;
        instruction_o.decoded.rd            = 7'b0;
        instruction_o.decoded.use_pc        = 1'b0;
        instruction_o.decoded.trans_id      = 4'b0;
        instruction_o.decoded.is_compressed = is_compressed_i;
        instruction_o.decoded.use_zimm      = 1'b0;
        instruction_o.decoded.bp            = branch_predict_i;
        ecall                       = 1'b0;
        ebreak                      = 1'b0;

        if (~ex_i.valid) begin
            case (instr.rtype.opcode)
                OPCODE_SYSTEM: begin
                    instruction_o.decoded.fu  = CSR;
                    instruction_o.decoded.rs1 = {2'b0, instr.itype.rs1};
                    instruction_o.decoded.rd  = {2'b0, instr.itype.rd};

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
                                    instruction_o.decoded.op = SRET;
                                    // check privilege level, SRET can only be executed in S and M mode
                                    // we'll just decode an illegal instruction if we are in the wrong privilege level
                                    if (priv_lvl_i == PRIV_LVL_U) begin
                                        illegal_instr = 1'b1;
                                        //  do not change privilege level if this is an illegal instruction
                                        instruction_o.decoded.op = ADD;
                                    end
                                    // if we are in S-Mode and Trap SRET (tsr) is set -> trap on illegal instruction
                                    if (priv_lvl_i == PRIV_LVL_S && tsr_i) begin
                                        illegal_instr = 1'b1;
                                        //  do not change privilege level if this is an illegal instruction
                                       instruction_o.decoded.op = ADD;
                                    end
                                end
                                // MRET
                                12'b1100000010: begin
                                    instruction_o.decoded.op = MRET;
                                    // check privilege level, MRET can only be executed in M mode
                                    // otherwise we decode an illegal instruction
                                    if (priv_lvl_i inside {PRIV_LVL_U, PRIV_LVL_S})
                                        illegal_instr = 1'b1;
                                end
                                // WFI
                                12'b1_0000_0101: begin
                                    instruction_o.decoded.op = WFI;
                                    // if timeout wait is set, trap on an illegal instruction in S Mode
                                    // (after 0 cycles timeout)
                                    if (priv_lvl_i == PRIV_LVL_S && tw_i) begin
                                        illegal_instr = 1'b1;
                                        instruction_o.decoded.op = ADD;
                                    end
                                    // we don't support U mode interrupts so WFI is illegal in this context
                                    if (priv_lvl_i == PRIV_LVL_U) begin
                                        illegal_instr = 1'b1;
                                        instruction_o.decoded.op = ADD;
                                    end
                                end
                                // SFENCE.VMA
                                default: begin
                                    if (instr.instr[31:25] == 7'b1001) begin
                                        // Reset illegal instruction here, this is the only type
                                        // of instruction which needs those kind of fields
                                        illegal_instr    = 1'b0;
                                        instruction_o.decoded.op = SFENCE_VMA;
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
                            instruction_o.decoded.op = CSR_WRITE;
                        end
                        // atomically set values in the CSR and write back to rd
                        3'b010: begin// CSRRS
                            imm_select = IIMM;
                            // this is just a read
                            if (instr.itype.rs1 == 5'b0)
                                instruction_o.decoded.op = CSR_READ;
                            else
                                instruction_o.decoded.op = CSR_SET;
                        end
                        // atomically clear values in the CSR and write back to rd
                        3'b011: begin// CSRRC
                            imm_select = IIMM;
                            // this is just a read
                            if (instr.itype.rs1 == 5'b0)
                                instruction_o.decoded.op = CSR_READ;
                            else
                                instruction_o.decoded.op = CSR_CLEAR;
                        end
                        // use zimm and iimm
                        3'b101: begin// CSRRWI
                            instruction_o.decoded.rs1 = {2'b0, instr.itype.rs1};
                            imm_select = IIMM;
                            instruction_o.decoded.use_zimm = 1'b1;
                            instruction_o.decoded.op = CSR_WRITE;
                        end
                        3'b110: begin// CSRRSI
                            instruction_o.decoded.rs1 = {2'b0, instr.itype.rs1};
                            imm_select = IIMM;
                            instruction_o.decoded.use_zimm = 1'b1;
                            // this is just a read
                            if (instr.itype.rs1 == 5'b0)
                                instruction_o.decoded.op = CSR_READ;
                            else
                                instruction_o.decoded.op = CSR_SET;
                        end
                        3'b111: begin// CSRRCI
                            instruction_o.decoded.rs1 = {2'b0, instr.itype.rs1};
                            imm_select = IIMM;
                            instruction_o.decoded.use_zimm = 1'b1;
                            // this is just a read
                            if (instr.itype.rs1 == 5'b0)
                                instruction_o.decoded.op = CSR_READ;
                            else
                                instruction_o.decoded.op = CSR_CLEAR;
                        end
                        default: illegal_instr = 1'b1;
                    endcase
                end
                // Memory ordering instructions
                OPCODE_FENCE: begin
                    instruction_o.decoded.fu  = CSR;
                    instruction_o.decoded.rs1 = '0;
                    instruction_o.decoded.rs2 = '0;
                    instruction_o.decoded.rd  = '0;

                    case (instr.stype.funct3)
                        // FENCE
                        // Currently implemented as a whole DCache flush boldly ignoring other things
                        3'b000: instruction_o.decoded.op  = FENCE;
                        // FENCE.I
                        3'b001: begin
                            if (instr.instr[31:20] != '0)
                                illegal_instr = 1'b1;
                            instruction_o.decoded.op  = FENCE_I;
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
                    instruction_o.decoded.fu  = (instr.rtype.funct7 == 7'b000_0001) ? MULT : ALU;
                    instruction_o.decoded.rs1 = {2'b0, instr.rtype.rs1};
                    instruction_o.decoded.rs2 = {2'b0, instr.rtype.rs2};
                    instruction_o.decoded.rd  = {2'b0, instr.rtype.rd};

                    unique case ({instr.rtype.funct7, instr.rtype.funct3})
                        {7'b000_0000, 3'b000}: instruction_o.decoded.op = ADD;   // Add
                        {7'b010_0000, 3'b000}: instruction_o.decoded.op = SUB;   // Sub
                        {7'b000_0000, 3'b010}: instruction_o.decoded.op = SLTS;  // Set Lower Than
                        {7'b000_0000, 3'b011}: instruction_o.decoded.op = SLTU;  // Set Lower Than Unsigned
                        {7'b000_0000, 3'b100}: instruction_o.decoded.op = XORL;  // Xor
                        {7'b000_0000, 3'b110}: instruction_o.decoded.op = ORL;   // Or
                        {7'b000_0000, 3'b111}: instruction_o.decoded.op = ANDL;  // And
                        {7'b000_0000, 3'b001}: instruction_o.decoded.op = SLL;   // Shift Left Logical
                        {7'b000_0000, 3'b101}: instruction_o.decoded.op = SRL;   // Shift Right Logical
                        {7'b010_0000, 3'b101}: instruction_o.decoded.op = SRA;   // Shift Right Arithmetic
                        // Multiplications
                        {7'b000_0001, 3'b000}: instruction_o.decoded.op = MUL;
                        {7'b000_0001, 3'b001}: instruction_o.decoded.op = MULH;
                        {7'b000_0001, 3'b010}: instruction_o.decoded.op = MULHSU;
                        {7'b000_0001, 3'b011}: instruction_o.decoded.op = MULHU;
                        {7'b000_0001, 3'b100}: instruction_o.decoded.op = DIV;
                        {7'b000_0001, 3'b101}: instruction_o.decoded.op = DIVU;
                        {7'b000_0001, 3'b110}: instruction_o.decoded.op = REM;
                        {7'b000_0001, 3'b111}: instruction_o.decoded.op = REMU;
                        default: begin
                            illegal_instr = 1'b1;
                        end
                    endcase
                end

                // --------------------------
                // 32bit Reg-Reg Operations
                // --------------------------
                OPCODE_OP32: begin
                    instruction_o.decoded.fu  = (instr.rtype.funct7 == 7'b000_0001) ? MULT : ALU;
                    instruction_o.decoded.rs1 = {2'b0, instr.rtype.rs1};
                    instruction_o.decoded.rs2 = {2'b0, instr.rtype.rs2};
                    instruction_o.decoded.rd  = {2'b0, instr.rtype.rd};

                        unique case ({instr.rtype.funct7, instr.rtype.funct3})
                            {7'b000_0000, 3'b000}: instruction_o.decoded.op = ADDW; // addw
                            {7'b010_0000, 3'b000}: instruction_o.decoded.op = SUBW; // subw
                            {7'b000_0000, 3'b001}: instruction_o.decoded.op = SLLW; // sllw
                            {7'b000_0000, 3'b101}: instruction_o.decoded.op = SRLW; // srlw
                            {7'b010_0000, 3'b101}: instruction_o.decoded.op = SRAW; // sraw
                            // Multiplications
                            {7'b000_0001, 3'b000}: instruction_o.decoded.op = MULW;
                            {7'b000_0001, 3'b100}: instruction_o.decoded.op = DIVW;
                            {7'b000_0001, 3'b101}: instruction_o.decoded.op = DIVUW;
                            {7'b000_0001, 3'b110}: instruction_o.decoded.op = REMW;
                            {7'b000_0001, 3'b111}: instruction_o.decoded.op = REMUW;
                            default: illegal_instr = 1'b1;
                        endcase
                end
                // --------------------------------
                // Reg-Immediate Operations
                // --------------------------------
                OPCODE_OPIMM: begin
                    instruction_o.decoded.fu  = ALU;
                    imm_select = IIMM;
                    instruction_o.decoded.rs1 = {2'b0, instr.itype.rs1};
                    instruction_o.decoded.rd  = {2'b0, instr.itype.rd};

                    unique case (instr.itype.funct3)
                        3'b000: instruction_o.decoded.op = ADD;   // Add Immediate
                        3'b010: instruction_o.decoded.op = SLTS;  // Set to one if Lower Than Immediate
                        3'b011: instruction_o.decoded.op = SLTU;  // Set to one if Lower Than Immediate Unsigned
                        3'b100: instruction_o.decoded.op = XORL;  // Exclusive Or with Immediate
                        3'b110: instruction_o.decoded.op = ORL;   // Or with Immediate
                        3'b111: instruction_o.decoded.op = ANDL;  // And with Immediate

                        3'b001: begin
                          instruction_o.decoded.op = SLL;  // Shift Left Logical by Immediate
                          if (instr.instr[31:26] != 6'b0)
                            illegal_instr = 1'b1;
                        end

                        3'b101: begin
                            if (instr.instr[31:26] == 6'b0)
                                instruction_o.decoded.op = SRL;  // Shift Right Logical by Immediate
                            else if (instr.instr[31:26] == 6'b010_000)
                                instruction_o.decoded.op = SRA;  // Shift Right Arithmetically by Immediate
                            else
                                illegal_instr = 1'b1;
                        end
                    endcase
                end

                // --------------------------------
                // 32 bit Reg-Immediate Operations
                // --------------------------------
                OPCODE_OPIMM32: begin
                    instruction_o.decoded.fu  = ALU;
                    imm_select = IIMM;
                    instruction_o.decoded.rs1 = {2'b0, instr.itype.rs1};
                    instruction_o.decoded.rd  = {2'b0, instr.itype.rd};

                    unique case (instr.itype.funct3)
                        3'b000: instruction_o.decoded.op = ADDW;  // Add Immediate

                        3'b001: begin
                          instruction_o.decoded.op = SLLW;  // Shift Left Logical by Immediate
                          if (instr.instr[31:25] != 7'b0)
                              illegal_instr = 1'b1;
                        end

                        3'b101: begin
                            if (instr.instr[31:25] == 7'b0)
                                instruction_o.decoded.op = SRLW;  // Shift Right Logical by Immediate
                            else if (instr.instr[31:25] == 7'b010_0000)
                                instruction_o.decoded.op = SRAW;  // Shift Right Arithmetically by Immediate
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
                    instruction_o.decoded.fu  = STORE;
                    imm_select = SIMM;
                    instruction_o.decoded.rs1  = {2'b0, instr.stype.rs1};
                    instruction_o.decoded.rs2  = {2'b0, instr.stype.rs2};
                    // determine store size
                    unique case (instr.stype.funct3)
                        3'b000: instruction_o.decoded.op  = SB;
                        3'b001: instruction_o.decoded.op  = SH;
                        3'b010: instruction_o.decoded.op  = SW;
                        3'b011: instruction_o.decoded.op  = SD;
                        default: illegal_instr = 1'b1;
                    endcase
                end

                OPCODE_LOAD: begin
                    instruction_o.decoded.fu  = LOAD;
                    imm_select = IIMM;
                    instruction_o.decoded.rs1 = {2'b0, instr.itype.rs1};
                    instruction_o.decoded.rd  = {2'b0, instr.itype.rd};
                    // determine load size and signed type
                    unique case (instr.itype.funct3)
                        3'b000: instruction_o.decoded.op  = LB;
                        3'b001: instruction_o.decoded.op  = LH;
                        3'b010: instruction_o.decoded.op  = LW;
                        3'b100: instruction_o.decoded.op  = LBU;
                        3'b101: instruction_o.decoded.op  = LHU;
                        3'b110: instruction_o.decoded.op  = LWU;
                        3'b011: instruction_o.decoded.op  = LD;
                        default: illegal_instr = 1'b1;
                    endcase
                end

                `ifdef ENABLE_ATOMICS
                OPCODE_AMO: begin
                    // we are going to use the load unit for AMOs
                    instruction_o.decoded.fu  = LOAD;
                    instruction_o.decoded.rd  = instr.stype.imm0;
                    instruction_o.decoded.rs1 = {2'b0, instr.itype.rs1};
                    // words
                    if (instr.stype.funct3 == 3'h2) begin
                        unique case (instr.instr[31:27])
                            5'h0:  instruction_o.decoded.op = AMO_ADDW;
                            5'h1:  instruction_o.decoded.op = AMO_SWAPW;
                            5'h2:  instruction_o.decoded.op = AMO_LRW;
                            5'h3:  instruction_o.decoded.op = AMO_SCW;
                            5'h4:  instruction_o.decoded.op = AMO_XORW;
                            5'h8:  instruction_o.decoded.op = AMO_ORW;
                            5'hC:  instruction_o.decoded.op = AMO_ANDW;
                            5'h10: instruction_o.decoded.op = AMO_MINW;
                            5'h14: instruction_o.decoded.op = AMO_MAXW;
                            5'h18: instruction_o.decoded.op = AMO_MINWU;
                            5'h1C: instruction_o.decoded.op = AMO_MAXWU;
                            default: illegal_instr = 1'b1;
                        endcase
                    // double words
                    end else if (instr.stype.funct3 == 3'h3) begin
                        unique case (instr.instr[31:27])
                            5'h0:  instruction_o.decoded.op = AMO_ADDD;
                            5'h1:  instruction_o.decoded.op = AMO_SWAPD;
                            5'h2:  instruction_o.decoded.op = AMO_LRD;
                            5'h3:  instruction_o.decoded.op = AMO_SCD;
                            5'h4:  instruction_o.decoded.op = AMO_XORD;
                            5'h8:  instruction_o.decoded.op = AMO_ORD;
                            5'hC:  instruction_o.decoded.op = AMO_ANDD;
                            5'h10: instruction_o.decoded.op = AMO_MIND;
                            5'h14: instruction_o.decoded.op = AMO_MAXD;
                            5'h18: instruction_o.decoded.op = AMO_MINDU;
                            5'h1C: instruction_o.decoded.op = AMO_MAXDU;
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
                    instruction_o.decoded.fu        = CTRL_FLOW;
                    instruction_o.decoded.rs1       = {2'b0, instr.stype.rs1};
                    instruction_o.decoded.rs2       = {2'b0, instr.stype.rs2};

                    is_control_flow_instr_o = 1'b1;

                    case (instr.stype.funct3)
                        3'b000: instruction_o.decoded.op = EQ;
                        3'b001: instruction_o.decoded.op = NE;
                        3'b100: instruction_o.decoded.op = LTS;
                        3'b101: instruction_o.decoded.op = GES;
                        3'b110: instruction_o.decoded.op = LTU;
                        3'b111: instruction_o.decoded.op = GEU;
                        default: begin
                            is_control_flow_instr_o = 1'b0;
                            illegal_instr           = 1'b1;
                        end
                    endcase
                end
                // Jump and link register
                OPCODE_JALR: begin
                    instruction_o.decoded.fu        = CTRL_FLOW;
                    instruction_o.decoded.op        = JALR;
                    instruction_o.decoded.rs1       = {2'b0, instr.itype.rs1};
                    imm_select              = IIMM;
                    instruction_o.decoded.rd        = {2'b0, instr.itype.rd};
                    is_control_flow_instr_o = 1'b1;
                    // invalid jump and link register -> reserved for vector encoding
                    if (instr.itype.funct3 != 3'b0)
                        illegal_instr = 1'b1;
                end
                // Jump and link
                OPCODE_JAL: begin
                    instruction_o.decoded.fu        = CTRL_FLOW;
                    imm_select              = JIMM;
                    instruction_o.decoded.rd        = {2'b0, instr.utype.rd};
                    is_control_flow_instr_o = 1'b1;
                end

                OPCODE_AUIPC: begin
                    instruction_o.decoded.fu     = ALU;
                    imm_select           = UIMM;
                    instruction_o.decoded.use_pc = 1'b1;
                    instruction_o.decoded.rd     = {2'b0, instr.utype.rd};
                end

                OPCODE_LUI: begin
                    imm_select           = UIMM;
                    instruction_o.decoded.fu     = ALU;
                    instruction_o.decoded.rd     = {2'b0, instr.utype.rd};
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
                instruction_o.decoded.result = pc_i;
                instruction_o.decoded.use_imm = 1'b1;
            end
            IIMM: begin
                instruction_o.decoded.result = imm_i_type;
                instruction_o.decoded.use_imm = 1'b1;
            end
            SIMM: begin
                instruction_o.decoded.result = imm_s_type;
                instruction_o.decoded.use_imm = 1'b1;
            end
            SBIMM: begin
                instruction_o.decoded.result = imm_sb_type;
                instruction_o.decoded.use_imm = 1'b1;
            end
            BIMM: begin
                instruction_o.decoded.result = imm_bi_type;
                instruction_o.decoded.use_imm = 1'b1;
            end
            UIMM: begin
                instruction_o.decoded.result = imm_u_type;
                instruction_o.decoded.use_imm = 1'b1;
            end
            JIMM: begin
                instruction_o.decoded.result = imm_uj_type;
                instruction_o.decoded.use_imm = 1'b1;
            end
            default: begin
                instruction_o.decoded.result = 64'b0;
                instruction_o.decoded.use_imm = 1'b0;
            end
        endcase
    end

    // ---------------------
    // Exception handling
    // ---------------------
    always_comb begin : exception_handling
        instruction_o.decoded.ex      = ex_i;
        instruction_o.decoded.valid   = ex_i.valid;
        // look if we didn't already get an exception in any previous
        // stage - we should not overwrite it as we retain order regarding the exception
        if (~ex_i.valid) begin
            // if we didn't already get an exception save the instruction here as we may need it
            // in the commit stage if we got a access exception to one of the CSR registers
            instruction_o.decoded.ex.tval  = instruction_i;
            // instructions which will throw an exception are marked as valid
            // e.g.: they can be committed anytime and do not need to wait for any functional unit
            // check here if we decoded an invalid instruction or if the compressed decoder already decoded
            // a invalid instruction
            if (illegal_instr || is_illegal_i) begin
                instruction_o.decoded.valid    = 1'b1;
                instruction_o.decoded.ex.valid = 1'b1;
                // we decoded an illegal exception here
                instruction_o.decoded.ex.cause = ILLEGAL_INSTR;
            // we got an ecall, set the correct cause depending on the current privilege level
            end else if (ecall) begin
                // this instruction has already executed
                instruction_o.decoded.valid    = 1'b1;
                // this exception is valid
                instruction_o.decoded.ex.valid = 1'b1;
                // depending on the privilege mode, set the appropriate cause
                case (priv_lvl_i)
                    PRIV_LVL_M: instruction_o.decoded.ex.cause = ENV_CALL_MMODE;
                    PRIV_LVL_S: instruction_o.decoded.ex.cause = ENV_CALL_SMODE;
                    PRIV_LVL_U: instruction_o.decoded.ex.cause = ENV_CALL_UMODE;
                    default:; // this should not happen
                endcase
            end else if (ebreak) begin
                // this instruction has already executed
                instruction_o.decoded.valid    = 1'b1;
                // this exception is valid
                instruction_o.decoded.ex.valid = 1'b1;
                // set breakpoint cause
                instruction_o.decoded.ex.cause = BREAKPOINT;
            end
        end
    end
endmodule



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
        .priv_lvl_i              ( priv_lvl_i_0				     ),              // current privilege level
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
    assign issue_entry_o_0.decoded = issue_q_0.sbe;
	assign issue_entry_o_1.decoded = issue_q_1.sbe;
	assign issue_entry_o_2.decoded = issue_q_2.sbe;
	assign issue_entry_o_3.decoded = issue_q_3.sbe;
	
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
            issue_n_0 = {1'b1, decoded_instruction_0.decoded, is_control_flow_instr_0};
			issue_n_0.sbe.is_included = fetch_entry_i_0.valid;
			issue_n_0.valid = 1'b1;
        end
		if ((!issue_q_1.valid || issue_instr_ack_i_1) && fetch_entry_valid_1) begin
            fetch_ack_i_1 = 1'b1;
            issue_n_1 = {1'b1, decoded_instruction_1.decoded, is_control_flow_instr_1};
			issue_n_1.sbe.is_included = fetch_entry_i_1.valid;
			issue_n_1.valid = 1'b1;
        end
		if ((!issue_q_2.valid || issue_instr_ack_i_2) && fetch_entry_valid_2) begin
            fetch_ack_i_2 = 1'b1;
            issue_n_2 = {1'b1, decoded_instruction_2.decoded, is_control_flow_instr_2};
			issue_n_2.sbe.is_included = fetch_entry_i_2.valid;
			issue_n_2.valid = 1'b1;
        end
		if ((!issue_q_3.valid || issue_instr_ack_i_3) && fetch_entry_valid_3) begin
            fetch_ack_i_3 = 1'b1;
            issue_n_3 = {1'b1, decoded_instruction_3.decoded, is_control_flow_instr_3};
 			issue_n_3.sbe.is_included = fetch_entry_i_3.valid;
 			issue_n_3.valid = 1'b1;
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