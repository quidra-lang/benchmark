#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

enum { MAX_CANDIDATES = 7, MAX_GROUPS = 10000, MAX_ENTRIES = 1000, SUBSETS = 128 };
typedef unsigned Field;
typedef struct { int items[MAX_CANDIDATES], count; } List;
typedef struct { int votes; List ranking; } Ballot;
typedef struct {
    int first[MAX_CANDIDATES], last[MAX_CANDIDATES], borda[MAX_CANDIDATES];
    int approval[MAX_CANDIDATES][MAX_CANDIDATES], nonblank;
    bool ready;
} Tallies;
typedef struct {
    int number, count, total, group_count, entry_count;
    char names[MAX_CANDIDATES][13];
    Field active;
    List tiebreak;
    int priority[MAX_CANDIDATES], entry_ends[MAX_ENTRIES];
    Ballot groups[MAX_GROUPS];
    Tallies cache[SUBSETS];
    int pairwise[MAX_CANDIDATES][MAX_CANDIDATES];
    bool pairs_ready;
} Election;
typedef enum {
    PLURALITY, RUNOFF, IRV, COOMBS, BUCKLIN, BORDA, BALDWIN, NANSON, BLACK,
    VETO, CONDORCET, COPELAND, MINIMAX, SCHULZE, RANKEDPAIRS, KEMENY, APPROVAL, STV
} MethodKind;
typedef struct { MethodKind kind; int parameter; } Method;
typedef struct { List order; bool tie; } Result;
typedef struct { char data[512]; size_t length; } Text;

static const char *const method_names[] = {
    "PLURALITY", "RUNOFF", "IRV", "COOMBS", "BUCKLIN", "BORDA", "BALDWIN", "NANSON", "BLACK",
    "VETO", "CONDORCET", "COPELAND", "MINIMAX", "SCHULZE", "RANKEDPAIRS", "KEMENY", "APPROVAL", "STV"
};
static const Method summary_methods[] = {
    {PLURALITY, 0}, {RUNOFF, 0}, {IRV, 0}, {COOMBS, 0}, {BUCKLIN, 0}, {BORDA, 0},
    {BALDWIN, 0}, {NANSON, 0}, {BLACK, 0}, {VETO, 0}, {COPELAND, 0}, {MINIMAX, 0},
    {SCHULZE, 0}, {RANKEDPAIRS, 0}, {KEMENY, 0}
};

static void append(Text *text, const char *format, ...) {
    va_list args;
    va_start(args, format);
    int added = vsnprintf(text->data + text->length, sizeof text->data - text->length, format, args);
    va_end(args);
    text->length += (size_t)added;
}

static void emit(FILE *output, const char *format, ...) {
    if (!output) return;
    va_list args;
    va_start(args, format);
    vfprintf(output, format, args);
    va_end(args);
}

static void error(const char *format, ...) {
    fputs("ERROR ", stdout);
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    putchar('\n');
}

static Field bit(int candidate) { return 1U << candidate; }
static List members(Field field) {
    List result = {0};
    for (int a = 0; a < MAX_CANDIDATES; ++a)
        if (field & bit(a)) result.items[result.count++] = a;
    return result;
}
static Field mask(List list) {
    Field result = 0;
    for (int i = 0; i < list.count; ++i) result |= bit(list.items[i]);
    return result;
}
static int position(List list, int candidate) {
    for (int i = 0; i < list.count; ++i) if (list.items[i] == candidate) return i;
    return -1;
}
static List effective(List ranking, Field field) {
    List result = {0};
    for (int i = 0; i < ranking.count; ++i)
        if (field & bit(ranking.items[i])) result.items[result.count++] = ranking.items[i];
    return result;
}
static Text names(const Election *e, List list, const char *separator) {
    Text result = {0};
    for (int i = 0; i < list.count; ++i)
        append(&result, "%s%s", i ? separator : "", e->names[list.items[i]]);
    return result;
}
static Text values(const Election *e, Field field, const int scores[], bool cents) {
    Text result = {0};
    List list = members(field);
    for (int i = 0; i < list.count; ++i) {
        int a = list.items[i];
        append(&result, "%s%s ", i ? ", " : "", e->names[a]);
        if (cents) append(&result, "%d.%02d", scores[a] / 100, scores[a] % 100);
        else append(&result, "%d", scores[a]);
    }
    return result;
}
static const char *tie_mark(bool tie) { return tie ? " (tie)" : ""; }
static void winner(FILE *output, const Election *e, Result result) {
    emit(output, "winner: %s%s\n", e->names[result.order.items[0]], tie_mark(result.tie));
}
static List ordered(const Election *e, Field field, const int scores[], bool descending) {
    List result = members(field);
    for (int i = 1; i < result.count; ++i) {
        int a = result.items[i], j = i;
        while (j > 0) {
            int b = result.items[j - 1];
            bool before = scores[a] == scores[b] ? e->priority[a] < e->priority[b]
                : descending ? scores[a] > scores[b] : scores[a] < scores[b];
            if (!before) break;
            result.items[j] = b;
            --j;
        }
        result.items[j] = a;
    }
    return result;
}
static Result scored(const Election *e, Field field, const int scores[], bool descending) {
    Result result = {.order = ordered(e, field, scores, descending)};
    result.tie = result.order.count > 1 && scores[result.order.items[0]] == scores[result.order.items[1]];
    return result;
}
static int earliest(const Election *e, Field field) {
    for (int i = 0; i < e->count; ++i) if (field & bit(e->tiebreak.items[i])) return e->tiebreak.items[i];
    return -1;
}
static void invalidate(Election *e) {
    for (int i = 0; i < SUBSETS; ++i) e->cache[i].ready = false;
    e->pairs_ready = false;
}
static Tallies *tallies(Election *e, Field field) {
    Tallies *result = &e->cache[field];
    if (result->ready) return result;
    *result = (Tallies){0};
    List candidates = members(field);
    int m = candidates.count;
    for (int i = 0; i < e->group_count; ++i) {
        Ballot group = e->groups[i];
        List rank = effective(group.ranking, field);
        Field ranked = mask(rank);
        if (rank.count) {
            result->first[rank.items[0]] += group.votes;
            result->nonblank += group.votes;
        }
        if (rank.count == m) result->last[rank.items[m - 1]] += group.votes;
        else for (int j = 0; j < m; ++j)
            if (!(ranked & bit(candidates.items[j]))) result->last[candidates.items[j]] += group.votes;
        for (int j = 0; j < rank.count; ++j) {
            int a = rank.items[j];
            result->borda[a] += group.votes * (m - j - 1);
            for (int depth = j; depth < m; ++depth) result->approval[depth][a] += group.votes;
        }
    }
    result->ready = true;
    return result;
}
static void pairwise(Election *e) {
    if (e->pairs_ready) return;
    memset(e->pairwise, 0, sizeof e->pairwise);
    for (int i = 0; i < e->group_count; ++i) {
        Ballot group = e->groups[i];
        int positions[MAX_CANDIDATES];
        for (int a = 0; a < e->count; ++a) positions[a] = MAX_CANDIDATES;
        for (int j = 0; j < group.ranking.count; ++j) positions[group.ranking.items[j]] = j;
        for (int a = 0; a < e->count; ++a) for (int b = 0; b < e->count; ++b)
            if (positions[a] < positions[b]) e->pairwise[a][b] += group.votes;
    }
    e->pairs_ready = true;
}
static int condorcet(Election *e, Field field, bool loser) {
    pairwise(e);
    List list = members(field);
    for (int i = 0; i < list.count; ++i) {
        int a = list.items[i];
        bool all = true;
        for (int j = 0; j < list.count; ++j) if (i != j) {
            int b = list.items[j];
            if (loser ? e->pairwise[a][b] >= e->pairwise[b][a] : e->pairwise[a][b] <= e->pairwise[b][a]) all = false;
        }
        if (all) return a;
    }
    return -1;
}
static int sum(Field field, const int scores[]) {
    int result = 0;
    for (int a = 0; a < MAX_CANDIDATES; ++a) if (field & bit(a)) result += scores[a];
    return result;
}
static bool majority(Field field, const int scores[]) {
    int total = sum(field, scores);
    for (int a = 0; a < MAX_CANDIDATES; ++a) if ((field & bit(a)) && 2 * scores[a] > total) return true;
    return false;
}
static int look_back(const Election *e, Field field, int history[][MAX_CANDIDATES], int rounds, bool *tie) {
    Field choices = field;
    for (int r = rounds - 1; r >= 0; --r) {
        int least = 2147483647;
        List list = members(choices);
        for (int i = 0; i < list.count; ++i) if (history[r][list.items[i]] < least) least = history[r][list.items[i]];
        for (int i = 0; i < list.count; ++i) if (history[r][list.items[i]] != least) choices &= ~bit(list.items[i]);
        if (r == rounds - 1) *tie = members(choices).count > 1;
    }
    for (int i = e->count - 1; i >= 0; --i) if (choices & bit(e->tiebreak.items[i])) return e->tiebreak.items[i];
    return -1;
}
static Result elimination(Election *e, Field field, MethodKind kind, FILE *output, bool exhausted) {
    Field remaining = field;
    List removed = {0};
    int history[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}}, round = 0;
    for (;;) {
        Tallies *current = tallies(e, remaining);
        ++round;
        bool done = members(remaining).count == 1 || majority(remaining, current->first);
        if (exhausted) {
            int active = sum(remaining, current->first);
            emit(output, "round %d: active %d, exhausted %d\n", round, active, e->total - active);
        } else emit(output, "round %d: %s", round, values(e, remaining, current->first, false).data);
        if (done) {
            if (!exhausted) emit(output, "\n");
            Result result = {.order = ordered(e, remaining, current->first, true)};
            for (int i = removed.count - 1; i >= 0; --i) result.order.items[result.order.count++] = removed.items[i];
            if (!exhausted) winner(output, e, result);
            return result;
        }
        bool tie = false;
        int eliminated;
        if (kind == COOMBS) {
            List worst = ordered(e, remaining, current->last, true);
            int maximum = current->last[worst.items[0]];
            Field choices = 0;
            for (int i = 0; i < worst.count; ++i) if (current->last[worst.items[i]] == maximum) choices |= bit(worst.items[i]);
            tie = members(choices).count > 1;
            List least = ordered(e, choices, current->first, true);
            eliminated = least.items[least.count - 1];
            emit(output, "; last %s", values(e, remaining, current->last, false).data);
        } else {
            memcpy(history[round - 1], current->first, sizeof current->first);
            eliminated = look_back(e, remaining, history, round, &tie);
        }
        if (!exhausted) emit(output, "; eliminated %s%s\n", e->names[eliminated], tie_mark(tie));
        removed.items[removed.count++] = eliminated;
        remaining &= ~bit(eliminated);
    }
}
static Result runoff(Election *e, Field field, FILE *output) {
    Tallies *first = tallies(e, field);
    Result result = {.order = ordered(e, field, first->first, true)};
    emit(output, "round 1: %s\n", values(e, field, first->first, false).data);
    if (!majority(field, first->first)) {
        int a = result.order.items[0], b = result.order.items[1];
        Field finalists = bit(a) | bit(b);
        bool advance_tie = result.order.count >= 3 && first->first[b] == first->first[result.order.items[2]];
        Tallies *second = tallies(e, finalists);
        result.tie = second->first[a] == second->first[b];
        if (second->first[b] > second->first[a]) {
            result.order.items[0] = b;
            result.order.items[1] = a;
        }
        emit(output, "finalists: %s%s\n", names(e, members(finalists), ", ").data, tie_mark(advance_tie));
        emit(output, "round 2: %s\n", values(e, finalists, second->first, false).data);
    }
    winner(output, e, result);
    return result;
}
static Result bucklin(Election *e, Field field, FILE *output) {
    Tallies *scores = tallies(e, field);
    int line = scores->nonblank / 2 + 1, final = 0;
    List list = members(field);
    emit(output, "majority: %d\n", line);
    for (int depth = 0; depth < list.count; ++depth) {
        final = depth;
        emit(output, "round %d: %s\n", depth + 1, values(e, field, scores->approval[depth], false).data);
        bool done = false;
        for (int i = 0; i < list.count; ++i) if (scores->approval[depth][list.items[i]] >= line) done = true;
        if (done) break;
    }
    Result result = {.order = list};
    for (int i = 1; i < list.count; ++i) {
        int a = result.order.items[i], j = i;
        while (j > 0) {
            int b = result.order.items[j - 1], depth = final;
            while (depth >= 0 && scores->approval[depth][a] == scores->approval[depth][b]) --depth;
            bool before = depth < 0 ? e->priority[a] < e->priority[b] : scores->approval[depth][a] > scores->approval[depth][b];
            if (!before) break;
            result.order.items[j--] = b;
        }
        result.order.items[j] = a;
    }
    result.tie = list.count > 1 && scores->approval[final][result.order.items[0]] == scores->approval[final][result.order.items[1]];
    winner(output, e, result);
    return result;
}
static Result borda_elimination(Election *e, Field field, bool nanson, FILE *output) {
    Field remaining = field;
    List tail = {0};
    int history[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}}, round = 0;
    while (members(remaining).count >= 2) {
        Tallies *scores = tallies(e, remaining);
        ++round;
        emit(output, "round %d: %s", round, values(e, remaining, scores->borda, false).data);
        List removed;
        if (nanson) {
            int total = sum(remaining, scores->borda), size = members(remaining).count;
            Field below = 0;
            for (int a = 0; a < e->count; ++a) if ((remaining & bit(a)) && scores->borda[a] * size < total) below |= bit(a);
            if (!below) { emit(output, "\n"); break; }
            emit(output, "; eliminated %s\n", names(e, members(below), ", ").data);
            removed = ordered(e, below, scores->borda, true);
        } else {
            memcpy(history[round - 1], scores->borda, sizeof scores->borda);
            bool tie = false;
            int a = look_back(e, remaining, history, round, &tie);
            removed = members(bit(a));
            emit(output, "; eliminated %s%s\n", e->names[a], tie_mark(tie));
        }
        remaining &= ~mask(removed);
        for (int i = 0; i < tail.count; ++i) removed.items[removed.count++] = tail.items[i];
        tail = removed;
    }
    int zero[MAX_CANDIDATES] = {0};
    Result result = {.order = ordered(e, remaining, zero, true), .tie = nanson && members(remaining).count > 1};
    for (int i = 0; i < tail.count; ++i) result.order.items[result.order.count++] = tail.items[i];
    winner(output, e, result);
    return result;
}
static void pair_lines(FILE *output, const Election *e, Field field, int matrix[][MAX_CANDIDATES]) {
    List list = members(field);
    for (int i = 0; i < list.count; ++i) for (int j = i + 1; j < list.count; ++j) {
        int a = list.items[i], b = list.items[j];
        const char *win = matrix[a][b] == matrix[b][a] ? "tie" : e->names[matrix[a][b] > matrix[b][a] ? a : b];
        emit(output, "%s vs %s: %d-%d (%s)\n", e->names[a], e->names[b], matrix[a][b], matrix[b][a], win);
    }
}
static void closure(Field field, bool relation[][MAX_CANDIDATES]) {
    List list = members(field);
    for (int k = 0; k < list.count; ++k) for (int i = 0; i < list.count; ++i) for (int j = 0; j < list.count; ++j) {
        int a = list.items[i], b = list.items[j], via = list.items[k];
        relation[a][b] = relation[a][b] || (relation[a][via] && relation[via][b]);
    }
}
static void condorcet_report(Election *e, Field field, FILE *output) {
    int win = condorcet(e, field, false), lose = condorcet(e, field, true);
    bool weak[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}}, strong[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}};
    List list = members(field), smith = {0}, schwartz = {0};
    for (int i = 0; i < list.count; ++i) for (int j = 0; j < list.count; ++j) {
        int a = list.items[i], b = list.items[j];
        weak[a][b] = e->pairwise[a][b] >= e->pairwise[b][a];
        strong[a][b] = e->pairwise[a][b] > e->pairwise[b][a];
    }
    closure(field, weak);
    closure(field, strong);
    for (int i = 0; i < list.count; ++i) {
        int a = list.items[i];
        bool top = true, unbeaten = true;
        for (int j = 0; j < list.count; ++j) {
            int b = list.items[j];
            top = top && weak[a][b];
            unbeaten = unbeaten && (!strong[b][a] || strong[a][b]);
        }
        if (top) smith.items[smith.count++] = a;
        if (unbeaten) schwartz.items[schwartz.count++] = a;
    }
    emit(output, "winner: %s\nloser: %s\nsmith: %s\nschwartz: %s\n", win < 0 ? "NONE" : e->names[win],
         lose < 0 ? "NONE" : e->names[lose], names(e, smith, ", ").data, names(e, schwartz, ", ").data);
}
static Result topological(const Election *e, Field field, bool relation[][MAX_CANDIDATES]) {
    Result result = {0};
    Field remaining = field;
    while (remaining) {
        Field choices = 0;
        for (int a = 0; a < e->count; ++a) if (remaining & bit(a)) {
            bool incoming = false;
            for (int b = 0; b < e->count; ++b) if (b != a && (remaining & bit(b)) && relation[b][a]) incoming = true;
            if (!incoming) choices |= bit(a);
        }
        if (result.order.count == 0) result.tie = members(choices).count > 1;
        int a = earliest(e, choices);
        result.order.items[result.order.count++] = a;
        remaining &= ~bit(a);
    }
    return result;
}
static Result schulze(Election *e, Field field, FILE *output) {
    pairwise(e);
    int paths[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}};
    bool relation[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}};
    List list = members(field);
    for (int i = 0; i < list.count; ++i) for (int j = 0; j < list.count; ++j) {
        int a = list.items[i], b = list.items[j];
        if (e->pairwise[a][b] > e->pairwise[b][a]) paths[a][b] = e->pairwise[a][b];
    }
    for (int i = 0; i < list.count; ++i) for (int j = 0; j < list.count; ++j) for (int k = 0; k < list.count; ++k) {
        if (i == j || i == k || j == k) continue;
        int via = list.items[i], a = list.items[j], b = list.items[k];
        int strength = paths[a][via] < paths[via][b] ? paths[a][via] : paths[via][b];
        if (strength > paths[a][b]) paths[a][b] = strength;
    }
    for (int a = 0; a < e->count; ++a) for (int b = 0; b < e->count; ++b) relation[a][b] = paths[a][b] > paths[b][a];
    Result result = topological(e, field, relation);
    pair_lines(output, e, field, paths);
    emit(output, "ranking: %s\n", names(e, result.order, " > ").data);
    winner(output, e, result);
    return result;
}
typedef struct { int from, to; } Edge;
static bool edge_before(const Election *e, Edge a, Edge b) {
    int aw = e->pairwise[a.from][a.to], bw = e->pairwise[b.from][b.to];
    if (aw != bw) return aw > bw;
    int al = e->pairwise[a.to][a.from], bl = e->pairwise[b.to][b.from];
    if (al != bl) return al < bl;
    if (a.from != b.from) return e->priority[a.from] < e->priority[b.from];
    return e->priority[a.to] < e->priority[b.to];
}
static Result ranked_pairs(Election *e, Field field, FILE *output) {
    pairwise(e);
    Edge pairs[MAX_CANDIDATES * MAX_CANDIDATES];
    int count = 0;
    List list = members(field);
    for (int i = 0; i < list.count; ++i) for (int j = 0; j < list.count; ++j) {
        int a = list.items[i], b = list.items[j];
        if (e->pairwise[a][b] > e->pairwise[b][a]) pairs[count++] = (Edge){a, b};
    }
    for (int i = 1; i < count; ++i) {
        Edge edge = pairs[i];
        int j = i;
        while (j > 0 && edge_before(e, edge, pairs[j - 1])) { pairs[j] = pairs[j - 1]; --j; }
        pairs[j] = edge;
    }
    bool locked[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}}, reached[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}};
    for (int i = 0; i < count; ++i) {
        int a = pairs[i].from, b = pairs[i].to;
        bool lock = !reached[b][a];
        emit(output, "%s %s>%s %d-%d\n", lock ? "lock" : "skip", e->names[a], e->names[b], e->pairwise[a][b], e->pairwise[b][a]);
        if (lock) {
            locked[a][b] = reached[a][b] = true;
            closure(field, reached);
        }
    }
    Result result = topological(e, field, locked);
    winner(output, e, result);
    return result;
}
static Result kemeny(Election *e, Field field, FILE *output) {
    pairwise(e);
    int best[SUBSETS] = {0}, ways[SUBSETS] = {0};
    Field heads[SUBSETS] = {0};
    ways[0] = 1;
    for (Field subset = 1; subset <= field; ++subset) {
        if (subset & ~field) continue;
        best[subset] = -1;
        List list = members(subset);
        for (int i = 0; i < list.count; ++i) {
            int a = list.items[i];
            Field rest = subset & ~bit(a);
            int score = best[rest];
            for (int j = 0; j < list.count; ++j) if (i != j) score += e->pairwise[a][list.items[j]];
            if (score > best[subset]) { best[subset] = score; ways[subset] = 0; heads[subset] = 0; }
            if (score == best[subset]) { ways[subset] += ways[rest]; heads[subset] |= bit(a); }
        }
    }
    Result result = {.tie = members(heads[field]).count > 1};
    for (Field remaining = field; remaining;) {
        int a = earliest(e, heads[remaining]);
        result.order.items[result.order.count++] = a;
        remaining &= ~bit(a);
    }
    emit(output, "score: %d\noptimal: %d\nranking: %s\n", best[field], ways[field], names(e, result.order, " > ").data);
    winner(output, e, result);
    return result;
}

typedef struct { int value, owner; } Parcel;
static void stv(Election *e, Field field, int seats, FILE *output) {
    Parcel *parcels = calloc((size_t)e->group_count, sizeof *parcels);
    if (!parcels) exit(EXIT_FAILURE);
    for (int i = 0; i < e->group_count; ++i)
        if (effective(e->groups[i].ranking, field).count) parcels[i].value = 100;
    int quota = tallies(e, field)->nonblank * 100 / (seats + 1) + 1;
    emit(output, "quota: %d.%02d\n", quota / 100, quota % 100);
    Field continuing = field;
    List elected = {0};
    int history[MAX_CANDIDATES][MAX_CANDIDATES] = {{0}}, round = 0;
    for (;;) {
        int scores[MAX_CANDIDATES] = {0}, exhausted = 0;
        for (int i = 0; i < e->group_count; ++i) {
            parcels[i].owner = -1;
            if (!parcels[i].value) continue;
            List rank = effective(e->groups[i].ranking, continuing);
            int value = e->groups[i].votes * parcels[i].value;
            if (rank.count) {
                parcels[i].owner = rank.items[0];
                scores[rank.items[0]] += value;
            } else exhausted += value;
        }
        memcpy(history[round], scores, sizeof scores);
        ++round;
        emit(output, "round %d: %s; exhausted %d.%02d", round, values(e, continuing, scores, true).data, exhausted / 100, exhausted % 100);
        List order = ordered(e, continuing, scores, true);
        if (order.count == seats - elected.count) {
            for (int i = 0; i < order.count; ++i) elected.items[elected.count++] = order.items[i];
            emit(output, "; elected %s\n", names(e, order, ", ").data);
            break;
        }
        int a = order.items[0];
        if (scores[a] >= quota) {
            int surplus = scores[a] - quota;
            elected.items[elected.count++] = a;
            continuing &= ~bit(a);
            for (int i = 0; i < e->group_count; ++i)
                if (parcels[i].owner == a) parcels[i].value = parcels[i].value * surplus / scores[a];
            emit(output, "; elected %s (surplus %d.%02d)\n", e->names[a], surplus / 100, surplus % 100);
            if (elected.count == seats) break;
        } else {
            bool tie = false;
            a = look_back(e, continuing, history, round, &tie);
            continuing &= ~bit(a);
            emit(output, "; excluded %s%s\n", e->names[a], tie_mark(tie));
        }
    }
    emit(output, "elected: %s\n", names(e, elected, ", ").data);
    free(parcels);
}

static Result tally(Election *e, Field field, Method method, FILE *output) {
    switch (method.kind) {
        case RUNOFF: return runoff(e, field, output);
        case IRV: case COOMBS: return elimination(e, field, method.kind, output, false);
        case BUCKLIN: return bucklin(e, field, output);
        case BALDWIN: case NANSON: return borda_elimination(e, field, method.kind == NANSON, output);
        case SCHULZE: return schulze(e, field, output);
        case RANKEDPAIRS: return ranked_pairs(e, field, output);
        case KEMENY: return kemeny(e, field, output);
        case CONDORCET: condorcet_report(e, field, output); return (Result){0};
        case STV: stv(e, field, method.parameter, output); return (Result){0};
        default: break;
    }
    Tallies *base = tallies(e, field);
    int scores[MAX_CANDIDATES] = {0};
    const int *selected = scores;
    const char *label = "scores";
    bool descending = true;
    int condorcet_winner = -1;
    switch (method.kind) {
        case PLURALITY: selected = base->first; label = "votes"; break;
        case BORDA: case BLACK:
            selected = base->borda;
            if (method.kind == BLACK) {
                condorcet_winner = condorcet(e, field, false);
                emit(output, "condorcet: %s\n", condorcet_winner < 0 ? "NONE" : e->names[condorcet_winner]);
            }
            break;
        case VETO: selected = base->last; label = "vetoes"; descending = false; break;
        case APPROVAL: {
            int depth = method.parameter < members(field).count ? method.parameter : members(field).count;
            selected = base->approval[depth - 1];
            label = "approvals";
            break;
        }
        case COPELAND: {
            pairwise(e);
            Text text = {0};
            List list = members(field);
            for (int i = 0; i < list.count; ++i) {
                int a = list.items[i], wins = 0, draws = 0, losses = 0;
                for (int j = 0; j < list.count; ++j) if (i != j) {
                    int b = list.items[j];
                    if (e->pairwise[a][b] > e->pairwise[b][a]) ++wins;
                    else if (e->pairwise[a][b] == e->pairwise[b][a]) ++draws;
                    else ++losses;
                }
                scores[a] = 2 * wins + draws;
                append(&text, "%s%s %d.%d (%d-%d-%d)", i ? ", " : "", e->names[a], scores[a] / 2, (scores[a] % 2) * 5, wins, draws, losses);
            }
            emit(output, "scores: %s\n", text.data);
            break;
        }
        case MINIMAX:
            pairwise(e);
            descending = false;
            for (int a = 0; a < e->count; ++a) if (field & bit(a))
                for (int b = 0; b < e->count; ++b) if (a != b && (field & bit(b))) {
                    int opposition = e->pairwise[b][a], support = e->pairwise[a][b], value = 0;
                    if (method.parameter == 2 || opposition > support) value = method.parameter == 1 ? opposition - support : opposition;
                    if (value > scores[a]) scores[a] = value;
                }
            break;
        default: abort();
    }
    Result result = scored(e, field, selected, descending);
    if (condorcet_winner >= 0) {
        int index = position(result.order, condorcet_winner);
        for (int i = index; i > 0; --i) result.order.items[i] = result.order.items[i - 1];
        result.order.items[0] = condorcet_winner;
        result.tie = false;
    }
    if (method.kind != COPELAND) emit(output, "%s: %s\n", label, values(e, field, selected, false).data);
    winner(output, e, result);
    return result;
}

static int split(char *text, char separator, char *parts[]) {
    int count = 0;
    parts[count++] = text;
    for (char *p = text; *p; ++p) if (*p == separator) { *p = '\0'; parts[count++] = p + 1; }
    return count;
}
static int candidate_index(const Election *e, const char *name) {
    for (int i = 0; i < e->count; ++i) if (strcmp(e->names[i], name) == 0) return i;
    return -1;
}
static bool checked_names(const Election *e, char *words[], int count, List *result) {
    *result = (List){0};
    for (int i = 0; i < count; ++i) {
        int a = candidate_index(e, words[i]);
        if (a < 0) { error("unknown candidate %s", words[i]); return false; }
        if (position(*result, a) >= 0) { error("duplicate candidate %s", words[i]); return false; }
        result->items[result->count++] = a;
    }
    return true;
}
static Method parse_method(char *words[]) {
    Method result = {0};
    for (int i = 0; i < 18; ++i) if (strcmp(words[0], method_names[i]) == 0) { result.kind = (MethodKind)i; break; }
    if (result.kind == APPROVAL || result.kind == STV) result.parameter = atoi(words[1]);
    else if (result.kind == MINIMAX) result.parameter = strcmp(words[1], "WINNING") == 0 ? 0 : strcmp(words[1], "MARGIN") == 0 ? 1 : 2;
    return result;
}
static const char *summary_name(int index) {
    return summary_methods[index].kind == MINIMAX ? "MINIMAX WINNING" : method_names[summary_methods[index].kind];
}

typedef struct { int votes; char notation[91]; } Distribution;
static int notation_order(const void *left, const void *right) {
    const Distribution *a = left, *b = right;
    return strcmp(a->notation, b->notation);
}
static int distribution_order(const void *left, const void *right) {
    const Distribution *a = left, *b = right;
    return a->votes != b->votes ? (a->votes > b->votes ? -1 : 1) : strcmp(a->notation, b->notation);
}
static void ballots_report(Election *e) {
    Distribution *groups = malloc((size_t)e->group_count * sizeof *groups);
    if (!groups) exit(EXIT_FAILURE);
    int blank = 0;
    for (int i = 0; i < e->group_count; ++i) {
        List rank = effective(e->groups[i].ranking, e->active);
        groups[i].votes = e->groups[i].votes;
        strcpy(groups[i].notation, rank.count ? names(e, rank, ">").data : "-");
        if (!rank.count) blank += groups[i].votes;
    }
    qsort(groups, (size_t)e->group_count, sizeof *groups, notation_order);
    int distinct = 0;
    for (int i = 0; i < e->group_count; ++i) {
        if (distinct > 0 && strcmp(groups[i].notation, groups[distinct - 1].notation) == 0) groups[distinct - 1].votes += groups[i].votes;
        else groups[distinct++] = groups[i];
    }
    qsort(groups, (size_t)distinct, sizeof *groups, distribution_order);
    printf("total %d, blank %d, distinct %d\n", e->total, blank, distinct);
    for (int i = 0; i < distinct; ++i) printf("%d %s\n", groups[i].votes, groups[i].notation);
    free(groups);
}
static void set_tiebreak(Election *e, List order) {
    e->tiebreak = order;
    for (int i = 0; i < order.count; ++i) e->priority[order.items[i]] = i;
}
static void finish_entry(Election *e) {
    e->entry_ends[e->entry_count++] = e->group_count;
    invalidate(e);
}
static void execute(Election *e, int *election_number, char *line) {
    char original[201];
    strcpy(original, line);
    char *words[12];
    int count = split(line, ' ', words);
    const char *command = words[0];
    if (strcmp(command, "CANDIDATES") == 0) {
        if (count == 2) { error("too few candidates"); return; }
        for (int i = 1; i < count; ++i) for (int j = 1; j < i; ++j)
            if (strcmp(words[i], words[j]) == 0) { error("duplicate candidate %s", words[i]); return; }
        memset(e, 0, sizeof *e);
        e->number = ++*election_number;
        e->count = count - 1;
        e->active = bit(e->count) - 1;
        for (int i = 0; i < e->count; ++i) strcpy(e->names[i], words[i + 1]);
        List order = members(e->active);
        for (int i = 1; i < order.count; ++i) {
            int a = order.items[i], j = i;
            while (j > 0 && strcmp(e->names[a], e->names[order.items[j - 1]]) < 0) { order.items[j] = order.items[j - 1]; --j; }
            order.items[j] = a;
        }
        set_tiebreak(e, order);
        printf("election %d: %d candidates\n", e->number, e->count);
        return;
    }
    if (!e->number) { error("no election"); return; }
    if (strcmp(command, "BALLOT") == 0) {
        List rank = {0};
        if (strcmp(words[2], "-") != 0) {
            char *choices[10];
            int length = split(words[2], '>', choices);
            if (!checked_names(e, choices, length, &rank)) return;
        }
        int votes = atoi(words[1]);
        e->groups[e->group_count++] = (Ballot){votes, rank};
        e->total += votes;
        finish_entry(e);
        return;
    }
    if (strcmp(command, "RANDOM") == 0) {
        int groups = atoi(words[1]);
        int64_t state = strtoll(words[2], NULL, 10);
        for (int i = 0; i < groups; ++i) {
            List rank = members(e->active);
            for (int j = rank.count - 1; j > 0; --j) {
                state = 48271 * state % 2147483647;
                int other = (int)(state % (j + 1)), temporary = rank.items[j];
                rank.items[j] = rank.items[other];
                rank.items[other] = temporary;
            }
            state = 48271 * state % 2147483647;
            rank.count = (int)(state % rank.count) + 1;
            e->groups[e->group_count++] = (Ballot){1, rank};
        }
        e->total += groups;
        finish_entry(e);
        return;
    }
    if (strcmp(command, "UNDO") == 0) {
        if (!e->entry_count) { error("nothing to undo"); return; }
        --e->entry_count;
        int end = e->entry_count ? e->entry_ends[e->entry_count - 1] : 0;
        for (int i = end; i < e->group_count; ++i) e->total -= e->groups[i].votes;
        e->group_count = end;
        invalidate(e);
        return;
    }
    if (strcmp(command, "WITHDRAW") == 0 || strcmp(command, "RESTORE") == 0) {
        int a = candidate_index(e, words[1]);
        if (a < 0) { error("unknown candidate %s", words[1]); return; }
        bool active = (e->active & bit(a)) != 0;
        if (strcmp(command, "WITHDRAW") == 0) {
            if (!active) { error("already withdrawn %s", words[1]); return; }
            if (members(e->active).count <= 2) { error("too few candidates"); return; }
            e->active &= ~bit(a);
        } else {
            if (active) { error("not withdrawn %s", words[1]); return; }
            e->active |= bit(a);
        }
        return;
    }
    if (strcmp(command, "TIEBREAK") == 0) {
        List order;
        if (!checked_names(e, words + 1, count - 1, &order)) return;
        if (order.count != e->count) { error("incomplete tiebreak"); return; }
        set_tiebreak(e, order);
        return;
    }
    if (strcmp(command, "STATUS") == 0) {
        List withdrawn = members((bit(e->count) - 1) & ~e->active);
        printf("[%s]\nelection %d\nactive: %s\nwithdrawn: %s\ntiebreak: %s\nballots: %d in %d entries\n",
               original, e->number, names(e, members(e->active), ", ").data,
               withdrawn.count ? names(e, withdrawn, ", ").data : "none", names(e, e->tiebreak, ", ").data, e->total, e->entry_count);
        return;
    }
    if (!e->entry_count) { error("no ballots"); return; }
    bool ranking = strcmp(command, "RANKING") == 0, spoilers = strcmp(command, "SPOILERS") == 0;
    Method method = {0};
    if (ranking || spoilers) {
        method = parse_method(words + 1);
        if (method.kind == CONDORCET || method.kind == STV) { error("not rankable"); return; }
        if (spoilers && members(e->active).count < 3) { error("too few candidates"); return; }
    }
    int compared[2] = {0};
    if (strcmp(command, "COMPARE") == 0) {
        for (int i = 0; i < 2; ++i) {
            compared[i] = candidate_index(e, words[i + 1]);
            if (compared[i] < 0) { error("unknown candidate %s", words[i + 1]); return; }
            if (!(e->active & bit(compared[i]))) { error("withdrawn candidate %s", words[i + 1]); return; }
        }
        if (compared[0] == compared[1]) { error("same candidate"); return; }
    }
    if (strcmp(command, "STV") == 0 && atoi(words[1]) >= members(e->active).count) { error("too many seats"); return; }
    printf("[%s]\n", original);
    if (ranking || spoilers) {
        Result result = tally(e, e->active, method, NULL);
        if (ranking) puts(names(e, result.order, " > ").data);
        else {
            int win = result.order.items[0];
            printf("winner: %s\n", e->names[win]);
            for (int a = 0; a < e->count; ++a) if (a != win && (e->active & bit(a))) {
                int other = tally(e, e->active & ~bit(a), method, NULL).order.items[0];
                printf("without %s: %s%s\n", e->names[a], e->names[other], other != win ? " (changed)" : "");
            }
        }
    } else if (strcmp(command, "BALLOTS") == 0) ballots_report(e);
    else if (strcmp(command, "PROFILE") == 0) {
        Tallies *scores = tallies(e, e->active);
        int size = members(e->active).count;
        for (int a = 0; a < e->count; ++a) if (e->active & bit(a)) {
            printf("%s:", e->names[a]);
            for (int j = 0; j < size; ++j) printf(" %d", scores->approval[j][a] - (j ? scores->approval[j - 1][a] : 0));
            printf(" unranked %d\n", e->total - scores->approval[size - 1][a]);
        }
    } else if (strcmp(command, "PAIRWISE") == 0) {
        pairwise(e);
        pair_lines(stdout, e, e->active, e->pairwise);
    } else if (strcmp(command, "EXHAUSTED") == 0) elimination(e, e->active, IRV, stdout, true);
    else if (strcmp(command, "SUMMARY") == 0 || strcmp(command, "COMPARE") == 0) {
        int wins[MAX_CANDIDATES] = {0};
        Text ahead[2] = {{0}, {0}};
        bool compare = strcmp(command, "COMPARE") == 0;
        for (int i = 0; i < 15; ++i) {
            Result result = tally(e, e->active, summary_methods[i], NULL);
            if (compare) {
                int side = position(result.order, compared[0]) < position(result.order, compared[1]) ? 0 : 1;
                append(&ahead[side], "%s%s", ahead[side].length ? ", " : "", summary_name(i));
            } else {
                int win = result.order.items[0];
                ++wins[win];
                printf("%s: %s\n", summary_name(i), e->names[win]);
            }
        }
        if (compare) {
            pairwise(e);
            int a = compared[0], b = compared[1];
            printf("%s %d, %s %d, neither %d\n%s ahead: %s\n%s ahead: %s\n", e->names[a], e->pairwise[a][b], e->names[b], e->pairwise[b][a],
                   e->total - e->pairwise[a][b] - e->pairwise[b][a], e->names[a], ahead[0].length ? ahead[0].data : "none",
                   e->names[b], ahead[1].length ? ahead[1].data : "none");
        } else printf("wins: %s\n", values(e, e->active, wins, false).data);
    } else tally(e, e->active, parse_method(words), stdout);
}

int main(void) {
    static Election election;
    int election_number = 0;
    char line[256];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int commands = atoi(line);
    for (int i = 0; i < commands; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        line[strcspn(line, "\r\n")] = '\0';
        execute(&election, &election_number, line);
    }
    return 0;
}
