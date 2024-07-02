`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 06/13/2024 01:16:48 PM
// Design Name: 
// Module Name: AddressTransChipEnable
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: This module handles address translation and the chip enable signals to control the what memory chips get accessed
// 
// Dependencies:
// 
// Revision: V-1.0.0.0
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module AddressTransChipEnable
#(
    parameter IO_SELECT_BITS = 8'd5, // Drives the number of bits in the IO map index select net
    parameter IO_REG_SIZE = 3'd1, // Drives the number of bits in the IO map data bus
    parameter IO_PAGE_NUM = 8'hFE, // Specifies what page of memory is IO mapped
    parameter IO_MAP_BLOCK_SIZE = 8'd8, // Defines the number of addresses per block in the IO map. Each block corresponds to one peripheral device ID and drives a peripheral chip enable line
    
    parameter RAM_HIGH_BIT = 4'd3, // Maximum number of RAM banks/chips (64k) supported on system. Drives number of bank chip enable lines
    parameter ROM_HIGH_BIT = 2'd3, // Maximum number of ROM banks/chips (64k) supported on system. Drives number of bank chip enable lines
    parameter PERI_HIGH_BIT = 2'd1 // Maximum number of addressable peripheral chips supported on system. Drives number of peripheral chip enable lines
)
(
    input wire clock,
    input wire internal_reset, // Internal reset signal from root module. Positive indicates a reset
    
    input wire translate_enable, // Line to enable this module. When high this module will output chip enable signals and translated addresses
    
    input wire io_enable, // Line to enable I/O. Driven by the high bit of the config_mode register (1 for enabled, 0 for disabled)
    
    output reg [7:0] page_table_index, // Used to select the index to read in the page configuration table
    input wire [7:0] page_table_data_bus, // Used to read the selected page configuration
    
    output reg [7:0] translation_table_index, // Used to select the index to read in the translation table
    input wire [15:0] translation_table_data_bus, // Used to read the selected page translation
    
    output reg [IO_SELECT_BITS - 1:0] io_map_index_select, // Used to select the index to read in the io map
    input wire [IO_REG_SIZE - 1:0] io_map_data_bus, // Used to read the selected IO block device ID. Drives the peripheral chip enable lines
    
    input wire [3:0] default_ram_data, // Used to read the current default RAM bank selection
    input wire [1:0] default_rom_data, // Used to read the current default ROM bank selection
    
    input wire rwb, // Read Write Bar signal from processor (1 for read, 0 for write)
    input wire [15:0] proc_address_bus, // 16-bit address bus from the processor
    
    output wire [15:0] sys_address_bus, // 16-bit address bus to the system
    
    output reg [RAM_HIGH_BIT:0] ram_chip_enable, // Chip enable lines for RAM memory chips
    output reg [ROM_HIGH_BIT:0] rom_chip_enable, // Chip enable lines for ROM memory chips
    output reg [PERI_HIGH_BIT:0] peri_chip_enable // Chip enable lines for peripheral chips
);
    
    //reg [15:0] adjusted_address;
    
    always @(posedge internal_reset) begin
        ram_chip_enable <= 0; // Disable all RAM chips on reset
        rom_chip_enable <= 0; // Disable all ROM chips on reset
        peri_chip_enable <= 0; // Disable all peripheral chips on reset
        //adjusted_address <= 0; // Zero the system bus address on reset
    end
    
    // Bit definitions for page configurations in page config table
    // Bit 0, RAM bank/chip select bit 0
    // Bit 1, RAM bank/chip select bit 1
    // Bit 2, RAM bank/chip select bit 2
    // Bit 3, RAM bank/chip select bit 3
    
    // Bit 4, ROM bank/chip select bit 0
    // Bit 5, ROM bank/chip select bit 1
    
    // Bit 6, RAM or ROM page (1 for RAM, 0 for ROM)
    
    // Bit 7, is page in shared memory (1 for true, 0 for false)
    
    assign sys_address_bus = (translate_enable) ? proc_address_bus + translation_table_data_bus : 16'bz; // Drive the system address lines with the adjusted address unless we are disconnected from root module    
    always @(*) begin
        ram_chip_enable <= 0; // Disable all RAM chips by default each cycle
        rom_chip_enable <= 0; // Disable all ROM chips by default each cycle
        peri_chip_enable <= 0; // Disable all peripheral chips by default each cycle
        
        if(translate_enable) begin // Processor is accessing system resources, not MMU intenals
            if(io_enable && (proc_address_bus[15:8] == IO_PAGE_NUM)) begin // IO is mapped into the address space and processor is accessing IO
                io_map_index_select <= proc_address_bus[7:0] / IO_MAP_BLOCK_SIZE; // Divide the low byte of the processor address by the number of addresses per block to get the io map index
                peri_chip_enable[io_map_data_bus] <= 1'b1; // Enable the corresponding peripheral device
            end else begin // IO is NOT mapped into the address space, or processor is not accessing IO addresses
                page_table_index <= proc_address_bus[15:8]; // Drive page config table index select from high byte of processor's address lines
                translation_table_index <= proc_address_bus[15:8]; // Drice translation table index select from high byte of processor's address lines
                // adjusted_address <= proc_address_bus + translation_table_data_bus; // Calculate final adjusted address from processor address and page translation
                
                if(page_table_data_bus[6]) begin // Bit 6 of the page configuration is 1. Page is a RAM page
                    if(page_table_data_bus[7] && !rwb) begin // Bit 7 of the page configuration is 1, page is in shared RAM. And the processor is writing
                        ram_chip_enable <= {RAM_HIGH_BIT + 1{1'b1}}; // Enable all RAM chips so memory write propegates to all RAM modules on the system bus
                    end else begin // Page is not shared memory or we are reading
                        if(page_table_data_bus[3:0] == 0) begin // The page is configured to use the currently selected default RAM bank
                            ram_chip_enable[default_ram_data] <= 1'b1; // Set the corresponding RAM chip enable line
                        end else begin // The page is configured to use an explicit RAM bank selection
                            ram_chip_enable[page_table_data_bus[3:0]] <= 1'b1; // Set the corresponding RAM chip enable line
                        end
                    end
                end else begin // Bit 6 of the page configuration is 0. Page is a ROM page
                    if(page_table_data_bus[5:4] == 0) begin // The page is configured to use the currently selected default ROM bank
                        rom_chip_enable[default_rom_data] <= 1'b1; // Set the corresponding ROM chip enable line
                    end else begin // The page is configured to use an explicit ROM bank selection
                        rom_chip_enable[page_table_data_bus[5:4]] <= 1'b1; // Set the corresponding ROM chip enable line
                    end
                end
            end
            
            /*if(io_enable) begin // IO is mapped into the address space
                if(proc_address_bus[15:8] == IO_PAGE) begin // Processor is accessing IO mapped region of memory
                    io_map_index_select <= proc_address_bus[7:0] / IO_MAP_BLOCK_SIZE; // Divide the low byte of the processor address by the number of addresses per block to get the io map index
                    peri_chip_enable[io_map_data_bus] <= 1'b1; // Enable the corresponding peripheral device
                end else begin // Processor is not accessing IO mapped region of memory
                    page_table_index <= proc_address_bus[15:8]; // Drive page config table index select from high byte of processor's address lines
                    translation_table_index <= proc_address_bus[15:8]; // Drice translation table index select from high byte of processor's address lines
                    adjusted_address <= proc_address_bus + translation_table_data_bus; // Calculate final adjusted address from processor address and page translation
                    
                    if(page_table_data_bus[6]) begin // Bit 6 of the page configuration is 1. Page is a RAM page
                        if(page_table_data_bus[7] && !rwb) begin // Bit 7 of the page configuration is 1, page is in shared RAM. And the processor is writing
                            ram_chip_enable <= {RAM_HIGH_BIT + 1{1'b1}}; // Enable all RAM chips so memory write propegates to all RAM modules on the system bus
                        end else begin // Page is not shared memory or we are reading
                            if(page_table_data_bus[3:0] == 0) begin // The page is configured to use the currently selected default RAM bank
                                ram_chip_enable[default_ram_data] <= 1'b1; // Set the corresponding RAM chip enable line
                            end else begin // The page is configured to use an explicit RAM bank selection
                                ram_chip_enable[page_table_data_bus[3:0]] <= 1'b1; // Set the corresponding RAM chip enable line
                            end
                        end
                    end else begin // Bit 6 of the page configuration is 0. Page is a ROM page
                        if(page_table_data_bus[5:4] == 0) begin // The page is configured to use the currently selected default ROM bank
                            rom_chip_enable[default_rom_data] <= 1'b1; // Set the corresponding ROM chip enable line
                        end else begin // The page is configured to use an explicit ROM bank selection
                            rom_chip_enable[page_table_data_bus[5:4]] <= 1'b1; // Set the corresponding ROM chip enable line
                        end
                    end
                end
            end else begin // IO is NOT mapped into the address space
                page_table_index <= proc_address_bus[15:8]; // Drive page config table index select from high byte of processor's address lines
                translation_table_index <= proc_address_bus[15:8]; // Drice translation table index select from high byte of processor's address lines
                adjusted_address <= proc_address_bus + translation_table_data_bus; // Calculate final adjusted address from processor address and page translation
                
                if(page_table_data_bus[6]) begin // Bit 6 of the page configuration is 1. Page is a RAM page
                    if(page_table_data_bus[7] && !rwb) begin // Bit 7 of the page configuration is 1, page is in shared RAM. And the processor is writing
                        ram_chip_enable <= {RAM_HIGH_BIT + 1{1'b1}}; // Enable all RAM chips so memory write propegates to all RAM modules on the system bus
                    end else begin // Page is not shared memory or we are reading
                        if(page_table_data_bus[3:0] == 0) begin // The page is configured to use the currently selected default RAM bank
                            ram_chip_enable[default_ram_data] <= 1'b1; // Set the corresponding RAM chip enable line
                        end else begin // The page is configured to use an explicit RAM bank selection
                            ram_chip_enable[page_table_data_bus[3:0]] <= 1'b1; // Set the corresponding RAM chip enable line
                        end
                    end
                end else begin // Bit 6 of the page configuration is 0. Page is a ROM page
                    if(page_table_data_bus[5:4] == 0) begin // The page is configured to use the currently selected default ROM bank
                        rom_chip_enable[default_rom_data] <= 1'b1; // Set the corresponding ROM chip enable line
                    end else begin // The page is configured to use an explicit ROM bank selection
                        rom_chip_enable[page_table_data_bus[5:4]] <= 1'b1; // Set the corresponding ROM chip enable line
                    end
                end
            end*/
        end
    end
    
endmodule
