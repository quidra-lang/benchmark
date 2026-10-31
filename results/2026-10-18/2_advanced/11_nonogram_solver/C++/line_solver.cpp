#include "nonogram.hpp"
#include <algorithm>

using Table = std::vector<std::vector<bool>>;
static Table fitTable(const std::string& cells, const Clue& clue) {
    int n = cells.size(), k = clue.size(); std::vector<int> empties(n + 1); for (int i = 0; i < n; ++i) empties[i + 1] = empties[i] + (cells[i] == Empty);
    Table table(n + 1,std::vector<bool>(k + 1)); table[0][0] = true;
    for (int end = 1; end <= n; ++end) for (int count = 0; count <= k; ++count) {
        bool fits = cells[end - 1] != Filled && table[end - 1][count];
        if (!fits && count) { int start = end - clue[count - 1]; if (start >= 0 && empties[end] == empties[start]) fits = start == 0 ? count == 1 : cells[start - 1] != Filled && table[start - 1][count - 1]; }
        table[end][count] = fits;
    } return table;
}
class Placements {
    const std::string& cells;
    const Clue& clue;
    int n, k;
    Table before, after;
public:
    Placements(const std::string& cells, const Clue& clue) : cells(cells), clue(clue), n(cells.size()), k(clue.size()), before(fitTable(cells,clue)), after(fitTable(std::string(cells.rbegin(),cells.rend()),Clue(clue.rbegin(),clue.rend()))) {}
    bool consistent() const { return before[n][k]; }
    std::vector<int> starts(int block) const {
        std::vector<int> result; for (int start = 0; start + clue[block] <= n; ++start) {
            int end = start + clue[block], rest = k - block - 1;
            if (cells.find(Empty,start) < static_cast<std::size_t>(end)) continue;
            bool left = start == 0 ? block == 0 : cells[start - 1] != Filled && before[start - 1][block];
            bool right = end == n ? rest == 0 : cells[end] != Filled && after[n - end - 1][rest]; if (left && right) result.push_back(start);
        } return result;
    }
    bool canBeEmpty(int index) const { if (cells[index] == Filled) return false; for (int blocks = 0; blocks <= k; ++blocks) if (before[index][blocks] && after[n - index - 1][k - blocks]) return true; return false; }
};
bool hasPlacement(const std::string& cells, const Clue& clue) { return Placements(cells,clue).consistent(); }
std::optional<std::string> solveLine(const std::string& cells, const Clue& clue, bool precise) {
    Placements placements(cells,clue); if (!placements.consistent()) return std::nullopt; int n = cells.size(); std::string solved = cells; std::vector<bool> covered(n);
    for (int block = 0; block < static_cast<int>(clue.size()); ++block) {
        std::vector<int> starts = placements.starts(block); int length = clue[block];
        if (precise) for (int start : starts) for (int i = start; i < start + length; ++i) covered[i] = true;
        else { for (int i = starts.back(); i < starts.front() + length; ++i) if (solved[i] == Unknown) solved[i] = Filled; for (int i = starts.front(); i < starts.back() + length; ++i) covered[i] = true; }
    }
    for (int i = 0; i < n; ++i) if (solved[i] == Unknown) {
        if (!covered[i]) solved[i] = Empty; else if (precise && !placements.canBeEmpty(i)) solved[i] = Filled;
    } return solved;
}
