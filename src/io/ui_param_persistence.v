`ifndef UI_PARAM_PERSISTENCE_V
`define UI_PARAM_PERSISTENCE_V
// 50 MHz UI domain only. The existing millisecond tick drives all NVM timing.
// A user write/default request during startup takes precedence over Flash load.
module ui_param_persistence #(
    parameter integer AUTO_SAVE_MS = 5000,
    parameter integer SPI_HALF_CYCLES = 8,
    parameter [19:0] DEFAULT_PARAMS = {3'd4,3'd2,3'd2,3'd3,8'd200}
)(
    input wire clk, rst_n, tick_1ms,
    input wire [19:0] current_params,
    input wire param_update, user_write, defaults_req, manual_save, auto_enable,
    output wire restore_valid,
    output wire [19:0] restore_data,
    output wire [3:0] led_status,
    output wire save_success, // One clk pulse after the NOR commit succeeds.
    output wire flash_cs_n, flash_sclk, flash_mosi,
    input wire flash_miso,
    output wire flash_wp_n, flash_hold_n
);
    wire store_ready, store_available, store_busy, store_load_valid, store_done, store_fault;
    wire [19:0] store_load_params;
    wire [3:0] store_fault_code;
    reg startup_override = 0, loaded_seen = 0, saved_valid = 0;
    reg manual_pending = 0, defaults_pending = 0, inflight = 0;
    reg save_start = 0, snapshot_default = 0;
    reg [19:0] saved_params = DEFAULT_PARAMS, snapshot = DEFAULT_PARAMS;
    localparam AW = $clog2(AUTO_SAVE_MS+1);
    reg [AW-1:0] idle_ms = 0;
    wire dirty = current_params!=saved_params;
    assign save_success = store_done;
    assign restore_valid = store_load_valid && !startup_override && !defaults_req && !user_write;
    assign restore_data = store_load_params;
    // LED1: startup restore accepted; LED2: current values durably saved;
    // LED3: Flash busy; LED4: Flash fault (latched until reset).
    assign led_status = {store_fault,store_busy,
                        (saved_valid && !dirty && !defaults_pending),loaded_seen};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) startup_override<=0;
        else if(!store_ready && (user_write || defaults_req)) startup_override<=1;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) loaded_seen<=0;
        else if(restore_valid) loaded_seen<=1;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) idle_ms<=0;
        else if(param_update || defaults_req || !auto_enable || !dirty || save_start) idle_ms<=0;
        else if(tick_1ms && store_ready && !store_busy && idle_ms<AUTO_SAVE_MS)
            idle_ms<=idle_ms+1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            manual_pending<=0;defaults_pending<=0;inflight<=0;save_start<=0;
            snapshot_default<=0;snapshot<=DEFAULT_PARAMS;
            saved_valid<=0;saved_params<=DEFAULT_PARAMS;
        end else begin
            save_start<=0;
            if(store_load_valid) begin saved_params<=store_load_params;saved_valid<=1;end
            if(store_done) begin saved_params<=snapshot;saved_valid<=1;inflight<=0;end
            if(store_fault) begin inflight<=0;manual_pending<=0;defaults_pending<=0;end
            if(store_ready && store_available && !store_busy && !inflight &&
               !save_start && !defaults_req && !manual_save && !param_update && !user_write &&
               (defaults_pending || manual_pending || (auto_enable && dirty && idle_ms>=AUTO_SAVE_MS))) begin
                manual_pending<=0;
                if(defaults_pending || dirty || !saved_valid) begin
                    snapshot<=defaults_pending ? DEFAULT_PARAMS : current_params;
                    snapshot_default<=defaults_pending;defaults_pending<=0;
                    inflight<=1;save_start<=1;
                end
            end
            if(manual_save && !store_fault) manual_pending<=1;
            if(defaults_req && !store_fault) begin defaults_pending<=1;manual_pending<=0;end
        end
    end
    w25q64_param_store #(.SPI_HALF_CYCLES(SPI_HALF_CYCLES),.DEFAULT_PARAMS(DEFAULT_PARAMS)) u_store(
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),
        .save_req(save_start),.save_defaults(snapshot_default),.save_params(snapshot),
        .ready(store_ready),.available(store_available),.busy(store_busy),
        .load_valid(store_load_valid),.load_params(store_load_params),.save_done(store_done),
        .fault(store_fault),.fault_code(store_fault_code),
        .flash_cs_n(flash_cs_n),.flash_sclk(flash_sclk),.flash_mosi(flash_mosi),
        .flash_miso(flash_miso),.flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n));
endmodule
`endif
