#include "nonogram.hpp"
#include <algorithm>
#include <sstream>

char stateChar(char state) { return state; }
std::string stateString(const std::string& cells) { std::string result; for (char state : cells) result += stateChar(state); return result; }
Lines gridDisplay(const std::vector<std::pair<std::string, Grid>>& grids) {
    if (grids.empty()) return {}; std::string heading = "grid"; for (const auto& grid : grids) heading += " " + grid.first; Lines lines{heading};
    for (int row = 0; row < static_cast<int>(grids[0].second.size()); ++row) { std::string text; for (const auto& grid : grids) { if (!text.empty()) text += " | "; text += stateString(grid.second[row]); } lines.push_back(text); } return lines;
}
Lines answerSheet(const Clues& rows, const Clues& columns, const Grid& grid) {
    std::vector<Lines> tokens; int width = 0, depth = 0, margin = 0;
    for (const Clue& clue : columns) { std::istringstream input(clueText(clue)); std::string token; Lines list; while (input >> token) { width = std::max<int>(width,token.size()); list.push_back(token); } depth = std::max<int>(depth,list.size()); tokens.push_back(list); }
    ++width; for (const Clue& clue : rows) margin = std::max<int>(margin,clueText(clue).size()); Lines lines;
    for (int i = 0; i < depth; ++i) { std::string text(margin,' '); for (const Lines& column : tokens) { int index = i - depth + static_cast<int>(column.size()); std::string token = index < 0 ? "" : column[index]; text += std::string(width - token.size(),' ') + token; } while (!text.empty() && text.back() == ' ') text.pop_back(); lines.push_back(text); }
    for (int r = 0; r < static_cast<int>(rows.size()); ++r) { std::string clue = clueText(rows[r]), text = std::string(margin - clue.size(),' ') + clue; for (char state : grid[r]) text += std::string(width - 1,' ') + stateChar(state); lines.push_back(text); } return lines;
}
