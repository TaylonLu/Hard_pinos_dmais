`timescale 1ns/1ps

module tb_mac;

// ─── sinais ───────────────────────────────────────────────────────────────────
reg         clk, reset, start;
reg  signed [15:0] pixel, peso, bias;
wire [9:0]  addr;
wire        done;
wire signed [15:0] saida;

// ─── instância ────────────────────────────────────────────────────────────────
mac uut (
    .clk   (clk),
    .reset (reset),
    .start (start),
    .pixel (pixel),
    .peso  (peso),
    .bias  (bias),
    .addr  (addr),
    .done  (done),
    .saida (saida)
);

// ─── clock 10 ns ─────────────────────────────────────────────────────────────
always #5 clk = ~clk;

// ─── conversão Q4.12 ─────────────────────────────────────────────────────────
function signed [15:0] to_q412;
    input real v;
    begin
        to_q412 = $rtoi(v * 4096.0);
    end
endfunction

function real from_q412;
    input signed [15:0] v;
    begin
        from_q412 = $itor(v) / 4096.0;
    end
endfunction

// ─── calcula esperado com os valores ja quantizados ──────────────────────────
// replica exatamente a logica do hardware para ter referencia correta
function real calc_esperado;
    input signed [15:0] pix_q;
    input signed [15:0] pes_q;
    input signed [15:0] bia_q;
    reg   signed [39:0] acum;
    reg   signed [31:0] prod;
    reg   signed [39:0] prod_ext, bias_ext, soma;
    reg   signed [27:0] shift;
    reg   signed [15:0] resultado;   // ← add this
    integer k;
    begin
        acum     = 0;
        prod     = pix_q * pes_q;
        prod_ext = {{8{prod[31]}}, prod};
        bias_ext = {{12{bia_q[15]}}, bia_q, 12'b0};

        for (k = 0; k < 784; k = k + 1)
            acum = acum + prod_ext;

        soma  = acum + bias_ext;
        shift = soma >>> 12;

        if (shift[27:16] != {12{shift[15]}}) begin
            if (shift[27] == 0)
                calc_esperado = $itor(16'sh7FFF) / 4096.0;
            else
                calc_esperado = $itor(16'sh8000) / 4096.0;
        end else begin
            resultado     = shift[15:0];         
            calc_esperado = $itor(resultado) / 4096.0;  
        end
    end
endfunction

// ─── variáveis de controle ───────────────────────────────────────────────────
integer passou, falhou;
real    esperado, erro;

// ─── task: roda um neurônio completo ─────────────────────────────────────────
task roda_neuronio;
    input real    pix_r;
    input real    pes_r;
    input real    bia_r;
    input [255:0] nome;
    reg signed [15:0] pix_q, pes_q, bia_q;
    begin
        pix_q = to_q412(pix_r);
        pes_q = to_q412(pes_r);
        bia_q = to_q412(bia_r);

        pixel = pix_q;
        peso  = pes_q;
        bias  = bia_q;

        // esperado calculado com os mesmos bits que o hardware usa
        esperado = calc_esperado(pix_q, pes_q, bia_q);

        @(negedge clk);
        start = 1;

        wait (done == 1);
        @(negedge clk);
        start = 0;

        wait (done == 0);

        erro = from_q412(saida) - esperado;
        if (erro < 0) erro = -erro;

        if (erro < 0.005) begin
            $display("PASS | %-34s | saida=%9.6f  esperado=%9.6f  erro=%f",
                     nome, from_q412(saida), esperado, erro);
            passou = passou + 1;
        end else begin
            $display("FAIL | %-34s | saida=%9.6f  esperado=%9.6f  erro=%f  <---",
                     nome, from_q412(saida), esperado, erro);
            falhou = falhou + 1;
        end
    end
endtask

// ─── estímulos ────────────────────────────────────────────────────────────────
initial begin
    $dumpfile("tb_mac.vcd");
    $dumpvars(0, tb_mac);

    clk    = 0;
    reset  = 1;
    start  = 0;
    pixel  = 0;
    peso   = 0;
    bias   = 0;
    passou = 0;
    falhou = 0;

    repeat(4) @(posedge clk);
    reset = 0;
    @(negedge clk);

    $display("──────────────────────────────────────────────────────────────────────────────");
    $display("Testbench MAC  (Q4.12)  —  esperado calculado com valores quantizados");
    $display("──────────────────────────────────────────────────────────────────────────────");

    // 1 — zero absoluto
    roda_neuronio( 0.0,    0.0,   0.0,    "Tudo zero");

    // 2 — saturacao positiva: 784*(1*1) >> MAX
    roda_neuronio( 1.0,    1.0,   0.0,    "Saturacao positiva");

    // 3 — saturacao negativa: 784*(-1*1) << MIN
    roda_neuronio(-1.0,    1.0,   0.0,    "Saturacao negativa");

    // 4 — acumulacao pequena sem saturar
    roda_neuronio( 0.001,  1.0,   0.0,    "Acumulacao pequena (pix=0.001)");

    // 5 — somente bias positivo
    roda_neuronio( 0.0,    0.0,   1.0,    "Somente bias +1.0");

    // 6 — somente bias negativo
    roda_neuronio( 0.0,    0.0,  -1.0,    "Somente bias -1.0");

    // 7 — produto fracionario satura
    roda_neuronio( 0.5,    0.5,   0.0,    "Frac 0.5x0.5 satura");

    // 8 — pesos tipicos de rede neural
    roda_neuronio( 1.0,    0.002, 0.1,    "Pesos pequenos (pes=0.002 bia=0.1)");

    // 9 — negativo com bias que compensa parcialmente
    roda_neuronio(-0.5,    0.01,  3.0,    "Negativo + bias compensador");

    // 10/11 — dois neuronios consecutivos (verifica limpeza do acumulador)
    roda_neuronio( 0.001,  1.0,   0.0,    "Neuronio A consecutivo");
    roda_neuronio( 0.002,  1.0,   0.0,    "Neuronio B consecutivo");

    // 12 — bias grande domina pixel minusculo
    roda_neuronio( 0.0001, 0.0001, 2.5,   "Bias domina pixel minusculo");

    // 13 — cancelamento: acumulacao ~ -bias
    roda_neuronio( 0.01,   0.01, -0.0784, "Cancelamento pixel+bias ~0");

    $display("──────────────────────────────────────────────────────────────────────────────");
    $display("Resultado: %0d PASS  |  %0d FAIL", passou, falhou);
    $display("──────────────────────────────────────────────────────────────────────────────");

    $finish;
end

// ─── timeout de segurança ─────────────────────────────────────────────────────
initial begin
    #8_000_000;
    $display("TIMEOUT — simulacao travada!");
    $finish;
end

endmodule