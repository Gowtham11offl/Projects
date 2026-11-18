// ============================================================================
// File Name   : apb_i2c_if.sv
// Module/Block: apb_i2c_if (SystemVerilog Interface)
// Description : Defines the physical signal interface connecting the APB Master
//               (testbench driver/monitor) to the APB-I2C bridge DUT, along with
//               the physical I2C open-drain serial bus signals (SCL & SDA).
// ============================================================================

`timescale 1ns/1ps // Time unit: 1ns, Time precision: 1ps

interface apb_i2c_if; // Declare the SystemVerilog interface bundle

    // ========================================================================
    // APB Protocol Signals (Master -> DUT / Slave)
    // ========================================================================
    logic        PCLK;      // APB bus clock signal (synchronizes all transfers)
    logic        PRESETn;   // Active-low APB asynchronous/synchronous system reset
    logic [31:0] PADDR;     // 32-bit APB register address bus driven by driver
    logic        PSEL;      // APB slave select: High when DUT is being targeted
    logic        PENABLE;   // APB enable signal: High during the access/data phase
    logic        PWRITE;    // APB transfer direction: 1 = Write transfer, 0 = Read transfer
    logic [31:0] PWDATA;    // 32-bit APB write data bus driven by the driver

    // ========================================================================
    // APB Response Signals (DUT -> Testbench / Master)
    // ========================================================================
    wire [31:0]  PRDATA;    // 32-bit APB read data bus driven back by the DUT
    wire         PREADY;    // APB ready indicator driven by DUT (1 = transfer complete)

    // ========================================================================
    // I2C Serial Bus Signals (Bidirectional Open-Drain with Pull-ups)
    // ========================================================================
    tri1         scl;       // I2C Serial Clock line (tri1: pulled High to 1 by default pull-up)
    tri1         sda;       // I2C Serial Data line (tri1: pulled High to 1 by default pull-up)

endinterface : apb_i2c_if // End of interface definition
