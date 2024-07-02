`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 05/25/2024 03:34:00 AM
// Design Name: 
// Module Name: MemoryManagementUnit Testbench
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: Test Bench for simulation of the MMU
// 
// Dependencies: MemoryManagementUnit.v, BankSelector.v
// 
// Revision: V-1.0.0.0
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module MMU_tb;
    parameter CLOCK_FREQUENCY_KHZ = 14000; // Clock frequency in KHz
    parameter CLOCK_PERIOD_NS = 1000000 / CLOCK_FREQUENCY_KHZ; // Clock period in nanoseconds
    
    reg clock; // System clock that feeds the processor, MMU, and other system clock driven modules
    reg resetb; // External reset signal wire that connects to all reset sensitive modules on the system
    
    wire proc_ready; // Wire connecting the Processor's ready pin to the MMU's driver pin. Used to halt the processor
    wire proc_rwb; // Wire connecting the Processor's RWB pin to the MMU's incoming rwb signal pin
    wire [15:0] proc_address_bus; // Net connecting the Processor's address bus to the MMU's incoming address bus pins
    
    wire [15:0] sys_address_bus; // Net connecting the MMU's outgoing address bus to the system. System side address sensitive modules are connected
    
    wire [7:0] data_bus; // Net connecting the MMU's outgoing data bus to the system. System side data sensitive modules are connected
    
    wire [3:0] ram_chip_enable; // Net connecting the MMU's outgoing ram chip enable pins to the system
    wire [3:0] rom_chip_enable; // Net connecting the MMU's outgoing rom chip enable pins to the system
    wire [1:0] peri_chip_enable; // Net connecting the MMU's outgoing peripheral chip enable pins to the system
    
    initial begin
        clock = 0;
        resetb = 1'b1; // Start with reset signal high (active low)
        
        #CLOCK_PERIOD_NS; // Wait for one clock cycle
        
        resetb = 1'b0; // Set resetb to low. Signal a reset to the system
        
        #CLOCK_PERIOD_NS; // Wait two clock cycles
        #CLOCK_PERIOD_NS;
        
        resetb = 1'b1; // Set resetb back to high. Reset signal should now have been receaved and activated reset in Processor and MMU
    end
    
    always #(CLOCK_PERIOD_NS / 2) clock = ~clock; // Generate clock signal
    
    Processor_tb #(.CLOCK_FREQUENCY_KHZ(CLOCK_FREQUENCY_KHZ)) processor
    (
        .clock(clock),
        .resetb(resetb),
        .ready(proc_ready),
        .rwb(proc_rwb),
        .address_bus(proc_address_bus),
        .data_bus(data_bus)
    );
    
    MemoryManagementUnit mmu (
        .clock(clock),
        .resetb(resetb),
        .proc_ready(proc_ready),
        .rwb(proc_rwb),
        .proc_address_bus(proc_address_bus),
        .sys_address_bus(sys_address_bus),
        .data_bus(data_bus),
        .ram_chip_enable(ram_chip_enable),
        .rom_chip_enable(rom_chip_enable),
        .peri_chip_enable(peri_chip_enable)
    );
    
    BIOSROM_tb bios (
        .clock(clock),
        .chip_enable(rom_chip_enable[0]),
        .rwb(proc_rwb),
        .address_bus(sys_address_bus),
        .data_bus(data_bus)
    );
    
    RAM_tb #(.ASSIGNED_ADDRESS(16'hbbaa), .ADDRESS_VALUE(8'hcc)) ram_00 
    (
        .clock(clock),
        .chip_enable(ram_chip_enable[0]),
        .rwb(proc_rwb),
        .address_bus(sys_address_bus),
        .data_bus(data_bus)    
    );
    
    ROM_tb #(.ASSIGNED_ADDRESS(16'hfffd), .ADDRESS_VALUE(8'hdd)) rom_01
    (
        .clock(clock),
        .chip_enable(rom_chip_enable[1]),
        .rwb(proc_rwb),
        .address_bus(sys_address_bus),
        .data_bus(data_bus)
    );
endmodule
