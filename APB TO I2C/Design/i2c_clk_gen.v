
`timescale 1ns/1ps  // Simulation time unit = 1ns and precision = 1ps.

// Module responsible for generating the clock enable pulse for I2C timing.
module i2c_clk_gen (

    // ---------------- Input and Output Ports ----------------

    input wire clk,        
    // System clock input (PCLK).

    input wire rst_n,      
    // Active-low asynchronous reset.

    output reg clk_en,     
    // Clock enable pulse sent to the I2C bit controller.

    input wire [15:0] prescale,
    // 16-bit prescaler value used to divide the system clock.

    input wire scl_out,    
    // SCL output control signal from the clock generator interface.

    input wire scl_in      
    // Actual SCL bus level read from the physical I2C bus.

);

    // ---------------- Internal Register ----------------

    reg [15:0] counter;
    // 16-bit counter used to count down the prescaler value.

    // ---------------- Clock Stretching Detection ----------------

    wire clk_stretch_active = (scl_out == 1'b1) && (scl_in == 1'b0);
    // Clock stretching is detected when the master releases SCL (scl_out = 1)
    // but the actual SCL bus remains LOW (scl_in = 0).
    // This usually means an I2C slave is holding SCL LOW.
    // The master must wait until the slave releases SCL.

    // ========================================================================
    // CLOCK DIVISION AND TIMING TICK GENERATION BLOCK
    // Generates periodic clock enable pulses using the prescaler.
    // ========================================================================

    always @(posedge clk or negedge rst_n) begin
    // Execute on every rising edge of clk or falling edge of reset.

        if (!rst_n) begin
        // When reset is LOW, initialize the clock enable output.

            clk_en <= 1'b0;
            // Keep clock enable LOW during reset.

        end else begin
        // Normal operation when reset is HIGH.

            if (clk_stretch_active) begin
            // Check whether the slave is stretching the I2C clock.

                counter <= counter;
                // Hold the counter at its current value.
                // No countdown happens while clock stretching is active.

                clk_en <= 1'b0;
                // Disable the timing pulse until SCL is released.

            end else if (counter == 0) begin
            // When the counter reaches zero, generate a new timing pulse.

                counter <= prescale;
                // Reload the counter with the prescaler value.

                clk_en <= 1'b1;
                // Generate a one-system-clock-cycle enable pulse.

            end else begin
            // If the counter is not zero, continue counting down.

                counter <= counter - 16'd1;
                // Decrement the counter by one on each system clock edge.

                clk_en <= 1'b0;
                // Keep clock enable LOW during countdown.

            end
        end
    end

endmodule
// End of I2C clock generator module.
