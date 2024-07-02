`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 06/08/2024 02:00:00 PM
// Design Name: 
// Module Name: PresetsConfigController
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: This module handles the access to the MMU's presets selection register as well as configuring the MMU when a preset is selected
// 
// Dependencies: 
// 
// Revision: V-1.0.0.0
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module PresetsConfigController 
(
    input wire clock,
    input wire internal_reset, // Internal reset signal from root module. Positive indicates a reset
    
    output reg proc_ready, // MMU can drive this line to halt the processor (low to halt)
    
    input wire write_enable, // Enable signal for writing to the preset selection register
    
    inout wire [7:0] data_bus, // Data bus for preset selection register, bi-directional
    
    output reg page_high_speed_we, // Write enable line for high speed bus in PageConfigController
    output reg [8:0] page_index, // Index select for page config table
    output wire [71:0] page_high_speed_bus // High speed bus to PageConfigController
);
    
    reg [7:0] preset; // Specifies the preset configuration to use when in presets configuration mode (15 presets)
    // Preset 00h, 0 pages / 0 pages shared RAM (0 bytes / 0 bytes shared), 256 pages ROM (65536 bytes)
    // Preset 01h, 64 pages / 0 pages shared RAM (16384 bytes / 0 bytes shared), 192 pages ROM (49152 bytes)
    // Preset 02h, 128 pages / 0 pages shared RAM (32768 bytes / 0 bytes shared), 128 pages ROM (32769 bytes)
    // Preset 04h, 192 pages / 0 pages shared RAM (49152 bytes / 0 bytes shared), 64 pages ROM (16384 bytes)
    // Preset 08h, 256 pages / 0 pages shared RAM (65536 bytes / 0 bytes shared), 0 pages ROM (0 bytes)
    
    // Preset 10h, 0 pages / 64 pages shared RAM (0 bytes / 16384 bytes shared), 192 pages ROM (49152 bytes)
    // Preset 11h, 64 pages / 64 pages shared RAM (16384 bytes / 16384 bytes shared), 128 pages ROM (32769 bytes)
    // Preset 12h, 128 pages / 64 pages shared RAM (32768 bytes / 16384 bytes shared), 64 pages ROM (16384 bytes) (default preset)
    // Preset 14h, 192 pages / 64 pages shared RAM (49153 bytes / 16384 bytes shared), 0 pages ROM (0 bytes)
    
    // Preset 20h, 0 pages / 128 pages shared RAM (0 bytes / 32768 bytes shared), 128 pages ROM (32769 bytes)
    // Preset 21h, 64 pages / 128 pages shared RAM (16384 bytes / 32768 bytes shared), 64 pages ROM (16384 bytes)
    // Preset 22h, 128 pages/ 128 pages shared RAM (32768 bytes / 32768 bytes shared), 0 pages ROM (0 bytes)
    
    // Preset 40h, 0 pages / 192 pages shared RAM (0 bytes / 49153 bytes shared), 64 pages ROM (16384 bytes)
    // Preset 41h, 64 pages / 192 pages shared RAM (16384 bytes / 49153 bytes shared), 0 pages ROM (0 bytes)
    
    // Preset 80h, 0 pages / 256 pages shared RAM (0 bytes / 65536 bytes shared), 0 pages ROM (0 bytes)
    
    (* ram_style = "block" *) reg [71:0] preset_tables [0:14][0:28]; // 15 tables of 261 bytes in 9 byte groups. Contain the presets for flashing the page configuration table
    
    localparam IDLE = 2'b00, FLASHING = 2'b01, DONE = 2'b10;
    reg [1:0] state = IDLE;
    reg [7:0] page_table_index;
    reg [3:0] preset_index;
    reg [4:0] preset_table_index;
    
    initial begin
        proc_ready = 0; // Disable the processor while initializing
        
        $readmemh("PresetsData.mem", preset_tables);
    end
    
    always @(posedge internal_reset) begin // Reset signal detected
        preset <= 8'h12; // On reset set the preset config to the default config, 0x12
        page_high_speed_we <= 0; // On reset de-assert high speed bus write enable
    end
    
    always @(preset) begin // Change in preset detected
        state <= FLASHING; // Set state to flash page config table when change in preset detected
        proc_ready <= 0; // Pull the ready signal low to halt the processor during the configuration flash
        page_table_index <= 0; // Initialize the page config table index to 0
        preset_table_index <= 5'h1F; // Initialize the presets table index to 1F (31) so it overflows to 0 on first iteration
        
        case(preset)
            8'h00: preset_index <= 0;
            8'h01: preset_index <= 1;
            8'h02: preset_index <= 2;
            8'h04: preset_index <= 3;
            8'h08: preset_index <= 4;
            8'h10: preset_index <= 5;
            8'h11: preset_index <= 6;
            8'h12: preset_index <= 7;
            8'h14: preset_index <= 8;
            8'h20: preset_index <= 9;
            8'h21: preset_index <= 10;
            8'h22: preset_index <= 11;
            8'h40: preset_index <= 12;
            8'h41: preset_index <= 13;
            8'h80: preset_index <= 14;
        endcase
    end
    
    assign data_bus = write_enable ? 8'bz : preset;
    assign page_high_speed_bus = page_high_speed_we ? preset_tables[preset_index][preset_table_index] : 72'bz;
    always @(data_bus) begin
        if (write_enable && data_bus !== 8'bz) begin // Processor is writing to the preset configuration selection register
            case(data_bus)
                8'h00, 8'h01, 8'h02, 8'h04, 8'h08,
                8'h10, 8'h11, 8'h12, 8'h14,
                8'h20, 8'h21, 8'h22,
                8'h40, 8'h41,
                8'h80: preset <= data_bus;
                
                default: preset <= 8'h12; // Set selection to default mode if input invalid
            endcase
        end
    end
    
    always @(posedge clock) begin // DDR write capability
        if(state == FLASHING) begin
            if(preset_table_index != 28) begin
                page_high_speed_we <= 1; // Enable the high speed bus to the page configuration table
                page_index <= page_table_index; // Output index selection on index select bus
            
                preset_table_index <= preset_table_index + 1;
                page_table_index <= page_table_index + 9;
            end else begin
                page_high_speed_we <= 0; // De-assert the Page Configuration Table high speed write enable by default each cycle
                proc_ready <= 1; // Enable the processor again
                state <= IDLE; // Set state back to IDLE
            end
        end
    end
    
    always @(negedge clock) begin // DDR write capability
        if(state == FLASHING) begin
            if(preset_table_index != 28) begin
                page_high_speed_we <= 1; // Enable the high speed bus to the page configuration table
                page_index <= page_table_index; // Output index selection on index select bus
            
                preset_table_index <= preset_table_index + 1;
                page_table_index <= page_table_index + 9;
            end else begin
                page_high_speed_we <= 0; // De-assert the Page Configuration Table high speed write enable by default each cycle
                proc_ready <= 1; // Enable the processor again
                state <= IDLE; // Set state back to IDLE
            end
        end
    end
    
endmodule
