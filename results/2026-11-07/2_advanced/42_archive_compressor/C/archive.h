#ifndef ARCHIVE_H
#define ARCHIVE_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
typedef uint8_t Byte;
typedef int64_t Integer;
typedef struct {
    Byte *data;
    size_t count, capacity;
} Bytes;
typedef struct {
    char **data;
    size_t count, capacity;
} Lines;
typedef struct {
    Bytes bytes;
    size_t count;
} BitWriter;
typedef struct {
    const Bytes *bytes;
    size_t position;
    bool zero_extend;
    const char *error;
} BitReader;
typedef struct {
    int codes, clears, longest, widths[4];
} LzwStats;
typedef struct {
    int literal, distance, length;
} Token;
typedef struct {
    Token *data;
    size_t count, capacity;
} Tokens;
typedef struct {
    int *lengths;
    int count, halvings;
} Huffman;
typedef struct {
    int bits, contexts, rescales;
} ArithStats;
void *resize(void *memory, size_t size);
void byte_push(Bytes *bytes, Byte value);
void bytes_append(Bytes *target, const Byte *values, size_t count);
Bytes bytes_copy(const Bytes *bytes);
void bytes_free(Bytes *bytes);
int bits(uint32_t value);
void bit_write(BitWriter *writer, uint32_t value, int width);
uint32_t bit_read(BitReader *reader, int width);
Bytes lzw_encode(const Bytes *data, LzwStats *stats);
const char *lzw_decode(const Bytes *payload, uint32_t size, Bytes *output);
Tokens tokenize(const Bytes *data, int offset_bits, int length_bits);
const char *output_match(Bytes *output, uint32_t size, int distance, int length);
Huffman huffman_lengths(const int *frequencies, int count, int maximum);
int *canonical_codes(const int *lengths, int count);
Bytes arith_encode(const Bytes *data, ArithStats *stats);
const char *arith_decode(const Bytes *payload, uint32_t size, Bytes *output);
#endif
