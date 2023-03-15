
//--------------------------------------------------------------------------------------------------------
// Module  : sdcmd_ctrl
// Type    : synthesizable, IP's sub module
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: sdcmd signal control,
//           instantiated by sd_reader
//--------------------------------------------------------------------------------------------------------

module sdcmd_ctrl (
    input  wire         rstn,
    input  wire         clk,
    // SDcard signals (sdclk and sdcmd)
    output reg          sdclk,
    inout               sdcmd,
    // config clk freq
    input  wire  [15:0] clkdiv,
    // user input signal
    input  wire         start,
    input  wire  [15:0] precnt,
    input  wire  [ 5:0] cmd,
    input  wire  [31:0] arg,
    // user output signal
    output reg          busy,
    output reg          done,
    output reg          timeout,
    output reg          syntaxe,
    output wire  [31:0] resparg
);

initial {busy, done, timeout, syntaxe} = '0;
initial sdclk = '0;

localparam [7:0] TIMEOUT = 8'd250;

reg sdcmdoe  = 1'b0;
reg sdcmdout = 1'b1;

// sdcmd tri-state driver
assign sdcmd = sdcmdoe ? sdcmdout : 1'bz;
wire sdcmdin = sdcmdoe ? 1'b1 : sdcmd;

function automatic logic [6:0] CalcCrc7(input logic [6:0] crc, input logic inbit);
    return {crc[5:0],crc[6]^inbit} ^ {3'b0,crc[6]^inbit,3'b0};
endfunction

reg  [ 5:0] req_cmd = '0;    // request[45:40]
reg  [31:0] req_arg = '0;    // request[39: 8]
reg  [ 6:0] req_crc = '0;    // request[ 7: 1]
wire [51:0] request = {6'b111101, req_cmd, req_arg, req_crc, 1'b1};

struct packed {
    logic        st;
    logic [ 5:0] cmd;
    logic [31:0] arg;
} response = '0;

assign resparg = response.arg;

reg  [17:0] clkdivr = '1;
reg  [17:0] clkcnt  = '0;
reg  [15:0] cnt1 = '0;
reg  [ 5:0] cnt2 = '1;
reg  [ 7:0] cnt3 = '0;
reg  [ 7:0] cnt4 = '1;


always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {busy, done, timeout, syntaxe} <= '0;
        sdclk <= 1'b0;
        {sdcmdoe, sdcmdout} <= 2'b01;
        {req_cmd, req_arg, req_crc} <= '0;
        response <= '0;
        clkdivr <= '1;
        clkcnt  <= '0;
        cnt1 <= '0;
        cnt2 <= '1;
        cnt3 <= '0;
        cnt4 <= '1;
    end else begin
        {done, timeout, syntaxe} <= '0;
        
        clkcnt <= ( clkcnt < {clkdivr[16:0],1'b1} ) ? clkcnt+18'd1 : '0;
        
        if     (clkcnt == '0)
            clkdivr <= {2'h0, clkdiv} + 18'd1;
        
        if(clkcnt == clkdivr)
            sdclk <= 1'b0;
        else if(clkcnt == {clkdivr[16:0],1'b1} )
            sdclk <= 1'b1;
        
        if(~busy) begin
            if(start) busy <= '1;
            req_cmd <= cmd;
            req_arg <= arg;
            req_crc <= '0;
            cnt1 <= precnt;
            cnt2 <= 6'd51;
            cnt3 <= TIMEOUT;
            cnt4 <= 8'd134;
        end else if(done) begin
            busy <= '0;
        end else if( clkcnt == clkdivr) begin
            {sdcmdoe, sdcmdout} <= 2'b01;
            if     (cnt1 != '0) begin
                cnt1 <= cnt1 - 16'd1;
            end else if(cnt2 != '1) begin
                cnt2 <= cnt2 - 6'd1;
                {sdcmdoe, sdcmdout} <= {1'b1, request[cnt2]};
                if(cnt2>=8 && cnt2<48) req_crc <= CalcCrc7(req_crc, request[cnt2]);
            end
        end else if( clkcnt == {clkdivr[16:0],1'b1} && cnt1=='0 && cnt2=='1 ) begin
            if(cnt3 != '0) begin
                cnt3 <= cnt3 - 8'd1;
                if(~sdcmdin)
                    cnt3 <= '0;
                else if(cnt3 == 8'd1)
                    {done, timeout, syntaxe} <= 3'b110;
            end else if(cnt4 != '1) begin
                cnt4 <= cnt4 - 8'd1;
                if(cnt4 >= 8'd96)
                    response <= {response[37:0], sdcmdin};
                if(cnt4 == '0) begin
                    {done, timeout} <= 2'b10;
                    syntaxe <= response.st || ((response.cmd!=req_cmd) && (response.cmd!='1) && (response.cmd!='0));
                end
            end
        end
    end

endmodule
