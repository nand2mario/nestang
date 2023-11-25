////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	ClockDivider_27Mto60Hz.cpp
//
// Project:	Verilog Tutorial Example file
//
// Purpose:	Main Verilator simulation script for the ClockDivider_27Mto60Hz design
//
//	In this script, we toggle the input, and (hopefully) watch the output
//	toggle.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Written and distributed by Gisselquist Technology, LLC
//
// This program is hereby granted to the public domain.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.
//
////////////////////////////////////////////////////////////////////////////////
//
//
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "VClockDivider_27Mto60Hz.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <math.h>
// random
#include <random>


#define MASTER_CLOCK_FREQUENCY      27000000
#define OUTPUT_UPDATE_FREQUENCY     120
#define TIMESCALE_NS                10
#define BITS_TO_SHIFT_COUNTER       19

#define PRINT_LATCH_STATE

void tick(int tick_count, VClockDivider_27Mto60Hz *tb, VerilatedVcdC* tfp){
    // The following eval () looks
    // redundant ... many of hours
    // of debugging reveal its not
    tb->eval();
    // dump 2nS before the tick
    if(tfp)
        tfp->dump(tick_count * TIMESCALE_NS - (TIMESCALE_NS / 2 - 1));
    tb->i_clk = 1;
    tb->eval();
    // tick every 10nS
    if(tfp)
        tfp->dump(tick_count * TIMESCALE_NS);
    tb->i_clk= 0;
    tb->eval();
    // trailing edge dump
    if(tfp){
        tfp->dump(tick_count * TIMESCALE_NS + (TIMESCALE_NS / 2));
        tfp->flush();
    }
}

int main(int argc, char **argv) {
    int last_led;
    unsigned tick_count = 0;

    // Call commandArgs
    Verilated::commandArgs(argc, argv);

    // Instantiate design
    VClockDivider_27Mto60Hz *tb = new VClockDivider_27Mto60Hz;

    // Generate a trace
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    tb->trace(tfp, 99);
    tfp ->open("ClockDivider_27Mto60Hztrace.vcd ");

    // 
    static uint8_t joystick_serial;
    static uint8_t joystick_serial_bit;
    std::random_device dev;
    std::mt19937 rng(dev());
    std::uniform_int_distribution<std::mt19937::result_type> dist255(0,255); // distribution in range [0, 255]
    joystick_serial = dist255(rng);

 

    tb->i_clk = 0x00;
    tb->i_rst = 0x00;

    printf("[  |  |  |  ] 0/100\n...\n");

    for(int k=0; k<(1<<BITS_TO_SHIFT_COUNTER); k++){
        // Tick()
        tick(++tick_count, tb, tfp);

        // printf("Output state\n\tk= %7d | i_clk= %d | o_clk= %d\n", 
        //     k, tb->i_clk, tb->o_clk);

        if (k == (int)((1<<BITS_TO_SHIFT_COUNTER)/4))
            printf("[##|  |  |  ] 25/100\n...\n");
        if (k == (int)((1<<BITS_TO_SHIFT_COUNTER)/2))
            printf("[##|##|  |  ] 50/100\n...\n");
        if (k == (int)(3*((1<<BITS_TO_SHIFT_COUNTER)/4)))
            printf("[##|##|##|  ] 75/100\n...\n");
    }
    printf("\r[##|##|##|##] DONE!\n");
}
