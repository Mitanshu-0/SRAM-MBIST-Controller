// =============================================================================
// File        : tb_mbist.v
// =============================================================================

`timescale 1ns / 1ps
`include "mbist_top.v"
`include "memory_model.v"

module tb_mbist;

    localparam ADDR_WIDTH = 4;
    localparam DATA_WIDTH = 8;
    localparam CLK_PERIOD = 10;

    reg  clk, rst_n, bist_start;
    wire bist_done, bist_pass;
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire [DATA_WIDTH-1:0] mem_din, mem_dout;
    wire mem_we, mem_en;

    mbist_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .bist_start(bist_start),
        .bist_done (bist_done),
        .bist_pass (bist_pass),
        .mem_addr  (mem_addr),
        .mem_din   (mem_din),
        .mem_dout  (mem_dout),
        .mem_we    (mem_we),
        .mem_en    (mem_en)
    );

    memory_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_mem (
        .clk (clk),
        .en  (mem_en),
        .we  (mem_we),
        .addr(mem_addr),
        .din (mem_din),
        .dout(mem_dout)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Synchronous active-low reset — hold 4 cycles
    task do_reset;
    begin
        u_mem.clear_faults();
        rst_n      = 1'b0;
        bist_start = 1'b0;
        repeat(4) @(posedge clk);
        #1;
        rst_n = 1'b1;
        @(posedge clk); #1;
    end
    endtask

    task run_and_check;
        input [8*40-1:0] label;
        input            expect_pass;
        integer t0;
    begin
        t0 = $time;
        bist_start = 1'b1;
        @(posedge clk); #1;
        bist_start = 1'b0;
        wait(bist_done);
        @(posedge clk); #1;
        if (bist_pass == expect_pass)
            $display("[%0t ns] OK   | %s | pass=%b | cycles=%0d",
                     $time, label, bist_pass, ($time-t0)/CLK_PERIOD);
        else
            $display("[%0t ns] FAIL | %s | got pass=%b expected=%b",
                     $time, label, bist_pass, expect_pass);
    end
    endtask

    task inject_stuck_fault;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] val;
    begin
        u_mem.inject_stuck_at(addr, val);
        $display("[%0t ns]      | stuck fault: mem[%0d]=0x%02h", $time, addr, val);
    end
    endtask

    task inject_corruption;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] val;
    begin
        u_mem.inject_corruption(addr, val);
        $display("[%0t ns]      | corruption: mem[%0d]=0x%02h", $time, addr, val);
    end
    endtask

    initial begin
        $dumpfile("mbist.vcd");
        $dumpvars(0, tb_mbist);
        $display("==============================================");
        $display("  MBIST — March C-");
        $display("==============================================");

        // Test 1: Clean — expect pass
        do_reset();
        run_and_check("T1: clean memory            ", 1'b1);

        // Test 2: SA1 injected mid-run
        do_reset();
        bist_start = 1'b1; @(posedge clk); #1;
        bist_start = 1'b0;
        repeat(10) @(posedge clk); #1;
        inject_stuck_fault(5, 8'hFF);
        wait(bist_done); @(posedge clk); #1;
        if (!bist_pass) $display("[%0t ns] OK   | T2: SA1 at addr 5 detected", $time);
        else            $display("[%0t ns] FAIL | T2: SA1 at addr 5 missed",   $time);

        // Test 3: Multiple faults
        do_reset();
        bist_start = 1'b1; @(posedge clk); #1;
        bist_start = 1'b0;
        repeat(10) @(posedge clk); #1;
        inject_stuck_fault(2, 8'hFF);
        inject_stuck_fault(7, 8'h00);
        wait(bist_done); @(posedge clk); #1;
        if (!bist_pass) $display("[%0t ns] OK   | T3: multi-fault detected", $time);
        else            $display("[%0t ns] FAIL | T3: multi-fault missed",   $time);

        // Test 4: Pre-existing fault before BIST starts
        do_reset();
        inject_stuck_fault(0, 8'hAA);
        inject_stuck_fault(3, 8'h55);
        run_and_check("T4: pre-existing faults      ", 1'b0);

        // Test 5: Back-to-back clean runs (verifies reset clears error flag)
        do_reset();
        run_and_check("T5a: clean run 1             ", 1'b1);
        do_reset();
        run_and_check("T5b: clean run 2             ", 1'b1);

        $display("==============================================");
        $display("  DONE");
        $display("==============================================");
        $finish;
    end

    initial begin
        #1_000_000;
        $display("WATCHDOG: timeout");
        $finish;
    end

endmodule
