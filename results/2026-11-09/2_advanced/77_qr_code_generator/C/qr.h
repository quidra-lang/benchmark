#ifndef QR_H
#define QR_H
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef struct MemoryBlock MemoryBlock;
typedef struct {
    MemoryBlock *head;
} Memory;
extern Memory permanent;
extern Memory *memory;
void *allocate(size_t size);
void clear_memory(Memory *pool);
char *substring(const char *source, size_t length), *copy_text(const char *source),
    *format(const char *pattern, ...);
#define VECTOR(Name, Type)                                                                         \
    typedef struct {                                                                               \
        Type *items;                                                                               \
        size_t count, capacity;                                                                    \
    } Name;                                                                                        \
    static inline void Name##_add(Name *list, Type item) {                                         \
        if (list->count == list->capacity) {                                                       \
            size_t capacity = list->capacity ? list->capacity * 2 : 8;                             \
            Type *items = allocate(capacity * sizeof(Type));                                       \
            if (list->count)                                                                       \
                memcpy(items, list->items, list->count * sizeof(Type));                            \
            list->items = items;                                                                   \
            list->capacity = capacity;                                                             \
        }                                                                                          \
        list->items[list->count++] = item;                                                         \
    }
VECTOR(Names, char *)
Names split(const char *source, const char *separator), read_lines(const char *path);
char *join(Names values, const char *separator), *trim(const char *source);
typedef struct {
    int items[512], count;
} Words;
void word_add(Words *words, int value);
extern const char *alphanumeric;
char *binary(int value, int width), *from_codewords(const Words *words),
    *hexadecimal(const Words *words);
Words to_codewords(const char *bits);
typedef struct {
    char bits[4097];
    int length;
} BitWriter;
void write_bits(BitWriter *writer, int value, int width);
typedef struct {
    const char *bits;
    int length, position;
} BitReader;
int remaining(const BitReader *reader), read_bits(BitReader *reader, int width);
typedef struct {
    int exp[255], log[256];
} ReedSolomon;
typedef struct {
    Words syndromes, corrected, positions;
    bool success;
} Correction;
void init_reed_solomon(ReedSolomon *rs);
int gf_multiply(const ReedSolomon *rs, int a, int b),
    gf_divide(const ReedSolomon *rs, int a, int b);
Words parity(const ReedSolomon *rs, const Words *data, int degree),
    syndromes(const ReedSolomon *rs, const Words *data, int degree);
Correction correct(const ReedSolomon *rs, const Words *received, int degree);
typedef struct {
    int x, y;
} Point;
typedef struct {
    Point items[3249];
    int count;
} Positions;
typedef struct {
    int size;
    unsigned char cells[57][57];
} Matrix;
enum { AREA_DATA, AREA_FUNCTION, AREA_FORMAT, AREA_VERSION };
int format_information(int level, int mask), version_information(int version);
void format_positions(int size, Positions positions[2]),
    version_positions(int size, Positions positions[2]);
void write_value(Matrix *symbol, const Positions *positions, int value);
int read_value(const Matrix *symbol, const Positions *positions);
typedef struct {
    Matrix symbol, areas;
    Positions order;
    int indices[57][57];
} Geometry;
void function_matrix(Geometry *geometry, int version, const Words *alignments);
Positions reading_order(const Matrix *areas);
typedef struct {
    int n1, n2, n3, n4;
} Penalty;
int penalty_total(Penalty penalty);
bool mask_condition(int mask, int x, int y);
Matrix apply_mask(Matrix symbol, const Positions *positions, int mask);
Penalty penalties(const Matrix *symbol);
Names symbol_lines(const Matrix *symbol);
char *pbm_text(const Matrix *symbol, int quiet, int scale);
#endif
