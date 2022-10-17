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

fs::path gamedir(PATH("games"));
#ifdef _MSC_VER
fs::path com_port(L"\\\\.\\COM10");
#else
fs::path com_port("/dev/ttyUSB0");
#endif
int baudrate = 921600;
bool readSerial = false;
bool dump_packet = false;
HANDLE uart;		// serial port

void usage() {
	printf("NESTang Loader 0.2\n");
	printf("Usage: loader [options] < game.nes or - >\n");
	printf("Options:\n");
	printf("    -c COM4    use specific serial port (for linux /dev/ttyUSB0).\n");
	printf("    -b <rate>  specify baudrate, e.g. 115200 (default is 921600).\n");
	printf("    -d <dir>   specify rom directory, default is 'games'.\n");
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
				com_port = argv[idx];
			}
			else if (strcmp(argv[idx], "-d") == 0 && idx + 1 < argc) {
				gamedir = argv[++idx];
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
		printf("Cannot open serial port\n");
		return 0;
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

	unsigned char last_keys1 = -1;
	unsigned char last_keys2 = -1;
	DWORD lastButtons = 0;
	DWORD lastPOV = 0;
	bool osdPressed = false;

	for (;;) {
		gamepad pad1, pad2;

		// Process controller #1
		if (updateGamepad(0, &pad1)) {
			printf("Cannot find any controller. Please connect a controller and try again.\n");
			return 1;
		}

		// press controller #1 LB to toggle OSD
		if (pad1.osdButton) {
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
			osd_update(pad1.nesKeys);
			goto joy_continue;
		}
		
		// Pass key to NES
		if (pad1.nesKeys != last_keys1) {
			// printf("Keys %.2x\n", keys1);
			writePacket(uart, 0x40, &pad1.nesKeys, 1);
			last_keys1 = pad1.nesKeys;
		}

		// Process controller #2
		if (updateGamepad(1, &pad2) == 0) {
			if (pad2.nesKeys != last_keys2) {
				writePacket(uart, 0x41, &pad2.nesKeys, 1);
				last_keys2 = pad2.nesKeys;
			}
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

	{ char v = 1; writePacket(uart, 0x35, &v, 1); }
	{ char v = 0; writePacket(uart, 0x35, &v, 1); }

	size_t total_read = 0xffffff;		// max size 16MB
	size_t pos = 0;

	while (pos < total_read) {
		streamsize want_read = (total_read - pos) > sizeof(sendbuf) ? sizeof(sendbuf) : (total_read - pos);
		f.read(sendbuf, want_read);
		streamsize n = f.gcount();
		//printf("want_read=%d, actual_read=%d\n", want_read, n);
		if (n > 0) {
			//printf("Write packet\n");
			writePacket(uart, 0x37, sendbuf, n);
		}
		if (f.eof())
			break;
		pos += n;
	}
	f.close();

	wprintf(L"%s transmitted over %s at baudrate %d.\n", p.filename().wstring().c_str(),
		com_port, baudrate);
	return 0;
}
