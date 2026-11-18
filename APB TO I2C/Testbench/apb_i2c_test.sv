// ============================================================================
// File Name   : apb_i2c_test.sv
// Module/Block: apb_i2c_test (SystemVerilog Test Class)
// Description : High-level test container that configures and launches the
//               verification environment for the APB-to-I2C bridge.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

class apb_i2c_test; // Define the test class container

    // ========================================================================
    // Member Declarations
    // ========================================================================
    // Handle to the verification environment containing generator, driver, monitor, scoreboard
    apb_environment env;

    // ========================================================================
    // Constructor
    // ========================================================================
    function new(virtual apb_i2c_if vif); // Test constructor receives virtual interface
        $display("[TEST] Creating APB-I2C Test"); // Log test creation message

        // Instantiate the verification environment and pass virtual interface
        env = new(vif); // Allocate and initialize environment object
    endfunction : new // End of constructor

    // ========================================================================
    // Main Test Execution Task
    // ========================================================================
    task run_test(); // High-level task executed by top testbench module

        // Display test startup banner
        $display("");                                    // Blank line
        $display("================================");    // Section banner top
        $display("   APB TO I2C VERIFICATION      ");    // Test banner title
        $display("================================");    // Section banner bottom

        // Execute the environment's run task to drive stimulus and collect results
        env.run(); // Blocks until all transactions complete and scoreboard reports

        // Display test completion banner
        $display("");                                    // Blank line
        $display("================================");    // Section banner top
        $display("       TEST COMPLETED           ");    // Test complete title
        $display("================================");    // Section banner bottom

    endtask : run_test // End of run_test task

endclass : apb_i2c_test // End of apb_i2c_test class
