module fifo #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    wr_en,
    input  wire [DATA_WIDTH-1:0]   wr_data,

    input  wire                    rd_en,
    output wire [DATA_WIDTH-1:0]   rd_data,

    output wire                    full,
    output wire                    empty,
    output wire                    almost_full,
    output wire                    almost_empty,
    output wire [$clog2(FIFO_DEPTH):0]  data_count
);

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    reg [DATA_WIDTH-1:0] memory [0:FIFO_DEPTH-1];
	 reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    reg [ADDR_WIDTH:0] rd_ptr;
    reg [ADDR_WIDTH:0] wr_ptr;

    // Write pointer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_ptr <= 0;
        else if (wr_en && !full)
            wr_ptr <= wr_ptr + 1'b1;
    end

    // Read pointer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_ptr <= 0;
        else if (rd_en && !empty)
            rd_ptr <= rd_ptr + 1'b1;
    end

    // Write memory
    always @(posedge clk) begin
        if (wr_en && !full)
            memory[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
    end
	 // --- ADD THIS BLOCK ---
    integer i;
    initial begin
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
    end
    // ----------------------

    // ✅ TRUE combinational read
    assign rd_data = memory[rd_ptr[ADDR_WIDTH-1:0]];

    // Status flags
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]) &&
                   (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]);

    assign data_count = wr_ptr - rd_ptr;

    assign almost_full  = (data_count >= FIFO_DEPTH-1);
    assign almost_empty = (data_count <= 1);

endmodule