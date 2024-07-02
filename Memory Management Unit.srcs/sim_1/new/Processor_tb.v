`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/26/2024 04:11:09 PM
// Design Name: 
// Module Name: Processor Testbench
// Project Name: Memory Management Unit
// Target Devices: XC7S6, XC7S25 (prototyping board)
// Tool Versions: 
// Description: Test Bench for simulation of the Processor in the broader system
// 
// Dependencies:
// 
// Revision: V-1.0.0.0
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Processor_tb (
    input wire clock,
    input wire resetb,
    input wire ready, // Active high, low halts processor
    output reg rwb, // 1 for read, 0 for write
    output reg [15:0] address_bus,
    inout wire [7:0] data_bus
    );

    parameter CLOCK_FREQUENCY_KHZ = 14000; // Default clock frequency in KHz. Overridden when instantiated
    parameter CLOCK_PERIOD_NS = 1000000 / CLOCK_FREQUENCY_KHZ; // Clock period in nanoseconds
    
    localparam tADS = 30; // Address Setup Time 30 ns
    localparam tMDS = 25; // Write Data Delay Time 25 ns
    localparam tDHW = 10; // Write data hold time 10 ns
    localparam tDSR = 10; // Read Data Setup Time 10 ns

    reg [1:0] resb_counter; // Counter to track the number of cycles resetb (RESB) is low
    
    reg [15:0] prog_counter; // Program counter register
    reg [7:0] read_data_reg; // Register for data to be read
    reg [7:0] write_data_reg; // Register for data to be written
    reg [7:0] temp_write_data;
    reg temp_rwb;
    
    reg [4:0] state; // Register to track state of processor
    
    reg [15:0] internal_address; // Register to hold the addrsss to be put onto the address lines on the next negative edge of clock
    reg data_bus_drive; // Control signal to drive the data bus
    
    initial begin
        prog_counter = 16'hEEEE; // Initialize Program Counter to something specific that isnt significant to reserved addresses or reset sequence
        read_data_reg = 8'b0; // Initialize the data register to 0
        write_data_reg = 8'b0;
        state = 5'b0000; // Initialize state to 0
        resb_counter = 2'b00; // Initialize the reset sequence counter
    end

    always @(posedge clock) begin
        if (!resetb) begin
            if (resb_counter < 2'b10) begin
                resb_counter <= resb_counter + 1; // RESB is low, increment counter
            end 
        end else if (resb_counter >= 2'b10) begin // resetb is positive and the reset counter is at 2
            resb_counter <= 2'b00; // On reset, zero the resetb signal counter
            state <= 4'b0001; // Start the reset sequence. Set state to 1
            rwb <= 1'b1; // Set rwb to signal read
            temp_rwb <= 1'b1;
            data_bus_drive <= 0;
        end else begin //resetb is positive and the reset counter is not at 2
            resb_counter <= 2'b00; // Zero the resetb signal counter
        end
    end
    
    assign data_bus = (data_bus_drive) ? write_data_reg : 8'bz;
    
    always @(negedge clock) begin
        if(ready & resetb) begin
            #tADS; // Delay to simulate Address Setup Time
            address_bus <= internal_address;
            rwb <= temp_rwb;
        end
    end
    
    always @(negedge clock) begin
        #tDHW; // Delay to simulate Write Data Hold Time
        data_bus_drive <= 0;
    end
    
    always @(posedge clock) begin
        if(ready && resetb) begin
            if(rwb) begin // Read from data bus
                #((CLOCK_PERIOD_NS / 2) - tDSR); // Delay to simulate the time the memory chip has to get the data lines stabilized
                read_data_reg <= data_bus;
            end else begin // Write to data bus
                #tMDS; // Delay to simulate the Write Data Delay Time
                write_data_reg <= temp_write_data;
                data_bus_drive <= 1;
            end
        end
    end
    
    always @(posedge clock) begin
        if(resetb && ready) begin
            case (state)
                4'b0001: begin // State 1: Reset internal hardware, read from FFFC
                    internal_address <= 16'hFFFC; // Read program counter low byte
                    state <= 4'b0010;
                end
                4'b0010: begin // State 2: Read from FFFD
                    internal_address <= 16'hFFFD; // Read program counter high byte
                    state <= 4'b0011;
                    #((CLOCK_PERIOD_NS / 2) - tDSR);
                    prog_counter[7:0] <= data_bus; // Store the low byte of the program counter
                    
                    #tDSR;
                    assert(data_bus == 8'haa) else $fatal("Data bus should be aa read from the BIOS ROM chip");
                end
                4'b0011: begin // State 3
                    state <= 4'b0100;
                    #((CLOCK_PERIOD_NS / 2) - tDSR);
                    prog_counter <= {data_bus, prog_counter[7:0]};
                    
                    #tDSR;
                    assert(data_bus == 8'hbb) else $fatal("Data bus should be bb read from the BIO ROM chip");
                end
                4'b0100: begin // State 4: Set program counter
                    #(4*CLOCK_PERIOD_NS); // Wait for 4 clock cycles to finish 7 cycle reset sim
                    internal_address <= prog_counter; // Access the address obtained from the reset vector at FFFC FFFD
                    state <= 4'b0101;
                end
                4'b0101: begin // State 5
                    internal_address <= 16'hFFF7; // Read from the rom bank selection register
                    state <= 4'b0110;
                    
                    #tDSR;
                    assert(data_bus == 8'hcc) else $fatal("Data bus should be cc read from default RAM bank 0");
                end
                4'b0110: begin // State 6
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF7;
                    temp_write_data <= 8'd1; // Select bank 1
                    state <= 4'b0111;
                    
                    #tDSR;
                    assert(data_bus == 8'h00) else $fatal("Data bus should be initialized default ROM bank selection of 0");
                end
                4'b0111: begin // State 7
                    temp_rwb <= 1'b1; // Set processor back to read mode
                    internal_address <= 16'hFFF7; // Read back the register
                    state <= 4'b1000;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'd1) else $fatal("Data bus should be driven by processor and be 1");
                end
                4'b1000: begin // State 8
                    internal_address <= 16'hFEE0; // Access VIA
                    state <= 4'b1001;
                    
                    #tDSR;
                    assert(data_bus == 8'd1) else $fatal("Data bus should be 1, driven by default ROM bank selection now 1");
                end
                4'b1001: begin // State 9
                    internal_address <= 16'hFEF0; // Access AIA
                    state <= 4'b1010;
                    
                    #tDSR;
                    assert(data_bus === 8'bz) else $fatal("Processor accessing IO, not connected now so data bus should be disconnected");
                end
                4'b1010: begin // State 10
                    internal_address <= 16'hFFFD; // Read program counter high byte
                    state <= 4'b1011;
                    
                    #tDSR;
                    assert(data_bus === 8'bz) else $fatal("Processor accessing IO, not connected now so data bus should be disconnected");
                end
                4'b1011: begin // State 11
                    internal_address <= 16'hFFF8; // Read default RAM bank selection
                    state <= 4'b1100;
                    
                    #tDSR;
                    assert(data_bus == 8'hdd) else $fatal("Data bus should be dd, driven by default ROM bank now bank 1");
                end
                4'b1100: begin // State 12
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF8;
                    temp_write_data <= 8'd1; // Select bank 1
                    state <= 4'b1101;
                    
                    #tDSR;
                    assert(data_bus == 8'h00) else $fatal("Data bus should be default RAM bank selection, 0");
                end
                4'b1101: begin // State 13
                    temp_rwb <= 1'b1; // Set processor back to read mode
                    internal_address <= 16'hFFF8;
                    state <= 4'b1110;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'd1) else $fatal("Data bus should be 1 driven by processor, the new default RAM bank selection");
                end
                4'b1110: begin // state 14
                    internal_address <= 16'hFFF9; // Read configuration mode
                    state <= 4'b1111;
                    
                    #tDSR;
                    assert(data_bus == 8'd1) else $fatal("Data bus should be 1 driven by MMU. The now default RAM bank selection");
                end
                4'b1111: begin // state 15
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF9; // Access the MMU configuration mode register
                    temp_write_data <= 8'b0000_0101; // Select ranged config mode with IO mapped in
                    state <= 5'b10000;
                    
                    #tDSR;
                    assert(data_bus == 8'b0000_0100) else $fatal("Data bus should be 100, the default configuration state of the MMU");
                end
                5'b10000: begin // state 16
                    temp_rwb <= 1'b1; // Set processor back to read mode
                    internal_address <= 16'hFFF9;
                    state <= 5'b10001;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'b0000_0101) else $fatal("Data bus should be 101, driven by processor to write");
                end
                5'b10001: begin // state 17
                    
                    state <= 5'b10010;
                    
                    #tDSR;
                    assert(data_bus == 8'b0000_0101) else $fatal("Data bus should be 101, drven by MMU. The new configuratio mode selection");
                end
                5'b10010: begin // state 18
                    $finish;
                end
            endcase
        end
    end
endmodule
