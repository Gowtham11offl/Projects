// ============================================================================
// File Name   : apb_i2c_transaction.sv
// Module/Block: apb_transaction (SystemVerilog Transaction Class)
// Description : Encapsulates a single APB bus transaction (Address, Data, Write/Read)
//               with randomization constraints and formatting/display functions.
// ============================================================================

`timescale 1ns/1ps // Set simulation timescale (1ns unit, 1ps precision)

class apb_transaction; // Define the transaction class for APB operations

    // ========================================================================
    // 1. Transaction Variables (Randomizable fields for stimulus generation)
    // ========================================================================
    rand bit [2:0] addr;   // Random 3-bit register offset (maps to internal registers 0x0 to 0x4)
    rand bit [7:0] data;   // Random 8-bit data payload to write or expect on read
    rand bit       write;  // Random transfer direction flag: 1 = Write operation, 0 = Read operation

    // ========================================================================
    // 2. Address Constraints
    // ========================================================================
    constraint valid_address { // Restrict randomized addresses to valid register space
        addr inside {[3'd0:3'd4]}; // Valid addresses are PRER_LO(0), PRER_HI(1), CTR(2), TXR/RXR(3), CR/SR(4)
    } // End of valid_address constraint block

    // ========================================================================
    // 3. Display Transaction Method
    // ========================================================================
    function void display(); // Utility function to print transaction fields to console

        $display("--------------------------------"); // Print decorative separator line
        $display("       APB TRANSACTION           "); // Print header label
        $display("--------------------------------"); // Print decorative separator line

        // Print whether this transaction represents an APB WRITE or READ operation
        $display("Operation : %s", write ? "WRITE" : "READ");

        // Print the target 3-bit register address in hexadecimal format
        $display("Address   : 0x%0h", addr);

        // Print the 8-bit data payload in hexadecimal format
        $display("Data      : 0x%0h", data);

        $display("--------------------------------"); // Print decorative footer line

    endfunction : display // End of display function

endclass : apb_transaction // End of apb_transaction class
