// ============================================================================
// File Name   : apb_i2c_core.v
// Module Name : apb_i2c_core (Top-Level APB-to-I2C Bridge Wrapper)
// Description : Implements an APB slave interface exposing 5 internal registers
//               (PRER_LO, PRER_HI, CTR, TXR/RXR, CR/SR) compliant with OpenCores
//               I2C controller specifications. Instantiates the Clock Generator,
//               Bit-Level Controller, and Byte-Level Controller, and connects
//               them to physical open-drain bidirectional SCL and SDA lines.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

module apb_i2c_core (
    // ========================================================================
    // APB Bus Interface Ports (Connect to APB Master / CPU System Bus)
    // ========================================================================
    input  wire        PCLK,      // APB system clock (synchronizes CPU bus and internal sub-modules)
    input  wire        PRESETn,   // Active-low system reset (synchronous/asynchronous design reset)
    input  wire [31:0] PADDR,     // 32-bit APB register address bus driven by CPU (lower 3 bits decoded)
    input  wire        PSEL,      // APB slave select: High when this bridge core is targeted
    input  wire        PENABLE,   // APB enable signal: High during the second (access) phase of APB transfer
    input  wire        PWRITE,    // APB transfer direction: 1 = CPU Write, 0 = CPU Read
    input  wire [31:0] PWDATA,    // 32-bit APB write data bus from CPU (lower 8 bits mapped to registers)
    output reg  [31:0] PRDATA,    // 32-bit APB read data bus returning register data to CPU
    output wire        PREADY,    // APB ready signal: asserted High to acknowledge transfer completion

    // ========================================================================
    // Physical Bidirectional I2C Serial Bus Ports
    // ========================================================================
    inout  wire        scl,       // Serial Clock line (bidirectional open-drain with external pull-up)
    inout  wire        sda        // Serial Data line (bidirectional open-drain with external pull-up)
);

    // ========================================================================
    // 1. Internal Register Declarations (OpenCores I2C Register Map)
    // ========================================================================
    reg [7:0] prer_lo; // Address 0x00: Prescale Low-byte (clock divider low 8 bits)
    reg [7:0] prer_hi; // Address 0x01: Prescale High-byte (clock divider high 8 bits)
    reg [7:0] ctr;     // Address 0x02: Control Register (Bit 7: Core Enable [EN], Bit 6: Interrupt Enable [IEN])

    // Transmit register (txr) is Write-only. Receive register (rxr) is Read-only.
    reg [7:0]  txr;    // Address 0x03 (Write): Transmit register holding byte to serialize onto I2C bus
    wire [7:0] rxr;    // Address 0x03 (Read): Receive register holding byte deserialized from I2C bus

    // Command register (cr) is Write-only. Status register (sr) is Read-only.
    reg [7:0]  cr;     // Address 0x04 (Write): Command register (Bit 7: STA, 6: STO, 5: RD, 4: WR, 3: ACK)
    wire [7:0] sr;     // Address 0x04 (Read): Status register (Bit 7: RxACK, 6: Busy, 1: TIP, 0: IF)

    // ========================================================================
    // 2. Internal Interconnect Wires Connecting Sub-Modules
    // ========================================================================
    wire        clk_en;        // 4x timing tick pulse from Clock Generator to Bit Controller
    wire [3:0]  bit_cmd;       // 4-bit command bus from Byte Controller to Bit Controller
    wire        bit_din;       // Serialized data bit from Byte Controller to Bit Controller
    wire        bit_dout;      // Sampled data bit from Bit Controller to Byte Controller
    wire        bit_ack;       // 1-bit transfer acknowledge pulse from Bit Controller
    
    wire        scl_oen;       // SCL output enable from Bit Controller (0 = drive Low, 1 = release/float)
    wire        sda_oen;       // SDA output enable from Bit Controller (0 = drive Low, 1 = release/float)
    wire        scl_in;        // Actual voltage level sampled back from the physical SCL pin
    wire        sda_in;        // Actual voltage level sampled back from the physical SDA pin

    wire [7:0]  byte_dout;     // Completed 8-bit byte from Byte Controller routed to RXR register
    wire        byte_ack;      // Completed byte pulse from Byte Controller (clears CR and flags IF)
    wire        byte_ack_out;  // Latch holding 9th ACK bit sampled from slave device
    wire        i2c_busy;      // Bus busy flag from Byte Controller (asserted during active transfers)

    // ========================================================================
    // 3. APB Bus Protocol Decoding Logic
    // ========================================================================
    assign PREADY = 1'b1;                                 // Internal registers respond with zero wait states
    wire apb_write = PSEL & PENABLE & PWRITE & PREADY;    // Asserted during the valid APB Write Access Phase
    wire apb_read  = PSEL & PENABLE & ~PWRITE & PREADY;   // Asserted during the valid APB Read Access Phase

    // ========================================================================
    // 4. APB Register Write Process (CPU -> Internal Bridge Registers)
    // ========================================================================
    always @(posedge PCLK or negedge PRESETn) begin // Synchronized to APB clock or active-low reset
        if (!PRESETn) begin // Asynchronous system reset
            // Default reset states defined by OpenCores I2C Specification
            prer_lo <= 8'hFF; // Reset prescaler low to 0xFF (maximum division default)
            prer_hi <= 8'hFF; // Reset prescaler high to 0xFF (maximum division default)
            ctr     <= 8'h00; // Reset control register to 0x00 (core disabled)
            txr     <= 8'h00; // Reset transmit data register to 0x00
            cr      <= 8'h00; // Reset command register to 0x00
        end else begin // Clocked sequential logic
            if (apb_write) begin // Valid CPU write access phase detected
                // Decode register target based on lower 3 bits of APB address bus
                case (PADDR[2:0])
                    3'h0: prer_lo <= PWDATA[7:0]; // Write Prescale Register Low byte
                    3'h1: prer_hi <= PWDATA[7:0]; // Write Prescale Register High byte
                    3'h2: ctr     <= PWDATA[7:0]; // Write Core Control Register
                    3'h3: txr     <= PWDATA[7:0]; // Write Transmit Data Register
                    3'h4: cr      <= PWDATA[7:0]; // Write Command Register (initiates transfer)
                    default: ;                    // Ignore writes to undefined offsets
                endcase // End address case
            end else begin // No active CPU write access
                // AUTO-CLEAR LOGIC:
                // When Byte Controller completes the transfer, it pulses `byte_ack`.
                // Clear active command bits (STA, STO, RD, WR) to 0 to prevent repeating transfers.
                if (byte_ack) begin
                    cr[7:4] <= 4'b0000; // Clear STA (bit 7), STO (bit 6), RD (bit 5), WR (bit 4)
                end // End byte_ack check
            end // End write check
        end // End reset check
    end // End always sequential block

    // ========================================================================
    // 5. APB Register Read Multiplexer (Internal Bridge Registers -> CPU)
    // ========================================================================
    always @(*) begin // Combinational logic for read multiplexer
        PRDATA = 32'h0000_0000; // Default read data bus value is zero
        if (apb_read) begin // Valid CPU read access phase detected
            // Multiplex targeted internal register onto PRDATA based on address
            case (PADDR[2:0])
                3'h0: PRDATA[7:0] = prer_lo; // Read Prescale Low byte
                3'h1: PRDATA[7:0] = prer_hi; // Read Prescale High byte
                3'h2: PRDATA[7:0] = ctr;     // Read Core Control Register
                3'h3: PRDATA[7:0] = rxr;     // Read Received Data Register (RXR)
                3'h4: PRDATA[7:0] = sr;      // Read Core Status Register (SR)
                default: PRDATA[7:0] = 8'h00;// Return zero for unused register addresses
            endcase // End address case
        end // End apb_read check
    end // End always combinational block

    // ========================================================================
    // 6. Connect Status (SR) and Receive (RXR) Wires (Spec Page 9)
    // ========================================================================
    assign rxr = byte_dout; // Link Receive register directly to output of Byte Controller

    // Status bits mapping:
    //   sr[7]   = RxACK (0 = slave ACK, 1 = slave NACK)
    //   sr[6]   = Busy (1 = bus active, 0 = bus idle)
    //   sr[5:2] = Reserved bits (tied to 4'b0000)
    //   sr[1]   = TIP (Transfer in Progress: 1 when sending or receiving data)
    //   sr[0]   = IF (Interrupt Flag: pulsed 1 when byte transfer completes)
    assign sr[7]   = byte_ack_out; // 9th bit ACK status received from slave
    assign sr[6]   = i2c_busy;     // Bus busy status
    assign sr[5:2] = 4'b0000;      // Reserved unused bits
    assign sr[1]   = i2c_busy;     // Transfer in progress status
    assign sr[0]   = byte_ack;     // Interrupt flag pulse

    // ========================================================================
    // 7. Physical Bidirectional Tristate Buffers (Open-Drain Driver Structure)
    // ========================================================================
    // Open-drain logic prevents VDD-to-GND contention on the shared physical bus.
    // If output enable is Low (0), pull pin to GND (1'b0).
    // If output enable is High (1), release pin to High-Z (1'bz) and let pull-up resistors pull it to VDD.
    assign scl = (scl_oen == 1'b0) ? 1'b0 : 1'bz; // Drive or float physical SCL pin
    assign sda = (sda_oen == 1'b0) ? 1'b0 : 1'bz; // Drive or float physical SDA pin

    // Feedback lines sample actual physical pin voltages back into internal controllers
    assign scl_in = scl; // Sample actual physical SCL voltage
    assign sda_in = sda; // Sample actual physical SDA voltage

    // ========================================================================
    // 8. Module Instantiations
    // ========================================================================

    // Sub-Module A: Clock Generator (Generates 4x timing tick and handles clock stretching)
    i2c_clk_gen u_clock_gen (
        .clk      (PCLK),                 // Connect APB system clock
        .rst_n    (PRESETn),              // Connect system reset
        .prescale ({prer_hi, prer_lo}),   // Combine 8-bit HI and LO registers into 16-bit prescaler
        .scl_out  (scl_oen),              // Master SCL output enable for clock stretch detection
        .scl_in   (scl_in),               // Physical SCL feedback input
        .clk_en   (clk_en)                // Output timing enable pulse
    ); // End u_clock_gen instantiation

    // Sub-Module B: Bit Controller (Drives 4-phase bit sequences onto SCL and SDA lines)
    i2c_bit_cntr u_bit_ctrl (
        .clk      (PCLK),                 // Connect APB system clock
        .rst_n    (PRESETn),              // Connect system reset
        .clk_en   (clk_en),               // Timing tick from Clock Generator
        .cmd      (bit_cmd),              // Command bus from Byte Controller
        .din      (bit_din),              // Serial data bit input from Byte Controller
        .dout     (bit_dout),             // Serial data bit output to Byte Controller
        .cmd_ack  (bit_ack),              // Bit completion acknowledge output
        .scl_oen  (scl_oen),              // SCL output enable to tristate buffer
        .sda_oen  (sda_oen),              // SDA output enable to tristate buffer
        .scl_in   (scl_in),               // Physical SCL feedback
        .sda_in   (sda_in)                // Physical SDA feedback
    ); // End u_bit_ctrl instantiation

    // Sub-Module C: Byte Controller (Coordinates byte serialization, deserialization, and protocol FSM)
    i2c_byte_cntr u_byte_ctrl (
        .clk      (PCLK),                 // Connect APB system clock
        .rst_n    (PRESETn),              // Connect system reset
        .start    (cr[7] & ctr[7]),       // Issue START only if core is enabled (ctr[7]=1)
        .stop     (cr[6] & ctr[7]),       // Issue STOP only if core is enabled (ctr[7]=1)
        .read     (cr[5] & ctr[7]),       // Issue READ only if core is enabled (ctr[7]=1)
        .write    (cr[4] & ctr[7]),       // Issue WRITE only if core is enabled (ctr[7]=1)
        .ack_in   (cr[3]),                // Master ACK/NACK value sent to slave during reads
        .din      (txr),                  // Data byte to serialize (loaded from TXR)
        .dout     (byte_dout),            // Deserialized byte received from slave (routed to RXR)
        .cmd_ack  (byte_ack),             // Byte transfer complete acknowledge pulse
        .ack_out  (byte_ack_out),         // Sampled 9th ACK bit from slave
        .i2c_busy (i2c_busy),             // Bus busy status output
        .bit_cmd  (bit_cmd),              // Command sent to Bit Controller
        .bit_din  (bit_din),              // Serialized bit sent to Bit Controller
        .bit_dout (bit_dout),             // Sampled bit received from Bit Controller
        .bit_ack  (bit_ack)               // Bit transfer acknowledge from Bit Controller
    ); // End u_byte_ctrl instantiation

endmodule // End of apb_i2c_core module
