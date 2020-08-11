////////////////////////////////////////////////////////
// Module: Multicycle Otter Debugger
// Author: Trevor McKay
// Version: v0.1
///////////////////////////////////////////////////////

`timescale 1ns / 1ps

module debugger(
    // serial connection
    input  srx,
    output stx,
    
    // from MCU
    input         clk,
    input  [31:0] pc,
    input  [1:0]  ps,
    input  [31:0] mem_d_out,
    input  [31:0] rf_d_out

    // to MCU
    output [31:0] db_mem_addr, 
    output [3:0]  db_mem_be,
    output [4:0]  db_rf_addr,
    output [31:0] db_pc_d_in,
    output        fsm_pause,
    output        db_active
);

    localparam FETCH = 0;
    localparam EXEC  = 1;
    localparam WB    = 2;

    logic        pause,
                 resume,
                 reset,
                 mem_rd,
                 mem_wr,
                 reg_rd,
                 reg_wr,
                 valid,
                 mcu_busy
                 addr
    logic [31:0] addr,
                 d_in,
                 d_rd
    reg   [1:0]  r_counter = 0;
    reg          r_paused = 0;

    mcu_controller #(
        .CLK_RATE(50),
        .BAUD(115200),
    ) ctrlr(.*);

    // if paused, pc <- pc;
    assign db_pc_d_in = (r_paused || (r_paused && valid)) ? pc : 0;
    // db is active if cmd is issued or otter is busy
    assign db_active  = (
        valid ||
        r_paused ||
        r_pause_pending ||
        (r_counter > 0)
    );
    // reg file address is bottom five bits
    assign db_rf_addr = addr[4:0];
    assign db_mem_addr = addr;
    // keep FSM stuck in fetch
    assign fsm_pause = (
        r_paused ||
        (pause && valid)
    );
    assign mcu_busy = (
        (r_counter > 0) ||
        (valid && (mem_rd || mem_wr)) ||
        (valid && (pause && (state != 0)))
    );

    always_ff @(posedge clk) begin

        if (r_counter > 0)
            r_counter <= r_counter - 1;

        if (pause && valid) begin
            if (state == 0) 
                r_paused <= 1;
            if (state == 1) begin
                r_pause_pending <= 1;
                r_counter <= 1;
            end
            if (state == 2) begin
                r_pause_pending <= 1;
                r_counter <= 2;
            end
        end

        if (r_pause_pending && (r_counter == 1)) begin
            r_paused <= 1;
        end
        
        if (resume && valid)
            r_paused <= 0;

        if ((mem_rd || mem_wr) && valid)
            r_counter <= 1;
    end // always_ff

endmodule // debugger
