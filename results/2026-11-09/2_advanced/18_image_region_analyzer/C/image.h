#ifndef IMAGE_H
#define IMAGE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <errno.h>

typedef long long Integer;
typedef struct { Integer numerator, denominator; } Rational;
typedef struct { char **items; int count, capacity; } Lines;
typedef struct { char *data; size_t size, capacity; } Text;
typedef struct { int x, y; } Point;
typedef struct { char *name; int width, height, maxval; int *pixels; } Image;
typedef struct { int width, height; bool *pixels; } Mask;
typedef struct { int *pixels, count, provisional; } Labeling;
typedef struct { int cutoff, below, above; Integer sum_below, sum_above, numerator, denominator; } Candidate;
typedef struct {
    int pixels, maxval, counts[256], below[256], minimum, maximum, median, mode, levels;
    Integer sums[256], total;
    int bin_width, bins[8], bin_count;
} Histogram;
typedef struct { int cutoff, upper, count; Candidate candidates[255]; } Otsu;
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
Lines read_lines(const char *path);
int words(char *line, char **parts);
Image *read_images(int *count);
Rational rational(Integer numerator, Integer denominator);
Rational parse_rational(const char *source);
int compare_rational(Rational first, Rational second);
char *decimal(Rational value, int places);
char *hull_area_text(Integer doubled);
void write_lines(const char *name, Lines lines);
Histogram histogram(const Image *image);
Otsu otsu(const Histogram *histogram);
int isodata(const Histogram *histogram, int *iterations);
Mask new_mask(int width, int height);
bool occupied(Mask mask, int x, int y);
Mask erode(Mask mask, const Point *offsets, int count);
Mask dilate(Mask mask, const Point *offsets, int count);
Mask opening(Mask mask, const Point *offsets, int count);
Mask closing(Mask mask, const Point *offsets, int count);
Mask thin(Mask mask);
int crossing_number(Mask mask, int x, int y);
Labeling label_components(Mask mask, int connectivity);
int bit_quad_euler(Mask mask, int connectivity);
#endif
