#include "defense.h"

static const Point directions[4] = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}};

int neighbor(const Grid *grid, int cell, int direction) {
    int x = cell % grid->width + directions[direction].x;
    int y = cell / grid->width + directions[direction].y;
    return grid_inside(grid, x, y) ? y * grid->width + x : -1;
}

void build_distance_field(const Grid *grid, const bool blocked[MAX_CELLS], DistanceField *field) {
    int queue[MAX_CELLS], first = 0, last = 0;
    for (int i = 0; i < grid->width * grid->height; i++) field->distance[i] = -1;
    field->distance[grid->exit] = 0;
    queue[last++] = grid->exit;
    while (first < last) {
        int current = queue[first++];
        for (int direction = 0; direction < 4; direction++) {
            int following = neighbor(grid, current, direction);
            if (following >= 0 && !grid_rock(grid, following) && !blocked[following] && field->distance[following] < 0) {
                field->distance[following] = field->distance[current] + 1;
                queue[last++] = following;
            }
        }
    }
}

int field_direction(const Grid *grid, const DistanceField *field, int cell) {
    int best = -1, best_distance = 0;
    for (int direction = 0; direction < 4; direction++) {
        int following = neighbor(grid, cell, direction);
        if (following < 0 || field->distance[following] < 0) continue;
        if (best < 0 || field->distance[following] < best_distance) {
            best = direction;
            best_distance = field->distance[following];
        }
    }
    return best;
}

int next_cell(const Grid *grid, const DistanceField *field, int cell) {
    return neighbor(grid, cell, field_direction(grid, field, cell));
}

int field_path(const Grid *grid, const DistanceField *field, int start, int cells[MAX_CELLS]) {
    int count = 0;
    for (int cell = start;; cell = next_cell(grid, field, cell)) {
        cells[count++] = cell;
        if (cell == grid->exit) return count;
    }
}
