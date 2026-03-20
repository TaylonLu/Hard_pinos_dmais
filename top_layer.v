`timescale 1ns/1ps

module top_layer (
    input wire clk,
    input wire rst,
    input wire start,
    output reg done
);

    // -------------------------
    // Parâmetros
    // -------------------------
    localparam N_PIXELS  = 784;
    localparam N_NEURONS = 128;

    localparam BETA_ROWS = 10;
    localparam BETA_COLS = 128;

    // -------------------------
    // Estados (mantido)
    // -------------------------
    reg [2:0] state;
    reg [3:0] data_state;

    localparam IDLE  = 0,
               LOAD  = 1,
               RUN   = 2,
               BIAS  = 3,
               CORDIC = 4,
               BETA  = 5,
               SAVE  = 6,
               NEXT  = 7,
               DONE  = 8;

    localparam IDLE_H = 9,
               PESO_H = 10,
               BETA_H = 11;

    // -------------------------
    // Sinais
    // -------------------------
    reg [9:0] addr; // endereço do pixel
    reg [7:0] neuron_id; // qual neuronio esta

    reg [3:0] beta_i;
    reg [7:0] beta_j;
	 reg [3:0] beta_i_d;
	 
    wire signed [15:0] Q_pixel, Q_W_i, Q_bias, Q_beta; // fio ou reg
	 
	 wire signed [15:0] Q_H_SIGMOID;
    wire signed [15:0] Q_H;
    wire cordic_flag;

    reg signed [15:0] a_reg, b_reg;
    wire signed [31:0] acc_mac;

    reg enable_mac;
    reg add_bias;

    reg signed [15:0] h [0:N_NEURONS-1]; // saída do tanh 
    reg signed [31:0] acc_out [0:9]; // acc_out[i] += h[j] * beta[i][j] == resultado

    integer i;

    // -------------------------
    // Endereços
    // -------------------------
    wire [16:0] weight_addr;
    wire [10:0] beta_addr;

    assign weight_addr = neuron_id * N_PIXELS + addr;
    assign beta_addr   = beta_i * BETA_COLS + beta_j;

    // -------------------------
    // ROMs 
    // -------------------------
    rom_pixels memory_pixels (    
		.address(addr),
		.clk(clk),
	//	.data(16'd0),
	//	.rden(1'b1),
	//	.wren(1'b0),
		.q(Q_pixel)
	);
    rom_weights memory_weights (
		.address(addr),
		.clk(clk),
	//	.data(16'd0),
	//	.rden(1'b1),
	//	.wren(1'b0),
		.q(Q_W_i)
	);
    rom_bias memory_bias (
		.address(addr),
		.clk(clk),
	//	.data(16'd0),
	//	.rden(1'b1),
	//	.wren(1'b0),
		.q(Q_bias)
	 );
    rom_beta memory_beta (
		.address(addr),
		.clk(clk),
	//	.data(16'd0),
	//	.rden(1'b1),
	//	.wren(1'b0),
		.q(Q_beta)
	);

    // -------------------------
    // MAC
    // -------------------------
    mac u_mac (
        .clk(clk),
        .rst(rst),
        .enable(enable_mac),
        .add_bias(add_bias),
        .a(a_reg),
        .b(b_reg),
        .bias(Q_bias),
        .acc(acc_mac)
    );

    // -------------------------
    // CORDIC
    // -------------------------
    cordicTanh u_cordic (
        .clk(clk),
        .rst(rst),
        .z0(acc_mac[15:0]),
        .out(Q_H), // tirei a variavel y_out
        .flag(cordic_flag)
    );
    // -------------------------
    // SIGMOID
    // -------------------------	

	sigmoid u_sigmoid(
		 .clk(clk),
		 .x(acc_mac[15:0]),
		 .y(Q_H_SIGMOID)
	);
	
/*
	always @(posedge clk) begin
		 if (cordic_flag) begin  // ou um enable qualquer
			  h[neuron_id] <= h_out; // salva na camada oculta
		 end
	end
*/
    // -------------------------
    // PIPELINE
    // -------------------------
    always @(posedge clk) begin
        if (rst) begin
            a_reg <= 0;
            b_reg <= 0;
        end else begin
            case (data_state)
                PESO_H: begin
                    a_reg <= Q_pixel;
                    b_reg <= Q_W_i;
                end
                BETA_H: begin
                    a_reg <= h[beta_j];
                    b_reg <= Q_beta;
                end
            endcase
        end
    end

    // -------------------------
    // FSM
    // -------------------------
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            data_state <= IDLE_H;

            addr <= 0;
            neuron_id <= 0;
            beta_i <= 0;
            beta_j <= 0;

            enable_mac <= 0;
            add_bias <= 0;
            done <= 0;

            for (i=0; i<10; i=i+1)
                acc_out[i] <= 0;

        end else begin
            case (state)

                IDLE: begin
                    done <= 0;
                    if (start) begin
                        neuron_id <= 0;
                        addr <= 0;
                        state <= LOAD;
                    end
                end

                LOAD: begin
                    addr <= 0; 
                    enable_mac <= 0;
                    state <= RUN;
                end

                RUN: begin
                    data_state <= PESO_H;

                    if (addr < N_PIXELS) begin
                        enable_mac <= 1;
                        addr <= addr + 1;
                    end else begin
                        enable_mac <= 0;
                        add_bias <= 1;
                        state <= BIAS;
                    end
                end

                BIAS: begin
                    add_bias <= 0;
                    state <= CORDIC;
                end

                CORDIC: begin
                    if (cordic_flag) begin
                        h[neuron_id] <= Q_H; // salva o resultado da ativaçao
                        beta_i <= 0;
                        beta_j <= 0;
                        state <= BETA;
                    end
                end

                BETA: begin
						 data_state <= BETA_H;

						 enable_mac <= 1;
						 add_bias   <= 0;
						 
						 beta_i_d <= beta_i; //salva/trava o index
 
						 acc_out[beta_i_d] <= acc_out[beta_i_d] + acc_mac;

						 if (beta_j < BETA_COLS-1) begin
							  beta_j <= beta_j + 1;
						 end else begin
							  beta_j <= 0;

							  if (beta_i < BETA_ROWS-1) begin
									beta_i <= beta_i + 1;
							  end else begin
									enable_mac <= 0;
									state <= SAVE;
							  end
						 end
					end

                SAVE: begin
                    state <= NEXT;
                end

                NEXT: begin
                    if (neuron_id < N_NEURONS-1) begin
                        neuron_id <= neuron_id + 1;
                        addr <= 0;
                        state <= LOAD;
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule

/*
    // -------------------------
    // Parâmetros
    // -------------------------
    localparam N_PIXELS  = 784;
    localparam N_NEURONS = 128;
	localparam N_NEURONS_B = 10;
    localparam TOTAL_WEIGHTS = N_PIXELS * N_NEURONS; // 100352
    localparam N_BETA = 1280; // 10 betas por neurônio

    // -------------------------
    // Memórias
    // -------------------------
    reg signed [15:0] pixels [0:N_PIXELS-1];
    reg signed [15:0] W_in   [0:TOTAL_WEIGHTS-1];
	 
    reg signed [15:0] bias   [0:N_NEURONS-1];
    reg signed [15:0] beta   [0:N_BETA-1];
	reg signed [31:0] acc_mac;
	 
	wire [15:0] Q_pixel, Q_W_i, Q_H, Q_beta;

    // saída dos neurônios
    reg signed [31:0] acc_out [0:N_NEURONS-1];    // saída MAC
    reg signed [31:0] y_out   [0:N_NEURONS_B-1];    // y = beta * h
	wire signed [15:0] tanh_out;
	 
	 // -------------------------
    // CONTADORES
    // -------------------------
	 reg [3:0] beta_neuron_c;
	 reg [9:0] addr;
    reg [7:0] neuron_id;
    reg [11:0] beta_idx;
	 reg [7:0] cordic_cnt;

	 
	 // --------------------------
	 // Sinais 
	 // --------------------------
	 reg enable_mac; // sinal para ficar multiplicando: pixels * peso
    reg add_bias;	// sinal para adicionar o bias: acumulador + bias
	 reg start_d; // Gambiarra
    reg cordic_flag;
	 
	 // -------------------------
    // FSM principal
    // -------------------------
    reg [2:0] state;
	 reg [3:0] data_state;
    
    localparam IDLE  = 00,
               LOAD  = 01,
               RUN   = 02,
               BIAS  = 03,
               CORDIC = 04,
               BETA  = 05,
               SAVE  = 06,
               NEXT  = 07,
               DONE  = 08;
	
	 localparam IDLE_H = 09,
					PESO_H = 10,
					BETA_H = 11;

	 // -------------------------

	 atv3_32x8 ppp (
			address,
			clk,
			data,
			rden,
			wren,
			q);
	
	 // ------------------------

    // -------------------------
    // Pipeline: registradores
    // -------------------------
    reg signed [15:0] a_reg, b_reg;
    wire [16:0] weight_index;
    assign weight_index = neuron_id * N_PIXELS + addr;

    always @(posedge clk) begin
        if (rst) begin
            a_reg <= 0;
            b_reg <= 0;
        end else begin
			  case (second_state)
				PESO_H: begin
					a_reg <= Q_pixel;
					b_reg <= Q_W_i;
				end
				BETA_H: begin
					a_reg <= Q_H;
					b_reg <= Q_beta;
				end
			endcase
        end
    end

    // -------------------------
    // MAC
    // -------------------------

    mac u_mac (
        .clk(clk),
        .rst(rst),
        .enable(enable_mac),
        .add_bias(add_bias),
        .a(a_reg),
        .b(b_reg),
        .bias(bias[neuron_id]),
        .acc(acc_mac)
    );

    // -------------------------
    // CORDIC tanh
    // -------------------------


    cordicTanh u_cordic (
        .clk(clk),
        .rst(rst),
        .z0(acc_mac[15:0]),
        .out(tanh_out),
        .flag(cordic_flag)
    );


    always @(posedge clk) begin
        if (rst) begin
            state 		<= IDLE;
				data_state  <= IDLE_H,
            addr 			<= 0;
            neuron_id 	<= 0;
            beta_idx 	<= 0;
            enable_mac 	<= 0;
            add_bias 	<= 0;
            done 			<= 0;
            acc_out[0] 	<= 0;
            y_out[0] 	<= 0;
            cordic_cnt 	<= 0;
            start_d 		<= 0;
				beta_neuron_c <= 0;
        end else begin
            start_d <= start;
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start && !start_d) begin 
                        neuron_id <= 0;
                        addr <= 0;
                        state <= LOAD;
                    end
                end

                // preparar pipeline
                LOAD: begin
                    enable_mac <= 0;
                    addr <= 0;
                    state <= RUN;
                end

                // somar pixels * pesos
                RUN: begin
						if (addr < N_PIXELS) begin
							data_state <= PESO_H;
                     enable_mac <= 1;
                     addr <= addr + 1;
                  end else begin
                     enable_mac <= 0;
                     add_bias <= 1;
                     addr <= 0;
                     state <= BIAS;
                   end
                end

                // aplicar bias
                BIAS: begin
                    add_bias <= 0;
                    state <= CORDIC;
                end

                // cordic tanh
               
                CORDIC: begin
						if (cordic_cnt == 8'd128) begin
							acc_out[neuron_id] <= acc_mac;
							cordic_cnt <= 0;
							state <= BETA;
							end
                end

                // multiplicar por β
                // multiplicar os 128 neuronios por βi,j
                BETA: begin
						if (data_state == PESO_H) begin
							data_state = BETA_H;
						end
                   if(beta_idx < N_BETA)
                        beta_neuron_c <= (beta_neuron_c == 9) ? 0 : beta_neuron_c + 1;
                        cordic_cnt <= cordic_cnt + 1;
                        beta_idx <= beta_idx + 1;
                    end else begin
                        state <= SAVE;
								data_state <= IDLE_H;
                    end
                end

                SAVE: begin
                    state <= NEXT;
                end

                NEXT: begin
                    if (neuron_id < N_NEURONS-1) begin
                        neuron_id <= neuron_id + 1;
                        addr <= 0;
                        state <= LOAD;
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end
                
            endcase
        end
    end

endmodule

*/