#ifndef BOOSTING_H
#define BOOSTING_H
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
typedef struct {
    char id[9];
    double values[10];
    int label;
} Row;
typedef struct {
    int n, d;
    Row rows[400];
} Rows;
typedef struct {
    int n, v[1000];
} Ints;
typedef struct {
    int n;
    double v[400];
} Vector;
typedef struct {
    int rounds, bins, folds, classes, samme_rounds, permutations, bootstrap, nvariants;
    char variants[4][9];
    double smoothing, convergence, clip;
    int64_t permutation_seed, noise_seed, bootstrap_seed;
    Vector margins, shrinkage;
    Ints noise, sizes;
} Params;
typedef struct {
    Rows train, test, multi_train, multi_test;
    char names[10][17], multi_names[10][17];
    Params params;
} Input;
Input *read_input(void);
typedef struct {
    int feature, nthresholds;
    double thresholds[9], values[10];
} Stump;
double stump_output(const Stump *stump, const double *values);
typedef struct {
    int n, order[400], ends[400];
    double thresholds[400], cuts[9];
} Feature;
typedef struct {
    int d;
    Feature features[10];
} Search;
Search *prepare(const Rows *rows, int bins);
typedef struct {
    Stump stump;
    double error;
    int polarity;
} Candidate;
Candidate discrete_stump(const Rows *rows, const Search *search, const double *weights);
Candidate regression_stump(const Rows *rows, const Search *search, const double *targets,
                           const double *weights);
Candidate multiclass_stump(const Rows *rows, const Search *search, const double *weights, int classes);
typedef struct {
    Stump stump;
    double z;
} RealCandidate;
RealCandidate real_stump(const Rows *rows, const Search *search, const double *weights, int bins,
                         double smoothing);
typedef struct {
    Stump stump;
    double weights[400], error, alpha, z, bound, loss;
    int polarity;
} Round;
typedef struct {
    const char *variant, *stop;
    int n;
    Round rounds[50];
    double cuts[10][9];
} Model;
Model *discrete(const Rows *rows, const Params *p, int maximum, double shrinkage,
                const double *initial_weights);
Model *samme(const Rows *rows, const Params *p);
Model *variant_train(const Rows *rows, const Params *p, const char *variant);
const char *real(double value, int precision);
const char *ratio(int64_t a, int64_t b);
int prediction(double score);
typedef struct {
    int64_t numerator, denominator;
} Fraction;
Fraction auc(const Rows *rows, const double *scores);
void confusion(const Rows *rows, const int *predictions, int classes, int out[6][6]);
int margin_count(const double *margins, int n, double threshold);
typedef struct {
    char *data;
    size_t size, capacity;
} Text;
void add(Text *out, const char *format, ...);
void line(Text *out, const char *format, ...);
void write_report(const char *name, Text text);
#endif
