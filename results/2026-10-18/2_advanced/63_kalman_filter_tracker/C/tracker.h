#ifndef TRACKER_H
#define TRACKER_H
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <float.h>
#include <sys/stat.h>
typedef struct {
    double x, y;
} Position;
typedef struct {
    int count;
    double values[6];
} Vector;
typedef struct {
    int rows, columns;
    double values[6][6];
} Matrix;
typedef struct {
    int row, column;
} Pair;
typedef struct {
    Pair *data;
    int count;
} Pairs;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    bool ca;
    double q_cv, q_ca, sigma, velocity, acceleration, gate, delta, cutoff, bound, xmin, xmax, ymin,
        ymax;
    int confirm, window, deletion, width, height;
    double abg[3], imm_q[2], imm_initial[2], transition[2][2], edges[10];
    int edge_count;
} Params;
typedef struct {
    Position residual;
    Matrix covariance, precision;
    double distance;
} Innovation;
typedef struct {
    bool ca;
    double q;
    Vector x, xp;
    Matrix P, Pp, F, H, R;
} Kalman;
typedef struct {
    Vector x, xp;
    Matrix P, Pp, F;
} History;
typedef struct {
    Kalman models[2];
    double probabilities[2], transition[2][2];
} IMM;
typedef struct {
    int covered, breaks, swaps, delay;
} Continuity;
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...), *joined(const char *first, const char *second);
void line(Lines *lines, const char *pattern, ...);
Matrix zeros(int rows, int columns), identity(int n), diagonal(Vector values), transpose(Matrix a),
    matrix_add(Matrix a, Matrix b), matrix_subtract(Matrix a, Matrix b),
    matrix_product(Matrix a, Matrix b), inverse(Matrix a);
Vector vector_add(Vector a, Vector b), vector_subtract(Vector a, Vector b),
    matrix_vector(Matrix a, Vector b);
double determinant2(Matrix a), quadratic2(Position v, Matrix a);
Matrix transition(bool ca, double t), process_noise(bool ca, double t, double q);
Kalman kalman(bool ca, double q, const Params *params, Position measurement);
void predict(Kalman *filter, double interval);
Innovation innovation(const Kalman *filter, Position measurement);
double update(Kalman *filter, Innovation innovation);
Vector *smooth(const History *history, int count);
Pairs minimum_matching(const double *costs, int rows, int columns),
    optimal_assignment(const double *costs, const bool *usable, int rows, int columns);
IMM imm(const Params *params, Position measurement);
void imm_step(IMM *filter, double interval, const Position *measurement);
Vector imm_estimate(const IMM *filter);
double squared_distance(Position a, Position b), distance(Position a, Position b),
    ospa(const Position *a, int a_count, const Position *b, int b_count, double cutoff);
Continuity continuity(const int *labels, int count);
char *real(double value);
#endif
