#ifndef QR_HPP
#define QR_HPP
#include <algorithm>
#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Words = std::vector<int>;
using Lines = std::vector<std::string>;
template <class... T> std::string text(const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
template <class... T> void line(Lines &out, const T &...values) { out.push_back(text(values...)); }
extern const std::string alphanumeric;
std::string binary(int value, int width), from_codewords(const Words &words),
    hexadecimal(const Words &words);
Words to_codewords(const std::string &bits);
struct BitWriter {
    std::string bits;
    void write(int value, int width);
};
struct BitReader {
    const std::string &bits;
    int position = 0;
    int remaining() const;
    int read(int width);
};
struct Correction {
    Words syndromes, corrected, positions;
    bool success = true;
};
class ReedSolomon {
    std::array<int, 255> exp{};
    std::array<int, 256> log{};
    int polynomial(const Words &coefficients, int argument) const;

  public:
    ReedSolomon();
    int multiply(int a, int b) const, divide(int a, int b) const;
    Words generator(int degree) const, parity(const Words &data, int degree) const,
        syndromes(const Words &words, int degree) const;
    Correction correct(const Words &received, int degree) const;
};
struct Point {
    int x, y;
};
using Positions = std::vector<Point>;
struct Matrix {
    int size = 0;
    std::array<std::array<int, 57>, 57> cells{};
};
enum Area { Data, Function, Format, Version };
int format_information(int level, int mask), version_information(int version);
std::array<Positions, 2> format_positions(int size), version_positions(int size);
void write_value(Matrix &symbol, const Positions &positions, int value);
int read_value(const Matrix &symbol, const Positions &positions);
struct Geometry {
    Matrix symbol, areas;
    Positions order;
    std::array<std::array<int, 57>, 57> indices{};
    int function_modules() const;
};
Geometry function_matrix(int version, const Words &alignments);
Positions reading_order(const Matrix &areas);
struct Penalty {
    int n1 = 0, n2 = 0, n3 = 0, n4 = 0;
    int total() const { return n1 + n2 + n3 + n4; }
};
bool mask_condition(int mask, int x, int y);
Matrix apply_mask(Matrix symbol, const Positions &positions, int mask);
Penalty penalties(const Matrix &symbol);
Lines symbol_lines(const Matrix &symbol);
std::string pbm_text(const Matrix &symbol, int quiet, int scale);
#endif
