#include "spatial.h"
Grid grid_new(int world, int side) {
    Grid out = {world, side, world / side, NULL};
    out.cells = calloc((size_t)out.dimension * (size_t)out.dimension, sizeof *out.cells);
    return out;
}
void grid_insert(Grid *grid, Point point) {
    points_insert(&grid->cells[(point.y / grid->side) * grid->dimension + point.x / grid->side], point);
}
void grid_delete(Grid *grid, Point point) {
    points_remove(&grid->cells[(point.y / grid->side) * grid->dimension + point.x / grid->side], point.id);
}
