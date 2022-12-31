// 32位Booth两位乘需要生成16个部分积
// 32位无符号数乘法→34位有符号数乘法，需17个部分积
module Adder (
    input   [63:0] in1,
    input   [63:0] in2,
    input   [63:0] in3,
    output  [63:0] C,
    output  [63:0] S
);
    assign S  = in1 ^ in2 ^ in3;
    assign C = {(in1 & in2 | in1 & in3 | in2 & in3), 1'b0} ;
endmodule

module Wallace_Mul (
    input          mul_clk,
    input          resetn,
    input          mul_signed,
    input   [31:0] A,
    input   [31:0] B,
    output  [63:0] result
);
    wire [63:0] A_add;  
    wire [63:0] A_sub;
    wire [63:0] A2_add;
    wire [63:0] A2_sub;
    wire [34:0] sel_x;
    wire [34:0] sel_2x;
    wire [34:0] sel_neg_x;
    wire [34:0] sel_neg_2x;
    wire [34:0] sel_0;
    wire [16:0] sel_x_val;
    wire [16:0] sel_2x_val;
    wire [16:0] sel_neg_x_val;
    wire [16:0] sel_neg_2x_val;
    wire [16:0] sel_0_val;
    wire [18:0] debug;
    // 扩展成34位以兼容无符号数乘法（偶数位易于处理）
    wire [33:0] B_r;
    wire [33:0] B_m;
    wire [33:0] B_l;
    // 未对齐的部分积
    wire [63:0] P [16:0];
    assign B_m  = {{2{B[31] & mul_signed}}, B};
    assign B_l  = {1'b0, B_m[33:1]};
    assign B_r  = {B_m[32:0], 1'b0};

    assign sel_neg_x   = ( B_l &  B_m & ~B_r) | (B_l & ~B_m & B_r);    // 110, 101
    assign sel_x       = (~B_l &  B_m & ~B_r) | (~B_l & ~B_m& B_r);    // 010, 001
    assign sel_neg_2x  = ( B_l & ~B_m & ~B_r) ;                      //  100
    assign sel_2x      = (~B_l & B_m & B_r);                         // 011
    assign sel_0       = (B_l & B_m & B_r) | (~B_l & ~B_m & ~B_r);     // 000, 111
    assign A_add       = {{32{A[31] & mul_signed}}, A};
    assign A_sub       = ~ A_add + 1'b1;
    assign A2_add      = {A_add, 1'b0};
    assign A2_sub      = ~A2_add + 1'b1; 
    // 奇数位才是有效的选取信号
    assign sel_x_val    = { sel_x[32], sel_x[30], sel_x[28], sel_x[26], sel_x[24],
                            sel_x[22], sel_x[20], sel_x[18], sel_x[16],
                            sel_x[14], sel_x[12], sel_x[10], sel_x[ 8],
                            sel_x[ 6], sel_x[ 4], sel_x[ 2], sel_x[ 0]};
    assign sel_neg_x_val= { sel_neg_x[32], sel_neg_x[30], sel_neg_x[28], sel_neg_x[26], sel_neg_x[24],
                            sel_neg_x[22], sel_neg_x[20], sel_neg_x[18], sel_neg_x[16],
                            sel_neg_x[14], sel_neg_x[12], sel_neg_x[10], sel_neg_x[ 8],
                            sel_neg_x[ 6], sel_neg_x[ 4], sel_neg_x[ 2], sel_neg_x[ 0]};     
    assign sel_2x_val   =  {sel_2x[32], sel_2x[30], sel_2x[28], sel_2x[26], sel_2x[24],
                            sel_2x[22], sel_2x[20], sel_2x[18], sel_2x[16],
                            sel_2x[14], sel_2x[12], sel_2x[10], sel_2x[ 8],
                            sel_2x[ 6], sel_2x[ 4], sel_2x[ 2], sel_2x[ 0]};        
    assign sel_neg_2x_val= {sel_neg_2x[32], sel_neg_2x[30], sel_neg_2x[28], sel_neg_2x[26], sel_neg_2x[24],
                            sel_neg_2x[22], sel_neg_2x[20], sel_neg_2x[18], sel_neg_2x[16],
                            sel_neg_2x[14], sel_neg_2x[12], sel_neg_2x[10], sel_neg_2x[ 8],
                            sel_neg_2x[ 6], sel_neg_2x[ 4], sel_neg_2x[ 2], sel_neg_2x[ 0]};   
    assign sel_0_val    =  {sel_0[32], sel_0[30], sel_0[28], sel_0[26], sel_0[24],
                            sel_0[22], sel_0[20], sel_0[18], sel_0[16],
                            sel_0[14], sel_0[12], sel_0[10], sel_0[ 8],
                            sel_0[ 6], sel_0[ 4], sel_0[ 2], sel_0[ 0]}; 
    // debug信号应为0FFFF                                                                                              
    assign debug        = sel_x_val + sel_neg_2x_val + sel_neg_x_val + sel_2x_val + sel_0_val;
    // 十六个未对齐的部分积
    assign {P[16], P[15], P[14], P[13], P[12],
            P[11], P[10], P[ 9], P[ 8],
            P[ 7], P[ 6], P[ 5], P[ 4],
            P[ 3], P[ 2], P[ 1], P[ 0]} 
            =  {{64{sel_x_val[16]}}, {64{sel_x_val[15]}}, {64{sel_x_val[14]}}, {64{sel_x_val[13]}}, {64{sel_x_val[12]}},
                {64{sel_x_val[11]}}, {64{sel_x_val[10]}}, {64{sel_x_val[ 9]}}, {64{sel_x_val[ 8]}},
                {64{sel_x_val[ 7]}}, {64{sel_x_val[ 6]}}, {64{sel_x_val[ 5]}}, {64{sel_x_val[ 4]}},
                {64{sel_x_val[ 3]}}, {64{sel_x_val[ 2]}}, {64{sel_x_val[ 1]}}, {64{sel_x_val[ 0]}}} & {17{A_add}} |
               {{64{sel_neg_x_val[16]}}, {64{sel_neg_x_val[15]}}, {64{sel_neg_x_val[14]}}, {64{sel_neg_x_val[13]}}, {64{sel_neg_x_val[12]}},
                {64{sel_neg_x_val[11]}}, {64{sel_neg_x_val[10]}}, {64{sel_neg_x_val[ 9]}}, {64{sel_neg_x_val[ 8]}},
                {64{sel_neg_x_val[ 7]}}, {64{sel_neg_x_val[ 6]}}, {64{sel_neg_x_val[ 5]}}, {64{sel_neg_x_val[ 4]}},
                {64{sel_neg_x_val[ 3]}}, {64{sel_neg_x_val[ 2]}}, {64{sel_neg_x_val[ 1]}}, {64{sel_neg_x_val[ 0]}}}  & {17{A_sub}} |
               {{64{sel_2x_val[16]}}, {64{sel_2x_val[15]}}, {64{sel_2x_val[14]}}, {64{sel_2x_val[13]}}, {64{sel_2x_val[12]}},
                {64{sel_2x_val[11]}}, {64{sel_2x_val[10]}}, {64{sel_2x_val[ 9]}}, {64{sel_2x_val[ 8]}},
                {64{sel_2x_val[ 7]}}, {64{sel_2x_val[ 6]}}, {64{sel_2x_val[ 5]}}, {64{sel_2x_val[ 4]}},
                {64{sel_2x_val[ 3]}}, {64{sel_2x_val[ 2]}}, {64{sel_2x_val[ 1]}}, {64{sel_2x_val[ 0]}}} & {17{A2_add}} |
               {{64{sel_neg_2x_val[16]}}, {64{sel_neg_2x_val[15]}}, {64{sel_neg_2x_val[14]}}, {64{sel_neg_2x_val[13]}}, {64{sel_neg_2x_val[12]}},
                {64{sel_neg_2x_val[11]}}, {64{sel_neg_2x_val[10]}}, {64{sel_neg_2x_val[ 9]}}, {64{sel_neg_2x_val[ 8]}},
                {64{sel_neg_2x_val[ 7]}}, {64{sel_neg_2x_val[ 6]}}, {64{sel_neg_2x_val[ 5]}}, {64{sel_neg_2x_val[ 4]}},
                {64{sel_neg_2x_val[ 3]}}, {64{sel_neg_2x_val[ 2]}}, {64{sel_neg_2x_val[ 1]}}, {64{sel_neg_2x_val[ 0]}}} & {17{A2_sub}}; 

//-----------------------------------------Level 1--------------------------------------------- 
    wire [63:0] level_1 [11:0];
    Adder adder1_1 (
        .in1({P[15], 30'b0}),
        .in2({P[14], 28'b0}),
        .in3({P[13], 26'b0}),
        .C(level_1[0]),
        .S(level_1[1])
    );
    Adder adder1_2 (
        .in1({P[12], 24'b0}),
        .in2({P[11], 22'b0}),
        .in3({P[10], 20'b0}),
        .C(level_1[2]),
        .S(level_1[3])
    );
    Adder adder1_3 (
        .in1({P[ 9], 18'b0}),
        .in2({P[ 8], 16'b0}),
        .in3({P[ 7], 14'b0}),
        .C(level_1[4]),
        .S(level_1[5])
    );
    Adder adder1_4 (
        .in1({P[ 6], 12'b0}),
        .in2({P[ 5], 10'b0}),
        .in3({P[ 4],  8'b0}),
        .C(level_1[6]),
        .S(level_1[7])
    );
    Adder adder1_5 (
        .in1({P[ 3],  6'b0}),
        .in2({P[ 2],  4'b0}),
        .in3({P[ 1],  2'b0}),
        .C(level_1[8]),
        .S(level_1[9])
    );
    assign level_1[10] = P[0];
    assign level_1[11] = {P[16], 32'b0};
//-----------------------------------------Level 2--------------------------------------------- 
    wire [63:0] level_2 [7:0];
    Adder adder2_1 (
        .in1(level_1[0]),
        .in2(level_1[1]),
        .in3(level_1[2]),
        .C(level_2[0]),
        .S(level_2[1])
    );
    Adder adder2_2 (
        .in1(level_1[3]),
        .in2(level_1[4]),
        .in3(level_1[5]),
        .C(level_2[2]),
        .S(level_2[3])
    );
    Adder adder2_3 (
        .in1(level_1[6]),
        .in2(level_1[7]),
        .in3(level_1[8]),
        .C(level_2[4]),
        .S(level_2[5])
    );
    Adder adder2_4 (
        .in1(level_1[9]),
        .in2(level_1[10]),
        .in3(level_1[11]),
        .C(level_2[6]),
        .S(level_2[7])
    );
//-----------------------------------------Level 3--------------------------------------------- 
    wire [63:0] level_3 [5:0];
    Adder adder3_1 (
        .in1(level_2[0]),
        .in2(level_2[1]),
        .in3(level_2[2]),
        .C(level_3[0]),
        .S(level_3[1])
    );
    Adder adder3_2 (
        .in1(level_2[3]),
        .in2(level_2[4]),
        .in3(level_2[5]),
        .C(level_3[2]),
        .S(level_3[3])
    );
    assign level_3[4] = level_2[6];
    assign level_3[5] = level_2[7];
//-----------------------------------------Level 4--------------------------------------------- 
    wire [63:0] level_4 [3:0];
    Adder adder4_1 (
        .in1(level_3[0]),
        .in2(level_3[1]),
        .in3(level_3[2]),
        .C(level_4[0]),
        .S(level_4[1])
    );
    Adder adder4_2 (
        .in1(level_3[3]),
        .in2(level_3[4]),
        .in3(level_3[5]),
        .C(level_4[2]),
        .S(level_4[3])
    );
//-----------------------------------------Level 5--------------------------------------------- 
    wire [63:0] level_5 [2:0];
    Adder adder5_1 (
        .in1(level_4[0]),
        .in2(level_4[1]),
        .in3(level_4[2]),
        .C(level_5[0]),
        .S(level_5[1])
    );
    assign level_5[2] = level_4[3]; 
//-----------------------------------------Level 5--------------------------------------------- 
    wire [63:0] level_6 [1:0];
    Adder adder6_1 (
        .in1(level_5[0]),
        .in2(level_5[1]),
        .in3(level_5[2]),
        .C(level_6[0]),
        .S(level_6[1])
    );
    assign result = (level_6[0] + level_6[1]) & {64{resetn}};
endmodule

