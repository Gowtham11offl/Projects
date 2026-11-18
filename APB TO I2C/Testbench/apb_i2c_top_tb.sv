// ============================================================================
// File Name   : apb_i2c_top_tb.sv
// Module/Block: apb_i2c_sv_tb (Top-Level Testbench Module)
// Description : Top-level verification module for the APB-to-I2C bridge design.
//               Generates clock and reset, instantiates physical interface, DUT,
//               I2C slave behavioral model, and runs the test class.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale: 1ns time step, 1ps precision

// Include all verification components and definitions in hierarchical order
`include "apb_i2c_if.sv"          // Interface definition containing bus wires
`include "apb_i2c_transaction.sv" // Transaction class definition
`include "apb_i2c_generator.sv"   // Stimulus generator class definition
`include "apb_i2c_driver.sv"      // APB bus driver class definition
`include "apb_i2c_monitor.sv"     // APB bus monitor class definition
`include "apb_i2c_scoreboard.sv"  // Scoreboard and checker class definition
`include "apb_i2c_environment.sv" // Environment container class definition
`include "apb_i2c_test.sv"        // Test sequence and control class definition

module apb_i2c_sv_tb; // Top-level testbench module declaration

    // ========================================================================
    // 1. Interface Instantiation
    // ========================================================================
    apb_i2c_if apb(); // Instantiate physical interface instance named 'apb'

    // ========================================================================
    // 2. Test Class Handle
    // ========================================================================
    apb_i2c_test test; // Declare handle for high-level test object

    // ========================================================================
    // 3. Design Under Test (DUT) Instantiation
    // ========================================================================
    apb_i2c_core DUT ( // Instantiate APB-to-I2C core bridge DUT
        .PCLK     (apb.PCLK),     // Connect APB system clock to interface clock
        .PRESETn  (apb.PRESETn),  // Connect active-low reset to interface reset
        .PADDR    (apb.PADDR),    // Connect 32-bit register address bus
        .PSEL     (apb.PSEL),     // Connect APB slave select signal
        .PENABLE  (apb.PENABLE),  // Connect APB enable signal (access phase)
        .PWRITE   (apb.PWRITE),   // Connect write/read direction control
        .PWDATA   (apb.PWDATA),   // Connect 32-bit write data bus
        .PRDATA   (apb.PRDATA),   // Connect 32-bit read data bus back to interface
        .PREADY   (apb.PREADY),   // Connect APB ready response signal
        .scl      (apb.scl),      // Connect bidirectional I2C SCL clock line
        .sda      (apb.sda)       // Connect bidirectional I2C SDA data line
    ); // End DUT instantiation

    // ========================================================================
    // 4. I2C Slave Model Instantiation
    // ========================================================================
    logic [7:0] slave_rx_data;  // 8-bit wire capturing data received by I2C slave
    logic       slave_rx_valid; // Pulse wire asserted when slave receives a valid byte

    i2c_slave #(
        .MY_ADDR(7'h5A)         // Set unique 7-bit slave address parameter to 0x5A
    ) SLAVE (
        .clk        (apb.PCLK),       // System clock for slave internal synchronizer
        .rst_n      (apb.PRESETn),    // Active-low reset for slave model
        .scl        (apb.scl),        // Connect to physical I2C SCL serial line
        .sda        (apb.sda),        // Connect to physical I2C SDA serial line
        .data_out   (slave_rx_data),  // Output byte received from master
        .data_valid (slave_rx_valid), // Output valid pulse
        .data_in    (8'h00)           // Default data to return when master reads slave
    ); // End SLAVE instantiation

    // ========================================================================
    // 5. Clock Generation (50 MHz Clock: 20 ns period)
    // ========================================================================
    initial begin
        apb.PCLK = 1'b0; // Initialize clock to 0 at simulation time t=0
    end // End clock initialization block

    // Invert clock every 10 ns (10 ns Low + 10 ns High = 20 ns period = 50 MHz)
    always #10 apb.PCLK = ~apb.PCLK;

    // ========================================================================
    // 6. Reset and Signal Initialization Process
    // ========================================================================
    initial begin

        apb.PRESETn = 1'b0;         // Assert active-low reset at time t=0

        apb.PADDR   = 32'h00000000; // Initialize address bus to 0
        apb.PSEL    = 1'b0;         // Initialize slave select to 0 (unselected)
        apb.PENABLE = 1'b0;         // Initialize enable to 0 (idle)
        apb.PWRITE  = 1'b0;         // Initialize write flag to 0
        apb.PWDATA  = 32'h00000000; // Initialize write data bus to 0

        // Display testbench banner to simulation console
        $display("");
        $display("====================================");
        $display("       APB TO I2C VERIFICATION      ");
        $display("====================================");

        // Hold reset active for 5 clock cycles
        repeat (5)
            @(negedge apb.PCLK); // Synchronize to falling edge of clock

        apb.PRESETn = 1'b1;      // Release active-low reset (de-assert reset)

        // Log reset release timestamp to console
        $display("[%0t] RESET RELEASED", $time);

        // Wait an additional 5 clock cycles for system stabilization
        repeat (5)
            @(negedge apb.PCLK);

        // ====================================================================
        // 7. Create Test Object
        // ====================================================================
        test = new(apb); // Construct test object and pass interface handle

        // ====================================================================
        // 8. Start Test Execution
        // ====================================================================
        test.run_test(); // Execute test scenario and verification checks

        // ====================================================================
        // 9. End Simulation
        // ====================================================================
        #100; // Add 100ns simulation cooldown delay

        // Display final simulation finish banner
        $display("====================================");
        $display("       SIMULATION FINISHED          ");
        $display("====================================");

        $finish; // Terminate simulation run cleanly

    end // End initial stimulus and reset block

endmodule : apb_i2c_sv_tb // End of top-level testbench module
