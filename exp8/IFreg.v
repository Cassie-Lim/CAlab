`include "macro.h"
module IFreg(
    input  wire   clk,
    input  wire   resetn,
    // inst sram interface
    output wire         inst_sram_en,
    output wire [ 3:0]  inst_sram_we,
    output wire [31:0]  inst_sram_addr,
    output wire [31:0]  inst_sram_wdata,
    input  wire [31:0]  inst_sram_rdata,
    // ds to fs interface
    input  wire         ds_allowin,
    input  wire [32:0]  br_zip,
    // fs to ds interface
    output wire         fs2ds_valid,
    output wire [`FS2DS_LEN -1:0]  fs2ds_bus
);

    reg         fs_valid;
    wire        fs_ready_go;
    wire        fs_allowin;
    wire        to_fs_valid;

    wire [31:0] seq_pc;
    wire [31:0] nextpc;

    wire         br_taken;
    wire [ 31:0] br_target;

    assign {br_taken, br_target} = br_zip;

    wire [31:0] fs_inst;
    reg  [31:0] fs_pc;
    assign fs2ds_bus = {fs_inst, fs_pc};


    assign seq_pc       = fs_pc + 3'h4;
    assign nextpc       = br_taken ? br_target : seq_pc;

    //------------------------------state control signal---------------------------------------
    assign to_fs_valid      = resetn;
    assign fs_ready_go      = 1'b1;
    assign fs_allowin       = ~fs_valid | fs_ready_go & ds_allowin;     
    assign fs2ds_valid      = fs_valid & fs_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            fs_valid <= 1'b0;
        else if(fs_allowin)
            fs_valid <= to_fs_valid; // 在reset撤销的下一个时钟上升沿才开始取指
    end
//------------------------------inst sram interface---------------------------------------
    
    assign inst_sram_en     = fs_allowin & resetn;
    assign inst_sram_we     = 4'b0;
    assign inst_sram_addr   = nextpc;
    assign inst_sram_wdata  = 32'b0;

//------------------------------pc relavant signals---------------------------------------
    
    assign seq_pc           = fs_pc + 3'h4;  
    assign nextpc           = br_taken ? br_target : seq_pc;

//------------------------------fs and ds state interface---------------------------------------
    //fs_pc存前一条指令的pc值
    always @(posedge clk) begin
        if(~resetn)
            fs_pc <= 32'h1BFF_FFFC;
        else if(fs_allowin)
            fs_pc <= nextpc;
    end

    assign fs_inst    = inst_sram_rdata;
    assign fs2ds_bus  = {fs_inst, fs_pc}; // 32+32
endmodule
