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
    
    wire proc_resetb; // Wire connecting the Processor's reset pin to the MMU's driver pin. This allows the MMU to delay the reset signal to the Processor until the MMU is initialized
    wire proc_ready; // Wire connecting the Processor's ready pin to the MMU's driver pin. Used to halt the processor
    wire proc_we; // Wire connecting the Processor's RWB pin to the MMU's incoming rwb signal pin
    reg [15:0] proc_address_bus; // Net connecting the Processor's address bus to the MMU's incoming address bus pins
    
    wire [15:0] sys_address_bus; // Net connecting the MMU's outgoing address bus to the system. System side address sensitive modules are connected
    
    wire [7:0] data_bus; // Net connecting the MMU's outgoing data bus to the system. System side data sensitive modules are connected
    wire [7:0] proc_data_in;
    wire [7:0] proc_data_out;
    
    wire [15:0] ram_chip_enable; // Net connecting the MMU's outgoing ram chip enable pins to the system
    wire [3:0] rom_chip_enable; // Net connecting the MMU's outgoing rom chip enable pins to the system
    wire [31:0] peri_chip_enable; // Net connecting the MMU's outgoing peripheral chip enable pins to the system
    
    initial begin
        clock = 1;
        resetb = 1'b1; // Start with reset signal high (active low)
        
        #CLOCK_PERIOD_NS; // Wait for one clock cycle
        
        resetb = 1'b0; // Set resetb to low. Signal a reset to the system
        
        #CLOCK_PERIOD_NS; // Wait two clock cycles
        #CLOCK_PERIOD_NS;
        #CLOCK_PERIOD_NS;
        
        resetb = 1'b1; // Set resetb back to high. Reset signal should now have been receaved and activated reset in Processor and MMU
        
        #(CLOCK_PERIOD_NS * 424);
        $finish;
    end
    
    always #(CLOCK_PERIOD_NS / 2) clock = ~clock; // Generate clock signal
    
    /*Processor_tb #(.CLOCK_FREQUENCY_KHZ(CLOCK_FREQUENCY_KHZ)) processor
    (
        .clock(clock),
        .resetb(resetb),
        .ready(proc_ready),
        .rwb(proc_rwb),
        .address_bus(proc_address_bus),
        .data_bus(data_bus)
    );*/
    
    wire proc_sync;
    wire [15:0] proc_address;
    reg proc_intr_req = 0;
    reg proc_NMintr_req = 0;
    reg proc_debug = 0;
    always @(posedge clock)
        if(proc_ready)
            proc_address_bus <= proc_address;
       
    assign data_bus = proc_we ? proc_data_out : 8'hz;
    assign proc_data_in = data_bus;
    cpu W65C02 (
        .clk(clock),
        .RST(!proc_resetb),
        .AD(proc_address),
        .sync(proc_sync),
        .DI(proc_data_in),
        .DO(proc_data_out),
        .WE(proc_we),
        .IRQ(proc_intr_req),
        .NMI(proc_NMintr_req),
        .RDY(proc_ready),
        .debug(proc_debug)
    );
    
    MemoryManagementUnit mmu (
        .clock(clock),
        .resetb(resetb),
        .proc_resetb(proc_resetb),
        .proc_ready(proc_ready),
        .rwb(!proc_we),
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
        .rwb(!proc_we),
        .address_bus(sys_address_bus),
        .data_bus(data_bus)
    );
    
    RAM_tb #() ram_00 
    (
        .clock(clock),
        .chip_enable(ram_chip_enable[1]),
        .rwb(!proc_we),
        .address_bus(sys_address_bus),
        .data_bus(data_bus)    
    );
    
    ROM_tb #(.MEM_FILE("MMUSystemsCheck_01.mem")) rom_01
    (
        .clock(clock),
        .chip_enable(rom_chip_enable[1]),
        .rwb(!proc_we),
        .address_bus(sys_address_bus),
        .data_bus(data_bus)
    );
endmodule
