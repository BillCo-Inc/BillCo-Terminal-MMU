`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/22/2024 02:45:13 PM
// Design Name: 
// Module Name: Zero_Stack_OffsetSelect
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: This module handles the access to the MMU's zero page and stack page offset selection registers
// 
// Dependencies: 
// 
// Revision: V-1.0.0.0
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Zero_Stack_PageNumSelect
#(
    parameter ZERO_PAGE_NUM = 8'd0,
    parameter STACK_PAGE_NUM = 8'd1
)
(
    input wire clock,
    input wire internal_reset, // Internal reset signal from root module. Positive indicates a reset
    
    input wire zp_write_enable, // Enable signal for writing to the zero page, page number selection register
    input wire stack_write_enable, // Enable signal for writing to the stack page, page number selection register
    
    inout wire [7:0] zp_data_bus, // Data bus for zero page, page number selection register, bi-directional
    inout wire [7:0] stack_data_bus, // Data bus for stack page, page number selection register, bi-directional
    
    output reg translation_table_word_we, // Write enable signal connection to translation table for its word bus
    input wire translation_table_word_wr, // Write received signal from translation table for asynchronous operation
    output reg [7:0] translation_table_index_select, // Index select signal to translation table
    output wire [15:0] translation_table_word_bus // Word bus connection to translation table
);
    
    reg zeroPage_we;
    reg [7:0] zeroPage_pageNum_select;
    
    reg stackPage_we;
    reg [7:0] stackPage_pageNum_select;
    
    always @(posedge internal_reset) begin // Reset signal detected
        zeroPage_we <= 0;
        zeroPage_pageNum_select <= 8'h00; // Initialize the zero page offset selection register to 0
        
        stackPage_we <= 0;
        stackPage_pageNum_select <= 8'h01; // Initialize the stack page offset selection register to 0
    end
    
    assign zp_data_bus = zp_write_enable ? 8'bz : zeroPage_pageNum_select;
    always @(zp_data_bus) begin
        if(zp_write_enable && zp_data_bus !== 8'bz) begin
            zeroPage_pageNum_select <= zp_data_bus;
        end
    end
    
    assign stack_data_bus = stack_write_enable ? 8'bz : stackPage_pageNum_select;
    always @(stack_data_bus) begin
        if(stack_write_enable && stack_data_bus !== 8'bz) begin
            if(stack_data_bus > 0) begin
                stackPage_pageNum_select <= stack_data_bus;
            end
        end
    end
    
    assign translation_table_word_bus = zeroPage_we ? {zeroPage_pageNum_select, 8'h00} : 16'bz;
    always @(zeroPage_pageNum_select) begin
        translation_table_word_we <= 1;
        zeroPage_we <= 1;
        translation_table_index_select <= ZERO_PAGE_NUM;
    end
    
    
    assign translation_table_word_bus = stackPage_we ? ({stackPage_pageNum_select, 8'h00} - 16'h0100) : 16'bz;
    always @(stackPage_pageNum_select) begin
        translation_table_word_we <= 1;
        stackPage_we <= 1;
        translation_table_index_select <= STACK_PAGE_NUM;
    end
    
    always @(posedge translation_table_word_wr) begin
        translation_table_word_we <= 0;
        zeroPage_we <= 0;
        stackPage_we <= 0;
    end
endmodule
