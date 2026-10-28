#ifndef TYPESETTING_HPP
#define TYPESETTING_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <functional>
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
using Integer = std::int64_t;
using Lines = std::vector<std::string>;
Lines read_lines(const std::string &path);
Lines split(const std::string &text, char delimiter);
Lines words(const std::string &text);
std::string join(const Lines &values, const std::string &delimiter);
std::string number(Integer value);
std::string lower(std::string value);
std::string upper(std::string value);
std::string trim(std::string value);
std::string rtrim(std::string value);
bool letter(char c);
struct Warning {
    int line;
    std::string message;
};
struct SourceLine {
    int line;
    std::string text;
};
enum class Kind {
    paragraph,
    item,
    enumeration,
    quote,
    term,
    title,
    author,
    h1,
    h2,
    table,
    verbatim,
    toc,
    lot,
    index,
    bibliography
};
struct Inline {
    std::string kind, text;
    int id = -1;
};
struct Block {
    Kind kind;
    int line, width, indent;
    std::string align, text, term, columns, caption, label, number;
    bool page_break = false;
    int body_number = 0;
    std::vector<SourceLine> body, inner;
    std::vector<Inline> tokens;
    std::vector<Lines> cells;
};
struct Bib {
    int line;
    std::string key, author, year, title, base, label;
    bool cited = false;
};
struct Document {
    std::vector<Block> blocks;
    std::vector<Bib> bibliography;
    std::vector<Warning> warnings;
    Lines additions;
    int width = 60, height = 40;
    std::array<std::string, 3> header{}, footer{};
};
using Params = std::map<std::string, Integer>;
Document parse_document(const Lines &lines);
bool body_kind(Kind kind);
using Dictionary = std::map<std::string, std::vector<int>>;
struct SplitPoint {
    int position;
    bool hyphen;
};
void register_word(Dictionary &dictionary, const std::string &word);
std::vector<SplitPoint> split_points(const Dictionary &dictionary, const std::string &word,
                                     const Params &params);
struct Measure {
    int length, slack, gaps;
    bool mid, last, previous_mid;
};
using MeasureLine = std::function<Measure(int, int)>;
struct Breaking {
    std::vector<int> ends;
    Integer cost = 0;
};
int line_class(const Measure &line);
Integer line_cost(const Measure &line, int previous_class, const Params &params);
Breaking break_lines(int count, const MeasureLine &measure, const Params &params, bool greedy);
struct Piece {
    int word, first, last;
    std::string text;
};
std::string render_line(const std::vector<Piece> &pieces, const Measure &line, const std::string &align);
Lines render_table(const Block &block);
std::string running_head(std::array<std::string, 3> fields, const std::map<std::string, std::string> &values,
                         int width, int serial);
struct LayoutLine {
    std::string text;
    std::vector<int> footnotes, indices;
    int first_block = -1, toc_target = -1, index_entry = -1, dynamic_width = 0;
};
enum class LayoutType { heading, solid, flow };
struct LayoutBlock {
    std::vector<LayoutLine> lines;
    LayoutType type;
    bool list = false, page_break = false;
};
struct Page {
    std::vector<LayoutLine> content;
    std::vector<int> footnotes;
    int height = 0;
    bool forced = false, blank = false;
    std::string display;
    int body_number = 0;
};
std::vector<Page> build_pages(const std::vector<LayoutBlock> &blocks, const std::vector<Lines> &footnotes,
                              const Params &params, int height);
Lines render_pages(const std::vector<Page> &pages, const std::vector<Lines> &footnotes,
                   const Document &document, const std::vector<int> &block_pages, int front_matter);
#endif
