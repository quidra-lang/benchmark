#ifndef STEREO_H
#define STEREO_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <limits.h>
#include <sys/stat.h>
typedef long long I;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    int width, height;
    I *pixels;
} PGM;
typedef struct {
    I *values;
    int pixels, disparities;
} Volume;
typedef struct {
    int *data, count;
} Pixels;
typedef struct {
    int x, y;
} Point;
typedef struct {
    int minimum, maximum, texture_window, sgm_window, paths, speckle_size, speckle_range,
        fusion_votes, object_range, object_size;
    I texture_threshold, uniqueness, lr, p1, p2, gamma, focal, baseline;
    int wta_kind, sgm_kind, windows[3][4], window_counts[3];
    Point samples[50];
    int sample_count;
} Params;
typedef struct {
    Pixels region[3], occluded;
} Regions;
typedef struct {
    I pixels, valid, bad1, bad2, error_sum, exact;
} Evaluation;
extern const Point directions[8];
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...), *joined(const char *first, const char *second);
void line(Lines *lines, const char *pattern, ...);
PGM read_pgm(const char *path);
Params read_parameters(void);
void write_pgm(const char *name, PGM image);
void save(const char *name, Lines lines);
I clamped(const I *image, int width, int height, int x, int y);
I *box_sum(const I *image, int width, int height, int window),
    *census(const I *image, int width, int height),
    *texture(const I *image, int width, int height, int window);
Volume cost_volume(PGM left, PGM right, const I *cl, const I *cr, int kind, int window,
                   const Params *params),
    path_costs(Volume base, PGM left, Point direction, const Params *params);
Volume *cumulative_costs(Volume base, PGM left, const Params *params);
char *hundredths(I value), *two_decimals(I numerator, I denominator);
I depth_hundredths(I disparity, I focal, I baseline);
typedef struct {
    char *disparity, *depth;
} Refined;
Refined subpixel(I disparity, const I *costs, const Params *params);
Regions truth_regions(PGM truth);
Evaluation evaluate(const I *image, const I *truth, Pixels region);
char *ratio(I numerator, I denominator);
#endif
