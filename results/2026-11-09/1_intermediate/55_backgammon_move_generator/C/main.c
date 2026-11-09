#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int checker[2][26];
} Position;
typedef struct {
    int from, to;
} Move;
typedef struct {
    Position pos;
    int side, cube, owner, score[2];
    bool pending, over;
} State;
typedef struct {
    Position pos;
    Move key[4];
    int key_count, count, first_die, evaluation;
    char text[128];
} Play;
typedef struct {
    Play *all;
    Play **legal;
    int count, legal_count, maximum;
} Plays;
typedef struct {
    int winner, kind, points;
} Result;
typedef struct {
    char record[160];
    State before, after;
} Entry;
typedef struct {
    Result result;
    int turns, first;
} Simulation;
enum { SINGLE, GAMMON, BACKGAMMON, DROP };
enum { UNAVAILABLE, NO_DOUBLE, DOUBLE_TAKE, DOUBLE_DROP };
enum {
    NEW,
    POS,
    SHOW,
    BOARD,
    PIPS,
    RACE,
    MOVES,
    PLAY,
    AUTO,
    HINT,
    EVAL,
    SHOTS,
    CUBE,
    DOUBLE,
    TAKE,
    DROP_CMD,
    RESIGN,
    SCORE,
    HISTORY,
    UNDO,
    REDO,
    GAME,
    MATCH,
    STATS,
    UNKNOWN
};
static const char *commands[] = {"NEW",     "POS",    "SHOW", "BOARD", "PIPS",   "RACE",
                                 "MOVES",   "PLAY",   "AUTO", "HINT",  "EVAL",   "SHOTS",
                                 "CUBE",    "DOUBLE", "TAKE", "DROP",  "RESIGN", "SCORE",
                                 "HISTORY", "UNDO",   "REDO", "GAME",  "MATCH",  "STATS"};
static const char *kinds[] = {"single", "gammon", "backgammon", "drop"};
static const char *decisions[] = {"unavailable", "no double", "double take", "double drop"};
static char color(int x) {
    return x == 0 ? 'W' : 'B';
}
static int max_int(int a, int b) {
    return a > b ? a : b;
}
static State initial(void) {
    State s = {0};
    s.cube = 1;
    s.owner = -1;
    for (int x = 0; x < 2; ++x) {
        s.pos.checker[x][24] = 2;
        s.pos.checker[x][13] = 5;
        s.pos.checker[x][8] = 3;
        s.pos.checker[x][6] = 5;
    }
    return s;
}
static int pair_compare(const void *left, const void *right) {
    const Move *a = left, *b = right;
    if (a->from != b->from)
        return b->from - a->from;
    return b->to - a->to;
}
static int canonical_compare(const void *left, const void *right) {
    const Play *a = *(Play *const *)left, *b = *(Play *const *)right;
    int n = a->key_count < b->key_count ? a->key_count : b->key_count;
    for (int i = 0; i < n; ++i) {
        int c = pair_compare(&a->key[i], &b->key[i]);
        if (c)
            return c;
    }
    return b->key_count - a->key_count;
}
static int position_compare(const void *left, const void *right) {
    const Play *a = *(Play *const *)left, *b = *(Play *const *)right;
    return memcmp(&a->pos, &b->pos, sizeof(Position));
}
static void make_notation(Play *play, const Move *moves, uint32_t hits) {
    int n = play->count;
    memcpy(play->key, moves, (size_t)n * sizeof(Move));
    qsort(play->key, (size_t)n, sizeof(Move), pair_compare);
    while (true) {
        int ai = -1, bi = -1;
        for (int i = 0; i < n && ai < 0; ++i) {
            int t = play->key[i].to;
            if (t == 0 || (hits & (1u << t)))
                continue;
            for (int j = 0; j < n; ++j) {
                if (play->key[j].from == t) {
                    ai = i;
                    bi = j;
                    break;
                }
            }
        }
        if (ai < 0)
            break;
        Move merged = {play->key[ai].from, play->key[bi].to};
        int out = 0;
        for (int i = 0; i < n; ++i) {
            if (i != ai && i != bi)
                play->key[out++] = play->key[i];
        }
        play->key[out++] = merged;
        n = out;
        qsort(play->key, (size_t)n, sizeof(Move), pair_compare);
    }
    play->key_count = n;
    if (n == 0) {
        strcpy(play->text, "none");
        return;
    }
    char *out = play->text;
    uint32_t marked = 0;
    for (int i = 0; i < n;) {
        Move m = play->key[i];
        int j = i + 1;
        while (j < n && play->key[j].from == m.from && play->key[j].to == m.to)
            ++j;
        if (i)
            *out++ = ' ';
        if (m.from == 25) {
            memcpy(out, "bar", 3);
            out += 3;
        } else
            out += sprintf(out, "%d", m.from);
        *out++ = '/';
        if (m.to == 0) {
            memcpy(out, "off", 3);
            out += 3;
        } else
            out += sprintf(out, "%d", m.to);
        if ((hits & (1u << m.to)) && !(marked & (1u << m.to))) {
            *out++ = '*';
            marked |= 1u << m.to;
        }
        if (j - i > 1)
            out += sprintf(out, "(%d)", j - i);
        i = j;
    }
    *out = '\0';
}
static void visit(Plays *plays, Position pos, int side, const int *dice, int remaining, Move *moves,
                  int count, uint32_t hits, int first_die) {
    Play *p = &plays->all[plays->count++];
    p->pos = pos;
    p->count = count;
    p->first_die = first_die;
    make_notation(p, moves, hits);
    if (count > plays->maximum)
        plays->maximum = count;
    bool tried[7] = {false};
    for (int di = 0; di < remaining; ++di) {
        int d = dice[di];
        if (tried[d])
            continue;
        tried[d] = true;
        for (int s = 1; s <= 25; ++s) {
            if (pos.checker[side][s] == 0)
                continue;
            if (pos.checker[side][25] > 0 && s != 25)
                continue;
            int t = max_int(0, s - d);
            bool valid = true;
            if (t > 0)
                valid = pos.checker[1 - side][25 - t] < 2;
            else {
                if (pos.checker[side][25] > 0)
                    valid = false;
                for (int q = 7; q <= 24; ++q)
                    if (pos.checker[side][q])
                        valid = false;
                if (s < d)
                    for (int q = s + 1; q <= 6; ++q)
                        if (pos.checker[side][q])
                            valid = false;
            }
            if (!valid)
                continue;
            Position next = pos;
            --next.checker[side][s];
            ++next.checker[side][t];
            uint32_t next_hits = hits;
            if (t > 0 && next.checker[1 - side][25 - t] == 1) {
                next.checker[1 - side][25 - t] = 0;
                ++next.checker[1 - side][25];
                next_hits |= 1u << t;
            }
            int rest[4], k = 0;
            for (int j = 0; j < remaining; ++j)
                if (j != di)
                    rest[k++] = dice[j];
            moves[count] = (Move){s, t};
            visit(plays, next, side, rest, k, moves, count + 1, next_hits,
                  count == 0 ? d : first_die);
        }
    }
}
static Plays enumerate(Position pos, int side, int d1, int d2) {
    Plays p = {0};
    p.all = malloc(10001 * sizeof(Play));
    p.legal = malloc(10001 * sizeof(Play *));
    if (!p.all || !p.legal)
        exit(EXIT_FAILURE);
    int dice[4] = {d1, d2, d1, d1};
    int n = 2;
    if (d1 == d2) {
        dice[1] = d1;
        n = 4;
    }
    Move moves[4];
    visit(&p, pos, side, dice, n, moves, 0, 0, 0);
    bool larger = false;
    if (p.maximum == 1 && d1 != d2) {
        for (int i = 0; i < p.count; ++i) {
            if (p.all[i].count == 1 && p.all[i].first_die == max_int(d1, d2))
                larger = true;
        }
    }
    for (int i = 0; i < p.count; ++i) {
        Play *play = &p.all[i];
        if (play->count == p.maximum && (!larger || play->first_die == max_int(d1, d2)))
            p.legal[p.legal_count++] = play;
    }
    qsort(p.legal, (size_t)p.legal_count, sizeof(Play *), position_compare);
    int unique = 0;
    for (int i = 0; i < p.legal_count; ++i) {
        if (unique == 0 ||
            memcmp(&p.legal[i]->pos, &p.legal[unique - 1]->pos, sizeof(Position)) != 0)
            p.legal[unique++] = p.legal[i];
    }
    p.legal_count = unique;
    qsort(p.legal, (size_t)unique, sizeof(Play *), canonical_compare);
    return p;
}
static void free_plays(Plays *p) {
    free(p->all);
    free(p->legal);
}
static int pips(const int *own) {
    int n = 0;
    for (int p = 1; p <= 25; ++p)
        n += p * own[p];
    return n;
}
static void evaluation(Position pos, int side, int values[7]) {
    const int *own = pos.checker[side], *opp = pos.checker[1 - side];
    int p = pips(opp) - pips(own), s = 0, home = 0, prime = 0, anchors = 0, run = 0;
    for (int point = 1; point <= 24; ++point) {
        if (own[point] == 1) {
            bool distances[25] = {false};
            for (int q = 0; q < point; ++q)
                if (opp[25 - q] > 0)
                    distances[point - q] = true;
            for (int a = 1; a <= 6; ++a)
                for (int b = 1; b <= 6; ++b) {
                    if (distances[a] || distances[b] || distances[a + b] ||
                        (a == b && (distances[3 * a] || distances[4 * a])))
                        ++s;
                }
        }
        if (own[point] >= 2) {
            if (point <= 6)
                ++home;
            if (point >= 19)
                ++anchors;
            prime = max_int(prime, ++run);
        } else
            run = 0;
    }
    int bar = opp[25] - own[25];
    int result[7] = {
        2 * p - s + 4 * home + 3 * prime + 3 * anchors + 6 * bar, p, s, home, prime, anchors, bar};
    memcpy(values, result, sizeof(result));
}
static int play_value(Play *p, int side) {
    int values[7];
    evaluation(p->pos, side, values);
    return values[0];
}
static int keith(const int *own) {
    int n =
        pips(own) + 2 * max_int(own[1] - 1, 0) + max_int(own[2] - 1, 0) + max_int(own[3] - 3, 0);
    for (int p = 4; p <= 6; ++p)
        if (own[p] == 0)
            ++n;
    return n;
}
static bool contact(Position p) {
    int w = 0, b = 25;
    for (int i = 1; i <= 24; ++i) {
        if (p.checker[0][i] > 0)
            w = i;
        if (p.checker[1][i] > 0)
            b = 25 - i;
    }
    if (p.checker[0][25])
        w = 25;
    if (p.checker[1][25])
        b = 0;
    return w > b;
}
static int cube_decision(State s, bool forbidden) {
    int x = s.side;
    if (s.owner == 1 - x || s.cube == 64 || forbidden)
        return UNAVAILABLE;
    if (contact(s.pos)) {
        int values[7];
        evaluation(s.pos, x, values);
        if (values[0] < 60)
            return NO_DOUBLE;
        return values[0] <= 100 ? DOUBLE_TAKE : DOUBLE_DROP;
    }
    int v = 8 * keith(s.pos.checker[x]) - 7 * keith(s.pos.checker[1 - x]);
    int limit = s.owner == -1 ? 28 : 21;
    if (v > limit)
        return NO_DOUBLE;
    return v >= 14 ? DOUBLE_TAKE : DOUBLE_DROP;
}
static Result end_game(State *s, int winner, int kind) {
    if (kind < 0) {
        const int *opp = s->pos.checker[1 - winner];
        bool back = opp[25] > 0;
        for (int p = 19; p <= 24; ++p)
            if (opp[p])
                back = true;
        kind = opp[0] > 0 ? SINGLE : (back ? BACKGAMMON : GAMMON);
    }
    int multipliers[] = {1, 2, 3, 1};
    Result r = {winner, kind, s->cube * multipliers[kind]};
    s->pending = false;
    s->over = true;
    s->score[winner] += r.points;
    return r;
}
static bool apply_play(State *s, const Play *p, Result *result) {
    s->pos = p->pos;
    if (s->pos.checker[s->side][0] == 15) {
        *result = end_game(s, s->side, -1);
        return true;
    }
    s->side = 1 - s->side;
    return false;
}
static void print_result(Result r) {
    printf("result %c %s %d\n", color(r.winner), kinds[r.kind], r.points);
}
static int64_t random_next(int64_t *seed) {
    return *seed = *seed * 48271 % 2147483647;
}
static int die(int64_t *seed) {
    return (int)(random_next(seed) % 6) + 1;
}
static Play *best_play(Plays *p, int side) {
    Play *best = p->legal[0];
    int value = play_value(best, side);
    for (int i = 1; i < p->legal_count; ++i) {
        int next = play_value(p->legal[i], side);
        if (next > value) {
            value = next;
            best = p->legal[i];
        }
    }
    return best;
}
static Simulation simulate(State state, int64_t *seed, const int strategies[2], bool opening,
                           int target, const int scores[2], bool crawford, bool verbose) {
    int d1 = 0, d2 = 0;
    if (opening) {
        do {
            d1 = die(seed);
            d2 = die(seed);
        } while (d1 == d2);
        state.side = d1 > d2 ? 0 : 1;
    }
    Simulation sim = {{0, 0, 0}, 0, state.side};
    for (int turn = 1;; ++turn) {
        int x = state.side;
        if (!opening || turn != 1) {
            bool forbidden = target > 0 && (crawford || scores[x] + state.cube >= target);
            int decision = cube_decision(state, forbidden);
            if (decision == DOUBLE_TAKE || decision == DOUBLE_DROP) {
                if (verbose)
                    printf("%d %c doubles %d\n", turn, color(x), state.cube * 2);
                if (decision == DOUBLE_DROP) {
                    if (verbose)
                        printf("%d %c drops\n", turn, color(1 - x));
                    sim.result = end_game(&state, x, DROP);
                    return sim;
                }
                if (verbose)
                    printf("%d %c takes\n", turn, color(1 - x));
                state.cube *= 2;
                state.owner = 1 - x;
            }
            d1 = die(seed);
            d2 = die(seed);
        }
        Plays plays = enumerate(state.pos, x, d1, d2);
        Play *play = plays.legal[0];
        if (strategies[x] == 0)
            play = best_play(&plays, x);
        else if (strategies[x] == 2)
            play = plays.legal[random_next(seed) % plays.legal_count];
        if (verbose)
            printf("%d %c %d-%d %s\n", turn, color(x), d1, d2, play->text);
        bool ended = apply_play(&state, play, &sim.result);
        ++sim.turns;
        free_plays(&plays);
        if (ended)
            return sim;
    }
}
static bool number(const char *s, int low, int high) {
    if (!s || !*s)
        return false;
    for (const char *p = s; *p; ++p)
        if (!isdigit((unsigned char)*p))
            return false;
    long long n = strtoll(s, NULL, 10);
    return n >= low && n <= high;
}
static int strategy(const char *s) {
    if (strcmp(s, "BEST") == 0)
        return 0;
    if (strcmp(s, "FIRST") == 0)
        return 1;
    if (strcmp(s, "RANDOM") == 0)
        return 2;
    return -1;
}
static bool parse_position(char **args, int argc, Position *pos) {
    if (argc != 4 || !number(args[1], 0, 15) || !number(args[2], 0, 15) ||
        (strcmp(args[3], "W") && strcmp(args[3], "B")))
        return false;
    memset(pos, 0, sizeof(*pos));
    const char *p = args[0];
    for (int point = 1; point <= 24; ++point) {
        char *end;
        long n = strtol(p, &end, 10);
        if (end == p || n < -15 || n > 15)
            return false;
        if (n > 0)
            pos->checker[0][point] = (int)n;
        else
            pos->checker[1][25 - point] = (int)-n;
        if (point < 24) {
            if (*end != ',')
                return false;
            p = end + 1;
        } else if (*end)
            return false;
    }
    pos->checker[0][25] = atoi(args[1]);
    pos->checker[1][25] = atoi(args[2]);
    for (int x = 0; x < 2; ++x) {
        int sum = 0;
        for (int point = 1; point <= 25; ++point)
            sum += pos->checker[x][point];
        pos->checker[x][0] = 15 - sum;
        if (15 - sum < 0 || 15 - sum > 14)
            return false;
    }
    return true;
}
static bool parse_play(char **tokens, int count, Move moves[512], int *move_count) {
    *move_count = 0;
    if (count == 1 && strcmp(tokens[0], "none") == 0)
        return true;
    for (int i = 0; i < count; ++i) {
        char element[201];
        strcpy(element, tokens[i]);
        size_t n = strlen(element);
        int repeat = 1;
        if (n >= 3 && element[n - 1] == ')') {
            if (element[n - 3] != '(' || element[n - 2] < '2' || element[n - 2] > '4')
                return false;
            repeat = element[n - 2] - '0';
            element[n - 3] = '\0';
        }
        int previous = -1, fields = 0;
        char *part = element;
        while (true) {
            char *slash = strchr(part, '/');
            if (slash)
                *slash = '\0';
            size_t len = strlen(part);
            int point;
            if (fields == 0 && strcmp(part, "bar") == 0)
                point = 25;
            else if (fields > 0 && strcmp(part, "off") == 0)
                point = 0;
            else {
                if (fields > 0 && len && part[len - 1] == '*')
                    part[--len] = '\0';
                if (!number(part, 1, 24) || (len > 1 && part[0] == '0'))
                    return false;
                point = atoi(part);
            }
            if (fields > 0) {
                if (previous <= point)
                    return false;
                for (int k = 0; k < repeat; ++k) {
                    if (*move_count == 512)
                        return false;
                    moves[(*move_count)++] = (Move){previous, point};
                }
            }
            previous = point;
            ++fields;
            if (!slash)
                break;
            part = slash + 1;
        }
        if (fields < 2)
            return false;
    }
    return true;
}
static const char *choose_play(Position pos, int side, char **tokens, int token_count, Plays *plays,
                               Play **chosen) {
    Move moves[512];
    int count;
    if (!parse_play(tokens, token_count, moves, &count))
        return "ILLEGAL syntax";
    Position final = pos;
    bool destinations[25] = {false}, nonbar = false, bearing = false;
    for (int i = 0; i < count; ++i) {
        --final.checker[side][moves[i].from];
        ++final.checker[side][moves[i].to];
        if (moves[i].to > 0)
            destinations[moves[i].to] = true;
        else
            bearing = true;
        if (moves[i].from != 25)
            nonbar = true;
    }
    for (int t = 1; t <= 24; ++t) {
        if (destinations[t] && pos.checker[1 - side][25 - t] == 1) {
            final.checker[1 - side][25 - t] = 0;
            ++final.checker[1 - side][25];
        }
    }
    for (int p = 1; p <= 25; ++p)
        if (final.checker[side][p] < 0)
            return "ILLEGAL no checker";
    if (final.checker[side][25] > 0 && nonbar)
        return "ILLEGAL bar";
    for (int t = 1; t <= 24; ++t)
        if (destinations[t] && pos.checker[1 - side][25 - t] >= 2)
            return "ILLEGAL blocked";
    if (bearing) {
        if (final.checker[side][25])
            return "ILLEGAL bear-off";
        for (int p = 7; p <= 24; ++p)
            if (final.checker[side][p])
                return "ILLEGAL bear-off";
    }
    for (int i = 0; i < plays->legal_count; ++i) {
        if (memcmp(&final, &plays->legal[i]->pos, sizeof(Position)) == 0) {
            *chosen = plays->legal[i];
            return NULL;
        }
    }
    bool possible = false, fewer = false;
    for (int i = 0; i < plays->count; ++i) {
        if (memcmp(&final, &plays->all[i].pos, sizeof(Position)) == 0) {
            possible = true;
            if (plays->all[i].count < plays->maximum)
                fewer = true;
        }
    }
    if (!possible)
        return "ILLEGAL impossible";
    return fewer ? "ILLEGAL too few dice" : "ILLEGAL larger die required";
}
static bool no_arguments(int command) {
    return command == NEW || command == SHOW || command == BOARD || command == PIPS ||
           command == RACE || command == EVAL || command == SHOTS || command == CUBE ||
           command == DOUBLE || command == TAKE || command == DROP_CMD || command == SCORE ||
           command == HISTORY;
}
static bool after_game_limited(int command) {
    return command == RACE || (command >= MOVES && command <= RESIGN) || command == GAME;
}
static bool pending_limited(int command) {
    return command == PLAY || command == AUTO || command == CUBE || command == DOUBLE ||
           command == RESIGN || command == GAME;
}
static bool valid_arguments(int command, char **a, int n, Position *pos) {
    if (no_arguments(command))
        return n == 0;
    if (command == POS)
        return parse_position(a, n, pos);
    if (command == MOVES || command == PLAY || command == AUTO || command == HINT) {
        if (n < 2 || !number(a[0], 1, 6) || !number(a[1], 1, 6))
            return false;
        if (command == PLAY)
            return n >= 3;
        if (command == HINT)
            return n == 3 && number(a[2], 1, 1000);
        return n == 2;
    }
    if (command == RESIGN)
        return n == 1 &&
               (!strcmp(a[0], "single") || !strcmp(a[0], "gammon") || !strcmp(a[0], "backgammon"));
    if (command == UNDO || command == REDO)
        return n == 1 && number(a[0], 1, 1000);
    if (command == GAME)
        return n == 3 && number(a[0], 1, 2147483646) && strategy(a[1]) >= 0 && strategy(a[2]) >= 0;
    if (command == MATCH || command == STATS)
        return n == 2 && number(a[0], 1, command == MATCH ? 15 : 50) && number(a[1], 1, 2147483646);
    return false;
}
static void board_line(Position pos, bool top, int row) {
    for (int i = 1; i <= 12; ++i) {
        int p = top ? i + 12 : 13 - i;
        if (row == 0)
            printf("%3d", p);
        else {
            int w = pos.checker[0][p], b = pos.checker[1][25 - p], n = max_int(w, b);
            if (row == 5 && n > 5)
                printf("%3d", n);
            else
                printf("%3c", n >= row ? (w ? 'W' : 'B') : '.');
        }
        if (i == 6)
            printf(" |");
    }
    putchar('\n');
}
static int ranked_compare(const void *a, const void *b) {
    const Play *x = *(Play *const *)a, *y = *(Play *const *)b;
    if (x->evaluation != y->evaluation)
        return y->evaluation - x->evaluation;
    return canonical_compare(a, b);
}
int main(void) {
    char line[256];
    if (!fgets(line, sizeof(line), stdin))
        return 0;
    int commands_count = atoi(line);
    State state = initial();
    static Entry history[500], redo[500];
    int history_count = 0, redo_count = 0;
    for (int line_number = 0; line_number < commands_count; ++line_number) {
        if (!fgets(line, sizeof(line), stdin))
            break;
        line[strcspn(line, "\r\n")] = '\0';
        char *tokens[128];
        int token_count = 0;
        char *token = strtok(line, " ");
        while (token) {
            tokens[token_count++] = token;
            token = strtok(NULL, " ");
        }
        int command = UNKNOWN;
        for (int i = 0; i < UNKNOWN; ++i)
            if (strcmp(tokens[0], commands[i]) == 0)
                command = i;
        if (command == UNKNOWN) {
            puts("ERROR unknown command");
            continue;
        }
        char **a = tokens + 1;
        int argc = token_count - 1;
        Position parsed;
        if (!valid_arguments(command, a, argc, &parsed)) {
            puts(command == POS ? "ERROR bad position" : "ERROR bad arguments");
            continue;
        }
        if (state.over && after_game_limited(command)) {
            puts("ERROR game over");
            continue;
        }
        if (state.pending && pending_limited(command)) {
            puts("ERROR double pending");
            continue;
        }
        int side = state.side;
        switch (command) {
        case NEW:
        case POS: {
            int w = state.score[0], b = state.score[1];
            state = initial();
            state.score[0] = w;
            state.score[1] = b;
            if (command == POS) {
                state.pos = parsed;
                state.side = a[3][0] == 'W' ? 0 : 1;
            }
            history_count = redo_count = 0;
            puts("OK");
            break;
        }
        case SHOW:
            printf("POS ");
            for (int p = 1; p <= 24; ++p)
                printf("%s%d", p == 1 ? "" : ",",
                       state.pos.checker[0][p] - state.pos.checker[1][25 - p]);
            printf(" %d %d %c\n", state.pos.checker[0][25], state.pos.checker[1][25], color(side));
            break;
        case BOARD: {
            board_line(state.pos, true, 0);
            for (int r = 1; r <= 5; ++r)
                board_line(state.pos, true, r);
            char owner[7];
            if (state.owner == -1)
                strcpy(owner, "center");
            else
                sprintf(owner, "%c", color(state.owner));
            printf("bar W%d B%d | off W%d B%d | cube %d %s | ", state.pos.checker[0][25],
                   state.pos.checker[1][25], state.pos.checker[0][0], state.pos.checker[1][0],
                   state.cube, owner);
            if (state.over)
                puts("game over");
            else
                printf("%c %s\n", color(side), state.pending ? "doubles" : "to move");
            for (int r = 5; r >= 1; --r)
                board_line(state.pos, false, r);
            board_line(state.pos, false, 0);
            break;
        }
        case PIPS:
            printf("pips W %d B %d\n", pips(state.pos.checker[0]), pips(state.pos.checker[1]));
            break;
        case RACE:
            if (contact(state.pos))
                puts("contact");
            else
                printf("race W %d B %d\n", keith(state.pos.checker[0]),
                       keith(state.pos.checker[1]));
            break;
        case EVAL: {
            int v[7];
            evaluation(state.pos, side, v);
            printf("eval %d pips %d blots %d home %d prime %d anchors %d bar %d\n", v[0], v[1],
                   v[2], v[3], v[4], v[5], v[6]);
            break;
        }
        case MOVES:
        case PLAY:
        case AUTO:
        case HINT: {
            int d1 = atoi(a[0]), d2 = atoi(a[1]);
            Plays plays = enumerate(state.pos, side, d1, d2);
            if (command == MOVES) {
                for (int i = 0; i < plays.legal_count; ++i)
                    puts(plays.legal[i]->text);
                printf("total %d\n", plays.legal_count);
            } else if (command == HINT) {
                for (int i = 0; i < plays.legal_count; ++i)
                    plays.legal[i]->evaluation = play_value(plays.legal[i], side);
                qsort(plays.legal, (size_t)plays.legal_count, sizeof(Play *), ranked_compare);
                int limit = atoi(a[2]);
                for (int i = 0; i < limit && i < plays.legal_count; ++i)
                    printf("%d %s\n", plays.legal[i]->evaluation, plays.legal[i]->text);
            } else {
                Play *play = NULL;
                const char *error = NULL;
                if (command == AUTO)
                    play = best_play(&plays, side);
                else
                    error = choose_play(state.pos, side, a + 2, argc - 2, &plays, &play);
                if (error)
                    puts(error);
                else {
                    State before = state;
                    Result result;
                    int value = command == AUTO ? play_value(play, side) : 0;
                    bool ended = apply_play(&state, play, &result);
                    printf("OK %s", play->text);
                    if (command == AUTO)
                        printf(" eval %d", value);
                    putchar('\n');
                    if (ended)
                        print_result(result);
                    Entry *entry = &history[history_count++];
                    snprintf(entry->record, sizeof(entry->record), "%c %d-%d %s", color(side), d1,
                             d2, play->text);
                    entry->before = before;
                    entry->after = state;
                    redo_count = 0;
                }
            }
            free_plays(&plays);
            break;
        }
        case SHOTS: {
            int counts[25] = {0}, total = 0;
            char rolls[128] = "";
            for (int d1 = 6; d1 >= 1; --d1)
                for (int d2 = d1; d2 >= 1; --d2) {
                    Plays plays = enumerate(state.pos, 1 - side, d1, d2);
                    bool any = false;
                    int weight = d1 == d2 ? 1 : 2;
                    for (int p = 24; p >= 1; --p) {
                        if (state.pos.checker[side][p] != 1)
                            continue;
                        bool hit = false;
                        for (int i = 0; i < plays.legal_count; ++i)
                            if (plays.legal[i]->pos.checker[side][p] == 0)
                                hit = true;
                        if (hit) {
                            counts[p] += weight;
                            any = true;
                        }
                    }
                    if (any) {
                        total += weight;
                        sprintf(rolls + strlen(rolls), " %d-%d", d1, d2);
                    }
                    free_plays(&plays);
                }
            printf("shots %d/36%s\n", total, rolls);
            for (int p = 24; p >= 1; --p)
                if (state.pos.checker[side][p] == 1)
                    printf("blot %d %d/36\n", p, counts[p]);
            break;
        }
        case CUBE:
            printf("cube %s\n", decisions[cube_decision(state, false)]);
            break;
        case DOUBLE:
            if (state.owner == 1 - side || state.cube == 64)
                puts("ERROR cube unavailable");
            else {
                state.pending = true;
                redo_count = 0;
                printf("OK double %d\n", state.cube * 2);
            }
            break;
        case TAKE:
        case DROP_CMD:
            if (!state.pending)
                puts("ERROR no double");
            else {
                state.pending = false;
                redo_count = 0;
                if (command == TAKE) {
                    state.cube *= 2;
                    state.owner = 1 - side;
                    printf("OK take %d %c\n", state.cube, color(state.owner));
                } else {
                    puts("OK drop");
                    print_result(end_game(&state, side, DROP));
                }
            }
            break;
        case RESIGN: {
            int kind =
                !strcmp(a[0], "single") ? SINGLE : (!strcmp(a[0], "gammon") ? GAMMON : BACKGAMMON);
            redo_count = 0;
            puts("OK resign");
            print_result(end_game(&state, 1 - side, kind));
            break;
        }
        case SCORE:
            printf("score W %d B %d\n", state.score[0], state.score[1]);
            break;
        case HISTORY:
            printf("history %d\n", history_count);
            for (int i = 0; i < history_count; ++i)
                printf("%d %s\n", i + 1, history[i].record);
            break;
        case UNDO:
        case REDO: {
            int n = atoi(a[0]);
            if (command == UNDO) {
                if (n > history_count) {
                    puts("ERROR cannot undo");
                    break;
                }
                memmove(redo + n, redo, (size_t)redo_count * sizeof(Entry));
                memcpy(redo, history + history_count - n, (size_t)n * sizeof(Entry));
                state = redo[0].before;
                history_count -= n;
                redo_count += n;
            } else {
                if (n > redo_count) {
                    puts("ERROR cannot redo");
                    break;
                }
                memcpy(history + history_count, redo, (size_t)n * sizeof(Entry));
                state = redo[n - 1].after;
                history_count += n;
                redo_count -= n;
                memmove(redo, redo + n, (size_t)redo_count * sizeof(Entry));
            }
            puts("OK");
            break;
        }
        case GAME: {
            int64_t seed = strtoll(a[0], NULL, 10);
            int strategies[2] = {strategy(a[1]), strategy(a[2])};
            Simulation sim = simulate(state, &seed, strategies, false, 0, NULL, false, true);
            print_result(sim.result);
            break;
        }
        case MATCH:
        case STATS: {
            int n = atoi(a[0]), points[2] = {0, 0}, turns = 0, game = 0, outcomes[4][2] = {{0}};
            int64_t seed = strtoll(a[1], NULL, 10);
            const int strategies[2] = {0, 0};
            bool crawford_used = false;
            while (command == STATS ? game < n : max_int(points[0], points[1]) < n) {
                ++game;
                bool crawford =
                    command == MATCH && !crawford_used && max_int(points[0], points[1]) == n - 1;
                if (crawford)
                    crawford_used = true;
                Simulation sim = simulate(initial(), &seed, strategies, true,
                                          command == MATCH ? n : 0, points, crawford, false);
                points[sim.result.winner] += sim.result.points;
                ++outcomes[sim.result.kind][sim.result.winner];
                turns += sim.turns;
                if (command == MATCH)
                    printf("game %d%s start %c turns %d result %c %s %d score %d-%d\n", game,
                           crawford ? " crawford" : "", color(sim.first), sim.turns,
                           color(sim.result.winner), kinds[sim.result.kind], sim.result.points,
                           points[0], points[1]);
            }
            if (command == MATCH)
                printf("match %c %d-%d\n", color(points[0] >= n ? 0 : 1), points[0], points[1]);
            else {
                for (int kind = 0; kind < 4; ++kind)
                    printf("%s W %d B %d\n", kinds[kind], outcomes[kind][0], outcomes[kind][1]);
                printf("points W %d B %d\nturns %d\n", points[0], points[1], turns);
            }
            break;
        }
        }
    }
    return 0;
}
