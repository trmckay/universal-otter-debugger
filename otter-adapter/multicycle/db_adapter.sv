////////////////////////////////////////////////////////
// Module: Multicycle Otter Debugger
// Author: Trevor McKay
// Version: v0.2
///////////////////////////////////////////////////////

`timescale 1ns / 1ps

module debugger(
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
    output wire         db_pc_pause,       // hold
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
        r_pc_pause  = 0,
        r_fsm_pause = 0;
    assign
        // pc must always pause immediately
        db_pc_pause  = (r_pc_pause  || (pause && valid)),
        // fsm must pause immediately if a pause is issued in the fetch state
        db_fsm_pause = (r_fsm_pause || (pause && valid && (mcu_ps == S_MCU_FETCH)));

    // hold on to outputs of mem/rf
    reg [31:0]
        r_rf_d_rd  = 0,
        r_mem_d_rd = 0;
        
    // stall for mem reads
    reg
        r_stall = 0;

    // save read type to forward correct data to controller
    reg
        r_read_type = 0;
    localparam
        RD_TYPE_MEM = 0,
        RD_TYPE_RF  = 1;

    // forward the correct data
    assign
        d_rd = (r_read_type) ? r_rf_d_rd : r_mem_d_rd;

    // determine if Otter is busy
    reg [1:0]
        r_wait = 0; 
    assign
        mcu_busy = (r_wait > 0) || valid;

//    initial begin
//        pause = 0;
//        resume = 0;
//        reset = 0;
//        mem_rd = 0;
//        mem_wr = 0;
//        reg_rd = 0;
//        reg_wr = 0;
//        valid = 0;
//        addr = 'h110C0000;
//        mem_size = 4;
//        d_in = 0;
        
//        # 4020
//        pause = 1; valid = 1;
//        # 40
//        pause = 0; valid = 0;
        
//        # 160
        
//        resume = 1; valid = 1;
//        # 40
//        resume = 0; valid = 0;
        
//        # 160
       
//        pause = 1; valid = 1;
//        # 40
//        pause = 0; valid = 0;
        
//        # 80;
//        mem_rd = 1; valid = 1;
//        # 40;
//        valid = 0;
//        # 40;
//        mem_rd = 0;
//    end
    
    debug_controller #(
        .CLK_RATE(50),
        .BAUD(115200)
    ) ctrlr(.*);

    always_ff @(posedge clk) begin

        case(r_ps)
            
            S_IDLE: begin
                if (valid) begin
                    if (pause) begin
                        // pc will remain paused always
                        r_pc_pause <= 1;
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
                        r_pc_pause   <= 0;
                        r_fsm_pause  <= 0;
                        db_mem_wr    <= 0;
                        db_mem_rd    <= 0;
                        db_rf_rd     <= 0;
                        db_rf_wr     <= 0;
                        db_reset     <= 0;
                        r_wait       <= 0;
                        r_ps         <= S_IDLE;
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
                // one cycle has passed since read/write assertion, read in the data
                r_rf_d_rd    <= rf_d_out;
                r_mem_d_rd   <= mem_d_out;
                // issuing complete
                r_wait       <= (r_wait > 0) ? r_wait - 1 : 0;
                r_ps         <= (r_wait > 0) ? S_ISSUE : S_PAUSED;
            end

            S_PAUSED: begin
                if (valid) begin
                    if (resume) begin
                        // return to idle state and clear pause signals
                        r_pc_pause  <= 0;
                        r_fsm_pause <= 0;
                        r_ps        <= S_IDLE;
                        r_wait      <= 0;
                    end // if (valid)
                    else if (reset) begin
                        db_reset    <= 1;
                        r_ps        <= S_IDLE;
                        r_pc_pause  <= 0;
                        r_fsm_pause <= 0;
                        r_wait      <= 0;
                    end // if (reset)
                    else begin
                        // perform the read/write
                        db_d_wr     <= d_in;
                        db_rf_addr  <= addr;
                        db_mem_addr <= addr;
                        db_mem_size <= mem_size;
                        db_mem_rd   <= mem_rd;
                        db_mem_wr   <= mem_wr;
                        db_rf_rd    <= reg_rd;
                        db_rf_wr    <= reg_wr;
                        r_read_type <= reg_rd; 
                        r_ps        <= S_ISSUE;
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
