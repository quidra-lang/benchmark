#include "crossword.h"

bool is_open(const Grid *grid, int row, int column) {
    return row >= 0 && row < grid->height && column >= 0 && column < grid->width && grid->cells[row * grid->width + column] != '#';
}

int asymmetric_cell(const Grid *grid, const char *symmetry) {
    for (int row = 0; row < grid->height; ++row) {
        for (int column = 0; column < grid->width; ++column) {
            int other_row = !strcmp(symmetry, "rot180") ? grid->height - row - 1 : row;
            int other_column = grid->width - column - 1;
            if (is_open(grid, row, column) != is_open(grid, other_row, other_column)) return row * grid->width + column;
        }
    }
    return -1;
}

int component_count(const Grid *grid) {
    bool seen[225] = {false};
    const int dr[] = {-1,1,0,0}, dc[] = {0,0,-1,1};
    int count = 0;
    for (int start = 0; start < grid->width * grid->height; ++start) {
        if (grid->cells[start] == '#' || seen[start]) continue;
        ++count;
        int stack[225], size = 0;
        stack[size++] = start;
        seen[start] = true;
        while (size) {
            int cell = stack[--size], row = cell / grid->width, column = cell % grid->width;
            for (int i = 0; i < 4; ++i) {
                int nr = row + dr[i], nc = column + dc[i];
                if (!is_open(grid, nr, nc)) continue;
                int next = nr * grid->width + nc;
                if (!seen[next]) { seen[next] = true; stack[size++] = next; }
            }
        }
    }
    return count;
}
