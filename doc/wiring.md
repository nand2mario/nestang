
# Wiring instructions for NESTang

This is for wiring the HDMI Pmod module (Muse-Lab PMOD-HDMI 1.0) to Tang Primer 20K. The module *almost* worked directly in the PMod sockets. The only thing off is the polarity of the data lanes. Alas, we therefore still need to connect it with dupont wires.

Connect the module to the Tang's bottom GPIOs as follows. 
- "HDMI_CKP" and etc are corresponding pin labels on the HDMI module.
- The #1 pin for the GPIO bank is on the left side of the board.

```
            Bottom GPIO   
             +-----+ 
          3V3|1   2|3V3 
             |3   4| 
             |5   6|GND             
             |7   8|                        
             |9  10|                        
             |11 12|                        
             |13 14|                         
             |15 16|                        
             |17 18|
             |19 20|
 HDMI_CKN H12|21 22|G11 HDMI_CKP
 HDMI_D0P H13|23 24|J12 HDMI_D0N
 HDMI_D1N K12|25 26|K13 HDMI_D1P
 HDMI_D2N L13|27 28|K11 HDMI_D2P
             |29 30|
             |31 32|
             |33 34|
             |35 36|
             |37 38|
             |39 40|
             +-----+
```

Other HDMI modules could also work. Essentially the key signals are VCC/GND, a pair of differential clocks and three pairs of differential video data.
