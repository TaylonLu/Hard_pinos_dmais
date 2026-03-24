module mac (

    input wire clk,
    input wire reset,
    input wire start,

    input wire signed [15:0] pixel, // Q4.12
    input wire signed [15:0] peso,  // Q4.12
    input wire signed [15:0] bias,  // Q4.12

    output reg [9:0] addr,   // 0 a 783
    output reg done,

    output reg signed [15:0] saida // Q4.12

);

// acumulador maior = mais precisão
reg signed [39:0] acumulador;   // Q8.24 com margem extra
wire signed [31:0] produto;     // Q8.24
wire signed [39:0] produto_ext;
wire signed [39:0] bias_ext;

// resultado antes da saturação
reg signed [39:0] soma_final;
reg signed [27:0] resultado_shift; // após >>12

// multiplicação
assign produto = pixel * peso;

// extensão para evitar overflow
assign produto_ext = {{8{produto[31]}}, produto};

// alinhar bias para Q8.24 e depois estender
assign bias_ext = {{12{bias[15]}}, bias, 12'b0};

// limites Q4.12
localparam signed [15:0] MAX_Q412 = 16'sh7FFF;
localparam signed [15:0] MIN_Q412 = 16'sh8000;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        addr <= 0;
        acumulador <= 0;
        done <= 0;
        saida <= 0;

    end else begin
        if (start) begin

            // acumulação normal
            acumulador <= acumulador + produto_ext;

            // último pixel
            if (addr == 783) begin

                // soma final com bias
                soma_final <= acumulador + produto_ext + bias_ext;

                // converte Q8.24 → Q4.12
                resultado_shift <= (acumulador + produto_ext + bias_ext) >>> 12;

                // SATURAÇÃO
                if (resultado_shift[27:16] != {12{resultado_shift[15]}}) begin
                    if (resultado_shift[27] == 0)
                        saida <= MAX_Q412;
                    else
                        saida <= MIN_Q412;
                end else begin
                    saida <= resultado_shift[15:0];
                end

                done <= 1;
                addr <= 0;
                acumulador <= 0; // limpa para próximo neurônio

            end else begin
                addr <= addr + 1;
                done <= 0;
            end

        end else begin
            done <= 0;
        end
    end
end

endmodule