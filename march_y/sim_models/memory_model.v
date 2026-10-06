// -----------------------------------------------------------------------------
// Memory Model  (simulation only)
// Synchronous write, synchronous read — 1-cycle read latency.
// -----------------------------------------------------------------------------
// synthesis translate_off
module memory_model #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  wire                  clk,
    input  wire                  en,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] din,
    output reg  [DATA_WIDTH-1:0] dout
);
    localparam DEPTH = 1 << ADDR_WIDTH;
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg                  fault_enable [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] fault_value  [0:DEPTH-1];
    integer i;

    initial begin
        dout = {DATA_WIDTH{1'b0}};
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i]          = {DATA_WIDTH{1'b0}};
            fault_enable[i] = 1'b0;
            fault_value[i]  = {DATA_WIDTH{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (en && we)
            mem[addr] <= fault_enable[addr] ? fault_value[addr] : din;

        if (en && !we)
            dout <= fault_enable[addr] ? fault_value[addr] : mem[addr];
        else
            dout <= {DATA_WIDTH{1'b0}};
    end

    task inject_stuck_at;
        input [ADDR_WIDTH-1:0] fault_addr;
        input [DATA_WIDTH-1:0] stuck_value;
    begin
        fault_enable[fault_addr] = 1'b1;
        fault_value[fault_addr]  = stuck_value;
        mem[fault_addr]          = stuck_value;
    end
    endtask

    task inject_corruption;
        input [ADDR_WIDTH-1:0] fault_addr;
        input [DATA_WIDTH-1:0] corrupt_value;
    begin
        mem[fault_addr] = corrupt_value;
    end
    endtask

    task clear_faults;
        integer idx;
    begin
        for (idx = 0; idx < DEPTH; idx = idx + 1) begin
            fault_enable[idx] = 1'b0;
            fault_value[idx]  = {DATA_WIDTH{1'b0}};
        end
    end
    endtask
endmodule
