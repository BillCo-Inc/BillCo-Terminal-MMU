`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 06/08/2024 02:00:00 PM
// Design Name: 
// Module Name: RangeConfigController
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: This module handles the access to the MMU's range selection and configuration registers as well as configuring the MMU when a configuration is specified
// 
// Dependencies: 
// 
// Revision: V-1.0.0.0
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module RangeConfigController 
(
    input wire clock,
    input wire internal_reset, // Internal reset signal from root module. Positive indicates a reset
    
    output reg proc_ready, // MMU can drive this line to halt the processor (low to halt)
    
    input wire start_write_enable, // Enable signal for writing to the range start register
    input wire end_write_enable, // Enable signal for writing to the range end register
    input wire config_write_enable, // Enable signal for writing to the range configuration register
    
    inout wire [7:0] start_data_bus, // Data bus for range start register, bi-directional
    inout wire [7:0] end_data_bus, // Data bus for range end register, bi-directional
    inout wire [7:0] config_data_bus, // Data bus for range configuration register, bi-directional
    
    output reg [8:0] page_index, // Index select for page config table
    
    output reg page_index_write, // Write enable line for single index bus in PageConfigController
    output wire [7:0] page_index_bus, // Single index bus in PageConfigController
    
    output reg page_high_speed_we, // Write enable line for high speed bus in PageConfigController
    output wire [71:0] page_high_speed_bus // High speed bus to PageConfigController
);
    
    reg [7:0] range_start; // Specifies the starting index for the range of pages when in range configuration mode (0-255)
    reg [7:0] range_end; // Specifies the ending index for the range of pages when in range configuration mode (0-255)
    reg [7:0] range_config; // Specifies the page properties for the range of pages when in range configuration mode (bits indicate properties)
    
    localparam IDLE = 2'b00, FLASHING = 2'b01, DONE = 2'b10;
    reg [1:0] state = IDLE;
    reg [7:0] page_table_index;
    
    always @(posedge internal_reset) begin // Reset signal detected
        proc_ready <= 1;
        range_start <= 0;
        range_end <= 0;
        page_index_write <= 0;
        page_high_speed_we <= 0;
    end
    
    always @(range_config) begin // Change in range configuration detected
        state <= FLASHING; // Set state to flash page config table when change in preset detected
        proc_ready <= 0; // Pull the ready signal low to halt the processor during the configuration flash
        page_table_index <= range_start; // Initialize the page config table index to the value in the range start register
    end
    
    assign start_data_bus = start_write_enable ? 8'bz : range_start;
    assign end_data_bus = end_write_enable ? 8'bz : range_end;
    assign config_data_bus = config_write_enable ? 8'bz : range_config;
    assign page_index_bus = page_index_write ? range_config : 8'bz;
    assign page_high_speed_bus = page_high_speed_we ?  {9{range_config}} : 72'bz;
    always @(start_data_bus, end_data_bus, config_data_bus) begin
        page_index_write <= 0; // De-assert Page Configuration Table write enable by default each cycle
        page_high_speed_we <= 0; // De-assert Page Configuration Table high speed write enable by default each cycle
        
        if (start_write_enable && start_data_bus !== 8'bz) begin // Processor is writing to the range start register
            range_start <= start_data_bus; // Write the value on the range start data bus to the register
        end else if(end_write_enable && end_data_bus !== 8'bz) begin // Processor is writing to the range end register
            range_end <= end_data_bus; // Write the value on the range end data bus to the register        
        end else if(config_write_enable && config_data_bus !== 8'bz) begin // Processor is writing to the range configuration register
            range_config <= config_data_bus; // Write the value on the range configuration data bus to the register
        end
    end
    
    always @(posedge clock) begin // DDR write capability
        page_high_speed_we <= 0; // De-assert the high speed bus write signal by default
        page_index_write <= 0; // De-assert the single index write signal by default
            
        if(state == FLASHING) begin
            page_index <= page_table_index; // Output index selection on index select bus
            if((range_end - page_table_index) > 8) begin // The number of page indices to flash is 9 or greater
                page_high_speed_we <= 1; // Enable the high speed bus to the page configuration table
                page_table_index <= page_table_index + 9; // Increment the index counter by 9
            end else begin // The number of page indices to flash is less than 9 so we cant use the high speed bus anymore
                page_index_write <= 1; // Enable the single index write signal to the page configuration table
                page_table_index <= page_table_index + 1; // Increment the index counder by 1
            end
            
            if(page_table_index == range_end) begin // The index conter is at the last index of the range
                proc_ready <= 1; // Enable the processesor again
            state <= IDLE; // Set state back to IDLE
            end
        end
    end
    
    always @(negedge clock) begin // DDR write capability
        page_high_speed_we <= 0; // De-assert the high speed bus write signal by default
        page_index_write <= 0; // De-assert the single index write signal by default
        
        if(state == FLASHING) begin
            page_index <= page_table_index; // Output index selection on index select bus
            if((range_end - page_table_index) > 8) begin // The number of page indices to flash is 9 or greater
                page_high_speed_we <= 1; // Enable the high speed bus to the page configuration table
                page_table_index <= page_table_index + 9; // Increment the index counter by 9
            end else begin // The number of page indices to flash is less than 9 so we cant use the high speed bus anymore
                page_index_write <= 1; // Enable the single index write signal to the page configuration table
                page_table_index <= page_table_index + 1; // Increment the index counder by 1
            end
            
            if(page_table_index == range_end) begin // The index conter is at the last index of the range
                proc_ready <= 1; // Enable the processesor again
            state <= IDLE; // Set state back to IDLE
            end
        end
    end
endmodule
