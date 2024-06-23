// Simple firmware for SNESTang
// nand2mario, 2024.1
//
// Needs xpack-gcc risc-v gcc: https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/
// Use build.bat to build. Then burn firmware.bin to SPI flash address 0x500000 with Gowin programmer.

#include <stdbool.h>
#include "picorv32.h"
#include "fatfs/ff.h"
#include "firmware.h"

uint32_t CORE_ID;

#define OPTION_FILE "/snestang.ini"
#define OPTION_INVALID 2

#define OPTION_OSD_KEY_SELECT_START 1
#define OPTION_OSD_KEY_SELECT_RIGHT 2
#define OPTION_OSD_KEY_HOME 3

// SNES BSRAM is mapped at address 7MB 
volatile uint8_t *SNES_BSRAM = (volatile uint8_t *)0x07000000;

int option_osd_key = OPTION_OSD_KEY_SELECT_RIGHT;
#define OSD_KEY_CODE (option_osd_key == OPTION_OSD_KEY_SELECT_START ? 0xC : (option_osd_key == OPTION_OSD_KEY_SELECT_RIGHT ? 0x84 : 0x24))
bool option_backup_bsram = false;
bool option_enhanced_apu = false;

bool snes_running;
int snes_ramsize;
bool snes_backup_valid;		// whether it is okay to save
char snes_backup_name[256];
uint16_t snes_bsram_crc16;
uint32_t snes_backup_time;

// Enhanced APU - enable
void enhanced_apu_enable(void){
   reg_enhanced_apu = 1;
}
// Enhanced APU - disable
void enhanced_apu_disable(void){
   reg_enhanced_apu = 0;
}

// return 0: success, 1: no option file found, 2: option file corrupt
int load_option()  {
	FIL f;
	int r = 0;
	char buf[1024];
	char *line, *key, *value;
	if (f_open(&f, OPTION_FILE, FA_READ))
		return 1;
	// XXX: handle escapes and quotes
	while (f_gets(buf, 1024, &f)) {
		line = trimwhitespace(buf);
		if (line[0] == '\0' || line[0] == '[' || line[0] == ';' || line[0] == '#')
			continue;
		// find '='
		char *s = strchr(line, '=');
		if (!s) {
			r = OPTION_INVALID;
			goto load_option_close;
		}
		*s='\0';
		key = trimwhitespace(line);
		value = trimwhitespace(s+1);
		// status("");
		uart_printf("key=%s, value=%s\n", key, value);
		// message("see below",1);

		// now handle all key-value pairs
		if (strcmp(key, "osd_key") == 0) {
			option_osd_key = atoi(value);
			if (option_osd_key <= 0) {
				r = OPTION_INVALID;
				message("OPTION_INVALID",1);
				goto load_option_close;
			}
		} else if (strcmp(key, "backup_bsram") == 0) {
			if (strcasecmp(value, "true") == 0)
				option_backup_bsram = true;
			else
				option_backup_bsram = false;
		} else if (strcmp(key, "enhanced_apu") == 0) {
			if (strcasecmp(value, "true") == 0){
				option_enhanced_apu = true;
				enhanced_apu_enable();
			}
			else{
				option_enhanced_apu = false;
				enhanced_apu_disable(); 
			}
		}else {
			// just ignore unknown keys
		}
	}

load_option_close:
	f_close(&f);
	return r;
}


// return 0: success, 1: cannot save
int save_option() {
	FIL f;
	if (f_open(&f, OPTION_FILE, FA_READ | FA_WRITE | FA_CREATE_ALWAYS)) {
		message("f_open failed",1);
		return 1;
	}
	if (f_puts("osd_key=", &f) < 0) {
		message("f_puts failed",1);
		goto save_options_close;
	}
	if (option_osd_key == OPTION_OSD_KEY_SELECT_START)
		f_puts("1\n", &f);
	else if (option_osd_key == OPTION_OSD_KEY_SELECT_RIGHT)
		f_puts("2\n", &f);
	else
		f_puts("3\n", &f);
	
	f_puts("backup_bsram=", &f);
	if (option_backup_bsram)
		f_puts("true\n", &f);
	else
		f_puts("false\n", &f);

	f_puts("enhanced_apu=", &f);
	if (option_enhanced_apu){
		f_puts("true\n", &f);
	}
	else{
		f_puts("false\n", &f);
	}
		
save_options_close:
	f_close(&f);
	// hide snestang.ini in dir list
	f_chmod(OPTION_FILE, AM_HID, AM_HID);
	return 0;
}

void status(char *msg) {
	cursor(0, 27);
	for (int i = 0; i < 32; i++)
		putchar(' ');
	cursor(2, 27);
	print(msg);
}

// show a pop-up message, press any key to discard (caller needs to redraw screen)
// msg: could be multi-line (separate with \n), max 10 lines
// center: whether to center the text
void message(char *msg, int center) {
	// count number of lines and max width
	int w[10], lines=10, maxw = 0;
	int len = strlen(msg);
	char *end = msg + len;
	char *sol = msg;
	for (int i = 0; i < 10; i++) {
		char *eol = strchr(sol, '\n');
		if (eol) { // found \n
			w[i] = min(eol - sol, 26);
			maxw = max(w[i], maxw);
			sol = eol+1;
		} else {
			w[i] = min(end - sol, 26);
			maxw = max(w[i], maxw);
			lines = i+1;
			break;
		}		
	}
	// status("");
	// printf("w=%d, lines=%d", maxw, lines);
	// draw a box 
	int y0 = 14 - ((lines + 2) >> 1);
	int y1 = y0 + lines + 2;
	int x0 = 16 - ((maxw + 2) >> 1);
	int x1 = x0 + maxw + 2;
	for (int y = y0; y < y1; y++)
		for (int x = x0; x < x1; x++) {
			cursor(x, y);
			if ((x == x0 || x == x1-1) && (y == y0 || y == y1-1))
				putchar('+');
			else if (x == x0 || x == x1-1)
				putchar('|');
			else if (y == y0 || y == y1-1)
				putchar('-');
			else
				putchar(' ');
		}
	// print text
	char *s = msg;
	for (int i = 0; i < lines; i++) {
		if (center)
			cursor(16-(w[i]>>1), y0+i+1);
		else
			cursor(x0+1, y0+i+1);
		while (*s != '\n' && *s != '\0') {
			putchar(*s);
			s++;
		}
		s++;
	}
	// wait for a keypress
	delay(300);
	for (;;) {
		int joy1, joy2;
		joy_get(&joy1, &joy2);
	   	if ((joy1 & 0x1) || (joy1 & 0x100) || (joy2 & 0x1) || (joy2 & 0x100))
	   		break;
	}
	delay(300);
}


FATFS fs;

#define PAGESIZE 22
#define TOPLINE 2
#define PWD_SIZE 1024

char pwd[PWD_SIZE];		// total path length 1023
// one page of file names to display
char file_names[PAGESIZE][256];
int file_dir[PAGESIZE];
int file_sizes[PAGESIZE];
int file_len;		// number of files on this page

// starting from `start`, load `len` file names into file_names, 
// file_dir. 
// *count is set to number of all valid entries and `file_len` is
// set to valid entries on this page.
// return: 0 if successful
int load_dir(char *dir, int start, int len, int *count) {
	DEBUG("load_dir: %s, start=%d, len=%d\n", dir, start, len);
	int cnt = 0;
	int r = 0;
	DIR d;
	file_len = 0;
	// initiaze sd again to be sure
	int init_ok = 0;
	for (int i = 0; i <= 10; i++)
		if (sd_init() == 0) {
			init_ok = 1;
			break;
		}
	if (!init_ok) return 99;

	if (f_opendir(&d, dir) != 0) {
		return -1;
	}
	// an entry to return to parent dir or main menu 
	int is_root = dir[1] == '\0';
	if (start == 0 && len > 0) {
		if (is_root) {
			strncpy(file_names[0], "<< Return to main menu", 256);
			file_dir[0] = 0;
		} else {
			strncpy(file_names[0], "..", 256);
			file_dir[0] = 1;
		}
		file_len++;
	}
	cnt++;

	// generate all file entries
	FILINFO fno;
	while (f_readdir(&d, &fno) == FR_OK) {
		if (fno.fname[0] == 0)
			break;
		if ((fno.fattrib & AM_HID) || (fno.fattrib & AM_SYS))
 			// skip hidden and system files
			continue;
		if (cnt >= start && file_len < len) {
			strncpy(file_names[file_len], fno.fname, 256);
			file_dir[file_len] = fno.fattrib & AM_DIR;
			file_sizes[file_len] = fno.fsize;
			file_len++;
		}
		cnt++;
	}
	f_closedir(&d);
	*count = cnt;
	DEBUG("load_dir: count=%d\n", cnt);
	return 0;
}

// return 0: user chose a ROM (*choice), 1: no choice made, -1: error
// file chosen: pwd / file_name[*choice]
int menu_loadrom(int *choice) {
	int page = 0, pages, total;
	int active = 0;
	pwd[0] = '/';
	pwd[1] = '\0';
	while (1) {
		clear();
		int r = load_dir(pwd, page*PAGESIZE, PAGESIZE, &total);
		if (r == 0) {
			pages = (total+PAGESIZE-1) / PAGESIZE;
			status("Page ");
			printf("%d/%d", page+1, pages);
			if (active > file_len-1)
				active = file_len-1;
			for (int i = 0; i < PAGESIZE; i++) {
				int idx = page*PAGESIZE + i;
				cursor(2, i+TOPLINE);
				if (idx < total) {
					print(file_names[i]);
					if (idx != 0 && file_dir[i])
						print("/");
				}
			}
			delay(300);
			while (1) {
				int r = joy_choice(TOPLINE, file_len, &active, OSD_KEY_CODE);
				if (r == 1) {
					if (strcmp(pwd, "/") == 0 && page == 0 && active == 0) {
						// return to main menu
						return 1;
					} else if (file_dir[active]) {
						if (file_names[active][0] == '.' && file_names[active][1] == '.') {
							// return to parent dir
							// message(file_names[active], 1);
							char *slash = strrchr(pwd, '/');
							if (slash)
								*slash = '\0';
						} else {								// enter sub dir
							strncat(pwd, "/", PWD_SIZE);
							strncat(pwd, file_names[active], PWD_SIZE);
						}
						active = 0;
						page = 0;
						break;
					} else {
						// actually load a ROM
						*choice = active;
						int res;
						if (CORE_ID == 1)
							res = loadnes(active);
						else
							res = loadsnes(active);
						if (res != 0) {
							message("Cannot load rom",1);
							break;
						}
					}
				}
				if (r == 2 && page < pages-1) {
					page++;
					break;
				} else if (r == 3 && page > 0) {
					page--;
					break;
				}
			}
		} else {
			status("Error opening director");
			printf(" %d", r);
			return -1;
		}
	}
}

void menu_options() {
	int choice = 0;
	while (1) {
		clear();
		cursor(8, 10);
		print("--- Options ---");

		cursor(2, 12);
		print("<< Return to main menu");
		cursor(2, 14);
		print("OSD hot key:");
		cursor(16, 14);
		if (option_osd_key == OPTION_OSD_KEY_SELECT_START)
			print("SELECT&START");
		else if(option_osd_key == OPTION_OSD_KEY_SELECT_RIGHT)
			print("SELECT&RIGHT");
		else
			print("HOME");
		cursor(2, 15);
		print("Backup BSRAM:");
		cursor(16, 15);
		if (option_backup_bsram)
			print("Yes");
		else
			print("No");
		cursor(2, 16);
		print("Enhanced APU:");
		cursor(16, 16);
		if (option_enhanced_apu)
			print("Yes");
		else
			print("No");

		delay(300);

		for (;;) {
			if (joy_choice(12, 5, &choice, OSD_KEY_CODE) == 1) {
				if (choice == 0) {
					return;
				} else if (choice == 1) {
					// nothing
				} else {
					if (choice == 2) {
						if (option_osd_key == OPTION_OSD_KEY_SELECT_START)
							option_osd_key = OPTION_OSD_KEY_SELECT_RIGHT;
						else if (option_osd_key == OPTION_OSD_KEY_SELECT_RIGHT)
							option_osd_key = OPTION_OSD_KEY_HOME;
						else
							option_osd_key = OPTION_OSD_KEY_SELECT_START;
					} else if (choice == 3) {
						option_backup_bsram = !option_backup_bsram;
					} else if (choice == 4) {
						option_enhanced_apu = !option_enhanced_apu;
						reg_enhanced_apu = !reg_enhanced_apu;
					}
					status("Saving options...");
					if (save_option()) {
						message("Cannot save options to SD",1);
						break;
					}
					break;	// redraw UI
				}
			}
		}
	}
}

int in_game;

// return 0 if snes header is successfully parsed at off
// typ 0: LoROM, 1: HiROM, 2: ExHiROM
int parse_snes_header(FIL *fp, int pos, int file_size, int typ, uint8_t *hdr, int *map_ctrl, int *rom_type_header, int *rom_size, int *ram_size, int *company) {
	int br;
	if (f_lseek(fp, pos))
		return 1;
	f_read(fp, hdr, 64, &br);
	if (br != 64) return 1;
	int mc = hdr[21];
	int rom = hdr[23];
	int ram = hdr[24];
	int checksum = (hdr[28] << 8) + hdr[29];
	int checksum_compliment = (hdr[30] << 8) + hdr[31];
	int reset = (hdr[61] << 8) + hdr[60];
	int size2 = 1024 << rom;

	status("");
	printf("size=%d", size2);

	// calc heuristics score
	int score = 0;		
	if (size2 >= file_size) score++;
	if (rom == 1) score++;
	if (checksum + checksum_compliment == 0xffff) score++;
	int all_ascii = 1;
	for (int i = 0; i < 21; i++)
		if (hdr[i] < 32 || hdr[i] > 127)
			all_ascii = 0;
	score += all_ascii;

	DEBUG("pos=%x, type=%d, map_ctrl=%d, rom=%d, ram=%d, checksum=%x, checksum_comp=%x, reset=%x, score=%d\n", 
			pos, typ, mc, rom, ram, checksum, checksum_compliment, reset, score);

	if (rom < 14 && ram <= 7 && score >= 1 && 
		reset >= 0x8000 &&				// reset vector position correct
	   ((typ == 0 && (mc & 3) == 0) || 	// normal LoROM
		(typ == 0 && mc == 0x53)    ||	// contra 3 has 0x53 and LoROM
		(typ == 1 && (mc & 3) == 1) ||	// HiROM
		(typ == 2 && (mc & 3) == 2))) {	// ExHiROM
		*map_ctrl = mc;
		*rom_type_header = hdr[22];
		*rom_size = rom;
		*ram_size = ram;
		*company = hdr[26];
		return 0;
	}
	return 1;
}

char load_fname[1024];
char load_buf[1024];

// actually load a rom file. if bsram backup is needed, also loads the backup.
// return 0 if successful
int loadsnes(int rom) {
	FIL f;
	strncpy(load_fname, pwd, 1024);
	strncat(load_fname, "/", 1024);
	strncat(load_fname, file_names[rom], 1024);

	// check extension .sfc or .smc
	char *p = strcasestr(file_names[rom], ".sfc");
	if (p == NULL)
		p = strcasestr(file_names[rom], ".smc");
	if (p == NULL) {
		status("Only .smc or .sfc supported");
		goto loadsnes_end;
	}
	// snes_backup_name = <base>.srm
	int base_len = p-file_names[rom];
	strncpy(snes_backup_name, file_names[rom], base_len);
	strcpy(snes_backup_name+base_len, ".srm");

	// initiaze sd again to be sure
	if (sd_init() != 0) return 99;

	int r = f_open(&f, load_fname, FA_READ);
	if (r) {
		status("Cannot open file");
		goto loadsnes_end;
	}
	int br, total = 0;
	int size = file_sizes[rom];
	int map_ctrl, rom_type_header, rom_size, ram_size, company;
	// parse SNES header from ROM file
	int off = size & 0x3ff;		// rom header (0 or 512)
	int header_pos;
	DEBUG("off=%d\n", off);
	
	header_pos = 0x7fc0 + off;
	if (parse_snes_header(&f, header_pos, size-off, 0, load_buf, &map_ctrl, &rom_type_header, &rom_size, &ram_size, &company)) {
		header_pos = 0xffc0 + off;
		if (parse_snes_header(&f, header_pos, size-off, 1, load_buf, &map_ctrl, &rom_type_header, &rom_size, &ram_size, &company)) {
			header_pos = 0x40ffc0 + off;
			if (parse_snes_header(&f, header_pos, size-off, 2, load_buf, &map_ctrl, &rom_type_header, &rom_size, &ram_size, &company)) {
				status("Not a SNES ROM file");
				delay(200);
				goto loadsnes_close_file;
			}
		}
	}

	// load actual ROM
	snes_ctrl(1);		// enable game loading, this resets SNES
	snes_running = false;

	// Send 64-byte header to snes
	for (int i = 0; i < 64; i += 4) {
		uint32_t *w = (uint32_t *)(load_buf + i);
		snes_data(*w);
	}

	// Send rom content to snes
	if ((r = f_lseek(&f, off)) != FR_OK) {
		status("Seek failure");
		goto loadsnes_snes_end;
	}
	do {
		if ((r = f_read(&f, load_buf, 1024, &br)) != FR_OK)
			break;
		for (int i = 0; i < br; i += 4) {
			uint32_t *w = (uint32_t *)(load_buf + i);
			snes_data(*w);				// send actual ROM data
		}
		total += br;
		if ((total & 0xffff) == 0) {	// display progress every 64KB
			status("");
			printf("%d/%dK", total >> 10, size >> 10);
			if ((map_ctrl & 3) == 0)
				print(" Lo");
			else if ((map_ctrl & 3) == 1)
				print(" Hi");
			else if ((map_ctrl & 3) == 2)
				print(" ExHi");
			printf(" ROM=%d RAM=%d", 1 << rom_size, ram_size ? (1 << ram_size) : 0);
		}
	} while (br == 1024);

	// load BSRAM backup
	snes_ramsize = ram_size == 0 ? 0 : ((1 << ram_size) << 10);
	if (snes_ramsize > 0)
		memset((uint8_t *)0x700000, 0, snes_ramsize);		// clear BSRAM
	backup_load(snes_backup_name, snes_ramsize);

	status("Success");
	snes_running = true;

	overlay(0);		// turn off OSD

loadsnes_snes_end:
	snes_ctrl(0);	// turn off game loading, this starts SNES
loadsnes_close_file:
	f_close(&f);
loadsnes_end:
	return r;
}

// load a NES rom file.
// return 0 if successful
int loadnes(int rom) {
	FIL f;
	strncpy(load_fname, pwd, 1024);
	strncat(load_fname, "/", 1024);
	strncat(load_fname, file_names[rom], 1024);

	DEBUG("loadnes start\n");

	// check extension .sfc or .smc
	char *p = strcasestr(file_names[rom], ".nes");
	if (p == NULL) {
		status("Only .nes supported");
		goto loadnes_end;
	}

	// initiaze sd again to be sure
	if (sd_init() != 0) return 99;

	int r = f_open(&f, load_fname, FA_READ);
	if (r) {
		status("Cannot open file");
		goto loadnes_end;
	}
	int off = 0, br, total = 0;
	int size = file_sizes[rom];

	// load actual ROM
	snes_ctrl(1);		// enable game loading, this resets SNES
	snes_running = false;

	// Send rom content to snes
	if ((r = f_lseek(&f, off)) != FR_OK) {
		status("Seek failure");
		goto loadnes_snes_end;
	}
	do {
		if ((r = f_read(&f, load_buf, 1024, &br)) != FR_OK)
			break;
		for (int i = 0; i < br; i += 4) {
			uint32_t *w = (uint32_t *)(load_buf + i);
			snes_data(*w);				// send actual ROM data
		}
		total += br;
		if ((total & 0xfff) == 0) {	// display progress every 4KB
			status("");
			printf("%d/%dK", total >> 10, size >> 10);
		}
	} while (br == 1024);

	DEBUG("loadnes: %d bytes\n", total);
	status("Success");
	snes_running = true;

	overlay(0);		// turn off OSD

loadnes_snes_end:
	snes_ctrl(0);	// turn off game loading, this starts the core
loadnes_close_file:
	f_close(&f);
loadnes_end:
	return r;
}

void backup_load(char *name, int size) {
	snes_backup_valid = false;
	if (!option_backup_bsram || size == 0) return;
	char path[266] = "/saves/";
	FILINFO fno;
	uint8_t *bsram = (uint8_t *)0x700000;			// directly read into BSRAM

	if (f_stat(path, &fno) != FR_OK) {
		if (f_mkdir(path) != FR_OK) {
			status("Cannot create /saves");
			uart_printf("Cannot create /saves\n");
			goto backup_load_crc;
		}
	}
	strcat(path, snes_backup_name);
	uart_printf("Loading bsram from: %s\n", snes_backup_name);
	FIL f;
	if (f_open(&f, path, FA_READ) != FR_OK) {
		snes_backup_valid = true;					// new save file, mark as valid
		uart_printf("Cannot open bsram file, assuming new\n");
		goto backup_load_crc;
	}
	uint8_t *p = bsram;	
	int load = 0;
	while (load < size) {
		int br;
		if (f_read(&f, p, 1024, &br) != FR_OK || br < 1024) 
			break;
		p += br;
		load += br;
	}
	snes_backup_valid = true;
	f_close(&f);
	int crc = gen_crc16(bsram, size);
	uart_printf("Bsram backup loaded %d bytes CRC=%x.\n", load, crc);

backup_load_crc:
	snes_bsram_crc16 = gen_crc16(bsram, size);

	return;
}

// return 0: successfully saved, 1: BSRAM unchanged, 2: file write failure
int backup_save(char *name, int size) {
	if (!option_backup_bsram || !snes_backup_valid || size == 0) return 1;
	char path[266] = "/saves/";
	FIL f;
	uint8_t *bsram = (uint8_t *)0x700000;		// directly read from BSRAM
	int r = 0;

	// first check if BSRAM content is changed since last save
	int newcrc = gen_crc16(bsram, size);
	uart_printf("New CRC: %x, size=%d\n", newcrc, size);
	if (newcrc == snes_bsram_crc16)
		return 1;

	strcat(path, snes_backup_name);
	if (f_open(&f, path, FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) {
		status("Cannot write save file");
		uart_printf("Cannot write save file");
		return 2;
	}
	int bw;
	// for (int off = 0; off < size; off += bw) {
	// 	if (f_write(&f, bsram, 1024, &bw) != FR_OK) {
	if (f_write(&f, bsram, size, &bw) != FR_OK || bw != size) {
		status("Write failure");
		uart_printf("Write failure, bw=%d\n", bw);
		r = 2;
		goto bsram_save_close;
	}
	// }
	snes_bsram_crc16 = newcrc;

bsram_save_close:
	f_close(&f);
	return r;
}

int backup_success_time;
void backup_process() {
	if (!snes_running || !option_backup_bsram || snes_ramsize == 0)
		return;
	int t = time_millis();
	if (t - snes_backup_time >= 10000) {
		// need to save
		int r = backup_save(snes_backup_name, snes_ramsize);
		if (r == 0)
			backup_success_time = t;
		if (backup_success_time != 0) {
			status("");
			printf("BSRAM saved %ds ago ", (t-backup_success_time)/1000);
			print_hex_digits(snes_bsram_crc16, 4);
		}
		snes_backup_time = t;
	}
}

#define CRC16 0x8005

uint16_t gen_crc16(const uint8_t *data, uint16_t size) {
    uint16_t out = 0;
    int bits_read = 0, bit_flag;

    /* Sanity check: */
    if(data == NULL)
        return 0;

    while(size > 0)
    {
        bit_flag = out >> 15;

        /* Get next bit: */
        out <<= 1;
        out |= (*data >> bits_read) & 1; // item a) work from the least significant bits

        /* Increment bit counter: */
        bits_read++;
        if(bits_read > 7)
        {
            bits_read = 0;
            data++;
            size--;
        }

        /* Cycle check: */
        if(bit_flag)
            out ^= CRC16;

    }

    // item b) "push out" the last 16 bits
    int i;
    for (i = 0; i < 16; ++i) {
        bit_flag = out >> 15;
        out <<= 1;
        if(bit_flag)
            out ^= CRC16;
    }

    // item c) reverse the bits
    uint16_t crc = 0;
    i = 0x8000;
    int j = 0x0001;
    for (; i != 0; i >>=1, j <<= 1) {
        if (i & out) crc |= j;
    }

    return crc;
}

int main() {
	CORE_ID = reg_core_id;
	overlay(1);

	// initialize UART
	reg_uart_clkdiv = 187; // 21505400 / 115200;

	sd_init();
	delay(100);
	DEBUG("CORE_ID=%d\n", CORE_ID);
	
	int mounted = 0;
	while(!mounted) {
		for (int attempts = 0; attempts < 255; attempts++) {
			if (f_mount(&fs, "", 0) == FR_OK) {
				mounted = 1;
				break;
			}
		}
		if (!mounted)
			message("Insert SD card and press any key", 1);
	}

	int r = load_option();
	if (r == 2) {	// file corrupt
		clear();
		message("Option file corrupt and is not loaded",1);
	} else if (r == 1) {	// file not exist
		// clear();
		// message("Cannot open option file",1);
	}

	for (;;) {
		// main menu
		clear();
		cursor(2, 10);
		//     01234567890123456789012345678901
		if (CORE_ID == 1)
			print("=== Welcome to NESTang ===");
		else
			print("~~~ Welcome to SNESTang ~~~");

		cursor(2, 12);
		print("1) Load ROM from SD card\n");
		cursor(2, 13);
		print("2) Options\n");
		cursor(2, 15);
		print("Version: ");
		print(__DATE__);

		delay(300);

		int choice = 0;
		for (;;) {
			int r = joy_choice(12, 2, &choice, OSD_KEY_CODE);
			if (r == 1) break;
		}

		if (choice == 0) {
			int rom;
			delay(300);
			menu_loadrom(&rom);
		} else if (choice == 1) {
			delay(300);
			menu_options();
			continue;
		}
	}
}

