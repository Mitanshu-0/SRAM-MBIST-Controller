// =============================================================================
// File        : fsm_controller.v
// Algorithm   : March Y
//
// Sequence:
//   M0: ↑ (w0)           — write 0, ascending
//   M1: ↑ (r0, w1, r1)   — read 0, write 1, read 1 back — ascending
//   M2: ↓ (r1, w0, r0)   — read 1, write 0, read 0 back — descending
//   M3: ↓ (r0)           — read 0, descending  (final verify)
//
// Fault coverage : SAF, TF, CFin
// Operations     : 8N
// States         : 12
//
// Key difference from March X / March C-:
//   Phases M1 and M2 each perform THREE operations per cell
//   (read → write → read-back). The read-back verifies write integrity
//   for that cell, providing stronger transition and coupling fault coverage
//   than March X's two-operation phases.
//
// NOTE — RDF (Read Destructive Faults) are NOT detected:
//   The write (w1 / w0) between the two reads overwrites any corruption
//   caused by the first read, masking the fault before the read-back fires.
//   The r,w,r structure checks write retention, not read destruction.
//
// State breakdown per address in M1 (4 states):
//   ST_M1_RD1  — issue read  (r0):  memory read initiated, no compare
//   ST_M1_WR   — compare(0) + w1:  check read result, write 1
//   ST_M1_RD2  — issue read  (r1):  second read initiated, no compare
//   ST_M1_CMP  — compare(1) + advance address
//
// M2 is the mirror: (r1) → compare(1)+w0 → (r0) → compare(0)+advance
//
// Port interface is IDENTICAL to March C- and March X fsm_controller.
// Drop-in replacement: swap only this file to change algorithm.
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
    // State encoding  (12 states, 4-bit)
    // -------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE   = 4'd0,
        ST_M0_WR  = 4'd1,   // M0: ↑(w0)

        ST_M1_RD1 = 4'd2,   // M1 step 1 — issue read (expect 0)
        ST_M1_WR  = 4'd3,   // M1 step 2 — compare(0), write 1
        ST_M1_RD2 = 4'd4,   // M1 step 3 — issue second read (expect 1 = written value)
        ST_M1_CMP = 4'd5,   // M1 step 4 — compare(1) verifies write retention, advance addr

        ST_M2_RD1 = 4'd6,   // M2 step 1 — issue read (expect 1)
        ST_M2_WR  = 4'd7,   // M2 step 2 — compare(1), write 0
        ST_M2_RD2 = 4'd8,   // M2 step 3 — issue second read (expect 0 = written value)
        ST_M2_CMP = 4'd9,   // M2 step 4 — compare(0) verifies write retention, advance addr

        ST_M3_RD  = 4'd10,  // M3: ↓(r0) — pipelined read+compare, advance
        ST_DONE   = 4'd11;

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
        // Defaults — all signals assigned to prevent latches
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
            // IDLE — wait for bist_start; pre-load addr=0 for M0
            // -----------------------------------------------------------------
            ST_IDLE: begin
                if (bist_start) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M0_WR;
                end
            end

            // -----------------------------------------------------------------
            // M0: ↑(w0) — initialise all cells to 0, ascending
            // On last address: write happens, then load addr=0 for M1.
            // -----------------------------------------------------------------
            ST_M0_WR: begin
                mem_we             = 1'b1;
                write_sel          = 1'b0;      // write 0
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M1_RD1;
                end
            end

            // =================================================================
            // M1: ↑(r0, w1, r1)
            //
            // Per-address sequence (4 states):
            //
            //   RD1 — Present address; memory read is initiated.
            //         Address does NOT advance (same cell for write next).
            //
            //   WR  — mem_dout now valid (1-cycle SRAM latency).
            //         Comparator checks: expected 0.
            //         Write 1 to same cell.
            //         Address still does NOT advance (second read next).
            //
            //   RD2 — Present same address again; second read is initiated.
            //         Checks write retention: was 1 actually stored?
            //         Address does NOT advance.
            //
            //   CMP — mem_dout reflects the written-1 value.
            //         Comparator checks: expected 1 (write-retention verify).
            //         Address advances. If last: load MAX_ADDR for M2.
            //
            // NOTE: The write between the two reads means this does NOT detect
            // RDF. Any corruption from reading 0 is overwritten by w1 before
            // the second read fires.
            // ================================================================= 
            ST_M1_RD1: begin
                // Issue read — no counter change, no compare, no write
                next_state = ST_M1_WR;
            end

            ST_M1_WR: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;      // expected 0 (from M0 initialisation)
                mem_we             = 1'b1;
                write_sel          = 1'b1;      // write 1  (decoupled from expect_sel)
                // No addr advance — stay on same cell for read-back
                next_state         = ST_M1_RD2;
            end

            ST_M1_RD2: begin
                // Issue second read — no counter change, no compare, no write
                next_state = ST_M1_CMP;
            end

            ST_M1_CMP: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b1;      // expected 1 (we just wrote 1)
                // Now advance the address
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;      // UP
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M2_RD1;
                end else begin
                    next_state = ST_M1_RD1;
                end
            end

            // =================================================================
            // M2: ↓(r1, w0, r0)
            //
            // Mirror of M1 but descending, value polarity inverted.
            // Cells contain 1 (left by M1). Read→write-0→read-back.
            //
            //   RD1 — Issue read; addr stable; direction held DOWN.
            //   WR  — comp(expect 1) + write 0; addr stable.
            //   RD2 — Issue second read; addr stable.
            //         Checks write retention: was 0 actually stored?
            //   CMP — comp(expect 0, write-retention verify); advance addr.
            //         If last (addr==0): load MAX_ADDR for M3.
            //
            // NOTE: Same masking applies — RDF not detectable here either.
            // ================================================================= 
            ST_M2_RD1: begin
                addr_gen_direction = 1'b1;      // DOWN — held for direction coherence
                next_state         = ST_M2_WR;
            end

            ST_M2_WR: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b1;      // expected 1 (from M1)
                mem_we             = 1'b1;
                write_sel          = 1'b0;      // write 0
                // No addr advance — stay on same cell for read-back
                next_state         = ST_M2_RD2;
            end

            ST_M2_RD2: begin
                addr_gen_direction = 1'b1;      // DOWN — keep stable
                next_state         = ST_M2_CMP;
            end

            ST_M2_CMP: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;      // expected 0 (we just wrote 0)
                // Advance address downward
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;      // DOWN
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M3_RD;
                end else begin
                    next_state = ST_M2_RD1;
                end
            end

            // -----------------------------------------------------------------
            // M3: ↓(r0) — pipelined read-only, descending
            //
            // addr pre-loaded to MAX_ADDR. Each cycle:
            //   - memory reads current address
            //   - comparator checks dout (previous cycle's read result)
            //   - address decrements
            // When addr_gen_done fires (addr==0 and enable): go to DONE.
            // First comparison is against M2_CMP's dout=0 (write cycle before
            // M3 entered → dout forced to 0 by memory model), so it is safe.
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
