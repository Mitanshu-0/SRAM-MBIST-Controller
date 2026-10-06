// =============================================================================
// Algorithm   : March C-
//
// Sequence:
//   M0: ↑ (w0)        — write 0, ascending
//   M1: ↑ (r0, w1)    — read 0, write 1, ascending
//   M2: ↑ (r1, w0)    — read 1, write 0, ascending
//   M3: ↓ (r0, w1)    — read 0, write 1, descending
//   M4: ↓ (r1, w0)    — read 1, write 0, descending
//   M5: ↑ (r0)        — read 0, ascending
//
// Fault coverage : SAF, TF, CFin, CFid
// Operations     : 10N
// States         : 12 
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
        ST_IDLE  = 4'd0,
        ST_M0_WR = 4'd1,    // M0: ↑(w0)
        ST_M1_RD = 4'd2,    // M1: ↑(r0,w1)
        ST_M1_WR = 4'd3,
        ST_M2_RD = 4'd4,    // M2: ↑(r1,w0)
        ST_M2_WR = 4'd5,
        ST_M3_RD = 4'd6,    // M3: ↓(r0,w1)
        ST_M3_WR = 4'd7,
        ST_M4_RD = 4'd8,    // M4: ↓(r1,w0)
        ST_M4_WR = 4'd9,
        ST_M5_RD = 4'd10,   // M5: ↑(r0)
        ST_DONE  = 4'd11;

    reg [3:0] state, next_state;


    // State register
    always @(posedge clk) begin
        if (!rst_n) state <= ST_IDLE;
        else        state <= next_state;
    end


    // Registered bist_pass
    // Avoids a combinational glitch path from comp_error directly to bist_pass.
    // Captured exactly once — on the clock edge that enters ST_DONE.
    always @(posedge clk) begin
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
            ST_IDLE: begin
                if (bist_start) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M0_WR;
                end
            end


            // M0: ↑(w0) — write 0 to every address, ascending
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


            // M1: ↑(r0, w1)
            ST_M1_RD: begin
                // No counter advance, no write — just issue the read
                next_state = ST_M1_WR;
            end

            ST_M1_WR: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;      // we expected 0
                mem_we             = 1'b1;
                write_sel          = 1'b1;      // write 1  ← decoupled from expect_sel
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M2_RD;
                end else begin
                    next_state = ST_M1_RD;
                end
            end



            // M2: ↑(r1, w0)
            ST_M2_RD: begin
                next_state = ST_M2_WR;
            end

            ST_M2_WR: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b1;      // expected 1
                mem_we             = 1'b1;
                write_sel          = 1'b0;      // write 0  ← decoupled
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M3_RD;
                end else begin
                    next_state = ST_M2_RD;
                end
            end

            // M3: ↓(r0, w1) — descending
            ST_M3_RD: begin
                addr_gen_direction = 1'b1;      // DOWN — held so comparator
                next_state         = ST_M3_WR;  // direction is stable in WR
            end

            ST_M3_WR: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;      // expected 0
                mem_we             = 1'b1;
                write_sel          = 1'b1;      // write 1
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M4_RD;
                end else begin
                    next_state = ST_M3_RD;
                end
            end


            // M4: ↓(r1, w0) — descending
            ST_M4_RD: begin
                addr_gen_direction = 1'b1;
                next_state         = ST_M4_WR;
            end

            ST_M4_WR: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b1;      // expected 1
                mem_we             = 1'b1;
                write_sel          = 1'b0;      // write 0
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;
                if (addr_gen_done) begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M5_RD;
                end else begin
                    next_state = ST_M4_RD;
                end
            end


            // M5: ↑(r0) — read only, no write
            ST_M5_RD: begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;      // expect 0
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;
                if (addr_gen_done) next_state = ST_DONE;
            end

            ST_DONE: begin
                bist_done  = 1'b1;
                // bist_pass is registered separately — see always block above
                next_state = ST_DONE;
            end

            default: next_state = ST_IDLE;

        endcase

        // Early-exit on error — skip remaining test, save power
        if (comp_error && (state != ST_DONE) && (state != ST_IDLE))
            next_state = ST_DONE;
    end

endmodule