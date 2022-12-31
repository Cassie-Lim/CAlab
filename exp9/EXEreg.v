`include "macro.h"
module EXEreg(
    input  wire        clk,
    input  wire        resetn,
    // ds and es interface
    output wire        es_allowin,
    input  wire        ds2es_valid,
    input  wire [`DS2ES_LEN -1:0] ds2es_bus,
    // output wire        es_allowin,
    // input  wire [5 :0] id_rf_zip, // {id_rf_we, id_rf_waddr}
    // input  wire        id2es_valid,
    // input  wire [31:0] id_pc,    
    // input  wire [31:0] id_alu_result, 
    // input  wire        id_res_from_mem, 
    // input  wire        id_mem_we,
    // input  wire [31:0] id_rkd_value,

    // exe and mem state interface
    input  wire        ms_allowin,
    output wire [38:0] es_rf_zip, // {es_res_from_mem, es_rf_we, es_rf_waddr, es_alu_result}
    output wire        es2ms_valid,
    output reg  [31:0] es_pc,    
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata
);

    wire        es_ready_go;
    reg         es_valid;

    reg  [11:0] es_alu_op     ;
    reg  [31:0] es_alu_src1   ;
    reg  [31:0] es_alu_src2   ;
    wire [31:0] es_alu_result ; 
    reg  [31:0] es_rkd_value  ;
    reg         es_res_from_mem;
    reg         es_mem_we     ;
    reg         es_rf_we      ;
    reg  [4 :0] es_rf_waddr   ;
    wire [31:0] es_mem_result ;

//------------------------------state control signal---------------------------------------

    assign es_ready_go      = 1'b1;
    assign es_allowin       = ~es_valid | es_ready_go & ms_allowin;     
    assign es2ms_valid  = es_valid & es_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            es_valid <= 1'b0;
        else if(es_allowin)
            es_valid <= ds2es_valid; 
    end

//------------------------------id and exe state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn)
            {es_alu_op, es_res_from_mem, es_alu_src1, es_alu_src2,
             es_mem_we, es_rf_we, es_rf_waddr, es_rkd_value, es_pc} <= {`DS2ES_LEN{1'b0}};
        else if(ds2es_valid & es_allowin)
            {es_alu_op, es_res_from_mem, es_alu_src1, es_alu_src2,
             es_mem_we, es_rf_we, es_rf_waddr, es_rkd_value, es_pc} <= ds2es_bus;    
    end


//------------------------------alu interface---------------------------------------
    alu u_alu(
        .alu_op     (es_alu_op    ),
        .alu_src1   (es_alu_src1  ),
        .alu_src2   (es_alu_src2  ),
        .alu_result (es_alu_result)
    );
//------------------------------data sram interface---------------------------------------
    assign data_sram_en     = (es_res_from_mem || es_mem_we) && es_valid;
    assign data_sram_we     = {4{es_mem_we & es_valid}};
    assign data_sram_addr   = es_alu_result;
    assign data_sram_wdata  = es_rkd_value;
    //暂时认为es_rf_wdata等于es_alu_result,只有在ld类指令需要特殊处理
    assign es_rf_zip       = {es_res_from_mem & es_valid, es_rf_we & es_valid, es_rf_waddr, es_alu_result};    

endmodule