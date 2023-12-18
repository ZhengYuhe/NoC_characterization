`timescale 1ns / 1ps
// Implements uniform random traffic generation

module axis_tg #(
    parameter DEST_SEED = 1234,
    parameter LOAD_SEED = 152123,

    parameter COUNT_WIDTH = 32,
    parameter TID = 0,

    parameter NOC_NUM_ENDPOINTS = 3, // I added this
    parameter TDATA_WIDTH = 512,
    parameter TDEST_WIDTH = 2,
    parameter TID_WIDTH = 2) (
    input   wire                                clk,
    input   wire                                rst_n,

    input   wire    [15 : 0]                    load,
    input   wire    [COUNT_WIDTH - 1 : 0]       num_packets,

    input   wire                                start,
    input   wire    [TDATA_WIDTH / 2 - 1 : 0]   ticks,
    output  logic                               done,
    output  logic   [COUNT_WIDTH - 1 : 0]       sent_packets[2**TDEST_WIDTH],

   

    output  logic                               axis_out_tvalid,
    input   wire                                axis_out_tready,
    output  logic   [TDATA_WIDTH - 1 : 0]       axis_out_tdata,
    output  logic                               axis_out_tlast,
    output  logic   [TID_WIDTH - 1 : 0]         axis_out_tid,
    output  logic   [TDEST_WIDTH - 1 : 0]       axis_out_tdest
);

    enum {
        IDLE,
        RUNNING, 
        FINISH
    } state, next_state;

    logic [TDEST_WIDTH - 1 : 0] dest;
    logic load_packet;
    logic [COUNT_WIDTH - 1 : 0] total_sent_packets;

    logic [TDATA_WIDTH + TDEST_WIDTH -1 : 0] tg_buffer_in, tg_buffer_out; //should enq the entire packet
    logic tg_q_full, tg_q_empty;
    logic legal_enq, legal_deq;
    //packet goes into queue, should be based load
    assign tg_buffer_in = {ticks, {(TDATA_WIDTH / 2 - COUNT_WIDTH){1'b0}}, sent_packets[dest], dest}; 
    assign legal_enq = load_packet && (!tg_q_full) && (state == RUNNING);
    assign legal_deq = axis_out_tready && (!tg_q_empty);
    Queue #(
        .QUEUE_DEPTH(131072), // twice of num packets
        .DATA_WIDTH(TDATA_WIDTH + TDEST_WIDTH)
    ) tg_buffer(
        .clk(clk),
        .reset(!rst_n),
        .start(1'b0),
        .enq(legal_enq), // assume queue has infinite length, should see assertion error if queue is full
        .deq(legal_deq), // user check if should deq
        .data_in(tg_buffer_in),
        .data_out(tg_buffer_out),
        .full(tg_q_full), 
        .empty(tg_q_empty)
    );


    assign axis_out_tdata = tg_buffer_out[TDATA_WIDTH + TDEST_WIDTH -1 : TDEST_WIDTH];
    assign axis_out_tlast = 1'b1;
    assign axis_out_tid = TID;
    assign axis_out_tdest = tg_buffer_out[TDEST_WIDTH - 1: 0];
    

    

    always_ff @(posedge clk) begin
        if (rst_n == 1'b0 || state == IDLE ) begin 
            total_sent_packets <= 0;
            for (int i = 0; i < 2**TDEST_WIDTH; i++) begin
                sent_packets[i] <= 0;
            end
        end else begin
            if (legal_enq) begin 
                total_sent_packets <= total_sent_packets + 1;
                sent_packets[dest] <= sent_packets[dest] + 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n == 1'b0) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        axis_out_tvalid = 1'b0;
        done = 1'b0;

        case (state)
            IDLE: begin
                done = 1'b1;
                axis_out_tvalid = 1'b0; //
                if (start) begin
                    next_state = RUNNING;
                end
            end
            RUNNING: begin
                // Making an assumption that ready is always high
                // otherwise load produced will be lower than required
                axis_out_tvalid = legal_deq; 
                if (total_sent_packets >= num_packets) begin
                    next_state = FINISH;
                    
                end
                    
                
            end 
            FINISH: begin
                next_state = FINISH;
                axis_out_tvalid = legal_deq;
                done = 1'b1;
            end
        endcase
    end

    
    random_dest #(
        .SEED(DEST_SEED),
        .NOC_NUM_ENDPOINTS(NOC_NUM_ENDPOINTS)
    ) dest_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (1'b1),
        .dest   (dest)
    );
    
    random_load #(
        .SEED(LOAD_SEED)) load_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .load   (load),
        .load_packet (load_packet)
    );

    
endmodule: axis_tg

module random_dest #(
    parameter SEED = 123434,
    parameter NOC_NUM_ENDPOINTS = 3)(
    input logic clk,
    input logic rst_n,
    input logic en,
    output logic [$clog2(NOC_NUM_ENDPOINTS)-1:0] dest
    );

    logic [31:0] rand32; 
    initial begin
        rand32 = $urandom(SEED);
        forever begin
            @(posedge clk); // should this be posedge or negedge
            rand32 = $urandom(); // look into more urandom syntax on how to use seed
            dest = rand32 % NOC_NUM_ENDPOINTS;
        end
    end
endmodule: random_dest

module random_load #(
    parameter SEED = 12345)(
    input logic clk,
    input logic rst_n,
    input logic [15:0] load,
    output logic load_packet
    );

    logic [31:0] rand32; 
    logic [15:0] load_factor;

    initial begin
        rand32 = $urandom(SEED);
        forever begin
            @(posedge clk); // should this be posedge or negedge
            rand32 = $urandom();
            load_factor = rand32[15:0];
            load_packet = load_factor < load;
            
        end
    end
endmodule: random_load

module lfsr_64 #(
    parameter SEED = 64'h48D34421DF9848B) (
    input   wire            clk,
    input   wire            rst_n,

    input   wire            ena,
    output  logic [63 : 0]  q
    );

    always_ff @(posedge clk) begin
        if (rst_n == 1'b0) begin
            q <= SEED;
        end else begin
            if (ena) begin
                q[63 : 1] <= q[62 : 0];
                q[0] <= ~(q[63] ^ q[62] ^ q[60] ^ q[59]);
            end
        end
    end

endmodule: lfsr_64

module lfsr_16 #(
    parameter SEED = 16'h92DA) (
    input   wire            clk,
    input   wire            rst_n,

    input   wire            ena,
    output  logic [15 : 0]  q
    );

    always_ff @(posedge clk) begin
        if (rst_n == 1'b0) begin
            q <= SEED;
        end else begin
            if (ena) begin
                q[15 : 1] <= q[14 : 0];
                q[0] <= ~(q[15] ^ q[14] ^ q[12] ^ q[3]);
            end
        end
    end

endmodule: lfsr_16




module Queue #(parameter DATA_WIDTH = 512, parameter QUEUE_DEPTH = 131072)(
  input wire clk,
  input wire reset,
  input wire start,
  input wire enq,
  input wire deq,
  input logic [DATA_WIDTH-1:0] data_in,
  output logic [DATA_WIDTH-1:0] data_out,
  output logic empty,
  output logic full
  );

  // Internal storage for the queue data
  logic [DATA_WIDTH-1:0] queue [QUEUE_DEPTH-1:0];

  // Internal pointers
  logic [$clog2(QUEUE_DEPTH)-1:0] write_ptr;
  logic [$clog2(QUEUE_DEPTH)-1:0] read_ptr;
  

  // Wire to indicate if the queue is empty or full
  logic [$clog2(QUEUE_DEPTH)-1:0] filled_count;
  assign empty = (filled_count == 0);
  assign full = (filled_count == QUEUE_DEPTH);
  

  // Combinational logic to determine the output data
  
  
  assign data_out = queue[read_ptr];

  // Sequential logic for enqueue and dequeue operations
  always_ff @(posedge clk) begin
    if (reset) begin
      write_ptr <= 0;
      read_ptr <= 0;
      //data_out <= 0;
    end else begin
      if (enq && !full) begin
        queue[write_ptr] <= data_in;
        if (write_ptr < (QUEUE_DEPTH - 1)) begin
          write_ptr <= write_ptr + 1;
        end else begin
          write_ptr <= 0;
        end
      end

      if (deq && !empty) begin
        //data_out <= queue[read_ptr];
        if (read_ptr < (QUEUE_DEPTH - 1)) begin
          read_ptr <= read_ptr + 1;
        end else begin
          read_ptr <= 0;
        end
      end
    end
  end

  // Logic to count the number of filled slots in the queue
  always_ff @(posedge clk) begin
    if (reset) begin
      filled_count <= 0;
    end else begin
      if (enq && !deq && !full)
        filled_count <= filled_count + 1;
      else if (!enq && deq && !empty)
        filled_count <= filled_count - 1;
    end
  end

  always_ff @(posedge clk)begin
    if(full)begin
        $display("QUEUE is FULL !!!!!!!!!!!!!!!!!!!!!!");
    end 
    if (full && enq) begin
        $display("\n");
        $display("ENQ when Queus is full !!!!!!!!!!!!!!!!!!!!!");
        $display("\n");
    end
    if (empty && deq) begin
        $display("\n");
        $display("DEQUE when Queus is empty !!!!!!!!!!!!!!!!!!!!!!");
        $display("\n");
    end
  end

endmodule