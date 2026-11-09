#include "dungeon.h"

typedef struct Region {
    int x, y, width, height, start, end;
    struct Region *first, *second;
} Region;

Monster *monster_at(Level *level, int x, int y) {
    for (int i = 0; i < level->monster_count; ++i) {
        Monster *monster = &level->monsters[i];
        if (monster->hp > 0 && monster->x == x && monster->y == y) return monster;
    }
    return NULL;
}

Item *item_at(Level *level, int x, int y) {
    for (int i = 0; i < level->item_count; ++i) {
        Item *item = level->items[i];
        if (item->ground && item->x == x && item->y == y) return item;
    }
    return NULL;
}

RoomCell draw_interior_cell(const Level *level, Minstd *rng, int room_number) {
    Room room = level->rooms[room_number];
    int x = room.x + 1 + rnd(rng, room.width - 2);
    int y = room.y + 1 + rnd(rng, room.height - 2);
    return (RoomCell){room_number, x, y};
}

RoomCell draw_room_cell(const Level *level, Minstd *rng) {
    int room = rnd(rng, level->room_count);
    return draw_interior_cell(level, rng, room);
}

static Region *region(int x, int y, int width, int height) {
    Region *result = allocate(sizeof(*result));
    result->x = x; result->y = y; result->width = width; result->height = height;
    return result;
}

static void split(Region *node, int depth, const Config *config, Minstd *rng, Region **leaves, int *count) {
    bool cv = node->width >= 2 * config->min_size, ch = node->height >= 2 * config->min_size;
    if (depth == config->max_split || (!cv && !ch)) {
        node->start = *count;
        leaves[(*count)++] = node;
        node->end = *count;
        return;
    }
    bool vertical = cv;
    if (cv && ch) {
        if (4 * node->width >= 5 * node->height) vertical = true;
        else if (4 * node->height >= 5 * node->width) vertical = false;
        else vertical = draw(rng) % 2 == 0;
    }
    if (vertical) {
        int cut = config->min_size + rnd(rng, node->width - 2 * config->min_size + 1);
        node->first = region(node->x, node->y, cut, node->height);
        node->second = region(node->x + cut, node->y, node->width - cut, node->height);
    } else {
        int cut = config->min_size + rnd(rng, node->height - 2 * config->min_size + 1);
        node->first = region(node->x, node->y, node->width, cut);
        node->second = region(node->x, node->y + cut, node->width, node->height - cut);
    }
    split(node->first, depth + 1, config, rng, leaves, count);
    split(node->second, depth + 1, config, rng, leaves, count);
    node->start = node->first->start;
    node->end = node->second->end;
}

static void make_room(Level *level, Region *leaf, const Config *config, Minstd *rng) {
    int max_width = config->room_max < leaf->width - 1 ? config->room_max : leaf->width - 1;
    int max_height = config->room_max < leaf->height - 1 ? config->room_max : leaf->height - 1;
    int width = config->room_min + rnd(rng, max_width - config->room_min + 1);
    int height = config->room_min + rnd(rng, max_height - config->room_min + 1);
    int x = leaf->x + rnd(rng, leaf->width - width);
    int y = leaf->y + rnd(rng, leaf->height - height);
    level->rooms[level->room_count++] = (Room){x, y, width, height};
    for (int row = y; row < y + height; ++row) {
        for (int column = x; column < x + width; ++column) {
            level->terrain[row * level->width + column] = row == y || row == y + height - 1 ? '-' : column == x || column == x + width - 1 ? '|' : '.';
        }
    }
}

static void dig_cell(Level *level, int x, int y) {
    char *cell = &level->terrain[y * level->width + x];
    if (*cell == ' ') *cell = '#';
    else if (*cell == '-' || *cell == '|') *cell = '+';
}

static void connect(Level *level, Region *node, Minstd *rng) {
    if (!node->first) return;
    connect(level, node->first, rng);
    connect(level, node->second, rng);
    int first = -1, second = -1, minimum = 0;
    for (int a = node->first->start; a < node->first->end; ++a) {
        Room ra = level->rooms[a];
        int ax = ra.x + ra.width / 2, ay = ra.y + ra.height / 2;
        for (int b = node->second->start; b < node->second->end; ++b) {
            Room rb = level->rooms[b];
            int distance = abs(ax - rb.x - rb.width / 2) + abs(ay - rb.y - rb.height / 2);
            if (first < 0 || distance < minimum) { first = a; second = b; minimum = distance; }
        }
    }
    Room a = level->rooms[first], b = level->rooms[second];
    int ax = a.x + a.width / 2, ay = a.y + a.height / 2;
    int bx = b.x + b.width / 2, by = b.y + b.height / 2;
    int sx = bx >= ax ? 1 : -1, sy = by >= ay ? 1 : -1;
    if (draw(rng) % 2 == 0) {
        for (int x = ax; ; x += sx) { dig_cell(level, x, ay); if (x == bx) break; }
        for (int y = ay; ; y += sy) { dig_cell(level, bx, y); if (y == by) break; }
    } else {
        for (int y = ay; ; y += sy) { dig_cell(level, ax, y); if (y == by) break; }
        for (int x = ax; ; x += sx) { dig_cell(level, x, by); if (x == bx) break; }
    }
}

Level generate_level(int depth, const Config *config, Minstd *rng) {
    Level result = {0};
    result.depth = depth; result.width = config->width; result.height = config->height;
    result.terrain = allocate((size_t)result.width * result.height);
    result.memory = allocate((size_t)result.width * result.height);
    memset(result.terrain, ' ', (size_t)result.width * result.height);
    memset(result.memory, ' ', (size_t)result.width * result.height);
    Region *root = region(0, 0, result.width, result.height), *leaves[64];
    int count = 0;
    split(root, 0, config, rng, leaves, &count);
    for (int i = 0; i < count; ++i) make_room(&result, leaves[i], config, rng);
    connect(&result, root, rng);
    RoomCell arrival = draw_room_cell(&result, rng);
    result.arrival_room = arrival.room; result.arrival_x = arrival.x; result.arrival_y = arrival.y;
    result.terrain[arrival.y * result.width + arrival.x] = '<';
    int other = rnd(rng, result.room_count - 1);
    if (other >= arrival.room) ++other;
    RoomCell target = draw_interior_cell(&result, rng, other);
    result.target_x = target.x; result.target_y = target.y;
    return result;
}
