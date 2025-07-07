
// ===============================================================================
// ARCHON HAZARD OVERRIDE UNIT (AHO) - Integrated and Enhanced
// Purpose: This module implements the Archon Hazard Override (AHO) unit,
//          responsible for detecting hazardous internal states and generating
//          override signals (flush, stall) for the CPU pipeline.
//
// Key Enhancements:
// 1. Direct incorporation of 'cache_miss_rate_tracker' as a primary input.
// 2. Implementation of 'fluctuating impact' for various metrics through
//    dynamic weighting, controlled by an external 'ml_predicted_action'.
// 3. A sophisticated rule-based decision engine for hazard mitigation,
//    combining dynamically weighted scores with fixed-priority anomaly detection.
// This version is designed to provide 'override_flush_sig' and 'override_stall_sig'
// to the Probabilistic Hazard FSM, rather than direct pipeline control.
// ===============================================================================

module archon_hazard_override_unit (
    input wire                 clk, // Changed from logic to wire
    input wire                 rst_n, // Active low reset // Changed from logic to wire

    // Core Hazard Metrics (now adapted to 8-bit where needed, Chaos is 16-bit)
    input wire [7:0]           internal_entropy_score_val, // Changed from logic to wire
    input wire [15:0]          chaos_score_val,            // Changed from logic to wire
    input wire                 anomaly_detected_val,       // Changed from logic to wire

    // Performance/System Health Metrics (now adapted to 8-bit where needed)
    input wire [7:0]           branch_miss_rate_tracker,   // Changed from logic to wire
    input wire [7:0]           cache_miss_rate_tracker,    // NEW: Current cache miss rate (from Data Memory/Cache) // Changed from logic to wire
    input wire [7:0]           exec_pressure_tracker,      // Current execution pressure (e.g., pipeline fullness) // Changed from logic to wire

    // Input from external ML model for dynamic weighting/context
    // This input dictates the current 'risk posture' or 'mode' for hazard detection.
    // Examples: 2'b00=Normal, 2'b01=MonitorRisk, 2'b10=HighRisk, 2'b11=CriticalRisk
    input wire [1:0]           ml_predicted_action, // Changed from logic to wire

    // Dynamically scaled thresholds for the combined hazard score (adjusted for new total score range)
    // These thresholds would typically be provided by an external control unit or derived
    // from system-wide context/ML predictions, scaled appropriately for 'total_combined_hazard_score'.
    input wire [20:0]          scaled_flush_threshold,     // Changed from logic to wire
    input wire [20:0]          scaled_stall_threshold,     // Changed from logic to wire

    // Outputs to CPU pipeline control (specifically for Probabilistic Hazard FSM or main control)
    output reg                override_flush_sig,         // Request for CPU pipeline flush // Changed from logic to reg
    output reg                override_stall_sig,         // Request for CPU pipeline stall // Changed from logic to reg
    output reg [1:0]          hazard_detected_level       // Severity: 00=None, 01=Low, 10=Medium, 11=High/Critical // Changed from logic to reg
);

    // --- Internal Signals for Dynamic Weight Assignment (Fluctuating Impact) ---
    // These 4-bit weights (0-15) are dynamically adjusted based on 'ml_predicted_action'.
    // They amplify or de-emphasize the impact of each raw metric on the total hazard score.
    reg [3:0] W_entropy; // Changed from logic to reg
    reg [3:0] W_chaos; // Changed from logic to reg
    reg [3:0] W_branch; // Changed from logic to reg
    reg [3:0] W_cache; // Changed from logic to reg
    reg [3:0] W_exec; // Changed from logic to reg

    // --- Internal Signals for Weighted Scores ---
    // Individual weighted scores are calculated by multiplying raw scores by weights.
    // Max product for 8-bit * 4-bit: 255 * 15 = 3825. A 12-bit register is sufficient.
    // Max product for 16-bit * 4-bit: 65535 * 15 = 983025. A 20-bit register is sufficient.
    wire [11:0] weighted_entropy_score;   // Changed from logic to wire
    wire [19:0] weighted_chaos_score;     // Changed from logic to wire
    wire [11:0] weighted_branch_miss_score; // Changed from logic to wire
    wire [11:0] weighted_cache_miss_score;  // Changed from logic to wire
    wire [11:0] weighted_exec_pressure_score; // Changed from logic to wire

    // --- Total Combined Hazard Score ---
    // Sum of all weighted scores.
    // Max sum: (3 * 3825) + (2 * 983025) = 11475 + 1966050 = 1977525.
    // A 21-bit register is sufficient (max value 2097151).
    wire [20:0] total_combined_hazard_score; // Changed from logic to wire

    // --- Output Registers (for synchronous outputs) ---
    // These are now directly the output ports, declared as `reg`
    // No separate `reg reg_override_flush_sig;` etc. needed.

    // --- Clocked Logic for Output Registers ---
    // This block is only needed if the outputs are synchronous registers
    // Since override_flush_sig and override_stall_sig are combinational outputs
    // from the always @(*) block, they should be assigned directly there.
    // The hazard_detected_level is also combinational from that same block.
    // The previous 'reg reg_override_flush_sig;' and associated always block
    // were for registering combinational signals at module output.
    // Since the outputs themselves are now `reg`, this block is removed
    // and the assignments are moved into the always @(*) block directly.

    // --- Combinational Logic for Dynamic Weight Assignment (Fluctuating Impact) ---
    // This block determines the importance (weights) of each metric based on the
    // 'ml_predicted_action', allowing the system to adapt its sensitivity.
    always @(*) begin
        case (ml_predicted_action)
            2'b00: begin // Normal Operation: Balanced weights, general monitoring
                W_entropy = 4'd8;   // Moderate impact for entropy/chaos
                W_chaos   = 4'd7;
                W_branch  = 4'd5;   // Moderate for branch/cache misses (performance indicators)
                W_cache   = 4'd6;
                W_exec    = 4'd4;   // Lower for execution pressure
            end
            2'b01: begin // Monitor Risk: Increased focus on anomaly/chaos indicators
                W_entropy = 4'd10; // Higher impact for entropy/chaos
                W_chaos   = 4'd9;
                W_branch  = 4'd7;   // Slightly increased for branch/cache misses
                W_cache   = 4'd8;
                W_exec    = 4'd3;   // Reduced emphasis on exec pressure
            end
            2'b10: begin // High Risk: Strong emphasis on potential security/stability issues
                W_entropy = 4'd12; // Significantly higher impact for entropy/chaos
                W_chaos   = 4'd11;
                W_branch  = 4'd9;   // Substantially increased for branch/cache misses (could indicate attack)
                W_cache   = 4'd10;
                W_exec    = 4'd2;   // Minimal emphasis on general performance for immediate risk
            end
            2'b11: begin // Critical Risk: Maximum sensitivity for all hazard indicators
                W_entropy = 4'd15; // Max impact
                W_chaos   = 4'd15; // Max impact
                W_branch  = 4'd13; // Very high impact
                W_cache    = 4'd14; // Very high impact
                W_exec    = 4'd1;   // Almost no impact for exec pressure, focus is on stopping threat
            end
            default: begin // Defensive default: Fallback to normal operation weights
                W_entropy = 4'd8; W_chaos = 4'd7; W_branch = 4'd5; W_cache = 4'd6; W_exec = 4'd4;
            end
        endcase
    end

    // --- Combinational Logic for Weighted Score Calculation (Dynamic Weighted Sum) ---
    // Each raw score is multiplied by its dynamically determined weight.
    assign weighted_entropy_score   = internal_entropy_score_val * W_entropy;
    assign weighted_chaos_score     = chaos_score_val * W_chaos;
    assign weighted_branch_miss_score = branch_miss_rate_tracker * W_branch;
    assign weighted_cache_miss_score    = cache_miss_rate_tracker * W_cache; // NEW: Cache miss included
    assign weighted_exec_pressure_score = exec_pressure_tracker * W_exec;

    // The total combined hazard score aggregates all weighted metric impacts.
    assign total_combined_hazard_score =
        weighted_entropy_score +
        weighted_chaos_score +
        weighted_branch_miss_score +
        weighted_cache_miss_score +
        weighted_exec_pressure_score;

    // --- Combinational Logic for Override Signals (Multi-dimensional Rule Engine) ---
    // This block implements the decision logic, prioritizing different hazard indicators.
    always @(*) begin
        override_flush_sig = 1'b0; // Assign directly to output reg
        override_stall_sig = 1'b0; // Assign directly to output reg
        hazard_detected_level = 2'b00; // Default to no hazard

        // Rule 1: High-priority anomaly detection (Pattern Detector)
        // If an anomaly is detected, this should trigger a flush immediately,
        // regardless of the combined hazard score, as it signifies a critical state.
        if (anomaly_detected_val) begin
            override_flush_sig = 1'b1;
            hazard_detected_level = 2'b11; // Critical
        end else begin
            // Rule 2: Evaluate based on combined hazard score against dynamic thresholds
            if (total_combined_hazard_score > scaled_flush_threshold) begin
                override_flush_sig = 1'b1;
                hazard_detected_level = 2'b10; // Medium to High (depending on threshold severity)
            end else if (total_combined_hazard_score > scaled_stall_threshold) begin
                override_stall_sig = 1'b1;
                hazard_detected_level = 2'b01; // Low to Medium
            end else begin
                // No significant hazard detected by AHO's scoring system
                override_flush_sig = 1'b0;
                override_stall_sig = 1'b0;
                hazard_detected_level = 2'b00; // None
            end
        end
    end

endmodule