#ifndef GEOMETRY_H
#define GEOMETRY_H
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <float.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
typedef int64_t Integer;
typedef struct {
    int n, v[1200];
} Ints;
typedef struct {
    int a, b;
} Pair;
typedef struct {
    int a, b, c;
} Triangle;
typedef struct {
    int n;
    Triangle v[800];
} Triangles;
typedef struct {
    int n;
    Pair v[400];
} HullEdges;
typedef struct {
    Integer x, y;
} Point;
Integer orient(Point p, Point q, Point r);
Integer incircle(Point a, Point b, Point c, Point d);
Integer d2(Point p, Point q);
Integer dot(Point o, Point p, Point q);
typedef struct {
    Integer x, y, d;
} Center;
Center center(Point a, Point b, Point c);
const char *fraction(Integer numerator, Integer denominator);
Point outward(Point u, Point v);
Triangle canonical(Triangle triangle);
typedef struct {
    int site;
    bool inside;
    Triangle containing;
    int visible, flips, triangles, hull;
} Insertion;
typedef struct {
    Ints path;
    bool outside;
    Pair edge;
} Walk;
typedef struct {
    int directed[400][400], size, entries;
} Triangulation;
void triangle_add(Triangulation *t, int a, int b, int c);
void triangle_remove(Triangulation *t, int a, int b, int c);
int third(const Triangulation *t, int a, int b);
Triangles triangles(const Triangulation *t);
HullEdges hull_edges(const Triangulation *t);
Triangulation *initialize(const Point *points, int n);
Insertion insert_site(Triangulation *t, const Point *points, int site);
Walk visibility_walk(const Triangulation *t, const Point *points, Point query);
double radius2(Point a, Point b, Point c);
const char *position(Center vertex, const Point *points, Ints hull);
Ints neighbor_order(const Triangulation *t, int site, Ints neighbors, int next);
double cell_area(Point site, const Center *vertices, Ints sequence);
double clipped_area(const Point *points, int site, Ints neighbors);
typedef struct {
    int a, b, left, right;
    Integer length2;
    bool gabriel, rng, mst;
} Edge;
typedef struct {
    int n;
    Edge v[1200];
} Edges;
typedef struct {
    int parent[400];
} Disjoint;
Disjoint disjoint(int n);
int find(Disjoint *sets, int value);
bool join(Disjoint *sets, int a, int b);
typedef struct {
    Ints v[400];
} Neighbors;
Ints nearest(const Point *points, const Neighbors *neighbors, int n);
Ints kruskal(Edges *edges, int sites);
bool gabriel(const Point *points, const Triangulation *t, int a, int b);
bool relative_neighborhood(const Point *points, int n, int a, int b);
Ints greedy_route(const Point *points, const Neighbors *neighbors, int source, int target);
typedef struct {
    double distance[400];
    int previous[400];
} Paths;
Paths dijkstra(const Point *points, const Neighbors *neighbors, int n, int source);
typedef struct {
    int width, height;
    char cells[60][120];
} Grid;
Grid canvas(int width, int height);
Pair map_point(Point point, int width, int height);
Pair map_center(Center point, int width, int height);
void draw_line(Grid *grid, Pair start, Pair end, char character);
Grid voronoi_plot(const Point *points, int n, int width, int height);
typedef struct {
    char *data;
    size_t size, capacity;
} Text;
void add(Text *out, const char *format, ...);
void line(Text *out, const char *format, ...);
void framed(Text *out, const Grid *grid);
#endif
