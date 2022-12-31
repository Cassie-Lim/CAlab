`include "macro.h"
module EXEreg(
    input  wire        clk,
    input  wire        resetn,
    // id and exe interface
    output wire        es_allowin,
    input  wire        ds2es_valid,
    input  wire [`DS2ES_LEN -1:0] ds2es_bus,
    // exe and mem state interface
    input  wire        ms_allowin,
    output wire [`ES2MS_LEN -1:0] es2ms_bus,
    output wire [39:0] es_rf_zip, // {es_csr_re, es_res_from_mem, es_rf_we, es_rf_waddr, es_alu_result}
    output wire        es2ms_valid,
    output reg  [31:0] es_pc,    
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    // exception interface
    input  wire        ms_ex,
    input  wire        wb_ex
);

    wire        es_ready_go;
    reg         es_valid;

    reg  [18:0] es_alu_op     ;
    reg  [31:0] es_alu_src1   ;
    reg  [31:0] es_alu_src2   ;
    wire [31:0] es_alu_result ; 
    wire        alu_complete  ;
    reg  [31:0] es_rkd_value  ;
    reg         es_res_from_mem;
    wire [ 3:0] es_mem_we     ;
    reg         es_rf_we      ;
    reg  [4 :0] es_rf_waddr   ;
    wire [31:0] es_rf_result_tmp;

    reg  [ 2:0] es_st_op_zip;

    wire        op_ld_h;
    wire        op_ld_w;
    wire        op_ld_hu;
    wire        op_st_b;
    wire        op_st_h;
    wire        op_st_w;

    wire        rd_cnt_h;
    wire        rd_cnt_l;
    reg  [63:0] es_timer_cnt;

    wire        es_ex;
    reg         es_csr_re;
    
    reg  [ 4:0] es_ld_inst_zip; // {op_ld_b, op_ld_bu,op_ld_h, op_ld_hu, op_ld_w}
    reg  [ 1:0] es_cnt_inst_zip; // {rd_cnt_h, rd_cnt_l}
    wire        es_except_ale;
    reg  [ 5:0] es_except_zip_tmp;
    wire [ 6:0] es_except_zip;
    reg  [78:0] es_csr_zip;
//------------------------------state control signal---------------------------------------
    assign es_ex            = |es_except_zip;
    assign es_ready_go      = alu_complete;
    assign es_allowin       = ~es_valid | es_ready_go & ms_allowin;     
    assign es2ms_valid  = es_valid & es_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            es_valid <= 1'b0;
        else if(wb_ex)
            es_valid <= 1'b0;
        else if(es_allowin)
            es_valid <= ds2es_valid; 
    end
//------------------------------id and exe state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn)
            {es_alu_op, es_res_from_mem, es_alu_src1, es_alu_src2,
             es_csr_re, es_rf_we, es_rf_waddr, es_rkd_value, es_pc, es_st_op_zip, 
             es_ld_inst_zip, es_cnt_inst_zip, es_csr_zip, es_except_zip_tmp} <= {`DS2ES_LEN{1'b0}};
        else if(ds2es_valid & es_allowin)
            {es_alu_op, es_res_from_mem, es_alu_src1, es_alu_src2,
             es_csr_re, es_rf_we, es_rf_waddr, es_rkd_value, es_pc, es_st_op_zip, 
             es_ld_inst_zip, es_cnt_inst_zip, es_csr_zip, es_except_zip_tmp} <= ds2es_bus;    
    end
    // 指令拆包
    assign {op_ld_h, op_ld_hu, op_ld_w} = es_ld_inst_zip[2:0];
    assign {op_st_b, op_st_h, op_st_w} = es_st_op_zip;
    assign {rd_cnt_h, rd_cnt_l} = es_cnt_inst_zip;
//------------------------------exe timer---------------------------------------
    
    always @(posedge clk) begin
        if(~resetn)
            es_timer_cnt <= 64'b0;
        else   
            es_timer_cnt <= es_timer_cnt + 1'b0;
    end
    
//------------------------------exe and mem state interface---------------------------------------
    assign es_except_ale = ((|es_alu_result[1:0]) & (op_st_w | op_ld_w)|
                            es_alu_result[0] & (op_st_h|op_ld_hu|op_ld_h)) & es_valid;
                            
    assign es_except_zip = {es_except_ale, es_except_zip_tmp};
    assign es2ms_bus = {
                        es_ld_inst_zip,     // 5  bit
                        es_pc,              // 32 bit
                        es_csr_zip,         // 79 bit
                        es_except_zip       //  7 bit
                    };
//------------------------------alu interface---------------------------------------
    alu u_alu(
        .clk            (clk       ),
        .resetn         (resetn & ~wb_ex),
        .alu_op         (es_alu_op    ),
        .alu_src1       (es_alu_src1  ),
        .alu_src2       (es_alu_src2  ),
        .alu_result     (es_alu_result),
        .complete       (alu_complete)
    );


//------------------------------data sram interface---------------------------------------
    assign es_mem_we[0]     = op_st_w | op_st_h & ~es_alu_result[1] | op_st_b & ~es_alu_result[0] & ~es_alu_result[1];   
    assign es_mem_we[1]     = op_st_w | op_st_h & ~es_alu_result[1] | op_st_b &  es_alu_result[0] & ~es_alu_result[1];   
    assign es_mem_we[2]     = op_st_w | op_st_h &  es_alu_result[1] | op_st_b & ~es_alu_result[0] &  es_alu_result[1];   
    assign es_mem_we[3]     = op_st_w | op_st_h &  es_alu_result[1] | op_st_b &  es_alu_result[0] &  es_alu_result[1];       
    assign data_sram_en     = (es_res_from_mem | (|es_mem_we)) & es_valid;
    assign data_sram_we     = {4{es_valid & ~wb_ex & ~ms_ex & ~es_ex}} & es_mem_we;//store 's exception
    assign data_sram_addr   = {es_alu_result[31:2], 2'b0};
    assign data_sram_wdata[ 7: 0]   = es_rkd_value[ 7: 0];
    assign data_sram_wdata[15: 8]   = op_st_b ? es_rkd_value[ 7: 0] : es_rkd_value[15: 8];
    assign data_sram_wdata[23:16]   = op_st_w ? es_rkd_value[23:16] : es_rkd_value[ 7: 0];
    assign data_sram_wdata[31:24]   = op_st_w ? es_rkd_value[31:24] : 
                                      op_st_h ? es_rkd_value[15: 8] : es_rkd_value[ 7: 0];
    // exe阶段暂时选出的写回数据
    assign es_rf_result_tmp = {32{rd_cnt_h}} & es_timer_cnt[63:32] | 
                              {32{rd_cnt_l}} & es_timer_cnt[31: 0] |
                              {32{~rd_cnt_h & ~rd_cnt_l}} & es_alu_result;
    //暂时认为es_rf_wdata等于es_rf_result_tmp,只有在ld类指令需要特殊处理
    assign es_rf_zip       = {es_csr_re & es_valid, es_res_from_mem & es_valid, es_rf_we & es_valid, es_rf_waddr, es_rf_result_tmp};    
endmodule