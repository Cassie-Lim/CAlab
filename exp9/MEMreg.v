module MEMreg(
    input  wire        clk,
    input  wire        resetn,
    // exe and mem state interface
    output wire        ms_allowin,
    input  wire [38:0] es_rf_zip, // es2ms_bus，{es_res_from_mem, es_rf_we, es_rf_waddr, es_rf_wdata}
    input  wire        es2ms_valid,
    input  wire [31:0] es_pc,    
    // mem and wb state interface
    input  wire        ws_allowin,
    output wire [37:0] ms_rf_zip, // {ms_rf_we, ms_rf_waddr, ms_rf_wdata}
    output wire        ms2ws_valid,
    output reg  [31:0] ms_pc,
    // data sram interface
    input  wire [31:0] data_sram_rdata    
);
    wire        ms_ready_go;
    reg         ms_valid;
    reg  [31:0] ms_alu_result ; 
    reg         ms_res_from_mem;
    reg         ms_rf_we      ;
    reg  [4 :0] ms_rf_waddr   ;
    wire [31:0] ms_rf_wdata   ;
    wire [31:0] ms_mem_result ;
//------------------------------state control signal---------------------------------------

    assign ms_ready_go      = 1'b1;
    assign ms_allowin       = ~ms_valid | ms_ready_go & ws_allowin;     
    assign ms2ws_valid      = ms_valid & ms_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            ms_valid <= 1'b0;
        else
            ms_valid <= es2ms_valid & ms_allowin; 
    end

//------------------------------exe and mem state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn) begin
            ms_pc <= 32'b0;
            {ms_res_from_mem, ms_rf_we, ms_rf_waddr, ms_alu_result} <= 38'b0;
        end
        if(es2ms_valid & ms_allowin) begin
            ms_pc <= es_pc;
            {ms_res_from_mem, ms_rf_we, ms_rf_waddr, ms_alu_result} <= es_rf_zip;
        end
    end

    assign ms_mem_result = data_sram_rdata;
    assign ms_rf_wdata = ms_res_from_mem ? ms_mem_result : ms_alu_result;
    assign ms_rf_zip  = {ms_rf_we & ms_valid, ms_rf_waddr, ms_rf_wdata};

endmodule