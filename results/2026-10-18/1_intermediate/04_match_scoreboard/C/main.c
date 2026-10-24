#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum Sport { TENNIS, TABLETENNIS, BADMINTON, VOLLEYBALL, BOWLING, DARTS };
typedef struct { int a, b, kind, loser; } Segment;
typedef struct {
    int points[2], games[2], sets[2], substitutions[2], timeouts[2];
    int stats[2][10], lineup[2][6];
    Segment segments[7];
    int segment_count, server, winner;
} Rally;
typedef struct { int rolls[21], count; } BowlingState;
typedef struct {
    int remaining[2], legs[2], sets[2], stats[2][8], segments[9][2], turn[3];
    int segment_count, server, turn_start, turn_count, turn_score, leg_number, winner;
} DartsState;
typedef union { Rally rally; BowlingState bowling; DartsState darts; } State;
typedef struct {
    char id[9], names[2][13];
    int sport, first, sets, games, final, start, legs;
    bool no_ad;
    int initial_lineup[2][6];
    State state;
    State *history;
    int history_count, history_capacity;
} Match;
typedef struct {
    int start[10], count[10], score[10], standing, frame;
    bool closed[10], final[10], fresh, finished;
    char marks[21];
} BowlingInfo;
typedef struct { char name[5]; int value; bool is_double; } Dart;
typedef struct { char **items; int count, capacity; } Strings;
static Dart darts[63];
static Match matches[1000];
static int match_count;
static jmp_buf recovery;
static char error_message[64];

static void *allocate(size_t size) {
    void *p = malloc(size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}
static char *slice(const char *s, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, s, length);
    result[length] = '\0';
    return result;
}
static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, args);
    va_end(args);
    return result;
}
static void appendf(char **s, const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    size_t old = strlen(*s);
    *s = realloc(*s, old + (size_t)length + 1);
    if (!*s) exit(EXIT_FAILURE);
    vsnprintf(*s + old, (size_t)length + 1, pattern, args);
    va_end(args);
}
static void push_owned(Strings *s, char *item) {
    if (s->count == s->capacity) {
        s->capacity = s->capacity ? s->capacity * 2 : 8;
        s->items = realloc(s->items, (size_t)s->capacity * sizeof *s->items);
        if (!s->items) exit(EXIT_FAILURE);
    }
    s->items[s->count++] = item;
}
static void free_strings(Strings *s) {
    for (int i = 0; i < s->count; ++i) free(s->items[i]);
    free(s->items);
    *s = (Strings){0};
}
static Strings split(const char *s, char delimiter) {
    Strings result = {0};
    const char *start = s;
    for (const char *p = s;; ++p) {
        if (!*p || *p == delimiter) {
            push_owned(&result, slice(start, (size_t)(p - start)));
            start = p + 1;
            if (!*p) break;
        }
    }
    return result;
}
static void fail(const char *message) {
    snprintf(error_message, sizeof error_message, "%s", message);
    longjmp(recovery, 1);
}
static int maximum(int a, int b) { return a > b ? a : b; }
static void initialize_darts(void) {
    int count = 0;
    for (int group = 0; group < 3; ++group) {
        int value = group == 0 ? 1 : group == 1 ? 3 : 2;
        char prefix = value == 1 ? 'S' : value == 2 ? 'D' : 'T';
        for (int n = 20; n >= 1; --n) {
            snprintf(darts[count].name, sizeof darts[count].name, "%c%d", prefix, n);
            darts[count].value = value * n;
            darts[count].is_double = value == 2;
            ++count;
        }
    }
    darts[60] = (Dart){"25", 25, false};
    darts[61] = (Dart){"BULL", 50, true};
    darts[62] = (Dart){"MISS", 0, false};
}
static int double_dart(int value) {
    if (value == 50) return 61;
    if (value >= 2 && value <= 40 && value % 2 == 0) return 60 - value / 2;
    return -1;
}
static int checkout(int score, int maximum_darts, int *result) {
    int last = double_dart(score);
    if (last >= 0) {
        result[0] = last;
        return 1;
    }
    if (maximum_darts >= 2) {
        for (int i = 0; i < 62; ++i) {
            last = double_dart(score - darts[i].value);
            if (last >= 0) {
                result[0] = i;
                result[1] = last;
                return 2;
            }
        }
    }
    if (maximum_darts >= 3 && score <= 170) {
        for (int i = 0; i < 62; ++i) {
            for (int j = 0; j < 62; ++j) {
                last = double_dart(score - darts[i].value - darts[j].value);
                if (last >= 0) {
                    result[0] = i;
                    result[1] = j;
                    result[2] = last;
                    return 3;
                }
            }
        }
    }
    return 0;
}
static void append_darts(char **s, const int *ids, int count) {
    for (int i = 0; i < count; ++i) appendf(s, "%s%s", i ? " " : "", darts[ids[i]].name);
}
static BowlingInfo bowling_info(const BowlingState *state) {
    BowlingInfo info = {0};
    info.standing = 10;
    info.fresh = true;
    for (int i = 0; i < state->count; ++i) {
        int frame = info.frame, pins = state->rolls[i];
        if (!info.count[frame]) info.start[frame] = i;
        info.marks[i] = info.fresh && pins == 10 ? 'X' : pins == info.standing ? '/' : pins == 0 ? '-' : (char)('0' + pins);
        ++info.count[frame];
        info.standing -= pins;
        info.fresh = false;
        bool ended = false;
        if (frame < 9) ended = (pins == 10 && info.count[frame] == 1) || info.count[frame] == 2;
        else if (info.count[frame] == 2) ended = state->rolls[info.start[frame]] + pins < 10;
        else if (info.count[frame] == 3) ended = true;
        if (ended) {
            info.closed[frame] = true;
            if (frame == 9) info.finished = true;
            else ++info.frame;
            info.standing = 10;
            info.fresh = true;
        } else if (frame == 9 && info.standing == 0) {
            info.standing = 10;
            info.fresh = true;
        }
    }
    for (int frame = 0; frame < 10; ++frame) {
        if (!info.count[frame]) continue;
        int start = info.start[frame];
        if (frame == 9) {
            info.final[frame] = info.closed[frame];
            for (int j = 0; j < info.count[frame]; ++j) info.score[frame] += state->rolls[start + j];
        } else if (state->rolls[start] == 10) {
            info.final[frame] = state->count >= start + 3;
            if (info.final[frame]) info.score[frame] = 10 + state->rolls[start + 1] + state->rolls[start + 2];
        } else if (info.count[frame] >= 2) {
            int total = state->rolls[start] + state->rolls[start + 1];
            info.final[frame] = total < 10 || state->count >= start + 3;
            if (info.final[frame]) info.score[frame] = total + (total == 10 ? state->rolls[start + 2] : 0);
        }
    }
    return info;
}
static int bowling_total(const BowlingInfo *info) {
    int total = 0;
    for (int i = 0; i < 10; ++i) total += info->score[i];
    return total;
}
static bool final_set(const Match *m, const Rally *s) { return s->sets[0] == m->sets / 2 && s->sets[1] == m->sets / 2; }
static int tennis_kind(const Match *m, const Rally *s) {
    if (final_set(m, s) && m->final == 3) return 2;
    if (s->games[0] == 6 && s->games[1] == 6 && !(final_set(m, s) && m->final == 2)) return 1;
    return 0;
}
static int rally_server(const Match *m, const Rally *s) {
    if (m->sport == TENNIS && tennis_kind(m, s)) return s->server ^ (((s->points[0] + s->points[1] + 1) / 2) % 2);
    if (m->sport == TABLETENNIS) {
        int first = m->first ^ (s->segment_count % 2), played = s->points[0] + s->points[1];
        return first ^ (played < 20 ? played / 2 % 2 : played % 2);
    }
    return s->server;
}
static bool normal_game(const Match *m, int own, int other) { return own >= 4 && (m->no_ad || own - other >= 2); }
static void add_rally(const Match *m, Rally *s, int side) {
    int other = 1 - side, server = rally_server(m, s);
    ++s->stats[side][0];
    ++s->stats[server][1];
    if (side == server) ++s->stats[side][2];
    ++s->stats[side][3];
    s->stats[other][3] = 0;
    s->stats[side][4] = maximum(s->stats[side][4], s->stats[side][3]);
    int kind = m->sport == TENNIS ? tennis_kind(m, s) : 0;
    if (m->sport == TENNIS && !kind) {
        int receiver = 1 - s->server;
        if (normal_game(m, s->points[receiver] + 1, s->points[s->server])) {
            ++s->stats[receiver][8];
            if (side == receiver) ++s->stats[receiver][9];
        }
    }
    ++s->points[side];
    if (m->sport == TENNIS) {
        int target = kind == 2 || (kind == 1 && final_set(m, s) && m->final == 1) ? 10 : 7;
        bool ended = kind ? s->points[side] >= target && s->points[side] - s->points[other] >= 2 : normal_game(m, s->points[side], s->points[other]);
        if (!ended) return;
        Segment segment;
        if (!kind) {
            ++s->stats[s->server][5];
            if (side == s->server) ++s->stats[side][6];
            else ++s->stats[side][7];
        }
        if (kind == 2) segment = (Segment){s->points[0], s->points[1], 2, 0};
        else {
            ++s->games[side];
            segment = (Segment){s->games[0], s->games[1], kind, kind ? s->points[other] : 0};
        }
        s->server ^= 1;
        memset(s->points, 0, sizeof s->points);
        bool set_ended = kind || (s->games[side] >= 6 && s->games[side] - s->games[other] >= 2);
        if (set_ended) {
            s->segments[s->segment_count++] = segment;
            ++s->sets[side];
            memset(s->games, 0, sizeof s->games);
            if (s->sets[side] == m->sets / 2 + 1) s->winner = side;
        }
        return;
    }
    if (m->sport == VOLLEYBALL && side != s->server) {
        s->server = side;
        int first = s->lineup[side][0];
        memmove(s->lineup[side], s->lineup[side] + 1, 5 * sizeof(int));
        s->lineup[side][5] = first;
    }
    if (m->sport == BADMINTON) s->server = side;
    int target = m->sport == TABLETENNIS ? 11 : m->sport == BADMINTON ? 21 : s->segment_count == 4 ? 15 : 25;
    bool ended = s->points[side] >= target && s->points[side] - s->points[other] >= 2;
    if (m->sport == BADMINTON && s->points[side] == 30) ended = true;
    if (!ended) return;
    s->segments[s->segment_count++] = (Segment){s->points[0], s->points[1], 0, 0};
    ++s->sets[side];
    int needed = m->sport == TABLETENNIS ? m->games / 2 + 1 : m->sport == BADMINTON ? 2 : 3;
    if (s->sets[side] == needed) s->winner = side;
    else {
        memset(s->points, 0, sizeof s->points);
        if (m->sport == VOLLEYBALL) {
            memcpy(s->lineup, m->initial_lineup, sizeof s->lineup);
            memset(s->substitutions, 0, sizeof s->substitutions);
            memset(s->timeouts, 0, sizeof s->timeouts);
            s->server = m->first ^ (s->segment_count % 2);
        }
    }
}
static void end_darts_turn(DartsState *s) {
    s->server ^= 1;
    s->turn_start = s->remaining[s->server];
    s->turn_count = s->turn_score = 0;
}
static void completed_darts_turn(DartsState *s, int side) {
    s->stats[side][3] = maximum(s->stats[side][3], s->turn_score);
    if (s->turn_score >= 100) ++s->stats[side][4];
    if (s->turn_score == 180) ++s->stats[side][5];
}
static void add_dart(const Match *m, DartsState *s, int id) {
    int side = s->server, remaining = s->remaining[side];
    Dart dart = darts[id];
    ++s->stats[side][0];
    if (remaining == 50 || (remaining <= 40 && remaining % 2 == 0)) ++s->stats[side][6];
    s->turn[s->turn_count++] = id;
    s->turn_score += dart.value;
    s->stats[side][1] += dart.value;
    int after = remaining - dart.value;
    if (after < 0 || after == 1 || (after == 0 && !dart.is_double)) {
        s->stats[side][1] -= s->turn_score;
        ++s->stats[side][2];
        s->remaining[side] = s->turn_start;
        end_darts_turn(s);
        return;
    }
    s->remaining[side] = after;
    if (!after) {
        ++s->stats[side][7];
        completed_darts_turn(s, side);
        ++s->legs[side];
        if (s->legs[side] == m->legs) {
            memcpy(s->segments[s->segment_count++], s->legs, sizeof s->legs);
            ++s->sets[side];
            if (s->sets[side] == m->sets) {
                s->winner = side;
                return;
            }
            memset(s->legs, 0, sizeof s->legs);
        }
        ++s->leg_number;
        s->remaining[0] = s->remaining[1] = m->start;
        s->server = m->first ^ ((s->leg_number - 1) % 2);
        s->turn_start = m->start;
        s->turn_count = s->turn_score = 0;
    } else if (s->turn_count == 3) {
        completed_darts_turn(s, side);
        end_darts_turn(s);
    }
}
static bool finished(const Match *m) {
    if (m->sport == BOWLING) return bowling_info(&m->state.bowling).finished;
    return m->sport == DARTS ? m->state.darts.winner >= 0 : m->state.rally.winner >= 0;
}
static int winner(const Match *m) { return m->sport == DARTS ? m->state.darts.winner : m->state.rally.winner; }
static void append_segment(char **line, const Segment *s, int first) {
    int a = first ? s->b : s->a, b = first ? s->a : s->b;
    appendf(line, s->kind == 2 ? " [%d-%d]" : " %d-%d", a, b);
    if (s->kind == 1) appendf(line, "(%d)", s->loser);
}
static const char *situation(const Match *m, const Rally *s, int side) {
    Rally next = *s;
    add_rally(m, &next, side);
    if (next.winner >= 0) return "match point";
    if (next.segment_count != s->segment_count) return m->sport == TABLETENNIS || m->sport == BADMINTON ? "game point" : "set point";
    if (m->sport == TENNIS && tennis_kind(m, s) == 0 && next.server != s->server) return rally_server(m, s) == side ? "game point" : "break point";
    return "";
}
static char *score(const Match *m) {
    if (m->sport == BOWLING) {
        const BowlingState *s = &m->state.bowling;
        BowlingInfo info = bowling_info(s);
        char *line = format("%s: %s", m->id, m->names[0]);
        int cumulative = 0;
        for (int frame = 0; frame < 10; ++frame) {
            if (!info.count[frame]) continue;
            appendf(&line, " ");
            for (int j = 0; j < info.count[frame]; ++j) appendf(&line, "%c", info.marks[info.start[frame] + j]);
            cumulative += info.score[frame];
            if (info.final[frame]) appendf(&line, "(%d)", cumulative);
        }
        return line;
    }
    int server = m->sport == DARTS ? m->state.darts.server : rally_server(m, &m->state.rally);
    bool over = finished(m);
    char *line = format("%s: %s%s vs %s%s", m->id, m->names[0], !over && server == 0 ? "*" : "", m->names[1], !over && server == 1 ? "*" : "");
    if (m->sport == DARTS) {
        const DartsState *s = &m->state.darts;
        appendf(&line, " sets %d-%d legs %d-%d score %d-%d", s->sets[0], s->sets[1], s->legs[0], s->legs[1], s->remaining[0], s->remaining[1]);
        if (!over) {
            if (s->turn_count) {
                appendf(&line, " turn ");
                append_darts(&line, s->turn, s->turn_count);
            }
            int ids[3], count = checkout(s->remaining[s->server], 3 - s->turn_count, ids);
            if (count) {
                appendf(&line, " checkout ");
                append_darts(&line, ids, count);
            }
        }
        return line;
    }
    const Rally *s = &m->state.rally;
    for (int i = 0; i < s->segment_count; ++i) append_segment(&line, &s->segments[i], 0);
    if (!over) {
        if (m->sport == TENNIS) {
            int kind = tennis_kind(m, s);
            if (kind == 2) appendf(&line, " [%d-%d]", s->points[0], s->points[1]);
            else {
                appendf(&line, " %d-%d ", s->games[0], s->games[1]);
                if (kind) appendf(&line, "%d-%d", s->points[0], s->points[1]);
                else if (!m->no_ad && s->points[0] >= 3 && s->points[1] >= 3) appendf(&line, "%s", s->points[0] == s->points[1] ? "40-40" : s->points[0] > s->points[1] ? "AD-40" : "40-AD");
                else {
                    const char *names[] = {"0", "15", "30", "40"};
                    appendf(&line, "%s-%s", names[s->points[0]], names[s->points[1]]);
                }
            }
        } else {
            appendf(&line, " %d-%d", s->points[0], s->points[1]);
            if (m->sport == VOLLEYBALL) appendf(&line, " server %d", s->lineup[s->server][0]);
        }
        for (int side = 0; side < 2; ++side) {
            const char *label = situation(m, s, side);
            if (*label) appendf(&line, " (%s %s)", label, m->names[side]);
        }
    }
    return line;
}
static void statistics(const Match *m, Strings *out) {
    if (m->sport == BOWLING) {
        BowlingState s = m->state.bowling;
        BowlingInfo info = bowling_info(&s);
        int strikes = 0, spares = 0, open = 0;
        for (int i = 0; i < s.count; ++i) {
            strikes += info.marks[i] == 'X';
            spares += info.marks[i] == '/';
        }
        for (int i = 0; i < 10; ++i) {
            int start = info.start[i];
            if (info.count[i] >= 2 && s.rolls[start] != 10 && s.rolls[start] + s.rolls[start + 1] < 10) ++open;
        }
        while (!info.finished) {
            s.rolls[s.count++] = info.standing;
            info = bowling_info(&s);
        }
        push_owned(out, format("%s %s: strikes %d spares %d open %d max %d", m->id, m->names[0], strikes, spares, open, bowling_total(&info)));
        return;
    }
    for (int side = 0; side < 2; ++side) {
        char *line = format("%s %s: ", m->id, m->names[side]);
        if (m->sport == DARTS) {
            const int *s = m->state.darts.stats[side];
            int average = s[0] ? s[1] * 300 / s[0] : 0;
            appendf(&line, "darts %d average %d.%02d busts %d high %d tons %d 180s %d doubles %d/%d", s[0], average / 100, average % 100, s[2], s[3], s[4], s[5], s[7], s[6]);
        } else {
            const Rally *r = &m->state.rally;
            const int *s = r->stats[side];
            appendf(&line, "points %d serve %d/%d run %d", s[0], s[2], s[1], s[4]);
            if (m->sport == TENNIS) appendf(&line, " holds %d/%d breaks %d break points %d/%d", s[6], s[5], s[7], s[9], s[8]);
            if (m->sport == VOLLEYBALL) {
                appendf(&line, " subs %d timeouts %d lineup ", r->substitutions[side], r->timeouts[side]);
                for (int i = 0; i < 6; ++i) appendf(&line, "%s%d", i ? "," : "", r->lineup[side][i]);
            }
        }
        push_owned(out, line);
    }
}
static char *result(const Match *m) {
    if (!finished(m)) fail("match not finished");
    if (m->sport == BOWLING) {
        BowlingInfo info = bowling_info(&m->state.bowling);
        return format("%s: %s %d", m->id, m->names[0], bowling_total(&info));
    }
    int first = winner(m);
    char *line = format("%s: %s def. %s", m->id, m->names[first], m->names[1 - first]);
    if (m->sport == DARTS) {
        const DartsState *s = &m->state.darts;
        for (int i = 0; i < s->segment_count; ++i) appendf(&line, " %d-%d", s->segments[i][first], s->segments[i][1 - first]);
    } else {
        const Rally *s = &m->state.rally;
        for (int i = 0; i < s->segment_count; ++i) append_segment(&line, &s->segments[i], first);
    }
    return line;
}
static Match *find_match(const char *id) {
    for (int i = 0; i < match_count; ++i) if (!strcmp(matches[i].id, id)) return &matches[i];
    return NULL;
}
static void create_match(const Strings *a) {
    if (find_match(a->items[1])) fail("duplicate match");
    Match m = {0};
    strcpy(m.id, a->items[1]);
    const char *sports[] = {"TENNIS", "TABLETENNIS", "BADMINTON", "VOLLEYBALL", "BOWLING", "DARTS"};
    for (int i = 0; i < 6; ++i) if (!strcmp(sports[i], a->items[2])) m.sport = i;
    strcpy(m.names[0], a->items[3]);
    if (m.sport != BOWLING) strcpy(m.names[1], a->items[4]);
    m.sets = m.sport == DARTS ? 1 : 3;
    m.games = 5;
    m.start = 501;
    m.legs = 1;
    int option_start = m.sport == BOWLING ? 4 : m.sport == VOLLEYBALL ? 7 : 5;
    const char *keys[] = {"FIRST", "SETS", "GAMES", "DEUCE", "FINAL", "START", "LEGS"};
    const char *values[] = {"A B", "3 5", "5 7", "AD NOAD", "TB7 TB10 ADV SUPER", "301 501 701", "1 2 3 4 5"};
    bool seen[7] = {false};
    for (int i = option_start; i < a->count; ++i) {
        Strings option = split(a->items[i], '=');
        int key = -1;
        if (option.count == 2) {
            for (int j = 0; j < 7; ++j) if (!strcmp(keys[j], option.items[0])) key = j;
        }
        bool allowed = key == 0 && m.sport != BOWLING
            || key == 1 && (m.sport == TENNIS || m.sport == DARTS)
            || key == 2 && m.sport == TABLETENNIS
            || (key == 3 || key == 4) && m.sport == TENNIS
            || (key == 5 || key == 6) && m.sport == DARTS;
        if (!allowed || seen[key]) {
            free_strings(&option);
            fail("invalid option");
        }
        Strings choices = split(key == 1 && m.sport == DARTS ? values[6] : values[key], ' ');
        int choice = -1;
        for (int j = 0; j < choices.count; ++j) if (!strcmp(choices.items[j], option.items[1])) choice = j;
        if (choice < 0) {
            free_strings(&choices);
            free_strings(&option);
            fail("invalid option");
        }
        seen[key] = true;
        if (key == 0) m.first = choice;
        if (key == 1) m.sets = atoi(option.items[1]);
        if (key == 2) m.games = atoi(option.items[1]);
        if (key == 3) m.no_ad = choice == 1;
        if (key == 4) m.final = choice;
        if (key == 5) m.start = atoi(option.items[1]);
        if (key == 6) m.legs = atoi(option.items[1]);
        free_strings(&choices);
        free_strings(&option);
    }
    if (m.sport == DARTS) {
        m.state.darts.remaining[0] = m.state.darts.remaining[1] = m.start;
        m.state.darts.server = m.first;
        m.state.darts.turn_start = m.start;
        m.state.darts.leg_number = 1;
        m.state.darts.winner = -1;
    } else if (m.sport != BOWLING) {
        m.state.rally.server = m.first;
        m.state.rally.winner = -1;
        if (m.sport == VOLLEYBALL) {
            for (int side = 0; side < 2; ++side) {
                Strings numbers = split(a->items[5 + side], ',');
                for (int i = 0; i < 6; ++i) m.initial_lineup[side][i] = atoi(numbers.items[i]);
                free_strings(&numbers);
            }
            memcpy(m.state.rally.lineup, m.initial_lineup, sizeof m.initial_lineup);
        }
    }
    matches[match_count++] = m;
}
typedef struct { char name[13]; int wins, losses; } Standing;
static int compare_standings(const void *left, const void *right) {
    const Standing *a = left, *b = right;
    if (a->wins != b->wins) return a->wins > b->wins ? -1 : 1;
    if (a->losses != b->losses) return a->losses < b->losses ? -1 : 1;
    return strcmp(a->name, b->name);
}
static char *standings(void) {
    Standing rows[2000] = {0};
    int count = 0;
    for (int i = 0; i < match_count; ++i) {
        Match *m = &matches[i];
        if (m->sport == BOWLING || !finished(m)) continue;
        int winning_side = winner(m);
        for (int side = 0; side < 2; ++side) {
            int id = 0;
            while (id < count && strcmp(rows[id].name, m->names[side])) ++id;
            if (id == count) strcpy(rows[count++].name, m->names[side]);
            if (side == winning_side) ++rows[id].wins;
            else ++rows[id].losses;
        }
    }
    if (count > 1) qsort(rows, count, sizeof *rows, compare_standings);
    char *line = format("standings: ");
    if (!count) appendf(&line, "none");
    for (int i = 0; i < count; ++i) appendf(&line, "%s%s %d-%d", i ? ", " : "", rows[i].name, rows[i].wins, rows[i].losses);
    return line;
}
static void remember(Match *m) {
    if (m->history_count == m->history_capacity) {
        m->history_capacity = m->history_capacity ? m->history_capacity * 2 : 16;
        m->history = realloc(m->history, (size_t)m->history_capacity * sizeof *m->history);
        if (!m->history) exit(EXIT_FAILURE);
    }
    m->history[m->history_count++] = m->state;
}
static void execute(const Strings *a, Strings *out) {
    const char *command = a->items[0];
    if (!strcmp(command, "MATCH")) {
        create_match(a);
        return;
    }
    if (!strcmp(command, "CHECKOUT")) {
        int ids[3], count = checkout(atoi(a->items[1]), 3, ids);
        char *line = format("checkout %s: ", a->items[1]);
        if (count) append_darts(&line, ids, count);
        else appendf(&line, "none");
        push_owned(out, line);
        return;
    }
    if (!strcmp(command, "STANDINGS")) {
        push_owned(out, standings());
        return;
    }
    Match *m = find_match(a->items[1]);
    if (!m) fail("unknown match");
    if (!strcmp(command, "SCORE")) {
        push_owned(out, score(m));
        return;
    }
    if (!strcmp(command, "STATS")) {
        statistics(m, out);
        return;
    }
    if (!strcmp(command, "RESULT")) {
        push_owned(out, result(m));
        return;
    }
    if (!strcmp(command, "UNDO")) {
        if (!m->history_count) fail("nothing to undo");
        m->state = m->history[--m->history_count];
        return;
    }
    bool point = !strcmp(command, "POINT"), roll = !strcmp(command, "ROLL"), dart = !strcmp(command, "THROW");
    bool sub = !strcmp(command, "SUB"), timeout = !strcmp(command, "TIMEOUT");
    if (!((point && m->sport <= VOLLEYBALL) || (roll && m->sport == BOWLING) || (dart && m->sport == DARTS) || ((sub || timeout) && m->sport == VOLLEYBALL))) fail("wrong event");
    int count = point ? (int)strlen(a->items[2]) : roll || dart ? a->count - 2 : 1;
    for (int i = 0; i < count; ++i) {
        if (finished(m)) fail("match over");
        int value = 0, position = -1, side = 0;
        if (point) value = a->items[2][i] == 'B';
        if (roll) {
            value = atoi(a->items[i + 2]);
            if (value > bowling_info(&m->state.bowling).standing) fail("too many pins");
        }
        if (dart) {
            value = -1;
            for (int j = 0; j < 63; ++j) if (!strcmp(darts[j].name, a->items[i + 2])) value = j;
            if (value < 0) fail("invalid dart");
        }
        if (sub || timeout) {
            side = !strcmp(a->items[2], "B");
            const Rally *s = &m->state.rally;
            if (timeout) {
                if (s->timeouts[side] >= 2) fail("no timeouts left");
            } else {
                int leaving = atoi(a->items[3]);
                value = atoi(a->items[4]);
                for (int j = 0; j < 6; ++j) if (s->lineup[side][j] == leaving) position = j;
                if (position < 0) fail("player not on court");
                for (int j = 0; j < 6; ++j) if (s->lineup[side][j] == value) fail("player already on court");
                if (s->substitutions[side] >= 6) fail("no substitutions left");
            }
        }
        remember(m);
        if (point) add_rally(m, &m->state.rally, value);
        if (roll) {
            BowlingState *s = &m->state.bowling;
            s->rolls[s->count++] = value;
        }
        if (dart) add_dart(m, &m->state.darts, value);
        if (sub) {
            m->state.rally.lineup[side][position] = value;
            ++m->state.rally.substitutions[side];
        }
        if (timeout) ++m->state.rally.timeouts[side];
    }
}
int main(void) {
    initialize_darts();
    char line[400];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        line[strcspn(line, "\n")] = '\0';
        Strings a = split(line, ' ');
        if (setjmp(recovery) == 0) {
            Strings out = {0};
            execute(&a, &out);
            for (int j = 0; j < out.count; ++j) puts(out.items[j]);
            free_strings(&out);
        } else printf("ERROR %s\n", error_message);
        free_strings(&a);
    }
    for (int i = 0; i < match_count; ++i) free(matches[i].history);
    return 0;
}
