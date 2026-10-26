#include "crossword.hpp"

bool startsRun(const Grid& grid, int row, int column, bool across) { return grid.isOpen(row, column) && !grid.isOpen(row - (across ? 0 : 1), column - (across ? 1 : 0)); }
int runLength(const Grid& grid, int row, int column, bool across) { int length = 0; while (grid.isOpen(row + (across ? 0 : length), column + (across ? length : 0))) ++length; return length; }
std::pair<int, std::string> findShortRun(const Grid& grid) {
    for (int row = 0; row < grid.height; ++row) for (int column = 0; column < grid.width; ++column) for (bool across : {true, false}) if (startsRun(grid, row, column, across) && runLength(grid, row, column, across) == 2) return {grid.cell(row, column), across ? "across" : "down"};
    return {-1, ""};
}
Layout::Layout(Grid grid) : grid(std::move(grid)), numbers(this->grid.cells.size()), acrossSlot(this->grid.cells.size(), -1), downSlot(this->grid.cells.size(), -1) {
    int next = 0;
    for (int row = 0; row < this->grid.height; ++row) for (int column = 0; column < this->grid.width; ++column) for (bool across : {true, false}) {
        if (!startsRun(this->grid, row, column, across)) continue;
        int length = runLength(this->grid, row, column, across);
        if (length < 3) continue;
        int start = this->grid.cell(row, column);
        if (!numbers[start]) numbers[start] = ++next;
        Slot slot{static_cast<int>(slots.size()), numbers[start], across, {}, {}, text(numbers[start], across ? 'A' : 'D')};
        for (int i = 0; i < length; ++i) { int position = this->grid.cell(row + (across ? 0 : i), column + (across ? i : 0)); slot.cells.push_back(position); (across ? acrossSlot : downSlot)[position] = slot.index; }
        slots.push_back(std::move(slot));
    }
    for (Slot& slot : slots) { for (int position : slot.cells) { int crossing = (slot.across ? downSlot : acrossSlot)[position]; if (crossing >= 0) slot.crossings.push_back(crossing); } std::sort(slot.crossings.begin(), slot.crossings.end()); }
}
int Layout::ownerCount(int cell) const { return static_cast<int>(acrossSlot[cell] >= 0) + static_cast<int>(downSlot[cell] >= 0); }
int Layout::orphanCell() const { for (int cell : grid.whites()) if (!ownerCount(cell)) return cell; return -1; }
