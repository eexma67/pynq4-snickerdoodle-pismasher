// Integer calculator (+, -, *, /) with an AXI4-Lite register interface.
//
// Signed 32-bit two's-complement operands. Multiply and divide are
// iterative (32 clock cycles) to keep timing easy at any fabric clock.
//
// Register map (byte offsets):
//   0x00 CTRL    W: bit0 = start (self-clearing)
//                R: bit0 = busy, bit1 = done, bit2 = div_by_zero, bit3 = overflow
//   0x04 OPCODE  0 = add, 1 = sub, 2 = mul, 3 = div
//   0x08 A       operand A
//   0x0C B       operand B
//   0x10 RES_LO  add/sub/div: result (quotient); mul: product bits [31:0]
//   0x14 RES_HI  mul: product bits [63:32]; div: remainder; add/sub: sign extension
//
// Division truncates toward zero and the remainder takes the sign of A, as in C.
// Division by zero sets div_by_zero and returns 0 / A. Overflow is set when the
// true result does not fit in RES_LO (add/sub/mul) or for INT_MIN / -1.

`timescale 1ns / 1ps

module calc_axi (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET s_axi_aresetn" *)
    input  wire        s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        s_axi_aresetn,

    input  wire [4:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [4:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    localparam OP_ADD = 2'd0, OP_SUB = 2'd1, OP_MUL = 2'd2, OP_DIV = 2'd3;
    localparam S_IDLE = 2'd0, S_MUL = 2'd1, S_DIV = 2'd2, S_FIX = 2'd3;

    wire clk = s_axi_aclk;
    wire rst = ~s_axi_aresetn;

    // ---------------------------------------------------------------- registers
    reg  [1:0]  opcode;
    reg  [31:0] reg_a, reg_b;
    reg  [31:0] res_lo, res_hi;
    reg         done, div_by_zero, overflow;
    reg  [1:0]  state;
    wire        busy = (state != S_IDLE);

    // ---------------------------------------------------------- AXI-Lite write
    // Accept a write once both address and data are valid; one response at a time.
    wire wr_en = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    assign s_axi_awready = wr_en;
    assign s_axi_wready  = wr_en;
    assign s_axi_bresp   = 2'b00;

    function [31:0] apply_strb(input [31:0] old, input [31:0] data, input [3:0] strb);
        integer i;
        begin
            for (i = 0; i < 4; i = i + 1)
                apply_strb[i*8 +: 8] = strb[i] ? data[i*8 +: 8] : old[i*8 +: 8];
        end
    endfunction

    wire start = wr_en && (s_axi_awaddr[4:2] == 3'd0) && s_axi_wstrb[0] && s_axi_wdata[0];

    always @(posedge clk) begin
        if (rst) begin
            s_axi_bvalid <= 1'b0;
            opcode       <= OP_ADD;
            reg_a        <= 32'd0;
            reg_b        <= 32'd0;
        end else begin
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
            if (wr_en) begin
                s_axi_bvalid <= 1'b1;
                // Operands are frozen while a calculation runs.
                if (!busy) begin
                    case (s_axi_awaddr[4:2])
                        3'd1: if (s_axi_wstrb[0]) opcode <= s_axi_wdata[1:0];
                        3'd2: reg_a <= apply_strb(reg_a, s_axi_wdata, s_axi_wstrb);
                        3'd3: reg_b <= apply_strb(reg_b, s_axi_wdata, s_axi_wstrb);
                        default: ;
                    endcase
                end
            end
        end
    end

    // ----------------------------------------------------------- AXI-Lite read
    assign s_axi_arready = !s_axi_rvalid;
    assign s_axi_rresp   = 2'b00;

    always @(posedge clk) begin
        if (rst) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
        end else begin
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                case (s_axi_araddr[4:2])
                    3'd0: s_axi_rdata <= {28'd0, overflow, div_by_zero, done, busy};
                    3'd1: s_axi_rdata <= {30'd0, opcode};
                    3'd2: s_axi_rdata <= reg_a;
                    3'd3: s_axi_rdata <= reg_b;
                    3'd4: s_axi_rdata <= res_lo;
                    3'd5: s_axi_rdata <= res_hi;
                    default: s_axi_rdata <= 32'd0;
                endcase
            end
        end
    end

    // ------------------------------------------------------------- arithmetic
    wire [32:0] sum  = {reg_a[31], reg_a} + {reg_b[31], reg_b};
    wire [32:0] diff = {reg_a[31], reg_a} - {reg_b[31], reg_b};
    wire [31:0] abs_a = reg_a[31] ? -reg_a : reg_a;
    wire [31:0] abs_b = reg_b[31] ? -reg_b : reg_b;

    reg  [63:0] acc;        // mul: product;   div: {remainder, quotient}
    reg  [63:0] mcand;      // mul: shifted multiplicand
    reg  [31:0] mplier;     // mul: remaining multiplier bits
    reg  [5:0]  count;
    reg         negate;     // result sign correction

    // One restoring-division step on {remainder, quotient}.
    wire [32:0] rem_shift = {acc[63:32], acc[31]};
    wire [32:0] rem_sub   = rem_shift - {1'b0, abs_b};
    wire        rem_ge    = !rem_sub[32];

    wire [63:0] product   = negate ? -acc : acc;

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            div_by_zero <= 1'b0;
            overflow    <= 1'b0;
            res_lo      <= 32'd0;
            res_hi      <= 32'd0;
            acc         <= 64'd0;
            mcand       <= 64'd0;
            mplier      <= 32'd0;
            count       <= 6'd0;
            negate      <= 1'b0;
        end else begin
            case (state)
            S_IDLE:
                if (start) begin
                    done        <= 1'b0;
                    div_by_zero <= 1'b0;
                    overflow    <= 1'b0;
                    case (opcode)
                    OP_ADD: begin
                        res_lo   <= sum[31:0];
                        res_hi   <= {32{sum[32]}};
                        overflow <= sum[32] != sum[31];
                        done     <= 1'b1;
                    end
                    OP_SUB: begin
                        res_lo   <= diff[31:0];
                        res_hi   <= {32{diff[32]}};
                        overflow <= diff[32] != diff[31];
                        done     <= 1'b1;
                    end
                    OP_MUL: begin
                        acc    <= 64'd0;
                        mcand  <= {32'd0, abs_a};
                        mplier <= abs_b;
                        negate <= reg_a[31] ^ reg_b[31];
                        count  <= 6'd32;
                        state  <= S_MUL;
                    end
                    OP_DIV:
                        if (reg_b == 32'd0) begin
                            res_lo      <= 32'd0;
                            res_hi      <= reg_a;
                            div_by_zero <= 1'b1;
                            done        <= 1'b1;
                        end else begin
                            acc    <= {32'd0, abs_a};
                            negate <= reg_a[31] ^ reg_b[31];
                            count  <= 6'd32;
                            state  <= S_DIV;
                        end
                    endcase
                end

            S_MUL: begin
                if (mplier[0])
                    acc <= acc + mcand;
                mcand  <= mcand << 1;
                mplier <= mplier >> 1;
                count  <= count - 6'd1;
                if (count == 6'd1)
                    state <= S_FIX;
            end

            S_DIV: begin
                acc[63:32] <= rem_ge ? rem_sub[31:0] : rem_shift[31:0];
                acc[31:0]  <= {acc[30:0], rem_ge};
                count      <= count - 6'd1;
                if (count == 6'd1)
                    state <= S_FIX;
            end

            S_FIX: begin
                if (opcode == OP_MUL) begin
                    res_lo   <= product[31:0];
                    res_hi   <= product[63:32];
                    overflow <= product[63:32] != {32{product[31]}};
                end else begin
                    res_lo   <= negate ? -acc[31:0] : acc[31:0];
                    res_hi   <= reg_a[31] ? -acc[63:32] : acc[63:32];
                    overflow <= (reg_a == 32'h8000_0000) && (reg_b == 32'hFFFF_FFFF);
                end
                done  <= 1'b1;
                state <= S_IDLE;
            end
            endcase
        end
    end

endmodule
