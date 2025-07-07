// ===============================================================================
// NEW MODULE: entropy_trigger_decoder.v
// Purpose: Simulates compression of incoming analog entropy signals (8-bit)
//          into meaningful trigger vectors or score levels (2-bit).
// ===============================================================================
module entropy_trigger_decoder(
    input wire [7:0] entropy_in,    // 8-bit entropy score (0-255)
    output reg [1:0] signal_class   // 2-bit output: 00 = LOW, 01 = MID, 10 = CRITICAL
);

    // Define thresholds for classification
    parameter THRESHOLD_LOW_TO_MID = 8'd85;     // Up to 85 is LOW
    parameter THRESHOLD_MID_TO_CRITICAL = 8'd170; // Up to 170 is MID, above is CRITICAL

    always @(*) begin
        if (entropy_in <= THRESHOLD_LOW_TO_MID) begin
            signal_class = 2'b00; // LOW
        end else if (entropy_in <= THRESHOLD_MID_TO_CRITICAL) begin
            signal_class = 2'b01; // MID
        end else begin
            signal_class = 2'b10; // CRITICAL
        end
    end

endmodule