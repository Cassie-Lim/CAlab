`ifndef MACRO
    `define MACRO
//-----------------------macros for bus---------------------------

    `define FS2DS_LEN 65
    `define DS2ES_LEN 250
    `define ES2MS_LEN 123
    `define MS2WS_LEN 150

//-----------------------macros for csr---------------------------
    // macros for csr_num
    `define CSR_CRMD   14'h00
    `define CSR_PRMD   14'h01
    `define CSR_EUEN   14'h02
    `define CSR_ECFG   14'h04
    `define CSR_ESTAT  14'h05
    `define CSR_ERA    14'h06
    `define CSR_BADV   14'h07
    `define CSR_EENTRY 14'h0c
    `define CSR_SAVE0  14'h30
    `define CSR_SAVE1  14'h31
    `define CSR_SAVE2  14'h32
    `define CSR_SAVE3  14'h33
    `define CSR_TID    14'h40
    `define CSR_TCFG   14'h41
    `define CSR_TVAL   14'h42
    `define CSR_TICLR  14'h44

    // macros for index
    `define CSR_CRMD_PLV    1 :0
    `define CSR_CRMD_IE     2
    `define CSR_PRMD_PPLV   1 :0
    `define CSR_PRMD_PIE    2
    `define CSR_ECFG_LIE    12:0
    `define CSR_ESTAT_IS10  1 :0
    `define CSR_ERA_PC      31:0
    `define CSR_EENTRY_VA   31:6
    `define CSR_SAVE_DATA   31:0
    `define CSR_TID_TID     31:0
    `define CSR_TCFG_EN     0
    `define CSR_TCFG_PERIOD 1
    `define CSR_TCFG_INITV  31:2
    `define CSR_TICLR_CLR   0

    // macros for ecode and esubcode
    `define ECODE_INT       6'h00
    `define ECODE_ADE       6'h08   // ADEM: esubcode=1; ADEF: esubcode=0
    `define ECODE_ALE       6'h09   
    `define ECODE_SYS       6'h0B
    `define ECODE_BRK       6'h0C   
    `define ECODE_INE       6'h0D
    `define ECODE_TLBR      6'h3F
    
    `define ESUBCODE_ADEF   9'b00

`endif
