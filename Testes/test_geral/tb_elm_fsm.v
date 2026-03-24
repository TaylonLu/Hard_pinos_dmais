// =============================================================================
// tb_elm_fsm.v — Testbench integrado: elm_fsm + mac + sigmoid + argmax
//
// Compilar:
//   iverilog -o tb_elm_fsm tb_elm_fsm.v elm_fsm.v mac.v ativacao_sigmoid.v argmax.v
// Simular:
//   vvp tb_elm_fsm
// =============================================================================
`timescale 1ns/1ps

module tb_elm_fsm;

    localparam N_HIDDEN  = 4;
    localparam N_CLASSES = 10;
    localparam IMG_SIZE  = 784;

    reg  clk, rst_n, start;
    wire done;
    wire [3:0] pred;

    reg  [7:0]         mem_image  [0:IMG_SIZE-1];
    reg  signed [15:0] mem_win    [0:N_HIDDEN*IMG_SIZE-1];
    reg  signed [15:0] mem_bias   [0:N_HIDDEN-1];
    reg  signed [15:0] mem_beta   [0:N_CLASSES*N_HIDDEN-1];
    reg  signed [15:0] mem_hidden [0:N_HIDDEN-1];
    reg  signed [15:0] mem_output [0:N_CLASSES-1];

    wire [9:0]  img_addr;
    wire [17:0] win_addr;
    wire [7:0]  bias_addr;
    wire [17:0] beta_addr;
    wire [7:0]  hid_wr_addr, hid_rd_addr;
    wire signed [15:0] hid_wr_data;
    wire        hid_wr_en;
    wire [3:0]  out_wr_addr;
    wire signed [15:0] out_wr_data;
    wire        out_wr_en;

    wire [7:0]         img_data    = mem_image[img_addr];
    wire signed [15:0] win_data    = mem_win[win_addr];
    wire signed [15:0] bias_data   = mem_bias[bias_addr];
    wire signed [15:0] beta_data   = mem_beta[beta_addr];
    wire signed [15:0] hid_rd_data = mem_hidden[hid_rd_addr];

    wire        mac_reset_w, mac_start_w, mac_done_w;
    wire [9:0]  mac_len_w, mac_addr_w;
    wire signed [15:0] mac_pixel_w, mac_peso_w, mac_bias_w, mac_saida_w;
    wire signed [15:0] sig_in_w, sig_out_w;
    wire        arg_reset_w, arg_start_w, arg_done_w;
    wire [3:0]  arg_idx_w, arg_pred_w;
    wire signed [15:0] arg_y_in_w;

    elm_fsm  u_fsm(
        .clk(clk),.rst_n(rst_n),.start(start),.done(done),.pred(pred),
        .img_addr(img_addr),.img_data(img_data),
        .win_addr(win_addr),.win_data(win_data),
        .bias_addr(bias_addr),.bias_data(bias_data),
        .beta_addr(beta_addr),.beta_data(beta_data),
        .hid_wr_addr(hid_wr_addr),.hid_wr_data(hid_wr_data),.hid_wr_en(hid_wr_en),
        .hid_rd_addr(hid_rd_addr),.hid_rd_data(hid_rd_data),
        .out_wr_addr(out_wr_addr),.out_wr_data(out_wr_data),.out_wr_en(out_wr_en),
        .mac_reset(mac_reset_w),.mac_start(mac_start_w),
        .mac_pixel(mac_pixel_w),.mac_peso(mac_peso_w),.mac_bias(mac_bias_w),
        .mac_addr(mac_addr_w),.mac_done(mac_done_w),.mac_saida(mac_saida_w),
        .sig_in(sig_in_w),.sig_out(sig_out_w),
        .arg_reset(arg_reset_w),.arg_start(arg_start_w),.arg_y_in(arg_y_in_w),
        .arg_idx(arg_idx_w),.arg_pred(arg_pred_w),.arg_done(arg_done_w)
    );

    mac u_mac (
        .clk(clk),.reset(mac_reset_w),.start(mac_start_w),
        .pixel(mac_pixel_w),.peso(mac_peso_w),.bias(mac_bias_w),
        .addr(mac_addr_w),.done(mac_done_w),.saida(mac_saida_w)
    );

    ativacao u_sig (.d_in(sig_in_w),.d_out(sig_out_w));

    argmax u_arg (
        .clk(clk),.reset(arg_reset_w),.start(arg_start_w),
        .y_in(arg_y_in_w),.idx(arg_idx_w),.pred(arg_pred_w),.done(arg_done_w)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (hid_wr_en) mem_hidden[hid_wr_addr] <= hid_wr_data;
        if (out_wr_en) mem_output[out_wr_addr]  <= out_wr_data;
    end

    task do_reset;
        begin
            rst_n = 0; start = 0;
            repeat(3) @(posedge clk);
            #1; rst_n = 1;
            @(posedge clk);
        end
    endtask

    task pulse_start;
        begin
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
        end
    endtask

    localparam MAX_CYC = 100_000;

    integer cyc_count;
    task wait_done;
        begin
            cyc_count = 0;
            while (!done && cyc_count < MAX_CYC) begin
                @(posedge clk); #1; cyc_count = cyc_count + 1;
            end
            if (!done) begin
                $display("  TIMEOUT apos %0d ciclos (max=%0d)", cyc_count, MAX_CYC);
                $finish;
            end else
                $display("  done em %0d ciclos", cyc_count);
        end
    endtask

    integer n, p, c, k;

    task load_test_a;
        begin
            for (p=0;p<IMG_SIZE;p=p+1)  mem_image[p] = 8'd0;
            for (n=0;n<N_HIDDEN;n=n+1)
                for (p=0;p<IMG_SIZE;p=p+1) mem_win[n*IMG_SIZE+p] = 16'sh0000;
            for (n=0;n<N_HIDDEN;n=n+1)  mem_bias[n] = 16'sh0000;
            for (c=0;c<N_CLASSES;c=c+1)
                for (k=0;k<N_HIDDEN;k=k+1) mem_beta[c*N_HIDDEN+k] = 16'sh0000;
        end
    endtask

    task load_test_b;  // pred esperado = 7
        begin
            for (p=0;p<IMG_SIZE;p=p+1)  mem_image[p] = 8'd128;
            for (n=0;n<N_HIDDEN;n=n+1)
                for (p=0;p<IMG_SIZE;p=p+1) mem_win[n*IMG_SIZE+p] = 16'sh0000;
            for (n=0;n<N_HIDDEN;n=n+1)  mem_bias[n] = 16'sh0100;
            for (c=0;c<N_CLASSES;c=c+1)
                for (k=0;k<N_HIDDEN;k=k+1) mem_beta[c*N_HIDDEN+k] = 16'sh0000;
            for (k=0;k<N_HIDDEN;k=k+1) mem_beta[7*N_HIDDEN+k] = 16'sh0100;
        end
    endtask

    task load_test_c;  // pred esperado = 3
        begin
            for (p=0;p<IMG_SIZE;p=p+1)  mem_image[p] = 8'd64;
            for (n=0;n<N_HIDDEN;n=n+1)
                for (p=0;p<IMG_SIZE;p=p+1) mem_win[n*IMG_SIZE+p] = 16'sh0000;
            for (n=0;n<N_HIDDEN;n=n+1)  mem_bias[n] = 16'sh0100;
            for (c=0;c<N_CLASSES;c=c+1)
                for (k=0;k<N_HIDDEN;k=k+1) mem_beta[c*N_HIDDEN+k] = 16'sh0000;
            for (k=0;k<N_HIDDEN;k=k+1) mem_beta[3*N_HIDDEN+k] = 16'sh0100;
        end
    endtask

    integer errors;
    reg [3:0] pred_cap;

    initial begin
        $dumpfile("tb_elm_fsm.vcd");
        $dumpvars(0, tb_elm_fsm);
        errors = 0;

        $display("\n=== Teste A: pesos zero, bias zero ===");
        load_test_a; do_reset; pulse_start; wait_done;
        $display("  pred=%0d (qualquer valor OK — scores iguais)", pred);
        $display("  PASS Teste A");

        $display("\n=== Teste B: pred esperado = 7 ===");
        load_test_b; do_reset; pulse_start; wait_done;
        pred_cap = pred;
        @(posedge clk); #1;
        if (pred_cap !== 4'd7) begin
            $display("  FAIL: pred=%0d (esperado=7)", pred_cap); errors=errors+1;
        end else $display("  PASS: pred=%0d", pred_cap);

        $display("\n=== Teste C: pred esperado = 3 ===");
        load_test_c; do_reset; pulse_start; wait_done;
        pred_cap = pred;
        @(posedge clk); #1;
        if (pred_cap !== 4'd3) begin
            $display("  FAIL: pred=%0d (esperado=3)", pred_cap); errors=errors+1;
        end else $display("  PASS: pred=%0d", pred_cap);

        $display("\n=== Teste D: re-execucao sem reset (pred=7) ===");
        load_test_b;
        repeat(3) @(posedge clk); // espera IDLE
        pulse_start; wait_done;
        pred_cap = pred;
        @(posedge clk); #1;
        if (pred_cap !== 4'd7) begin
            $display("  FAIL: pred=%0d (esperado=7)", pred_cap); errors=errors+1;
        end else $display("  PASS: pred=%0d", pred_cap);

        $display("\n============================");
        $display(" SUMARIO FSM");
        $display("============================");
        if (errors==0) $display(" TODOS OS TESTES PASSARAM");
        else           $display(" %0d FALHA(S)", errors);
        $display("============================\n");
        $finish;
    end

    initial begin #200_000_000; $display("TIMEOUT GLOBAL"); $finish; end

endmodule