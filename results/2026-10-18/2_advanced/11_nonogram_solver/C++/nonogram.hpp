#pragma once
#include <optional>
#include <string>
#include <utility>
#include <vector>

constexpr char Unknown = '?', Filled = '#', Empty = '.';
using Clue = std::vector<int>;
using Clues = std::vector<Clue>;
using Lines = std::vector<std::string>;
using Grid = Lines;
bool isClueLine(const std::string& text);
std::optional<Clue> parseClue(const std::string& text);
Clue runClue(const std::string& cells);
std::string clueText(const Clue& clue, char separator = ' ');
int span(const Clue& clue);
bool hasPlacement(const std::string& cells, const Clue& clue);
std::optional<std::string> solveLine(const std::string& cells, const Clue& clue, bool precise);
struct Step {
    bool row;
    int index, gain;
    bool contradiction;
    std::string label() const;
    std::string text() const;
};
struct Propagation { std::vector<Step> steps; std::optional<Step> conflict; std::string record() const; };
std::string label(bool row, int index);
std::string lineCells(const Grid& grid, bool row, int index);
int determined(const Grid& grid);
Propagation propagate(Grid& grid, const Clues& rows, const Clues& columns, bool precise, std::vector<bool> rowMarks, std::vector<bool> columnMarks);
std::pair<int, int> guessCell(const Grid& grid);
struct Guess { int number, depth, row, column; char value; int solves, known; std::string result; };
struct SearchResult { std::vector<Guess> guesses; std::vector<Grid> solutions; int backtracks = 0, maxDepth = 0, lineSolves = 0; };
SearchResult search(const Grid& grid, const Clues& rows, const Clues& columns);
char stateChar(char state);
std::string stateString(const std::string& cells);
Lines gridDisplay(const std::vector<std::pair<std::string, Grid>>& grids);
Lines answerSheet(const Clues& rows, const Clues& columns, const Grid& grid);
