module cache(
    input clk,
    input resetn,
    //CPU<->cache
    input         valid,//请求有效
    input         op,//1：write 0 : read
    input [ 7:0]  index, //addr[11:4]
    input [19:0]  tag, 
    input [ 3:0]  offset, //addr[3:0]
    input [ 3:0]  wstrb,
    input [31:0]  wdata,
    output        addr_ok,//读：地址被接受，写：地址和数据被接受
    output        data_ok,//（请求ok）读；数据返回，写：数据写入完成
    output[31:0]  rdata,

    //AXO <-> cache
    //read
    output        rd_req,
    output[ 2:0]  rd_type,//3'b000-BYTE  3'b001-HALFWORD 3'b010-WORD 3'b100-cache-rowcache�?
    output[31:0]  rd_addr,
    input         rd_rdy,//读请求能否被接受的握手信号IN
    input         ret_valid,
    input         ret_last,
    input [31:0]  ret_data,
    //write
    output        wr_req,
    output[ 2:0]  wr_type,
    output[31:0]  wr_addr,
    output[ 3:0]  wr_wstrb,
    output[127:0] wr_data,       
    input         wr_rdy//wr_req要看到wr_rdy后才=1
);
    reg [1:0] ret_cnt;//cmax=3 ~offset[3:2]& bank分四段
    wire rst= ~resetn;
    genvar i,j;
    //主状态机
    parameter IDLE 		= 5'b00001;
    parameter LOOKUP 	= 5'b00010;
    parameter MISS 		= 5'b00100;
    parameter REPLACE 	= 5'b01000;
    parameter REFILL 	= 5'b10000;
    reg [4:0] curstate;
    reg [4:0] nxtstate;
    parameter WRBUF_IDLE = 2'b01;
    parameter WRBUF_WRITE =2'b10;
    reg[1:0] wrbuf_curstate;
    reg[1:0] wrbuf_nxtstate;

    reg  [68:0] req_buf;   // {op, wstrb, wdata, index, tag, offset}
    wire        op_r;
    wire [ 3:0] wstrb_r;
    wire [31:0] wdata_r;
    wire [ 7:0] index_r;
    wire [19:0] tag_r;
    wire [ 3:0] offset_r;

    wire        tag_we    [1:0];
    wire [ 7:0] tag_addr  [1:0];
    wire [19:0] tag_wdata [1:0]; 
    wire [19:0] tag_rdata [1:0];//[20:1]tag
    wire [ 3:0] data_bank_we    [1:0][3:0];
    wire [ 7:0] data_bank_addr  [1:0][3:0];
    wire [31:0] data_bank_wdata [1:0][3:0];
    wire [31:0] data_bank_rdata [1:0][3:0];
    reg  [255:0] dirty_arr [1:0];
    reg  [255:0] valid_arr [1:0];
    
    wire replace_way;

    wire hit_write;
    wire hit_write_hazard;
    wire [1:0] way_hit;
    wire [31:0] load_res;
//tag compare
    wire cache_hit= way_hit[0] || way_hit[1];
    assign way_hit[0]= valid_arr[0][index_r] && (tag_rdata[0] == tag_r);
    assign way_hit[1]= valid_arr[1][index_r] && (tag_rdata[1] == tag_r);
    assign hit_write = (curstate== LOOKUP) && cache_hit && op_r;
    assign hit_write_hazard= ( (curstate== LOOKUP) && hit_write && valid && ~op && {index, offset} == {index_r, offset_r} )
                            || ((wrbuf_curstate== WRBUF_WRITE) && valid && ~op && offset[3:2]== offset_r[3:2]);
    assign load_res= data_bank_rdata[way_hit[1]][offset_r[3:2]];//读成功命中
//读cache最后要返回                       
    assign rdata =ret_valid? ret_data:load_res;


//主状态机
    always@(posedge clk) begin
        if(rst) begin
            curstate <= IDLE;
        end 
        else begin
            curstate <= nxtstate;
        end
    end
    always@(*) begin
        case(curstate)
            IDLE:
                if(valid & ~hit_write_hazard) begin
                    nxtstate = LOOKUP; 
                end       
                else begin//no request/hit write hazard
                    nxtstate = IDLE;
                end
            LOOKUP:
                if(cache_hit & (~valid | hit_write_hazard) ) begin
                    nxtstate = IDLE;
                end
                else if (cache_hit & valid) begin
                    nxtstate = LOOKUP;
                end  
                else if (~dirty_arr[replace_way][index_r] | ~valid_arr[replace_way][index_r]) begin
                    nxtstate = REPLACE;
                end
                else begin
                    nxtstate = MISS;
                end
            MISS:
                if (~wr_rdy) begin
                        nxtstate = MISS;
                end
                else begin
                    nxtstate = REPLACE;
                end
               
            REPLACE:
                if(~rd_rdy) begin
                    nxtstate = REPLACE;
                end
                else  begin
                    nxtstate = REFILL;
                end
            REFILL:
                if (ret_valid & ret_last) begin
                    nxtstate = IDLE;
                end else begin
                    nxtstate = REFILL;
                end
            default:
                nxtstate = IDLE;
        endcase
    end 

    //write_buffer状态机，独立于主状态机之外
    always @ (posedge clk) begin
        if (rst) begin
            wrbuf_curstate <= WRBUF_IDLE;
        end else begin
            wrbuf_curstate <= wrbuf_nxtstate;
        end
    end
    always @ (*) begin
        case (wrbuf_curstate)
            //没有待写的数据
            WRBUF_IDLE:
                if (hit_write) begin
                    wrbuf_nxtstate = WRBUF_WRITE;
                end else begin
                    wrbuf_nxtstate = WRBUF_IDLE;
                end
            //有待写的数据
            WRBUF_WRITE:
                if (hit_write) begin
                    wrbuf_nxtstate = WRBUF_WRITE;
                end else begin
                    wrbuf_nxtstate = WRBUF_IDLE;
                end
            default:wrbuf_nxtstate = WRBUF_IDLE;
        endcase
    end

//write buffer
    reg  [48:0] write_buf;  // way, index, offset, wstrb, wdata
    wire        wrbuf_way;//way0
    wire [ 7:0] wrbuf_index;
    wire [ 3:0] wrbuf_offset;
    wire [ 3:0] wrbuf_wstrb;
    wire [31:0] wrbuf_wdata;
    always @ (posedge clk) begin
        if (rst) begin
            write_buf <= 49'b0;
        end else if (hit_write) begin
            write_buf <= {way_hit[1], index_r, offset_r, wstrb_r, wdata_r};
        end
    end
    assign {wrbuf_way, wrbuf_index, wrbuf_offset, wrbuf_wstrb, wrbuf_wdata} = write_buf;

//requset buffer:锁存，输出要与RAM读出的信息处于同�?�?
    always @ (posedge clk) begin
        if (rst) begin
            req_buf <= 69'b0;
        end else if (valid && addr_ok) begin
            req_buf <= {op, wstrb, wdata, index, tag, offset};
        end
    end
    assign {op_r, wstrb_r, wdata_r, index_r, tag_r, offset_r} = req_buf;

//miss buffer:记录replace_way+ret_cnt:从axi线返回几个数据
    always @ (posedge clk) begin
        if (rst) begin
            ret_cnt <= 2'b0;
        end else if (ret_valid & ~ret_last) begin
            ret_cnt <= ret_cnt + 2'd1;
        end else if (ret_valid & ret_last) begin
            ret_cnt <= 2'b0;
        end
    end
    //LFSR:线性反馈移位寄存器 伪随机数 好replace_way在REFILL-> IDLE变比较好
    reg [2:0] lfsr;
    always @(posedge clk) begin
        if(rst)begin
            lfsr<= 3'b111;
        end
        else if(ret_valid & ret_last)begin
            lfsr <={lfsr[0],lfsr[2]^lfsr[0],lfsr[1]};
        end
    end
    assign replace_way=lfsr[0];



//dirty array
    always @ (posedge clk) begin
        if (rst) begin
            dirty_arr[0] <= 256'b0;
            dirty_arr[1] <= 256'b0;
        end else if (wrbuf_curstate==WRBUF_WRITE) begin//hit_write
            dirty_arr[wrbuf_way][wrbuf_index] <= 1'b1;
        end else if (ret_valid & ret_last) begin //hit_miss:REFILL->IDLE
            dirty_arr[replace_way][index_r] <= op_r;//都是r！！！！
        end
    end

// valid array
    always @ (posedge clk) begin
        if (rst) begin
            valid_arr[0] <= 256'b0;
            valid_arr[1] <= 256'b0;
        end else if (ret_valid & ret_last) begin
            valid_arr[replace_way][index_r] <= 1'b1;
        end
    end

//实例化
    generate 
        for(i=0;i<2;i=i+1)begin
            TAG_RAM tag_ram_i(
                .clka(clk),
                .wea(tag_we[i]),
                .addra(tag_addr[i]),
                .dina (tag_wdata[i]),
                .douta(tag_rdata[i])
            );
        end
    endgenerate
    generate // way 0
        for (i = 0; i < 4; i = i + 1) begin
            DATA_Bank_RAM data_bank_ram_i(
                .clka (clk),
                .wea  (data_bank_we[0][i]),
                .addra(data_bank_addr[0][i]),
                .dina (data_bank_wdata[0][i]),
                .douta(data_bank_rdata[0][i])
            );
        end
    endgenerate
    generate // way 1
        for (i = 0; i < 4; i = i + 1) begin
            DATA_Bank_RAM data_bank_ram_i(
                .clka (clk),
                .wea  (data_bank_we[1][i]),
                .addra(data_bank_addr[1][i]),
                .dina (data_bank_wdata[1][i]),
                .douta(data_bank_rdata[1][i])
            );
        end
    endgenerate
    //实例化需要的端口
    assign tag_we[0] = ret_valid & ret_last & ~replace_way;
    assign tag_we[1] = ret_valid & ret_last &  replace_way;
    assign tag_wdata[0] = tag_r;//r!!!!
    assign tag_wdata[1] = tag_r;
    assign tag_addr[0] = (curstate== IDLE)|| (curstate== LOOKUP) ? index : index_r;//index是虚地址
    assign tag_addr[1] = (curstate== IDLE)|| (curstate== LOOKUP) ? index : index_r;
    generate
        for (i = 0; i < 4; i = i + 1) begin
            //we:4'bits 
            assign data_bank_we[0][i] = {4{(wrbuf_curstate==WRBUF_WRITE) & (wrbuf_offset[3:2] == i) & ~wrbuf_way}} & wrbuf_wstrb
                                      | {4{ret_valid & ret_cnt == i & ~replace_way}} & 4'hf;
            assign data_bank_we[1][i] = {4{(wrbuf_curstate==WRBUF_WRITE) & (wrbuf_offset[3:2] == i) & wrbuf_way}} & wrbuf_wstrb
                                      | {4{ret_valid & ret_cnt == i &  replace_way}} & 4'hf;
            assign data_bank_wdata[0][i] = (wrbuf_curstate==WRBUF_WRITE) ? wrbuf_wdata ://hit_write
                                           (offset_r[3:2] != i || ~op_r)   ? ret_data    :
                                           {wstrb_r[3] ? wdata_r[31:24] : ret_data[31:24],
                                            wstrb_r[2] ? wdata_r[23:16] : ret_data[23:16],
                                            wstrb_r[1] ? wdata_r[15: 8] : ret_data[15: 8],
                                            wstrb_r[0] ? wdata_r[ 7: 0] : ret_data[ 7: 0]};
            assign data_bank_wdata[1][i] = (wrbuf_curstate==WRBUF_WRITE) ? wrbuf_wdata :
                                           (offset_r[3:2] != i || ~op_r)   ? ret_data    :
                                           {wstrb_r[3] ? wdata_r[31:24] : ret_data[31:24],
                                            wstrb_r[2] ? wdata_r[23:16] : ret_data[23:16],
                                            wstrb_r[1] ? wdata_r[15: 8] : ret_data[15: 8],
                                            wstrb_r[0] ? wdata_r[ 7: 0] : ret_data[ 7: 0]};    
        
        end
    endgenerate
    
    generate
        for (i=0; i<2; i=i+1) begin
            for (j=0; j<4; j=j+1) begin
                assign data_bank_addr[i][j] = (curstate== IDLE)|| (curstate== LOOKUP) ? index : index_r;
            end
        end
    endgenerate


//10.1.3.4模块接口de信号
    assign wr_type= 3'b100;
    assign rd_type= 3'b100;
    assign rd_addr = {tag_r, index_r, offset_r};
    assign wr_addr = {tag_rdata[replace_way][19:0], index_r, offset_r};
    //控制相关
    reg wr_req_r;
    assign wr_req= wr_req_r;
    always @ (posedge clk) begin
        if (rst) begin
            wr_req_r <= 1'b0;
        end 
        else if( curstate==MISS & nxtstate==REPLACE)begin
            wr_req_r <=1'b1;
        end
        // else if (curstate==MISS & nxtstate==REPLACE & dirty_arr[replace_way][index_r] & valid_arr[replace_way][index_r] ) begin
        //     wr_req_r <= 1'b1; 
        // end 
        // else if(curstate==MISS & nxtstate==REPLACE & ( ~dirty_arr[replace_way][index_r] | ~valid_arr[replace_way][index_r]) )begin
        //     wr_req_r <= 1'b0;
        // end
        else if(wr_rdy)begin
            wr_req_r <= 1'b0;
        end
    end
    assign addr_ok =(curstate==IDLE) || ( curstate==LOOKUP & valid &cache_hit & op) || (curstate==LOOKUP & valid & cache_hit & ~op & ~hit_write_hazard);
    assign data_ok =(curstate== LOOKUP && cache_hit)|| (curstate==LOOKUP && op_r) || (~op_r && curstate==REFILL && ret_valid && ret_cnt==offset_r[3:2]);
    assign rd_req  =(curstate==REPLACE);
    assign wr_wstrb = 4'hf;
    assign wr_data  = {data_bank_rdata[replace_way][3],
                       data_bank_rdata[replace_way][2],
                       data_bank_rdata[replace_way][1],
                       data_bank_rdata[replace_way][0]};



endmodule
