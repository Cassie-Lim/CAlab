`include "macro.h"
module IDreg(
    input  wire        clk,
    input  wire        resetn,
    // fs and ds interface
    input  wire                   fs2ds_valid,
    output wire                   ds_allowin,
    output wire [32:0]            br_zip,
    input  wire [`FS2DS_LEN -1:0] fs2ds_bus,
    // ds and es interface
    input  wire                   es_allowin,
    output wire                   ds2es_valid,
    output wire [`DS2ES_LEN -1:0] ds2es_bus,
    // signals to determine whether confict occurs
    input  wire [37:0] ws_rf_zip, // {ws_rf_we, ws_rf_waddr, ws_rf_wdata}
    input  wire [38:0] ms_rf_zip, // {ms_csr_re, ms_rf_we, ms_rf_waddr, ms_rf_wdata}
    input  wire [39:0] es_rf_zip, // {es_csr_re, es_res_from_mem, es_rf_we, es_rf_waddr, es_alu_result}
    // exception interface
    input  wire        wb_ex
);

    wire [7 :0] ds_mem_inst_zip;
    wire        ds_ready_go;
    reg         ds_valid;
    reg  [31:0] ds_inst;
    wire        ds_stall;

    wire [18:0] ds_alu_op;
    wire [31:0] ds_alu_src1   ;
    wire [31:0] ds_alu_src2   ;
    wire        ds_src1_is_pc;
    wire        ds_src2_is_imm;
    wire        ds_res_from_mem;
    reg  [31:0] ds_pc;
    wire [31:0] ds_rkd_value;

    wire        dst_is_r1;
    wire        gr_we;
    wire        ds_src_reg_is_rd;
    wire        rj_eq_rd;
    wire        rj_ge_rd_u;
    wire        rj_ge_rd;
    wire [4: 0] dest;
    wire [31:0] rj_value;
    wire [31:0] rkd_value;
    wire [31:0] imm;
    wire [31:0] br_offs;
    wire [31:0] jirl_offs;
    wire        br_taken;
    wire [31:0] br_target;

    wire [ 5:0] op_31_26;
    wire [ 3:0] op_25_22;
    wire [ 1:0] op_21_20;
    wire [ 4:0] op_19_15;
    wire [ 4:0] rd;
    wire [ 4:0] rj;
    wire [ 4:0] rk;
    wire [11:0] i12;
    wire [19:0] i20;
    wire [15:0] i16;
    wire [25:0] i26;

    wire [63:0] op_31_26_d;
    wire [15:0] op_25_22_d;
    wire [ 3:0] op_21_20_d;
    wire [31:0] op_19_15_d;
//简单算术逻辑运算
    wire        inst_add_w;
    wire        inst_sub_w;
    wire        inst_slti;
    wire        inst_slt;
    wire        inst_sltui;
    wire        inst_sltu;
    wire        inst_nor;
    wire        inst_and;
    wire        inst_andi;
    wire        inst_or;
    wire        inst_ori;
    wire        inst_xor;
    wire        inst_xori;
    wire        inst_sll_w;
    wire        inst_slli_w;
    wire        inst_srl_w;
    wire        inst_srli_w;
    wire        inst_sra_w;
    wire        inst_srai_w;
    wire        inst_addi_w;
//访存指令
    wire        inst_ld_b;
    wire        inst_ld_h;
    wire        inst_ld_w;
    wire        inst_ld_bu;
    wire        inst_ld_hu;
    wire        inst_st_b;
    wire        inst_st_h;
    wire        inst_st_w;
//转移指令
    wire        inst_jirl;
    wire        inst_b;
    wire        inst_bl;
    wire        inst_blt;
    wire        inst_bge;
    wire        inst_bltu;
    wire        inst_bgeu;
    wire        inst_beq;
    wire        inst_bne;

    wire        inst_lu12i_w;
    wire        inst_pcaddul2i;
//复杂算术逻辑运算
    wire        inst_mul_w;
    wire        inst_mulh_w;
    wire        inst_mulh_wu;
    wire        inst_div_w;
    wire        inst_div_wu;
    wire        inst_mod_w;
    wire        inst_mod_wu;
//系统调用异常支持指令
    wire        inst_csrrd;
    wire        inst_csrwr;
    wire        inst_csrxchg;
    wire        inst_ertn;
    wire        inst_syscall;

    wire        need_ui5;
    wire        need_ui12;
    wire        need_si12;
    wire        need_si16;
    wire        need_si20;
    wire        need_si26;
    wire        src2_is_4;



    // wire        wb_ex;
    // wire [31:0] wb_pc;
    // wire [ 5:0] wb_ecode;
    // wire [ 8:0] wb_esubcode;
    // wire [31:0] ex_entry;
    // wire [31:0] ertn_entry;
    // wire        ertn_flush;

    wire [ 4:0] rf_raddr1;
    wire [31:0] rf_rdata1;
    wire [ 4:0] rf_raddr2;
    wire [31:0] rf_rdata2;

    wire        conflict_r1_wb;
    wire        conflict_r2_wb;
    wire        conflict_r1_mem;
    wire        conflict_r2_mem;
    wire        conflict_r1_exe;
    wire        conflict_r2_exe;
    wire        need_r1;
    wire        need_r2;

    wire        ws_rf_we   ;
    wire [ 4:0] ws_rf_waddr;
    wire [31:0] ws_rf_wdata;
    wire        ms_rf_we   ;
    wire        ms_csr_re  ;
    wire [ 4:0] ms_rf_waddr;
    wire [31:0] ms_rf_wdata;
    wire        es_rf_we   ;
    wire        es_csr_re  ;
    wire [ 4:0] es_rf_waddr;
    wire [31:0] es_rf_wdata;
    wire        es_res_from_mem;

    wire        ds_rf_we   ;
    wire [ 4:0] ds_rf_waddr;

    wire        ds_csr_re;
    wire [13:0] ds_csr_num;
    wire        ds_csr_we;
    wire [31:0] ds_csr_wmask;
    wire [31:0] ds_csr_wvalue;
    wire [ 6:0] ds_rf_zip;
    wire [81:0] ds_except_zip;  // {ds_csr_num, ds_csr_wmask, ds_csr_wvalue, inst_syscall, inst_ertn, ds_csr_we}
//------------------------------state control signal---------------------------------------
    // always @(posedge clk) begin
    //     if(~resetn | br_taken | inst_syscall | inst_ertn)
    //         ds_valid <= 1'b0;
    //     else if(ds_allowin)
    //         ds_valid <= if_to_ds_valid; 
    // end
    assign ds_ready_go      = ~ds_stall;
    assign ds_allowin       = ~ds_valid | ds_ready_go & es_allowin; 
    assign ds_stall         = (es_res_from_mem|es_csr_re) & (conflict_r1_exe & need_r1|conflict_r2_exe & need_r2)|
                                ms_csr_re & (conflict_r1_mem | conflict_r2_mem);    
    assign ds2es_valid      = ds_valid & ds_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            ds_valid <= 1'b0;
        else if(wb_ex)
            ds_valid <= 1'b0;
        else if(br_taken)
            ds_valid <= 1'b0;
        else if(ds_allowin)
            ds_valid <= fs2ds_valid;
    end

//------------------------------if and id state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn)
            {ds_inst, ds_pc} <= 64'b0;
        if(fs2ds_valid & ds_allowin) begin
            {ds_inst, ds_pc} <= fs2ds_bus;
        end
    end

    assign rj_eq_rd = rj_value == rkd_value;
    assign rj_ge_rd = ($signed(rj_value) > $signed(rkd_value));
    assign rj_ge_rd_u = ($unsigned(rj_value) > $unsigned(rkd_value));
    assign br_taken = (inst_beq  &  rj_eq_rd
                    | inst_bne   & !rj_eq_rd
                    | inst_bge   &  rj_ge_rd
                    | inst_blt   & !rj_ge_rd
                    | inst_bgeu  &  rj_ge_rd_u
                    | inst_bltu  & !rj_ge_rd_u
                    | inst_jirl
                    | inst_bl
                    | inst_b
                    ) & ds_valid;
    assign br_target = (inst_beq || inst_bne || inst_bl || inst_b || 
                        inst_bge || inst_bgeu|| inst_blt|| inst_bltu) ? (ds_pc + br_offs) :
                                                    /*inst_jirl*/ (rj_value + jirl_offs);
    assign br_zip = {br_taken, br_target}; 
//------------------------------decode instruction---------------------------------------
    
    assign op_31_26  = ds_inst[31:26];
    assign op_25_22  = ds_inst[25:22];
    assign op_21_20  = ds_inst[21:20];
    assign op_19_15  = ds_inst[19:15];

    assign rd   = ds_inst[ 4: 0];
    assign rj   = ds_inst[ 9: 5];
    assign rk   = ds_inst[14:10];

    assign i12  = ds_inst[21:10];
    assign i20  = ds_inst[24: 5];
    assign i16  = ds_inst[25:10];
    assign i26  = {ds_inst[ 9: 0], ds_inst[25:10]};


    decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
    decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
    decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
    decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

    assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
    assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
    assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
    assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
    assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
    assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
    assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
    assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
    
    assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
    assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
    assign inst_sra_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
    
    assign inst_mul_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
    assign inst_mulh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
    assign inst_mulh_wu= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
    assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
    assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
    assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
    assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];

    assign inst_syscall = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h16];

    assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
    assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
    assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
    assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
    assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
    assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
    assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
    assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
    assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];

    assign inst_ld_b    = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
    assign inst_ld_h    = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
    assign inst_ld_w    = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
    assign inst_st_b    = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
    assign inst_st_h    = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
    assign inst_st_w    = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
    assign inst_ld_bu   = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
    assign inst_ld_hu   = op_31_26_d[6'h0a] & op_25_22_d[4'h9];

    assign inst_jirl   = op_31_26_d[6'h13];
    assign inst_b      = op_31_26_d[6'h14];
    assign inst_bl     = op_31_26_d[6'h15];
    assign inst_beq    = op_31_26_d[6'h16];
    assign inst_bne    = op_31_26_d[6'h17];
    assign inst_blt     = op_31_26_d[6'h18];
    assign inst_bge     = op_31_26_d[6'h19];
    assign inst_bltu    = op_31_26_d[6'h1a];
    assign inst_bgeu    = op_31_26_d[6'h1b];
    assign inst_lu12i_w   = op_31_26_d[6'h05] & ~ds_inst[25];
    assign inst_pcaddul2i = op_31_26_d[6'h07] & ~ds_inst[25];

    assign inst_csrrd   = op_31_26_d[6'h01] & (op_25_22[3:2] == 2'b0) & (rj == 5'h00);
    assign inst_csrwr   = op_31_26_d[6'h01] & (op_25_22[3:2] == 2'b0) & (rj == 5'h01);
    assign inst_csrxchg = op_31_26_d[6'h01] & (op_25_22[3:2] == 2'b0) & ~inst_csrrd & ~inst_csrwr;

    assign inst_ertn    = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] 
                        & (rk == 5'h0e) & (~|rj) & (~|rd);

    assign ds_alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_ld_hu |
                        inst_ld_h  | inst_ld_bu  | inst_ld_b | inst_st_b  | 
                        inst_st_w  | inst_st_h   | inst_jirl | inst_bl    | 
                        inst_pcaddul2i;
    assign ds_alu_op[ 1] = inst_sub_w | inst_bne | inst_beq;
    assign ds_alu_op[ 2] = inst_slt | inst_slti | inst_blt | inst_bge;
    assign ds_alu_op[ 3] = inst_sltu | inst_sltui | inst_bltu | inst_bgeu;
    assign ds_alu_op[ 4] = inst_and | inst_andi;
    assign ds_alu_op[ 5] = inst_nor;
    assign ds_alu_op[ 6] = inst_or | inst_ori;
    assign ds_alu_op[ 7] = inst_xor | inst_xori;
    assign ds_alu_op[ 8] = inst_slli_w | inst_sll_w;
    assign ds_alu_op[ 9] = inst_srli_w | inst_srl_w;
    assign ds_alu_op[10] = inst_srai_w | inst_sra_w;
    assign ds_alu_op[11] = inst_lu12i_w;
    assign ds_alu_op[12] = inst_mul_w ;
    assign ds_alu_op[13] = inst_mulh_w;
    assign ds_alu_op[14] = inst_mulh_wu;
    assign ds_alu_op[15] = inst_div_w;
    assign ds_alu_op[16] = inst_div_wu;
    assign ds_alu_op[17] = inst_mod_w;
    assign ds_alu_op[18] = inst_mod_wu;


    assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
    assign need_ui12  =  inst_andi   | inst_ori | inst_xori ;
    assign need_si12  =  inst_slti    | inst_sltui  | inst_addi_w |
                         inst_ld_w    | inst_ld_b   | inst_ld_h   | 
                         inst_ld_bu   | inst_ld_hu  |inst_st_w    | 
                         inst_st_b    | inst_st_h;
    // assign need_si16  =  inst_jirl | inst_beq | inst_bne;
    assign need_si20  =  inst_lu12i_w | inst_pcaddul2i;
    assign need_si26  =  inst_b | inst_bl;
    assign src2_is_4  =  inst_jirl | inst_bl;

    assign imm = src2_is_4 ? 32'h4                      :
                need_si20 ? {i20[19:0], 12'b0}         :
                (need_ui5 || need_si12) ? {{20{i12[11]}}, i12[11:0]} :
                {20'b0, i12[11:0]};

    assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                                {{14{i16[15]}}, i16[15:0], 2'b0} ;

    assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    assign ds_src_reg_is_rd = inst_beq | inst_bne  | inst_blt | inst_bltu | 
                           inst_bge | inst_bgeu | inst_st_w| inst_st_h |
                           inst_st_b| inst_csrwr| inst_csrxchg;

    assign ds_src1_is_pc    = inst_jirl | inst_bl | inst_pcaddul2i;

    assign ds_src2_is_imm   = inst_slli_w |
                        inst_srli_w |
                        inst_srai_w |
                        inst_addi_w |
                        inst_ld_w   |
                        inst_ld_b   |
                        inst_ld_bu  |
                        inst_ld_h   |
                        inst_ld_hu  |
                        inst_st_w   |
                        inst_st_b   |
                        inst_st_h   |
                        inst_lu12i_w|
                        inst_jirl   |
                        inst_bl     |
                        inst_pcaddul2i|
                        inst_andi   |
                        inst_ori    |
                        inst_xori   |
                        inst_slti   |
                        inst_sltui;

    assign ds_alu_src1 = ds_src1_is_pc  ? ds_pc[31:0] : rj_value;
    assign ds_alu_src2 = ds_src2_is_imm ? imm : rkd_value;

    assign ds_res_from_mem  = inst_ld_w | inst_ld_h | inst_ld_hu | inst_ld_b | inst_ld_bu;
    assign ds_rkd_value = rkd_value;
    assign dst_is_r1     = inst_bl;
    assign gr_we         = ~inst_st_w & ~inst_st_h & ~inst_st_b & ~inst_beq  & 
                           ~inst_bne  & ~inst_b    & ~inst_bge  & ~inst_bgeu & 
                           ~inst_blt  & ~inst_bltu & ~inst_syscall; 
    assign dest          = dst_is_r1 ? 5'd1 : rd;

//------------------------------regfile control---------------------------------------
    assign rf_raddr1 = rj;
    assign rf_raddr2 = ds_src_reg_is_rd ? rd :rk;
    assign ds_rf_we    = gr_we & ds_valid; 
    assign ds_rf_waddr = dest; 
    assign ds_rf_zip   = {ds_csr_re, ds_rf_we, ds_rf_waddr};
    //写回、访存、执行阶段传回数据处理
    assign {ws_rf_we, ws_rf_waddr, ws_rf_wdata} = ws_rf_zip;
    assign {ms_csr_re, ms_rf_we, ms_rf_waddr, ms_rf_wdata} = ms_rf_zip;
    assign {es_csr_re, es_res_from_mem, es_rf_we, es_rf_waddr, es_rf_wdata} = es_rf_zip;
    regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (ws_rf_we    ),
    .waddr  (ws_rf_waddr ),
    .wdata  (ws_rf_wdata )
    );
    // 冲突：写使能 + 写地址不为0号寄存器 + 写地址与当前读寄存器地址相同
    assign conflict_r1_wb = (|rf_raddr1) & (rf_raddr1 == ws_rf_waddr) & ws_rf_we;
    assign conflict_r2_wb = (|rf_raddr2) & (rf_raddr2 == ws_rf_waddr) & ws_rf_we;
    assign conflict_r1_mem = (|rf_raddr1) & (rf_raddr1 == ms_rf_waddr) & ms_rf_we;
    assign conflict_r2_mem = (|rf_raddr2) & (rf_raddr2 == ms_rf_waddr) & ms_rf_we;
    assign conflict_r1_exe = (|rf_raddr1) & (rf_raddr1 == es_rf_waddr) & es_rf_we;
    assign conflict_r2_exe = (|rf_raddr2) & (rf_raddr2 == es_rf_waddr) & es_rf_we;
    assign need_r1         = ~ds_src1_is_pc & (|ds_alu_op);
    assign need_r2         = ~ds_src2_is_imm & (|ds_alu_op);
    
    // 数据冲突时处理有先后顺序，以最后一次更新为准
    assign rj_value  =  conflict_r1_exe ? es_rf_wdata:
                        conflict_r1_mem ? ms_rf_wdata:
                        conflict_r1_wb  ? ws_rf_wdata : rf_rdata1; 
    assign rkd_value =  conflict_r2_exe ? es_rf_wdata:
                        conflict_r2_mem ? ms_rf_wdata:
                        conflict_r2_wb  ? ws_rf_wdata : rf_rdata2; 
    assign ds_mem_inst_zip = {inst_st_b, inst_st_h, inst_st_w, inst_ld_b, 
                          inst_ld_bu,inst_ld_h, inst_ld_hu, inst_ld_w};
    

    assign ds_csr_re    = inst_csrrd | inst_csrwr | inst_csrxchg;
    assign ds_csr_we    = inst_csrwr | inst_csrxchg;
    assign ds_csr_wmask    = {32{inst_csrxchg}} & rj_value | {32{inst_csrwr}};
    assign ds_csr_wvalue   = rkd_value;
    assign ds_csr_num   = ds_inst[23:10];

    assign ds_except_zip  = {ds_csr_num, ds_csr_wmask, ds_csr_wvalue, inst_syscall, inst_ertn, ds_csr_we};

//------------------------------ds to es interface--------------------------------------
    assign ds2es_bus = {ds_alu_op,          //19 bit
                        ds_res_from_mem,    //1  bit
                        ds_alu_src1,        //32 bit
                        ds_alu_src2,        //32 bit
                        ds_rf_zip,          //7  bit
                        ds_rkd_value,       //32 bit
                        ds_pc,              //32 bit
                        ds_mem_inst_zip,    //8  bit
                        ds_except_zip       //82 bit
                        };

endmodule