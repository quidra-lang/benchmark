#ifndef ANALYSIS_H
#define ANALYSIS_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <sys/stat.h>
#include <errno.h>

typedef long long Integer;
typedef struct { char **items; int count, capacity; } Lines;
typedef struct { int *values, count; } Nodes;
typedef struct { int id; char *host, *title; char *words[8]; int word_count; } Page;
typedef struct { int line, source, target; } Record;
typedef struct { char *words[4]; int word_count, seeds[5], seed_count; } Query;
typedef struct {
    double damping, tolerance, sweep[5], spam_threshold;
    int iterations, sweep_count, trusted[10], trusted_count, spam_top, hits_iterations, top_k, root_limit, neighbor_limit;
} Settings;
typedef struct { Page pages[500]; int count; Record records[6000]; int record_count; Query queries[20]; int query_count; Settings settings; } Input;
typedef struct { int count; int *weights; Nodes out[500], in[500]; } Graph;
typedef struct { int count, labels[500], sizes[500], minimum[500]; } Components;
typedef struct { double values[500], changes[100]; int iterations, converged_at; } PageRank;
typedef struct { double authority[500], hub[500]; } Hits;
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
void extend(Lines *target, Lines source);
Lines read_lines(const char *path);
int split_fields(char *line, const char *separator, char **parts);
void read_input(Input *input);
Graph graph_from_weights(int count, int *weights);
Components strong_components(const Graph *graph);
void reachable(const Graph *graph, const bool *starts, bool reverse, bool *seen);
void bfs_distances(const Graph *graph, const bool *starts, int *distances);
int weak_components(const Graph *graph, int *labels);
PageRank power_iteration(const Graph *graph, const bool *teleport, double damping, int iterations, double tolerance);
Hits hits(const Graph *graph, const bool *nodes, int iterations);
char *fixed(double value, int places);
Integer scaled(double value, int places);
char *fraction(Integer numerator, Integer denominator);
void write_lines(const char *name, Lines lines);
#endif
