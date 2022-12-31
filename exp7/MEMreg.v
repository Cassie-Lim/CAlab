module MEMreg(
    input  wire        clk,
    input  wire        resetn,
    // exe and mem state interface
    output wire        mem_allowin,
    input  wire [5 :0] exe_rf_zip, // {exe_rf_we, exe_rf_waddr}
    input  wire        exe_to_mem_valid,
    input  wire [31:0] exe_pc,    
    input  wire [31:0] exe_alu_result, 
    input  wire        exe_res_from_mem, 
    input  wire        exe_mem_we,
    input  wire [31:0] exe_rkd_value,
    // mem and wb state interface
    input  wire        wb_allowin,
    output wire [37:0] mem_rf_zip, // {mem_rf_we, mem_rf_waddr, mem_rf_wdata}
    output wire        mem_to_wb_valid,
    output reg  [31:0] mem_pc,    
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata
);
    wire        mem_ready_go;
    wire [31:0] mem_result;
    reg         mem_valid;
    reg         mem_we;
    reg  [31:0] rkd_value;
    wire [31:0] mem_rf_wdata;
    reg         mem_rf_we;
    reg  [4 :0] mem_rf_waddr;
    reg  [31:0] alu_result;
    reg         ms_res_from_mem;

//------------------------------state control signal---------------------------------------

    assign mem_ready_go      = 1'b1;
    assign mem_allowin       = ~mem_valid | mem_ready_go & wb_allowin;     
    assign mem_to_wb_valid  = mem_valid & mem_ready_go;
    assign mem_rf_wdata     = ms_res_from_mem ? mem_result : alu_result;
    assign mem_rf_zip       = {mem_rf_we, mem_rf_waddr, mem_rf_wdata};
    always @(posedge clk) begin
        if(~resetn)
            mem_valid <= 1'b0;
        else
            mem_valid <= exe_to_mem_valid & mem_allowin; 
    end

//------------------------------exe and mem state interface---------------------------------------
    always @(posedge clk) begin
        if(exe_to_mem_valid & mem_allowin)
            mem_pc <= exe_pc;
    end
    always @(posedge clk) begin
        if(exe_to_mem_valid & mem_allowin)
            alu_result <= exe_alu_result;
    end
    always @(posedge clk) begin
        if(exe_to_mem_valid & mem_allowin)
            {mem_rf_we, mem_rf_waddr} <= exe_rf_zip;
    end
    always @(posedge clk) begin
        if(exe_to_mem_valid & mem_allowin)
            {ms_res_from_mem, mem_we, rkd_value} <= {exe_res_from_mem, exe_mem_we, exe_rkd_value};
    end
//------------------------------mem and wb state interface---------------------------------------
    assign mem_result   = data_sram_rdata;

//------------------------------data sram interface---------------------------------------

    assign data_sram_en    = exe_res_from_mem || exe_mem_we;
    assign data_sram_we    = {4{exe_mem_we}};
    assign data_sram_addr  = exe_alu_result;
    assign data_sram_wdata = exe_rkd_value;

endmodule