// ============================================================================
// File Name   : apb_i2c_environment.sv
// Module/Block: apb_environment (SystemVerilog Environment Class)
// Description : Instantiates, interconnects, and orchestrates all testbench
//               components (Generator, Driver, Monitor, Scoreboard) and manages
//               the simulation lifecycle and synchronization.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

class apb_environment; // Define the testbench environment container class

    // ========================================================================
    // 1. Virtual Interface Handle
    // ========================================================================
    // Virtual interface providing physical signal connectivity to DUT
    virtual apb_i2c_if vif;

    // ========================================================================
    // 2. Inter-Component Mailboxes
    // ========================================================================
    mailbox #(apb_transaction) gen2drv; // Mailbox channel from generator to driver
    mailbox #(apb_transaction) mon2scb; // Mailbox channel from monitor to scoreboard

    // ========================================================================
    // 3. Testbench Component Handles
    // ========================================================================
    apb_generator   generator;  // Handle for stimulus generator instance
    apb_driver      driver;     // Handle for APB protocol driver instance
    apb_monitor     monitor;    // Handle for APB bus monitor instance
    apb_scoreboard  scoreboard; // Handle for reference model and checker instance

    // ========================================================================
    // 4. Constructor
    // ========================================================================
    function new(virtual apb_i2c_if vif); // Constructor receives virtual interface
        this.vif = vif; // Assign virtual interface to class member

        // Instantiate communication mailboxes
        gen2drv = new(); // Allocate mailbox connecting generator and driver
        mon2scb = new(); // Allocate mailbox connecting monitor and scoreboard

        // Instantiate sub-components and pass appropriate interfaces and mailboxes
        generator  = new(gen2drv);       // Generator only requires driver mailbox
        driver     = new(vif, gen2drv);  // Driver requires virtual interface and stimulus mailbox
        monitor    = new(vif, mon2scb);  // Monitor requires virtual interface and scoreboard mailbox
        scoreboard = new(mon2scb);       // Scoreboard requires monitor mailbox
    endfunction : new // End of constructor

    // ========================================================================
    // 5. Environment Run Task
    // ========================================================================
    task run(); // Coordinates the parallel execution of all testbench components

        // Display environment startup banner
        $display("");
        $display("================================");
        $display("     ENVIRONMENT STARTED        ");
        $display("================================");

        // Fork all sub-component run tasks to execute concurrently in background threads
        fork
            generator.run();              // Thread 1: Start stimulus generation
            driver.run(generator.count);  // Thread 2: Start transaction driving
            monitor.run();                // Thread 3: Start bus monitoring
            scoreboard.run();             // Thread 4: Start scoreboarding and checks
        join_none // Return immediately and let background threads run

        // Wait until the driver completes all scheduled transactions
        wait(driver.done == 1'b1); // Block until driver asserts its completion flag

        // Wait for 2 additional clock cycles to allow monitor to capture trailing cycles
        repeat (2) @(posedge vif.PCLK);

        // Terminate background tasks (monitor and scoreboard run loops) cleanly
        disable fork; // Kill all background threads spawned by this task's fork block

        // Display environment completion banner
        $display("");
        $display("================================");
        $display("    ENVIRONMENT COMPLETED       ");
        $display("================================");

        // Generate and display final scoreboard report
        scoreboard.report(); // Print total pass and fail statistics

    endtask : run // End of run task

endclass : apb_environment // End of apb_environment class
