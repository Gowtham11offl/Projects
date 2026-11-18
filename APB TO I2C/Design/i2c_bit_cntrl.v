// ============================================================================
// File Name   : i2c_bit_cnt.v
// Module Name : i2c_bit_cntr (I2C Bit-Level Controller)
// Description : Handles individual bit operations (START, STOP, Write Bit, Read Bit)
//               on the physical I2C lines using a 4-phase state machine (A, B, C, D)
//               synchronized to the clk_en timing ticks from i2c_clk_gen.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

module i2c_bit_cntr (
    input  wire        clk,        // Main system clock (PCLK)
    input  wire        rst_n,      // Active-low asynchronous reset
    input  wire        clk_en,     // Timing enable tick from Clock Generator (4x per I2C clock period)
    input  wire [3:0]  cmd,        // 4-bit command bus from Byte Controller (START, STOP, WRITE, READ)
    input  wire        din,        // Data bit to send out onto SDA (from Byte Controller shift register)
    output reg         dout,       // Received data bit sampled from SDA line sent back to Byte Controller
    output reg         cmd_ack,    // Command Acknowledge pulse (1 cycle) indicating bit completion
    output reg         scl_oen,    // SCL Output Enable Negated: 0 = drive Low (GND), 1 = release/float (High-Z)
    output reg         sda_oen,    // SDA Output Enable Negated: 0 = drive Low (GND), 1 = release/float (High-Z)
    input  wire        scl_in,     // Actual physical voltage level sampled back from SCL wire
    input  wire        sda_in      // Actual physical voltage level sampled back from SDA wire
);

    // ========================================================================
    // State Encoding: 4 Clock Phases of an I2C Bit Transfer
    // ========================================================================
    localparam state_idle = 3'd0;  // Idle state: waiting for next bit command
    localparam state_A    = 3'd1;  // Phase A (Setup): SCL pulled Low, SDA data placed/stabilized
    localparam state_B    = 3'd2;  // Phase B (Clock Delay): SCL Low, hold time enforced
    localparam state_c    = 3'd3;  // Phase C (Clock High / Sample): SCL released High, SDA sampled
    localparam state_d    = 3'd4;  // Phase D (Data Hold): SCL High, transition back to Low

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [2:0] state;               // FSM current state register (holds 3-bit state)
    reg [3:0] active_cmd;          // Captures cmd to prevent CPU changes from corrupting FSM mid-bit

    // ========================================================================
    // 4-Phase Bit-Level State Machine Sequential Process
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin // Triggered on clock rising edge or reset falling edge
        if(!rst_n) begin // Active-low asynchronous reset condition
            // Clear FSM state to IDLE
            state      <= state_idle;
            // Clear captured command register to 0
            active_cmd <= 4'b0000;
            // De-assert command acknowledge flag
            cmd_ack    <= 1'b0;
            // Release SCL open-drain output (float High)
            scl_oen    <= 1'b1;
            // Release SDA open-drain output (float High)
            sda_oen    <= 1'b1;
            // Initialize dout bit output to 0
            dout       <= 1'b0;
        end else begin // Clocked sequential execution
            cmd_ack <= 1'b0; // Default: pulse acknowledge is Low unless explicitly asserted

            case (state) // Evaluate active FSM state
                // -------------------------------------------------------------
                // STATE_IDLE: Wait for Byte Controller to initiate a bit operation
                // -------------------------------------------------------------
                state_idle : begin
                    // Check for non-zero command while ensuring we don't restart on previous ack
                    if(cmd != 4'b0000 && !cmd_ack) begin
                        active_cmd <= cmd;       // Latch the active command
                        state      <= state_A;   // Advance to Phase A (Setup)
                    end // End command detection check
                end // End state_idle

                // -------------------------------------------------------------
                // STATE_A (Phase A - Data Setup Phase):
                // SCL is pulled Low. SDA is driven according to command.
                // -------------------------------------------------------------
                state_A : begin
                    if(clk_en) begin // Wait for timing enable tick
                        state   <= state_B;      // Advance to Phase B
                        scl_oen <= 1'b0;         // Pull SCL Low (active drive to 0)

                        case(active_cmd) // Drive SDA depending on command type
                            4'b0001 : sda_oen <= 1'b1; // START command: keep SDA High (floating)
                            4'b0010 : sda_oen <= 1'b0; // STOP command: pull SDA Low in preparation
                            4'b0100 : sda_oen <= din;  // WRITE command: place data bit onto SDA
                            4'b1000 : sda_oen <= 1'b1; // READ command: release SDA to High-Z for slave
                            default : ;                // Default: maintain current SDA output enable
                        endcase // End active_cmd case
                    end // End clk_en check
                end // End state_A

                // -------------------------------------------------------------
                // STATE_B (Phase B - Clock Delay / SCL Low):
                // SCL is held Low. Start/Stop transitions prepared.
                // -------------------------------------------------------------
                state_B : begin
                    if(clk_en) begin // Wait for timing enable tick
                        state   <= state_c;      // Advance to Phase C (Clock High)
                        scl_oen <= 1'b1;         // Release SCL to float High (or drive High)

                        case(active_cmd) // Apply Phase B transitions
                            4'b0001 : sda_oen <= 1'b0; // START condition: pull SDA Low while SCL is High
                            4'b0010 : sda_oen <= 1'b0; // STOP condition: keep SDA Low while SCL goes High
                            default : ;                // Normal data bits keep their state from Phase A
                        endcase // End active_cmd case
                    end // End clk_en check
                end // End state_B

                // -------------------------------------------------------------
                // STATE_C (Phase C - Clock High / Data Sample Phase):
                // SCL is High. SDA line is stable and sampled if reading.
                // -------------------------------------------------------------
                state_c : begin
                    if(clk_en) begin // Wait for timing enable tick
                        state   <= state_d;      // Advance to Phase D (Hold)
                        scl_oen <= 1'b1;         // SCL remains released High

                        case(active_cmd) // Apply Phase C actions
                            4'b0010 : sda_oen <= 1'b1;   // STOP condition: release SDA to float High (Low->High)
                            4'b1000 : dout    <= sda_in; // READ command: sample actual SDA wire voltage
                            default : ;                  // Other commands maintain current state
                        endcase // End active_cmd case
                    end // End clk_en check
                end // End state_c

                // -------------------------------------------------------------
                // STATE_D (Phase D - Data Hold / Bit Termination):
                // Concludes the bit cycle and signals completion to Byte Controller.
                // -------------------------------------------------------------
                state_d : begin
                    if(clk_en) begin // Wait for timing enable tick
                        state   <= state_idle;   // Return to IDLE state for next bit command
                        cmd_ack <= 1'b1;         // Pulse acknowledge to notify Byte Controller bit is complete
                        scl_oen <= 1'b0;         // Pull SCL back Low to end the I2C bit clock pulse
                    end // End clk_en check
                end // End state_d
                
                default : state <= state_idle; // Recovery default branch returns to IDLE
            endcase // End state case statement
        end // End reset if-else
    end // End always sequential process

endmodule // End of i2c_bit_cntr module
