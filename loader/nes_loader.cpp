// NESTang loader
// nand2mario, 2022.10
//
// This targets Visual C++ Community 2022 on Windows and g++ on Linux
// - C++17 is used for the filesystem library.
// - All paths are std::filesystem::path. This allows us to portably access i18n file names.

#ifdef _MSC_VER
#include "stdafx.h"
#include <windows.h>
#else
#include <unistd.h>
#endif

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <fstream>
namespace fs = std::filesystem;		// C++17
using namespace std;

#include "osd.h"
#include "util.h"

#ifdef _MSC_VER
fs::path gamedir(L"games");
fs::path com_port(L"\\\\.\\COM10");
#else
fs::path gamedir("games");
fs::path com_port("/dev/ttyUSB1");
#endif
int baudrate = 921600;
bool readSerial = false;
bool dump_packet = false;
HANDLE uart;		// serial port
int config;

void usage() {
	printf("NESTang Loader 0.2\n");
	printf("Usage: loader [options] < game.nes or - >\n");
	printf("Options:\n");
	printf("    -c <port>  use specific serial port (\\\\.\\COM4, /dev/ttyUSB0...).\n");
	printf("    -b <rate>  specify baudrate, e.g. 115200 (default is 921600).\n");
	printf("    -d <dir>   specify rom directory, default is 'games'.\n");
	printf("    -n <config>  set config word (0-255)\n");
	printf("    -r         display message from serial for debug.\n");
	printf("    -v         verbose. print packets sent.\n");
	printf("    -h         display this help message.\n");
}

// Return: 
//    index to next argument if successful
//    -1 if failure
int parseArgs(int argc, char* argv[]) {
	int idx;
	for (idx = 1; idx < argc; idx++) {
		if (strlen(argv[idx]) > 1 && argv[idx][0] == '-') {
			if (strcmp(argv[idx], "-r") == 0) {
				readSerial = true;
			}
			else if (strcmp(argv[idx], "-b") == 0) {
				baudrate = atoi(argv[++idx]);
			}
			else if (strcmp(argv[idx], "-v") == 0) {
				dump_packet = true;
			}
			else if (strcmp(argv[idx], "-c") == 0 && idx + 1 < argc) {
				com_port = argv[++idx];
			}
			else if (strcmp(argv[idx], "-d") == 0 && idx + 1 < argc) {
				gamedir = argv[++idx];
			}
			else if (strcmp(argv[idx], "-n") == 0 && idx + 1 < argc) {
				config = atoi(argv[++idx]);
			}
			else if (strcmp(argv[idx], "-h") == 0) {
				usage();
				return 0;
			}
			else {
				printf("Unknown option: %s\n", argv[idx]);
				return -1;
			}
		}
		else
			break;
	}
	if (idx >= argc) {
		usage();
		return -1;
	}
	return idx;
}

bool inOSD = false;
int sendNES(fs::path p);

int main(int argc, char* argv[]) {
	int idx = parseArgs(argc, argv);
	if (idx < 0) {
		return 1;
	}

	uart = openSerialPort(com_port, baudrate);
	if (!uart) {
		printf("Cannot open serial port: %s\n", com_port.string().c_str());
		return 0;
	}

	if (config != 0) {
		uint8_t config_byte = (uint8_t)config;
		writePacket(uart, 0x36, &config_byte, 1);
		printf("Sent config word: %d\n", config);
	}

	if (strcmp(argv[idx], "-") != 0) {
		if (sendNES(fs::path(argv[idx])))
			return -1;
	}
	else {
		if (!fs::exists(gamedir) || !fs::is_directory(gamedir)) {
#ifdef _MSC_VER
			wprintf(L"%s does not exist or is not a directory.\n", gamedir.c_str());
#else
			printf("%s does not exist or is not a directory.\n", gamedir.c_str());
#endif
			return -1;
		}
		printf("Press LB on first controller to open on screen menu.\n");
	}

	if (readSerial)
		readFromSerial(uart);

	scanGamepads();
	struct gamepad pad[2];
	memset(pad, 0, sizeof(pad));

	unsigned char last_keys0 = -1;
	unsigned char last_keys1 = -1;
	DWORD lastButtons = 0;
	DWORD lastPOV = 0;
	bool osdPressed = false;

	for (;;) {

		// Get updates from gamepads
		if (updateGamepads(pad) <= 0) {
			printf("Cannot find any controller. Please connect a controller and try again.\n");
			return 1;
		}

		// press controller #1 LB to toggle OSD
		if (pad[0].osdButton) {
			if (!osdPressed) {
				inOSD = !inOSD;
				osd_show(inOSD);
				if (inOSD) {
					osd_update(0, true);
				}
				osdPressed = true;
				goto joy_continue;
			}
		} else
			osdPressed = false;

		if (inOSD) {
			// pass keys to OSD module
			osd_update(pad[0].nesKeys);
			goto joy_continue;
		}
		
		// Pass key to NES
		if (pad[0].nesKeys != last_keys0) {
			// printf("Keys %.2x\n", keys1);
			writePacket(uart, 0x40, &pad[0].nesKeys, 1);
			last_keys0 = pad[0].nesKeys;
		}

		// Process controller #2
		if (pad[1].nesKeys != last_keys1) {
			writePacket(uart, 0x41, &pad[1].nesKeys, 1);
			last_keys1 = pad[1].nesKeys;
		}

	joy_continue:
#ifdef _MSC_VER
		Sleep(1);
#else
		usleep(1000);
#endif
	}
	return 0;
}

// return 0 if successful
static char sendbuf[16384];
int sendNES(fs::path p)
{
	ifstream f(p, ios::binary);
	if (!f.is_open()) { printf("File open fail\n"); return 1; }

	// Reset NES machine
	{ char v = 1; writePacket(uart, 0x35, &v, 1); }
	{ char v = 0; writePacket(uart, 0x35, &v, 1); }

	size_t total_read = 0xffffff;		// max size 16MB
	size_t pos = 0;

	bool first = true;
	while (pos < total_read) {
		streamsize want_read = (total_read - pos) > sizeof(sendbuf) ? sizeof(sendbuf) : (total_read - pos);
		f.read(sendbuf, want_read);
		streamsize n = f.gcount();
		// printf("want_read=%d, actual_read=%d\n", (int)want_read, (int)n);
		if (n > 0) {
			if (first && n > 16 && strncmp(&sendbuf[7], "DiskDude!", 9) == 0) {
				// "DiskDude!" work-around. See https://www.nesdev.org/wiki/INES
				// Older versions of the iNES emulator ignored bytes 7-15 and writes "DiskDude!" there, 
				// corrupting byte 7 and results in 64 being added to the mapper number.
				printf("Old rom file detected with 'DiskDude!' string. Applying fix on-the-fly.\n");
				sendbuf[7] = 0;		// simply setting byte 7 to 0 should fix it
			}

			//printf("Write packet\n");
			writePacket(uart, 0x37, sendbuf, n);
		}
		if (f.eof())
			break;
		pos += n;
		first = false;
	}
	f.close();

#ifdef _MSC_VER
	wprintf(L"%s transmitted over %s at baudrate %d.\n", p.filename().wstring().c_str(),
		com_port.wstring().c_str(), baudrate);
#else
	printf("%s transmitted over %s at baudrate %d.\n", p.filename().string().c_str(),
		com_port.string().c_str(), baudrate);
#endif
	return 0;
}
