
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

    // NEW Military-Grade Control Inputs
    input wire [1:0] mission_profile,         // Top-level mission profile for CPU FSM
    input wire override_authentication_valid, // Top-level signal indicating authenticated overrides
    input wire [7:0] entropy_threshold_fsm,   // Top-level dynamic entropy threshold for CPU FSM

    // Debug & Status Outputs from the CPU pipeline
    output wire [3:0] cpu_debug_pc,
    output wire [15:0] cpu_debug_instr,
    output wire cpu_debug_stall,
    output wire cpu_debug_flush,
    output wire cpu_debug_lock,
    output wire [7:0] cpu_debug_fsm_entropy_log,
    output wire [2:0] cpu_debug_fsm_instr_type_log,
    output wire cpu_debug_hazard_flag,
    output wire [1:0] cpu_debug_fsm_state,
    output wire cpu_debug_shock_detected,
    output wire [1:0] cpu_debug_classified_entropy
);

    wire archon_top_internal_hazard_to_cpu = 1'b0; // Placeholder for other top-level hazards

    // Instantiate the full CPU pipeline with integrated entropy control
    pipeline_cpu u_pipeline_cpu (
        .clk(clk),
        .reset(reset),
        .external_entropy_in(external_entropy_in),
        .analog_entropy_raw_in(analog_entropy_raw),
        .ml_predicted_action(ml_predicted_action),
        .internal_hazard_flag_for_fsm(archon_top_internal_hazard_to_cpu),
        .analog_lock_override_in(analog_lock_override),
        .analog_flush_override_in(analog_flush_override),
        .quantum_override_signal_in(quantum_override_signal),

        // NEW Military-Grade Control Inputs (passed from archon_top's ports)
        .mission_profile_in(mission_profile),
        .override_authentication_valid_in(override_authentication_valid),
        .entropy_threshold_fsm_in(entropy_threshold_fsm),

        // Connect Debug/Status Outputs
        .debug_pc(cpu_debug_pc),
        .debug_instr(cpu_debug_instr),
        .debug_stall(cpu_debug_stall),
        .debug_flush(cpu_debug_flush),
        .debug_lock(cpu_debug_lock),
        .debug_fsm_entropy_log(cpu_debug_fsm_entropy_log),
        .debug_fsm_instr_type_log(cpu_debug_fsm_instr_type_log),
        .debug_hazard_flag(cpu_debug_hazard_flag),
        .debug_fsm_state(cpu_debug_fsm_state),
        .debug_shock_detected(cpu_debug_shock_detected),
        .debug_classified_entropy(cpu_debug_classified_entropy)
    );

endmodule
