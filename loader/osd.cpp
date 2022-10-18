#include <cstdio>
#include <filesystem>
#include <iostream>
namespace fs = std::filesystem;		// C++17
#include <vector>
#include <chrono>
#include <cstring>

#include "osd.h"
#include "util.h"

using namespace std;

static const int CMD_OSD_ADDR_LOW = 0x80;
static const int CMD_OSD_ADDR_HIGH = 0x81;
static const int CMD_OSD_DATA = 0x82;
static const int CMD_OSD_SHOW = 0x83;

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

	//printf("OSD flush: %d ~ %d\n", osd_dirty_top, osd_dirty_bottom);

	// {Y[6:0],X[4:0]}
	int addr = osd_dirty_top << 5;
	unsigned char addr_lo = addr & 0xff;
	unsigned char addr_hi = (addr >> 8) & 0xff;

	writePacket(h, CMD_OSD_ADDR_LOW, &addr_lo, 1);
	writePacket(h, CMD_OSD_ADDR_HIGH, &addr_hi, 1);
	writePacket(h, CMD_OSD_DATA, osdbuf + addr, 32 * 8 * (osd_dirty_bottom - osd_dirty_top));

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
	writePacket(uart, CMD_OSD_SHOW, &v, 1);
	osd_update(-1);
	active = show;
}

extern fs::path gamedir;

// current dir
struct fileentry {
	string name;
	fs::path path;
};
static vector<fs::path> paths;		// last is the current dir
static vector<fileentry> files;		// a list of files in current dir
static int filePageStart, fileCur;	// index of page start and current file

void osd_setgamedir(wstring dir) {
	paths.clear();
	paths.push_back(fs::path(dir));
}

// populate `files`
void load_dir() {
	files.clear();
	if (paths.empty())
		return;
	fs::path p = paths.back();
	if (paths.size() > 1) {
		fileentry e = { "..", p.parent_path() };
		files.push_back(e);
	}
	for (const auto& entry : fs::directory_iterator(p)) {
		//cout << entry.path() << endl;
		string suffix = entry.is_directory() ? "/" : "";
		fileentry e = { entry.path().filename().string() + suffix, entry.path() };
		files.push_back(e);
	}
}

static void screen_top(unsigned char key);
extern int sendNES(fs::path p);
extern bool inOSD;

static void screen_dir(unsigned char key) {
	if (key == 1) {			// A - choose dir or file
		if (files[fileCur].name == ".." || files[fileCur].name.back() == '/') {
			// it's a dir, cd to it
			if (files[fileCur].name == "..")
				paths.pop_back();		// go to parent dir
			else
				paths.push_back(files[fileCur].path);
			load_dir();
			filePageStart = 0; fileCur = 0;
		}
		else {
			// it's a file, send it and close OSD
			inOSD = false;
			osd_show(false);
			sendNES(files[fileCur].path);
			return;
		}
	}
	else if (key == 2) {	// B - return to parent dir or top menu
		if (paths.size() > 1) {
			paths.pop_back();
			load_dir();
			filePageStart = 0; fileCur = 0;
		} else {
			screen = SCREEN_TOP;
			screen_top(0);
			return;
		}
	}
	else if (key == 16) {	// up
		if (fileCur > 0) {
			fileCur--;
			if (filePageStart > fileCur)
				filePageStart = fileCur;
		}
	}
	else if (key == 32) {	// down
		if (fileCur < files.size()-1) {
			fileCur++;
			if (filePageStart < fileCur - 15)
				filePageStart = fileCur - 15;
		}
	}
	// update OSD
	osd_clear();
	for (int i = 0; i < 16 && filePageStart + i < files.size(); i++) {
		int pos = filePageStart + i;
		osd_print(1, i, files[pos].name.c_str());
		if (pos == fileCur)
			osd_invert(0, i, 32);
	}
	osd_flush(uart);
}

static void screen_top(unsigned char key) {
	//printf("screen_top\n");
	if (key == 1) {			// A
		screen = SCREEN_DIR;
		paths.clear();
		paths.push_back(gamedir);
		load_dir();
		filePageStart = 0; fileCur = 0;
		screen_dir(0);
		return;
	}		

	//printf("TOP screen\n");
	osd_clear();
	osd_print(7, 1, "Welcome to NESTang");
	osd_print(1, 7, "Load .nes");
	osd_print(1, 14, "github.com/nand2mario/nestang");
	osd_invert(0, 7, 32);		// highlight our "menu item"

	osd_flush(uart);
}

using namespace std::chrono;
#define GET_TIME() duration_cast< milliseconds >(system_clock::now().time_since_epoch());

// A keypress, key == 255 means just show the page
static unsigned char lastKey = 0;
static milliseconds lastTime;
static bool keyRepeat;

void osd_update(unsigned char key, bool force) {
	milliseconds now = GET_TIME();
	int dur = (int)(now - lastTime).count();

	if (!force && key == lastKey) {
		if (!keyRepeat && dur < 500 || keyRepeat && dur < 50)
			return;
		keyRepeat = true;
	}
	if (key != lastKey) keyRepeat = false;

	//printf("osd_update: key=%d, screen=%d\n", key, screen);
	lastKey = key;
	lastTime = now;
	switch (screen) {
	case SCREEN_TOP:
		screen_top(key);
		break;
	case SCREEN_DIR:
		screen_dir(key);
		break;
	}
}