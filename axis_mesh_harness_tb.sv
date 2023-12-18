`timescale 1ns / 1ps

module axis_mesh_harness_tb();
    localparam NUM_ROWS = 2;
    localparam NUM_COLS = 2;
    localparam DATA_WIDTH = 32;
    localparam TDEST_WIDTH = $clog2(NUM_ROWS * NUM_COLS); // can use a function based on num_rows and num_cols
    localparam TID_WIDTH = $clog2(NUM_ROWS * NUM_COLS);
    localparam SERIALIZATION_FACTOR = 1; // can set to one, make another plot with SERIALIZATION_FACTOR = 1
    localparam COUNT_WIDTH = 32;
    localparam TDATA_WIDTH = 512;
    localparam NUM_PACKETS = 65536; //2 << 16

    localparam int DEST_SEED[NUM_ROWS * NUM_COLS] = {
        //123,445,788,985,
        //456,234,567,189,
        //500,220,290,240,
        643,330,341,278};

    localparam int LOAD_SEED[NUM_ROWS * NUM_COLS] = {
        //18740,18500,18441,10301,
        //15213,21127,12345,99101,
        //18447,18221,18240,18100,
        18643,18580,18725,18622};

    logic clk, clk_noc, rst_n;
    logic [TDATA_WIDTH / 2 - 1 : 0] ticks;

    logic                       axis_in_tvalid  [NUM_ROWS][NUM_COLS];
    logic                       axis_in_tready  [NUM_ROWS][NUM_COLS];
    logic [TDATA_WIDTH - 1 : 0]  axis_in_tdata   [NUM_ROWS][NUM_COLS];
    logic                       axis_in_tlast   [NUM_ROWS][NUM_COLS];
    logic [TDEST_WIDTH - 1 : 0] axis_in_tdest   [NUM_ROWS][NUM_COLS];
    logic [TID_WIDTH - 1 : 0]   axis_in_tid     [NUM_ROWS][NUM_COLS];

    logic                       axis_out_tvalid [NUM_ROWS][NUM_COLS];
    logic                       axis_out_tready [NUM_ROWS][NUM_COLS];
    logic [TDATA_WIDTH - 1 : 0]  axis_out_tdata  [NUM_ROWS][NUM_COLS];
    logic                       axis_out_tlast  [NUM_ROWS][NUM_COLS];
    logic [TDEST_WIDTH - 1 : 0] axis_out_tdest  [NUM_ROWS][NUM_COLS];
    logic [TID_WIDTH - 1 : 0]   axis_out_tid    [NUM_ROWS][NUM_COLS];

    logic                       done            [NUM_ROWS][NUM_COLS];
    logic                       start           [NUM_ROWS][NUM_COLS];
    logic [COUNT_WIDTH - 1 : 0] sent_packets    [NUM_ROWS][NUM_COLS][2**TDEST_WIDTH];
    logic [COUNT_WIDTH - 1 : 0] recv_packets    [NUM_ROWS][NUM_COLS][2**TID_WIDTH];
    logic                       error           [NUM_ROWS][NUM_COLS];


    logic [COUNT_WIDTH - 1 : 0] packet_counts  [NUM_ROWS][NUM_COLS];
    logic [TDATA_WIDTH / 2 - 1 : 0] total_latencies [NUM_ROWS][NUM_COLS];

    logic [TDATA_WIDTH / 2 - 1 : 0] start_tick, end_tick;
    logic [15:0] load;

    always_ff @(posedge clk) begin
        if (rst_n == 0) begin
            ticks <= 0;
        end else begin
            ticks <= ticks + 1'b1;
        end
    end

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    initial begin
        clk_noc = 0;
        forever begin
            #5 clk_noc = ~clk_noc;
        end
    end

    logic all_done;
    int total_packet_count;
    logic [TDATA_WIDTH / 2 - 1 : 0] sum_latency;
    int sum_packets;
    int fd1, fd2, fd3;
    logic[16:0] load_factor;

    initial begin
        load_factor = 0;
        fd1 = $fopen("/home/yuhez/noc/testbench/latency_record.txt", "w");
        fd2 = $fopen("/home/yuhez/noc/testbench/packet_counts.txt", "w");
        fd3 = $fopen("/home/yuhez/noc/testbench/e2e_latency.txt", "w");
       

        for (int ld = 0; ld < 20; ld = ld+1)begin //sweep across various load
            load_factor = load_factor + 2048;
            load = load_factor - 1;
            
            $display("begin executing load = %0d", load);
            rst_n = 1'b0;
            for (int i = 0; i < NUM_ROWS; i = i + 1) begin
                for (int j = 0; j < NUM_COLS; j = j + 1) begin
                    start[i][j] = 1'b0;
                end
            end
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            for (int i = 0; i < NUM_ROWS; i = i + 1) begin
                for (int j = 0; j < NUM_COLS; j = j + 1) begin
                    start[i][j] = 1'b1;
                end
            end

            start_tick = ticks;

            @(posedge clk);
            @(posedge clk);
            @(posedge clk);

            for (int i = 0; i < NUM_ROWS; i = i + 1) begin
                for (int j = 0; j < NUM_COLS; j = j + 1) begin
                    start[i][j] = 1'b1;
                end
            end

            all_done = 1'b0;
            while (all_done == 0)begin
                @(posedge clk);
                
                
                total_packet_count = 0;
                for (int i = 0; i < NUM_ROWS; i = i + 1) begin
                    for (int j = 0; j < NUM_COLS; j = j + 1) begin
                        total_packet_count += packet_counts[i][j];
                    end
                end

                all_done = total_packet_count >= (NUM_PACKETS * NUM_COLS * NUM_ROWS);
                
                if (ticks >= (1<<27)) begin 
                    $display("Timeout! at load = %0d", load);
                    $fclose(fd1);
                    $fclose(fd2);
                    $fclose(fd3);
                    $finish;
                end
            end
            
            
            if (all_done) begin // does the all_done signal only depend on traffic generator?
                end_tick = ticks;

                sum_latency = 0;
                for (int i = 0; i < NUM_ROWS; i = i + 1) begin
                    for (int j = 0; j < NUM_COLS; j = j + 1) begin
                        sum_latency += total_latencies[i][j];
                        
                    end
                end
                $fwrite(fd1, "%d\n", sum_latency);
                
                
                sum_packets = 0;
                for (int i = 0; i < NUM_ROWS; i = i + 1) begin
                    for (int j = 0; j < NUM_COLS; j = j + 1) begin
                        sum_packets += packet_counts[i][j];
                    end
                end
                $fwrite(fd2, "%d\n", sum_packets);
                
                

                $fwrite(fd3, "%d   ", start_tick);
                $fwrite(fd3, "%d   ", end_tick);
                $fwrite(fd3, "%d   ", load);
                $fwrite(fd3, "\n");
                
                
                $display("finish executing load = %0d\n", load);

            end

            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
        
        end  //sweep load
        $display("All done!");
        $fclose(fd1);
        $fclose(fd2);
        $fclose(fd3);
        $finish;
    end

    generate begin: harness_gen
        genvar i, j;
        for (i = 0; i < NUM_ROWS; i = i + 1) begin: for_rows
            for (j = 0; j < NUM_COLS; j = j + 1) begin: for_cols
            axis_tg #(
                .DEST_SEED      (DEST_SEED[i * NUM_COLS + j]),
                .LOAD_SEED      (LOAD_SEED[i * NUM_COLS + j]),

                .COUNT_WIDTH    (COUNT_WIDTH),
                .TID            (i * NUM_COLS + j),
                .NOC_NUM_ENDPOINTS (NUM_COLS * NUM_ROWS),
                .TDATA_WIDTH    (TDATA_WIDTH),
                .TDEST_WIDTH    (TDEST_WIDTH),
                .TID_WIDTH      (TID_WIDTH))
            tg_inst (
                .clk,
                .rst_n,

                .load           (load),
                .num_packets    (NUM_PACKETS),

                .start          (start[i][j]),
                .ticks,
                .done           (done[i][j]),
                .sent_packets   (sent_packets[i][j]),

                

                .axis_out_tvalid    (axis_in_tvalid[i][j]),
                .axis_out_tready    (axis_in_tready[i][j]),
                .axis_out_tdata     (axis_in_tdata[i][j]),
                .axis_out_tlast     (axis_in_tlast[i][j]),
                .axis_out_tid       (axis_in_tid[i][j]),
                .axis_out_tdest     (axis_in_tdest[i][j])
            );

            axis_checker #(
                .COUNT_WIDTH    (COUNT_WIDTH),
                .TDEST          (i * NUM_COLS + j),
                .NUM_ROUTERS    (2**TID_WIDTH),
                .TDATA_WIDTH    (TDATA_WIDTH),
                .TDEST_WIDTH    (TDEST_WIDTH),
                .TID_WIDTH      (TID_WIDTH))
            checker_inst (
                .clk,
                .rst_n,

                .ticks,
                .recv_packets   (recv_packets[i][j]),
                .error          (error[i][j]),

                .axis_in_tvalid (axis_out_tvalid[i][j]),
                .axis_in_tready (axis_out_tready[i][j]),
                .axis_in_tdata  (axis_out_tdata[i][j]),
                .axis_in_tlast  (axis_out_tlast[i][j]),
                .axis_in_tid    (axis_out_tid[i][j]),
                .axis_in_tdest  (axis_out_tdest[i][j]),

                .packet_count (packet_counts[i][j]),
                .total_latency (total_latencies[i][j])
            );
            end
        end
    end
    endgenerate

    axis_mesh #(
        .NUM_ROWS                   (NUM_ROWS),
        .NUM_COLS                   (NUM_COLS),
        .PIPELINE_LINKS             (1),

        .TDEST_WIDTH                (TDEST_WIDTH),
        .TID_WIDTH                  (TID_WIDTH),
        .TDATA_WIDTH                (TDATA_WIDTH),
        .SERIALIZATION_FACTOR       (SERIALIZATION_FACTOR),
        .CLKCROSS_FACTOR            (1),
        .SINGLE_CLOCK               (1),
        .SERDES_IN_BUFFER_DEPTH     (4),
        .SERDES_OUT_BUFFER_DEPTH    (4),
        .SERDES_EXTRA_SYNC_STAGES   (0),

        .FLIT_BUFFER_DEPTH          (4),
        .ROUTING_TABLE_PREFIX       ("routing_tables/mesh_2x2/"),
        .ROUTER_PIPELINE_OUTPUT     (1),
        .ROUTER_DISABLE_SELFLOOP    (0),
        .ROUTER_FORCE_MLAB          (0)
        ) dut (
        .clk_noc(clk_noc),
        .clk_usr(clk),
        .rst_n,

        .axis_in_tvalid ,
        .axis_in_tready ,
        .axis_in_tdata  ,
        .axis_in_tlast  ,
        .axis_in_tid    ,
        .axis_in_tdest  ,

        .axis_out_tvalid,
        .axis_out_tready,
        .axis_out_tdata ,
        .axis_out_tlast ,
        .axis_out_tid   ,
        .axis_out_tdest
    );

endmodule: axis_mesh_harness_tb