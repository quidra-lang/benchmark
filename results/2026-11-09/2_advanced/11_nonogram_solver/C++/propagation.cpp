#include "nonogram.hpp"
#include <algorithm>

std::string label(bool row, int index) { return std::string(row ? "R" : "C") + std::to_string(index + 1); }
std::string Step::label() const { return ::label(row,index); }
std::string Step::text() const { return label() + (contradiction ? "!" : "+" + std::to_string(gain)); }
std::string Propagation::record() const { std::string result; for (const Step& step : steps) { if (!result.empty()) result += ' '; result += step.text(); } return result; }
std::string lineCells(const Grid& grid, bool row, int index) { if (row) return grid[index]; std::string result; for (const std::string& cells : grid) result += cells[index]; return result; }
int determined(const Grid& grid) { int count = 0; for (const std::string& row : grid) count += std::count_if(row.begin(),row.end(),[](char c) { return c != Unknown; }); return count; }
Propagation propagate(Grid& grid, const Clues& rows, const Clues& columns, bool precise, std::vector<bool> rowMarks, std::vector<bool> columnMarks) {
    Propagation result;
    while (true) {
        auto rowFound = std::find(rowMarks.begin(),rowMarks.end(),true); bool row = rowFound != rowMarks.end(); int index;
        if (row) { index = rowFound - rowMarks.begin(); rowMarks[index] = false; }
        else { auto found = std::find(columnMarks.begin(),columnMarks.end(),true); if (found == columnMarks.end()) return result; index = found - columnMarks.begin(); columnMarks[index] = false; }
        std::string cells = lineCells(grid,row,index); auto solved = solveLine(cells,row ? rows[index] : columns[index],precise);
        if (!solved) { Step step{row,index,0,true}; result.steps.push_back(step); result.conflict = step; return result; }
        int gain = 0; for (int i = 0; i < static_cast<int>(cells.size()); ++i) if (cells[i] == Unknown && (*solved)[i] != Unknown) {
            ++gain; if (row) { grid[index][i] = (*solved)[i]; columnMarks[i] = true; } else { grid[i][index] = (*solved)[i]; rowMarks[i] = true; }
        } result.steps.push_back({row,index,gain,false});
    }
}
