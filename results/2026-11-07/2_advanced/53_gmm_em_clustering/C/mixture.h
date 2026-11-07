#ifndef MIXTURE_H
#define MIXTURE_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdarg.h>
#include <limits.h>
#include <sys/stat.h>
typedef int64_t I;
typedef struct {
    double x, y;
} Vec;
typedef struct {
    double a, b, c;
} Cov;
typedef enum { FULL, TIED, DIAG, SPHERICAL } Type;
typedef struct {
    char id[9];
    Vec xy;
} Point;
typedef struct {
    double weight;
    Vec mean;
    Cov cov;
} Component;
typedef struct {
    int k;
    Component components[4];
    Type type;
} Model;
typedef struct {
    int ks[4], k_count, iterations, kmeans_max, folds, width, height, type_count;
    Type types[4];
    double epsilon, tolerance, uncertain, low_density, xmin, xmax, ymin, ymax, *gof;
    int gof_count;
} Params;
typedef struct {
    Point points[300];
    int count;
    Params params;
    Model initial[5];
} Input;
typedef struct {
    double responsibility[4], scores[4], log_density;
} Record;
typedef struct {
    Record records[300];
    double loglik;
} Expectation;
typedef struct {
    Model model;
    Expectation e;
    double trace[41];
    int settled, largest, violations[40], violation_count;
} Fit;
typedef struct {
    double leading, trailing;
    Vec direction;
    double angle, major, minor, area, correlation;
} Eigen;
typedef struct {
    Vec centers[4];
    int assignment[300], sizes[4], iterations;
    double inertia;
} Kmeans;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
void *allocate(size_t count, size_t size);
void release_all(void);
char *format(const char *pattern, ...);
void load(Input *input);
const char *type_name(Type type);
double determinant(Cov cov);
double mahalanobis(Vec point, Vec mean, Cov cov);
double weighted_log(Vec point, Component component);
Eigen eigen(Cov cov);
double bhattacharyya(Component a, Component b);
Model adjust(Model initial, Type type);
void expectation(const Point *points, int count, Model model, Expectation *result);
void run_em(const Point *points, int count, Model initial, Type type, const Params *params, Fit *result);
double distance2(Vec a, Vec b);
double distance(Vec a, Vec b);
Kmeans run_kmeans(const Point *points, int count, Model initial, int maximum);
I rounded(double value, int digits);
char *real(double value, int digits);
void line(Lines *lines, const char *pattern, ...);
void frame(Lines *lines, char **grid, int height, int width);
void save(const char *name, Lines lines);
#endif
