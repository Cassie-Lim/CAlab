module EXEreg(
    input  wire        clk,
    input  wire        resetn,
    // id and exe state interface
    output wire        exe_allowin,
    input  wire [5 :0] id_rf_zip, // {id_rf_we, id_rf_waddr}
    input  wire        id_to_exe_valid,
    input  wire [31:0] id_pc,    
    input  wire [75:0] id_alu_data_zip, // {exe_alu_op, exe_alu_src1, exe_alu_src2}
    input  wire        id_res_from_mem, 
    input  wire        id_mem_we,
    input  wire [31:0] id_rkd_value,
    // exe and mem state interface
    input  wire        mem_allowin,
    output reg  [5 :0] exe_rf_zip, // {exe_rf_we, exe_rf_waddr}
    output wire        exe_to_mem_valid,
    output reg  [31:0] exe_pc,    
    output wire [31:0] exe_alu_result, 
    output reg         exe_res_from_mem, 
    output reg         exe_mem_we,
    output reg  [31:0] exe_rkd_value
);

    wire        exe_ready_go;
    reg         exe_valid;

    reg  [11:0] exe_alu_op;
    reg  [31:0] exe_alu_src1   ;
    reg  [31:0] exe_alu_src2   ;


//------------------------------state control signal---------------------------------------

    assign exe_ready_go      = 1'b1;
    assign exe_allowin       = ~exe_valid | exe_ready_go & mem_allowin;     
    assign exe_to_mem_valid  = exe_valid & exe_ready_go;
    always @(posedge clk) begin
        if(~resetn)
            exe_valid <= 1'b0;
        else
            exe_valid <= id_to_exe_valid & exe_allowin; 
    end

//------------------------------id and exe state interface---------------------------------------
    always @(posedge clk) begin
        if(id_to_exe_valid & exe_allowin)
            exe_pc <= id_pc;
    end
    always @(posedge clk) begin
        if(id_to_exe_valid & exe_allowin)
            {exe_alu_op, exe_alu_src1, exe_alu_src2} <= id_alu_data_zip;
    end
    always @(posedge clk) begin
        if(id_to_exe_valid & exe_allowin)
            {exe_res_from_mem, exe_mem_we, exe_rkd_value, exe_rf_zip} <= {id_res_from_mem, id_mem_we, id_rkd_value, id_rf_zip};
    end
        
    alu u_alu(
        .alu_op     (exe_alu_op    ),
        .alu_src1   (exe_alu_src1  ),
        .alu_src2   (exe_alu_src2  ),
        .alu_result (exe_alu_result)
    );
endmodule