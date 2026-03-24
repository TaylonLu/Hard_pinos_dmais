`timescale 1ns/1ps

module tb_elm;

// ---------------------------------------------------------------------------
// 1. TESTBENCH: ativacao_sigmoid
// ---------------------------------------------------------------------------
reg  signed [15:0] sig_in;
wire signed [15:0] sig_out;

ativacao u_sig (
    .d_in  (sig_in),
    .d_out (sig_out)
);

// Valores de referência em Q4.12 (x256 = 1.0 → 0x0100)
// sigma(0)   = 0.5000 → 0x0080
// sigma(1)   = 0.7311 → ~0x00BB
// sigma(2)   = 0.8808 → ~0x00E1
// sigma(3)   = 0.9526 → ~0x00F3
// sigma(6)   = ~1.0   → 0x0100  (saturação)
// sigma(-1)  = 0.2689 → ~0x0045  (simetria)
// sigma(-6)  = ~0.0   → 0x0000  (saturação negativa)

integer sig_errors;

task check_sigmoid;
    input signed [15:0] in_val;
    input signed [15:0] exp_val;
    input signed [15:0] tol;
    input [127:0] label; // não usado diretamente — apenas para organização
    reg signed [15:0] diff;
    begin
        sig_in = in_val;
        #1;
        diff = sig_out - exp_val;
        if (diff < 0) diff = -diff;
        if (diff > tol) begin
            $display("FAIL sigmoid(0x%04X): got 0x%04X, exp ~0x%04X (tol %0d)",
                     in_val, sig_out, exp_val, tol);
            sig_errors = sig_errors + 1;
        end else begin
            $display("PASS sigmoid(0x%04X) = 0x%04X  (exp ~0x%04X)",
                     in_val, sig_out, exp_val);
        end
    end
endtask

// ---------------------------------------------------------------------------
// 2. TESTBENCH: mac
// ---------------------------------------------------------------------------
reg        clk, reset_mac, start_mac;
reg  signed [15:0] mac_pixel, mac_peso, mac_bias;
wire [9:0]  mac_addr;
wire        mac_done;
wire signed [15:0] mac_saida;

mac u_mac (
    .clk   (clk),
    .reset (reset_mac),
    .start (start_mac),
    .pixel (mac_pixel),
    .peso  (mac_peso),
    .bias  (mac_bias),
    .addr  (mac_addr),
    .done  (mac_done),
    .saida (mac_saida)
);

// Clock 10 ns
initial clk = 0;
always #5 clk = ~clk;

integer mac_errors;

// ---------------------------------------------------------------------------
// 3. TESTBENCH: argmax
// ---------------------------------------------------------------------------
reg        rst_arg, start_arg;
reg  signed [15:0] y_in_arg;
reg  [3:0]  idx_arg;
wire [3:0]  pred_arg;
wire        done_arg;

argmax u_arg (
    .clk   (clk),
    .reset (rst_arg),
    .start (start_arg),
    .y_in  (y_in_arg),
    .idx   (idx_arg),
    .pred  (pred_arg),
    .done  (done_arg)
);

integer arg_errors;

// ---------------------------------------------------------------------------
// TAREFA AUXILIAR: reset_mac_task
// ---------------------------------------------------------------------------
task do_reset_mac;
    begin
        reset_mac = 1;
        start_mac = 0;
        @(posedge clk); #1;
        reset_mac = 0;
    end
endtask

// ---------------------------------------------------------------------------
// TAREFA: roda mac por 784 ciclos com pixel e peso fixos, verifica resultado
// ---------------------------------------------------------------------------
task run_mac_fixed;
    input signed [15:0] pix;
    input signed [15:0] wt;
    input signed [15:0] bs;
    input signed [15:0] exp;
    input signed [15:0] tol;
    integer cyc;
    reg signed [15:0] diff;
    begin
        do_reset_mac;
        mac_pixel = pix;
        mac_peso  = wt;
        mac_bias  = bs;
        start_mac = 1;
        // alimenta 784 ciclos
        for (cyc = 0; cyc < 784; cyc = cyc + 1)
            @(posedge clk);
        #1; // propaga
        start_mac = 0;
        @(posedge clk); #1;
        diff = mac_saida - exp;
        if (diff < 0) diff = -diff;
        if (diff > tol) begin
            $display("FAIL mac(pix=0x%04X w=0x%04X b=0x%04X): got=0x%04X exp~0x%04X tol=%0d",
                     pix, wt, bs, mac_saida, exp, tol);
            mac_errors = mac_errors + 1;
        end else begin
            $display("PASS mac(pix=0x%04X w=0x%04X b=0x%04X) = 0x%04X (exp~0x%04X)",
                     pix, wt, bs, mac_saida, exp);
        end
    end
endtask

// ---------------------------------------------------------------------------
// SEQUÊNCIA PRINCIPAL
// ---------------------------------------------------------------------------
integer i;
reg signed [15:0] vals [0:9];
reg signed [15:0] diff_v;
reg signed [15:0] pos_val;

initial begin
    $dumpfile("tb_elm.vcd");
    $dumpvars(0, tb_elm);

    // -----------------------------------------------------------------------
    // BLOCO 1: ativacao_sigmoid
    // -----------------------------------------------------------------------
    $display("\n=== ativacao_sigmoid ===");
    sig_errors = 0;
    sig_in = 0;

    // sigma(0)  = 0.5 → 0x0080, tolerância 2 LSB
    check_sigmoid(16'h0000, 16'h0080, 16'd3,  "sigma(0)");

    // sigma(0.5) em Q4.12: 0.5*256=0x0080 → saída ~0x009F
    check_sigmoid(16'h0080, 16'h009F, 16'd4,  "sigma(0.5)");

    // sigma(1.0): 1*256=0x0100 → ~0x00BB
    check_sigmoid(16'h0100, 16'h00BB, 16'd4,  "sigma(1.0)");

    // sigma(2.0): 2*256=0x0200 → ~0x00E1
    check_sigmoid(16'h0200, 16'h00E1, 16'd4,  "sigma(2.0)");

    // sigma(3.0): 3*256=0x0300 → ~0x00F3
    check_sigmoid(16'h0300, 16'h00F3, 16'd4,  "sigma(3.0)");

    // sigma(6.0): saturação → 0x0100
    check_sigmoid(16'h0600, 16'h0100, 16'd2,  "sigma(6.0 sat)");

    // sigma(-1.0) = 1-sigma(1) → ~ONE-0x00BB = 0x0045
    check_sigmoid(-16'sh0100, 16'sh0045, 16'd4, "sigma(-1.0)");

    // sigma(-6.0): saturação negativa → ~0x0000
    check_sigmoid(-16'sh0600, 16'h0000, 16'd2,  "sigma(-6.0 sat)");

    // simetria: sigma(x) + sigma(-x) deve ser ~ONE para qualquer x
    sig_in = 16'h0180; #1;

    begin
        pos_val = sig_out;
        sig_in  = -16'sh0180; #1;
        diff_v = pos_val + sig_out - 16'h0100;
        if (diff_v < 0) diff_v = -diff_v;
        if (diff_v > 2)
            $display("FAIL simetria (1.5): pos+neg=0x%04X (exp=0x0100)", pos_val+sig_out);
        else
            $display("PASS simetria (1.5): pos+neg=0x%04X", pos_val+sig_out);
    end

    if (sig_errors == 0)
        $display(">>> ativacao_sigmoid: TODOS OS TESTES PASSARAM");
    else
        $display(">>> ativacao_sigmoid: %0d FALHA(S)", sig_errors);

    // -----------------------------------------------------------------------
    // BLOCO 2: mac
    // -----------------------------------------------------------------------
    $display("\n=== mac ===");
    mac_errors = 0;
    reset_mac  = 1;
    start_mac  = 0;
    mac_pixel  = 0;
    mac_peso   = 0;
    mac_bias   = 0;
    @(posedge clk); @(posedge clk);
    reset_mac = 0;

    // Teste 2a: pixel=0, peso=qualquer, bias=0 → saida=0
    // pixel Q4.12: 0 = 0x0000; peso = 0x1000 (1.0); bias=0
    run_mac_fixed(16'h0000, 16'h1000, 16'h0000,
                  16'h0000, 16'd4);

    // Teste 2b: pixel=1.0 (0x1000), peso=1.0 (0x1000), bias=0
    // acc = 784 * (1<<12)*(1<<12) >> 12 = 784 * 4096 = 3211264 em Q8.24
    // resultado_shift = acc >> 12 = 784 em Q4.12 → satura em 0x7FFF
    run_mac_fixed(16'h1000, 16'h1000, 16'h0000,
                  16'sh7FFF, 16'd1);

    // Teste 2c: pequeno produto sem saturação
    // pixel=0.125 (0x0200 em Q4.12), peso=0.125 (0x0200), bias=0
    // produto = 0x0200*0x0200 = 0x40000 → Q8.24
    // acc = 784 * 0x40000 = 784 * 262144 = 205,520,896
    // >>12 = 50176 = 0xC400 → satura em 0x7FFF
    run_mac_fixed(16'h0200, 16'h0200, 16'h0000,
                  16'sh7FFF, 16'd1);

    // Teste 2d: valores negativos — pixel=-1, peso=1, bias=0 → resultado negativo, satura MIN
    run_mac_fixed(-16'sh1000, 16'h1000, 16'h0000,
                  16'sh8000, 16'd1);

    // Teste 2e: bias positivo sozinho (pixel=0, peso=0, bias=1.0=0x1000)
    // acc=0, soma_final = bias_ext = 0x1000<<12 = 0x1000_000
    // >>12 = 0x1000 (4096 decimal) → satura 0x7FFF
    run_mac_fixed(16'h0000, 16'h0000, 16'h1000,
                16'h1000, 16'd1);

    // Teste 2f: resultado exato pequeno — pixel & peso muito pequenos, bias=0
    // Usa pixel=0 (resultado do mac=0+bias=0)
    run_mac_fixed(16'h0000, 16'h0000, 16'h0000,
                  16'h0000, 16'd1);

    if (mac_errors == 0)
        $display(">>> mac: TODOS OS TESTES PASSARAM");
    else
        $display(">>> mac: %0d FALHA(S)", mac_errors);

    // -----------------------------------------------------------------------
    // BLOCO 3: argmax
    // -----------------------------------------------------------------------
    $display("\n=== argmax ===");
    arg_errors = 0;
    rst_arg    = 1;
    start_arg  = 0;
    y_in_arg   = 0;
    idx_arg    = 0;
    @(posedge clk); #1;
    rst_arg = 0;

    // Caso 3a: máximo na classe 0
    vals[0] = 16'sh0500;
    vals[1] = 16'sh0100;
    vals[2] = 16'sh0200;
    vals[3] = 16'sh0050;
    vals[4] = 16'sh0010;
    vals[5] = 16'sh0020;
    vals[6] = 16'sh0030;
    vals[7] = 16'sh0015;
    vals[8] = 16'sh0005;
    vals[9] = 16'sh0001;

    start_arg = 1;
    for (i = 0; i < 10; i = i + 1) begin
        y_in_arg = vals[i];
        idx_arg  = i[3:0];
        @(posedge clk); #1;
    end
    start_arg = 0;
    @(posedge clk); #1;

    if (pred_arg !== 4'd0) begin
        $display("FAIL argmax caso A: pred=%0d (exp=0)", pred_arg);
        arg_errors = arg_errors + 1;
    end else
        $display("PASS argmax caso A: pred=%0d (max na classe 0)", pred_arg);

    if (!done_arg)
        $display("FAIL argmax done não asserted no fim");
    else
        $display("PASS argmax done asserted corretamente");

    // Caso 3b: máximo na classe 7 — reset e novo ciclo
    rst_arg = 1; @(posedge clk); #1; rst_arg = 0;

    vals[0] = 16'sh0010;
    vals[1] = 16'sh0020;
    vals[2] = 16'sh0030;
    vals[3] = 16'sh0040;
    vals[4] = 16'sh0050;
    vals[5] = 16'sh0060;
    vals[6] = 16'sh0070;
    vals[7] = 16'sh0FFF;  // <-- máximo
    vals[8] = 16'sh0080;
    vals[9] = 16'sh0090;

    start_arg = 1;
    for (i = 0; i < 10; i = i + 1) begin
        y_in_arg = vals[i];
        idx_arg  = i[3:0];
        @(posedge clk); #1;
    end
    start_arg = 0;
    @(posedge clk); #1;

    if (pred_arg !== 4'd7) begin
        $display("FAIL argmax caso B: pred=%0d (exp=7)", pred_arg);
        arg_errors = arg_errors + 1;
    end else
        $display("PASS argmax caso B: pred=%0d (max na classe 7)", pred_arg);

    // Caso 3c: máximo na classe 9 (último)
    rst_arg = 1; @(posedge clk); #1; rst_arg = 0;

    vals[0] = 16'sh0001;
    vals[1] = 16'sh0002;
    vals[2] = 16'sh0003;
    vals[3] = 16'sh0004;
    vals[4] = 16'sh0005;
    vals[5] = 16'sh0006;
    vals[6] = 16'sh0007;
    vals[7] = 16'sh0008;
    vals[8] = 16'sh0009;
    vals[9] = 16'sh7FFF;  // <-- máximo

    start_arg = 1;
    for (i = 0; i < 10; i = i + 1) begin
        y_in_arg = vals[i];
        idx_arg  = i[3:0];
        @(posedge clk); #1;
    end
    start_arg = 0;
    @(posedge clk); #1;

    if (pred_arg !== 4'd9) begin
        $display("FAIL argmax caso C: pred=%0d (exp=9)", pred_arg);
        arg_errors = arg_errors + 1;
    end else
        $display("PASS argmax caso C: pred=%0d (max na classe 9)", pred_arg);

    // Caso 3d: todos iguais — deve ficar na classe 0 (primeiro a entrar)
    rst_arg = 1; @(posedge clk); #1; rst_arg = 0;

    start_arg = 1;
    for (i = 0; i < 10; i = i + 1) begin
        y_in_arg = 16'sh0100;   // todos iguais
        idx_arg  = i[3:0];
        @(posedge clk); #1;
    end
    start_arg = 0;
    @(posedge clk); #1;

    if (pred_arg !== 4'd0) begin
        $display("FAIL argmax caso D (empate): pred=%0d (exp=0)", pred_arg);
        arg_errors = arg_errors + 1;
    end else
        $display("PASS argmax caso D (empate): pred=%0d (classe 0)", pred_arg);

    // Caso 3e: valor negativo — deve ignorar e ficar no mínimo inicial (classe 0 se único)
    rst_arg = 1; @(posedge clk); #1; rst_arg = 0;

    start_arg = 1;
    for (i = 0; i < 10; i = i + 1) begin
        y_in_arg = -16'sh0100;  // todos negativos
        idx_arg  = i[3:0];
        @(posedge clk); #1;
    end
    start_arg = 0;
    @(posedge clk); #1;
    // Nenhum supera max_val=0x8000, então pred mantém 0 (reset)
    $display("INFO argmax caso E (todos neg): pred=%0d (qualquer é válido aqui)", pred_arg);

    if (arg_errors == 0)
        $display(">>> argmax: TODOS OS TESTES PASSARAM");
    else
        $display(">>> argmax: %0d FALHA(S)", arg_errors);

    // -----------------------------------------------------------------------
    // SUMÁRIO
    // -----------------------------------------------------------------------
    $display("\n============================");
    $display(" SUMÁRIO FINAL");
    $display("============================");
    $display(" ativacao_sigmoid : %s (%0d erros)",
             (sig_errors==0) ? "OK" : "FALHA", sig_errors);
    $display(" mac              : %s (%0d erros)",
             (mac_errors==0) ? "OK" : "FALHA", mac_errors);
    $display(" argmax           : %s (%0d erros)",
             (arg_errors==0) ? "OK" : "FALHA", arg_errors);
    $display("============================\n");

    $finish;
end

// Timeout de segurança (100.000 ciclos)
initial begin
    #1_000_000;
    $display("TIMEOUT — simulação encerrada forçadamente");
    $finish;
end

endmodule