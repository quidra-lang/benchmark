#ifndef MESH_H
#define MESH_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
typedef int64_t Integer;
typedef struct {
    Integer v[3];
} Point;
typedef struct {
    int *data;
    int count, capacity;
} IntList;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    IntList vertices;
    int line, group;
} Polygon;
typedef struct {
    int line;
    char *kind;
} InputError;
typedef struct {
    Point vertices[1001];
    int vertex_count;
    Polygon polygons[1000];
    int polygon_count;
    Lines groups;
    InputError errors[2000];
    int error_count, lines, ignored;
} Object;
typedef struct {
    int v[3], polygon, line, group, triangle;
} Face;
typedef struct {
    Face *data;
    int count, capacity;
} Faces;
typedef struct {
    int triangle, polygon, line;
    const char *reason;
} Removed;
typedef struct {
    Point snapped[1001], points[1001];
    int point_count, representative[1001], new_number[1001];
    Faces faces;
    Removed removed[2000];
    int removed_count, triangles, snapped_count, merged_count;
} Cleanup;
typedef struct {
    int snap, fill_holes;
    bool merge, degenerate, duplicates, orient, outward, keep_unused;
    Lines sections;
    Lines queries[50];
    int query_count;
} Options;
typedef struct {
    int a, b;
    IntList faces;
} Edge;
typedef struct {
    Edge *edges;
    int edge_count, vertices, face_count, component_count;
    int *face_component, *fans;
    IntList *component_faces, *component_vertices, *component_edges, *vertex_faces, *vertex_edges, *neighbors,
        *fan_components, *component_nonmanifold_vertices;
} Topology;
typedef struct {
    int component;
    IntList vertices;
    bool closed, filled;
    const char *kind;
} Loop;
typedef struct {
    Loop *data;
    int count, capacity;
} Loops;
void *resize(void *memory, size_t size);
char *text(const char *value);
char *format(const char *pattern, ...);
void int_push(IntList *list, int value);
bool int_contains(const IntList *list, int value);
IntList int_copy(const IntList *list);
void int_free(IntList *list);
void int_sort(IntList *list);
char *list(const IntList *values, int offset);
void line_push(Lines *lines, char *line);
void free_lines(Lines *lines);
Lines read_lines(const char *path);
Lines words(const char *line);
bool integer_word(const char *word);
Object *read_object(void);
void write_lines(const char *name, const Lines *lines);
void write_object(const Cleanup *clean, const Lines *groups);
void face_push(Faces *faces, Face face);
Topology analyze(const Faces *faces, int vertices);
void topology_free(Topology *topology);
int edge_index(const Topology *topology, int a, int b);
Loops trace_loops(const Topology *topology);
void loops_free(Loops *loops);
int loop_length(const Loop *loop);
bool directed(const Face *face, int a, int b);
void flip(Face *face);
void orient_faces(Faces *faces, const Topology *topology);
IntList inconsistent_edges(const Faces *faces, const Topology *topology);
Point difference(Point a, Point b);
Point cross(Point a, Point b);
Integer dot(Point a, Point b);
Point normal(const Face *face, const Point *points);
Integer determinant(const Face *face, const Point *points);
double area(const IntList *face_ids, const Faces *faces, const Point *points);
char *fraction(Integer numerator, Integer denominator);
char *real(double value);
char *point_text(Point point);
char *centroid(const IntList *face_ids, const Faces *faces, const Point *points, Integer volume6);
int winding(Point point, const IntList *face_ids, const Faces *faces, const Point *points);
const char *triangle_angle(const Face *face, const Point *points);
Faces triangulate(const Object *object);
Cleanup *cleanup(const Object *object, const Options *options);
void fill_faces(Faces *faces, const Loop *loop, int group);
#endif
