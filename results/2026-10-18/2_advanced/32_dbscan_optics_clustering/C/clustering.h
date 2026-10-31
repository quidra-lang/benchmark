#ifndef CLUSTERING_H
#define CLUSTERING_H
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int64_t Integer;
#define DISTANCE_INF INT64_MAX
typedef struct {
    int *values, count, capacity;
} IntList;
void push(IntList *, int);
typedef struct {
    char **values;
    int count, capacity;
} Lines;
void add_line(Lines *, const char *, ...);
char *format(const char *, ...);
void append_text(char **, const char *, ...);
char *read_line(FILE *);
void write_lines(FILE *, const Lines *);
void framed(FILE *, char **, int, int);
typedef struct {
    int id, x, y;
} Point;
typedef struct {
    IntList eps, extract;
    int min_points, max_eps, xi_u, xi_v, xi_size, width, height, kwidth, kheight, rwidth;
} Params;
typedef struct {
    Point *points;
    int count;
    Params params;
} Input;
Input read_input(void);
Integer distance(Point, Point);
typedef struct {
    Integer *values;
    int count;
} Distances;
static inline Integer at(const Distances *d, int a, int b) {
    return d->values[(size_t)a * (size_t)d->count + (size_t)b];
}
typedef struct {
    int gx, gy;
    IntList points;
} Cell;
typedef struct {
    int radius, count, cell_count;
    Cell *cells;
    IntList *neighbors;
    int *candidates, *occupancy;
    int busiest_x, busiest_y, busiest_count;
    Integer total_candidates, pairs, brute_pairs;
    bool correct;
} Grid;
Grid build_grid(const Point *, const Distances *, int);
int *dbscan(const Grid *, int);
typedef struct {
    Integer *core, *reach;
    int *predecessor, *order, count;
} Optics;
Optics optics(const Grid *, const Distances *, int);
char *fraction(Integer, Integer);
char *root(Integer);
char *ari_value(Integer, Integer);
#endif
