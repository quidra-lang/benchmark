#ifndef CODEC_HPP
#define CODEC_HPP
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using I = long long;
using Bytes = std::vector<int>;
using Pixel = std::array<I, 3>;
using Sequence = std::array<I, 64>;
using Matrix = std::array<std::array<I, 8>, 8>;
using Key = std::pair<int, int>;
using Lines = std::vector<std::string>;
struct Image {
    int width = 0, height = 0;
    std::vector<Pixel> pixels;
};
struct Plane {
    int width = 0, height = 0;
    std::vector<I> pixels;
};
struct Params {
    std::vector<int> qualities, truncate;
    int sampling = 0, restart = 0, target = 0, generations = 0;
    bool optimized = false;
};
struct Huffman {
    std::array<int, 16> counts{};
    Bytes symbols;
    std::array<int, 256> lengths{}, codes{};
    Huffman() = default;
    Huffman(std::array<int, 16> counts, Bytes symbols);
};
using Tables = std::map<Key, Huffman>;
using Quantization = std::map<int, Matrix>;
using Frequencies = std::map<Key, std::array<I, 256>>;
struct SourceTables {
    Matrix transform{};
    std::array<Matrix, 2> basic{};
    Tables huffman;
};
Image read_ppm(const std::string &path);
Params read_params();
SourceTables read_tables();
Bytes read_hex(const std::string &path);
void write_ppm(const std::string &name, const Image &image);
void write_hex(const std::string &name, const Bytes &bytes);
void save(const std::string &name, const Lines &lines);
I floor_div(I a, I b), clamp(I value);
Pixel to_ycbcr(Pixel pixel), to_rgb(Pixel pixel);
std::array<Plane, 3> split_planes(const Image &image),
    component_planes(const std::array<Plane, 3> &planes, const std::array<Key, 3> &factors, int mx,
                     int my),
    upsample(const std::array<Plane, 3> &planes, const std::array<Key, 3> &factors, int width,
             int height);
Image combine_rgb(const std::array<Plane, 3> &planes);
std::array<Key, 64> zigzag_order();
Matrix forward(const Matrix &block, const Matrix &transform),
    inverse_dct(const Matrix &coefficients, const Matrix &transform),
    quantize(const Matrix &values, const Matrix &table),
    dequantize(const Sequence &sequence, const Matrix &table, int keep = 64);
Sequence zigzag(const Matrix &values);
Quantization quantization_tables(const std::array<Matrix, 2> &basic, int quality);
int category(I value);
Key extra_bits(I value);
I amplitude(int bits, int size);
Huffman optimized_table(const std::array<I, 256> &frequencies);
struct DecodeError {
    std::string kind;
};
struct BitWriter {
    Bytes data;
    int buffer = 0, pending = 0, padding = 0, stuffed = 0;
    void write(int value, int width);
    void pad();
    void restart(int number);
};
struct BitReader {
    const Bytes &data;
    int position, buffer = 0, remaining = 0;
    BitReader(const Bytes &data, int position) : data(data), position(position) {}
    int bit(), read(int width);
    void discard();
};
int find_resync(const Bytes &data, int position);
extern const std::array<Key, 4> table_keys;
extern const std::array<std::string, 4> table_names;
template <class... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
