`timescale 1ns/1ps

`include "i2c_clk_gen.v"
`include "i2c_byte_cntrl.v"
`include "i2c_bit_cntrl.v"
`include "i2c_slave.v"

module apb_i2c_core (
  
    // ------------------------------------------------------------------------
    // APB Bus Interface Ports
    // ------------------------------------------------------------------------
  
    input  wire        PCLK,      
    input  wire        PRESETn,   
    input  wire [31:0] PADDR,     
    input  wire        PSEL,      
    input  wire        PENABLE,   
    input  wire        PWRITE,    
    input  wire [31:0] PWDATA,    
    output reg  [31:0] PRDATA,    
    output wire        PREADY,    

    // ------------------------------------------------------------------------
    // Physical Bidirectional I2C Pins
    // ------------------------------------------------------------------------
  
    inout  wire        scl,       
    inout  wire        sda        
);

    // ========================================================================
    // 1. Register Declarations (OpenCores Spec Page 7)
    // ========================================================================
  
    reg [7:0] prer_lo; 
    reg [7:0] prer_hi; 
    reg [7:0] ctr;     

    
    reg [7:0] txr;     
    wire [7:0] rxr;    

   
    reg [7:0] cr;      
    wire [7:0] sr;     

    // ========================================================================
    // 2. Internal Wires connecting the Sub-modules
    // ========================================================================
  
    wire        clk_en;       
    wire        bit_din;      
    wire        bit_dout;     
    wire        bit_ack;      
    
    wire        scl_oen;      
    wire        sda_oen;      
    wire        scl_in;      
    wire        sda_in;       

    wire [7:0]  byte_dout;    
    wire        byte_ack;     
    wire        byte_ack_out; 
    wire        i2c_busy;     

    // ========================================================================
    // 3. APB Read/Write Decode Logic
    // ========================================================================
  
    assign PREADY = 1'b1;                                 
    wire apb_write = PSEL & PENABLE & PWRITE & PREADY;    
    wire apb_read  = PSEL & PENABLE & ~PWRITE & PREADY;  

    // ========================================================================
    // 4. APB Register Write Logic (CPU -> Registers)
    // ========================================================================
  
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            
            prer_lo <= 8'hFF;
            prer_hi <= 8'hFF;
            ctr     <= 8'h00;
            txr     <= 8'h00;
            cr      <= 8'h00;
        end else begin
            if (apb_write) begin
                
                case (PADDR[2:0])
                    3'h0: prer_lo <= PWDATA[7:0];
                    3'h1: prer_hi <= PWDATA[7:0];
                    3'h2: ctr     <= PWDATA[7:0];
                    3'h3: txr     <= PWDATA[7:0];
                    3'h4: cr      <= PWDATA[7:0]; 
                    default: ;
                endcase
            end else begin
                if (byte_ack) begin
                    cr[7:4] <= 4'b0000;
                end
            end
        end
    end

    // ========================================================================
    // 5. APB Register Read Logic (Registers -> CPU)
    // ========================================================================
  
    always @(*) begin
        PRDATA = 32'h0000_0000; 
        if (apb_read) begin
            case (PADDR[2:0])
                3'h0: PRDATA[7:0] = prer_lo;
                3'h1: PRDATA[7:0] = prer_hi;
                3'h2: PRDATA[7:0] = ctr;
                3'h3: PRDATA[7:0] = rxr; 
                3'h4: PRDATA[7:0] = sr;  
                default: PRDATA[7:0] = 8'h00;
            endcase
        end
    end

    // ========================================================================
    // 6. Connect Status (SR) and Receive (RXR) Wires (Spec Page 9)
    // ========================================================================
  
    assign rxr = byte_dout; 
    assign sr[7]   = byte_ack_out; 
    assign sr[6]   = i2c_busy;     
    assign sr[5:2] = 4'b0000;      
    assign sr[1]   = i2c_busy;     
    assign sr[0]   = byte_ack;     

    // ========================================================================
    // 7. Physical Bidirectional Buffers (Tristate Logic)
    //   Uses Open-Drain structure to prevent short circuits on the I2C bus.
    // ========================================================================
  

    assign scl = (scl_oen == 1'b0) ? 1'b0 : 1'bz;
    assign sda = (sda_oen == 1'b0) ? 1'b0 : 1'bz;

   
    assign scl_in = scl;
    assign sda_in = sda;

    // ========================================================================
    // 8. Module Instantiations
    // ========================================================================

    
    i2c_clk_gen u_clock_gen (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .prescale ({prer_hi, prer_lo}), 
        .scl_out  (scl_oen),
        .scl_in   (scl_in),
        .clk_en   (clk_en)
    );

  
    i2c_bit_cntrl u_bit_ctrl (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .clk_en   (clk_en),
        .cmd      (bit_cmd),
        .din      (bit_din),
        .dout     (bit_dout),
        .cmd_ack  (bit_ack),
        .scl_oen  (scl_oen),
        .sda_oen  (sda_oen),
        .scl_in   (scl_in),
        .sda_in   (sda_in)
    );

    
    i2c_byte_cntrl u_byte_ctrl (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .start    (cr[7] & ctr[7]), 
        .stop     (cr[6] & ctr[7]),
        .read     (cr[5] & ctr[7]),
        .write    (cr[4] & ctr[7]),
        .ack_in   (cr[3]),
        .din      (txr),
        .dout     (byte_dout),
        .cmd_ack  (byte_ack),
        .ack_out  (byte_ack_out),
        .i2c_busy (i2c_busy),
        .bit_cmd  (bit_cmd),
        .bit_din  (bit_din),
        .bit_dout (bit_dout),
        .bit_ack  (bit_ack)
    );

endmodule
