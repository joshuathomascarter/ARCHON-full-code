// ===============================================================================
// NEW MODULE: entropy_control_logic.v
// Purpose: Directly uses the 16-bit external entropy input from 'entropy_bus.txt'.
//          Applies simple, configurable thresholds to generate stall/flush signals.
//          This module provides the *base* entropy-driven control signals.
//          These can then be modulated by ML and chaos predictors in the main CPU.
// ===============================================================================
module entropy_control_logic(
    input wire [15:0] external_entropy_in, // 16-bit external entropy from entropy_bus.txt
    output wire entropy_stall,            // Assert to signal a basic entropy-induced stall
    output wire entropy_flush             // Assert to signal a basic entropy-induced flush
);

    // Define entropy thresholds for stall and flush
    // These values are for a 16-bit (0-65535) entropy input.
    // Changed thresholds to be more sensitive to higher values, and logic to trigger on > threshold.
    parameter ENTROPY_STALL_THRESHOLD = 16'd10000;  // Example: Above 10000, consider stalling
    parameter ENTROPY_FLUSH_THRESHOLD = 16'd50000; // Example: Above 50000, consider flushing

    // Inverted logic: now asserts stall/flush when entropy_in is GREATER than threshold
    assign entropy_stall = (external_entropy_in > ENTROPY_STALL_THRESHOLD);
    assign entropy_flush = (external_entropy_in > ENTROPY_FLUSH_THRESHOLD);

endmodule