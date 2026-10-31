#ifndef SPATIAL_H
#define SPATIAL_H
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
typedef int64_t Integer;
typedef struct {
    Integer x1, y1, x2, y2;
} Box;
typedef struct {
    int id;
    Integer x, y;
} Point;
typedef struct {
    int id;
    Box box;
} Object;
typedef struct {
    Point *v;
    int n, capacity;
} Points;
typedef struct {
    Object *v;
    int n, capacity;
} Objects;
void points_push(Points *values, Point value);
void points_insert(Points *values, Point value);
void points_remove(Points *values, int id);
void objects_push(Objects *values, Object value);
Box point_box(Point point);
typedef struct {
    int world, bucket, maximum, minimum, grid;
} Params;
typedef struct {
    char name[16];
    Integer values[4];
    int n;
} Command;
typedef struct {
    Points points;
    Objects rectangles;
    Params params;
    Command *commands;
    int ncommands;
} Input;
Input read_input(void);
bool key_less(Point a, Point b, int axis);
typedef struct KDNode {
    Point point;
    int depth;
    struct KDNode *left, *right;
} KDNode;
KDNode *kd_build(const Point *points, int n, int depth);
void kd_insert(KDNode **node, Point point, int depth);
Point kd_minimum(const KDNode *node, int axis);
void kd_delete(KDNode **node, Point point);
void kd_free(KDNode *node);
typedef struct QuadNode {
    Integer x, y, size;
    Points points;
    struct QuadNode *children[4];
} QuadNode;
int destination(const QuadNode *node, Point point);
void quad_insert(QuadNode *node, Point point, int bucket);
void quad_delete(QuadNode *node, Point point, int bucket);
void quad_free(QuadNode *node);
Integer area(Box box);
Box mbr(Box a, Box b);
Integer enlargement(Box a, Box b);
bool intersects(Box a, Box b);
bool contains(Box a, Box b);
Integer overlap(Box a, Box b);
Integer distance(Integer x, Integer y, Box box);
typedef struct RNode RNode;
typedef struct {
    Box box;
    int id, number;
    RNode *child;
} Entry;
struct RNode {
    int level, n;
    RNode *parent;
    Entry entries[65];
};
typedef struct {
    RNode *root;
    int maximum, minimum;
} RTree;
Box node_box(const RNode *node);
RTree rtree_new(int maximum, int minimum);
void rtree_insert(RTree *tree, Entry entry, int level);
void rtree_delete(RTree *tree, Point point);
void rtree_bulk(RTree *tree, const Entry *entries, int n);
RNode *rtree_leaf(const RNode *node, Point point);
void rtree_free(RNode *node);
typedef struct {
    int world, side, dimension;
    Points *cells;
} Grid;
Grid grid_new(int world, int side);
void grid_insert(Grid *grid, Point point);
void grid_delete(Grid *grid, Point point);
const char *fraction(Integer numerator, Integer denominator);
const char *ids(const int *values, int n);
typedef struct {
    char *data;
    size_t size, capacity;
} Text;
void add(Text *out, const char *format, ...);
void line(Text *out, const char *format, ...);
void write_report(const char *name, Text text);
#endif
