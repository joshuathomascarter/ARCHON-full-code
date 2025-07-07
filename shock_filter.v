// ===============================================================================
// NEW MODULE: entropy_shock_filter.v
// Purpose: Detects sudden, significant changes ("shocks") in an analog entropy input.
// ===============================================================================
module entropy_shock_filter (
    input wire clk,
    input wire reset, // Assuming system reset, active high
    input wire [7:0] analog_entropy_in, // 8-bit analog entropy input
    output reg shock_detected
);

reg [7:0] prev_sample; // Stores the previous entropy sample
reg [7:0] delta;       // Stores the absolute difference between current and previous sample

// Parameter: Threshold for detecting a shock. Adjust based on noise characteristics.
parameter [7:0] THRESHOLD = 8'd20; // Example: A change greater than 20 units is a shock

always @(posedge clk or posedge reset) begin
    if (reset) begin
        // On reset, clear previous sample and reset shock detection
        prev_sample <= 8'd0;
        shock_detected <= 1'b0;
    end else begin
        // Calculate the absolute difference between current and previous sample
        // Using unsigned subtraction and then comparison with THRESHOLD
        // This calculates |analog_entropy_in - prev_sample|
        if (analog_entropy_in > prev_sample) begin
            delta <= analog_entropy_in - prev_sample;
        end else begin
            delta <= prev_sample - analog_entropy_in;
        end
        
        // Update the previous sample for the next cycle's comparison
        prev_sample <= analog_entropy_in;

        // Detect shock if the delta exceeds the threshold
        if (delta > THRESHOLD) begin
            shock_detected <= 1'b1;
        end else begin
            shock_detected <= 1'b0;
        end
    end
end
endmodule