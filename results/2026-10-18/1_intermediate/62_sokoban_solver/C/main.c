#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *data;
    size_t len, cap;
} String;
typedef struct {
    int player, boxes[4], count;
} Position;
typedef struct {
    int h, w, size, goals[4], goal_count, offsets[4], distance[4][100];
    unsigned char walls[100], goal[100], interior[100], dead[100];
    char reason[80];
} Level;
typedef struct {
    char name[9];
    Position position;
    String history;
} Snapshot;
typedef struct {
    Level level;
    Position initial, current, solution_position;
    String history, redo, solution;
    int has_solution, snapshot_count;
    Snapshot snapshots[500];
} Game;
static const char *directions = "udlr", *symbols = "#-.$*@+";
static void *allocate(size_t size) {
    void *p = malloc(size);
    if (!p)
        exit(EXIT_FAILURE);
    return p;
}
static void reserve(String *s, size_t size) {
    if (size + 1 > s->cap) {
        size_t cap = s->cap ? s->cap : 32;
        while (cap < size + 1)
            cap *= 2;
        char *p = realloc(s->data, cap);
        if (!p)
            exit(EXIT_FAILURE);
        s->data = p;
        s->cap = cap;
    }
}
static void append_char(String *s, char c) {
    reserve(s, s->len + 1);
    s->data[s->len++] = c;
    s->data[s->len] = 0;
}
static void append(String *s, const char *text) {
    size_t n = strlen(text);
    reserve(s, s->len + n);
    memcpy(s->data + s->len, text, n + 1);
    s->len += n;
}
static const char *text(const String *s) {
    return s->data ? s->data : "";
}
static void clear(String *s) {
    s->len = 0;
    if (s->data)
        s->data[0] = 0;
}
static void assign(String *s, const char *value) {
    clear(s);
    append(s, value);
}
static void dispose(String *s) {
    free(s->data);
    *s = (String){0};
}
static int box_index(Position p, int cell) {
    for (int i = 0; i < p.count; i++)
        if (p.boxes[i] == cell)
            return i;
    return -1;
}
static void sort_boxes(Position *p) {
    for (int i = 1; i < p->count; i++) {
        int b = p->boxes[i], j = i;
        while (j && p->boxes[j - 1] > b) {
            p->boxes[j] = p->boxes[j - 1];
            j--;
        }
        p->boxes[j] = b;
    }
}
static Position move_box(Position p, int source, int target) {
    p.boxes[box_index(p, source)] = target;
    sort_boxes(&p);
    return p;
}
static int same(Position a, Position b) {
    return a.player == b.player && a.count == b.count &&
           memcmp(a.boxes, b.boxes, (size_t)a.count * sizeof(int)) == 0;
}
static int inside(const Level *l, int c) {
    return c >= 0 && c < l->size && l->interior[c];
}
static int neighbor(const Level *l, int c, int d) {
    int r = c / l->w, col = c % l->w;
    static const int dr[] = {-1, 1, 0, 0}, dc[] = {0, 0, -1, 1};
    r += dr[d];
    col += dc[d];
    return r < 0 || r >= l->h || col < 0 || col >= l->w ? -1 : r * l->w + col;
}
static void reach(const Level *l, Position p, unsigned char seen[100]) {
    int queue[100], head = 0, tail = 0;
    memset(seen, 0, 100);
    seen[p.player] = 1;
    queue[tail++] = p.player;
    while (head < tail) {
        int c = queue[head++];
        for (int d = 0; d < 4; d++) {
            int n = neighbor(l, c, d);
            if (inside(l, n) && !seen[n] && box_index(p, n) < 0) {
                seen[n] = 1;
                queue[tail++] = n;
            }
        }
    }
}
static int representative(const Level *l, Position p) {
    unsigned char seen[100];
    reach(l, p, seen);
    for (int i = 0; i < l->size; i++)
        if (seen[i])
            return i;
    return -1;
}
static String walk(const Level *l, Position p, int target) {
    int previous[100], arrived[100], queue[100], head = 0, tail = 0;
    for (int i = 0; i < 100; i++)
        previous[i] = -1;
    queue[tail++] = p.player;
    previous[p.player] = p.player;
    while (head < tail) {
        int c = queue[head++];
        for (int d = 0; d < 4; d++) {
            int n = neighbor(l, c, d);
            if (inside(l, n) && box_index(p, n) < 0 && previous[n] < 0) {
                previous[n] = c;
                arrived[n] = d;
                queue[tail++] = n;
            }
        }
    }
    String path = {0};
    for (int c = target; c != p.player; c = previous[c])
        append_char(&path, directions[arrived[c]]);
    for (size_t i = 0; i < path.len / 2; i++) {
        char c = path.data[i];
        path.data[i] = path.data[path.len - 1 - i];
        path.data[path.len - 1 - i] = c;
    }
    return path;
}
static void analyze(Level *l) {
    l->goal_count = 0;
    for (int c = 0; c < l->size; c++)
        if (l->goal[c])
            l->goals[l->goal_count++] = c;
    for (int g = 0; g < l->goal_count; g++) {
        int queue[100], head = 0, tail = 0;
        for (int c = 0; c < 100; c++)
            l->distance[g][c] = -1;
        int start = l->goals[g];
        l->distance[g][start] = 0;
        queue[tail++] = start;
        while (head < tail) {
            int c = queue[head++];
            for (int d = 0; d < 4; d++) {
                int b = c - l->offsets[d], stand = b - l->offsets[d];
                if (inside(l, b) && inside(l, stand) && l->distance[g][b] < 0) {
                    l->distance[g][b] = l->distance[g][c] + 1;
                    queue[tail++] = b;
                }
            }
        }
    }
    for (int c = 0; c < l->size; c++) {
        l->dead[c] = l->interior[c];
        for (int g = 0; g < l->goal_count; g++)
            if (l->distance[g][c] >= 0)
                l->dead[c] = 0;
    }
}
static void offsets(Level *l) {
    l->offsets[0] = -l->w;
    l->offsets[1] = l->w;
    l->offsets[2] = -1;
    l->offsets[3] = 1;
}
static void load(Game *game, char rows[10][101], int h, int w) {
    Level l = {0};
    Position p = {.player = -1};
    int players = 0;
    l.h = h;
    l.w = w;
    l.size = h * w;
    offsets(&l);
    for (int c = 0; c < l.size; c++) {
        char ch = rows[c / w][c % w];
        l.walls[c] = ch == '#';
        l.goal[c] = strchr(".*+", ch) != NULL;
        if (ch == '@' || ch == '+') {
            p.player = c;
            players++;
        }
        if (ch == '$' || ch == '*')
            p.boxes[p.count++] = c;
        if (l.goal[c])
            l.goals[l.goal_count++] = c;
    }
    if (players == 1) {
        int queue[100], head = 0, tail = 0;
        queue[tail++] = p.player;
        l.interior[p.player] = 1;
        while (head < tail) {
            int c = queue[head++];
            for (int d = 0; d < 4; d++) {
                int n = neighbor(&l, c, d);
                if (n >= 0 && !l.walls[n] && !l.interior[n]) {
                    l.interior[n] = 1;
                    queue[tail++] = n;
                }
            }
        }
    }
    if (players != 1)
        snprintf(l.reason, sizeof l.reason, "players %d", players);
    else if (!p.count)
        strcpy(l.reason, "no boxes");
    else if (p.count != l.goal_count)
        snprintf(l.reason, sizeof l.reason, "boxes %d goals %d", p.count, l.goal_count);
    else {
        for (int c = 0; c < l.size; c++)
            if (l.interior[c] && (c / w == 0 || c / w == h - 1 || c % w == 0 || c % w == w - 1)) {
                snprintf(l.reason, sizeof l.reason, "open %d %d", c / w + 1, c % w + 1);
                break;
            }
        if (!l.reason[0])
            for (int c = 0; c < l.size; c++)
                if ((l.goal[c] || box_index(p, c) >= 0) && !l.interior[c]) {
                    snprintf(l.reason, sizeof l.reason, "outside %d %d", c / w + 1, c % w + 1);
                    break;
                }
    }
    if (!l.reason[0])
        analyze(&l);
    for (int i = 0; i < game->snapshot_count; i++)
        dispose(&game->snapshots[i].history);
    game->snapshot_count = 0;
    game->has_solution = 0;
    clear(&game->solution);
    clear(&game->history);
    clear(&game->redo);
    game->level = l;
    game->initial = game->current = p;
}
static int decode(const char *word, const char *allowed, String *out) {
    for (size_t i = 0; word[i];) {
        int count = 0, digits = 0;
        size_t start = i;
        while (word[i] >= '0' && word[i] <= '9') {
            if (digits < 3)
                count = count * 10 + word[i] - '0';
            digits++;
            i++;
        }
        if (digits > 2 || (digits && word[start] == '0') || !word[i] || !strchr(allowed, word[i]))
            return 0;
        if (!digits)
            count = 1;
        for (int j = 0; j < count; j++)
            append_char(out, word[i]);
        i++;
    }
    return 1;
}
static int number_word(const char *s) {
    size_t n = strlen(s);
    if (n < 1 || n > 6 || (n > 1 && s[0] == '0'))
        return 0;
    for (size_t i = 0; i < n; i++)
        if (s[i] < '0' || s[i] > '9')
            return 0;
    return 1;
}
static int pushes(const char *s) {
    int n = 0;
    for (; *s; s++)
        n += *s >= 'A' && *s <= 'Z';
    return n;
}
static int goals_on(const Level *l, Position p) {
    int n = 0;
    for (int i = 0; i < p.count; i++)
        n += l->goal[p.boxes[i]];
    return n;
}
static void progress(const Level *l, Position p) {
    int n = goals_on(l, p);
    printf("goals %d/%d%s", n, p.count, n == p.count ? " solved" : "");
}
static int step(const Level *l, Position *p, char direction, char *letter) {
    int d = (int)(strchr(directions, tolower((unsigned char)direction)) - directions),
        off = l->offsets[d];
    int t = p->player + off;
    if (l->walls[t])
        return 1;
    *letter = directions[d];
    if (box_index(*p, t) >= 0) {
        int beyond = t + off;
        if (l->walls[beyond] || box_index(*p, beyond) >= 0)
            return 2;
        *p = move_box(*p, t, beyond);
        *letter = (char)toupper((unsigned char)*letter);
    }
    p->player = t;
    return 0;
}
static int execute(Game *g, const char *sequence, String *letters, int commit) {
    Position p = g->current;
    int failure = 0;
    for (size_t i = 0; sequence[i]; i++) {
        char letter;
        failure = step(&g->level, &p, sequence[i], &letter);
        if (failure)
            break;
        append_char(letters, letter);
    }
    if (commit) {
        g->current = p;
        append(&g->history, text(letters));
        if (letters->len)
            clear(&g->redo);
    }
    return failure;
}
static int frozen(const Level *, Position, int, unsigned);
static int axis_blocked(const Level *l, Position p, int b, int a, int z, unsigned assumed) {
    int ia = box_index(p, a), iz = box_index(p, z);
    if (l->walls[a] || l->walls[z] || (ia >= 0 && (assumed & (1u << ia))) ||
        (iz >= 0 && (assumed & (1u << iz))))
        return 1;
    if (l->dead[a] && l->dead[z])
        return 1;
    unsigned more = assumed | (1u << box_index(p, b));
    return (ia >= 0 && frozen(l, p, a, more)) || (iz >= 0 && frozen(l, p, z, more));
}
static int frozen(const Level *l, Position p, int b, unsigned assumed) {
    return axis_blocked(l, p, b, b - 1, b + 1, assumed) &&
           axis_blocked(l, p, b, b - l->w, b + l->w, assumed);
}
static int has_frozen(const Level *l, Position p) {
    for (int i = 0; i < p.count; i++)
        if (!l->goal[p.boxes[i]] && frozen(l, p, p.boxes[i], 0))
            return 1;
    return 0;
}
static int pushable(const Level *l, Position p, int b, int d, const unsigned char *seen) {
    int t = b + l->offsets[d], stand = b - l->offsets[d];
    return inside(l, stand) && seen[stand] && inside(l, t) && box_index(p, t) < 0;
}

typedef struct {
    Position p;
    size_t parent;
    int box, direction;
} Node;
typedef struct {
    uint64_t *keys;
    size_t cap, count;
} Known;
typedef struct {
    int outcome;
    size_t expanded, states;
    String notation;
} Search;
static uint64_t state_key(Position p) {
    uint64_t key = (uint64_t)p.player + 1;
    for (int i = 0; i < p.count; i++)
        key = (key << 7) | (uint64_t)(p.boxes[i] + 1);
    return key;
}
static size_t hash_key(uint64_t key) {
    key ^= key >> 30;
    key *= UINT64_C(0xbf58476d1ce4e5b9);
    key ^= key >> 27;
    key *= UINT64_C(0x94d049bb133111eb);
    return (size_t)(key ^ (key >> 31));
}
static int remember(Known *k, uint64_t key) {
    if (!k->cap || (k->count + 1) * 10 > k->cap * 7) {
        size_t old_cap = k->cap;
        uint64_t *old = k->keys;
        k->cap = k->cap ? k->cap * 2 : 1024;
        k->keys = calloc(k->cap, sizeof(uint64_t));
        if (!k->keys)
            exit(EXIT_FAILURE);
        for (size_t i = 0; i < old_cap; i++)
            if (old[i]) {
                size_t slot = hash_key(old[i]) & (k->cap - 1);
                while (k->keys[slot])
                    slot = (slot + 1) & (k->cap - 1);
                k->keys[slot] = old[i];
            }
        free(old);
    }
    size_t slot = hash_key(key) & (k->cap - 1);
    while (k->keys[slot]) {
        if (k->keys[slot] == key)
            return 0;
        slot = (slot + 1) & (k->cap - 1);
    }
    k->keys[slot] = key;
    k->count++;
    return 1;
}
static Search search(const Level *l, Position start, int source, int target, int prune,
                     size_t limit) {
    size_t capacity = 1024, count = 1, expanded = 0, result_index = 0;
    Node *nodes = allocate(capacity * sizeof(Node));
    Known known = {0};
    Search result = {0};
    Position first = start;
    first.player = representative(l, first);
    nodes[0] = (Node){first, SIZE_MAX, 0, 0};
    remember(&known, state_key(first));
    while (expanded < count) {
        if (limit && expanded == limit) {
            result.outcome = 2;
            break;
        }
        size_t parent = expanded++;
        Node node = nodes[parent];
        unsigned char seen[100];
        reach(l, node.p, seen);
        for (int i = 0; i < node.p.count; i++) {
            int b = node.p.boxes[i], fixed = 0;
            if (source >= 0)
                for (int j = 0; j < start.count; j++)
                    if (start.boxes[j] != source && start.boxes[j] == b)
                        fixed = 1;
            if (fixed)
                continue;
            for (int d = 0; d < 4; d++) {
                if (!pushable(l, node.p, b, d, seen))
                    continue;
                int destination = b + l->offsets[d];
                Position next = move_box(node.p, b, destination);
                if (prune && (l->dead[destination] || has_frozen(l, next)))
                    continue;
                next.player = b;
                next.player = representative(l, next);
                if (!remember(&known, state_key(next)))
                    continue;
                if (count == capacity) {
                    capacity *= 2;
                    Node *grown = realloc(nodes, capacity * sizeof(Node));
                    if (!grown)
                        exit(EXIT_FAILURE);
                    nodes = grown;
                }
                nodes[count] = (Node){next, parent, b, d};
                result_index = count++;
                if ((source >= 0 && destination == target) ||
                    (source < 0 && goals_on(l, next) == next.count)) {
                    result.outcome = 1;
                    goto finished;
                }
            }
        }
    }
finished:
    result.expanded = expanded;
    result.states = count;
    if (result.outcome == 1) {
        size_t length = 0;
        for (size_t n = result_index; nodes[n].parent != SIZE_MAX; n = nodes[n].parent)
            length++;
        size_t *chain = allocate(length * sizeof(size_t)), n = result_index;
        for (size_t i = length; i > 0; i--) {
            chain[i - 1] = n;
            n = nodes[n].parent;
        }
        Position p = start;
        for (size_t i = 0; i < length; i++) {
            Node push = nodes[chain[i]];
            int off = l->offsets[push.direction];
            String path = walk(l, p, push.box - off);
            append(&result.notation, text(&path));
            dispose(&path);
            append_char(&result.notation, (char)toupper((unsigned char)directions[push.direction]));
            p = move_box(p, push.box, push.box + off);
            p.player = push.box;
        }
        free(chain);
    }
    free(nodes);
    free(known.keys);
    return result;
}
static char symbol(const Level *l, Position p, int c) {
    if (l->walls[c])
        return '#';
    if (p.player == c)
        return l->goal[c] ? '+' : '@';
    if (box_index(p, c) >= 0)
        return l->goal[c] ? '*' : '$';
    return l->goal[c] ? '.' : '-';
}
static void cell(const Level *l, int c) {
    printf("%d %d", c / l->w + 1, c % l->w + 1);
}
static int count_flags(const unsigned char *a, int n) {
    int count = 0;
    for (int i = 0; i < n; i++)
        count += a[i] != 0;
    return count;
}
static const char *turns[] = {"ROT90", "ROT180", "ROT270", "FLIPH", "FLIPV"};
static const char *direction_maps[] = {"rlud", "durl", "lrdu", "udrl", "dulr"};
static int transform_index(const char *s) {
    for (int i = 0; i < 5; i++)
        if (!strcmp(s, turns[i]))
            return i;
    return -1;
}
static int map_cell(const Level *l, int c, int t) {
    int r = c / l->w, col = c % l->w;
    switch (t) {
    case 0:
        return col * l->h + l->h - 1 - r;
    case 1:
        return (l->h - 1 - r) * l->w + l->w - 1 - col;
    case 2:
        return (l->w - 1 - col) * l->h + r;
    case 3:
        return r * l->w + l->w - 1 - col;
    default:
        return (l->h - 1 - r) * l->w + col;
    }
}
static Position map_position(const Level *l, Position p, int t) {
    p.player = map_cell(l, p.player, t);
    for (int i = 0; i < p.count; i++)
        p.boxes[i] = map_cell(l, p.boxes[i], t);
    sort_boxes(&p);
    return p;
}
static void turn_letters(String *s, int t) {
    for (size_t i = 0; i < s->len; i++) {
        char old = s->data[i],
             ch = direction_maps[t][strchr(directions, tolower((unsigned char)old)) - directions];
        s->data[i] = isupper((unsigned char)old) ? (char)toupper((unsigned char)ch) : ch;
    }
}
static void transform(Game *g, int t) {
    Level old = g->level, next = {0};
    next.h = (t == 0 || t == 2) ? old.w : old.h;
    next.w = (t == 0 || t == 2) ? old.h : old.w;
    next.size = old.size;
    offsets(&next);
    for (int c = 0; c < old.size; c++) {
        int n = map_cell(&old, c, t);
        next.walls[n] = old.walls[c];
        next.goal[n] = old.goal[c];
        next.interior[n] = old.interior[c];
    }
    analyze(&next);
    g->level = next;
    g->initial = map_position(&old, g->initial, t);
    g->current = map_position(&old, g->current, t);
    turn_letters(&g->history, t);
    turn_letters(&g->redo, t);
    for (int i = 0; i < g->snapshot_count; i++) {
        g->snapshots[i].position = map_position(&old, g->snapshots[i].position, t);
        turn_letters(&g->snapshots[i].history, t);
    }
    if (g->has_solution) {
        g->solution_position = map_position(&old, g->solution_position, t);
        turn_letters(&g->solution, t);
    }
    printf("transformed %dx%d\n", next.h, next.w);
}
static void bound_visit(const Level *l, Position p, int depth, unsigned used, int total,
                        int order[4], int best[4], int *minimum) {
    if (depth == p.count) {
        if (*minimum < 0 || total < *minimum) {
            *minimum = total;
            memcpy(best, order, (size_t)p.count * sizeof(int));
        }
        return;
    }
    for (int g = 0; g < l->goal_count; g++)
        if (!(used & (1u << g)) && l->distance[g][p.boxes[depth]] >= 0) {
            order[depth] = g;
            bound_visit(l, p, depth + 1, used | (1u << g), total + l->distance[g][p.boxes[depth]],
                        order, best, minimum);
        }
}
static void error(const char *message) {
    printf("error: %s\n", message);
}
static void counted(const char *label, const String *s) {
    printf("%s %zu", label, s->len);
    if (s->len)
        printf(" %s", text(s));
    putchar('\n');
}
enum Command {
    CMD_IMPORT,
    CMD_VALID,
    CMD_INFO,
    CMD_SHOW,
    CMD_EXPORT,
    CMD_MOVE,
    CMD_PUSH,
    CMD_BRING,
    CMD_PATH,
    CMD_UNDO,
    CMD_REDO,
    CMD_RESET,
    CMD_STATUS,
    CMD_HISTORY,
    CMD_BOXES,
    CMD_REACH,
    CMD_DEADSQUARES,
    CMD_DEADLOCK,
    CMD_BOUND,
    CMD_SAVE,
    CMD_RESTORE,
    CMD_CHECK,
    CMD_SOLVE,
    CMD_HINT,
    CMD_PLAY,
    CMD_TRANSFORM
};
static const char *commands[] = {
    "IMPORT", "VALID", "INFO",    "SHOW",   "EXPORT",  "MOVE",  "PUSH",  "BRING",       "PATH",
    "UNDO",   "REDO",  "RESET",   "STATUS", "HISTORY", "BOXES", "REACH", "DEADSQUARES", "DEADLOCK",
    "BOUND",  "SAVE",  "RESTORE", "CHECK",  "SOLVE",   "HINT",  "PLAY",  "TRANSFORM"};
static const char *formats[] = {"x", "", "", "", "", "s", "nnd", "nnnn", "nn", "n", "n", "", "",
                                "",  "", "", "", "", "",  "a",   "a",    "s",  "n", "n", "", "t"};
static int valid_argument(char kind, const char *s) {
    if (kind == 'n')
        return number_word(s);
    if (kind == 'd')
        return strlen(s) == 1 && strchr(directions, s[0]);
    if (kind == 't')
        return transform_index(s) >= 0;
    if (kind == 'a') {
        size_t n = strlen(s);
        if (n < 1 || n > 8)
            return 0;
        for (size_t i = 0; i < n; i++)
            if (s[i] < 'a' || s[i] > 'z')
                return 0;
    }
    if (kind == 's') {
        String out = {0};
        int ok = decode(s, "udlrUDLR", &out);
        dispose(&out);
        return ok;
    }
    return 1;
}
static void command(Game *g, char **words, int count) {
    int cmd = -1;
    for (int i = 0; i < 26; i++)
        if (!strcmp(words[0], commands[i]))
            cmd = i;
    if (cmd < 0) {
        printf("error: unknown command %s\n", words[0]);
        return;
    }
    if ((size_t)(count - 1) != strlen(formats[cmd])) {
        error("bad arguments");
        return;
    }
    for (int i = 1; i < count; i++)
        if (!valid_argument(formats[cmd][i - 1], words[i])) {
            error("bad arguments");
            return;
        }
    Level *l = &g->level;
    if (cmd == CMD_IMPORT) {
        char rows[10][101];
        int h = 0, w = -1;
        const char *start = words[1];
        while (1) {
            const char *end = strchr(start, '|');
            size_t n = end ? (size_t)(end - start) : strlen(start);
            char part[101];
            memcpy(part, start, n);
            part[n] = 0;
            String row = {0};
            if (h == 10 || !decode(part, symbols, &row) || row.len < 1 || row.len > 10 ||
                (w >= 0 && (size_t)w != row.len)) {
                dispose(&row);
                error("bad level");
                return;
            }
            w = (int)row.len;
            strcpy(rows[h++], text(&row));
            dispose(&row);
            if (!end)
                break;
            start = end + 1;
        }
        load(g, rows, h, w);
        printf("loaded %dx%d\n", h, w);
        return;
    }
    if (cmd == CMD_VALID) {
        if (l->reason[0])
            printf("invalid %s\n", l->reason);
        else
            puts("valid");
        return;
    }
    if (l->reason[0]) {
        error("invalid level");
        return;
    }
    int cell_count = cmd == CMD_BRING ? 2 : (cmd == CMD_PUSH || cmd == CMD_PATH ? 1 : 0);
    for (int i = 0; i < cell_count; i++) {
        int r = atoi(words[1 + 2 * i]), c = atoi(words[2 + 2 * i]);
        if (r < 1 || r > l->h || c < 1 || c > l->w) {
            error("bad value");
            return;
        }
    }
    if ((cmd == CMD_UNDO || cmd == CMD_REDO) && atoi(words[1]) < 1) {
        error("bad value");
        return;
    }
    if ((cmd == CMD_SOLVE || cmd == CMD_HINT) && (atoi(words[1]) < 1 || atoi(words[1]) > 100000)) {
        error("bad value");
        return;
    }
    int b = cell_count ? (atoi(words[1]) - 1) * l->w + atoi(words[2]) - 1 : 0;
    switch (cmd) {
    case CMD_INFO:
        printf("size %dx%d walls %d cells %d boxes %d dead %d\n", l->h, l->w,
               count_flags(l->walls, l->size), count_flags(l->interior, l->size), g->current.count,
               count_flags(l->dead, l->size));
        break;
    case CMD_SHOW:
        for (int c = 0; c < l->size; c++) {
            putchar(symbol(l, g->current, c));
            if (c % l->w == l->w - 1)
                putchar('\n');
        }
        break;
    case CMD_EXPORT:
        fputs("level ", stdout);
        for (int r = 0; r < l->h; r++) {
            if (r)
                putchar('|');
            for (int c = 0; c < l->w;) {
                char ch = symbol(l, g->current, r * l->w + c);
                int n = 1;
                while (c + n < l->w && symbol(l, g->current, r * l->w + c + n) == ch)
                    n++;
                if (n > 1)
                    printf("%d", n);
                putchar(ch);
                c += n;
            }
        }
        putchar('\n');
        break;
    case CMD_MOVE:
    case CMD_CHECK: {
        String sequence = {0}, letters = {0};
        decode(words[1], "udlrUDLR", &sequence);
        int failure = execute(g, text(&sequence), &letters, cmd == CMD_MOVE);
        if (cmd == CMD_MOVE) {
            if (letters.len)
                printf("moved %s\n", text(&letters));
            if (failure)
                printf("error: step %zu %s\n", letters.len + 1, failure == 1 ? "wall" : "blocked");
        } else if (failure)
            printf("check fail step %zu %s\n", letters.len + 1, failure == 1 ? "wall" : "blocked");
        else {
            Position p = g->current;
            for (size_t i = 0; i < sequence.len; i++) {
                char letter;
                step(l, &p, sequence.data[i], &letter);
            }
            printf("check ok moves %zu pushes %d ", letters.len, pushes(text(&letters)));
            progress(l, p);
            putchar('\n');
        }
        dispose(&sequence);
        dispose(&letters);
        break;
    }
    case CMD_PUSH: {
        int d = (int)(strchr(directions, words[3][0]) - directions), off = l->offsets[d];
        unsigned char seen[100];
        if (box_index(g->current, b) < 0) {
            error("no box");
            break;
        }
        if (!inside(l, b + off) || box_index(g->current, b + off) >= 0) {
            error("blocked");
            break;
        }
        reach(l, g->current, seen);
        if (!inside(l, b - off) || !seen[b - off]) {
            error("unreachable");
            break;
        }
        String path = walk(l, g->current, b - off), letters = {0};
        append_char(&path, directions[d]);
        execute(g, text(&path), &letters, 1);
        printf("pushed %s\n", text(&letters));
        dispose(&path);
        dispose(&letters);
        break;
    }
    case CMD_BRING: {
        int target = (atoi(words[3]) - 1) * l->w + atoi(words[4]) - 1;
        if (box_index(g->current, b) < 0) {
            error("no box");
            break;
        }
        if (b == target) {
            puts("brought 0");
            break;
        }
        Search s = search(l, g->current, b, target, 0, 0);
        if (s.outcome != 1)
            error("no route");
        else {
            String letters = {0};
            execute(g, text(&s.notation), &letters, 1);
            printf("brought %d %s\n", pushes(text(&s.notation)), text(&s.notation));
            dispose(&letters);
        }
        dispose(&s.notation);
        break;
    }
    case CMD_PATH: {
        unsigned char seen[100];
        reach(l, g->current, seen);
        if (!seen[b]) {
            error("unreachable");
            break;
        }
        String path = walk(l, g->current, b), letters = {0};
        execute(g, text(&path), &letters, 1);
        counted("path", &letters);
        dispose(&path);
        dispose(&letters);
        break;
    }
    case CMD_UNDO:
    case CMD_REDO: {
        String *from = cmd == CMD_UNDO ? &g->history : &g->redo;
        if (!from->len) {
            error(cmd == CMD_UNDO ? "nothing to undo" : "nothing to redo");
            break;
        }
        size_t k = (size_t)atoi(words[1]);
        if (k > from->len)
            k = from->len;
        for (size_t i = 0; i < k; i++) {
            char ch = from->data[--from->len];
            from->data[from->len] = 0;
            if (cmd == CMD_UNDO) {
                char dir = (char)tolower((unsigned char)ch);
                int off = l->offsets[strchr(directions, dir) - directions];
                if (isupper((unsigned char)ch))
                    g->current = move_box(g->current, g->current.player + off, g->current.player);
                g->current.player -= off;
                append_char(&g->redo, dir);
            } else {
                char letter;
                step(l, &g->current, ch, &letter);
                append_char(&g->history, letter);
            }
        }
        printf("%s %zu\n", cmd == CMD_UNDO ? "undone" : "redone", k);
        break;
    }
    case CMD_RESET:
        g->current = g->initial;
        clear(&g->history);
        clear(&g->redo);
        puts("reset");
        break;
    case CMD_STATUS:
        printf("moves %zu pushes %d ", g->history.len, pushes(text(&g->history)));
        progress(l, g->current);
        putchar('\n');
        break;
    case CMD_HISTORY:
        counted("history", &g->history);
        break;
    case CMD_BOXES: {
        unsigned char seen[100];
        reach(l, g->current, seen);
        printf("boxes %d\n", g->current.count);
        for (int i = 0; i < g->current.count; i++) {
            int box = g->current.boxes[i], best = -1;
            char possible[5];
            int n = 0;
            for (int j = 0; j < l->goal_count; j++)
                if (l->distance[j][box] >= 0 && (best < 0 || l->distance[j][box] < best))
                    best = l->distance[j][box];
            for (int d = 0; d < 4; d++)
                if (pushable(l, g->current, box, d, seen))
                    possible[n++] = directions[d];
            possible[n] = 0;
            fputs("box ", stdout);
            cell(l, box);
            if (best < 0)
                fputs(" dead", stdout);
            else
                printf(" %d", best);
            printf(" %s\n", n ? possible : "-");
        }
        break;
    }
    case CMD_REACH: {
        unsigned char seen[100];
        reach(l, g->current, seen);
        printf("reach %d first ", count_flags(seen, l->size));
        for (int c = 0; c < l->size; c++)
            if (seen[c]) {
                cell(l, c);
                break;
            }
        putchar('\n');
        break;
    }
    case CMD_DEADSQUARES:
        printf("dead %d\n", count_flags(l->dead, l->size));
        for (int c = 0; c < l->size; c++) {
            putchar(l->walls[c] ? '#' : l->goal[c] ? '.' : l->dead[c] ? 'x' : '-');
            if (c % l->w == l->w - 1)
                putchar('\n');
        }
        break;
    case CMD_DEADLOCK: {
        int found = -1;
        const char *why = "dead";
        for (int i = 0; i < g->current.count; i++)
            if (l->dead[g->current.boxes[i]]) {
                found = g->current.boxes[i];
                break;
            }
        if (found < 0) {
            why = "frozen";
            for (int i = 0; i < g->current.count; i++)
                if (!l->goal[g->current.boxes[i]] &&
                    frozen(l, g->current, g->current.boxes[i], 0)) {
                    found = g->current.boxes[i];
                    break;
                }
        }
        if (found < 0)
            puts("no deadlock");
        else {
            printf("deadlock %s ", why);
            cell(l, found);
            putchar('\n');
        }
        break;
    }
    case CMD_BOUND: {
        int order[4], best[4], minimum = -1;
        bound_visit(l, g->current, 0, 0, 0, order, best, &minimum);
        if (minimum < 0) {
            puts("bound none");
            break;
        }
        printf("bound %d\n", minimum);
        for (int i = 0; i < g->current.count; i++) {
            int box = g->current.boxes[i];
            fputs("box ", stdout);
            cell(l, box);
            fputs(" goal ", stdout);
            cell(l, l->goals[best[i]]);
            printf(" pushes %d\n", l->distance[best[i]][box]);
        }
        break;
    }
    case CMD_SAVE:
    case CMD_RESTORE: {
        int index = -1;
        for (int i = 0; i < g->snapshot_count; i++)
            if (!strcmp(g->snapshots[i].name, words[1]))
                index = i;
        if (cmd == CMD_SAVE) {
            if (index < 0) {
                index = g->snapshot_count++;
                strcpy(g->snapshots[index].name, words[1]);
            }
            g->snapshots[index].position = g->current;
            assign(&g->snapshots[index].history, text(&g->history));
            printf("saved %s moves %zu\n", words[1], g->history.len);
        } else if (index < 0)
            printf("error: no snapshot %s\n", words[1]);
        else {
            g->current = g->snapshots[index].position;
            assign(&g->history, text(&g->snapshots[index].history));
            clear(&g->redo);
            printf("restored %s moves %zu\n", words[1], g->history.len);
        }
        break;
    }
    case CMD_SOLVE:
    case CMD_HINT: {
        if (cmd == CMD_SOLVE) {
            g->has_solution = 0;
            clear(&g->solution);
        }
        if (goals_on(l, g->current) == g->current.count) {
            puts("already solved");
            break;
        }
        Search s = search(l, g->current, -1, -1, 1, (size_t)atoi(words[1]));
        if (s.outcome != 1)
            printf("%s expanded %zu states %zu\n", s.outcome == 2 ? "limit" : "no solution",
                   s.expanded, s.states);
        else if (cmd == CMD_SOLVE) {
            printf("solution pushes %d moves %zu expanded %zu states %zu\n%s\n",
                   pushes(text(&s.notation)), s.notation.len, s.expanded, s.states,
                   text(&s.notation));
            assign(&g->solution, text(&s.notation));
            g->solution_position = g->current;
            g->has_solution = 1;
        } else {
            size_t i = 0;
            while (!isupper((unsigned char)s.notation.data[i]))
                i++;
            s.notation.data[i + 1] = 0;
            String letters = {0};
            execute(g, text(&s.notation), &letters, 1);
            printf("hint %s\n", text(&s.notation));
            dispose(&letters);
        }
        dispose(&s.notation);
        break;
    }
    case CMD_PLAY:
        if (!g->has_solution || !same(g->current, g->solution_position))
            error("no solution");
        else {
            String letters = {0};
            execute(g, text(&g->solution), &letters, 1);
            printf("played pushes %d moves %zu\n", pushes(text(&g->solution)), g->solution.len);
            dispose(&letters);
        }
        break;
    case CMD_TRANSFORM:
        transform(g, transform_index(words[1]));
        break;
    }
}
static int read_line(String *line) {
    clear(line);
    int ch;
    while ((ch = getchar()) != EOF && ch != '\n')
        append_char(line, (char)ch);
    if (line->len && line->data[line->len - 1] == '\r')
        line->data[--line->len] = 0;
    return ch != EOF || line->len > 0;
}
static void read_row(char row[101]) {
    String line = {0};
    read_line(&line);
    strcpy(row, text(&line));
    dispose(&line);
}
int main(void) {
    String line = {0};
    char rows[10][101];
    int h, w;
    if (!read_line(&line) || sscanf(text(&line), "%d %d", &h, &w) != 2) {
        dispose(&line);
        return 0;
    }
    for (int i = 0; i < h; i++)
        read_row(rows[i]);
    Game *g = calloc(1, sizeof(Game));
    if (!g)
        return EXIT_FAILURE;
    load(g, rows, h, w);
    read_line(&line);
    int count = atoi(text(&line));
    for (int n = 0; n < count; n++) {
        if (!read_line(&line))
            break;
        char **words = allocate((line.len + 1) * sizeof(char *));
        int word_count = 0;
        for (char *word = strtok(line.data, " "); word; word = strtok(NULL, " "))
            words[word_count++] = word;
        if (!strcmp(words[0], "LOAD")) {
            h = atoi(words[1]);
            w = atoi(words[2]);
            int bad = 0;
            for (int i = 0; i < h; i++) {
                read_row(rows[i]);
                if (!bad && (strlen(rows[i]) != (size_t)w || strspn(rows[i], symbols) != (size_t)w))
                    bad = i + 1;
            }
            if (bad)
                printf("error: bad row %d\n", bad);
            else {
                load(g, rows, h, w);
                printf("loaded %dx%d\n", h, w);
            }
        } else
            command(g, words, word_count);
        free(words);
    }
    for (int i = 0; i < g->snapshot_count; i++)
        dispose(&g->snapshots[i].history);
    dispose(&g->history);
    dispose(&g->redo);
    dispose(&g->solution);
    dispose(&line);
    free(g);
    return 0;
}
