#include "defense.h"
#include <string.h>

const char *target_mode_names[5] = {"FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST"};

Targets parse_targets(const char *text) {
    return strcmp(text, "ground") == 0 ? GROUND : strcmp(text, "air") == 0 ? AIR : BOTH;
}

void parse_tower_type(const char *line, TowerType *kind) {
    char targets[16];
    sscanf(line, "tower %12s %c %15s %d", kind->name, &kind->symbol, targets, &kind->level_count);
    kind->targets = parse_targets(targets);
}

void parse_level(const char *line, Level *level) {
    sscanf(line, "level %d %d %d %d %d %d %d %d %d %d", &level->cost, &level->range, &level->power, &level->interval, &level->shot_speed, &level->splash, &level->slow_rate, &level->slow_time, &level->burn_amount, &level->burn_time);
}

Tower make_tower(int number, TowerType *kind, int cell, int tick) {
    return (Tower){.number = number, .cell = cell, .level = 1, .ready = tick, .investment = kind->levels[0].cost, .built = tick, .mode = FIRST, .kind = kind};
}

const Level *tower_level(const Tower *tower) { return &tower->kind->levels[tower->level - 1]; }
bool can_aim(Targets targets, const Enemy *enemy) { return targets == BOTH || targets == enemy->kind->movement; }

bool in_range(const Tower *tower, const Grid *grid, Point point) {
    int reach = tower_level(tower)->range;
    return squared_distance(cell_center(grid, tower->cell), point) <= reach * reach;
}

int parse_target_mode(const char *text) {
    for (int i = 0; i < 5; i++) if (strcmp(text, target_mode_names[i]) == 0) return i;
    return -1;
}

int select_target(const Tower *tower, const Enemy *enemies, const int *living, int count, const Grid *grid, const DistanceField *field) {
    int best = -1, best_key = 0;
    for (int i = 0; i < count; i++) {
        int index = living[i];
        const Enemy *enemy = &enemies[index];
        if (!enemy->alive || !can_aim(tower->kind->targets, enemy) || !in_range(tower, grid, enemy_position(enemy, grid))) continue;
        int key;
        switch (tower->mode) {
            case FIRST: key = remaining_distance(enemy, grid, field); break;
            case LAST: key = -remaining_distance(enemy, grid, field); break;
            case STRONGEST: key = -enemy->hp; break;
            case WEAKEST: key = enemy->hp; break;
            default: key = squared_distance(cell_center(grid, tower->cell), enemy_position(enemy, grid)); break;
        }
        if (best < 0 || key < best_key) { best = index; best_key = key; }
    }
    return best;
}
