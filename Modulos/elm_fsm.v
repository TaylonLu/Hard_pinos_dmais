module elm_fsm (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    output reg  done,
    output reg  [3:0] pred,

    output reg  [7:0]  hid_wr_addr,
    output reg  signed [15:0] hid_wr_data,
    output reg         hid_wr_en,

    output reg  [7:0]  hid_rd_addr,
    input  wire signed [15:0] hid_rd_data,

    output reg  [3:0]  out_wr_addr,
    output reg  signed [15:0] out_wr_data,
    output reg         out_wr_en,

    output wire signed [15:0] sig_in,
    input  wire signed [15:0] sig_out,

    output reg          arg_reset,
    output reg          arg_start,
    output reg  signed  [15:0] arg_y_in,
    output reg          [3:0]  arg_idx,
    input  wire         [3:0]  arg_pred,
    input  wire         arg_done
);

    reg         mac_reset;
    reg         mac_start;
    reg  signed [15:0] mac_pixel;
    reg  signed [15:0] mac_peso;
    reg  signed [15:0] mac_bias;
    wire [9:0]  mac_addr;
    wire        mac_done;
    wire signed [15:0] mac_saida;

    wire [15:0]         img_data;
    wire signed [15:0]  win_data;
    wire signed [15:0]  bias_data;
    wire signed [15:0]  beta_data;

    reg  [9:0]  img_addr;
    reg  [17:0] win_addr;
    reg  [7:0]  bias_addr;
    reg  [17:0] beta_addr;
    reg  [9:0]  mac_n_ops;
    reg  [4:0]  mac_shift;
    reg  [1:0]  pipe_cnt;

    digito digito_inst (
        .address  (img_addr),
        .data     (8'b0),
        .inclock  (clk),
        .outclock (clk),
        .wren     (1'b0),
        .q        (img_data)
    );

    pesos pesos_inst (
        .address (win_addr),
        .clock   (clk),
        .q       (win_data)
    );

    beta beta_inst (
        .address (beta_addr),
        .clock   (clk),
        .q       (beta_data)
    );

    bias bias_inst (
        .address (bias_addr),
        .clock   (clk),
        .q       (bias_data)
    );

    mac mac_inst (
        .clk    (clk),
        .reset  (mac_reset),
        .start  (mac_start),
        .pixel  (mac_pixel),
        .peso   (mac_peso),
        .bias   (mac_bias),
        .shift  (mac_shift),
        .n_ops  (mac_n_ops),
        .addr   (mac_addr),
        .done   (mac_done),
        .saida  (mac_saida)
    );

    ativacao sigmoid_inst (
        .d_in  (sig_in),
        .d_out (sig_out)
    );

    argmax argmax_inst (
        .clk   (clk),
        .reset (arg_reset),
        .start (arg_start),
        .y_in  (arg_y_in),
        .idx   (arg_idx),
        .pred  (arg_pred),
        .done  (arg_done)
    );

    parameter N_HIDDEN  = 128;
    parameter N_CLASSES = 10;
    parameter IMG_SIZE  = 784;

    reg signed [15:0] mac_saida_reg;
    assign sig_in = mac_saida_reg;

    localparam [5:0]
        IDLE        = 5'd0,
        H_RESET_MAC = 5'd1,
        H_PIPE      = 5'd2,
        H_RUN       = 5'd3,
        H_WAIT      = 5'd4,
        H_SIG       = 5'd5,
        H_WRITE     = 5'd6,
        H_FLUSH     = 5'd7,
        O_RESET_MAC = 5'd8,
        O_PIPE      = 5'd9,
        O_RUN       = 5'd10,
        O_WAIT      = 5'd11,
        O_WAIT2     = 5'd12,
        O_WRITE     = 5'd13,
        ARG_FEED    = 5'd14,
        ARG_FLUSH   = 5'd15,
        ARG_WAIT    = 5'd16,
        DONE_ST     = 5'd17,
        ERROR_ST    = 5'd18;

    reg [5:0]  state;
    reg [7:0]  n_cnt;
    reg [3:0]  c_cnt;
    reg [9:0]  p_cnt;
    reg signed [15:0] y_scores [0:N_CLASSES-1];

    wire signed [15:0] pixel_q412 = {8'b0, img_data[7:0]};

    integer SAIDA_MAC, SAIDA_BETA, SAIDA_SIGMOID, SAIDA_ARG_FEED, SAIDA_FINAL, RESET_SIMULACAO, SAIDA_H_WAIT, SAIDA_H_WRITE, RESET_O_RUN, SAIDA_O_WAIT, SAIDA_O_WRITE;

    initial begin
        SAIDA_H_WAIT = $fopen("Saida/SAIDA_H_WAIT.txt", "w");
        SAIDA_BETA    = $fopen("Saida/SAIDA_BETA.txt",   "w");
        SAIDA_FINAL   = $fopen("Saida/SAIDA_FINAL.txt",  "w");
        RESET_SIMULACAO = $fopen("Saida/RESET_SIMULACAO.txt", "w");
        SAIDA_H_WRITE = $fopen("Saida/SAIDA_H_WRITE.txt", "w");
        RESET_O_RUN = $fopen("Saida/RESET_O_RUN.txt", "w");
        SAIDA_O_WAIT = $fopen("Saida/SAIDA_O_WAIT.txt", "w");
        SAIDA_O_WRITE = $fopen("Saida/SAIDA_O_WRITE.txt", "w");
        SAIDA_ARG_FEED = $fopen("Saida/SAIDA_ARG_FEED.txt", "w");
    end

    reg [9:0] p_cnt_d;
    reg [3:0] c_cnt_d;
    always @(posedge clk) begin
        p_cnt_d <= p_cnt;
        c_cnt_d <= c_cnt;
        if (state == O_RUN)
            $fdisplay(SAIDA_BETA, "MAC recebe c=%d k=%d  h[k]=%d  beta=%d",
                      c_cnt_d, p_cnt_d, mac_pixel, mac_peso);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= IDLE;
            n_cnt         <= 0;
            c_cnt         <= 0;
            p_cnt         <= 0;
            pipe_cnt      <= 0;
            done          <= 0;
            pred          <= 0;
            mac_reset     <= 1;
            mac_start     <= 0;
            mac_pixel     <= 0;
            mac_peso      <= 0;
            mac_bias      <= 0;
            mac_shift     <= 0;
            mac_n_ops     <= 0;
            mac_saida_reg <= 0;
            hid_wr_en     <= 0;
            out_wr_en     <= 0;
            arg_reset     <= 1;
            arg_start     <= 0;
            arg_y_in      <= 0;
            arg_idx       <= 0;
            img_addr      <= 0;
            win_addr      <= 0;
            bias_addr     <= 0;
            beta_addr     <= 0;
            hid_rd_addr   <= 0;
        end else begin
            mac_reset <= 0;
            mac_start <= 0;
            hid_wr_en <= 0;
            out_wr_en <= 0;
            arg_reset <= 0;
            arg_start <= 0;

            case (state)

                IDLE: begin
                    done      <= 0;
                    n_cnt     <= 0;
                    c_cnt     <= 0;
                    p_cnt     <= 0;
                    mac_reset <= 1;
                    arg_reset <= 1;
                    if (start) begin
                        mac_reset <= 0;
                        arg_reset <= 0;
                        state     <= H_RESET_MAC;
                    end
                end

                H_RESET_MAC: begin
                    mac_reset <= 1;
                    p_cnt     <= 0;
                    img_addr  <= 0;
                    mac_shift <= 14;
                    mac_n_ops <= IMG_SIZE - 1;
                    win_addr  <= n_cnt * IMG_SIZE;
                    bias_addr <= n_cnt[7:0];
                    state     <= H_PIPE;
                end

                H_PIPE: begin
                    img_addr <= 1;
                    win_addr <= n_cnt * IMG_SIZE + 1;
                    p_cnt    <= 1;        
                    state <= H_RUN;
                end

                H_RUN: begin
                    mac_start <= 1;
                    mac_pixel <= pixel_q412;
                    mac_peso  <= win_data;
                    mac_bias  <= (p_cnt == IMG_SIZE - 1) ? bias_data : 16'sh0000;

                    if (p_cnt == IMG_SIZE - 1) begin
                        state <= H_WAIT;
                    end else begin
                        p_cnt    <= p_cnt + 1;
                        img_addr <= p_cnt + 1;
                        win_addr <= n_cnt * IMG_SIZE + p_cnt + 1;
                        state    <= H_RUN;
                    end
                end

                H_WAIT: begin
                    mac_start <= 0;
                    if (mac_done) begin    
                        mac_saida_reg <= mac_saida;
                        $fdisplay(SAIDA_H_WAIT, "MAC pronto neuronio=%d  mac_saida=%d mac_done=%d", n_cnt, mac_saida, mac_done);
                        state <= H_SIG;
                    end

                end

                H_SIG: begin
                    state <= H_WRITE;
                end

                H_WRITE: begin
                    hid_wr_en   <= 1;
                    hid_wr_addr <= n_cnt[7:0];
                    hid_wr_data <= sig_out;
                    $fdisplay(SAIDA_H_WRITE,  "neuronio=%d  mac_saida_reg=%d  sig_in=%d  sig_out=%d", n_cnt, mac_saida_reg, sig_in, sig_out);
                    
                    if (n_cnt == N_HIDDEN - 1) begin
                        n_cnt <= 0;
                        c_cnt <= 0;
                        p_cnt <= 0;
                        state <= O_RESET_MAC;
                    end else begin
                        n_cnt <= n_cnt + 1;
                        state <= H_RESET_MAC;
                    end
                end


                O_RESET_MAC: begin
                    mac_reset   <= 1;
                    p_cnt       <= 0; 
                    hid_rd_addr <= 0;                      // começa no índice 0
                    mac_shift   <= 12;
                    mac_n_ops   <= N_HIDDEN;          // 128 multiplicações por classe
                    beta_addr   <= c_cnt * N_HIDDEN;        
                    mac_bias    <= 16'sh0000;
                    state       <= O_PIPE;
                    $fdisplay(RESET_SIMULACAO, "RESET MAC para classe %d, p_cnt = %d, hid_rd_addr = %d, beta_peso = %d, beta_addr = %d, mac_shift = %d, mac_saida = %d, mac_n_ops = %d", c_cnt, p_cnt, hid_rd_addr, beta_data, beta_addr, mac_shift, mac_saida_reg, mac_n_ops);
                end

                O_PIPE: begin
             
                    beta_addr   <= c_cnt * N_HIDDEN + 1;
                    state       <= O_RUN;
                end
                
                O_RUN: begin
                    $fdisplay(RESET_O_RUN, "RUN MAC para classe %d, p_cnt = %d, hid_rd_addr = %d, beta_peso = %d, beta_addr = %d, mac_shift = %d, mac_n_ops = %d", c_cnt, p_cnt, hid_rd_addr, beta_data, beta_addr, mac_shift, mac_n_ops);
                    mac_start   <= 1;

                    mac_pixel   <= hid_rd_data;    
                    mac_peso    <= beta_data;      


                    if (p_cnt == N_HIDDEN - 1) begin
                        state <= O_WAIT;
                    end else begin
                        p_cnt <= p_cnt + 1;
                        hid_rd_addr <= p_cnt + 1;
                        beta_addr   <= c_cnt * N_HIDDEN + p_cnt + 1;
                        state <= O_RUN;
                    end
                end

                O_WAIT: begin
                    mac_start <= 0;
                    if (mac_done) begin    
                        $fdisplay(SAIDA_O_WAIT, "MAC pronto para classe %d  mac_saida=%d mac_done=%d", c_cnt, mac_saida, mac_done);
                        mac_saida_reg <= mac_saida;
                        state         <= O_WRITE;
                    end
                end

                O_WRITE: begin
                    out_wr_en       <= 1;
                    out_wr_addr     <= c_cnt[3:0];
                    out_wr_data     <= mac_saida_reg;
                    y_scores[c_cnt] <= mac_saida_reg;
                    $fdisplay(SAIDA_O_WRITE, "classe=%d  mac_saida_reg=%d", c_cnt, mac_saida_reg);
              
                    if (c_cnt == N_CLASSES - 1) begin
                        c_cnt <= 0;
                        state <= ARG_FEED;
                    end else begin
                        c_cnt <= c_cnt + 1;
                        state <= O_RESET_MAC;
                    end
                end


                ARG_FEED: begin
                    arg_start <= 1;
                    arg_y_in  <= y_scores[c_cnt];
                    arg_idx   <= c_cnt[3:0];
                    $fdisplay(SAIDA_ARG_FEED, "Alimentando Argmax com idx=%d  y_score=%d", arg_idx, arg_y_in);
                    if (c_cnt == N_CLASSES - 1) begin
                        c_cnt <= 0;
                        state <= ARG_WAIT;
                    end else begin
                        c_cnt <= c_cnt + 1;
                        state <= ARG_FEED;
                    end
                end

                ARG_WAIT: begin
                    arg_start <= 0;
                    if (arg_done) begin  
                        pred      <= arg_pred;
                        done      <= 1;
                        state     <= DONE_ST;
                    end
                end

                DONE_ST: begin
                    $fdisplay(SAIDA_FINAL,
                        "SAIDAS FINAIS:\n Y_scores[0]=%d\n Y_scores[1]=%d\n Y_scores[2]=%d\n Y_scores[3]=%d\n Y_scores[4]=%d\n Y_scores[5]=%d\n Y_scores[6]=%d\n Y_scores[7]=%d\n Y_scores[8]=%d\n Y_scores[9]=%d",
                        y_scores[0], y_scores[1], y_scores[2], y_scores[3], y_scores[4], y_scores[5], y_scores[6], y_scores[7], y_scores[8], y_scores[9]);
                    $fdisplay(SAIDA_FINAL,"Classificação pronta -> classe %d, valor máximo: %d", pred, y_scores[pred]);
                    done <= 1;
                    if (!start) begin
                        done  <= 0;
                        state <= IDLE;
                    end
                end

                ERROR_ST: begin
                    done <= 0;
                end

                default: state <= ERROR_ST;

            endcase
        end
    end

    reg [79:0] state_name;
    always @(*) begin
        case (state)
            IDLE        : state_name = "IDLE      ";
            H_RESET_MAC : state_name = "H_RST_MAC ";
            H_PIPE      : state_name = "H_PIPE    ";
            H_RUN       : state_name = "H_RUN     ";
            H_WAIT      : state_name = "H_WAIT    ";
            H_SIG       : state_name = "H_SIG     ";
            H_WRITE     : state_name = "H_WRITE   ";
            H_FLUSH     : state_name = "H_FLUSH   ";
            O_RESET_MAC : state_name = "O_RST_MAC ";
            O_PIPE      : state_name = "O_PIPE    ";
            O_RUN       : state_name = "O_RUN     ";
            O_WRITE     : state_name = "O_WRITE   ";
            ARG_FEED    : state_name = "ARG_FEED  ";
            ARG_WAIT    : state_name = "ARG_WAIT  ";
            DONE_ST     : state_name = "DONE      ";
            ERROR_ST    : state_name = "ERROR     ";
            ARG_FLUSH   : state_name = "ARG_FLUSH ";
            default     : state_name = "???       ";
        endcase
    end

endmodule
