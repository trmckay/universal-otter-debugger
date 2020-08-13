////////////////////////////////////////////////////////
// Module: Multicycle Otter Adapter for UART Debugger
// Author: Trevor McKay
// Version: v1.0
///////////////////////////////////////////////////////

`timescale 1ns / 1ps

module db_adapter_mc(
    // serial connection
    input               srx,
    output              stx,

    // from MCU
    input               clk,
    input        [31:0] pc,
    input logic  [1:0]  mcu_ps,
    input        [31:0] mem_d_out,
    input        [31:0] rf_d_out,
    input logic  [6:0]  opcode,

    // to MCU
    output wire         db_active,         // hold
    output wire         db_fsm_pause,      // hold
    output reg   [31:0] db_mem_addr  = 0,  // hold
    output reg   [1:0]  db_mem_size  = 0,  // hold
    output reg          db_mem_wr    = 0,  // one-shot
    output reg          db_mem_rd    = 0,  // one-shot
    output reg   [4:0]  db_rf_addr   = 0,  // hold
    output reg          db_rf_wr     = 0,  // one-shot
    output reg          db_rf_rd     = 0,  // one-shot
    output reg   [31:0] db_d_wr      = 0,  // one-shot
    output reg          db_reset     = 0   // one-shot
);

    // mcu states
    localparam
        S_MCU_FETCH = 0,
        S_MCU_EXEC  = 1,
        S_MCU_WB    = 2;

    // opcode of load instructions
    localparam
        LOAD = 7'b0000011;

    // db wrapper states
    localparam
        S_IDLE   = 0,
        S_ISSUE  = 1,
        S_PAUSED = 2;
    reg [1:0]
        r_ps = S_IDLE;

    // outputs of debug controller
    logic
        pause,
        resume,
        reset,
        mem_rd,
        mem_wr,
        reg_rd,
        reg_wr,
        valid;
    logic [1:0]
        mem_size;
    logic [31:0]
        addr,
        d_in;

    // inputs to debug controller 
    logic
        mcu_busy,
        error = 0;
    logic [31:0]    
        d_rd;

    // separate registers for pausing so it can issue immediately
    reg
        r_db_active  = 0,
        r_fsm_pause = 0;
    assign
        // pc must always pause immediately (db_active should pause the PC)
        db_active  = (r_db_active  || (pause && valid)),
        // fsm must pause immediately if a pause is issued in the fetch state
        db_fsm_pause = (r_fsm_pause || (pause && valid && (mcu_ps == S_MCU_FETCH)));

    // hold on to outputs of mem/rf
    reg [31:0]
        r_rf_d_rd  = 0,
        r_mem_d_rd = 0;
        
    // save read type to forward correct data to controller
    reg
        r_read_type = 0;
    localparam
        RD_TYPE_MEM = 0,
        RD_TYPE_RF  = 1;

    // forward the correct data based on last read type
    assign
        d_rd = (r_read_type) ? r_rf_d_rd : r_mem_d_rd;

    // determine if Otter is busy
    // busy immediately on command issue
    reg [1:0]
        r_wait = 0; 
    assign
        mcu_busy = (r_wait > 0) || valid;
    
    debug_controller #(
        .CLK_RATE(50),
        .BAUD(115200)
    ) ctrlr(.*);

    always_ff @(posedge clk) begin

        case(r_ps)
            S_IDLE: begin
                if (valid) begin
                    if (pause) begin
                        // always clear reset signal in idle, except when issued
                        db_reset     <= 0;
                        // pc will remain paused always
                        r_db_active <= 1;
                        case (mcu_ps)
                            // in fetch, pause can be issued before ir execs
                            S_MCU_FETCH: begin
                                r_ps        <= S_PAUSED;
                                r_fsm_pause <= 1;
                            end
                            // in exec, only need to wait if it is a load instruction
                            S_MCU_EXEC: begin
                                r_ps        <= (opcode == LOAD) ? S_ISSUE : S_PAUSED;
                                r_fsm_pause <= (opcode == LOAD) ? 0 : 1;
                                r_wait      <= (opcode == LOAD) ? 1 : 0;
                            end
                            // in writeback, never need to wait
                            S_MCU_WB: begin
                                r_ps        <= S_PAUSED;
                                r_fsm_pause <= 1;
                            end
                        endcase // mcu_ps
                    end // if (pause)

                    // reset pc and fsm, return to idle
                    else if (reset) begin
                        db_reset   <= 1;
                        r_ps       <= S_IDLE;
                    end // if (reset)

                    else begin // !pause && !reset
                        // always clear reset signal in idle, except when issued
                        db_reset     <= 0;
                        /* r_db_active  <= 0; */
                        /* r_fsm_pause  <= 0; */
                        /* db_mem_wr    <= 0; */
                        /* db_mem_rd    <= 0; */
                        /* db_rf_rd     <= 0; */
                        /* db_rf_wr     <= 0; */
                        /* r_wait       <= 0; */
                        /* r_ps         <= S_IDLE; */
                    end // else
                end // if (valid)
            end // S_IDLE

            // the logic below has no practical effect if coming
            // from S_IDLE after a pause is issued
            S_ISSUE: begin
                // these signals are all one-shot, clear them
                db_mem_wr    <= 0;
                db_mem_rd    <= 0;
                db_rf_rd     <= 0;
                db_rf_wr     <= 0;
                db_rf_wr     <= 0;
                
                if (r_wait > 1) begin
                    // wait another cycle
                    r_wait <= r_wait - 1;
                    r_ps   <= S_ISSUE;
                end
                if (r_wait == 1) begin
                    // at one cycle left, results can be saved
                    // TODO: maybe wait times can be reduced by one
                    r_rf_d_rd  <= rf_d_out;
                    r_mem_d_rd <= mem_d_out;
                    r_wait     <= r_wait - 1;
                    r_ps       <= S_ISSUE;
                end
                if (r_wait == 0) begin
                    // done waiting, return to S_PAUSED
                    r_ps <= S_PAUSED;
                end
            end

            S_PAUSED: begin
                // memory and rf access should only be done while mcu is paused
                // this is enforced here 
                // this is also why "db_active" is tied to the PC being paused
                if (valid) begin
                    if (resume) begin
                        // return to idle state and clear pause signals
                        r_db_active <= 0;
                        r_fsm_pause <= 0;
                        r_ps        <= S_IDLE;
                        r_wait      <= 0;
                    end // if (valid)
                    else if (reset) begin
                        db_reset    <= 1;
                        r_ps        <= S_IDLE;
                        r_db_active <= 0;
                        r_fsm_pause <= 0;
                        r_wait      <= 0;
                    end // if (reset)
                    else begin
                        // perform the read/write
                        // note: controller behavior is such that
                        //   only one will be issued at any
                        //   give time
                        db_d_wr     <= d_in;
                        db_rf_addr  <= addr;
                        db_mem_addr <= addr;
                        db_mem_size <= mem_size;
                        db_mem_rd   <= mem_rd;
                        db_mem_wr   <= mem_wr;
                        db_rf_rd    <= reg_rd;
                        db_rf_wr    <= reg_wr;
                        // connect 'd_rd' port of controller based
                        //   on the last performed read
                        //   0 = memory, 1 = register file
                        r_read_type <= reg_rd; 
                        r_ps        <= S_ISSUE;
                        // wait for operation to complete before returning
                        //   to S_PAUSED
                        if (mem_rd || mem_wr)
                            r_wait  <= 2;
                        if (reg_rd || reg_wr)
                            r_wait  <= 1;
                    end // !resume && !reset
                end // if (valid)
            end // S_PAUSED

        endcase // r_ps
    end //always_ff

endmodule // debugger
