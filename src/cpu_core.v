module cpu_core (
    input  wire       clk,    // FPGA CLK input
    input  wire       rst_n,    // Active low reset
    input  wire       i_step,     // "Clock" enable (Execute one cycle)
    
    // Inputs from "io_in"
    input  wire [1:0] instruction,  //CPU Mode select
    /*
    00 = LOADPROG (Write to Program Memory)

    01 = LOADDATA (Write to Data Memory)

    10 = SETRUNPT (Set PC manually)

    11 = RUNPROG (Actually execute the code in memory)
    */
    input  wire [3:0] data_in,   // 4-bit input from the RP2040 - can be opcode or data itself
    input  wire       data_in_3_latched, // From top module logic - the state of input pin from the previous cycle

    // Outputs to "io_out"
    output reg  [3:0] pc,    //program counter - shows current program line being executed
    output reg  [3:0] regval   //result value - the value of the answer after operations
);

    // Memory Arrays (16 x 4-bit) - 16 slot memory with each slot being 4 bit wide
    reg [3:0] prog [0:15];    //Stores the instructions/code
    reg [3:0] data [0:15];    //Stores the variables
    
    // Internal Signals
    wire [3:0] progc;   // Current Prog
    wire [3:0] datac;   // Current variable/operation
    wire [3:0] npc;     // Next Program Counter (pc+1)
    
    assign progc = prog[pc];
    assign datac = data[pc];
    assign npc   = pc + 1;

    // ISA Definitions
    localparam LOAD = 4'd0, STORE = 4'd1, ADD = 4'd2, MUL = 4'd3, SUB = 4'd4;
    localparam SHIFTL = 4'd5, SHIFTR = 4'd6, JUMPTOIF = 4'd7;
    localparam LOGICAND = 4'd8, LOGICOR = 4'd9, EQUALS = 4'd10, NEQ = 4'd11;
    localparam BITAND = 4'd12, BITOR = 4'd13, LOGICNOT = 4'd14, BITNOT = 4'd15;

    // Instruction Definitions
    localparam LOADPROG = 2'd0, LOADDATA = 2'd1, SETRUNPT = 2'd2, RUNPROG = 2'd3;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 0;
            regval <= 0;
            // Clear memories
            for (i=0; i<16; i=i+1) begin
                prog[i] <= 4'd0;
                data[i] <= 4'd0;
            end
        end 
        else if (i_step) begin
            // EXECUTE ONE CYCLE
            case (instruction)
                LOADPROG: begin 
                    prog[pc] <= data_in;
                    pc <= npc;
                end
                LOADDATA: begin 
                    data[pc] <= data_in;
                    pc <= npc;
                end
                SETRUNPT: begin 
                    pc <= data_in;
                end
                RUNPROG: begin 
                    case (progc)
                        LOAD: begin regval <= datac; pc <= npc; end
                        STORE: begin data[datac] <= regval; pc <= npc; end
                        ADD:  begin regval <= regval + datac; pc <= npc; end
                        SUB:  begin regval <= regval - datac; pc <= npc; end
                        MUL:  begin regval <= regval * datac; pc <= npc; end
                        SHIFTL: begin 
                             pc <= npc;
                             regval <= ((datac<4) ? regval<<datac : regval << 3);
                        end
                        SHIFTR: begin 
                             pc <= npc;
                             regval <= ((datac<4) ? regval>>datac : regval >> 3);
                        end
                        JUMPTOIF: begin
                             // Use the latched version of input bit 7 (data_in[3])
                             pc <= (data_in_3_latched) ? datac : npc;
                        end
                        LOGICAND: begin regval <= regval && datac; pc <= npc; end
                        LOGICOR:  begin regval <= regval || datac; pc <= npc; end
                        EQUALS:   begin regval <= (regval == datac); pc <= npc; end
                        NEQ:      begin regval <= (regval != datac); pc <= npc; end
                        BITAND:   begin regval <= (regval & datac); pc <= npc; end
                        BITNOT:   begin regval <= ~(regval); pc <= npc; end
                        BITOR:    begin regval <= (regval | datac); pc <= npc; end
                        LOGICNOT: begin regval <= !regval; pc <= npc; end
                    endcase
                end
            endcase
        end
    end

endmodule
