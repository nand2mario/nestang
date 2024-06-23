#ifndef FIRMWARE_H
#define FIRMWARE_H


// Load backup file content into SNES BSRAM. If no such file exists, this creates an empty one.
// name: save file name (.srm)
// size: in number of KB
void backup_load(char *name, int size);

// Save current BSRAM content on to SD card.
// name: save file name (.srm)
// size: in number of KB
int backup_save(char *name, int size);

// Saves every 10 seconds
void backup_process();

int loadnes(int rom);
int loadsnes(int rom);

void message(char *msg, int center);

void status(char *msg);

#define CRC16 0x8005

uint16_t gen_crc16(const uint8_t *data, uint16_t size);

#endif