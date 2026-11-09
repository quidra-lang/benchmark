/* checks.h: malformed directives, kept for regression tests */
#define 3D 1
#define defined 1
#define __LINE__ 7
#define DUP(a, a) a
#define SEP(a b) a
#define VA(x) __VA_ARGS__
#define HASH(x) #y
#define EDGE ## x
#define OPEN(a,
#define TAIL(a, ...) a ## __VA_ARGS__ ##
#undef
#undef CLAMP extra
#foo bar
# 42 "bogus"
#
#else
#endif
#if 1
#else
#elif 1
#else
#endif
#if
#endif
#define NOTHING
#if NOTHING
#endif
#if (1
#endif
#if 1 ? 2
#endif
#if 1 2
#endif
#if BIT(3)
#endif
#if 08 || 0x
#endif
#if 'ab'
#endif
#if defined
#endif
#if defined(DEBUG
#endif
#if __has_include "util.h"
#endif
#ifdef
#endif
#ifdef 3
#endif
#ifdef DEBUG extra
#else junk
#endif junk
#include "config.h" junk
#include
#include ""
#include <platform.h
#include UNDEFINED_HEADER
#pragma push_macro(LOG_LEVEL)
#pragma GCC poison 3rd_party
#pragma once extra
#ifndef DEBUG
#include "nonexistent.h"
#if 1/0
#bogus directive in a skipped group
#else
#error "not reported"
#endif
#endif
#define
#define BADP(x,) x
#define BADV(..., x) x
#undef __FILE__
#ifdef __has_include
#endif
#if 1 +
#endif
#if 1 + )
#endif
#if __has_include()
#endif
#if __has_include("util.h"
#endif
