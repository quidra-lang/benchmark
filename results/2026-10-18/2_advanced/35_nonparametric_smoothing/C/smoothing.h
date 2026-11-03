#ifndef SMOOTHING_H
#define SMOOTHING_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <inttypes.h>
typedef int64_t Integer;
typedef struct {
    char **data;
    size_t len, cap;
} Lines;
typedef struct {
    char *data;
    size_t len, cap;
} Text;
typedef struct {
    bool defined;
    double value;
} Optional;
Optional some(double value);
void *allocate(size_t count, size_t size);
void grow(void **data, size_t *cap, size_t need, size_t size);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void line_add(Lines *lines, const char *pattern, ...);
void extend(Lines *out, Lines lines);
Lines read_lines(const char *path);
Lines split(const char *text, char delimiter);
typedef struct {
    int n, x[200], y[200];
    double real_x[200], real_y[200];
} Data;
typedef struct {
    char *name;
    Data data;
} Series;
typedef struct {
    char *series;
    int x;
} TestPoint;
typedef struct {
    Lines rows[17];
} Params;
typedef struct {
    Series series[3];
    int series_count;
    TestPoint tests[100];
    int test_count;
    Params params;
} Input;
int hundredths(const char *text);
Input *read_input(void);
typedef enum { LINEAR, MEAN, MEDIAN, NW, LL, LOESS, SPLINE, ISOTONIC } Kind;
typedef struct {
    char *text;
    double value;
    int integer;
} Parameter;
typedef struct {
    char *name;
    Kind kind;
    char *kernel;
    int degree, candidate_count;
    Parameter candidates[10];
} Method;
typedef struct {
    Optional estimate;
    double weights[200];
    Optional leverage;
} KernelResult;
KernelResult kernel_estimate(const Data *data, const char *kernel, int bandwidth, int position,
                             bool local_linear);
typedef struct {
    double value, zeta, weights[200];
} LocalFit;
LocalFit local_fit(const Data *data, int position, int span, int degree, const double *rho);
double median(const double *values, int count);
typedef struct {
    double scale;
    int zero;
    double change;
} Robust;
typedef struct {
    double fitted[200], leverage[200], rho[200], edf;
    Robust iterations[10];
    int count;
} LoessFit;
LoessFit loess_fit(const Data *data, int span, int degree, int iterations);
typedef struct {
    double fitted[200], gamma[200];
} SplineValues;
typedef struct {
    int n, positions[200];
    double x[200], h[200], d[200], l1[200], l2[200], penalty;
    SplineValues *basis;
} Spline;
Spline *spline_create(const int *positions, int count, double penalty);
SplineValues spline_fit(const Spline *spline, const double *values);
double spline_evaluate(const Spline *spline, const SplineValues *fit, int position);
void spline_prepare(Spline *spline);
void spline_leverage(Spline *spline, double *values);
void spline_weights(const Spline *spline, int position, double *values);
Optional loo_score(const double *observed, const Optional *predictions, int count);
double gcv_score(const double *observed, const double *fitted, int count, double edf);
int selected_candidate(const Optional *scores, int count);
typedef struct {
    int first, last;
    Integer sum;
    int count;
} IsoBlock;
typedef struct {
    Data data;
    Method method;
    Parameter parameter;
    double fitted[200], leverage[200], rho[200];
    Optional edf;
    double intercept, slope, xbar, sxx;
    Spline *spline;
    SplineValues spline_values;
    IsoBlock blocks[200];
    int block_count;
    Robust robust[10];
    int robust_count;
    char *direction;
    double increasing_rss, decreasing_rss;
    bool defined;
} Fit;
Fit make_fit(const Data *data, const Method *method, Parameter parameter, const char *direction,
             int robust_iterations, bool full);
Optional estimate(const Fit *fit, int position);
void weights(const Fit *fit, int position, double *values);
#endif
