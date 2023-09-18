
//--------------------------------------------------------------------------------------------------------
// Module  : sd_file_list_reader
// Type    : synthesizable, IP's top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: A SD-card host to initialize SD-card, list root directory and read files
//           op=1: list all files in root dir and output names through list_en, list_name and list_file_num
//           op=2: read content of the file numbered read_file
//           Support CardType   : SDv1.1 , SDv2  or SDHCv2
//           Support FileSystem : FAT16 or FAT32
//--------------------------------------------------------------------------------------------------------

// FAT32: https://www.p-dd.com/chapter3-page6.html

module sd_file_list_reader #(
    parameter      [2:0] CLK_DIV       = 3'd2,          // when clk =   0~ 25MHz , set CLK_DIV = 3'd1,
                                                        // when clk =  25~ 50MHz , set CLK_DIV = 3'd2,
                                                        // when clk =  50~100MHz , set CLK_DIV = 3'd3,
                                                        // when clk = 100~200MHz , set CLK_DIV = 3'd4,
                                                        // ......
    parameter            SIMULATE      = 0              // 0:normal use.         1:only for simulation
) (
    // rstn active-low, 1:working, 0:reset
    input  wire       rstn,
    // clock
    input  wire       clk,
    // SDcard signals (connect to SDcard), this design do not use sddat1~sddat3.
    output wire       sdclk,
    inout             sdcmd,
    input  wire       sddat0,            // FPGA only read SDDAT signal but never drive it
    // command interface
    input             op,                // 0: list root dir, 1: read file. rstn <= 0 to restart a new operation.
    input      [11:0] read_file,         // file number to read for cmd=2
    output      [2:0] done,              // operation finished
    // status output (optional for user)
    output wire [3:0] card_stat,         // show the sdcard initialize status
    output wire [1:0] card_type,         // 0=UNKNOWN    , 1=SDv1    , 2=SDv2  , 3=SDHCv2
    output wire [1:0] filesystem_type,   // 0=UNASSIGNED , 1=UNKNOWN , 2=FAT16 , 3=FAT32 
    output reg        file_found,        // 0=file not found, 1=file found
    // listing output (root directory, files only)
    output     [7:0]  list_name[0:51],   // name of current file, max 52 chars, [255:248] is first char, etc.
    output     [7:0]  list_namelen,
    output reg [11:0] list_file_num,     // number of current file: 0, 1...
    output            list_en,           // pulse on new list result
    // reading content data output (sync with clk)
    output reg        outen,             // when outen=1, a byte of file content is read out from outbyte
    output reg  [7:0] outbyte,           // a byte of file content
    output debug_read_done,
    output [31:0] debug_read_sector_no,
    output debug_filesystem_state
);

initial file_found = 1'b0;
initial {outen,outbyte} = 0;


reg         read_start     = 1'b0;
reg  [31:0] read_sector_no = 0;
wire        read_done;

assign debug_read_done = read_done;
assign debug_read_sector_no = read_sector_no;

wire        rvalid;
wire [ 8:0] raddr;
wire [ 7:0] rdata;

reg  [31:0] rootdir_sector = 0 , rootdir_sector_t;             // rootdir sector number (FAT16 only)
reg  [15:0] rootdir_sectorcount = 0 , rootdir_sectorcount_t;   // (FAT16 only)

reg  [31:0] curr_cluster = 0 , curr_cluster_t;    // current reading cluster number

wire [ 6:0] curr_cluster_fat_offset;
wire [24:0] curr_cluster_fat_no;
assign {curr_cluster_fat_no,curr_cluster_fat_offset} = curr_cluster;

wire [ 7:0] curr_cluster_fat_offset_fat16;
wire [23:0] curr_cluster_fat_no_fat16;
assign {curr_cluster_fat_no_fat16,curr_cluster_fat_offset_fat16} = curr_cluster;

reg  [31:0] target_cluster = 0;           // target cluster number item in FAT32 table
reg  [15:0] target_cluster_fat16 = 16'h0; // target cluster number item in FAT16 table
reg  [ 7:0] cluster_sector_offset=8'h0 , cluster_sector_offset_t;   // current sector number in cluster

reg  [31:0] file_cluster = 0;
reg  [31:0] file_size = 0;

reg  [ 7:0] cluster_size = 0 , cluster_size_t;
reg  [31:0] first_fat_sector_no = 0 , first_fat_sector_no_t;
reg  [31:0] first_data_sector_no= 0 , first_data_sector_no_t;

reg         search_fat = 1'b0;

localparam [2:0] RESET         = 3'd0,
                 SEARCH_MBR    = 3'd1,
                 SEARCH_DBR    = 3'd2,
                 LS_ROOT_FAT16 = 3'd3,
                 LS_ROOT_FAT32 = 3'd4,
                 READ_A_FILE   = 3'd5,
                 DONE          = 3'd6;

reg        [2:0] filesystem_state = RESET;
assign debug_filesystem_state = filesystem_state;
assign done = filesystem_state == DONE;

localparam [1:0] UNASSIGNED = 2'd0,
                 UNKNOWN    = 2'd1,
                 FAT16      = 2'd2,
                 FAT32      = 2'd3;

reg        [1:0] filesystem = UNASSIGNED,
                 filesystem_parsed;

//enum logic [2:0] {RESET, SEARCH_MBR, SEARCH_DBR, LS_ROOT_FAT16, LS_ROOT_FAT32, READ_A_FILE, DONE} filesystem_state = RESET;
//enum logic [1:0] {UNASSIGNED, UNKNOWN, FAT16, FAT32} filesystem=UNASSIGNED, filesystem_parsed;

assign filesystem_type = filesystem;



//----------------------------------------------------------------------------------------------------------------------
// loop variables
integer ii, i;


//----------------------------------------------------------------------------------------------------------------------
// store MBR or DBR fields
//----------------------------------------------------------------------------------------------------------------------
reg [ 7:0] sector_content [0:511];
initial for (ii=0; ii<512; ii=ii+1) sector_content[ii] = 0;

always @ (posedge clk)
    if (rvalid)
        sector_content[raddr] <= rdata;



//----------------------------------------------------------------------------------------------------------------------
// parse MBR or DBR fields
//----------------------------------------------------------------------------------------------------------------------
wire        is_boot_sector     = ( {sector_content['h1FE],sector_content['h1FF]}==16'h55AA );
wire        is_dbr             =    sector_content[0]==8'hEB || sector_content[0]==8'hE9;
wire [31:0] dbr_sector_no      =   {sector_content['h1C9],sector_content['h1C8],sector_content['h1C7],sector_content['h1C6]};
wire [15:0] bytes_per_sector   =   {sector_content['hC],sector_content['hB]};
wire [ 7:0] sector_per_cluster =    sector_content['hD];
wire [15:0] resv_sectors       =   {sector_content['hF],sector_content['hE]};
wire [ 7:0] number_of_fat      =    sector_content['h10];
wire [15:0] rootdir_itemcount  =   {sector_content['h12],sector_content['h11]};   // root dir item count (FAT16 Only)

reg  [31:0] sectors_per_fat = 0;
reg  [31:0] root_cluster    = 0;

always @ (*) begin    
    sectors_per_fat   = {16'h0, sector_content['h17], sector_content['h16]};
    root_cluster      = 0;
    if(sectors_per_fat>0) begin                     // FAT16 case
        filesystem_parsed = FAT16;
    end else if(sector_content['h56]==8'h32) begin  // FAT32 case
        filesystem_parsed = FAT32;
        sectors_per_fat   = {sector_content['h27],sector_content['h26],sector_content['h25],sector_content['h24]};
        root_cluster      = {sector_content['h2F],sector_content['h2E],sector_content['h2D],sector_content['h2C]};
    end else begin   // Unknown FileSystem
        filesystem_parsed = UNKNOWN;
    end
end



//----------------------------------------------------------------------------------------------------------------------
// main FSM
//----------------------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)
    if(~rstn) begin           
        filesystem_state <= RESET;
        read_start <= 1'b0;
        read_sector_no <= 0;
        filesystem <= UNASSIGNED;
        search_fat <= 1'b0;
        cluster_size <= 8'h0;
        first_fat_sector_no   <= 0;
        first_data_sector_no  <= 0;
        curr_cluster          <= 0;
        cluster_sector_offset <= 8'h0;
        rootdir_sector        <= 0;
        rootdir_sectorcount   <= 16'h0;
    end else begin
        // nand2mario: this is confusing due to mixing of blocking and non-blocking assignments
        // all *_t variables are combinatorial and thus uses blocking assignments
        cluster_size_t = cluster_size;
        first_fat_sector_no_t  = first_fat_sector_no;
        first_data_sector_no_t = first_data_sector_no;
        curr_cluster_t = curr_cluster;
        cluster_sector_offset_t = cluster_sector_offset;
        rootdir_sector_t = rootdir_sector;
        rootdir_sectorcount_t = rootdir_sectorcount;
    
        read_start <= 1'b0;
        
        if (read_done) begin
            case(filesystem_state)
            SEARCH_MBR :    if(is_boot_sector) begin
                                filesystem_state <= SEARCH_DBR;
                                if(~is_dbr) read_sector_no <= dbr_sector_no;
                            end else begin
                                read_sector_no <= read_sector_no + 1;
                            end

                            // DBR format: https://www.p-dd.com/chapter3-page19.html
            SEARCH_DBR :    if(is_boot_sector && is_dbr ) begin
                                if(bytes_per_sector!=16'd512) begin
                                    filesystem_state <= DONE;
                                end else begin
                                    filesystem <= filesystem_parsed;
                                    if(filesystem_parsed==FAT16) begin
                                        cluster_size_t        = sector_per_cluster;
                                        first_fat_sector_no_t = read_sector_no + resv_sectors;
                                        
                                        rootdir_sectorcount_t = rootdir_itemcount / (16'd512/16'd32);
                                        rootdir_sector_t      = first_fat_sector_no_t + sectors_per_fat * number_of_fat;
                                        first_data_sector_no_t= rootdir_sector_t + rootdir_sectorcount_t - cluster_size_t*2;
                                        
                                        cluster_sector_offset_t = 8'h0;
                                        read_sector_no      <= rootdir_sector_t + cluster_sector_offset_t;
                                        filesystem_state <= LS_ROOT_FAT16;
                                    end else if(filesystem_parsed==FAT32) begin
                                        cluster_size_t        = sector_per_cluster;             // 4
                                        first_fat_sector_no_t = read_sector_no + resv_sectors;  // 0x155E
                                                                                                // sectors_per_fat = 0x7551, number_of_fat = 2
                                        first_data_sector_no_t= first_fat_sector_no_t + sectors_per_fat * number_of_fat - cluster_size_t * 2;
                                                                                                // 0xFFF8
                                        curr_cluster_t        = root_cluster;                   // 2
                                        cluster_sector_offset_t = 8'h0;
                                        read_sector_no      <= first_data_sector_no_t + cluster_size_t * curr_cluster_t + cluster_sector_offset_t;
                                                                                                // 0x10000
                                        filesystem_state <= LS_ROOT_FAT32;
                                    end else begin
                                        filesystem_state <= DONE;
                                    end
                                end
                            end
            LS_ROOT_FAT16 :     if(file_found) begin
                                    curr_cluster_t = file_cluster;
                                    cluster_sector_offset_t = 8'h0;
                                    read_sector_no <= first_data_sector_no_t + cluster_size_t * curr_cluster_t + cluster_sector_offset_t;
                                    filesystem_state <= READ_A_FILE;
                                end else if(cluster_sector_offset_t<rootdir_sectorcount_t) begin
                                    cluster_sector_offset_t = cluster_sector_offset_t + 8'd1;
                                    read_sector_no <= rootdir_sector_t + cluster_sector_offset_t;
                                end else begin
                                    filesystem_state <= DONE;   // cant find target file
                                end
            LS_ROOT_FAT32 : if(~search_fat) begin
                                if(file_found) begin
                                    curr_cluster_t = file_cluster;
                                    cluster_sector_offset_t = 8'h0;
                                    read_sector_no <= first_data_sector_no_t + cluster_size_t * curr_cluster_t + cluster_sector_offset_t;
                                    filesystem_state <= READ_A_FILE;
                                end else if(cluster_sector_offset_t<(cluster_size_t-1)) begin
                                    cluster_sector_offset_t = cluster_sector_offset_t + 8'd1;
                                    read_sector_no <= first_data_sector_no_t + cluster_size_t * curr_cluster_t + cluster_sector_offset_t;
                                end else begin   // read FAT to get next cluster
                                    search_fat <= 1'b1;
                                    cluster_sector_offset_t = 8'h0;
                                    read_sector_no <= first_fat_sector_no_t + curr_cluster_fat_no;
                                end
                            end else begin
                                search_fat <= 1'b0;
                                cluster_sector_offset_t = 8'h0;
                                if(target_cluster=='h0FFF_FFFF || target_cluster=='h0FFF_FFF8 || target_cluster=='hFFFF_FFFF || target_cluster<2) begin
                                    filesystem_state <= DONE;   // cant find target file
                                end else begin
                                    curr_cluster_t = target_cluster;
                                    read_sector_no <= first_data_sector_no_t + cluster_size_t * curr_cluster_t + cluster_sector_offset_t;
                                end
                            end
            READ_A_FILE  : 
                            if(~search_fat) begin
                                if(cluster_sector_offset_t<(cluster_size_t-1)) begin
                                    cluster_sector_offset_t = cluster_sector_offset_t + 8'd1;
                                    read_sector_no <= first_data_sector_no_t + cluster_size_t * curr_cluster_t + cluster_sector_offset_t;
                                end else begin   // read FAT to get next cluster
                                    search_fat <= 1'b1;
                                    cluster_sector_offset_t = 8'h0;
                                    read_sector_no <= first_fat_sector_no_t + (filesystem==FAT16 ? curr_cluster_fat_no_fat16 : curr_cluster_fat_no);
                                end
                            end else begin
                                search_fat <= 1'b0;
                                cluster_sector_offset_t = 8'h0;
                                if(filesystem==FAT16) begin
                                    if(target_cluster_fat16>=16'hFFF0 || target_cluster_fat16<16'h2) begin
                                        filesystem_state <= DONE;   // read to the end of file, done
                                    end else begin
                                        curr_cluster_t = {16'h0,target_cluster_fat16};
                                        read_sector_no <= first_data_sector_no_t + cluster_size_t * curr_cluster_t + cluster_sector_offset_t;
                                    end
                                end else begin
                                    if(target_cluster=='h0FFF_FFFF || target_cluster=='h0FFF_FFF8 || target_cluster=='hFFFF_FFFF || target_cluster<2) begin
                                        filesystem_state <= DONE;   // read to the end of file, done
                                    end else begin
                                        curr_cluster_t = target_cluster;
                                        read_sector_no <= first_data_sector_no_t + cluster_size_t * curr_cluster_t + cluster_sector_offset_t;
                                    end
                                end
                            end
            endcase
        end else begin
            case (filesystem_state)
                RESET         : filesystem_state  <= SEARCH_MBR;
                SEARCH_MBR    : read_start <= 1'b1;
                SEARCH_DBR    : read_start <= 1'b1;
                LS_ROOT_FAT16 : read_start <= 1'b1;
                LS_ROOT_FAT32 : read_start <= 1'b1;
                READ_A_FILE   : read_start <= 1'b1;
                //DONE          : $finish;
            endcase
        end
        
        cluster_size <= cluster_size_t;
        first_fat_sector_no <= first_fat_sector_no_t;
        first_data_sector_no <= first_data_sector_no_t;
        curr_cluster <= curr_cluster_t;
        cluster_sector_offset <= cluster_sector_offset_t;
        rootdir_sector <= rootdir_sector_t;
        rootdir_sectorcount <= rootdir_sectorcount_t;
    end


generate if (SIMULATE) begin
    always @ (posedge clk)
        if (read_done) begin
        end else begin
            if (filesystem_state == DONE) $finish;   // only for finish simulation, will be ignore when synthesize
        end
end endgenerate




//----------------------------------------------------------------------------------------------------------------------
// capture data in FAT table
//----------------------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn) begin
    if(~rstn) begin
        target_cluster <= 0;
        target_cluster_fat16 <= 16'h0;
    end else begin
        if(search_fat && rvalid) begin
            if(filesystem==FAT16) begin
                if(raddr[8:1]==curr_cluster_fat_offset_fat16)
                    target_cluster_fat16[8*raddr[0] +: 8] <= rdata;
            end else if(filesystem==FAT32) begin
                if(raddr[8:2]==curr_cluster_fat_offset)
                    target_cluster[8*raddr[1:0] +: 8] <= rdata;
            end
        end
    end
end


sd_reader #(
    .CLK_DIV    ( CLK_DIV        ),
    .SIMULATE   ( SIMULATE       )
) u_sd_reader (
    .rstn       ( rstn           ),
    .clk        ( clk            ),
    .sdclk      ( sdclk          ),
    .sdcmd      ( sdcmd          ),
    .sddat0     ( sddat0         ),
    .card_type  ( card_type      ),
    .card_stat  ( card_stat      ),
    .rstart     ( read_start     ),
    .rsector    ( read_sector_no ),
    .rbusy      (                ),
    .rdone      ( read_done      ),
    .outen      ( rvalid         ),
    .outaddr    ( raddr          ),
    .outbyte    ( rdata          )
);



//----------------------------------------------------------------------------------------------------------------------
// parse root dir
//----------------------------------------------------------------------------------------------------------------------
reg         fready = 1'b0;            // a file is find when fready = 1
assign list_en = fready;
reg  [ 7:0] fnamelen = 0;
reg  [15:0] fcluster = 0;
reg  [31:0] fsize = 0;
reg  [ 7:0] fname [0:51];
assign list_name = fname;
assign list_namelen = fnamelen;
reg  [ 7:0] file_name [0:51];
reg         isshort=1'b0, islongok=1'b0, islong=1'b0, longvalid=1'b0;
reg         isshort_t   , islongok_t   , islong_t   , longvalid_t   ;
reg  [ 5:0] longno = 6'h0 , longno_t;
reg  [ 7:0] lastchar = 8'h0;
reg  [ 7:0] fdtnamelen = 8'h0 , fdtnamelen_t;
reg  [ 7:0] sdtnamelen = 8'h0 , sdtnamelen_t;
reg  [ 7:0] file_namelen = 8'h0;
reg  [15:0] file_1st_cluster = 16'h0 , file_1st_cluster_t;
reg  [31:0] file_1st_size = 0 , file_1st_size_t;

initial for(i=0;i<52;i=i+1) begin file_name[i]=8'h0; fname[i]=8'h0; end

always @ (posedge clk or negedge rstn) begin
    if(~rstn) begin
        fready<=1'b0;  fnamelen<=8'h0; file_namelen<=8'h0;
        fcluster<=16'h0;  fsize<=0;
        for(i=0;i<52;i=i+1) begin file_name[i]<=8'h0; fname[i]<=8'h0; end
        
        {isshort, islongok, islong, longvalid} <= 4'b0000;
        
        longno     <= 6'h0;
        lastchar   <= 8'h0;
        fdtnamelen <= 8'h0;
        sdtnamelen <= 8'h0;
        file_1st_cluster <= 16'h0;
        file_1st_size <= 0;
    end else begin
        {isshort_t, islongok_t, islong_t, longvalid_t} = {isshort, islongok, islong, longvalid};
        longno_t = longno;
        fdtnamelen_t = fdtnamelen;
        sdtnamelen_t = sdtnamelen;
        file_1st_cluster_t = file_1st_cluster;
        file_1st_size_t = file_1st_size;
        
        fready<=1'b0;  fnamelen<=8'h0;
        // for(i=0;i<52;i=i+1) fname[i]<=8'h0;
        fcluster<=16'h0;  fsize<=0;

        if (filesystem_state == SEARCH_MBR) list_file_num <= 0;     // reset file number on start of search

        if( rvalid && (filesystem_state==LS_ROOT_FAT16||filesystem_state==LS_ROOT_FAT32) && ~search_fat ) begin
            // valid byte from root dir FAT
            // Root dir: https://www.p-dd.com/chapter3-page26.html
            // FAT32 tables: https://www.p-dd.com/chapter3-page23.html
            case (raddr[4:0])
                5'h1A : file_1st_cluster_t[ 0+:8] = rdata;
                5'h1B : file_1st_cluster_t[ 8+:8] = rdata;
                5'h1C :    file_1st_size_t[ 0+:8] = rdata;
                5'h1D :    file_1st_size_t[ 8+:8] = rdata;
                5'h1E :    file_1st_size_t[16+:8] = rdata;
                5'h1F :    file_1st_size_t[24+:8] = rdata;
            endcase
            
            if(raddr[4:0]==5'h0) begin
                {islongok_t, isshort_t} = 2'b00;
                fdtnamelen_t = 8'h0;  sdtnamelen_t=8'h0;
                
                if(rdata!=8'hE5 && rdata!=8'h2E && rdata!=8'h00) begin  // file name entry is valid
                    if(islong_t && longno_t==6'h1)
                        islongok_t = 1'b1;
                    else
                        isshort_t = 1'b1;
                end
                
                if(rdata[7]==1'b0 && ~islongok_t) begin
                    if(rdata[6]) begin
                        {islong_t,longvalid_t} = 2'b11;
                        longno_t = rdata[5:0];
                    end else if(islong_t) begin
                        if(longno_t>6'h1 && (rdata[5:0]+6'h1==longno_t) ) begin
                            islong_t = 1'b1;
                            longno_t = rdata[5:0];
                        end else begin
                            islong_t = 1'b0;
                        end
                    end else
                        islong_t = 1'b0;
                end else
                    islong_t = 1'b0;
            end else if(raddr[4:0]==5'hB) begin             // file attribute
                if(rdata!=8'h0F)                            // not LFN
                    islong_t = 1'b0;
                if(rdata!=8'h20 && rdata != 8'h21)          // not valid dir entry
                    {isshort_t, islongok_t} = 2'b00;
            end else if(raddr[4:0]==5'h1F) begin
                if(islongok_t && longvalid_t || isshort_t) begin
                    fready <= 1'b1;
                    fnamelen <= file_namelen;
                    list_file_num <= list_file_num + 1;     // increment file number
                    for(i=0;i<52;i=i+1) fname[i] <= (i<file_namelen) ? file_name[i] : 8'h0;
                    fcluster <= file_1st_cluster_t;
                    fsize <= file_1st_size_t;
                end
            end
            
            if(islong_t) begin
                if(raddr[4:0]>5'h0&&raddr[4:0]<5'hB || raddr[4:0]>=5'hE&&raddr[4:0]<5'h1A || raddr[4:0]>=5'h1C)begin
                    if(raddr[4:0]<5'hB ? raddr[0] : ~raddr[0]) begin
                        lastchar <= rdata;
                        fdtnamelen_t = fdtnamelen_t + 8'd1;
                    end else begin
                        //automatic logic [15:0] unicode = {rdata,lastchar};
                        if({rdata,lastchar} == 16'h0000) begin
                            file_namelen <= fdtnamelen_t-8'd1 + (longno_t-8'd1)*8'd13;
                        end else if({rdata,lastchar} != 16'hFFFF) begin
                            if(rdata == 8'h0) begin
//                                file_name[fdtnamelen_t-8'd1+(longno_t-8'd1)*8'd13] <= (lastchar>=8'h61 && lastchar<=8'h7A) ? lastchar&8'b11011111 : lastchar;     // convert to upper case
                                file_name[fdtnamelen_t-8'd1+(longno_t-8'd1)*8'd13] <= lastchar; 
                            end else begin
                                longvalid_t = 1'b0;
                            end
                        end
                    end
                end
            end 
            
            if(isshort_t) begin
                if(raddr[4:0]<5'h8) begin
                    if(rdata!=8'h20) begin
                        file_name[sdtnamelen_t] <= rdata;
                        sdtnamelen_t = sdtnamelen_t + 8'd1;
                    end
                end else if(raddr[4:0]<5'hB) begin
                    if(raddr[4:0]==5'h8) begin
                        file_name[sdtnamelen_t] <= 8'h2E;
                        sdtnamelen_t = sdtnamelen_t + 8'd1;
                    end
                    if(rdata!=8'h20) begin
                        file_name[sdtnamelen_t] <= rdata;
                        sdtnamelen_t = sdtnamelen_t + 8'd1;
                    end
                end else if(raddr[4:0]==5'hB) begin
                    file_namelen <= sdtnamelen_t;
                end
            end
            
        end
        
        {isshort, islongok, islong, longvalid} <= {isshort_t, islongok_t, islong_t, longvalid_t};
        longno <= longno_t;
        fdtnamelen <= fdtnamelen_t;
        sdtnamelen <= sdtnamelen_t;
        file_1st_cluster <= file_1st_cluster_t;
        file_1st_size <= file_1st_size_t;
    end
end



//----------------------------------------------------------------------------------------------------------------------
// compare target file number until we reach read_file
//----------------------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        file_found <= 1'b0;
        file_cluster <= 0;
        file_size <= 0;
    end else begin
        if (fready && op &&  list_file_num==read_file) begin
            file_found <= 1'b1;
            file_cluster <= fcluster;
            file_size <= fsize;
        end
    end



//----------------------------------------------------------------------------------------------------------------------
// output file content
//----------------------------------------------------------------------------------------------------------------------
reg [31:0] fptr = 0;

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        fptr <= 0;
        {outen,outbyte} <= 0;
    end else begin
        if(rvalid && filesystem_state==READ_A_FILE && ~search_fat && fptr<file_size) begin
            fptr <= fptr + 1;
            {outen,outbyte} <= {1'b1,rdata};
        end else
            {outen,outbyte} <= 0;
    end

endmodule
