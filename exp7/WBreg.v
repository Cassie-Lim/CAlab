module WBreg(
    input  wire        clk,
    input  wire        resetn,
    // mem and wb state interface
    output wire        wb_allowin,
    input  wire [37:0] mem_rf_zip, // {mem_rf_we, mem_rf_waddr, mem_rf_wdata}
    input  wire        mem_to_wb_valid,
    input  wire [31:0] mem_pc,    
    // input  wire [27:0] alu_result, 
    // input  wire        res_from_mem, 
    // input  wire [31:0] mem_result,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    // id and wb state interface
    output wire [37:0] wb_rf_zip  // {rf_we, rf_waddr, rf_wdata}
);
    
    wire        wb_ready_go;
    reg         wb_valid;
    reg  [31:0] wb_pc;
    reg  [31:0] rf_wdata;
    reg  [4 :0] rf_waddr;
    reg         rf_we;
//------------------------------state control signal---------------------------------------

    assign wb_ready_go      = 1'b1;
    assign wb_allowin       = ~wb_valid | wb_ready_go ;     
    // assign wb_to_wb_valid  = wb_valid & wb_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            wb_valid <= 1'b0;
        else
            wb_valid <= mem_to_wb_valid & wb_allowin; 
    end

//------------------------------mem and wb state interface---------------------------------------
    always @(posedge clk) begin
        if(mem_to_wb_valid)
            wb_pc <= mem_pc;
    end
    always @(posedge clk) begin
        if(mem_to_wb_valid)
            {rf_we, rf_waddr, rf_wdata} <= mem_rf_zip;
    end
//------------------------------mem and wb state interface---------------------------------------


//------------------------------id and wb state interface---------------------------------------
    assign wb_rf_zip = {rf_we, rf_waddr, rf_wdata};
//------------------------------trace debug interface---------------------------------------
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_wdata = rf_wdata;
    assign debug_wb_rf_we = {4{rf_we & wb_valid}};
    assign debug_wb_rf_wnum = rf_waddr;
endmodule