module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    input  wire       s_tick,
    output reg [7:0]  rx_data,
    output reg        rx_done,
    output reg        framing_err // Restored
);
    localparam [2:0] ST_IDLE=3'd0, ST_START=3'd1, ST_DATA=3'd2, ST_STOP=3'd3, ST_DONE=3'd4;
    reg [2:0] state;
    reg [3:0] s_tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE; rx_done <= 0; framing_err <= 0;
        end else begin
            rx_done <= 0;
            case (state)
                ST_IDLE: if (!rx) begin state <= ST_START; s_tick_cnt <= 0; end
                ST_START: if (s_tick) begin
                    if (s_tick_cnt == 7) begin state <= ST_DATA; s_tick_cnt <= 0; bit_cnt <= 0; end
                    else s_tick_cnt <= s_tick_cnt + 1;
                end
                ST_DATA: if (s_tick) begin
                    if (s_tick_cnt == 15) begin
                        s_tick_cnt <= 0; shift_reg <= {rx, shift_reg[7:1]};
                        if (bit_cnt == 7) state <= ST_STOP;
                        else bit_cnt <= bit_cnt + 1;
                    end else s_tick_cnt <= s_tick_cnt + 1;
                end
                ST_STOP: if (s_tick) begin
                    if (s_tick_cnt == 15) begin
                        state <= ST_DONE;
                        framing_err <= (rx == 1'b0); // If stop bit is low, error!
                    end else s_tick_cnt <= s_tick_cnt + 1;
                end
                ST_DONE: begin rx_done <= 1; rx_data <= shift_reg; state <= ST_IDLE; end
            endcase
        end
    end
endmodule
