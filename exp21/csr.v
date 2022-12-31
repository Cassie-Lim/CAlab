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
    input  wire [ 5:0]   wb_ecode  , //来自WB阶段的异常类型
    input  wire [ 8:0]   wb_esubcode,//来自WB阶段的异常类型辅助码
    input  wire [31:0]   wb_vaddr   ,//来自WB阶段的访存地址
    input  wire [31:0]   wb_pc,      //写回的返回地址
// --- TLB ---

    //tlbsrch
    input  wire          inst_wb_tlbsrch,
    input  wire          tlbsrch_found,
    input  wire [`TLBNUM_IDX-1:0] tlbsrch_idxgot,
    output wire [`TLBNUM_IDX-1:0] tlbindex_index_CSRoutput,
        // 带有CSRoutput格式的命名，是为了便于在CPU Core中统一。 
    
    //tlbrd
    //要注意tlbsrch和tlbrd使用的并非同一套端口
    input  wire         inst_wb_tlbrd,

    input  wire         tlbread_e, // 是有效TLB项
    input  wire  [ 5:0] tlbread_ps,
    input  wire  [18:0] tlbread_vppn,
    input  wire  [ 9:0] tlbread_asid,
    input  wire         tlbread_g,

    input  wire  [19:0] tlbread_ppn0,
    input  wire  [ 1:0] tlbread_plv0,
    input  wire  [ 1:0] tlbread_mat0,
    input  wire         tlbread_d0,
    input  wire         tlbread_v0,

    input  wire  [19:0] tlbread_ppn1,
    input  wire  [ 1:0] tlbread_plv1,
    input  wire  [ 1:0] tlbread_mat1,
    input  wire         tlbread_d1,
    input  wire         tlbread_v1,

    // tlbwr & refill
    // input  wire        inst_wb_tlbwr,   //这个信号没用,tlbrefill同理
    output wire        tlbwr_e,
    output wire [ 5:0] tlbwr_ps,
    output wire [18:0] tlbehi_vppn_CSRoutput,
    output wire [ 9:0] asid_CSRoutput,
    output wire        tlbwr_g,

    output wire [19:0] tlbwr_ppn0,
    output wire [ 1:0] tlbwr_plv0,
    output wire [ 1:0] tlbwr_mat0,
    output wire        tlbwr_d0,
    output wire        tlbwr_v0,

    output wire [19:0] tlbwr_ppn1,
    output wire [ 1:0] tlbwr_plv1,
    output wire [ 1:0] tlbwr_mat1,
    output wire        tlbwr_d1,
    output wire        tlbwr_v1,

    // 需要查看特权等级以进行地址转换
    output wire [ 1:0] crmd_plv_CSRoutput,
    // DMW0
    output wire        csr_dmw0_plv0,
    output wire        csr_dmw0_plv3,
    output wire [ 2:0] csr_dmw0_pseg,
    output wire [ 2:0] csr_dmw0_vseg,
    // DMW1
    output wire        csr_dmw1_plv0,
    output wire        csr_dmw1_plv3,
    output wire [ 2:0] csr_dmw1_pseg,
    output wire [ 2:0] csr_dmw1_vseg,
    // 直接地址翻译
    output wire        csr_direct_addr,

    output wire [ 5:0] estat_ecode_CSRoutput,
    input  wire        current_exc_fetch
);
    wire [ 7: 0] hw_int_in;
    wire         ipi_int_in;
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
    // 数据保存
    reg  [31: 0] csr_save0_data;
    reg  [31: 0] csr_save1_data;
    reg  [31: 0] csr_save2_data;
    reg  [31: 0] csr_save3_data;
    // 出错虚地址
    wire         wb_ex_addr_err;
    reg  [31: 0] csr_badv_vaddr;
    wire [31: 0] csr_badv_data;
    // 定时器编号 
    wire [31: 0] csr_tid_data;
    reg  [31: 0] csr_tid_tid;

    // 定时器配置
    wire [31: 0] csr_tcfg_data;
    reg          csr_tcfg_en;
    reg          csr_tcfg_periodic;
    reg  [29: 0] csr_tcfg_initval;
    wire [31: 0] tcfg_next_value;

    // 定时器数值
    wire [31: 0] csr_tval_data;
    reg  [31: 0] timer_cnt;
    // 定时中断清除
    wire [31: 0] csr_ticlr_data;

    // TLB
    wire [31:0] tlbidx_data;
    reg  [`TLBNUM_IDX-1:0] tlbindex_index;
    reg  [ 5:0] tlbindex_ps;
    reg         tlbindex_ne;
    wire [31:0] tlbehi_data;
    reg  [18:0] tlbehi_vppn;
    wire [31:0] tlbelo0_data;
    reg         tlbelo0_v;
    reg         tlbelo0_d;
    reg  [ 1:0] tlbelo0_plv;
    reg  [ 1:0] tlbelo0_mat;
    reg         tlbelo0_g;
    reg  [`PALEN-13:0] tlbelo0_ppn;
    wire [31:0] tlbelo1_data;
    reg         tlbelo1_v;
    reg         tlbelo1_d;
    reg  [ 1:0] tlbelo1_plv;
    reg  [ 1:0] tlbelo1_mat;
    reg         tlbelo1_g;
    reg  [`PALEN-13:0] tlbelo1_ppn;
    wire [31:0] asid_data;
    reg  [ 9:0] asid_asid;
    wire [ 7:0] asid_asidbits;
    wire [31:0] tlbrentry_data;
    reg  [25:0] tlbrentry_pa;
    reg         dmw0_plv0;
    reg         dmw0_plv3;
    reg  [ 1:0] dmw0_mat ;
    reg  [ 2:0] dmw0_pseg;
    reg  [ 2:0] dmw0_vseg;
    wire [31:0] dmw0_data;
    reg         dmw1_plv0;
    reg         dmw1_plv3;
    reg  [ 1:0] dmw1_mat ;
    reg  [ 2:0] dmw1_pseg;
    reg  [ 2:0] dmw1_vseg;
    wire [31:0] dmw1_data;
    wire        tlbehi_exc;
    reg         current_exc_fetch_r;

    assign has_int = (|(csr_estat_is[11:0] & csr_ecfg_lie[11:0])) & csr_crmd_ie;
    assign ex_entry = (wb_ecode == 6'h3f) ? tlbrentry_data : csr_eentry_data;
    assign ertn_entry = csr_era_data;
    // CRMD的PLV、IE域
    assign crmd_plv_CSRoutput = csr_crmd_plv;
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
        else if (csr_we && csr_num == `CSR_CRMD) begin
            csr_crmd_da <= csr_wmask[`CSR_CRMD_DA] & csr_wvalue[`CSR_CRMD_DA]
                          | ~csr_wmask[`CSR_CRMD_DA] & csr_crmd_da;
            csr_crmd_pg  <= csr_wmask[`CSR_CRMD_PG ] & csr_wvalue[`CSR_CRMD_PG ]
                          | ~csr_wmask[`CSR_CRMD_PG ] & csr_crmd_pg;
            csr_crmd_datf <= csr_wmask[`CSR_CRMD_DATF] & csr_wvalue[`CSR_CRMD_DATF]
                          | ~csr_wmask[`CSR_CRMD_DATF] & csr_crmd_datf;            
            csr_crmd_datm <= csr_wmask[`CSR_CRMD_DATM] & csr_wvalue[`CSR_CRMD_DATM]
                          | ~csr_wmask[`CSR_CRMD_DATM] & csr_crmd_datm;
        end
        else if (ertn_flush && csr_estat_ecode == `ECODE_TLBR) begin
            csr_crmd_da   <= 1'b0;
            csr_crmd_pg   <= 1'b1;
            csr_crmd_datf <= current_exc_fetch_r ? 2'b01 : 2'b00;
            csr_crmd_datm <= current_exc_fetch_r ? 2'b00 : 2'b01;
        end
        else if (wb_ex && wb_ecode == `ECODE_TLBR) begin
            csr_crmd_da   <= 1'b1;
            csr_crmd_pg   <= 1'b0;
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
    assign hw_int_in = 8'b0;
    assign ipi_int_in= 1'b0;
    always @(posedge clk) begin
        if (reset) begin
            csr_estat_is[1:0] <= 2'b0;
        end
        else if (csr_we && (csr_num == `CSR_ESTAT)) begin
            csr_estat_is[1:0] <= ( csr_wmask[`CSR_ESTAT_IS10] & csr_wvalue[`CSR_ESTAT_IS10])
                               | (~csr_wmask[`CSR_ESTAT_IS10] & csr_estat_is[1:0]          );
        end

        csr_estat_is[9:2] <= hw_int_in[7:0]; //硬中断
        csr_estat_is[10] <= 1'b0; 

        if (timer_cnt[31:0] == 32'b0) begin
            csr_estat_is[11] <= 1'b1;
        end
        else if (csr_we && csr_num == `CSR_TICLR && csr_wmask[`CSR_TICLR_CLR] 
                && csr_wvalue[`CSR_TICLR_CLR]) 
            csr_estat_is[11] <= 1'b0;
        csr_estat_is[12] <= ipi_int_in;     // 核间中断
    end    
    // ESTAT的Ecode和EsubCode域
    always @(posedge clk) begin
        if (wb_ex) begin
            csr_estat_ecode    <= wb_ecode;
            csr_estat_esubcode <= wb_esubcode;
            current_exc_fetch_r<=current_exc_fetch;
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
    assign wb_ex_addr_err = wb_ecode==`ECODE_ALE || wb_ecode==`ECODE_ADE || wb_ecode==`ECODE_TLBR || wb_ecode==`ECODE_PIL
                         || wb_ecode==`ECODE_PIS || wb_ecode==`ECODE_PIF || wb_ecode==`ECODE_PME  || wb_ecode==`ECODE_PPI; 
    always @(posedge clk) begin
        if (wb_ex && wb_ex_addr_err) begin
            csr_badv_vaddr <= current_exc_fetch ? wb_pc : wb_vaddr;
        end
    end
    // TID
    always @(posedge clk) begin
        if (reset) begin
            csr_tid_tid <= 32'b0;
        end
        else if (csr_we && csr_num == `CSR_TID) begin
            csr_tid_tid <= csr_wmask[`CSR_TID_TID] & csr_wvalue[`CSR_TID_TID]
                        | ~csr_wmask[`CSR_TID_TID] & csr_tid_tid;
        end
    end

    // TCFG的EN、Periodic、InitVal域
    always @(posedge clk) begin
        if (reset) begin
            csr_tcfg_en <= 1'b0;
            csr_tcfg_periodic <= 1'b0;
            csr_tcfg_initval <= 30'b0;
        end
        else if (csr_we && csr_num == `CSR_TCFG) begin
            csr_tcfg_en <= csr_wmask[`CSR_TCFG_EN] & csr_wvalue[`CSR_TCFG_EN]
                        | ~csr_wmask[`CSR_TCFG_EN] & csr_tcfg_en;
            csr_tcfg_periodic <= csr_wmask[`CSR_TCFG_PERIOD] & csr_wvalue[`CSR_TCFG_PERIOD]
                              | ~csr_wmask[`CSR_TCFG_PERIOD] & csr_tcfg_periodic;
            csr_tcfg_initval  <= csr_wmask[`CSR_TCFG_INITV] & csr_wvalue[`CSR_TCFG_INITV]
                              | ~csr_wmask[`CSR_TCFG_INITV] & csr_tcfg_initval;
        end
    end

    // TVAL
    assign tcfg_next_value = csr_wmask[31:0] & csr_wvalue[31:0]
                           |~csr_wmask[31:0] & csr_tcfg_data;
    always @(posedge clk) begin
        if (reset) begin
            timer_cnt <= 32'hffffffff;
        end
        else if (csr_we && csr_num == `CSR_TCFG && tcfg_next_value[`CSR_TCFG_EN]) begin
            timer_cnt <= {tcfg_next_value[`CSR_TCFG_INITV], 2'b0};
        end
        else if (csr_tcfg_en && timer_cnt != 32'hffffffff) begin
            if (timer_cnt[31:0] == 32'b0 && csr_tcfg_periodic) begin
                // TODO 应该执行这行但是没执行
                timer_cnt <= {csr_tcfg_initval, 2'b0};
            end
            else begin
                timer_cnt <= timer_cnt - 1'b1;
            end
        end
    end

    // TICLR的CLR域
    assign csr_ticlr_clr = 1'b0;

    assign csr_crmd_data  = {23'b0, csr_crmd_datm, csr_crmd_datf, csr_crmd_pg, 
                            csr_crmd_da, csr_crmd_ie, csr_crmd_plv};
    assign csr_prmd_data  = {29'b0, csr_prmd_pie, csr_prmd_pplv};
    assign csr_ecfg_data  = {19'b0, csr_ecfg_lie};
    assign csr_estat_data = { 1'b0, csr_estat_esubcode, csr_estat_ecode, 3'b0, csr_estat_is};
    assign csr_eentry_data= {csr_eentry_va, 6'b0};
    assign csr_badv_data  = csr_badv_vaddr;
    assign csr_tid_data   = csr_tid_tid;
    assign csr_tcfg_data  = {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en};
    assign csr_tval_data  = timer_cnt;
    assign csr_ticlr_data = {31'b0, csr_ticlr_clr};
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
                      | {32{csr_num == `CSR_BADV  }} & csr_badv_data
                      | {32{csr_num == `CSR_TID   }} & csr_tid_data
                      | {32{csr_num == `CSR_TCFG  }} & csr_tcfg_data
                      | {32{csr_num == `CSR_TVAL  }} & csr_tval_data
                      | {32{csr_num == `CSR_TICLR }} & csr_ticlr_data
                      | {32{csr_num == `CSR_TLBIDX}} & tlbidx_data
                      | {32{csr_num == `CSR_TLBEHI}} & tlbehi_data
                      | {32{csr_num == `CSR_TLBELO0}} & tlbelo0_data
                      | {32{csr_num == `CSR_TLBELO1}} & tlbelo1_data
                      | {32{csr_num == `CSR_ASID  }} & asid_data
                      | {32{csr_num == `CSR_TLBRENTRY}} & tlbrentry_data;


    // ------------ TLB -------------
    // TLBIDX
    assign tlbindex_index_CSRoutput = tlbindex_index;
    assign tlbidx_data = {tlbindex_ne, 1'b0, tlbindex_ps, 8'h0, 12'h0, tlbindex_index};// 假定TLBNUM=16,后续需要修改！
    always @(posedge clk) begin
        if (reset) begin
            tlbindex_index <= 4'b0;
            tlbindex_ps <= 6'b0;
            tlbindex_ne <= 1'b0;
        end
        else if (csr_we && csr_num == `CSR_TLBIDX) begin
            tlbindex_index <= csr_wmask[`CSR_TLBIDX_INDEX] & csr_wvalue[`CSR_TLBIDX_INDEX]
                           | ~csr_wmask[`CSR_TLBIDX_INDEX] & tlbindex_index;
            tlbindex_ps <= csr_wmask[`CSR_TLBIDX_PS] & csr_wvalue[`CSR_TLBIDX_PS]
                        | ~csr_wmask[`CSR_TLBIDX_PS] & tlbindex_ps;
            tlbindex_ne <= csr_wmask[`CSR_TLBIDX_NE] & csr_wvalue[`CSR_TLBIDX_NE]
                        | ~csr_wmask[`CSR_TLBIDX_NE] & tlbindex_ne;
        end
        else if (inst_wb_tlbsrch) begin
            tlbindex_ne <= ~tlbsrch_found;
            tlbindex_index <= tlbsrch_found ? tlbsrch_idxgot : tlbindex_index; // 避免多层嵌套
        end
        else if (inst_wb_tlbrd) begin
            tlbindex_ps <= {6{tlbread_e}} & tlbread_ps;
            tlbindex_ne <= ~tlbread_e;
        end
    end
    
        // output for tlbwr
    assign tlbwr_e  = ~tlbindex_ne;
    assign tlbwr_ps =  tlbindex_ps;

    // TLBEHI
    assign tlbehi_data = {tlbehi_vppn, 13'h0};
    assign tlbehi_exc  = wb_ecode == `ECODE_TLBR || wb_ecode == `ECODE_PIL || wb_ecode == `ECODE_PIS 
                      || wb_ecode == `ECODE_PIF  || wb_ecode == `ECODE_PME || wb_ecode == `ECODE_PPI;
    always @(posedge clk) begin
        if (reset) begin
            tlbehi_vppn <= 19'b0;
        end
        else if (wb_ex && tlbehi_exc)begin
            tlbehi_vppn <= current_exc_fetch ? wb_pc[`CSR_TLBEHI_VPPN] : wb_vaddr[`CSR_TLBEHI_VPPN];
        end
        else if(csr_we && csr_num == `CSR_TLBEHI) begin
            tlbehi_vppn <= csr_wmask[`CSR_TLBEHI_VPPN] & csr_wvalue[`CSR_TLBEHI_VPPN]
                        | ~csr_wmask[`CSR_TLBEHI_VPPN] & tlbehi_vppn;
        end
        else if (inst_wb_tlbrd) begin
            tlbehi_vppn <= tlbread_e ? tlbread_vppn : 19'd0; 
        end
    end
    assign tlbehi_vppn_CSRoutput = tlbehi_vppn;

    assign tlbwr_g = tlbelo0_g && tlbelo1_g;
    // TLBELO0
    assign tlbelo0_data = {4'h0, tlbelo0_ppn, 1'b0, tlbelo0_g, tlbelo0_mat, tlbelo0_plv, tlbelo0_d, tlbelo0_v};// 假定PALEN=32,后续需要修改！
    always @(posedge clk) begin
        if (reset) begin
            tlbelo0_v <= 1'b0;
            tlbelo0_d <= 1'b0;
            tlbelo0_plv <= 2'b0;
            tlbelo0_mat <= 2'b0;
            tlbelo0_g <= 1'b0;
            tlbelo0_ppn <= 20'b0;
        end
        else if(csr_we && csr_num == `CSR_TLBELO0) begin
            tlbelo0_v <= csr_wmask[`CSR_TLBELO_V] & csr_wvalue[`CSR_TLBELO_V]
                        | ~csr_wmask[`CSR_TLBELO_V] & tlbelo0_v;
            tlbelo0_d <= csr_wmask[`CSR_TLBELO_D] & csr_wvalue[`CSR_TLBELO_D]
                        | ~csr_wmask[`CSR_TLBELO_D] & tlbelo0_d;
            tlbelo0_plv <= csr_wmask[`CSR_TLBELO_PLV] & csr_wvalue[`CSR_TLBELO_PLV]
                        | ~csr_wmask[`CSR_TLBELO_PLV] & tlbelo0_plv;
            tlbelo0_mat <= csr_wmask[`CSR_TLBELO_MAT] & csr_wvalue[`CSR_TLBELO_MAT]
                        | ~csr_wmask[`CSR_TLBELO_MAT] & tlbelo0_mat;
            tlbelo0_g <= csr_wmask[`CSR_TLBELO_G] & csr_wvalue[`CSR_TLBELO_G]
                        | ~csr_wmask[`CSR_TLBELO_G] & tlbelo0_g;
            tlbelo0_ppn <= csr_wmask[`CSR_TLBELO_PPN] & csr_wvalue[`CSR_TLBELO_PPN]
                        | ~csr_wmask[`CSR_TLBELO_PPN] & tlbelo0_ppn;
        end
        else if (inst_wb_tlbrd) begin
            if (tlbread_e) begin
                tlbelo0_v <= tlbread_v0;
                tlbelo0_d <= tlbread_d0;
                tlbelo0_plv <= tlbread_plv0;
                tlbelo0_mat <= tlbread_mat0;
                tlbelo0_g <= tlbread_g;
                tlbelo0_ppn <= tlbread_ppn0;                  
            end
            else begin
                tlbelo0_v <= 1'b0;
                tlbelo0_d <= 1'b0;
                tlbelo0_plv <= 2'b0;
                tlbelo0_mat <= 2'b0;
                tlbelo0_g <= 1'b0;
                tlbelo0_ppn <= 20'b0;
            end
        end
    end
    assign tlbwr_ppn0 = tlbelo0_ppn;
    assign tlbwr_plv0 = tlbelo0_plv;
    assign tlbwr_mat0 = tlbelo0_mat;
    assign tlbwr_d0   = tlbelo0_d;
    assign tlbwr_v0   = tlbelo0_v;

    // TLBELO1
    assign tlbelo1_data = {4'h0, tlbelo1_ppn, 1'b0, tlbelo1_g, tlbelo1_mat, tlbelo1_plv, tlbelo1_d, tlbelo1_v};// 假定PALEN=32,后续需要修改！
    always @(posedge clk) begin
        if (reset) begin
            tlbelo1_v <= 1'b0;
            tlbelo1_d <= 1'b0;
            tlbelo1_plv <= 2'b0;
            tlbelo1_mat <= 2'b0;
            tlbelo1_g <= 1'b0;
            tlbelo1_ppn <= 20'b0;
        end
        else if(csr_we && csr_num == `CSR_TLBELO1) begin
            tlbelo1_v <= csr_wmask[`CSR_TLBELO_V] & csr_wvalue[`CSR_TLBELO_V]
                        | ~csr_wmask[`CSR_TLBELO_V] & tlbelo1_v;
            tlbelo1_d <= csr_wmask[`CSR_TLBELO_D] & csr_wvalue[`CSR_TLBELO_D]
                        | ~csr_wmask[`CSR_TLBELO_D] & tlbelo1_d;
            tlbelo1_plv <= csr_wmask[`CSR_TLBELO_PLV] & csr_wvalue[`CSR_TLBELO_PLV]
                        | ~csr_wmask[`CSR_TLBELO_PLV] & tlbelo1_plv;
            tlbelo1_mat <= csr_wmask[`CSR_TLBELO_MAT] & csr_wvalue[`CSR_TLBELO_MAT]
                        | ~csr_wmask[`CSR_TLBELO_MAT] & tlbelo1_mat;
            tlbelo1_g <= csr_wmask[`CSR_TLBELO_G] & csr_wvalue[`CSR_TLBELO_G]
                        | ~csr_wmask[`CSR_TLBELO_G] & tlbelo1_g;
            tlbelo1_ppn <= csr_wmask[`CSR_TLBELO_PPN] & csr_wvalue[`CSR_TLBELO_PPN]
                        | ~csr_wmask[`CSR_TLBELO_PPN] & tlbelo1_ppn;
        end
        else if (inst_wb_tlbrd) begin
            if (tlbread_e) begin
                tlbelo1_v <= tlbread_v1;
                tlbelo1_d <= tlbread_d1;
                tlbelo1_plv <= tlbread_plv1;
                tlbelo1_mat <= tlbread_mat1;
                tlbelo1_g <= tlbread_g;
                tlbelo1_ppn <= tlbread_ppn1;                  
            end
            else begin
                tlbelo1_v <= 1'b0;
                tlbelo1_d <= 1'b0;
                tlbelo1_plv <= 2'b0;
                tlbelo1_mat <= 2'b0;
                tlbelo1_g <= 1'b0;
                tlbelo1_ppn <= 20'b0;
            end
        end
    end
    assign tlbwr_ppn1 = tlbelo1_ppn;
    assign tlbwr_plv1 = tlbelo1_plv;
    assign tlbwr_mat1 = tlbelo1_mat;
    assign tlbwr_d1   = tlbelo1_d;
    assign tlbwr_v1   = tlbelo1_v;

    // ASID
    assign asid_asidbits = 8'd10;
    assign asid_data = {8'h0, asid_asidbits, 6'h0, asid_asid};
    always @(posedge clk) begin
        if (reset) begin
            asid_asid <= 10'b0;
        end
        else if(csr_we && csr_num == `CSR_ASID) begin
             asid_asid <= csr_wmask[`CSR_ASID_ASID] & csr_wvalue[`CSR_ASID_ASID]
                       | ~csr_wmask[`CSR_ASID_ASID] & asid_asid;
        end
        else if (inst_wb_tlbrd) begin
            asid_asid <= {10{tlbread_e}} & tlbread_asid;
        end
    end
    assign asid_CSRoutput = asid_asid;
    // TLBRENTRY
    assign tlbrentry_data = {tlbrentry_pa, 6'h0};
    always @(posedge clk) begin
        if (reset) begin
            tlbrentry_pa <= 26'b0;
        end
        else if(csr_we && csr_num == `CSR_TLBRENTRY) begin
             tlbrentry_pa <= csr_wmask[`CSR_TLBRENTRY_PA] & csr_wvalue[`CSR_TLBRENTRY_PA]
                       | ~csr_wmask[`CSR_TLBRENTRY_PA] & tlbrentry_pa;
        end
    end
    // DMW0
    assign csr_dmw0_plv0 = dmw0_plv0;
    assign csr_dmw0_plv3 = dmw0_plv3;
    assign csr_dmw0_pseg = dmw0_pseg;
    assign csr_dmw0_vseg = dmw0_vseg;
        assign dmw0_data = {dmw0_vseg, 1'b0, dmw0_pseg, 19'd0, dmw0_mat, dmw0_plv3, 2'd0, dmw0_plv0};
    always @(posedge clk ) begin
        if (reset) begin
            dmw0_plv0 <= 1'b0;
            dmw0_plv3 <= 1'b0;
            dmw0_mat  <= 2'h0;
            dmw0_pseg <= 3'h0;
            dmw0_vseg <= 3'h0;
        end
        else if(csr_we && csr_num == `CSR_DMW0) begin
            dmw0_plv0 <= csr_wmask[`CSR_DMW_PLV0] & csr_wvalue[`CSR_DMW_PLV0]
                       | ~csr_wmask[`CSR_DMW_PLV0] & dmw0_plv0;
            dmw0_plv3 <= csr_wmask[`CSR_DMW_PLV3] & csr_wvalue[`CSR_DMW_PLV3]
                       | ~csr_wmask[`CSR_DMW_PLV3] & dmw0_plv3;   
            dmw0_mat  <= csr_wmask[`CSR_DMW_MAT ] & csr_wvalue[`CSR_DMW_MAT ]
                       | ~csr_wmask[`CSR_DMW_MAT] & dmw0_mat ;    
            dmw0_pseg <= csr_wmask[`CSR_DMW_PSEG] & csr_wvalue[`CSR_DMW_PSEG]
                       | ~csr_wmask[`CSR_DMW_PSEG] & dmw0_pseg;
            dmw0_vseg <= csr_wmask[`CSR_DMW_VSEG] & csr_wvalue[`CSR_DMW_VSEG]
                       | ~csr_wmask[`CSR_DMW_VSEG] & dmw0_vseg;
        end
    end
    // DMW1
    assign csr_dmw1_plv0 = dmw1_plv0;
    assign csr_dmw1_plv3 = dmw1_plv3;
    assign csr_dmw1_pseg = dmw1_pseg;
    assign csr_dmw1_vseg = dmw1_vseg;
    assign dmw1_data = {dmw1_vseg, 1'b0, dmw1_pseg, 19'd0, dmw1_mat, dmw1_plv3, 2'd0, dmw1_plv0};
    always @(posedge clk ) begin
        if (reset) begin
            dmw1_plv0 <= 1'b0;
            dmw1_plv3 <= 1'b0;
            dmw1_mat  <= 2'h0;
            dmw1_pseg <= 3'h0;
            dmw1_vseg <= 3'h0;
        end
        else if(csr_we && csr_num == `CSR_DMW1) begin
            dmw1_plv0 <= csr_wmask[`CSR_DMW_PLV0] & csr_wvalue[`CSR_DMW_PLV0]
                       | ~csr_wmask[`CSR_DMW_PLV0] & dmw1_plv0;
            dmw1_plv3 <= csr_wmask[`CSR_DMW_PLV3] & csr_wvalue[`CSR_DMW_PLV3]
                       | ~csr_wmask[`CSR_DMW_PLV3] & dmw1_plv3;   
            dmw1_mat  <= csr_wmask[`CSR_DMW_MAT ] & csr_wvalue[`CSR_DMW_MAT ]
                       | ~csr_wmask[`CSR_DMW_MAT] & dmw1_mat ;    
            dmw1_pseg <= csr_wmask[`CSR_DMW_PSEG] & csr_wvalue[`CSR_DMW_PSEG]
                       | ~csr_wmask[`CSR_DMW_PSEG] & dmw1_pseg;
            dmw1_vseg <= csr_wmask[`CSR_DMW_VSEG] & csr_wvalue[`CSR_DMW_VSEG]
                       | ~csr_wmask[`CSR_DMW_VSEG] & dmw1_vseg;
        end
    end
    // 地址直接翻译
    assign csr_direct_addr = csr_crmd_da && ~csr_crmd_pg;

    assign estat_ecode_CSRoutput = csr_estat_ecode;
endmodule