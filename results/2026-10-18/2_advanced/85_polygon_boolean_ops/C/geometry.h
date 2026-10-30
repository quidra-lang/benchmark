#ifndef GEOMETRY_H
#define GEOMETRY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
typedef long long Integer;
typedef struct {
    Integer n, d;
} Fraction;
typedef struct {
    Integer x, y, d;
} Point;
typedef struct {
    Integer ax, ay, bx, by;
} OriginalLine;
Fraction fraction(Integer, Integer);
int fraction_compare(Fraction, Fraction);
double fraction_real(Fraction);
Integer fraction_round(Fraction);
char *fraction_text(Fraction, char[64]);
Point point(Integer, Integer, Integer);
Fraction point_x(Point);
Fraction point_y(Point);
bool point_equal(Point, Point);
bool point_less(Point, Point);
char *point_text(Point, char[96]);
OriginalLine original_line(Point, Point);
OriginalLine reverse_line(OriginalLine);
Integer line_cross(OriginalLine, Point);
Integer direction_cross(OriginalLine, OriginalLine);
Integer integer_cross(Point, Point, Point);
char *segment_text(Point, Point, char[192]);
bool on_segment(Point, Point, Point);
bool touching(Point, Point, Point, Point);
bool overlapping(Point, Point, Point, Point);
typedef struct {
    Fraction first, second;
    Point point;
} Intersection;
bool crossing(OriginalLine, OriginalLine, Intersection *);
Point line_intersection(OriginalLine, OriginalLine);
typedef struct Ring {
    size_t references, count, point_capacity, edge_capacity, edge_count;
    Point *points;
    OriginalLine *edges;
} Ring;
typedef struct {
    Ring **items;
    size_t count, capacity;
} Rings;
typedef struct Polygon {
    size_t references;
    Rings input, rings;
} Polygon;
typedef struct {
    Polygon **items;
    size_t count, capacity;
} PolygonList;
typedef struct {
    PolygonList polygons;
    Polygon *a, *b;
} Result;
Ring *ring_new(void);
void ring_point(Ring *, Point);
void ring_edge(Ring *, OriginalLine);
void ring_complete_integer(Ring *);
Ring *ring_retain(Ring *);
void ring_release(Ring *);
void rings_add(Rings *, Ring *);
void rings_free(Rings *);
Rings rings_copy(const Rings *);
Polygon *polygon_retain(Polygon *);
void polygon_release(Polygon *);
void polygon_list_add(PolygonList *, Polygon *);
void polygon_list_free(PolygonList *);
void result_free(Result *);
Result result_copy(const Result *);
bool on_edge(Point, const Ring *, size_t);
bool inside_ring(Point, const Ring *);
bool interior(Point, const Rings *);
bool boundary(Point, const Ring *);
Ring *rotate_ring(const Ring *);
bool counterclockwise(const Ring *);
Ring *reverse_ring(const Ring *);
Polygon *canonical(const Rings *);
PolygonList assemble(const Rings *);
double ring_area(const Ring *);
double ring_perimeter(const Ring *);
Rings flatten(const PolygonList *);
double total_area(const PolygonList *);
typedef struct Crossing Crossing;
typedef struct GhNode {
    Point point;
    int side;
    Crossing *crossing;
    bool entering;
    OriginalLine outgoing;
    struct GhNode *next, *previous, *other;
} GhNode;
struct Crossing {
    Point point;
    GhNode *first, *second;
    size_t index;
};
typedef struct {
    GhNode **items;
    size_t count, capacity;
} NodeList;
typedef struct {
    Rings rings[2];
    NodeList *nodes[2];
    bool *initial_inside[2];
    GhNode **node_storage;
    size_t node_count, node_capacity;
    Crossing **crossing_storage, **crossings;
    size_t crossing_count, crossing_capacity, order_count;
    int na, nb;
} GhGraph;
GhGraph *graph_new(const Rings *, const Rings *);
Rings traverse(const GhGraph *, bool, bool);
void graph_free(GhGraph *);
typedef struct {
    char **items;
    size_t count, capacity;
} Lines;
typedef struct {
    char *data;
    size_t count, capacity;
} Text;
typedef struct {
    char *storage, **items;
    size_t count;
} Words;
typedef struct {
    Lines rows;
    int result, a, b, both;
} Rendered;
Rendered render(const Result *, int, int, int, int, int, int);
void *allocate(size_t);
void *resize(void *, size_t);
char *copy_text(const char *);
char *format_text(const char *, ...);
void text_add(Text *, const char *);
void text_format(Text *, const char *, ...);
char *text_take(Text *);
void lines_add(Lines *, char *);
void line(Lines *, const char *, ...);
void lines_take(Lines *, Lines);
void lines_free(Lines *);
Words words(const char *);
void words_free(Words *);
Lines read_lines(const char *);
void write_lines(const char *, const Lines *);
#endif
