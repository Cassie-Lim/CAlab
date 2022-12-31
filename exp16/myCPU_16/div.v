module Div(
    input  wire    div_clk,
    input  wire    resetn,
    input  wire    div,
    input  wire    div_signed,
    input  wire [31:0] x,   //被除数
    input  wire [31:0] y,   //除数
    output wire [31:0] s,   //商
    output wire [31:0] r,   //余数
    output wire    complete //除法完成信号
);

    wire        sign_s;
    wire        sign_r;
    wire [31:0] abs_x;
    wire [31:0] abs_y;
    wire [32:0] pre_r;
    wire [32:0] recover_r;
    reg  [63:0] x_pad;
    reg  [32:0] y_pad;
    reg  [31:0] s_r;
    reg  [32:0] r_r;    // 当前的余数
    reg  [ 5:0] counter;

// 1.确定符号位
    assign sign_s = (x[31]^y[31]) & div_signed;
    assign sign_r = x[31] & div_signed;
    assign abs_x  = (div_signed & x[31]) ? (~x+1'b1): x;
    assign abs_y  = (div_signed & y[31]) ? (~y+1'b1): y;
// 2.循环迭代得到商和余数绝对值
    assign complete = counter == 6'd33;
    //初始化计数器
    always @(posedge div_clk) begin
        if(~resetn) begin
            counter <= 6'b0;
        end
        else if(div) begin
            if(complete)
                counter <= 6'b0;
            else
                counter <= counter + 1'b1;
        end
    end
    //准备操作数,counter=0
    always @(posedge div_clk) begin
        if(~resetn)
            {x_pad, y_pad} <= {64'b0, 33'b0};
        else if(div) begin
            if(~|counter)
                {x_pad, y_pad} <= {32'b0, abs_x, 1'b0, abs_y};
        end
    end

    //求解当前迭代的减法结果
    assign pre_r = r_r - y_pad;                     //未恢复余数的结果
    assign recover_r = pre_r[32] ? r_r : pre_r;     //恢复余数的结果
    always @(posedge div_clk) begin
        if(~resetn) 
            s_r <= 32'b0;
        else if(div & ~complete & |counter) begin
            s_r[32-counter] <= ~pre_r[32];
        end
    end
    always @(posedge div_clk) begin
        if(~resetn)
            r_r <= 33'b0;
        if(div & ~complete) begin
            if(~|counter)   //余数初始化
                r_r <= {32'b0, abs_x[31]};
            else
                r_r <=  (counter == 32) ? recover_r : {recover_r, x_pad[31 - counter]};
        end
    end
// 3.调整最终商和余数
    assign s = div_signed & sign_s ? (~s_r+1'b1) : s_r;
    assign r = div_signed & sign_r ? (~r_r+1'b1) : r_r;
endmodule