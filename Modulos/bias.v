module bias (
    input  wire [7:0] address,
    input  wire clock,
    output reg signed [15:0] q
);

    reg signed [15:0] mem [0:127];
    initial begin
        $readmemh("/home/duda/Documents/Test_verilog/Modulos/arquivos/b_q.hex", mem);
    end

    always @(posedge clock) begin
        q <= mem[address];
    end
endmodule