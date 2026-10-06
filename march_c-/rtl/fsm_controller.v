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
// States         : 13
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
    output reg                   write_sel,
    output reg                   expect_sel,
    output reg                   comp_enable,
    output reg                   mem_we,
    output reg                   bist_done,
    output reg                   bist_pass
);

    localparam MAX_ADDR = {ADDR_WIDTH{1'b1}};


    // States — 4 bits, 13 used
    localparam [3:0]
        ST_IDLE     = 4'd0,
        ST_M0_WR    = 4'd1,    // M0: ↑(w0)
        ST_M1_RD    = 4'd2,    // M1: ↑(r0,w1)
        ST_M1_WR    = 4'd3,
        ST_M2_RD    = 4'd4,    // M2: ↑(r1,w0)
        ST_M2_WR    = 4'd5,
        ST_M3_RD    = 4'd6,    // M3: ↓(r0,w1)
        ST_M3_WR    = 4'd7,
        ST_M4_RD    = 4'd8,    // M4: ↓(r1,w0)
        ST_M4_WR    = 4'd9,
        ST_M5_RD    = 4'd10,   // M5: ↑(r0)
        ST_M5_FINAL = 4'd11,   // M5: final read result
        ST_DONE     = 4'd12;

    reg [3:0] state, next_state;


    // State register
    always @(posedge clk)
    begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end


    // Registered BIST result
    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            bist_pass <= 1'b0;
            bist_done <= 1'b0;
        end
        else
        begin
            bist_done <= (next_state == ST_DONE);

            if (state == ST_M5_FINAL)
                bist_pass <= ~comp_error;
            else if (next_state == ST_DONE && state != ST_DONE)
                bist_pass <= ~comp_error;
        end
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
                write_sel          = 1'b0;
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;

                if (addr_gen_done)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M1_RD;
                end
            end


            // M1: ↑(r0, w1)
            ST_M1_RD:
            begin
                next_state = ST_M1_WR;
            end

            ST_M1_WR:
            begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;
                mem_we             = 1'b1;
                write_sel          = 1'b1;
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;

                if (addr_gen_done)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M2_RD;
                end
                else
                begin
                    next_state = ST_M1_RD;
                end
            end


            // M2: ↑(r1, w0)
            ST_M2_RD:
            begin
                next_state = ST_M2_WR;
            end

            ST_M2_WR:
            begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b1;
                mem_we             = 1'b1;
                write_sel          = 1'b0;
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;

                if (addr_gen_done)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M3_RD;
                end
                else
                begin
                    next_state = ST_M2_RD;
                end
            end


            // M3: ↓(r0, w1)
            ST_M3_RD:
            begin
                next_state = ST_M3_WR;
            end

            ST_M3_WR:
            begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;
                mem_we             = 1'b1;
                write_sel          = 1'b1;
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;

                if (addr_gen_done)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = MAX_ADDR;
                    next_state          = ST_M4_RD;
                end
                else
                begin
                    next_state = ST_M3_RD;
                end
            end


            // M4: ↓(r1, w0)
            ST_M4_RD:
            begin
                addr_gen_direction = 1'b1;
                next_state         = ST_M4_WR;
            end

            ST_M4_WR:
            begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b1;
                mem_we             = 1'b1;
                write_sel          = 1'b0;
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b1;

                if (addr_gen_done)
                begin
                    addr_gen_load       = 1'b1;
                    addr_gen_load_value = {ADDR_WIDTH{1'b0}};
                    next_state          = ST_M5_RD;
                end
                else
                begin
                    next_state = ST_M4_RD;
                end
            end


            // M5: ↑(r0) — read only, ascending
            ST_M5_RD:
            begin
                comp_enable        = 1'b1;
                expect_sel         = 1'b0;
                addr_gen_enable    = 1'b1;
                addr_gen_direction = 1'b0;

                if (addr_gen_done)
                    next_state = ST_M5_FINAL;
            end


            // M5 final read-result cycle
            ST_M5_FINAL:
            begin
                comp_enable = 1'b1;
                expect_sel  = 1'b0;
                next_state  = ST_DONE;
            end


            // DONE
            ST_DONE:
            begin
                next_state = ST_DONE;
            end


            default:
                next_state = ST_IDLE;

        endcase


        // Early-exit on error — save power
        if (comp_error &&
            (state != ST_DONE) &&
            (state != ST_IDLE) &&
            (state != ST_M5_FINAL))
            next_state = ST_DONE;

    end

endmodule
