#ifndef REGEX_H
#define REGEX_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#define CAPACITY 42
#define VISWORDS 5
typedef struct { unsigned char bit[128]; } Charset;
enum { I_CHAR, I_ANY, I_CLASS, I_SPLIT, I_JMP, I_SAVE, I_ASSERT, I_BACKREF, I_LOOK, I_MATCH };
enum { A_BOL, A_EOL, A_WORD, A_NOTWORD };
enum { L_AHEAD, L_NOT, L_ATOMIC };
typedef struct { int op, x, y, kind, neg; Charset set; } Instruction;
typedef struct Node Node;
struct Node { int type, value, neg, min, max, mode, column; char *reference; Charset set; Node **child; int count; };
typedef struct {
    char *name, *flags, *text, *error;
    int error_column, groups, insensitive, multiline, dotall, compatible;
    char *names[81];
    Node *root;
    Instruction *code;
    int size, capacity;
} Pattern;
typedef struct { int cap[CAPACITY]; } Capture;
typedef struct { Capture *data; int count, capacity; } Matches;
typedef struct { long steps; int aborted; } Meter;
typedef struct { char *data; size_t length, capacity; } Buffer;
void *checked_alloc(size_t n);
void *checked_realloc(void *p, size_t n);
char *duplicate(const char *s);
char *read_line(FILE *f);
void append_bytes(Buffer *b, const char *s, size_t n);
void append_text(Buffer *b, const char *s);
int swap_case(int c);
int word_character(int c);
Charset predefined(int c);
int equal_character(const Pattern *p, int a, int b);
int class_character(const Pattern *p, Charset s, int neg, int c);
int assertion(const Pattern *p, int kind, const char *s, int n, int q);
int consumes(const Pattern *p, const Instruction *i, const char *s, int n, int q);
void quote(FILE *f, const char *s, size_t n);
void display_character(FILE *f, int c);
void display_set(FILE *f, Charset s, int neg);
void display_instruction(FILE *f, Instruction i);
int backtrack_search(const Pattern *p, const char *s, int start, int full, Meter *m, Capture *out);
int pike_search(const Pattern *p, const char *s, int start, int full, Meter *m, Capture *out);
#endif
