#include "nonogram.hpp"
#include <algorithm>
#include <functional>
#include <limits>

std::pair<int, int> guessCell(const Grid& grid) {
    int h = grid.size(), w = grid[0].size(); std::vector<int> rows(h), columns(w);
    for (int r = 0; r < h; ++r) for (int c = 0; c < w; ++c) if (grid[r][c] == Unknown) { ++rows[r]; ++columns[c]; }
    std::pair<int, int> best{-1,-1}; int score = std::numeric_limits<int>::max();
    for (int r = 0; r < h; ++r) for (int c = 0; c < w; ++c) if (grid[r][c] == Unknown && rows[r] + columns[c] < score) { best = {r,c}; score = rows[r] + columns[c]; } return best;
}
SearchResult search(const Grid& grid, const Clues& rows, const Clues& columns) {
    SearchResult result; int h = rows.size(), w = columns.size();
    std::function<bool(const Grid&, int)> visit = [&](const Grid& parent, int depth) {
        auto cell = guessCell(parent);
        for (char value : {Filled,Empty}) {
            Grid child = parent; child[cell.first][cell.second] = value; std::vector<bool> rowMarks(h), columnMarks(w); rowMarks[cell.first] = true; columnMarks[cell.second] = true;
            Propagation propagation = propagate(child,rows,columns,true,rowMarks,columnMarks); int known = determined(child); std::string outcome = "open";
            if (propagation.conflict) { outcome = "contradiction at=" + propagation.conflict->label(); ++result.backtracks; }
            else if (known == h * w) { result.solutions.push_back(child); outcome = "solution" + std::to_string(result.solutions.size()); }
            int solves = propagation.steps.size(); result.lineSolves += solves; result.maxDepth = std::max(result.maxDepth,depth);
            result.guesses.push_back({static_cast<int>(result.guesses.size()) + 1,depth,cell.first,cell.second,value,solves,known,outcome});
            if (outcome == "open") { if (visit(child,depth + 1)) return true; } else if (result.solutions.size() == 2) return true;
        } return false;
    }; visit(grid,1); return result;
}
