module uart_top_with_fifo #(
    parameter CLK_FREQ   = 50_000_000,
    parameter BAUD       = 115200,
    parameter FIFO_DEPTH = 16
)(
    input  wire       clk, rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output reg        error_led,
    output wire       rx_fifo_full, rx_fifo_empty,
    output wire       tx_fifo_full, tx_fifo_empty,
    input  wire       user_rd_en,
    output wire [7:0] user_rx_data,
    input  wire       user_wr_en,
    input  wire [7:0] user_tx_data
	
);

    // Internal Signals
    wire [7:0] rx_data_raw;
    wire       rx_done_tick, tx_done_tick, tick;
    reg        tx_start, fsm_rx_pop;
    wire [7:0] tx_fifo_out;
    wire framing_err;
	
    
    // FSM States
    localparam ST_IDLE   = 2'd0, ST_CMD = 2'd1, ST_DATA = 2'd2, ST_CHKSUM = 2'd3;
    reg [1:0] p_state;
    reg [7:0] hold_cmd, hold_data, reg_file;
    
    // The Sync Fix
    reg wait_fifo; 

    // Arbitration Logic
    wire actual_rx_pop = user_rd_en || fsm_rx_pop;

    // --- Sub-Modules ---
    baud_gen_fixed #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) baud_gen_inst (
        .clk(clk), .rst_n(rst_n), .tick(tick)
    );

    uart_rx rx_inst (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx), .s_tick(tick),
        .rx_done(rx_done_tick), .rx_data(rx_data_raw),.framing_err(framing_err)
    );

    uart_tx_fixed tx_inst (
        .clk(clk), .rst_n(rst_n), .tx_start(tx_start), .s_tick(tick),
        .tx_data(tx_fifo_out), .tx_done(tx_done_tick), .tx(uart_tx),.tx_busy(tx_busy)
    );

    fifo #(.DATA_WIDTH(8), .FIFO_DEPTH(FIFO_DEPTH)) rx_fifo_inst (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx_done_tick), .wr_data(rx_data_raw),
        .rd_en(actual_rx_pop), .rd_data(user_rx_data),
        .full(rx_fifo_full), .empty(rx_fifo_empty),.almost_full(),   // Added for 18.1 compatibility
        .almost_empty(),  // Added
        .data_count()
    );

    fifo #(.DATA_WIDTH(8), .FIFO_DEPTH(FIFO_DEPTH)) tx_fifo_inst (
        .clk(clk), .rst_n(rst_n),
        .wr_en(user_wr_en), .wr_data(user_tx_data),
        .rd_en(tx_done_tick || (!tx_start && !tx_fifo_empty)),
        .rd_data(tx_fifo_out),
        .full(tx_fifo_full), .empty(tx_fifo_empty),
        .almost_full(),   // Added
        .almost_empty(),  // Added
        .data_count()     // Added
    );

    // TX Startup Logic
    always @(posedge clk) begin
        if (!rst_n) tx_start <= 0;
        else tx_start <= (!tx_fifo_empty && !tx_start);
    end

    // --- THE FIX: WAIT-STATE FSM ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_state    <= ST_IDLE;
            fsm_rx_pop <= 1'b0;
            reg_file   <= 8'h00;
            error_led  <= 1'b0;
            wait_fifo  <= 1'b0;
            hold_data  <= 8'h0;
            hold_cmd   <= 8'h0;
        end else begin
            fsm_rx_pop <= 1'b0; // Pulse default

            if (wait_fifo) begin
                // Spend 1 cycle doing nothing to let FIFO update rd_data
                wait_fifo <= 1'b0;
            end 
            else if (!rx_fifo_empty) begin
                case (p_state)
                    ST_IDLE: begin
                        if (user_rx_data == 8'h55) begin
                            fsm_rx_pop <= 1'b1;
                            wait_fifo  <= 1'b1; // Trigger wait for next state
                            p_state    <= ST_CMD;
                        end else begin
                            fsm_rx_pop <=1'b1;
                            wait_fifo  <= 1'b1;
                        end
                    end

                    ST_CMD: begin
                        hold_cmd   <= user_rx_data;
                        fsm_rx_pop <= 1'b1;
                        wait_fifo  <= 1'b1;
                        p_state    <= ST_DATA;
                    end

                    ST_DATA: begin
                        hold_data  <= user_rx_data;
                        fsm_rx_pop <= 1'b1;
                        wait_fifo  <= 1'b1;

                        p_state    <= ST_CHKSUM;
                    end

                    ST_CHKSUM: begin
                        // Checksum Match Logic
                        if (user_rx_data == (hold_cmd + hold_data)) begin
                           if (hold_cmd == 8'h01) begin
										reg_file <= hold_data;  
									end
									error_led <= 1'b0;
                        end 
                        
                        else begin
                            error_led <= 1'b1;
                            $display("  [FSM] FAIL: Checksum Error");
                        end
                        fsm_rx_pop <= 1'b1;
                        wait_fifo  <= 1'b1;
                        p_state    <= ST_IDLE;
                    end
                endcase
            end
        end
    end
    // Simulation-only safety checks
    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n) begin
            // Check 1: Prevent FIFO Underflow
            if (fsm_rx_pop && rx_fifo_empty) begin
                $display("!!! ASSERTION FAILED: FSM TRIED TO POP EMPTY FIFO at %0t", $time);
                $stop;
            end
            // Check 2: Prevent TX Over-triggering
            if (tx_start && tx_busy) begin
                $display("!!! ASSERTION FAILED: TX START ISSUED WHILE BUSY at %0t", $time);
                $stop;
            end
        end
    end
endmodule
