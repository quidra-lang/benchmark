#pragma once
#include <algorithm>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
using Indices = std::vector<int>;
template<class... Parts> std::string text(const Parts&... parts) { std::ostringstream stream; (stream << ... << parts); return stream.str(); }
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
template<class T> std::string join(const std::vector<T>& values, const std::string& separator = " ") {
    std::ostringstream stream;
    for (std::size_t i = 0; i < values.size(); ++i) { if (i) stream << separator; stream << values[i]; }
    return stream.str();
}
struct Grid {
    Lines rows;
    std::string cells;
    int width, height;
    explicit Grid(Lines rows);
    int cell(int row, int column) const;
    std::string location(int cell) const;
    bool isOpen(int row, int column) const;
    bool isGiven(int cell) const;
    Indices whites() const;
    int asymmetricCell(const std::string& symmetry) const;
    int componentCount() const;
};
struct Slot { int index, number; bool across; Indices cells, crossings; std::string label; int length() const { return static_cast<int>(cells.size()); } };
struct Layout {
    Grid grid;
    Indices numbers, acrossSlot, downSlot;
    std::vector<Slot> slots;
    explicit Layout(Grid grid);
    int ownerCount(int cell) const;
    int orphanCell() const;
};
bool startsRun(const Grid& grid, int row, int column, bool across);
int runLength(const Grid& grid, int row, int column, bool across);
std::pair<int, std::string> findShortRun(const Grid& grid);
bool validWord(const std::string& value);
bool validInteger(const std::string& value, int low, int high);
std::string wordLineError(const std::string& line);
std::string clueLineError(const std::string& line);
bool matches(const std::string& word, const std::string& pattern);
struct WordIndex {
    std::map<std::string, int> scores;
    Lines ranked;
    std::map<int, Lines> byLength;
    std::map<std::tuple<int, int, char>, Lines> byLetter;
    explicit WordIndex(std::map<std::string, int> scores);
    Lines candidates(const std::string& pattern, int minimum, const std::set<std::string>& used) const;
};
struct GridState {
    std::string letters;
    Lines words;
    std::set<std::string> used;
    GridState(std::string letters, int count);
    std::string pattern(const Slot& slot) const;
    Indices assign(const Slot& slot, const std::string& word);
    void unassign(const Slot& slot, const Indices& filled);
};
class Attempt {
    enum class SearchResult { complete, fail, abort };
    Layout layout;
    const WordIndex& index;
    SearchResult search();
public:
    GridState state, best;
    int minimum, budget, nodes = 0, backtracks = 0, prunes = 0, deadEnds = 0, maxDepth = 0;
    Indices sequence, failures;
    Lines trace;
    std::string outcome;
    Attempt(const Layout& layout, const WordIndex& index, const GridState& initial, int minimum, int budget);
    void run();
    const GridState& finalState() const;
};
std::string decimal(Integer numerator, Integer denominator, int places);
Lines gridLines(const Grid& grid, const std::string& letters);
Lines numberLines(const Layout& layout);
std::string listLine(const Slot& slot, const std::string& clue, const std::string& entry, const std::string& score, bool theme);
