module rom_beta (
    input  wire        clk,
    input  wire [10:0] address,
    output reg  signed [15:0] q
);

    reg signed [15:0] mem [0:1799];

    initial begin
    end

    always @(posedge clk) begin
        q <= mem[address];
    end

endmodule