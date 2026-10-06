// -----------------------------------------------------------------------------
// Comparator
// Compares mem_dout against expect_data.
// Sticky error flag — set on first mismatch, cleared only by reset.
// -----------------------------------------------------------------------------
module comparator #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  enable,
    input  wire [DATA_WIDTH-1:0] data_read,
    input  wire [DATA_WIDTH-1:0] expected_data,
    output reg                   error_flag
);
    always @(posedge clk) begin
        if (!rst_n)
            error_flag <= 1'b0;
        else if (enable && (data_read != expected_data))
            error_flag <= 1'b1;
    end
endmodule
