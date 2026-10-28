#ifndef DETECTOR_H
#define DETECTOR_H
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <inttypes.h>
#include <sys/stat.h>
typedef int64_t I;
typedef struct {
    I x, y;
} Point;
typedef struct {
    Point *data;
    int count, capacity;
} Points;
typedef struct {
    int *data;
    int count, capacity;
} Ids;
typedef struct {
    int width, height;
    I *data;
} Image;
typedef struct {
    I ks, divisor, low, high, r_min, r_max, circle_percent, circle_count, rho_step, vote_threshold,
        line_count, tolerance, max_gap, min_length, junction_distance, junction_angle, angle_tolerance,
        square_tolerance, margin, harris_window, harris_threshold, corner_count, match_distance,
        overlay_divisor;
    I *kernel;
} Params;
typedef struct {
    I data[180][2];
} Trig;
typedef struct {
    Image image;
    Params params;
    Trig trig;
} Input;
typedef struct {
    Image gx, gy, magnitude;
} Gradient;
typedef struct {
    Image direction, nms, edges;
    Points *components;
    int count;
    I strong, weak;
} Canny;
typedef struct {
    I radius;
    Point center;
    I votes, points;
} CirclePeak;
typedef struct {
    Points *offsets;
    I **votes;
    CirclePeak *peaks;
    int peak_count;
    I candidates;
} CircleVotes;
typedef struct {
    I theta, rho, votes;
} LinePeak;
typedef struct {
    I low, high, maximum;
    Image votes;
    LinePeak *peaks;
    int peak_count;
} LineVotes;
typedef struct {
    Point point;
    I response;
} Corner;
typedef struct {
    Corner *values;
    int count;
    I candidates;
} Corners;
void *allocate(size_t count, size_t size);
void release_all(void);
void release_one(void *value);
char *format(const char *pattern, ...);
void point_push(Points *values, Point value);
void id_push(Ids *values, int value);
Image image_new(int width, int height);
I image_at(Image image, Point point);
void image_set(Image image, Point point, I value);
bool image_inside(Image image, Point point);
Input load(void);
void write_pgm(const char *name, Image image);
I absolute(I value);
I floor_div(I a, I b);
I clamped(Image image, I x, I y);
Image smooth(Image image, const Params *params);
Gradient gradient(Image image);
Canny canny(Gradient gradient, const Params *params);
Points circle_points(I radius);
CircleVotes circle_votes(Image edges, const Params *params);
I rho(Point point, I theta, const Trig *trig, const Params *params);
LineVotes line_votes(Image edges, const Trig *trig, const Params *params);
Corners corners(Gradient gradient, const Params *params);
#endif
