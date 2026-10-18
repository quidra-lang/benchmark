#pragma once
/* util.h - small helper macros */
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define CLAMP(v, lo, hi) MIN(MAX(v, lo), hi)
#define SWAP16(x) ((((x) & 0xFF) << 8) | (((x) >> 8) & 0xFF))
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define NOARGS() 0
#define LOG(level, ...) log_print(level, __VA_ARGS__)
#define MS_TO_TICKS(ms) ((ms) * TICK_HZ / 1000)
#define UNUSED_IN_HEADER 1
