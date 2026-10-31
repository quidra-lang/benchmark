#ifndef REGRESSION_H
#define REGRESSION_H
#include <inttypes.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int64_t Integer;
typedef struct {
    double values[31];
    int count;
} Vector;
typedef struct {
    double values[300];
    int count;
} Scores;
typedef struct {
    int values[300];
    int count;
} Targets;
typedef struct {
    double values[300][31];
    int rows, columns;
} Matrix;
typedef struct {
    double values[31][31];
    int size;
} Square;
typedef struct {
    char id[9];
    double values[6];
    int label;
} Row;
typedef struct {
    char names[6][9];
    Row rows[300];
    int count, features;
} Table;
typedef struct {
    int indices[3], degree;
    char name[27];
} Feature;
typedef struct {
    Feature values[30];
    int count;
} Features;
typedef struct {
    double mean[30], deviation[30];
    int count;
} Statistics;
typedef struct {
    int positive, degree, gd_iterations, batch, epochs, softmax_iterations, bootstrap, permutations, width,
        height, fp_cost, fn_cost, lambda_count;
    Integer sgd_seed, bootstrap_seed, permutation_seed;
    double threshold, gd_rate, sgd_rate, softmax_rate, softmax_lambda, lambdas[8];
} Params;
Table read_table(const char *);
Params read_params(void);
Features build_features(const Table *, int);
Vector expand(const double *, const Features *);
Matrix expanded(const Table *, const Features *);
Statistics statistics(const Matrix *, int);
Vector standardize_point(Vector, const Statistics *, int);
Matrix standardize(const Matrix *, const Statistics *, int);
Targets labels(const Table *, int);
double score(Vector, const double *);
double sigmoid(double);
double logistic_loss(double, int);
Scores probabilities(Vector, const Matrix *);
double average_loss(Vector, const Matrix *, const Targets *);
double objective(Vector, const Matrix *, const Targets *, double);
Vector gradient(Vector, const Matrix *, const Targets *, double);
Square hessian(Vector, const Matrix *, double);
double length(Vector);
typedef struct {
    Integer state;
} Minstd;
Integer draw(Minstd *);
void shuffle(Minstd *, Targets *);
Square cholesky(Square);
Vector solve(Square, Vector);
typedef struct {
    int iteration;
    Vector weights;
} Checkpoint;
typedef struct {
    Checkpoint points[101];
    int count;
} Trace;
Trace newton(const Matrix *, const Targets *, double);
Trace gradient_descent(const Matrix *, const Targets *, double, double, int);
Trace stochastic(const Matrix *, const Targets *, double, const Params *);
typedef struct {
    Vector classes[4];
    int count;
} SoftWeights;
typedef struct {
    double probabilities[4], loss;
    int predicted;
} SoftPoint;
SoftPoint soft_point(SoftWeights, const double *, int);
double soft_loss(SoftWeights, const Matrix *, const Targets *);
double soft_objective(SoftWeights, const Matrix *, const Targets *, double);
SoftWeights soft_gradient(SoftWeights, const Matrix *, const Targets *, double);
typedef struct {
    int iteration;
    SoftWeights weights;
} SoftCheckpoint;
typedef struct {
    SoftCheckpoint points[11];
    int count;
} SoftTrace;
SoftTrace train_softmax(const Matrix *, const Targets *, int, const Params *);
char *real(double, int);
char *ratio(Integer, Integer);
typedef struct {
    Integer numerator, denominator;
} Fraction;
char *fraction_text(Fraction);
typedef struct {
    Integer tp, fp, tn, fn;
} Confusion;
Confusion confusion(Scores, const Targets *, double);
Fraction auc(Scores, const Targets *);
typedef struct {
    double threshold;
    Integer tp, fp;
} RocPoint;
typedef struct {
    RocPoint points[300];
    int count;
} Roc;
Roc roc(Scores, const Targets *);
#endif
