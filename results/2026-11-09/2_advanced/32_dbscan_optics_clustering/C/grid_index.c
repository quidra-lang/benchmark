#include "clustering.h"
static int cell_compare(const void *a, const void *b) {
    const Cell *x = a, *y = b;
    if (x->gy != y->gy)
        return (x->gy > y->gy) - (x->gy < y->gy);
    return (x->gx > y->gx) - (x->gx < y->gx);
}
static const Cell *find_cell(const Grid *grid, int gx, int gy) {
    int first = 0, end = grid->cell_count;
    while (first < end) {
        int middle = first + (end - first) / 2;
        Cell cell = grid->cells[middle];
        if (cell.gy < gy || (cell.gy == gy && cell.gx < gx))
            first = middle + 1;
        else
            end = middle;
    }
    if (first < grid->cell_count && grid->cells[first].gx == gx && grid->cells[first].gy == gy)
        return grid->cells + first;
    return NULL;
}
Grid build_grid(const Point *points, const Distances *distances, int radius) {
    int n = distances->count;
    Grid grid = {.radius = radius, .count = n, .correct = true};
    grid.cells = calloc((size_t)n, sizeof *grid.cells);
    grid.neighbors = calloc((size_t)n, sizeof *grid.neighbors);
    grid.candidates = calloc((size_t)n, sizeof *grid.candidates);
    grid.occupancy = calloc((size_t)n + 1, sizeof *grid.occupancy);
    for (int i = 0; i < n; ++i) {
        int gx = points[i].x / radius, gy = points[i].y / radius, cell = 0;
        while (cell < grid.cell_count && (grid.cells[cell].gx != gx || grid.cells[cell].gy != gy))
            ++cell;
        if (cell == grid.cell_count) {
            grid.cells[cell].gx = gx;
            grid.cells[cell].gy = gy;
            ++grid.cell_count;
        }
        push(&grid.cells[cell].points, i);
    }
    qsort(grid.cells, (size_t)grid.cell_count, sizeof *grid.cells, cell_compare);
    for (int i = 0; i < grid.cell_count; ++i) {
        Cell cell = grid.cells[i];
        ++grid.occupancy[cell.points.count];
        if (cell.points.count > grid.busiest_count) {
            grid.busiest_count = cell.points.count;
            grid.busiest_x = cell.gx;
            grid.busiest_y = cell.gy;
        }
    }
    Integer neighbors = 0, brute = 0;
    for (int i = 0; i < n; ++i) {
        int gx = points[i].x / radius, gy = points[i].y / radius;
        for (int row = gy - 1; row <= gy + 1; ++row)
            for (int column = gx - 1; column <= gx + 1; ++column) {
                const Cell *cell = find_cell(&grid, column, row);
                if (!cell)
                    continue;
                for (int q = 0; q < cell->points.count; ++q) {
                    int j = cell->points.values[q];
                    ++grid.candidates[i];
                    if (at(distances, i, j) <= (Integer)radius * radius)
                        push(grid.neighbors + i, j);
                }
            }
        int brute_count = 0;
        for (int j = 0; j < n; ++j)
            if (at(distances, i, j) <= (Integer)radius * radius)
                ++brute_count;
        if (brute_count != grid.neighbors[i].count)
            grid.correct = false;
        brute += brute_count;
        neighbors += grid.neighbors[i].count;
        grid.total_candidates += grid.candidates[i];
    }
    grid.pairs = (neighbors - n) / 2;
    grid.brute_pairs = (brute - n) / 2;
    return grid;
}
