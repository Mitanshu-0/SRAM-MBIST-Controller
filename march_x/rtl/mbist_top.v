// =============================================================================
// File        : mbist_top.v
// Description : MBIST Top — March X algorithm.
//               Shared datapath; only fsm_controller differs from March C-.
//               To swap algorithm: replace fsm_controller.v only.
// =============================================================================

`include "address_generator.v"
`include "data_generator.v"
`include "comparator.v"
`include "fsm_controller.v"

module mbist_top #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  bist_start,
    output wire                  bist_done,
    output wire                  bist_pass,

    output wire [ADDR_WIDTH-1:0] mem_addr,
    output wire [DATA_WIDTH-1:0] mem_din,
    input  wire [DATA_WIDTH-1:0] mem_dout,
    output wire                  mem_we,
    output wire                  mem_en
);

    // ---- FSM → Datapath control wires ----
    wire                  addr_gen_enable;
    wire                  addr_gen_direction;
    wire                  addr_gen_load;
    wire [ADDR_WIDTH-1:0] addr_gen_load_value;
    wire                  addr_gen_done;

    wire                  write_sel;
    wire                  expect_sel;

    wire                  comp_enable;
    wire                  comp_error;

    wire                  fsm_mem_we;
    wire [ADDR_WIDTH-1:0] gen_addr;
    wire [DATA_WIDTH-1:0] write_data;
    wire [DATA_WIDTH-1:0] expect_data;

    // ---- Datapath ----
    address_generator #(.ADDR_WIDTH(ADDR_WIDTH)) u_addr_gen (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (addr_gen_enable),
        .load       (addr_gen_load),
        .load_value (addr_gen_load_value),
        .direction  (addr_gen_direction),
        .addr       (gen_addr),
        .done       (addr_gen_done)
    );

    data_generator #(.DATA_WIDTH(DATA_WIDTH)) u_data_gen (
        .write_sel  (write_sel),
        .expect_sel (expect_sel),
        .write_data (write_data),
        .expect_data(expect_data)
    );

    comparator #(.DATA_WIDTH(DATA_WIDTH)) u_comparator (
        .clk          (clk),
        .rst_n        (rst_n),
        .enable       (comp_enable),
        .data_read    (mem_dout),
        .expected_data(expect_data),
        .error_flag   (comp_error)
    );

    // ---- FSM — March X ----
    fsm_controller #(.ADDR_WIDTH(ADDR_WIDTH)) u_fsm (
        .clk                 (clk),
        .rst_n               (rst_n),
        .bist_start          (bist_start),
        .addr_gen_done       (addr_gen_done),
        .comp_error          (comp_error),
        .addr_gen_enable     (addr_gen_enable),
        .addr_gen_direction  (addr_gen_direction),
        .addr_gen_load       (addr_gen_load),
        .addr_gen_load_value (addr_gen_load_value),
        .write_sel           (write_sel),
        .expect_sel          (expect_sel),
        .comp_enable         (comp_enable),
        .mem_we              (fsm_mem_we),
        .bist_done           (bist_done),
        .bist_pass           (bist_pass)
    );

    // ---- Memory interface ----
    assign mem_en   = 1'b1;
    assign mem_addr = gen_addr;
    assign mem_din  = write_data;
    assign mem_we   = fsm_mem_we;

endmodule
