// =====================================================================
// Enhanced Instruction Memory Module
// Features:
// - Stores 16 instructions (expandable to more if needed)
// - Uses a 4-bit program counter for addressing
// - Outputs the full instr_opcode for CPU execution
// - Optional reset capability with NOP instruction at PC=0
// =====================================================================

module instruction_ram(
    input wire clk,             // Clock signal (for synchronous read if needed)
    input wire reset,           // Reset signal
    input wire [3:0] pc_in,     // 4-bit Program Counter input
    output wire [15:0] instr_opcode // 16-bit instruction output
);

    // Instruction Memory (16 instructions of 16 bits each)
    reg [15:0] imem [0:15];

    integer i; // Moved loop variable declaration to module scope

    initial begin
        // Initialize instruction memory with a sample program
        // This program is for demonstration. Replace with actual program.
        // Assume opcode format: [opcode (4)|rd (3)|rs1 (3)|rs2 (3)|imm (3)] for R-type/I-type
        // Or [opcode (4)|branch_target (12)] for J-type
        // Or [opcode (4)|rs1 (3)|imm (9)] for Load/Store etc.

        for (i = 0; i < 16; i = i + 1) begin // Corrected loop variable declaration
            imem[i] = 16'h0000; // Initialize all to NOP or 0
        end
        imem[0] = 16'h1234; // ADD R1, R2, R3 (opcode 1, rd=1, rs1=2, rs2=3) - Placeholder
        imem[1] = 16'h2452; // ADDI R4, R5, #2 (opcode 2, rd=4, rs1=5, imm=2) - Placeholder
        imem[2] = 16'h3678; // SUB R6, R7, R8 - Placeholder
        imem[3] = 16'h4891; // LD R8, (R9 + #1) - Placeholder
        imem[4] = 16'h5ABA; // ST R10, (R11 + #10) - Placeholder
        imem[5] = 16'h6CDE; // XOR R12, R13, R14 - Placeholder
        imem[6] = 16'h7F01; // BEQ R15, R0, +1 (branch if R15 == R0, to PC+1) - Placeholder
        imem[7] = 16'h8002; // JUMP PC+2 (unconditional jump) - Placeholder
        imem[8] = 16'h9123; // NOP - Placeholder
        imem[9] = 16'h0000; // NOP - Placeholder
        imem[10] = 16'h0000; // NOP - Placeholder
        imem[11] = 16'h0000; // NOP - Placeholder
        imem[12] = 16'h0000; // NOP - Placeholder
        imem[13] = 16'h0000; // NOP - Placeholder
        imem[14] = 16'h0000; // NOP - Placeholder
        imem[15] = 16'h0000; // NOP - Placeholder
    end

    // Instruction fetch logic
    assign instr_opcode = imem[pc_in];

endmodule

