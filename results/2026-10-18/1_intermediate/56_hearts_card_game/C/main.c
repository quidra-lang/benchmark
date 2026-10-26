#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <setjmp.h>

typedef uint64_t CardSet;
static const char *SEATS = "NESW", *SUITS = "CDSH", *RANKS = "23456789TJQKA";
static const char *STRATEGIES[] = {"BASIC", "LOW", "HIGH", "SMART", "MOON"};
static jmp_buf command_error;
static char error_reason[256];
static void fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vsnprintf(error_reason, sizeof error_reason, format, args);
    va_end(args);
    longjmp(command_error, 1);
}
static void *allocate(size_t n) {
    void *p = malloc(n);
    if (!p)
        exit(1);
    return p;
}
static char *format(const char *fmt, ...) {
    va_list args, copy;
    va_start(args, fmt);
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, fmt, copy);
    va_end(copy);
    char *s = allocate((size_t)n + 1);
    vsnprintf(s, (size_t)n + 1, fmt, args);
    va_end(args);
    return s;
}
static CardSet bit(int c) {
    return UINT64_C(1) << c;
}
static int size(CardSet h) {
    int n = 0;
    while (h) {
        h &= h - 1;
        ++n;
    }
    return n;
}
static CardSet suit_cards(int s) {
    return UINT64_C(8191) << (s * 13);
}
static bool penalty(int c) {
    return c == 36 || c / 13 == 3;
}
static const char *card_text(int c) {
    static char slots[8][3];
    static int next;
    char *s = slots[next++ % 8];
    s[0] = RANKS[c % 13];
    s[1] = SUITS[c / 13];
    s[2] = 0;
    return s;
}
static void cards_text(CardSet h, char out[160]) {
    int n = 0;
    for (int c = 0; c < 52; ++c)
        if (h & bit(c)) {
            if (n)
                out[n++] = ' ';
            out[n++] = RANKS[c % 13];
            out[n++] = SUITS[c / 13];
        }
    if (!n)
        out[n++] = '-';
    out[n] = 0;
}
static int extreme(CardSet h, bool high) {
    for (int rank = high ? 12 : 0; rank >= 0 && rank < 13; rank += high ? -1 : 1)
        for (int suit = 0; suit < 4; ++suit)
            if (h & bit(suit * 13 + rank))
                return suit * 13 + rank;
    return -1;
}
static int parse_seat(const char *s) {
    const char *p = strlen(s) == 1 ? strchr(SEATS, s[0]) : NULL;
    if (!p)
        fail("bad seat %s", s);
    return (int)(p - SEATS);
}
static int parse_card(const char *s) {
    if (strlen(s) != 2 || !strchr(RANKS, s[0]) || !strchr(SUITS, s[1]))
        fail("bad card %s", s);
    return (int)(strchr(SUITS, s[1]) - SUITS) * 13 + (int)(strchr(RANKS, s[0]) - RANKS);
}
static int bounded(const char *s, int low, int high) {
    char *end;
    long n = strtol(s, &end, 10);
    if (*end || end == s || n < low || n > high)
        fail("bad value %s", s);
    return (int)n;
}
static CardSet checked_set(const int *cards, int n) {
    CardSet h = 0;
    for (int i = 0; i < n; ++i) {
        if (h & bit(cards[i]))
            fail("duplicate card %s", card_text(cards[i]));
        h |= bit(cards[i]);
    }
    return h;
}
static const char *direction(char c) {
    return c == 'L' ? "LEFT" : c == 'R' ? "RIGHT" : c == 'A' ? "ACROSS" : "HOLD";
}
typedef struct {
    int target, limit, moon;
    bool jack, qsbreak, blood;
    char pass[9];
} Rules;
typedef struct {
    int level;
    char *text;
} Line;
typedef struct {
    Line *lines;
    size_t count, capacity;
} Log;
static void log_line(Log *log, int level, char *s) {
    if (log->count == log->capacity) {
        log->capacity = log->capacity ? log->capacity * 2 : 64;
        log->lines = realloc(log->lines, log->capacity * sizeof(Line));
        if (!log->lines)
            exit(1);
    }
    log->lines[log->count++] = (Line){level, s};
}
static void trim_log(Log *log, size_t n) {
    while (log->count > n)
        free(log->lines[--log->count].text);
}
typedef enum { NO_GAME, BETWEEN, PASSING, PLAYING } State;
typedef struct {
    int seat, card;
} Play;
typedef struct {
    Play plays[4];
    int count;
} Trick;
typedef struct {
    CardSet hands[4], taken[4];
    Trick tricks[13], current;
    int trick_count, counts[4], leader;
    bool broken;
} Hand;
typedef struct {
    Hand hand;
    size_t log_count;
    int seat, card;
} Snapshot;
typedef struct {
    int number, points[4], shooter;
    char pass;
    size_t begin, end;
} History;
typedef struct {
    Rules rules;
    int bots[4];
    int64_t random;
    State state;
    int number, scores[4], stats[4][4];
    CardSet stacked[4], passes[4];
    bool specified[4], passed[4];
    char pass;
    Hand hand;
    Snapshot undo[52];
    int undo_count;
    History history[100];
    int history_count;
    size_t hand_begin;
    Log log;
} Game;
static int point(const Game *g, int c) {
    return c == 36 ? 13 : c / 13 == 3 ? 1 : c == 22 && g->rules.jack ? -10 : 0;
}
static int points(const Game *g, CardSet h) {
    int total = 0;
    for (int c = 0; c < 52; ++c)
        if (h & bit(c))
            total += point(g, c);
    return total;
}
static Game *new_game(Rules rules, const int bots[4], int64_t seed) {
    Game *g = calloc(1, sizeof *g);
    if (!g)
        exit(1);
    g->rules = rules;
    memcpy(g->bots, bots, sizeof g->bots);
    g->random = seed;
    g->state = BETWEEN;
    return g;
}
static void free_game(Game *g) {
    if (g) {
        trim_log(&g->log, 0);
        free(g->log.lines);
        free(g);
    }
}
static void emit(Game *g, int level, const char *fmt, ...) {
    va_list args, copy;
    va_start(args, fmt);
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, fmt, copy);
    va_end(copy);
    char *s = allocate((size_t)n + 1);
    vsnprintf(s, (size_t)n + 1, fmt, args);
    va_end(args);
    log_line(&g->log, level, s);
}
static void pair_line(Game *g, int level, const char *label, const int v[4]) {
    emit(g, level, "%s N %d E %d S %d W %d", label, v[0], v[1], v[2], v[3]);
}
static void stats_lines(Game *g, bool output) {
    for (int s = 0; s < 4; ++s) {
        int *v = g->stats[s];
        if (output)
            printf("stats %c tricks %d hearts %d queens %d moons %d\n", SEATS[s], v[0], v[1], v[2],
                   v[3]);
        else
            emit(g, 0, "stats %c tricks %d hearts %d queens %d moons %d", SEATS[s], v[0], v[1],
                 v[2], v[3]);
    }
}
static void ranking(const int scores[4], int order[4]) {
    for (int i = 0; i < 4; ++i)
        order[i] = i;
    for (int i = 1; i < 4; ++i) {
        int s = order[i], j = i;
        while (j && scores[order[j - 1]] > scores[s]) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = s;
    }
}
static bool ended(Game *g, const int scores[4]) {
    if (g->number >= g->rules.limit)
        return true;
    for (int s = 0; s < 4; ++s)
        if (scores[s] >= g->rules.target)
            return true;
    return false;
}
static void begin_play(Game *g) {
    g->state = PLAYING;
    for (int s = 0; s < 4; ++s)
        if (g->hand.hands[s] & bit(0))
            g->hand.leader = s;
    emit(g, 2, "lead %c", SEATS[g->hand.leader]);
}
static void deal(Game *g) {
    ++g->number;
    g->pass = g->rules.pass[(g->number - 1) % strlen(g->rules.pass)];
    memset(&g->hand, 0, sizeof g->hand);
    CardSet used = 0;
    int free_seats[4], free_count = 0;
    for (int s = 0; s < 4; ++s) {
        if (g->specified[s]) {
            g->hand.hands[s] = g->stacked[s];
            used |= g->stacked[s];
        } else
            free_seats[free_count++] = s;
    }
    int deck[52], count = 0;
    for (int c = 0; c < 52; ++c)
        if (!(used & bit(c)))
            deck[count++] = c;
    for (int i = count - 1; i > 0; --i) {
        g->random = 48271 * g->random % 2147483647;
        int j = (int)(g->random % (i + 1));
        int temp = deck[i];
        deck[i] = deck[j];
        deck[j] = temp;
    }
    for (int i = 0; i < count; ++i)
        g->hand.hands[free_seats[i % free_count]] |= bit(deck[i]);
    memset(g->specified, 0, sizeof g->specified);
    memset(g->passed, 0, sizeof g->passed);
    memset(g->passes, 0, sizeof g->passes);
    g->undo_count = 0;
    g->hand_begin = g->log.count;
    emit(g, 1, "hand %d pass %s", g->number, direction(g->pass));
    for (int s = 0; s < 4; ++s) {
        char cards[160];
        cards_text(g->hand.hands[s], cards);
        emit(g, 2, "%c: %s", SEATS[s], cards);
    }
    if (g->pass == 'H')
        begin_play(g);
    else
        g->state = PASSING;
}
static void pass_cards(Game *g, int seat, CardSet cards) {
    g->hand.hands[seat] &= ~cards;
    g->passes[seat] = cards;
    g->passed[seat] = true;
    char text[160];
    cards_text(cards, text);
    emit(g, 2, "%c passes %s", SEATS[seat], text);
    if (g->passed[0] && g->passed[1] && g->passed[2] && g->passed[3]) {
        int offset = g->pass == 'L' ? 1 : g->pass == 'R' ? 3 : 2;
        for (int s = 0; s < 4; ++s)
            g->hand.hands[(s + offset) % 4] |= g->passes[s];
        begin_play(g);
    }
}
static int actor(const Game *g) {
    return (g->hand.leader + g->hand.current.count) % 4;
}
static CardSet legal(const Game *g) {
    const Hand *h = &g->hand;
    CardSet hand = h->hands[actor(g)];
    if (!h->current.count) {
        if (!h->trick_count)
            return bit(0);
        CardSet safe = hand & ~suit_cards(3);
        return !h->broken && safe ? safe : hand;
    }
    CardSet follow = hand & suit_cards(h->current.plays[0].card / 13);
    if (follow)
        return follow;
    if (!h->trick_count && !g->rules.blood) {
        CardSet safe = hand & ~(suit_cards(3) | bit(36));
        if (safe)
            return safe;
    }
    return hand;
}
static void add_priority(CardSet *out, int *count, int c, CardSet hand) {
    if (*count < 3 && (hand & bit(c)) && !(*out & bit(c))) {
        *out |= bit(c);
        ++*count;
    }
}
static CardSet choose_pass(const Game *g, int seat) {
    CardSet hand = g->hand.hands[seat], out = 0;
    int count = 0, strategy = g->bots[seat];
    if (strategy == 1 || strategy == 2 || strategy == 4) {
        CardSet remaining = hand;
        if (strategy == 4) {
            CardSet safe = hand & ~suit_cards(3);
            while (safe && count < 3) {
                int c = extreme(safe, false);
                add_priority(&out, &count, c, hand);
                safe &= ~bit(c);
            }
            remaining = hand & suit_cards(3);
        }
        while (remaining && count < 3) {
            int c = extreme(remaining, strategy == 1);
            add_priority(&out, &count, c, hand);
            remaining &= ~bit(c);
        }
        return out;
    }
    bool protect = strategy == 3 && (hand & bit(36)) && size(hand & suit_cards(2)) >= 5;
    if (!protect)
        for (int c = 36; c <= 38; ++c)
            add_priority(&out, &count, c, hand);
    if (strategy == 3) {
        int c = size(hand & suit_cards(0)), d = size(hand & suit_cards(1));
        int suit = c && (!d || c <= d) ? 0 : d ? 1 : -1;
        if (suit >= 0) {
            CardSet selected = hand & suit_cards(suit);
            while (selected && count < 3) {
                int card = extreme(selected, true);
                add_priority(&out, &count, card, hand);
                selected &= ~bit(card);
            }
        }
    }
    CardSet hearts = hand & suit_cards(3);
    while (hearts && count < 3) {
        int c = extreme(hearts, true);
        add_priority(&out, &count, c, hand);
        hearts &= ~bit(c);
    }
    while (hand && count < 3) {
        int c = extreme(hand, true);
        add_priority(&out, &count, c, hand);
        hand &= ~bit(c);
    }
    return out;
}
static bool queen_played(const Game *g) {
    for (int s = 0; s < 4; ++s)
        if (g->hand.taken[s] & bit(36))
            return true;
    for (int i = 0; i < g->hand.current.count; ++i)
        if (g->hand.current.plays[i].card == 36)
            return true;
    return false;
}
static int choose_play(const Game *g) {
    const Hand *h = &g->hand;
    int seat = actor(g), strategy = g->bots[seat];
    CardSet choices = legal(g), hand = h->hands[seat];
    if (strategy == 1 || strategy == 2)
        return extreme(choices, strategy == 2);
    if (strategy == 4)
        for (int s = 0; s < 4; ++s)
            if (s != seat && (h->taken[s] & (suit_cards(3) | bit(36))))
                strategy = 0;
    if (!h->current.count) {
        CardSet spades = choices & suit_cards(2) & ((UINT64_C(1) << 36) - 1);
        if (strategy == 3 && !queen_played(g) && !(hand & bit(36)) && spades)
            return extreme(spades, false);
        int suit = -1, best = strategy == 4 ? -1 : 100;
        for (int s = 0; s < 4; ++s) {
            int n = size(choices & suit_cards(s));
            if (n && (strategy == 4 ? n > best : n < best)) {
                suit = s;
                best = n;
            }
        }
        return extreme(choices & suit_cards(suit), strategy == 4);
    }
    int led = h->current.plays[0].card / 13;
    if (hand & suit_cards(led)) {
        int winning = -1;
        for (int i = 0; i < h->current.count; ++i) {
            int c = h->current.plays[i].card;
            if (c / 13 == led && c % 13 > winning)
                winning = c % 13;
        }
        CardSet lower = 0;
        for (int c = 0; c < 52; ++c)
            if ((choices & bit(c)) && c % 13 < winning)
                lower |= bit(c);
        if (strategy == 4) {
            int high = extreme(choices, true);
            return high % 13 > winning ? high : extreme(choices, false);
        }
        if (lower)
            return extreme(lower, true);
        if (strategy == 3 && h->current.count == 3)
            return extreme(choices & ~bit(36) ? choices & ~bit(36) : bit(36), true);
        return extreme(choices, false);
    }
    if (strategy == 4) {
        CardSet safe = choices & ~(suit_cards(3) | bit(36));
        return extreme(safe ? safe : choices, false);
    }
    if (choices & bit(36))
        return 36;
    if (strategy == 3 && !queen_played(g)) {
        if (choices & bit(38))
            return 38;
        if (choices & bit(37))
            return 37;
    }
    CardSet hearts = choices & suit_cards(3);
    return extreme(hearts ? hearts : choices, true);
}
static int winner(Trick t) {
    int best = 0;
    for (int i = 1; i < t.count; ++i)
        if (t.plays[i].card / 13 == t.plays[0].card / 13 &&
            t.plays[i].card % 13 > t.plays[best].card % 13)
            best = i;
    return t.plays[best].seat;
}
static int trick_points(const Game *g, Trick t) {
    int n = 0;
    for (int i = 0; i < t.count; ++i)
        n += point(g, t.plays[i].card);
    return n;
}
static char *trick_line(const Game *g, Trick t, int number) {
    char plays[100] = "";
    for (int i = 0; i < t.count; ++i) {
        size_t n = strlen(plays);
        snprintf(plays + n, sizeof plays - n, "%s%c %s", i ? " " : "", SEATS[t.plays[i].seat],
                 card_text(t.plays[i].card));
    }
    return format("trick %d: %s -> %c %d", number, plays, SEATS[winner(t)], trick_points(g, t));
}
static void finish_hand(Game *g) {
    int p[4], shooter = -1;
    for (int s = 0; s < 4; ++s) {
        p[s] = points(g, g->hand.taken[s]);
        if (size(g->hand.taken[s] & (suit_cards(3) | bit(36))) == 14)
            shooter = s;
    }
    if (shooter >= 0) {
        p[shooter] -= 26;
        int method = g->rules.moon;
        if (method == 2) {
            int add[4], ranks[4];
            for (int s = 0; s < 4; ++s)
                add[s] = g->scores[s] + p[s] + (s == shooter ? 0 : 26);
            ranking(add, ranks);
            method = ended(g, add) && ranks[0] != shooter ? 1 : 0;
        }
        if (method == 1)
            p[shooter] -= 26;
        else
            for (int s = 0; s < 4; ++s)
                if (s != shooter)
                    p[s] += 26;
        emit(g, 1, "moon %c %s", SEATS[shooter], method == 1 ? "SUB" : "ADD");
    }
    for (int s = 0; s < 4; ++s) {
        g->scores[s] += p[s];
        g->stats[s][0] += g->hand.counts[s];
        g->stats[s][1] += size(g->hand.taken[s] & suit_cards(3));
        g->stats[s][2] += !!(g->hand.taken[s] & bit(36));
        g->stats[s][3] += s == shooter;
    }
    pair_line(g, 1, "points", p);
    pair_line(g, 1, "scores", g->scores);
    History *history = &g->history[g->history_count++];
    history->number = g->number;
    history->pass = g->pass;
    memcpy(history->points, p, sizeof p);
    history->shooter = shooter;
    history->begin = g->hand_begin;
    history->end = g->log.count;
    g->state = ended(g, g->scores) ? NO_GAME : BETWEEN;
    if (g->state == NO_GAME) {
        emit(g, 0, "game over hands %d", g->number);
        int order[4];
        ranking(g->scores, order);
        for (int i = 0; i < 4; ++i)
            emit(g, 0, "rank %d %c %d", i + 1, SEATS[order[i]], g->scores[order[i]]);
        stats_lines(g, false);
    }
}
static void play_card(Game *g, int card) {
    Hand *h = &g->hand;
    int seat = actor(g);
    g->undo[g->undo_count++] = (Snapshot){*h, g->log.count, seat, card};
    h->hands[seat] &= ~bit(card);
    h->current.plays[h->current.count++] = (Play){seat, card};
    if (card / 13 == 3 || (card == 36 && g->rules.qsbreak))
        h->broken = true;
    if (h->current.count == 4) {
        int w = winner(h->current);
        for (int i = 0; i < 4; ++i)
            h->taken[w] |= bit(h->current.plays[i].card);
        ++h->counts[w];
        h->tricks[h->trick_count++] = h->current;
        log_line(&g->log, 2, trick_line(g, h->current, h->trick_count));
        h->current.count = 0;
        h->leader = w;
        if (h->trick_count == 13)
            finish_hand(g);
    }
}
static void auto_pass(Game *g) {
    for (int s = 0; s < 4; ++s)
        if (!g->passed[s])
            pass_cards(g, s, choose_pass(g, s));
}
static void auto_hand(Game *g) {
    if (g->state == PASSING)
        auto_pass(g);
    while (g->state == PLAYING)
        play_card(g, choose_play(g));
}
static void auto_game(Game *g) {
    if (g->state == PASSING || g->state == PLAYING)
        auto_hand(g);
    while (g->state != NO_GAME) {
        deal(g);
        auto_hand(g);
    }
}
static Rules rules = {100, 100, 0, false, false, false, "LRAH"};
static int bots[4];
static Game *table;
static bool active(void) {
    return table && table->state != NO_GAME;
}
static void require_game(void) {
    if (!active())
        fail("no game");
}
static void require_state(State state, const char *error) {
    if (!active() || table->state != state)
        fail("%s", error);
}
static void require_hand(void) {
    if (!active() || (table->state != PASSING && table->state != PLAYING))
        fail("no hand");
}
static void simulation(const char *command, int seed, int count) {
    int64_t random = seed;
    if (!strcmp(command, "GAME")) {
        Game *g = new_game(rules, bots, random);
        auto_game(g);
        printf("game seed %d\n", seed);
        for (size_t i = 0; i < g->log.count; ++i)
            if (g->log.lines[i].level <= count)
                puts(g->log.lines[i].text);
        free_game(g);
        return;
    }
    bool rotate = !strcmp(command, "ROTATE");
    int rounds = rotate ? 4 : 1, games = count * rounds, hands = 0;
    int places[4][4] = {{0}}, totals[4] = {0}, stats[4][4] = {{0}};
    for (int r = 0; r < rounds; ++r) {
        int strategies[4];
        for (int s = 0; s < 4; ++s)
            strategies[(s + r) % 4] = bots[s];
        for (int k = 0; k < count; ++k) {
            Game *g = new_game(rules, strategies, random);
            auto_game(g);
            random = g->random;
            hands += g->number;
            int order[4];
            ranking(g->scores, order);
            for (int s = 0; s < 4; ++s) {
                int actual = (s + r) % 4, place = 0;
                while (order[place] != actual)
                    ++place;
                ++places[s][place];
                totals[s] += g->scores[actual];
                for (int j = 0; j < 4; ++j)
                    stats[s][j] += g->stats[actual][j];
            }
            free_game(g);
        }
    }
    printf("%s seed %d games %d hands %d\n", rotate ? "rotate" : "match", seed, games, hands);
    for (int s = 0; s < 4; ++s) {
        int64_t numerator = 100LL * totals[s], cents = numerator / games;
        if (numerator < 0 && numerator % games)
            --cents;
        int64_t magnitude = cents < 0 ? -cents : cents;
        printf("%c", SEATS[s]);
        if (rotate)
            printf(" %s", STRATEGIES[bots[s]]);
        printf(
            " places %d %d %d %d total %d average %s%lld.%02lld tricks %d hearts %d queens %d moons %d\n",
            places[s][0], places[s][1], places[s][2], places[s][3], totals[s], cents < 0 ? "-" : "",
            (long long)(magnitude / 100), (long long)(magnitude % 100), stats[s][0], stats[s][1],
            stats[s][2], stats[s][3]);
    }
}
static void command(char **w, int n) {
    const char *cmd = w[0];
    const char *known[] = {"RULE",    "BOT",    "SETTINGS", "GAME",    "MATCH", "ROTATE", "NEW",
                           "ABANDON", "STACK",  "DEAL",     "SHOW",    "PASS",  "PLAY",   "AUTO",
                           "UNDO",    "CLAIM",  "LEGAL",    "PREVIEW", "SCORE", "TAKEN",  "TRICKS",
                           "VOIDS",   "UNSEEN", "STATS",    "HISTORY", "REPLAY"};
    bool found = false;
    for (int i = 0; i < 26; ++i)
        if (!strcmp(cmd, known[i]))
            found = true;
    if (!found)
        fail("unknown command %s", cmd);
    if (!strcmp(cmd, "RULE")) {
        const char *name = w[1], *value = w[2];
        int number = 0;
        if (!strcmp(name, "TARGET"))
            number = bounded(value, 1, 1000);
        else if (!strcmp(name, "LIMIT"))
            number = bounded(value, 1, 100);
        else if (!strcmp(name, "MOON")) {
            if (strcmp(value, "ADD") && strcmp(value, "SUB") && strcmp(value, "AUTO"))
                fail("bad value %s", value);
        } else if (!strcmp(name, "JACK") || !strcmp(name, "QSBREAK") || !strcmp(name, "BLOOD")) {
            if (strcmp(value, "ON") && strcmp(value, "OFF"))
                fail("bad value %s", value);
        } else if (!strcmp(name, "PASS")) {
            if (strlen(value) < 1 || strlen(value) > 8 || strspn(value, "LRAH") != strlen(value))
                fail("bad value %s", value);
        } else
            fail("unknown rule %s", name);
        if (active())
            fail("game in progress");
        if (!strcmp(name, "TARGET"))
            rules.target = number;
        else if (!strcmp(name, "LIMIT"))
            rules.limit = number;
        else if (!strcmp(name, "MOON"))
            rules.moon = !strcmp(value, "SUB") ? 1 : !strcmp(value, "AUTO") ? 2 : 0;
        else if (!strcmp(name, "JACK"))
            rules.jack = !strcmp(value, "ON");
        else if (!strcmp(name, "QSBREAK"))
            rules.qsbreak = !strcmp(value, "ON");
        else if (!strcmp(name, "BLOOD"))
            rules.blood = !strcmp(value, "ON");
        else
            strcpy(rules.pass, value);
        printf("rule %s %s\n", name, value);
        return;
    }
    if (!strcmp(cmd, "BOT")) {
        int seat = parse_seat(w[1]), strategy = -1;
        for (int i = 0; i < 5; ++i)
            if (!strcmp(w[2], STRATEGIES[i]))
                strategy = i;
        if (strategy < 0)
            fail("bad value %s", w[2]);
        bots[seat] = strategy;
        if (table)
            table->bots[seat] = strategy;
        printf("bot %c %s\n", SEATS[seat], w[2]);
        return;
    }
    if (!strcmp(cmd, "SETTINGS")) {
        printf("rules TARGET %d LIMIT %d MOON %s JACK %s QSBREAK %s BLOOD %s PASS %s\n",
               rules.target, rules.limit,
               rules.moon == 0   ? "ADD"
               : rules.moon == 1 ? "SUB"
                                 : "AUTO",
               rules.jack ? "ON" : "OFF", rules.qsbreak ? "ON" : "OFF", rules.blood ? "ON" : "OFF",
               rules.pass);
        printf("bots N %s E %s S %s W %s\n", STRATEGIES[bots[0]], STRATEGIES[bots[1]],
               STRATEGIES[bots[2]], STRATEGIES[bots[3]]);
        return;
    }
    if (!strcmp(cmd, "GAME") || !strcmp(cmd, "MATCH") || !strcmp(cmd, "ROTATE")) {
        int seed = bounded(w[1], 1, 2147483646);
        int count = bounded(w[2], !strcmp(cmd, "GAME") ? 0 : 1,
                            !strcmp(cmd, "GAME")    ? 2
                            : !strcmp(cmd, "MATCH") ? 50
                                                    : 10);
        simulation(cmd, seed, count);
        return;
    }
    if (!strcmp(cmd, "NEW")) {
        int seed = bounded(w[1], 1, 2147483646);
        if (active())
            fail("game in progress");
        free_game(table);
        table = new_game(rules, bots, seed);
        printf("new game seed %d\n", seed);
        return;
    }
    if (!strcmp(cmd, "ABANDON")) {
        require_game();
        free_game(table);
        table = NULL;
        puts("game abandoned");
        return;
    }
    int seat = -1, cards[20], count = n - 2;
    bool stack = !strcmp(cmd, "STACK"), pass = !strcmp(cmd, "PASS"), play = !strcmp(cmd, "PLAY"),
         claim = !strcmp(cmd, "CLAIM");
    if (stack || pass || play || claim)
        seat = parse_seat(w[1]);
    if (stack || pass || play)
        for (int i = 0; i < count; ++i)
            cards[i] = parse_card(w[i + 2]);
    if (stack && count != 13)
        fail("need 13 cards");
    const char *mode = !strcmp(cmd, "AUTO") ? w[1] : "";
    if (*mode && strcmp(mode, "PASS") && strcmp(mode, "CARD") && strcmp(mode, "TRICK") &&
        strcmp(mode, "HAND") && strcmp(mode, "GAME"))
        fail("bad value %s", mode);
    if (stack || !strcmp(cmd, "DEAL")) {
        require_game();
        if (table->state != BETWEEN)
            fail("hand in progress");
    } else if (!strcmp(cmd, "SHOW") || !strcmp(mode, "HAND"))
        require_hand();
    else if (pass || !strcmp(mode, "PASS"))
        require_state(PASSING, "not passing");
    else if (play || claim || !strcmp(cmd, "UNDO") || !strcmp(cmd, "LEGAL") ||
             !strcmp(cmd, "PREVIEW") || !strcmp(cmd, "TAKEN") || !strcmp(cmd, "TRICKS") ||
             !strcmp(cmd, "VOIDS") || !strcmp(cmd, "UNSEEN") || !strcmp(mode, "CARD") ||
             !strcmp(mode, "TRICK"))
        require_state(PLAYING, "not playing");
    else
        require_game();
    Game *g = table;
    Hand *h = &g->hand;
    size_t before = g->log.count;
    if (stack) {
        CardSet set = checked_set(cards, count);
        for (int i = 0; i < count; ++i)
            for (int s = 0; s < 4; ++s)
                if (s != seat && g->specified[s] && (g->stacked[s] & bit(cards[i])))
                    fail("%s stacked for %c", card_text(cards[i]), SEATS[s]);
        g->specified[seat] = true;
        g->stacked[seat] = set;
        printf("stacked %c\n", SEATS[seat]);
        return;
    }
    if (!strcmp(cmd, "DEAL"))
        deal(g);
    else if (!strcmp(cmd, "SHOW")) {
        for (int s = 0; s < 4; ++s) {
            char text[160];
            cards_text(h->hands[s], text);
            printf("%c: %s\n", SEATS[s], text);
        }
        return;
    } else if (pass) {
        if (g->passed[seat])
            fail("%c already passed", SEATS[seat]);
        CardSet set = checked_set(cards, count);
        for (int i = 0; i < count; ++i)
            if (!(h->hands[seat] & bit(cards[i])))
                fail("%c does not hold %s", SEATS[seat], card_text(cards[i]));
        pass_cards(g, seat, set);
    } else if (play) {
        int card = cards[0];
        if (actor(g) != seat)
            fail("waiting for %c", SEATS[actor(g)]);
        if (!(h->hands[seat] & bit(card)))
            fail("%c does not hold %s", SEATS[seat], card_text(card));
        if (!(legal(g) & bit(card))) {
            if (!h->current.count)
                fail("%s", h->trick_count ? "hearts not broken" : "must lead 2C");
            int led = h->current.plays[0].card / 13;
            if (h->hands[seat] & suit_cards(led))
                fail("must follow %c", SUITS[led]);
            fail("no points on first trick");
        }
        printf("%c plays %s\n", SEATS[seat], card_text(card));
        play_card(g, card);
    } else if (*mode) {
        if (!strcmp(mode, "PASS"))
            auto_pass(g);
        else if (!strcmp(mode, "CARD")) {
            int seat = actor(g), card = choose_play(g);
            printf("%c plays %s\n", SEATS[seat], card_text(card));
            play_card(g, card);
        } else if (!strcmp(mode, "TRICK")) {
            int completed = h->trick_count;
            while (g->state == PLAYING && h->trick_count == completed)
                play_card(g, choose_play(g));
        } else if (!strcmp(mode, "HAND"))
            auto_hand(g);
        else
            auto_game(g);
    } else if (!strcmp(cmd, "UNDO")) {
        if (!g->undo_count)
            fail("nothing to undo");
        Snapshot *s = &g->undo[--g->undo_count];
        *h = s->hand;
        trim_log(&g->log, s->log_count);
        printf("undo %c %s\n", SEATS[s->seat], card_text(s->card));
        return;
    } else if (claim) {
        if (actor(g) != seat)
            fail("waiting for %c", SEATS[actor(g)]);
        if (h->current.count)
            fail("trick in progress");
        for (int c = 0; c < 52; ++c) {
            if (!(h->hands[seat] & bit(c)))
                continue;
            for (int other = 0; other < 4; ++other) {
                if (other == seat)
                    continue;
                for (int higher = c + 1; higher < (c / 13 + 1) * 13; ++higher) {
                    if (h->hands[other] & bit(higher))
                        fail("claim rejected");
                }
            }
        }
        CardSet all = 0;
        for (int s = 0; s < 4; ++s) {
            all |= h->hands[s];
            h->hands[s] = 0;
        }
        int remaining = 13 - h->trick_count;
        h->taken[seat] |= all;
        h->counts[seat] += remaining;
        emit(g, 2, "claim %c tricks %d points %d", SEATS[seat], remaining, points(g, all));
        finish_hand(g);
    } else if (!strcmp(cmd, "LEGAL")) {
        char text[160];
        cards_text(legal(g), text);
        printf("legal %c: %s bot %s\n", SEATS[actor(g)], text, card_text(choose_play(g)));
        return;
    } else if (!strcmp(cmd, "PREVIEW")) {
        CardSet choices = legal(g);
        for (int c = 0; c < 52; ++c)
            if (choices & bit(c)) {
                Game *copy = new_game(g->rules, g->bots, g->random);
                copy->hand = *h;
                copy->number = g->number;
                copy->state = PLAYING;
                int ntricks = h->trick_count;
                play_card(copy, c);
                while (copy->state == PLAYING && copy->hand.trick_count == ntricks)
                    play_card(copy, choose_play(copy));
                Trick trick = copy->hand.tricks[copy->hand.trick_count - 1];
                printf("preview %s -> %c %d\n", card_text(c), SEATS[winner(trick)],
                       trick_points(copy, trick));
                free_game(copy);
            }
        return;
    } else if (!strcmp(cmd, "SCORE")) {
        printf("scores N %d E %d S %d W %d\n", g->scores[0], g->scores[1], g->scores[2],
               g->scores[3]);
        if (g->state == PLAYING)
            printf("taken N %d E %d S %d W %d\n", points(g, h->taken[0]), points(g, h->taken[1]),
                   points(g, h->taken[2]), points(g, h->taken[3]));
        return;
    } else if (!strcmp(cmd, "TAKEN")) {
        for (int s = 0; s < 4; ++s) {
            CardSet set = 0;
            for (int c = 0; c < 52; ++c)
                if ((h->taken[s] & bit(c)) && point(g, c))
                    set |= bit(c);
            char text[160];
            cards_text(set, text);
            printf("%c: %s\n", SEATS[s], text);
        }
        return;
    } else if (!strcmp(cmd, "TRICKS")) {
        for (int i = 0; i < h->trick_count; ++i) {
            char *line = trick_line(g, h->tricks[i], i + 1);
            puts(line);
            free(line);
        }
        if (h->current.count) {
            printf("current:");
            for (int i = 0; i < h->current.count; ++i)
                printf(" %c %s", SEATS[h->current.plays[i].seat],
                       card_text(h->current.plays[i].card));
            putchar('\n');
        } else if (!h->trick_count)
            puts("no tricks");
        return;
    } else if (!strcmp(cmd, "VOIDS")) {
        bool missing[4][4] = {{false}};
        for (int i = 0; i <= h->trick_count; ++i) {
            Trick t = i == h->trick_count ? h->current : h->tricks[i];
            if (!t.count)
                continue;
            int led = t.plays[0].card / 13;
            for (int j = 0; j < t.count; ++j)
                if (t.plays[j].card / 13 != led)
                    missing[t.plays[j].seat][led] = true;
        }
        printf("voids");
        for (int s = 0; s < 4; ++s) {
            printf(" %c ", SEATS[s]);
            bool any = false;
            for (int suit = 0; suit < 4; ++suit) {
                if (missing[s][suit]) {
                    putchar(SUITS[suit]);
                    any = true;
                }
            }
            if (!any)
                putchar('-');
        }
        putchar('\n');
        return;
    } else if (!strcmp(cmd, "UNSEEN")) {
        CardSet seen = h->hands[actor(g)];
        for (int s = 0; s < 4; ++s)
            seen |= h->taken[s];
        for (int i = 0; i < h->current.count; ++i)
            seen |= bit(h->current.plays[i].card);
        char text[160];
        cards_text(((UINT64_C(1) << 52) - 1) & ~seen, text);
        printf("unseen %c: %s\n", SEATS[actor(g)], text);
        return;
    } else if (!strcmp(cmd, "STATS")) {
        stats_lines(g, true);
        return;
    } else if (!strcmp(cmd, "HISTORY")) {
        if (!g->history_count)
            puts("no hands");
        for (int i = 0; i < g->history_count; ++i) {
            History r = g->history[i];
            printf("hand %d pass %s points N %d E %d S %d W %d", r.number, direction(r.pass),
                   r.points[0], r.points[1], r.points[2], r.points[3]);
            if (r.shooter >= 0)
                printf(" moon %c", SEATS[r.shooter]);
            putchar('\n');
        }
        return;
    } else if (!strcmp(cmd, "REPLAY")) {
        int number = bounded(w[1], 1, g->history_count);
        History r = g->history[number - 1];
        for (size_t i = r.begin; i < r.end; ++i)
            puts(g->log.lines[i].text);
        return;
    }
    for (size_t i = before; i < g->log.count; ++i)
        puts(g->log.lines[i].text);
}
static char *read_line(void) {
    size_t count = 0, capacity = 128;
    char *line = allocate(capacity);
    int ch;
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            char *grown = realloc(line, capacity);
            if (!grown)
                exit(1);
            line = grown;
        }
        line[count++] = (char)ch;
    }
    if (!count && ch == EOF) {
        free(line);
        return NULL;
    }
    if (count && line[count - 1] == '\r')
        --count;
    line[count] = 0;
    return line;
}
int main(void) {
    char *first = read_line();
    if (!first)
        return 0;
    int count = atoi(first);
    free(first);
    for (int i = 0; i < count; ++i) {
        char *line = read_line();
        if (!line)
            break;
        size_t capacity = 16;
        char **words = allocate(capacity * sizeof *words);
        int n = 0;
        char *word = strtok(line, " ");
        while (word) {
            if ((size_t)n == capacity) {
                capacity *= 2;
                char **grown = realloc(words, capacity * sizeof *words);
                if (!grown)
                    exit(1);
                words = grown;
            }
            words[n++] = word;
            word = strtok(NULL, " ");
        }
        if (setjmp(command_error))
            printf("error: %s\n", error_reason);
        else
            command(words, n);
        free(words);
        free(line);
    }
    free_game(table);
    return 0;
}
