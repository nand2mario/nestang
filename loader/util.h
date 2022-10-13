#pragma once
#include <windows.h>
#include <string>

DWORD readFromSerial(PVOID lpParam);
void writePacket(HANDLE h, int address, const void* data, size_t data_size);

static std::wstring s2ws(const std::string& str)
{
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

extern char font8x8_basic[128][8];