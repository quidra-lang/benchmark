#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { DICE = 5, FACES = 6, CATEGORIES = 13, MAX_PLAYERS = 6, MAX_ENTRIES = 78, CODES = 46656 };
typedef enum { KIND, STRAIGHT, HIGH, UPPER } Strategy;
typedef enum { FORCED, FREE, OFF } JokerRule;

static const char *categories[] = {
    "ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND",
    "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE"
};
static const char *strategies[] = {"KIND", "STRAIGHT", "HIGH", "UPPER"};
static const int powers[] = {1, 6, 36, 216, 1296, 7776};
static const int factorial[] = {1, 1, 2, 6, 24, 120};
static char error_message[128];

static bool fail(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(error_message, sizeof error_message, format, arguments);
    va_end(arguments);
    return false;
}

typedef struct { char text[64]; } Text;

static Text fraction(int64_t numerator, int64_t denominator) {
    int64_t a = numerator, b = denominator;
    while (b) { int64_t rest = a % b; a = b; b = rest; }
    numerator /= a;
    denominator /= a;
    Text text;
    if (denominator == 1) snprintf(text.text, sizeof text.text, "%" PRId64, numerator);
    else snprintf(text.text, sizeof text.text, "%" PRId64 "/%" PRId64, numerator, denominator);
    return text;
}

static Text average(int64_t sum, int count) {
    int64_t value = count ? 100 * sum / count : 0;
    Text text;
    snprintf(text.text, sizeof text.text, "%" PRId64 ".%02" PRId64, value / 100, value % 100);
    return text;
}

static bool held(int mask, int die) { return (mask & (1 << (4 - die))) != 0; }

static Text pattern_text(int mask) {
    Text text;
    for (int i = 0; i < DICE; i++) text.text[i] = held(mask, i) ? '1' : '0';
    text.text[DICE] = '\0';
    return text;
}

static Text face_text(const int *faces, int mask) {
    Text text = {""};
    int length = 0;
    if (faces) for (int i = 0; i < DICE; i++) if (held(mask, i)) {
        if (length) text.text[length++] = ' ';
        text.text[length++] = (char)('0' + faces[i]);
    }
    if (!length) text.text[length++] = '-';
    text.text[length] = '\0';
    return text;
}

static void face_counts(const int faces[DICE], int counts[FACES]) {
    memset(counts, 0, FACES * sizeof *counts);
    for (int i = 0; i < DICE; i++) counts[faces[i] - 1]++;
}

static void decode(int code, int counts[FACES]) {
    for (int i = 0; i < FACES; i++) { counts[i] = code % 6; code /= 6; }
}

static int held_code(const int faces[DICE], int mask) {
    int code = 0;
    for (int i = 0; i < DICE; i++) if (held(mask, i)) code += powers[faces[i] - 1];
    return code;
}

static int frequent(const int counts[FACES]) {
    int best = 0;
    for (int i = 1; i < FACES; i++) if (counts[i] >= counts[best]) best = i;
    return best;
}

static int normal_score(int category, const int counts[FACES]) {
    if (category < 6) return (category + 1) * counts[category];
    int total = 0, maximum = 0, bits = 0;
    bool pair = false, triple = false;
    for (int i = 0; i < FACES; i++) {
        total += (i + 1) * counts[i];
        if (counts[i] > maximum) maximum = counts[i];
        if (counts[i]) bits |= 1 << i;
        pair |= counts[i] == 2;
        triple |= counts[i] == 3;
    }
    switch (category) {
        case 6: return maximum >= 3 ? total : 0;
        case 7: return maximum >= 4 ? total : 0;
        case 8: return pair && triple ? 25 : 0;
        case 9: return (bits & 15) == 15 || (bits & 30) == 30 || (bits & 60) == 60 ? 30 : 0;
        case 10: return bits == 31 || bits == 62 ? 40 : 0;
        case 11: return maximum == 5 ? 50 : 0;
        default: return total;
    }
}

typedef struct {
    char name[9];
    Strategy strategy;
    int scores[CATEGORIES], yahtzee_bonus;
} Player;

static int upper_subtotal(const Player *player) {
    int total = 0;
    for (int i = 0; i < 6; i++) if (player->scores[i] >= 0) total += player->scores[i];
    return total;
}

static int upper_bonus(const Player *player) { return upper_subtotal(player) >= 63 ? 35 : 0; }

static int player_total(const Player *player) {
    int total = player->yahtzee_bonus + upper_bonus(player);
    for (int i = 0; i < CATEGORIES; i++) if (player->scores[i] >= 0) total += player->scores[i];
    return total;
}

static int player_round(const Player *player) {
    int round = 1;
    for (int i = 0; i < CATEGORIES; i++) round += player->scores[i] >= 0;
    return round;
}

typedef struct { int points[CATEGORIES], allowed, best, yahtzee_face; bool joker; } Candidates;

static Candidates evaluate(const Player *player, const int counts[FACES], JokerRule rule) {
    Candidates result = {.best = -1, .yahtzee_face = -1};
    for (int i = 0; i < FACES; i++) if (counts[i] == 5) result.yahtzee_face = i;
    for (int c = 0; c < CATEGORIES; c++) if (player->scores[c] < 0) result.allowed |= 1 << c;
    result.joker = rule != OFF && result.yahtzee_face >= 0 && player->scores[11] >= 0;
    if (result.joker && rule == FORCED) {
        int upper = 1 << result.yahtzee_face;
        if (result.allowed & upper) result.allowed = upper;
        else if (result.allowed & 0x1fc0) result.allowed &= 0x1fc0;
    }
    for (int c = 0; c < CATEGORIES; c++) {
        int points = player->scores[c] >= 0 ? -1 : !(result.allowed & (1 << c)) ? 0
            : result.joker && c >= 8 && c <= 10 ? c == 8 ? 25 : c == 9 ? 30 : 40 : normal_score(c, counts);
        result.points[c] = points;
        if (points >= 0 && (result.best < 0 || points > result.points[result.best])) result.best = c;
    }
    return result;
}

typedef struct { int code, weight; } Outcome;
static Outcome outcomes[6][252];
static int outcome_count[6];

static void make_outcomes(int size, int face, int remaining, int code, int divisor) {
    if (face == FACES) {
        if (!remaining) outcomes[size][outcome_count[size]++] = (Outcome){code, factorial[size] / divisor};
        return;
    }
    for (int n = 0; n <= remaining; n++) make_outcomes(size, face + 1, remaining - n, code + n * powers[face], divisor * factorial[n]);
}

typedef struct {
    int seat, rolls, faces[DICE], hold;
    bool finished;
} Turn;

typedef struct { Turn before; int category, points, bonus; bool joker; } ScoreEntry;
typedef struct { Turn after; ScoreEntry entry; } RedoEntry;

typedef struct {
    Player players[MAX_PLAYERS];
    int player_count, max_rolls;
    JokerRule joker;
    int64_t random_state, face_counts[FACES];
    int loaded[8000], loaded_head, loaded_tail;
    ScoreEntry entries[MAX_ENTRIES];
    int entry_count;
    RedoEntry redo[MAX_ENTRIES];
    int redo_count;
    Turn turn;
    bool verbose;
} Game;

static Game *new_game(int64_t seed, int count, char *const *names, int rolls, JokerRule joker, bool verbose) {
    Game *game = calloc(1, sizeof *game);
    if (!game) exit(EXIT_FAILURE);
    game->player_count = count;
    game->random_state = seed;
    game->max_rolls = rolls;
    game->joker = joker;
    game->verbose = verbose;
    for (int i = 0; i < count; i++) {
        strcpy(game->players[i].name, names[i]);
        for (int c = 0; c < CATEGORIES; c++) game->players[i].scores[c] = -1;
    }
    return game;
}

static bool check_game(const Game *game) { return game ? true : fail("no game"); }

static bool check_turn(const Game *game) {
    if (!check_game(game)) return false;
    return !game->turn.finished || fail("game over");
}

static bool check_rolled(const Game *game) {
    if (!check_turn(game)) return false;
    return game->turn.rolls != 0 || fail("not rolled");
}

static bool check_rolls_left(const Game *game) {
    if (!check_rolled(game)) return false;
    return game->turn.rolls < game->max_rolls || fail("no rolls left");
}

static bool roll(Game *game) {
    if (!check_turn(game)) return false;
    Turn *turn = &game->turn;
    if (turn->rolls == game->max_rolls) return fail("no rolls left");
    if (turn->hold == 31) return fail("all dice held");
    game->redo_count = 0;
    for (int i = 0; i < DICE; i++) {
        if (turn->rolls && held(turn->hold, i)) continue;
        if (game->loaded_head < game->loaded_tail) turn->faces[i] = game->loaded[game->loaded_head++];
        else {
            game->random_state = 48271 * game->random_state % 2147483647;
            turn->faces[i] = (int)(game->random_state % 6) + 1;
        }
        game->face_counts[turn->faces[i] - 1]++;
    }
    turn->rolls++;
    if (game->verbose) printf("%s roll %d: %s\n", game->players[turn->seat].name, turn->rolls, face_text(turn->faces, 31).text);
    return true;
}

static bool hold(Game *game, int mask) {
    if (!check_rolls_left(game)) return false;
    game->redo_count = 0;
    game->turn.hold = mask;
    if (game->verbose) printf("%s holds %s: %s\n", game->players[game->turn.seat].name, pattern_text(mask).text, face_text(game->turn.faces, mask).text);
    return true;
}

static bool keep(Game *game, const int *values, int count) {
    if (!check_rolls_left(game)) return false;
    int mask = 0;
    for (int j = 0; j < count; j++) {
        int die = -1;
        for (int i = 0; i < DICE; i++) if (!held(mask, i) && game->turn.faces[i] == values[j]) { die = i; break; }
        if (die < 0) return fail("not showing %d", values[j]);
        mask |= 1 << (4 - die);
    }
    return hold(game, mask);
}

static bool score(Game *game, int category, bool preview) {
    if (!check_rolled(game)) return false;
    Player *player = &game->players[game->turn.seat];
    if (player->scores[category] >= 0) return fail("%s already used", categories[category]);
    int counts[FACES];
    face_counts(game->turn.faces, counts);
    Candidates candidates = evaluate(player, counts, game->joker);
    if (!(candidates.allowed & (1 << category))) {
        return fail("joker requires %s", player->scores[candidates.yahtzee_face] < 0 ? categories[candidates.yahtzee_face] : "lower box");
    }
    int points = candidates.points[category];
    int bonus = candidates.yahtzee_face >= 0 && player->scores[11] == 50 ? 100 : 0;
    int upper = upper_subtotal(player);
    int gained_upper = category < 6 && upper < 63 && upper + points >= 63 ? 35 : 0;
    int total = player_total(player) + points + bonus + gained_upper;
    if (game->verbose) {
        printf("%s %s %d in %s", player->name, preview ? "would score" : "scores", points, categories[category]);
        if (candidates.joker) printf(" joker");
        if (bonus) printf(" ybonus 100");
        if (gained_upper) printf(" ubonus 35");
        printf(" total %d\n", total);
    }
    if (preview) return true;
    game->redo_count = 0;
    game->entries[game->entry_count++] = (ScoreEntry){game->turn, category, points, bonus, candidates.joker};
    player->scores[category] = points;
    player->yahtzee_bonus += bonus;
    if (game->entry_count == CATEGORIES * game->player_count) game->turn = (Turn){.finished = true};
    else game->turn = (Turn){.seat = (game->turn.seat + 1) % game->player_count};
    if (game->verbose) {
        if (game->turn.finished) puts("game over");
        else {
            Player *next = &game->players[game->turn.seat];
            printf("turn %d %s\n", player_round(next), next->name);
        }
    }
    return true;
}

static bool undo(Game *game) {
    if (!check_game(game)) return false;
    if (!game->entry_count) return fail("nothing to undo");
    ScoreEntry entry = game->entries[--game->entry_count];
    game->redo[game->redo_count++] = (RedoEntry){game->turn, entry};
    Player *player = &game->players[entry.before.seat];
    player->scores[entry.category] = -1;
    player->yahtzee_bonus -= entry.bonus;
    game->turn = entry.before;
    printf("undo %s %s %d\n", player->name, categories[entry.category], entry.points);
    return true;
}

static bool redo(Game *game) {
    if (!check_game(game)) return false;
    if (!game->redo_count) return fail("nothing to redo");
    RedoEntry saved = game->redo[--game->redo_count];
    ScoreEntry entry = saved.entry;
    Player *player = &game->players[entry.before.seat];
    player->scores[entry.category] = entry.points;
    player->yahtzee_bonus += entry.bonus;
    game->entries[game->entry_count++] = entry;
    game->turn = saved.after;
    printf("redo %s %s %d\n", player->name, categories[entry.category], entry.points);
    return true;
}

static int bot_hold(const Game *game, Strategy strategy) {
    const int *faces = game->turn.faces;
    int counts[FACES];
    face_counts(faces, counts);
    int favorite = frequent(counts), mask = 0;
    if (strategy == STRAIGHT) {
        int best_start = 0, best_length = 0;
        for (int start = 0; start < FACES; start++) {
            int end = start;
            while (end < FACES && counts[end]) end++;
            if (end - start >= best_length) { best_start = start; best_length = end - start; }
        }
        if (best_length >= 3) {
            for (int face = best_start + 1; face <= best_start + best_length; face++) {
                for (int i = 0; i < DICE; i++) if (faces[i] == face) { mask |= 1 << (4 - i); break; }
            }
            return mask;
        }
    }
    for (int i = 0; i < DICE; i++) if (strategy == HIGH ? faces[i] >= 5 : faces[i] == favorite + 1) mask |= 1 << (4 - i);
    return mask;
}

static void bot_turn(Game *game) {
    Player *player = &game->players[game->turn.seat];
    Strategy strategy = player->strategy;
    if (!game->turn.rolls) roll(game);
    while (game->turn.rolls < game->max_rolls) {
        int mask = bot_hold(game, strategy);
        if (mask == 31) break;
        hold(game, mask);
        roll(game);
    }
    int counts[FACES];
    face_counts(game->turn.faces, counts);
    Candidates candidates = evaluate(player, counts, game->joker);
    int favorite = frequent(counts);
    int category = strategy == UPPER && counts[favorite] >= 3 && (candidates.allowed & (1 << favorite)) ? favorite : candidates.best;
    score(game, category, false);
}

static void ranking(const Game *game, int order[MAX_PLAYERS]) {
    for (int i = 0; i < game->player_count; i++) {
        int j = i;
        while (j > 0 && player_total(&game->players[i]) > player_total(&game->players[order[j - 1]])) { order[j] = order[j - 1]; j--; }
        order[j] = i;
    }
}

typedef struct {
    const Player *player;
    JokerRule joker;
    /* Values at depth j are scaled by 7776^j to keep comparisons exact. */
    int64_t values[4][CODES], expectations[4][CODES];
} Adviser;

static int64_t expected(Adviser *adviser, int code, int depth);

static void search_holds(Adviser *adviser, const int counts[FACES], int face, int code, int depth, int64_t *best) {
    if (face == FACES) {
        int64_t value = expected(adviser, code, depth);
        if (value > *best) *best = value;
        return;
    }
    for (int n = 0; n <= counts[face]; n++) search_holds(adviser, counts, face + 1, code + n * powers[face], depth, best);
}

static int64_t advise_value(Adviser *adviser, int code, int depth) {
    int64_t *memo = &adviser->values[depth][code];
    if (*memo >= 0) return *memo;
    int counts[FACES];
    decode(code, counts);
    if (!depth) {
        Candidates candidates = evaluate(adviser->player, counts, adviser->joker);
        *memo = candidates.points[candidates.best];
    } else {
        int64_t best = -1;
        search_holds(adviser, counts, 0, 0, depth, &best);
        *memo = best;
    }
    return *memo;
}

static int64_t expected(Adviser *adviser, int code, int depth) {
    int64_t *memo = &adviser->expectations[depth][code];
    if (*memo >= 0) return *memo;
    int counts[FACES], rerolled = DICE;
    decode(code, counts);
    for (int i = 0; i < FACES; i++) rerolled -= counts[i];
    int64_t sum = 0;
    for (int i = 0; i < outcome_count[rerolled]; i++) {
        Outcome outcome = outcomes[rerolled][i];
        sum += outcome.weight * advise_value(adviser, code + outcome.code, depth - 1);
    }
    *memo = sum * powers[DICE - rerolled];
    return *memo;
}

static bool advise(Game *game) {
    if (!check_rolls_left(game)) return false;
    Adviser *adviser = malloc(sizeof *adviser);
    if (!adviser) exit(EXIT_FAILURE);
    adviser->player = &game->players[game->turn.seat];
    adviser->joker = game->joker;
    for (int depth = 0; depth < 4; depth++) for (int code = 0; code < CODES; code++) {
        adviser->values[depth][code] = adviser->expectations[depth][code] = -1;
    }
    int depth = game->max_rolls - game->turn.rolls, chosen = 0;
    int64_t best = -1, denominator = 1;
    for (int i = 0; i < depth; i++) denominator *= 7776;
    for (int mask = 0; mask < 32; mask++) {
        int64_t value = expected(adviser, held_code(game->turn.faces, mask), depth);
        if (value > best) { best = value; chosen = mask; }
    }
    printf("advise %s: %s expect %s\n", pattern_text(chosen).text, face_text(game->turn.faces, chosen).text, fraction(best, denominator).text);
    free(adviser);
    return true;
}

static bool odds(Game *game, int mask) {
    if (!check_rolls_left(game)) return false;
    int code = held_code(game->turn.faces, mask), counts[FACES], rerolled = DICE;
    decode(code, counts);
    for (int i = 0; i < FACES; i++) rerolled -= counts[i];
    int64_t sums[CATEGORIES] = {0}, chances[CATEGORIES] = {0}, best = 0;
    Player *player = &game->players[game->turn.seat];
    for (int i = 0; i < outcome_count[rerolled]; i++) {
        Outcome outcome = outcomes[rerolled][i];
        decode(code + outcome.code, counts);
        Candidates candidates = evaluate(player, counts, game->joker);
        for (int c = 0; c < CATEGORIES; c++) if (candidates.points[c] >= 0) {
            sums[c] += outcome.weight * candidates.points[c];
            if (candidates.points[c] > 0) chances[c] += outcome.weight;
        }
        best += outcome.weight * candidates.points[candidates.best];
    }
    printf("odds %s outcomes %d\n", pattern_text(mask).text, powers[rerolled]);
    for (int c = 0; c < CATEGORIES; c++) if (player->scores[c] < 0) {
        printf("%s expect %s chance %s\n", categories[c], fraction(sums[c], powers[rerolled]).text, fraction(chances[c], powers[rerolled]).text);
    }
    printf("best expect %s\n", fraction(best, powers[rerolled]).text);
    return true;
}

static void card_row(const Game *game, const char *heading, int row) {
    printf("%-9s", heading);
    for (int i = 0; i < game->player_count; i++) {
        const Player *player = &game->players[i];
        char cell[32];
        if (row < 0) strcpy(cell, player->name);
        else if (row < CATEGORIES && player->scores[row] < 0) strcpy(cell, "-");
        else {
            int value = row < CATEGORIES ? player->scores[row] : row == 13 ? upper_subtotal(player)
                : row == 14 ? upper_bonus(player) : row == 15 ? player->yahtzee_bonus : player_total(player);
            snprintf(cell, sizeof cell, "%d", value);
        }
        int width = (int)strlen(player->name);
        if (width < 4) width = 4;
        printf(" %*s", width, cell);
    }
    putchar('\n');
}

typedef struct { char name[9]; int games, wins, best; int64_t sum; } Record;
typedef struct {
    Game *game;
    int rolls;
    JokerRule joker;
    Record records[2400];
    int record_count;
} Table;

static Record *record_for(Table *table, const char *name) {
    for (int i = 0; i < table->record_count; i++) if (strcmp(table->records[i].name, name) == 0) return &table->records[i];
    Record *record = &table->records[table->record_count++];
    *record = (Record){0};
    strcpy(record->name, name);
    return record;
}

static int compare_records(const void *left, const void *right) {
    const Record *a = *(const Record *const *)left, *b = *(const Record *const *)right;
    if (a->wins != b->wins) return a->wins > b->wins ? -1 : 1;
    if (a->best != b->best) return a->best > b->best ? -1 : 1;
    return strcmp(a->name, b->name);
}

static bool positive(const char *word, int64_t maximum, int64_t *result) {
    if (word[0] < '1' || word[0] > '9') return fail("bad value %s", word);
    for (const char *p = word; *p; p++) if (*p < '0' || *p > '9') return fail("bad value %s", word);
    int64_t value = strtoll(word, NULL, 10);
    if (value > maximum) return fail("bad value %s", word);
    *result = value;
    return true;
}

static bool valid_name(const char *word) {
    if (strlen(word) > 8) return fail("bad name %s", word);
    for (const char *p = word; *p; p++) if (*p < 'A' || *p > 'Z') return fail("bad name %s", word);
    return true;
}

static bool parse_pattern(const char *word, int *result) {
    if (strlen(word) != DICE) return fail("bad pattern %s", word);
    int mask = 0;
    for (int i = 0; i < DICE; i++) {
        if (word[i] != '0' && word[i] != '1') return fail("bad pattern %s", word);
        mask = mask * 2 + word[i] - '0';
    }
    *result = mask;
    return true;
}

static int category_index(const char *word) {
    for (int i = 0; i < CATEGORIES; i++) if (strcmp(categories[i], word) == 0) return i;
    return -1;
}

static bool parse_strategy(const char *word, Strategy *result) {
    for (int i = 0; i < 4; i++) if (strcmp(strategies[i], word) == 0) { *result = (Strategy)i; return true; }
    return fail("bad strategy %s", word);
}

static void simulate(const Table *table, int64_t seed, int count, const Strategy *bots, int players) {
    int wins[MAX_PLAYERS] = {0}, best[MAX_PLAYERS] = {0}, bonus[MAX_PLAYERS] = {0}, yahtzee[MAX_PLAYERS] = {0};
    int64_t sums[MAX_PLAYERS] = {0}, state = seed;
    char *names[] = {"A", "B", "C", "D", "E", "F"};
    for (int n = 0; n < count; n++) {
        Game *game = new_game(state, players, names, table->rolls, table->joker, false);
        for (int i = 0; i < players; i++) game->players[i].strategy = bots[i];
        while (!game->turn.finished) bot_turn(game);
        state = game->random_state;
        int order[MAX_PLAYERS];
        ranking(game, order);
        wins[order[0]]++;
        for (int i = 0; i < players; i++) {
            Player *player = &game->players[i];
            int total = player_total(player);
            sums[i] += total;
            if (total > best[i]) best[i] = total;
            bonus[i] += upper_bonus(player) == 35;
            yahtzee[i] += player->scores[11] == 50;
        }
        free(game);
    }
    printf("sim seed %" PRId64 " games %d players %d\n", seed, count, players);
    for (int i = 0; i < players; i++) printf("seat %d %s wins %d average %s best %d bonus %d yahtzee %d\n",
        i + 1, strategies[bots[i]], wins[i], average(sums[i], count).text, best[i], bonus[i], yahtzee[i]);
}

static bool execute(Table *table, char **words, int count) {
    const char *command = words[0];
    Game *game = table->game;
    if (strcmp(command, "RULE") == 0) {
        if (strcmp(words[1], "ROLLS") != 0 && strcmp(words[1], "JOKER") != 0) return fail("unknown rule %s", words[1]);
        int rolls = table->rolls;
        JokerRule joker = table->joker;
        if (strcmp(words[1], "ROLLS") == 0) {
            int64_t value;
            if (!positive(words[2], 4, &value)) return false;
            rolls = (int)value;
        } else if (strcmp(words[2], "FORCED") == 0) joker = FORCED;
        else if (strcmp(words[2], "FREE") == 0) joker = FREE;
        else if (strcmp(words[2], "OFF") == 0) joker = OFF;
        else return fail("bad value %s", words[2]);
        if (game) return fail("game in progress");
        table->rolls = rolls;
        table->joker = joker;
        printf("rule %s %s\n", words[1], words[2]);
    } else if (strcmp(command, "GAME") == 0) {
        int64_t seed;
        if (!positive(words[1], 2147483646, &seed)) return false;
        for (int i = 2; i < count; i++) if (!valid_name(words[i])) return false;
        if (count - 2 > MAX_PLAYERS) return fail("too many players");
        if (game) return fail("game in progress");
        for (int i = 2; i < count; i++) for (int j = 2; j < i; j++) if (strcmp(words[i], words[j]) == 0) return fail("duplicate name %s", words[i]);
        table->game = new_game(seed, count - 2, words + 2, table->rolls, table->joker, true);
        printf("game seed %" PRId64 " players", seed);
        for (int i = 2; i < count; i++) printf(" %s", words[i]);
        printf("\nturn 1 %s\n", words[2]);
    } else if (strcmp(command, "BOT") == 0) {
        if (!valid_name(words[1])) return false;
        Strategy strategy;
        if (!parse_strategy(words[2], &strategy) || !check_game(game)) return false;
        int player = -1;
        for (int i = 0; i < game->player_count; i++) if (strcmp(game->players[i].name, words[1]) == 0) { player = i; break; }
        if (player < 0) return fail("no player %s", words[1]);
        game->players[player].strategy = strategy;
        printf("bot %s %s\n", words[1], words[2]);
    } else if (strcmp(command, "LOAD") == 0 || strcmp(command, "KEEP") == 0) {
        int values[20];
        for (int i = 1; i < count; i++) {
            int64_t value;
            if (!positive(words[i], 6, &value)) return false;
            values[i - 1] = (int)value;
        }
        if (!check_game(game)) return false;
        if (strcmp(command, "KEEP") == 0) return keep(game, values, count - 1);
        for (int i = 0; i < count - 1; i++) game->loaded[game->loaded_tail++] = values[i];
        printf("loaded %d\n", game->loaded_tail - game->loaded_head);
    } else if (strcmp(command, "ROLL") == 0) return roll(game);
    else if (strcmp(command, "HOLD") == 0 || strcmp(command, "ODDS") == 0) {
        int mask;
        if (!parse_pattern(words[1], &mask)) return false;
        return strcmp(command, "HOLD") == 0 ? hold(game, mask) : odds(game, mask);
    } else if (strcmp(command, "SCORE") == 0 || strcmp(command, "WHATIF") == 0) {
        int category = category_index(words[1]);
        if (category < 0) return fail("bad category %s", words[1]);
        return score(game, category, strcmp(command, "WHATIF") == 0);
    } else if (strcmp(command, "UNDO") == 0) return undo(game);
    else if (strcmp(command, "REDO") == 0) return redo(game);
    else if (strcmp(command, "SUGGEST") == 0) {
        if (!check_rolled(game)) return false;
        int counts[FACES];
        face_counts(game->turn.faces, counts);
        Candidates candidates = evaluate(&game->players[game->turn.seat], counts, game->joker);
        printf("suggest");
        for (int c = 0; c < CATEGORIES; c++) if (candidates.points[c] >= 0) printf(" %s %d", categories[c], candidates.points[c]);
        printf(" best %s %d\n", categories[candidates.best], candidates.points[candidates.best]);
    } else if (strcmp(command, "ADVISE") == 0) return advise(game);
    else if (strcmp(command, "AUTO") == 0) {
        int64_t turns;
        if (!positive(words[1], 100, &turns) || !check_turn(game)) return false;
        game->redo_count = 0;
        for (int i = 0; i < turns && !game->turn.finished; i++) bot_turn(game);
    } else if (strcmp(command, "STATUS") == 0) {
        if (!check_game(game)) return false;
        if (game->turn.finished) puts("status game over");
        else {
            Player *player = &game->players[game->turn.seat];
            printf("status round %d player %s rolls %d dice %s holds %s\n", player_round(player), player->name, game->turn.rolls,
                   face_text(game->turn.rolls ? game->turn.faces : NULL, 31).text, pattern_text(game->turn.hold).text);
        }
    } else if (strcmp(command, "CARD") == 0) {
        if (!check_game(game)) return false;
        card_row(game, "CATEGORY", -1);
        for (int c = 0; c < CATEGORIES; c++) card_row(game, categories[c], c);
        card_row(game, "UPPER", 13);
        card_row(game, "BONUS", 14);
        card_row(game, "YBONUS", 15);
        card_row(game, "TOTAL", 16);
    } else if (strcmp(command, "BONUS") == 0) {
        if (!check_game(game)) return false;
        for (int i = 0; i < game->player_count; i++) {
            Player *player = &game->players[i];
            int upper = upper_subtotal(player), maximum = upper;
            for (int c = 0; c < 6; c++) if (player->scores[c] < 0) maximum += 5 * (c + 1);
            printf("bonus %s upper %d need %d max %d %s\n", player->name, upper, upper < 63 ? 63 - upper : 0,
                   maximum, upper >= 63 ? "made" : maximum < 63 ? "lost" : "open");
        }
    } else if (strcmp(command, "STATS") == 0) {
        if (!check_game(game)) return false;
        for (int i = 0; i < game->player_count; i++) {
            int turns = 0, rolls = 0, zeros = 0, yahtzees = 0, sum = 0;
            for (int j = 0; j < game->entry_count; j++) {
                ScoreEntry *entry = &game->entries[j];
                if (entry->before.seat != i) continue;
                turns++;
                rolls += entry->before.rolls;
                zeros += entry->points == 0;
                sum += entry->points;
                int counts[FACES];
                face_counts(entry->before.faces, counts);
                yahtzees += counts[frequent(counts)] == 5;
            }
            printf("stats %s turns %d rolls %d zeros %d yahtzees %d average %s\n", game->players[i].name, turns, rolls, zeros, yahtzees, average(sum, turns).text);
        }
    } else if (strcmp(command, "LOG") == 0) {
        if (!check_game(game)) return false;
        for (int i = 0; i < game->entry_count; i++) {
            ScoreEntry *entry = &game->entries[i];
            printf("log %d %s %s %s %d", i + 1, game->players[entry->before.seat].name, face_text(entry->before.faces, 31).text,
                   categories[entry->category], entry->points);
            if (entry->joker) printf(" joker");
            if (entry->bonus) printf(" ybonus 100");
            putchar('\n');
        }
        if (!game->entry_count) puts("no scores");
    } else if (strcmp(command, "FACES") == 0) {
        if (!check_game(game)) return false;
        int64_t total = 0, squares = 0;
        printf("faces");
        for (int i = 0; i < FACES; i++) {
            int64_t count = game->face_counts[i];
            total += count;
            squares += count * count;
            printf(" %" PRId64, count);
        }
        printf(" total %" PRId64 " chi2 %s\n", total, fraction(6 * squares - total * total, total ? total : 1).text);
    } else if (strcmp(command, "STANDINGS") == 0 || strcmp(command, "END") == 0) {
        if (!check_game(game)) return false;
        int order[MAX_PLAYERS];
        ranking(game, order);
        bool end = strcmp(command, "END") == 0;
        if (end) puts(game->turn.finished ? "end final" : "end abandoned");
        int leader = player_total(&game->players[order[0]]);
        for (int i = 0; i < game->player_count; i++) {
            Player *player = &game->players[order[i]];
            int total = player_total(player);
            if (!end) printf("standing %d %s %d behind %d\n", i + 1, player->name, total, leader - total);
            else {
                printf("rank %d %s %d\n", i + 1, player->name, total);
                if (game->turn.finished) {
                    Record *record = record_for(table, player->name);
                    record->games++;
                    record->wins += i == 0;
                    record->sum += total;
                    if (total > record->best) record->best = total;
                }
            }
        }
        if (end) { free(game); table->game = NULL; }
    } else if (strcmp(command, "RECORDS") == 0) {
        Record *order[2400];
        for (int i = 0; i < table->record_count; i++) order[i] = &table->records[i];
        qsort(order, table->record_count, sizeof *order, compare_records);
        for (int i = 0; i < table->record_count; i++) {
            Record *record = order[i];
            printf("record %s games %d wins %d best %d average %s\n", record->name, record->games, record->wins,
                   record->best, average(record->sum, record->games).text);
        }
        if (!table->record_count) puts("no records");
    } else if (strcmp(command, "SIM") == 0) {
        int64_t seed, games;
        if (!positive(words[1], 2147483646, &seed) || !positive(words[2], 50, &games)) return false;
        Strategy bots[8];
        for (int i = 3; i < count; i++) if (!parse_strategy(words[i], &bots[i - 3])) return false;
        if (count - 3 > MAX_PLAYERS) return fail("too many players");
        simulate(table, seed, (int)games, bots, count - 3);
    } else return fail("unknown command %s", command);
    return true;
}

int main(void) {
    for (int size = 0; size <= DICE; size++) make_outcomes(size, 0, size, 0, 1);
    Table *table = calloc(1, sizeof *table);
    if (!table) return EXIT_FAILURE;
    table->rolls = 3;
    char line[512];
    if (!fgets(line, sizeof line, stdin)) { free(table); return 0; }
    int commands = atoi(line);
    for (int i = 0; i < commands && fgets(line, sizeof line, stdin); i++) {
        char *words[24];
        int count = 0;
        for (char *word = strtok(line, " \r\n"); word; word = strtok(NULL, " \r\n")) words[count++] = word;
        if (!execute(table, words, count)) printf("error: %s\n", error_message);
    }
    free(table->game);
    free(table);
    return 0;
}
