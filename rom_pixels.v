module rom_pixels (
    input wire clk,
    input wire [9:0] address,   // 0..783
    output reg signed [15:0] q
);

    reg signed [15:0] mem [0:783];

    initial begin
    end

    always @(posedge clk) begin
        q <= mem[address];
    end

endmodule