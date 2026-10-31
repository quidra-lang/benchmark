#include <ctype.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CELLS = 100, SHIPS = 5 };
typedef enum { SETUP, BATTLE, OVER } Phase;
typedef enum { HUMAN = -1, HUNT, PROB, RANDOM } Strategy;
typedef enum { REEF, UNKNOWN, MISS_VIEW, HIT_VIEW, SUNK_VIEW } CellView;
typedef enum { ALREADY, MISS, HIT, SUNK } Result;
typedef enum { NORMAL, SINKS_ONLY, QUIET } Output;

static const char *const ship_names[] = {
    "CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER"
};
static const int lengths[] = {5, 4, 3, 3, 2};
static const char symbols[] = "CBRSD";
static const char *const strategies[] = {"HUNT", "PROB", "RANDOM"};
static const char *const phases[] = {"SETUP", "BATTLE", "OVER"};

typedef struct { int start, step; } Ship;
typedef struct {
    int64_t shots, hits, sunk, turns, streak, longest, wins;
} Stats;
typedef struct {
    Ship fleet[SHIPS];
    int board[CELLS];
    bool attacked[CELLS];
    int candidates[4 * 17], candidate_count;
    int64_t random;
    Strategy controller;
    bool torpedo_used, sonar_used;
    Stats stats;
} Player;
typedef struct {
    Player players[2];
    bool reefs[CELLS], salvo, chain, touch;
    Phase phase;
    int current, winner;
} Game;
typedef struct {
    CellView cells[CELLS];
    bool excluded[CELLS], remaining[SHIPS];
} View;
typedef struct {
    int cell, info;
    const char *step;
    int64_t next_random;
} Choice;
typedef struct { Result result; int ship; } Shot;
typedef struct { int winner; int64_t shots[2], hits[2]; } Match;
typedef struct { char text[64]; } Message;

static int64_t advance(int64_t state) {
    return state * 48271 % 2147483647;
}

static int cell_number(const char *text) {
    return (text[0] - 'A') * 10 + atoi(text + 1) - 1;
}

static Message cell_name(int cell) {
    Message result;
    snprintf(result.text, sizeof result.text, "%c%d", 'A' + cell / 10, cell % 10 + 1);
    return result;
}

static int ship_number(const char *name) {
    for (int s = 0; s < SHIPS; ++s)
        if (strcmp(name, ship_names[s]) == 0) return s;
    return -1;
}

static Strategy strategy(const char *name) {
    for (int s = HUNT; s <= RANDOM; ++s)
        if (strcmp(name, strategies[s]) == 0) return (Strategy)s;
    return HUMAN;
}

static void clear_fleet(Player *p) {
    for (int s = 0; s < SHIPS; ++s) p->fleet[s] = (Ship){-1, 1};
    for (int c = 0; c < CELLS; ++c) p->board[c] = -1;
}

static void init_game(Game *g) {
    memset(g, 0, sizeof *g);
    g->phase = SETUP;
    g->winner = -1;
    for (int p = 0; p < 2; ++p) {
        clear_fleet(&g->players[p]);
        g->players[p].random = p + 1;
        g->players[p].controller = HUMAN;
    }
}

static int attacked_count(const Player *p, int s) {
    Ship ship = p->fleet[s];
    int count = 0;
    if (ship.start >= 0)
        for (int i = 0; i < lengths[s]; ++i)
            count += p->attacked[ship.start + i * ship.step];
    return count;
}

static bool sunk(const Player *p, int s) {
    return p->fleet[s].start >= 0 && attacked_count(p, s) == lengths[s];
}

static int placed(const Player *p) {
    int count = 0;
    for (int s = 0; s < SHIPS; ++s) count += p->fleet[s].start >= 0;
    return count;
}

static int afloat(const Player *p) {
    int count = 0;
    for (int s = 0; s < SHIPS; ++s)
        count += p->fleet[s].start >= 0 && !sunk(p, s);
    return count;
}

static int allowance(const Game *g, int p) {
    return g->salvo ? afloat(&g->players[p]) : 1;
}

static bool in_bounds(int start, int step, int length) {
    return step == 1 ? start % 10 + length <= 10 : start / 10 + length <= 10;
}

static bool adjacent(int a, int b) {
    return abs(a / 10 - b / 10) <= 1 && abs(a % 10 - b % 10) <= 1;
}

static bool ships_touch(Ship a, int a_length, Ship b, int b_length) {
    for (int i = 0; i < a_length; ++i)
        for (int j = 0; j < b_length; ++j)
            if (adjacent(a.start + i * a.step, b.start + j * b.step)) return true;
    return false;
}

static Message placement_error(const Game *g, const Player *p, int s, Ship ship) {
    Message error = {{0}};
    if (!in_bounds(ship.start, ship.step, lengths[s])) {
        strcpy(error.text, "out of bounds");
        return error;
    }
    for (int i = 0; i < lengths[s]; ++i)
        if (g->reefs[ship.start + i * ship.step]) {
            strcpy(error.text, "on reef");
            return error;
        }
    for (int other = 0; other < SHIPS; ++other)
        for (int i = 0; i < lengths[s]; ++i)
            if (p->board[ship.start + i * ship.step] == other) {
                snprintf(error.text, sizeof error.text, "overlaps %s", ship_names[other]);
                return error;
            }
    if (!g->touch)
        for (int other = 0; other < SHIPS; ++other)
            if (p->fleet[other].start >= 0 &&
                ships_touch(ship, lengths[s], p->fleet[other], lengths[other])) {
                snprintf(error.text, sizeof error.text, "touches %s", ship_names[other]);
                return error;
            }
    return error;
}

static void put_ship(Player *p, int s, Ship ship) {
    p->fleet[s] = ship;
    for (int i = 0; i < lengths[s]; ++i) p->board[ship.start + i * ship.step] = s;
}

static void print_placed(const Game *g, int p, int s) {
    Ship ship = g->players[p].fleet[s];
    printf("PLACED %d %s %s-%s\n", p + 1, ship_names[s], cell_name(ship.start).text,
           cell_name(ship.start + (lengths[s] - 1) * ship.step).text);
}

static int64_t autoplace(Game *g, int owner, int64_t seed) {
    Player *p = &g->players[owner];
    clear_fleet(p);
    p->random = seed;
    int64_t attempts = 0;
    for (int s = 0; s < SHIPS; ++s) {
        for (;;) {
            ++attempts;
            p->random = advance(p->random);
            int step = p->random % 2 == 0 ? 1 : 10;
            p->random = advance(p->random);
            int k = (int)(p->random % (10 * (11 - lengths[s])));
            int start = step == 1 ? k / (11 - lengths[s]) * 10 + k % (11 - lengths[s]) : k;
            Ship ship = {start, step};
            if (!placement_error(g, p, s, ship).text[0]) {
                put_ship(p, s, ship);
                break;
            }
        }
    }
    return attempts;
}

static Message parse_layout(const Game *g, const char *layout, Player *replacement) {
    Message error = {{0}};
    clear_fleet(replacement);
    for (int s = 0; s < SHIPS; ++s) {
        int cells[CELLS], count = 0;
        for (int c = 0; c < CELLS; ++c)
            if (layout[c / 10 * 11 + c % 10] == symbols[s]) cells[count++] = c;
        if (count != lengths[s]) {
            snprintf(error.text, sizeof error.text, "%s has %d cells", ship_names[s], count);
            return error;
        }
        int step = cells[1] - cells[0];
        bool straight = (step == 1 || step == 10) && in_bounds(cells[0], step, count);
        for (int i = 0; i < count; ++i) straight &= cells[i] == cells[0] + i * step;
        if (!straight) {
            snprintf(error.text, sizeof error.text, "%s not straight", ship_names[s]);
            return error;
        }
        for (int i = 0; i < count; ++i)
            if (g->reefs[cells[i]]) {
                snprintf(error.text, sizeof error.text, "%s on reef", ship_names[s]);
                return error;
            }
        put_ship(replacement, s, (Ship){cells[0], step});
    }
    if (!g->touch)
        for (int a = 0; a < SHIPS; ++a)
            for (int b = a + 1; b < SHIPS; ++b)
                if (ships_touch(replacement->fleet[a], lengths[a], replacement->fleet[b], lengths[b])) {
                    snprintf(error.text, sizeof error.text, "%s touches %s", ship_names[a], ship_names[b]);
                    return error;
                }
    return error;
}

static View make_view(const Game *g, int p) {
    View view = {0};
    const Player *opponent = &g->players[1 - p];
    for (int s = 0; s < SHIPS; ++s) view.remaining[s] = !sunk(opponent, s);
    for (int c = 0; c < CELLS; ++c) {
        int s = opponent->board[c];
        view.cells[c] = g->reefs[c] ? REEF : !opponent->attacked[c] ? UNKNOWN :
                        s < 0 ? MISS_VIEW : view.remaining[s] ? HIT_VIEW : SUNK_VIEW;
    }
    if (!g->touch)
        for (int c = 0; c < CELLS; ++c)
            if (view.cells[c] == SUNK_VIEW)
                for (int dr = -1; dr <= 1; ++dr)
                    for (int dc = -1; dc <= 1; ++dc) {
                        int r = c / 10 + dr, col = c % 10 + dc;
                        if ((dr || dc) && r >= 0 && r < 10 && col >= 0 && col < 10)
                            view.excluded[r * 10 + col] = true;
                    }
    return view;
}

static bool candidate(const View *view, int cell) {
    return cell >= 0 && cell < CELLS && view->cells[cell] == UNKNOWN && !view->excluded[cell];
}

static int neighbour(int cell, int dr, int dc) {
    int row = cell / 10 + dr, col = cell % 10 + dc;
    return row >= 0 && row < 10 && col >= 0 && col < 10 ? row * 10 + col : -1;
}

static void density(const View *view, int scores[CELLS]) {
    memset(scores, 0, CELLS * sizeof *scores);
    for (int s = 0; s < SHIPS; ++s)
        if (view->remaining[s])
            for (int start = 0; start < CELLS; ++start)
                for (int direction = 0; direction < 2; ++direction) {
                    int step = direction == 0 ? 1 : 10;
                    if (!in_bounds(start, step, lengths[s])) continue;
                    bool possible = true;
                    int hits = 0;
                    for (int i = 0; i < lengths[s]; ++i) {
                        int c = start + i * step;
                        if (view->excluded[c] || (view->cells[c] != UNKNOWN && view->cells[c] != HIT_VIEW)) {
                            possible = false;
                            break;
                        }
                        hits += view->cells[c] == HIT_VIEW;
                    }
                    if (possible)
                        for (int i = 0; i < lengths[s]; ++i) scores[start + i * step] += 1 + 10 * hits;
                }
}

static int best_cell(const View *view, const int scores[CELLS]) {
    int best = -1;
    for (int c = 0; c < CELLS; ++c)
        if (view->cells[c] == UNKNOWN && (best < 0 || scores[c] > scores[best])) best = c;
    return best;
}

static Choice choose(const Game *g, int p, Strategy method) {
    View view = make_view(g, p);
    const Player *player = &g->players[p];
    if (method == PROB) {
        int scores[CELLS];
        density(&view, scores);
        int cell = best_cell(&view, scores);
        return (Choice){cell, scores[cell], NULL, player->random};
    }
    if (method == RANDOM) {
        int cells[CELLS], count = 0;
        for (int c = 0; c < CELLS; ++c)
            if (candidate(&view, c)) cells[count++] = c;
        int64_t next = advance(player->random);
        return (Choice){cells[next % count], count, NULL, next};
    }
    for (int h = 0; h < CELLS; ++h)
        if (view.cells[h] == HIT_VIEW)
            for (int direction = 0; direction < 2; ++direction) {
                int dr = direction, dc = 1 - direction;
                int front = neighbour(h, dr, dc);
                if (front < 0 || view.cells[front] != HIT_VIEW) continue;
                while (front >= 0 && view.cells[front] == HIT_VIEW) front = neighbour(front, dr, dc);
                int back = neighbour(h, -dr, -dc);
                if (candidate(&view, front)) return (Choice){front, 0, "LINE", player->random};
                if (candidate(&view, back)) return (Choice){back, 0, "LINE", player->random};
            }
    for (int i = player->candidate_count - 1; i >= 0; --i)
        if (candidate(&view, player->candidates[i]))
            return (Choice){player->candidates[i], 0, "STACK", player->random};
    int shortest = 10;
    for (int s = 0; s < SHIPS; ++s)
        if (view.remaining[s] && lengths[s] < shortest) shortest = lengths[s];
    for (int c = 0; c < CELLS; ++c)
        if (candidate(&view, c) && (c / 10 + c % 10) % shortest == 0)
            return (Choice){c, 0, "PARITY", player->random};
    abort();
}

static void record_shot(Player *p, Result result) {
    ++p->stats.shots;
    if (result == HIT || result == SUNK) {
        ++p->stats.hits;
        ++p->stats.streak;
        if (p->stats.streak > p->stats.longest) p->stats.longest = p->stats.streak;
    } else p->stats.streak = 0;
    if (result == SUNK) ++p->stats.sunk;
}

static Shot shoot(Game *g, int p, int cell) {
    Player *attacker = &g->players[p], *opponent = &g->players[1 - p];
    Shot shot = {ALREADY, opponent->board[cell]};
    if (!opponent->attacked[cell]) {
        opponent->attacked[cell] = true;
        shot.result = shot.ship < 0 ? MISS : sunk(opponent, shot.ship) ? SUNK : HIT;
    }
    if (shot.result == HIT) {
        static const int dr[] = {0, 1, 0, -1}, dc[] = {-1, 0, 1, 0};
        for (int d = 0; d < 4; ++d) {
            int c = neighbour(cell, dr[d], dc[d]);
            if (c >= 0) attacker->candidates[attacker->candidate_count++] = c;
        }
    }
    record_shot(attacker, shot.result);
    return shot;
}

static Message shot_text(Shot shot) {
    Message text;
    static const char *const names[] = {"ALREADY", "MISS", "HIT"};
    if (shot.result == SUNK) snprintf(text.text, sizeof text.text, "SUNK %s", ship_names[shot.ship]);
    else strcpy(text.text, names[shot.result]);
    return text;
}

static void emit_shot(const Game *g, int p, int cell, Shot shot, Output output) {
    if (output == NORMAL)
        printf("SHOT %d %s %s\n", p + 1, cell_name(cell).text, shot_text(shot).text);
    else if (output == SINKS_ONLY && shot.result == SUNK)
        printf("SINK %d %s %" PRId64 "\n", p + 1, ship_names[shot.ship], g->players[p].stats.shots);
}

static void finish_turn(Game *g, int p, bool hit, Output output) {
    ++g->players[p].stats.turns;
    if (afloat(&g->players[1 - p]) == 0) {
        g->phase = OVER;
        g->winner = p;
        ++g->players[p].stats.wins;
        if (output == NORMAL) printf("WINNER %d\n", p + 1);
    } else g->current = g->chain && hit ? p : 1 - p;
}

static void ai_turn(Game *g, int p, Strategy method, Output output) {
    int shots = allowance(g, p);
    bool hit = false;
    for (int i = 0; i < shots; ++i) {
        Choice choice = choose(g, p, method);
        g->players[p].random = choice.next_random;
        Shot shot = shoot(g, p, choice.cell);
        emit_shot(g, p, choice.cell, shot, output);
        hit |= shot.result == HIT || shot.result == SUNK;
        if (afloat(&g->players[1 - p]) == 0) break;
    }
    finish_turn(g, p, hit, output);
}

static void automatic_control(Game *g) {
    while (g->phase == BATTLE && g->players[g->current].controller != HUMAN) {
        int p = g->current;
        ai_turn(g, p, g->players[p].controller, NORMAL);
    }
}

static const char *turn_error(const Game *g, int p) {
    if (g->phase == OVER) return "game over";
    if (g->phase == SETUP && (placed(&g->players[0]) != SHIPS || placed(&g->players[1]) != SHIPS))
        return "fleets not ready";
    if (g->current != p) return "not your turn";
    return NULL;
}

static Match play_match(const Game *settings, int64_t seed1, int64_t seed2,
                        Strategy first, Strategy second, Output output) {
    Game g;
    init_game(&g);
    g.salvo = settings->salvo;
    g.chain = settings->chain;
    g.touch = settings->touch;
    memcpy(g.reefs, settings->reefs, sizeof g.reefs);
    autoplace(&g, 0, seed1);
    autoplace(&g, 1, seed2);
    g.phase = BATTLE;
    Strategy methods[] = {first, second};
    while (g.phase == BATTLE) ai_turn(&g, g.current, methods[g.current], output);
    return (Match){g.winner, {g.players[0].stats.shots, g.players[1].stats.shots},
                  {g.players[0].stats.hits, g.players[1].stats.hits}};
}

static void show_board(const Game *g, int p, bool radar) {
    printf("%s %d\n  1 2 3 4 5 6 7 8 9 10\n", radar ? "RADAR" : "BOARD", p + 1);
    View view = make_view(g, p);
    const Player *player = &g->players[p];
    static const char view_symbols[] = "~.ox#";
    for (int row = 0; row < 10; ++row) {
        putchar('A' + row);
        for (int col = 0; col < 10; ++col) {
            int c = row * 10 + col, s = player->board[c];
            char mark;
            if (radar) mark = view_symbols[view.cells[c]];
            else if (g->reefs[c]) mark = '~';
            else if (s < 0) mark = player->attacked[c] ? 'o' : '.';
            else mark = player->attacked[c] ? (char)tolower((unsigned char)symbols[s]) : symbols[s];
            printf(" %c", mark);
        }
        putchar('\n');
    }
}

static void print_stats(const Game *g) {
    for (int p = 0; p < 2; ++p) {
        Stats s = g->players[p].stats;
        printf("STATS %d shots %" PRId64 " hits %" PRId64 " sunk %" PRId64
               " turns %" PRId64 " streak %" PRId64 " accuracy ",
               p + 1, s.shots, s.hits, s.sunk, s.turns, s.longest);
        if (s.shots) printf("%" PRId64 "%%", s.hits * 100 / s.shots);
        else putchar('-');
        printf(" wins %" PRId64 "\n", s.wins);
    }
}

static void command(Game *g, char **w, int count) {
    const char *cmd = w[0];
    bool setup_command = strcmp(cmd, "PLACE") == 0 || strcmp(cmd, "REMOVE") == 0 ||
        strcmp(cmd, "AUTOPLACE") == 0 || strcmp(cmd, "LAYOUT") == 0 || strcmp(cmd, "REEF") == 0 ||
        strcmp(cmd, "SALVO") == 0 || strcmp(cmd, "CHAIN") == 0 || strcmp(cmd, "TOUCH") == 0;
    if (setup_command && g->phase != SETUP) { puts("ERROR setup closed"); return; }
    if (strcmp(cmd, "NEW") == 0) {
        int64_t wins[] = {g->players[0].stats.wins, g->players[1].stats.wins};
        init_game(g);
        for (int p = 0; p < 2; ++p) g->players[p].stats.wins = wins[p];
        puts("NEW");
    } else if (strcmp(cmd, "SEED") == 0 || strcmp(cmd, "CONTROL") == 0) {
        int p = atoi(w[1]) - 1;
        if (strcmp(cmd, "SEED") == 0) {
            g->players[p].random = strtoll(w[2], NULL, 10);
            printf("SEED %d %" PRId64 "\n", p + 1, g->players[p].random);
        } else {
            g->players[p].controller = strategy(w[2]);
            printf("CONTROL %d %s\n", p + 1, w[2]);
        }
    } else if (strcmp(cmd, "SALVO") == 0 || strcmp(cmd, "CHAIN") == 0 || strcmp(cmd, "TOUCH") == 0) {
        bool enabled = strcmp(w[1], "ON") == 0;
        if (strcmp(cmd, "SALVO") == 0) g->salvo = enabled;
        else if (strcmp(cmd, "CHAIN") == 0) g->chain = enabled;
        else g->touch = enabled;
        printf("%s %s\n", cmd, w[1]);
    } else if (strcmp(cmd, "PLACE") == 0 || strcmp(cmd, "REMOVE") == 0) {
        int p = atoi(w[1]) - 1, s = ship_number(w[2]);
        Player *player = &g->players[p];
        bool removing = strcmp(cmd, "REMOVE") == 0;
        if ((player->fleet[s].start >= 0) != removing) {
            printf("ERROR %s %s placed\n", ship_names[s], removing ? "not" : "already");
            return;
        }
        if (removing) {
            Ship ship = player->fleet[s];
            for (int i = 0; i < lengths[s]; ++i) player->board[ship.start + i * ship.step] = -1;
            player->fleet[s].start = -1;
            printf("REMOVED %d %s\n", p + 1, ship_names[s]);
        } else {
            Ship ship = {cell_number(w[3]), w[4][0] == 'H' ? 1 : 10};
            Message error = placement_error(g, player, s, ship);
            if (error.text[0]) { printf("ERROR %s\n", error.text); return; }
            put_ship(player, s, ship);
            print_placed(g, p, s);
        }
    } else if (strcmp(cmd, "AUTOPLACE") == 0) {
        int p = atoi(w[1]) - 1;
        int64_t attempts = autoplace(g, p, strtoll(w[2], NULL, 10));
        printf("AUTOPLACE %d attempts %" PRId64 "\n", p + 1, attempts);
        for (int s = 0; s < SHIPS; ++s) print_placed(g, p, s);
    } else if (strcmp(cmd, "LAYOUT") == 0) {
        int p = atoi(w[1]) - 1;
        Player replacement = {0};
        Message error = parse_layout(g, w[2], &replacement);
        if (error.text[0]) { printf("ERROR %s\n", error.text); return; }
        memcpy(g->players[p].fleet, replacement.fleet, sizeof replacement.fleet);
        memcpy(g->players[p].board, replacement.board, sizeof replacement.board);
        printf("LAYOUT %d\n", p + 1);
        for (int s = 0; s < SHIPS; ++s) print_placed(g, p, s);
    } else if (strcmp(cmd, "REEF") == 0) {
        int cell = cell_number(w[1]);
        if (g->reefs[cell]) { printf("ERROR reef exists at %s\n", w[1]); return; }
        for (int p = 0; p < 2; ++p)
            if (g->players[p].board[cell] >= 0) {
                printf("ERROR %s occupied by %d %s\n", w[1], p + 1, ship_names[g->players[p].board[cell]]);
                return;
            }
        g->reefs[cell] = true;
        printf("REEF %s\n", w[1]);
    } else if (strcmp(cmd, "FIRE") == 0 || strcmp(cmd, "AI") == 0 ||
               strcmp(cmd, "TORPEDO") == 0 || strcmp(cmd, "SONAR") == 0) {
        int p = atoi(w[1]) - 1;
        const char *error = turn_error(g, p);
        if (error) { printf("ERROR %s\n", error); return; }
        Player *player = &g->players[p], *opponent = &g->players[1 - p];
        if (strcmp(cmd, "FIRE") == 0) {
            int expected = allowance(g, p);
            if (count - 2 != expected) { printf("ERROR expected %d shots\n", expected); return; }
            for (int i = 2; i < count; ++i)
                if (g->reefs[cell_number(w[i])]) { printf("ERROR reef at %s\n", w[i]); return; }
        } else if (strcmp(cmd, "TORPEDO") == 0 && player->torpedo_used) {
            puts("ERROR torpedo used"); return;
        } else if (strcmp(cmd, "SONAR") == 0 && player->sonar_used) {
            puts("ERROR sonar used"); return;
        }
        g->phase = BATTLE;
        bool hit = false;
        if (strcmp(cmd, "AI") == 0) ai_turn(g, p, strategy(w[2]), NORMAL);
        else {
            if (strcmp(cmd, "FIRE") == 0) {
                for (int i = 2; i < count; ++i) {
                    int cell = cell_number(w[i]);
                    Shot shot = shoot(g, p, cell);
                    emit_shot(g, p, cell, shot, NORMAL);
                    hit |= shot.result == HIT || shot.result == SUNK;
                    if (afloat(opponent) == 0) break;
                }
            } else if (strcmp(cmd, "SONAR") == 0) {
                player->sonar_used = true;
                int centre = cell_number(w[2]), ships = 0;
                for (int c = 0; c < CELLS; ++c)
                    ships += adjacent(c, centre) && opponent->board[c] >= 0 && !opponent->attacked[c];
                printf("SONAR %d %s %d\n", p + 1, w[2], ships);
            } else {
                player->torpedo_used = true;
                Message result = {"MISS"};
                bool stopped_at_ship = false;
                for (int i = 0; i < 10; ++i) {
                    int c = (w[2][0] - 'A') * 10 + (w[3][0] == 'W' ? i : 9 - i);
                    if (g->reefs[c]) {
                        snprintf(result.text, sizeof result.text, "REEF %s", cell_name(c).text);
                        break;
                    }
                    if (opponent->board[c] >= 0) {
                        Shot shot = shoot(g, p, c);
                        hit = shot.result == HIT || shot.result == SUNK;
                        snprintf(result.text, sizeof result.text, "%s %s", shot_text(shot).text, cell_name(c).text);
                        stopped_at_ship = true;
                        break;
                    }
                    opponent->attacked[c] = true;
                }
                if (!stopped_at_ship) record_shot(player, MISS);
                printf("TORPEDO %d %s %s %s\n", p + 1, w[2], w[3], result.text);
            }
            finish_turn(g, p, hit, NORMAL);
        }
        automatic_control(g);
    } else if (strcmp(cmd, "RESIGN") == 0) {
        if (g->phase != BATTLE) { puts("ERROR not in battle"); return; }
        int p = atoi(w[1]) - 1;
        g->phase = OVER;
        g->winner = 1 - p;
        ++g->players[1 - p].stats.wins;
        printf("RESIGN %d\nWINNER %d\n", p + 1, 2 - p);
    } else if (strcmp(cmd, "HINT") == 0 || strcmp(cmd, "DENSITY") == 0) {
        if (g->phase == OVER) { puts("ERROR game over"); return; }
        int p = atoi(w[1]) - 1;
        if (strcmp(cmd, "HINT") == 0) {
            Strategy method = strategy(w[2]);
            Choice choice = choose(g, p, method);
            printf("HINT %d %s %s ", p + 1, w[2], cell_name(choice.cell).text);
            if (method == HUNT) puts(choice.step);
            else printf("%d\n", choice.info);
        } else {
            View view = make_view(g, p);
            int scores[CELLS];
            density(&view, scores);
            printf("DENSITY %d\n ", p + 1);
            for (int col = 1; col <= 10; ++col) printf("%5d", col);
            putchar('\n');
            for (int row = 0; row < 10; ++row) {
                putchar('A' + row);
                for (int col = 0; col < 10; ++col) {
                    int c = row * 10 + col;
                    if (view.cells[c] == UNKNOWN) printf("%5d", scores[c]);
                    else printf("%5s", view.cells[c] == REEF ? "~" : "-");
                }
                putchar('\n');
            }
            int best = best_cell(&view, scores);
            printf("BEST %s %d\n", cell_name(best).text, scores[best]);
        }
    } else if (strcmp(cmd, "SHOW") == 0 || strcmp(cmd, "RADAR") == 0) {
        show_board(g, atoi(w[1]) - 1, strcmp(cmd, "RADAR") == 0);
    } else if (strcmp(cmd, "EXPORT") == 0) {
        int p = atoi(w[1]) - 1;
        printf("EXPORT %d ", p + 1);
        for (int c = 0; c < CELLS; ++c) {
            if (c && c % 10 == 0) putchar('/');
            int s = g->players[p].board[c];
            putchar(s < 0 ? '.' : symbols[s]);
        }
        putchar('\n');
    } else if (strcmp(cmd, "FLEET") == 0) {
        int p = atoi(w[1]) - 1;
        const Player *player = &g->players[p];
        printf("FLEET %d afloat %d\n", p + 1, afloat(player));
        for (int s = 0; s < SHIPS; ++s) {
            Ship ship = player->fleet[s];
            if (ship.start < 0) printf("%s unplaced\n", ship_names[s]);
            else printf("%s %s-%s %d/%d %s\n", ship_names[s], cell_name(ship.start).text,
                        cell_name(ship.start + (lengths[s] - 1) * ship.step).text,
                        attacked_count(player, s), lengths[s], sunk(player, s) ? "SUNK" : "AFLOAT");
        }
    } else if (strcmp(cmd, "STATUS") == 0) {
        int reefs = 0;
        for (int c = 0; c < CELLS; ++c) reefs += g->reefs[c];
        printf("STATUS %s salvo %s chain %s touch %s reefs %d", phases[g->phase],
               g->salvo ? "ON" : "OFF", g->chain ? "ON" : "OFF", g->touch ? "ON" : "OFF", reefs);
        if (g->phase == SETUP) printf(" placed %d %d\n", placed(&g->players[0]), placed(&g->players[1]));
        else if (g->phase == BATTLE) printf(" turn %d shots %d afloat %d %d\n", g->current + 1,
            allowance(g, g->current), afloat(&g->players[0]), afloat(&g->players[1]));
        else printf(" winner %d afloat %d %d\n", g->winner + 1, afloat(&g->players[0]), afloat(&g->players[1]));
    } else if (strcmp(cmd, "STATS") == 0) print_stats(g);
    else if (strcmp(cmd, "MATCH") == 0) {
        Strategy a = strategy(w[3]), b = strategy(w[4]);
        printf("MATCH 1 %s 2 %s\n", w[3], w[4]);
        Match result = play_match(g, strtoll(w[1], NULL, 10), strtoll(w[2], NULL, 10), a, b, SINKS_ONLY);
        printf("RESULT winner %d shots %" PRId64 " %" PRId64 " hits %" PRId64 " %" PRId64 "\n",
               result.winner + 1, result.shots[0], result.shots[1], result.hits[0], result.hits[1]);
    } else if (strcmp(cmd, "SERIES") == 0) {
        int matches = atoi(w[1]);
        int64_t random = strtoll(w[2], NULL, 10), wins[2] = {0}, shots[2] = {0}, fastest[2] = {0};
        for (int i = 0; i < matches; ++i) {
            int64_t seed1 = random = advance(random);
            int64_t seed2 = random = advance(random);
            Match result = play_match(g, seed1, seed2, strategy(w[3]), strategy(w[4]), QUIET);
            int winner = result.winner;
            ++wins[winner];
            for (int p = 0; p < 2; ++p) shots[p] += result.shots[p];
            if (!fastest[winner] || result.shots[winner] < fastest[winner]) fastest[winner] = result.shots[winner];
        }
        printf("SERIES %d wins %" PRId64 " %" PRId64 " shots %" PRId64 " %" PRId64 " fastest",
               matches, wins[0], wins[1], shots[0], shots[1]);
        for (int p = 0; p < 2; ++p) {
            if (fastest[p]) printf(" %" PRId64, fastest[p]);
            else printf(" -");
        }
        putchar('\n');
    } else if (strcmp(cmd, "TOURNEY") == 0) {
        int matches = atoi(w[1]), order[] = {HUNT, PROB, RANDOM};
        int64_t random = strtoll(w[2], NULL, 10), wins[3] = {0}, shots[3] = {0};
        for (int a = HUNT; a <= RANDOM; ++a)
            for (int b = HUNT; b <= RANDOM; ++b)
                if (a != b)
                    for (int i = 0; i < matches; ++i) {
                        int64_t seed1 = random = advance(random);
                        int64_t seed2 = random = advance(random);
                        Match result = play_match(g, seed1, seed2, (Strategy)a, (Strategy)b, QUIET);
                        ++wins[result.winner == 0 ? a : b];
                        shots[a] += result.shots[0];
                        shots[b] += result.shots[1];
                    }
        for (int i = 1; i < 3; ++i) {
            int value = order[i], j = i;
            while (j > 0) {
                int previous = order[j - 1];
                if (wins[previous] > wins[value] ||
                    (wins[previous] == wins[value] && (shots[previous] < shots[value] ||
                     (shots[previous] == shots[value] && previous < value)))) break;
                order[j] = previous;
                --j;
            }
            order[j] = value;
        }
        printf("TOURNEY %d\n", matches);
        for (int i = 0; i < 3; ++i)
            printf("%d %s wins %" PRId64 " shots %" PRId64 "\n", i + 1, strategies[order[i]],
                   wins[order[i]], shots[order[i]]);
    }
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = malloc(capacity);
    if (!line) exit(EXIT_FAILURE);
    int c;
    while ((c = getchar()) != EOF && c != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            char *grown = realloc(line, capacity);
            if (!grown) { free(line); exit(EXIT_FAILURE); }
            line = grown;
        }
        line[length++] = (char)c;
    }
    if (c == EOF && length == 0) { free(line); return NULL; }
    line[length] = '\0';
    return line;
}

int main(void) {
    char *line = read_line();
    if (!line) return 0;
    int commands = atoi(line);
    free(line);
    Game game;
    init_game(&game);
    for (int i = 0; i < commands; ++i) {
        line = read_line();
        if (!line) break;
        char *words[8];
        int count = 0;
        for (char *word = strtok(line, " \r\n"); word; word = strtok(NULL, " \r\n")) words[count++] = word;
        command(&game, words, count);
        free(line);
    }
    return 0;
}
