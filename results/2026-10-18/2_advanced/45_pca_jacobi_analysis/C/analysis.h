#ifndef ANALYSIS_H
#define ANALYSIS_H
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef struct {
    int n;
    double v[300];
} Vector;
typedef struct {
    int rows, cols;
    double v[300][24];
} Matrix;
typedef struct {
    char id[9];
    double values[12];
    bool missing[12];
} Sample;
typedef struct {
    char missing[16], scaling[16], components[16];
    double cumulative, t2, spe;
    int repetitions, cycles, top, scree, bw, bh, radius, dw, dh;
    int64_t seed;
} Params;
typedef struct {
    int p, n, ns;
    char names[12][13];
    Sample data[300], supplementary[50];
    Params params;
} Input;
Input read_input(void);
Vector vector(int n);
Matrix matrix(int rows, int cols);
Matrix identity(int n);
Vector column(const Matrix *matrix, int index);
double dot(Vector a, Vector b);
Vector multiply(const Matrix *matrix, Vector values);
Vector normalize(Vector values);
Vector orient(Vector values);
double difference(Vector a, Vector b);
void deflate(Matrix *matrix, double value, Vector values);
typedef struct {
    Matrix inverse;
    double determinant;
} Inverse;
Inverse inverse_determinant(const Matrix *matrix);
typedef struct {
    Vector values;
    Matrix vectors;
    int sweeps;
} Eigen;
typedef struct {
    double value;
    Vector vector;
    int agreement;
} Power;
Eigen jacobi(const Matrix *matrix);
void power_iteration(const Matrix *matrix, const Eigen *references, Power *out);
Vector means(const Matrix *rows);
Matrix covariance(const Matrix *rows, Vector means);
Matrix correlation(const Matrix *covariance, Vector deviations);
Vector standardize(const Sample *row, Vector means, Vector scales);
Vector scores(Vector row, const Matrix *vectors);
Vector residuals(Vector row, Vector scores, const Matrix *vectors, int count);
double hotelling(Vector scores, Vector eigenvalues, int count);
typedef struct {
    int height, width;
    char cells[40][80];
} Grid;
typedef struct {
    int row, column;
} Cell;
Grid grid(int height, int width);
void framed(FILE *out, const Grid *grid);
Cell biplot_cell(double x, double y, double xlimit, double ylimit, int width, int height);
Cell circle_cell(double x, double y, int radius);
Cell diagnostic_cell(double t2, double spe, double xlimit, double ylimit, int width, int height);
void shaft_cells(Grid *grid, Cell origin, Cell tip);
char shaft_character(Cell origin, Cell tip);
void scree_line(FILE *out, int length, int kaiser, int broken, int width);
const char *real(double value, int precision);
#endif
