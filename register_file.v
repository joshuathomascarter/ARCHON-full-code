
// =====================================================================
// Register File Module
// Features:
// - 8 4-bit registers (R0-R7)
// - R0 is hardwired to 0
// - Dual read ports for simultaneous operand fetching
// - Single write port for result write-back
// =====================================================================
module register_file(
    input wire clk,             // Clock signal for synchronous write
    input wire reset,           // Reset signal
    input wire regfile_write_enable, // Enable signal for write operation
    input wire [2:0] write_addr, // 3-bit address for write operation
    input wire [3:0] write_data, // 4-bit data to write

    input wire [2:0] read_addr1, // 3-bit address for read port 1
    input wire [2:0] read_addr2, // 3-bit address for read port 2
    output wire [3:0] read_data1, // 4-bit data from read port 1
    output wire [3:0] read_data2  // 4-bit data from read port 2
);

    // 8 registers, each 4 bits wide
    reg [3:0] registers [0:7];

    integer i; // Moved loop variable declaration to module scope

    initial begin
        // Initialize all registers to 0 on startup
        for (i = 0; i < 8; i = i + 1) begin // Corrected loop variable declaration
            registers[i] = 4'h0;
        end
    end

    // Write operation (synchronous)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 8; i = i + 1) begin // Corrected loop variable declaration
                registers[i] = 4'h0;
            end
        end else if (regfile_write_enable) begin
            // R0 is hardwired to 0, so never write to it
            if (write_addr != 3'b000) begin
                registers[write_addr] <= write_data;
            end
        end
    end

    // Read operations (combinational)
    assign read_data1 = (read_addr1 == 3'b000) ? 4'h0 : registers[read_addr1]; // R0 always reads 0
    assign read_data2 = (read_addr2 == 3'b000) ? 4'h0 : registers[read_addr2]; // R0 always reads 0

endmodule

