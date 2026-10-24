#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { MAX_AGENTS = 24, MAX_SIDE = 12, MAX_MATCHINGS = 50 };
typedef enum { TWO_SIDED, ROOMMATE, HOUSING } MarketType;
typedef enum { NONE, GS, GSR, BOSTON, EGALITARIAN, MINREGRET } Source;
static const char *const sources[] = {"-", "GS", "GSR", "BOSTON", "EGALITARIAN", "MINREGRET"};

typedef struct {
    char name[9];
    int preference[MAX_AGENTS], length, capacity;
} Agent;

typedef struct { int partner[MAX_SIDE]; } Matching;
typedef struct {
    char name[9], houses[MAX_SIDE][9];
    MarketType type;
    int count, proposers, receivers;
    Agent agents[MAX_AGENTS];
    Matching current;
    Source source;
} Market;

typedef struct { char *data; size_t length, capacity; } Text;
typedef struct { int items[MAX_AGENTS], head, count; bool present[MAX_AGENTS]; } Queue;
typedef struct { Matching matching; int proposals; } Deferred;
typedef struct { Matching matching; int applications; } Boston;
typedef struct { int count, proposer[MAX_SIDE], receiver[MAX_SIDE]; } Rotation;
typedef struct { Matching matching; int origin, via; } Node;
typedef struct {
    Node nodes[MAX_MATCHINGS];
    Rotation rotations[MAX_MATCHINGS * MAX_SIDE];
    int count, rotation_count;
} Lattice;
typedef struct { int left, right; } Pair;

static Market *markets[500];
static int market_count;

static void *allocate(size_t size) {
    void *p = malloc(size);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void append(Text *text, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    size_t needed = text->length + (size_t)n + 1;
    if (needed > text->capacity) {
        size_t capacity = text->capacity ? text->capacity * 2 : 256;
        if (capacity < needed) capacity = needed;
        char *p = realloc(text->data, capacity);
        if (!p) exit(EXIT_FAILURE);
        text->data = p;
        text->capacity = capacity;
    }
    vsnprintf(text->data + text->length, text->capacity - text->length, format, args);
    va_end(args);
    text->length += (size_t)n;
}

static void emit(Text *text) {
    if (text->data) fputs(text->data, stdout);
    free(text->data);
}

static void enqueue(Queue *queue, int agent) {
    queue->items[(queue->head + queue->count) % MAX_AGENTS] = agent;
    ++queue->count;
    queue->present[agent] = true;
}

static int dequeue(Queue *queue) {
    int agent = queue->items[queue->head];
    queue->head = (queue->head + 1) % MAX_AGENTS;
    --queue->count;
    queue->present[agent] = false;
    return agent;
}

static int index_of(const Market *market, const char *name) {
    for (int i = 0; i < market->count; ++i)
        if (!strcmp(market->agents[i].name, name)) return i;
    return -1;
}

static int house_index(const Market *market, const char *name) {
    for (int i = 0; i < market->count; ++i)
        if (!strcmp(market->houses[i], name)) return i;
    return -1;
}

static Market *find_market(const char *name) {
    for (int i = 0; i < market_count; ++i)
        if (!strcmp(markets[i]->name, name)) return markets[i];
    return NULL;
}

static bool require_type(const Market *market, MarketType type) {
    if (market->type == type) return true;
    printf("ERROR WRONG TYPE %s\n", market->name);
    return false;
}

static int require_agent(const Market *market, const char *name, int side) {
    int agent = index_of(market, name);
    if (agent < 0) printf("ERROR UNKNOWN AGENT %s\n", name);
    else if (side == 0 && agent >= market->proposers) {
        printf("ERROR NOT PROPOSER %s\n", name);
        return -1;
    } else if (side == 1 && agent < market->proposers) {
        printf("ERROR NOT RECEIVER %s\n", name);
        return -1;
    }
    return agent;
}

static int rank_of(const Market *market, int agent, int partner) {
    const Agent *a = &market->agents[agent];
    for (int i = 0; i < a->length; ++i)
        if (a->preference[i] == partner) return i + 1;
    return a->length + 1;
}

static bool accepts(const Market *market, int agent, int partner) {
    return rank_of(market, agent, partner) <= market->agents[agent].length;
}

static Matching empty_matching(void) {
    Matching result;
    for (int p = 0; p < MAX_SIDE; ++p) result.partner[p] = -1;
    return result;
}

static const char *partner_name(const Market *market, int partner) {
    return partner < 0 ? "*" : market->agents[partner].name;
}

static void print_matching(const Market *market, Matching matching) {
    for (int p = 0; p < market->proposers; ++p)
        printf("%s%s-%s", p ? " " : "", market->agents[p].name,
               partner_name(market, matching.partner[p]));
    putchar('\n');
}

static bool able(const Market *market, int agent, const int next[], const int held[]) {
    return held[agent] < market->agents[agent].capacity && next[agent] < market->agents[agent].length;
}

static Deferred deferred(const Market *market, bool reverse, Text *history) {
    Deferred result = { .matching = empty_matching() };
    bool holding[MAX_AGENTS][MAX_AGENTS] = {{false}};
    int next[MAX_AGENTS] = {0}, held[MAX_AGENTS] = {0};
    Queue queue = {0};
    int begin = reverse ? market->proposers : 0;
    int end = reverse ? market->count : market->proposers;
    for (int x = begin; x < end; ++x)
        if (able(market, x, next, held)) enqueue(&queue, x);
    while (queue.count) {
        int x = dequeue(&queue), y = market->agents[x].preference[next[x]++];
        int rejected = -1;
        bool accepted = false;
        ++result.proposals;
        if (accepts(market, y, x)) {
            if (held[y] < market->agents[y].capacity) accepted = true;
            else {
                int worst = -1;
                for (int w = begin; w < end; ++w)
                    if (holding[y][w] && (worst < 0 || rank_of(market, y, w) > rank_of(market, y, worst)))
                        worst = w;
                if (rank_of(market, y, x) < rank_of(market, y, worst)) {
                    accepted = true;
                    rejected = worst;
                    holding[y][worst] = false;
                    --held[y];
                    --held[worst];
                    if (able(market, worst, next, held) && !queue.present[worst]) enqueue(&queue, worst);
                }
            }
        }
        if (accepted) {
            holding[y][x] = true;
            ++held[x];
            ++held[y];
        }
        if (history) {
            append(history, "PROPOSE %s %s %s", market->agents[x].name, market->agents[y].name,
                   accepted ? "HOLD" : "REJECT");
            if (rejected >= 0) append(history, " REJECT %s", market->agents[rejected].name);
            append(history, "\n");
        }
        if (able(market, x, next, held)) enqueue(&queue, x);
    }
    for (int y = 0; y < market->count; ++y)
        for (int x = begin; x < end; ++x)
            if (holding[y][x]) result.matching.partner[reverse ? y : x] = reverse ? x : y;
    return result;
}

static Boston boston(const Market *market) {
    Boston result = { .matching = empty_matching() };
    int remaining[MAX_AGENTS], rounds = 0;
    for (int r = market->proposers; r < market->count; ++r) remaining[r] = market->agents[r].capacity;
    for (int p = 0; p < market->proposers; ++p)
        if (market->agents[p].length > rounds) rounds = market->agents[p].length;
    for (int round = 0; round < rounds; ++round) {
        int applications[MAX_SIDE];
        for (int p = 0; p < market->proposers; ++p) {
            applications[p] = -1;
            if (result.matching.partner[p] < 0 && market->agents[p].length > round) {
                applications[p] = market->agents[p].preference[round];
                ++result.applications;
            }
        }
        for (int r = market->proposers; r < market->count; ++r)
            for (int i = 0; i < market->agents[r].length && remaining[r]; ++i) {
                int p = market->agents[r].preference[i];
                if (applications[p] == r) {
                    result.matching.partner[p] = r;
                    --remaining[r];
                }
            }
    }
    return result;
}

static int rotations(const Market *market, Matching matching, Rotation result[]) {
    int owner[MAX_AGENTS], successor[MAX_SIDE];
    for (int r = 0; r < market->count; ++r) owner[r] = -1;
    for (int p = 0; p < market->proposers; ++p)
        if (matching.partner[p] >= 0) owner[matching.partner[p]] = p;
    for (int p = 0; p < market->proposers; ++p) {
        successor[p] = -1;
        if (matching.partner[p] < 0) continue;
        const Agent *a = &market->agents[p];
        for (int i = rank_of(market, p, matching.partner[p]); i < a->length; ++i) {
            int r = a->preference[i];
            if (accepts(market, r, p) && (owner[r] < 0 || rank_of(market, r, p) < rank_of(market, r, owner[r]))) {
                successor[p] = owner[r];
                break;
            }
        }
    }
    bool covered[MAX_SIDE] = {false};
    int count = 0;
    for (int start = 0; start < market->proposers; ++start) {
        if (covered[start]) continue;
        bool seen[MAX_SIDE] = {false};
        Rotation rotation = {0};
        int p = start;
        while (p >= 0 && !seen[p]) {
            seen[p] = true;
            rotation.proposer[rotation.count] = p;
            rotation.receiver[rotation.count++] = matching.partner[p];
            p = successor[p];
        }
        if (p == start) {
            result[count++] = rotation;
            for (int i = 0; i < rotation.count; ++i) covered[rotation.proposer[i]] = true;
        }
    }
    return count;
}

static bool same_rotation(const Rotation *a, const Rotation *b) {
    if (a->count != b->count) return false;
    for (int i = 0; i < a->count; ++i)
        if (a->proposer[i] != b->proposer[i] || a->receiver[i] != b->receiver[i]) return false;
    return true;
}

static bool enumerate(const Market *market, Lattice *lattice) {
    lattice->count = 1;
    lattice->rotation_count = 0;
    lattice->nodes[0] = (Node){ .matching = deferred(market, false, NULL).matching };
    for (int i = 0; i < lattice->count; ++i) {
        Rotation sequence[MAX_SIDE];
        Matching matching = lattice->nodes[i].matching;
        int count = rotations(market, matching, sequence);
        for (int j = 0; j < count; ++j) {
            Rotation *rotation = &sequence[j];
            int number = 0;
            while (number < lattice->rotation_count && !same_rotation(rotation, &lattice->rotations[number])) ++number;
            if (number == lattice->rotation_count) lattice->rotations[lattice->rotation_count++] = *rotation;
            Matching next = matching;
            for (int k = 0; k < rotation->count; ++k)
                next.partner[rotation->proposer[k]] = rotation->receiver[(k + 1) % rotation->count];
            int previous = 0;
            while (previous < lattice->count && memcmp(next.partner, lattice->nodes[previous].matching.partner,
                                                       (size_t)market->proposers * sizeof(int))) ++previous;
            if (previous == lattice->count) {
                if (lattice->count == MAX_MATCHINGS) return false;
                lattice->nodes[lattice->count++] = (Node){next, i + 1, number + 1};
            }
        }
    }
    return true;
}

static void metrics(const Market *market, Matching matching, int *cost, int *regret) {
    *cost = *regret = 0;
    for (int p = 0; p < market->proposers; ++p) {
        int r = matching.partner[p];
        if (r < 0) continue;
        int a = rank_of(market, p, r), b = rank_of(market, r, p);
        *cost += a + b;
        if (a > *regret) *regret = a;
        if (b > *regret) *regret = b;
    }
}

static void check_matching(const Market *market, const int partner[]) {
    Pair unacceptable[MAX_SIDE * MAX_SIDE], blocking[MAX_SIDE * MAX_SIDE];
    int bad = 0, blocks = 0;
    if (market->type == TWO_SIDED) {
        int counts[MAX_AGENTS] = {0}, worst[MAX_AGENTS] = {0};
        for (int p = 0; p < market->proposers; ++p) {
            int r = partner[p];
            if (r < 0) continue;
            ++counts[r];
            int rank = rank_of(market, r, p);
            if (rank > worst[r]) worst[r] = rank;
            if (!accepts(market, p, r) || !accepts(market, r, p)) unacceptable[bad++] = (Pair){p, r};
        }
        for (int p = 0; p < market->proposers; ++p)
            for (int r = market->proposers; r < market->count; ++r)
                if (partner[p] != r && accepts(market, p, r) && accepts(market, r, p) &&
                    rank_of(market, p, r) < rank_of(market, p, partner[p]) &&
                    (counts[r] < market->agents[r].capacity || rank_of(market, r, p) < worst[r]))
                    blocking[blocks++] = (Pair){p, r};
    } else {
        for (int a = 0; a < market->count; ++a)
            for (int b = a + 1; b < market->count; ++b) {
                bool mutual = accepts(market, a, b) && accepts(market, b, a);
                if (partner[a] == b) {
                    if (!mutual) unacceptable[bad++] = (Pair){a, b};
                } else if (mutual && rank_of(market, a, b) < rank_of(market, a, partner[a]) &&
                           rank_of(market, b, a) < rank_of(market, b, partner[b]))
                    blocking[blocks++] = (Pair){a, b};
            }
    }
    if (!bad && !blocks) printf("CHECK %s STABLE\n", market->name);
    else {
        printf("CHECK %s UNSTABLE unacceptable=%d blocking=%d\n", market->name, bad, blocks);
        for (int i = 0; i < bad; ++i)
            printf("UNACCEPTABLE %s %s\n", market->agents[unacceptable[i].left].name, market->agents[unacceptable[i].right].name);
        for (int i = 0; i < blocks; ++i)
            printf("BLOCKING %s %s\n", market->agents[blocking[i].left].name, market->agents[blocking[i].right].name);
    }
}

typedef struct { bool present[MAX_AGENTS][MAX_AGENTS]; } Working;

static int working_list(const Market *market, const Working *working, int agent, int result[]) {
    int count = 0;
    const Agent *a = &market->agents[agent];
    for (int i = 0; i < a->length; ++i)
        if (working->present[agent][a->preference[i]]) result[count++] = a->preference[i];
    return count;
}

static int first_empty(const Market *market, const Working *working) {
    int list[MAX_AGENTS];
    for (int a = 0; a < market->count; ++a)
        if (!working_list(market, working, a, list)) return a;
    return -1;
}

static void table(const Market *market, const Working *working, Text *history) {
    for (int a = 0; a < market->count; ++a) {
        int list[MAX_AGENTS], count = working_list(market, working, a, list);
        append(history, "TABLE %s", market->agents[a].name);
        if (!count) append(history, " -");
        for (int i = 0; i < count; ++i) append(history, " %s", market->agents[list[i]].name);
        append(history, "\n");
    }
}

static void roommates(const Market *market, bool verbose) {
    Working working = {0};
    Queue queue = {0};
    int held[MAX_AGENTS], proposals = 0, failure = -1;
    for (int a = 0; a < market->count; ++a) {
        held[a] = -1;
        enqueue(&queue, a);
        for (int i = 0; i < market->agents[a].length; ++i)
            working.present[a][market->agents[a].preference[i]] = true;
    }
    while (queue.count) {
        int x = dequeue(&queue), list[MAX_AGENTS];
        working_list(market, &working, x, list);
        int y = list[0];
        if (held[y] >= 0) enqueue(&queue, held[y]);
        held[y] = x;
        ++proposals;
        int count = working_list(market, &working, y, list);
        bool after = false;
        for (int i = 0; i < count; ++i) {
            int w = list[i];
            if (after) working.present[y][w] = working.present[w][y] = false;
            if (w == x) after = true;
        }
        failure = first_empty(market, &working);
        if (failure >= 0) break;
    }
    Text history = {0};
    int rotation_count = 0;
    if (failure < 0 && verbose) table(market, &working, &history);
    while (failure < 0) {
        int list[MAX_AGENTS], start = -1;
        for (int a = 0; a < market->count; ++a)
            if (working_list(market, &working, a, list) >= 2) { start = a; break; }
        if (start < 0) break;
        int path[MAX_AGENTS], position[MAX_AGENTS], count = 0, p = start;
        for (int a = 0; a < market->count; ++a) position[a] = -1;
        while (position[p] < 0) {
            position[p] = count;
            path[count++] = p;
            working_list(market, &working, p, list);
            int q = list[1];
            int length = working_list(market, &working, q, list);
            p = list[length - 1];
        }
        int begin = position[p], size = count - begin, front[MAX_AGENTS];
        append(&history, "ROTATION %d", ++rotation_count);
        for (int i = 0; i < size; ++i) {
            int x = path[begin + i];
            working_list(market, &working, x, list);
            front[i] = list[0];
            append(&history, " %s-%s", market->agents[x].name, market->agents[front[i]].name);
        }
        append(&history, "\n");
        Working removed = {0};
        for (int i = 0; i < size; ++i) {
            int u = front[(i + 1) % size], length = working_list(market, &working, u, list);
            bool after = false;
            for (int j = 0; j < length; ++j) {
                int w = list[j];
                if (after) removed.present[u][w] = removed.present[w][u] = true;
                if (w == path[begin + i]) after = true;
            }
        }
        for (int a = 0; a < market->count; ++a)
            for (int b = 0; b < market->count; ++b)
                if (removed.present[a][b]) working.present[a][b] = false;
        if (verbose) table(market, &working, &history);
        failure = first_empty(market, &working);
    }
    printf("ROOMMATES %s proposals=%d\n", market->name, proposals);
    emit(&history);
    if (failure >= 0) printf("NO STABLE MATCHING %s\n", market->agents[failure].name);
    else {
        fputs("MATCHING", stdout);
        for (int a = 0; a < market->count; ++a) {
            int list[MAX_AGENTS];
            working_list(market, &working, a, list);
            if (a < list[0]) printf(" %s-%s", market->agents[a].name, market->agents[list[0]].name);
        }
        putchar('\n');
    }
}

static int effective(const Market *market, int agent, int result[]) {
    const Agent *a = &market->agents[agent];
    for (int i = 0; i < a->length; ++i) {
        result[i] = a->preference[i];
        if (result[i] == agent) return i + 1;
    }
    result[a->length] = agent;
    return a->length + 1;
}

static void print_allocation(const Market *market, const int allocation[]) {
    fputs("ALLOCATION", stdout);
    for (int a = 0; a < market->count; ++a)
        printf(" %s-%s", market->agents[a].name, allocation[a] < 0 ? "*" : market->houses[allocation[a]]);
    putchar('\n');
}

static void ttc(const Market *market) {
    bool remaining[MAX_AGENTS] = {false};
    int allocation[MAX_AGENTS], left = market->count, cycles = 0;
    for (int a = 0; a < market->count; ++a) remaining[a] = true;
    Text history = {0};
    while (left) {
        int points[MAX_AGENTS], start = -1;
        for (int a = 0; a < market->count; ++a) if (remaining[a]) {
            if (start < 0) start = a;
            int list[MAX_AGENTS], length = effective(market, a, list);
            for (int i = 0; i < length; ++i)
                if (remaining[list[i]]) { points[a] = list[i]; break; }
        }
        bool seen[MAX_AGENTS] = {false};
        int p = start;
        while (!seen[p]) { seen[p] = true; p = points[p]; }
        int first = p;
        append(&history, "CYCLE %d", ++cycles);
        do {
            allocation[p] = points[p];
            append(&history, " %s:%s", market->agents[p].name, market->houses[allocation[p]]);
            remaining[p] = false;
            --left;
            p = points[p];
        } while (p != first);
        append(&history, "\n");
    }
    printf("TTC %s cycles=%d\n", market->name, cycles);
    emit(&history);
    print_allocation(market, allocation);
}

static void serial(const Market *market, const int order[]) {
    bool taken[MAX_AGENTS] = {false}, worse[MAX_AGENTS] = {false};
    int allocation[MAX_AGENTS], assigned = 0;
    for (int a = 0; a < market->count; ++a) allocation[a] = -1;
    for (int i = 0; i < market->count; ++i) {
        int a = order[i];
        for (int j = 0; j < market->agents[a].length; ++j) {
            int house = market->agents[a].preference[j];
            if (!taken[house]) {
                allocation[a] = house;
                taken[house] = true;
                ++assigned;
                break;
            }
        }
        int list[MAX_AGENTS], length = effective(market, a, list);
        worse[a] = true;
        for (int j = 0; j < length; ++j)
            if (list[j] == allocation[a]) worse[a] = false;
    }
    printf("SERIAL %s assigned=%d\n", market->name, assigned);
    print_allocation(market, allocation);
    fputs("WORSE", stdout);
    bool any = false;
    for (int a = 0; a < market->count; ++a) if (worse[a]) { printf(" %s", market->agents[a].name); any = true; }
    puts(any ? "" : " -");
}

static void hr(const Market *market) {
    Matching resident = deferred(market, false, NULL).matching;
    Matching hospital = deferred(market, true, NULL).matching;
    printf("HR %s residents=%d hospitals=%d\n", market->name, market->proposers, market->receivers);
    fputs("RESIDENT-OPTIMAL ", stdout); print_matching(market, resident);
    fputs("HOSPITAL-OPTIMAL ", stdout); print_matching(market, hospital);
    fputs("UNMATCHED", stdout);
    bool any = false, rural = true;
    for (int p = 0; p < market->proposers; ++p) {
        if (resident.partner[p] < 0) { printf(" %s", market->agents[p].name); any = true; }
        if ((resident.partner[p] < 0) != (hospital.partner[p] < 0)) rural = false;
    }
    puts(any ? "" : " -");
    for (int r = market->proposers; r < market->count; ++r) {
        int a = 0, h = 0;
        bool same = true;
        for (int p = 0; p < market->proposers; ++p) {
            a += resident.partner[p] == r;
            h += hospital.partner[p] == r;
            if ((resident.partner[p] == r) != (hospital.partner[p] == r)) same = false;
        }
        printf("HOSPITAL %s cap=%d resident=%d hospital=%d same=%s\n", market->agents[r].name,
               market->agents[r].capacity, a, h, same ? "YES" : "NO");
        if (a != h || (a < market->agents[r].capacity && !same)) rural = false;
    }
    printf("RURAL %s\n", rural ? "HOLDS" : "FAILS");
}

static void manipulate(const Market *market, int a) {
    int baseline_b = boston(market).matching.partner[a];
    int baseline_g = deferred(market, false, NULL).matching.partner[a];
    const Agent *agent = &market->agents[a];
    printf("MANIPULATE %s %s boston=%s gs=%s swaps=%d\n", market->name, agent->name,
           partner_name(market, baseline_b), partner_name(market, baseline_g), agent->length ? agent->length - 1 : 0);
    bool improved = false;
    for (int i = 0; i + 1 < agent->length; ++i) {
        Market trial = *market;
        trial.agents[a].preference[i] = agent->preference[i + 1];
        trial.agents[a].preference[i + 1] = agent->preference[i];
        int b = boston(&trial).matching.partner[a];
        int g = deferred(&trial, false, NULL).matching.partner[a];
        int result[] = {b, g}, baseline[] = {baseline_b, baseline_g};
        const char *labels[] = {"BOSTON", "GS"};
        for (int k = 0; k < 2; ++k) if (rank_of(market, a, result[k]) < rank_of(market, a, baseline[k])) {
            printf("IMPROVE %s %d %s %s result=%s\n", labels[k], i + 1,
                   market->agents[agent->preference[i]].name, market->agents[agent->preference[i + 1]].name,
                   partner_name(market, result[k]));
            improved = true;
        }
    }
    if (!improved) puts("NO IMPROVEMENT");
}

static int gcd(int a, int b) {
    while (b) { int remainder = a % b; a = b; b = remainder; }
    return a;
}

static void stats(const Market *market) {
    int pairs = 0, sum[2] = {0}, first[2] = {0}, receivers[MAX_AGENTS] = {0};
    for (int p = 0; p < market->proposers; ++p) {
        int r = market->current.partner[p];
        if (r < 0) continue;
        ++pairs;
        ++receivers[r];
        int ranks[] = {rank_of(market, p, r), rank_of(market, r, p)};
        for (int i = 0; i < 2; ++i) { sum[i] += ranks[i]; first[i] += ranks[i] == 1; }
    }
    int unmatched[] = {market->proposers - pairs, 0};
    for (int r = market->proposers; r < market->count; ++r) unmatched[1] += !receivers[r];
    printf("STATS %s source=%s pairs=%d\n", market->name, sources[market->source], pairs);
    const char *labels[] = {"PROPOSERS", "RECEIVERS"};
    for (int i = 0; i < 2; ++i) {
        printf("%s sum=%d average=", labels[i], sum[i]);
        if (pairs) {
            int divisor = gcd(sum[i], pairs), hundredths = 100 * sum[i] / pairs;
            printf("%d/%d truncated=%d.%02d", sum[i] / divisor, pairs / divisor, hundredths / 100, hundredths % 100);
        } else fputs("- truncated=-", stdout);
        printf(" first=%d unmatched=%d\n", first[i], unmatched[i]);
    }
}

static void create_market(char *words[], int count) {
    const char *command = words[0], *name = words[1];
    if (find_market(name)) { printf("ERROR DUPLICATE MARKET %s\n", name); return; }
    Market market = {0};
    strcpy(market.name, name);
    market.type = !strcmp(command, "ROOMS") ? ROOMMATE : !strcmp(command, "HOUSES") ? HOUSING : TWO_SIDED;
    if (!strcmp(command, "RANDOM")) {
        int n = atoi(words[2]);
        market.proposers = market.receivers = n;
        market.count = 2 * n;
        int64_t state = strtoll(words[3], NULL, 10);
        for (int a = 0; a < market.count; ++a) {
            Agent *agent = &market.agents[a];
            snprintf(agent->name, sizeof agent->name, "%c%d", a < n ? 'P' : 'R', a % n + 1);
            agent->length = n;
            agent->capacity = 1;
            for (int i = 0; i < n; ++i) agent->preference[i] = (a < n ? n : 0) + i;
            for (int i = n; i > 1; --i) {
                state = 48271 * state % 2147483647;
                int j = (int)(state % i), temporary = agent->preference[i - 1];
                agent->preference[i - 1] = agent->preference[j];
                agent->preference[j] = temporary;
            }
        }
        printf("RANDOM %s n=%d seed=%lld\n", name, n, (long long)strtoll(words[3], NULL, 10));
    } else {
        for (int i = 2; i < count; ++i) {
            if (!strcmp(words[i], "|")) { market.proposers = market.count; continue; }
            char *house = NULL;
            if (market.type == HOUSING) { house = strchr(words[i], ':'); *house++ = '\0'; }
            if (index_of(&market, words[i]) >= 0) { printf("ERROR DUPLICATE AGENT %s\n", words[i]); return; }
            if (house && house_index(&market, house) >= 0) { printf("ERROR DUPLICATE HOUSE %s\n", house); return; }
            strcpy(market.agents[market.count].name, words[i]);
            market.agents[market.count].capacity = 1;
            if (house) strcpy(market.houses[market.count], house);
            ++market.count;
        }
        if (market.type == TWO_SIDED) {
            market.receivers = market.count - market.proposers;
            printf("MARKET %s proposers=%d receivers=%d\n", name, market.proposers, market.receivers);
        } else printf("%s %s agents=%d\n", command, name, market.count);
    }
    Market *saved = allocate(sizeof *saved);
    *saved = market;
    markets[market_count++] = saved;
}

static void show(const Market *market) {
    if (market->type == TWO_SIDED)
        printf("SHOW %s MARKET proposers=%d receivers=%d\n", market->name, market->proposers, market->receivers);
    else printf("SHOW %s %s agents=%d\n", market->name, market->type == ROOMMATE ? "ROOMS" : "HOUSES", market->count);
    for (int a = 0; a < market->count; ++a) {
        const Agent *agent = &market->agents[a];
        if (market->type == TWO_SIDED) {
            printf("%s %s", a < market->proposers ? "PROPOSER" : "RECEIVER", agent->name);
            if (a >= market->proposers) printf(" cap=%d", agent->capacity);
        } else {
            printf("AGENT %s", agent->name);
            if (market->type == HOUSING) printf(" house=%s", market->houses[a]);
        }
        if (!agent->length) fputs(" -", stdout);
        for (int i = 0; i < agent->length; ++i) {
            int b = agent->preference[i];
            printf(" %s", market->type == HOUSING ? market->houses[b] : market->agents[b].name);
        }
        putchar('\n');
    }
    if (market->type == TWO_SIDED) printf("CURRENT %s\n", sources[market->source]);
}

static void command(char *words[], int count) {
    const char *op = words[0];
    if (!strcmp(op, "MARKET") || !strcmp(op, "ROOMS") || !strcmp(op, "HOUSES") || !strcmp(op, "RANDOM")) {
        create_market(words, count);
        return;
    }
    Market *market = find_market(words[1]);
    if (!market) { printf("ERROR UNKNOWN MARKET %s\n", words[1]); return; }
    if (!strcmp(op, "SHOW")) show(market);
    else if (!strcmp(op, "PREF")) {
        int a = require_agent(market, words[2], -1);
        if (a < 0) return;
        int preference[MAX_AGENTS], length = 0;
        bool used[MAX_AGENTS] = {false};
        for (int i = 3; i < count; ++i) {
            int b = market->type == HOUSING ? house_index(market, words[i]) : index_of(market, words[i]);
            bool possible = b >= 0;
            if (market->type == TWO_SIDED) possible = possible && ((a < market->proposers) != (b < market->proposers));
            if (market->type == ROOMMATE) possible = possible && b != a;
            if (!possible) { printf("ERROR BAD CHOICE %s\n", words[i]); return; }
            if (used[b]) { printf("ERROR DUPLICATE CHOICE %s\n", words[i]); return; }
            used[b] = true;
            preference[length++] = b;
        }
        memcpy(market->agents[a].preference, preference, (size_t)length * sizeof(int));
        market->agents[a].length = length;
        market->source = NONE;
        printf("PREF %s %s length=%d\n", market->name, market->agents[a].name, length);
    } else if (!strcmp(op, "CHECK")) {
        if (market->type == HOUSING) { printf("ERROR WRONG TYPE %s\n", market->name); return; }
        int partner[MAX_AGENTS], counts[MAX_AGENTS] = {0};
        for (int a = 0; a < market->count; ++a) partner[a] = -1;
        for (int i = 2; i < count; ++i) {
            char *right = strchr(words[i], '-');
            *right++ = '\0';
            bool two = market->type == TWO_SIDED;
            int x = require_agent(market, words[i], two ? 0 : -1);
            if (x < 0) return;
            int y = require_agent(market, right, two ? 1 : -1);
            if (y < 0) return;
            if (partner[x] >= 0) { printf("ERROR DUPLICATE AGENT %s\n", words[i]); return; }
            if (two) {
                if (++counts[y] > market->agents[y].capacity) { printf("ERROR OVER CAPACITY %s\n", right); return; }
            } else {
                if (y == x || partner[y] >= 0) { printf("ERROR DUPLICATE AGENT %s\n", right); return; }
                partner[y] = x;
            }
            partner[x] = y;
        }
        check_matching(market, partner);
    } else if (!strcmp(op, "ROOMMATES")) {
        if (!require_type(market, ROOMMATE)) return;
        for (int a = 0; a < market->count; ++a)
            if (market->agents[a].length < market->count - 1) { printf("ERROR INCOMPLETE %s\n", market->agents[a].name); return; }
        roommates(market, count == 3);
    } else if (!strcmp(op, "TTC") || !strcmp(op, "SERIAL")) {
        if (!require_type(market, HOUSING)) return;
        if (!strcmp(op, "TTC")) ttc(market);
        else {
            int order[MAX_AGENTS], length = 0;
            bool used[MAX_AGENTS] = {false};
            for (int i = 2; i < count; ++i) {
                int a = require_agent(market, words[i], -1);
                if (a < 0) return;
                if (used[a]) { printf("ERROR DUPLICATE AGENT %s\n", words[i]); return; }
                used[a] = true;
                order[length++] = a;
            }
            if (length != market->count) { puts("ERROR BAD ORDER"); return; }
            serial(market, order);
        }
    } else {
        if (!require_type(market, TWO_SIDED)) return;
        if (!strcmp(op, "CAPACITY")) {
            int r = require_agent(market, words[2], 1);
            if (r < 0) return;
            market->agents[r].capacity = atoi(words[3]);
            market->source = NONE;
            printf("CAPACITY %s %s %d\n", market->name, market->agents[r].name, market->agents[r].capacity);
        } else if (!strcmp(op, "GS") || !strcmp(op, "GSR")) {
            Text history = {0};
            bool reverse = !strcmp(op, "GSR");
            Deferred result = deferred(market, reverse, count == 3 ? &history : NULL);
            market->current = result.matching;
            market->source = reverse ? GSR : GS;
            printf("%s %s proposals=%d\n", op, market->name, result.proposals);
            emit(&history);
            fputs("MATCHING ", stdout); print_matching(market, result.matching);
        } else if (!strcmp(op, "BOSTON")) {
            Boston result = boston(market);
            market->current = result.matching;
            market->source = BOSTON;
            printf("BOSTON %s applications=%d\n", market->name, result.applications);
            fputs("MATCHING ", stdout); print_matching(market, result.matching);
        } else if (!strcmp(op, "HR")) hr(market);
        else if (!strcmp(op, "MANIPULATE")) {
            int a = require_agent(market, words[2], 0);
            if (a >= 0) manipulate(market, a);
        } else if (!strcmp(op, "STATS")) {
            if (market->source == NONE) puts("ERROR NO MATCHING");
            else stats(market);
        } else {
            for (int r = market->proposers; r < market->count; ++r)
                if (market->agents[r].capacity != 1) { puts("ERROR NOT ONE TO ONE"); return; }
            Lattice *lattice = allocate(sizeof *lattice);
            if (!enumerate(market, lattice)) { free(lattice); puts("ERROR TOO MANY MATCHINGS"); return; }
            if (!strcmp(op, "LATTICE")) {
                printf("LATTICE %s matchings=%d rotations=%d\n", market->name, lattice->count, lattice->rotation_count);
                for (int i = 0; i < lattice->count; ++i) {
                    Node node = lattice->nodes[i];
                    int cost, regret;
                    metrics(market, node.matching, &cost, &regret);
                    printf("MATCHING %d from=", i + 1);
                    if (i) printf("%d via=%d", node.origin, node.via);
                    else fputs("- via=-", stdout);
                    printf(" cost=%d regret=%d ", cost, regret);
                    print_matching(market, node.matching);
                }
                for (int i = 0; i < lattice->rotation_count; ++i) {
                    const Rotation *rotation = &lattice->rotations[i];
                    printf("ROTATION %d", i + 1);
                    for (int j = 0; j < rotation->count; ++j)
                        printf(" %s-%s", market->agents[rotation->proposer[j]].name, market->agents[rotation->receiver[j]].name);
                    putchar('\n');
                }
            } else {
                bool egalitarian = !strcmp(op, "EGALITARIAN");
                int best = 0, value = 0;
                for (int i = 0; i < lattice->count; ++i) {
                    int cost, regret;
                    metrics(market, lattice->nodes[i].matching, &cost, &regret);
                    int candidate = egalitarian ? cost : regret;
                    if (!i || candidate < value) { best = i; value = candidate; }
                }
                market->current = lattice->nodes[best].matching;
                market->source = egalitarian ? EGALITARIAN : MINREGRET;
                printf("%s %s matching=%d %s=%d\n", op, market->name, best + 1, egalitarian ? "cost" : "regret", value);
                fputs("MATCHING ", stdout); print_matching(market, market->current);
            }
            free(lattice);
        }
    }
}

int main(void) {
    char line[512];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int commands = atoi(line);
    for (int i = 0; i < commands; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        line[strcspn(line, "\r\n")] = '\0';
        char *words[32];
        int count = 0;
        for (char *word = strtok(line, " "); word; word = strtok(NULL, " ")) words[count++] = word;
        command(words, count);
    }
    for (int i = 0; i < market_count; ++i) free(markets[i]);
    return 0;
}
