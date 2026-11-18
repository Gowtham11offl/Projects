// ============================================================================
// File Name   : apb_i2c_generator.sv
// Module/Block: apb_generator (SystemVerilog Generator Class)
// Description : Creates, randomizes, and sends sequences of APB transactions
//               to the driver via a SystemVerilog mailbox.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

class apb_generator; // Define the stimulus generator component class

    // ========================================================================
    // Member Declarations
    // ========================================================================
    // Mailbox handle used to transfer randomized transactions to the driver
    mailbox #(apb_transaction) gen2drv;

    // Total number of transactions to generate during the simulation run
    int count;

    // Status flag asserted High when all planned transactions are created and dispatched
    bit done;

    // ========================================================================
    // Constructor
    // ========================================================================
    function new(mailbox #(apb_transaction) gen2drv); // Constructor accepts driver mailbox
        this.gen2drv = gen2drv; // Bind external mailbox to internal class member
        count        = 10;      // Set default transaction generation count to 10 iterations
        done         = 1'b0;    // Initialize completion flag to 0 (in-progress)
    endfunction : new // End of constructor

    // ========================================================================
    // Generator Execution Task
    // ========================================================================
    task run(); // Main task to generate and dispatch transactions
        apb_transaction tr; // Declare a local transaction class handle

        repeat (count) begin // Loop for the designated number of transactions
            tr = new(); // Instantiate a new transaction object

            // Randomize transaction variables (addr, data, write) subject to constraints
            if (!tr.randomize()) // Check if constraint solver succeeded
                $fatal(1, "Transaction randomization failed!"); // Abort simulation on randomization failure

            // Log transaction generation event to simulation transcript
            $display("\n[GENERATOR] Transaction Generated");
            tr.display(); // Call display method to print address, data, and direction

            // Put transaction handle into mailbox to be picked up by the driver
            gen2drv.put(tr); // Blocking mailbox put: delivers item to driver
        end // End repeat loop

        done = 1'b1; // Mark generation as complete

        // Display notice confirming all transactions have been dispatched
        $display("\n[GENERATOR] All transactions generated");
    endtask : run // End of run task

endclass : apb_generator // End of apb_generator class
