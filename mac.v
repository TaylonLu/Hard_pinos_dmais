module mac (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire add_bias,

    input wire signed [15:0] a,
    input wire signed [15:0] b,
    input wire signed [15:0] bias,

    output reg signed [31:0] acc
);

    wire signed [31:0] mult;
    wire signed [31:0] mult_full;

    assign mult_full = a * b;
    assign mult = mult_full >>> 12;


    always @(posedge clk) begin

        if (rst)
            acc <= 0;
        else if (enable)begin
            acc <= acc + mult;
        end
        else if (add_bias)begin
            acc <= acc + bias;
            end
    end

endmodule