// ===============================================================================
// MODULE: fsm_entropy_overlay.v
// Purpose: State machine managing CPU behavior based on various entropy,
//          hazard, ML, and now, military-grade control inputs.
// ===============================================================================

module fsm_entropy_overlay (
    input wire clk,
    input wire rst_n, // Active low reset

    input wire [1:0] ml_predicted_action,    // ML model's predicted action for AHO and FSM
    input wire [7:0] internal_entropy_score, // Entropy score from QED
    input wire internal_hazard_flag,         // Consolidated hazard flag from AHO/other CPU hazards
    input wire [1:0] classified_entropy_level, // Classified entropy from entropy_trigger_decoder
    input wire [2:0] instr_type,             // Type of instruction currently in EX stage

    input wire analog_lock_override,         // From top-level analog controller
    input wire analog_flush_override,        // From top-level analog controller
    input wire quantum_override_signal,      // From Qiskit simulation / quantum sensor

    input wire shock_detected_in,            // NEW: Input from entropy_shock_filter

    // NEW Military-Grade Inputs
    input wire [1:0] mission_profile_in,       // 00: Normal, 01: High Threat, 10: Diagnostic, 11: Reserved
    input wire override_authentication_valid_in, // Indicates if analog_override signals are authenticated
    input wire [7:0] entropy_threshold_fsm_in, // Dynamic entropy threshold for FSM decisions

    output reg [1:0] fsm_state,              // Output control signal for pipeline (00: Normal, 01: Stall, 10: Flush, 11: Lock)
    output reg [7:0] entropy_log_out,        // Debug output: last logged entropy
    output reg [2:0] instr_type_log_out      // Debug output: last logged instruction type
);

    // --- FSM State Definitions ---
    localparam STATE_NORMAL    = 2'b00; // Normal operational state
    localparam STATE_STALL     = 2'b01; // System stalled, awaiting resolution or re-evaluation
    localparam STATE_FLUSH     = 2'b10; // System flushing pipelines/buffers
    localparam STATE_LOCK      = 2'b11; // Critical lock state, requires external reset

    // --- ML Action Code Definitions ---
    localparam ML_OK    = 2'b00; // ML suggests normal operation
    localparam ML_STALL = 2'b01; // ML suggests stalling the system
    localparam ML_FLUSH = 2'b10; // ML suggests flushing the system
    localparam ML_LOCK  = 2'b11; // ML suggests locking the system

    // --- Entropy Classification Levels ---
    localparam ENTROPY_LOW      = 2'b00; // Low entropy, normal
    localparam ENTROPY_MID      = 2'b01; // Medium entropy, potentially concerning
    localparam ENTROPY_CRITICAL = 2'b10; // Critical entropy, highly concerning
    // Note: If 2'b11 is used for 'unclassified' in your decoder, ensure its handling in FSM logic.
    // For now, it will fall into 'default' if not explicitly handled.

    // --- Instruction Type Definitions ---
    localparam INSTR_TYPE_ALU    = 3'b000; // Arithmetic Logic Unit operation
    localparam INSTR_TYPE_LOAD   = 3'b001; // Memory load operation
    localparam INSTR_TYPE_STORE  = 3'b010; // Memory store operation
    localparam INSTR_TYPE_BRANCH = 3'b011; // Program control branch instruction
    localparam INSTR_TYPE_JUMP   = 3'b100; // Program control jump instruction
    localparam INSTR_TYPE_OTHER  = 3'b111; // Other/unclassified instruction type

    // --- Mission Profile Definitions ---
    localparam MISSION_NORMAL     = 2'b00;
    localparam MISSION_HIGH_THREAT= 2'b01;
    localparam MISSION_DIAGNOSTIC = 2'b10;
    // 2'b11 Reserved

    // Internal FSM State Registers
    reg [1:0] current_state, next_state;

    // ==================================================================
    // Synchronous State Register Logic
    // ==================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_NORMAL;
            entropy_log_out <= 8'h00;
            instr_type_log_out <= INSTR_TYPE_OTHER;
        end else begin
            current_state <= next_state;
            // Log continuously to aid in debugging, regardless of state change.
            entropy_log_out <= internal_entropy_score;
            instr_type_log_out <= instr_type;
        end
    end

    // ==================================================================
    // Combinational Next-State Logic
    // ==================================================================
    always @(*) begin
        // Default to staying in the current state unless a condition dictates a change.
        next_state = current_state;

        // --- High-Priority Overrides (Prioritized from most critical) ---
        // 1. Quantum override takes highest priority, forcing a LOCK.
        if (quantum_override_signal) begin
            next_state = STATE_LOCK;
        end
        // 2. Authenticated Analog lock override takes next priority.
        else if (override_authentication_valid_in && analog_lock_override) begin
            next_state = STATE_LOCK;
        end
        // 3. Authenticated Analog flush override takes next priority.
        else if (override_authentication_valid_in && analog_flush_override) begin
            next_state = STATE_FLUSH;
        end
        // 4. NEW: Entropy Shock detected takes next priority, forcing a flush or lock based on current state.
        else if (shock_detected_in) begin
            // If already in a critical state (STALL/FLUSH), escalate to LOCK on shock
            if (current_state == STATE_STALL || current_state == STATE_FLUSH) begin
                next_state = STATE_LOCK;
            end else begin // From NORMAL, a shock forces FLUSH
                next_state = STATE_FLUSH;
            end
        end
        // --- Normal State Transition Logic ---
        else begin
            case (current_state)
                STATE_NORMAL: begin
                    // In NORMAL state, process ML predictions first.
                    case (ml_predicted_action)
                        ML_STALL: next_state = STATE_STALL;
                        ML_FLUSH: next_state = STATE_FLUSH;
                        ML_LOCK:  next_state = STATE_LOCK;
                        default: begin // ML_OK or undefined ML action
                            // If ML is OK, check internal entropy and hazards.
                            if (internal_hazard_flag) begin
                                next_state = STATE_STALL; // Internal hazard -> STALL
                            end
                            // Prioritize classified entropy levels
                            else if (classified_entropy_level == ENTROPY_CRITICAL) begin
                                // Critical entropy: FLUSH, unless mission profile dictates LOCK
                                if (mission_profile_in == MISSION_HIGH_THREAT) begin
                                    next_state = STATE_LOCK; // More aggressive in high threat
                                end else begin
                                    next_state = STATE_FLUSH;
                                end
                            end
                            else if (internal_entropy_score > entropy_threshold_fsm_in) begin // Dynamic Threshold Check
                                if (mission_profile_in == MISSION_HIGH_THREAT) begin
                                    next_state = STATE_FLUSH; // High threat with high entropy -> FLUSH
                                end else begin
                                    next_state = STATE_STALL; // Normal high entropy -> STALL
                                end
                            end
                            else if (classified_entropy_level == ENTROPY_MID) begin
                                // Medium entropy: more conservative action based on instruction type and mission
                                case (instr_type)
                                    INSTR_TYPE_BRANCH, INSTR_TYPE_JUMP: next_state = STATE_STALL;
                                    INSTR_TYPE_LOAD, INSTR_TYPE_STORE: begin
                                        if (mission_profile_in == MISSION_HIGH_THREAT) begin
                                            next_state = STATE_FLUSH; // Sensitive data ops in high threat
                                        end else begin
                                            next_state = STATE_STALL;
                                        end
                                    end
                                    default: next_state = STATE_NORMAL; // Stay NORMAL for other types with mid entropy
                                endcase
                            end
                            // If none of the above conditions met, next_state remains STATE_NORMAL (from default assignment)
                        end
                    endcase
                end

                STATE_STALL: begin
                    // From STALL state, ML can transition to FLUSH or LOCK, or return to NORMAL if conditions clear.
                    case (ml_predicted_action)
                        ML_FLUSH: next_state = STATE_FLUSH;
                        ML_LOCK:  next_state = STATE_LOCK;
                        default: begin // ML_OK or undefined ML action
                            // Return to NORMAL if ML is OK, no hazard, entropy is low, and no shock.
                            if (ml_predicted_action == ML_OK &&
                                !internal_hazard_flag &&
                                classified_entropy_level == ENTROPY_LOW &&
                                internal_entropy_score <= entropy_threshold_fsm_in) begin
                                next_state = STATE_NORMAL; // Return to normal if conditions clear
                            end
                            // Otherwise, remain in STALL or escalate if other conditions are met (handled by default next_state)
                        end
                    endcase
                end

                STATE_FLUSH: begin
                    // From FLUSH state, ML can transition to LOCK, or return to NORMAL/STALL if conditions clear.
                    case (ml_predicted_action)
                        ML_LOCK: next_state = STATE_LOCK;
                        default: begin // ML_OK or undefined ML action
                            // Return to NORMAL if ML is OK, no hazard, entropy is low, and no shock.
                            if (ml_predicted_action == ML_OK &&
                                !internal_hazard_flag &&
                                classified_entropy_level == ENTROPY_LOW &&
                                internal_entropy_score <= entropy_threshold_fsm_in) begin
                                next_state = STATE_NORMAL; // Return to normal if conditions clear
                            end
                            // If ML suggests STALL, transition to STALL.
                            else if (ml_predicted_action == ML_STALL) begin
                                next_state = STATE_STALL;
                            end
                            // Otherwise, remain in FLUSH (from default next_state)
                        end
                    endcase
                end

                STATE_LOCK: begin
                    // Only exit from LOCK state if ALL lock-forcing overrides are removed AND conditions clear.
                    if (!quantum_override_signal &&
                        !(override_authentication_valid_in && analog_lock_override) && // Authenticated analog lock removed
                        !shock_detected_in && // Shock gone
                        ml_predicted_action != ML_LOCK && // ML no longer predicts LOCK
                        !internal_hazard_flag && // No internal hazard
                        classified_entropy_level != ENTROPY_CRITICAL && // No critical classified entropy
                        internal_entropy_score <= entropy_threshold_fsm_in) begin // Entropy below threshold
                        next_state = STATE_NORMAL; // Return to normal if conditions sufficiently clear
                    end else begin
                        next_state = STATE_LOCK; // Remain locked otherwise
                    end
                end

                default:
                    next_state = STATE_NORMAL; // Safety default: if in an undefined state, return to NORMAL.
            endcase
        end
    end


    // ==================================================================
    // Output State Assignment
    // ==================================================================
    always @(*) begin // This ensures fsm_state updates whenever current_state changes
        fsm_state = current_state;
    end
endmodule
