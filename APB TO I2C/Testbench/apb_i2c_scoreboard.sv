// ============================================================================
// File Name   : apb_i2c_scoreboard.sv
// Module/Block: apb_scoreboard (SystemVerilog Scoreboard Class)
// Description : Maintains a reference model of internal registers (PRER_LO,
//               PRER_HI, CTR), compares observed read data against expected
//               values, and generates a pass/fail verification report.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

class apb_scoreboard; // Define the scoreboard component class

    // ========================================================================
    // 1. Mailbox Handle
    // ========================================================================
    // Mailbox handle to receive monitored transactions from the APB monitor
    mailbox #(apb_transaction) mon2scb;

    // ========================================================================
    // 2. Reference Register Model and Test Counters
    // ========================================================================
    // Array representing golden expected values for registers 0x0, 0x1, and 0x2
    bit [7:0] expected_regs [0:2];

    int pass_count; // Counter tracking number of successfully verified read checks
    int fail_count; // Counter tracking number of failed comparison mismatches

    // ========================================================================
    // 3. Constructor
    // ========================================================================
    function new(mailbox #(apb_transaction) mon2scb); // Scoreboard constructor
        this.mon2scb = mon2scb; // Store monitor mailbox reference

        // Initialize reference model with design-specified default reset values:
        expected_regs[0] = 8'hFF; // PRER_LO default reset value from DUT RTL (Address 0x0)
        expected_regs[1] = 8'hFF; // PRER_HI default reset value from DUT RTL (Address 0x1)
        expected_regs[2] = 8'h00; // CTR control register default reset value (Address 0x2)

        pass_count = 0; // Initialize pass counter to 0
        fail_count = 0; // Initialize fail counter to 0
    endfunction : new // End of constructor

    // ========================================================================
    // 4. Scoreboard Execution Task
    // ========================================================================
    task run(); // Main verification task running concurrently with simulation
        apb_transaction tr; // Local transaction object handle

        forever begin // Loop continuously to process incoming transactions

            // Retrieve observed transaction from the monitor mailbox
            mon2scb.get(tr);

            // Check if the monitored operation is a WRITE or a READ
            if (tr.write) begin

                // Update golden reference model for configuration registers (0x0 to 0x2)
                if (tr.addr <= 3'd2) begin

                    expected_regs[tr.addr] = tr.data; // Store written data in reference model

                    // Log model update event to console
                    $display(
                        "[SCOREBOARD] WRITE MODEL UPDATED: ADDR=%0h DATA=%0h",
                        tr.addr, tr.data
                    );

                end
                else begin // Register is TXR (0x3) or CR (0x4)

                    // Log write observation for command/data registers
                    $display(
                        "[SCOREBOARD] WRITE OBSERVED: ADDR=%0h DATA=%0h",
                        tr.addr, tr.data
                    );

                end // End register address check

            end
            else begin // Transaction is a READ operation

                // Verify read value against golden model for registers 0x0 to 0x2
                if (tr.addr <= 3'd2) begin

                    // Check if actual read data matches the expected golden model data
                    if (tr.data === expected_regs[tr.addr]) begin

                        pass_count++; // Increment successful match counter

                        // Log passing comparison result
                        $display(
                            "[SCOREBOARD] PASS: ADDR=%0h EXPECTED=%0h ACTUAL=%0h",
                            tr.addr,
                            expected_regs[tr.addr],
                            tr.data
                        );

                    end
                    else begin // Mismatch detected!

                        fail_count++; // Increment failure counter

                        // Report error with expected vs actual values
                        $error(
                            "[SCOREBOARD] FAIL: ADDR=%0h EXPECTED=%0h ACTUAL=%0h",
                            tr.addr,
                            expected_regs[tr.addr],
                            tr.data
                        );

                    end // End comparison check

                end
                else begin // Read is from RXR (0x3) or SR (0x4)

                    // Log read observation for dynamic hardware registers (checked separately)
                    $display(
                        "[SCOREBOARD] READ OBSERVED: ADDR=%0h DATA=%0h (CHECK DEFERRED)",
                        tr.addr, tr.data
                    );

                end // End address classification

            end // End WRITE / READ branch

        end // End forever loop

    endtask : run // End of run task

    // ========================================================================
    // 5. Final Reporting Function
    // ========================================================================
    function void report(); // Summarizes total pass/fail statistics at end of test

        $display("");                                    // Blank separator line
        $display("================================");    // Section banner top
        $display("      SCOREBOARD REPORT         ");    // Report title banner
        $display("================================");    // Section banner bottom

        $display("PASS COUNT = %0d", pass_count);        // Print total passing comparisons
        $display("FAIL COUNT = %0d", fail_count);        // Print total failing comparisons

        $display("================================");    // Section banner footer

    endfunction : report // End of report function

endclass : apb_scoreboard // End of apb_scoreboard class
