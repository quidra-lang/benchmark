#ifndef SOLVER_H
#define SOLVER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
typedef struct {
    char **data;
    int count, capacity;
} TextLines;
typedef struct {
    int64_t numerator, denominator;
} Rational;
typedef struct {
    char value[64];
} FractionText;
typedef struct {
    bool finite;
    Rational value;
} Bound;
typedef enum { COMP_LE, COMP_GE, COMP_EQ } Comparison;
typedef enum { BOUND_LOWER, BOUND_UPPER, BOUND_BOTH } BoundKind;
typedef enum { OPTIMAL, INFEASIBLE, UNBOUNDED, NODE_LIMIT, ERROR } Status;
typedef struct {
    int line;
    char *message;
} ModelError;
typedef struct {
    char name[17];
    Rational coefficient;
} Term;
typedef struct {
    Term *data;
    int count, capacity;
} Terms;
typedef struct {
    char name[17];
    Comparison comparison;
    int line;
    Terms terms;
    Rational rhs;
} RawConstraint;
typedef struct {
    int line;
    char name[17];
    BoundKind kind;
    Bound lower, upper;
} BoundLine;
typedef struct {
    int line;
    TextLines names;
} Declaration;
typedef struct {
    char name[17];
    bool maximize;
    Terms objective;
    RawConstraint *constraints;
    int constraint_count, constraint_capacity;
    BoundLine *bounds;
    int bound_count, bound_capacity;
    Declaration *integers, *binaries;
    int integer_count, integer_capacity, binary_count, binary_capacity;
    ModelError error;
} RawModel;
typedef struct {
    char name[17];
    int value;
} Override;
typedef struct {
    int level, limit;
    Override *logs, *limits;
    int log_count, limit_count;
} Settings;
typedef struct {
    char name[17];
    Comparison comparison;
    Rational rhs;
    Rational *coefficients;
} Constraint;
typedef struct {
    char name[17];
    bool maximize;
    char (*variables)[17];
    int variable_count, variable_capacity;
    Rational *cost;
    Constraint *constraints;
    int constraint_count;
    Bound *lower, *upper;
    bool *integer;
    ModelError error;
} Model;
typedef struct {
    Rational values[30][90], beta[30];
    int basis[30], rows, columns;
} Tableau;
typedef struct {
    int iterations, entering;
    TextLines lines;
} PhaseResult;
typedef enum { MAP_SHIFT, MAP_REFLECT, MAP_SPLIT } MapKind;
typedef struct {
    MapKind kind;
    Rational offset;
    int columns[2], column_count, upper_row;
} VariableMap;
typedef struct {
    char columns[90][32], rows[30][20];
    Comparison comparisons[30];
    int column_variable[90], directions[90], sigma[30], initial[30], slack[30];
    bool artificial[90];
    Rational costs1[90], costs2[90];
    VariableMap maps[15];
    int map_count;
    Rational constant;
    int sign;
    Tableau tableau;
} Standard;
typedef struct {
    Status status;
    Rational objective, w, rate;
    Standard standard;
    Rational solution[15], farkas[30], ray[15];
    int phase1, phase2, drives, redundant;
    TextLines log;
} LPResult;
typedef struct {
    Status status;
    Rational objective;
    bool has_solution;
    Rational solution[15];
    LPResult **solves;
    int solve_count, solve_capacity;
    TextLines tree;
} ModelResult;
void *allocate(size_t size);
void *resize(void *data, size_t size);
char *copy_text(const char *text);
char *format_text(const char *format, ...);
void lines_push(TextLines *lines, char *text);
void lines_add(TextLines *lines, const char *text);
void lines_append(TextLines *lines, const TextLines *from);
void lines_free(TextLines *lines);
TextLines read_lines(const char *path);
TextLines split_words(const char *text);
char *join_texts(const TextLines *texts, const char *separator);
Rational rational(int64_t numerator, int64_t denominator);
Rational integer(int64_t value);
Rational rat_add(Rational a, Rational b);
Rational rat_sub(Rational a, Rational b);
Rational rat_mul(Rational a, Rational b);
Rational rat_div(Rational a, Rational b);
Rational rat_neg(Rational value);
Rational rat_abs(Rational value);
int rat_compare(Rational a, Rational b);
int64_t rat_floor(Rational value);
int64_t rat_ceil(Rational value);
bool rat_whole(Rational value);
FractionText rat_text(Rational value);
FractionText rat_approx(Rational value);
FractionText bound_text(Bound value, bool lower);
bool read_number(const char *word, bool signed_number, Rational *out);
RawModel *read_models(int *count);
Settings read_settings(void);
void raw_model_free(RawModel *model);
int integer_count(const Model *model);
const char *status_name(Status status);
const char *comparison_name(Comparison comparison);
void tableau_reduced(const Tableau *tableau, const Rational *cost, Rational *reduced,
                     Rational *value);
void tableau_pivot(Tableau *tableau, int row, int column);
TextLines tableau_display(const Tableau *tableau, const char *heading, const Standard *standard,
                          const Rational *cost, Rational constant, int sign);
PhaseResult phase(Tableau *tableau, const Rational *cost, const bool *candidates,
                  const Standard *standard, Rational constant, int sign);
int lp_pivots(const LPResult *result);
LPResult *solve_lp(const Model *model, const Bound *lower, const Bound *upper, int number,
                   int level);
void result_push(ModelResult *result, LPResult *lp);
ModelResult branch_bound(const Model *model, int limit, int level);
#endif
