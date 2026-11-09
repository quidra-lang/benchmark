#ifndef ARCHIVE_HPP
#define ARCHIVE_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Byte = std::uint8_t;
using Bytes = std::vector<Byte>;
using Integer = std::int64_t;
using Lines = std::vector<std::string>;
struct DecodeError {
    std::string kind;
};
struct BitWriter {
    Bytes bytes;
    std::size_t count = 0;
    void write(std::uint32_t value, int width);
};
struct BitReader {
    const Bytes &bytes;
    std::size_t position = 0;
    bool zero_extend = false;
    std::uint32_t read(int width);
};
int bits(std::uint32_t value);
struct LzwStats {
    int codes = 0, clears = 0, longest = 0;
    std::array<int, 4> widths{};
};
Bytes lzw_encode(const Bytes &data, LzwStats &stats);
void lzw_decode(const Bytes &payload, std::uint32_t size, Bytes &output);
struct Token {
    int literal = 0, distance = 0, length = 0;
    bool match() const;
};
std::vector<Token> tokenize(const Bytes &data, int offset_bits, int length_bits);
void output_match(Bytes &output, std::uint32_t size, int distance, int length);
struct Huffman {
    std::vector<int> lengths;
    int halvings = 0;
};
Huffman huffman_lengths(std::vector<int> frequencies, int maximum);
std::vector<int> canonical_codes(const std::vector<int> &lengths);
struct ArithStats {
    int bits = 0, contexts = 0, rescales = 0;
};
Bytes arith_encode(const Bytes &data, ArithStats &stats);
void arith_decode(const Bytes &payload, std::uint32_t size, Bytes &output);
#endif
