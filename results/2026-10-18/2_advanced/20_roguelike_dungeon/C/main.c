#include "dungeon.h"

typedef struct Allocation { struct Allocation *next; max_align_t alignment; } Allocation;
static Allocation *allocations;

static void release_all(void) {
    while (allocations) { Allocation *next = allocations->next; free(allocations); allocations = next; }
}

void *allocate(size_t bytes) {
    static bool registered;
    if (!registered) { atexit(release_all); registered = true; }
    Allocation *block = calloc(1, sizeof(*block) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = allocations;
    allocations = block;
    return block + 1;
}

static char *formatted(const char *pattern, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    if (length < 0) exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    return result;
}

char *format(const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *result = formatted(pattern, arguments);
    va_end(arguments);
    return result;
}

void text_add(Text *text, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *part = formatted(pattern, arguments);
    va_end(arguments);
    size_t length = strlen(part);
    if (text->size + length + 1 > text->capacity) {
        size_t capacity = text->capacity ? 2 * text->capacity : 64;
        while (capacity < text->size + length + 1) capacity *= 2;
        char *data = allocate(capacity);
        if (text->size) memcpy(data, text->data, text->size);
        text->data = data;
        text->capacity = capacity;
    }
    memcpy(text->data + text->size, part, length + 1);
    text->size += length;
}

void add_line(Lines *lines, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *line = formatted(pattern, arguments);
    va_end(arguments);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? 2 * lines->capacity : 32;
        char **items = allocate((size_t)capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
        lines->capacity = capacity;
    }
    lines->items[lines->count++] = line;
}

static Lines read_lines(const char *name) {
    FILE *file = fopen(format("input/%s", name), "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines lines = {0};
    Text line = {0};
    int character;
    while ((character = fgetc(file)) != EOF) {
        if (character == '\n') {
            add_line(&lines, "%s", line.data ? line.data : "");
            line.size = 0;
            if (line.data) line.data[0] = '\0';
        } else text_add(&line, "%c", character);
    }
    if (ferror(file)) exit(EXIT_FAILURE);
    fclose(file);
    return lines;
}

static char **tokens(char *line, int *count) {
    char **parts = allocate((strlen(line) + 1) * sizeof(*parts));
    *count = 0;
    for (char *part = strtok(line, " "); part; part = strtok(NULL, " ")) parts[(*count)++] = part;
    return parts;
}

static Config read_config(void) {
    Lines source = read_lines("config.txt");
    char **row[16];
    int counts[16];
    for (int i = 0; i < 16; ++i) row[i] = tokens(source.items[i], &counts[i]);
    Config config = {0};
    config.generation_seed = strtoll(row[0][1], NULL, 10); config.game_seed = strtoll(row[0][2], NULL, 10);
    config.width = atoi(row[1][1]); config.height = atoi(row[1][2]);
    config.min_size = atoi(row[2][1]); config.max_split = atoi(row[2][2]);
    config.room_min = atoi(row[3][1]); config.room_max = atoi(row[3][2]); config.levels = atoi(row[4][1]);
    config.monster_base = atoi(row[5][1]); config.monster_step = atoi(row[5][2]);
    config.item_base = atoi(row[6][1]); config.item_step = atoi(row[6][2]);
    config.sleep_chance = atoi(row[7][1]); config.wake_chance = atoi(row[7][2]); config.radius = atoi(row[8][1]);
    config.max_hp = atoi(row[9][1]); config.regen = atoi(row[9][2]); config.hitdie = parse_dice(row[10][1]);
    config.food_start = atoi(row[11][1]); config.food_max = atoi(row[11][2]);
    config.food_hungry = atoi(row[11][3]); config.food_weak = atoi(row[11][4]); config.pack_limit = atoi(row[12][1]);
    config.start = row[13] + 1; config.start_count = counts[13] - 1;
    config.xp_count = counts[14] - 1; config.xp = allocate((size_t)config.xp_count * sizeof(int));
    for (int i = 0; i < config.xp_count; ++i) config.xp[i] = atoi(row[14][i + 1]);
    config.checkpoint_count = counts[15] - 1; config.checkpoints = allocate((size_t)config.checkpoint_count * sizeof(int));
    for (int i = 0; i < config.checkpoint_count; ++i) config.checkpoints[i] = atoi(row[15][i + 1]);
    return config;
}

typedef struct { char *name, *argument; } Command;
typedef struct {
    int x, y, depth, hp, max_hp, level, xp, gold, satiation, poison;
    Item **pack, *weapon, *armor; int pack_count;
} Player;
typedef struct { int count, hits, criticals, damage; } AttackStats;
typedef struct {
    Config config; MonsterType monster_types[20]; int monster_type_count;
    ItemType item_types[30], amulet; int item_type_count;
    Command *commands; int command_count;
    Minstd generation_rng, rng;
    Level levels[9]; Player player; int turn;
    Lines messages, maps; bool *visible; int *distance;
    char *result, *cause;
    int succeeded, failed, unused, moves, poison_damage, starvation_damage, usage[6], kills[20];
    AttackStats player_attacks, monster_attacks;
} Game;

static Level *current_level(Game *game) { return &game->levels[game->player.depth - 1]; }

static void say(Game *game, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *message = formatted(pattern, arguments);
    va_end(arguments);
    add_line(&game->messages, "%04d %s", game->turn, message);
}

static const char *hunger(const Game *game) {
    int food = game->player.satiation;
    if (food > game->config.food_hungry) return "normal";
    if (food > game->config.food_weak) return "hungry";
    return food > 0 ? "weak" : "starving";
}

static int defense(const Player *player) { return 10 + (player->armor ? player->armor->kind->armor + player->armor->bonus : 0); }
static void die(Game *game, char *cause) { say(game, "You die."); game->result = "died"; game->cause = cause; }
static Item *new_item(ItemType *kind, int x, int y, bool ground) {
    Item *item = allocate(sizeof(*item));
    item->kind = kind; item->x = x; item->y = y; item->ground = ground;
    return item;
}

static void build_levels(Game *game) {
    Config *config = &game->config;
    for (int depth = 1; depth <= config->levels; ++depth) {
        Level *level = &game->levels[depth - 1];
        *level = generate_level(depth, config, &game->generation_rng);
        int item_count = config->item_base + config->item_step * (depth - 1);
        level->items = allocate((size_t)(item_count + 1) * sizeof(Item *));
        if (depth < config->levels) level->terrain[level->target_y * level->width + level->target_x] = '>';
        else level->items[level->item_count++] = new_item(&game->amulet, level->target_x, level->target_y, true);
        int candidate_ids[30], weights[30], candidates = 0;
        for (int i = 0; i < game->monster_type_count; ++i) {
            MonsterType *kind = &game->monster_types[i];
            if (kind->min_depth <= depth && depth <= kind->max_depth) { candidate_ids[candidates] = i; weights[candidates++] = kind->weight; }
        }
        int monster_count = config->monster_base + config->monster_step * (depth - 1);
        level->monsters = allocate((size_t)monster_count * sizeof(Monster));
        for (int number = 1; number <= monster_count; ++number) {
            int choice = select_weight(&game->generation_rng, weights, candidates);
            MonsterType *kind = &game->monster_types[candidate_ids[choice]];
            RoomCell cell;
            do { cell = draw_room_cell(level, &game->generation_rng); }
            while (cell.room == level->arrival_room || level->terrain[cell.y * level->width + cell.x] != '.' || monster_at(level, cell.x, cell.y));
            int hp = roll_dice(&game->generation_rng, kind->hp);
            bool asleep = draw(&game->generation_rng) % 100 < config->sleep_chance;
            level->monsters[level->monster_count++] = (Monster){number, kind, cell.x, cell.y, hp, hp, 0, asleep, false};
        }
        candidates = 0;
        for (int i = 0; i < game->item_type_count; ++i) {
            ItemType *kind = &game->item_types[i];
            if (kind->min_depth <= depth && depth <= kind->max_depth) { candidate_ids[candidates] = i; weights[candidates++] = kind->weight; }
        }
        for (int number = 0; number < item_count; ++number) {
            int choice = select_weight(&game->generation_rng, weights, candidates);
            ItemType *kind = &game->item_types[candidate_ids[choice]];
            RoomCell cell;
            do { cell = draw_room_cell(level, &game->generation_rng); }
            while (level->terrain[cell.y * level->width + cell.x] != '.' || item_at(level, cell.x, cell.y));
            Item *item = new_item(kind, cell.x, cell.y, true);
            if (kind->category == GOLD) item->amount = roll_dice(&game->generation_rng, kind->dice);
            level->items[level->item_count++] = item;
        }
        level->items_placed = level->item_count;
    }
}

static Game *read_game(void) {
    Game *game = allocate(sizeof(*game));
    game->config = read_config();
    game->generation_rng.state = game->config.generation_seed;
    game->rng.state = game->config.game_seed;
    game->amulet = (ItemType){.category = AMULET, .name = "amulet"};
    Lines source = read_lines("monsters.txt");
    for (int i = 0; i < source.count; ++i) { int count; game->monster_types[game->monster_type_count++] = parse_monster_type(tokens(source.items[i], &count)); }
    source = read_lines("items.txt");
    for (int i = 0; i < source.count; ++i) { int count; game->item_types[game->item_type_count++] = parse_item_type(tokens(source.items[i], &count)); }
    game->commands = allocate(9999 * sizeof(Command));
    source = read_lines("commands.txt");
    for (int i = 0; i < source.count; ++i) {
        int count;
        char **parts = tokens(source.items[i], &count);
        int repetitions = !strcmp(parts[0], "wait") ? (count == 2 ? atoi(parts[1]) : 1) : count == 3 ? atoi(parts[2]) : 1;
        char *argument = count > 1 && strcmp(parts[0], "wait") ? parts[1] : NULL;
        for (int j = 0; j < repetitions; ++j) game->commands[game->command_count++] = (Command){parts[0], argument};
    }
    build_levels(game);
    Player *player = &game->player;
    player->x = game->levels[0].arrival_x; player->y = game->levels[0].arrival_y; player->depth = 1;
    player->hp = player->max_hp = game->config.max_hp; player->level = 1; player->satiation = game->config.food_start;
    player->pack = allocate((size_t)game->config.pack_limit * sizeof(Item *));
    for (int i = 0; i < game->config.start_count; ++i) {
        ItemType *kind = NULL;
        for (int j = 0; j < game->item_type_count; ++j) if (!strcmp(game->config.start[i], game->item_types[j].name)) kind = &game->item_types[j];
        Item *item = new_item(kind, player->x, player->y, false);
        player->pack[player->pack_count++] = item;
        if (kind->category == WEAPON && !player->weapon) player->weapon = item;
        if (kind->category == ARMOR && !player->armor) player->armor = item;
    }
    game->turn = 1;
    return game;
}

static void update_view(Game *game) {
    Level *level = current_level(game);
    Player *player = &game->player;
    game->visible = field_of_view(level, player->x, player->y, game->config.radius);
    for (int y = 0; y < level->height; ++y) {
        for (int x = 0; x < level->width; ++x) if (game->visible[y * level->width + x]) {
            Item *item = item_at(level, x, y);
            level->memory[y * level->width + x] = item ? item_symbol(item) : level->terrain[y * level->width + x];
        }
    }
    for (int i = 0; i < level->monster_count; ++i) {
        Monster *monster = &level->monsters[i];
        if (monster->hp <= 0) continue;
        bool seen = game->visible[monster->y * level->width + monster->x];
        if (seen && !monster->was_visible) say(game, "You see the %s.", monster->kind->name);
        monster->was_visible = seen;
    }
}

static void gain_xp(Game *game, int amount) {
    Player *player = &game->player;
    player->xp += amount;
    while (player->level <= game->config.xp_count && player->xp >= game->config.xp[player->level - 1]) {
        ++player->level;
        int gained = roll_dice(&game->rng, game->config.hitdie);
        player->max_hp += gained;
        player->hp += gained;
        say(game, "Welcome to level %d.", player->level);
    }
}

static void record_attack(AttackStats *stats, Attack attack) {
    ++stats->count;
    if (attack.outcome != MISS) { ++stats->hits; stats->damage += attack.damage; }
    if (attack.outcome == CRITICAL) ++stats->criticals;
}

static void player_attack(Game *game, Monster *monster) {
    Player *player = &game->player;
    monster->asleep = false;
    int to_hit = player->level, bonus = 0;
    Dice dice = {1,2};
    if (player->weapon) {
        to_hit += player->weapon->kind->to_hit + player->weapon->bonus;
        bonus = player->weapon->bonus;
        dice = player->weapon->kind->dice;
    }
    if (player->satiation <= game->config.food_weak) to_hit -= 2;
    Attack attack = resolve_attack(&game->rng, to_hit, monster->kind->defense, dice, bonus);
    record_attack(&game->player_attacks, attack);
    if (attack.outcome == MISS) { say(game, "You miss the %s.", monster->kind->name); return; }
    say(game, "You hit the %s%s for %d.", monster->kind->name, attack.outcome == CRITICAL ? " hard" : "", attack.damage);
    monster->hp -= attack.damage;
    if (monster->hp <= 0) {
        say(game, "You kill the %s.", monster->kind->name);
        ++current_level(game)->kills;
        for (int i = 0; i < game->monster_type_count; ++i) if (&game->monster_types[i] == monster->kind) ++game->kills[i];
        gain_xp(game, monster->kind->xp);
    }
}

static void monster_attack(Game *game, Monster *monster) {
    Player *player = &game->player;
    MonsterType *kind = monster->kind;
    Attack attack = resolve_attack(&game->rng, kind->to_hit, defense(player), kind->damage, 0);
    record_attack(&game->monster_attacks, attack);
    if (attack.outcome == MISS) { say(game, "The %s misses you.", kind->name); return; }
    say(game, "The %s hits you%s for %d.", kind->name, attack.outcome == CRITICAL ? " hard" : "", attack.damage);
    player->hp -= attack.damage;
    if (player->hp <= 0) die(game, format("killed_by %s", kind->name));
    else if (kind->poisonous) { player->poison += 5; say(game, "You are poisoned."); }
}

static bool move_player(Game *game, int direction) {
    Level *level = current_level(game);
    Player *player = &game->player;
    int dx = direction_x[direction], dy = direction_y[direction], x = player->x + dx, y = player->y + dy;
    if (!passable(level, x, y)) { say(game, "You bump into a wall."); return false; }
    if (!can_move(level, player->x, player->y, dx, dy)) { say(game, "You cannot move diagonally through a door."); return false; }
    Monster *monster = monster_at(level, x, y);
    if (monster) { player_attack(game, monster); return true; }
    player->x = x; player->y = y;
    ++game->moves;
    Item *item = item_at(level, x, y);
    if (item) say(game, "You see %s here.", reference_name(item));
    else if (level->terrain[y * level->width + x] == '>') say(game, "There is a staircase down here.");
    return true;
}

static bool pickup(Game *game) {
    Level *level = current_level(game);
    Player *player = &game->player;
    Item *item = item_at(level, player->x, player->y);
    if (!item) { say(game, "There is nothing here."); return false; }
    enum ItemClass category = item->kind->category;
    if (category == GOLD) { player->gold += item->amount; say(game, "You pick up %s.", display_name(item)); }
    else if (category == AMULET) {
        say(game, "You pick up the amulet."); say(game, "You win!");
        game->result = "won"; game->cause = "amulet";
    } else if (player->pack_count == game->config.pack_limit) { say(game, "Your pack is full."); return false; }
    else {
        player->pack[player->pack_count++] = item;
        say(game, "You pick up the %s (%d).", display_name(item), player->pack_count);
    }
    item->ground = false;
    ++level->picked;
    ++game->usage[0];
    return true;
}

static bool use_item(Game *game, const char *command, int number) {
    Player *player = &game->player;
    Level *level = current_level(game);
    if (number > player->pack_count) { say(game, "You do not have that item."); return false; }
    Item *item = player->pack[number - 1];
    enum ItemClass required = !strcmp(command, "quaff") ? POTION : !strcmp(command, "read") ? SCROLL : !strcmp(command, "wield") ? WEAPON : !strcmp(command, "wear") ? ARMOR : FOOD;
    if (item->kind->category != required) { say(game, "You cannot %s that.", command); return false; }
    if (required == WEAPON) {
        if (player->weapon == item) { say(game, "You are already wielding that."); return false; }
        player->weapon = item;
        ++game->usage[4];
        say(game, "You are now wielding the %s.", display_name(item));
        return true;
    }
    if (required == ARMOR) {
        if (player->armor == item) { say(game, "You are already wearing that."); return false; }
        player->armor = item;
        ++game->usage[5];
        say(game, "You are now wearing the %s.", display_name(item));
        return true;
    }
    memmove(player->pack + number - 1, player->pack + number, (size_t)(player->pack_count - number) * sizeof(Item *));
    --player->pack_count;
    if (required == FOOD) {
        ++game->usage[3];
        player->satiation += item->kind->nutrition;
        if (player->satiation > game->config.food_max) player->satiation = game->config.food_max;
        say(game, "You eat the %s.", display_name(item));
        return true;
    }
    const char *effect = item->kind->effect;
    if (required == POTION) {
        ++game->usage[1];
        say(game, "You quaff the %s.", display_name(item));
        if (!strcmp(effect, "heal")) {
            player->hp += roll_dice(&game->rng, item->kind->dice);
            if (player->hp > player->max_hp) { ++player->max_hp; player->hp = player->max_hp; }
            player->poison = 0;
            say(game, "You feel better.");
        } else if (!strcmp(effect, "poison")) { player->poison += item->kind->poison_turns; say(game, "You feel very sick."); }
        else {
            say(game, "You feel more experienced.");
            if (player->level <= game->config.xp_count) gain_xp(game, game->config.xp[player->level - 1] - player->xp);
        }
    } else {
        ++game->usage[2];
        say(game, "You read the %s.", display_name(item));
        if (!strcmp(effect, "mapping")) {
            for (int i = 0; i < level->width * level->height; ++i) if (level->terrain[i] != ' ' && level->memory[i] == ' ') level->memory[i] = level->terrain[i];
            say(game, "A map forms in your mind.");
        } else if (!strcmp(effect, "teleport")) {
            RoomCell cell;
            do { cell = draw_room_cell(level, &game->rng); }
            while ((cell.x == player->x && cell.y == player->y) || monster_at(level, cell.x, cell.y));
            player->x = cell.x; player->y = cell.y;
            say(game, "You are teleported.");
        } else if (!strcmp(effect, "enchant_weapon")) {
            if (player->weapon) { say(game, "Your %s glows blue.", display_name(player->weapon)); ++player->weapon->bonus; }
            else say(game, "Your hands twitch.");
        } else {
            if (player->armor) { say(game, "Your %s glows silver.", display_name(player->armor)); ++player->armor->bonus; }
            else say(game, "Your skin tingles.");
        }
    }
    return true;
}

static bool execute(Game *game, Command command) {
    if (!strcmp(command.name, "move")) {
        for (int direction = 0; direction < 8; ++direction) if (!strcmp(command.argument, direction_names[direction])) return move_player(game, direction);
    }
    if (!strcmp(command.name, "wait")) return true;
    if (!strcmp(command.name, "pickup")) return pickup(game);
    if (!strcmp(command.name, "descend")) {
        Player *player = &game->player;
        Level *level = current_level(game);
        if (level->terrain[player->y * level->width + player->x] != '>') { say(game, "There are no stairs here."); return false; }
        ++player->depth;
        level = current_level(game);
        player->x = level->arrival_x; player->y = level->arrival_y;
        say(game, "You descend to depth %d.", player->depth);
        return true;
    }
    return use_item(game, command.name, atoi(command.argument));
}

static bool can_attack(Game *game, Monster *monster) {
    int dx = game->player.x - monster->x, dy = game->player.y - monster->y;
    if (abs(dx) > 1 || abs(dy) > 1 || (!dx && !dy)) return false;
    return can_move(current_level(game), monster->x, monster->y, dx, dy);
}

static void wander(Game *game, Monster *monster) {
    int direction = (int)(draw(&game->rng) % 8);
    int dx = direction_x[direction], dy = direction_y[direction];
    Level *level = current_level(game);
    if (!can_move(level, monster->x, monster->y, dx, dy)) return;
    int x = monster->x + dx, y = monster->y + dy;
    if (x == game->player.x && y == game->player.y) monster_attack(game, monster);
    else if (!monster_at(level, x, y)) { monster->x = x; monster->y = y; }
}

static void chase(Game *game, Monster *monster) {
    if (can_attack(game, monster)) { monster_attack(game, monster); return; }
    Level *level = current_level(game);
    int here = game->distance[monster->y * level->width + monster->x];
    int chosen = -1, minimum = 0;
    for (int direction = 0; direction < 8; ++direction) {
        int dx = direction_x[direction], dy = direction_y[direction];
        if (!can_move(level, monster->x, monster->y, dx, dy)) continue;
        int x = monster->x + dx, y = monster->y + dy, distance = game->distance[y * level->width + x];
        if (distance < 0 || (here >= 0 && distance >= here)) continue;
        if (monster_at(level, x, y) || (x == game->player.x && y == game->player.y)) continue;
        if (chosen < 0 || distance < minimum) { chosen = direction; minimum = distance; }
    }
    if (chosen >= 0) { monster->x += direction_x[chosen]; monster->y += direction_y[chosen]; }
}

static void monster_action(Game *game, Monster *monster) {
    Level *level = current_level(game);
    bool sees = game->visible[monster->y * level->width + monster->x];
    if (monster->asleep) {
        if (sees && draw(&game->rng) % 100 < game->config.wake_chance) { monster->asleep = false; say(game, "The %s wakes up.", monster->kind->name); }
    } else if (monster->kind->stationary) {
        if (can_attack(game, monster)) monster_attack(game, monster);
    } else if (monster->kind->erratic && draw(&game->rng) % 2 == 0) wander(game, monster);
    else if (sees) chase(game, monster);
    else wander(game, monster);
}

static void monsters_act(Game *game) {
    Level *level = current_level(game);
    game->distance = distances(level, game->player.x, game->player.y);
    for (int i = 0; i < level->monster_count; ++i) {
        Monster *monster = &level->monsters[i];
        if (monster->hp <= 0) continue;
        monster->energy += monster->kind->speed;
        while (monster->energy >= 2) {
            monster->energy -= 2;
            monster_action(game, monster);
            if (game->result) return;
        }
    }
}

static void end_turn(Game *game) {
    Level *level = current_level(game);
    Player *player = &game->player;
    for (int i = 0; i < level->monster_count; ++i) {
        Monster *monster = &level->monsters[i];
        if (monster->hp > 0 && monster->kind->regenerates && monster->hp < monster->max_hp) ++monster->hp;
    }
    if (player->poison > 0) {
        --player->hp;
        ++game->poison_damage;
        if (player->hp <= 0) { die(game, "poison"); return; }
        --player->poison;
        if (!player->poison) say(game, "You feel less sick.");
    }
    if (!player->satiation) {
        --player->hp;
        ++game->starvation_damage;
        if (player->hp <= 0) { die(game, "starvation"); return; }
    } else {
        const char *before = hunger(game);
        --player->satiation;
        const char *after = hunger(game);
        if (strcmp(before, after)) {
            if (!strcmp(after, "hungry")) say(game, "You are getting hungry.");
            else if (!strcmp(after, "weak")) say(game, "You feel weak from hunger.");
            else say(game, "You are starving.");
        }
    }
    if (game->turn % game->config.regen == 0 && !player->poison && player->satiation > 0 && player->hp < player->max_hp) ++player->hp;
}

static char *status_line(Game *game) {
    Player *player = &game->player;
    return format("STATUS hp %d/%d level %d xp %d defense %d gold %d food %d %s poison %d", player->hp, player->max_hp, player->level, player->xp, defense(player), player->gold, player->satiation, hunger(game), player->poison);
}

static void map_rows(Game *game, Level *level, bool current, Lines *lines) {
    char border[83];
    border[0] = '+';
    memset(border + 1, '-', (size_t)level->width);
    border[level->width + 1] = '+';
    border[level->width + 2] = '\0';
    add_line(lines, "%s", border);
    for (int y = 0; y < level->height; ++y) {
        char row[83];
        row[0] = '|';
        for (int x = 0; x < level->width; ++x) {
            int cell = y * level->width + x;
            char value = level->memory[cell];
            if (current && game->visible[cell]) {
                Monster *monster = monster_at(level, x, y);
                Item *item = item_at(level, x, y);
                value = x == game->player.x && y == game->player.y ? '@' : monster ? monster->kind->symbol : item ? item_symbol(item) : level->terrain[cell];
            }
            row[x + 1] = value;
        }
        row[level->width + 1] = '|';
        row[level->width + 2] = '\0';
        add_line(lines, "%s", row);
    }
    add_line(lines, "%s", border);
}

static void checkpoint(Game *game) {
    add_line(&game->maps, "CHECKPOINT turn %d depth %d", game->turn, game->player.depth);
    map_rows(game, current_level(game), true, &game->maps);
    add_line(&game->maps, "%s", status_line(game));
}

static void run_game(Game *game) {
    update_view(game);
    for (int i = 0; i < game->command_count; ++i) {
        if (game->result) { ++game->unused; continue; }
        if (!execute(game, game->commands[i])) { ++game->failed; continue; }
        ++game->succeeded;
        if (game->result) continue;
        update_view(game);
        monsters_act(game);
        if (game->result) continue;
        end_turn(game);
        if (game->result) continue;
        for (int j = 0; j < game->config.checkpoint_count; ++j) if (game->turn == game->config.checkpoints[j]) checkpoint(game);
        ++game->turn;
    }
    if (!game->result) { game->result = "alive"; game->cause = "commands_exhausted"; }
}

static void exploration(const Level *level, int *explored, int *total) {
    *explored = *total = 0;
    for (int i = 0; i < level->width * level->height; ++i) if (level->terrain[i] != ' ') {
        ++*total;
        *explored += level->memory[i] != ' ';
    }
}

static char *dec_1(int numerator, int denominator) {
    if (!denominator) return "-";
    int rounded = (20 * numerator + denominator) / (2 * denominator);
    return format("%d.%d", rounded / 10, rounded % 10);
}

static void attack_line(Lines *lines, const char *name, AttackStats stats) {
    add_line(lines, "%s %d hits %d criticals %d damage %d accuracy %s", name, stats.count, stats.hits, stats.criticals, stats.damage, dec_1(100 * stats.hits, stats.count));
}

static Lines stats_lines(Game *game) {
    Lines lines = {0};
    Player *player = &game->player;
    add_line(&lines, "result %s", game->result);
    add_line(&lines, "cause %s", game->cause);
    add_line(&lines, "turns %d", game->succeeded);
    add_line(&lines, "depth %d", player->depth);
    add_line(&lines, "level %d", player->level);
    add_line(&lines, "xp %d", player->xp);
    add_line(&lines, "hp %d/%d", player->hp, player->max_hp);
    add_line(&lines, "defense %d", defense(player));
    add_line(&lines, "gold %d", player->gold);
    add_line(&lines, "food %d %s", player->satiation, hunger(game));
    add_line(&lines, "poison %d", player->poison);
    add_line(&lines, "weapon %s", player->weapon ? display_name(player->weapon) : "-");
    add_line(&lines, "armor %s", player->armor ? display_name(player->armor) : "-");
    add_line(&lines, "commands %d executed %d failed %d unused %d", game->command_count, game->succeeded, game->failed, game->unused);
    add_line(&lines, "moves %d", game->moves);
    attack_line(&lines, "player_attacks", game->player_attacks);
    attack_line(&lines, "monster_attacks", game->monster_attacks);
    add_line(&lines, "poison_damage %d starvation_damage %d", game->poison_damage, game->starvation_damage);
    add_line(&lines, "picked %d quaffed %d read %d eaten %d wielded %d worn %d", game->usage[0], game->usage[1], game->usage[2], game->usage[3], game->usage[4], game->usage[5]);
    int kills = 0;
    for (int i = 0; i < game->monster_type_count; ++i) kills += game->kills[i];
    add_line(&lines, "kills %d", kills);
    for (int i = 0; i < game->monster_type_count; ++i) if (game->kills[i]) add_line(&lines, "KILL %s %d", game->monster_types[i].name, game->kills[i]);
    for (int i = 0; i < game->config.levels; ++i) {
        Level *level = &game->levels[i];
        int explored, total;
        exploration(level, &explored, &total);
        add_line(&lines, "LEVEL %d rooms %d explored %d/%d %s monsters %d/%d items %d/%d", level->depth, level->room_count, explored, total, dec_1(100 * explored, total), level->kills, level->monster_count, level->picked, level->items_placed);
    }
    for (int i = 0; i < player->pack_count; ++i) {
        Item *item = player->pack[i];
        add_line(&lines, "INVENTORY %d %s%s", i + 1, display_name(item), item == player->weapon ? " (wielded)" : item == player->armor ? " (worn)" : "");
    }
    return lines;
}

static void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}

int main(void) {
    Game *game = read_game();
    run_game(game);
    add_line(&game->maps, "FINAL turn %d depth %d", game->succeeded, game->player.depth);
    for (int i = 0; i < game->player.depth; ++i) {
        Level *level = &game->levels[i];
        int explored, total;
        exploration(level, &explored, &total);
        add_line(&game->maps, "LEVEL %d explored %d/%d", level->depth, explored, total);
        map_rows(game, level, level->depth == game->player.depth, &game->maps);
    }
    add_line(&game->maps, "%s", status_line(game));
    write_lines("messages.txt", game->messages);
    write_lines("maps.txt", game->maps);
    write_lines("stats.txt", stats_lines(game));
    return 0;
}
