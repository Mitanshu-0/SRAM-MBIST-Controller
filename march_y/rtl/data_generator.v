// -----------------------------------------------------------------------------
// Data Generator
// Two independent outputs:
//   write_data  — data to write into memory (controlled by write_sel)
//   expect_data — data the comparator checks against (controlled by expect_sel)
//
// Decoupling these two was necessary because in phases like M1(r0,w1) the
// FSM must compare against 0 AND write 1 in the same cycle — impossible
// with a single select signal driving one shared bus.
// -----------------------------------------------------------------------------
module data_generator #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  write_sel,      // 0 = write all-0s, 1 = write all-1s
    input  wire                  expect_sel,     // 0 = expect all-0s, 1 = expect all-1s
    output wire [DATA_WIDTH-1:0] write_data,
    output wire [DATA_WIDTH-1:0] expect_data
);
    assign write_data  = write_sel  ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}};
    assign expect_data = expect_sel ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}};
endmodule
