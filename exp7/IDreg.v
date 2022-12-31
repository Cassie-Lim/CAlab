module IDreg(
    input  wire        clk,
    input  wire        resetn,
    // if and id state interface
    output wire        id_allowin,
    output wire        br_taken,
    output wire [31:0] br_target,
    input  wire        if_to_id_valid,
    input  wire [31:0] if_inst,
    input  wire [31:0] if_pc,
    // id and exe state interface
    input  wire        exe_allowin,
    output wire [5 :0] id_rf_zip, // {id_rf_we, id_rf_waddr}
    output wire        id_to_exe_valid,
    output reg  [31:0] id_pc,    
    output wire [75:0] id_alu_data_zip, // {alu_op, alu_src1, alu_src2}
    output wire        id_res_from_mem, // res_from_mem
    output wire        id_mem_we,
    output wire [31:0] id_rkd_value,
    // id and wb state interface
    input  wire [37:0] wb_rf_zip  // {wb_rf_we, wb_rf_waddr, wb_rf_wdata}
);

    wire        id_ready_go;
    reg         id_valid;
    reg  [31:0] inst;

    wire [11:0] alu_op;
    wire [31:0] alu_src1   ;
    wire [31:0] alu_src2   ;
    wire        src1_is_pc;
    wire        src2_is_imm;
    wire        res_from_mem;
    wire        dst_is_r1;
    wire        gr_we;
    wire        mem_we;
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

    wire        conflict_r1;
    wire        conflict_r2;
    wire [ 4:0] rf_raddr1;
    wire [31:0] rf_rdata1;
    wire [ 4:0] rf_raddr2;
    wire [31:0] rf_rdata2;
    // reg         wb_rf_we   ;
    // reg  [ 4:0] wb_rf_waddr;
    // reg  [31:0] wb_rf_wdata;
    wire        wb_rf_we   ;
    wire [ 4:0] wb_rf_waddr;
    wire [31:0] wb_rf_wdata;
    wire        id_rf_we   ;
    wire [ 4:0] id_rf_waddr;


        
//------------------------------state control signal---------------------------------------
    assign id_ready_go      = 1'b1;
    assign id_allowin       = ~id_valid | id_ready_go & exe_allowin;     
    assign id_to_exe_valid  = id_valid & id_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            id_valid <= 1'b0;
        else
            // 有效条件：if向id输入有效、非转移指令、id允许接收数据
            id_valid <= if_to_id_valid & ~br_taken & id_allowin; 
    end

//------------------------------if and id state interface---------------------------------------
    
    always @(posedge clk) begin
        if(if_to_id_valid & id_allowin) begin
            id_pc <= if_pc;
        end
    end
    always @(posedge clk) begin
        if(if_to_id_valid & id_allowin) begin
            inst  <= if_inst;
        end
    end

    assign rj_eq_rd = (rj_value == rkd_value);
    assign br_taken = (inst_beq  &&  rj_eq_rd
                    || inst_bne  && !rj_eq_rd
                    || inst_jirl
                    || inst_bl
                    || inst_b
                    ) && id_valid;
    assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (id_pc + br_offs) :
                                                    /*inst_jirl*/ (rj_value + jirl_offs);
//------------------------------decode instruction---------------------------------------
    
    assign op_31_26  = inst[31:26];
    assign op_25_22  = inst[25:22];
    assign op_21_20  = inst[21:20];
    assign op_19_15  = inst[19:15];

    assign rd   = inst[ 4: 0];
    assign rj   = inst[ 9: 5];
    assign rk   = inst[14:10];

    assign i12  = inst[21:10];
    assign i20  = inst[24: 5];
    assign i16  = inst[25:10];
    assign i26  = {inst[ 9: 0], inst[25:10]};

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
    assign inst_lu12i_w= op_31_26_d[6'h05] & ~inst[25];

    assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                        | inst_jirl | inst_bl;
    assign alu_op[ 1] = inst_sub_w;
    assign alu_op[ 2] = inst_slt;
    assign alu_op[ 3] = inst_sltu;
    assign alu_op[ 4] = inst_and;
    assign alu_op[ 5] = inst_nor;
    assign alu_op[ 6] = inst_or;
    assign alu_op[ 7] = inst_xor;
    assign alu_op[ 8] = inst_slli_w;
    assign alu_op[ 9] = inst_srli_w;
    assign alu_op[10] = inst_srai_w;
    assign alu_op[11] = inst_lu12i_w;

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

    assign src1_is_pc    = inst_jirl | inst_bl;

    assign src2_is_imm   = inst_slli_w |
                        inst_srli_w |
                        inst_srai_w |
                        inst_addi_w |
                        inst_ld_w   |
                        inst_st_w   |
                        inst_lu12i_w|
                        inst_jirl   |
                        inst_bl     ;

    assign alu_src1 = src1_is_pc  ? id_pc[31:0] : rj_value;
    assign alu_src2 = src2_is_imm ? imm : rkd_value;

    assign res_from_mem  = inst_ld_w;
    assign dst_is_r1     = inst_bl;
    assign gr_we         = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b; 
    assign mem_we        = inst_st_w ;   
    assign dest          = dst_is_r1 ? 5'd1 : rd;

//------------------------------regfile control---------------------------------------
    assign rf_raddr1 = rj;
    assign rf_raddr2 = src_reg_is_rd ? rd :rk;
    assign id_rf_we    = gr_we ; 
    assign id_rf_waddr = dest; 
    assign id_rf_zip   = {id_rf_we, id_rf_waddr};
    //写回阶段传回数据处理
    // always @(posedge clk) begin 
    //     {wb_rf_we, wb_rf_waddr, wb_rf_wdata} <= wb_rf_zip;
    // end
    assign {wb_rf_we, wb_rf_waddr, wb_rf_wdata} = wb_rf_zip;
    regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (wb_rf_we    ),
    .waddr  (wb_rf_waddr ),
    .wdata  (wb_rf_wdata )
    );
    assign conflict_r1 = (|rf_raddr1) & (rf_raddr1 == wb_rf_waddr);
    assign conflict_r2 = (|rf_raddr2) & (rf_raddr2 == wb_rf_waddr);
    // assign rj_value  = conflict_r1? wb_rf_wdata: rf_rdata1;
    // assign rkd_value = conflict_r2? wb_rf_wdata: rf_rdata2;
    assign rj_value  = rf_rdata1;
    assign rkd_value = rf_rdata2;

    assign id_alu_data_zip = {alu_op, alu_src1, alu_src2};
    assign id_mem_we = mem_we;
    assign id_rkd_value = rkd_value;
    assign id_res_from_mem = res_from_mem;

endmodule