#include "crossword.hpp"

Grid::Grid(Lines rows) : rows(std::move(rows)), width(static_cast<int>(this->rows.front().size())), height(static_cast<int>(this->rows.size())) { for (const std::string& row : this->rows) cells += row; }
int Grid::cell(int row, int column) const { return row * width + column; }
std::string Grid::location(int position) const { return text(position / width + 1, ',', position % width + 1); }
bool Grid::isOpen(int row, int column) const { return row >= 0 && column >= 0 && row < height && column < width && rows[row][column] != '#'; }
bool Grid::isGiven(int position) const { return cells[position] != '#' && cells[position] != '.'; }
Indices Grid::whites() const { Indices result; for (int i = 0; i < static_cast<int>(cells.size()); ++i) if (cells[i] != '#') result.push_back(i); return result; }
int Grid::asymmetricCell(const std::string& symmetry) const {
    for (int row = 0; row < height; ++row) for (int column = 0; column < width; ++column) { int otherRow = symmetry == "rot180" ? height - 1 - row : row, otherColumn = width - 1 - column; if (isOpen(row, column) != isOpen(otherRow, otherColumn)) return cell(row, column); }
    return -1;
}
int Grid::componentCount() const {
    std::vector<bool> seen(cells.size());
    int count = 0;
    for (int start : whites()) {
        if (seen[start]) continue;
        ++count; seen[start] = true;
        Indices stack{start};
        while (!stack.empty()) {
            int position = stack.back(); stack.pop_back(); int row = position / width, column = position % width;
            for (const std::pair<int, int>& point : std::vector<std::pair<int, int>>{{row - 1, column}, {row + 1, column}, {row, column - 1}, {row, column + 1}}) if (isOpen(point.first, point.second)) { int child = cell(point.first, point.second); if (!seen[child]) { seen[child] = true; stack.push_back(child); } }
        }
    }
    return count;
}
