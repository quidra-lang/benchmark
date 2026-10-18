/*
 * main.c - sensor node firmware, used as a preprocessor test bed
 */
#include "config.h"
#include "util.h"
#include <regs.h>
#include "config.h"
#include "util.h"   /* included twice on purpose */
#include "missing.h"
#include <util.h>
#pragma once
#define SYS_HEADER <platform.h>
#include SYS_HEADER

#define STR(x) #x
#define XSTR(x) STR(x)
#define CAT(a, b) a ## b
#define XCAT(a, b) CAT(a, b)
#define BOARD_FILE(n) XSTR(XCAT(board_v, n).h)
#include BOARD_FILE(BOARD_REV)

#if __has_include("optional.h")
#include "optional.h"
#elif __has_include(<regs.h>) && HAS_SENSOR
#define HAVE_REGS 1
#endif

#define UNIQUE(name) XCAT(name, __COUNTER__)
#define NAIVE_UNIQUE(name) CAT(name, __COUNTER__)
static int UNIQUE(slot), UNIQUE(slot);
static int NAIVE_UNIQUE(slot);

#if defined(DEBUG) && LOG_LEVEL >= 2
#define TRACE(fmt, ...) log_write(__FILE__, __LINE__, fmt, ## __VA_ARGS__)
#elif defined DEBUG
#define TRACE(fmt, ...) log_write(fmt)
#else
#define TRACE(fmt, ...)
#endif

#ifdef BOARD_REV_2
#define RADIO "ble"
#elifndef FEATURE_BLE
#define RADIO "usb-only"
#endif
#undef NOT_DEFINED_ANYWHERE

#define COLOR_ENTRY(name, rgb) COLOR_##name = rgb,
enum color {
#define X COLOR_ENTRY
#include "colors.def"
#undef X
};
#define NAME_ENTRY(name, rgb) [COLOR_##name] = #name,
static const char *color_names[] = {
#define X NAME_ENTRY
#include "colors.def"
#undef X
};

#include "legacy.h"
#include "legacy.h"

int main(void)
{
    TRACE("boot %d", BOARD_REV);
    TRACE("ready");
    GPIOA_MODER |= BIT(LED_PIN) | BIT(BUTTON_PIN);
    u32 timeout = MS_TO_TICKS(250);
    int clamped = CLAMP(reading, 0, 1023);
    int biggest = MAX(MAX(a, b), MAX(c, d));
    swap_bytes(SWAP16(0x1234));
    ASSERT_ON(clamped >= 0 && timeout != 0);
    LOG(1, "values: %d %d", clamped,
        biggest);
    LOG(2);
    const char *radio = RADIO;
    int v = MAX
#define AFTER_MAX
        (1, 2);

#define foo foo + 1
#define ping(x) pong(x + 1)
#define pong(x) ping(x * 2)
    int f1 = foo;
    int f2 = ping(3);

#define y 3
#define fx(a) fx(y * (a))
#undef y
#define y 2
#define gx fx
#define zz zz[0]
#define hx gx(~
#define mx(a) a(w)
#define w 0,1
#define tx(a) a
#define px() int
#define qx(x) x
#define rx(x, v) x ## v
#define str(x) # x
    fx(v+1) + fx(fx(zz)) % tx(tx(gx)(0) + tx)(1);
    gx(y+(3,4)-w) | hx 5) & mx
        (fx)^mx(mx);
    px() i[qx()] = { qx(1), rx(2,3), rx(4,), rx(,5), rx(,) };
    char c[2][6] = { str(hello), str() };

#define SHOW(...) puts(#__VA_ARGS__)
    SHOW(path = "C:\temp\new", ch = '"', done);
    SHOW();
    int bad1 = CAT(+, -), bad2 = CAT(x, +), bad3 = CAT(/, /);
    int ok1 = CAT(1, e5), ok2 = CAT(<, <=), ok3 = CAT(-, >);
    int m1 = MAX(1, 2, 3), m2 = MAX(1), m3 = NOARGS(1), m4 = NOARGS();
    int arr[] = { MAX(1,
#ifdef DEBUG
        2
#endif
    ) };

#define NEG -1
#define ID(x) x
#define EMPTY
    int a1 = -NEG, a2 = ID(a)b, a3 = ID(+)+, a4 = 1 ID(/)ID(/) 2;
    int a5 = ID(1).5, a6 = x EMPTY+y, a7 = ID()ID(z);
    report_line(__LINE__, ID(
        __LINE__));

#pragma push_macro("LOG_LEVEL")
#undef LOG_LEVEL
#define LOG_LEVEL 0
    int quiet = LOG_LEVEL;
#pragma pop_macro("LOG_LEVEL")
    int loud = LOG_LEVEL;
#pragma pop_macro("LOG_LEVEL")
#pragma push_macro("TEMP_FLAG")
#define TEMP_FLAG 7
    int temp = TEMP_FLAG;
#pragma pop_macro("TEMP_FLAG")
    int temp_after = TEMP_FLAG;

#define COPY(dst, src) strcpy(dst, src)
#pragma GCC poison strcpy gets CPU_MHZ
    strcpy(buffer, PLATFORM_NAME);
    COPY(buffer, PLATFORM_NAME);
    int mhz = CPU_MHZ;
#ifndef DEBUG
    gets(buffer);
#endif
#pragma pack(push, 1)
#define UNUSED_LOCAL 42
#define REDEFINED_LOCAL 1
#define REDEFINED_LOCAL 2
#undef REDEFINED_LOCAL
#define LINE_BASE 2000
    return 0;
}

#include "broken.h"
#include "recur.h"
#include "checks.h"

#line 900 "generated.c"
const char *where = __FILE__ ":" XSTR(__LINE__);
#warning "generated section starts here"
#line LINE_BASE
int line_after_reset = __LINE__;
#line 0
#line 12 34
#error stop after __LINE__ checks
