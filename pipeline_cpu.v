module pipeline_cpu(
    input wire clk,
    input wire reset, // Active high reset (converts to active low for some modules)
    input wire [15:0] external_entropy_in, // Input from entropy_bus.txt (for Entropy Control Logic)
    input wire [7:0] analog_entropy_raw_in, // Raw analog entropy for shock filter and decoder
    input wire [1:0] ml_predicted_action, // ML model's predicted action for AHO and FSM
    input wire internal_hazard_flag_for_fsm, // This is an input to pipeline_cpu from archon_top

    input wire analog_lock_override_in,  // From top-level analog controller
    input wire analog_flush_override_in, // From top-level analog controller
    input wire quantum_override_signal_in, // Quantum override signal from Qiskit simulation

    // NEW Military-Grade Control Inputs for FSM
    input wire [1:0] mission_profile_in,        // Mission profile for FSM
    input wire override_authentication_valid_in, // Authentication signal for overrides
    input wire [7:0] entropy_threshold_fsm_in,  // Dynamic entropy threshold for FSM

    output wire [3:0] debug_pc,         // For debugging: current PC
    output wire [15:0] debug_instr,      // For debugging: current instruction
    output wire debug_stall,            // For debugging: indicates pipeline stall
    output wire debug_flush,            // For debugging: indicates pipeline flush
    output wire debug_lock,             // For debugging: indicates system lock
    output wire [7:0] debug_fsm_entropy_log, // For debugging: entropy value logged by new FSM
    output wire [2:0] debug_fsm_instr_type_log, // Debug output for logged instruction type
    output wire debug_hazard_flag,      // Expose the internal hazard flag
    output wire [1:0] debug_fsm_state,  // Expose the FSM state
    output wire debug_shock_detected,   // Expose shock detected from filter
    output wire [1:0] debug_classified_entropy // Expose classified entropy from decoder
);

    // --- Active Low Reset for Modules that use it ---
    wire rst_n = ~reset;

    // --- Internal Wires & Registers for Pipeline Stages ---
    reg [3:0] pc_reg;
    wire [15:0] if_instr;
    wire [3:0] if_pc_plus_1;
    reg [3:0] next_pc;

    reg [3:0] if_id_pc_plus_1_reg;
    reg [15:0] if_id_instr_reg;

    wire [3:0] id_pc_plus_1;
    wire [15:0] id_instr;
    wire [3:0] id_operand1;
    wire [3:0] id_operand2;
    wire [2:0] id_rs1_addr;
    wire [2:0] id_rs2_addr;
    wire [2:0] id_rd_addr;
    reg [2:0] id_alu_op;
    wire [3:0] id_immediate;
    wire id_reg_write_enable;
    wire id_mem_read_enable;
    wire id_mem_write_enable;
    wire id_is_branch_inst;
    wire id_is_jump_inst;
    wire [3:0] id_branch_target;

    reg [2:0] instr_type_to_fsm_comb;
    reg [2:0] instr_type_to_fsm_reg;    // Registered instruction type for FSM input

    wire [3:0] ex_opcode_from_ex_stage; // Wire to hold opcode from EX stage

    reg [3:0] id_ex_pc_plus_1_reg;
    reg [3:0] id_ex_operand1_reg;
    reg [3:0] id_ex_operand2_reg;
    reg [2:0] id_ex_rd_addr_reg;
    reg [2:0] id_ex_alu_op_reg;
    reg id_ex_reg_write_enable_reg;
    reg id_ex_mem_read_enable_reg;
    reg id_ex_mem_write_enable_reg;
    reg id_ex_is_branch_inst_reg;
    reg id_ex_is_jump_inst_reg;
    reg [3:0] id_ex_branch_target_reg;
    reg [15:0] id_ex_instr_reg;
    reg [3:0] id_ex_branch_pc_reg;

    wire [3:0] ex_alu_operand1;
    wire [3:0] ex_alu_operand2;
    wire [3:0] ex_alu_result;
    wire ex_zero_flag;
    wire ex_negative_flag;
    wire ex_carry_flag;
    wire ex_overflow_flag;
    wire [2:0] ex_rd_addr;
    wire ex_reg_write_enable;
    wire ex_mem_read_enable;
    wire ex_mem_write_enable;
    wire ex_is_branch_inst;
    wire ex_is_jump_inst;
    wire [3:0] ex_branch_target;
    wire [3:0] ex_branch_pc;

    reg [3:0] ex_mem_alu_result_reg;
    reg [3:0] ex_mem_mem_write_data_reg;
    reg [2:0] ex_mem_rd_addr_reg;
    reg ex_mem_reg_write_enable_reg;
    reg ex_mem_mem_read_enable_reg;
    reg ex_mem_mem_write_enable_reg;
    reg ex_mem_zero_flag_reg;
    reg ex_mem_is_branch_inst_reg;
    reg ex_mem_is_jump_inst_reg;
    reg [3:0] ex_mem_pc_plus_1_reg;
    reg [3:0] ex_mem_branch_target_reg;
    reg [3:0] ex_mem_branch_pc_reg;

    wire [3:0] mem_read_data;
    wire [3:0] mem_alu_result;
    wire [2:0] mem_rd_addr;
    wire mem_reg_write_enable;
    wire mem_mem_read_enable;
    wire mem_mem_write_enable;
    wire [3:0] mem_mem_addr;

    wire branch_actual_taken;
    wire branch_mispredicted_local;
    reg branch_mispredicted;
    wire [3:0] branch_resolved_pc;
    wire [3:0] branch_resolved_target_pc;

    reg [3:0] mem_wb_write_data_reg;
    reg [2:0] mem_wb_rd_addr_reg;
    reg mem_wb_reg_write_enable_reg;

    wire [3:0] wb_write_data;
    wire [2:0] wb_rd_addr;
    wire wb_reg_write_enable;

    // --- Pipeline Control Signals ---
    wire pipeline_stall;
    wire pipeline_flush;

    // For simplicity, tracking rough execution pressure
    reg [7:0] exec_pressure_counter;
    reg [7:0] cache_miss_rate_dummy; // Dummy value, requires actual cache model to be meaningful

    // AHO internal hazard signals
    wire aho_override_flush_req;
    wire aho_override_stall_req;
    wire [1:0] aho_hazard_level;

    // Consolidated internal hazard flag for the new FSM
    wire new_fsm_internal_hazard_flag;
    wire [1:0] new_fsm_control_signal;
    wire [7:0] new_fsm_entropy_log;
    wire [2:0] new_fsm_instr_type_log;
    wire shock_detected_internal; // Internal wire for shock filter output

    localparam AHO_SCALED_FLUSH_THRESH = 21'd1000000; // Example threshold
    localparam AHO_SCALED_STALL_THRESH = 21'd500000;  // Example threshold

    wire [1:0] classified_entropy_level_wire; // Internal wire for classified entropy

    wire [7:0] debug_branch_miss_rate;
    reg [7:0] branch_miss_rate_counter;

    wire pd_anomaly_detected_out;
    wire pd_reset; // Correctly declare pd_reset

    // --- Instantiate Sub-modules ---
    instruction_ram i_imem (
        .clk(clk),
        .reset(reset),
        .pc_in(pc_reg),
        .instr_opcode(if_instr)
    );

    register_file i_regfile (
        .clk(clk),
        .reset(reset),
        .regfile_write_enable(wb_reg_write_enable),
        .write_addr(wb_rd_addr),
        .write_data(wb_write_data),
        .read_addr1(id_rs1_addr),
        .read_addr2(id_rs2_addr),
        .read_data1(id_operand1),
        .read_data2(id_operand2)
    );

    alu_unit i_alu (
        .alu_operand1(ex_alu_operand1),
        .alu_operand2(ex_alu_operand2),
        .alu_op(id_ex_alu_op_reg),
        .alu_result(ex_alu_result),
        .zero_flag(ex_zero_flag),
        .negative_flag(ex_negative_flag),
        .carry_flag(ex_carry_flag),
        .overflow_flag(ex_overflow_flag)
    );

    data_mem i_dmem (
        .clk(clk),
        .mem_write_enable(mem_mem_write_enable),
        .mem_read_enable(mem_mem_read_enable),
        .addr(mem_mem_addr),
        .write_data(ex_mem_mem_write_data_reg),
        .read_data(mem_read_data)
    );

    wire [3:0] if_btb_predicted_next_pc;
    wire if_btb_predicted_taken;
    branch_target_buffer i_btb (
        .clk(clk),
        .reset(reset),
        .pc_in(pc_reg),
        .branch_resolved_pc(branch_resolved_pc),
        .branch_resolved_pc_valid(ex_mem_is_branch_inst_reg || ex_mem_is_jump_inst_reg),
        .branch_resolved_target_pc(branch_resolved_target_pc),
        .branch_resolved_taken(branch_actual_taken),
        .predicted_next_pc(if_btb_predicted_next_pc),
        .predicted_taken(if_btb_predicted_taken)
    );

    wire [3:0] qed_instr_opcode_input;
    assign qed_instr_opcode_input = id_ex_instr_reg[15:12];
    wire qed_reset = reset;
    wire [7:0] qed_entropy_score_out;
    quantum_entropy_detector i_qed (
        .clk(clk),
        .reset(qed_reset),
        .instr_opcode(qed_instr_opcode_input),
        .alu_result(ex_alu_result),
        .zero_flag(ex_zero_flag),
        .entropy_score_out(qed_entropy_score_out)
    );

    wire cd_reset = reset;
    wire [15:0] cd_chaos_score_out;
    chaos_detector i_chaos_detector (
        .clk(clk),
        .reset(cd_reset),
        .branch_mispredicted(branch_mispredicted),
        .mem_access_addr(mem_mem_addr),
        .data_mem_read_data(mem_read_data),
        .chaos_score_out(cd_chaos_score_out)
    );

    assign pd_reset = reset; // Connect pd_reset
    pattern_detector i_pattern_detector (
        .clk(clk),
        .reset(pd_reset),
        .zero_flag_current(ex_zero_flag),
        .negative_flag_current(ex_negative_flag),
        .carry_flag_current(ex_carry_flag),
        .overflow_flag_current(ex_overflow_flag),
        .anomaly_detected_out(pd_anomaly_detected_out)
    );

    entropy_shock_filter u_entropy_shock_filter (
        .clk(clk),
        .reset(reset),
        .analog_entropy_in(analog_entropy_raw_in),
        .shock_detected(shock_detected_internal)
    );

    // This block is the sole driver for branch_miss_rate_counter
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            branch_miss_rate_counter <= 8'h0;
        end else begin
            if (~pipeline_stall && ~pipeline_flush) begin
                if (branch_mispredicted) begin
                    if (branch_miss_rate_counter < 8'hFF) begin
                        branch_miss_rate_counter <= branch_miss_rate_counter + 8'h1;
                    end
                end else begin
                    if (branch_miss_rate_counter > 8'h0) begin
                        branch_miss_rate_counter <= branch_miss_rate_counter - 8'h1;
                    end
                end
            end
        end
    end

    assign debug_branch_miss_rate = branch_miss_rate_counter;

    archon_hazard_override_unit i_aho (
        .clk(clk),
        .rst_n(rst_n),
        .internal_entropy_score_val(qed_entropy_score_out),
        .chaos_score_val(cd_chaos_score_out),
        .anomaly_detected_val(pd_anomaly_detected_out),
        .branch_miss_rate_tracker(debug_branch_miss_rate),
        .cache_miss_rate_tracker(cache_miss_rate_dummy),
        .exec_pressure_tracker(exec_pressure_counter),
        .ml_predicted_action(ml_predicted_action),
        .scaled_flush_threshold(AHO_SCALED_FLUSH_THRESH),
        .scaled_stall_threshold(AHO_SCALED_STALL_THRESH),
        .override_flush_sig(aho_override_flush_req),
        .override_stall_sig(aho_override_stall_req),
        .hazard_detected_level(aho_hazard_level)
    );

    entropy_trigger_decoder i_entropy_decoder (
        .entropy_in(analog_entropy_raw_in), // Connect to the raw analog entropy input
        .signal_class(classified_entropy_level_wire)
    );

    // Assign the opcode from the EX stage for FSM instruction type logging
    assign ex_opcode_from_ex_stage = id_ex_instr_reg[15:12];

    // Combinational assignment for instruction type
    always @(*) begin
        case (ex_opcode_from_ex_stage)
            4'h1, 4'h2, 4'h3, 4'h6: instr_type_to_fsm_comb = 3'b000; // ALU
            4'h4:                   instr_type_to_fsm_comb = 3'b001; // LOAD
            4'h5:                   instr_type_to_fsm_comb = 3'b010; // STORE
            4'h7:                   instr_type_to_fsm_comb = 3'b011; // BRANCH
            4'h8:                   instr_type_to_fsm_comb = 3'b100; // JUMP
            default:                instr_type_to_fsm_comb = 3'b111; // OTHER (e.g., NOP or unmapped)
        endcase
    end

    // Synchronously register the instruction type for FSM input
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            instr_type_to_fsm_reg <= 3'b111; // Default to OTHER on reset
        end else begin
            if (~pipeline_stall && ~pipeline_flush) begin
                instr_type_to_fsm_reg <= instr_type_to_fsm_comb;
            end
        end
    end

    // NEW: Entropy-Aware FSM
    // Consolidate AHO's requests with the 'internal_hazard_flag_for_fsm' input
    assign new_fsm_internal_hazard_flag = aho_override_flush_req || aho_override_stall_req || internal_hazard_flag_for_fsm;

    fsm_entropy_overlay i_entropy_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .ml_predicted_action(ml_predicted_action),
        .internal_entropy_score(qed_entropy_score_out),
        .internal_hazard_flag(new_fsm_internal_hazard_flag),
        .classified_entropy_level(classified_entropy_level_wire),
        .instr_type(instr_type_to_fsm_reg),

        .analog_lock_override(analog_lock_override_in),
        .analog_flush_override(analog_flush_override_in),
        .quantum_override_signal(quantum_override_signal_in),
        .shock_detected_in(shock_detected_internal), // NEW: Connect shock filter output

        // NEW Military-Grade Control Inputs (passed from pipeline_cpu's ports)
        .mission_profile_in(mission_profile_in),
        .override_authentication_valid_in(override_authentication_valid_in),
        .entropy_threshold_fsm_in(entropy_threshold_fsm_in),
        
        .fsm_state(new_fsm_control_signal),
        .entropy_log_out(new_fsm_entropy_log),
        .instr_type_log_out(new_fsm_instr_type_log)
    );

    wire entropy_ctrl_stall;
    wire entropy_ctrl_flush;
    // Assuming entropy_control_logic exists elsewhere or is a placeholder
    // If this module is not provided, you'll need to define it or remove this instantiation.
    /*
    entropy_control_logic i_entropy_ctrl (
        .external_entropy_in(external_entropy_in),
        .entropy_stall(entropy_ctrl_stall),
        .entropy_flush(entropy_ctrl_flush)
    );
    */
    // For now, if entropy_control_logic is not defined, tie these off to avoid errors.
    assign entropy_ctrl_stall = 1'b0;
    assign entropy_ctrl_flush = 1'b0;


    // --- Pipeline Control Unit ---
    assign pipeline_flush = (new_fsm_control_signal == 2'b10) || // FSM recommends FLUSH
                            (new_fsm_control_signal == 2'b11) || // FSM recommends LOCK (also implies flush)
                            entropy_ctrl_flush;                   // Old entropy control also recommends flush

    assign pipeline_stall = (new_fsm_control_signal == 2'b01) || // FSM recommends STALL
                            (new_fsm_control_signal == 2'b11) || // FSM recommends LOCK (also implies stall)
                            entropy_ctrl_stall;                   // Old entropy control also recommends stall

    // --- Execution Pressure Counter ---
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            exec_pressure_counter <= 8'h0;
            cache_miss_rate_dummy <= 8'h0;
        end else begin
            if (pipeline_flush) begin
                exec_pressure_counter <= 8'h0;
                cache_miss_rate_dummy <= 8'h0;
            end else if (~pipeline_stall) begin
                if (id_ex_instr_reg[15:12] != 4'h9) begin // Assuming 4'h9 is a NOP or low-pressure instruction
                    if (exec_pressure_counter < 8'hFF) begin
                        exec_pressure_counter <= exec_pressure_counter + 8'h1;
                    end
                end else begin
                    if (exec_pressure_counter > 8'h0) begin
                        exec_pressure_counter <= exec_pressure_counter - 8'h1;
                    end
                end
                // Dummy cache miss rate logic
                if (cache_miss_rate_dummy < 8'hFF && (exec_pressure_counter % 5 == 0)) begin
                    cache_miss_rate_dummy <= cache_miss_rate_dummy + 8'h1;
                end else if (cache_miss_rate_dummy > 8'h0 && (exec_pressure_counter % 7 == 0)) begin
                    cache_miss_rate_dummy <= cache_miss_rate_dummy - 8'h1;
                end
            end
        end
    end

    // --- IF Stage ---
    assign if_pc_plus_1 = pc_reg + 4'b0001;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_reg <= 4'h0;
        end else begin
            if (pipeline_flush) begin
                pc_reg <= 4'h0;
            end else if (pipeline_stall) begin
                pc_reg <= pc_reg;
            end else begin
                pc_reg <= next_pc;
            end
        end
    end

    always @(*) begin
        next_pc = if_pc_plus_1;

        if (ex_mem_is_jump_inst_reg) begin
            next_pc = ex_mem_branch_target_reg;
        end else if (ex_mem_is_branch_inst_reg) begin
            if (branch_actual_taken) begin
                next_pc = ex_mem_branch_target_reg;
            end else begin
                next_pc = ex_mem_pc_plus_1_reg;
            end
        end else if (if_btb_predicted_taken) begin
            next_pc = if_btb_predicted_next_pc;
        end
    end

    // IF-ID Pipeline Register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            if_id_pc_plus_1_reg <= 4'h0;
            if_id_instr_reg <= 16'h0000;
        end else begin
            if (~pipeline_flush && ~pipeline_stall) begin
                if_id_pc_plus_1_reg <= if_pc_plus_1;
                if_id_instr_reg <= if_instr;
            end
        end
    end

    // --- ID Stage ---
    assign id_pc_plus_1 = if_id_pc_plus_1_reg;
    assign id_instr = if_id_instr_reg;

    wire [3:0] id_opcode = id_instr[15:12];
    assign id_rd_addr = id_instr[11:9];
    assign id_rs1_addr = id_instr[8:6];
    assign id_rs2_addr = id_instr[5:3];
    assign id_immediate = {1'b0, id_instr[2:0]};

    assign id_reg_write_enable = (id_opcode == 4'h1 || id_opcode == 4'h2 || id_opcode == 4'h3 ||
                                  id_opcode == 4'h4 || id_opcode == 4'h6 || id_opcode == 4'h0);
    assign id_mem_read_enable  = (id_opcode == 4'h4);
    assign id_mem_write_enable = (id_opcode == 4'h5);
    assign id_is_branch_inst   = (id_opcode == 4'h7);
    assign id_is_jump_inst     = (id_opcode == 4'h8);
    assign id_branch_target    = id_instr[3:0];

    always @(*) begin
        case (id_opcode)
            4'h1: id_alu_op = 3'b000; // ADD
            4'h2: id_alu_op = 3'b000; // SUB
            4'h3: id_alu_op = 3'b001; // AND
            4'h4: id_alu_op = 3'b000; // LOAD
            4'h5: id_alu_op = 3'b000; // STORE
            4'h6: id_alu_op = 3'b100; // XOR
            4'h7: id_alu_op = 3'b001; // BEQ
            default: id_alu_op = 3'b000; // Default ALU operation
        endcase
    end

    wire ex_mem_writes_to_rs1_id = ex_mem_reg_write_enable_reg && (ex_mem_rd_addr_reg == id_rs1_addr);
    wire ex_mem_writes_to_rs2_id = ex_mem_reg_write_enable_reg && (ex_mem_rd_addr_reg == id_rs2_addr);
    wire mem_wb_writes_to_rs1_id = mem_wb_reg_write_enable_reg && (mem_wb_rd_addr_reg == id_rs1_addr);
    wire mem_wb_writes_to_rs2_id = mem_wb_reg_write_enable_reg && (mem_wb_rd_addr_reg == id_rs2_addr);

    wire [3:0] forward_operand1 = (ex_mem_writes_to_rs1_id && (id_rs1_addr != 3'b000)) ? ex_mem_alu_result_reg :
                                  (mem_wb_writes_to_rs1_id && (id_rs1_addr != 3'b000)) ? mem_wb_write_data_reg :
                                  id_operand1;
    wire [3:0] forward_operand2 = (ex_mem_writes_to_rs2_id && (id_rs2_addr != 3'b000)) ? ex_mem_alu_result_reg :
                                  (mem_wb_writes_to_rs2_id && (id_rs2_addr != 3'b000)) ? mem_wb_write_data_reg :
                                  id_operand2;

    // ID-EX Pipeline Register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            id_ex_pc_plus_1_reg <= 4'h0;
            id_ex_operand1_reg <= 4'h0;
            id_ex_operand2_reg <= 4'h0;
            id_ex_rd_addr_reg <= 3'h0;
            id_ex_alu_op_reg <= 3'h0;
            id_ex_reg_write_enable_reg <= 1'b0;
            id_ex_mem_read_enable_reg <= 1'b0;
            id_ex_mem_write_enable_reg <= 1'b0;
            id_ex_is_branch_inst_reg <= 1'b0;
            id_ex_is_jump_inst_reg <= 1'b0;
            id_ex_branch_target_reg <= 4'h0;
            id_ex_instr_reg <= 16'h0000;
            id_ex_branch_pc_reg <= 4'h0;
        end else begin
            if (~pipeline_flush && ~pipeline_stall) begin
                id_ex_pc_plus_1_reg <= id_pc_plus_1;
                id_ex_operand1_reg <= forward_operand1;
                id_ex_operand2_reg <= (id_opcode == 4'h2 || id_opcode == 4'h4 || id_opcode == 4'h5) ? id_immediate : forward_operand2;
                id_ex_rd_addr_reg <= id_rd_addr;
                id_ex_alu_op_reg <= id_alu_op;
                id_ex_reg_write_enable_reg <= id_reg_write_enable;
                id_ex_mem_read_enable_reg <= id_mem_read_enable;
                id_ex_mem_write_enable_reg <= id_mem_write_enable;
                id_ex_is_branch_inst_reg <= id_is_branch_inst;
                id_ex_is_jump_inst_reg <= id_is_jump_inst;
                id_ex_branch_target_reg <= id_branch_target;
                id_ex_instr_reg <= id_instr;
                id_ex_branch_pc_reg <= id_pc_plus_1 - 4'h1;
            end
        end
    end

    // --- EX Stage ---
    assign ex_alu_operand1 = id_ex_operand1_reg;
    assign ex_alu_operand2 = id_ex_operand2_reg;
    assign ex_rd_addr = id_ex_rd_addr_reg;
    assign ex_reg_write_enable = id_ex_reg_write_enable_reg;
    assign ex_mem_read_enable = id_ex_mem_read_enable_reg;
    assign ex_mem_write_enable = id_ex_mem_write_enable_reg;
    assign ex_is_branch_inst = id_ex_is_branch_inst_reg;
    assign ex_is_jump_inst = id_ex_is_jump_inst_reg;
    assign ex_branch_target = id_ex_branch_target_reg;
    assign ex_branch_pc = id_ex_branch_pc_reg;

    wire [3:0] actual_branch_target_calc;
    assign actual_branch_target_calc = ex_branch_pc + ex_branch_target;

    // EX-MEM Pipeline Register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ex_mem_alu_result_reg       <= 4'h0;
            ex_mem_mem_write_data_reg   <= 4'h0;
            ex_mem_rd_addr_reg          <= 3'h0;
            ex_mem_reg_write_enable_reg <= 1'b0;
            ex_mem_mem_read_enable_reg  <= 1'b0;
            ex_mem_mem_write_enable_reg <= 1'b0;
            ex_mem_zero_flag_reg        <= 1'b0;
            ex_mem_is_branch_inst_reg   <= 1'b0;
            ex_mem_is_jump_inst_reg     <= 1'b0;
            ex_mem_pc_plus_1_reg        <= 4'h0;
            ex_mem_branch_target_reg    <= 4'h0;
            ex_mem_branch_pc_reg        <= 4'h0;
        end else begin
            if (~pipeline_flush && ~pipeline_stall) begin
                ex_mem_alu_result_reg       <= ex_alu_result;
                ex_mem_mem_write_data_reg   <= ex_alu_operand2;
                ex_mem_rd_addr_reg          <= ex_rd_addr;
                ex_mem_reg_write_enable_reg <= ex_reg_write_enable;
                ex_mem_mem_read_enable_reg  <= ex_mem_read_enable;
                ex_mem_mem_write_enable_reg <= ex_mem_write_enable;
                ex_mem_zero_flag_reg        <= ex_zero_flag;
                ex_mem_is_branch_inst_reg   <= ex_is_branch_inst;
                ex_mem_is_jump_inst_reg     <= ex_is_jump_inst;
                ex_mem_pc_plus_1_reg        <= id_ex_pc_plus_1_reg;
                ex_mem_branch_target_reg    <= actual_branch_target_calc;
                ex_mem_branch_pc_reg        <= ex_branch_pc;
            end
        end
    end

    // --- MEM Stage ---
    assign mem_alu_result = ex_mem_alu_result_reg;
    assign mem_rd_addr = ex_mem_rd_addr_reg;
    assign mem_reg_write_enable = ex_mem_reg_write_enable_reg;
    assign mem_mem_read_enable = ex_mem_mem_read_enable_reg;
    assign mem_mem_write_enable = ex_mem_mem_write_enable_reg;
    assign mem_mem_addr = ex_mem_alu_result_reg;

    // Combinational logic for branch resolution and misprediction detection
    assign branch_actual_taken = ex_mem_is_branch_inst_reg && ex_mem_zero_flag_reg;
    assign branch_resolved_pc = ex_mem_branch_pc_reg;
    assign branch_resolved_target_pc = ex_mem_branch_target_reg;

    assign branch_mispredicted_local =
        (ex_mem_is_branch_inst_reg || ex_mem_is_jump_inst_reg) ?
            (ex_mem_is_branch_inst_reg ?
                ((if_btb_predicted_taken != branch_actual_taken) ||
                 (branch_actual_taken && (if_btb_predicted_next_pc != branch_resolved_target_pc))) :
                (ex_mem_is_jump_inst_reg && (if_btb_predicted_next_pc != branch_resolved_target_pc))) : 1'b0;

    // Sequential registration for branch_mispredicted
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            branch_mispredicted <= 1'b0;
        end else begin
            if (~pipeline_stall && ~pipeline_flush) begin
                branch_mispredicted <= branch_mispredicted_local;
            end
        end
    end

    // MEM-WB Pipeline Register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_wb_write_data_reg <= 4'h0;
            mem_wb_rd_addr_reg <= 3'h0;
            mem_wb_reg_write_enable_reg <= 1'b0;
        end else begin
            if (~pipeline_flush && ~pipeline_stall) begin
                if (mem_mem_read_enable) begin
                    mem_wb_write_data_reg <= mem_read_data;
                end else begin
                    mem_wb_write_data_reg <= mem_alu_result;
                end
                mem_wb_rd_addr_reg <= mem_rd_addr;
                mem_wb_reg_write_enable_reg <= mem_reg_write_enable;
            end
        end
    end

    // --- WB Stage ---
    assign wb_write_data = mem_wb_write_data_reg;
    assign wb_rd_addr = mem_wb_rd_addr_reg;
    assign wb_reg_write_enable = mem_wb_reg_write_enable_reg;

    // --- Debug Outputs ---
    assign debug_pc = pc_reg;
    assign debug_instr = if_instr;
    assign debug_stall = pipeline_stall;
    assign debug_flush = pipeline_flush;
    assign debug_lock = (new_fsm_control_signal == 2'b11);
    assign debug_fsm_entropy_log = new_fsm_entropy_log;
    assign debug_fsm_instr_type_log = new_fsm_instr_type_log;
    assign debug_hazard_flag = new_fsm_internal_hazard_flag;
    assign debug_fsm_state = new_fsm_control_signal;
    assign debug_shock_detected = shock_detected_internal;
    assign debug_classified_entropy = classified_entropy_level_wire;
