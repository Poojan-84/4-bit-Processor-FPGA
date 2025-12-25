(* top *) module top ( 
    (* iopad_external_pin, clkbuf_inhibit *) input clk,
    (* iopad_external_pin *) input  rst_n, 

    // SPI Interface
    (* iopad_external_pin *) input  spi_ss_n, 
    (* iopad_external_pin *) input  spi_sck, 
    (* iopad_external_pin *) input  spi_mosi, 
    (* iopad_external_pin *) output spi_miso, 
    (* iopad_external_pin *) output spi_miso_en
);

    // Wires for SPI Module
    wire [7:0] spi_rx_data;
    wire       spi_rx_valid;
    reg  [7:0] spi_tx_data;

    // Instantiate existing SPI Target
    spi_target #( .WIDTH(8) ) u_spi_target (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_enable(1'b1),
        .i_ss_n(spi_ss_n),
        .i_sck(spi_sck),
        .i_mosi(spi_mosi),
        .o_miso(spi_miso),
        .o_miso_oe(spi_miso_en),
        .o_rx_data(spi_rx_data),
        .o_rx_data_valid(spi_rx_valid),
        .i_tx_data(spi_tx_data),
        .o_tx_data_hold() 
    );

    // CPU Signals
    wire [3:0] cpu_pc;
    wire [3:0] cpu_regval;
    
    // Logic to handle Inputs
    reg cpu_reset_cmd;
    reg step_cmd;
    reg [1:0] cpu_instr;
    reg [3:0] cpu_data;
    reg last_data_bit_3;

    // Pulse generation for Step
    reg spi_rx_valid_d;
    wire spi_rx_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_rx_valid_d <= 1'b0;
            cpu_reset_cmd <= 1'b0;
            step_cmd <= 1'b0;
            cpu_instr <= 2'b00;
            cpu_data <= 4'b0000;
            last_data_bit_3 <= 1'b0;
        end else begin
            spi_rx_valid_d <= spi_rx_valid;
            
            // Only update inputs when a new SPI byte arrives
            if (spi_rx_valid && !spi_rx_valid_d) begin
                // Packet Format: {Data[3:0], Instr[1:0], Reset, Step}
                cpu_data  <= spi_rx_data[7:4];
                cpu_instr <= spi_rx_data[3:2];
                cpu_reset_cmd <= spi_rx_data[1];
                step_cmd  <= spi_rx_data[0];
                
                // Keep track of Data[3] for the JUMP instruction condition
                last_data_bit_3 <= spi_rx_data[7]; 
            end else begin
                step_cmd <= 1'b0; // Auto-clear the step command so we only step once per byte
            end
            
            // Constantly update the output for the NEXT transaction
            spi_tx_data <= {cpu_regval, cpu_pc};
        end
    end

    // Instantiate the CPU Core
    cpu_core u_cpu (
        .clk(clk),
        .rst_n(rst_n && !cpu_reset_cmd), // Hardware reset OR Software reset
        .i_step(step_cmd),               // Step only when SPI sends "1" at bit 0
        .instruction(cpu_instr),
        .data_in(cpu_data),
        .data_in_3_latched(last_data_bit_3),
        .pc(cpu_pc),
        .regval(cpu_regval)
    );

endmodule
