// ============================================================================
// File Name   : apb_i2c_driver.sv
// Module/Block: apb_driver (SystemVerilog Driver Class)
// Description : Retrieves APB transactions from the generator mailbox and converts
//               them into cycle-accurate APB protocol pin wiggles (Setup Phase,
//               Access Phase, and Bus Idle/Completion Phase) on the virtual interface.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

class apb_driver; // Define the APB bus driver component class

    // ========================================================================
    // Member Declarations
    // ========================================================================
    bit done; // Status flag indicating the driver has driven all scheduled transactions

    // ========================================================================
    // 1. Virtual Interface Handle
    // ========================================================================
    // Virtual interface connecting driver class methods to physical signals in the DUT
    virtual apb_i2c_if vif;

    // ========================================================================
    // 2. Mailbox Handle
    // ========================================================================
    // Mailbox handle from which transactions are received from generator
    mailbox #(apb_transaction) gen2drv;

    // ========================================================================
    // 3. Constructor
    // ========================================================================
    function new(
        virtual apb_i2c_if vif,            // Virtual interface pass-through
        mailbox #(apb_transaction) gen2drv // Generator-to-driver mailbox pass-through
    );
        this.vif     = vif;     // Store virtual interface reference in local member
        this.gen2drv = gen2drv; // Store generator mailbox reference in local member
        done         = 1'b0;    // Initialize driver completion flag to 0
    endfunction : new // End of constructor

    // ========================================================================
    // 4. Driver Execution Task
    // ========================================================================
    task run(int transaction_count); // Drives the specified count of APB transfers
        apb_transaction tr;        // Transaction object handle to hold retrieved item
        logic [31:0]    read_data; // Local variable to sample 32-bit read data from APB bus

        // Loop through and drive each transaction sequentially
        repeat (transaction_count) begin

            // Retrieve transaction object from the mailbox (blocks until available)
            gen2drv.get(tr);

            // Display notification of retrieved transaction
            $display("\n[DRIVER] Received Transaction");

            // Print the transaction details (operation, address, data)
            tr.display();

            // ----------------------------------------------------------------
            // APB Phase 1: SETUP PHASE
            // Drive Address, Write control, Select, and Data with PENABLE = 0
            // ----------------------------------------------------------------
            @(negedge vif.PCLK); // Synchronize to falling edge of clock to meet setup times

            vif.PSEL    = 1'b1;              // Assert Slave Select (DUT targeted)
            vif.PENABLE = 1'b0;              // Keep PENABLE Low during setup phase

            vif.PADDR   = {29'b0, tr.addr};  // Zero-extend 3-bit register address to 32 bits
            vif.PWRITE  = tr.write;          // Drive transfer direction: 1=Write, 0=Read

            if (tr.write)                    // If write operation, drive write data
                vif.PWDATA = {24'b0, tr.data}; // Zero-extend 8-bit data payload to 32 bits

            // ----------------------------------------------------------------
            // APB Phase 2: ACCESS PHASE
            // Assert PENABLE High and wait for slave assertion of PREADY
            // ----------------------------------------------------------------
            @(negedge vif.PCLK); // Advance to the next clock cycle

            vif.PENABLE = 1'b1;  // Assert PENABLE High to mark the access phase

            // Poll PREADY on rising edge of clock until slave acknowledges readiness
            do begin
                @(posedge vif.PCLK); // Wait for clock rising edge where PREADY is sampled
            end
            while (vif.PREADY !== 1'b1); // Continue waiting if PREADY is not 1

            // If this was a READ operation, sample PRDATA from DUT
            if (!tr.write) begin
                read_data = vif.PRDATA; // Capture 32-bit data from read data bus

                // Print the captured 8-bit register data to simulation log
                $display("[DRIVER] READ DATA = 0x%0h", read_data[7:0]);
            end // End of read data capture block

            // ----------------------------------------------------------------
            // APB Phase 3: COMPLETE TRANSFER / BUS IDLE
            // De-assert control signals and return bus to idle state
            // ----------------------------------------------------------------
            @(negedge vif.PCLK); // Wait for falling edge to complete cycle cleanly

            vif.PSEL    = 1'b0;  // De-assert Slave Select signal
            vif.PENABLE = 1'b0;  // De-assert Enable signal
            vif.PWRITE  = 1'b0;  // Return Write direction to read/idle (default 0)
            vif.PADDR   = 32'h0; // Clear address bus to zero
            vif.PWDATA  = 32'h0; // Clear write data bus to zero

            // Print completion status for this single APB transfer
            $display("[DRIVER] APB Transfer Completed");

        end // End of repeat loop

        // --------------------------------------------------------------------
        // All Transactions Completed Notification
        // --------------------------------------------------------------------
        done = 1'b1; // Assert driver completion flag to signal environment

        // Print final status message
        $display("[DRIVER] All APB transactions completed");

    endtask : run // End of run task

endclass : apb_driver // End of apb_driver class
