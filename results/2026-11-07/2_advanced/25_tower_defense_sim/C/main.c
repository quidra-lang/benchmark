#include "defense.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct { int reward, group_count; Group groups[20]; } Wave;
typedef struct {
    int gold, lives, interest_rate, interest_cap, sell_rate;
    int start, interval, early, snapshot_count, snapshots[20];
} Params;
typedef struct { int tick; char command[16], arguments[3][16]; } Action;
typedef struct {
    int start, end, spawned, peak, kills, leaks, lives_lost, bounty;
    int reward, interest, gold, lives, released[20], damage[MAX_TOWERS];
    bool cleared;
} WaveRecord;
typedef struct {
    Grid grid;
    DistanceField field;
    TowerType tower_types[10];
    EnemyType enemy_types[20];
    Wave waves[50];
    WaveRecord records[50];
    Tower towers[MAX_TOWERS];
    Action actions[2000];
    Params params;
    int tower_type_count, enemy_type_count, wave_count, tower_count, action_count;
    int record_count, active, next_start, tick, gold, lives, outcome;
    Enemy *enemies;
    int enemy_count, *living, living_count, alive_count;
    size_t enemy_capacity, living_capacity;
    Projectile *projectiles;
    int projectile_count, projectile_number;
    size_t projectile_capacity;
    int kills[MAX_CELLS], income[5], spent, done, refused;
    FILE *events, *snapshots;
} Game;

static int minimum(int first, int second) { return first < second ? first : second; }

static void *grow(void *storage, size_t *capacity, size_t needed, size_t width) {
    if (needed <= *capacity) return storage;
    size_t next = *capacity ? *capacity * 2 : 64;
    while (next < needed) next *= 2;
    void *resized = realloc(storage, next * width);
    if (!resized) abort();
    *capacity = next;
    return resized;
}

static FILE *input_file(const char *name) {
    char path[64];
    snprintf(path, sizeof path, "input/%s", name);
    FILE *input = fopen(path, "r");
    if (!input) abort();
    return input;
}

static void read_inputs(Game *game) {
    game->grid = read_grid("input/map.txt");
    char line[512];
    FILE *input = input_file("towers.txt");
    while (fgets(line, sizeof line, input)) {
        TowerType *kind = &game->tower_types[game->tower_type_count++];
        parse_tower_type(line, kind);
        for (int level = 0; level < kind->level_count; level++) {
            fgets(line, sizeof line, input);
            parse_level(line, &kind->levels[level]);
        }
    }
    fclose(input);
    input = input_file("waves.txt");
    while (fgets(line, sizeof line, input)) {
        if (strncmp(line, "enemy ", 6) == 0) {
            int count = game->enemy_type_count;
            parse_enemy_type(line, game->enemy_types, count, &game->enemy_types[count]);
            game->enemy_type_count++;
        } else if (strncmp(line, "wave ", 5) == 0) {
            sscanf(line, "wave %d", &game->waves[game->wave_count++].reward);
        } else {
            Wave *wave = &game->waves[game->wave_count - 1];
            parse_group(line, game->enemy_types, game->enemy_type_count, &wave->groups[wave->group_count++]);
        }
    }
    fclose(input);
    input = input_file("actions.txt");
    while (fgets(line, sizeof line, input)) {
        Action *action = &game->actions[game->action_count++];
        sscanf(line, "%d %15s %15s %15s %15s", &action->tick, action->command, action->arguments[0], action->arguments[1], action->arguments[2]);
    }
    fclose(input);
    input = input_file("params.txt");
    Params *params = &game->params;
    fscanf(input, "gold %d\nlives %d\ninterest %d %d\nsell %d\nschedule %d %d\nearly %d\n", &params->gold, &params->lives, &params->interest_rate, &params->interest_cap, &params->sell_rate, &params->start, &params->interval, &params->early);
    fgets(line, sizeof line, input);
    strtok(line, " \n");
    for (char *token = strtok(NULL, " \n"); token; token = strtok(NULL, " \n")) params->snapshots[params->snapshot_count++] = atoi(token);
    fclose(input);
}

static void event(Game *game, const char *pattern, ...) {
    fprintf(game->events, "%d ", game->tick);
    va_list arguments;
    va_start(arguments, pattern);
    vfprintf(game->events, pattern, arguments);
    va_end(arguments);
    fputc('\n', game->events);
}

static Tower *tower_at(Game *game, int cell) {
    for (int i = 0; i < game->tower_count; i++) {
        Tower *tower = &game->towers[i];
        if (tower->sold == 0 && tower->cell == cell) return tower;
    }
    return NULL;
}

static Tower *standing_tower(Game *game, int number) {
    if (number < 1 || number > game->tower_count || game->towers[number - 1].sold) return NULL;
    return &game->towers[number - 1];
}

static void blocked_cells(Game *game, bool blocked[MAX_CELLS]) {
    memset(blocked, 0, MAX_CELLS * sizeof *blocked);
    for (int i = 0; i < game->tower_count; i++) if (!game->towers[i].sold) blocked[game->towers[i].cell] = true;
}

static void update_field(Game *game) {
    DistanceField previous = game->field;
    bool blocked[MAX_CELLS];
    blocked_cells(game, blocked);
    build_distance_field(&game->grid, blocked, &game->field);
    for (int i = 0; i < game->grid.spawn_count; i++) {
        int spawn = game->grid.spawns[i];
        if (previous.distance[spawn] != game->field.distance[spawn]) event(game, "REPATH %d %d %d", i + 1, previous.distance[spawn], game->field.distance[spawn]);
    }
}

static const char *build_refusal(Game *game, const char *name, int x, int y, TowerType **kind) {
    *kind = NULL;
    for (int i = 0; i < game->tower_type_count; i++) if (strcmp(game->tower_types[i].name, name) == 0) *kind = &game->tower_types[i];
    if (!*kind) return "type";
    if (!grid_inside(&game->grid, x, y)) return "bounds";
    int cell = y * game->grid.width + x;
    if (!grid_buildable(&game->grid, cell)) return "terrain";
    if (tower_at(game, cell)) return "tower";
    if (game->gold < (*kind)->levels[0].cost) return "gold";
    for (int i = 0; i < game->living_count; i++) {
        const Enemy *enemy = &game->enemies[game->living[i]];
        if (enemy->alive && enemy->kind->movement == GROUND && (enemy->cell == cell || enemy->next_cell == cell)) return "enemy";
    }
    bool blocked[MAX_CELLS];
    blocked_cells(game, blocked);
    blocked[cell] = true;
    DistanceField trial;
    build_distance_field(&game->grid, blocked, &trial);
    for (int i = 0; i < game->grid.spawn_count; i++) if (trial.distance[game->grid.spawns[i]] < 0) return "blocked";
    for (int i = 0; i < game->living_count; i++) {
        const Enemy *enemy = &game->enemies[game->living[i]];
        if (enemy->alive && enemy->kind->movement == GROUND && trial.distance[enemy->next_cell] < 0) return "blocked";
    }
    return NULL;
}

static bool perform_action(Game *game, const Action *action) {
    const char *command = action->command;
    if (strcmp(command, "BUILD") == 0) {
        const char *name = action->arguments[0];
        int x = atoi(action->arguments[1]), y = atoi(action->arguments[2]);
        TowerType *kind;
        const char *reason = build_refusal(game, name, x, y, &kind);
        if (reason) { event(game, "BUILD_REFUSED %s %s %s %s", name, action->arguments[1], action->arguments[2], reason); return false; }
        int cost = kind->levels[0].cost;
        int number = ++game->tower_count;
        game->towers[number - 1] = make_tower(number, kind, y * game->grid.width + x, game->tick);
        game->gold -= cost;
        game->spent += cost;
        event(game, "BUILD T%d %s %d %d cost %d gold %d", number, name, x, y, cost, game->gold);
        update_field(game);
        return true;
    }
    if (strcmp(command, "CALL") == 0) {
        if (game->active >= 0) { event(game, "CALL_REFUSED active"); return false; }
        int bonus = (game->next_start - game->tick) * game->params.early;
        game->gold += bonus;
        game->income[3] += bonus;
        game->next_start = game->tick;
        event(game, "CALL %d bonus %d gold %d", game->record_count + 1, bonus, game->gold);
        return true;
    }
    const char *number_text = action->arguments[0];
    Tower *tower = standing_tower(game, atoi(number_text));
    const char *reason = NULL;
    if (!tower) reason = "notower";
    else if (strcmp(command, "UPGRADE") == 0) {
        if (tower->level == tower->kind->level_count) reason = "maxlevel";
        else if (game->gold < tower->kind->levels[tower->level].cost) reason = "gold";
        else {
            int cost = tower->kind->levels[tower->level++].cost;
            game->gold -= cost;
            game->spent += cost;
            tower->investment += cost;
            event(game, "UPGRADE T%d level %d cost %d gold %d", tower->number, tower->level, cost, game->gold);
            return true;
        }
    } else if (strcmp(command, "SELL") == 0) {
        int rate = tower->built == game->tick ? 100 : game->params.sell_rate;
        int refund = tower->investment * rate / 100;
        tower->sold = game->tick;
        game->gold += refund;
        game->income[4] += refund;
        event(game, "SELL T%d refund %d gold %d", tower->number, refund, game->gold);
        update_field(game);
        return true;
    } else {
        int mode = parse_target_mode(action->arguments[1]);
        if (mode < 0) reason = "mode";
        else {
            tower->mode = (TargetMode)mode;
            event(game, "TARGET T%d %s", tower->number, target_mode_names[mode]);
            return true;
        }
    }
    event(game, "%s_REFUSED T%s %s", command, number_text, reason);
    return false;
}

static void add_enemy(Game *game, Enemy enemy) {
    game->enemies = grow(game->enemies, &game->enemy_capacity, (size_t)game->enemy_count + 1, sizeof *game->enemies);
    game->living = grow(game->living, &game->living_capacity, (size_t)game->living_count + 1, sizeof *game->living);
    game->living[game->living_count++] = game->enemy_count;
    game->enemies[game->enemy_count++] = enemy;
    game->alive_count++;
    game->records[game->active].spawned++;
    enemy.kind->spawned++;
}

static void compact_living(Game *game) {
    int count = 0;
    for (int i = 0; i < game->living_count; i++) if (game->enemies[game->living[i]].alive) game->living[count++] = game->living[i];
    game->living_count = count;
}

static void spawn_enemies(Game *game) {
    if (game->active < 0 && game->tick == game->next_start) {
        game->active = game->record_count++;
        game->records[game->active].start = game->tick;
        Wave *plan = &game->waves[game->active];
        int count = 0;
        for (int i = 0; i < plan->group_count; i++) count += plan->groups[i].count;
        event(game, "WAVE_START %d enemies %d", game->active + 1, count);
    }
    if (game->active < 0) return;
    WaveRecord *record = &game->records[game->active];
    Wave *plan = &game->waves[game->active];
    for (int i = 0; i < plan->group_count; i++) {
        Group *group = &plan->groups[i];
        int released = record->released[i];
        if (released == group->count || game->tick != record->start + group->delay + released * group->interval) continue;
        record->released[i]++;
        Enemy enemy = make_enemy(game->enemy_count + 1, group->kind, group->multiplier);
        int spawn = game->grid.spawns[group->spawn - 1];
        if (enemy.kind->movement == AIR) enemy.point = cell_center(&game->grid, spawn);
        else { enemy.cell = spawn; enemy.next_cell = next_cell(&game->grid, &game->field, spawn); }
        add_enemy(game, enemy);
        event(game, "SPAWN E%d %s %d hp %d", enemy.number, enemy.kind->name, group->spawn, enemy.hp);
    }
    if (game->alive_count > record->peak) record->peak = game->alive_count;
}

static void credit_damage(Game *game, Tower *tower, int enemy_index, int damage) {
    tower->damage += damage;
    game->enemies[enemy_index].kind->damage += damage;
    game->records[game->active].damage[tower->number - 1] += damage;
}

static void kill_enemy(Game *game, int index, Tower *tower) {
    Enemy parent = game->enemies[index];
    game->enemies[index].alive = false;
    game->alive_count--;
    game->kills[occupied_cell(&parent, &game->grid)]++;
    WaveRecord *record = &game->records[game->active];
    int bounty = parent.kind->bounty;
    tower->kills++;
    record->kills++;
    parent.kind->kills++;
    game->gold += bounty;
    record->bounty += bounty;
    game->income[0] += bounty;
    event(game, "KILL E%d %s T%d bounty %d gold %d", parent.number, parent.kind->name, tower->number, bounty, game->gold);
    for (int child_index = 0; child_index < parent.kind->split_count; child_index++) {
        Enemy child = split_enemy(&parent, game->enemy_count + 1);
        add_enemy(game, child);
        event(game, "SPAWN E%d %s E%d hp %d", child.number, child.kind->name, parent.number, child.hp);
    }
}

static void leak_enemy(Game *game, int index) {
    Enemy *enemy = &game->enemies[index];
    enemy->alive = false;
    game->alive_count--;
    int lost = minimum(game->lives, enemy->kind->lives);
    game->lives -= lost;
    WaveRecord *record = &game->records[game->active];
    record->leaks++;
    record->lives_lost += lost;
    enemy->kind->leaks++;
    event(game, "LEAK E%d %s lives %d", enemy->number, enemy->kind->name, game->lives);
    if (game->lives == 0) {
        event(game, "DEFEAT");
        record->end = game->tick;
        record->gold = game->gold;
        record->lives = game->lives;
        game->active = -1;
        game->outcome = 2;
    }
}

static void move_enemy(Game *game, int index) {
    Enemy *enemy = &game->enemies[index];
    if (enemy->burn.remaining > 0) {
        Tower *source = enemy->burn.source;
        int damage = minimum(enemy->hp, enemy->burn.strength);
        enemy->hp -= damage;
        credit_damage(game, source, index, damage);
        advance_effect(&enemy->burn);
        if (enemy->hp == 0) { kill_enemy(game, index, source); return; }
    }
    enemy->hp = minimum(enemy->hp + enemy->kind->regen, enemy->max_hp);
    int speed = slowed_speed(enemy);
    if (enemy->slow.remaining > 0) advance_effect(&enemy->slow);
    bool arrived = false;
    if (enemy->kind->movement == AIR) {
        enemy->point = advance_point(enemy->point, cell_center(&game->grid, game->grid.exit), speed, &arrived);
    } else {
        if (grid_water(&game->grid, occupied_cell(enemy, &game->grid))) speed /= 2;
        while (speed > 0) {
            int rest = 100 - enemy->progress;
            if (speed < rest) { enemy->progress += speed; speed = 0; }
            else {
                speed -= rest;
                enemy->cell = enemy->next_cell;
                enemy->progress = 0;
                if (enemy->cell == game->grid.exit) { arrived = true; break; }
                enemy->next_cell = next_cell(&game->grid, &game->field, enemy->cell);
            }
        }
    }
    if (arrived) leak_enemy(game, index);
}

static void move_enemies(Game *game) {
    int before_count = game->living_count;
    for (int i = 0; i < before_count; i++) {
        int index = game->living[i];
        if (game->enemies[index].alive) move_enemy(game, index);
        if (game->outcome) break;
    }
    compact_living(game);
}

static void fire_towers(Game *game) {
    for (int i = 0; i < game->tower_count; i++) {
        Tower *tower = &game->towers[i];
        if (tower->sold || game->tick < tower->ready) continue;
        int target = select_target(tower, game->enemies, game->living, game->living_count, &game->grid, &game->field);
        if (target < 0) continue;
        const Level *performance = tower_level(tower);
        Projectile shot = {.number = ++game->projectile_number, .target = target, .tower = tower, .targets = tower->kind->targets, .performance = *performance, .position = cell_center(&game->grid, tower->cell), .aim = enemy_position(&game->enemies[target], &game->grid)};
        game->projectiles = grow(game->projectiles, &game->projectile_capacity, (size_t)game->projectile_count + 1, sizeof *game->projectiles);
        game->projectiles[game->projectile_count++] = shot;
        tower->shots++;
        tower->ready = game->tick + performance->interval;
        event(game, "SHOT T%d E%d", tower->number, game->enemies[target].number);
    }
}

static void impact(Game *game, const Projectile *shot) {
    int *victims = malloc(((size_t)game->living_count + 1) * sizeof *victims);
    if (!victims) abort();
    int count = 0;
    if (shot->performance.splash == 0) {
        if (game->enemies[shot->target].alive) victims[count++] = shot->target;
    } else {
        int reach = shot->performance.splash * shot->performance.splash;
        for (int i = 0; i < game->living_count; i++) {
            int index = game->living[i];
            const Enemy *enemy = &game->enemies[index];
            if (enemy->alive && can_aim(shot->targets, enemy) && squared_distance(enemy_position(enemy, &game->grid), shot->aim) <= reach) victims[count++] = index;
        }
    }
    if (count == 0) shot->tower->fizzles++;
    for (int i = 0; i < count; i++) {
        int index = victims[i];
        Enemy *enemy = &game->enemies[index];
        shot->tower->hits++;
        int damage = damage_dealt(enemy->hp, shot->performance.power, enemy->kind->armor);
        enemy->hp -= damage;
        credit_damage(game, shot->tower, index, damage);
        if (enemy->hp == 0) { kill_enemy(game, index, shot->tower); continue; }
        if (shot->performance.slow_rate > 0) receive_effect(&enemy->slow, shot->performance.slow_rate, shot->performance.slow_time, NULL);
        if (shot->performance.burn_amount > 0) receive_effect(&enemy->burn, shot->performance.burn_amount, shot->performance.burn_time, shot->tower);
    }
    free(victims);
}

static void move_projectiles(Game *game) {
    int remaining = 0;
    for (int i = 0; i < game->projectile_count; i++) {
        Projectile *shot = &game->projectiles[i];
        if (game->enemies[shot->target].alive) shot->aim = enemy_position(&game->enemies[shot->target], &game->grid);
        if (fly_projectile(shot)) impact(game, shot);
        else game->projectiles[remaining++] = *shot;
    }
    game->projectile_count = remaining;
    compact_living(game);
}

static void check_wave_end(Game *game) {
    if (game->active < 0 || game->alive_count > 0) return;
    WaveRecord *record = &game->records[game->active];
    Wave *plan = &game->waves[game->active];
    for (int i = 0; i < plan->group_count; i++) if (record->released[i] != plan->groups[i].count) return;
    record->reward = plan->reward;
    game->gold += record->reward;
    record->interest = minimum(game->params.interest_cap, game->gold * game->params.interest_rate / 100);
    game->gold += record->interest;
    game->income[1] += record->reward;
    game->income[2] += record->interest;
    record->cleared = true;
    record->end = game->tick;
    record->gold = game->gold;
    record->lives = game->lives;
    game->active = -1;
    event(game, "WAVE_END %d reward %d interest %d gold %d", game->record_count, record->reward, record->interest, game->gold);
    if (game->record_count == game->wave_count) { game->outcome = 1; event(game, "VICTORY"); }
    else game->next_start = game->tick + game->params.interval;
}

static char count_digit(int count) { return count == 0 ? '.' : count <= 9 ? (char)('0' + count) : '*'; }

static void make_picture(Game *game, int kind, char picture[MAX_CELLS]) {
    int size = game->grid.width * game->grid.height;
    if (kind == 0) {
        memcpy(picture, game->grid.terrain, (size_t)size);
        for (int i = 0; i < game->grid.spawn_count; i++) {
            int path[MAX_CELLS];
            int count = field_path(&game->grid, &game->field, game->grid.spawns[i], path);
            for (int j = 0; j < count; j++) {
                int cell = path[j];
                if (grid_buildable(&game->grid, cell) || grid_water(&game->grid, cell)) picture[cell] = '+';
            }
        }
        for (int i = 0; i < game->tower_count; i++) if (!game->towers[i].sold) picture[game->towers[i].cell] = game->towers[i].kind->symbol;
        int occupants[MAX_CELLS] = {0};
        for (int i = 0; i < game->living_count; i++) {
            const Enemy *enemy = &game->enemies[game->living[i]];
            if (!enemy->alive) continue;
            int cell = occupied_cell(enemy, &game->grid);
            occupants[cell]++;
            picture[cell] = occupants[cell] == 1 ? enemy->kind->symbol : '*';
        }
        return;
    }
    for (int cell = 0; cell < size; cell++) {
        Tower *tower = tower_at(game, cell);
        if (kind == 1) {
            if (grid_rock(&game->grid, cell) || cell == game->grid.exit) picture[cell] = game->grid.terrain[cell];
            else if (tower) picture[cell] = tower->kind->symbol;
            else if (game->field.distance[cell] < 0) picture[cell] = '?';
            else picture[cell] = "^>v<"[field_direction(&game->grid, &game->field, cell)];
        } else if (kind == 2) {
            if (grid_rock(&game->grid, cell)) picture[cell] = '#';
            else if (tower) picture[cell] = tower->kind->symbol;
            else {
                int count = 0;
                Point center = cell_center(&game->grid, cell);
                for (int i = 0; i < game->tower_count; i++) if (!game->towers[i].sold && in_range(&game->towers[i], &game->grid, center)) count++;
                picture[cell] = count_digit(count);
            }
        } else {
            picture[cell] = game->kills[cell] > 0 ? count_digit(game->kills[cell]) : grid_rock(&game->grid, cell) ? '#' : '.';
        }
    }
}

static void print_picture(Game *game, int kind) {
    char picture[MAX_CELLS];
    make_picture(game, kind, picture);
    fputs("  ", game->snapshots);
    for (int x = 0; x < game->grid.width; x++) fputc('0' + x % 10, game->snapshots);
    fputc('\n', game->snapshots);
    for (int y = 0; y < game->grid.height; y++) {
        fprintf(game->snapshots, "%d ", y % 10);
        fwrite(picture + y * game->grid.width, 1, (size_t)game->grid.width, game->snapshots);
        fputc('\n', game->snapshots);
    }
}

static void snapshot(Game *game, bool final) {
    fprintf(game->snapshots, "%s %d wave %d next ", final ? "FINAL" : "SNAPSHOT", game->tick, game->record_count);
    if (game->active < 0 && game->outcome == 0) fprintf(game->snapshots, "%d", game->next_start);
    else fputc('-', game->snapshots);
    fprintf(game->snapshots, " gold %d lives %d\n", game->gold, game->lives);
    print_picture(game, 0);
    for (int i = 0; i < game->grid.spawn_count; i++) fprintf(game->snapshots, "PATH %d length %d\n", i + 1, game->field.distance[game->grid.spawns[i]]);
    for (int i = 0; i < game->tower_count; i++) {
        const Tower *tower = &game->towers[i];
        if (!tower->sold) fprintf(game->snapshots, "T%d %s %d %d level %d mode %s ready %d\n", tower->number, tower->kind->name, tower->cell % game->grid.width, tower->cell / game->grid.width, tower->level, target_mode_names[tower->mode], tower->ready);
    }
    for (int i = 0; i < game->living_count; i++) {
        const Enemy *enemy = &game->enemies[game->living[i]];
        if (!enemy->alive) continue;
        Point position = enemy_position(enemy, &game->grid);
        fprintf(game->snapshots, "E%d %s %d %d hp %d/%d slow %d %d burn %d %d\n", enemy->number, enemy->kind->name, position.x, position.y, enemy->hp, enemy->max_hp, enemy->slow.strength, enemy->slow.remaining, enemy->burn.strength, enemy->burn.remaining);
    }
    for (int i = 0; i < game->projectile_count; i++) {
        const Projectile *shot = &game->projectiles[i];
        fprintf(game->snapshots, "P%d T%d E%d %d %d\n", shot->number, shot->tower->number, shot->target + 1, shot->position.x, shot->position.y);
    }
    if (final) {
        fputs("FLOW\n", game->snapshots);
        print_picture(game, 1);
        fputs("COVERAGE\n", game->snapshots);
        print_picture(game, 2);
        fputs("KILLS\n", game->snapshots);
        print_picture(game, 3);
    }
}

static void write_waves(Game *game) {
    FILE *output = fopen("output/waves.csv", "wb");
    fputs("wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives", output);
    for (int i = 0; i < game->tower_count; i++) fprintf(output, ",T%d", i + 1);
    fputc('\n', output);
    for (int i = 0; i < game->record_count; i++) {
        WaveRecord *record = &game->records[i];
        fprintf(output, "%d,%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d", i + 1, record->start, record->end, record->cleared ? "cleared" : "lost", record->spawned, record->peak, record->kills, record->leaks, record->lives_lost, record->bounty, record->reward, record->interest, record->gold, record->lives);
        for (int tower = 0; tower < game->tower_count; tower++) fprintf(output, ",%d", record->damage[tower]);
        fputc('\n', output);
    }
    fclose(output);
}

static void one_decimal(FILE *output, long long numerator, long long denominator) {
    if (denominator == 0) { fputc('-', output); return; }
    long long rounded = (20 * numerator + denominator) / (2 * denominator);
    fprintf(output, "%lld.%lld", rounded / 10, rounded % 10);
}

static void write_summary(Game *game) {
    FILE *output = fopen("output/summary.txt", "wb");
    int cleared = 0, perfect = 0, spawned = 0, killed = 0, leaked = 0, damage = 0;
    for (int i = 0; i < game->record_count; i++) {
        if (game->records[i].cleared) { cleared++; if (game->records[i].leaks == 0) perfect++; }
    }
    for (int i = 0; i < game->enemy_type_count; i++) {
        EnemyType *kind = &game->enemy_types[i];
        spawned += kind->spawned;
        killed += kind->kills;
        leaked += kind->leaks;
    }
    Tower *mvp = NULL;
    for (int i = 0; i < game->tower_count; i++) {
        damage += game->towers[i].damage;
        if (!mvp || game->towers[i].damage > mvp->damage) mvp = &game->towers[i];
    }
    fprintf(output, "outcome %s\nticks %d\nwaves %d/%d perfect %d\nlives %d/%d\ngold %d\n", game->outcome == 1 ? "victory" : "defeat", game->tick, cleared, game->wave_count, perfect, game->lives, game->params.lives, game->gold);
    fprintf(output, "enemies spawned %d killed %d leaked %d\n", spawned, killed, leaked);
    fprintf(output, "income bounty %d reward %d interest %d early %d refund %d\n", game->income[0], game->income[1], game->income[2], game->income[3], game->income[4]);
    fprintf(output, "spent %d\ndamage %d\n", game->spent, damage);
    fprintf(output, "actions total %d done %d refused %d unused %d\n", game->action_count, game->done, game->refused, game->action_count - game->done - game->refused);
    fprintf(output, "score %d\n", 10 * killed + 100 * game->lives + 50 * perfect + game->gold);
    if (mvp) fprintf(output, "mvp T%d damage %d\n", mvp->number, mvp->damage);
    else fputs("mvp -\n", output);
    for (int i = 0; i < game->enemy_type_count; i++) {
        EnemyType *kind = &game->enemy_types[i];
        fprintf(output, "ENEMY %s spawned %d killed %d leaked %d damage %d\n", kind->name, kind->spawned, kind->kills, kind->leaks, kind->damage);
    }
    for (int i = 0; i < game->tower_count; i++) {
        Tower *tower = &game->towers[i];
        fprintf(output, "TOWER T%d %s %d %d level %d mode %s ", tower->number, tower->kind->name, tower->cell % game->grid.width, tower->cell / game->grid.width, tower->level, target_mode_names[tower->mode]);
        if (tower->sold) fprintf(output, "sold %d", tower->sold);
        else fputs("active", output);
        fprintf(output, " shots %d hits %d fizzles %d kills %d damage %d per_shot ", tower->shots, tower->hits, tower->fizzles, tower->kills, tower->damage);
        one_decimal(output, tower->damage, tower->shots);
        fputs(" share ", output);
        one_decimal(output, 100LL * tower->damage, damage);
        fprintf(output, " invested %d\n", tower->investment);
    }
    fclose(output);
}

int main(void) {
    Game *game = calloc(1, sizeof *game);
    if (!game) abort();
    read_inputs(game);
    game->gold = game->params.gold;
    game->lives = game->params.lives;
    game->active = -1;
    game->next_start = game->params.start;
    bool blocked[MAX_CELLS] = {0};
    build_distance_field(&game->grid, blocked, &game->field);
    mkdir("output", 0777);
    game->events = fopen("output/events.txt", "wb");
    game->snapshots = fopen("output/snapshots.txt", "wb");
    if (!game->events || !game->snapshots) abort();
    int action_index = 0;
    while (!game->outcome) {
        game->tick++;
        while (action_index < game->action_count && game->actions[action_index].tick == game->tick) {
            if (perform_action(game, &game->actions[action_index++])) game->done++;
            else game->refused++;
        }
        spawn_enemies(game);
        move_enemies(game);
        if (game->outcome) break;
        fire_towers(game);
        move_projectiles(game);
        check_wave_end(game);
        for (int i = 0; i < game->params.snapshot_count; i++) if (game->params.snapshots[i] == game->tick) snapshot(game, false);
    }
    snapshot(game, true);
    write_waves(game);
    write_summary(game);
    fclose(game->events);
    fclose(game->snapshots);
    free(game->enemies);
    free(game->living);
    free(game->projectiles);
    free(game);
    return 0;
}
