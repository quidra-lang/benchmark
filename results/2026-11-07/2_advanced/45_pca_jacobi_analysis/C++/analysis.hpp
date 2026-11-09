#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Vector = std::vector<double>;
using Matrix = std::vector<Vector>;
using Lines = std::vector<std::string>;
struct Sample {
    std::string id;
    std::vector<std::optional<double>> values;
};
struct Params {
    std::string missing, scaling, components;
    double cumulative = 0, t2 = 0, spe = 0;
    int repetitions = 0, cycles = 0, top = 0, scree = 0, bw = 0, bh = 0, radius = 0, dw = 0, dh = 0;
    std::int64_t seed = 0;
};
struct Input {
    Lines names;
    std::vector<Sample> data, supplementary;
    Params params;
};
Input read_input();
Matrix identity(int size);
Vector column(const Matrix &matrix, int index);
double dot(const Vector &a, const Vector &b);
Vector multiply(const Matrix &matrix, const Vector &vector);
Vector normalize(Vector vector);
Vector orient(Vector vector);
double difference(const Vector &a, const Vector &b);
void deflate(Matrix &matrix, double value, const Vector &vector);
std::pair<Matrix, double> inverse_determinant(const Matrix &matrix);
struct Eigen {
    Vector values;
    Matrix vectors;
    int sweeps = 0;
};
struct Power {
    double value;
    Vector vector;
    int agreement = 0;
};
Eigen jacobi(const Matrix &matrix);
std::vector<Power> power_iteration(const Matrix &matrix, const Matrix &references);
Vector means(const Matrix &rows);
Matrix covariance(const Matrix &rows, const Vector &means);
Matrix correlation(const Matrix &covariance, const Vector &deviations);
Vector standardize(const Sample &row, const Vector &means, const Vector &scales);
Vector scores(const Vector &row, const Matrix &vectors);
Vector residuals(const Vector &row, const Vector &scores, const Matrix &vectors, int count);
double hotelling(const Vector &scores, const Vector &eigenvalues, int count);
using Grid = std::vector<std::string>;
Grid grid(int height, int width);
Lines framed(const Grid &grid);
using Cell = std::pair<int, int>;
Cell biplot_cell(double x, double y, double xlimit, double ylimit, int width, int height);
Cell circle_cell(double x, double y, int radius);
Cell diagnostic_cell(double t2, double spe, double xlimit, double ylimit, int width, int height);
std::vector<Cell> shaft_cells(Cell origin, Cell tip);
char shaft_character(Cell origin, Cell tip);
std::string scree_line(int length, int kaiser, int broken, int width);
