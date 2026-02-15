// Fixed UART TX with 16x Oversampling
module uart_tx_fixed (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,  // Trigger for transmission
    input  wire       s_tick,    // 16x baud rate tick from baud_gen
    input  wire [7:0] tx_data,
    output reg        tx,
    output reg        tx_busy,
    output reg        tx_done
);

    // State encoding
    localparam [1:0]
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11;

    reg [1:0]  state;
    reg [3:0]  s_tick_cnt;  // Counts 0-15 (16 ticks per bit)
    reg [2:0]  bit_cnt;     // Counts 0-7 (8 data bits)
    reg [7:0]  shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            s_tick_cnt <= 4'd0;
            bit_cnt    <= 3'd0;
            shift_reg  <= 8'h00;
            tx         <= 1'b1;   // Idle line is HIGH
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
        end else begin
            tx_done <= 1'b0; // Default: tx_done is a single-cycle pulse
            
            case (state)
                IDLE: begin
                    tx         <= 1'b1;
                    tx_busy    <= 1'b0;
                    s_tick_cnt <= 4'd0;
                    bit_cnt    <= 3'd0;
                    
                    if (tx_start) begin
                        tx        <= 1'b0;    // Immediately pull low for START bit
                        tx_busy   <= 1'b1;
                        shift_reg <= tx_data; // Load data to transmit
                        state     <= START;
                    end
                end

                START: begin
                    tx <= 1'b0;  // Hold START bit low
                    
                    if (s_tick) begin
                        if (s_tick_cnt == 4'd15) begin
                            // Completed 16 ticks (one full bit period)
                            s_tick_cnt <= 4'd0;
                            tx         <= shift_reg[0]; // Drive first data bit
                            state      <= DATA;
                        end else begin
                            s_tick_cnt <= s_tick_cnt + 1'b1;
                        end
                    end
                end

                DATA: begin
                    if (s_tick) begin
                        if (s_tick_cnt == 4'd15) begin
                            // Completed one bit period
                            s_tick_cnt <= 4'd0;
                            
                            if (bit_cnt == 3'd7) begin
                                // All 8 bits sent
                                bit_cnt <= 3'd0;
                                tx      <= 1'b1; // Drive STOP bit
                                state   <= STOP;
                            end else begin
                                // Shift to next bit
                                bit_cnt   <= bit_cnt + 1'b1;
                                shift_reg <= {1'b0, shift_reg[7:1]};
                                tx        <= shift_reg[1]; // Pre-drive next bit
                            end
                        end else begin
                            s_tick_cnt <= s_tick_cnt + 1'b1;
                            tx         <= shift_reg[0]; // Hold current bit
                        end
                    end
                end

                STOP: begin
                    tx <= 1'b1;  // Hold STOP bit high
                    
                    if (s_tick) begin
                        if (s_tick_cnt == 4'd15) begin
                            // Completed STOP bit
                            s_tick_cnt <= 4'd0;
                            tx_done    <= 1'b1; // Signal completion
                            tx_busy    <= 1'b0;
                            state      <= IDLE;
                        end else begin
                            s_tick_cnt <= s_tick_cnt + 1'b1;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
