#include <cstdio>
#include <cstring>
#include <vector>

#include "util.h"
namespace fs = std::filesystem;
using namespace std;

// Serial port functions and others

unsigned int swapbits(unsigned int a) {
	a &= 0xff;
	unsigned int b = 0;
	for (int i = 0; i < 8; i++, a >>= 1, b <<= 1) b |= (a & 1);
	return b >> 1;
}

#define POLY 0x8408
unsigned int crc16(uint8_t* data_p, uint16_t length, uint32_t crc)
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

unsigned int crc16b(uint8_t* data_p, uint16_t length, uint32_t crc) {
	uint8_t c[16], newcrc[16];
	uint8_t d[8];
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

// open serial port
#ifdef _MSC_VER
HANDLE openSerialPort(fs::path serial, int baudrate) {
	HANDLE uart = CreateFile(serial.wstring().c_str(), GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
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
    return uart;
}

#else

// Linux: https://www.pololu.com/docs/0J73/15.5
#include <fcntl.h> // Contains file controls like O_RDWR
#include <errno.h> // Error integer and strerror() function
#include <termios.h> // Contains POSIX terminal control definitions
#include <unistd.h> // write(), read(), close()
HANDLE openSerialPort(fs::path serial, int baudrate) {
    int uart = open(serial.string().c_str(), O_RDWR);
    if (uart < 0) {
        printf("Error %i from open: %s\n", errno, strerror(errno));
        return 0;
    }

    struct termios tty;
    if(tcgetattr(uart, &tty) != 0) {
        printf("Error %i from tcgetattr: %s\n", errno, strerror(errno));
        return 0;
    }
    // Turn off any options that might interfere with our ability to send and
    // receive raw binary bytes.
    tty.c_iflag &= ~(INLCR | IGNCR | ICRNL | IXON | IXOFF);
    tty.c_oflag &= ~(ONLCR | OCRNL);
    tty.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
 
    // Set up timeouts: Calls to read() will return as soon as there is
    // at least one byte available or when 100 ms has passed.
    tty.c_cc[VTIME] = 1;
    tty.c_cc[VMIN] = 0;

    cfsetspeed(&tty, baudrate);

    if (tcsetattr(uart, TCSANOW, &tty) != 0) {
       printf("Error %i from tcsetattr: %s\n", errno, strerror(errno));
    }

    return uart;
}
#endif

size_t formatPacket(uint8_t* buf, int address, const void* data, size_t data_size) {
	uint8_t* org = buf;
	while (data_size) {
		int n = data_size > 256 ? 256 : (int)data_size;
		int cksum = address + n;
		buf[1] = address;
		buf[2] = (uint8_t)n;
		for (int i = 0; i < n; i++) {
			int v = ((uint8_t*)data)[i];
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

extern bool dump_packet;

uint8_t buf[(3 + 64) * 256];

void writePacket(HANDLE h, int address, const void* data, size_t data_size) {
	size_t n = formatPacket(buf, address, data, data_size);
	DWORD written;

#ifdef _MSC_VER
	if (!WriteFile(h, buf, (DWORD)n, &written, NULL) || written != n) {
		printf("WriteFile failed\n");
		return;
	}
#else
    written = write(h, buf, n);
    if (written != n) {
        printf("write failed\n");
        return;
    }
#endif

	if (dump_packet) {
		for (int i = 0; i < n; i++)
			printf("%02x ", buf[i]);
		printf("\n");
	}
}

// continuously print serial input
#ifdef _MSC_VER
void readFromSerial(HANDLE h) {
	char b[128];
	DWORD read;
	OVERLAPPED ov = { 0 };
	ov.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	if (!ov.hEvent) {
		printf("Cannot create event\n");
		return;
	}

	while (1) {
		if (!ReadFile(h, b, sizeof(b) - 1, &read, &ov)) {
			printf("Readfile failed\n");
			goto done;
		}
		if (GetOverlappedResult(h, &ov, &read, TRUE)) {
			b[read] = '\0';
			printf("%s", b);
		}
	}

done:
	if (ov.hEvent != 0) CloseHandle(ov.hEvent);
}
#else
void readFromSerial(HANDLE h) {
	char b[128];
    size_t received = 0;
    while (1) {
        ssize_t r = read(h, b, sizeof(b)-1);
        if (r < 0)
        {
            perror("failed to read from port");
            return;
        }
        // if (r == 0) {
        //     // Timeout
        //     break;
        // }
        b[r] = '\0';
        printf("%s", b);
    }    
}
#endif


#ifdef _MSC_VER
// Windows gamepad support

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

int scanGamepads() {
    return 0;       // return value is not used
}

int updateGamepads(gamepad *pad) {
	JOYINFOEX joy;
    joy.dwSize = sizeof(joy);
    joy.dwFlags = JOY_RETURNALL;

    if (joyGetPosEx(JOYSTICKID1, &joy) != MMSYSERR_NOERROR)
        return 0;
    pad[0].nesKeys = joyinfoToKey(joy);
    pad[0].osdButton = joy.dwButtons & 0x10;

    if (joyGetPosEx(JOYSTICKID2, &joy) != MMSYSERR_NOERROR)
        return 1;
    pad[1].nesKeys = joyinfoToKey(joy);
    pad[1].osdButton = joy.dwButtons & 0x10;

    return 2;
}

#else
// Linux gamepad support through evdev

/*
evdev: /dev/input/event0

Xbox 360 controller:
    Input device ID: bus 0x3 vendor 0x45e product 0x2a1 version 0x100

A button: type 1, code 304
    Event: time 1666011315.117402, type: 1, code: 304, value: 1
    Event: time 1666011315.224379, type: 1, code: 304, value: 0
B button: type 1, code 305
X button: type 1, code 307
Y button: type 1, code 308
LB button: type 1, code 310
RB button: type 1, code 311

D-Pad Left: 1-704, 3-16 (-1)
    Event: time 1666011468.378533, type: 1, code: 704, value: 1
    Event: time 1666011468.378533, type: 3, code: 16, value: -1
    Event: time 1666011468.538558, type: 1, code: 704, value: 0
    Event: time 1666011468.538558, type: 3, code: 16, value: 0
D-Pad Right: 1-705, 3-16 (1)
D-Pad Up: 1-706, 3-17 (-1)
D-Pad down: 1-707, 3-17 (1)

L-Stick: 3-0 (X, -32768~32767), 3-1 (Y, -32768~32767)
    Event: time 1666011815.285503, type: 3, code: 1, value: 19078
*/

#include <dirent.h>
#include <linux/input.h>

static int pad[2];       // fd
static string padName[2];  // e.g.: "event9", "event10"

static int is_event_device(const struct dirent *dir) {
	return strncmp("event", dir->d_name, 5) == 0;
}

// compare names to already open gamepads, if same do nothing
// if different, then close open ones and open new gamepads
static void openPads(vector<string> names) {
    for (int i = 0; i < 2; i++) {
        if (i >= names.size() && padName[i] != "") {
            // some pad disconnected
            close(pad[i]);
            pad[i] = 0;
            padName[i] = "";
            continue;
        }
        if (i < names.size() && names[i] != padName[i]) {
            if (padName[i] != "")
                close(pad[i]);
            string p = "/dev/input/";
            p += names[i];
            printf("Opening gamepad %s\n", p.c_str());
            if ((pad[i] = open(p.c_str(), O_RDONLY)) < 0) {
                perror("");
                if (errno == EACCES && getuid() != 0) {
                    fprintf(stderr, "You do not have access to %s. Try "
                            "running as root instead.\n", p.c_str());          
                }      
                exit(1);
            }
            padName[i] = names[i];
        }
    }
}

// return: number of gamepads found
int scanGamepads() {
    struct dirent **namelist;
	int i, ndev, devnum;
	char *filename;
    unsigned short id[4];

	ndev = scandir("/dev/input", &namelist, is_event_device, alphasort);
	vector<string> names;
    for (int i = 0; i < ndev; i++) {
        struct dirent *e = namelist[i];
        char fname[267];
		snprintf(fname, sizeof(fname), "%s/%s", "/dev/input", e->d_name);
        int fd = open(fname, O_RDONLY);
        if (fd >= 0) {
        	ioctl(fd, EVIOCGID, id);
            char ids[10];
            snprintf(ids, sizeof(ids), "%04x:%04x", id[ID_VENDOR], id[ID_PRODUCT]);
            if (GAMEPADS.find(string(ids)) != GAMEPADS.end())
                names.push_back(string(e->d_name));
        }
    }
    printf("Found %d gamepads\n", (int)names.size());
    openPads(names);
    return names.size();
}

#include <sys/select.h>

void readGamepad(int fd, struct gamepad *p) {
    unsigned int size;
    struct input_event ev;

    while (1) {
        size = read(fd, &ev, sizeof(struct input_event));

        if (size < sizeof(struct input_event)) {
            printf("expected %lu bytes, got %u\n", sizeof(struct input_event), size);
            perror("\nerror reading");
            return;
        }
        if (ev.type == 0 && ev.code == 0) {
            // end of current batch of events
            return;
        }
        uint16_t t = ev.type;
        uint16_t c = ev.code;
        int v = ev.value;
        // printf("Event: time %ld.%06ld, ", ev.time.tv_sec, ev.time.tv_usec);
        // printf("type: %hu, code: %hu, value: %d\n", t, c, v);

        if (t == 1) {
            if (c == 304 || c == 307)   // map A and X to button A
                p->nesKeys = p->nesKeys & ~1 | v;
            else if (c == 305 || c == 308)  // B and y to button B
                p->nesKeys = p->nesKeys & ~2 | (v << 1);
            else if (c == 314)          // Select
                p->nesKeys = p->nesKeys & ~4 | (v << 2);
            else if (c == 315)          // Start
                p->nesKeys = p->nesKeys & ~8 | (v << 3);
            else if (c == 706)          // D-Pad up
                p->nesKeys = p->nesKeys & ~16 | (v << 4);
            else if (c == 707)          // D-Pad down
                p->nesKeys = p->nesKeys & ~32 | (v << 5);
            else if (c == 704)          // D-Pad left
                p->nesKeys = p->nesKeys & ~64 | (v << 6);
            else if (c == 705)          // D-Pad right
                p->nesKeys = p->nesKeys & ~128 | (v << 7);
            else if (c == 310)          // LB
                p->osdButton = (v == 1);
        } else if (t == 3) {
            const int HALF = 32768/2;
            if (c == 1) {
                p->nesKeys = p->nesKeys & ~16 | ((v < -HALF) << 4);     // stick up
                p->nesKeys = p->nesKeys & ~32 | ((v > HALF) << 5);    // stick down
            }
            if (c == 0)  {
                p->nesKeys = p->nesKeys & ~64 | ((v < -HALF) << 6);     // stick left
                p->nesKeys = p->nesKeys & ~128 | ((v > HALF) << 7);     // stick right
            }
        }
    }
}

int updateGamepads(gamepad *p) {
    fd_set fdset;
    FD_ZERO(&fdset);
    int cnt = 0;
    if (pad[0] > 0) {
        FD_SET(pad[0], &fdset);
        cnt++;
    }
    if (pad[1] > 0) {
        FD_SET(pad[1], &fdset);
        cnt++;
    }
    int maxfd = max(pad[0], pad[1]) + 1;
    int err = select(maxfd, &fdset, NULL, NULL, NULL);
    if (err == 0) {
        printf("select() timeout\n");
        return cnt;
    } else if (err < -1) {
        perror("select() error\n");
        return 0;
    }
    if (pad[0] > 0 && FD_ISSET(pad[0], &fdset))
        readGamepad(pad[0], p);
    if (pad[1] > 0 && FD_ISSET(pad[1], &fdset))
        readGamepad(pad[1], p+1);

    return cnt;
}

// https://gist.github.com/nondebug/aec93dff7f0f1969f4cc2291b24a3171
set<string> GAMEPADS = {
"0000:006f", "0001:0329", "0005:05ac", "0010:0082", "0078:0006", "0079:0006", 
"0079:0011", "0079:1800", "0079:181a", "0079:181b", "0079:181c", "0079:1830", 
"0079:1843", "0079:1844", "0079:1879", "0079:18d2", "0079:18d3", "0079:18d4", 
"0111:1417", "0111:1420", "040b:6530", "040b:6533", "0411:00c6", "041e:1003", 
"041e:1050", "0428:4001", "0433:1101", "044f:0f00", "044f:0f03", "044f:0f07", 
"044f:0f10", "044f:a0a3", "044f:b102", "044f:b300", "044f:b304", "044f:b312", 
"044f:b315", "044f:b320", "044f:b323", "044f:b326", "044f:b653", "044f:b65b", 
"044f:b671", "044f:b677", "044f:d001", "044f:d003", "044f:d008", "044f:d009", 
"045e:0007", "045e:000e", "045e:0026", "045e:0027", "045e:0028", "045e:0202", 
"045e:0285", "045e:0287", "045e:0288", "045e:0289", "045e:028e", "045e:0291", 
"045e:02a0", "045e:02a1", "045e:02d1", "045e:02dd", "045e:02e0", "045e:02e3", 
"045e:02ea", "045e:02fd", "045e:02ff", "045e:0719", "046d:c20b", "046d:c211", 
"046d:c215", "046d:c216", "046d:c218", "046d:c219", "046d:c21a", "046d:c21d", 
"046d:c21e", "046d:c21f", "046d:c242", "046d:c261", "046d:c299", "046d:c29a", 
"046d:c29b", "046d:ca84", "046d:ca88", "046d:ca8a", "046d:caa3", "046d:cad1", 
"046d:f301", "047d:4003", "047d:4005", "047d:4008", "04b4:010a", "04b4:c681", 
"04b4:d5d5", "04d9:0002", "04e8:a000", "0500:9b28", "050d:0802", "050d:0803", 
"050d:0805", "054c:0268", "054c:042f", "054c:05c4", "054c:05c5", "054c:09cc", 
"054c:0ba0", "056e:2003", "056e:2004", "057e:0306", "057e:0330", "057e:0337", 
"057e:2006", "057e:2007", "057e:2009", "057e:200e", "0583:2060", "0583:206f", 
"0583:3050", "0583:3051", "0583:a000", "0583:a009", "0583:a024", "0583:a025", 
"0583:a130", "0583:a133", "0583:b031", "05a0:3232", "05ac:022d", "05ac:033d", 
"05e3:0596", "05fd:1007", "05fd:107a", "05fd:3000", "05fe:0014", "05fe:3030", 
"05fe:3031", "062a:0020", "062a:0033", "062a:2410", "06a3:0109", "06a3:0200", 
"06a3:0201", "06a3:0241", "06a3:040b", "06a3:040c", "06a3:052d", "06a3:075c", 
"06a3:3509", "06a3:f518", "06a3:f51a", "06a3:f622", "06a3:f623", "06a3:ff0c", 
"06a3:ff0d", "06d6:0025", "06d6:0026", "06f8:a300", "0738:02a0", "0738:3250", 
"0738:3285", "0738:3384", "0738:3480", "0738:3481", "0738:4426", "0738:4506", 
"0738:4516", "0738:4520", "0738:4522", "0738:4526", "0738:4530", "0738:4536", 
"0738:4540", "0738:4556", "0738:4586", "0738:4588", "0738:45ff", "0738:4716", 
"0738:4718", "0738:4726", "0738:4728", "0738:4736", "0738:4738", "0738:4740", 
"0738:4743", "0738:4758", "0738:4a01", "0738:5266", "0738:6040", "0738:8180", 
"0738:8250", "0738:8384", "0738:8480", "0738:8481", "0738:8818", "0738:8838", 
"0738:9871", "0738:b726", "0738:b738", "0738:beef", "0738:cb02", "0738:cb03", 
"0738:cb29", "0738:f401", "0738:f738", "07b5:0213", "07b5:0312", "07b5:0314", 
"07b5:0315", "07b5:9902", "07ff:ffff", "0810:0001", "0810:0003", "0810:1e01", 
"0810:e501", "081f:e401", "0925:0005", "0925:03e8", "0925:1700", "0925:2801", 
"0925:8866", "0926:2526", "0926:8888", "0955:7210", "0955:7214", "0955:b400", 
"0b05:4500", "0c12:0005", "0c12:07f4", "0c12:08f1", "0c12:0e10", "0c12:0ef6", 
"0c12:1cf6", "0c12:8801", "0c12:8802", "0c12:8809", "0c12:880a", "0c12:8810", 
"0c12:9902", "0c45:4320", "0d2f:0002", "0e4c:1097", "0e4c:1103", "0e4c:2390", 
"0e4c:3510", "0e6f:0003", "0e6f:0005", "0e6f:0006", "0e6f:0008", "0e6f:0105", 
"0e6f:0113", "0e6f:011e", "0e6f:011f", "0e6f:0124", "0e6f:0125", "0e6f:0130", 
"0e6f:0131", "0e6f:0133", "0e6f:0139", "0e6f:013a", "0e6f:0146", "0e6f:0147", 
"0e6f:0158", "0e6f:015b", "0e6f:015c", "0e6f:0160", "0e6f:0161", "0e6f:0162", 
"0e6f:0163", "0e6f:0164", "0e6f:0165", "0e6f:0201", "0e6f:0213", "0e6f:021f", 
"0e6f:0246", "0e6f:02a0", "0e6f:02a4", "0e6f:02a6", "0e6f:02a7", "0e6f:02ab", 
"0e6f:02ad", "0e6f:0301", "0e6f:0346", "0e6f:0401", "0e6f:0413", "0e6f:0501", 
"0e6f:6302", "0e6f:f501", "0e6f:f701", "0e6f:f900", "0e8f:0003", "0e8f:0008", 
"0e8f:0012", "0e8f:0041", "0e8f:0201", "0e8f:1006", "0e8f:3008", "0e8f:3010", 
"0e8f:3013", "0e8f:3075", "0e8f:310d", "0f0d:000a", "0f0d:000c", "0f0d:000d", 
"0f0d:0010", "0f0d:0011", "0f0d:0016", "0f0d:001b", "0f0d:0022", "0f0d:0027", 
"0f0d:003d", "0f0d:0040", "0f0d:0049", "0f0d:004d", "0f0d:0055", "0f0d:005b", 
"0f0d:005c", "0f0d:005e", "0f0d:005f", "0f0d:0063", "0f0d:0066", "0f0d:0067", 
"0f0d:006a", "0f0d:006b", "0f0d:006e", "0f0d:0070", "0f0d:0078", "0f0d:0084", 
"0f0d:0085", "0f0d:0086", "0f0d:0087", "0f0d:0088", "0f0d:008a", "0f0d:008b", 
"0f0d:008c", "0f0d:0090", "0f0d:0092", "0f0d:00c5", "0f0d:00d8", "0f0d:00ee", 
"0f0d:0100", "0f30:010b", "0f30:0110", "0f30:0111", "0f30:0112", "0f30:0202", 
"0f30:0208", "0f30:1012", "0f30:1100", "0f30:1112", "0f30:1116", "0f30:8888", 
"102c:ff0c", "1038:1412", "1038:1420", "1080:0009", "10c4:82c0", "11c0:5213", 
"11c0:5506", "11c9:55f0", "11ff:3331", "11ff:3341", "1235:ab21", "124b:4d01", 
"1292:4e47", "12ab:0004", "12ab:0006", "12ab:0301", "12ab:0302", "12ab:0303", 
"12ab:8809", "12bd:c001", "12bd:d012", "12bd:d015", "12bd:e001", "1345:1000", 
"1345:3008", "1430:02a0", "1430:4734", "1430:4748", "1430:474c", "1430:8888", 
"1430:f801", "146b:0601", "146b:0d01", "146b:5500", "14d8:6208", "14d8:cd07", 
"14d8:cfce", "1532:0037", "1532:0300", "1532:0401", "1532:0900", "1532:0a00", 
"1532:0a03", "1532:0a14", "1532:1000", "15e4:3f00", "15e4:3f0a", "15e4:3f10", 
"162e:beef", "1689:0001", "1689:fd00", "1689:fd01", "1689:fe00", "1690:0001", 
"16c0:0487", "16c0:05e1", "16c0:0a99", "16d0:0a60", "16d0:0d04", "16d0:0d05", 
"16d0:0d06", "16d0:0d07", "1781:057e", "1781:0a96", "1781:0a9d", "18d1:2c40", 
"1949:0402", "19fa:0607", "1a15:2262", "1a34:0203", "1a34:0401", "1a34:0801", 
"1a34:0802", "1a34:0836", "1a34:f705", "1bad:0002", "1bad:0003", "1bad:0130", 
"1bad:028e", "1bad:0300", "1bad:5500", "1bad:f016", "1bad:f018", "1bad:f019", 
"1bad:f020", "1bad:f021", "1bad:f023", "1bad:f025", "1bad:f027", "1bad:f028", 
"1bad:f02d", "1bad:f02e", "1bad:f030", "1bad:f036", "1bad:f038", "1bad:f039", 
"1bad:f03a", "1bad:f03d", "1bad:f03e", "1bad:f03f", "1bad:f042", "1bad:f080", 
"1bad:f0ca", "1bad:f501", "1bad:f502", "1bad:f503", "1bad:f504", "1bad:f505", 
"1bad:f506", "1bad:f900", "1bad:f901", "1bad:f902", "1bad:f903", "1bad:f904", 
"1bad:f906", "1bad:f907", "1bad:fa01", "1bad:fd00", "1bad:fd01", "1d50:6053", 
"1d79:0301", "1dd8:000b", "1dd8:000f", "1dd8:0010", "2002:9000", "20bc:5500", 
"20d6:0dad", "20d6:281f", "20d6:6271", "20d6:89e5", "20d6:ca6d", "20e8:5860", 
"2222:0060", "2222:4010", "22ba:1020", "2378:1008", "2378:100a", "24c6:5000", 
"24c6:5300", "24c6:5303", "24c6:530a", "24c6:531a", "24c6:5397", "24c6:541a", 
"24c6:542a", "24c6:543a", "24c6:5500", "24c6:5501", "24c6:5502", "24c6:5503", 
"24c6:5506", "24c6:550d", "24c6:550e", "24c6:5510", "24c6:551a", "24c6:561a", 
"24c6:5b00", "24c6:5b02", "24c6:5b03", "24c6:5d04", "24c6:fafa", "24c6:fafb", 
"24c6:fafc", "24c6:fafd", "24c6:fafe", "2563:0523", "2563:0547", "2563:0575", 
"25f0:83c1", "25f0:c121", "2717:3144", "2810:0009", "2836:0001", "289b:0003", 
"289b:0005", "289b:0026", "289b:002e", "289b:002f", "28de:0476", "28de:1102", 
"28de:1142", "28de:11fc", "28de:11ff", "28de:1201", "2c22:2000", "2c22:2300", 
"2c22:2302", "2dc8:1003", "2dc8:1080", "2dc8:2810", "2dc8:2820", "2dc8:2830", 
"2dc8:2840", "2dc8:3000", "2dc8:3001", "2dc8:3810", "2dc8:3820", "2dc8:3830", 
"2dc8:6000", "2dc8:6001", "2dc8:6100", "2dc8:6101", "2dc8:9000", "2dc8:9001", 
"2dc8:9002", "2dc8:ab11", "2dc8:ab12", "2dc8:ab20", "2dc8:ab21", "2dfa:0001", 
"2e24:1688", "3767:0101", "3820:0009", "6666:0667", "6666:8804", "8000:1002", 
"8888:0308", "aa55:0101", "d209:0450", "f000:0003", "f000:0008", "f000:00f1", 
"f766:0001", "f766:0005"
};

#endif

/**
 * 8x8 monochrome bitmap fonts for rendering
 * Author: Daniel Hepper <daniel@hepper.net>
 *
 * License: Public Domain
 *
 * Based on:
 * // Summary: font8x8.h
 * // 8x8 monochrome bitmap fonts for rendering
 * //
 * // Author:
 * //     Marcel Sondaar
 * //     International Business Machines (public domain VGA fonts)
 * //
 * // License:
 * //     Public Domain
 *
 * Fetched from: http://dimensionalrift.homelinux.net/combuster/mos3/?p=viewsource&file=/modules/gfx/font8_8.asm
 **/
 // Constant: font8x8_basic
 // Contains an 8x8 font map for unicode points U+0000 - U+007F (basic latin)
char font8x8_basic[128][8] = {
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0000 (nul)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0001
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0002
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0003
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0004
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0005
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0006
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0007
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0008
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0009
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000A
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000B
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000C
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000D
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000E
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+000F
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0010
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0011
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0012
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0013
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0014
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0015
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0016
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0017
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0018
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0019
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001A
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001B
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001C
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001D
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001E
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+001F
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0020 (space)
    { 0x18, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x18, 0x00},   // U+0021 (!)
    { 0x36, 0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0022 (")
    { 0x36, 0x36, 0x7F, 0x36, 0x7F, 0x36, 0x36, 0x00},   // U+0023 (#)
    { 0x0C, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x0C, 0x00},   // U+0024 ($)
    { 0x00, 0x63, 0x33, 0x18, 0x0C, 0x66, 0x63, 0x00},   // U+0025 (%)
    { 0x1C, 0x36, 0x1C, 0x6E, 0x3B, 0x33, 0x6E, 0x00},   // U+0026 (&)
    { 0x06, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0027 (')
    { 0x18, 0x0C, 0x06, 0x06, 0x06, 0x0C, 0x18, 0x00},   // U+0028 (()
    { 0x06, 0x0C, 0x18, 0x18, 0x18, 0x0C, 0x06, 0x00},   // U+0029 ())
    { 0x00, 0x66, 0x3C, (char)0xFF, 0x3C, 0x66, 0x00, 0x00},   // U+002A (*)
    { 0x00, 0x0C, 0x0C, 0x3F, 0x0C, 0x0C, 0x00, 0x00},   // U+002B (+)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x06},   // U+002C (,)
    { 0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x00},   // U+002D (-)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x00},   // U+002E (.)
    { 0x60, 0x30, 0x18, 0x0C, 0x06, 0x03, 0x01, 0x00},   // U+002F (/)
    { 0x3E, 0x63, 0x73, 0x7B, 0x6F, 0x67, 0x3E, 0x00},   // U+0030 (0)
    { 0x0C, 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x3F, 0x00},   // U+0031 (1)
    { 0x1E, 0x33, 0x30, 0x1C, 0x06, 0x33, 0x3F, 0x00},   // U+0032 (2)
    { 0x1E, 0x33, 0x30, 0x1C, 0x30, 0x33, 0x1E, 0x00},   // U+0033 (3)
    { 0x38, 0x3C, 0x36, 0x33, 0x7F, 0x30, 0x78, 0x00},   // U+0034 (4)
    { 0x3F, 0x03, 0x1F, 0x30, 0x30, 0x33, 0x1E, 0x00},   // U+0035 (5)
    { 0x1C, 0x06, 0x03, 0x1F, 0x33, 0x33, 0x1E, 0x00},   // U+0036 (6)
    { 0x3F, 0x33, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x00},   // U+0037 (7)
    { 0x1E, 0x33, 0x33, 0x1E, 0x33, 0x33, 0x1E, 0x00},   // U+0038 (8)
    { 0x1E, 0x33, 0x33, 0x3E, 0x30, 0x18, 0x0E, 0x00},   // U+0039 (9)
    { 0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x00},   // U+003A (:)
    { 0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x06},   // U+003B (;)
    { 0x18, 0x0C, 0x06, 0x03, 0x06, 0x0C, 0x18, 0x00},   // U+003C (<)
    { 0x00, 0x00, 0x3F, 0x00, 0x00, 0x3F, 0x00, 0x00},   // U+003D (=)
    { 0x06, 0x0C, 0x18, 0x30, 0x18, 0x0C, 0x06, 0x00},   // U+003E (>)
    { 0x1E, 0x33, 0x30, 0x18, 0x0C, 0x00, 0x0C, 0x00},   // U+003F (?)
    { 0x3E, 0x63, 0x7B, 0x7B, 0x7B, 0x03, 0x1E, 0x00},   // U+0040 (@)
    { 0x0C, 0x1E, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x00},   // U+0041 (A)
    { 0x3F, 0x66, 0x66, 0x3E, 0x66, 0x66, 0x3F, 0x00},   // U+0042 (B)
    { 0x3C, 0x66, 0x03, 0x03, 0x03, 0x66, 0x3C, 0x00},   // U+0043 (C)
    { 0x1F, 0x36, 0x66, 0x66, 0x66, 0x36, 0x1F, 0x00},   // U+0044 (D)
    { 0x7F, 0x46, 0x16, 0x1E, 0x16, 0x46, 0x7F, 0x00},   // U+0045 (E)
    { 0x7F, 0x46, 0x16, 0x1E, 0x16, 0x06, 0x0F, 0x00},   // U+0046 (F)
    { 0x3C, 0x66, 0x03, 0x03, 0x73, 0x66, 0x7C, 0x00},   // U+0047 (G)
    { 0x33, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x33, 0x00},   // U+0048 (H)
    { 0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00},   // U+0049 (I)
    { 0x78, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E, 0x00},   // U+004A (J)
    { 0x67, 0x66, 0x36, 0x1E, 0x36, 0x66, 0x67, 0x00},   // U+004B (K)
    { 0x0F, 0x06, 0x06, 0x06, 0x46, 0x66, 0x7F, 0x00},   // U+004C (L)
    { 0x63, 0x77, 0x7F, 0x7F, 0x6B, 0x63, 0x63, 0x00},   // U+004D (M)
    { 0x63, 0x67, 0x6F, 0x7B, 0x73, 0x63, 0x63, 0x00},   // U+004E (N)
    { 0x1C, 0x36, 0x63, 0x63, 0x63, 0x36, 0x1C, 0x00},   // U+004F (O)
    { 0x3F, 0x66, 0x66, 0x3E, 0x06, 0x06, 0x0F, 0x00},   // U+0050 (P)
    { 0x1E, 0x33, 0x33, 0x33, 0x3B, 0x1E, 0x38, 0x00},   // U+0051 (Q)
    { 0x3F, 0x66, 0x66, 0x3E, 0x36, 0x66, 0x67, 0x00},   // U+0052 (R)
    { 0x1E, 0x33, 0x07, 0x0E, 0x38, 0x33, 0x1E, 0x00},   // U+0053 (S)
    { 0x3F, 0x2D, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00},   // U+0054 (T)
    { 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x3F, 0x00},   // U+0055 (U)
    { 0x33, 0x33, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00},   // U+0056 (V)
    { 0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00},   // U+0057 (W)
    { 0x63, 0x63, 0x36, 0x1C, 0x1C, 0x36, 0x63, 0x00},   // U+0058 (X)
    { 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x0C, 0x1E, 0x00},   // U+0059 (Y)
    { 0x7F, 0x63, 0x31, 0x18, 0x4C, 0x66, 0x7F, 0x00},   // U+005A (Z)
    { 0x1E, 0x06, 0x06, 0x06, 0x06, 0x06, 0x1E, 0x00},   // U+005B ([)
    { 0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x40, 0x00},   // U+005C (\)
    { 0x1E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1E, 0x00},   // U+005D (])
    { 0x08, 0x1C, 0x36, 0x63, 0x00, 0x00, 0x00, 0x00},   // U+005E (^)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, (char)0xFF},   // U+005F (_)
    { 0x0C, 0x0C, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+0060 (`)
    { 0x00, 0x00, 0x1E, 0x30, 0x3E, 0x33, 0x6E, 0x00},   // U+0061 (a)
    { 0x07, 0x06, 0x06, 0x3E, 0x66, 0x66, 0x3B, 0x00},   // U+0062 (b)
    { 0x00, 0x00, 0x1E, 0x33, 0x03, 0x33, 0x1E, 0x00},   // U+0063 (c)
    { 0x38, 0x30, 0x30, 0x3e, 0x33, 0x33, 0x6E, 0x00},   // U+0064 (d)
    { 0x00, 0x00, 0x1E, 0x33, 0x3f, 0x03, 0x1E, 0x00},   // U+0065 (e)
    { 0x1C, 0x36, 0x06, 0x0f, 0x06, 0x06, 0x0F, 0x00},   // U+0066 (f)
    { 0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x1F},   // U+0067 (g)
    { 0x07, 0x06, 0x36, 0x6E, 0x66, 0x66, 0x67, 0x00},   // U+0068 (h)
    { 0x0C, 0x00, 0x0E, 0x0C, 0x0C, 0x0C, 0x1E, 0x00},   // U+0069 (i)
    { 0x30, 0x00, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E},   // U+006A (j)
    { 0x07, 0x06, 0x66, 0x36, 0x1E, 0x36, 0x67, 0x00},   // U+006B (k)
    { 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00},   // U+006C (l)
    { 0x00, 0x00, 0x33, 0x7F, 0x7F, 0x6B, 0x63, 0x00},   // U+006D (m)
    { 0x00, 0x00, 0x1F, 0x33, 0x33, 0x33, 0x33, 0x00},   // U+006E (n)
    { 0x00, 0x00, 0x1E, 0x33, 0x33, 0x33, 0x1E, 0x00},   // U+006F (o)
    { 0x00, 0x00, 0x3B, 0x66, 0x66, 0x3E, 0x06, 0x0F},   // U+0070 (p)
    { 0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x78},   // U+0071 (q)
    { 0x00, 0x00, 0x3B, 0x6E, 0x66, 0x06, 0x0F, 0x00},   // U+0072 (r)
    { 0x00, 0x00, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x00},   // U+0073 (s)
    { 0x08, 0x0C, 0x3E, 0x0C, 0x0C, 0x2C, 0x18, 0x00},   // U+0074 (t)
    { 0x00, 0x00, 0x33, 0x33, 0x33, 0x33, 0x6E, 0x00},   // U+0075 (u)
    { 0x00, 0x00, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00},   // U+0076 (v)
    { 0x00, 0x00, 0x63, 0x6B, 0x7F, 0x7F, 0x36, 0x00},   // U+0077 (w)
    { 0x00, 0x00, 0x63, 0x36, 0x1C, 0x36, 0x63, 0x00},   // U+0078 (x)
    { 0x00, 0x00, 0x33, 0x33, 0x33, 0x3E, 0x30, 0x1F},   // U+0079 (y)
    { 0x00, 0x00, 0x3F, 0x19, 0x0C, 0x26, 0x3F, 0x00},   // U+007A (z)
    { 0x38, 0x0C, 0x0C, 0x07, 0x0C, 0x0C, 0x38, 0x00},   // U+007B ({)
    { 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x00},   // U+007C (|)
    { 0x07, 0x0C, 0x0C, 0x38, 0x0C, 0x0C, 0x07, 0x00},   // U+007D (})
    { 0x6E, 0x3B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},   // U+007E (~)
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}    // U+007F
};