#include "dungeon.h"

const int direction_x[8] = {0,1,1,1,0,-1,-1,-1};
const int direction_y[8] = {-1,-1,0,1,1,1,0,-1};
const char *direction_names[8] = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"};

bool passable(const Level *level, int x, int y) {
    if (x < 0 || y < 0 || x >= level->width || y >= level->height) return false;
    return strchr(".#+<>", level->terrain[y * level->width + x]) != NULL;
}

bool can_move(const Level *level, int x, int y, int dx, int dy) {
    if (!passable(level, x + dx, y + dy)) return false;
    return !dx || !dy || (level->terrain[y * level->width + x] != '+' && level->terrain[(y + dy) * level->width + x + dx] != '+');
}

static bool line_visible(const Level *level, int x, int y, int target_x, int target_y) {
    int dx = abs(target_x - x), dy = abs(target_y - y);
    int sx = target_x > x ? 1 : -1, sy = target_y > y ? 1 : -1;
    int error = dx - dy;
    while (x != target_x || y != target_y) {
        int twice = 2 * error;
        if (twice > -dy) { error -= dy; x += sx; }
        if (twice < dx) { error += dx; y += sy; }
        if ((x != target_x || y != target_y) && !passable(level, x, y)) return false;
    }
    return true;
}

bool *field_of_view(const Level *level, int px, int py, int radius) {
    bool *visible = allocate((size_t)level->width * level->height * sizeof(bool));
    for (int y = 0; y < level->height; ++y) {
        for (int x = 0; x < level->width; ++x) {
            int dx = x - px, dy = y - py;
            if (dx * dx + dy * dy <= radius * radius) visible[y * level->width + x] = line_visible(level, px, py, x, y);
        }
    }
    return visible;
}

int *distances(const Level *level, int px, int py) {
    int size = level->width * level->height;
    int *result = allocate((size_t)size * sizeof(int));
    for (int i = 0; i < size; ++i) result[i] = -1;
    int queue[2400], head = 0, tail = 0;
    int start = py * level->width + px;
    result[start] = 0;
    queue[tail++] = start;
    while (head < tail) {
        int cell = queue[head++], x = cell % level->width, y = cell / level->width;
        for (int direction = 0; direction < 8; ++direction) {
            int dx = direction_x[direction], dy = direction_y[direction];
            if (!can_move(level, x, y, dx, dy)) continue;
            int next = (y + dy) * level->width + x + dx;
            if (result[next] >= 0) continue;
            result[next] = result[cell] + 1;
            queue[tail++] = next;
        }
    }
    return result;
}
