`timescale 1ns/1ps

module tb_argmax;

    reg clk;
    reg reset;
    reg start;
    reg signed [15:0] y_in;
    reg [3:0] idx;

    reg signed [15:0] max_real;  // valor real máximo esperado
    reg [3:0] pred_real;         // índice do valor máximo esperado

    wire [3:0] pred;
    wire done;

    // Instância do módulo
    argmax uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .y_in(y_in),
        .idx(idx),
        .pred(pred),
        .done(done)
    );

    // Clock de 10 ns
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        reset = 1;
        start = 0;
        y_in = 0;
        idx = 0;
        max_real = -32768; // menor valor possível
        pred_real = 0;
        #20;

        reset = 0;

        start = 1;

        y_in = 16'sd10; idx = 4'd0; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd20; idx = 4'd1; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd15; idx = 4'd2; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd25; idx = 4'd3; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd5;  idx = 4'd4; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd30; idx = 4'd5; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd28; idx = 4'd6; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd30; idx = 4'd7; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd18; idx = 4'd8; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end
        y_in = 16'sd12; idx = 4'd9; #10; if (y_in > max_real) begin max_real = y_in; pred_real = idx; end

        start = 0;
        #20;

        $display("\n--- RESULTADO FINAL ---");
        $display("Pred módulo argmax: %d", pred);
        $display("Índice real esperado: %d", pred_real);
        $display("Valor máximo real: %d", max_real);
        $display("done = %b", done);

        $stop;
    end

    initial begin
        $monitor("idx= %d \t y_in= %d \t pred_mod= %d \t done= %b", 
                 idx, y_in, pred, done);
    end

endmodule