
module mac (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire signed [15:0] pixel,
    input  wire signed [15:0] peso,
    input  wire signed [15:0] bias,
    input  wire [9:0]  n_ops,
    input  wire [4:0]  shift,   
    output reg  [9:0]  addr,
    output reg         done,
    output reg  signed [15:0] saida
);


    reg  signed [31:0] acumulador;
    wire signed [31:0] produto = pixel * peso;
    wire signed [31:0] saida_normalizada = (acumulador + produto + bias) >>> shift;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            addr       <= 0;
            acumulador <= 0;
            saida      <= 0;
            done       <= 0;
        end else begin
            if (done) begin
                if (!start) begin
                    done       <= 0;
                    acumulador <= 0;
                    addr       <= 0;
                end
            end else if (start) begin
                acumulador <= acumulador + produto;
                if (addr == n_ops - 1) begin
                    saida <= saida_normalizada[15:0];
                    done  <= 1;
                end else begin
                    addr <= addr + 1;
                end
            end
            
        end
    end
endmodule



/*
module mac (
    input  wire clk,
    input  wire reset,
    input  wire start,
    input  wire signed [15:0] pixel,
    input  wire signed [15:0] peso,
    input  wire signed [15:0] bias,
    output reg  [9:0]          addr,
    output reg                 done,
    output reg  signed [15:0]  saida
);

reg signed [39:0] acumulador;

wire signed [31:0] produto       = pixel * peso;
wire signed [39:0] produto_ext   = {{8{produto[31]}}, produto};
wire signed [39:0] bias_ext      = {{12{bias[15]}}, bias, 12'b0};


wire signed [39:0] acum_completo    = acumulador + produto_ext;
wire signed [39:0] soma_final_w     = acum_completo + bias_ext;
wire signed [27:0] resultado_shift_w = soma_final_w[39:12];

localparam signed [15:0] MAX_Q412 = 16'sh7FFF;
localparam signed [15:0] MIN_Q412 = 16'sh8000;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        addr        <= 0;
        acumulador  <= 0;
        done        <= 0;
        saida       <= 0;
    end else begin
        if (done) begin
            // aguarda start descer antes de aceitar novo neurônio
            if (!start) begin
                done       <= 0;
                acumulador <= 0;
                addr       <= 0;
            end
        end else if (start) begin
            if (addr == 783) begin
                // saturação com valor correto no mesmo ciclo
                if (resultado_shift_w[27:16] != {12{resultado_shift_w[15]}})
                    saida <= resultado_shift_w[27] ? MIN_Q412 : MAX_Q412;
                else
                    saida <= resultado_shift_w[15:0];
                done <= 1;
                // acumulador e addr limpos só quando done cair (bloco acima)
            end else begin
                acumulador <= acum_completo;
                addr       <= addr + 1;
            end
        end
    end
end

endmodule

*/