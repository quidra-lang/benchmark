#include <limits.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAX_RECTANGLES 40
#define MAX_COORDINATES (2 * MAX_RECTANGLES)
#define MAX_CELLS (MAX_COORDINATES - 1)
#define MAX_PAIRS (MAX_RECTANGLES * (MAX_RECTANGLES - 1) / 2)

typedef struct {
    int x1, y1, x2, y2;
} Box;
typedef struct {
    char name[9], layer[9];
    Box box;
} Rectangle;
typedef struct {
    int count;
    Rectangle rectangles[MAX_RECTANGLES];
} State;
typedef struct {
    State state;
    char *command;
} Saved;
typedef struct {
    int kind;
    char inner[9], outer[9];
    int value;
} Rule;
typedef struct {
    int count;
    Rectangle *items[MAX_RECTANGLES];
} Rectangles;
typedef struct {
    Box common;
    int ox, oy, gap, kind;
    const char *direction;
} Relation;
typedef struct {
    Rectangle *a, *b;
    Relation relation;
} Pair;
typedef struct {
    int nx, ny, xs[MAX_COORDINATES], ys[MAX_COORDINATES];
    int counts[MAX_CELLS][MAX_CELLS];
} Grid;
typedef struct {
    long long area;
    Box box;
    int anchor_x, anchor_y;
} Hole;
typedef struct {
    int count, capacity;
    Box *items;
} Boxes;
static State state;
static Saved *history;
static int history_count, history_capacity;
static Rule rules[20];
static int rule_count;
static jmp_buf command_error;
static const char *rule_kinds[] = {"enclose", "spacing", "width"};

static void fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("error: ", stdout);
    vprintf(format, args);
    putchar('\n');
    va_end(args);
    longjmp(command_error, 1);
}

static int minimum(int a, int b) {
    return a < b ? a : b;
}

static int maximum(int a, int b) {
    return a > b ? a : b;
}

static char *copy(const char *text) {
    char *result = malloc(strlen(text) + 1);
    if (!result) exit(EXIT_FAILURE);
    strcpy(result, text);
    return result;
}

static char *read_line(void) {
    size_t count = 0, capacity = 128;
    char *line = malloc(capacity);
    int ch;
    if (!line) exit(EXIT_FAILURE);
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            char *next = realloc(line, capacity);
            if (!next) exit(EXIT_FAILURE);
            line = next;
        }
        line[count++] = (char)ch;
    }
    line[count] = '\0';
    return line;
}

static int width(Box box) {
    return box.x2 - box.x1;
}

static int height(Box box) {
    return box.y2 - box.y1;
}

static long long area(Box box) {
    return (long long)width(box) * height(box);
}

static void print_box(Box box) {
    printf("(%d,%d)-(%d,%d)", box.x1, box.y1, box.x2, box.y2);
}

static bool contains(Box a, Box b) {
    return a.x1 <= b.x1 && a.y1 <= b.y1 && a.x2 >= b.x2 && a.y2 >= b.y2;
}

static Box shift(Box box, int dx, int dy) {
    return (Box){box.x1 + dx, box.y1 + dy, box.x2 + dx, box.y2 + dy};
}

static void bounds(Box box) {
    if (box.x1 < -10000 || box.y1 < -10000 || box.x2 > 10000 || box.y2 > 10000 || box.x1 > 10000 || box.y1 > 10000 || box.x2 < -10000 || box.y2 < -10000) fail("out of bounds");
}

static int rectangle_compare(const void *a, const void *b) {
    return strcmp(((const Rectangle *)a)->name, ((const Rectangle *)b)->name);
}

static int pointer_compare(const void *a, const void *b) {
    return strcmp((*(Rectangle *const *)a)->name, (*(Rectangle *const *)b)->name);
}

static int integer_compare(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}

static int get(const char *name) {
    for (int i = 0; i < state.count; i++) if (!strcmp(state.rectangles[i].name, name)) return i;
    fail("unknown rectangle %s", name);
    return -1;
}

static bool exists(const char *name) {
    for (int i = 0; i < state.count; i++) if (!strcmp(state.rectangles[i].name, name)) return true;
    return false;
}

static void save(const char *line) {
    if (history_count == history_capacity) {
        history_capacity = history_capacity ? history_capacity * 2 : 16;
        Saved *next = realloc(history, (size_t)history_capacity * sizeof *next);
        if (!next) exit(EXIT_FAILURE);
        history = next;
    }
    history[history_count++] = (Saved){state, copy(line)};
}

static void add(Rectangle rectangle) {
    state.rectangles[state.count++] = rectangle;
    qsort(state.rectangles, (size_t)state.count, sizeof *state.rectangles, rectangle_compare);
}

static Rectangles layer(const char *name, bool required) {
    Rectangles result = {0};
    for (int i = 0; i < state.count; i++) if (!strcmp(state.rectangles[i].layer, name)) result.items[result.count++] = &state.rectangles[i];
    if (required && !result.count) fail("no rectangles on %s", name);
    return result;
}

static void names(const Rectangles *rectangles) {
    if (!rectangles->count) printf("none");
    for (int i = 0; i < rectangles->count; i++) printf("%s%s", i ? " " : "", rectangles->items[i]->name);
}

static Relation relation(const Rectangle *a, const Rectangle *b) {
    Box x = a->box, y = b->box;
    Relation r = {0};
    r.common = (Box){maximum(x.x1, y.x1), maximum(x.y1, y.y1), minimum(x.x2, y.x2), minimum(x.y2, y.y2)};
    r.ox = width(r.common);
    r.oy = height(r.common);
    r.gap = maximum(0, maximum(-r.ox, -r.oy));
    r.kind = r.ox < 0 || r.oy < 0 ? 3 : r.ox > 0 && r.oy > 0 ? 0 : r.ox == 0 && r.oy == 0 ? 2 : 1;
    r.direction = r.kind == 2 ? "corner" : r.ox < 0 && r.oy < 0 ? "diagonal" : r.ox < 0 ? "x" : "y";
    return r;
}

static int margin(const Rectangle *outer, const Rectangle *inner) {
    return minimum(minimum(inner->box.x1 - outer->box.x1, inner->box.y1 - outer->box.y1), minimum(outer->box.x2 - inner->box.x2, outer->box.y2 - inner->box.y2));
}

static Grid make_grid(const Rectangles *rectangles) {
    Grid grid = {0};
    for (int i = 0; i < rectangles->count; i++) {
        Box b = rectangles->items[i]->box;
        grid.xs[grid.nx++] = b.x1;
        grid.xs[grid.nx++] = b.x2;
        grid.ys[grid.ny++] = b.y1;
        grid.ys[grid.ny++] = b.y2;
    }
    qsort(grid.xs, (size_t)grid.nx, sizeof *grid.xs, integer_compare);
    qsort(grid.ys, (size_t)grid.ny, sizeof *grid.ys, integer_compare);
    int n = 0;
    for (int i = 0; i < grid.nx; i++) if (!n || grid.xs[i] != grid.xs[n - 1]) grid.xs[n++] = grid.xs[i];
    grid.nx = n;
    n = 0;
    for (int i = 0; i < grid.ny; i++) if (!n || grid.ys[i] != grid.ys[n - 1]) grid.ys[n++] = grid.ys[i];
    grid.ny = n;
    for (int r = 0; r < rectangles->count; r++) {
        Box b = rectangles->items[r]->box;
        for (int j = 0; j + 1 < grid.ny; j++) if (grid.ys[j] >= b.y1 && grid.ys[j + 1] <= b.y2) for (int i = 0; i + 1 < grid.nx; i++) if (grid.xs[i] >= b.x1 && grid.xs[i + 1] <= b.x2) grid.counts[j][i]++;
    }
    return grid;
}

static Box grid_bounds(const Grid *grid) {
    return (Box){grid->xs[0], grid->ys[0], grid->xs[grid->nx - 1], grid->ys[grid->ny - 1]};
}

static long long grid_area(const Grid *grid, int threshold) {
    long long result = 0;
    for (int j = 0; j + 1 < grid->ny; j++) for (int i = 0; i + 1 < grid->nx; i++) if (grid->counts[j][i] >= threshold) result += (long long)(grid->xs[i + 1] - grid->xs[i]) * (grid->ys[j + 1] - grid->ys[j]);
    return result;
}

static long long clipped(const Grid *grid, Box box) {
    long long result = 0;
    for (int j = 0; j + 1 < grid->ny; j++) for (int i = 0; i + 1 < grid->nx; i++) if (grid->counts[j][i] > 0) result += (long long)maximum(0, minimum(grid->xs[i + 1], box.x2) - maximum(grid->xs[i], box.x1)) * maximum(0, minimum(grid->ys[j + 1], box.y2) - maximum(grid->ys[j], box.y1));
    return result;
}

static long long perimeter(const Grid *grid) {
    long long result = 0;
    for (int j = 0; j + 1 < grid->ny; j++) for (int i = 0; i + 1 < grid->nx; i++) if (grid->counts[j][i] > 0) {
        if (!i || !grid->counts[j][i - 1]) result += grid->ys[j + 1] - grid->ys[j];
        if (i + 2 == grid->nx || !grid->counts[j][i + 1]) result += grid->ys[j + 1] - grid->ys[j];
        if (!j || !grid->counts[j - 1][i]) result += grid->xs[i + 1] - grid->xs[i];
        if (j + 2 == grid->ny || !grid->counts[j + 1][i]) result += grid->xs[i + 1] - grid->xs[i];
    }
    return result;
}

static bool empty_rectangle(const Grid *grid, Box *best) {
    bool found = false;
    for (int left = 0; left + 1 < grid->nx; left++) {
        bool blocked[MAX_CELLS] = {false};
        for (int right = left + 1; right < grid->nx; right++) {
            for (int j = 0; j + 1 < grid->ny; j++) blocked[j] |= grid->counts[j][right - 1] > 0;
            int bottom = 0;
            while (bottom + 1 < grid->ny) {
                if (blocked[bottom]) {
                    bottom++;
                    continue;
                }
                int top = bottom + 1;
                while (top + 1 < grid->ny && !blocked[top]) top++;
                Box candidate = {grid->xs[left], grid->ys[bottom], grid->xs[right], grid->ys[top]};
                if (!found || area(candidate) > area(*best) || (area(candidate) == area(*best) && (candidate.x1 < best->x1 || (candidate.x1 == best->x1 && (candidate.y1 < best->y1 || (candidate.y1 == best->y1 && width(candidate) < width(*best))))))) {
                    *best = candidate;
                    found = true;
                }
                bottom = top;
            }
        }
    }
    return found;
}

static void add_box(Boxes *boxes, Box box) {
    if (boxes->count == boxes->capacity) {
        boxes->capacity = boxes->capacity ? boxes->capacity * 2 : 16;
        Box *next = realloc(boxes->items, (size_t)boxes->capacity * sizeof *next);
        if (!next) exit(EXIT_FAILURE);
        boxes->items = next;
    }
    boxes->items[boxes->count++] = box;
}

static int box_compare(const void *a, const void *b) {
    const Box *x = a, *y = b;
    return x->y1 != y->y1 ? x->y1 - y->y1 : x->x1 - y->x1;
}

static Boxes pieces(const Grid *grid) {
    Boxes result = {0};
    Box active[MAX_RECTANGLES];
    int active_count = 0;
    for (int j = 0; j + 1 < grid->ny; j++) {
        Box next[MAX_RECTANGLES];
        int count = 0;
        bool used[MAX_RECTANGLES] = {false};
        int i = 0;
        while (i + 1 < grid->nx) {
            if (!grid->counts[j][i]) {
                i++;
                continue;
            }
            int right = i + 1;
            while (right + 1 < grid->nx && grid->counts[j][right]) right++;
            int bottom = grid->ys[j];
            for (int k = 0; k < active_count; k++) if (active[k].x1 == grid->xs[i] && active[k].x2 == grid->xs[right]) {
                bottom = active[k].y1;
                used[k] = true;
                break;
            }
            next[count++] = (Box){grid->xs[i], bottom, grid->xs[right], grid->ys[j + 1]};
            i = right;
        }
        for (int k = 0; k < active_count; k++) if (!used[k]) add_box(&result, active[k]);
        memcpy(active, next, (size_t)count * sizeof *active);
        active_count = count;
    }
    for (int k = 0; k < active_count; k++) add_box(&result, active[k]);
    if (result.count > 1) qsort(result.items, (size_t)result.count, sizeof *result.items, box_compare);
    return result;
}

static int hole_compare(const void *a, const void *b) {
    const Hole *x = a, *y = b;
    return x->anchor_y != y->anchor_y ? x->anchor_y - y->anchor_y : x->anchor_x - y->anchor_x;
}

static void print_holes(const Grid *grid, const char *layer_name) {
    bool seen[MAX_CELLS][MAX_CELLS] = {
        {false}
    };
    int queue[MAX_CELLS * MAX_CELLS];
    Hole *holes = NULL;
    int count = 0, capacity = 0;
    int dx[] = {-1, 1, 0, 0}, dy[] = {0, 0, -1, 1};
    for (int j = 0; j + 1 < grid->ny; j++) for (int i = 0; i + 1 < grid->nx; i++) if (!grid->counts[j][i] && !seen[j][i]) {
        Hole hole = {
            0, {grid->xs[i], grid->ys[j], grid->xs[i + 1], grid->ys[j + 1]}, grid->xs[i], grid->ys[j]
        };
        bool boundary = false;
        int head = 0, tail = 0;
        queue[tail++] = j * MAX_CELLS + i;
        seen[j][i] = true;
        while (head < tail) {
            int cell = queue[head++], x = cell % MAX_CELLS, y = cell / MAX_CELLS;
            boundary |= !x || !y || x + 2 == grid->nx || y + 2 == grid->ny;
            hole.area += (long long)(grid->xs[x + 1] - grid->xs[x]) * (grid->ys[y + 1] - grid->ys[y]);
            hole.box.x1 = minimum(hole.box.x1, grid->xs[x]);
            hole.box.y1 = minimum(hole.box.y1, grid->ys[y]);
            hole.box.x2 = maximum(hole.box.x2, grid->xs[x + 1]);
            hole.box.y2 = maximum(hole.box.y2, grid->ys[y + 1]);
            if (grid->ys[y] < hole.anchor_y || (grid->ys[y] == hole.anchor_y && grid->xs[x] < hole.anchor_x)) {
                hole.anchor_x = grid->xs[x];
                hole.anchor_y = grid->ys[y];
            }
            for (int d = 0; d < 4; d++) {
                int xx = x + dx[d], yy = y + dy[d];
                if (xx >= 0 && xx + 1 < grid->nx && yy >= 0 && yy + 1 < grid->ny && !grid->counts[yy][xx] && !seen[yy][xx]) {
                    seen[yy][xx] = true;
                    queue[tail++] = yy * MAX_CELLS + xx;
                }
            }
        }
        if (!boundary) {
            if (count == capacity) {
                capacity = capacity ? capacity * 2 : 8;
                Hole *next = realloc(holes, (size_t)capacity * sizeof *next);
                if (!next) exit(EXIT_FAILURE);
                holes = next;
            }
            holes[count++] = hole;
        }
    }
    if (count > 1) qsort(holes, (size_t)count, sizeof *holes, hole_compare);
    printf("holes %s: %d\n", layer_name, count);
    for (int i = 0; i < count; i++) {
        printf("hole %d: area %lld, bbox ", i + 1, holes[i].area);
        print_box(holes[i].box);
        putchar('\n');
    }
    free(holes);
}

static int nets(const Rectangles *rectangles, Rectangles result[MAX_RECTANGLES]) {
    bool seen[MAX_RECTANGLES] = {false};
    int count = 0;
    for (int start = 0; start < rectangles->count; start++) if (!seen[start]) {
        Rectangles group = {0};
        int queue[MAX_RECTANGLES], head = 0, tail = 0;
        queue[tail++] = start;
        seen[start] = true;
        while (head < tail) {
            int i = queue[head++];
            group.items[group.count++] = rectangles->items[i];
            for (int j = 0; j < rectangles->count; j++) if (!seen[j] && relation(rectangles->items[i], rectangles->items[j]).kind <= 1) {
                seen[j] = true;
                queue[tail++] = j;
            }
        }
        qsort(group.items, (size_t)group.count, sizeof *group.items, pointer_compare);
        result[count++] = group;
    }
    return count;
}

static int spacing_compare(const void *a, const void *b) {
    const Pair *x = a, *y = b;
    if (x->relation.gap != y->relation.gap) return x->relation.gap - y->relation.gap;
    int c = strcmp(x->a->name, y->a->name);
    return c ? c : strcmp(x->b->name, y->b->name);
}

static int spacing(const Rectangles *rectangles, int space, Pair result[MAX_PAIRS]) {
    int count = 0;
    for (int i = 0; i < rectangles->count; i++) for (int j = i + 1; j < rectangles->count; j++) {
        Rectangle *a = rectangles->items[i], *b = rectangles->items[j];
        Relation r = relation(a, b);
        if (r.kind == 2 || (r.kind == 3 && r.gap < space)) result[count++] = (Pair){a, b, r};
    }
    if (count > 1) qsort(result, (size_t)count, sizeof *result, spacing_compare);
    return count;
}

static void print_spacing(const Pair *pair) {
    printf("%s %s gap %d %s\n", pair->a->name, pair->b->name, pair->relation.gap, pair->relation.direction);
}

static int overlap_compare(const void *a, const void *b) {
    const Pair *x = a, *y = b;
    int c = strcmp(x->a->layer, y->a->layer);
    if (c) return c;
    c = strcmp(x->a->name, y->a->name);
    return c ? c : strcmp(x->b->name, y->b->name);
}

static void print_info(const Rectangle *rectangle) {
    printf("%s %s ", rectangle->name, rectangle->layer);
    print_box(rectangle->box);
    printf(" %dx%d", width(rectangle->box), height(rectangle->box));
}

static void density(long long value, long long total) {
    long long scaled = 10000LL * value / total;
    printf("%lld.%02lld", scaled / 100, scaled % 100);
}

static int rule_compare(const void *a, const void *b) {
    const Rule *x = a, *y = b;
    if (x->kind != y->kind) return x->kind - y->kind;
    int c = strcmp(x->inner, y->inner);
    return c ? c : strcmp(x->outer, y->outer);
}

static void check(void) {
    if (!rule_count) fail("no rules");
    int total = 0;
    for (int i = 0; i < rule_count; i++) {
        Rule *rule = &rules[i];
        Rectangles list = layer(rule->inner, false);
        Pair violations[MAX_PAIRS];
        int count = 0, best[MAX_RECTANGLES], widths[MAX_RECTANGLES];
        bool marked[MAX_RECTANGLES] = {false};
        Rectangles outer = layer(rule->outer, false);
        if (rule->kind == 1) count = spacing(&list, rule->value, violations);
        else for (int j = 0; j < list.count; j++) {
            Rectangle *r = list.items[j];
            if (rule->kind == 2) {
                widths[j] = minimum(width(r->box), height(r->box));
                marked[j] = widths[j] < rule->value;
            } else {
                best[j] = INT_MIN;
                for (int k = 0; k < outer.count; k++) best[j] = maximum(best[j], margin(outer.items[k], r));
                marked[j] = !outer.count || best[j] < rule->value;
            }
            count += marked[j];
        }
        printf("%s %s", rule_kinds[rule->kind], rule->inner);
        if (rule->kind == 0) printf(" %s", rule->outer);
        printf(" %d: %d violations\n", rule->value, count);
        if (rule->kind == 1) for (int j = 0; j < count; j++) print_spacing(&violations[j]);
        else for (int j = 0; j < list.count; j++) if (marked[j]) {
            printf("%s %s ", list.items[j]->name, rule->kind == 2 ? "width" : "best margin");
            if (rule->kind == 2) printf("%d\n", widths[j]);
            else if (outer.count) printf("%d\n", best[j]);
            else puts("none");
        }
        total += count;
    }
    printf("check: %d violations in %d rules\n", total, rule_count);
}

static void command(const char *line, char *parsed) {
    char *a[8];
    int argc = 0;
    for (char *p = strtok(parsed, " "); p; p = strtok(NULL, " ")) a[argc++] = p;
    const char *c = a[0];
    if (!strcmp(c, "ADD")) {
        if (exists(a[1])) fail("duplicate rectangle %s", a[1]);
        Box b = {atoi(a[3]), atoi(a[4]), atoi(a[5]), atoi(a[6])};
        if (b.x1 >= b.x2 || b.y1 >= b.y2) fail("invalid rectangle");
        bounds(b);
        Rectangle r = {0};
        strcpy(r.name, a[1]);
        strcpy(r.layer, a[2]);
        r.box = b;
        save(line);
        add(r);
        printf("added %s %s ", r.name, r.layer);
        print_box(b);
        putchar('\n');
    } else if (!strcmp(c, "COPY") || !strcmp(c, "MOVE") || !strcmp(c, "RESIZE") || !strcmp(c, "SPLIT") || !strcmp(c, "LAYER") || !strcmp(c, "DELETE")) {
        int index = get(a[1]);
        Rectangle old = state.rectangles[index], changed = old, extra = old;
        bool add_extra = false;
        if (!strcmp(c, "COPY")) {
            if (exists(a[2])) fail("duplicate rectangle %s", a[2]);
            strcpy(extra.name, a[2]);
            extra.box = shift(old.box, atoi(a[3]), atoi(a[4]));
            bounds(extra.box);
            add_extra = true;
        } else if (!strcmp(c, "MOVE")) {
            changed.box = shift(old.box, atoi(a[2]), atoi(a[3]));
            bounds(changed.box);
        } else if (!strcmp(c, "RESIZE")) {
            int w = atoi(a[2]), h = atoi(a[3]);
            if (w <= 0 || h <= 0) fail("invalid size");
            changed.box.x2 = old.box.x1 + w;
            changed.box.y2 = old.box.y1 + h;
            bounds(changed.box);
        } else if (!strcmp(c, "SPLIT")) {
            if (exists(a[4])) fail("duplicate rectangle %s", a[4]);
            int pos = atoi(a[3]);
            bool x = !strcmp(a[2], "x");
            if (pos <= (x ? old.box.x1 : old.box.y1) || pos >= (x ? old.box.x2 : old.box.y2)) fail("cut outside %s", old.name);
            if (x) {
                changed.box.x2 = pos;
                extra.box.x1 = pos;
            } else {
                changed.box.y2 = pos;
                extra.box.y1 = pos;
            }
            strcpy(extra.name, a[4]);
            add_extra = true;
        } else if (!strcmp(c, "LAYER")) {
            if (!strcmp(old.layer, a[2])) fail("already on %s", old.layer);
            strcpy(changed.layer, a[2]);
        }
        save(line);
        if (!strcmp(c, "DELETE")) {
            memmove(state.rectangles + index, state.rectangles + index + 1, (size_t)(state.count - index - 1) * sizeof *state.rectangles);
            state.count--;
            printf("deleted %s\n", old.name);
        } else if (!strcmp(c, "COPY")) {
            add(extra);
            printf("copied %s to %s ", old.name, extra.name);
            print_box(extra.box);
            putchar('\n');
        } else {
            state.rectangles[index] = changed;
            if (add_extra) add(extra);
            if (!strcmp(c, "LAYER")) printf("layer %s %s -> %s\n", old.name, old.layer, changed.layer);
            else if (!strcmp(c, "SPLIT")) {
                printf("split %s at %s=%s: %s ", old.name, a[2], a[3], old.name);
                print_box(changed.box);
                printf(", %s ", extra.name);
                print_box(extra.box);
                putchar('\n');
            } else {
                printf("%s %s to ", !strcmp(c, "MOVE") ? "moved" : "resized", old.name);
                print_box(changed.box);
                putchar('\n');
            }
        }
    } else if (!strcmp(c, "UNDO")) {
        if (!history_count) fail("nothing to undo");
        Saved saved = history[--history_count];
        state = saved.state;
        printf("undo: %s\n", saved.command);
        free(saved.command);
    } else if (!strcmp(c, "LIST")) {
        printf("rectangles: %d\n", state.count);
        for (int i = 0; i < state.count; i++) {
            print_info(&state.rectangles[i]);
            putchar('\n');
        }
    } else if (!strcmp(c, "INFO")) {
        Rectangle *r = &state.rectangles[get(a[1])];
        print_info(r);
        printf(" area %lld\n", area(r->box));
        const char *labels[] = {"overlaps", "touches", "corners", "encloses", "enclosed by"};
        for (int k = 0; k < 5; k++) {
            Rectangles list = {0};
            for (int i = 0; i < state.count; i++) {
                Rectangle *other = &state.rectangles[i];
                if (other == r) continue;
                Relation rel = relation(r, other);
                if (k < 3 ? !strcmp(r->layer, other->layer) && rel.kind == k : k == 3 ? contains(r->box, other->box) : contains(other->box, r->box)) list.items[list.count++] = other;
            }
            printf("%s: ", labels[k]);
            names(&list);
            putchar('\n');
        }
    } else if (!strcmp(c, "LAYERS")) {
        char layers[MAX_RECTANGLES][9];
        int count = 0;
        for (int i = 0; i < state.count; i++) {
            bool found = false;
            for (int j = 0; j < count; j++) if (!strcmp(layers[j], state.rectangles[i].layer)) found = true;
            if (!found) strcpy(layers[count++], state.rectangles[i].layer);
        }
        for (int i = 1; i < count; i++) {
            char name[9];
            strcpy(name, layers[i]);
            int j = i;
            while (j > 0 && strcmp(layers[j - 1], name) > 0) {
                strcpy(layers[j], layers[j - 1]);
                j--;
            }
            strcpy(layers[j], name);
        }
        printf("layers: %d\n", count);
        for (int i = 0; i < count; i++) {
            Rectangles list = layer(layers[i], true), groups[MAX_RECTANGLES];
            Grid grid = make_grid(&list);
            int k = nets(&list, groups);
            printf("%s: %d rectangles, area %lld, nets %d\n", layers[i], list.count, grid_area(&grid, 1), k);
        }
    } else if (!strcmp(c, "OVERLAPS")) {
        if (argc == 2) layer(a[1], true);
        Pair pairs[MAX_PAIRS];
        int count = 0;
        for (int i = 0; i < state.count; i++) for (int j = i + 1; j < state.count; j++) {
            Rectangle *x = &state.rectangles[i], *y = &state.rectangles[j];
            if (strcmp(x->layer, y->layer) || (argc == 2 && strcmp(x->layer, a[1]))) continue;
            Relation r = relation(x, y);
            if (r.kind == 0) pairs[count++] = (Pair){x, y, r};
        }
        if (count > 1) qsort(pairs, (size_t)count, sizeof *pairs, overlap_compare);
        printf("overlaps %s: %d\n", argc == 1 ? "all layers" : a[1], count);
        for (int i = 0; i < count; i++) {
            if (argc == 1) printf("%s ", pairs[i].a->layer);
            printf("%s %s ", pairs[i].a->name, pairs[i].b->name);
            print_box(pairs[i].relation.common);
            printf(" area %lld\n", area(pairs[i].relation.common));
        }
    } else if (!strcmp(c, "INTERSECT") || !strcmp(c, "ADJACENT") || !strcmp(c, "ENCLOSE") || !strcmp(c, "PATH")) {
        int x_index = get(a[1]);
        int y_index = get(a[2]);
        if (x_index == y_index) fail("same rectangle %s", a[1]);
        Rectangle *x = &state.rectangles[x_index], *y = &state.rectangles[y_index];
        Relation r = relation(x, y);
        if (!strcmp(c, "PATH")) {
            if (strcmp(x->layer, y->layer)) fail("different layers");
            int previous[MAX_RECTANGLES], queue[MAX_RECTANGLES], head = 0, tail = 0;
            for (int i = 0; i < state.count; i++) previous[i] = -1;
            previous[x_index] = x_index;
            queue[tail++] = x_index;
            while (head < tail) {
                int at = queue[head++];
                for (int j = 0; j < state.count; j++) if (previous[j] < 0 && !strcmp(x->layer, state.rectangles[j].layer) && relation(&state.rectangles[at], &state.rectangles[j]).kind <= 1) {
                    previous[j] = at;
                    queue[tail++] = j;
                }
            }
            printf("path %s %s: ", x->name, y->name);
            if (previous[y_index] < 0) puts("none");
            else {
                int path[MAX_RECTANGLES], count = 0;
                for (int at = y_index;; at = previous[at]) {
                    path[count++] = at;
                    if (at == x_index) break;
                }
                for (int i = count - 1; i >= 0; i--) printf("%s%s", i == count - 1 ? "" : " -> ", state.rectangles[path[i]].name);
                printf(" (%d steps)\n", count - 1);
            }
        } else if (!strcmp(c, "ENCLOSE")) {
            int m = margin(x, y);
            printf("enclose %s %s: %s, margins left %d bottom %d right %d top %d", x->name, y->name, m >= 0 ? "yes" : "no", y->box.x1 - x->box.x1, y->box.y1 - x->box.y1, x->box.x2 - y->box.x2, x->box.y2 - y->box.y2);
            if (m >= 0) printf(", min %d", m);
            putchar('\n');
        } else if (!strcmp(c, "INTERSECT")) {
            printf("intersect %s %s: ", x->name, y->name);
            if (r.kind == 0) {
                print_box(r.common);
                printf(" area %lld\n", area(r.common));
            } else if (r.kind == 1) {
                fputs("segment ", stdout);
                print_box(r.common);
                printf(" length %d\n", r.ox + r.oy);
            } else if (r.kind == 2) printf("point (%d,%d)\n", r.common.x1, r.common.y1);
            else printf("none, gap %d\n", r.gap);
        } else {
            printf("adjacent %s %s: ", x->name, y->name);
            if (r.kind == 0) puts("overlapping");
            else if (r.kind == 1) {
                const char *direction = !r.ox ? x->box.x2 == r.common.x1 ? "west" : "east" : x->box.y2 == r.common.y1 ? "south" : "north";
                printf("%s is %s of %s, edge ", x->name, direction, y->name);
                print_box(r.common);
                printf(", length %d\n", r.ox + r.oy);
            } else if (r.kind == 2) printf("corner only at (%d,%d)\n", r.common.x1, r.common.y1);
            else puts("not adjacent");
        }
    } else if (!strcmp(c, "AT")) {
        int x = atoi(a[1]), y = atoi(a[2]);
        bool found = false;
        printf("at (%d,%d): ", x, y);
        for (int i = 0; i < state.count; i++) {
            Rectangle *r = &state.rectangles[i];
            Box b = r->box;
            if (x >= b.x1 && x <= b.x2 && y >= b.y1 && y <= b.y2) {
                bool xx = x == b.x1 || x == b.x2, yy = y == b.y1 || y == b.y2;
                printf("%s%s %s %s", found ? ", " : "", r->name, r->layer, xx && yy ? "corner" : xx || yy ? "edge" : "inside");
                found = true;
            }
        }
        if (!found) printf("none");
        putchar('\n');
    } else if (!strcmp(c, "NEAREST")) {
        Rectangle *r = &state.rectangles[get(a[1])], *best = NULL;
        int gap = INT_MAX;
        for (int i = 0; i < state.count; i++) {
            Rectangle *other = &state.rectangles[i];
            if (r != other && !strcmp(r->layer, other->layer)) {
                int g = relation(r, other).gap;
                if (g < gap) {
                    gap = g;
                    best = other;
                }
            }
        }
        printf("nearest %s: ", r->name);
        if (best) printf("%s gap %d\n", best->name, gap);
        else puts("none");
    } else if (!strcmp(c, "RULE")) {
        int kind = !strcmp(a[1], "ENCLOSE") ? 0 : !strcmp(a[1], "SPACING") ? 1 : 2;
        if (kind == 0 && !strcmp(a[2], a[3])) fail("same layer %s", a[2]);
        Rule rule = {0};
        rule.kind = kind;
        strcpy(rule.inner, a[2]);
        if (!kind) strcpy(rule.outer, a[3]);
        rule.value = atoi(a[kind ? 3 : 4]);
        int i = 0;
        while (i < rule_count && rule_compare(&rules[i], &rule)) i++;
        if (i == rule_count) rule_count++;
        rules[i] = rule;
        qsort(rules, (size_t)rule_count, sizeof *rules, rule_compare);
        printf("rule %s %s", rule_kinds[kind], rule.inner);
        if (!kind) printf(" %s", rule.outer);
        printf(" %d\n", rule.value);
    } else if (!strcmp(c, "CHECK")) check();
    else {
        const char *layer_name = !strcmp(c, "COVER") ? a[2] : a[1];
        Rectangles list = layer(layer_name, true);
        Grid grid = make_grid(&list);
        Box box = grid_bounds(&grid);
        if (!strcmp(c, "AREA")) printf("area %s: %lld\n", layer_name, grid_area(&grid, 1));
        else if (!strcmp(c, "COVER")) printf("cover %s >= %s: %lld\n", layer_name, a[1], grid_area(&grid, atoi(a[1])));
        else if (!strcmp(c, "PERIMETER")) printf("perimeter %s: %lld\n", layer_name, perimeter(&grid));
        else if (!strcmp(c, "NETS")) {
            Rectangles groups[MAX_RECTANGLES];
            int count = nets(&list, groups);
            printf("nets %s: %d\n", layer_name, count);
            for (int i = 0; i < count; i++) {
                Grid net_grid = make_grid(&groups[i]);
                printf("net %d: ", i + 1);
                names(&groups[i]);
                printf(" area %lld\n", grid_area(&net_grid, 1));
            }
        } else if (!strcmp(c, "DRC")) {
            Pair violations[MAX_PAIRS];
            int s = atoi(a[2]), count = spacing(&list, s, violations);
            printf("drc %s spacing %d: %d violations\n", layer_name, s, count);
            for (int i = 0; i < count; i++) print_spacing(&violations[i]);
        } else if (!strcmp(c, "BBOX")) {
            printf("bbox %s: ", layer_name);
            print_box(box);
            printf(" %dx%d, %d rectangles, density ", width(box), height(box), list.count);
            density(grid_area(&grid, 1), area(box));
            puts("%");
        } else if (!strcmp(c, "DENSITY")) {
            int w = atoi(a[2]), columns = (width(box) + w - 1) / w, rows = (height(box) + w - 1) / w;
            if (columns > 20 || rows > 20) fail("too many windows");
            long long values[20][20], low = LLONG_MAX, high = -1;
            int low_x = 0, low_y = 0, high_x = 0, high_y = 0;
            for (int j = 0; j < rows; j++) for (int i = 0; i < columns; i++) {
                values[j][i] = clipped(&grid, (Box){box.x1 + i * w, box.y1 + j * w, box.x1 + (i + 1) * w, box.y1 + (j + 1) * w});
                if (values[j][i] < low) {
                    low = values[j][i];
                    low_x = i;
                    low_y = j;
                }
                if (values[j][i] > high) {
                    high = values[j][i];
                    high_x = i;
                    high_y = j;
                }
            }
            printf("density %s window %d: %dx%d\n", layer_name, w, columns, rows);
            for (int j = rows - 1; j >= 0; j--) {
                for (int i = 0; i < columns; i++) printf("%s%lld", i ? " " : "", 100LL * values[j][i] / ((long long)w * w));
                putchar('\n');
            }
            fputs("min ", stdout);
            density(low, (long long)w * w);
            printf("%% at (%d,%d)\n", box.x1 + low_x * w, box.y1 + low_y * w);
            fputs("max ", stdout);
            density(high, (long long)w * w);
            printf("%% at (%d,%d)\n", box.x1 + high_x * w, box.y1 + high_y * w);
        } else if (!strcmp(c, "RENDER")) {
            Box window = {atoi(a[2]), atoi(a[3]), atoi(a[4]), atoi(a[5])};
            if (window.x1 >= window.x2 || window.y1 >= window.y2) fail("invalid window");
            if (width(window) > 60 || height(window) > 40) fail("window too large");
            printf("render %s ", layer_name);
            print_box(window);
            putchar('\n');
            for (int y = window.y2 - 1; y >= window.y1; y--) {
                for (int x = window.x1; x < window.x2; x++) {
                    int count = 0;
                    for (int i = 0; i < list.count; i++) {
                        Box b = list.items[i]->box;
                        if (x >= b.x1 && x < b.x2 && y >= b.y1 && y < b.y2) count++;
                    }
                    putchar(count == 0 ? '.' : count < 10 ? '0' + count : '*');
                }
                putchar('\n');
            }
        } else if (!strcmp(c, "EMPTY")) {
            Box empty;
            printf("empty %s: ", layer_name);
            if (empty_rectangle(&grid, &empty)) {
                print_box(empty);
                printf(" area %lld\n", area(empty));
            } else puts("none");
        } else if (!strcmp(c, "HOLES")) print_holes(&grid, layer_name);
        else if (!strcmp(c, "MERGE")) {
            Boxes result = pieces(&grid);
            printf("merge %s: %d pieces\n", layer_name, result.count);
            for (int i = 0; i < result.count; i++) {
                print_box(result.items[i]);
                putchar('\n');
            }
            free(result.items);
        }
    }
}

int main(void) {
    char *line = read_line();
    int count = atoi(line);
    free(line);
    for (int i = 0; i < count; i++) {
        line = read_line();
        char *parsed = copy(line);
        if (setjmp(command_error) == 0) command(line, parsed);
        free(parsed);
        free(line);
    }
    for (int i = 0; i < history_count; i++) free(history[i].command);
    free(history);
    return 0;
}
