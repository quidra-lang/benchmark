#ifndef SEGMENTS_H
#define SEGMENTS_H
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
typedef double Point[6];
typedef struct { const Point *v; int n, dimensions; } Points;
typedef struct { char **items; int count, capacity; } Lines;
typedef struct {
    int reference, snapshot, outcome_days, min_k, max_k, restarts, iterations;
    char *methods[3]; int method_count;
    Integer seed;
    int subsamples, percent, overdue_factor, order_bins[10], bin_count;
    int top_categories, top_customers, period_days, periods;
    double outlier_sd;
} Settings;
typedef struct { int customer, day, category; char order_id[13]; Integer amount; } Row;
typedef struct {
    Settings settings;
    Row *rows; int valid_count, row_count, duplicates, free_rows;
    char **ids, **categories; int customer_count, category_count;
} Transactions;
typedef struct { int customer, day; const char *id; Integer net; const Row **rows; int row_count; } Order;
typedef struct { Order *items; int count; } Orders;
typedef struct {
    int file_number;
    const char *id;
    Integer spend;
    Order **orders; int order_count;
    Integer *category_spend; bool *category_present;
    Point raw, transformed, point;
} Customer;
typedef struct { Customer *items; int count; } Customers;
typedef struct { Point mean, sd, raw_mean, raw_sd; } Scaling;
typedef struct { double mean, sd; } Moments;
typedef struct { int labels[400]; Point centers[10]; int iterations, reseeds; bool converged; double sse; } Lloyd;
typedef struct { int feature; bool greater; double threshold; } Condition;
typedef struct { char *name; Condition *conditions; int count; } Rule;
typedef struct { Rule *items; int count; } Rules;
extern const char *feature_names[6];
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
void extend(Lines *target, Lines source);
Lines read_lines(const char *path);
int split_fields(char *line, const char *separator, char **parts);
int string_index(char *const *values, int count, const char *value);
Transactions read_transactions(void);
Orders group_orders(const Transactions *data, int first, int last);
Customers eligible_customers(const Transactions *data, Orders orders, int day);
double ordered_sum(const double *values, int count);
Moments mean_sd(const double *values, int count);
Scaling fit_scaling(Customers customers);
void standardize(Customers customers, const Scaling *scaling);
double correlation(Points points, int first, int second);
double squared_distance(const double *first, const double *second, int dimensions);
void mean_point(Points points, double *result);
void assign_points(Points points, const Point *centers, int k, int *labels, double *errors);
void cluster_sizes(const int *labels, int count, int k, int *sizes);
void cluster_center(Points points, const int *labels, int label, double *center);
void cluster_centers(Points points, const int *labels, int k, Point *centers);
int refill(int *labels, double *errors, int count, int k);
Lloyd lloyd(Points points, const Point *initial, int k, int limit);
double sse(Points points, const int *labels, const Point *centers);
double *distance_table(Points points);
void silhouettes(const double *table, const int *labels, const int *sizes, int count, int k, double *result);
double calinski_harabasz(Points points, const Point *centers, const int *sizes, int k, double within);
double davies_bouldin(Points points, const int *labels, const Point *centers, const int *sizes, int k);
double elbow(int k, int first_k, int last_k, double within, double first, double last);
double hartigan(double within, double next, int count, int k);
double adjusted_rand(const int *first, const int *second, int count);
Rules read_rules(void);
int matching_rule(Rules rules, const double *center);
void original_scale(const double *center, const Scaling *scaling, double *result);
char *real_text(double value);
double rounded_key(double value);
char *amount(Integer cents);
char *reals(const double *values, int count);
char *integers(const int *values, int count);
void write_lines(const char *name, Lines lines);
#endif
