`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 06/01/2024 08:47:24 PM
// Design Name: 
// Module Name: TranslationTable
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: Stores the offsets to be used to translate pages in the processor's address space to differnt regions of memory
// 
// Dependencies:
// 
// Revision: V-1.0.0.0
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module TranslationTable
(
    input wire clock,
    input wire internal_reset, // High initiates reset
    
    input wire [7:0] index_select, // Used to index into the table. Calculated from processor's address lines
    input wire byte_select, // Select lower or upper byte (0 for lower byte, 1 for upper byte)
    
    input wire byte_we, // Enable signal for writing to the table with the byte data bus
    inout wire [7:0] byte_data_bus, // Internal data bus for byte, connected to system bus in root when necessary
    
    input wire word_we, // Enable signal for writing to the table with the word data bus
    output reg word_wr, // Write received signal from the table to asynchronous writer 
    inout wire [15:0] word_data_bus // Internal data bus for whole word
);

    // Translation table to be stored in BRAM
    (* ram_style = "block" *) reg [15:0] translation_table [0:255]; // Translations for each page (256) in the processor's 16 bit address space
    
    // Reset sequence, initialize the table
    integer i;
    always @(posedge internal_reset) begin
        for(i = 0; i < 256; i = i + 1) begin
            translation_table[i] <= 16'b0;
        end
    end
    
    
    // Read/Write controle
    assign word_data_bus = word_we ? 16'bz : translation_table[index_select];
    always @(index_select, word_data_bus) begin
        if(word_we && word_data_bus !== 16'bz) begin
            translation_table[index_select] <= word_data_bus;
            word_wr <= 1;
        end
    end
    always @(negedge word_we) begin
        word_wr <= 0;
    end
    
    assign byte_data_bus = byte_we ? 8'bz : (byte_select ? translation_table[index_select][15:8] : translation_table[index_select][7:0]);
    always @(byte_data_bus) begin
        if(byte_we && byte_data_bus !== 8'bz) begin
            if(byte_select) begin
                translation_table[index_select][15:8] <= byte_data_bus; // Write upper byte
            end else begin
                translation_table[index_select][7:0] <= byte_data_bus; // Write lower byte
            end
        end
    end

endmodule