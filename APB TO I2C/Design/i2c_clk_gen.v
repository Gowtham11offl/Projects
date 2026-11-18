`timescale 1ns/1ps

module i2c_clk_gen ( 
   
  
    input  wire        clk,       
    input  wire        rst_n,     
    output reg         clk_en,     
    input  wire [15:0] prescale,  
    input  wire        scl_out,   
    input  wire        scl_in     
);

    reg [15:0] counter;           

    wire clk_stretch_active = (scl_out == 1'b1) && (scl_in == 1'b0);

   
    // Clock Division & Timing Tick Generation Block
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            clk_en <= 1'b0;
        end else begin
            if (clk_stretch_active) begin
                counter <= counter;
                clk_en <= 1'b0;
            end else if(counter == 0) begin
                counter <= prescale;
                clk_en <= 1'b1;
            end else begin
                counter <= counter - 16'd1;
                clk_en <= 1'b0;
            end
        end
    end
endmodule
