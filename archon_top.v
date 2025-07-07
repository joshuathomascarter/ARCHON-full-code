module archon_top (
    input wire clk,
    input wire reset, // Active high system reset

    // Primary Entropy Sources
    input wire [15:0] external_entropy_in, // From external TRNG or entropy bus
    input wire [7:0] analog_entropy_raw,   // From dedicated analog sensor for shock filter/decoder

    // Machine Learning Prediction Input (from a separate ML accelerator/module)
    input wire [1:0] ml_predicted_action,

    // Top-level Analog Override Signals (for critical manual/external control)
    input wire analog_lock_override,
    input wire analog_flush_override,
    input wire quantum_override_signal, // From a quantum-level monitoring system

    // Debug & Status Outputs from the CPU pipeline
    output wire [3:0] cpu_debug_pc,
    output wire [15:0] cpu_debug_instr,
    output wire cpu_debug_stall,
    output wire cpu_debug_flush,
    output wire cpu_debug_lock,
    output wire [7:0] cpu_debug_fsm_entropy_log,
    output wire [2:0] cpu_debug_fsm_instr_type_log,
    output wire cpu_debug_hazard_flag, // Renamed from debug_hazard_flag_out for consistency
    output wire [1:0] cpu_debug_fsm_state,
    output wire cpu_debug_shock_detected, // NEW: Debug output for shock filter
    output wire [1:0] cpu_debug_classified_entropy // NEW: Debug output for classified entropy level
);

    // Wire to represent any internal hazard detected within the CPU core,
    // which is then fed back to the FSM *within* the CPU.
    // For this example, we'll assume it's always '0' from archon_top's perspective,
    // as the actual hazard detection is part of `pipeline_cpu`.
    // If `archon_top` itself had other hazard detection (e.g., bus errors),
    // they'd be combined here.
    wire archon_top_internal_hazard_to_cpu = 1'b0; // Placeholder

    // Instantiate the full CPU pipeline with integrated entropy control
    pipeline_cpu u_pipeline_cpu (
        .clk(clk),
        .reset(reset),
        .external_entropy_in(external_entropy_in),
        .analog_entropy_raw_in(analog_entropy_raw), // NEW: Connect new analog entropy input
        .ml_predicted_action(ml_predicted_action),
        .internal_hazard_flag_for_fsm(archon_top_internal_hazard_to_cpu), // Connect placeholder/actual hazard
        .analog_lock_override_in(analog_lock_override),
        .analog_flush_override_in(analog_flush_override),
        .quantum_override_signal_in(quantum_override_signal),

        // Connect Debug/Status Outputs
        .debug_pc(cpu_debug_pc),
        .debug_instr(cpu_debug_instr),
        .debug_stall(cpu_debug_stall),
        .debug_flush(cpu_debug_flush),
        .debug_lock(cpu_debug_lock),
        .debug_fsm_entropy_log(cpu_debug_fsm_entropy_log),
        .debug_fsm_instr_type_log(cpu_debug_fsm_instr_type_log),
        .debug_hazard_flag(cpu_debug_hazard_flag), // Connect to output
        .debug_fsm_state(cpu_debug_fsm_state),
        .debug_shock_detected(cpu_debug_shock_detected), // NEW: Connect shock detected output
        .debug_classified_entropy(cpu_debug_classified_entropy) // NEW: Connect classified entropy output
    );

endmodule