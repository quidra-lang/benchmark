#ifndef RECOMMENDER_H
#define RECOMMENDER_H
#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef struct {
    int n, v[1000];
} Ints;
typedef struct {
    int n;
    char **v;
} Strings;
typedef struct {
    char *data;
    size_t size, capacity;
} Text;
typedef struct {
    int user, item, rating;
    int64_t time;
} Rating;
typedef struct {
    int id;
    char *title, *genre_list;
    Strings genres;
} Item;
typedef struct {
    int neighbors, shrinkage, factors, epochs, iterations, top, buckets, list;
    double minimum, item_reg, user_reg, rate, regularization, als_reg;
    int64_t seed;
    Ints cutoffs, grid, user_groups, item_groups, users, items;
} Params;
typedef struct {
    int nu, ni, nc, nt, nm;
    Rating train[5000], test[1000];
    Item catalog[300], items[300];
    int users[200], user_count[200], item_count[300], user_sum[200], item_sum[300], ratings[200][300];
    double user_mean[200], item_mean[300], mean;
    Params params;
} Data;
Data *read_input(void);
char *copy_string(const char *text);
void strings_add(Strings *values, const char *value);
Strings split(const char *text, char delimiter);
bool strings_has(Strings values, const char *value);
void strings_sort(Strings values);
typedef struct {
    bool user_defined[200][200], item_defined[300][300];
    double user[200][200], item[300][300];
    int user_common[200][200], common[300][300], difference[300][300];
} Similarities;
Similarities *similarities(const Data *data);
typedef struct {
    int index;
    double similarity;
} Neighbor;
int select_neighbors(Neighbor *candidates, int count, int limit);
typedef struct {
    const char *method;
    int epoch;
    double rmse;
} Training;
typedef struct {
    double p[200][20], q[300][20], x[200][20], y[300][20], user_bias[200], item_bias[300];
    Training log[70];
    int log_count;
} Factors;
double factor_dot(const double *a, const double *b, int n);
void solve(const double a[20][20], const double *w, double *x, int n);
Factors *train_factors(const Data *data, const double *user_bias, const double *item_bias);
double clip(double value);
double rmse(const double *errors, int n);
double mae(const double *errors, int n);
double rank_weight(int rank);
typedef struct {
    int hits;
    double recall, ndcg, ap, rr;
} RankingMetrics;
RankingMetrics ranking_metrics(Ints list, const bool *relevant, int nrelevant, int length);
const char *real(double value);
void add(Text *out, const char *format, ...);
void line(Text *out, const char *format, ...);
void write_report(const char *name, Text text);
#endif
