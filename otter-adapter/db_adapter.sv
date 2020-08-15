////////////////////////////////////////////////////////
// Module: Multicycle Otter Adapter for UART Debugger
// Author: Trevor McKay
// Version: v1.0
///////////////////////////////////////////////////////

`timescale 1ns / 1ps

// uncomment to select target architecture
`define MULTICYCLE
// `define PIPELINE

// uncomment if using variable latency memory
// `define VLM

module db_adapter_mc #(
    CLK_RATE = 50 // clk rate in MHz
    )(
    // serial connection
    input               srx,
    output              stx,

    // from MCU
    input               clk,
    input        [31:0] pc,
    input        [31:0] rf_d_out,
    input        [31:0] mem_d_out,

    `ifdef MULTICYCLE
        input    [1:0]  mcu_ps,
        input    [6:0]  opcode,
    `endif

    `ifdef PIPELINE
        // ir exiting the pipeline is valid
        input           wb_ir_flagged,
    `endif

    `ifdef VLM
        // support for VLM
        input           mem_stall,
    `endif

    // to MCU
    output wire         db_active,          // hold
    output reg   [31:0] db_mem_addr   = 0,  // hold
    output reg   [1:0]  db_mem_size   = 0,  // hold
    output reg          db_mem_wr     = 0,  // one-shot
    output reg          db_mem_rd     = 0,  // one-shot
    output reg   [4:0]  db_rf_addr    = 0,  // hold
    output reg          db_rf_wr      = 0,  // one-shot
    output reg          db_rf_rd      = 0,  // one-shot
    output reg   [31:0] db_d_wr       = 0,  // one-shot
    output reg          db_reset      = 0   // one-shot

    `ifdef PIPELINE
        // flag instruction in fetch to know when pipeline is flushed
        ,output wire    flag_fetch_ir = 0
    `endif

    `ifdef MULTICYCLE
        // FSM pausing is separate from PC in multicycle architecture
        ,output wire    db_fsm_pause       // hold
    `endif
);

    `ifdef MULTICYCLE
        // mcu states
        localparam
            S_MCU_FETCH = 0,
            S_MCU_EXEC  = 1,
            S_MCU_WB    = 2;

        // opcode of load instructions
        localparam
            LOAD = 7'b0000011;
    `endif

    `ifdef PIPELINE
        localparam STAGES = 5;
    `endif

    // db wrapper states
    localparam
        S_IDLE        = 0,
        S_WAIT_CYCLES = 1,
        S_PAUSED      = 2;

    `ifdef PIPELINE
        localparam
            S_FLUSH = 3;
    `endif

    `ifdef VLM
        localparam
            S_ACCESS_VLM = 4;
    `endif

    reg [2:0]
        r_ps = S_IDLE;

    // outputs of debug controller
    logic pause, resume, reset,
        mem_rd, mem_wr, reg_rd,
        reg_wr, valid;
    logic [1:0] mem_size;
    logic [31:0] addr, d_in;

    // inputs to debug controller
    logic
        mcu_busy,
        error = 0;
    logic [31:0] d_rd;

    // separate registers for pausing so it can issue immediately
    reg r_db_active  = 0;
    // pc must always pause immediately (db_active should pause the PC)
    assign db_active  = (r_db_active  || (pause && valid));

    `ifdef MULTICYCLE
        // fsm must pause immediately if a pause is issued in the fetch state
        reg r_fsm_pause = 0;
        assign db_fsm_pause = (r_fsm_pause || (pause && valid && (mcu_ps == S_MCU_FETCH)));
    `endif

    `ifdef PIPELINE
        assign flag_fetch_ir = (pause && valid);
    `endif

    // hold on to outputs of mem/rf
    reg [31:0]
        r_rf_d_rd  = 0,
        r_mem_d_rd = 0;

    // save read type to forward correct data to controller
    reg r_read_type = 0;
    localparam
        RD_TYPE_MEM = 0,
        RD_TYPE_RF  = 1;

    // forward the correct data based on last read type
    assign d_rd = (r_read_type) ? r_rf_d_rd : r_mem_d_rd;

    // determine if Otter is busy
    // busy immediately on command issue
    reg [1:0] r_wait = 0;
    `ifdef PIPELINE
        reg r_pause_pending = 0;
        `ifdef VLM
            assign mcu_busy = (r_wait > 0) || valid || r_pause_pending || mem_stall;
        `else
            assign mcu_busy = (r_wait > 0) || valid || r_pause_pending;
        `endif
    `elsif MULTICYCLE
        `ifdef VLM
            assign mcu_busy = (r_wait > 0) || valid || mem_stall;
        `else
            assign mcu_busy = (r_wait > 0) || valid;
        `endif
    `endif

    debug_controller #(
        .CLK_RATE(CLK_RATE),
        .BAUD(115200)
    ) ctrlr(.*);

    always_ff @(posedge clk) begin

        `ifdef PIPELINE
            if (r_pc_disable_cycles > 0)
                r_pc_disable_cycles <= r_pc_disable_cycles - 1;
        `endif

        case(r_ps)

            S_IDLE: begin
                // always clear reset signal in idle
                db_reset     <= 0;

                if (valid && pause) begin
                    // pc will remain paused while debugger is accepting commands
                    r_db_active  <= 1;

                    // multicycle arch needs to wait depending on present state
                    `ifdef MULTICYCLE
                        case (mcu_ps)
                            // in fetch, pause can be issued before ir execs
                            S_MCU_FETCH: begin
                                r_ps        <= S_PAUSED;
                                r_fsm_pause <= 1;
                            end
                            // in exec, only need to wait if it is a load instruction
                            S_MCU_EXEC: begin
                                r_ps        <= (opcode == LOAD) ? S_WAIT_CYCLES : S_PAUSED;
                                r_fsm_pause <= (opcode == LOAD) ? 0 : 1;
                                r_wait      <= (opcode == LOAD) ? 1 : 0;
                            end
                            // in writeback, never need to wait
                            S_MCU_WB: begin
                                r_ps        <= S_PAUSED;
                                r_fsm_pause <= 1;
                            end
                        endcase // mcu_ps
                    `endif

                    `ifdef PIPELINE
                        r_ps            <= S_FLUSH;
                        r_pause_pending <= 1;
                    `endif
                end // if (valid && pause)
            end // S_IDLE

            S_WAIT_CYCLES: begin

                // for multicycle architecture,
                // behavior is predictable
                //
                // register reads are asynchronous,
                // register writes take one cycle,
                // memory reads and writes all take one cycle,

                // these signals are all one-shot, clear them
                db_mem_wr    <= 0;
                db_mem_rd    <= 0;
                db_rf_rd     <= 0;
                db_rf_wr     <= 0;

                // wait another cycle
                if (r_wait > 1)
                    r_wait <= r_wait - 1;

                // at one cycle left, results can be saved
                if (r_wait == 1) begin
                    r_rf_d_rd  <= rf_d_out;
                    r_wait     <= r_wait - 1;
                end

                `ifdef MULTICYCLE
                    // mem reads in multicycle have predictable delays
                    if (r_wait == 1) begin
                        r_mem_d_rd <= mem_d_out;
                        r_wait     <= r_wait - 1;
                    end
                `endif

                // done waiting, return to S_PAUSED
                if (r_wait == 0)
                    r_ps <= S_PAUSED;
            end

            `ifdef PIPELINE
                S_FLUSH: begin
                    `ifdef VLM
                    if (wb_ir_flagged && !mem_stall) begin
                    `else
                    if (wb_ir_flagged) begin
                    `endif
                        r_ps <= S_PAUSED;
                    end
                end
            `endif

            S_PAUSED: begin
                // memory and rf access should only be done while mcu is paused
                // this is enforced here
                if (valid) begin
                    if (resume) begin
                        // return to idle state and clear pause signals
                        r_db_active <= 0;
                        r_ps        <= S_IDLE;
                        r_wait      <= 0;

                        `ifdef MULTICYCLE
                            r_fsm_pause <= 0;
                        `endif

                    end // if (valid)
                    else if (reset) begin
                        db_reset    <= 1;
                        r_ps        <= S_IDLE;
                        r_db_active <= 0;
                        r_wait      <= 0;

                        `ifdef MULTICYCLE
                            r_fsm_pause <= 0;
                        `endif
                    end // if (reset)

                    else begin
                        // perform the read/write
                        // note: controller behavior is such that
                        //   only one will be issued at any time
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

                        // for VLM,
                        // only register operations are predictable,
                        // still us S_WAIT_CYCLES for these,
                        // use S_WAIT_MEM for variable latency memory
                        `ifdef VLM
                            if (mem_rd || mem_wr)
                                r_ps <= S_ACCESS_VLM;
                            if (reg_rd || reg_wr) begin
                                r_ps <= S_WAIT_CYCLES
                                r_wait <= 1;
                            end
                        `else
                            r_ps <= S_WAIT_CYCLES;
                            if (mem_rd || mem_wr)
                                r_wait  <= 2;
                            if (reg_rd || reg_wr)
                                r_wait  <= 1;
                        `endif

                    end // !resume && !reset
                end // if (valid)
            end // S_PAUSED

            `ifdef VLM
                S_ACCESS_VLM: begin
                    if (!mem_stall) begin
                        db_mem_rd  <= 0;
                        db_mem_wr  <= 0;
                        r_mem_d_rd <= mem_d_out;
                        r_ps <= S_PAUSED;
                    end
                end
            `endif

            default: r_ps <= IDLE;

        endcase // r_ps
    end //always_ff

endmodule // debugger
