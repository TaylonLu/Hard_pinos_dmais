module rom_bias (
    input wire clk,
    input wire [7:0] address,
    output reg signed [15:0] q
);

    reg signed [15:0] mem [0:127];

    initial begin
    end

    always @(posedge clk) begin
        q <= mem[address];
    end

endmodule