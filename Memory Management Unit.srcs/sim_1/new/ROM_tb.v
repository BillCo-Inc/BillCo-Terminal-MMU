`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/29/2024 06:23:14 PM
// Design Name: 
// Module Name: ROM Testbench
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: Test Bench for simulation of syncronous read only memory chips in the broader system
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ROM_tb
#(
    parameter ASSIGNED_ADDRESS = 16'b0,
    parameter ADDRESS_VALUE = 8'hff
)
(
    input wire clock,
    input wire chip_enable,
    input wire rwb, // 1 for read, 0 for write. From the perspective of the processor
    input wire [15:0] address_bus, // System address bus
    inout wire [7:0] data_bus // System data bus
);
    
    integer i;
    
    reg [7:0] chip_memory [0:65535]; // The memory space of the flash chip
    reg [7:0] write_buffer; // Register to store value for read to be put onto bus on positive edge following read request on negative edge
    reg data_bus_drive; // Control signal to drive the data bus
    
    initial begin
        for (i = 0; i < 65356; i = i + 1) begin
            chip_memory[i] = 8'h00; // Initialize all addresses to 0
        end
        
        chip_memory[ASSIGNED_ADDRESS] = ADDRESS_VALUE;
    end
    
    assign data_bus = (data_bus_drive) ? write_buffer : 8'bz;
    
    always @(posedge clock) begin
        data_bus_drive <= 0;
        
        if (chip_enable) begin // Check to see if this chip is enabled
            if (rwb) begin // Write to data bus
                write_buffer <= chip_memory[address_bus];
                data_bus_drive <= 1;
            end
        end
    end
endmodule
