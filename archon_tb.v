`timescale 1ns / 1ps

// ===============================================================================
// Testbench for archon_top module
// Purpose: To simulate and verify the functionality of the integrated ARCHON CPU,
//          including its pipeline, hazard detection, and entropy-aware FSM.
// ===============================================================================
module archon_top_testbench;

    // --- Testbench Parameters ---
    parameter CLK_PERIOD = 10; // Clock period in ns (10ns -> 100MHz clock)
    parameter SIM_DURATION = 500; // Simulation duration in ns

    // --- Inputs to the archon_top module (declared as reg for stimulus) ---
    reg clk;                       // Clock signal
    reg rst_n;                     // Active-low reset signal
    reg [1:0] ml_predicted_action; // ML model's predicted action
    reg [7:0] internal_entropy_score; // Internal entropy score (dummy input for now)
    reg analog_flush_override;     // External analog flush override
    reg analog_lock_override;      // External analog lock override
    reg quantum_override_signal;   // Critical quantum override signal
    reg [15:0] external_entropy_in; // External entropy input (from 'entropy_bus.txt' concept)

    // --- Outputs from the archon_top module (declared as wire for monitoring) ---
    wire [1:0] fsm_state;          // Current state of the entropy-aware FSM
    wire [3:0] debug_pc_out;       // Debug output: Program Counter
    wire [15:0] debug_instr_out;   // Debug output: Current Instruction
    wire debug_stall_out;          // Debug output: Pipeline Stall status
    wire debug_flush_out;          // Debug output: Pipeline Flush status
    wire debug_lock_out;           // Debug output: System Lock status
    wire [7:0] debug_fsm_entropy_log_out; // Debug output: Entropy value logged by FSM on state change
    wire [2:0] debug_fsm_instr_type_log_out; // Debug output: Instruction type logged by FSM on state change
    wire debug_hazard_flag;        // Debug output: Combined internal hazard flag

    // --- Instantiate the Device Under Test (DUT) ---
    archon_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .ml_predicted_action(ml_predicted_action),
        .internal_entropy_score(internal_entropy_score),
        .analog_flush_override(analog_flush_override),
        .analog_lock_override(analog_lock_override),
        .quantum_override_signal(quantum_override_signal),
        .external_entropy_in(external_entropy_in),
        .fsm_state(fsm_state),
        .debug_pc_out(debug_pc_out),
        .debug_instr_out(debug_instr_out),
        .debug_stall_out(debug_stall_out),
        .debug_flush_out(debug_flush_out),
        .debug_lock_out(debug_lock_out),
        .debug_fsm_entropy_log_out(debug_fsm_entropy_log_out),
        .debug_fsm_instr_type_log_out(debug_fsm_instr_type_log_out),
        .debug_hazard_flag(debug_hazard_flag)
    );

    // --- Clock Generation ---
    // Generates a continuous clock signal with the defined CLK_PERIOD.
    always #((CLK_PERIOD)/2) clk = ~clk;

    // --- Initial Block for Test Stimulus ---
    // This block defines the sequence of operations for the simulation.
    initial begin
        // Initialize all inputs at the beginning of simulation
        clk = 1'b0;
        rst_n = 1'b0; // Assert reset (active-low)
        ml_predicted_action = 2'b00; // ML: Normal
        internal_entropy_score = 8'h00; // Low entropy
        analog_flush_override = 1'b0;
        analog_lock_override = 1'b0;
        quantum_override_signal = 1'b0;
        external_entropy_in = 16'h0000; // Low external entropy

        // --- Dump VCD for waveform viewing ---
        // This creates a waveform file that can be opened with tools like GTKWave.
        $dumpfile("archon_top.vcd");
        $dumpvars(0, archon_top_testbench); // Dump all signals in the testbench

        // --- Monitor key signals continuously ---
        // This will print a line every time any of these signals change.
        $monitor("Time=%0t | PC=%h | Instr=%h | Stall=%b | Flush=%b | Lock=%b | FSM_State=%b | Hazard_Flag=%b | FSM_Entropy_Log=%h | FSM_Instr_Type_Log=%b",
                 $time, debug_pc_out, debug_instr_out, debug_stall_out, debug_flush_out, debug_lock_out, fsm_state, debug_hazard_flag, debug_fsm_entropy_log_out, debug_fsm_instr_type_log_out);

        // --- Reset Sequence ---
        # (CLK_PERIOD * 2); // Hold reset for a few clock cycles
        rst_n = 1'b1;       // De-assert reset

        $display("\n--- Simulation Start ---");

        // --- Scenario 1: Normal Operation ---
        // Let the CPU run normally for some cycles.
        $display("\nTime=%0t: Scenario 1 - Normal Operation", $time);
        # (CLK_PERIOD * 10);

        // --- Scenario 2: ML Predicted Stall ---
        // ML model predicts a stall, but no actual hazard yet.
        $display("\nTime=%0t: Scenario 2 - ML Predicted Stall", $time);
        ml_predicted_action = 2'b01; // ML: Stall
        # (CLK_PERIOD * 5);
        ml_predicted_action = 2'b00; // ML: Back to normal
        $display("Time=%0t: ML prediction reverted to Normal", $time);
        # (CLK_PERIOD * 5);

        // --- Scenario 3: High Internal Entropy (should cause stall) ---
        // Simulate a high internal entropy score, which should trigger a stall via FSM.
        $display("\nTime=%0t: Scenario 3 - High Internal Entropy", $time);
        internal_entropy_score = 8'd200; // Set high entropy (above threshold)
        # (CLK_PERIOD * 5);
        internal_entropy_score = 8'h50; // Reduce entropy
        $display("Time=%0t: Internal entropy reduced", $time);
        # (CLK_PERIOD * 5);

        // --- Scenario 4: External Entropy Flush ---
        // Simulate a critical external entropy event causing a flush.
        $display("\nTime=%0t: Scenario 4 - External Entropy Flush", $time);
        external_entropy_in = 16'd60000; // Very high external entropy
        # (CLK_PERIOD * 5);
        external_entropy_in = 16'h0000; // Reset external entropy
        $display("Time=%0t: External entropy reset", $time);
        # (CLK_PERIOD * 5);

        // --- Scenario 5: Analog Flush Override ---
        // Simulate an immediate analog flush override.
        $display("\nTime=%0t: Scenario 5 - Analog Flush Override", $time);
        analog_flush_override = 1'b1;
        # (CLK_PERIOD * 3);
        analog_flush_override = 1'b0;
        $display("Time=%0t: Analog flush override released", $time);
        # (CLK_PERIOD * 5);

        // --- Scenario 6: Quantum Lock Override ---
        // Simulate a critical quantum override, forcing a system lock.
        $display("\nTime=%0t: Scenario 6 - Quantum Lock Override", $time);
        quantum_override_signal = 1'b1;
        # (CLK_PERIOD * 10); // Hold lock for a longer period
        quantum_override_signal = 1'b0; // Typically, a lock would require a full system reset to clear.
                                        // For simulation, we'll release it to see if it recovers.
        $display("Time=%0t: Quantum lock override released", $time);
        # (CLK_PERIOD * 5);

        // --- Scenario 7: Combined Hazard (AHO) ---
        // This scenario is harder to directly control from testbench inputs
        // as it depends on internal CPU state (branch_mispredicted, exec_pressure_counter, etc.).
        // We'll just let it run and observe if AHO outputs change.
        $display("\nTime=%0t: Scenario 7 - Observing AHO behavior (depends on internal CPU state)", $time);
        // You would typically manipulate internal_entropy_score, ml_predicted_action, etc.
        // in combination to trigger specific AHO thresholds.
        // For now, just let the internal counters evolve.
        # (CLK_PERIOD * 20);

        $display("\n--- Simulation End ---");
        # (CLK_PERIOD * 2); // Give some time for final signals to propagate
        $finish; // End simulation
    end

endmodule
