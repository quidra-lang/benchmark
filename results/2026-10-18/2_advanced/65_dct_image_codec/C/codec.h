#ifndef CODEC_H
#define CODEC_H
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <sys/stat.h>
typedef long long I;
typedef struct {
    int *data, count, capacity;
} Bytes;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    I values[3];
} Pixel;
typedef struct {
    I values[64];
} Sequence;
typedef struct {
    I values[8][8];
} Matrix;
typedef struct {
    int first, second;
} Pair;
typedef struct {
    int width, height;
    Pixel *pixels;
} Image;
typedef struct {
    int width, height;
    I *pixels;
} Plane;
typedef struct {
    int qualities[8], quality_count, truncate[8], truncate_count, sampling, restart, target,
        generations;
    bool optimized;
} Params;
typedef struct {
    int counts[16], symbols[256], symbol_count, lengths[256], codes[256];
    bool defined;
} Huffman;
typedef struct {
    Huffman values[2][16];
} Tables;
typedef struct {
    Matrix values[4];
    bool defined[4];
} Quantization;
typedef struct {
    I values[2][16][256];
} Frequencies;
typedef struct {
    Matrix transform, basic[2];
    Tables huffman;
} SourceTables;
typedef struct {
    Bytes data;
    int buffer, pending, padding, stuffed;
} BitWriter;
typedef struct {
    const Bytes *data;
    int position, buffer, remaining;
    const char *error;
} BitReader;
extern const Pair table_keys[4];
extern const char *table_names[4];
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...), *joined(const char *first, const char *second);
void line(Lines *lines, const char *pattern, ...);
void byte(Bytes *bytes, int value);
void append(Bytes *first, const Bytes *second);
Image read_ppm(const char *path);
Params read_params(void);
SourceTables *read_tables(void);
Bytes read_hex(const char *path);
void write_ppm(const char *name, Image image);
void write_hex(const char *name, Bytes bytes);
void save(const char *name, Lines lines);
I floor_div(I a, I b), clamp(I value);
Pixel to_ycbcr(Pixel pixel), to_rgb(Pixel pixel);
void split_planes(Image image, Plane out[3]);
void component_planes(const Plane planes[3], const Pair factors[3], int mx, int my, Plane out[3]);
void upsample(const Plane planes[3], const Pair factors[3], int width, int height, Plane out[3]);
Image combine_rgb(const Plane planes[3]);
void zigzag_order(Pair out[64]);
Matrix forward(Matrix block, Matrix transform), inverse_dct(Matrix coefficients, Matrix transform),
    quantize(Matrix values, Matrix table), dequantize(Sequence sequence, Matrix table, int keep);
Sequence zigzag(Matrix values);
Quantization quantization_tables(const Matrix basic[2], int quality);
int category(I value);
Pair extra_bits(I value);
I amplitude(int bits, int size);
Huffman huffman(const int counts[16], const int *symbols, int count),
    optimized_table(const I frequencies[256]);
void write_bits(BitWriter *writer, int value, int width);
void pad(BitWriter *writer);
void restart(BitWriter *writer, int number);
int read_bit(BitReader *reader), read_bits(BitReader *reader, int width);
void discard(BitReader *reader);
int find_resync(const Bytes *data, int position);
#endif
