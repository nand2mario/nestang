
# Wiring instructions for NESTang

This is for two modules:
1. SDRAM memory module: Mister SDRAM XS-D v2.5 (128MB). Chip is 2 x Alliance memory AS4C32M16SB-7TIN. Only the first chip is used. So total available size is 64MB.
2. HDMI Pmod module: Muse-Lab PMOD-HDMI 1.0.

Both modules are not directly pin compatible with Tang 20K. So without spinning a custom PCB, the easiest way is to connect the pins manually with wires (luckily we are not working at high clock speed). For the memory module you probably need 40 male-female Dupont wires. For the HDMI module, you need 10 female-female wires.

Wiring diagram is as follow. For example, 
  - Top GPIO pin #1 (3V3) to Mister pin #29 (3V3)
  - Top GPIO pin #3 (N6) to Mister pin #1 (DQ0)
  - Bottom GPIO pin #1 (H12) to HDMI PMod pin HDMI_CKN (not drawn, but the module has labels)

```
Mister SDRAM XS/D v2.5                       Top GPIO(J3)                         Bottom GPIO   
        +-----+                                +-----+                             +-----+ 
  DQ0   |1   2|   DQ1                3V3  29 3V3|1   2|GND 12 GND               3V3|1   2|3V3 
  DQ2   |3   4|   DQ3                DQ0  1   N6|3   4|N7  2  DQ1                  |3   4| 
  DQ4   |5   6|   DQ5                DQ2  3  B11|5   6|A12 4  DQ3                  |5   6|GND             
  DQ6   |7   8|   DQ7                DQ4  5   L9|7   8|N8  6  DQ5                  |7   8|                        
  DQ15  |9  10|   DQ14               DQ6  7   R9|9  10|N9  8  DQ7                  |9  10|                        
        |11 12|    GND                        A6|11 12|A7                          |11 12|                        
  DQ13  |13 14|   DQ12                        C6|13 14|B8                          |13 14|                         
  DQ11  |15 16|   DQ10               DQ15 9  C10|15 16|GND                         |15 16|                        
  DQ9   |17 18|   DQ8                DQ13 13 A11|17 18|C11 10 DQ14                 |17 18|
  A12   |19 20|   CLK                DQ11 15 B12|19 20|C12 14 DQ12                 |19 20|
  A9    |21 22|   A11                DQ9  17 B13|21 22|A14 16 DQ10     HDMI_CKN H12|21 22|G11 HDMI_CKP
  A7    |23 24|   A8                 A12  19 B14|23 24|A15 18 DQ8      HDMI_D0P H13|23 24|J12 HDMI_D0N
  A5    |25 26|   A6                 A9   21 D14|25 26|E15 20 CLK      HDMI_D1N K12|25 26|K13 HDMI_D1P
  WE    |27 28|   A4                 A7   23 F16|27 28|F14 22 A11      HDMI_D2N L13|27 28|K11 HDMI_D2P
 3V3    |29 30|    GND               A5   25 G15|29 30|G14 24 A8                   |29 30|
  CAS   |31 32|   RAS                WE   27 J14|31 32|J16 26 A6                   |31 32|
  CS1   |33 34|   BA0                CAS  31 G12|33 34|F13 28 A4                   |33 34|
  BA1   |35 36|   A10                CS1  33 M14|35 36|M15 32 RAS                  |35 36|K13 38 A1
  A0    |37 38|   A1                 BA1  35 T14|37 38|R13 34 BA0                  |37 38|K11 39 A2
  A2    |39 40|   A3                 A0   37 P13|39 40|R12 36 A10                  |39 40|T12 40 A3
        +-----+                                 +-----+                            +-----+
```

The end result will look something like this. 

<img src='images/wiring.jpg' width=400>

Ugh! Ugly but works...

(#1 pins for both GPIO banks are on the left. The #1 pin for the SDRAM module is also on the left and facing the camera.)