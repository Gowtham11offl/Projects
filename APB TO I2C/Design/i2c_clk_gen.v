// ============================================================================
// File Name   : i2c_clk_gen.v
// Module Name : i2c_clk_gen (I2C Clock Generator)
// Description : Divides high-speed system clock (PCLK) down to a slower timing
//               tick pulse (clk_en) that dictates the speed of the I2C transfer.
//               Monitors physical SCL feedback to dynamically handle Clock Stretching.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

module i2c_clk_gen ( 
    input  wire        clk,        // System Clock input (e.g., 50MHz APB PCLK)
    input  wire        rst_n,      // Active-low asynchronous system reset
    output reg         clk_en,     // Output tick pulse (asserted High for 1 cycle when counter reaches 0)
    input  wire [15:0] prescale,   // 16-bit clock division factor loaded from PRER register
    input  wire        scl_out,    // SCL command output driven by master Bit Controller (0=pull low, 1=release)
    input  wire        scl_in      // Actual physical voltage level sampled back from the SCL pin
);

    // ========================================================================
    // Internal Registers and Wire Declarations
    // ========================================================================
    reg [15:0] counter;            // 16-bit down-counter register to count clock ticks

    // ------------------------------------------------------------------------
    // Clock Stretching Detection Logic:
    //   If the master releases SCL to float High (scl_out == 1'b1), but the
    //   sampled SCL pin remains Low (scl_in == 1'b0), an external I2C Slave
    //   is holding SCL Low to request additional processing time (clock stretching).
    // ------------------------------------------------------------------------
    wire clk_stretch_active = (scl_out == 1'b1) && (scl_in == 1'b0); // 1 when stretching active

    // ------------------------------------------------------------------------
    // Clock Division & Timing Tick Generation Sequential Process
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin // Triggered on positive clock edge or negative reset edge
        if(!rst_n) begin // Check for active-low asynchronous reset
            // Asynchronous reset: clear the down-counter to zero
            counter <= 16'b0;
            // De-assert clock enable pulse to zero
            clk_en <= 1'b0;
        end else begin // Normal clocked operation
            if (clk_stretch_active) begin // Clock stretching condition detected
                // Slave is holding SCL low: freeze counter at current value
                counter <= counter;
                // Keep clock enable tick Low during stretched periods
                clk_en <= 1'b0;
            end else if(counter == 0) begin // Down-counter reached zero
                // Reload counter with 16-bit prescale factor to start new countdown period
                counter <= prescale;
                // Assert clk_en for 1 clock cycle to advance the Bit Controller FSM
                clk_en <= 1'b1;
            end else begin // Counter is non-zero and no clock stretch active
                // Decrement counter by 1 towards zero
                counter <= counter - 16'd1;
                // Maintain clock enable tick Low between reload ticks
                clk_en <= 1'b0;
            end // End counter evaluation if-else
        end // End reset if-else
    end // End always sequential process

endmodule // End of i2c_clk_gen module
