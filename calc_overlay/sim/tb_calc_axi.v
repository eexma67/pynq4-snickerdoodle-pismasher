// Self-checking testbench for calc_axi: drives AXI4-Lite and compares
// against reference arithmetic for corner cases and random operands.

`timescale 1ns / 1ps

module tb_calc_axi;

    reg clk = 0, aresetn = 0;
    always #5 clk = ~clk;

    reg  [4:0]  awaddr = 0, araddr = 0;
    reg         awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    reg  [31:0] wdata = 0;
    reg  [3:0]  wstrb = 0;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    calc_axi dut (
        .s_axi_aclk(clk), .s_axi_aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready)
    );

    task axi_write(input [4:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1; wdata = data; wstrb = 4'hF; wvalid = 1; bready = 1;
            @(posedge clk); while (!(awready && wready)) @(posedge clk);
            @(negedge clk); awvalid = 0; wvalid = 0;
            while (!bvalid) @(posedge clk);
            @(negedge clk); bready = 0;
        end
    endtask

    task axi_read(input [4:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            araddr = addr; arvalid = 1; rready = 1;
            @(posedge clk); while (!arready) @(posedge clk);
            @(negedge clk); arvalid = 0;
            while (!rvalid) @(posedge clk);
            data = rdata;
            @(negedge clk); rready = 0;
        end
    endtask

    integer errors = 0, tests = 0;

    task check(input [1:0] op, input [31:0] a, input [31:0] b);
        reg [31:0] ctrl, lo, hi;
        reg [31:0] exp_lo, exp_hi;
        reg        exp_dz, exp_ovf;
        reg signed [63:0] p;
        reg signed [32:0] s;
        integer polls;
        begin
            axi_write(5'h04, {30'd0, op});
            axi_write(5'h08, a);
            axi_write(5'h0C, b);
            axi_write(5'h00, 32'd1);
            polls = 0;
            ctrl = 32'd1;
            while (ctrl[0] || !ctrl[1]) begin
                axi_read(5'h00, ctrl);
                polls = polls + 1;
                if (polls > 100) begin
                    $display("TIMEOUT op=%0d a=%0d b=%0d", op, $signed(a), $signed(b));
                    $finish;
                end
            end
            axi_read(5'h10, lo);
            axi_read(5'h14, hi);

            exp_dz = 0; exp_ovf = 0;
            case (op)
            0: begin s = $signed({a[31], a}) + $signed({b[31], b});
                     exp_lo = s[31:0]; exp_hi = {32{s[32]}}; exp_ovf = s[32] != s[31]; end
            1: begin s = $signed({a[31], a}) - $signed({b[31], b});
                     exp_lo = s[31:0]; exp_hi = {32{s[32]}}; exp_ovf = s[32] != s[31]; end
            2: begin p = $signed(a) * $signed(b);
                     exp_lo = p[31:0]; exp_hi = p[63:32]; exp_ovf = p[63:32] != {32{p[31]}}; end
            3: if (b == 0) begin
                   exp_lo = 0; exp_hi = a; exp_dz = 1;
               end else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) begin
                   exp_lo = 32'h8000_0000; exp_hi = 0; exp_ovf = 1;
               end else begin
                   exp_lo = $signed(a) / $signed(b); exp_hi = $signed(a) % $signed(b);
               end
            endcase

            tests = tests + 1;
            if (lo !== exp_lo || hi !== exp_hi || ctrl[2] !== exp_dz || ctrl[3] !== exp_ovf) begin
                errors = errors + 1;
                $display("FAIL op=%0d a=%0d b=%0d : got lo=%0d hi=%0d dz=%b ovf=%b, expected lo=%0d hi=%0d dz=%b ovf=%b",
                         op, $signed(a), $signed(b), $signed(lo), $signed(hi), ctrl[2], ctrl[3],
                         $signed(exp_lo), $signed(exp_hi), exp_dz, exp_ovf);
            end
        end
    endtask

    reg [31:0] corner [0:9];
    integer i, j, op;

    initial begin
        corner[0] = 0;            corner[1] = 1;            corner[2] = 32'hFFFF_FFFF;
        corner[3] = 7;            corner[4] = -7;           corner[5] = 32'h7FFF_FFFF;
        corner[6] = 32'h8000_0000; corner[7] = 3;           corner[8] = -3;
        corner[9] = 100000;

        repeat (5) @(posedge clk);
        aresetn = 1;

        for (op = 0; op < 4; op = op + 1)
            for (i = 0; i < 10; i = i + 1)
                for (j = 0; j < 10; j = j + 1)
                    check(op, corner[i], corner[j]);

        for (i = 0; i < 2000; i = i + 1)
            check($random & 3, $random, (i % 3 == 0) ? ($random % 1000) : $random);

        if (errors == 0)
            $display("PASS: %0d tests", tests);
        else
            $display("FAILED: %0d of %0d tests", errors, tests);
        $finish;
    end

endmodule
