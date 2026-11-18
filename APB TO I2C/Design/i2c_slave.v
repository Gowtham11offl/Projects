// ============================================================================
// File Name   : i2c_slave.v
// Module Name : i2c_slave (I2C Slave Behavioral / Simulation Model)
// Description : Emulates an external I2C slave device with configurable 7-bit
//               address (MY_ADDR). Handles START/STOP condition detection,
//               SCL/SDA synchronization, address matching, ACK generation,
//               and byte-level data transmission and reception.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

module i2c_slave #(
    parameter [6:0] MY_ADDR = 7'h5A // The unique 7-bit I2C address assigned to this slave device
)(
    input  wire       clk,        // Main system clock (50 MHz clock for internal logic & synchronizers)
    input  wire       rst_n,      // Active-low asynchronous reset
    inout  wire       sda,        // Bidirectional physical I2C serial data line
    inout  wire       scl,        // Bidirectional physical I2C serial clock line
    output reg  [7:0] data_out,   // 8-bit parallel data byte received by the slave from the master
    output reg        data_valid, // 1-cycle active High pulse indicating a complete new byte is received
    input  wire [7:0] data_in     // 8-bit parallel data byte to transmit to master when read is requested
);

    // ========================================================================
    // 1. Asynchronous Pin Synchronizers (Anti-Metastability Shift Registers)
    // ========================================================================
    // 3-bit shift registers to safely sample asynchronous SCL/SDA lines into 50MHz domain
    reg [2:0] scl_sync; // Shift register for SCL sampling
    reg [2:0] sda_sync; // Shift register for SDA sampling

    always @(posedge clk or negedge rst_n) begin // Triggered on positive clock edge or reset
        if (!rst_n) begin // Active-low reset
            scl_sync <= 3'b111; // Default idle state on I2C bus is High (1) due to pull-up resistors
            sda_sync <= 3'b111; // Default idle state on I2C bus is High (1) due to pull-up resistors
        end else begin // Sequential sampling
            // Shift left and append current physical pin logic value into bit 0
            scl_sync <= (scl_sync << 1) | scl; // Sample SCL pin
            sda_sync <= (sda_sync << 1) | sda; // Sample SDA pin
        end // End reset if-else
    end // End synchronizer always block

    // ========================================================================
    // 2. Edge Detection and Bus Condition Logic
    // ========================================================================
    // SCL Rising Edge: was 0 at stage [2] and transitioned to 1 at stage [1]
    wire scl_rising  = (scl_sync[2] == 1'b0 && scl_sync[1] == 1'b1);

    // SCL Falling Edge: was 1 at stage [2] and transitioned to 0 at stage [1]
    wire scl_falling = (scl_sync[2] == 1'b1 && scl_sync[1] == 1'b0);

    // START Condition Detection: SDA falls (1 -> 0) while SCL is stable High (1)
    wire start_detect = (scl_sync[1] == 1'b1) && (sda_sync[2] == 1'b1 && sda_sync[1] == 1'b0);

    // STOP Condition Detection: SDA rises (0 -> 1) while SCL is stable High (1)
    wire stop_detect  = (scl_sync[1] == 1'b1) && (sda_sync[2] == 1'b0 && sda_sync[1] == 1'b1);

    // ========================================================================
    // 3. Open-Drain Tristate Buffer Control for SDA Pin
    // ========================================================================
    reg sda_out; // Internal register controlling slave drive state (0 = pull low, 1 = release)

    // Tristate assignment: if sda_out is 0, pull line to GND; if 1, release line to High-Z
    assign sda = (sda_out == 1'b0) ? 1'b0 : 1'bz;

    // ========================================================================
    // 4. Slave Finite State Machine (FSM) States
    // ========================================================================
    localparam IDLE       = 3'd0; // Idle state: waiting for START condition
    localparam GET_ADDR   = 3'd1; // Receiving 8 bits (7-bit slave address + 1-bit R/W flag)
    localparam ACK_ADDR   = 3'd2; // Generating ACK pulse if address matches MY_ADDR
    localparam RECV_DATA  = 3'd3; // Receiving 8-bit data byte from the master
    localparam ACK_DATA   = 3'd4; // Generating ACK pulse for received data byte
    localparam SEND_DATA  = 3'd5; // Transmitting 8-bit data byte to the master
    localparam WAIT_ACK   = 3'd6; // Waiting for master to acknowledge transmitted byte

    // ========================================================================
    // 5. Internal FSM Registers
    // ========================================================================
    reg [2:0] state;     // FSM current state register
    reg [3:0] bit_count; // Tracks number of bits transferred (0 to 8)
    reg [7:0] shift_reg; // Shift register to assemble received bits or serialize outgoing bits
    reg       rw_bit;    // Stores R/W direction bit: 0 = Master Write, 1 = Master Read

    // ========================================================================
    // 6. Slave Main FSM Sequential Process
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin // Sequential block sensitive to clk and rst_n
        if (!rst_n) begin // Asynchronous active-low reset
            state      <= IDLE; // Return to IDLE state
            sda_out    <= 1'b1; // Release SDA line to High-Z
            bit_count  <= 4'd0; // Reset bit counter to 0
            data_valid <= 1'b0; // De-assert data valid indicator
            data_out   <= 8'h00;// Clear data output register
            shift_reg  <= 8'h00;// Clear shift register
            rw_bit     <= 1'b0; // Clear read/write bit
        end else begin // Clocked operation

            data_valid <= 1'b0; // Default: data_valid pulse is Low

            // Asynchronous Priority Check 1: START condition detection (handles repeated starts)
            if (start_detect) begin
                state     <= GET_ADDR; // Immediately jump to address reception state
                bit_count <= 4'd0;     // Reset bit counter for new address frame
                sda_out   <= 1'b1;     // Release SDA line so master can drive address
            end 
            // Asynchronous Priority Check 2: STOP condition detection
            else if (stop_detect) begin
                state   <= IDLE;       // Return to IDLE state
                sda_out <= 1'b1;       // Release SDA line
            end 
            else begin // Normal synchronous FSM operation
                case (state) // Evaluate active slave state
                    // ---------------------------------------------------------
                    // IDLE: Wait for communication to begin
                    // ---------------------------------------------------------
                    IDLE: begin
                        sda_out <= 1'b1; // Keep SDA line released in High-Z
                    end

                    // ---------------------------------------------------------
                    // GET_ADDR: Receive 7 address bits + 1 R/W bit from Master
                    // ---------------------------------------------------------
                    GET_ADDR: begin
                        if (scl_rising) begin // Sample incoming data when SCL is stable High
                            shift_reg <= (shift_reg << 1) | sda_sync[1]; // Shift in sampled SDA bit
                            bit_count <= bit_count + 4'd1;               // Increment received bit counter
                        end
                        else if (scl_falling) begin // Evaluate after clock falling edge
                            if (bit_count == 4'd8) begin // All 8 bits (7 addr + 1 R/W) received
                                if (shift_reg[7:1] == MY_ADDR) begin // Does address match MY_ADDR?
                                    sda_out <= 1'b0;           // Address match! Pull SDA Low to ACK
                                    rw_bit  <= shift_reg[0];   // Store R/W direction (0=Write, 1=Read)
                                    state   <= ACK_ADDR;       // Advance to address ACK state
                                end else begin // Address mismatch
                                    sda_out <= 1'b1;           // Address not for this device, release SDA
                                    state   <= IDLE;           // Return to IDLE and ignore transaction
                                end // End address match check
                            end // End bit count check
                        end // End SCL edge check
                    end // End GET_ADDR

                    // ---------------------------------------------------------
                    // ACK_ADDR: Complete address ACK clock pulse and branch to R/W
                    // ---------------------------------------------------------
                    ACK_ADDR: begin
                        if (scl_falling) begin // After the 9th clock pulse completes
                            bit_count <= 4'd0; // Reset bit counter for incoming/outgoing data
                            
                            if (rw_bit == 1'b0) begin // Master requested WRITE operation
                                sda_out <= 1'b1;      // Release SDA so master can transmit data byte
                                state   <= RECV_DATA; // Advance to data reception state
                            end else begin // Master requested READ operation
                                sda_out   <= data_in[7];     // Drive MSB (Bit 7) of data_in onto SDA
                                shift_reg <= data_in << 1;   // Shift data_in left to prepare Bit 6
                                bit_count <= 4'd1;           // Mark first bit placed
                                state     <= SEND_DATA;      // Advance to data transmission state
                            end // End rw_bit check
                        end // End scl_falling check
                    end // End ACK_ADDR

                    // ---------------------------------------------------------
                    // RECV_DATA: Receive 8-bit data byte from Master
                    // ---------------------------------------------------------
                    RECV_DATA: begin
                        if (scl_rising) begin // Sample stable SDA on SCL rising edge
                            shift_reg <= (shift_reg << 1) | sda_sync[1]; // Shift in sampled data bit
                            bit_count <= bit_count + 4'd1;               // Increment bit counter
                        end
                        else if (scl_falling) begin // Evaluate bit count on SCL falling edge
                            if (bit_count == 4'd8) begin // Complete 8-bit byte received
                                sda_out    <= 1'b0;          // Pull SDA Low to ACK data reception
                                data_out   <= shift_reg;     // Latch assembled byte to data_out port
                                data_valid <= 1'b1;          // Assert 1-cycle data valid pulse
                                state      <= ACK_DATA;      // Advance to data ACK state
                            end // End bit count check
                        end // End SCL edge check
                    end // End RECV_DATA

                    // ---------------------------------------------------------
                    // ACK_DATA: Complete data ACK clock pulse
                    // ---------------------------------------------------------
                    ACK_DATA: begin
                        if (scl_falling) begin // After data ACK clock pulse falls
                            sda_out   <= 1'b1;      // Release SDA line
                            bit_count <= 4'd0;      // Reset counter for subsequent byte
                            state     <= RECV_DATA; // Return to receive next potential byte
                        end // End scl_falling check
                    end // End ACK_DATA

                    // ---------------------------------------------------------
                    // SEND_DATA: Transmit 8-bit data byte to Master
                    // ---------------------------------------------------------
                    SEND_DATA: begin
                        if (scl_falling) begin // Change data while SCL is Low (safe hold time)
                            if (bit_count == 4'd8) begin // All 8 bits transmitted
                                sda_out <= 1'b1;     // Release SDA so master can send ACK/NACK
                                state   <= WAIT_ACK; // Advance to wait for master ACK
                            end else begin // Transmit remaining data bits
                                sda_out   <= shift_reg[7];   // Place next MSB onto SDA line
                                shift_reg <= shift_reg << 1; // Shift left for subsequent bits
                                bit_count <= bit_count + 4'd1; // Increment transmitted bit counter
                            end // End bit count check
                        end // End scl_falling check
                    end // End SEND_DATA

                    // ---------------------------------------------------------
                    // WAIT_ACK: Sample Master ACK/NACK and terminate or repeat
                    // ---------------------------------------------------------
                    WAIT_ACK: begin
                        if (scl_falling) begin // After master's ACK/NACK clock pulse ends
                            state   <= IDLE; // Return to IDLE state
                            sda_out <= 1'b1; // Release SDA line
                        end // End scl_falling check
                    end // End WAIT_ACK

                    default: state <= IDLE; // Default fallback state
                endcase // End state case statement
            end // End normal FSM operation
        end // End reset if-else
    end // End slave always block

endmodule // End of i2c_slave module
