#include "nonogram.hpp"
#include <algorithm>
#include <numeric>
#include <sstream>

bool isClueLine(const std::string& text) { return !text.empty() && std::all_of(text.begin(),text.end(),[](char c) { return c == ' ' || (c >= '0' && c <= '9'); }); }
std::optional<Clue> parseClue(const std::string& text) {
    if (text == "0") return Clue{}; if (text.empty() || text.front() == ' ' || text.back() == ' ') return std::nullopt;
    std::istringstream input(text); std::string token; Clue clue;
    while (std::getline(input,token,' ')) { if (token.empty() || token.size() > 2 || token.front() == '0' || !std::all_of(token.begin(),token.end(),[](char c) { return c >= '0' && c <= '9'; })) return std::nullopt; clue.push_back(std::stoi(token)); } return clue;
}
Clue runClue(const std::string& cells) { Clue clue; int run = 0; for (char cell : cells) { if (cell == Filled) ++run; else if (run) { clue.push_back(run); run = 0; } } if (run) clue.push_back(run); return clue; }
std::string clueText(const Clue& clue, char separator) { if (clue.empty()) return "0"; std::string result; for (int block : clue) { if (!result.empty()) result += separator; result += std::to_string(block); } return result; }
int span(const Clue& clue) { return std::accumulate(clue.begin(),clue.end(),0) + static_cast<int>(clue.size()) - 1; }
