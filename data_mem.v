
// =====================================================================
// Data Memory Module
// Features:
// - Simple synchronous read, asynchronous write data memory
// - Can be expanded to different sizes or types
// =====================================================================
module data_mem(
    input wire clk,             // Clock signal for synchronous operation
    input wire mem_write_enable, // Write enable signal
    input wire mem_read_enable,  // Read enable signal (for synchronous read)
    input wire [3:0] addr,       // 4-bit address input
    input wire [3:0] write_data, // 4-bit data to write
    output reg [3:0] read_data   // 4-bit data read
);

    reg [3:0] dmem [0:15]; // 16 entries, 4 bits each

    integer i; // Moved loop variable declaration to module scope

    initial begin
        // Initialize data memory
        for (i = 0; i < 16; i = i + 1) begin // Corrected loop variable declaration
            dmem[i] = 4'h0;
        end
    end

    // Write operation (synchronous)
    always @(posedge clk) begin // Corrected: Used 'begin' here
        if (mem_write_enable) begin
            dmem[addr] <= write_data;
        end
    end

    // Read operation (synchronous, value is stable on next clock cycle)
    always @(posedge clk) begin // Corrected: Used 'begin' here
        if (mem_read_enable) begin
            read_data <= dmem[addr];
        end
    end

endmodule

