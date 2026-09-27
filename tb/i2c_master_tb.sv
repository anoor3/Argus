// ============================================================================
// i2c_master_tb.sv -- self-checking testbench for i2c_master.sv
//
// Open-drain bus with pull-ups and a behavioral slave that samples SDA on the
// rising edge of SCL. The slave ACKs a matching 7-bit address and captures the
// data byte. Checks address ACK, data capture, and NACK on wrong address.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module i2c_master_tb;

    reg        clk = 0, rst = 1, start = 0;
    reg  [6:0] addr = 7'h50;
    reg        rw = 0;
    reg  [7:0] wr_byte = 8'h9C;
    reg  [15:0] clk_div = 16'd2;
    wire       sda_oe, scl_oe;
    wire [7:0] rd_byte;
    wire       ack, busy, done;

    integer errors = 0;

    // Open-drain: line high unless master or slave pulls low.
    reg  slv_sda_oe = 0;
    wire sda_line = (sda_oe | slv_sda_oe) ? 1'b0 : 1'b1;
    wire scl_line = (scl_oe) ? 1'b0 : 1'b1;

    always #10 clk = ~clk;
    `WATCHDOG(4000000)

    i2c_master dut (
        .clk(clk), .rst(rst), .start(start),
        .addr(addr), .rw(rw), .wr_byte(wr_byte), .clk_div(clk_div),
        .sda_in(sda_line), .scl_in(scl_line),
        .sda_oe(sda_oe), .scl_oe(scl_oe),
        .rd_byte(rd_byte), .ack(ack), .busy(busy), .done(done)
    );

    // ---- behavioral I2C slave, driven by SCL edges ----
    localparam [6:0] SLAVE_ADDR = 7'h50;

    reg [7:0] shf;
    integer   bitc;
    integer   phase_field;   // 0=address, 1=data, 2=done
    reg       matched;
    reg [7:0] cap_addr, cap_data;

    // Detect START (SDA falls while SCL high) to reset the byte machine.
    always @(negedge sda_line) begin
        if (scl_line == 1'b1) begin
            bitc = 0; phase_field = 0; matched = 0; slv_sda_oe = 0;
        end
    end

    // Sample bits on rising SCL. After 8 bits, the 9th rising SCL is the ACK.
    always @(posedge scl_line) begin
        if (!rst) begin
            if (bitc < 8) begin
                shf = {shf[6:0], sda_line};
                bitc = bitc + 1;
            end else begin
                // 9th clock = ACK bit position; nothing to sample from master
                bitc = 0;
                if (phase_field == 0) begin
                    cap_addr = shf;
                    matched  = (shf[7:1] == SLAVE_ADDR);
                    phase_field = 1;
                end else if (phase_field == 1) begin
                    cap_data = shf;
                    phase_field = 2;
                end
            end
        end
    end

    // Drive ACK low during the ACK window: after 8 bits collected, while SCL is
    // low pull SDA, release once the ACK clock's falling edge passes.
    always @(negedge scl_line) begin
        if (!rst) begin
            if (bitc == 8 && matched) slv_sda_oe = 1'b1; // set up ACK before rise
            else                      slv_sda_oe = 1'b0;
        end
    end

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        // Matching address transaction
        @(negedge clk); addr=7'h50; wr_byte=8'h9C; start=1;
        @(negedge clk); start=0;
        @(posedge done);
        `CHECK_EQ(cap_addr[7:1], SLAVE_ADDR, "slave saw matching address")
        `CHECK(ack == 1'b1, "address ACK detected")
        `CHECK_EQ(cap_data, 8'h9C, "slave captured data byte")

        repeat (20) @(posedge clk);

        // Non-matching address -> NACK, must still complete
        @(negedge clk); addr=7'h11; wr_byte=8'h55; start=1;
        @(negedge clk); start=0;
        @(posedge done);
        `CHECK(ack == 1'b0, "NACK for non-matching address")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire
