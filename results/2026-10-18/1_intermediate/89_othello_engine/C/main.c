#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <ctype.h>

static const int weights[64] = {
    100,-20,10,5,5,10,-20,100,
    -20,-50,-2,-2,-2,-2,-50,-20,
    10,-2,-1,-1,-1,-1,-2,10,
    5,-2,-1,-1,-1,-1,-2,5,
    5,-2,-1,-1,-1,-1,-2,5,
    10,-2,-1,-1,-1,-1,-2,10,
    -20,-50,-2,-2,-2,-2,-50,-20,
    100,-20,10,5,5,10,-20,100
};

typedef struct {
    char board[65];
    char side;
    bool over;
} Position;

typedef struct {
    char side;
    int square;
    int flipped;
    bool passed;
    Position before;
    Position after;
} Move;

typedef struct {
    Position pos;
    Move history[64];
    Move redo[64];
    int nh;
    int nr;
} Game;

typedef struct {
    int p;
    int value;
} Ranking;

typedef struct {
    uint64_t state;
} Random;

static char other(char side) {
    return side == 'B' ? 'W' : 'B';
}

static void initialize(Game *g) {
    memset(g, 0, sizeof(*g));
    memset(g->pos.board, '.', 64);
    g->pos.board[64] = '\0';
    g->pos.board[27] = g->pos.board[36] = 'W';
    g->pos.board[28] = g->pos.board[35] = 'B';
    g->pos.side = 'B';
}

static bool inside(int r, int c) {
    return r >= 0 && r < 8 && c >= 0 && c < 8;
}

static void square_name(int p, char dest[3]) {
    dest[0] = (char)('a' + p % 8);
    dest[1] = (char)('1' + p / 8);
    dest[2] = '\0';
}

static int square_number(const char *s) {
    return 8 * (s[1] - '1') + s[0] - 'a';
}

static int compare_int(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}

static int flips(const char *board, char side, int p, int result[64]) {
    if (board[p] != '.') return 0;
    int n = 0, row = p / 8, col = p % 8;
    for (int dr = -1; dr <= 1; ++dr) {
        for (int dc = -1; dc <= 1; ++dc) {
            if (dr == 0 && dc == 0) continue;
            int r = row + dr, c = col + dc, path[8], count = 0;
            while (inside(r, c) && board[8 * r + c] == other(side)) {
                path[count++] = 8 * r + c;
                r += dr;
                c += dc;
            }
            if (count != 0 && inside(r, c) && board[8 * r + c] == side) {
                for (int i = 0; i < count; ++i) result[n++] = path[i];
            }
        }
    }
    qsort(result, (size_t)n, sizeof(int), compare_int);
    return n;
}

static int legal(const char *board, char side, int result[64]) {
    int count = 0, temporary[64];
    for (int p = 0; p < 64; ++p) {
        if (board[p] == '.' && flips(board, side, p, temporary) > 0) {
            result[count++] = p;
        }
    }
    return count;
}

static void place(const char *board, char side, int p, char dest[65]) {
    memcpy(dest, board, 65);
    int chosen[64], n = flips(board, side, p, chosen);
    dest[p] = side;
    for (int i = 0; i < n; ++i) dest[chosen[i]] = side;
}

static int disc_count(const char *board, char value) {
    int result = 0;
    for (int i = 0; i < 64; ++i) result += board[i] == value;
    return result;
}

static bool terminal(const char *board) {
    int moves[64];
    return legal(board, 'B', moves) == 0 && legal(board, 'W', moves) == 0;
}

static void game_over(const char *board, char line[100]) {
    int b = disc_count(board, 'B'), w = disc_count(board, 'W');
    sprintf(line, "game over B %d W %d %s", b, w,
        b > w ? "winner B" : b < w ? "winner W" : "draw");
}

static void status(const Game *g, char line[100]) {
    if (g->pos.over) game_over(g->pos.board, line);
    else sprintf(line, "%c to move", g->pos.side);
}

static int evaluate(const char *board, char side, int values[4]) {
    int weight = 0, moves[64];
    for (int p = 0; p < 64; ++p) {
        if (board[p] == side) weight += weights[p];
        else if (board[p] == other(side)) weight -= weights[p];
    }
    int own = legal(board, side, moves);
    int enemy = legal(board, other(side), moves);
    values[0] = weight + 10 * (own - enemy);
    values[1] = weight;
    values[2] = own;
    values[3] = enemy;
    return values[0];
}

static int search(const char *board, char side, int depth) {
    int moves[64], enemy[64], count = legal(board, side, moves);
    char opposite = other(side);
    if (!count && !legal(board, opposite, enemy)) {
        return (depth < 0 ? 1 : 1000) * (disc_count(board, side) - disc_count(board, opposite));
    }
    if (!depth) {
        int values[4];
        return evaluate(board, side, values);
    }
    if (!count) return -search(board, opposite, depth < 0 ? -1 : depth - 1);
    int best = -10000000;
    for (int i = 0; i < count; ++i) {
        char next[65];
        place(board, side, moves[i], next);
        int value = -search(next, opposite, depth < 0 ? -1 : depth - 1);
        if (value > best) best = value;
    }
    return best;
}

static int compare_ranking(const void *a, const void *b) {
    const Ranking *x = a, *y = b;
    if (x->value != y->value) return (x->value < y->value) - (x->value > y->value);
    return (x->p > y->p) - (x->p < y->p);
}

static int ranked(const char *board, char side, int depth, Ranking result[64]) {
    int moves[64], n = legal(board, side, moves);
    for (int i = 0; i < n; ++i) {
        char next[65];
        place(board, side, moves[i], next);
        result[i] = (Ranking){moves[i], -search(next, other(side), depth < 0 ? -1 : depth - 1)};
    }
    qsort(result, (size_t)n, sizeof(Ranking), compare_ranking);
    return n;
}

static void variation(const char *board, char side, int depth, char path[256], char final[65]) {
    memcpy(final, board, 65);
    path[0] = '\0';
    while (depth != 0 && !terminal(final)) {
        Ranking choices[64];
        int n = ranked(final, side, depth, choices);
        char word[8];
        if (n) {
            square_name(choices[0].p, word);
            char next[65];
            place(final, side, choices[0].p, next);
            memcpy(final, next, 65);
        } else {
            strcpy(word, "pass");
        }
        if (path[0] != '\0') strcat(path, " ");
        strcat(path, word);
        side = other(side);
        if (depth > 0) --depth;
    }
}

static uint64_t perft(const char *board, char side, int depth) {
    if (depth == 0) return 1;
    int moves[64], other_moves[64], n = legal(board, side, moves);
    char opponent = other(side);
    if (!n) {
        return legal(board, opponent, other_moves) == 0 ? 1 : perft(board, opponent, depth - 1);
    }
    uint64_t count = 0;
    for (int i = 0; i < n; ++i) {
        char next[65];
        place(board, side, moves[i], next);
        count += perft(next, opponent, depth - 1);
    }
    return count;
}

static void stable(const char *board, int result[2]) {
    bool set[64] = {false};
    const int dr[4] = {0,1,1,1};
    const int dc[4] = {1,0,1,-1};
    while (true) {
        int found[64], n = 0;
        for (int p = 0; p < 64; ++p) {
            if (board[p] == '.' || set[p]) continue;
            bool valid = true;
            for (int axis = 0; axis < 4; ++axis) {
                bool full = true, anchor = false;
                for (int sign = -1; sign <= 1; sign += 2) {
                    int r = p / 8 + dr[axis] * sign;
                    int c = p % 8 + dc[axis] * sign;
                    if (!inside(r, c) || (set[8*r+c] && board[8*r+c] == board[p])) anchor = true;
                    while (inside(r, c)) {
                        if (board[8*r+c] == '.') full = false;
                        r += dr[axis] * sign;
                        c += dc[axis] * sign;
                    }
                }
                if (!full && !anchor) {
                    valid = false;
                    break;
                }
            }
            if (valid) found[n++] = p;
        }
        if (!n) break;
        for (int i = 0; i < n; ++i) set[found[i]] = true;
    }
    result[0] = result[1] = 0;
    for (int p = 0; p < 64; ++p) {
        if (set[p] && board[p] == 'B') ++result[0];
        if (set[p] && board[p] == 'W') ++result[1];
    }
}

static int transform_square(int p, const char *op) {
    int r = p / 8, c = p % 8;
    if (!strcmp(op, "rot90")) return 8*c + 7-r;
    if (!strcmp(op, "rot180")) return 63-p;
    if (!strcmp(op, "rot270")) return 8*(7-c) + r;
    if (!strcmp(op, "mirror")) return 8*r + 7-c;
    if (!strcmp(op, "flip")) return 8*(7-r) + c;
    if (!strcmp(op, "diag")) return 8*c + r;
    return 8*(7-c) + 7-r;
}

static void transform_board(const char *board, const char *op, char result[65]) {
    memset(result, '.', 64);
    result[64] = '\0';
    for (int p = 0; p < 64; ++p) {
        result[transform_square(p, op)] = board[p];
    }
}

static uint64_t draw(Random *random) {
    random->state = random->state * 48271 % 2147483647;
    return random->state;
}

static void random_game(const char *board, char side, Random *random, char result[65]) {
    memcpy(result, board, 65);
    while (true) {
        int moves[64], enemy[64], n = legal(result, side, moves);
        if (n) {
            char next[65];
            place(result, side, moves[draw(random) % (uint64_t)n], next);
            memcpy(result, next, 65);
        } else if (!legal(result, other(side), enemy)) {
            return;
        }
        side = other(side);
    }
}

static bool adjust(Game *g, bool quiet) {
    int moves[64];
    if (legal(g->pos.board, g->pos.side, moves)) return false;
    if (legal(g->pos.board, other(g->pos.side), moves)) {
        if (!quiet) printf("%c passes\n", g->pos.side);
        g->pos.side = other(g->pos.side);
        return true;
    }
    g->pos.over = true;
    if (!quiet) {
        char line[100];
        game_over(g->pos.board, line);
        puts(line);
    }
    return false;
}

static bool play(Game *g, int p, bool quiet, bool have_value, int value) {
    Position before = g->pos;
    char side = g->pos.side;
    int flipped[64], n = flips(before.board, side, p, flipped);
    char board[65];
    place(before.board, side, p, board);
    memcpy(g->pos.board, board, 65);
    if (!quiet) {
        char sq[3];
        square_name(p, sq);
        if (have_value) printf("%c %s flips %d value %d\n", side, sq, n, value);
        else printf("%c %s flips %d\n", side, sq, n);
    }
    g->pos.side = other(side);
    bool passed = adjust(g, quiet);
    g->history[g->nh++] = (Move){side, p, n, passed, before, g->pos};
    g->nr = 0;
    return passed;
}

static const char *reason(const Game *g, int p) {
    if (g->pos.over) return "game over";
    if (g->pos.board[p] != '.') return "occupied";
    int result[64];
    if (flips(g->pos.board, g->pos.side, p, result) == 0) return "no flips";
    return NULL;
}

static void record(Game *g, const char *text) {
    Game *trial = malloc(sizeof(Game));
    if (!trial) exit(EXIT_FAILURE);
    initialize(trial);
    int positions[60], total = (int)strlen(text) / 2, passes = 0;
    for (int i = 0; i < total; ++i) {
        int p = 8 * (text[2*i+1] - '1') + text[2*i] - 'a';
        const char *why = reason(trial, p);
        if (why) {
            char sq[3];
            square_name(p, sq);
            printf("ILLEGAL move %d %s %s\n", i + 1, sq, why);
            free(trial);
            return;
        }
        positions[i] = p;
        if (play(trial, p, true, false, 0)) ++passes;
    }
    *g = *trial;
    free(trial);
    char first[3];
    square_name(positions[0], first);
    const char *op = !strcmp(first, "e6") ? "diag" :
        !strcmp(first, "d3") ? "anti" :
        !strcmp(first, "c4") ? "rot180" : "";
    char normalized[121];
    for (int i = 0; i < total; ++i) {
        int p = *op ? transform_square(positions[i], op) : positions[i];
        square_name(p, normalized + 2*i);
    }
    normalized[2*total] = '\0';
    printf("record %d moves %d passes\nnormal %s\n", total, passes, normalized);
    char line[100];
    status(g, line);
    puts(line);
}

static void show_sheet(const Game *g) {
    char fields[64][4];
    const char *original = g->nh ? g->history[0].before.board : g->pos.board;
    for (int p = 0; p < 64; ++p) {
        fields[p][0] = original[p];
        fields[p][1] = '\0';
    }
    for (int i = 0; i < g->nh; ++i) {
        snprintf(fields[g->history[i].square], sizeof(fields[0]), "%d", i + 1);
    }
    putchar(' ');
    for (int c = 0; c < 8; ++c) printf("%3c", 'a' + c);
    putchar('\n');
    for (int r = 0; r < 8; ++r) {
        printf("%d", r + 1);
        for (int c = 0; c < 8; ++c) printf("%3s", fields[8*r+c]);
        putchar('\n');
    }
}

static void average(int flipped, int moves, char output[32]) {
    int value = flipped * 100 / moves;
    sprintf(output, "%d.%02d", value / 100, value % 100);
}

static void stats(const Game *g) {
    int total = 0, passes = 0;
    for (int i = 0; i < g->nh; ++i) {
        total += g->history[i].flipped;
        passes += g->history[i].passed;
    }
    if (!g->nh) puts("moves 0");
    else {
        char mean[32];
        average(total, g->nh, mean);
        printf("moves %d flips %d avg %s passes %d\n", g->nh, total, mean, passes);
    }
    for (char side = 'B'; side <= 'W'; side += 'W' - 'B') {
        int moves = 0, sum = 0, maximum = -1, max_square = -1, corners = 0;
        for (int i = 0; i < g->nh; ++i) {
            const Move *m = &g->history[i];
            if (m->side != side) continue;
            ++moves;
            sum += m->flipped;
            if (m->flipped > maximum) {
                maximum = m->flipped;
                max_square = m->square;
            }
            if (m->square == 0 || m->square == 7 || m->square == 56 || m->square == 63) ++corners;
        }
        if (!moves) printf("%c moves 0\n", side);
        else {
            char mean[32], sq[3];
            average(sum, moves, mean);
            square_name(max_square, sq);
            printf("%c moves %d flips %d avg %s max %d %s corners %d\n",
                side, moves, sum, mean, maximum, sq, corners);
        }
    }
}

static void automatic(Game *g, int black, int white, bool random, uint64_t seed) {
    Random rng = {seed};
    int moves = 0, passes = 0;
    char text[121] = "";
    while (!g->pos.over) {
        int p;
        if (random) {
            int choices[64], n = legal(g->pos.board, g->pos.side, choices);
            p = choices[draw(&rng) % (uint64_t)n];
        } else {
            Ranking moveset[64];
            ranked(g->pos.board, g->pos.side, g->pos.side == 'B' ? black : white, moveset);
            p = moveset[0].p;
        }
        char sq[3];
        square_name(p, sq);
        strcat(text, sq);
        if (play(g, p, true, false, 0)) ++passes;
        ++moves;
    }
    printf("%s %d moves %d passes\nmoves %s\n", random ? "random" : "autoplay", moves, passes, text);
    char line[100];
    game_over(g->pos.board, line);
    puts(line);
}

static void monte_carlo(const Game *g, int games, uint64_t seed) {
    Random rng = {seed};
    int positions[64], n = legal(g->pos.board, g->pos.side, positions);
    int best = -1, best_pos = -1;
    for (int i = 0; i < n; ++i) {
        char start[65];
        place(g->pos.board, g->pos.side, positions[i], start);
        int w = 0, d = 0, l = 0;
        for (int j = 0; j < games; ++j) {
            char end[65];
            random_game(start, other(g->pos.side), &rng, end);
            int delta = disc_count(end, g->pos.side) - disc_count(end, other(g->pos.side));
            if (delta > 0) ++w;
            else if (delta == 0) ++d;
            else ++l;
        }
        char sq[3];
        square_name(positions[i], sq);
        printf("%s %d %d %d\n", sq, w, d, l);
        if (2*w + d > best) {
            best = 2*w + d;
            best_pos = positions[i];
        }
    }
    char sq[3];
    square_name(best_pos, sq);
    printf("best %s %d\n", sq, best);
}

static bool among(const char *word, const char *const *choices, size_t n) {
    for (size_t i = 0; i < n; ++i) {
        if (!strcmp(word, choices[i])) return true;
    }
    return false;
}

static bool valid_square(const char *s) {
    return strlen(s) == 2 && s[0] >= 'a' && s[0] <= 'h' && s[1] >= '1' && s[1] <= '8';
}

static bool valid_record(const char *s) {
    size_t len = strlen(s);
    if (len == 0 || len > 120 || len % 2) return false;
    for (size_t i = 0; i < len; i += 2) {
        if (s[i] < 'a' || s[i] > 'h' || s[i+1] < '1' || s[i+1] > '8') return false;
    }
    return true;
}

static bool unsigned_number(const char *s, uint64_t *value) {
    if (!*s) return false;
    for (const char *p = s; *p; ++p) if (!isdigit((unsigned char)*p)) return false;
    *value = strtoull(s, NULL, 10);
    return true;
}

static void execute(Game *g, char *line) {
    static const char *zero[] = {"NEW","DUMP","SHOW","SCORE","LEGAL","HISTORY","SHEET","STATS","EVAL","STABLE","SOLVE"};
    static const char *numeric[] = {"UNDO","REDO","HINT","PV","AI","ANALYZE","RANDOM","PERFT","DIVIDE"};
    static const char *active[] = {"FLIPS","MOVE","PLAY","HINT","PV","AI","SOLVE","AUTOPLAY","RANDOM","MC","DIVIDE"};
    static const char *additional[] = {"LOAD","TRANSFORM","AUTOPLAY","MC","FLIPS","MOVE","PLAY","RECORD"};
    static const char *ops[] = {"rot90","rot180","rot270","mirror","flip","diag","anti"};
    char *parts[210];
    int argc = 0;
    for (char *p = strtok(line, " "); p != NULL; p = strtok(NULL, " ")) {
        parts[argc++] = p;
    }
    if (!argc) return;
    const char *cmd = parts[0];
    char **args = parts + 1;
    int count = argc - 1;
    if (!among(cmd, zero, sizeof(zero)/sizeof(zero[0])) &&
        !among(cmd, numeric, sizeof(numeric)/sizeof(numeric[0])) &&
        !among(cmd, additional, sizeof(additional)/sizeof(additional[0]))) {
        puts("ERROR unknown command");
        return;
    }
    const char *error = NULL;
    uint64_t a = 0, b = 0;
    if (!strcmp(cmd,"LOAD")) {
        if (count != 2 || strlen(args[0]) != 64 ||
            (strcmp(args[1], "B") && strcmp(args[1], "W"))) error = "bad board";
        if (!error) for (int i = 0; i < 64; ++i) {
            if (args[0][i] != 'B' && args[0][i] != 'W' && args[0][i] != '.') error = "bad board";
        }
    } else if (!strcmp(cmd, "MOVE") || !strcmp(cmd, "FLIPS")) {
        if (count != 1) error = "bad arguments";
        else if (!valid_square(args[0])) error = "bad square";
    } else if (!strcmp(cmd, "PLAY") || !strcmp(cmd, "RECORD")) {
        if (count != 1) error = "bad arguments";
        else if (!valid_record(args[0])) error = "bad record";
    } else if (among(cmd, zero, sizeof(zero)/sizeof(zero[0]))) {
        if (count != 0) error = "bad arguments";
    } else if (!strcmp(cmd, "TRANSFORM")) {
        if (count != 1 || !among(args[0], ops, sizeof(ops)/sizeof(ops[0]))) error = "bad arguments";
    } else {
        int expected = !strcmp(cmd,"MC") || !strcmp(cmd,"AUTOPLAY") ? 2 : 1;
        if (count != expected || !unsigned_number(args[0], &a) ||
            (expected == 2 && !unsigned_number(args[1], &b))) error = "bad arguments";
        if (!error) {
            if (!strcmp(cmd, "AUTOPLAY")) {
                if (a < 1 || a > 4 || b < 1 || b > 4) error = "bad arguments";
            } else if (!strcmp(cmd, "HINT") || !strcmp(cmd, "PV") || !strcmp(cmd, "AI") || !strcmp(cmd, "ANALYZE")) {
                if (a < 1 || a > 4) error = "bad arguments";
            } else if (!strcmp(cmd, "PERFT") || !strcmp(cmd, "DIVIDE")) {
                if (a < 1 || a > 8) error = "bad arguments";
            } else if (!strcmp(cmd, "MC")) {
                if (a < 1 || a > 100 || b < 1 || b > 2147483646ULL) error = "bad arguments";
            } else if (!strcmp(cmd, "RANDOM")) {
                if (a < 1 || a > 2147483646ULL) error = "bad arguments";
            } else if (a < 1) error = "bad arguments";
        }
    }
    if (error) {
        printf("ERROR %s\n", error);
        return;
    }
    if (g->pos.over && among(cmd, active, sizeof(active)/sizeof(active[0]))) {
        puts("ERROR game over");
        return;
    }
    int value = (int)a;
    if (!strcmp(cmd, "NEW")) {
        initialize(g);
        puts("OK");
    } else if (!strcmp(cmd, "LOAD")) {
        memcpy(g->pos.board, args[0], 65);
        g->pos.side = args[1][0];
        g->pos.over = false;
        g->nh = g->nr = 0;
        puts("OK");
        adjust(g, false);
    } else if (!strcmp(cmd, "DUMP")) {
        printf("board %s %c\n", g->pos.board, g->pos.side);
    } else if (!strcmp(cmd, "SHOW")) {
        int moves[64], n = g->pos.over ? 0 : legal(g->pos.board, g->pos.side, moves);
        bool possible[64] = {false};
        for (int i = 0; i < n; ++i) possible[moves[i]] = true;
        puts("  a b c d e f g h");
        for (int r = 0; r < 8; ++r) {
            printf("%d", r + 1);
            for (int c = 0; c < 8; ++c) {
                int p = 8*r+c;
                printf(" %c", possible[p] ? '*' : g->pos.board[p]);
            }
            putchar('\n');
        }
        char line[100];
        status(g, line);
        puts(line);
    } else if (!strcmp(cmd, "SCORE")) {
        printf("score B %d W %d empty %d\n", disc_count(g->pos.board,'B'),
            disc_count(g->pos.board,'W'), disc_count(g->pos.board,'.'));
    } else if (!strcmp(cmd, "LEGAL")) {
        int moves[64], n = g->pos.over ? 0 : legal(g->pos.board, g->pos.side, moves);
        printf("legal %d", n);
        for (int i = 0; i < n; ++i) {
            char sq[3];
            square_name(moves[i], sq);
            printf(" %s", sq);
        }
        putchar('\n');
    } else if (!strcmp(cmd, "MOVE") || !strcmp(cmd, "FLIPS")) {
        int p = square_number(args[0]);
        const char *why = reason(g, p);
        if (why) printf("ILLEGAL %s\n", why);
        else if (!strcmp(cmd, "MOVE")) play(g, p, false, false, 0);
        else {
            int results[64], n = flips(g->pos.board, g->pos.side, p, results);
            printf("flips %s %d", args[0], n);
            for (int i = 0; i < n; ++i) {
                char sq[3];
                square_name(results[i], sq);
                printf(" %s", sq);
            }
            putchar('\n');
        }
    } else if (!strcmp(cmd, "PLAY")) {
        size_t len = strlen(args[0]);
        for (size_t i = 0; i < len; i += 2) {
            int p = 8 * (args[0][i+1] - '1') + args[0][i] - 'a';
            const char *why = reason(g, p);
            if (why) {
                char sq[3];
                square_name(p, sq);
                printf("ILLEGAL move %zu %s %s\n", i/2+1, sq, why);
                break;
            }
            play(g, p, false, false, 0);
        }
    } else if (!strcmp(cmd, "RECORD")) {
        record(g, args[0]);
    } else if (!strcmp(cmd, "UNDO")) {
        if ((uint64_t)g->nh < a) puts("ERROR cannot undo");
        else {
            int start = g->nh - value;
            g->pos = g->history[start].before;
            memmove(g->redo+value, g->redo, (size_t)g->nr * sizeof(Move));
            memcpy(g->redo, g->history+start, (size_t)value * sizeof(Move));
            g->nh = start;
            g->nr += value;
            char line[100];
            status(g, line);
            puts(line);
        }
    } else if (!strcmp(cmd, "REDO")) {
        if ((uint64_t)g->nr < a) puts("ERROR cannot redo");
        else {
            memcpy(g->history+g->nh, g->redo, (size_t)value * sizeof(Move));
            g->pos = g->redo[value-1].after;
            g->nh += value;
            g->nr -= value;
            memmove(g->redo, g->redo+value, (size_t)g->nr * sizeof(Move));
            char line[100];
            status(g, line);
            puts(line);
        }
    } else if (!strcmp(cmd, "HISTORY")) {
        printf("history %d\n", g->nh);
        for (int i = 0; i < g->nh; ++i) {
            const Move *m = &g->history[i];
            char sq[3];
            square_name(m->square, sq);
            printf("%d %c %s %d%s\n", i+1, m->side, sq, m->flipped, m->passed ? " pass" : "");
        }
    } else if (!strcmp(cmd, "SHEET")) {
        show_sheet(g);
    } else if (!strcmp(cmd, "STATS")) {
        stats(g);
    } else if (!strcmp(cmd, "TRANSFORM")) {
        char board[65];
        transform_board(g->pos.board, args[0], board);
        memcpy(g->pos.board, board, 65);
        for (int which = 0; which < 2; ++which) {
            Move *array = which == 0 ? g->history : g->redo;
            int n = which == 0 ? g->nh : g->nr;
            for (int i = 0; i < n; ++i) {
                Move *m = array+i;
                m->square = transform_square(m->square, args[0]);
                transform_board(m->before.board, args[0], board);
                memcpy(m->before.board, board, 65);
                transform_board(m->after.board, args[0], board);
                memcpy(m->after.board, board, 65);
            }
        }
        puts("OK");
    } else if (!strcmp(cmd, "EVAL")) {
        int v[4];
        evaluate(g->pos.board, g->pos.side, v);
        printf("eval %d weights %d mobility %d %d\n", v[0],v[1],v[2],v[3]);
    } else if (!strcmp(cmd, "STABLE")) {
        int count[2];
        stable(g->pos.board, count);
        printf("stable B %d W %d\n", count[0],count[1]);
    } else if (!strcmp(cmd, "HINT")) {
        Ranking moves[64];
        int n = ranked(g->pos.board, g->pos.side, value, moves);
        for (int i = 0; i < n; ++i) {
            char sq[3];
            square_name(moves[i].p, sq);
            printf("%s %d\n", sq, moves[i].value);
        }
    } else if (!strcmp(cmd, "PV")) {
        char path[256], final[65];
        variation(g->pos.board, g->pos.side, value, path, final);
        printf("pv %d %s\n", search(g->pos.board, g->pos.side, value), path);
    } else if (!strcmp(cmd, "AI")) {
        Ranking choices[64];
        ranked(g->pos.board, g->pos.side, value, choices);
        play(g, choices[0].p, false, true, choices[0].value);
    } else if (!strcmp(cmd, "ANALYZE")) {
        int losses[2] = {0,0};
        for (int i = 0; i < g->nh; ++i) {
            Move *m = &g->history[i];
            Ranking choices[64];
            int n = ranked(m->before.board, m->side, value, choices);
            int played = 0;
            for (int j = 0; j < n; ++j) {
                if (choices[j].p == m->square) played = choices[j].value;
            }
            losses[m->side == 'B' ? 0 : 1] += choices[0].value - played;
            char sq[3], best[3];
            square_name(m->square, sq);
            square_name(choices[0].p, best);
            printf("%d %c %s %d best %s %d\n", i+1, m->side, sq, played, best, choices[0].value);
        }
        printf("loss B %d W %d\n", losses[0], losses[1]);
    } else if (!strcmp(cmd, "SOLVE")) {
        if (disc_count(g->pos.board,'.') >= 9) puts("ERROR too many empties");
        else {
            Ranking choices[64];
            int n = ranked(g->pos.board, g->pos.side, -1, choices);
            for (int i = 0; i < n; ++i) {
                char sq[3];
                square_name(choices[i].p, sq);
                printf("%s %d\n", sq, choices[i].value);
            }
            char path[256], final[65];
            variation(g->pos.board, g->pos.side, -1, path, final);
            printf("line %s\nfinal B %d W %d\n", path,
                disc_count(final,'B'), disc_count(final,'W'));
        }
    } else if (!strcmp(cmd, "AUTOPLAY")) {
        automatic(g, value, (int)b, false, 0);
    } else if (!strcmp(cmd, "RANDOM")) {
        automatic(g, 0, 0, true, a);
    } else if (!strcmp(cmd, "MC")) {
        monte_carlo(g, value, b);
    } else if (!strcmp(cmd, "PERFT")) {
        printf("perft %d %llu\n", value, (unsigned long long)perft(g->pos.board, g->pos.side, value));
    } else if (!strcmp(cmd, "DIVIDE")) {
        int moves[64], n = legal(g->pos.board, g->pos.side, moves);
        uint64_t total = 0;
        for (int i = 0; i < n; ++i) {
            char next[65], sq[3];
            place(g->pos.board, g->pos.side, moves[i], next);
            square_name(moves[i], sq);
            uint64_t count = perft(next, other(g->pos.side), value - 1);
            printf("%s %llu\n", sq, (unsigned long long)count);
            total += count;
        }
        printf("total %llu\n", (unsigned long long)total);
    }
}

int main(void) {
    char buffer[1024];
    if (!fgets(buffer, sizeof(buffer), stdin)) return 0;
    int commands = atoi(buffer);
    Game *game = malloc(sizeof(Game));
    if (!game) return EXIT_FAILURE;
    initialize(game);
    while (commands-- > 0 && fgets(buffer, sizeof(buffer), stdin)) {
        buffer[strcspn(buffer, "\r\n")] = '\0';
        execute(game, buffer);
    }
    free(game);
    return 0;
}