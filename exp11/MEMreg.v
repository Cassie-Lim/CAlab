module MEMreg(
    input  wire        clk,
    input  wire        resetn,
    // exe and mem state interface
    output wire        ms_allowin,
    input  wire [38:0] es_rf_zip, // es2ms_bus，{es_res_from_mem, es_rf_we, es_rf_waddr, es_rf_wdata}
    input  wire [ 4:0] es_ld_inst_zip,
    input  wire        es2ms_valid, // {op_ld_b, op_ld_bu,op_ld_h, op_ld_hu, op_ld_w}
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
    reg  [7 :0] ms_ld_inst_zip;
    wire [31:0] ms_rf_wdata   ;
    wire [31:0] ms_mem_result ;
    wire [31:0] shift_rdata   ;
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
            ms_ld_inst_zip <= 8'b0;
            {ms_res_from_mem, ms_rf_we, ms_rf_waddr, ms_alu_result} <= 38'b0;
        end
        if(es2ms_valid & ms_allowin) begin
            ms_pc <= es_pc;
            ms_ld_inst_zip <= es_ld_inst_zip;
            {ms_res_from_mem, ms_rf_we, ms_rf_waddr, ms_alu_result} <= es_rf_zip;
        end
    end
    // 细粒度译码
    assign {op_ld_b, op_ld_bu,op_ld_h, op_ld_hu, op_ld_w} = ms_ld_inst_zip;
    assign shift_rdata   = {24'b0, data_sram_rdata} >> {ms_alu_result[1:0], 3'b0};
    assign ms_mem_result[ 7: 0]   =  shift_rdata[ 7: 0];
    assign ms_mem_result[15: 8]   =  {8{op_ld_b}} & {8{shift_rdata[7]}} |
                                     {8{op_ld_bu}} & 8'b0               |
                                     {8{~op_ld_bu & ~op_ld_b}} & shift_rdata[15: 8];
    assign ms_mem_result[31:16]   =  {16{op_ld_b}} & {16{shift_rdata[7]}} |
                                     {16{op_ld_h}} & {16{shift_rdata[15]}}|
                                     {16{op_ld_bu | op_ld_hu}} & 16'b0    |
                                     {16{op_ld_w}} & shift_rdata[31:16];
    assign ms_rf_wdata = {32{ms_res_from_mem}} & ms_mem_result | {32{~ms_res_from_mem}} & ms_alu_result;
    assign ms_rf_zip  = {ms_rf_we & ms_valid, ms_rf_waddr, ms_rf_wdata};

endmodule