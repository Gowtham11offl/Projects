// ============================================================================
// File Name   : i2c_byte_cntr.v
// Module Name : i2c_byte_cntr (I2C Byte-Level Controller)
// Description : Coordinates parallel-to-serial serialization (for Writes) and
//               serial-to-parallel deserialization (for Reads) of 8-bit bytes.
//               Drives bit-level commands (START, STOP, Bit Write, Bit Read) to
//               the Bit Controller and manages the 9th ACK/NACK bit.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

module i2c_byte_cntr (
    input  wire        clk,        // Main system clock (PCLK)
    input  wire        rst_n,      // Active-low asynchronous reset
    input  wire [7:0]  din,        // Data byte to transmit (loaded from TXR register)
    input  wire        ack_in,     // Master ACK response to send when reading from slave (0=ACK, 1=NACK)
    input  wire        start,      // Start transfer request flag (derived from cr[7] & ctr[7])
    input  wire        write,      // Write transfer request flag (derived from cr[4] & ctr[7])
    input  wire        read,       // Read transfer request flag (derived from cr[5] & ctr[7])
    input  wire        stop,       // Stop transfer request flag (derived from cr[6] & ctr[7])
    output reg  [7:0]  dout,       // Received 8-bit byte from I2C bus (sent to RXR register)
    output reg         cmd_ack,    // Byte transfer complete pulse (clears cr command register in top wrapper)
    output reg         ack_out,    // Latch holding 9th ACK bit sampled from Slave (sent to sr[7])
    output reg         i2c_busy,   // I2C bus busy indicator (sent to sr[6] and sr[1] status bits)
    output reg  [3:0]  bit_cmd,    // 4-bit command bus sent to Bit Controller (START/STOP/Read/Write)
    output reg         bit_din,    // Individual data bit serialized and sent to Bit Controller
    input  wire        bit_ack,    // Single-bit transfer completion acknowledge pulse from Bit Controller
    input  wire        bit_dout    // Individual data bit sampled by Bit Controller during reads
);

    // ========================================================================
    // State Encoding: Byte-Level Operation States
    // ========================================================================
    localparam state_idle  = 3'd0; // Idle state: waiting for CPU command
    localparam state_start = 3'd1; // Generating I2C START condition
    localparam state_data  = 3'd2; // Shifting 8 bits of data (serialize or deserialize)
    localparam state_ack   = 3'd3; // Exchanging the 9th ACK/NACK bit with slave
    localparam state_stop  = 3'd4; // Generating I2C STOP condition
    localparam state_done  = 3'd5; // Final completion state: pulses cmd_ack and clears status

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [2:0] state;               // Current state register of the byte-level FSM
    reg [2:0] bit_counter;         // Counts bits from 7 down to 0 for 8-bit serialization
    reg [7:0] shift_reg;           // Internal shift register holding transmitted/received byte

    // ========================================================================
    // Byte-Level State Machine Sequential Process
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin // Triggered on positive clock edge or negative reset edge
        if(!rst_n) begin // Active-low asynchronous reset
            // Reset FSM state to IDLE
            state       <= state_idle;
            // Clear parallel data output register to 0
            dout        <= 8'h00;
            // Clear command bus to Bit Controller
            bit_cmd     <= 4'b0000;
            // Clear outgoing serialized data bit to 0
            bit_din     <= 1'b0;
            // Clear slave ACK status latch
            ack_out     <= 1'b0;
            // De-assert byte completion acknowledge pulse
            cmd_ack     <= 1'b0;
            // De-assert bus busy indicator flag
            i2c_busy    <= 1'b0;
            // Reset bit counter to 0
            bit_counter <= 3'd0;
            // Clear internal shift register
            shift_reg   <= 8'h00;
        end else begin // Clocked operation
            cmd_ack <= 1'b0; // Default: pulse acknowledge is Low unless transfer is complete

            case(state) // Evaluate active FSM state
                // -------------------------------------------------------------
                // STATE_IDLE: Wait for CPU to issue command (START, WRITE, READ, STOP)
                // -------------------------------------------------------------
                state_idle : begin 
                    // Check if any operation command is active and ensure we don't repeat on same ack cycle
                    if((start || write || read || stop) && !cmd_ack) begin
                        i2c_busy  <= 1'b1;         // Assert bus busy status flag
                        shift_reg <= din;          // Preload transmit byte from din into shift register
                        
                        if (start) begin // START condition commanded
                            state   <= state_start;
                            bit_cmd <= 4'b0001;    // Issue START command (0001) to Bit Controller
                        end else begin // Direct data transfer (no START requested)
                            state       <= state_data; // Advance directly to data serialization phase
                            bit_counter <= 3'd7;       // Initialize countdown counter to 7 (for 8 bits: 7 down to 0)
                            if(write) begin // Write transfer mode
                                bit_cmd <= 4'b0100;    // Issue Bit WRITE command (0100) to Bit Controller
                                bit_din <= din[7];     // Drive MSB (Bit 7) onto bit_din first
                            end else begin // Read transfer mode
                                bit_cmd <= 4'b1000;    // Issue Bit READ command (1000) to Bit Controller
                            end // End write/read check
                        end // End start check
                    end else begin // No commands pending
                        i2c_busy <= 1'b0;          // De-assert bus busy indicator
                        bit_cmd  <= 4'b0000;       // Send NO_OP command to Bit Controller
                    end // End command detection check
                end // End state_idle

                // -------------------------------------------------------------
                // STATE_START: Wait for Bit Controller to complete START condition
                // -------------------------------------------------------------
                state_start : begin
                    if(bit_ack) begin // Wait for Bit Controller acknowledge pulse
                        state       <= state_data;     // Advance to data shifting phase
                        bit_counter <= 3'd7;           // Set bit count for 8 bits (7 down to 0)
                        if(write) begin // Transmit data after START
                            bit_din <= shift_reg[7];   // Place MSB on bit_din
                            bit_cmd <= 4'b0100;        // Command Bit Controller to WRITE bit
                        end else begin // Receive data after START
                            bit_cmd <= 4'b1000;        // Command Bit Controller to READ bit
                        end // End write check
                    end // End bit_ack check
                end // End state_start

                // -------------------------------------------------------------
                // STATE_DATA: Shift 8 data bits across bus (one bit at a time)
                // -------------------------------------------------------------
                state_data : begin
                    if(bit_ack) begin // Wait for each bit completion pulse from Bit Controller
                        if(read) begin // Read mode
                            // Shift left and append received bit at LSB
                            shift_reg <= (shift_reg << 1) | bit_dout;
                        end else begin // Write mode
                            // Shift left to prepare next outgoing bit
                            shift_reg <= shift_reg << 1;
                        end // End read/write shift update
                        
                        if (bit_counter == 3'd0) begin // Completed all 8 bits (0 through 7)
                            state <= state_ack; // Advance to 9th ACK phase
                            if(write) begin // Following a write transfer
                                bit_cmd <= 4'b1000; // Bit Controller must READ the ACK from the slave
                            end else begin // Following a read transfer
                                bit_cmd <= 4'b0100; // Bit Controller must WRITE our ACK response to slave
                                bit_din <= ack_in;  // Send master's ACK setting (0=ACK, 1=NACK)
                            end // End write/read ACK setup
                        end else begin // More data bits remain to be shifted
                            bit_counter <= bit_counter - 3'd1; // Decrement bit counter
                            if(write) begin // Write mode
                                bit_cmd <= 4'b0100;      // Continue Bit WRITE command
                                bit_din <= shift_reg[6]; // Place next MSB (bit 6 of pre-shift reg)
                            end else begin // Read mode
                                bit_cmd <= 4'b1000;      // Continue Bit READ command
                            end // End write/read continuation
                        end // End bit_counter completion check
                    end // End bit_ack check
                end // End state_data

                // -------------------------------------------------------------
                // STATE_ACK: Manage 9th ACK bit and transition to STOP or DONE
                // -------------------------------------------------------------
                state_ack : begin
                    if(bit_ack) begin // Wait for 9th ACK bit operation to complete
                        if(write) begin // On write, capture slave's ACK response
                            ack_out <= bit_dout; // 0 = slave ACK, 1 = slave NACK
                        end // End write capture
                        if(read) begin // On read, finalize collected byte
                            dout <= shift_reg;   // Latch assembled 8-bit byte for CPU access
                        end // End read capture
                        
                        if(stop) begin // STOP condition requested by CPU
                            state   <= state_stop;
                            bit_cmd <= 4'b0010;  // Issue STOP command (0010) to Bit Controller
                        end else begin // No STOP requested (e.g. repeated start or continuous transfer)
                            state   <= state_done; // Advance directly to completion state
                        end // End stop check
                    end // End bit_ack check
                end // End state_ack

                // -------------------------------------------------------------
                // STATE_STOP: Wait for Bit Controller to complete STOP condition
                // -------------------------------------------------------------
                state_stop : begin
                    if(bit_ack) begin // Wait for STOP pulse completion
                        state <= state_done; // Advance to completion state
                    end // End bit_ack check
                end // End state_stop

                // -------------------------------------------------------------
                // STATE_DONE: Pulse acknowledge to clear CPU Command Register
                // -------------------------------------------------------------
                state_done : begin
                    cmd_ack <= 1'b1;       // Assert 1-cycle acknowledge pulse to clear cr register
                    state   <= state_idle; // Return to IDLE state ready for next command
                end // End state_done

                default : state <= state_idle; // Safe recovery default returns to IDLE
            endcase // End state case statement
        end // End reset if-else
    end // End always sequential process

endmodule // End of i2c_byte_cntr module
