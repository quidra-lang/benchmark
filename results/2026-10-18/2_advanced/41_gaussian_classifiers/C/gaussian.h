#ifndef GAUSSIAN_H
#define GAUSSIAN_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
typedef struct {
    double v[6];
} Vector;
typedef struct {
    double v[6][6];
} Matrix;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    int *data;
    int count, capacity;
} IntList;
typedef struct {
    double *data;
    int count, capacity;
} DoubleList;
typedef struct {
    int v[6], count;
} Features;
typedef struct {
    int id, label;
    Vector values;
} Row;
typedef struct {
    Row *data;
    int count, capacity;
} Rows;
typedef struct {
    char *name;
    Features features;
} Subset;
typedef struct {
    int x, y;
} Pair;
typedef struct {
    bool empirical;
    double smoothing, gamma, outlier;
    DoubleList smoothing_grid, gamma_grid, calibration, reject;
    IntList curve;
    int folds, bootstrap, map_width, map_height, plot_width, plot_height;
    int64_t seed;
    Subset *subsets;
    int subset_count;
    Pair *pairs;
    int pair_count;
} Params;
typedef struct {
    Lines features, classes;
    Rows train, test;
    double costs[5][5];
    Params params;
} Dataset;
typedef struct {
    Vector values;
    Matrix vectors;
    int sweeps;
} Eigen;
typedef struct {
    int count, classes, size, counts[5];
    Vector means[5];
    Matrix scatter[5];
    Vector center, variance;
    double priors[5];
} Statistics;
typedef struct {
    int kind;
    Features features;
    Statistics stats;
    Matrix covariance[5], lower[5];
    double log_det[5], max_variance, added;
} Model;
typedef struct {
    int predicted, decision;
    double posterior[5], log_posterior[5], distance[5], confidence;
} Prediction;
typedef struct {
    int64_t numerator, denominator;
} Fraction;
typedef struct {
    int confusion[5][5], support[5], predicted[5], correct, total, classes;
    Fraction accuracy, balanced, kappa, recall[5], precision[5], f1[5];
    double macro_f1;
} Measures;
typedef struct {
    int b01, b10;
    double chi2;
} McNemar;
typedef struct {
    int64_t state;
} Generator;
void *resize(void *memory, size_t size);
char *text(const char *value);
char *format(const char *pattern, ...);
void line_push(Lines *lines, char *line);
void lines_extend(Lines *target, const Lines *source);
void lines_free(Lines *lines);
void int_push(IntList *list, int value);
void double_push(DoubleList *list, double value);
void row_push(Rows *rows, Row row);
Dataset *read_dataset(void);
Matrix cholesky(const Matrix *matrix, int size);
Vector forward(const Matrix *lower, const Vector *right, int size);
Vector backward(const Matrix *lower, const Vector *right, int size);
double log_determinant(const Matrix *lower, int size);
double quadratic(const Matrix *lower, const Vector *right, int size);
Eigen jacobi(const Matrix *matrix, int size);
Statistics statistics(const Rows *rows, Features features, int classes, bool empirical);
Model train(const Rows *rows, Features features, int classes, int kind, bool empirical, double smoothing,
            double gamma);
Prediction predict(const Model *model, const Vector *values, const double costs[5][5]);
Fraction make_fraction(int64_t a, int64_t b);
Fraction fraction_add(Fraction a, Fraction b);
Fraction fraction_divide(Fraction value, int64_t divisor);
Measures evaluate(const Rows *rows, const int *prediction, int classes);
McNemar mcnemar(const Rows *rows, const int *a, const int *b);
int64_t draw(Generator *generator);
char *real(double value);
char *fraction(Fraction value);
Lines frame(const Lines *cells);
int cell(double value, double low, double high, int size);
void write_lines(const char *name, const Lines *lines);
char *numbers(Vector values, int size);
char *integers(const IntList *values);
char *names(Features features, const Lines *names);
#endif
