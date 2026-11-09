#include "crossword.h"

bool starts_run(const Grid *grid, int row, int column, bool across) {
    return is_open(grid, row, column) && !is_open(grid, row - !across, column - across);
}

int run_length(const Grid *grid, int row, int column, bool across) {
    int length = 0;
    while (is_open(grid, row + length * !across, column + length * across)) ++length;
    return length;
}

int short_run(const Grid *grid, bool *across) {
    for (int row = 0; row < grid->height; ++row) {
        for (int column = 0; column < grid->width; ++column) {
            for (int direction = 0; direction < 2; ++direction) {
                bool horizontal = direction == 0;
                if (starts_run(grid, row, column, horizontal) && run_length(grid, row, column, horizontal) == 2) {
                    *across = horizontal;
                    return row * grid->width + column;
                }
            }
        }
    }
    return -1;
}

Layout extract_slots(Grid grid) {
    Layout result = {0};
    result.grid = grid;
    for (int i = 0; i < 225; ++i) { result.across[i] = -1; result.down[i] = -1; }
    int numbered = 0;
    for (int row = 0; row < grid.height; ++row) {
        for (int column = 0; column < grid.width; ++column) {
            for (int direction = 0; direction < 2; ++direction) {
                bool across = direction == 0;
                if (!starts_run(&grid, row, column, across)) continue;
                int length = run_length(&grid, row, column, across);
                if (length < 3) continue;
                int start = row * grid.width + column;
                if (!result.numbers[start]) result.numbers[start] = ++numbered;
                Slot *slot = &result.slots[result.count];
                slot->number = result.numbers[start];
                slot->length = length;
                slot->across = across;
                slot->label = format("%d%c", slot->number, across ? 'A' : 'D');
                int *owners = across ? result.across : result.down;
                for (int i = 0; i < length; ++i) {
                    slot->cells[i] = (row + i * !across) * grid.width + column + i * across;
                    owners[slot->cells[i]] = result.count;
                }
                ++result.count;
            }
        }
    }
    for (int s = 0; s < result.count; ++s) {
        Slot *slot = &result.slots[s];
        bool crossed[150] = {false};
        const int *other = slot->across ? result.down : result.across;
        for (int i = 0; i < slot->length; ++i) if (other[slot->cells[i]] >= 0) crossed[other[slot->cells[i]]] = true;
        slot->crossings.values = allocate((size_t)result.count * sizeof(int));
        for (int t = 0; t < result.count; ++t) if (crossed[t]) slot->crossings.values[slot->crossings.count++] = t;
    }
    return result;
}

int owner_count(const Layout *layout, int cell) { return (layout->across[cell] >= 0) + (layout->down[cell] >= 0); }
