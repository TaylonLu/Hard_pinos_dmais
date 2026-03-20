module rom_weights (
    input wire clk,
    input wire [16:0] address, // até 100351
    output reg signed [15:0] q
);

    reg signed [15:0] mem [0:100351];

    initial begin
    end

    always @(posedge clk) begin
        q <= mem[address];
    end

endmodule