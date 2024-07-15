`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 05/24/2024 08:47:24 PM
// Design Name: 
// Module Name: MemoryManagementUnit
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: This is the root module used to define the architecture of the MMU unit
// 
// Dependencies: BankSelector.v
// 
// Revision: V-2.0.0.0
// Revision 2.0 - Design number 2
// Additional Comments: See "Old" directory for original version
// 
//////////////////////////////////////////////////////////////////////////////////


module MemoryManagementUnit 
#(
    parameter RAM_HIGH_BIT = 4'd3, // Maximum number of RAM banks/chips (64k) supported on system. Drives number of bank chip enable lines
    parameter ROM_HIGH_BIT = 2'd3, // Maximum number of ROM banks/chips (64k) supported on system. Drives number of bank chip enable lines
    parameter PERI_HIGH_BIT = 2'd1 // Maximum number of addressable peripheral chips supported on system. Drives number of peripheral chip enable lines
)
(
    input wire clock,
    input wire resetb,
    
    output wire proc_ready, // MMU can drive this line to halt the processor (low will halt)
    input wire rwb, // Read Write Bar signal from processor (1 for read, 0 for write)
    input wire [15:0] proc_address_bus, // 16-bit address bus from the processor
    
    output wire [15:0] sys_address_bus, // 16-bit address bus to the system
    
    inout wire [7:0] data_bus, // 8-bit system data bus, bi-directional
    
    output wire [RAM_HIGH_BIT:0] ram_chip_enable, // Chip enable lines for RAM memory chips
    output wire [ROM_HIGH_BIT:0] rom_chip_enable, // Chip enable lines for ROM memory chips
    output wire [PERI_HIGH_BIT:0] peri_chip_enable // Chip enable lines for peripheral chips
);
    localparam PAGE_TABLE_START_ADDR = 16'h0000;
    localparam PAGE_TABLE_END_ADDR = 16'h00FF;
    
    localparam TRANSLATION_TABLE_START_ADDR = 16'h0100;
    localparam TRANSLATION_TABLE_END_ADDR = 16'h02FF;
    
    localparam IO_MAP_TABLE_START_ADDR = 16'h0000;
    localparam IO_MAP_TABLE_END_ADDR = 16'h00FF;
    
    localparam IO_PAGE_NUM = 8'hFE;
     
    localparam VIA_ADDR_START = 16'hFEE0;
    localparam VIA_ADDR_END = 16'hFEEF;
    
    localparam ACIA_ADDR_START = 16'hFEF0;
    localparam ACIA_ADDR_END = 16'hFEF3;
    
    localparam RANGE_START_ADDR = 16'hFFF4;
    localparam RANGE_END_ADDR = 16'hFFF5;
    localparam RANGE_CONFIG_ADDR = 16'hFFF6;
    
    localparam PRESET_SELECT_ADDR = 16'hFFF6;
    
    localparam ROM_BANK_SELECT_ADDR = 16'hFFF7;
    localparam RAM_BANK_SELECT_ADDR = 16'hFFF8;
    localparam CONFIG_MODE_ADDR = 16'hFFF9;
    
    localparam PROC_RESERVED_START = 16'hFFFA;
    localparam PROC_RESERVED_END = 16'hFFFF;
    
    reg [2:0] config_mode; // MMU configuration mode register (always visible at CONFIG_MODE_ADDR)
    // 000b, presets configuration mode, I/O not mapped in
    // 001b, range configuration mode, I/O not mapped in
    // 010b, advanced configuration mode, I/O not mapped in
    // 011b, I/O table configuration mode, I/O not mapped in
    
    // 100b, presets configuration mode, I/O is mapped in (default)
    // 101b, range configuration mode, I/O is mapped in
    // 110b, advanced configuration mode, I/O is mapped in
    // 111b, I/O table configuration mode, I/O is mapped in
    
    // Bit definitions for page configurations in page config table
    // Bit 0, RAM bank/chip select bit 0
    // Bit 1, RAM bank/chip select bit 1
    // Bit 2, RAM bank/chip select bit 2
    // Bit 3, RAM bank/chip select bit 3
    
    // Bit 4, ROM bank/chip select bit 0
    // Bit 5, ROM bank/chip select bit 1
    
    // Bit 6, RAM or ROM page (1 for RAM, 0 for ROM)
    
    // Bit 7, is page in shared memory (1 for true, 0 for false)
    
    reg [1:0] resb_counter; // Counter to track the number of cycles resetb (RESB) is low
    reg internal_reset; // Internal reset signal to be sent to sub-modules
    
// Sub-Module Instatiation **************************************************************
// **************************************************************************************
    
    reg root_PageConfigIndexWriteEnable; // Root module's register to drive the Page Configuration Table write enable signal
    
    wire page_write_enable;
    reg [8:0] page_table_index; // This is 9 bits because the table internally has 261 indexes. This is used by other MMU modules
    wire [7:0] page_table_data_bus;
    wire page_high_speed_write;
    wire [71:0] page_high_speed_bus;
    assign page_table_data_bus = (root_PageConfigIndexWriteEnable) ? data_bus : 8'bz;
    PageConfigTable pageConfigTable 
    (
        .clock(clock),
        .internal_reset(internal_reset),
        
        .write_enable(page_write_enable),
        .index_select(page_table_index),
        
        .data_bus(page_table_data_bus),
        
        .high_speed_write(page_high_speed_write),
        .high_speed_bus(page_high_speed_bus)
    );
    
    reg root_TranslationTableWriteEnable; // Root module's register to drive the Translation Table write enable signal
    
    wire translation_write_enable;
    wire [15:0] translation_table_word_bus;
    wire [7:0] translation_table_byte_bus;
    reg [7:0] translation_table_index;
    reg translation_byte_select;
    assign translation_table_byte_bus = (root_TranslationTableWriteEnable) ? data_bus : 8'bz; // Drive translation table byte bus from data_bus when processor is writing to the translation table
    TranslationTable translationTable
    (
        .clock(clock),
        .internal_reset(internal_reset),
        
        .write_enable(translation_write_enable),
        .index_select(translation_table_index),
        .byte_select(translation_byte_select),
        
        .word_data_bus(translation_table_word_bus),
        .byte_data_bus(translation_table_byte_bus)
    );
    
    localparam IO_BLOCK_SIZE = 8;
    localparam IO_INDEX_SELECT_BITS = $clog2(256 / IO_BLOCK_SIZE);
    localparam IO_MAP_REG_SIZE = $clog2(PERI_HIGH_BIT + 1);
    localparam IO_MAP_ADDR_START = 16'h0000;
    localparam IO_MAP_ADDR_END = 16'h0000 + (256 / IO_BLOCK_SIZE);
    
    reg iomap_write_enable;
    reg [IO_INDEX_SELECT_BITS - 1:0] iomap_index;
    wire [IO_MAP_REG_SIZE - 1:0] iomap_data_bus;
    assign iomap_data_bus = (iomap_write_enable) ? data_bus[IO_MAP_REG_SIZE - 1:0] : {IO_MAP_REG_SIZE{1'bz}}; // Drive IO Map data bus from data_bus when processor is writing to the IO Map
    IOMapTable 
    #(
        .BLOCK_SIZE(IO_BLOCK_SIZE),
        .INDEX_SELECT_BITS(IO_INDEX_SELECT_BITS),
        .REG_SIZE(IO_MAP_REG_SIZE),
        
        .VIA_PAGE_START(VIA_ADDR_START[7:0]),
        .VIA_PAGE_END(VIA_ADDR_END[7:0]),
        .VIA_PERI_ID(0),
        
        .ACIA_PAGE_START(ACIA_ADDR_START[7:0]),
        .ACIA_PAGE_END(ACIA_ADDR_END[7:0]),
        .ACIA_PERI_ID(1)
    )
    ioMapTable
    (   
        .clock(clock), 
        .internal_reset(internal_reset),
        
        .write_enable(iomap_write_enable),
        .index_select(iomap_index),
        
        .data_bus(iomap_data_bus)
    );
    
    reg ram_write_enable; // Enable signal for the ram bank select register
    wire [3:0] ram_select_data; // Net to transfer data to and from ram bank select register
    reg rom_write_enable; // Enable signal for the rom bank select register
    wire [1:0] rom_select_data; // Net to transfer data to and from rom bank select register
    assign ram_select_data = (ram_write_enable) ? data_bus[3:0] : 4'bz; // Drive RAM bank selection bus from data_bus when processor is writing to ram bank selection register
    assign rom_select_data = (rom_write_enable) ? data_bus[1:0] : 2'bz; // Drive ROM bank selection bus from data_bus when processor is writing to rom bank selection register
    BankSelector #(.RAM_BANKS(RAM_HIGH_BIT + 1), .ROM_BANKS(ROM_HIGH_BIT + 1)) bankSelector
    (
        .clock(clock),
        .internal_reset(internal_reset),
        
        .ram_write_enable(ram_write_enable),
        .rom_write_enable(rom_write_enable),
        
        .ram_data_bus(ram_select_data),
        .rom_data_bus(rom_select_data)
    );
    
    wire preset_config_ready; // Line to cary presets configuration controller internal ready register
    reg preset_write_enable; // Enable signal for the preset selection register
    wire [7:0] preset_select_data; // Net to transfer data to and from preset selection register
    wire [8:0] preset_PageConfigIndexSelect; // Net to carry Presets Configuration Controller page config table index select signal
    wire preset_PageConfigHighSpeedWriteEnable; // Signal high speed write enable of page config table from Presets Configuration Controller
    //wire [71:0] preset_PageConfigHighSpeedBus; // Net for connecting Presets Configuration Controller to Page Config Table high speed bus
    assign preset_select_data = (preset_write_enable) ? data_bus : 8'bz; // Drive preset selection bus from data_bus when processor is writing to preset selection register
    PresetsConfigController presetsConfigController
    (
        .clock(clock),
        .internal_reset(internal_reset),
        
        .proc_ready(preset_config_ready),
        
        .write_enable(preset_write_enable),
        
        .data_bus(preset_select_data),
        
        .page_high_speed_we(preset_PageConfigHighSpeedWriteEnable),
        .page_index(preset_PageConfigIndexSelect),
        .page_high_speed_bus(page_high_speed_bus)
    );
    
    wire range_config_ready; // Line to cary range configuration controller internal ready register
    reg range_start_write_enable; // Enable signal for range configuration range start register
    reg range_end_write_enable; // Enable signal for range configuration range end register
    reg range_config_write_enable; // Enable signal for range configuration range config register
    wire [7:0] range_start_data_bus; // Net to transfer data to and from range configuration range start register
    wire [7:0] range_end_data_bus; // Net to transfer data to and from range configuration range end register
    wire [7:0] range_config_data_bus; // Net to transfer data to and from range configuration range config register
    wire [8:0] range_PageConfigIndexSelect; // Net to transfer Range Config Controller page config table index selection
    wire range_PageConfigIndexWriteEnable; // Signal write enable of page config table index from Range Configuration Controller
    //wire [7:0] range_PageConfigIndexDataBus; // Net for connecting Range Configuration Controller to Page Configuration Table index data bus
    wire range_PageConfigHighSpeedWriteEnable; // Signal high speed write enable of page config table from Range Configuration Controller
    //wire [71:0] range_PageConfigHighSpeedDataBus; // Net for connecting Range Configuration Controller to Page Configuration Table high speed data bus
    assign range_start_data_bus = (range_start_write_enable) ? data_bus : 8'bz; // Drive range configuration range start bus from data_bus when processor is writing to the range start register
    assign range_end_data_bus = (range_end_write_enable) ? data_bus : 8'bz; // Drive range configuration range end bus from data_bus when processor is writing to the range end register
    assign range_config_data_bus = (range_config_write_enable) ? data_bus : 8'bz; // Drive range configuration range config bus from data_bus when processor is writing to the range config register
    RangeConfigController rangeConfigController
    (
        .clock(clock),
        .internal_reset(internal_reset),
        
        .proc_ready(range_config_ready),
        
        .start_write_enable(range_start_write_enable),
        .end_write_enable(range_end_write_enable),
        .config_write_enable(range_config_write_enable),
        
        .start_data_bus(range_start_data_bus),
        .end_data_bus(range_end_data_bus),
        .config_data_bus(range_config_data_bus),
        
        .page_index(range_PageConfigIndexSelect),
        
        .page_index_write(range_PageConfigIndexWriteEnable),
        .page_index_bus(page_table_data_bus),
        
        .page_high_speed_we(range_PageConfigHighSpeedWriteEnable),
        .page_high_speed_bus(page_high_speed_bus)
    );
    
    reg translate_enable;
    wire [7:0] addressTrans_PageConfigIndexSelect; // Net to transfer Address Translation and Chip Enable page config table index selection
    wire [7:0] addressTrans_TranslationTableIndexSelect; // Net to transfer Address Translation and Chip Enable translation table index selection
    wire [IO_INDEX_SELECT_BITS - 1:0] addressTrans_IOMapIndexSelect; // Net to transfer Address Translation and Chip Enable io map index selection
    AddressTransChipEnable
    #(
        .IO_SELECT_BITS(IO_INDEX_SELECT_BITS),
        .IO_REG_SIZE(IO_MAP_REG_SIZE),
        .IO_PAGE_NUM(IO_PAGE_NUM),
        .IO_MAP_BLOCK_SIZE(IO_BLOCK_SIZE),
        
        .RAM_HIGH_BIT(RAM_HIGH_BIT),
        .ROM_HIGH_BIT(ROM_HIGH_BIT),
        .PERI_HIGH_BIT(PERI_HIGH_BIT)
    )
    addrTransChipEnable
    (
        .clock(clock),
        .internal_reset(internal_reset),
        
        .translate_enable(translate_enable),
        
        .io_enable(config_mode[2]),
        
        .page_table_index(addressTrans_PageConfigIndexSelect),
        .page_table_data_bus(page_table_data_bus),
        
        .translation_table_index(addressTrans_TranslationTableIndexSelect),
        .translation_table_data_bus(translation_table_word_bus),
        
        .io_map_index_select(addressTrans_IOMapIndexSelect),
        .io_map_data_bus(iomap_data_bus),
        
        .default_ram_data(ram_select_data),
        .default_rom_data(rom_select_data),
        
        .rwb(rwb),
        .proc_address_bus(proc_address_bus),
        
        .sys_address_bus(sys_address_bus),
        
        .ram_chip_enable(ram_chip_enable),
        .rom_chip_enable(rom_chip_enable),
        .peri_chip_enable(peri_chip_enable)
    );
    
// End Section **************************************************************************

// Root Module Registers and Variables **************************************************
// **************************************************************************************
    

// **************************************************************************************

// Sub-Module control lines and interconnect ********************************************
// **************************************************************************************
    assign proc_ready = preset_config_ready & range_config_ready; // Drive the processor ready line with an and gate combining the ready signals from the halting sub-modules
    
    assign page_write_enable = root_PageConfigIndexWriteEnable | range_PageConfigIndexWriteEnable; // Drive the Page Configuration Table single index write enable line
    
    assign page_high_speed_write = preset_PageConfigHighSpeedWriteEnable | range_PageConfigHighSpeedWriteEnable; // Drive the Page Configuration Table high speed bus write enable line
    
    assign translation_write_enable = root_TranslationTableWriteEnable; // Drive the Translation Table write enable line
    
    always @(preset_PageConfigIndexSelect) begin // Detected a change in the Presets Configuration Controller page config table index select lines
        page_table_index <= preset_PageConfigIndexSelect;
    end
    always @(range_PageConfigIndexSelect) begin // Detected a change in the Range Configuration Controller page config table index select lines
        page_table_index <= range_PageConfigIndexSelect;
    end
    always @(addressTrans_PageConfigIndexSelect) begin // Detected a change in the Address Translation and Chip Enable page config table index select lines
        page_table_index <= addressTrans_PageConfigIndexSelect;
    end
    
    always @(addressTrans_TranslationTableIndexSelect) begin // Detected a change in the Address Translation and Chip Enable translation table index select lines
        translation_table_index <= addressTrans_TranslationTableIndexSelect;
    end
    
    always @(addressTrans_IOMapIndexSelect) begin // Detected a change in the Address Translation and Chip Enable IO Map index select lines
        iomap_index <= addressTrans_IOMapIndexSelect;
    end
    
// End Section **************************************************************************
    
// Root module functionality ************************************************************
// **************************************************************************************
    wire [15:0] adjusted_address = proc_address_bus - TRANSLATION_TABLE_START_ADDR;
    reg [7:0] data_out; // Internal register to drive data_bus when MMU is system driver (processor is reading from MMU)
    
    reg mmu_read; // Signify a read from mmu is detected. Used to determine when MMU drives data_bus
    reg [3:0] reg_read_selection; // Used to select what internal data bus should drive the system bus when MMU is being read from
    
    always @(*) begin
        case(reg_read_selection)
            4'd0: data_out <= {5'b0, config_mode}; // Output config mode value on data bus
            4'd1: data_out <= {4'b0, ram_select_data}; // Output the value in the default ram bank selection register
            4'd2: data_out <= {6'b0, rom_select_data}; // Output the value in the default rom bank selection register
            4'd3: data_out <= preset_select_data; // Output the value in the preset selection register
            4'd4: data_out <= range_start_data_bus; // Output the value in the range configuration range start register
            4'd5: data_out <= range_end_data_bus; // Output the value in the range configuration range end register
            4'd6: data_out <= range_config_data_bus; // Output the value in the range configuration range config register
            4'd7: data_out <= page_table_data_bus; // Output the value on the page configuration table index bus
            4'd8: data_out <= translation_table_byte_bus; // Output the value on the translation table byte bus
            4'd9: data_out <= {{8 - IO_MAP_REG_SIZE{1'b0}}, iomap_data_bus}; // Output the value the io map bus
        endcase
    end
    
    reg config_write_enable;
    always @(data_bus) begin
        if(config_write_enable && data_bus[2:0] !== 3'dz) begin
            config_mode <= data_bus[2:0]; // Assign the value on the data bus to the configuration mode register
        end
    end
    
    assign data_bus = (mmu_read) ? data_out : 8'bz; // When processor is reading from MMU drive the data bus
    
    always @(negedge resetb) begin
        resb_counter <= 2'b00;
    end
    
    always @(posedge clock) begin
        if(!resetb) begin
            if(resb_counter < 2'b10) begin
                resb_counter <= resb_counter + 1; // RESB is low, increment counter
            end
        end else if(resb_counter >= 2'b10) begin // resetb is positive and the reset counter is at 2
            internal_reset <= 1'b1; // Assert an internal reset signal
            resb_counter <= 2'b00; // On reset zero the resetb signal counter
            
            config_mode <= 3'b100; // On reset set the config mode to presets config mode
            
            root_PageConfigIndexWriteEnable <= 0; // On reset de-assert write enable for page table
            page_table_index <= 8'b0; // On reset initialize page table index selection to index 0
            
            root_TranslationTableWriteEnable <= 0; // On reset de-assert write enable for translation table
            translation_table_index <= 8'b0; // On reset initialize translation table index selection to index 0
            translation_byte_select <= 0; // On reset initialize the translation table index byte selection to lower byte (0 for low byte, 1 for high byte)
            
            iomap_write_enable <= 0;
            iomap_index <= 0;
            
            ram_write_enable <= 0; // On reset de-assert write enable for ram bank selection register
            rom_write_enable <= 0; // On reset de-assert wirte enable for rom bank selection register
            
            preset_write_enable <= 0; // On reset de-assert write enable for preset selection register
            
            range_start_write_enable <= 0; // On reset de-assert write enable for range configuration range start register
            range_end_write_enable <= 0; // On reset de-assert write enable for range configuration range end register
            range_config_write_enable <= 0; // On reset de-assert write enable for range configuration range config register
            
            translate_enable <= 0; // On reset de-assert MMU translate enable to disconnect the system address bus
            
            mmu_read <= 0; // On reset de-assert the processor MMU read signal so we dont drive the system data bus
            reg_read_selection <= 0; // On reset initialize the
            
            config_write_enable <= 0; // On reset de-assert the configuration mode register write enable signal
        end else begin // resetb is positive and the reset counter is not at 2
            internal_reset <= 1'b0; // De-assert the internal reset
            resb_counter <= 2'b00; // Zero the resetb signal counter
        end
    end
    
    always @(proc_address_bus, rwb) begin
        mmu_read <= 0; // De-assert an MMU read by default
        config_write_enable <= 0; // De-assert write enable of the configuration mode register
        root_PageConfigIndexWriteEnable <= 0; // De-assert page configuration write enable by default each cycle
        root_TranslationTableWriteEnable <= 0; // De-assert translation table write enable by default each cycle
        iomap_write_enable <= 0; // De-assert io map write enable by default each cycle
        ram_write_enable <= 0; // De-assert default ram bank select write enable by default each cycle
        rom_write_enable <= 0; // De-assert default rom bank select write enable by default each cycle
        preset_write_enable <= 0; // De-assert preset selection register write enable by default each cycle
        range_start_write_enable <= 0; // De-assert range configuration range start write enable by default each cycle
        range_end_write_enable <= 0; // De-assert range configuration range end write enable by default each cycle
        range_config_write_enable <= 0; // De-assert range configuration range config write enable by default each cycle
        translate_enable <= 0; // De-assert MMU translate by default each cycle. Disconnects the system address bus
        
        if(proc_ready) begin // We only want to run these if the processor isnt halted
            case(proc_address_bus)
                CONFIG_MODE_ADDR: begin
                    if(rwb) begin // Processor is reading
                        mmu_read <= 1; // Assert Processor <- MMU read
                        reg_read_selection <= 4'd0;
                    end else begin // Processor is writing
                        if(data_bus < 4'b1000) begin
                            config_write_enable <= 1; // Set write enable for the configuration mode register
                        end
                    end
                end
                
                RAM_BANK_SELECT_ADDR: begin
                    if(rwb) begin // Processor is reading
                        mmu_read <= 1; // Assert Processor <- MMU read
                        reg_read_selection <= 4'd1;
                    end else begin // Processor is writing
                        ram_write_enable <= 1; // Set write enable for the default ram bank selection register
                    end
                end
                
                ROM_BANK_SELECT_ADDR: begin
                    if(rwb) begin // Processor is reading
                        mmu_read <= 1; // Assert Processor <- MMU read
                        reg_read_selection <= 4'd2;
                    end else begin // Processor is writing
                        rom_write_enable <= 1; // Set write enable for the default rom bank selection register
                    end
                end
            
                default: begin
                    case(config_mode[1:0])
                        2'b00: begin // 00b, presets configuration mode
                            case(proc_address_bus)
                                PRESET_SELECT_ADDR: begin
                                    if(rwb) begin // Processor is reading
                                        mmu_read <= 1; // Assert Processor <- MMU read
                                        reg_read_selection <= 4'd3;
                                    end else begin // Processor is writing
                                        preset_write_enable <= 1; // Set write enable for the preset selection register
                                    end
                                end
                                
                                default: begin
                                    translate_enable <= 1; // Set the translate enable signal high to drive system address bus and chip enable lines
                                end
                            endcase
                        end
                        
                        2'b01: begin // 01b, range configuration mode
                            case(proc_address_bus)
                                RANGE_START_ADDR: begin // Processor is accessing the range configuration range start register
                                    if(rwb) begin // Processor is reading
                                        mmu_read <= 1; // Assert Processor <- MMU read
                                        reg_read_selection <= 4'd4;
                                    end else begin // Processor is writing
                                        range_start_write_enable <= 1; // Set write enable for the range configuration range start register
                                    end
                                end
                                
                                RANGE_END_ADDR: begin // Processor is accessing the range configuration range end register
                                    if(rwb) begin // Processor is reading
                                        mmu_read <= 1; // Assert Processor <- MMU read
                                        reg_read_selection <= 4'd5;
                                    end else begin // Processor is writing
                                        range_end_write_enable <= 1; // Set write enable for the range configuration range end register
                                    end
                                end
                                
                                RANGE_CONFIG_ADDR: begin // Processor is accessing the range configuration range config register
                                    if(rwb) begin // Processor is reading
                                        mmu_read <= 1; // Assert Processor <- MMU read
                                        reg_read_selection <= 4'd6;
                                    end else begin // Processor is writing
                                        range_config_write_enable <= 1; // Set write enable for the range configuration range config register
                                    end
                                end
                                
                                default: begin
                                    translate_enable <= 1; // Set the translate enable signal high to drive system address bus and chip enable lines
                                end
                            endcase
                        end
                        
                        2'b10: begin // 10b, advanced configuration mode
                            if((proc_address_bus >= PAGE_TABLE_START_ADDR) && (proc_address_bus <= PAGE_TABLE_END_ADDR)) begin // Processor is accessing the page configuration table
                                page_table_index <= proc_address_bus[7:0]; // Index into the page configuration table using the low byte of processor address bus
                                if(rwb) begin // Processor is reading
                                    mmu_read <= 1; // Assert Processor <- MMU read
                                    reg_read_selection <= 4'd7;
                                end else begin // Processor is writing
                                    root_PageConfigIndexWriteEnable <= 1; // Set write enable for the page configuration table
                                end
                            end else if((proc_address_bus >= TRANSLATION_TABLE_START_ADDR) && (proc_address_bus <= TRANSLATION_TABLE_END_ADDR)) begin // Processor is accessing the translation table
                                translation_table_index <= adjusted_address[8:1]; // Read bits 8 though 1 to get index
                                translation_byte_select <= ~adjusted_address[0]; // High byte of translation word if address bit 0 is 0
                                if(rwb) begin // Processor is reading
                                    mmu_read <= 1;
                                    reg_read_selection <= 4'd8;
                                end else begin // Processor is writing
                                    root_TranslationTableWriteEnable <= 1; // Set the write enable for the translation table
                                end
                            end else begin // Processor is not accessing either the page configuration table or translation table
                                translate_enable <= 1; // Set the translate enable signal high to drive system address bus and chip enable lines
                            end
                        end
                        
                        2'b11: begin // 11b, IO map configuration mode
                            if((proc_address_bus >= IO_MAP_TABLE_START_ADDR) && (proc_address_bus <= IO_MAP_TABLE_END_ADDR)) begin // Processor is accessing the io map table
                                iomap_index <= proc_address_bus[7:0]; // Index into the io map table using the low byte of processor address bus
                                if(rwb) begin // Processor is reading
                                    mmu_read <= 1; // Assert Processor <- MMU read
                                    reg_read_selection <= 4'd9;
                                end else begin // Processor is writing
                                    iomap_write_enable <= 1; // Set the write enable for the io map table
                                end
                            end
                        end
                    endcase
                end
            endcase
        end
    end
    
// End Section **************************************************************************
    
endmodule
