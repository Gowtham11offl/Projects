// ============================================================================
// File Name   : apb_i2c_monitor.sv
// Module/Block: apb_monitor (SystemVerilog Monitor Class)
// Description : Passively observes the APB interface, detects valid bus transfers
//               (PSEL & PENABLE & PREADY), captures Address/Data/Operation, and
//               forwards sampled transactions to the scoreboard via mailbox.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

class apb_monitor; // Define the APB bus monitor component class

    // ========================================================================
    // 1. Virtual Interface Handle
    // ========================================================================
    // Virtual interface through which monitor samples physical bus signals
    virtual apb_i2c_if vif;

    // ========================================================================
    // 2. Mailbox Handle
    // ========================================================================
    // Mailbox handle used to send sampled transactions to the scoreboard
    mailbox #(apb_transaction) mon2scb;

    // ========================================================================
    // 3. Constructor
    // ========================================================================
    function new(
        virtual apb_i2c_if vif,            // Virtual interface pass-through
        mailbox #(apb_transaction) mon2scb // Monitor-to-scoreboard mailbox pass-through
    );
        this.vif     = vif;     // Assign virtual interface to internal member
        this.mon2scb = mon2scb; // Assign scoreboard mailbox to internal member
    endfunction : new // End of constructor

    // ========================================================================
    // 4. Monitor Execution Task
    // ========================================================================
    task run(); // Main monitor task that runs continuously throughout simulation
        apb_transaction tr; // Local transaction object handle

        forever begin // Continuous passive monitoring loop

            @(posedge vif.PCLK); // Sample bus lines on every rising edge of APB clock

            // Check if a valid APB transfer is completing:
            // 1. PSEL is active (bridge selected)
            // 2. PENABLE is active (access phase)
            // 3. PREADY is active (slave acknowledges transfer completion)
            if ((vif.PSEL    === 1'b1) &&
                (vif.PENABLE === 1'b1) &&
                (vif.PREADY  === 1'b1)) begin

                tr = new(); // Instantiate a new transaction object to hold captured data

                tr.addr  = vif.PADDR[2:0]; // Capture lower 3 bits of address bus
                tr.write = vif.PWRITE;     // Capture transfer direction (1 = Write, 0 = Read)

                // Capture data based on transfer direction
                if (vif.PWRITE) begin // WRITE transfer occurred
                    tr.data = vif.PWDATA[7:0]; // Sample lower 8 bits of write data bus

                    // Print notification of detected APB write
                    $display("\n[MONITOR] APB WRITE DETECTED");
                end
                else begin // READ transfer occurred
                    tr.data = vif.PRDATA[7:0]; // Sample lower 8 bits of read data bus

                    // Print notification of detected APB read
                    $display("\n[MONITOR] APB READ DETECTED");
                end // End if-else direction check

                // Display captured transaction contents to the console log
                tr.display();

                // Send the captured transaction handle to the scoreboard for verification
                mon2scb.put(tr); // Non-blocking/blocking mailbox put to forward data

            end // End valid APB transfer check

        end // End forever loop

    endtask : run // End of run task

endclass : apb_monitor // End of apb_monitor class
