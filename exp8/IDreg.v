`include "macro.h"
module IDreg(
    input  wire          clk,
    input  wire          resetn,
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
    input  wire [37:0] ms_rf_zip, // {ms_rf_we, ms_rf_waddr, ms_rf_wdata}
    input  wire [38:0] es_rf_zip  // {es_res_from_mem, es_rf_we, es_rf_waddr, es_alu_result}
);

    wire        ds_ready_go;
    reg         ds_valid;
    reg  [31:0] ds_inst;
    wire        ds_stall;

    wire [11:0] ds_alu_op;
    wire [31:0] ds_alu_src1   ;
    wire [31:0] ds_alu_src2   ;
    wire        ds_src1_is_pc;
    wire        ds_src2_is_imm;
    wire        ds_res_from_mem;
    reg  [31:0] ds_pc;
    wire [31:0] ds_rkd_value;
    wire        ds_mem_we;

    wire        dst_is_r1;
    wire        gr_we;
    wire        src_reg_is_rd;
    wire        rj_eq_rd;
    wire [4: 0] dest;
    wire [31:0] rj_value;
    wire [31:0] rkd_value;
    wire [31:0] imm;
    wire [31:0] br_offs;
    wire [31:0] jirl_offs;

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

    wire        inst_add_w;
    wire        inst_sub_w;
    wire        inst_slt;
    wire        inst_sltu;
    wire        inst_nor;
    wire        inst_and;
    wire        inst_or;
    wire        inst_xor;
    wire        inst_slli_w;
    wire        inst_srli_w;
    wire        inst_srai_w;
    wire        inst_addi_w;
    wire        inst_ld_w;
    wire        inst_st_w;
    wire        inst_jirl;
    wire        inst_b;
    wire        inst_bl;
    wire        inst_beq;
    wire        inst_bne;
    wire        inst_lu12i_w;

    wire        need_ui5;
    wire        need_si12;
    wire        need_si16;
    wire        need_si20;
    wire        need_si26;
    wire        src2_is_4;

    wire        br_taken;
    wire [31:0] br_target;

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
    wire [ 4:0] ms_rf_waddr;
    wire [31:0] ms_rf_wdata;
    wire        es_rf_we   ;
    wire [ 4:0] es_rf_waddr;
    wire [31:0] es_rf_wdata;
    wire        es_res_from_mem;

    wire        ds_rf_we   ;
    wire [ 4:0] ds_rf_waddr;


        
//------------------------------state control signal---------------------------------------
    assign ds_ready_go      = ~ds_stall;
    assign ds_allowin       = ~ds_valid | ds_ready_go & es_allowin; 
    assign ds_stall         = es_res_from_mem & (conflict_r1_exe & need_r1|conflict_r2_exe & need_r2);    
    assign ds2es_valid      = ds_valid & ds_ready_go;
    always @(posedge clk) begin
        if(~resetn)
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

    assign rj_eq_rd = (rj_value == rkd_value);
    assign br_taken = (inst_beq  &&  rj_eq_rd
                    || inst_bne  && !rj_eq_rd
                    || inst_jirl
                    || inst_bl
                    || inst_b
                    ) && ds_valid;
    assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (ds_pc + br_offs) :
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
    assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
    assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
    assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
    assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
    assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
    assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
    assign inst_jirl   = op_31_26_d[6'h13];
    assign inst_b      = op_31_26_d[6'h14];
    assign inst_bl     = op_31_26_d[6'h15];
    assign inst_beq    = op_31_26_d[6'h16];
    assign inst_bne    = op_31_26_d[6'h17];
    assign inst_lu12i_w= op_31_26_d[6'h05] & ~ds_inst[25];

    assign ds_alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                        | inst_jirl | inst_bl;
    assign ds_alu_op[ 1] = inst_sub_w;
    assign ds_alu_op[ 2] = inst_slt;
    assign ds_alu_op[ 3] = inst_sltu;
    assign ds_alu_op[ 4] = inst_and;
    assign ds_alu_op[ 5] = inst_nor;
    assign ds_alu_op[ 6] = inst_or;
    assign ds_alu_op[ 7] = inst_xor;
    assign ds_alu_op[ 8] = inst_slli_w;
    assign ds_alu_op[ 9] = inst_srli_w;
    assign ds_alu_op[10] = inst_srai_w;
    assign ds_alu_op[11] = inst_lu12i_w;

    assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
    assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w;
    assign need_si16  =  inst_jirl | inst_beq | inst_bne;
    assign need_si20  =  inst_lu12i_w;
    assign need_si26  =  inst_b | inst_bl;
    assign src2_is_4  =  inst_jirl | inst_bl;

    assign imm = src2_is_4 ? 32'h4                      :
                need_si20 ? {i20[19:0], 12'b0}         :
    /*need_ui5 || need_si12*/{{20{i12[11]}}, i12[11:0]} ;

    assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                                {{14{i16[15]}}, i16[15:0], 2'b0} ;

    assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w;

    assign ds_src1_is_pc    = inst_jirl | inst_bl;

    assign ds_src2_is_imm   = inst_slli_w |
                        inst_srli_w |
                        inst_srai_w |
                        inst_addi_w |
                        inst_ld_w   |
                        inst_st_w   |
                        inst_lu12i_w|
                        inst_jirl   |
                        inst_bl     ;

    assign ds_alu_src1 = ds_src1_is_pc  ? ds_pc[31:0] : rj_value;
    assign ds_alu_src2 = ds_src2_is_imm ? imm : rkd_value;

    assign ds_rkd_value = rkd_value;
    assign ds_res_from_mem  = inst_ld_w;
    assign dst_is_r1     = inst_bl;
    assign gr_we         = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b & ds_valid; 
    assign ds_mem_we        = inst_st_w & ds_valid;   
    assign dest          = dst_is_r1 ? 5'd1 : rd;

//------------------------------regfile control---------------------------------------
    assign rf_raddr1 = rj;
    assign rf_raddr2 = src_reg_is_rd ? rd :rk;
    assign ds_rf_we    = gr_we ; 
    assign ds_rf_waddr = dest; 
    //写回、访存、执行阶段传回数据处理
    assign {ws_rf_we, ws_rf_waddr, ws_rf_wdata} = ws_rf_zip;
    assign {ms_rf_we, ms_rf_waddr, ms_rf_wdata} = ms_rf_zip;
    assign {es_res_from_mem, es_rf_we, es_rf_waddr, es_rf_wdata} = es_rf_zip;
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

//------------------------------ds to es interface--------------------------------------
    assign ds2es_bus = {ds_alu_op,          //12 bit
                        ds_res_from_mem,    //1  bit
                        ds_alu_src1,        //32 bit
                        ds_alu_src2,        //32 bit
                        ds_mem_we,          //1  bit
                        ds_rf_we,           //1  bit
                        ds_rf_waddr,        //5  bit
                        ds_rkd_value,       //32 bit
                        ds_pc               //32 bit
                        };
endmodule