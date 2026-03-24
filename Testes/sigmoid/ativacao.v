module ativacao (
    input wire signed [15:0] d_in,
    output reg signed [15:0] d_out
);
// aproxima a sigmoid com uso de varias retas y = ax + b
// conforme o intervalo do valor da entrada (limite)
// as constantes difinem o ponto inicial e controla a curvatura 
// com a simetria aplicada aos valores negativos

// Constantes para as retas de aproximação
localparam signed [15:0] ONE      = 16'h0100; // 1.0
localparam signed [15:0] ZERO     = 16'h0000; // 0.0


localparam signed [15:0] S0   = 16'h0080; // 0.0 = 0.5000
localparam signed [15:0] S0_5 = 16'h009F; // 0.5 ~ 0.6225
localparam signed [15:0] S1   = 16'h00BB; // 1.0 ~ 0.7311
localparam signed [15:0] S1_5 = 16'h00D1; // 1.5 ~ 0.8176
localparam signed [15:0] S2   = 16'h00E1; // 2.0 ~ 0.8808
localparam signed [15:0] S2_5 = 16'h00EC; // 2.5 ~ 0.9241
localparam signed [15:0] S3   = 16'h00F3; // 3.0 ~ 0.9526

// Limites 
localparam signed [15:0] L0_5 = 16'h0080; // 0.5
localparam signed [15:0] L1   = 16'h0100; // 1.0
localparam signed [15:0] L1_5 = 16'h0180; // 1.5
localparam signed [15:0] L2   = 16'h0200; // 2.0
localparam signed [15:0] L2_5 = 16'h0280; // 2.5
localparam signed [15:0] L3   = 16'h0300; // 3.0
localparam signed [15:0] L4_5 = 16'h0480; // 4.5

reg negativo;
reg signed [15:0] x;
reg signed [15:0] dx; // para o cálculo da reta (dx = x - limite)

always @(*) begin

    // Sinal e valor absoluto
    negativo = d_in[15];
    x = negativo ? -d_in : d_in;

    // Aproximação 
    if (x < L0_5) begin
        // Intervalo [0, 0.5): inclinação ~ 0.24 ~ (dx>>2) + (dx>>4)
        dx = x;
        d_out = S0 + (dx >>> 2) + (dx >>> 4);
    end
    else if (x < L1) begin
        // Intervalo [0.5, 1.0): inclinação ~ 0.22 ~ (dx>>2) + (dx>>5)
        dx = x - L0_5;
        d_out = S0_5 + (dx >>> 2) + (dx >>> 5);
    end
    else if (x < L1_5) begin
        // Intervalo [1.0, 1.5): inclinação ~ 0.17 ~ (dx>>3) + (dx>>4)
        dx = x - L1;
        d_out = S1 + (dx >>> 3) + (dx >>> 4);
    end
    else if (x < L2) begin
        // Intervalo [1.5, 2.0): inclinação ~ 0.13 ~ (dx>>3) + (dx>>5)
        dx = x - L1_5;
        d_out = S1_5 + (dx >>> 3) + (dx >>> 5);
    end
    else if (x < L2_5) begin
        // Intervalo [2.0, 2.5): inclinação ~ 0.09 ~ (dx>>4) - (dx>>6)  ≈ dx>>4
        dx = x - L2;
        d_out = S2 + (dx >>> 4);
    end
    else if (x < L3) begin
        // Intervalo [2.5, 3.0): inclinação ~ 0.06 ~ (dx>>4) + (dx>>6) ≈ dx>>4
        dx = x - L2_5;
        d_out = S2_5 + (dx >>> 4);
    end
    else if (x < L4_5) begin
        // Intervalo [3.0, 4.5): inclinação ~ 0.03 ~ dx>>5
        dx = x - L3;
        d_out = S3 + (dx >>> 5);
    end
    else begin
        // Saturação
        d_out = ONE;
    end
    
    // Simetria da sigmoid 
    if (negativo)
        d_out = ONE - d_out;

	// Força a ficar no intervalo
	// Se passou do máximo -> trava no máximo
    // Se passou do mínimo -> trava no mínimo
	if (d_out < ZERO)
        d_out = ZERO;
		  
    if (d_out > ONE)
        d_out = ONE;
	
end

endmodule