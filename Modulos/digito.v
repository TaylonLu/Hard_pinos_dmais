module digito (
    input  wire [9:0] address,
    input  wire [7:0] data,
    input  wire inclock,
    input  wire outclock,
    input  wire wren,
    output reg  [15:0] q
);

    // 1024 posições de 8 bits (ajuste para seu caso)
    reg [15:0] mem [0:783];

    // Inicializa a memória a partir de arquivo hex
    initial begin
        $readmemh("/home/duda/Documents/Test_verilog/Modulos/imagem/imagem_8.hex", mem); 
    end

    // Leitura síncrona
    always @(posedge outclock) begin
        q <= mem[address];
    end

    // Escrita (não usada aqui, mas incluída para compatibilidade)
    always @(posedge inclock) begin
        if (wren)
            mem[address] <= data;
    end

endmodule