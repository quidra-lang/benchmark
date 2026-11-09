#include "defense.h"

Grid read_grid(const char *path) {
    FILE *input = fopen(path, "r");
    Grid grid = {0};
    char row[64];
    fscanf(input, "%d %d\n", &grid.width, &grid.height);
    for (int y = 0; y < grid.height; y++) {
        fgets(row, sizeof row, input);
        for (int x = 0; x < grid.width; x++) {
            int cell = y * grid.width + x;
            grid.terrain[cell] = row[x];
            if (row[x] == 'E') grid.exit = cell;
            if (row[x] >= '1' && row[x] <= '9') {
                grid.spawns[row[x] - '1'] = cell;
                grid.spawn_count++;
            }
        }
    }
    fclose(input);
    return grid;
}

bool grid_inside(const Grid *grid, int x, int y) {
    return x >= 0 && x < grid->width && y >= 0 && y < grid->height;
}

bool grid_rock(const Grid *grid, int cell) { return grid->terrain[cell] == '#'; }
bool grid_water(const Grid *grid, int cell) { return grid->terrain[cell] == '~'; }
bool grid_buildable(const Grid *grid, int cell) { return grid->terrain[cell] == '.'; }

Point cell_center(const Grid *grid, int cell) {
    return (Point){100 * (cell % grid->width), 100 * (cell / grid->width)};
}
