`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 05/19/2024 05:02:59 PM
// Design Name: 
// Module Name: BankSelector
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: This module handles the access to the MMU's defualt bank selection registers
// 
// Dependencies: 
// 
// Revision: V-1.0.0.0
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module BankSelector 
#(
    RAM_BANKS = 4,
    ROM_BANKS = 4
)
(
    input wire clock,
    input wire internal_reset, // Internal reset signal from root module. Positive indicates a reset
    
    input wire ram_write_enable, // Enable signal for writing to the ram bank selection register
    input wire rom_write_enable, // Enable signal for writing to the rom bank selection register
    
    inout wire [3:0] ram_data_bus, // Data bus for ram select register, bi-directional
    inout wire [1:0] rom_data_bus // Data bus for rom select register, bi-directional
);
    
    reg [3:0] ram_bank_select; // Register for storing the default active RAM bank (at RAM_BANK_SELECT_ADDR)
    reg [1:0] rom_bank_select; // Register for storing the default active ROM bank (at ROM_BANK_SELECT_ADDR)
    
    always @(posedge internal_reset) begin // Reset signal detected
        ram_bank_select <= 4'b0; // Initialize the ram select register to 0
        rom_bank_select <= 2'b0; // Initialize the rom select register to 0
    end
    
    assign ram_data_bus = ram_write_enable ? 4'bz : ram_bank_select;
    assign rom_data_bus = rom_write_enable ? 2'bz : rom_bank_select;
    always @(ram_data_bus, rom_data_bus) begin
        if (ram_write_enable && ram_data_bus !== 4'bz) begin // Processor is writing to the ram bank selection register
            if (ram_data_bus < RAM_BANKS) begin // Check that the value is within the supported range
                ram_bank_select <= ram_data_bus; // Write the data bus to the register
            end
        end else if (rom_write_enable && rom_data_bus !== 2'bz) begin // Processor is writing to the rom bank selection register
            if (rom_data_bus < ROM_BANKS) begin // Check that the value is within the supported range
                rom_bank_select <= rom_data_bus; // Write the data bus to the register
            end
        end
    end
endmodule   
