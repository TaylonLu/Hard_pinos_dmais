`timescale 1ns/1ps

module tb_sigmoid;

reg signed [15:0] d_in;
wire signed [15:0] d_out;

ativacao uut (
    .d_in(d_in),
    .d_out(d_out)
);

function real to_real;
    input signed [15:0] v;
    begin
        to_real = v / 256.0;
    end
endfunction

integer i;

initial begin
    $display("Teste da Sigmoid");
    $display("Entrada\t\tSaída");
    $display("-----------------------------");

    for (i = -1536; i <= 1536; i = i + 128) begin
        d_in = i;
        #10;
        $display("%0.4f\t->\t%0.4f", to_real(d_in), to_real(d_out));
    end

    $finish;
end

endmodule