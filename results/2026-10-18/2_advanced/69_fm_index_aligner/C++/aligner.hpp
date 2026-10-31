#ifndef ALIGNER_HPP
#define ALIGNER_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using I = long long;
using Lines = std::vector<std::string>;
struct Reference {
    std::string name, bases;
    int masked = 0;
};
struct Read {
    std::string name, bases, quality;
};
struct Input {
    std::vector<Reference> references;
    std::vector<Read> reads;
    std::map<std::string, std::vector<int>> parameters;
};
Input read_inputs();
std::string reverse_complement(const std::string &sequence);
struct Params {
    int mismatches, minimum_length, trim_quality, seed_length, seed_step, maximum_seed_hits,
        band_width, match, mismatch, gap_open, gap_extend, minimum_score, maximum_alternatives,
        occ_interval, sample_interval, direct_limit, coverage_window, coverage_mapq, variant_depth,
        variant_quality, variant_percent, homozygous_percent;
    explicit Params(const Input &input);
};
int symbol_number(char symbol);
std::vector<int> counting_sort(const std::vector<int> &positions, const std::vector<int> &keys,
                               int key_count);
struct SuffixArray {
    std::vector<int> order, classes;
};
SuffixArray suffix_array(const std::string &text);
std::vector<int> direct_sort(const std::string &text);
struct Check {
    int ordered = 0, lcp_sum = 0, maximum = -1, row = 1;
};
Check adjacent_check(const std::string &text, const std::vector<int> &suffixes);
struct Interval {
    int lower, upper;
    bool empty() const { return lower >= upper; }
};
struct Index {
    int size, interval, sample_count = 0;
    std::string bwt;
    std::array<int, 6> C{};
    std::vector<std::array<int, 6>> checkpoints;
    std::vector<int> samples;
    Index(const std::string &text, const std::vector<int> &suffixes, int occurrence_interval,
          int sample_interval = 0);
    int occurrence(char symbol, int position) const, lf(int row) const;
    Interval extend(Interval interval, char base) const,
        backward_search(const std::string &sequence) const;
    std::pair<int, int> locate(int row) const;
    std::string inverse() const;
};
std::vector<int> lower_bounds(const std::string &sequence, const Index &reverse);
struct Leaf {
    int lower, upper, mismatches;
};
struct Search {
    int nodes = 0, positions = 0;
    std::vector<Leaf> leaves;
};
Search backtrack(const std::string &sequence, int maximum, const Index &forward,
                 const Index &reverse);
struct Alignment {
    int reference = 0, position = 0, strand = 0, nm = 0;
    std::string operations, oriented, cigar, md;
    std::vector<std::pair<int, int>> pairs;
};
struct Result {
    Read read;
    std::string core, reason = "SHORT", method;
    std::vector<int> qualities;
    int length = 0, trimmed = 0, other_count = 0, score = 0, mapq = 0, x0 = 0, x1 = 0;
    bool mapped = false;
    Alignment primary;
    std::vector<Alignment> others;
    std::set<int> targets;
};
std::string ratio(I numerator, I denominator),
    sam_record(const Result &result, const std::vector<Reference> &references,
               int maximum_alternatives);
Lines sam_header(const std::vector<Reference> &references);
void save(const std::string &name, const Lines &lines);
template <class... T> void line(Lines &out, const T &...values) {
    std::ostringstream stream;
    (stream << ... << values);
    out.push_back(stream.str());
}
#endif
