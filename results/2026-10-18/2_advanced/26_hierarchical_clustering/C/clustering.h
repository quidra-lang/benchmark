#ifndef CLUSTERING_H
#define CLUSTERING_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MAX_OBSERVATIONS 120
#define MAX_FEATURES 10
#define MAX_NODES 239
#define MAX_PAIRS 7140

typedef int64_t Integer;
typedef double Matrix[MAX_OBSERVATIONS][MAX_OBSERVATIONS];
typedef double Vectors[MAX_OBSERVATIONS][MAX_FEATURES];
typedef struct { char **items; size_t count, capacity; } Lines;
typedef struct { char *data; size_t length, capacity; } Text;
typedef struct {
    char *distance, *standardize, *compare_linkage, *depth_text;
    char *linkages[7];
    int linkage_count, cut_count, cut_counts[MAX_OBSERVATIONS];
    double *cut_heights;
    size_t height_count;
    int depth, inconsistency_count, gap_max_k, list_size, width;
    int replicates, percent, refine_iterations;
    Integer seed;
} Settings;
typedef struct {
    int count, features;
    char *feature_names[MAX_FEATURES], *ids[MAX_OBSERVATIONS], *labels[MAX_OBSERVATIONS];
    Vectors raw;
    Settings settings;
} Dataset;
typedef struct { int a, b, size; double height; } Merge;
typedef struct { int parent, child; double weight; } Edge;
typedef struct {
    int count;
    Merge merges[MAX_OBSERVATIONS - 1];
    int children[MAX_OBSERVATIONS - 1][2], order[MAX_OBSERVATIONS];
    int sizes[MAX_NODES], members[MAX_NODES][MAX_OBSERVATIONS], depths[MAX_NODES];
    double heights[MAX_OBSERVATIONS - 1], subtree_heights[MAX_OBSERVATIONS - 1];
} Tree;
typedef struct { Integer numerator, denominator; } Fraction;

void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
void append_lines(Lines *target, Lines source);
void paragraph(Lines *target, Lines source);
Lines read_lines(const char *path);
Dataset *read_dataset(void);
void write_lines(const char *name, Lines lines);
double sequential_sum(const double *values, int count);
double squared_distance(const double *first, const double *second, int features);
void feature_statistics(const Dataset *data, double means[MAX_FEATURES], double deviations[MAX_FEATURES]);
void analysis_vectors(const Dataset *data, const double *means, const double *deviations, Vectors vectors);
double vector_distance(const double *first, const double *second, int features, const char *kind);
void distance_matrix(const Vectors vectors, int count, int features, const char *kind, Matrix matrix);
void agglomerate(const Matrix delta, int count, const char *method, Merge *merges);
void minimum_spanning_tree(const Matrix delta, int count, Edge *edges);
void ordered_children(Tree *tree);
void leaf_order(Tree *tree);
int column_position(double height, double maximum, int width);
Lines dendrogram_rows(const Tree *tree, const Dataset *data, double maximum, const int *cuts, size_t cut_count, int width);
double correlation(const double *first, const double *second, int count);
Fraction fraction(Integer numerator, Integer denominator);
double fraction_value(Fraction value);
bool fraction_greater(Fraction first, Fraction second);
Fraction adjusted_rand(const int *first, const int *second, int count, int first_groups, int second_groups);
void silhouette_values(const int *partition, int count, int groups, const Matrix delta, double *values);
#endif
