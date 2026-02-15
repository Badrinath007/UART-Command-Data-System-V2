`timescale 1ns / 1ps

module uart_fifo_tb;

    // --- 1. Parameter Definitions ---
    parameter CLK_FREQ   = 50_000_000;
    parameter BAUD       = 115200;
    parameter FIFO_DEPTH = 16;
    localparam BIT_PERIOD = 1_000_000_000 / BAUD; // in ns

    // --- 2. Signal Declarations (Matching RTL Ports) ---
    logic       clk, rst_n;
    logic       uart_rx;
    wire        uart_tx;
    wire        error_led;
    wire        rx_fifo_full, rx_fifo_empty;
    wire        tx_fifo_full, tx_fifo_empty;
    logic       user_rd_en;
    wire [7:0]  user_rx_data;
    logic       user_wr_en;
    logic [7:0] user_tx_data;

    // Internal test counters
    int total_tests = 0;
    int errors = 0;

    // --- 3. DUT Instantiation ---
    uart_top_with_fifo #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD(BAUD),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (.*);

    // --- 4. Clock Generation ---
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // 50MHz
    end

    // --- 5. Helper Tasks ---

    // Send a single raw byte over UART
    task send_uart_byte(input [7:0] data);
        int i;
        begin
            uart_rx = 0; // Start bit
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_PERIOD);
            end
            uart_rx = 1; // Stop bit
            #(BIT_PERIOD);
        end
    endtask

    // Send a full protocol packet: [Header(0x55)] [Cmd] [Data] [Checksum]
    task send_packet(input [7:0] cmd, input [7:0] data);
        logic [7:0] checksum;
        begin
            checksum = cmd + data;
            send_uart_byte(8'h55);     // Header
            send_uart_byte(cmd);      // Command
            send_uart_byte(data);     // Data
            send_uart_byte(checksum); // Checksum
        end
    endtask

    // --- 6. Main Test Sequence ---
    initial begin
        $monitor("TIME: %0t | X-CHECK -> FSM: %b | REG_FILE: %h | ERROR_LED: %b",$time, dut.p_state, dut.reg_file, error_led);
        // Initialize
        rst_n = 0;
        uart_rx = 1;
        user_rd_en = 0;
        user_wr_en = 0;
        user_tx_data = 8'h00;

        #100 rst_n = 1;
        #1000;

        $display("\n--- STARTING BUG-FREE TAPEOUT VERIFICATION ---");

        // [TEST 1] Standard Protocol Check
        total_tests++;
        $display("[TEST 1] Sending Valid Packet (Reg Write 0xA5)...");
        send_packet(8'h01, 8'hA5);
        #200000; // Wait for processing
        if (dut.reg_file == 8'hA5) 
            $display("  [PASS] Register updated correctly.");
        else begin
            $display("  [FAIL] Register mismatch! Got: 0x%h", dut.reg_file);
            errors++;
        end

        // [TEST 2] Sending Bad Checksum (Data Integrity Check)
        total_tests++;
        
        $display("\n[TEST 2] Sending Bad Checksum (Expect Rejection)...");
        begin
            // 1. Capture the "Safe" value (should be 0xA5 from Test 1)
            logic [7:0] safe_value;
            safe_value = dut.reg_file; 
        
            // 2. Send a Corrupted Packet (CMD=0x01, DATA=0xFF, CHKSUM=0x00 -> WRONG)
            send_uart_byte(8'h55); // Sync
            #(BIT_PERIOD);
            send_uart_byte(8'h01); // Cmd
            #(BIT_PERIOD);
            send_uart_byte(8'hEE); // Data (We changed to 0xEE from 0xFF)
            #(BIT_PERIOD);
            send_uart_byte(8'h00); // Bad Checksum
            
            // 3. Wait for FSM to process
            #(BIT_PERIOD * 4); 

            // 4. Assert Results
            if (dut.error_led === 1'b1 && dut.reg_file === safe_value) begin
                $display("  [PASS] LED High & Data Protected (Reg=0x%h)", dut.reg_file);
            end else begin
                $display("  [FAIL] LED=%b (Exp:1) | Reg=0x%h (Exp:0x%h)", dut.error_led, dut.reg_file, safe_value);
                errors++;
            end
        end
        

        // [TEST 3] Burst Stress (Force FIFO Full)
        $display("\n[TEST 3] Bursting to Fill FIFO (Using Force)...");
        
        // --- THE FIX: Paralyze the FSM so it can't empty the FIFO ---
        // We force the internal 'fsm_rx_pop' signal to 0.
        // The UART will keep writing, but the FSM cannot read.
        force dut.fsm_rx_pop = 1'b0; 
        
        // 1. Burst 18 bytes (FIFO depth is 16, so this guarantees overflow)
        for (int j = 0; j < 18; j++) begin
            send_uart_byte(8'hAA); 
            // Minimal delay just to separate bytes on the wire
            #(BIT_PERIOD); 
        end

        // 2. Check if Full flag triggered
        if (rx_fifo_full === 1'b1) begin
            $display("  [PASS] FIFO hit FULL state successfully.");
        end else begin
            $display("  [FAIL] FIFO did not fill. Count=%d", dut.rx_fifo_inst.data_count);
            errors++;
        end

        // 3. CLEANUP: Release the signal so FSM can work again
        release dut.fsm_rx_pop;
        
        // 4. Wait for FSM to drain the FIFO (Recover)
        wait(rx_fifo_empty == 1'b1);
        $display("  [INFO] FSM recovered and drained FIFO.");

        // [TEST 4] Reset Mid-Packet (FSM Recovery Test)
        
        begin
            $display("\n[TEST 4] Reset Mid-Packet (FSM Recovery Test)...");        
            // 1. Start sending a packet (Sync + Cmd)
            send_uart_byte(8'h55); 
            #(BIT_PERIOD * 10);
            send_uart_byte(8'h01); 
            #(BIT_PERIOD * 5); // Reset exactly in the middle of command reception
        
            // 2. Trigger asynchronous reset
            rst_n = 0;
            #(20); // Hold reset for 1 clock cycle
            rst_n = 1;
            #(20);
            
            // 3. Verify Recovery
            if (dut.p_state == 2'b00 && rx_fifo_empty) begin
                $display("   [PASS] FSM returned to IDLE and FIFO cleared.");
            end 
            else begin
                $display("   [FAIL] FSM/FIFO hung after mid-packet reset! State: %b", dut.p_state);
            end
        end

        // Final Assessment
        $display("\n===============================\n");
        $display(" FINAL REPORT: %0d Tests, %0d Errors", total_tests, errors);
        if (errors == 0) $display(" STATUS: SYSTEM READY FOR TAPEOUT");
        else             $display(" STATUS: SYSTEM FAILED - BUGS DETECTED");
        $display("===============================\n");

        $stop;
    end
    // --- ULTIMATE STABILITY SENTRY ---
    // This lives inside the testbench but acts as a secondary observer
    reg [7:0] shadow_reg; 

    always @(posedge clk) begin
        if (!rst_n) begin
            shadow_reg <= 8'h00;
        end else begin
            // 1. Ghost Hunter: FSM Check
            if ($isunknown(dut.p_state)) begin
                $display("\n[FATAL] %0t: FSM hit X-state!", $time);
                $stop;
            end

            // 2. Capture a 'Known Good' copy of the register 
            // We only update our shadow copy when the FSM is IDLE and healthy
            if (dut.p_state == 2'b00 && dut.error_led == 1'b0) begin
                shadow_reg <= dut.reg_file;
            end

            // 3. The Moment of Truth: Check when a packet finishes
            // When FSM moves from CHKSUM(11) -> IDLE(00)
            if (dut.p_state == 2'b11) begin
                wait(dut.p_state == 2'b00); 
                #100; // Let simulator delta-cycles settle
                
                if (dut.error_led == 1'b1) begin
                     // If there was an error, the hardware register MUST match our shadow copy
                     if (dut.reg_file !== shadow_reg) begin
                         $display("\n[FATAL ERROR] %0t: Register corrupted! HW: %h, Expected: %h", $time, dut.reg_file, shadow_reg);
                         $stop;
                     end else begin
                         $display("   [SENTRY] Verified: Checksum Error detected, Register LOCKED at %h.", shadow_reg);
                     end
                end else begin
                     $display("   [SENTRY] Verified: Valid Packet accepted. Register updated.");
                end
            end
        end
    end

endmodule