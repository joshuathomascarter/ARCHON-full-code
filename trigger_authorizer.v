
// ===============================================================================
// MODULE: trigger_authorizer.v
// Description: Implements a Finite State Machine (FSM) for a Weapon Trigger
//              Authorizer system. It evaluates multiple risk and override signals
//              to determine if a single-cycle ENABLE_FIRE pulse should be issued.
//              Designed with military-grade safety and responsiveness in mind.
// ===============================================================================

module trigger_authorizer (
    input wire clk,                  // System clock
    input wire rst_n,                // Asynchronous active-low reset
    input wire [7:0] entropy_score,  // Input from Quantum Entropy Detector (QED) or similar
    input wire analog_spike_detected,// Input from physical sensor (e.g., EMP, sudden energy surge)
    input wire ml_risk_flag,         // Input from Machine Learning model (1 = high-risk detected)
    input wire manual_lock,          // Manual override: 1 = force system into LOCKED state

    output reg enable_fire           // 1-cycle pulse when fire is authorized
);

    // --- FSM State Definitions ---
    // Using localparam for states, as recommended.
    localparam [2:0] // 3 bits needed for 5 states (000 to 100)
        IDLE            = 3'b000, // Waiting for authorization conditions
        CHECK           = 3'b001, // Evaluating all inputs
        READY_TO_FIRE   = 3'b010, // All conditions met, ready to issue pulse
        LOCKED          = 3'b011, // Manual lock engaged, system disabled
        FORCED_ABORT    = 3'b100; // High risk detected, system disabled

    // --- Internal FSM State Registers ---
    reg [2:0] current_state; // Current state of the FSM
    reg [2:0] next_state;    // Next state of the FSM (combinational logic result)

    // --- Thresholds and Constants ---
    // Entropy threshold for allowing fire.
    // Below this value is considered "low entropy" and safe for firing.
    localparam ENTROPY_FIRE_THRESHOLD = 8'd100; // Example: Entropy must be below 100

    // --- enable_fire pulse generation logic ---
    // This register will hold the 'enable_fire' signal.
    // It's set to 1 only for one cycle when transitioning into READY_TO_FIRE.
    reg enable_fire_pulse_reg;

    // ==================================================================
    // Synchronous State Register Logic (State Transitions)
    // This block updates the current_state on the clock edge or reset.
    // ==================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Asynchronous reset: Force to IDLE state and de-assert fire pulse.
            current_state <= IDLE;
            enable_fire_pulse_reg <= 1'b0;
        end else begin
            // Update current state based on next_state determined by combinational logic.
            current_state <= next_state;

            // Logic to generate the 1-cycle ENABLE_FIRE pulse:
            // Assert 'enable_fire_pulse_reg' only if the FSM is transitioning TO READY_TO_FIRE.
            // In all other cases, de-assert it.
            if (next_state == READY_TO_FIRE && current_state != READY_TO_FIRE) begin
                enable_fire_pulse_reg <= 1'b1; // Assert pulse for one cycle
            end else begin
                enable_fire_pulse_reg <= 1'b0; // De-assert pulse
            end
        end
    end

    // ==================================================================
    // Combinational Next-State Logic
    // This block determines the next_state based on current_state and inputs.
    // It also defines the conditions for entering various states.
    // ==================================================================
    always @(*) begin
        // Default to staying in the current state unless a specific transition condition is met.
        next_state = current_state;

        // --- High-Priority Overrides (Manual Lock takes highest precedence) ---
        if (manual_lock) begin
            next_state = LOCKED; // Manual lock always forces LOCKED state
        end
        // --- Risk-Based Abort Conditions (Checked if not manually locked) ---
        else if (analog_spike_detected || ml_risk_flag || (entropy_score >= ENTROPY_FIRE_THRESHOLD)) begin
            next_state = FORCED_ABORT; // Any high-risk indicator forces ABORT
        end
        // --- FSM State Transitions ---
        else begin
            case (current_state)
                IDLE: begin
                    // From IDLE, move to CHECK to evaluate conditions.
                    // (Assuming an implicit "request to fire" or continuous evaluation)
                    next_state = CHECK;
                end

                CHECK: begin
                    // Evaluate all conditions to determine if fire is authorized.
                    if (!analog_spike_detected && !ml_risk_flag && (entropy_score < ENTROPY_FIRE_THRESHOLD) && !manual_lock) begin
                        next_state = READY_TO_FIRE; // All conditions met, move to READY_TO_FIRE
                    end else begin
                        // If conditions are not met, but not critical enough for ABORT/LOCK,
                        // return to IDLE to wait for conditions to clear or a new cycle.
                        next_state = IDLE;
                    end
                end

                READY_TO_FIRE: begin
                    // After issuing the ENABLE_FIRE pulse, immediately return to IDLE.
                    // This ensures the 1-cycle pulse and prepares for a new authorization cycle.
                    next_state = IDLE;
                end

                LOCKED: begin
                    // Stay in LOCKED as long as manual_lock is asserted (handled by top-level if).
                    // If manual_lock is de-asserted (checked by the 'else if' above),
                    // the FSM will transition out of LOCKED.
                    // It will then go to FORCED_ABORT if other risks are present,
                    // or to IDLE if all clear.
                    next_state = LOCKED; // Default: remain in LOCKED if manual_lock is still active
                end

                FORCED_ABORT: begin
                    // Stay in FORCED_ABORT as long as risk conditions persist (handled by top-level if).
                    // If risk conditions clear (checked by the 'else if' above),
                    // the FSM will transition out of FORCED_ABORT.
                    // It will then go to IDLE to wait for a new authorization cycle.
                    next_state = FORCED_ABORT; // Default: remain in FORCED_ABORT if risks are still active
                end

                default: begin
                    // Safety default: If FSM enters an undefined state, reset to IDLE.
                    next_state = IDLE;
                end
            endcase
        end
    end

    // ==================================================================
    // Output Assignment
    // The final output 'enable_fire' is directly driven by the pulse register.
    // ==================================================================
    assign enable_fire = enable_fire_pulse_reg;

endmodule
