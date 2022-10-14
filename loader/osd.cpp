#include <windows.h>
#include <cstdio>
#include <filesystem>
#include <iostream>
namespace fs = std::filesystem;		// C++17
#include <vector>

using namespace std;

#include "OSD.h"
#include "util.h"

char osdbuf[4096];			// 256*128 mono, every line is 32 bytes
int osd_dirty_top = 0, osd_dirty_bottom = 16;		// in text lines
void osd_flush(HANDLE h);

// print a string to OSD
// x: 0 - 31, y: 0 - 15
// h: pass 0 for delayed flush
void osd_print(int x, int y, const char* s, HANDLE h = 0) {
	if (x < 0 || x >= 32 || y < 0 || y >= 16)
		return;

	// 1. update in-memory buffer 
	size_t c = strlen(s);
	for (int xx = x; xx < x + c && xx < 32; xx++) {
		char* ch = font8x8_basic[s[xx - x]];
		for (int l = 0; l < 8; l++)		// 8 scanlines
			osdbuf[(y * 8 + l) * 32 + xx] = ch[l];
	}
	if (osd_dirty_top == -1 || osd_dirty_top > y)
		osd_dirty_top = y;
	if (osd_dirty_bottom == -1 || osd_dirty_bottom < y + 1)
		osd_dirty_bottom = y + 1;

	// 2. send the corresponding lines over UART
	if (h) osd_flush(h);
}

// invert a number of characters
// x: 0 - 31, y: 0 - 15
// h: pass 0 for delayed flush
void osd_invert(int x, int y, int len, HANDLE h = 0) {
	if (x < 0 || x >= 32 || y < 0 || y >= 16)
		return;
	for (int l = 0; l < 8; l++)
		for (int xx = x; xx < x + len && xx < 32; xx++)
			osdbuf[(y * 8 + l) * 32 + xx] ^= 0xff;
	if (h) osd_flush(h);
}

void osd_clear(HANDLE h = 0) {
	memset(osdbuf, 0, sizeof(osdbuf));
	osd_dirty_top = 0;
	osd_dirty_bottom = 16;
	if (h) osd_flush(h);
}

// send OSD updates to device
void osd_flush(HANDLE h) {
	if (osd_dirty_top == -1)
		return;

	printf("OSD flush: %d ~ %d\n", osd_dirty_top, osd_dirty_bottom);

	// {Y[6:0],X[4:0]}
	int addr = osd_dirty_top << 5;
	unsigned char addr_lo = addr & 0xff;
	unsigned char addr_hi = (addr >> 8) & 0xff;

	writePacket(h, 0x80, &addr_lo, 1);
	writePacket(h, 0x81, &addr_hi, 1);
	writePacket(h, 0x82, osdbuf + addr, 32 * 8 * (osd_dirty_bottom - osd_dirty_top));

	osd_dirty_top = -1;
	osd_dirty_bottom = -1;
}

extern HANDLE uart;

static const int SCREEN_TOP = 0;
static const int SCREEN_DIR = 1;

static int lastScreen = -1;
static int screen = SCREEN_TOP;
static char dir[] = "games";
static bool active = false;

// Change visibility of OSD
void osd_show(bool show) {
	printf("OSD is %s\n", show ? "on" : "off");
	if (!active && show) {
		// when turning on OSD, return to top page
		screen = SCREEN_TOP;
	}
	
	char v = show ? 1 : 0;
	writePacket(uart, 0x83, &v, 1);
	osd_update(-1);
	active = show;
}

extern wstring gamedir;

// current dir
static vector<fs::path> paths;		// last the current dir
static vector<fs::path> files;
static int filePageStart, fileCur;	// index of page start and current file

void osd_setgamedir(std::wstring dir) {
	paths.clear();
	paths.push_back(fs::path(dir));
}

static void screen_dir(unsigned char key) {
	if (key == 1) {			// A - choose file
	}
	else if (key == 2) {	// B - cancel
	}
	osd_clear();
	for (int i = 0; i < 16 && filePageStart + i < files.size(); i++) {
		int pos = filePageStart + i;
		osd_print(1, i, files[pos].filename().string().c_str());
		if (pos == fileCur)
			osd_invert(0, i, 32);
	}
	osd_flush(uart);
}

// populate `files`
void load_dir() {
	files.clear();
	if (paths.empty())
		return;
	fs::path p = paths.back();
	if (paths.size() > 1) {
		files.push_back(p.parent_path());
	}
	for (const auto& entry : fs::directory_iterator(p)) {
		cout << entry.path() << endl;
		files.push_back(entry.path());
	}
}

extern wstring gamedir;

static void screen_top(unsigned char key) {
	printf("screen_top\n");
	if (key == 1) {			// A
		screen = SCREEN_DIR;
		paths.clear();
		paths.push_back(fs::path(gamedir));
		load_dir();
		filePageStart = 0; fileCur = 0;
		screen_dir(0);
		return;
	}		

	printf("TOP screen\n");
	osd_clear();
	osd_print(6, 1, "Welcome to NESTang");

	osd_print(0, 8, "Load .nes");
	osd_invert(0, 8, 32);		// highlight our "menu item"

	osd_flush(uart);
}

// A keypress, key == 255 means just show the page
static unsigned char lastKey = 0;
void osd_update(unsigned char key, bool force) {
	if (!force && key == lastKey) {
		return;
	}
	printf("osd_update: key=%d, screen=%d\n", key, screen);
	lastKey = key;
	switch (screen) {
	case SCREEN_TOP:
		screen_top(key);
		break;
	case SCREEN_DIR:
		screen_dir(key);
		break;
	}
}