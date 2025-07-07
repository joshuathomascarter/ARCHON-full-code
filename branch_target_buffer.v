

// ===============================================================================
// Branch Target Buffer (BTB) Module
// Features:
// - Stores predicted next PC for branches.
// - Improves pipeline performance by reducing branch prediction penalty.
// - Updates on misprediction.
// ===============================================================================
module branch_target_buffer(
    input wire clk,
    input wire reset,
    input wire [3:0] pc_in,             // Current PC to check for prediction
    input wire [3:0] branch_resolved_pc, // PC of branch instruction whose outcome is resolved
    input wire branch_resolved_pc_valid, // Indicates if branch_resolved_pc is valid
    input wire [3:0] branch_resolved_target_pc, // Actual target PC of the resolved branch
    input wire branch_resolved_taken, // Actual outcome of the resolved branch (taken/not taken)

    output wire [3:0] predicted_next_pc, // Predicted next PC
    output wire predicted_taken         // Predicted branch outcome (taken/not taken)
);

    // Simple BTB: Stores target PC for each instruction address
    // Each entry: {predicted_taken_bit, predicted_target_pc[3:0]}
    reg [4:0] btb_table [0:15]; // 16 entries, 5 bits each (1 for taken, 4 for PC)

    integer i; // Moved loop variable declaration to module scope

    initial begin
        // Initialize BTB (e.g., all not taken, target PC is 0)
        for (i = 0; i < 16; i = i + 1) begin // Corrected loop variable declaration
            btb_table[i] = 5'b0_0000;
        end
    end

    // Prediction logic (combinational read)
    assign predicted_next_pc = btb_table[pc_in][3:0];
    assign predicted_taken = btb_table[pc_in][4];

    // Update logic (synchronous write)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin // Corrected loop variable declaration
                btb_table[i] = 5'b0_0000;
            end
        end else begin
            if (branch_resolved_pc_valid) begin
                // Update BTB entry for the resolved branch
                btb_table[branch_resolved_pc] <= {branch_resolved_taken, branch_resolved_target_pc};
            end
        end
    end

endmodule

