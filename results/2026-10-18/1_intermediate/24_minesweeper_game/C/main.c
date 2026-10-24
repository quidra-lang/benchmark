#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { MAX_CELLS = 900, MAX_COMPONENT = 30 };
typedef enum { READY, PLAYING, WON, LOST } State;
typedef enum { UNMARKED, FLAGGED, QUESTIONED } Mark;
typedef enum { BLOCK, CELL, NONE } Safety;
typedef enum { REVEAL, FLAG, UNFLAG, QUESTION, CHORD, AUTO_REVEAL, AUTO_FLAG, GUESS } MoveKind;
typedef enum {
    NEW, PRESET, LAYOUT, SAFETY, RESTART, CMD_REVEAL, CMD_FLAG, CMD_UNFLAG, CMD_QUESTION,
    CMD_CHORD, UNDO, SHOW, STATUS, CMD_CELL, HISTORY, REPLAY, HINT, AUTO, ANALYZE,
    PROB, FRONTIER, SOLVE, BOARDINFO, STATS
} Command;

static const char *command_names[] = {
    "NEW", "PRESET", "LAYOUT", "SAFETY", "RESTART", "REVEAL", "FLAG", "UNFLAG",
    "QUESTION", "CHORD", "UNDO", "SHOW", "STATUS", "CELL", "HISTORY", "REPLAY",
    "HINT", "AUTO", "ANALYZE", "PROB", "FRONTIER", "SOLVE", "BOARDINFO", "STATS"
};
static const int arguments[] = {4, 2, 2, 1, 0, 2, 2, 2, 2, 2, 0, 0, 0, 2, 1, 1, 0, 0, 0, 2, 0, 0, 0, 0};
static const char *move_names[] = {"reveal", "flag", "unflag", "question", "chord", "auto-reveal", "auto-flag", "guess"};
static const char *state_names[] = {"ready", "playing", "won", "lost"};
static char error_message[128];

static bool fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(error_message, sizeof error_message, format, args);
    va_end(args);
    return false;
}

static void *allocate(size_t size) {
    void *memory = malloc(size);
    if (!memory) exit(EXIT_FAILURE);
    return memory;
}

static void *grow(void *memory, size_t *capacity, size_t item_size) {
    *capacity = *capacity ? *capacity * 2 : 16;
    void *next = realloc(memory, *capacity * item_size);
    if (!next) exit(EXIT_FAILURE);
    return next;
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = allocate(capacity);
    int c;
    while ((c = getchar()) != EOF && c != '\n') {
        if (length + 1 == capacity) line = grow(line, &capacity, 1);
        line[length++] = (char)c;
    }
    if (c == EOF && !length) { free(line); return NULL; }
    if (length && line[length - 1] == '\r') length--;
    line[length] = '\0';
    return line;
}

typedef struct { MoveKind kind; int cell; } Move;
typedef struct {
    Command command;
    bool revealed[MAX_CELLS];
    unsigned char marks[MAX_CELLS];
    size_t move_count;
} Snapshot;

typedef struct {
    int width, height, cells, mines;
    int64_t seed;
    bool determined, mine[MAX_CELLS], revealed[MAX_CELLS];
    unsigned char number[MAX_CELLS], marks[MAX_CELLS], degree[MAX_CELLS];
    int neighbors[MAX_CELLS][8];
    State state;
    int exploded;
    Move *moves;
    size_t move_count, move_capacity;
    Snapshot *undo;
    size_t undo_count, undo_capacity;
} Game;

typedef struct { int played, won, lost, streak, best; size_t fastest; bool has_fastest; } Statistics;
typedef struct { Game *game; Safety safety; Statistics stats; } Table;

static bool finished(const Game *game) { return game->state == WON || game->state == LOST; }

static int flag_count(const Game *game) {
    int count = 0;
    for (int i = 0; i < game->cells; i++) count += game->marks[i] == FLAGGED;
    return count;
}

static int opened_count(const Game *game) {
    int count = 0;
    for (int i = 0; i < game->cells; i++) count += game->revealed[i];
    return count;
}

static int remaining(const Game *game) { return game->mines - flag_count(game); }
static bool unknown(const Game *game, int cell) { return !game->revealed[cell] && game->marks[cell] != FLAGGED; }

static Game *new_game(int width, int height, int mines, int64_t seed) {
    Game *game = calloc(1, sizeof *game);
    if (!game) exit(EXIT_FAILURE);
    game->width = width;
    game->height = height;
    game->cells = width * height;
    game->mines = mines;
    game->seed = seed;
    game->exploded = -1;
    for (int cell = 0; cell < game->cells; cell++) {
        int x = cell % width, y = cell / width;
        for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
            if ((!dx && !dy) || x + dx < 0 || x + dx >= width || y + dy < 0 || y + dy >= height) continue;
            game->neighbors[cell][game->degree[cell]++] = (y + dy) * width + x + dx;
        }
    }
    return game;
}

static void free_game(Game *game) {
    if (!game) return;
    free(game->moves);
    free(game->undo);
    free(game);
}

static void restart(Game *game) {
    memset(game->revealed, 0, sizeof game->revealed);
    memset(game->marks, 0, sizeof game->marks);
    game->move_count = game->undo_count = 0;
    game->exploded = -1;
    game->state = game->determined ? PLAYING : READY;
}

static Game *copy_game(const Game *source, bool keep_moves) {
    Game *copy = allocate(sizeof *copy);
    *copy = *source;
    copy->moves = NULL;
    copy->move_count = copy->move_capacity = 0;
    copy->undo = NULL;
    copy->undo_count = copy->undo_capacity = 0;
    if (keep_moves && source->move_count) {
        copy->move_count = copy->move_capacity = source->move_count;
        copy->moves = allocate(copy->move_count * sizeof *copy->moves);
        memcpy(copy->moves, source->moves, copy->move_count * sizeof *copy->moves);
    }
    return copy;
}

static void add_move(Game *game, MoveKind kind, int cell) {
    if (game->move_count == game->move_capacity) game->moves = grow(game->moves, &game->move_capacity, sizeof *game->moves);
    game->moves[game->move_count++] = (Move){kind, cell};
}

static void number_board(Game *game) {
    for (int cell = 0; cell < game->cells; cell++) {
        game->number[cell] = 0;
        for (int i = 0; i < game->degree[cell]; i++) game->number[cell] += game->mine[game->neighbors[cell][i]];
    }
}

static void place_mines(Game *game, int first, Safety safety) {
    int candidates[MAX_CELLS], count = 0;
    int sx = first % game->width, sy = first / game->width;
    for (int cell = 0; cell < game->cells; cell++) {
        int x = cell % game->width, y = cell / game->width;
        if (safety == NONE || (safety == CELL && cell != first) || (safety == BLOCK && (abs(x - sx) >= 2 || abs(y - sy) >= 2))) {
            candidates[count++] = cell;
        }
    }
    int64_t state = game->seed;
    for (int i = 0; i < game->mines; i++) {
        state = 48271 * state % 2147483647;
        int chosen = (int)(state % count);
        game->mine[candidates[chosen]] = true;
        memmove(candidates + chosen, candidates + chosen + 1, (size_t)(count - chosen - 1) * sizeof *candidates);
        count--;
    }
    number_board(game);
    game->determined = true;
    game->state = PLAYING;
}

static int reveal(Game *game, int cell, Safety safety) {
    if (!game->determined) place_mines(game, cell, safety);
    if (game->mine[cell]) { game->state = LOST; game->exploded = cell; return 0; }
    int queue[MAX_CELLS], head = 0, tail = 0;
    game->revealed[cell] = true;
    game->marks[cell] = UNMARKED;
    queue[tail++] = cell;
    while (head < tail) {
        int current = queue[head++];
        if (game->number[current]) continue;
        for (int i = 0; i < game->degree[current]; i++) {
            int next = game->neighbors[current][i];
            if (!unknown(game, next)) continue;
            game->revealed[next] = true;
            game->marks[next] = UNMARKED;
            queue[tail++] = next;
        }
    }
    return tail;
}

static int chord(Game *game, int cell, Safety safety) {
    int opened = 0;
    for (int i = 0; i < game->degree[cell]; i++) {
        int next = game->neighbors[cell][i];
        if (unknown(game, next)) opened += reveal(game, next, safety);
        if (game->state == LOST) break;
    }
    return opened;
}

static void check_win(Game *game) {
    if (game->state != PLAYING || opened_count(game) != game->cells - game->mines) return;
    game->state = WON;
    for (int cell = 0; cell < game->cells; cell++) if (game->mine[cell]) game->marks[cell] = FLAGGED;
}

static void show(const Game *game) {
    for (int cell = 0; cell < game->cells; cell++) {
        char symbol;
        if (game->state == LOST && game->mine[cell]) symbol = cell == game->exploded ? '!' : game->marks[cell] == FLAGGED ? 'F' : '*';
        else if (game->state == LOST && game->marks[cell] == FLAGGED) symbol = 'X';
        else if (game->revealed[cell]) symbol = game->number[cell] ? (char)('0' + game->number[cell]) : '.';
        else symbol = game->marks[cell] == FLAGGED ? 'F' : game->marks[cell] == QUESTIONED ? '?' : '#';
        putchar(symbol);
        if (cell % game->width == game->width - 1) putchar('\n');
    }
}

static void ending_output(const Game *game) {
    if (game->state == LOST) { printf("boom %d,%d\n", game->exploded % game->width, game->exploded / game->width); show(game); }
    else if (game->state == WON) printf("win moves %zu\n", game->move_count);
}

typedef struct { int cell, rem, count, unknown[8]; } Constraint;

static int constraints(const Game *game, Constraint result[MAX_CELLS]) {
    int count = 0;
    for (int cell = 0; cell < game->cells; cell++) {
        if (!game->revealed[cell] || !game->number[cell]) continue;
        Constraint constraint = {.cell = cell, .rem = game->number[cell]};
        for (int i = 0; i < game->degree[cell]; i++) {
            int next = game->neighbors[cell][i];
            constraint.rem -= game->marks[next] == FLAGGED;
            if (unknown(game, next)) constraint.unknown[constraint.count++] = next;
        }
        if (constraint.count) result[count++] = constraint;
    }
    return count;
}

typedef enum { NO_REASON, SINGLE, SUBSET, COUNT } ReasonKind;
typedef struct { ReasonKind kind; int a, b; } Reason;
typedef struct { Reason safe[MAX_CELLS], mines[MAX_CELLS]; bool any; } Deduction;

static void add_reason(Deduction *result, bool safe, int cell, Reason reason) {
    Reason *slot = safe ? &result->safe[cell] : &result->mines[cell];
    if (slot->kind == NO_REASON) *slot = reason;
    result->any = true;
}

static bool contains(const Constraint *constraint, int cell) {
    for (int i = 0; i < constraint->count; i++) if (constraint->unknown[i] == cell) return true;
    return false;
}

static void deduce(const Game *game, Deduction *result) {
    memset(result, 0, sizeof *result);
    Constraint list[MAX_CELLS];
    int count = constraints(game, list);
    for (int rule = 1; rule <= 2; rule++) {
        for (int i = 0; i < count; i++) {
            const Constraint *c = &list[i];
            if (c->rem != (rule == 1 ? 0 : c->count)) continue;
            for (int j = 0; j < c->count; j++) add_reason(result, rule == 1, c->unknown[j], (Reason){SINGLE, c->cell, 0});
        }
        if (result->any) return;
    }
    int at[MAX_CELLS];
    for (int cell = 0; cell < game->cells; cell++) at[cell] = -1;
    for (int i = 0; i < count; i++) at[list[i].cell] = i;
    for (int i = 0; i < count; i++) {
        const Constraint *a = &list[i];
        int ax = a->cell % game->width, ay = a->cell / game->width;
        /* A nonempty subset pair must share a neighbor, so its centers are at most two cells apart. */
        for (int y = ay - 2; y <= ay + 2; y++) for (int x = ax - 2; x <= ax + 2; x++) {
            if (x < 0 || x >= game->width || y < 0 || y >= game->height) continue;
            int index = at[y * game->width + x];
            if (index < 0 || index == i) continue;
            const Constraint *b = &list[index];
            if (a->count >= b->count) continue;
            bool subset = true;
            for (int j = 0; j < a->count; j++) if (!contains(b, a->unknown[j])) { subset = false; break; }
            if (!subset) continue;
            int difference = b->rem - a->rem;
            if (difference != 0 && difference != b->count - a->count) continue;
            for (int j = 0; j < b->count; j++) if (!contains(a, b->unknown[j])) {
                add_reason(result, difference == 0, b->unknown[j], (Reason){SUBSET, a->cell, b->cell});
            }
        }
    }
    if (result->any) return;
    if (game->state == PLAYING && remaining(game) == 0) {
        for (int cell = 0; cell < game->cells; cell++) if (unknown(game, cell)) add_reason(result, true, cell, (Reason){COUNT, 0, 0});
    }
}

static void hint(const Game *game) {
    Deduction result;
    deduce(game, &result);
    for (int side = 0; side < 2; side++) for (int cell = 0; cell < game->cells; cell++) {
        Reason reason = side == 0 ? result.safe[cell] : result.mines[cell];
        if (reason.kind == NO_REASON) continue;
        printf("hint %s %d,%d by ", side == 0 ? "safe" : "mine", cell % game->width, cell / game->width);
        if (reason.kind == COUNT) puts("count");
        else {
            printf("%s %d,%d", reason.kind == SINGLE ? "single" : "subset", reason.a % game->width, reason.a / game->width);
            if (reason.kind == SUBSET) printf(" %d,%d", reason.b % game->width, reason.b / game->width);
            putchar('\n');
        }
        return;
    }
    puts("hint none");
}

typedef struct { int start, size, configs, minimum, maximum; } Component;
typedef struct {
    Constraint constraints[MAX_CELLS];
    int constraint_count;
    int component_of[MAX_CELLS], cells[MAX_CELLS], ways[MAX_CELLS];
    Component components[MAX_CELLS];
    int component_count, total;
} Frontier;

static int root(int parent[MAX_CELLS], int cell) {
    while (parent[cell] != cell) { parent[cell] = parent[parent[cell]]; cell = parent[cell]; }
    return cell;
}

static Frontier *make_frontier(const Game *game) {
    Frontier *frontier = calloc(1, sizeof *frontier);
    if (!frontier) exit(EXIT_FAILURE);
    frontier->constraint_count = constraints(game, frontier->constraints);
    int parent[MAX_CELLS], ids[MAX_CELLS];
    bool present[MAX_CELLS] = {false};
    for (int i = 0; i < game->cells; i++) { parent[i] = i; ids[i] = -1; frontier->component_of[i] = -1; }
    for (int i = 0; i < frontier->constraint_count; i++) {
        Constraint *c = &frontier->constraints[i];
        for (int j = 0; j < c->count; j++) {
            present[c->unknown[j]] = true;
            int left = root(parent, c->unknown[j]);
            int right = root(parent, c->unknown[0]);
            parent[left] = right;
        }
    }
    for (int cell = 0; cell < game->cells; cell++) if (present[cell]) {
        int representative = root(parent, cell);
        if (ids[representative] < 0) ids[representative] = frontier->component_count++;
        int id = ids[representative];
        frontier->component_of[cell] = id;
        frontier->components[id].size++;
        frontier->total++;
    }
    int position[MAX_CELLS] = {0}, offset = 0;
    for (int i = 0; i < frontier->component_count; i++) {
        frontier->components[i].start = offset;
        offset += frontier->components[i].size;
    }
    for (int cell = 0; cell < game->cells; cell++) {
        int id = frontier->component_of[cell];
        if (id >= 0) frontier->cells[frontier->components[id].start + position[id]++] = cell;
    }
    return frontier;
}

static int bit_count(uint32_t bits) {
    int count = 0;
    while (bits) { bits &= bits - 1; count++; }
    return count;
}

typedef struct {
    uint32_t masks[MAX_CELLS];
    int targets[MAX_CELLS], constraint_count, size;
    int configs, minimum, maximum, ways[MAX_COMPONENT];
} Search;

static void search_configurations(Search *search, int depth, uint32_t mines) {
    uint32_t assigned = (UINT32_C(1) << depth) - 1;
    for (int i = 0; i < search->constraint_count; i++) {
        int used = bit_count(search->masks[i] & mines);
        int left = bit_count(search->masks[i] & ~assigned);
        if (used > search->targets[i] || used + left < search->targets[i]) return;
    }
    if (depth == search->size) {
        int total = bit_count(mines);
        search->configs++;
        if (total < search->minimum) search->minimum = total;
        if (total > search->maximum) search->maximum = total;
        for (int i = 0; i < search->size; i++) search->ways[i] += (mines & (UINT32_C(1) << i)) != 0;
        return;
    }
    search_configurations(search, depth + 1, mines);
    search_configurations(search, depth + 1, mines | (UINT32_C(1) << depth));
}

static void count_component(Frontier *frontier, int id) {
    Component *component = &frontier->components[id];
    Search search = {.size = component->size, .minimum = component->size + 1, .maximum = -1};
    int local[MAX_CELLS];
    for (int i = 0; i < component->size; i++) local[frontier->cells[component->start + i]] = i;
    for (int i = 0; i < frontier->constraint_count; i++) {
        const Constraint *c = &frontier->constraints[i];
        if (frontier->component_of[c->unknown[0]] != id) continue;
        uint32_t mask = 0;
        for (int j = 0; j < c->count; j++) mask |= UINT32_C(1) << local[c->unknown[j]];
        search.masks[search.constraint_count] = mask;
        search.targets[search.constraint_count++] = c->rem;
    }
    search_configurations(&search, 0, 0);
    component->configs = search.configs;
    component->minimum = search.minimum;
    component->maximum = search.maximum;
    for (int i = 0; i < component->size; i++) frontier->ways[frontier->cells[component->start + i]] = search.ways[i];
}

static int gcd(int a, int b) {
    while (b) { int rest = a % b; a = b; b = rest; }
    return a;
}

static void probability(const Game *game, int cell) {
    Frontier *frontier = make_frontier(game);
    int id = frontier->component_of[cell];
    printf("prob %d,%d ", cell % game->width, cell / game->width);
    if (id < 0) puts("unconstrained");
    else {
        count_component(frontier, id);
        Component *component = &frontier->components[id];
        if (!component->configs) puts("inconsistent");
        else {
            int divisor = gcd(frontier->ways[cell], component->configs);
            printf("%d/%d size %d configs %d\n", frontier->ways[cell] / divisor, component->configs / divisor, component->size, component->configs);
        }
    }
    free(frontier);
}

static void frontier_report(const Game *game) {
    Frontier *frontier = make_frontier(game);
    printf("frontier %d components %d\n", frontier->total, frontier->component_count);
    for (int i = 0; i < frontier->component_count; i++) {
        count_component(frontier, i);
        Component *component = &frontier->components[i];
        int first = frontier->cells[component->start];
        printf("component %d,%d size %d", first % game->width, first / game->width, component->size);
        if (!component->configs) puts(" inconsistent");
        else printf(" configs %d min %d max %d\n", component->configs, component->minimum, component->maximum);
    }
    free(frontier);
}

typedef struct { int rounds, flagged, opened, guesses; } AutoResult;

static AutoResult auto_play(Game *game, Safety safety) {
    AutoResult total = {0};
    while (game->state == PLAYING) {
        Deduction result;
        deduce(game, &result);
        if (!result.any) break;
        total.rounds++;
        for (int cell = 0; cell < game->cells; cell++) if (result.safe[cell].kind != NO_REASON && !game->revealed[cell]) {
            add_move(game, AUTO_REVEAL, cell);
            total.opened += reveal(game, cell, safety);
            check_win(game);
            if (finished(game)) return total;
        }
        for (int cell = 0; cell < game->cells; cell++) if (result.mines[cell].kind != NO_REASON && unknown(game, cell)) {
            game->marks[cell] = FLAGGED;
            total.flagged++;
            add_move(game, AUTO_FLAG, cell);
        }
    }
    return total;
}

static AutoResult solve(Game *game, Safety safety) {
    AutoResult total = {0};
    while (!finished(game)) {
        AutoResult step = auto_play(game, safety);
        total.rounds += step.rounds;
        total.flagged += step.flagged;
        total.opened += step.opened;
        if (finished(game)) break;
        Frontier *frontier = make_frontier(game);
        for (int i = 0; i < frontier->component_count; i++) count_component(frontier, i);
        int unknown_count = 0;
        for (int cell = 0; cell < game->cells; cell++) unknown_count += unknown(game, cell);
        int outside_mines = remaining(game);
        if (outside_mines < 0) outside_mines = 0;
        int guess = -1, best_numerator = 0, best_denominator = 1;
        for (int cell = 0; cell < game->cells; cell++) if (unknown(game, cell)) {
            int id = frontier->component_of[cell], numerator, denominator;
            if (id < 0) { numerator = outside_mines; denominator = unknown_count; }
            else {
                numerator = frontier->ways[cell];
                denominator = frontier->components[id].configs;
                if (!denominator) continue;
            }
            if (guess < 0 || (int64_t)numerator * best_denominator < (int64_t)best_numerator * denominator) {
                guess = cell;
                best_numerator = numerator;
                best_denominator = denominator;
            }
        }
        free(frontier);
        if (guess < 0) break;
        total.guesses++;
        add_move(game, GUESS, guess);
        total.opened += reveal(game, guess, safety);
        check_win(game);
    }
    return total;
}

static void replay(const Game *game, size_t count, Safety safety) {
    Game *copy = copy_game(game, false);
    restart(copy);
    for (size_t i = 0; i < count; i++) {
        Move move = game->moves[i];
        switch (move.kind) {
            case REVEAL: case AUTO_REVEAL: case GUESS: reveal(copy, move.cell, safety); break;
            case CHORD: chord(copy, move.cell, safety); break;
            case FLAG: case AUTO_FLAG: copy->marks[move.cell] = FLAGGED; break;
            case UNFLAG: copy->marks[move.cell] = UNMARKED; break;
            case QUESTION: copy->marks[move.cell] = copy->marks[move.cell] == QUESTIONED ? UNMARKED : QUESTIONED; break;
        }
        check_win(copy);
    }
    printf("replay %zu/%zu\n", count, game->move_count);
    show(copy);
    free_game(copy);
}

static void board_info(const Game *game) {
    bool visited[MAX_CELLS] = {false};
    int openings = 0, largest = 0, isolated = 0;
    for (int cell = 0; cell < game->cells; cell++) {
        if (game->mine[cell]) continue;
        if (game->number[cell]) {
            bool adjacent_blank = false;
            for (int i = 0; i < game->degree[cell]; i++) {
                int next = game->neighbors[cell][i];
                adjacent_blank |= !game->mine[next] && game->number[next] == 0;
            }
            isolated += !adjacent_blank;
        } else if (!visited[cell]) {
            openings++;
            bool covered[MAX_CELLS] = {false};
            int queue[MAX_CELLS], head = 0, tail = 0;
            queue[tail++] = cell;
            visited[cell] = true;
            covered[cell] = true;
            while (head < tail) {
                int current = queue[head++];
                for (int i = 0; i < game->degree[current]; i++) {
                    int next = game->neighbors[current][i];
                    covered[next] = true;
                    if (!game->number[next] && !visited[next]) { visited[next] = true; queue[tail++] = next; }
                }
            }
            int size = 0;
            for (int i = 0; i < game->cells; i++) size += covered[i];
            if (size > largest) largest = size;
        }
    }
    printf("3bv %d openings %d largest %d mines %d safe %d\n", openings + isolated, openings, largest, game->mines, game->cells - game->mines);
}

static void neighbor_counts(const Game *game, int cell, int *flags, int *unknowns, int *opened) {
    *flags = *unknowns = *opened = 0;
    for (int i = 0; i < game->degree[cell]; i++) {
        int next = game->neighbors[cell][i];
        *flags += game->marks[next] == FLAGGED;
        *unknowns += unknown(game, next);
        *opened += game->revealed[next];
    }
}

static bool process(Game *game, Command command, int cell, int64_t value, Safety safety) {
    int x = cell % game->width, y = cell / game->width;
    if (command == CMD_REVEAL || command == CMD_FLAG || command == CMD_UNFLAG || command == CMD_QUESTION || command == PROB) {
        if (game->revealed[cell]) return fail("already revealed");
        if ((command == CMD_REVEAL || command == PROB) && game->marks[cell] == FLAGGED) return fail("flagged");
        if (command == CMD_FLAG && game->marks[cell] == FLAGGED) return fail("already flagged");
        if (command == CMD_UNFLAG && game->marks[cell] != FLAGGED) return fail("not flagged");
    }
    switch (command) {
        case RESTART:
            restart(game);
            printf("restart %dx%d mines %d\n", game->width, game->height, game->mines);
            break;
        case CMD_REVEAL: {
            add_move(game, REVEAL, cell);
            int opened = reveal(game, cell, safety);
            if (game->state != LOST) { printf("revealed %d\n", opened); check_win(game); }
            ending_output(game);
            break;
        }
        case CMD_FLAG:
            game->marks[cell] = FLAGGED;
            add_move(game, FLAG, cell);
            printf("flagged %d,%d left %d\n", x, y, remaining(game));
            break;
        case CMD_UNFLAG:
            game->marks[cell] = UNMARKED;
            add_move(game, UNFLAG, cell);
            printf("unflagged %d,%d left %d\n", x, y, remaining(game));
            break;
        case CMD_QUESTION:
            add_move(game, QUESTION, cell);
            game->marks[cell] = game->marks[cell] == QUESTIONED ? UNMARKED : QUESTIONED;
            printf("%s %d,%d left %d\n", game->marks[cell] == UNMARKED ? "unmarked" : "questioned", x, y, remaining(game));
            break;
        case CMD_CHORD: {
            if (!game->revealed[cell]) return fail("not revealed");
            if (!game->number[cell]) return fail("no number");
            int flags, unknowns, opened;
            neighbor_counts(game, cell, &flags, &unknowns, &opened);
            if (flags != game->number[cell]) return fail("flags %d of %d", flags, game->number[cell]);
            if (!unknowns) return fail("nothing to reveal");
            add_move(game, CHORD, cell);
            opened = chord(game, cell, safety);
            if (game->state != LOST) { printf("chorded %d\n", opened); check_win(game); }
            ending_output(game);
            break;
        }
        case UNDO: {
            if (!game->undo_count) return fail("nothing to undo");
            Snapshot *snapshot = &game->undo[--game->undo_count];
            memcpy(game->revealed, snapshot->revealed, sizeof game->revealed);
            memcpy(game->marks, snapshot->marks, sizeof game->marks);
            game->move_count = snapshot->move_count;
            const char *name = snapshot->command == AUTO ? "auto" : snapshot->command == SOLVE ? "solve" : move_names[snapshot->command - CMD_REVEAL];
            printf("undo %s moves %zu\n", name, game->move_count);
            break;
        }
        case SHOW: show(game); break;
        case STATUS:
            printf("status %s left %d moves %zu revealed %d/%d\n", state_names[game->state], remaining(game), game->move_count, opened_count(game), game->cells - game->mines);
            break;
        case CMD_CELL: {
            int flags, unknowns, opened;
            neighbor_counts(game, cell, &flags, &unknowns, &opened);
            if (game->revealed[cell]) printf("cell %d,%d number %d flags %d unknown %d\n", x, y, game->number[cell], flags, unknowns);
            else printf("cell %d,%d hidden mark %s open %d\n", x, y, game->marks[cell] == FLAGGED ? "flag" : game->marks[cell] == QUESTIONED ? "question" : "none", opened);
            break;
        }
        case HISTORY: {
            printf("history %zu\n", game->move_count);
            size_t count = (uint64_t)value < game->move_count ? (size_t)value : game->move_count;
            for (size_t i = game->move_count - count; i < game->move_count; i++) {
                Move move = game->moves[i];
                printf("%zu %s %d,%d\n", i + 1, move_names[move.kind], move.cell % game->width, move.cell / game->width);
            }
            break;
        }
        case REPLAY:
            if ((uint64_t)value > game->move_count) return fail("no move %" PRId64, value);
            replay(game, (size_t)value, safety);
            break;
        case HINT: hint(game); break;
        case AUTO: case SOLVE: {
            AutoResult result = command == AUTO ? auto_play(game, safety) : solve(game, safety);
            if (command == SOLVE) printf("solve guesses %d rounds %d flagged %d revealed %d\n", result.guesses, result.rounds, result.flagged, result.opened);
            else printf("auto rounds %d flagged %d revealed %d\n", result.rounds, result.flagged, result.opened);
            ending_output(game);
            break;
        }
        case ANALYZE: {
            Game *copy = copy_game(game, true);
            AutoResult result = auto_play(copy, safety);
            if (copy->state == LOST) printf("analyze boom %d,%d rounds %d\n", copy->exploded % copy->width, copy->exploded / copy->width, result.rounds);
            else if (copy->state == WON) printf("analyze clear rounds %d\n", result.rounds);
            else printf("analyze stuck rounds %d revealed %d/%d\n", result.rounds, opened_count(copy), copy->cells - copy->mines);
            free_game(copy);
            break;
        }
        case PROB: probability(game, cell); break;
        case FRONTIER: frontier_report(game); break;
        case BOARDINFO: board_info(game); break;
        default: break;
    }
    return true;
}

static bool number_word(const char *word, int64_t *value) {
    size_t length = strlen(word);
    if (length > 10 || (length > 1 && word[0] == '0')) return false;
    for (size_t i = 0; i < length; i++) if (word[i] < '0' || word[i] > '9') return false;
    *value = strtoll(word, NULL, 10);
    return true;
}

static bool has_cell(Command command) {
    return (command >= CMD_REVEAL && command <= CMD_CHORD) || command == CMD_CELL || command == PROB;
}

static bool needs_unfinished(Command command) {
    return (command >= CMD_REVEAL && command <= UNDO) || command == HINT || command == AUTO
        || command == ANALYZE || command == PROB || command == FRONTIER || command == SOLVE;
}

static bool records_undo(Command command) {
    return (command >= CMD_REVEAL && command <= CMD_CHORD) || command == AUTO || command == SOLVE;
}

static bool layout(Table *table, int width, int height) {
    bool mines[MAX_CELLS] = {false};
    int count = 0, bad_row = 0;
    for (int y = 0; y < height; y++) {
        char *row = read_line();
        bool good = strlen(row) == (size_t)width;
        for (size_t x = 0; row[x]; x++) if (row[x] != '*' && row[x] != '.') good = false;
        if (!good) { if (!bad_row) bad_row = y + 1; }
        else for (int x = 0; x < width; x++) { mines[y * width + x] = row[x] == '*'; count += row[x] == '*'; }
        free(row);
    }
    if (bad_row) return fail("bad row %d", bad_row);
    if (count == 0 || count == width * height) return fail("bad mine count %d", count);
    Game *game = new_game(width, height, count, 0);
    memcpy(game->mine, mines, sizeof mines);
    game->determined = true;
    game->state = PLAYING;
    number_board(game);
    free_game(table->game);
    table->game = game;
    printf("layout %dx%d mines %d\n", width, height, count);
    return true;
}

static bool execute(Table *table, char **words, int count) {
    if (strcmp(words[0], "LAYOUT") == 0) return layout(table, atoi(words[1]), atoi(words[2]));
    int index = -1;
    for (int i = 0; i < 24; i++) if (strcmp(words[0], command_names[i]) == 0) { index = i; break; }
    if (index < 0) return fail("unknown command %s", words[0]);
    Command command = (Command)index;
    if (count != arguments[command] + 1) return fail("bad arguments");
    int64_t values[4] = {0};
    int preset = -1;
    Safety safety = table->safety;
    if (command == PRESET) {
        const char *presets[] = {"beginner", "intermediate", "expert"};
        for (int i = 0; i < 3; i++) if (strcmp(words[1], presets[i]) == 0) preset = i;
        if (preset < 0 || !number_word(words[2], &values[0])) return fail("bad arguments");
    } else if (command == SAFETY) {
        if (strcmp(words[1], "block") == 0) safety = BLOCK;
        else if (strcmp(words[1], "cell") == 0) safety = CELL;
        else if (strcmp(words[1], "none") == 0) safety = NONE;
        else return fail("bad arguments");
    } else for (int i = 1; i < count; i++) if (!number_word(words[i], &values[i - 1])) return fail("bad arguments");
    if (command == NEW || command == PRESET) {
        if (command == PRESET) {
            const int widths[] = {9, 16, 30}, heights[] = {9, 16, 16}, mines[] = {10, 40, 99};
            values[3] = values[0]; values[0] = widths[preset]; values[1] = heights[preset]; values[2] = mines[preset];
        }
        if (values[0] < 1 || values[0] > 30 || values[1] < 1 || values[1] > 30 || values[2] < 1
            || values[2] > values[0] * values[1] - 9 || values[3] < 1 || values[3] > 2147483646) return fail("bad value");
        Game *game = new_game((int)values[0], (int)values[1], (int)values[2], values[3]);
        free_game(table->game);
        table->game = game;
        printf("new %dx%d mines %d\n", game->width, game->height, game->mines);
        return true;
    }
    if (command == HISTORY && values[0] == 0) return fail("bad value");
    if (command == SAFETY) { table->safety = safety; printf("safety %s\n", words[1]); return true; }
    if (command == STATS) {
        Statistics *stats = &table->stats;
        printf("stats played %d won %d lost %d rate ", stats->played, stats->won, stats->lost);
        if (stats->played) printf("%d%%", 100 * stats->won / stats->played); else putchar('-');
        printf(" streak %d best %d fastest ", stats->streak, stats->best);
        if (stats->has_fastest) printf("%zu\n", stats->fastest); else puts("-");
        return true;
    }
    Game *game = table->game;
    if (!game) return fail("no game");
    if (has_cell(command) && (values[0] >= game->width || values[1] >= game->height)) return fail("out of range");
    if (needs_unfinished(command) && finished(game)) return fail("game over");
    if ((command == ANALYZE || command == BOARDINFO) && !game->determined) return fail("not started");
    Snapshot snapshot = {.command = command, .move_count = game->move_count};
    if (records_undo(command)) {
        memcpy(snapshot.revealed, game->revealed, sizeof snapshot.revealed);
        memcpy(snapshot.marks, game->marks, sizeof snapshot.marks);
    }
    State before = game->state;
    int cell = has_cell(command) ? (int)values[1] * game->width + (int)values[0] : 0;
    if (!process(game, command, cell, values[0], safety)) return false;
    if (records_undo(command) && game->move_count > snapshot.move_count) {
        if (game->undo_count == game->undo_capacity) game->undo = grow(game->undo, &game->undo_capacity, sizeof *game->undo);
        game->undo[game->undo_count++] = snapshot;
    }
    if (before != WON && before != LOST && finished(game)) {
        Statistics *stats = &table->stats;
        stats->played++;
        if (game->state == WON) {
            stats->won++; stats->streak++;
            if (stats->streak > stats->best) stats->best = stats->streak;
            if (!stats->has_fastest || game->move_count < stats->fastest) { stats->fastest = game->move_count; stats->has_fastest = true; }
        } else { stats->lost++; stats->streak = 0; }
    }
    return true;
}

int main(void) {
    char *line = read_line();
    if (!line) return 0;
    int commands = atoi(line);
    free(line);
    Table table = {0};
    for (int i = 0; i < commands; i++) {
        line = read_line();
        char *words[6];
        int count = 0;
        for (char *word = strtok(line, " "); word && count < 6; word = strtok(NULL, " ")) words[count++] = word;
        if (!execute(&table, words, count)) printf("error: %s\n", error_message);
        free(line);
    }
    free_game(table.game);
    return 0;
}
