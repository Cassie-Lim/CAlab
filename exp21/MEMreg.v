`include "macro.h"
module MEMreg(
    input  wire        clk,
    input  wire        resetn,
    // exe and mem state interface
    output wire        ms_allowin,
    input  wire [`ES2MS_LEN -1:0] es2ms_bus,
    input  wire [39:0] es_rf_zip, // {es_csr_re, es_res_from_mem, es_rf_we, es_rf_waddr, es_rf_wdata}
    output wire [`TLB_CONFLICT_BUS_LEN-1:0] ms_tlb_blk_zip,
    input  wire        es2ms_valid, // {op_ld_b, op_ld_bu,op_ld_h, op_ld_hu, op_ld_w}
    // mem and wb state interface
    input  wire        ws_allowin,
    output wire [`MS2WS_LEN -1:0] ms2ws_bus,
    output wire [39:0] ms_rf_zip, // {ms_rf_we, ms_rf_waddr, ms_rf_wdata}
    output wire        ms2ws_valid,
    // data sram interface
    input  wire         data_sram_data_ok,
    input  wire [31:0]  data_sram_rdata,
    // exception signal
    output wire        ms_ex,
    input  wire        wb_ex   
);
    wire       op_ld_b;
    wire       op_ld_h;
    wire       op_ld_w;
    wire       op_ld_bu;
    wire       op_ld_hu;

    wire        ms_ready_go;
    reg         ms_valid;
    reg  [31:0] ms_rf_result_tmp ; 
    reg         ms_res_from_mem;
    reg         ms_rf_we      ;
    reg         ms_csr_re     ;
    reg  [4 :0] ms_rf_waddr   ;
    reg  [4 :0] ms_ld_inst_zip;
    wire [31:0] ms_rf_wdata   ;
    wire [31:0] ms_mem_result ;
    wire [31:0] shift_rdata   ;

    reg  [ 7:0] ms_except_zip;
    reg  [78:0] ms_csr_zip;
    reg  [31:0] ms_pc;

    wire        ms_wait_data_ok;
    reg         ms_wait_data_ok_r;
    reg  [31:0] ms_data_buf;
    reg         data_buf_valid;  // 判断指令缓存是否有效

// TLB
    reg  [ 9:0] es2ms_tlb_zip; // ZIP信号
    wire        inst_tlbsrch;
    wire        inst_tlbrd;
    wire        inst_tlbwr;
    wire        inst_tlbfill;
    wire        ms_refetch_flag;
    wire        tlbsrch_found;
    wire [ 3:0] tlbsrch_idxgot;
    wire [ 9:0] ms2wb_tlb_zip;
    //csr
    wire [13:0] ms_csr_num;
    wire        ms_csr_we;
    wire [31:0] ms_csr_wmask;
    wire [31:0] ms_csr_wvalue;
    reg  [`TLB_ERRLEN-1:0] es2ms_tlb_exc;
    wire [`TLB_ERRLEN-1:0] ms2ws_tlb_exc;

//------------------------------state control signal---------------------------------------
    assign ms_wait_data_ok  = ms_wait_data_ok_r & ms_valid & ~wb_ex;
    assign ms_ready_go      = ~ms_wait_data_ok | ms_wait_data_ok & data_sram_data_ok;
    assign ms_allowin       = ~ms_valid | ms_ready_go & ws_allowin;     
    assign ms2ws_valid      = ms_valid & ms_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            ms_valid <= 1'b0;
        else if(wb_ex)
            ms_valid <= 1'b0;
        else if(ms_allowin)
            ms_valid <= es2ms_valid; 
    end
    assign ms_ex = ((|ms_except_zip) | (|es2ms_tlb_exc)) & ~ms_refetch_flag & ms_valid; // Refetch is just like an exception, but not officially one.
    
//------------------------------data buffer----------------------------------------------
    // 设置寄存器，暂存数据，并用valid信号表示其内数据是否有效
    always @(posedge clk) begin
        if(~resetn) begin
            ms_data_buf <= 32'b0;
            data_buf_valid <= 1'b0;
        end
        else if(ms2ws_valid & ws_allowin)   // 缓存已经流向下一流水级
            data_buf_valid <= 1'b0;
        else if(~data_buf_valid & data_sram_data_ok & ms_valid) begin
            ms_data_buf <= data_sram_rdata;
            data_buf_valid <= 1'b1;
        end

    end
//------------------------------exe and mem state interface---------------------------------------
    always @(posedge clk) begin
        if(~resetn) begin
            {ms_wait_data_ok_r, ms_ld_inst_zip, ms_pc, ms_csr_zip, ms_except_zip, es2ms_tlb_zip, es2ms_tlb_exc} <= {`ES2MS_LEN{1'b0}};
            {ms_csr_re, ms_res_from_mem, ms_rf_we, ms_rf_waddr, ms_rf_result_tmp} <= 39'b0;
        end
        if(es2ms_valid & ms_allowin) begin
            {ms_wait_data_ok_r, ms_ld_inst_zip, ms_pc, ms_csr_zip, ms_except_zip, es2ms_tlb_zip, es2ms_tlb_exc} <= es2ms_bus;
            {ms_csr_re, ms_res_from_mem, ms_rf_we, ms_rf_waddr, ms_rf_result_tmp} <= es_rf_zip;
        end
    end
//------------------------------mem and wb state interface---------------------------------------
    // 细粒度译码
    assign {op_ld_b, op_ld_bu,op_ld_h, op_ld_hu, op_ld_w} = ms_ld_inst_zip;
    assign shift_rdata   = {24'b0, {32{data_buf_valid}} & ms_data_buf | {32{~data_buf_valid}} & data_sram_rdata} >> {ms_rf_result_tmp[1:0], 3'b0};
    assign ms_mem_result[ 7: 0]   =  shift_rdata[ 7: 0];
    assign ms_mem_result[15: 8]   =  {8{op_ld_b}} & {8{shift_rdata[7]}} |
                                     {8{op_ld_bu}} & 8'b0               |
                                     {8{~op_ld_bu & ~op_ld_b}} & shift_rdata[15: 8];
    assign ms_mem_result[31:16]   =  {16{op_ld_b}} & {16{shift_rdata[7]}} |
                                     {16{op_ld_h}} & {16{shift_rdata[15]}}|
                                     {16{op_ld_bu | op_ld_hu}} & 16'b0    |
                                     {16{op_ld_w}} & shift_rdata[31:16];
    assign ms_rf_wdata = {32{ms_res_from_mem}} & ms_mem_result | {32{~ms_res_from_mem}} & ms_rf_result_tmp;
    assign ms_rf_zip  = {~ms2ws_valid & ms_res_from_mem & ms_valid, ms_csr_re & ms_valid, ms_rf_we & ms_valid, ms_rf_waddr, ms_rf_wdata};
    
    assign ms2ws_bus = {
                        ms_rf_result_tmp,   // 32 bit
                        ms_pc,              // 32 bit
                        ms_csr_zip,         // 79 bit
                        ms_except_zip,      //  8 bits, added 1 bit in exp19
                        ms2wb_tlb_zip,      // 10 bits
                        ms2ws_tlb_exc       //  8 bits
                    };


//---------------------------------- tlb --------------------------------------
    assign {ms_refetch_flag, inst_tlbsrch, inst_tlbrd, inst_tlbwr, inst_tlbfill, tlbsrch_found, tlbsrch_idxgot} = es2ms_tlb_zip;
    assign ms2wb_tlb_zip = es2ms_tlb_zip;
    assign {ms_csr_num, ms_csr_wmask, ms_csr_wvalue, ms_csr_we} = ms_csr_zip;
    assign ms_tlb_blk_zip = {inst_tlbrd & ms_valid, ms_csr_we & ms_valid, ms_csr_num};
    assign ms2ws_tlb_exc = es2ms_tlb_exc;
endmodule