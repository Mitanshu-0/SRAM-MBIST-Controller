// =============================================================================
// Algorithm   : March Y
//
// Sequence:
//   M0: ↑ (w0)              — write 0, ascending
//   M1: ↑ (r0, w1, r1)      — read 0, write 1, read 1, ascending
//   M2: ↓ (r1, w0, r0)      — read 1, write 0, read 0, descending
//   M3: ↓ (r0)              — read 0, descending
//
// Fault coverage : SAF, TF, CFin
// Operations     : 8N
// States         : 12
//
// Note:
//   M1 and M2 use a read-back operation after every write.
//   This verifies that the value written into each SRAM cell is retained
//   correctly before moving to the next address.
//
// RDF limitation:
//   Read Destructive Faults are not detected by this sequence because
//   the write operation occurs between the two reads and can overwrite
//   corruption caused by the first read.
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


    // States — 4 bits, 12 used
    localparam [3:0]
        ST_IDLE   = 4'd0,

        ST_M0_WR  = 4'd1,    // M0: ↑(w0)

        ST_M1_RD1 = 4'd2,    // M1: ↑(r0,w1,r1)
        ST_M1_WR  = 4'd3,
        ST_M1_RD2 = 4'd4,
        ST_M1_CMP = 4'd5,

        ST_M2_RD1 = 4'd6,    // M2: ↓(r1,w0,r0)
        ST_M2_WR  = 4'd7,
        ST_M2_RD2 = 4'd8,
        ST_M2_CMP = 4'd9,

        ST_M3_RD  = 4'd10,   // M3: ↓(r0)
        ST_DONE   = 4'd11;

    reg [3:0] state, next_state;


    // State register
    always @(posedge clk)
    begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end


    // Registered bist_pass
    // Avoids a combinational glitch path from comp_error directly to bist_pass.
    // Captured exactly once — on the clock edge that enters ST_DONE.
    always @(posedge clk)
    begin
        if (!rst_n)
            bist_pass <= 1'b0;
        else if (next_state == ST_DONE && state != ST_DONE)
            bist_pass <= ~comp_error;
    end


    // Next-state and output logic
    always @(*) begin

        // Defaults — all signals must be assigned to prevent latches
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


            // IDLE → M0_WR
            ST_IDLE:
            begin
                if (bist_start)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M0_WR;
                end
            end


            // M0: ↑(w0) — write 0 to every address, ascending
            ST_M0_WR:
            begin
                mem_we             = 1'b1;
                write_sel          = 1'b0;      // write 0

                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;      // UP

                if (addr_gen_done)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M1_RD1;
                end
            end


            // =========================================================================
            // M1: ↑(r0, w1, r1)
            //
            // For each address:
            //
            //   RD1 → read current value
            //   WR  → compare 0 and write 1
            //   RD2 → read the newly written value
            //   CMP → compare 1 and advance address
            //
            // The address remains unchanged during RD1, WR and RD2.
            // The address advances only during CMP.
            // =========================================================================

            // M1 — first read: r0
            ST_M1_RD1:
            begin
                // Issue read — no counter advance, no compare, no write
                next_state = ST_M1_WR;
            end


            // M1 — compare r0 and write 1
            ST_M1_WR:
            begin
                comp_enable = 1'b1;
                expect_sel  = 1'b0;              // expected 0

                mem_we     = 1'b1;
                write_sel  = 1'b1;               // write 1

                // Address remains unchanged for the read-back
                next_state = ST_M1_RD2;
            end


            // M1 — second read: r1
            ST_M1_RD2:
            begin
                // Issue read of the value just written
                // No counter advance, no compare, no write
                next_state = ST_M1_CMP;
            end


            // M1 — compare r1 and advance address
            ST_M1_CMP:
            begin
                comp_enable = 1'b1;
                expect_sel  = 1'b1;              // expected 1

                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;       // UP

                if (addr_gen_done)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M2_RD1;
                end
                else
                begin
                    next_state = ST_M1_RD1;
                end
            end


            // =========================================================================
            // M2: ↓(r1, w0, r0)
            //
            // For each address:
            //
            //   RD1 → read current value
            //   WR  → compare 1 and write 0
            //   RD2 → read the newly written value
            //   CMP → compare 0 and advance address
            //
            // The address remains unchanged during RD1, WR and RD2.
            // The address advances only during CMP.
            // =========================================================================

            // M2 — first read: r1
            ST_M2_RD1:
            begin
                addr_gen_direction = 1'b1;       // DOWN
                next_state          = ST_M2_WR;
            end


            // M2 — compare r1 and write 0
            ST_M2_WR:
            begin
                comp_enable = 1'b1;
                expect_sel  = 1'b1;              // expected 1

                mem_we     = 1'b1;
                write_sel  = 1'b0;               // write 0

                // Address remains unchanged for the read-back
                next_state = ST_M2_RD2;
            end


            // M2 — second read: r0
            ST_M2_RD2:
            begin
                addr_gen_direction = 1'b1;       // DOWN

                // Issue read of the value just written
                // No counter advance, no compare, no write
                next_state = ST_M2_CMP;
            end


            // M2 — compare r0 and advance address
            ST_M2_CMP:
            begin
                comp_enable = 1'b1;
                expect_sel  = 1'b0;              // expected 0

                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;       // DOWN

                if (addr_gen_done)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M3_RD;
                end
                else
                begin
                    next_state = ST_M2_RD1;
                end
            end


            // M3: ↓(r0) — final read-only verification, descending
            ST_M3_RD:
            begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;       // expect 0

                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;       // DOWN

                if (addr_gen_done)
                    next_state = ST_DONE;
            end


            // DONE — BIST completed
            ST_DONE:
            begin
                bist_done = 1'b1;

                // bist_pass is registered separately — see always block above
                next_state = ST_DONE;
            end


            default:
                next_state = ST_IDLE;

        endcase


        // Early-exit on error — skip remaining test, save power
        if (comp_error && (state != ST_DONE) && (state != ST_IDLE))
            next_state = ST_DONE;

    end

endmodule
