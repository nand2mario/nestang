#include "picorv32.h"
#include <stdarg.h>
#include <limits.h>

#define FREQ 10800000

int curx, cury;

void cursor(int x, int y) {
   curx = x;
   cury = y;
}

int _overlay_status;

void overlay(int on) {
   if (on)
      reg_textdisp = 0x01000000;
   else
      reg_textdisp = 0x02000000;
   _overlay_status = on;
}

int overlay_status() {
   return _overlay_status;
}

int putchar(int c)
{
	if (curx >= 0 && curx < 32 && cury >= 0 && cury < 28) {
      reg_textdisp = (curx << 16) + (cury << 8) + c;
      if (c >= 32 && c < 128)
         curx++;
   }
   // new line
   if (c == '\n') {
      curx = 2;
      cury++;
   }
   return c;
}
int uart_putchar(int c);
int _putchar(int c, int uart) {
   if (uart)
      uart_putchar(c);
   else
      putchar(c);
}

int print(const char *p)
{
	while (*p)
		putchar(*(p++));
   return 0;
}
int uart_print(const char *p);
int _print(const char *p, int uart) {
   if (uart)
      uart_print(p);
   else
      print(p);
}

void _print_hex_digits(uint32_t val, int nbdigits, int uart) {
   for (int i = (4*nbdigits)-4; i >= 0; i -= 4) {
      _putchar("0123456789ABCDEF"[(val >> i) % 16], uart);
   }
}
void print_hex_digits(uint32_t val, int nbdigits) {
   _print_hex_digits(val, nbdigits, 0);
}
void uart_print_hex_digits(uint32_t val, int ndigits) {
   _print_hex_digits(val, ndigits, 1);
}

void _print_hex(uint32_t val, int uart) {
   _print_hex_digits(val, 8, uart);
}
void print_hex(uint32_t val) {
   _print_hex(val, 0);
}
void uart_print_hex(uint32_t val) {
   _print_hex(val, 1);
}

void _print_dec(int val, int uart) {
   char buffer[255];
   char *p = buffer;
   if(val < 0) {
      _putchar('-', uart);
      _print_dec(-val, uart);
      return;
   }
   while (val || p == buffer) {
      *(p++) = val % 10;
      val = val / 10;
   }
   while (p != buffer) {
      _putchar('0' + *(--p), uart);
   }
}
void print_dec(int val) {
   _print_dec(val, 0);
}
void uart_print_dec(int val) {
   _print_dec(val, 1);
}

int _printf(const char *fmt, va_list ap, int uart) {
    for(;*fmt;fmt++) {
        if(*fmt=='%') {
            fmt++;
                 if(*fmt=='s') _print(va_arg(ap,char *), uart);
            else if(*fmt=='x') _print_hex(va_arg(ap,int), uart);
            else if(*fmt=='d') _print_dec(va_arg(ap,int), uart);
            else if(*fmt=='c') _putchar(va_arg(ap,int), uart);	   
            else if(*fmt=='b') _print_hex_digits(va_arg(ap,int), 2, uart);	      // byte
            else if(*fmt=='w') _print_hex_digits(va_arg(ap,int), 4, uart);	      // 16-bit word
            else _putchar(*fmt, uart);
        } else 
            _putchar(*fmt, uart);
    }
    return 0;
}


int printf(const char *fmt,...)
{
   va_list ap;
   va_start(ap, fmt);
   _printf(fmt, ap, 0);
   va_end(ap);
   return 0;
}

void clear() {
   for (int i = 0; i < 28; i++) {
      cursor(0, i);
      for (int j = 0; j < 32; j++)
         putchar(' ');
   }
}

void uart_init(int clkdiv) {
   reg_uart_clkdiv = clkdiv;
}

int uart_putchar(int c) {
   reg_uart_data = c;
   return c;
}

int uart_print(const char *s) {
	while (*s)
		_putchar(*(s++), 1);   
   return 0;
}

int uart_printf(const char *fmt,...) {
   va_list ap;
   va_start(ap, fmt);
   _printf(fmt, ap, 1);
   va_end(ap);
   return 0;   
}

// int delay_count;
// void delay(int ms) {
// 	for (int i = 0; i < ms; i++) {
//       delay_count = 0;
// 		for (int j = 0; j < 500; j++) {
// 			delay_count++;
// 		}
//    }
// }

void delay(int ms) {
   int t0 = time_millis();
   while (time_millis() - t0 < ms) {}
}

void joy_get(int *joy1, int *joy2) {
   uint32_t joy = reg_joystick;
   *joy1 = joy & 0xffff;
   *joy2 = (joy >> 16) & 0xffff;
}

void backup_process();

// (R L X A RT LT DN UP START SELECT Y B)
// overlay_key_code: 0x84 for SELECT&RIGHT, 0xC for SELECT&START, 0x804 for SELECT/RB, 0x24 for HOME
int joy_choice(int start_line, int len, int *active, int overlay_key_code) {
   int joy1, joy2;
   int last = *active;

   joy_get(&joy1, &joy2);
   // DEBUG("joy_choice: joy1=%x, joy2=%x\n", joy1, joy2);

   if ((joy1 == overlay_key_code) || (joy2 == overlay_key_code)) {
      overlay(!overlay_status());    // toggle OSD
      delay(300);
   }

   backup_process();                // saves backup every 10 seconds

   if (!overlay_status()) {         // stop responding when OSD is off
      // DEBUG("joy_choice: overlay off\n");
      return 0;
   }

   if ((joy1 & 0x10) || (joy2 & 0x10)) {
      if (*active > 0) (*active)--;
   }
   if ((joy1 & 0x20) || (joy2 & 0x20)) {
      if (*active < len-1) (*active)++;
   }
   if ((joy1 & 0x40) || (joy2 & 0x40))
      return 3;      // previous page
   if ((joy1 & 0x80) || (joy2 & 0x80))
      return 2;      // next page
   if ((joy1 & 0x1) || (joy1 & 0x100) || (joy2 & 0x1) || (joy2 & 0x100))
      return 1;      // confirm

   cursor(0, start_line + (*active));
   print(">");
   if (last != *active) {
      cursor(0, start_line + last);
      print(" ");
      delay(100);     // button debounce
   }

   // DEBUG("joy_choice: return\n");

   return 0;      
}

void snes_ctrl(uint32_t ctrl) {
   reg_romload_ctrl = ctrl;
}
extern void snes_data(uint32_t data) {
   reg_romload_data = data;
}

/* 
 * Needed to prevent the compiler from recognizing memcpy in the
 * body of memcpy and replacing it with a call to memcpy
 * (infinite recursion) 
 */ 
// #pragma GCC optimize ("no-tree-loop-distribute-patterns")

void* memcpy(void * dst, void const * src, size_t len) {
   uint32_t * plDst = (uint32_t *) dst;
   uint32_t const * plSrc = (uint32_t const *) src;

   // If source and destination are aligned,
   // copy 32s bit by 32 bits.
   if (!((uint32_t)src & 3) && !((uint32_t)dst & 3)) {
      while (len >= 4) {
	 *plDst++ = *plSrc++;
	 len -= 4;
      }
   }

   uint8_t* pcDst = (uint8_t *) plDst;
   uint8_t const* pcSrc = (uint8_t const *) plSrc;
   
   while (len--) {
      *pcDst++ = *pcSrc++;
   }
   
   return dst;
}

/*
 * Super-slow memset function.
 * TODO: write word by word.
 */ 
void* memset(void* s, int c, size_t n) {
   uint8_t* p = (uint8_t*)s;
   for(size_t i=0; i<n; ++i) {
       *p = (uint8_t)c;
       p++;
   }
   return s;
}

int memcmp(const void *s1, const void *s2, size_t n) {
   uint8_t *p1 = (uint8_t *)s1;
   uint8_t *p2 = (uint8_t *)s2;
   for (int i = 0; i < n; i++) {
      if (*p1 != *p2)
         return (*p1) < (*p2) ? -1 : 1;
      p1++;
      p2++;
   }
   return 0;
}

int strcmp(const char* s1, const char* s2)
{
   while(*s1 && (*s1 == *s2)) {
      s1++;
      s2++;
   }
   return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

int strcasecmp(const char* s1, const char* s2) {
   while(*s1 && (tolower(*s1) == tolower(*s2))) {
      s1++;
      s2++;
   }
   return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}


char *strstr(const char *haystack, const char *substring) {
   char *string = (char *)haystack;
   char *a, *b;
   b = (char *)substring;
   if (*b == 0) 
	   return string;
   for (; *string != 0; string += 1) {
	   if (*string != *b)
	      continue;
	   a = string;
	   while (1) {
         if (*b == 0) 
            return string;
         if (*a++ != *b++) 
            break;
      }
      b = (char *)substring;
   }
   return NULL;
}

char *strcasestr(char *string, char *substring) {
   char *a, *b;
   b = substring;
   if (*b == 0) 
	   return string;
   for (; *string != 0; string += 1) {
	   if (tolower(*string) != tolower(*b))
	      continue;
	   a = string;
	   while (1) {
         if (*b == 0) 
            return string;
         if (tolower(*a++) != tolower(*b++)) 
            break;
      }
      b = substring;
   }
   return NULL;
}

char *strcat(char *dest, const char *src) {
   char *rdest = dest;

   while (*dest)
      dest++;
   while (*dest++ = *src++)
      ;
   return rdest;
}

char* strncat(char* destination, const char* source, size_t num)
{
   int i, j;
   for (i = 0; destination[i] != '\0'; i++);
   for (j = 0; source[j] != '\0' && j < num; j++) {
      destination[i + j] = source[j];
   }
   destination[i + j] = '\0';
   return destination;
}

char * strcpy(char *strDest, const char *strSrc) {
   //  assert(strDest!=NULL && strSrc!=NULL);
    char *temp = strDest;
    while(*strDest++ = *strSrc++);
    return temp;
}

char *strncpy(char* _dst, const char* _src, size_t _n) {
   size_t i = 0;
   char *r = _dst;
   while(i++ != _n && (*_dst++ = *_src++));
   return r;
}

char *strchr(const char *s, int c) {
   while (*s) {
      if (*s == c)
         return (char *)s;
      s++;
   }
   return (char *)0;
}

char *strrchr(const char *s, int c) {
   char *r = 0;
   do {
      if (*s == c)
         r = (char*) s;
   } while (*s++);
   return r;
}

size_t strlen(const char *s) {
   size_t r = 0;
   while (*s != '\0') {
      r++;
      s++;
   }
   return r;
}

int isspace(int c) {
	return (c == '\t' || c == '\n' ||
	    c == '\v' || c == '\f' || c == '\r' || c == ' ' ? 1 : 0);
}

char *trimwhitespace(char *str) {
   char *end;
   // Trim leading space
   while(isspace((unsigned char)*str)) str++;

   if(*str == 0)  // All spaces?
      return str;

   // Trim trailing space
   end = str + strlen(str) - 1;
   while(end > str && isspace((unsigned char)*end)) end--;

   // Write new null terminator character
   end[1] = '\0';

   return str;
}

int atoi(const char *str) {
   int sign = 1, base = 0, i = 0;
 
   // if whitespaces then ignore.
   while (str[i] == ' ') {
      i++;
   }
 
   // sign of number
   if (str[i] == '-' || str[i] == '+') {
      if (str[i] == '-')
         sign = -1;
      i++;
   }
 
   // checking for valid input
   while (str[i] >= '0' && str[i] <= '9') {
      // handling overflow test case
      if (base > INT_MAX / 10
         || (base == INT_MAX / 10 && str[i] - '0' > 7)) {
         if (sign == 1)
            return INT_MAX;
         else
            return INT_MIN;
      }
      base = 10 * base + (str[i++] - '0');
   }
   return sign == -1 ? -base : base;
}
