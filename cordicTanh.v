module cordicTanh(
    input wire clk,
    input wire rst,
    input wire signed [15:0] z0,
    output wire signed [15:0] out,
    output reg flag
);

    // -------------------------
    // Registradores
    // -------------------------
    reg [4:0] itr;
    reg signed [15:0] zj, yj, xj;

    wire signed [15:0] zn, zi, zval;
    wire signed [15:0] yn, yi, yval;
    wire signed [15:0] xn, xi, xval;

    reg [1:0] zsel;
    reg ysel, xsel, m;
    reg hold, clear;

    reg [1:0] extreme, extreme_next;

    wire signed [15:0] extremeCheckP, extremeCheckN;
    wire di;

    // -------------------------
    // FSM
    // -------------------------
    parameter [2:0] RST = 3'b000,
                    TANH = 3'b001,
                    REPEAT = 3'b010,
                    DIVIDE = 3'b011,
                    EXTR = 3'b100;

    reg [2:0] CS, NS;

    // -------------------------
    // ROM atanh
    // -------------------------
    reg signed [15:0] ROM;
    always @(*) begin
        case(itr)
            5'd1:  ROM = 16'h08CA;
            5'd2:  ROM = 16'h0416;
            5'd3:  ROM = 16'h0203;
            5'd4:  ROM = 16'h0100;
            5'd5:  ROM = 16'h0080;
            5'd6:  ROM = 16'h0040;
            5'd7:  ROM = 16'h0020;
            5'd8:  ROM = 16'h0010;
            5'd9:  ROM = 16'h0008;
            5'd10: ROM = 16'h0004;
            5'd11: ROM = 16'h0002;
            5'd12: ROM = 16'h0001;
            default: ROM = 16'h0001;
        endcase
    end

    // -------------------------
    // DATAPATH
    // -------------------------

    assign zval = (zsel == 2'b00) ? z0 :
                  (zsel == 2'b01) ? 16'h0000 :
                  (zsel == 2'b10) ? zn : 16'h0000;

    always @(posedge clk)
        if (rst) zj <= 0;
        else zj <= zval;

    assign di = (m == 0) ? zj[15] : (~yj[15]);
    assign zi = (m == 0) ? ROM : (16'h1000 >>> itr);
    assign zn = (di == 0) ? zj - zi : zj + zi;

    // y
    assign yval = (ysel == 0) ? 0 : yn;
    always @(posedge clk)
        if (rst) yj <= 0;
        else yj <= yval;

    assign yi = xj >>> itr;
    assign yn = (di == 0) ? yj + yi : yj - yi;

    // x
    assign xval = (xsel == 0) ? 16'h1000 : xn;
    always @(posedge clk)
        if (rst) xj <= 16'h1000;
        else xj <= xval;

    assign xi = yj >>> itr;
    assign xn = (di == 0 && m == 0) ? xj + xi :
                (di == 1 && m == 0) ? xj - xi :
                xj;

    // iterador
    always @(posedge clk)
        if (rst || clear)
            itr <= 5'd1;
        else if (!hold)
            itr <= itr + 1;

    // extremos
    assign extremeCheckP = z0 - 16'h4000;
    assign extremeCheckN = z0 - 16'hC000;

    // -------------------------
    // FSM (CORRIGIDA)
    // -------------------------
    always @(*) begin
        // defaults
        NS = CS;
        extreme_next = extreme;

        m = 0;
        ysel = 0;
        xsel = 0;
        zsel = 0;

        hold = 1;
        clear = 1;

        flag = 0;

        case(CS)

            RST: begin
                if (extremeCheckP[15] == 0 || extremeCheckN[15] == 1)
                    NS = EXTR;
                else
                    NS = TANH;
            end

            EXTR: begin
                if(extremeCheckP[15]==0 && z0[15]==0) begin
                    extreme_next = 2'b01;
                    flag = 1;
                    NS = RST;
                end 
                else if(extremeCheckN[15]==1 && z0[15]==1) begin
                    extreme_next = 2'b10;
                    flag = 1;
                    NS = RST;
                end
            end

            TANH: begin
                ysel = 1;
                xsel = 1;

                if(itr == 5'd14) begin
                    m = 1;
                    zsel = 1;
                    NS = DIVIDE;
                end else begin
                    zsel = 2;
                    clear = 0;
                    NS = REPEAT;
                end
            end

            REPEAT: begin
                ysel = 1;
                xsel = 1;
                zsel = 2;
                hold = 0;
                clear = 0;
                NS = TANH;
            end

            DIVIDE: begin
                if(itr == 5'd14) begin
                    flag = 1;
                    NS = RST;
                end else begin
                    m = 1;
                    ysel = 1;
                    xsel = 1;
                    zsel = 2;
                    hold = 0;
                    clear = 0;
                    NS = DIVIDE;
                end
            end

        endcase
    end

    // -------------------------
    // REGISTRADORES
    // -------------------------
    always @(posedge clk) begin
        if (rst)
            CS <= RST;
        else
            CS <= NS;
    end

    always @(posedge clk) begin
        if (rst)
            extreme <= 0;
        else
            extreme <= extreme_next;
    end

    // -------------------------
    // SAÍDA
    // -------------------------
reg signed [15:0] out_reg;
assign out = out_reg;

always @(posedge clk) begin
    if (rst)
        out_reg <= 0;
    else if (flag)
        out_reg <= zj;   // resultado final
end


    // -------------------------
    // DEBUG (opcional)
    // -------------------------
   // always @(posedge clk) begin
   //     if (!rst) begin
   //         $display("[CORDIC] itr=%0d z=%d x=%d y=%d state=%b",
   //             itr, zj, xj, yj, CS);
   //     end
   // end

endmodule