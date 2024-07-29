`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 06/01/2024 08:47:24 PM
// Design Name: 
// Module Name: PageConfigTable
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: Module handles the page configuration table
// 
// Dependencies:
// 
// Revision: V-1.0.0.0
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module PageConfigTable 
(
    input wire clock, 
    input wire internal_reset, // High initiates reset
    
    input wire byte_we, // Enable signal for writing to the table
    output reg byte_wr, // Write received signal for the byte bus
    input wire [8:0] index_select, // Used to index into the table. Driven by processor address bus high byte
    
    inout wire [7:0] data_bus, // Internal data bus, connected to system bus in root when necessary
    
    input wire high_speed_we, // Enable signal for a high speed write
    output reg high_speed_wr, // Write received signal for the high speed bus
    input wire [71:0] high_speed_bus // Internal high speed bus for flashing table
);
    
    // Bit definitions for page configurations in page config table
    // Bit 0, RAM bank/chip select bit 0
    // Bit 1, RAM bank/chip select bit 1
    // Bit 2, RAM bank/chip select bit 2
    // Bit 3, RAM bank/chip select bit 3
    
    // Bit 4, ROM bank/chip select bit 0
    // Bit 5, ROM bank/chip select bit 1
    
    // Bit 6, RAM or ROM page (1 for RAM, 0 for ROM)
    
    // Bit 7, is page in shared memory (1 for true, 0 for false)
    
    // Page table to be stored in BRAM
    (* ram_style = "block" *) reg [7:0] page_config_table [0:260];
    
    
    // Read/Write control
    reg[4:0] i;
    assign data_bus = (byte_we | high_speed_we) ? 8'bz : page_config_table[index_select];
    
    always @(posedge high_speed_we, posedge byte_we) begin
        if(high_speed_we && high_speed_bus !== 72'bz) begin // High speed writing to the configuration table
            for(i = 0; i < 4'd9; i = i + 1) begin
                page_config_table[index_select + i] <= high_speed_bus[(8-i)*8 +: 8]; // Write the 9 bytes from high speed bus to contiguos indexes in reverse order
            end
            
            high_speed_wr <= 1;
        end else if(byte_we && data_bus !== 8'dz) begin // Writing to the configuration table
            page_config_table[index_select] <= data_bus; // Write the value of the data bus to selected page config index
            
            byte_wr <= 1;
        end
    end
    always @(negedge byte_we) begin
        byte_wr <= 0;
    end
    always @(negedge high_speed_we) begin
        high_speed_wr <= 0;
    end
    
    /*always @(posedge clock) begin
        if(high_speed_write && high_speed_bus !== 72'bz) begin // High speed writing to the configuration table
            for(i = 0; i < 4'd9; i = i + 1) begin
                page_config_table[index_select + i] <= high_speed_bus[(8-i)*8 +: 8]; // Write the 9 bytes from high speed bus to contiguos indexes in reverse order
            end
        end else if(write_enable && data_bus !== 8'dz) begin // Writing to the configuration table
            page_config_table[index_select] <= data_bus; // Write the value of the data bus to selected page config index
        end
    end
    
    always @(negedge clock) begin // DDR capibility
        if(high_speed_write && high_speed_bus !== 72'bz) begin
            for(i = 0; i < 4'd9; i = i + 1) begin
                page_config_table[index_select + i] <= high_speed_bus[(8-i)*8 +: 8];
            end
        end else if(write_enable && data_bus !== 8'dz) begin // Writing to the configuration table
            page_config_table[index_select] <= data_bus; // Write the value of the data bus to selected page config index
        end
    end*/

endmodule