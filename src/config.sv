`define RES_720P
`define GW_IDE

package configPackage;  

  `ifdef RES_480P
    localparam FRAMEWIDTH = 720;
    localparam FRAMEHEIGHT = 480;
    localparam TOTALWIDTH = 858;
    localparam TOTALHEIGHT = 525;
    localparam SCALE = 3;
    localparam VIDEOID = 2;
    localparam VIDEO_REFRESH = 59.94;

    localparam IDIV_SEL_X5 = 0;
    localparam FBDIV_SEL_X5 = 4;
    localparam ODIV_SEL_X5 = 4;
    localparam DUTYDA_SEL_X5 = "1000";
    localparam DYN_SDIV_SEL_X5 = 2;
    
    localparam CLKFRQ = 27000;
  `endif

  `ifdef RES_720P
    localparam FRAMEWIDTH = 1280;
    localparam FRAMEHEIGHT = 720;
    localparam TOTALWIDTH = 1650;
    localparam TOTALHEIGHT = 750;
    localparam SCALE = 5;
    localparam VIDEOID = 4;
    localparam VIDEO_REFRESH = 60.0;

    localparam IDIV_SEL_X5 = 3;
    localparam FBDIV_SEL_X5 = 54;
    localparam ODIV_SEL_X5 = 2;
    localparam DUTYDA_SEL_X5 = "1000";
    localparam DYN_SDIV_SEL_X5 = 2;
    
    localparam CLKFRQ = 74250;
  `endif

  localparam COLLEN = 80;
  localparam AUDIO_BIT_WIDTH = 16;

  localparam POWERUPNS = 100000000.0;
  localparam CLKPERNS = (1.0/CLKFRQ)*1000000.0;
  localparam int POWERUPCYCLES = $ceil( POWERUPNS/CLKPERNS );

endpackage