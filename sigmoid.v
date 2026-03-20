module sigmoid(
    input wire clk,
    input wire signed [15:0] x, // Q4.12
    output reg signed [15:0] y  // Q4.12
);

    reg signed [15:0] lut [0:255]; // LUT 256 entradas


    wire [7:0] index;
    assign index = x[15:8] + 8'd128; // shift para 0..255

    always @(posedge clk) begin
        y <= lut[index];
    end

endmodule