#include "stdafx.h"
//#define	_CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
namespace fs = std::filesystem;		// C++17

#include "osd.h"
#include "util.h"

std::wstring gamedir(L"games");
wchar_t com_port[256] = L"\\\\.\\COM10";
int baudrate = 921600;
bool readSerial = false;
bool dump_packet = false;
HANDLE uart;		// serial port

// https://www.nesdev.org/wiki/Standard_controller
unsigned char joyinfoToKey(JOYINFOEX& joy) {
	unsigned char keys = 0;
	keys |= !!(joy.dwButtons & 1) * 1;          // Map A and X to A
	keys |= !!(joy.dwButtons & 4) * 1;
	keys |= !!(joy.dwButtons & 2) * 2;          // Map B and Y to B
	keys |= !!(joy.dwButtons & 8) * 2;
	keys |= !!(joy.dwButtons & 0x40) * 4;       // select
	keys |= !!(joy.dwButtons & 0x80) * 8;       // start
	keys |= (joy.dwYpos < 0x4000) * 16;
	keys |= (joy.dwPOV == JOY_POVFORWARD) * 16;     // FIXME: cannot do 45 degree with d-pad, stick is ok.
	keys |= (joy.dwYpos >= 0xC000) * 32;
	keys |= (joy.dwPOV == JOY_POVBACKWARD) * 32;
	keys |= (joy.dwXpos < 0x4000) * 64;
	keys |= (joy.dwPOV == JOY_POVLEFT) * 64;
	keys |= (joy.dwXpos >= 0xC000) * 128;
	keys |= (joy.dwPOV == JOY_POVRIGHT) * 128;
	return keys;
}

void usage() {
	printf("NESTang Loader 0.2.1\n");
	printf("Usage: loader [options] < game.nes or - >\n");
	printf("Options:\n");
	printf("    -c COM4    use specific COM port.\n");
	printf("    -b <rate>  specify baudrate, e.g. 115200 (default is 921600).\n");
	printf("    -d <dir>   specify rom directory, default is 'games'.");
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
		if (argv[idx][0] == '-') {
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
				mbstowcs(com_port, argv[++idx], sizeof(com_port)/sizeof(wchar_t));
			}
			else if (strcmp(argv[idx], "-d") == 0 && idx + 1 < argc) {
				gamedir = s2ws(std::string(argv[++idx]));
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


int main(int argc, char* argv[]) {
	int idx = parseArgs(argc, argv);
	if (idx < 0) {
		return 1;
	}

	uart = CreateFile(com_port, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (!uart) {
		printf("CreateFile failed\n");
		return 0;
	}

	DCB dcb = { 0 };
	dcb.DCBlength = sizeof(DCB);
	dcb.ByteSize = 8;
	dcb.StopBits = ONESTOPBIT;
	dcb.BaudRate = baudrate;
	dcb.fBinary = TRUE;
	if (!SetCommState(uart, &dcb)) {
		printf("SetCommState failed\n");
		return 0;
	}

	if (strcmp(argv[idx], "-") != 0) {
		FILE* f = fopen(argv[idx], "rb");
		if (!f) { printf("File open fail\n"); return 1; }

		{ char v = 1; writePacket(uart, 0x35, &v, 1); }
		{ char v = 0; writePacket(uart, 0x35, &v, 1); }

		size_t total_read = 0xffffff;//10180;
		size_t pos = 0;

		while (pos < total_read) {
			char buf[16384];
			size_t want_read = (total_read - pos) > sizeof(buf) ? sizeof(buf) : (total_read - pos);
			size_t n = fread(buf, (size_t)1, want_read, f);
			if (n <= 0) {
				break;
			}
			writePacket(uart, 0x37, buf, n);
			pos += n;
		}

		wprintf(L"NES file transmitted over %s at baudrate %d.\n", com_port, baudrate);
	}

	if (readSerial)
		readFromSerial(uart);

	unsigned char last_keys1 = -1;
	unsigned char last_keys2 = -1;
	DWORD lastButtons = 0;
	DWORD lastPOV = 0;
	bool inOSD = false, osdPressed = false;

	for (;;) {
		JOYINFOEX joy;
		unsigned char keys1, keys2;

		joy.dwSize = sizeof(joy);
		joy.dwFlags = JOY_RETURNALL;

		// Process controller #1
		if (joyGetPosEx(JOYSTICKID1, &joy) != MMSYSERR_NOERROR) {
			printf("Cannot find any controller. Please connect a controller and try again.\n");
			return 1;
		}
		keys1 = joyinfoToKey(joy);

		// press controller #1 LB to toggle OSD
		if (joy.dwButtons & 0x10) {
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
			osd_update(keys1);
			goto joy_continue;
		}
		
		// Pass key to NES
		if (keys1 != last_keys1) {
			// printf("Keys %.2x\n", keys1);
			writePacket(uart, 0x40, &keys1, 1);
			last_keys1 = keys1;
		}

		// Process controller #2
		if (joyGetPosEx(JOYSTICKID2, &joy) == MMSYSERR_NOERROR) {
			keys2 = joyinfoToKey(joy);
			if (keys2 != last_keys2) {
				writePacket(uart, 0x41, &keys2, 1);
				last_keys2 = keys2;
			}
		}

	joy_continue:
		Sleep(1);
	}
	return 0;
}

