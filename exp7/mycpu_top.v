module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);
    wire        id_allowin;
    wire        exe_allowin;
    wire        mem_allowin;
    wire        wb_allowin;

    wire        if_to_id_valid;
    wire        id_to_exe_valid;
    wire        exe_to_mem_valid;
    wire        mem_to_wb_valid;

    wire [31:0] if_pc;
    wire [31:0] id_pc;
    wire [31:0] exe_pc;
    wire [31:0] mem_pc;

    wire [5 :0] id_rf_zip;
    wire [5 :0] exe_rf_zip;
    wire [37:0] mem_rf_zip;
    wire [37:0] wb_rf_zip;

    wire        id_res_from_mem;
    wire        exe_res_from_mem;

    wire        id_mem_we;
    wire        exe_mem_we;
    
    wire [31:0] id_rkd_value;
    wire [31:0] exe_rkd_value;


    wire        br_taken;
    wire [31:0] br_target;
    wire [31:0] if_inst;
    wire [75:0] id_alu_data_zip;
    wire [31:0] exe_alu_result;

    IFreg my_ifReg(
        .clk(clk),
        .resetn(resetn),

        .inst_sram_en(inst_sram_en),
        .inst_sram_we(inst_sram_we),
        .inst_sram_addr(inst_sram_addr),
        .inst_sram_wdata(inst_sram_wdata),
        .inst_sram_rdata(inst_sram_rdata),
        
        .id_allowin(id_allowin),
        .br_taken(br_taken),
        .br_target(br_target),
        .if_to_id_valid(if_to_id_valid),
        .if_inst(if_inst),
        .if_pc(if_pc)
    );

    IDreg my_idReg(
        .clk(clk),
        .resetn(resetn),

        .id_allowin(id_allowin),
        .br_taken(br_taken),
        .br_target(br_target),
        .if_to_id_valid(if_to_id_valid),
        .if_inst(if_inst),
        .if_pc(if_pc),

        .exe_allowin(exe_allowin),
        .id_rf_zip(id_rf_zip),
        .id_to_exe_valid(id_to_exe_valid),
        .id_pc(id_pc),
        .id_alu_data_zip(id_alu_data_zip),
        .id_res_from_mem(id_res_from_mem),
        .id_mem_we(id_mem_we),
        .id_rkd_value(id_rkd_value),

        .wb_rf_zip(wb_rf_zip)
    );

    EXEreg my_exeReg(
        .clk(clk),
        .resetn(resetn),
        
        .exe_allowin(exe_allowin),
        .id_rf_zip(id_rf_zip),
        .id_to_exe_valid(id_to_exe_valid),
        .id_pc(id_pc),
        .id_alu_data_zip(id_alu_data_zip),
        .id_res_from_mem(id_res_from_mem),
        .id_mem_we(id_mem_we),
        .id_rkd_value(id_rkd_value),

        .mem_allowin(mem_allowin),
        .exe_rf_zip(exe_rf_zip),
        .exe_to_mem_valid(exe_to_mem_valid),
        .exe_pc(exe_pc),
        .exe_alu_result(exe_alu_result),
        .exe_res_from_mem(exe_res_from_mem),
        .exe_mem_we(exe_mem_we),
        .exe_rkd_value(exe_rkd_value)
    );

    MEMreg my_memReg(
        .clk(clk),
        .resetn(resetn),

        .mem_allowin(mem_allowin),
        .exe_rf_zip(exe_rf_zip),
        .exe_to_mem_valid(exe_to_mem_valid),
        .exe_pc(exe_pc),
        .exe_alu_result(exe_alu_result),
        .exe_res_from_mem(exe_res_from_mem),
        .exe_mem_we(exe_mem_we),
        .exe_rkd_value(exe_rkd_value),

        .wb_allowin(wb_allowin),
        .mem_rf_zip(mem_rf_zip),
        .mem_to_wb_valid(mem_to_wb_valid),
        .mem_pc(mem_pc),

        .data_sram_en(data_sram_en),
        .data_sram_we(data_sram_we),
        .data_sram_addr(data_sram_addr),
        .data_sram_wdata(data_sram_wdata),
        .data_sram_rdata(data_sram_rdata)
    ) ;

    WBreg my_wbReg(
        .clk(clk),
        .resetn(resetn),

        .wb_allowin(wb_allowin),
        .mem_rf_zip(mem_rf_zip),
        .mem_to_wb_valid(mem_to_wb_valid),
        .mem_pc(mem_pc),

        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata),

        .wb_rf_zip(wb_rf_zip)
    );
endmodule
