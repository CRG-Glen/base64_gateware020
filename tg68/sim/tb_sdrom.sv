`timescale 1ns / 1ps
// SD boot ROM read-back (sd_subsystem.v, ROM_BYTES): every byte offset of
// the 32 KB ROM window must read as the original 32 KB sfsd image did:
// the image's byte below ROM_BYTES, 0xFF (its padding) above.
module tb;
    reg clk = 0; always #5.87 clk = ~clk;
    reg [31:1] a = 0;
    wire [15:0] d_out;
    wire sd_space, sd_int_win, dtack_n, ss_n, sclk, mosi;
    sd_subsystem u (
        .sd_lo_x(1'b0), .clk(clk), .reset(1'b0), .a(a), .as_n(1'b1), .uds_n(1'b1), .lds_n(1'b1),
        .rw(1'b1), .d_in(16'd0), .sd_configured(1'b0), .base_sd(8'hE9),
        .sd_space(sd_space), .sd_int_win(sd_int_win), .d_out(d_out), .dtack_n(dtack_n),
        .rom_we(1'b0), .rom_waddr(15'd0), .rom_wdata(8'd0),
        .sd_miso(1'b1), .sd_cd_n(1'b0), .sd_ss_n(ss_n), .sd_sclk(sclk), .sd_mosi(mosi));
    reg [7:0] img [0:18431];
    integer i, bad = 0, ff = 0;
    reg [7:0] exp;
    initial begin
        $readmemh("sfsd.mem", img);
        for (i = 0; i < 32768; i = i + 1) begin
            a = {16'h00E9, i[14:0]};
            @(posedge clk); @(posedge clk); #1;
            exp = (i < 18432) ? img[i] : 8'hFF;
            if (i >= 18432) ff = ff + 1;
            if (d_out !== {exp, exp}) begin
                if (bad < 5) $display("FAIL ROM byte %0d: read %h, expected %h", i, d_out, {exp, exp});
                bad = bad + 1;
            end
        end
        $display("SD ROM: 32768 bytes read, %0d of them above ROM_BYTES (0xFF), %0d wrong", ff, bad);
        if (bad) $display("FAILED"); else $display("PASS");
        $finish;
    end
endmodule
