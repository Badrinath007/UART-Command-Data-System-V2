module baud_gen_fixed #(
    parameter N = 27,
    parameter BAUD = 115200,
    parameter CLK_FREQ = 50_000_000
)(
    input  wire clk,
    input  wire rst_n,
    output wire tick
);

    // --- Verilog-2001 Constant Function for log2 ---
    function integer clog2;
        input integer value;
        begin
            value = value - 1;
            for (clog2 = 0; value > 0; clog2 = clog2 + 1)
                value = value >> 1;
        end
    endfunction
    // -----------------------------------------------

    // Automatically calculate the counter width
    localparam WIDTH = clog2(N);

    // Use the calculated width
    reg [WIDTH-1:0] count_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            count_reg <= 0;
        else if (count_reg == N-1)
            count_reg <= 0;
        else
            count_reg <= count_reg + 1;
    end
    
    assign tick = (count_reg == N-1);
    
endmodule
