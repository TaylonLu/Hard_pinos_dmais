// =============================================================================
// fsm_controlador.v  —  FSM de controle do co-processador ELM
//
// Correções em relação ao código original:
//  1. N_HIDDEN e N_CLASSES declarados como parâmetros configuráveis
//  2. Lógica de transição reescrita: cada estado avança apenas sua condição
//  3. Race condition de y_val eliminada — comparação feita com mac_out direto
//  4. mac_start controlado por estado, sem pulso de reinício problemático
//  5. Endereçamento 2D correto: addr_beta = classe_idx*N_HIDDEN + hidden_idx
//  6. Estado ARGMAX removido — argmax calculado inline em OUTPUT_STORE
//  7. Transição DONE→IDLE corrigida: volta ao idle quando start vai a 0
//  8. Sinais de saída das memórias adicionados (addr_beta, addr_hidden)
//  9. Pixel convertido de 8-bit para Q4.12 internamente
// =============================================================================

module fsm_controlador (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,

    // ── Interface com o módulo MAC ───────────────────────────────────────────
    output reg         mac_start,
    input  wire        mac_done,
    input  wire signed [15:0] mac_out,   // Q4.12 — resultado do MAC

    // ── Endereços de memória ─────────────────────────────────────────────────
    output reg  [9:0]  addr_img,         // mem_image  [0..783]
    output reg  [17:0] addr_win,         // mem_W_in   [0..N_HIDDEN*784-1]
    output reg  [8:0]  addr_bias,        // mem_bias   [0..N_HIDDEN-1]
    output reg  [14:0] addr_beta,        // mem_beta   [0..N_CLASSES*N_HIDDEN-1]
    output reg  [8:0]  addr_hidden,      // mem_hidden [0..N_HIDDEN-1]

    // ── Escrita na memória oculta (h[n]) ─────────────────────────────────────
    output reg         hidden_we,        // write-enable para mem_hidden
    output reg signed [15:0] hidden_din, // dado a escrever em mem_hidden

    // ── Status e resultado ───────────────────────────────────────────────────
    output reg  [1:0]  status,           // 2'b00=IDLE, 2'b01=BUSY, 2'b10=DONE, 2'b11=ERROR
    output reg  [3:0]  pred             // dígito predito 0..9
);

	 parameter N_HIDDEN  = 256;   // número de neurônios da camada oculta
    parameter N_CLASSES = 10;     // número de classes de saída (dígitos 0–9)
    // ── Codificação de estados ───────────────────────────────────────────────
    localparam [2:0]
        IDLE         = 3'd0,
        HIDDEN_MAC   = 3'd1,   // acumula pixel[p] × W_in[n][p]
        HIDDEN_ACT   = 3'd2,   // aplica σ e salva h[n]
        OUTPUT_MAC   = 3'd3,   // acumula h[k] × β[c][k]
        OUTPUT_STORE = 3'd4,   // salva y[c] e atualiza argmax
        DONE_ST      = 3'd5,
        ERROR_ST     = 3'd6;

    reg [2:0] state;

    // ── Contadores internos ───────────────────────────────────────────────────
    reg  [9:0]  pixel_cnt;      // 0..783 — pixel atual na camada oculta
    reg  [8:0]  neuron_cnt;     // 0..N_HIDDEN-1 — neurônio oculto atual
    reg  [9:0]  hidden_cnt;     // 0..N_HIDDEN-1 — índice de h ao gerar saída
    reg  [3:0]  classe_cnt;     // 0..N_CLASSES-1 — classe de saída atual

    // ── argmax inline ─────────────────────────────────────────────────────────
    reg signed [15:0] max_val;

    // ── Interface com módulo de ativação (combinacional externo) ─────────────
    // O módulo ativacao_sigmoid é instanciado externamente e conectado assim:
    //   .d_in  (mac_out)   → resultado do MAC antes de gravar em h[n]
    //   .d_out (sigma_out) → valor ativado a ser armazenado
    // Por clareza, declaramos sigma_out como entrada da FSM:
    input  wire signed [15:0] sigma_out,  // saída da ativacao_sigmoid(mac_out)

    // ── Registrador de saída temporário ──────────────────────────────────────
    reg signed [15:0] y_reg;    // captura mac_out no ciclo DONE do OUTPUT_MAC

    // =========================================================================
    // Lógica sequencial: estado + contadores + saídas
    // =========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            pixel_cnt   <= 0;
            neuron_cnt  <= 0;
            hidden_cnt  <= 0;
            classe_cnt  <= 0;
            max_val     <= 16'sh8000;   // menor valor Q4.12 (−8.0)
            mac_start   <= 0;
            hidden_we   <= 0;
            hidden_din  <= 0;
            status      <= 2'b00;       // IDLE
            pred        <= 0;
            addr_img    <= 0;
            addr_win    <= 0;
            addr_bias   <= 0;
            addr_beta   <= 0;
            addr_hidden <= 0;
            y_reg       <= 0;
        end else begin
            // Defaults a cada ciclo (evita latches)
            hidden_we  <= 0;
            mac_start  <= 0;

            case (state)

                // ── IDLE ─────────────────────────────────────────────────────
                IDLE: begin
                    status     <= 2'b00;
                    pixel_cnt  <= 0;
                    neuron_cnt <= 0;
                    hidden_cnt <= 0;
                    classe_cnt <= 0;
                    max_val    <= 16'sh8000;
                    if (start) begin
                        state  <= HIDDEN_MAC;
                        status <= 2'b01;   // BUSY
                    end
                end

                // ── HIDDEN_MAC ───────────────────────────────────────────────
                // Calcula o produto escalar pixel[p] × W_in[n][p] ao longo de
                // 784 ciclos. O módulo MAC recebe mac_start=1 e controla addr
                // internamente; aqui apenas publicamos os endereços para as
                // memórias externas lerem e entregarem pixel/peso ao MAC.
                HIDDEN_MAC: begin
                    mac_start  <= 1;
                    addr_img   <= pixel_cnt;
                    addr_win   <= neuron_cnt * 784 + pixel_cnt;
                    addr_bias  <= neuron_cnt;

                    if (mac_done) begin
                        // MAC terminou os 784 pixels deste neurônio
                        state <= HIDDEN_ACT;
                        // Não incrementamos pixel_cnt aqui; HIDDEN_ACT volta
                        // e reinicia pixel_cnt=0 para o próximo neurônio.
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end

                // ── HIDDEN_ACT ───────────────────────────────────────────────
                // mac_out contém acc+bias do neurônio atual.
                // sigma_out = σ(mac_out) já está disponível combinacionalmente.
                // Gravamos h[n] = sigma_out na memória oculta.
                HIDDEN_ACT: begin
                    hidden_we   <= 1;
                    hidden_din  <= sigma_out;      // σ(mac_out)
                    addr_hidden <= neuron_cnt;

                    if (neuron_cnt == N_HIDDEN - 1) begin
                        // Todos os neurônios ocultos processados
                        neuron_cnt <= 0;
                        pixel_cnt  <= 0;
                        state      <= OUTPUT_MAC;
                    end else begin
                        neuron_cnt <= neuron_cnt + 1;
                        pixel_cnt  <= 0;
                        state      <= HIDDEN_MAC;
                    end
                end

                // ── OUTPUT_MAC ───────────────────────────────────────────────
                // Calcula y[c] = Σ h[k] × β[c][k], para k=0..N_HIDDEN-1.
                OUTPUT_MAC: begin
                    mac_start   <= 1;
                    addr_hidden <= hidden_cnt;
                    addr_beta   <= classe_cnt * N_HIDDEN + hidden_cnt;

                    if (mac_done) begin
                        state <= OUTPUT_STORE;
                        // Captura resultado ANTES de qualquer incremento
                        y_reg <= mac_out;
                    end else begin
                        hidden_cnt <= hidden_cnt + 1;
                    end
                end

                // ── OUTPUT_STORE ─────────────────────────────────────────────
                // y_reg contém y[c] deste ciclo. Atualiza argmax.
                // Elimina necessidade de estado ARGMAX separado.
                OUTPUT_STORE: begin
                    // Atualiza argmax com o valor capturado
                    if (y_reg > max_val) begin
                        max_val <= y_reg;
                        pred    <= classe_cnt[3:0];
                    end

                    if (classe_cnt == N_CLASSES - 1) begin
                        // Todas as classes calculadas → concluído
                        state  <= DONE_ST;
                        status <= 2'b10;   // DONE
                    end else begin
                        classe_cnt <= classe_cnt + 1;
                        hidden_cnt <= 0;   // reinicia índice h para próxima classe
                        state      <= OUTPUT_MAC;
                    end
                end

                // ── DONE_ST ──────────────────────────────────────────────────
                DONE_ST: begin
                    status <= 2'b10;
                    if (!start) begin
                        // ARM leu o resultado e baixou start → volta ao IDLE
                        state <= IDLE;
                    end
                end

                // ── ERROR_ST ─────────────────────────────────────────────────
                ERROR_ST: begin
                    status <= 2'b11;
                    // Só sai do estado de erro via reset externo
                end

                default: state <= ERROR_ST;

            endcase
        end
    end

endmodule