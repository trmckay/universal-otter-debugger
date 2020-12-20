////////////////////////////////////////////////////////
// Module: Debugging Unit for the Otter
// Author: Trevor McKay
// Version: v1.0
///////////////////////////////////////////////////////

`timescale 1ns / 1ps

//// --->                !!! IMPORTANT !!!                    <---  ////
//// --->   !!! uncomment to select target architecture !!!   <---  ////

`define MULTICYCLE   // for multicycle Otter (CPE-233)
// `define PIPELINE     // for pipelined Otter (CPE-333)
// `define VLM          // for variable latency / AXI memory (CPE-333)
// `define TESTBENCH    // for using in simulation without physical connection

module otter_debug_adapter #(
    CLK_RATE = 50 // clk rate in MHz
    )(

    `ifdef MULTICYCLE
        input    [1:0]  mcu_ps,
        input    [6:0]  opcode,
        // FSM pausing is separate from PC in multicycle architecture
        output wire    db_fsm_pause,       // hold
    `endif

    `ifdef PIPELINE
        // ir exiting the pipeline is valid
        input           wb_ir_flagged,
        // flag instruction in fetch to know when pipeline is flushed
        output wire     db_flag_fetch_ir,
    `endif

    `ifdef VLM
        // support for VLM
        input           mem_stall,
    `endif

    // serial connection
    input               srx,
    output              stx,

    // from MCU
    input               clk,
    input        [31:0] pc,
    input        [31:0] rf_d_out,
    input        [31:0] mem_d_out,

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
);

    // check for compatible combinations of options
    initial begin
        `ifndef MULTICYCLE
            `ifndef PIPELINE
                $error("Otter debugger: no target architecture is defined");
            `endif
        `endif

        `ifdef PIPELINE
            `ifndef VLM
                $warning("Otter debugger: not using VLM with pipelined architecture");
            `endif
        `endif

        `ifdef MULTICYCLE
            `ifdef VLM
                $warning("Otter debugger: using VLM with multicycle architecture");
            `endif
        `endif
    end

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

    // mmio not yet supported
    localparam MAX_MEM_ADDR = 32'h11000000-1;
    localparam MAX_RF_ADDR = 31;

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
        error;
    logic [31:0] d_rd;

    assign error = (
        (addr > MAX_RF_ADDR && reg_rd && valid) ||
        (addr > MAX_MEM_ADDR && mem_rd && valid)
    );

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
        assign db_flag_fetch_ir = (pause && valid);
    `endif

    // hold on to outputs of mem/rf
    reg [31:0]
        r_rf_d_rd  = 0,
        r_mem_d_rd = 0,
        r_pc = 0;

    // save read type to forward correct data to controller
    reg [1:0] r_read_type = 0;
    localparam
        RD_TYPE_MEM = 0,
        RD_TYPE_RF  = 1,
        RD_TYPE_PC  = 2;

    // forward the correct data based on last read type
    always_comb begin
        case (r_read_type)
            RD_TYPE_MEM: d_rd = r_mem_d_rd;
            RD_TYPE_RF: d_rd = r_rf_d_rd;
            RD_TYPE_PC: d_rd = r_pc;
        endcase
    end

    // determine if Otter is busy
    // busy immediately on command issue
    reg [1:0] r_wait = 0;

    `ifdef PIPELINE
        reg r_pause_pending = 0;
        assign mcu_busy = ((r_wait > 0) || valid || r_pause_pending) && !error;
    `endif

    `ifdef MULTICYCLE
        assign mcu_busy = ((r_wait > 0) || valid) && !error;
    `endif

    `ifdef TESTBENCH

        localparam CLK_T_NS = 2000 / CLK_RATE;

        `define ctrlr_issue(SIG) \
            SIG = 1; valid = 1; \
            # CLK_T_NS \
            SIG = 0; valid = 0;

        initial begin
            pause = 0; resume = 0; reset = 0; mem_rd = 0;
            mem_wr = 0; reg_rd = 0; reg_wr = 0; valid = 0;
            addr = 'h4; mem_size = 'd2; d_in = 'hFFFF;

            // put testcases here
            // some examples are shown below

            # 4030
            `ctrlr_issue(pause);
            # 1020
            `ctrlr_issue(mem_rd);
            # 1020
            addr = 'h1;
            `ctrlr_issue(reg_rd);
            # 1020
            `ctrlr_issue(resume);
        end

    `else
        debug_controller #(
            .CLK_RATE(CLK_RATE),
            .BAUD(115200)
        ) ctrlr(.*);
    `endif

    always_ff @(posedge clk) begin

        case(r_ps)

            S_IDLE: begin
                // always clear reset signal in idle
                db_reset <= 0;

                if (valid && pause) begin
                    // pc will remain paused while debugger is accepting commands
                    r_db_active <= 1;
                    r_pc <= pc;
                    r_read_type <= RD_TYPE_PC;

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

                // these signals are all one-shot, clear them
                `ifndef VLM
                    db_mem_wr    <= 0;
                    db_mem_rd    <= 0;
                `endif
                db_rf_rd     <= 0;
                db_rf_wr     <= 0;

                if (r_wait > 0) begin
                    r_wait <= r_wait - 1;
                end

                if (r_wait == 0) begin
                    r_rf_d_rd <= rf_d_out;
                    `ifndef VLM
                        r_mem_d_rd <= mem_d_out;
                    `endif
                    r_ps <= S_PAUSED;
                end
            end

            `ifdef PIPELINE
                S_FLUSH: begin
                    `ifdef VLM
                    if (wb_ir_flagged && !mem_stall) begin
                    `else
                    if (wb_ir_flagged) begin
                    `endif
                        r_pause_pending <= 0;
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
                        if (!error) begin
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
                            if (mem_rd)
                                r_read_type <= RD_TYPE_MEM;
                            if (reg_rd)
                                r_read_type <= RD_TYPE_RF;

                            // for VLM,
                            // only register operations are predictable,
                            // still us S_WAIT_CYCLES for these,
                            // use S_WAIT_MEM for variable latency memory
                            `ifdef VLM
                                if (mem_rd || mem_wr) begin
                                    r_wait <= 2;
                                    r_ps   <= S_ACCESS_VLM;
                                end
                                if (reg_wr) begin
                                    r_wait <= 1;
                                    r_ps   <= S_WAIT_CYCLES;
                                end
                                if (reg_rd) begin
                                    r_wait <= 1;
                                    r_ps   <= S_WAIT_CYCLES;
                                end
                            `else
                                r_ps <= S_WAIT_CYCLES;
                                if (mem_rd || mem_wr || reg_wr)
                                    r_wait  <= 1;
                                if (reg_rd)
                                    r_wait  <= 0;
                            `endif
                        end
                    end // !resume && !reset
                end // if (valid)
            end // S_PAUSED

            `ifdef VLM
                S_ACCESS_VLM: begin
                    if (!mem_stall) begin
                        db_mem_rd  <= 0;
                        db_mem_wr  <= 0;
                        if (r_wait > 0)
                            r_wait <= r_wait - 1;
                    end
                    if (r_wait == 1)
                        r_mem_d_rd <= mem_d_out;
                    if (r_wait == 0)
                        r_ps <= S_PAUSED;
                end
            `endif

            default: r_ps <= S_IDLE;

        endcase // r_ps
    end //always_ff

endmodule // debugger
