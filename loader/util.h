#pragma once

#include <string>
#include <filesystem>
#include <set>
#include <stdint.h>

#ifdef _MSC_VER
// Windows
#include <windows.h>
#define PATH(x) L ## x

#else
// Linux definitions
#define PATH(x) x

typedef uint32_t DWORD;
typedef int HANDLE;
typedef void * PVOID;

#endif

void readFromSerial(HANDLE h);
void writePacket(HANDLE h, int address, const void* data, size_t data_size);
HANDLE openSerialPort(std::filesystem::path serial, int baudrate);

#ifdef _MSC_VER
static std::wstring s2ws(const std::string& str)
{
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}
#endif

struct gamepad {
    unsigned char nesKeys;
    bool osdButton;
};

// scan for gamepads on the system
// return number of gamepads found
int scanGamepads();

// read latest status of up to two gamepads
// pad - pad[0], pad[1] are the two gamepad struct to be filled
// return number of gamepads found
int updateGamepads(gamepad *pad);

extern std::set<std::string> GAMEPADS;

extern char font8x8_basic[128][8];