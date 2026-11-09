#ifndef REGRESSION_H
#define REGRESSION_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
typedef struct {
    double *data;
    int count;
} Vector;
typedef struct {
    double *data;
    int rows, columns;
} Matrix;
#define AT(matrix, row, column) ((matrix).data[(size_t)(row) * (size_t)(matrix).columns + (size_t)(column)])
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    int *data;
    int count, capacity;
} IntList;
typedef struct {
    bool missing;
    double number;
    char *label;
} Cell;
typedef struct {
    Cell cells[12];
} Record;
typedef struct {
    Lines names;
    bool categorical[12];
    Record *rows;
    int count;
} Dataframe;
typedef struct {
    double rank_tol, alpha, confidence, leverage, studentized, cook, dffits, vif, durbin, breusch, normality,
        plot_limit;
    int best_subsets, plot_width, plot_height;
} Params;
typedef struct {
    Dataframe data, prediction;
    Lines formulas;
    Params params;
} Input;
typedef struct {
    char *name;
    int column, power;
    bool categorical;
} Factor;
typedef struct {
    Factor factors[3];
    int count;
    char *name;
} Term;
typedef struct {
    int response, weight;
    char *raw;
    Term *terms;
    int count;
} Formula;
typedef struct {
    char *name, *label;
    int column, power;
    bool categorical;
} Component;
typedef struct {
    char *name;
    int term;
    Component components[3];
    int count;
} Column;
typedef struct {
    Formula formula;
    IntList used;
    Lines levels[12];
    Column columns[20];
    int count;
    Matrix x;
    Vector y, weights;
} Design;
typedef struct {
    int rank;
    IntList accepted;
    bool *alias;
    Vector coefficients, effects, variance, fitted, residuals, weighted_residuals, leverage;
    Matrix triangular, inverse, u, g;
    double rss;
} Fit;
typedef struct {
    Vector standardized, studentized, cooks, dffits;
    Lines flags;
    Matrix dfbetas;
    int flag_counts[4], any;
    double durbin, bp, bp_p, jb, jb_p, skewness, kurtosis;
    int bp_df;
} Diagnostics;
void *resize(void *memory, size_t size);
char *text(const char *value);
char *format(const char *pattern, ...);
void line_push(Lines *lines, char *line);
void lines_extend(Lines *target, const Lines *source);
void lines_free(Lines *lines);
void int_push(IntList *list, int value);
bool int_contains(const IntList *list, int value);
void int_sort(IntList *list);
Vector vector_new(int count);
Matrix matrix_new(int rows, int columns);
Input *read_input(void);
Formula parse_formula(const char *line, const Dataframe *data);
bool contained(const Term *a, const Term *b);
char *formula_text(const Formula *formula, const IntList *terms, const Dataframe *data);
Design *build_design(Formula formula, const Dataframe *data);
IntList selected_columns(const Design *design, const IntList *terms);
Vector record_values(const Column *columns, int count, const Record *record);
bool predictable(const Design *design, const Record *record);
Fit fit(const Matrix *x, const Vector *y, const Vector *weights, double tolerance);
void fit_free(Fit *model);
double log_gamma(double x);
double beta_fraction(double a, double b, double x);
double beta_i(double x, double a, double b);
double gamma_q(double a, double x);
double p_t(double value, double degrees);
double p_f(double value, double first, double second);
double p_chi(double value, double degrees);
double t_quantile(double confidence, double degrees);
const char *significance(double p);
char *real(double value);
char *p_format(double value);
Diagnostics diagnostics(const Matrix *x, const Vector *weights, const Fit *model, const Params *params);
void diagnostics_free(Diagnostics *diagnostics);
#endif
