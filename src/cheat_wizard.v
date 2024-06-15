module cheat_wizard(
                        input wire i_clk,
                        input wire i_reset_n,
                        // Cheats
                        input wire i_cheats_enabled,
                        input wire i_cheats_loaded,
                        input wire [23:0] i_sram_address,
                        input wire [7:0] i_sram_data,
                        output wire o_cheat_stb,
                        output wire [7:0] o_sram_data,
                        // Wishbone slave
                        input wire i_wb_cyc,
                        input wire i_wb_stb,
                        input wire i_wb_we,
                        input wire i_wb_err,
                        input wire [1:0] i_wb_addr,
                        input wire [128:0] i_wb_idata,
                        output wire o_wb_ack,
                        output wire o_wb_stall,
                        output wire o_wb_err
                    );
// Wishbone Cheat Data FSM
reg [7:0] cheats_nr;
reg [7:0] cheats_nr_last;
reg cheats_compare_enabled_temp;
reg [16:0] cheats_address_temp;
reg [7:0] cheat_compare_value_temp;
reg [7:0] cheats_replace_value_temp;
reg cheats_compare_enabled[3:0];
reg [16:0] cheats_address[3:0];
reg [7:0] cheat_compare_value[3:0];
reg [7:0] cheats_replace_value[3:0];
reg [1:0] cheat_data_ix;

// Cheats stuff
wire cheat_compare_stb_0;
wire cheat_compare_stb_1;
wire cheat_compare_stb_2;
wire cheat_compare_stb_3;
wire cheats_nr_stb;

assign cheats_nr_stb = (cheats_nr_last != cheats_nr);

assign cheat_compare_stb_0 = (~cheats_compare_enabled[0] ? 1'b1 : (i_sram_data == cheat_compare_value[0]));
assign cheat_compare_stb_1 = (~cheats_compare_enabled[1] ? 1'b1 : (i_sram_data == cheat_compare_value[1]));
assign cheat_compare_stb_2 = (~cheats_compare_enabled[2] ? 1'b1 : (i_sram_data == cheat_compare_value[2]));
assign cheat_compare_stb_3 = (~cheats_compare_enabled[3] ? 1'b1 : (i_sram_data == cheat_compare_value[3]));
assign o_cheat_stb = ( (i_cheats_enabled)&&(i_cheats_loaded)&&(i_sram_address == cheats_address[0])&&(cheat_compare_stb_0) ) ||
                     ( (i_cheats_enabled)&&(i_cheats_loaded)&&(i_sram_address == cheats_address[1])&&(cheat_compare_stb_1) ) ||
                     ( (i_cheats_enabled)&&(i_cheats_loaded)&&(i_sram_address == cheats_address[2])&&(cheat_compare_stb_2) ) ||
                     ( (i_cheats_enabled)&&(i_cheats_loaded)&&(i_sram_address == cheats_address[3])&&(cheat_compare_stb_3) );
assign o_sram_data = !o_cheat_stb        ? i_sram_data :
                     cheat_compare_stb_0 ? cheats_replace_value[0] : 
                     cheat_compare_stb_1 ? cheats_replace_value[1] : 
                     cheat_compare_stb_2 ? cheats_replace_value[2] :
                     cheat_compare_stb_3 ? cheats_replace_value[3] :
                     8'h00;


// Wishbone stuff
reg wb_ack;
reg wb_err;
reg [128:0] wb_odata;
reg wb_stall;

initial wb_ack = 0;
initial wb_err = 0;
initial wb_odata = 0;
initial wb_stall= 0;

always @(posedge i_clk) begin
    if((~i_reset_n)||(i_wb_err)) begin
    end else begin
        // cheats_data
        if(i_reset_n) begin
            if((i_wb_stb)&&(i_wb_we)&&(i_wb_we)&&((i_wb_addr == 2'h01))&&(i_wb_we)&&(~o_wb_err)) begin
                wb_odata <= i_wb_idata;
                wb_stall <= 1'b1;
                cheat_data_ix <= 2'b00;
                
                cheats_compare_enabled[i_wb_idata[111:104] - 1'b1] <= i_wb_idata[96];
                cheats_address[i_wb_idata[111:104] - 1'b1] <= i_wb_idata[79:64];
                cheat_compare_value[i_wb_idata[111:104] - 1'b1] <= i_wb_idata[39:32];
                cheats_replace_value[i_wb_idata[111:104] - 1'b1] <= i_wb_idata[7:0];
                
            end else 
                wb_stall <= 1'b0;
        end
    end
end

assign o_wb_ack = i_wb_stb;
assign o_wb_stall = wb_stall;
assign o_wb_err = wb_err;

//
// Formal methods
//
`ifdef FORMAL
    // f_past_valid
	reg	f_past_valid;
	initial	f_past_valid = 1'b0;
	initial assert(!f_past_valid);
	always @(posedge i_clk)
		f_past_valid = 1'b1;

    // BMC Assumptions
    always @(posedge i_clk)
        if((f_past_valid)&&((~$past(i_reset_n))||(~$past(i_wb_err)))) begin
            assume((i_wb_addr == 2'h01)||(i_wb_addr == 2'h02)||(i_wb_addr == 2'h03));
            assume($stable(i_wb_addr));
            assume($stable(i_wb_idata));
        end

    always @(posedge i_clk)
        if((f_past_valid)&&((~$past(i_reset_n))||(~$past(i_wb_err))))
            if(i_wb_addr == 2'h01)
                assume(i_wb_idata == 128'h00000000_00000000_00000000_00000001);
    
    always @(posedge i_clk)
        if((f_past_valid)&&((~$past(i_reset_n))||(~$past(i_wb_err))))
            if(i_wb_addr == 2'h02)
                assume(i_wb_idata == 128'h00000000_00000000_00000000_00000001);

    always @(posedge i_clk)
        if((f_past_valid)&&((~$past(i_reset_n))||(~$past(i_wb_err))))
            if(i_wb_addr == 2'h03)
                assume(i_wb_idata == 128'h00000001_000023A2_000000D6_00000024);

    always @(posedge i_clk)
        if((f_past_valid)&&(~$past(f_past_valid))) begin
            assume(i_wb_stb);
            assume(i_wb_we);
            assume(~i_wb_err);
            assume(~i_wb_cyc);
        end else begin
            assume(~i_wb_stb);
            assume(~i_wb_we);
            assume(~i_wb_err);
            assume(i_wb_cyc);
        end

    always @(posedge i_clk)
        if((f_past_valid)&&($past(f_past_valid))&&((~$past(i_reset_n))))
            if($past(i_cheats_enabled))
                assume(i_cheats_enabled == $past(i_cheats_enabled));
    always @(posedge i_clk)
        if((f_past_valid)&&($past(f_past_valid))&&((~$past(i_reset_n))))
            if($past(i_cheats_loaded))
                assume(i_cheats_loaded == $past(i_cheats_loaded));
        

    // BMC Assertions
    always @(posedge i_clk)
        if((f_past_valid)&&($past(f_past_valid))&&((~$past(i_reset_n))||(~$past(i_wb_err)))) begin
            assert(wb_err == 1'b0);
        end

    // Cover
    always @(posedge i_clk)
        if((f_past_valid)&&(i_reset_n))
            if((i_wb_stb)&&(i_wb_we)&&(~i_wb_err)&&(~o_wb_stall)&&(i_wb_addr == 2'h03)&&(i_wb_idata == 128'h00000001_000023A2_000000D6_00000024))
                if((i_cheats_enabled)&&(i_cheats_loaded)&&(i_sram_address == 23'h00_23A2)&&(i_sram_data == 8'hD6))
                    cover(o_cheat_stb);

    // Contract
    always @(posedge i_clk)
        if((f_past_valid)&&($past(i_reset_n))&&(i_reset_n)&&(($past(i_wb_stb))&&($past(i_wb_cyc))&&($past(i_wb_we))&&(~$past(i_wb_err))&&($past(i_wb_addr) == 1))) begin
            assert(wb_odata == i_wb_idata);
        end

    always @(posedge i_clk)
        if((f_past_valid)&&($past(f_past_valid))&&((~$past(i_reset_n))||(~$past(i_wb_err))))
            if(i_wb_stb)
                assert(o_wb_ack);

    always @(posedge i_clk)
        if((f_past_valid)&&($past(f_past_valid))&&((~$past(i_reset_n))||(~$past(i_wb_err))))
            assert(cheat_compare_stb_0 == (~cheats_compare_enabled[0] ? 1'b1 : (i_sram_data == cheat_compare_value[0])));
    
    always @(posedge i_clk)
        if((f_past_valid)&&($past(f_past_valid))&&((~$past(i_reset_n))||(~$past(i_wb_err))))
            if((cheat_compare_stb_0)&&(~cheat_compare_stb_1)&&(~cheat_compare_stb_2)&&(~cheat_compare_stb_3))
                assert(o_cheat_stb == ( (i_cheats_enabled)&&(i_cheats_loaded)&&(i_sram_address == cheats_address[0])&&(cheat_compare_stb_0) ));
    
    always @(posedge i_clk)
        if((f_past_valid)&&($past(f_past_valid))&&((~$past(i_reset_n))||(~$past(i_wb_err))))
            if((i_cheats_enabled)&&(i_cheats_loaded)&&(i_sram_address == cheats_address[0])&&(i_sram_data == cheat_compare_value[0]))
                if((cheat_compare_stb_0)&&(~cheat_compare_stb_1)&&(~cheat_compare_stb_2)&&(~cheat_compare_stb_3)) begin
                    assert(o_sram_data == cheats_replace_value[0]);
                end
    
    // Induction assumptions

    // Induction assertions

`endif // FORMAL

endmodule