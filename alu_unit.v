
// =====================================================================
// ALU Module (Arithmetic Logic Unit)
// Features:
// - Performs basic arithmetic and logical operations.

// =====================================================================
// ALU Module (Arithmetic Logic Unit)
// Features:
// - Performs basic arithmetic and logical operations.
// - Outputs 4-bit result and 4 flags (Zero, Negative, Carry, Overflow).
// =====================================================================
module alu_unit(
    input wire [3:0] alu_operand1, // First 4-bit operand
    input wire [3:0] alu_operand2, // Second 4-bit operand
    input wire [2:0] alu_op,       // 3-bit ALU operation code
                                   // 3'b000: ADD
                                   // 3'b001: SUB
                                   // 3'b010: AND
                                   // 3'b011: OR
                                   // 3'b100: XOR
                                   // 3'b101: SLT (Set Less Than)
                                   // Other codes can be defined for shifts, etc.
    output reg [3:0] alu_result,   // 4-bit result
    output reg zero_flag,          // Result is zero
    output reg negative_flag,      // Result is negative (MSB is 1)
    output reg carry_flag,         // Carry out from addition or borrow from subtraction
    output reg overflow_flag       // Signed overflow
);

    always @(*) begin
        alu_result = 4'h0;
        zero_flag = 1'b0;
        negative_flag = 1'b0;
        carry_flag = 1'b0;
        overflow_flag = 1'b0;

        case (alu_op)
            3'b000: begin // ADD
                alu_result = alu_operand1 + alu_operand2;
                carry_flag = (alu_operand1 + alu_operand2) > 4'b1111; // Check for unsigned carry out
                overflow_flag = ((!alu_operand1[3] && !alu_operand2[3] && alu_result[3]) || (alu_operand1[3] && alu_operand2[3] && !alu_result[3])); // Signed overflow
            end
            3'b001: begin // SUB (using 2's complement addition)
                alu_result = alu_operand1 - alu_operand2;
                carry_flag = (alu_operand1 >= alu_operand2); // For subtraction, carry_flag usually means no borrow
                overflow_flag = ((alu_operand1[3] && !alu_operand2[3] && !alu_result[3]) || (!alu_operand1[3] && alu_operand2[3] && alu_result[3])); // Signed overflow
            end
            3'b010: begin // AND
                alu_result = alu_operand1 & alu_operand2;
            end
            3'b011: begin // OR
                alu_result = alu_operand1 | alu_operand2;
            end
            3'b100: begin // XOR
                alu_result = alu_operand1 ^ alu_operand2;
            end
            3'b101: begin // SLT (Set Less Than)
                alu_result = ($signed(alu_operand1) < $signed(alu_operand2)) ? 4'h1 : 4'h0;
            end
            default: begin
                alu_result = 4'h0; // NOP or undefined
            end
        endcase

        // Common flag calculations
        if (alu_result == 4'h0)
            zero_flag = 1'b1;
        if (alu_result[3] == 1'b1) // Check MSB for signed negative
            negative_flag = 1'b1;
    end

endmodule

