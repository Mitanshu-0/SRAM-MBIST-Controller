// =============================================================================
// File        : mbist_datapath.v
// =============================================================================

// -----------------------------------------------------------------------------
// Address Generator
// Synchronous reset. Load takes priority over enable.
// -----------------------------------------------------------------------------
module address_generator #(
    parameter ADDR_WIDTH = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  enable,
    input  wire                  direction,      // 0 = up, 1 = down
    input  wire                  load,
    input  wire [ADDR_WIDTH-1:0] load_value,
    output reg  [ADDR_WIDTH-1:0] addr,
    output wire                  done
);
    localparam MAX_ADDR = {ADDR_WIDTH{1'b1}};

    always @(posedge clk) begin
        if (!rst_n)
            addr <= {ADDR_WIDTH{1'b0}};
        else if (load)
            addr <= load_value;
        else if (enable)
            addr <= direction ? (addr - 1'b1) : (addr + 1'b1);
    end

    assign done = enable & (direction ? (addr == 0)
                                      : (addr == MAX_ADDR));
endmodule
