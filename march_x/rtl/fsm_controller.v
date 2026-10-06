// =============================================================================
// File        : fsm_controller.v
// Algorithm   : March X
//
// Sequence:
//   M0: ↑ (w0)       — write 0, ascending
//   M1: ↑ (r0, w1)   — read 0, write 1, ascending
//   M2: ↓ (r1, w0)   — read 1, write 0, descending
//   M3: ↓ (r0)       — read 0, descending  (verify all zeros)
//
// Fault coverage : SAF, TF, CFin
// Operations     : 6N
// States         : 8
//
// Port interface is identical to the March C- fsm_controller.
// Drop-in replacement: only swap this file to change algorithm.
// =============================================================================

module fsm_controller #(
    parameter ADDR_WIDTH = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  bist_start,
    input  wire                  addr_gen_done,
    input  wire                  comp_error,

    output reg                   addr_gen_enable,
    output reg                   addr_gen_direction,
    output reg                   addr_gen_load,
    output reg  [ADDR_WIDTH-1:0] addr_gen_load_value,
    output reg                   write_sel,         // 0=write 0s, 1=write 1s
    output reg                   expect_sel,        // 0=expect 0s, 1=expect 1s
    output reg                   comp_enable,
    output reg                   mem_we,
    output reg                   bist_done,
    output reg                   bist_pass
);

    localparam MAX_ADDR = {ADDR_WIDTH{1'b1}};

    // -------------------------------------------------------------------------
    // State encoding  (8 states, 4-bit)
    // -------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE  = 4'd0,
        ST_M0_WR = 4'd1,    // M0: ↑(w0)
        ST_M1_RD = 4'd2,    // M1: ↑(r0,w1) — issue read, addr stable
        ST_M1_WR = 4'd3,    //               — compare(0), write 1, advance
        ST_M2_RD = 4'd4,    // M2: ↓(r1,w0) — issue read, addr stable
        ST_M2_WR = 4'd5,    //               — compare(1), write 0, advance
        ST_M3_RD = 4'd6,    // M3: ↓(r0)    — pipelined read+compare, advance
        ST_DONE  = 4'd7;

    reg [3:0] state, next_state;

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) state <= ST_IDLE;
        else        state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Registered bist_pass — captured once on the edge that enters ST_DONE
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            bist_pass <= 1'b0;
        else if (next_state == ST_DONE && state != ST_DONE)
            bist_pass <= ~comp_error;
    end

    // -------------------------------------------------------------------------
    // Next-state + output logic
    // -------------------------------------------------------------------------
    always @(*) begin
        // Defaults — prevent latches
        next_state          = state;
        addr_gen_enable     = 1'b0;
        addr_gen_direction  = 1'b0;         // UP
        addr_gen_load       = 1'b0;
        addr_gen_load_value = {ADDR_WIDTH{1'b0}};
        write_sel           = 1'b0;
        expect_sel          = 1'b0;
        comp_enable         = 1'b0;
        mem_we              = 1'b0;
        bist_done           = 1'b0;

        case (state)

            // -----------------------------------------------------------------
            // IDLE — wait for bist_start, load addr=0 for M0
            // -----------------------------------------------------------------
            ST_IDLE: begin
                if (bist_start) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M0_WR;
                end
            end

            // -----------------------------------------------------------------
            // M0: ↑(w0) — write 0 to every address, ascending
            // On last address: load addr=0 for M1 in the same cycle.
            // -----------------------------------------------------------------
            ST_M0_WR: begin
                mem_we             = 1'b1;
                write_sel          = 1'b0;      // write 0
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M1_RD;
                end
            end

            // -----------------------------------------------------------------
            // M1: ↑(r0, w1)
            //
            // RD: Present address to memory for reading.
            //     No counter change — stay on same address for write.
            //
            // WR: mem_dout valid (registered 1-cycle latency).
            //     Compare against 0, then write 1.
            //     Advance counter; on last address load addr=MAX_ADDR for M2.
            // -----------------------------------------------------------------
            ST_M1_RD: begin
                next_state = ST_M1_WR;
            end

            ST_M1_WR: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;      // expected 0
                mem_we             = 1'b1;
                write_sel          = 1'b1;      // write 1 (decoupled from expect)
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M2_RD;
                end else begin
                    next_state = ST_M1_RD;
                end
            end

            // -----------------------------------------------------------------
            // M2: ↓(r1, w0) — same structure as M1 but descending, expect 1
            // -----------------------------------------------------------------
            ST_M2_RD: begin
                //addr_gen_direction = 1'b1;      // DOWN — hold so direction is
                next_state         = ST_M2_WR;  // stable in WR cycle
            end

            ST_M2_WR: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b1;      // expected 1
                mem_we             = 1'b1;
                write_sel          = 1'b0;      // write 0 (decoupled from expect)
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;      // DOWN
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M3_RD;
                end else begin
                    next_state = ST_M2_RD;
                end
            end

            // -----------------------------------------------------------------
            // M3: ↓(r0) — pipelined read-only, descending
            //
            // addr is pre-loaded to MAX_ADDR. Each cycle:
            //   - memory reads current address
            //   - comparator checks mem_dout (result of previous-cycle read)
            //   - counter advances downward
            // When addr_gen_done fires (addr==0): transition to DONE.
            // The stale first comparison is safe — mem_dout after M2_WR is 0
            // (write cycle forces dout=0 in the memory model), matching expect.
            // -----------------------------------------------------------------
            ST_M3_RD: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;      // expect 0
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;      // DOWN
                if (addr_gen_done) next_state = ST_DONE;
            end

            // -----------------------------------------------------------------
            ST_DONE: begin
                bist_done  = 1'b1;
                next_state = ST_DONE;
            end

            default: next_state = ST_IDLE;

        endcase

        // Early-exit on first error — skip remaining phases, save power
        if (comp_error && (state != ST_DONE) && (state != ST_IDLE))
            next_state = ST_DONE;
    end

endmodule
