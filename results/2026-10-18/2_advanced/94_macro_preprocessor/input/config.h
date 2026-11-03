/*
 * config.h - board configuration
 */
#ifndef CONFIG_H
#define CONFIG_H

#include <platform.h>

#define TICK_HZ 1000
#define LED_PIN 5
#define BUTTON_PIN 13

#if BOARD_REV >= 3
#  define HAS_SENSOR 1
#  define SENSOR_CHANNELS 4
#elif BOARD_REV == 2
#  define HAS_SENSOR 1
#  define SENSOR_CHANNELS 2
#else
#  define HAS_SENSOR 0
#endif

#ifdef BOARD_REV_2
#define BOARD_NAME "rev2"
#elifdef BOARD_REV
#define BOARD_NAME "rev" XSTR(BOARD_REV)
#elifndef DEBUG
#define BOARD_NAME "unknown"
#endif

#if (CPU_MHZ * 1000000L) > 0x2000000 && 'A' == 65
#define FAST_CPU 1
#endif
#if -7 / 2 == -3 && -7 % 2 == -1 && -7 >> 1 == -4 && (1 << 20) >> 3 == 131072 && ~0 == -1 && (5 & 3 | 8 ^ 2) == 11 && 010 == 8 && '\n' == 10
#define INT_SEMANTICS_OK 1
#endif
#if 0 && (1 / 0)
#error "never evaluated"
#endif
#if 1 || UNDEFINED_A
#define SHORT_CIRCUIT_OK 1
#endif
#if UNDEFINED_B + 1 > 0 ? !defined UNDEFINED_C : 1 / 0
#define TERNARY_OK 1
#endif
#if (BOARD_REV - 4) * 2
#define NEGATIVE_IS_TRUE 1
#endif
#if CPU_MHZ / (FEATURE_USB - 1)
#define NEVER 1
#endif

#endif /* CONFIG_H */
