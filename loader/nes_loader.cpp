#include "stdafx.h"
#define	_CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// print serial input
DWORD WINAPI ReadFromSerial(PVOID lpParam) {
	char b[128];
	DWORD read;
	HANDLE h = (HANDLE)lpParam;
	OVERLAPPED ov = { 0 };
	ov.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	if (!ov.hEvent) {
		printf("Cannot create event\n");
		return 1;
	}

	while (1) {
		if (!ReadFile(h, b, sizeof(b) - 1, &read, &ov)) {
			printf("Readfile failed\n");
			goto done;
		}
		if (GetOverlappedResult(h, &ov, &read, TRUE)) {
			b[read] = '\0';
			printf(b);
		}
	}

done:
	if (ov.hEvent != 0) CloseHandle(ov.hEvent);
	return 0;
}

unsigned int swapbits(unsigned int a) {
	a &= 0xff;
	unsigned int b = 0;
	for (int i = 0; i < 8; i++, a >>= 1, b <<= 1) b |= (a & 1);
	return b >> 1;
}

#define POLY 0x8408
unsigned int crc16(BYTE* data_p, unsigned short length, unsigned int crc)
{
	unsigned char i;
	unsigned int data;
	if (length == 0)
		return crc;
	do {
		for (i = 0, data = (unsigned int)0xff & *data_p++; i < 8; i++, data <<= 1) {
			if ((crc & 0x0001) ^ ((data >> 7) & 0x0001))
				crc = (crc >> 1) ^ POLY;
			else  crc >>= 1;
		}
	} while (--length);
	return crc;
}

unsigned int crc16b(BYTE* data_p, unsigned short length, unsigned int crc) {
	byte c[16], newcrc[16];
	byte d[8];
	for (int j = 0; j < 16; j++) c[j] = (crc >> (15 - j)) & 1;

	for (int i = 0; i < length; i++) {
		for (int j = 0; j < 8; j++) d[j] = (data_p[i] >> j) & 1;

		newcrc[0] = d[4] ^ d[0] ^ c[8] ^ c[12];
		newcrc[1] = d[5] ^ d[1] ^ c[9] ^ c[13];
		newcrc[2] = d[6] ^ d[2] ^ c[10] ^ c[14];
		newcrc[3] = d[7] ^ d[3] ^ c[11] ^ c[15];
		newcrc[4] = d[4] ^ c[12];
		newcrc[5] = d[5] ^ d[4] ^ d[0] ^ c[8] ^ c[12] ^ c[13];
		newcrc[6] = d[6] ^ d[5] ^ d[1] ^ c[9] ^ c[13] ^ c[14];
		newcrc[7] = d[7] ^ d[6] ^ d[2] ^ c[10] ^ c[14] ^ c[15];
		newcrc[8] = d[7] ^ d[3] ^ c[0] ^ c[11] ^ c[15];
		newcrc[9] = d[4] ^ c[1] ^ c[12];
		newcrc[10] = d[5] ^ c[2] ^ c[13];
		newcrc[11] = d[6] ^ c[3] ^ c[14];
		newcrc[12] = d[7] ^ d[4] ^ d[0] ^ c[4] ^ c[8] ^ c[12] ^ c[15];
		newcrc[13] = d[5] ^ d[1] ^ c[5] ^ c[9] ^ c[13];
		newcrc[14] = d[6] ^ d[2] ^ c[6] ^ c[10] ^ c[14];
		newcrc[15] = d[7] ^ d[3] ^ c[7] ^ c[11] ^ c[15];

		memcpy(c, newcrc, 16);
	}

	unsigned int r = 0;
	for (int j = 0; j < 16; j++) r = r * 2 + c[j];
	return r;
}

size_t FormatPacket(byte* buf, int address, const void* data, int data_size) {
	byte* org = buf;
	while (data_size) {
		int n = data_size > 256 ? 256 : data_size;
		int cksum = address + n;
		buf[1] = address;
		buf[2] = n;
		for (int i = 0; i < n; i++) {
			int v = ((byte*)data)[i];
			buf[i + 3] = v;
			cksum += v;
		}
		buf[0] = -cksum;
		buf += n + 3;
		data = (char*)data + n;
		data_size -= n;
	}
	return buf - org;
}

bool dump_packet = false;

byte buf[(3 + 64) * 256];

void WritePacket(HANDLE h, int address, const void* data, size_t data_size) {
	size_t n = FormatPacket(buf, address, data, data_size);
	DWORD written;
	if (!WriteFile(h, buf, n, &written, NULL) || written != n) {
		printf("WriteFile failed\n");
		return;
	}

	if (dump_packet) {
		for (int i = 0; i < n; i++)
			printf("%02x ", buf[i]);
		printf("\n");
	}
}

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

#define BAUDRATE 921600

wchar_t com_port[256] = L"\\\\.\\COM10";
bool readSerial = false;

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
			else if (strcmp(argv[idx], "-v") == 0) {
				dump_packet = true;
			}
			else if (strcmp(argv[idx], "-c") == 0 && idx + 1 < argc) {
				mbstowcs(com_port, argv[++idx], sizeof(com_port));
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
		printf("Usage: loader [options] <game.nes>\n");
		printf("Options:\n");
		printf("    -c COM4    use specific COM port.\n");
		printf("    -r         display message from serial for debug.\n");
		printf("    -v         verbose. print packets sent.\n");
		return -1;
	}
	return idx;
}


int main(int argc, char* argv[]) {
	int idx = parseArgs(argc, argv);
	if (idx < 0) {
		return 1;
	}

	HANDLE h = CreateFile(com_port, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (!h) {
		printf("CreateFile failed\n");
		return 0;
	}

	DCB dcb = { 0 };
	dcb.DCBlength = sizeof(DCB);
	dcb.ByteSize = 8;
	dcb.StopBits = ONESTOPBIT;
	dcb.BaudRate = BAUDRATE;
	//dcb.BaudRate = 115200;
	dcb.fBinary = TRUE;
	if (!SetCommState(h, &dcb)) {
		printf("SetCommState failed\n");
		return 0;
	}

	// Create serial input thread
	HANDLE t;
	DWORD tid;

	FILE* f = fopen(argv[idx], "rb");
	if (!f) { printf("File open fail\n"); return 1; }

	{ char v = 1; WritePacket(h, 0x35, &v, 1); }
	{ char v = 0; WritePacket(h, 0x35, &v, 1); }

	size_t total_read = 0xffffff;//10180;
	size_t pos = 0;

	while (pos < total_read) {
		char buf[16384];
		size_t want_read = (total_read - pos) > sizeof(buf) ? sizeof(buf) : (total_read - pos);
		int n = fread(buf, 1, want_read, f);
		if (n <= 0) {
			break;
		}
		WritePacket(h, 0x37, buf, n);
		pos += n;
	}

	wprintf(L"NES file transmitted over %s at baudrate %d.\n", com_port, BAUDRATE);

	if (readSerial)
		ReadFromSerial(h);

	unsigned char last_keys1 = -1;
	unsigned char last_keys2 = -1;
	DWORD lastButtons = 0;
	DWORD lastPOV = 0;

	for (;;) {
		JOYINFOEX joy;
		joy.dwSize = sizeof(joy);
		joy.dwFlags = JOY_RETURNALL;

		// Process controller #1
		if (joyGetPosEx(JOYSTICKID1, &joy) != MMSYSERR_NOERROR) {
			printf("Cannot find any controller. Please connect a controller and try again.\n");
			return 1;
		}
		unsigned char keys1 = joyinfoToKey(joy);
		if (keys1 != last_keys1) {
			//        printf("Keys %.2x\n", keys);
			WritePacket(h, 0x40, &keys1, 1);
			last_keys1 = keys1;
		}

		// Process controller #2
		unsigned char keys2 = 0;

		if (joyGetPosEx(JOYSTICKID2, &joy) == MMSYSERR_NOERROR) {
			keys2 = joyinfoToKey(joy);
			if (keys2 != last_keys2) {
				WritePacket(h, 0x41, &keys2, 1);
				last_keys2 = keys2;
			}
		}

		/*
		if (lastButtons != joy.dwButtons) {
			printf("%x\n", joy.dwButtons);
			lastButtons = joy.dwButtons;
		}
		if (lastPOV != joy.dwPOV) {
			printf("%d\n", joy.dwPOV);
			lastPOV = joy.dwPOV;
		}

	*/
		Sleep(1);
	}
	return 0;
}

