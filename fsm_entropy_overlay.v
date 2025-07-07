// ======================================================================
// FSM Entropy Overlay Module (Modified for entropy_shock_filter integration)
// Description: This module implements a Finite State Machine (FSM) that
//              acts as an overlay, dynamically adjusting system behavior
//              (e.g., stalling, flushing, or locking) based on a
//              combination of machine learning (ML) predictions,
//              internal entropy scores, hazard flags, and various
//              override signals. It's designed to manage system stability
//              and security in the face of unpredictable or anomalous
//              conditions.
//
// States:
// - STATE_OK: Normal operation.
// - STATE_STALL: Halts execution to prevent potential issues, allowing
//                for resolution or re-evaluation.
// - STATE_FLUSH: Clears pipelines or buffers, typically in response to
//                detected corruption or irrecoverable states.
// - STATE_LOCK: Enters a secure, unchangeable state, usually indicating
//               a critical security breach or system integrity compromise.
//
// Inputs:
// - ML Predicted Action: Direct guidance from an ML model on desired
//                        system state.
// - Internal Entropy Score: A measure of randomness or unpredictability
//                            within the system, indicating potential
//                            anomalies or attacks.
// - Internal Hazard Flag: Indicates an architectural hazard within the
//                          system (e.g., data dependency, control hazard).
// - Analog Overrides: External, high-priority signals for immediate
//                      system state changes (lock or flush).
// - Classified Entropy Level: Pre-classified severity of entropy (low, mid, critical).
// - Quantum Override Signal: A highly critical override, possibly from
//                            a quantum-level monitoring system, forcing a lock.
// - Instruction Type: Categorization of the currently executing instruction,
//                     used for context-aware state transitions.
// - NEW: shock_detected_in: Signal from entropy_shock_filter indicating a sudden
//                          drastic change in analog entropy.
//
// Outputs:
// - FSM State: The current operational state of the FSM.
// - Entropy Log Out: Logs the entropy score when a state transition occurs.
// - Instruction Type Log Out: Logs the instruction type when a state transition occurs.
// ======================================================================
module fsm_entropy_overlay(
    input wire clk,                       // Clock signal
    input wire rst_n,                     // Asynchronous active-low reset
    input wire [1:0] ml_predicted_action, // Machine Learning model's predicted action
    input wire [7:0] internal_entropy_score,// Current internal entropy score
    input wire internal_hazard_flag,      // Flag indicating an internal system hazard
    input wire analog_lock_override,      // External override to force LOCK state
    input wire analog_flush_override,     // External override to force FLUSH state
    input wire [1:0] classified_entropy_level, // Pre-classified entropy level (Low, Mid, Critical)
    input wire quantum_override_signal,   // Critical override from quantum monitoring
    input wire [2:0] instr_type,          // Type of the current instruction
    input wire shock_detected_in,         // NEW: Input from entropy_shock_filter
    
    output reg [1:0] fsm_state,           // Current FSM state
    output reg [7:0] entropy_log_out,     // Log of entropy score at state change
    output reg [2:0] instr_type_log_out   // Log of instruction type at state change
);

    // --- FSM State Definitions ---
    parameter STATE_OK      = 2'b00; // Normal operational state
    parameter STATE_STALL   = 2'b01; // System stalled, awaiting resolution or re-evaluation
    parameter STATE_FLUSH   = 2'b10; // System flushing pipelines/buffers
    parameter STATE_LOCK    = 2'b11; // System locked due to critical event

    // --- ML Action Code Definitions ---
    parameter ML_OK    = 2'b00; // ML suggests normal operation
    parameter ML_STALL = 2'b01; // ML suggests stalling the system
    parameter ML_FLUSH = 2'b10; // ML suggests flushing the system
    parameter ML_LOCK  = 2'b11; // ML suggests locking the system

    // --- Entropy Classification Levels ---
    parameter ENTROPY_LOW      = 2'b00; // Low entropy, normal
    parameter ENTROPY_MID      = 2'b01; // Medium entropy, potentially concerning
    parameter ENTROPY_CRITICAL = 2'b10; // Critical entropy, highly concerning

    // --- Instruction Type Definitions ---
    parameter INSTR_TYPE_ALU    = 3'b000; // Arithmetic Logic Unit operation
    parameter INSTR_TYPE_LOAD   = 3'b001; // Memory load operation
    parameter INSTR_TYPE_STORE  = 3'b010; // Memory store operation
    parameter INSTR_TYPE_BRANCH = 3'b011; // Program control branch instruction
    parameter INSTR_TYPE_JUMP   = 3'b100; // Program control jump instruction
    parameter INSTR_TYPE_OTHER  = 3'b111; // Other/unclassified instruction type

    // --- Thresholds ---
    parameter ENTROPY_HIGH_THRESHOLD = 8'd180; // Example threshold for high entropy (decimal 180)

    // --- Internal FSM State Registers ---
    reg [1:0] current_state, next_state;

    // ==================================================================
    // Synchronous State Register Logic
    // ==================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_OK;
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

        // --- High-Priority Overrides ---
        // Quantum override takes highest priority, forcing a LOCK.
        if (quantum_override_signal) begin
            next_state = STATE_LOCK;
        end
        // Analog lock override takes next priority.
        else if (analog_lock_override) begin
            next_state = STATE_LOCK;
        end
        // Analog flush override takes next priority.
        else if (analog_flush_override) begin
            next_state = STATE_FLUSH;
        end
        // NEW: Entropy Shock detected takes next priority.
        // A sudden shock implies a critical anomaly, so flushing is a strong protective measure.
        else if (shock_detected_in) begin
            next_state = STATE_FLUSH; // Force a flush immediately upon shock detection
        end
        // --- Normal State Transition Logic ---
        else begin
            case (current_state)
                STATE_OK: begin
                    // In OK state, process ML predictions first.
                    case (ml_predicted_action)
                        ML_STALL: next_state = STATE_STALL;
                        ML_FLUSH: next_state = STATE_FLUSH;
                        ML_LOCK:  next_state = STATE_LOCK;
                        default: begin // ML_OK or undefined ML action
                            // If ML is OK, check internal entropy and hazards.
                            if ((classified_entropy_level == ENTROPY_LOW || classified_entropy_level == 2'b11) && // 2'b11 for unclassified
                                internal_entropy_score > ENTROPY_HIGH_THRESHOLD) begin
                                next_state = STATE_STALL; // High entropy -> STALL
                            end else if (internal_hazard_flag) begin
                                next_state = STATE_STALL; // Internal hazard -> STALL
                            end else if (classified_entropy_level == ENTROPY_CRITICAL) begin
                                // Critical entropy without ML/shock intervention -> FLUSH or STALL based on instr_type
                                case (instr_type)
                                    INSTR_TYPE_BRANCH, INSTR_TYPE_JUMP: next_state = STATE_STALL;
                                    INSTR_TYPE_LOAD, INSTR_TYPE_STORE: next_state = STATE_FLUSH;
                                    default: next_state = STATE_FLUSH;
                                endcase
                            end else if (classified_entropy_level == ENTROPY_MID) begin
                                // Medium entropy: more conservative action
                                case (instr_type)
                                    INSTR_TYPE_BRANCH, INSTR_TYPE_JUMP, INSTR_TYPE_LOAD, INSTR_TYPE_STORE: next_state = STATE_STALL;
                                    default: next_state = STATE_OK; // Stay OK for other types with mid entropy
                                endcase
                            end
                            // Otherwise, stay in OK (next_state remains current_state from default assignment)
                        end
                    endcase
                end
                STATE_STALL: begin
                    // In STALL state, ML can transition to FLUSH or LOCK, or return to OK if conditions clear.
                    case (ml_predicted_action)
                        ML_FLUSH: next_state = STATE_FLUSH;
                        ML_LOCK:  next_state = STATE_LOCK;
                        default: begin // ML_OK or undefined ML action
                            // Return to OK if ML is OK, no hazard, and entropy is low, and no shock.
                            if (ml_predicted_action == ML_OK &&
                                !internal_hazard_flag &&
                                classified_entropy_level == ENTROPY_LOW &&
                                internal_entropy_score <= ENTROPY_HIGH_THRESHOLD &&
                                !shock_detected_in) // NEW: Must not have a shock
                                next_state = STATE_OK;
                            // If ML suggests STALL (which it would if default) and conditions still not clear, remain stalled.
                        end
                    endcase
                end
                STATE_FLUSH: begin
                    // In FLUSH state, ML can transition to LOCK, or return to OK/STALL if conditions clear.
                    case (ml_predicted_action)
                        ML_LOCK: next_state = STATE_LOCK;
                        default: begin // ML_OK or undefined ML action
                            // Return to OK if ML is OK, no hazard, and entropy is low, and no shock.
                            if (ml_predicted_action == ML_OK &&
                                !internal_hazard_flag &&
                                classified_entropy_level == ENTROPY_LOW &&
                                internal_entropy_score <= ENTROPY_HIGH_THRESHOLD &&
                                !shock_detected_in) // NEW: Must not have a shock
                                next_state = STATE_OK;
                            // If ML suggests STALL, transition to STALL.
                            else if (ml_predicted_action == ML_STALL)
                                next_state = STATE_STALL;
                        end
                    endcase
                end
                STATE_LOCK: begin
                    // Allow exit from LOCK state if all lock-forcing overrides are removed
                    // AND no critical entropy or internal hazard is present AND no shock.
                    if (!quantum_override_signal && !analog_lock_override &&
                        classified_entropy_level != ENTROPY_CRITICAL && !internal_hazard_flag &&
                        !shock_detected_in) begin // NEW: Must not have a shock
                        next_state = STATE_OK; // Return to OK if conditions clear
                    end else begin
                        next_state = STATE_LOCK; // Remain locked otherwise
                    end
                end
                default:
                    // Safety default: if in an undefined state, return to OK.
                    next_state = STATE_OK;
            endcase
        end
    end

    // ==================================================================
    // Output State Assignment
    // ==================================================================
    always @(*) begin
        fsm_state = current_state;
    end

endmodule