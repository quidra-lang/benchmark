#ifndef LAYOUT_H
#define LAYOUT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <limits.h>
#include <sys/stat.h>
typedef struct {
    int *data;
    int count, capacity;
} IntList;
typedef struct {
    char **data;
    int count, capacity;
} TextLines;
typedef struct {
    IntList rows[600];
    int count;
} Orders;
typedef enum { DIR_TB, DIR_BT, DIR_LR, DIR_RL } Direction;
typedef struct {
    bool coffman, promotion, median, sifting, reduce;
    int width, sweeps, node_sep, dummy_sep, layer_gap, restarts;
    int64_t seed;
    Direction direction;
} Settings;
typedef struct {
    int id;
    char label[13];
} NodeData;
typedef struct {
    int from, to;
} RawEdge;
typedef struct {
    char name[21];
    Settings settings;
    NodeData nodes[40];
    int node_count;
    RawEdge edges[150];
    int edge_count;
    bool has_path;
    int path_from, path_to, self_loops, duplicates, error_line;
    const char *error;
} Block;
typedef struct {
    int row, column;
} Cell;
typedef struct {
    Cell *data;
    int count, capacity;
} CellList;
typedef struct {
    unsigned char lines;
    char arrow, box;
    bool highlighted;
} Pixel;
typedef struct {
    int main_length, secondary_length, rows, columns;
    Direction direction;
    Pixel *cells;
} Canvas;
typedef struct {
    int from, to, upper, lower;
    bool reversed, transitive;
    IntList chain, segments;
    int span, crossings, bends, length;
    CellList route;
} Edge;
typedef struct {
    char name[16];
    int layer, width, left, right, x;
    IntList upper, lower;
} Vertex;
typedef struct {
    int upper, lower, edge, gap, offset;
} Segment;
typedef struct {
    int round, node, difference;
} Promotion;
typedef struct {
    int height[40], labels[40], dummies_before, rounds;
    Promotion *promotions;
    int promotion_count, promotion_capacity;
} LayeringResult;
typedef struct {
    int run, number, moved, swaps, crossings;
} Sweep;
typedef struct {
    int round, moves, crossings;
} Sift;
typedef struct {
    int root[600], aligned[600], blocks, width, low, high;
} BKVariant;
typedef struct {
    unsigned char *marked;
    int conflicts;
    BKVariant variants[4];
    int smallest;
} Coordinates;
typedef struct {
    const Block *block;
    int nodes, vertex_count, edge_count, segment_count;
    Vertex vertices[600];
    Edge edges[120];
    Segment segments[720];
    Orders gaps, orders, scc;
    IntList acyclic;
    LayeringResult layering;
    Coordinates coordinates;
    Sweep sweeps[510];
    int sweep_count;
    Sift *sifts;
    int sift_count, sift_capacity;
    int best_run, best_sweep, initial_crossings, adopted_crossings, final_crossings, brute;
    int sources, sinks, isolated, components;
    int tracks[599], gap_widths[599], band_starts[600], thickness[600];
    int main_length, secondary_length;
    Canvas canvas;
    IntList path;
} Layout;
extern const char *setting_names[13];
extern const char *variant_names[4];
void *allocate(size_t size);
void *resize(void *data, size_t size);
char *copy_text(const char *text);
char *format_text(const char *format, ...);
void int_push(IntList *list, int value);
void int_add(IntList *list, int value);
bool int_has(const IntList *list, int value);
IntList int_copy(const IntList *list);
void int_free(IntList *list);
void lines_push(TextLines *lines, char *text);
void lines_add(TextLines *lines, const char *text);
void lines_append(TextLines *lines, const TextLines *from);
void lines_free(TextLines *lines);
TextLines read_lines(const char *path);
TextLines split_words(const char *text);
char *join_texts(const TextLines *texts, const char *separator);
const char *direction_name(Direction direction);
bool vertical(Direction direction);
TextLines settings_values(Settings settings);
Block *read_blocks(int *count);
IntList acyclic(int nodes, const Edge *edges, int edge_count);
LayeringResult assign_layers(const Orders *predecessors, const Orders *successors,
                             Settings settings);
void positions(const Orders *orders, int *out);
int gap_crossings(const Segment *segments, const IntList *indices, const int *positions, int width);
int total_crossings(const Layout *layout, const Orders *orders);
int brute_crossings(Layout *layout, const Orders *orders, bool count_edges);
int adjacent_cost(const Layout *layout, int left, int right, const int *positions);
int floor_div(int a, int b);
Coordinates coordinates(Layout *layout);
Canvas canvas_create(int main_length, int secondary_length, Direction direction);
Cell canvas_map(const Canvas *canvas, int main, int secondary);
Pixel *canvas_at(Canvas *canvas, Cell cell);
void canvas_line(Canvas *canvas, int main, int secondary, unsigned char kind);
void canvas_main_line(Canvas *canvas, int main, int secondary);
void canvas_segment(Canvas *canvas, int start, int gap, int upper, int lower, int offset);
void canvas_highlight(Canvas *canvas, Cell from, Cell to);
int canvas_crossing_cells(const Canvas *canvas);
TextLines canvas_drawing(const Canvas *canvas, const char *name);
void orders_free(Orders *orders);
Orders orders_copy(const Orders *orders);
#endif
