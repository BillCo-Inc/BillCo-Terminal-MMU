`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: BillCo Inc.
// Engineer: Andrew Todd
// 
// Create Date: 06/13/2024 03:35:51 PM
// Design Name: 
// Module Name: IOMapTable
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: Module handles the I/O map table that mapps 8 address blocks of memory to certain peripheral chips
// 
// Dependencies:
// 
// Revision: V-1.0.0.0
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module IOMapTable
#(
    parameter BLOCK_SIZE = 8'd8, // The number of addresses per block
    parameter INDEX_SELECT_BITS = 8'd5, // The number of bits for the index select net. Determined by the number needed to address the indices of the table
    parameter REG_SIZE = 3'd1, // The number of bits needed for the tables registers. Determined by the number needed to represent the total number of peripheral chip enable lines
    
    parameter VIA_PAGE_START = 8'hE0, // Address in the page where we start mapping the VIA
    parameter VIA_PAGE_END = 8'hEF, // Address in the page where we end mapping of the VIA
    parameter VIA_PERI_ID = 0, // The peripheral device id for the VIA. Corresponds to the peripheral chip enable lines
    
    parameter ACIA_PAGE_START = 8'hF0, // Address in the page where we start mapping the ACIA
    parameter ACIA_PAGE_END = 8'hF3, // Address in the page where we end mapping of the ACIA
    parameter ACIA_PERI_ID = 1 // The peripheral device id for the ACIA. Corresponds to the peripheral chip enable lines
)
(   input wire clock, 
    input wire internal_reset, // High initiates reset
    
    input wire write_enable, // Enable signal for writing to the table
    input wire [INDEX_SELECT_BITS - 1:0] index_select, // Used to index into the table
    
    inout wire [REG_SIZE - 1:0] data_bus // Internal data bus, connected to system bus in root when necessary
);

    // Calculate the number of indices in the table      
    initial begin // assertions
        if(BLOCK_SIZE % 4 != 0) begin
            $display("Assertion Failed in %m. BLOCK_SIZE must be a multiple of 4");
            $finish;
        end
    end
    localparam TABLE_INDICES = 256 / BLOCK_SIZE;
    
    localparam VIA_BLOCK_START = VIA_PAGE_START / BLOCK_SIZE;
    localparam VIA_BLOCK_END = VIA_PAGE_END / BLOCK_SIZE;
    
    localparam ACIA_BLOCK_START = ACIA_PAGE_START / BLOCK_SIZE;
    localparam ACIA_BLOCK_END = ACIA_PAGE_END / BLOCK_SIZE;
    
    // I/O map table to be stored in BRAM
    (* ram_style = "block" *) reg [REG_SIZE - 1:0] io_map_table [0:TABLE_INDICES - 1];
    
    reg[8:0] i;
    always @(posedge internal_reset) begin
        for(i = 0; i < TABLE_INDICES; i = i + 1) begin
            io_map_table[i] <= {REG_SIZE{1'b0}};
        end
        
        for(i = VIA_BLOCK_START; i < VIA_BLOCK_END + 1; i = i + 1) begin
            io_map_table[i] <= VIA_PERI_ID;
        end
        
        for(i = ACIA_BLOCK_START; i < ACIA_BLOCK_END + 1; i = i + 1) begin
            io_map_table[i] <= ACIA_PERI_ID;
        end
    end
    
    assign data_bus = write_enable ? {REG_SIZE{1'bz}} : io_map_table[index_select];
    always @(data_bus) begin
        if(write_enable && data_bus !== {REG_SIZE{1'bz}}) begin // Writing to the configuration table
            io_map_table[index_select] <= data_bus; // Write the value of the data bus to selected page config index
        end
    end

endmodule
