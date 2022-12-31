`include "macro.h"
module IFreg(
    input  wire   clk,
    input  wire   resetn,
    // inst sram interface
    output wire         inst_sram_req,
    output wire         inst_sram_wr,
    output wire [ 1:0]  inst_sram_size,
    output wire [ 3:0]  inst_sram_wstrb,
    output wire [31:0]  inst_sram_addr,
    output wire [31:0]  inst_sram_wdata,
    input  wire         inst_sram_addr_ok,
    input  wire         inst_sram_data_ok,
    input  wire [31:0]  inst_sram_rdata,
    input  wire [ 3:0]  axi_arid,
    // ds to fs interface
    input  wire         ds_allowin,
    input  wire [33:0]  br_zip,
    // fs to ds interface
    output wire         fs2ds_valid,
    output wire [`FS2DS_LEN -1:0]  fs2ds_bus,
    // exception interface
    input  wire         wb_ex,
    input  wire         ertn_flush, // MODIFIED: TLB REFETCH REUSED; FOR DETAILS SEE MYCPU.CORE
    input  wire [31:0]  ex_entry,   
    input  wire [31:0]  ertn_entry, // MODIFIED: TLB REFETCH REUSED; FOR DETAILS SEE MYCPU.CORE
    // tlb
    output wire [18:0] s0_vppn,
    output wire        s0_va_bit12,
    input  wire        s0_found,
    input  wire [$clog2(`TLBNUM)-1:0] s0_index,
    input  wire [19:0] s0_ppn,
    input  wire [ 5:0] s0_ps,
    input  wire [ 1:0] s0_plv,
    input  wire [ 1:0] s0_mat,
    input  wire        s0_d,
    input  wire        s0_v,
    input  wire [ 1:0] crmd_plv_CSRoutput,
        // DMW0
    input  wire        csr_dmw0_plv0,
    input  wire        csr_dmw0_plv3,
    input  wire [ 2:0] csr_dmw0_pseg,
    input  wire [ 2:0] csr_dmw0_vseg,
        // DMW1
    input  wire        csr_dmw1_plv0,
    input  wire        csr_dmw1_plv3,
    input  wire [ 2:0] csr_dmw1_pseg,
    input  wire [ 2:0] csr_dmw1_vseg,
        // 直接地址翻译
    input  wire        csr_direct_addr
);
    wire        pf_ready_go;
    wire        to_fs_valid;
    reg         pf_block;
    reg         fs_valid;
    wire        fs_ready_go;
    wire        fs_allowin;

    wire [31:0] seq_pc;
    wire [31:0] nextpc_vrtl; // 虚拟地址 ADDED EXP19
    wire [31:0] nextpc_phy;  // 物理地址 ADDED EXP19

    wire         br_stall;
    wire         br_taken;
    wire [31:0]  br_target;
    reg          br_taken_r;
    reg          wb_ex_r;
    reg          ertn_flush_r;
    reg  [31:0]  br_target_r;
    reg  [31:0]  ex_entry_r;
    reg  [31:0]  ertn_entry_r;

    assign {br_stall, br_taken, br_target} = br_zip;

    wire [31:0] fs_inst;
    reg  [31:0] fs_pc;
    reg  [31:0] fs_inst_buf;
    reg         inst_buf_valid;  // 判断指令缓存是否有效
    reg         inst_sram_addr_ack;

    wire        fs_cancel;
    wire        pf_cancel;
    reg         inst_discard;   // 判断cancel之后是否需要丢掉一条指令

    wire        fs_except_adef;
    wire [`TLB_ERRLEN-1:0] fs_tlb_exc;

    // addr translation
    wire        dmw0_hit;
    wire        dmw1_hit;
    wire [31:0] dmw0_paddr;
    wire [31:0] dmw1_paddr;
    wire [31:0] tlb_paddr ;
    wire        tlb_used  ; // 确实用到了TLB进行地址翻译

    assign fs_except_adef = ((|nextpc_vrtl[1:0]) | (nextpc_vrtl[31] & crmd_plv_CSRoutput == 2'd3)) & ~dmw0_hit & ~dmw1_hit & fs_valid; 
//------------------------------pre-IF signal---------------------------------------
    assign pf_ready_go      = inst_sram_req & inst_sram_addr_ok; 
    assign to_fs_valid      = pf_ready_go & ~pf_cancel & ~pf_block;
    assign seq_pc           = fs_pc + 3'h4;  
    assign nextpc_vrtl      = wb_ex_r? ex_entry_r: wb_ex? ex_entry:
                              ertn_flush_r? ertn_entry_r: ertn_flush? ertn_entry:
                              br_taken_r? br_target_r: br_taken ? br_target : seq_pc;
    always @(posedge clk) begin
        if(~resetn) begin
            {wb_ex_r, ertn_flush_r, br_taken_r} <= 3'b0;
            {ex_entry_r, ertn_entry_r, br_target_r} <= {3{32'b0}};
        end
        else if(wb_ex) begin
            ex_entry_r <= ex_entry;
            wb_ex_r <= 1'b1;
        end
        else if(ertn_flush) begin
            ertn_entry_r <= ertn_entry;
            ertn_flush_r <= 1'b1;
        end    
        else if(br_taken) begin
            br_target_r <= br_target;
            br_taken_r <= 1'b1;
        end
        // 若对应地址已经获得了来自指令SRAM的ok，后续nextpc_vrtl不再从寄存器中取
        else if(pf_ready_go) begin
            {wb_ex_r, ertn_flush_r, br_taken_r} <= 3'b0;
        end
    end
    always @(posedge clk) begin
        if(~resetn)
            pf_block <= 1'b0;
        else if(pf_cancel & ~pf_block & ~axi_arid[0] & ~inst_sram_data_ok)
            pf_block <= 1'b1;
        else if(inst_sram_data_ok)
            pf_block <= 1'b0;
    end

    // 判断当前地址是否已经握手成功，若成功则拉低req，避免重复申请
    always @(posedge clk) begin
        if(~resetn)
            inst_sram_addr_ack <= 1'b0;
        else if(pf_ready_go)
            inst_sram_addr_ack <= 1'b1;
        else if(inst_sram_data_ok)
            inst_sram_addr_ack <= 1'b0;
    end
//------------------------------IF signal---------------------------------------
    assign fs_ready_go      = (inst_sram_data_ok | inst_buf_valid) & ~inst_discard;
    assign fs_allowin       = ~fs_valid | fs_ready_go & ds_allowin;     
    assign fs2ds_valid      = fs_valid & fs_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            fs_valid <= 1'b0;
        else if(fs_allowin)
            fs_valid <= to_fs_valid; // 在reset撤销的下一个时钟上升沿才开始取指
        else if(fs_cancel)
            fs_valid <= 1'b0;
    end
//------------------------------inst sram interface---------------------------------------
    assign inst_sram_req    = fs_allowin & resetn & ~br_stall & ~pf_block & ~inst_sram_addr_ack;
    assign inst_sram_wr     = |inst_sram_wstrb;
    assign inst_sram_wstrb  = 4'b0;
    assign inst_sram_addr   = nextpc_phy;
    assign inst_sram_wdata  = 32'b0;
    assign inst_sram_size   = 3'b0;
//------------------------------cancel relevant---------------------------------------
    assign fs_cancel = wb_ex | ertn_flush | br_taken;
    // assign pf_cancel = 1'b0;       // pre-IF无需被cancel，原因是在给出nextpc_vrtl时的值都是正确的
    assign pf_cancel = fs_cancel;
    always @(posedge clk) begin
        if(~resetn)
            inst_discard <= 1'b0;
        // 流水级取消：当pre-IF阶段发送错误地址请求已被指令SRAM接受 or IF内有有效指令且正在等待数据返回时，需要丢弃一条指令
        else if(fs_cancel & ~fs_allowin & ~fs_ready_go | pf_cancel & inst_sram_req)
            inst_discard <= 1'b1;
        else if(inst_discard & inst_sram_data_ok)
            inst_discard <= 1'b0;
    end
//------------------------------fs and ds state interface---------------------------------------

    always @(posedge clk) begin
        if(~resetn)
            fs_pc <= 32'h1BFF_FFFC;
        else if(to_fs_valid & fs_allowin)
            fs_pc <= nextpc_vrtl;
    end
    // 设置寄存器，暂存指令，并用valid信号表示其内指令是否有效
    always @(posedge clk) begin
        if(~resetn) begin
            fs_inst_buf <= 32'b0;
            inst_buf_valid <= 1'b0;
        end
        else if(to_fs_valid & fs_allowin)   // 缓存已经流入IF级
            inst_buf_valid <= 1'b0;
        else if(fs_cancel)                  // IF取消后需要清空当前buffer
            inst_buf_valid <= 1'b0;
        else if(~inst_buf_valid & inst_sram_data_ok & ~inst_discard) begin
            fs_inst_buf <= fs_inst;
            inst_buf_valid <= 1'b1;
        end
    end
    assign fs_inst    = inst_buf_valid ? fs_inst_buf : inst_sram_rdata;
    assign fs2ds_bus = {fs_tlb_exc, fs_except_adef ,fs_inst, fs_pc}; // 8+1+32+32
//------------------------------tlb---------------------------------------
    assign {s0_vppn, s0_va_bit12} = nextpc_vrtl[31:12];
    assign dmw0_hit  = (nextpc_vrtl[31:29] == csr_dmw0_vseg) && (crmd_plv_CSRoutput == 2'd0 && csr_dmw0_plv0 || crmd_plv_CSRoutput == 2'd3 && csr_dmw0_plv3);
    assign dmw1_hit  = (nextpc_vrtl[31:29] == csr_dmw1_vseg) && (crmd_plv_CSRoutput == 2'd0 && csr_dmw1_plv0 || crmd_plv_CSRoutput == 2'd3 && csr_dmw1_plv3);
    assign dmw0_paddr = {csr_dmw0_pseg, nextpc_vrtl[28:0]};
    assign dmw1_paddr = {csr_dmw1_pseg, nextpc_vrtl[28:0]};
    assign tlb_paddr  = (s0_ps == 6'd22) ? {s0_ppn[19:10], nextpc_vrtl[21:0]} : {s0_ppn, nextpc_vrtl[11:0]}; // 根据Page Size决定
    assign nextpc_phy = csr_direct_addr ? nextpc_vrtl :
                        dmw0_hit        ? dmw0_paddr  :
                        dmw1_hit        ? dmw1_paddr  :
                                          tlb_paddr   ;     
    assign tlb_used = ~csr_direct_addr && ~dmw0_hit && ~dmw1_hit;
    assign {fs_tlb_exc[`EARRAY_PIL],fs_tlb_exc[`EARRAY_PIS],fs_tlb_exc[`EARRAY_PME],fs_tlb_exc[`EARRAY_TLBR_MEM], fs_tlb_exc[`EARRAY_PPI_MEM]} = 5'h0;
    assign fs_tlb_exc[`EARRAY_TLBR_FETCH] = fs_valid & tlb_used & ~s0_found;
    assign fs_tlb_exc[`EARRAY_PIF ] = fs_valid & tlb_used & ~fs_tlb_exc[`EARRAY_TLBR_FETCH] & ~s0_v;
    assign fs_tlb_exc[`EARRAY_PPI_FETCH ] = fs_valid & tlb_used & ~fs_tlb_exc[`EARRAY_PIF ] & (crmd_plv_CSRoutput > s0_plv);
endmodule
