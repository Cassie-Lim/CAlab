`include "macro.h"
module csr(
    input  wire          clk       ,
    input  wire          reset     ,
    // 读端口
    input  wire          csr_re    ,
    input  wire [13:0]   csr_num   ,
    output wire [31:0]   csr_rvalue,
    // 写端口
    input  wire          csr_we    ,
    input  wire [31:0]   csr_wmask ,
    input  wire [31:0]   csr_wvalue,
    // 与硬件电路交互的接口信号
    output wire [31:0]   ex_entry  , //送往pre-IF的异常入口地址
    output wire [31:0]   ertn_entry, //送往pre-IF的返回入口地址
    output wire          has_int   , //送往ID阶段的中断有效信号
    input  wire          ertn_flush, //来自WB阶段的ertn指令执行有效信号
    input  wire          wb_ex     , //来自WB阶段的异常处理触发信号
    input  wire [ 5:0]   wb_ecode  , //异常类型
    input  wire [ 8:0]   wb_esubcode,
    input  wire [31:0]   wb_pc       //写回的返回地址
);
    // 当前模式信息
    wire [31: 0] csr_crmd_data;
    reg  [ 1: 0] csr_crmd_plv;      //CRMD的PLV域，当前特权等级
    reg          csr_crmd_ie;       //CRMD的全局中断使能信号
    reg          csr_crmd_da;       //CRMD的直接地址翻译使能
    reg          csr_crmd_pg;
    reg  [ 6: 5] csr_crmd_datf;
    reg  [ 8: 7] csr_crmd_datm;
    // reg  [31: 9] csr_crmd_r0;

    // 例外前模式信息
    wire [31: 0] csr_prmd_data;
    reg  [ 1: 0] csr_prmd_pplv;     //CRMD的PLV域旧值
    reg          csr_prmd_pie;      //CRMD的IE域旧值

    // 例外控制
    wire [31: 0] csr_ecfg_data;     // 保留位31:13
    reg  [12: 0] csr_ecfg_lie;      //局部中断使能位

    // 例外状态
    wire [31: 0] csr_estat_data;    // 保留位15:13, 31
    reg  [12: 0] csr_estat_is;      // 例外中断的状态位（8个硬件中断+1个定时器中断+1个核间中断+2个软件中断）
    reg  [ 5: 0] csr_estat_ecode;   // 例外类型一级编码
    reg  [ 8: 0] csr_estat_esubcode;// 例外类型二级编码

    // 例外返回地址ERA
    reg  [31: 0] csr_era_data;  // data

    // 例外入口地址eentry
    wire [31: 0] csr_eentry_data;   // 保留位5:0
    reg  [25: 0] csr_eentry_va;     // 例外中断入口高位地址
    // 出错虚地址
    reg  [31: 0] csr_save0_data;
    reg  [31: 0] csr_save1_data;
    reg  [31: 0] csr_save2_data;
    reg  [31: 0] csr_save3_data;

    // // 定时器编号 
    // reg  [31: 0] cs_tid_data;

    // // 定时器配置
    // wire [31: 0] cs_tcfg_data;
    // reg          cs_tcfg_en;
    // reg          cs_tcfg_periodic;

    // 定时中断清除
    wire [31: 0] csr_ticlr_data;

    assign has_int = (~|(csr_estat_is[11:0] & csr_ecfg_lie[11:0])) & csr_crmd_ie;
    assign ex_entry = csr_eentry_data;
    assign ertn_entry = csr_era_data;
    // CRMD的PLV、IE域
    always @(posedge clk) begin
        if (reset) begin
            csr_crmd_plv <= 2'b0;
            csr_crmd_ie  <= 1'b0;
        end
        else if (wb_ex) begin
            csr_crmd_plv <= 2'b0;
            csr_crmd_ie  <= 1'b0;
        end
        else if (ertn_flush) begin
            csr_crmd_plv <= csr_prmd_pplv;
            csr_crmd_ie  <= csr_prmd_pie;
        end
        else if (csr_we && csr_num == `CSR_CRMD) begin
            csr_crmd_plv <= csr_wmask[`CSR_CRMD_PLV] & csr_wvalue[`CSR_CRMD_PLV]
                          | ~csr_wmask[`CSR_CRMD_PLV] & csr_crmd_plv;
            csr_crmd_ie  <= csr_wmask[`CSR_CRMD_IE ] & csr_wvalue[`CSR_CRMD_IE ]
                          | ~csr_wmask[`CSR_CRMD_IE ] & csr_crmd_ie;
        end
    end

    // CRMD的DA、PG、DATF、DATM域
    always @(posedge clk) begin
        if(reset) begin
            csr_crmd_da   <= 1'b1;
            csr_crmd_pg   <= 1'b0;
            csr_crmd_datf <= 2'b0;
            csr_crmd_datm <= 2'b0;
        end
        // else if(TLB重填例外) begin
        //     csr_crmd_da   <= 1'b1;
        //     csr_crmd_pg   <= 1'b1;
        // end
        else if (csr_we && csr_estat_ecode == 6'h3f) begin
            csr_crmd_da   <= 1'b0;
            csr_crmd_pg   <= 1'b1;
            csr_crmd_datf <= 2'b01;
            csr_crmd_datm <= 2'b01;            
        end
    end

    // PRMD的PPLV、PIE域
    always @(posedge clk) begin
        if (wb_ex) begin
            csr_prmd_pplv <= csr_crmd_plv;
            csr_prmd_pie  <= csr_crmd_ie;
        end
        else if (csr_we && csr_num==`CSR_PRMD) begin
            csr_prmd_pplv <=  csr_wmask[`CSR_PRMD_PPLV] & csr_wvalue[`CSR_PRMD_PPLV]
                           | ~csr_wmask[`CSR_PRMD_PPLV] & csr_prmd_pplv;
            csr_prmd_pie  <=  csr_wmask[`CSR_PRMD_PIE ] & csr_wvalue[`CSR_PRMD_PIE ]
                           | ~csr_wmask[`CSR_PRMD_PIE ] & csr_prmd_pie;
        end
    end

    // ECFG的LIE域
    always @(posedge clk) begin
        if(reset)
            csr_ecfg_lie <= 13'b0;
        else if(csr_we && csr_num == `CSR_ECFG)
            csr_ecfg_lie <= csr_wmask[`CSR_ECFG_LIE] & csr_wvalue[`CSR_ECFG_LIE]
                        |  ~csr_wmask[`CSR_ECFG_LIE] & csr_ecfg_lie;
    end
    // ESTAT的IS域
    always @(posedge clk) begin
        if (reset) begin
            csr_estat_is[1:0] <= 2'b0;
        end
        else if (csr_we && (csr_num == `CSR_ESTAT)) begin
            csr_estat_is[1:0] <= ( csr_wmask[`CSR_ESTAT_IS10] & csr_wvalue[`CSR_ESTAT_IS10])
                               | (~csr_wmask[`CSR_ESTAT_IS10] & csr_estat_is[1:0]          );
        end

        // csr_estat_is[9:2] <= hw_int_in[7:0]; //硬中断
        csr_estat_is[9:2] <= 8'b0;
        csr_estat_is[ 10] <= 1'b0;

        csr_estat_is[ 11] <= 1'b0;
        // if (timer_cnt[31:0] == 32'b0) begin
        //     csr_estat_is[11] <= 1'b1;
        // end
        // else if (csr_we && csr_num == `CSR_TICLR && csr_wmask[`CSR_TICLR_CLR] 
        //         && csr_wvalue[`CSR_TICLR_CLR]) 
        //     csr_estat_is[11] <= 1'b0;

        // csr_estat_is[ 12] <= ipi_int_in;
        csr_estat_is[ 12] <= 1'b0;  // 核间中断
    end    
    // ESTAT的Ecode和EsubCode域
    always @(posedge clk) begin
        if (wb_ex) begin
            csr_estat_ecode    <= wb_ecode;
            csr_estat_esubcode <= wb_esubcode;
        end
    end
    // ERA的PC域
    always @(posedge clk) begin
        if(wb_ex)
            csr_era_data <= wb_pc;
        else if (csr_we && csr_num == `CSR_ERA) 
            csr_era_data <= csr_wmask[`CSR_ERA_PC] & csr_wvalue[`CSR_ERA_PC]
                        | ~csr_wmask[`CSR_ERA_PC] & csr_era_data;
    end
     // EENTRY
    always @(posedge clk) begin
        if (csr_we && (csr_num == `CSR_EENTRY))
            csr_eentry_va <=   csr_wmask[`CSR_EENTRY_VA] & csr_wvalue[`CSR_EENTRY_VA]
                            | ~csr_wmask[`CSR_EENTRY_VA] & csr_eentry_va ;
    end

    // SAVE0~3
    always @(posedge clk) begin
        if (csr_we && csr_num == `CSR_SAVE0) 
            csr_save0_data <=  csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                            | ~csr_wmask[`CSR_SAVE_DATA] & csr_save0_data;
        if (csr_we && (csr_num == `CSR_SAVE1)) 
            csr_save1_data <=  csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                            | ~csr_wmask[`CSR_SAVE_DATA] & csr_save1_data;
        if (csr_we && (csr_num == `CSR_SAVE2)) 
            csr_save2_data <=  csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                            | ~csr_wmask[`CSR_SAVE_DATA] & csr_save2_data;
        if (csr_we && (csr_num == `CSR_SAVE3)) 
            csr_save3_data <=  csr_wmask[`CSR_SAVE_DATA] & csr_wvalue[`CSR_SAVE_DATA]
                            | ~csr_wmask[`CSR_SAVE_DATA] & csr_save3_data;
    end
    // BADV的VAddr域
    assign csr_crmd_data  = {23'b0, csr_crmd_datm, csr_crmd_datf, csr_crmd_pg, 
                            csr_crmd_da, csr_crmd_ie, csr_crmd_plv};
    assign csr_prmd_data  = {29'b0, csr_prmd_pie, csr_prmd_pplv};
    assign csr_ecfg_data  = {19'b0, csr_ecfg_lie};
    assign csr_estat_data = { 1'b0, csr_estat_esubcode, csr_estat_ecode, 3'b0, csr_estat_is};
    assign csr_eentry_data= {csr_eentry_va, 6'b0};

    assign csr_rvalue = {32{csr_num == `CSR_CRMD  }} & csr_crmd_data
                      | {32{csr_num == `CSR_PRMD  }} & csr_prmd_data
                      | {32{csr_num == `CSR_ECFG  }} & csr_ecfg_data
                      | {32{csr_num == `CSR_ESTAT }} & csr_estat_data
                      | {32{csr_num == `CSR_ERA   }} & csr_era_data
                      | {32{csr_num == `CSR_EENTRY}} & csr_eentry_data
                      | {32{csr_num == `CSR_SAVE0 }} & csr_save0_data
                      | {32{csr_num == `CSR_SAVE1 }} & csr_save1_data
                      | {32{csr_num == `CSR_SAVE2 }} & csr_save2_data
                      | {32{csr_num == `CSR_SAVE3 }} & csr_save3_data
                      | {32{csr_num == `CSR_TICLR }} & csr_ticlr_data;

    assign csr_ticlr_data = 32'b0;
endmodule