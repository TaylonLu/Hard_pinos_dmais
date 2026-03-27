
//   mac       — reset, start, pixel, peso, bias  -> addr, done, saida
//   sigmoid   — (combinacional) saida do mac     -> h_val
//   argmax    — reset, start, y_in, idx          -> pred, done
//   memórias  — leitura de mem_image, mem_win, mem_bias, mem_beta
//               escrita em mem_hidden, mem_output
module elm_fsm (
    // --- Globais ---
    input  wire clk,
    input  wire rst_n,

    // --- Disparo e status ---
    input  wire start,
    output reg  done,
    output reg  [3:0] pred,

    // REMOVIDO: img_data, win_data, bias_data, beta_data como inputs
    // Eles agora são wires internos, alimentados pelas instâncias de memória

    // --- Interface com mem_hidden (escrita h[n]) ---
    output reg  [7:0]  hid_wr_addr,
    output reg  signed [15:0] hid_wr_data,
    output reg         hid_wr_en,

    // --- Interface com mem_hidden (leitura h[k] para fase 2) ---
    output reg  [7:0]  hid_rd_addr,
    input  wire signed [15:0] hid_rd_data,

    // --- Interface com mem_output (escrita y[c]) ---
    output reg  [3:0]  out_wr_addr,
    output reg  signed [15:0] out_wr_data,
    output reg         out_wr_en,

    // --- Interface com mac ---
    output reg         mac_reset,
    output reg         mac_start,
    output reg  signed [15:0] mac_pixel,
    output reg  signed [15:0] mac_peso,
    output reg  signed [15:0] mac_bias,
    input  wire [9:0]  mac_addr,
    input  wire        mac_done,
    input  wire signed [15:0] mac_saida,

    // --- Interface com ativacao_sigmoid (combinacional) ---
    output wire signed [15:0] sig_in,
    input  wire signed [15:0] sig_out,

    // --- Interface com argmax ---
    output reg         arg_reset,
    output reg         arg_start,
    output reg  signed [15:0] arg_y_in,
    output reg  [3:0]  arg_idx,
    input  wire [3:0]  arg_pred,
    input  wire        arg_done
);

    // ----------------------------------------------------------------
    // Wires internos para saídas das memórias (substituem os inputs)
    // Cada wire recebe apenas UMA fonte: a saída (.q) da respectiva
    // instância de memória. Assim não há mais múltiplos drivers.
    // ----------------------------------------------------------------
    wire [7:0]          img_data;   // pixel lido da memória digito
    wire signed [15:0]  win_data;   // peso  lido da memória pesos
    wire signed [15:0]  bias_data;  // bias  lido da memória bias
    wire signed [15:0]  beta_data;  // beta  lido da memória beta

    // Endereços continuam como reg (driven pela FSM)
    reg  [9:0]  img_addr;
    reg  [17:0] win_addr;
    reg  [7:0]  bias_addr;
    reg  [17:0] beta_addr;

    // ----------------------------------------------------------------
    // Instâncias de memória
    // Cada memória recebe seu endereço (reg, driven pela FSM) e
    // entrega seu dado no wire interno correspondente.
    // ----------------------------------------------------------------

    // Memória da imagem (somente leitura pela FSM)
    // Nota: digito usa dois clocks (inclock/outclock) — ajuste conforme
    // seu IP. Os sinais data/wren são irrelevantes para leitura pura;
    // ligamos a constante segura (wren=0).
    digito digito_inst (
        .address  (img_addr),
        .data     (8'b0),        // sem escrita
        .inclock  (clk),
        .outclock (clk),
        .wren     (1'b0),        // somente leitura
        .q        (img_data)     // saída -> wire interno
    );

    // Memória dos pesos W_in (somente leitura)
    pesos pesos_inst (
        .address (win_addr),
        .clock   (clk),
        .q       (win_data)      // saída -> wire interno
    );

    // Memória dos betas (somente leitura)
    beta beta_inst (
        .address (beta_addr),
        .clock   (clk),
        .q       (beta_data)     // saída -> wire interno
    );

    // Memória dos biases (somente leitura)
    bias bias_inst (
        .address (bias_addr),
        .clock   (clk),
        .q       (bias_data)     // saída -> wire interno
    );

    // ----------------------------------------------------------------
    // Constantes
    // ----------------------------------------------------------------
    parameter N_HIDDEN  = 128;
    parameter N_CLASSES = 10;
    parameter IMG_SIZE  = 784;

    // Sigmoid conectado direto à saída do mac
    assign sig_in = mac_saida;

    // ----------------------------------------------------------------
    // Estados da FSM
    // ----------------------------------------------------------------
    localparam [3:0]
        IDLE          = 4'd0,
        H_RESET_MAC   = 4'd1,
        H_RUN         = 4'd2,
        H_WAIT        = 4'd3,
        H_WRITE       = 4'd4,
        O_RESET_MAC   = 4'd5,
        O_RUN         = 4'd6,
        O_WAIT        = 4'd7,
        O_WRITE       = 4'd8,
        ARG_FEED      = 4'd9,
        ARG_WAIT      = 4'd10,
        DONE_ST       = 4'd11,
        ERROR_ST      = 4'd12;

    reg [3:0] state;

    reg [7:0]  n_cnt;
    reg [3:0]  c_cnt;
    reg [9:0]  p_cnt;

    reg signed [15:0] y_scores [0:N_CLASSES-1];

    // Pixel Q8.0 -> Q4.12: desloca 4 bits à esquerda
    wire signed [15:0] pixel_q412 = {4'b0000, img_data, 4'b0000};
	 
    integer i;

    // FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= IDLE;
            n_cnt       <= 0;
            c_cnt       <= 0;
            p_cnt       <= 0;
            done        <= 0;
            pred        <= 0;
            mac_reset   <= 1;
            mac_start   <= 0;
            mac_pixel   <= 0;
            mac_peso    <= 0;
            mac_bias    <= 0;
            hid_wr_en   <= 0;
            out_wr_en   <= 0;
            arg_reset   <= 1;
            arg_start   <= 0;
            arg_y_in    <= 0;
            arg_idx     <= 0;
            img_addr    <= 0;
            win_addr    <= 0;
            bias_addr   <= 0;
            beta_addr   <= 0;
            hid_rd_addr <= 0;
        end else begin
            // defaults por ciclo 
            mac_reset  <= 0;
            mac_start  <= 0;
            hid_wr_en  <= 0;
            out_wr_en  <= 0;
            arg_reset  <= 0;
            arg_start  <= 0;

            case (state)

                // IDLE: Aguarda pulso de start. Inicializa todos os contadores.
                IDLE: begin
                    done      <= 0;
                    n_cnt     <= 0;
                    c_cnt     <= 0;
                    p_cnt     <= 0;
                    mac_reset <= 1;    // mantém mac em reset
                    arg_reset <= 1;    // mantém argmax em reset

                    if (start) begin
                        mac_reset <= 0;
                        arg_reset <= 0;
                        state     <= H_RESET_MAC;
                    end
                end

                // H_RESET_MAC: Pulsa mac_reset=1 por 1 ciclo antes de cada neurônio oculto
                // pré-carrega o endereço do bias do neurônio n
                H_RESET_MAC: begin
                    mac_reset  <= 1;
                    p_cnt      <= 0;
                    img_addr   <= 0;
                    win_addr   <= n_cnt * IMG_SIZE;   // W_in[n][0]
                    bias_addr  <= n_cnt[7:0];
                    state      <= H_RUN;
                end

                // H_RUN: Apresenta pixel[p] e W_in[n][p] ao mac a cada ciclo
                // mac acumula internamente usando start=1.
                // bias é apresentado apenas no último ciclo (mac soma no done).
                H_RUN: begin
                    mac_start <= 1;
                    mac_pixel <= pixel_q412;           // img_data vem de img_addr
                    mac_peso  <= win_data;             // win_data vem de win_addr
                    mac_bias  <= (p_cnt == IMG_SIZE - 1) ? bias_data : 16'sh0000;

                    // Avança endereços para o próximo ciclo
                    if (p_cnt < IMG_SIZE - 1) begin
                        p_cnt    <= p_cnt + 1;
                        img_addr <= p_cnt + 1;
                        win_addr <= n_cnt * IMG_SIZE + p_cnt + 1;
                        state    <= H_RUN;
                    end else begin
                        // Último pixel: aguarda mac terminar
                        state <= H_WAIT;
                    end
                end

                // H_WAIT: mac_done sobe 1 ciclo após o último start=1, registra a saída e avança
                H_WAIT: begin
                    mac_start <= 0;
                    if (mac_done)
                        state <= H_WRITE;
                end

                // H_WRITE: Aplica sigmoid em sig_out e grava h[n].
                H_WRITE: begin
                    hid_wr_en   <= 1;
                    hid_wr_addr <= n_cnt[7:0];
                    hid_wr_data <= sig_out;      // sig_in = mac_saida

                    if (n_cnt == N_HIDDEN - 1) begin
                        // Todos os neurônios ocultos prontos -> camada de saída
                        n_cnt <= 0;
                        c_cnt <= 0;
                        state <= O_RESET_MAC;
                    end else begin
                        n_cnt <= n_cnt + 1;
                        state <= H_RESET_MAC;
                    end
                end

                // O_RESET_MAC: Reseta mac antes de cada classe de saída
                O_RESET_MAC: begin
                    mac_reset   <= 1;
                    p_cnt       <= 0;
                    hid_rd_addr <= 0;
                    beta_addr   <= c_cnt * N_HIDDEN;   // beta[c][0]
                    state       <= O_RUN;
                end

                // O_RUN: Calcula y[c] = somatoria h[k] × beta[c][k]  para k=0..N_HIDDEN-1
                O_RUN: begin
                    mac_start <= 1;
                    mac_pixel <= hid_rd_data;     // h[k]
                    mac_peso  <= beta_data;       // beta[c][k]
                    mac_bias  <= 16'sh0000;       // sem bias na saída

                    if (p_cnt < N_HIDDEN - 1) begin
                        p_cnt       <= p_cnt + 1;
                        hid_rd_addr <= p_cnt + 1;
                        beta_addr   <= c_cnt * N_HIDDEN + p_cnt + 1;
                        state       <= O_RUN;
                    end else begin
                        state <= O_WAIT;
                    end
                end

                // O_WAIT 
                O_WAIT: begin
                    mac_start <= 0;
                    if (mac_done)
                        state <= O_WRITE;
                end

                // O_WRITE: Grava y[c] em mem_output e salva no vetor local.
                O_WRITE: begin
                    out_wr_en   <= 1;
                    out_wr_addr <= c_cnt[3:0];
                    out_wr_data <= mac_saida;
                    y_scores[c_cnt] <= mac_saida;

                    if (c_cnt == N_CLASSES - 1) begin
                        // Todos os resultados prontos -> alimentar argmax
                        c_cnt <= 0;
                        state <= ARG_FEED;
                    end else begin
                        c_cnt <= c_cnt + 1;
                        state <= O_RESET_MAC;
                    end
                end

                // ARG_FEED: Envia y_scores[c_cnt] ao argmax 1 por ciclo.
                ARG_FEED: begin
                    arg_start <= 1;
                    arg_y_in  <= y_scores[c_cnt];
                    arg_idx   <= c_cnt[3:0];

                    if (c_cnt == N_CLASSES - 1) begin
                        state <= ARG_WAIT;
                    end else begin
                        c_cnt <= c_cnt + 1;
                        state <= ARG_FEED;
                    end
                end

                // ARG_WAIT 
                ARG_WAIT: begin
                    arg_start <= 0;
                    if (arg_done) begin
                        pred  <= arg_pred;
                        done  <= 1;
                        state <= DONE_ST;
                    end
                end

                // DONE_ST: Mantém done=1 e pred estáveis até start ser desassertado
                DONE_ST: begin
                    done <= 1;
                    if (!start) begin
                        done  <= 0;
                        state <= IDLE;
                    end
                end

                // ERROR_ST
                ERROR_ST: begin
                    done <= 0;
                    // Aguarda reset externo (rst_n=0)
                end

                default: state <= ERROR_ST;

            endcase
        end
    end

    // Saída de estado 
    reg [79:0] state_name;
    always @(*) begin
        case (state)
            IDLE        : state_name = "IDLE      ";
            H_RESET_MAC : state_name = "H_RST_MAC ";
            H_RUN       : state_name = "H_RUN     ";
            H_WAIT      : state_name = "H_WAIT    ";
            H_WRITE     : state_name = "H_WRITE   ";
            O_RESET_MAC : state_name = "O_RST_MAC ";
            O_RUN       : state_name = "O_RUN     ";
            O_WAIT      : state_name = "O_WAIT    ";
            O_WRITE     : state_name = "O_WRITE   ";
            ARG_FEED    : state_name = "ARG_FEED  ";
            ARG_WAIT    : state_name = "ARG_WAIT  ";
            DONE_ST     : state_name = "DONE      ";
            ERROR_ST    : state_name = "ERROR     ";
            default     : state_name = "???       ";
        endcase
    end

endmodule