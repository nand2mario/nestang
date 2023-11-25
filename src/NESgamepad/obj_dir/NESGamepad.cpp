////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	NESGamepad.cpp
//
// Project:	Verilog Tutorial Example file
//
// Purpose:	Main Verilator simulation script for the NESGamepad design
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
#include "VNESGamepad.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <math.h>
// random
#include <random>


#define MASTER_CLOCK_FREQUENCY      27000000
#define OUTPUT_UPDATE_FREQUENCY     120
#define SERIAL_DATA_COUNTER         2 * 8191
#define NUMBER_OF_STATES (10)
#define LATCH_STATE (1)
#define READ_STATE (1 << (NUMBER_OF_STATES-1))

#define PRINT_LATCH_STATE

void tick(int tick_count, VNESGamepad *tb, VerilatedVcdC* tfp){
    // The following eval () looks
    // redundant ... many of hours
    // of debugging reveal its not
    tb->eval();
    // dump 2nS before the tick
    if(tfp)
        tfp->dump(tick_count * 10 - 2);
    tb->i_clk = 1;
    tb->eval();
    // tick every 10nS
    if(tfp)
        tfp->dump(tick_count * 10);
    tb->i_clk= 0;
    tb->eval();
    // trailing edge dump
    if(tfp){
        tfp->dump(tick_count * 10 + 5);
        tfp->flush();
    }
}

int main(int argc, char **argv) {
    int last_led;
    unsigned tick_count = 0;

    // Call commandArgs
    Verilated::commandArgs(argc, argv);

    // Instantiate design
    VNESGamepad *tb = new VNESGamepad;

    // Generate a trace
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    tb->trace(tfp, 99);
    tfp ->open("NESGamepadtrace.vcd ");

    // 
    static uint8_t joystick_serial;
    static uint8_t joystick_serial_bit;
    std::random_device dev;
    std::mt19937 rng(dev());
    std::uniform_int_distribution<std::mt19937::result_type> dist255(0,255); // distribution in range [0, 255]
    joystick_serial = dist255(rng);

 

    tb->i_clk = 0x00;
    tb->data_clock = 0x00;
    tb->serial_data = 0x01;
    tb->i_rst = 0x00;
    static int serial_data_counter = SERIAL_DATA_COUNTER;
    static int FSM_state = LATCH_STATE;
    static bool create_new_data_value = false;
    #ifdef PRINT_LATCH_STATE
    static bool latch_info_was_printed = false;
    #endif
    for(int k=0; k<(1<<19); k++){
        // Tick()
        tick(++tick_count, tb, tfp);

        // 
        // if(tb->i_clk <= 128)
        //     tb->i_rst = 0x01;
        // else
        //     tb->i_rst = 0x00;

        //
        // printf("k= %7d | i_clk= %d | o_clk= %d | i_rst= %u | data_latch= %d | o_latch_counter= %d | data= %d | o_cycle_stage: %d | button_state= %d\n", 
        // k, tb->i_clk, tb->o_clk, tb->i_rst, tb->data_latch, tb->o_latch_counter, joystick_serial, tb->o_cycle_stage, tb->button_state);
        
        serial_data_counter--;
        if(!serial_data_counter && !tb->data_latch){
            // FSM_state
            FSM_state = FSM_state << 1;
            if(FSM_state > READ_STATE)
                FSM_state = LATCH_STATE;
            
            serial_data_counter = SERIAL_DATA_COUNTER;
            // tb->serial_data = (tb->serial_data == 0x00) ? 0x01 : 0x00;

            if(FSM_state != LATCH_STATE && FSM_state != READ_STATE){

                joystick_serial_bit = joystick_serial & 0x80;
                tb->serial_data = joystick_serial >> 7 ;
                joystick_serial = (uint8_t)(joystick_serial << 1);
            }
        }
#ifdef PRINT_LATCH_STATE
        // Latch state
        if(tb->data_latch){
            //
            if(!latch_info_was_printed){
            printf("Latch state\n\tk= %7d | i_clk= %d | o_clk= %d | i_rst= %u | data_latch= %d | o_latch_counter= %d | data= %d | o_cycle_stage: %d | button_state= %d\n", 
            k, tb->i_clk, tb->o_clk, tb->i_rst, tb->data_latch, tb->o_latch_counter, joystick_serial, tb->o_cycle_stage, tb->button_state);
            latch_info_was_printed = true;
            }
        }
        else
            latch_info_was_printed = false;
#endif

        // Data out state
        if(tb->o_cycle_stage == READ_STATE){
            if(!create_new_data_value){
                // printf("Output state\n\tk= %7d | i_clk= %d | o_clk= %d | i_rst= %d | data_latch= %u | o_cycle_stage: %d | button_state= %d\n", 
                //     k, tb->i_clk, tb->o_clk, tb->i_rst, tb->data_latch, tb->o_cycle_stage, tb->button_state);
                create_new_data_value = true;
                joystick_serial = dist255(rng);
                // printf("Next data= %u\n", joystick_serial);
            }
        }
        else
            create_new_data_value = false;
    }
}
