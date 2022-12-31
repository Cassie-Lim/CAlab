module WBreg(
    input  wire        clk,
    input  wire        resetn,
    // mem and ws state interface
    output wire        ws_allowin,
    input  wire [37:0] ms_rf_zip, // {ms_rf_we, ms_rf_waddr, ms_rf_wdata}
    input  wire        ms2ws_valid,
    input  wire [31:0] ms_pc,    
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    // id and ws state interface
    output wire [37:0] ws_rf_zip  // {ws_rf_we, ws_rf_waddr, ws_rf_wdata}
);
    
    wire        ws_ready_go;
    reg         ws_valid;
    reg  [31:0] ws_pc;
    reg  [31:0] ws_rf_wdata;
    reg  [4 :0] ws_rf_waddr;
    reg         ws_rf_we;
//------------------------------state control signal---------------------------------------

    assign ws_ready_go      = 1'b1;
    assign ws_allowin       = ~ws_valid | ws_ready_go ;     
    always @(posedge clk) begin
        if(~resetn)
            ws_valid <= 1'b0;
        else if(ws_allowin)
            ws_valid <= ms2ws_valid; 
    end

//------------------------------mem and ws state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn) begin
            ws_pc <= 32'b0;
            {ws_rf_we, ws_rf_waddr, ws_rf_wdata} <= 38'b0;
        end
        if(ms2ws_valid & ws_allowin) begin
            ws_pc <= ms_pc;
            {ws_rf_we, ws_rf_waddr, ws_rf_wdata} <= ms_rf_zip;
        end
    end

//------------------------------id and ws state interface---------------------------------------
    assign ws_rf_zip = {ws_rf_we & ws_valid, ws_rf_waddr, ws_rf_wdata};
//------------------------------trace debug interface---------------------------------------
    assign debug_wb_pc = ws_pc;
    assign debug_wb_rf_wdata = ws_rf_wdata;
    assign debug_wb_rf_we = {4{ws_rf_we & ws_valid}};
    assign debug_wb_rf_wnum = ws_rf_waddr;
endmodule