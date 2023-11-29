////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	NESGamepad.cpp
//
// Project:	NESTang Tang Nano 20k
//
// Purpose:	Main Verilator simulation script for the NESGamepad design
//
//	In this script we simulate some reads to a classic NES Gamepad
//
// Creator:	F. J. Polo @GitHub /fjpolo
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
#define OUTPUT_UPDATE_FREQUENCY     (1 / 12) * 1000000
#define SAMPLING_CLOCK_COUNT        250000
#define SERIAL_DATA_COUNT           324
#define NUMBER_OF_STATES            (9)
#define LATCH_STATE                 (1)
#define READ_STATE                  (1 << (NUMBER_OF_STATES-2))

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
    tb->i_serial_data = 0x01;
    tb->i_rst = 0x00;
    static int i_sampling_clock_counter = SAMPLING_CLOCK_COUNT;
    static int i_serial_data_counter = SERIAL_DATA_COUNT;
    static int FSM_state = LATCH_STATE;
    static bool create_new_data_value = false;
    #ifdef PRINT_LATCH_STATE
    static bool latch_info_was_printed = false;
    #endif
    for(int k=0; k<(1<<23); k++){
        // Tick()
        tick(++tick_count, tb, tfp);

        // Data out state
        if(FSM_state == READ_STATE){
            if(!create_new_data_value){
                create_new_data_value = true;
                joystick_serial = dist255(rng);
            }
        }
        else
            create_new_data_value = false;
        
        i_serial_data_counter--;
        if(!i_serial_data_counter){
            // FSM_state
            FSM_state = FSM_state << 1;
            if(FSM_state > READ_STATE)
                FSM_state = LATCH_STATE;
            i_serial_data_counter = SERIAL_DATA_COUNT;

            if(FSM_state != READ_STATE){
                joystick_serial_bit = joystick_serial & 0x80;
                tb->i_serial_data = joystick_serial >> 7 ;
                joystick_serial = (uint8_t)(joystick_serial << 1);
            }
        }
#ifdef PRINT_LATCH_STATE
        // Latch state
        if(tb->o_data_latch){
            //
            if(!latch_info_was_printed){
            printf("Latch state\n\tk= %7d | i_clk= %d | i_rst= %u | o_data_latch= %d | o_button_state= %d\n", 
            k, tb->i_clk, tb->i_rst, tb->o_data_latch, tb->o_button_state);
            latch_info_was_printed = true;
            }
        }
        else
            latch_info_was_printed = false;
#endif

    }
}
