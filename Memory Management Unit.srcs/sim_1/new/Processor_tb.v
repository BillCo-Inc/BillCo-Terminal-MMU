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
    
    reg [15:0] state; // Register to track state of processor
    
    reg [15:0] internal_address; // Register to hold the addrsss to be put onto the address lines on the next negative edge of clock
    reg data_bus_drive; // Control signal to drive the data bus
    
    reg internal_ready;
    reg rollback_state;
    
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
    
    always @(negedge clock) begin
        if(ready == 0) begin
            internal_ready <= 0;
            if(!rollback_state) begin
                state <= state - 1;
                rollback_state <= 1;
            end
        end else begin
            internal_ready <= 1;
            rollback_state <= 0;
        end
    end
    
    assign data_bus = (data_bus_drive) ? write_data_reg : 8'bz;
    
    always @(negedge clock) begin
        if(internal_ready && resetb) begin
            #tADS; // Delay to simulate Address Setup Time
            address_bus <= internal_address;
            rwb <= temp_rwb;
        end
    end
    
    always @(negedge clock) begin
        if(internal_ready && resetb) begin
            #tDHW; // Delay to simulate Write Data Hold Time
            data_bus_drive <= 0;
        end
    end
    
    always @(posedge clock) begin
        if(internal_ready && resetb) begin
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
        if(internal_ready && resetb) begin
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
                    assert(data_bus == 8'hbb) else $fatal("Data bus should be bb read from the BIOS ROM chip");
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
                    internal_address <= 16'hFEF0; // Access ACIA
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
                    internal_address <= 16'hFFF6; // Read the current preset configuration (should be 12 hex)
                    state <= 4'b1111;
                    
                    #tDSR;
                    assert(data_bus == 8'd1) else $fatal("Data bus should be 1 driven by MMU. The now default RAM bank selection");
                end
                4'b1111: begin // state 15
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF6; // Write to the presets configuration register
                    temp_write_data <= 8'h21; // Set MMU to preset number 11 (21 hex)
                    state <= 5'b10000;
                    
                    #tDSR;
                    assert(data_bus == 8'h12) else $fatal("Data bus should be hex 12, the default presets configuration mode of the MMU");
                end
                5'b10000: begin // state 16
                    temp_rwb <= 1'b1; // Set processor back to read mode
                    internal_address <= 16'hFFF6;
                    state <= 5'b10001;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'h21) else $fatal("Data bus should be hex 21, driven by the processor to write to presets configuration register");
                end
                5'b10001: begin // state 17
                    internal_address <= 16'hFFF9; // Read configuration mode
                    state <= 5'b10010;
                    
                    #tDSR;
                    assert(data_bus == 8'h21) else $fatal("Data bus should be hex 21, driven by the MMU. The new presets configuration mode");
                end
                5'b10010: begin // state 18
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF9; // Access the MMU configuration mode register
                    temp_write_data <= 8'b0000_0101; // Select ranged config mode with IO mapped in
                    state <= 5'b10011;
                    
                    #tDSR;
                    assert(data_bus == 8'b0000_0100) else $fatal("Data bus should be 100, the default configuration state of the MMU");
                end
                5'b10011: begin // state 19
                    temp_rwb <= 1'b1; // Set processor back to read mode
                    internal_address <= 16'hFFF9;
                    state <= 5'b10100;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'b0000_0101) else $fatal("Data bus should be 101, driven by processor to write");
                end
                5'b10100: begin // state 20
                    internal_address <= 16'hFFF4; // Read the range start register
                    state <= 5'b10101;
                    
                    #tDSR;
                    assert(data_bus == 8'b0000_0101) else $fatal("Data bus should be 101, drven by MMU. The new configuration mode selection");
                end
                5'b10101: begin // state 21
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF4;
                    temp_write_data <= 8'd20;
                    state <= 5'b10110;
                    
                    #tDSR;
                    assert(data_bus == 8'd0) else $fatal("Data bus should be 0, driven by MMU. The default range configuration start index");
                end
                5'b10110: begin // state 22
                    temp_rwb <= 1'b1; // Set processor to read
                    internal_address <= 16'hFFF4;
                    state <= 5'b10111;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'h14) else $fatal("Data bus should be hex 14, driven by the processor to write to range config start register");
                end
                5'b10111: begin // state 23
                    internal_address <= 16'hFFF5; // Read the range end register
                    state <= 5'b11000;
                    
                    #tDSR;
                    assert(data_bus == 8'h14) else $fatal("Data bus should be hex 14, driven by the MMU. The new range start value");
                end
                5'b11000: begin // state 24
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF5;
                    temp_write_data <= 8'd32;
                    state <= 5'b11001;
                    
                    #tDSR;
                    assert(data_bus == 8'd0) else $fatal("Data bus should be 0, driven by MMU. The default range configuration end index");
                end
                5'b11001: begin // state 25
                    temp_rwb <= 1'b1; // Set processor to read
                    internal_address <= 16'hFFF5;
                    state <= 5'b11010;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'h20) else $fatal("Data bus should be hex 20, driven by processor to write to range config end register");
                end
                5'b11010: begin // state 26
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF6;
                    temp_write_data <= 8'h43; // Change the configuration for pages 20 though 32 to be RAM bank 3 pages
                    state <= 5'b11011;
                    
                    #tDSR;
                    assert(data_bus == 8'h20) else $fatal("Data bus should be hex 20, driven by the MMU. The new range end value");
                end
                5'b11011: begin // state 27
                    temp_rwb <= 1'b1; // Set processor to read
                    internal_address <= 16'hFFF6;
                    state <= 5'b11100;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'h43) else $fatal("Data bus should be hex 43, driven by the processor to write to the range configuration register");
                end
                5'b11100: begin // state 28
                    temp_rwb <= 1'b0; // Set processor to write
                    internal_address <= 16'hFFF9;
                    temp_write_data[2:0] <= 3'b110;
                    state <= 5'b11101;
                    
                    #tDSR;
                    assert(data_bus == 8'h43) else $fatal("Data bus should be hex 43, driven by the MMU. The new range configuration value");
                end
                5'b11101: begin // state 29
                    temp_rwb <= 1'b1;
                    internal_address <= 16'h0000;
                    state <= 5'b11110;
                    
                    #(tMDS + 1);
                    assert(data_bus == 8'b0000_0110) else $fatal("Data bus should be binary 110 (hex 6), driven by the processor to write to MMU configuration mode register");
                end
                5'b11110: begin // state 30
                    internal_address <= 16'h0013;
                    state <= 5'b11111;
                    
                    #tDSR;
                    assert(data_bus == 8'hC0) else $fatal("Processor read from page config table address 0. Should read C0 as preset number 10 was set");
                end
                16'd31: begin // state 31
                    internal_address <= 16'h0014;
                    state <= 16'd32;
                    
                    #tDSR;
                    assert(data_bus == 8'hC0) else $fatal("Processor read from page config table address 19 (hex 13). Should read C0");
                end
                16'd32: begin // state 32
                    internal_address <= 16'h0020;
                    state <= 16'd33;
                    
                    #tDSR;
                    assert(data_bus == 8'h43) else $fatal("Processor read from page config table address 20 (hex 14). Should be 43");
                end
                16'd33: begin // state 33
                    internal_address <= 16'h0021;
                    state <= 16'd34;
                    
                    #tDSR;
                    assert(data_bus == 8'h43) else $fatal("Processor read from page config table address 32 (hex 20). Should be 43");
                end
                16'd34: begin // state 34
                    internal_address <= 16'h007F;
                    state <= 16'd35;
                    
                    #tDSR;
                    assert(data_bus == 8'hC0) else $fatal("Processor read from page config table address 33 (hex 21). Should be C0");
                end
                16'd35: begin // state 35
                    internal_address <= 16'h0080;
                    state <= 16'd36;
                    
                    #tDSR;
                    assert(data_bus == 8'hC0) else $fatal("Processor read from page config table address 127 (hex 7F). Should be C0");
                end
                16'd36: begin // state 36
                    internal_address <= 16'h00BF;
                    state <= 16'd37;
                    
                    #tDSR;
                    assert(data_bus == 8'h40) else $fatal("Processor read from page config table address 128 (hex 80). Should be 40");
                end
                16'd37: begin // state 37
                    internal_address <= 16'h00C0;
                    state <= 16'd38;
                    
                    #tDSR;
                    assert(data_bus == 8'h40) else $fatal("Processor read from page config table address 191 (hex BF). Should be 40");
                end
                16'd38: begin // state 38
                    internal_address <= 16'h00FF;
                    state <= 16'd39;
                    
                    #tDSR;
                    assert(data_bus == 8'h00) else $fatal("Processor read from page config table address 192 (hex C0). Should be 00");
                end
                16'd39: begin // state 39
                    
                    state <= 16'd40;
                    
                    #tDSR;
                    assert(data_bus == 8'h00) else $fatal("Processor read from page config table address 255 (hex FF). Should be 00");
                end
                16'd40: begin // state 40
                    $finish;
                end
            endcase
        end
    end
endmodule
