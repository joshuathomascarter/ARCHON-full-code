
// ======================================================================
// Pattern Detector Module (Conceptual Higher-Order Descriptor Example)
// Enhanced Features:
// - Stores a deeper history of ALU flags using shift registers.
// - Detects MULTIPLE specific "anomalous" patterns across history.
// - Outputs a single "anomaly_detected" flag if ANY pattern matches.
// ======================================================================
module pattern_detector(
    input clk,
    input reset,
    // Current flags represent the flags from the *current* cycle's ALU output (EX stage)
    input wire zero_flag_current,
    input wire negative_flag_current,
    input wire carry_flag_current,
    input wire overflow_flag_current,

    output wire anomaly_detected_out // Corrected: Changed from 'reg' to 'wire' as it's driven by assign
);

    // History depth: We'll store current and previous 2 cycles for 3-cycle total view
    parameter HISTORY_DEPTH = 3; // For 3 cycles of data (current, prev1, prev2).

    // Shift registers for ALU flags (these must be 'reg' as they are assigned in always block)
    reg [HISTORY_DEPTH-1:0] zero_flag_history;
    reg [HISTORY_DEPTH-1:0] negative_flag_history;
    reg [HISTORY_DEPTH-1:0] carry_flag_history;
    reg [HISTORY_DEPTH-1:0] overflow_flag_history;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            zero_flag_history <= 'b0;
            negative_flag_history <= 'b0;
            carry_flag_history <= 'b0;
            overflow_flag_history <= 'b0;
            // anomaly_detected_out <= 1'b0; // Removed: 'anomaly_detected_out' is now a wire, not reg
        end else begin
            // Shift in current flags, pushing older flags out
            zero_flag_history <= {zero_flag_history[HISTORY_DEPTH-2:0], zero_flag_current};
            negative_flag_history <= {negative_flag_history[HISTORY_DEPTH-2:0], negative_flag_current};
            carry_flag_history <= {carry_flag_history[HISTORY_DEPTH-2:0], carry_flag_current};
            overflow_flag_history <= {overflow_flag_history[HISTORY_DEPTH-2:0], overflow_flag_current};
        end
    end

    // Define Multiple Anomalous Patterns (using current, prev1, prev2 flags)
    // Access: {flag_history[0]} is current, {flag_history[1]} is prev1, {flag_history[2]} is prev2

    wire pattern1_match;
    wire pattern2_match;

    // Pattern 1: (Prev2 Zero=0, Prev1 Negative=1, Current Carry=1)
    // A pattern that might indicate a specific arithmetic flow leading to a problem
    assign pattern1_match = (!zero_flag_history[2]) && (negative_flag_history[1]) && (carry_flag_history[0]);

    // Pattern 2: (Prev2 Carry=1, Prev1 Overflow=0, Current Zero=0)
    // A pattern that might indicate an unexpected sequence of flags related to overflow/zero conditions
    assign pattern2_match = (carry_flag_history[2]) && (!overflow_flag_history[1]) && (!zero_flag_history[0]);

    // If ANY defined pattern matches, assert anomaly_detected
    assign anomaly_detected_out = pattern1_match || pattern2_match;

endmodule
