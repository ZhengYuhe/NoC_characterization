`timescale 1ns / 1ps
// Implements uniform random traffic generation

module axis_checker #(
    parameter COUNT_WIDTH = 32,
    parameter TDEST = 0,

    parameter TDATA_WIDTH = 512,
    parameter TDEST_WIDTH = 2,
    parameter TID_WIDTH = 2,
    parameter NUM_ROUTERS = 2) (
    input   wire                                clk,
    input   wire                                rst_n,

    input   wire    [TDATA_WIDTH / 2 - 1 : 0]   ticks,
    output  logic   [COUNT_WIDTH - 1 : 0]       recv_packets[NUM_ROUTERS],
    output  logic   [COUNT_WIDTH - 1 : 0]       total_recv_packets,
    output  logic                               error,

    input   wire                                axis_in_tvalid,
    output  logic                               axis_in_tready,
    input   wire    [TDATA_WIDTH - 1 : 0]       axis_in_tdata,
    input   wire                                axis_in_tlast,
    input   wire    [TID_WIDTH - 1 : 0]         axis_in_tid,
    input   wire    [TDEST_WIDTH - 1 : 0]       axis_in_tdest,

    output logic    [TDATA_WIDTH / 2 - 1 : 0]   total_latency,
    output logic    [COUNT_WIDTH - 1 : 0]       packet_count
);
    logic [TDATA_WIDTH / 2 - 1 : 0] start_tick, end_tick;
    logic [TDATA_WIDTH / 2 - 1 : 0] sent_tick;
    logic [COUNT_WIDTH - 1 : 0] sent_count;

    logic [TDATA_WIDTH / 2 - 1 : 0]   packet_latency;

    assign sent_tick = axis_in_tdata[TDATA_WIDTH - 1 : TDATA_WIDTH / 2];
    assign sent_count = axis_in_tdata[COUNT_WIDTH - 1 : 0];
    assign axis_in_tready = 1'b1;

    always_ff @(posedge clk) begin
        if (rst_n == 1'b0) begin
            for (int i = 0; i < 2 ** TID_WIDTH; i = i + 1) begin
                recv_packets[i] <= '0;
            end
            total_recv_packets <= '0;
            error <= 1'b0;
            total_latency <= 0;
            packet_count <= 0;
        end else begin
            if (axis_in_tvalid) begin
                if (total_recv_packets == '0) begin
                    start_tick <= ticks;
                end
                end_tick <= ticks;
                recv_packets[axis_in_tid] <= recv_packets[axis_in_tid] + 1'b1;

                // sum latency
                total_latency <= total_latency + ticks - sent_tick;
                packet_latency <= ticks - sent_tick;

                //$display("packet_latency: %0d", packet_latency);

                packet_count <= packet_count + 1;
                
                total_recv_packets <= total_recv_packets + 1'b1;
                if ((sent_count != recv_packets[axis_in_tid]) || (axis_in_tdest != TDEST)) begin
                    $display("ERROR RAISED at TDEST: %0d", TDEST);
                    $display("  axis_in_tid: %0d  axis_in_tdest: %0d", axis_in_tid, axis_in_tdest);
                    $display("  sent_tick: %0d  tick: %0d", sent_tick, ticks);
                    $display("  sent_count: %0d  recv_packets[%0d]: %0d", sent_count, axis_in_tid, recv_packets[axis_in_tid]);
                    $display("  total_recv_packets: %0d", total_recv_packets);
                    $display("\n");
                    $display("\n");
                    
                    
                    error <= 1'b1;
                end 
            end
        end
    end

    // synthesis translate_off
    real latency;

    always_ff @(posedge clk) begin
        if (rst_n == 1'b0) begin
            latency <= 0;
        end else begin
            if (axis_in_tvalid && axis_in_tready) begin
                latency <= (latency * total_recv_packets + (ticks - sent_tick)) / (total_recv_packets + 1'b1);
            end
        end
    end

    /*
    always_ff @(negedge rst_n) begin
        if (~rst_n) begin
            if (end_tick - start_tick != 0) begin
                $display("Id: %d, Total Recv Count: %d, Average latency: %f, Throughput: ", TDEST, total_recv_packets, latency, real'(total_recv_packets) / (end_tick - start_tick));
                $fflush;
            end else begin
                $display("Id: %d, Total Recv Count: %d, Average latency: %f, Throughput: undef", TDEST, total_recv_packets, latency);
                $fflush;
            end
        end
    end
    // synthesis translate_on
    */
endmodule: axis_checker