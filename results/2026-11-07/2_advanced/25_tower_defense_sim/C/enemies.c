#include "defense.h"
#include <string.h>

EnemyType *find_enemy_type(EnemyType *types, int count, const char *name) {
    for (int i = 0; i < count; i++) if (strcmp(types[i].name, name) == 0) return &types[i];
    return NULL;
}

void parse_enemy_type(const char *line, EnemyType *types, int count, EnemyType *kind) {
    char movement[16], split[16];
    *kind = (EnemyType){0};
    sscanf(line, "enemy %12s %c %15s %d %d %d %d %d %d %15s %d", kind->name, &kind->symbol, movement, &kind->hp, &kind->armor, &kind->speed, &kind->bounty, &kind->lives, &kind->regen, split, &kind->split_count);
    kind->movement = parse_targets(movement);
    if (strcmp(split, "-") != 0) kind->split_into = find_enemy_type(types, count, split);
}

void parse_group(const char *line, EnemyType *types, int count, Group *group) {
    char name[13];
    sscanf(line, "group %12s %d %d %d %d %d", name, &group->spawn, &group->count, &group->delay, &group->interval, &group->multiplier);
    group->kind = find_enemy_type(types, count, name);
}

Enemy make_enemy(int number, EnemyType *kind, int multiplier) {
    int hp = kind->hp * multiplier / 100;
    return (Enemy){.number = number, .multiplier = multiplier, .max_hp = hp, .hp = hp, .kind = kind, .alive = true};
}

Enemy split_enemy(const Enemy *parent, int number) {
    Enemy child = make_enemy(number, parent->kind->split_into, parent->multiplier);
    child.cell = parent->cell;
    child.next_cell = parent->next_cell;
    child.progress = parent->progress;
    child.point = parent->point;
    return child;
}

Point enemy_position(const Enemy *enemy, const Grid *grid) {
    if (enemy->kind->movement == AIR) return enemy->point;
    Point current = cell_center(grid, enemy->cell), following = cell_center(grid, enemy->next_cell);
    return (Point){current.x + (following.x - current.x) * enemy->progress / 100, current.y + (following.y - current.y) * enemy->progress / 100};
}

int occupied_cell(const Enemy *enemy, const Grid *grid) {
    if (enemy->kind->movement == GROUND) return enemy->progress < 50 ? enemy->cell : enemy->next_cell;
    return (enemy->point.y + 50) / 100 * grid->width + (enemy->point.x + 50) / 100;
}

int remaining_distance(const Enemy *enemy, const Grid *grid, const DistanceField *field) {
    if (enemy->kind->movement == AIR) return integer_sqrt(squared_distance(enemy->point, cell_center(grid, grid->exit)));
    return 100 * field->distance[enemy->next_cell] + 100 - enemy->progress;
}

int slowed_speed(const Enemy *enemy) {
    return enemy->slow.remaining > 0 ? enemy->kind->speed * (100 - enemy->slow.strength) / 100 : enemy->kind->speed;
}
