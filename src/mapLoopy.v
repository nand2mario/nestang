// Mappers from Loopy's Power Pak source code
//
//

//Taken from Loopy's Power Pak mapper source mapVRC6.v
// change ain below to set VRC6 variant
module MAPVRC6(     //signal descriptions in powerpak.v
    input m2,
    input m2_n,
    input clk20,

    input reset,
    input nesprg_we,
    output nesprg_oe,
    input neschr_rd,
    input neschr_wr,
    input [15:0] prgain,
    input [13:0] chrain,
    input [7:0] nesprgdin,
    input [7:0] ramprgdin,
    output [7:0] nesprgdout,

    output [7:0] neschrdout,
    output neschr_oe,

    output chrram_we,
    output chrram_oe,
    output wram_oe,
    output wram_we,
    output prgram_we,
    output prgram_oe,
    output [18:10] ramchraout,
    output [18:13] ramprgaout,
    output irq,
    output ciram_ce,

    output exp6,
    
    input cfg_boot,
    input [18:12] cfg_chrmask,
    input [18:13] cfg_prgmask,
    input cfg_vertical,
    input cfg_fourscreen,
    input cfg_chrram,
	 
	 input ce,// add
	 output [15:0] snd_level,
	 input mapper26

);
    //wire [15:0] ain=prgain;                             //MAP18
    //wire [15:0] ain={prgain[15:2],prgain[0],prgain[1]}; //MAP1A
    wire [15:0] ain=mapper26 ? {prgain[15:2],prgain[0],prgain[1]} :  prgain; //MAP1A : MAP18

    reg [4:0] prgbank8;
    reg [5:0] prgbankC;
    reg [7:0] chrbank0, chrbank1, chrbank2, chrbank3, chrbank4, chrbank5, chrbank6, chrbank7;
    reg [1:0] mirror;
    reg [7:0] irqlatch;
    reg irqM,irqE,irqA;
    always@(posedge clk20) begin
        if(ce && nesprg_we) begin
            casex({ain[15:12],ain[1:0]})
                6'b1000xx:prgbank8<=nesprgdin;      //800x
                6'b1100xx:prgbankC<=nesprgdin;      //C00x
                6'b101111:mirror<=nesprgdin[3:2];   //B003
                6'b110100:chrbank0<=nesprgdin;      //D000
                6'b110101:chrbank1<=nesprgdin;      //D001
                6'b110110:chrbank2<=nesprgdin;      //D002
                6'b110111:chrbank3<=nesprgdin;      //D003
                6'b111000:chrbank4<=nesprgdin;      //E000
                6'b111001:chrbank5<=nesprgdin;      //E001
                6'b111010:chrbank6<=nesprgdin;      //E002
                6'b111011:chrbank7<=nesprgdin;      //E003
                6'b111100:irqlatch<=nesprgdin;      //F000
                6'b111101:{irqM,irqA}<={nesprgdin[2],nesprgdin[0]}; //F001
            endcase
        end
    end

    //bankswitch
    reg [18:13] prgbankin;
    reg [17:10] chrbank;
    always@* begin
        casex(prgain[15:13])
            3'b0xx:prgbankin=0;                         //sram
            3'b10x:prgbankin={prgbank8,prgain[13]};     //89AB
            3'b110:prgbankin=prgbankC;                  //CD
            default:prgbankin=6'b111111;                //EF
        endcase
        case(chrain[12:10])
            0:chrbank=chrbank0;
            1:chrbank=chrbank1;
            2:chrbank=chrbank2;
            3:chrbank=chrbank3;
            4:chrbank=chrbank4;
            5:chrbank=chrbank5;
            6:chrbank=chrbank6;
            7:chrbank=chrbank7;
        endcase
    end

    //IRQ
    reg [7:0] irqcnt;
    reg timeout;
    reg [6:0] scalar;
    reg [1:0] line;
    wire irqclk=irqM|(scalar==0);
    wire setE=nesprg_we & {ain[15:12],ain[1:0]}==6'b111101 & nesprgdin[1];
    always@(posedge clk20) begin
        if(setE) begin
            scalar<=113;
            line<=0;
            irqcnt<=irqlatch;
        end else if(ce && irqE) begin
            if(scalar!=0)
                scalar<=scalar-1;
            else begin
                scalar<=(~line[1])?113:112;
                line<=line[1]?0:line+1;
            end
            if(irqclk) begin
                if(irqcnt==255)     irqcnt<=irqlatch;
                else            irqcnt<=irqcnt+1;
            end
        end
    end
    always@(posedge clk20) begin
        if(reset) begin
            irqE<=0;
            timeout<=0;
        end else if (ce) begin
            if(nesprg_we & ain[15:12]==15 & ^ain[1:0]) //write Fxx1 or Fxx2
                timeout<=0;
            else if(irqclk & irqcnt==255)
                timeout<=1;

            if(nesprg_we & {ain[15:12],ain[1:0]}==6'b111101) //write Fxx1
                irqE<=nesprgdin[1];
            else if(nesprg_we & {ain[15:12],ain[1:0]}==6'b111110) //write Fxx2
                irqE<=irqA;
        end
    end

    assign irq=timeout & irqE;

//mirroring
    assign ramchraout[10]=!chrain[13] ? chrbank[10] : ((mirror==0 & chrain[10]) | (mirror==1 & chrain[11]) | (mirror==3));
    assign ramchraout[11]=chrbank[11];
    assign ciram_ce=chrain[13];

//rom size mask
    assign ramprgaout[18:13]=prgbankin[18:13] & cfg_prgmask;
    assign ramchraout[18:12]={1'b0,chrbank[17:12]} & cfg_chrmask;

//ram control
    assign chrram_we=neschr_wr & !chrain[13] & cfg_chrram;
    assign chrram_oe=neschr_rd & !chrain[13];

    assign neschr_oe=0;
    assign neschrdout=8'bx;

    assign wram_oe=m2_n & ~nesprg_we & prgain[15:13]=='b011;
    assign wram_we=m2_n &  nesprg_we & prgain[15:13]=='b011;
    
    assign prgram_we=0;
    assign prgram_oe=~cfg_boot & m2_n & ~nesprg_we & prgain[15];

    wire config_rd = 0;
    //gamegenie gg(m2, reset, nesprg_we, prgain, nesprgdin, ramprgdin, nesprgdout, config_rd);
    assign nesprgdout=8'b0;
    assign nesprg_oe=wram_oe | prgram_oe | config_rd;

//sound
//    wire [5:0] vrc6_out;
    assign exp6 = 0;
    wire [3:0] vrc6sq1_out;
    wire [3:0] vrc6sq2_out;
    wire [4:0] vrc6saw_out;
    vrc6sound snd(clk20, ce, reset, nesprg_we, ain, nesprgdin, vrc6sq1_out, vrc6sq2_out, vrc6saw_out);
//    vrc6sound snd(m2, reset, nesprg_we, ain, nesprgdin, vrc6_out);
//    pdm #(6) pdm_mod(clk20, vrc6_out, exp6);

    ApuLookupTable lookup(clk20, 
                      {4'b0, vrc6sq1_out}+
							 {4'b0, vrc6sq2_out},
							 {3'b0, vrc6saw_out},
                      snd_level);

endmodule


module vrc6sound(
//    input m2,
    input clk,
    input ce,
    input reset,
    input wr,
    input [15:0] ain,
    input [7:0] din,
//    output [5:0] out        //range=0..0x3D
    output [3:0] outSq1,       //range=0..0x0F
    output [3:0] outSq2,       //range=0..0x0F
    output [4:0] outSaw        //range=0..0x1F
);
    reg mode0, mode1;
    reg [3:0] vol0, vol1;
    reg [5:0] vol2;
    reg [2:0] duty0, duty1;
    reg [11:0] freq0, freq1, freq2;
    reg [11:0] div0, div1;
    reg [12:0] div2;
    reg en0, en1, en2;

    reg [3:0] duty0cnt, duty1cnt;
    reg [2:0] duty2cnt;
    reg [7:0] acc;

    always@(posedge clk, posedge reset) begin
        if(reset) begin
            en0<=0;
            en1<=0;
            en2<=0;
        end else if(ce) begin
            if(wr) begin
                case(ain)
                    16'h9000: {mode0, duty0, vol0}<=din;
                    16'h9001: freq0[7:0]<=din;
                    16'h9002: {en0, freq0[11:8]} <= {din[7],din[3:0]};

                    16'hA000: {mode1, duty1, vol1}<=din;
                    16'hA001: freq1[7:0]<=din;
                    16'hA002: {en1, freq1[11:8]} <= {din[7],din[3:0]};

                    16'hB000: vol2<=din[5:0];
                    16'hB001: freq2[7:0]<=din;
                    16'hB002: {en2, freq2[11:8]}<={din[7],din[3:0]};
                endcase
            end
            if(en0) begin
                if(div0!=0)
                    div0<=div0-1;
                else begin
                    div0<=freq0;
                    duty0cnt<=duty0cnt+1;
                end
            end
            if(en1) begin
                if(div1!=0)
                    div1<=div1-1;
                else begin
                    div1<=freq1;
                    duty1cnt<=duty1cnt+1;
                end
            end
            if(en2) begin
                if(div2!=0)
                    div2<=div2-1;
                else begin
                    div2<={freq2,1'b1};
                    if(duty2cnt==6) begin
                        duty2cnt<=0;
                        acc<=0;
                    end else begin
                        duty2cnt<=duty2cnt+1;
                        acc<=acc+vol2;
                    end
                end
            end
        end
    end

    wire [4:0] duty0pos=duty0cnt+{1'b1,~duty0};
    wire [4:0] duty1pos=duty1cnt+{1'b1,~duty1};
    wire [3:0] ch0=((~duty0pos[4]|mode0)&en0)?vol0:0;
    wire [3:0] ch1=((~duty1pos[4]|mode1)&en1)?vol1:0;
    wire [4:0] ch2=en2?acc[7:3]:0;
//    assign out=ch0+ch1+ch2;
    assign outSq1=ch0;
    assign outSq2=ch1;
    assign outSaw=ch2;

endmodule

//Taken from Loopy's Power Pak mapper source mapN106.v
//fixme- sound ram is supposed to be readable (does this affect any games?)
module MAPN106(     //signal descriptions in powerpak.v
    input m2,
    input m2_n,
    input clk20,

    input reset,
    input nesprg_we,
    output nesprg_oe,
    input neschr_rd,
    input neschr_wr,
    input [15:0] prgain,
    input [13:0] chrain,
    input [7:0] nesprgdin,
    input [7:0] ramprgdin,
    output reg [7:0] nesprgdout,

    output [7:0] neschrdout,
    output neschr_oe,

    output reg chrram_we,
    output reg chrram_oe,
    output wram_oe,
    output wram_we,
    output prgram_we,
    output prgram_oe,
    output reg [18:10] ramchraout,
    output [18:13] ramprgaout,
    output irq,
    output reg ciram_ce,
    output exp6,
    
    input cfg_boot,
    input [18:12] cfg_chrmask,
    input [18:13] cfg_prgmask,
    input cfg_vertical,
    input cfg_fourscreen,
    input cfg_chrram,
	 
	 input ce,// add
	 output [15:0] snd_level
);

    reg [1:0] chr_en;
    reg [5:0] prg89,prgAB,prgCD;
    reg [7:0] chr0,chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr10,chr11,chr12,chr13;
    reg mirror;
    always@(posedge clk20) begin
        if(ce && nesprg_we)
        case(prgain[15:11])
            5'b10000: chr0<=nesprgdin;              //8000
            5'b10001: chr1<=nesprgdin;
            5'b10010: chr2<=nesprgdin;              //9000
            5'b10011: chr3<=nesprgdin;
            5'b10100: chr4<=nesprgdin;              //A000
            5'b10101: chr5<=nesprgdin;
            5'b10110: chr6<=nesprgdin;              //B000
            5'b10111: chr7<=nesprgdin;
            5'b11000: chr10<=nesprgdin;             //C000
            5'b11001: chr11<=nesprgdin; 
            5'b11010: chr12<=nesprgdin;             //D000
            5'b11011: chr13<=nesprgdin;
            5'b11100: {mirror,prg89}<=nesprgdin;    //E000
            5'b11101: {chr_en,prgAB}<=nesprgdin;    //E800
            5'b11110: prgCD<=nesprgdin;             //F000
            //5'b11111:                             //F800 (sound)
        endcase
    end

    //IRQ
    reg [15:0] count;
    wire [15:0] count_next=count+1;
    wire countup=count[15] & ~&count[14:0];
    reg timeout;
    assign irq=timeout;
    always@(posedge clk20) begin
	   if (ce) begin
        if(prgain[15:12]==4'b0101)              timeout<=0;
        else if(count==16'hFFFF)                timeout<=1;
        if(nesprg_we & prgain[15:11]==5'b01010) count[7:0]<=nesprgdin;
        else if(countup)                        count[7:0]<=count_next[7:0];
        if(nesprg_we & prgain[15:11]==5'b01011) count[15:8]<=nesprgdin;
        else if(countup)                        count[15:8]<=count_next[15:8];          
		end
    end

    //PRG bank
    reg [18:13] prgbankin;
    always@* begin
        case(prgain[14:13])
            0:prgbankin=prg89;
            1:prgbankin=prgAB;
            2:prgbankin=prgCD;
            3:prgbankin=6'b111111;
        endcase
    end
    assign ramprgaout[18:13]=prgbankin[18:13] & cfg_prgmask & {4'b1111,{2{prgain[15]}}};

    //CHR control
    reg chrram;
    reg [17:10] chrbank;
    always@* begin
        case(chrain[13:10])
            0:chrbank=chr0;
            1:chrbank=chr1;
            2:chrbank=chr2;
            3:chrbank=chr3;
            4:chrbank=chr4;
            5:chrbank=chr5;
            6:chrbank=chr6;
            7:chrbank=chr7;
            8,12:chrbank=chr10;
            9,13:chrbank=chr11;
            10,14:chrbank=chr12;
            11,15:chrbank=chr13;
        endcase
        chrram=(~(chrain[12]?chr_en[1]:chr_en[0]))&(&chrbank[17:15]);   //ram/rom select
        if(!chrain[13]) begin
            ciram_ce=0;
            chrram_oe=neschr_rd;
            chrram_we=neschr_wr & chrram;
            ramchraout[10]=chrbank[10];
        end else begin
            ciram_ce=&chrbank[17:15] | mirror;
            chrram_oe=~ciram_ce & neschr_rd;
            chrram_we=~ciram_ce & neschr_wr & chrram;
            ramchraout[10]=mirror?chrain[10]:chrbank[10];
        end
        ramchraout[11]=chrbank[11];
        ramchraout[17:12]=chrbank[17:12] & cfg_chrmask[17:12];
        ramchraout[18]=chrram;
    end

    assign wram_oe=m2_n & ~nesprg_we & prgain[15:13]==3'b011;
    assign wram_we=m2_n &  nesprg_we & prgain[15:13]==3'b011;

    assign prgram_we=0;
    assign prgram_oe= ~cfg_boot & m2_n & ~nesprg_we & prgain[15];

    wire config_rd = 0;
    //wire [7:0] gg_out;
    //gamegenie gg(m2, reset, nesprg_we, prgain, nesprgdin, ramprgdin, gg_out, config_rd);

    //PRG data out
    wire counter_oe = m2_n & ~nesprg_we & prgain[15:12]=='b0101;
    always @* case(prgain[15:11])
        5'b01010: nesprgdout = count[7:0];
        5'b01011: nesprgdout = count[15:8];
        default: nesprgdout = nesprgdin;
    endcase

    assign nesprg_oe=wram_oe | prgram_oe | counter_oe | config_rd;

    assign neschr_oe=0;
    assign neschrdout=0;

    //sound
    wire [10:0] n106_out;
    wire [9:0] saturated=n106_out[9:0] | {10{n106_out[10]}};    //this is still too quiet for the suggested 47k resistor, but more clipping will make some games sound bad
    namco106_sound n106(ce, clk20, reset, nesprg_we, prgain, nesprgdin, n106_out);
    //pdm #(10) pdm_mod(clk20, saturated, exp6);
	 assign snd_level = {6'b0, saturated};

endmodule

module namco106_sound(
    input m2,
    input clk20,
    input reset,
    input wr,
    input [15:0] ain,
    input [7:0] din,
    output reg [10:0] out       //range is 0..0x708
);
    reg carry;
    reg autoinc;
    reg [6:0] ram_ain;
    reg [6:0] ram_aout;
    wire [7:0] ram_dout;
    reg [2:0] ch;
    reg [7:0] cnt_L[7:0];
    reg [7:0] cnt_M[7:0];
    reg [1:0] cnt_H[7:0];
    wire [2:0] sum_H=cnt_H[ch]+ram_dout[1:0]+carry;
    reg [4:0] sample_pos[7:0];
    reg [2:0] cycle;
    reg [3:0] sample;
    wire [7:0] chan_out=sample*ram_dout[3:0];   //sample*vol
    reg [10:0] out_acc;
    wire [10:0] sum=out_acc+chan_out;
    reg addr_lsb;
    wire [7:0] sample_addr=ram_dout+sample_pos[ch];

    //ram in
    always@(posedge clk20) begin
	   if (m2) begin
        if(wr & ain[15:11]==5'b11111)           //F800..FFFF
            {autoinc,ram_ain}<=din;
        else if(ain[15:11]==5'b01001 & autoinc) //4800..4FFF
            ram_ain<=ram_ain+1;     
		end
    end

    //mixer FSM
    always@* case(cycle)
        0: ram_aout={1'b1,ch,3'd0};     //freq[7:0]
        1: ram_aout={1'b1,ch,3'd2};     //freq[15:8]
        2: ram_aout={1'b1,ch,3'd4};     //length, freq[17:16]
        3: ram_aout={1'b1,ch,3'd6};     //address
        4: ram_aout=sample_addr[7:1];   //sample address
        5: ram_aout={1'b1,ch,3'd7};     //volume
        default: ram_aout=7'bXXXXXXX;
    endcase
    reg [3:0] count45,cnt45;
    always@(posedge clk20)
		if (m2) begin
        count45<=(count45==14)?0:count45+1;
		end
    always@(posedge clk20) begin
        cnt45<=count45;
        if(cnt45[1:0]==0) cycle<=0;             // this gives 45 21.4M clocks per channel
        else if(cycle!=7) cycle<=cycle+1;
        case(cycle)
            1: {carry, cnt_L[ch]}<=cnt_L[ch][7:0]+ram_dout;
            2: {carry, cnt_M[ch]}<=cnt_M[ch][7:0]+ram_dout+carry;
            3: begin
                cnt_H[ch]<=sum_H[1:0];
                if(sum_H[2])
                    sample_pos[ch]<=(sample_pos[ch]=={ram_dout[4:2]^3'b111,2'b11})?0:(sample_pos[ch]+1);
            end
            4: addr_lsb<=sample_addr[0];
            5: sample<=addr_lsb?ram_dout[7:4]:ram_dout[3:0];
            6: begin
                if(ch==7) begin
                    ch<=ram_dout[6:4]^7;
                    out_acc<=0;
                    out<=sum;
                end else begin
                    ch<=ch+1;
                    out_acc<=sum;
                end
            end
        endcase
    end

    reg [7:0] expansion_ram[0:1023]; // Block RAM, otherwise we need to time multiplex..

endmodule

