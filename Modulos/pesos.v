module pesos (
    input  wire [17:0] address,
    input  wire clock,
    output reg signed [15:0] q
);

    reg signed [15:0] mem [0:100351]; // ajuste para seu tamanho
    initial begin
        $readmemh("/home/duda/Documents/Test_verilog/Modulos/arquivos/W_in_q.hex", mem);
    end

    always @(posedge clock) begin
        q <= mem[address];
    end
endmodule