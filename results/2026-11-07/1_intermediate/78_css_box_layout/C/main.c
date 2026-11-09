#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
enum {
    DISPLAY, POSITION, BOX_SIZING, WIDTH, HEIGHT, MIN_WIDTH, MIN_HEIGHT,
    MAX_WIDTH, MAX_HEIGHT, MT, MR, MB, ML, PT,
    PR, PB, PL, BT, BR, BB, BL,
    TOP, RIGHT, BOTTOM, LEFT, DIRECTION, WRAP, JUSTIFY,
    ALIGN_ITEMS, ALIGN_SELF, ROW_GAP, COLUMN_GAP, ORDER, GROW, SHRINK,
    BASIS, COLUMNS, ROWS, GRID_COLUMN, GRID_ROW, PROPERTY_COUNT, MARGIN = PROPERTY_COUNT,
    PADDING, BORDER, GAP
};
static const char *property_names[] = {
    "display", "position", "box-sizing", "width",
    "height", "min-width", "min-height", "max-width",
    "max-height", "margin-top", "margin-right", "margin-bottom",
    "margin-left", "padding-top", "padding-right", "padding-bottom",
    "padding-left", "border-top", "border-right", "border-bottom",
    "border-left", "top", "right", "bottom",
    "left", "flex-direction", "flex-wrap", "justify-content",
    "align-items", "align-self", "row-gap", "column-gap",
    "order", "flex-grow", "flex-shrink", "flex-basis",
    "grid-template-columns", "grid-template-rows", "grid-column", "grid-row",
    "margin", "padding", "border", "gap"
};
static const char *initial_values[] = {
    "block", "static", "content-box", "auto", "auto", "0", "0", "none",
    "none", "0", "0", "0", "0", "0", "0", "0",
    "0", "0", "0", "0", "0", "auto", "auto", "auto",
    "auto", "row", "nowrap", "start", "stretch", "auto", "0", "0",
    "0", "0", "1", "auto", "none", "none", "auto", "auto"
};

typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;

typedef struct {
    Allocation *head;
} Arena;

typedef struct {
    int count, capacity;
    char **items;
} Strings;

typedef struct Element Element;
struct Element {
    char *type, *id, *text;
    Strings classes, lines;
    const char *style[PROPERTY_COUNT];
    Element *parent, *containing, *children[60];
    int index, depth, child_count, cw, ch, rx, ry, x, y, intrinsic;
    bool displayed;
};

typedef struct {
    int property;
    char *value;
} Declaration;

typedef struct {
    Strings selectors;
    int count;
    Declaration declarations[80];
} Rule;

typedef struct {
    int count;
    Element *items[60];
} ElementList;

typedef struct {
    char kind;
    int value;
} Track;

typedef struct {
    Element *element;
    int row, column, rows, columns, aw, ax, width, contribution;
    bool placed;
} GridItem;

typedef struct {
    int count, columns, rows;
    GridItem items[60];
} Grid;

typedef struct {
    Element *element;
    int base, hypothetical, size, cross, outer;
    long long weight;
    bool frozen;
} FlexItem;

typedef struct {
    bool displayed;
    int x, y, width, height;
} Box;
static Arena permanent, work, layout_memory;
static Element elements[60];
static Rule rules[60];
static int element_count, rule_count, viewport_width, viewport_height;

static void *allocate(Arena *arena, size_t size) {
    void *pointer = calloc(1, size ? size : 1);
    Allocation *allocation = malloc(sizeof *allocation);
    if (!pointer || !allocation) exit(1);
    allocation->pointer = pointer;
    allocation->next = arena->head;
    arena->head = allocation;
    return pointer;
}

static void clear_arena(Arena *arena) {
    while (arena->head) {
        Allocation *next = arena->head->next;
        free(arena->head->pointer);
        free(arena->head);
        arena->head = next;
    }
}

static char *part(Arena *arena, const char *text, size_t length) {
    char *copy = allocate(arena, length + 1);
    memcpy(copy, text, length);
    return copy;
}

static char *copy(Arena *arena, const char *text) {
    return part(arena, text, strlen(text));
}

static void add_string(Arena *arena, Strings *strings, char *value) {
    if (strings->count == strings->capacity) {
        int capacity = strings->capacity ? strings->capacity * 2 : 8;
        char **items = allocate(arena, (size_t)capacity * sizeof *items);
        if (strings->count) memcpy(items, strings->items, (size_t)strings->count * sizeof *items);
        strings->items = items;
        strings->capacity = capacity;
    }
    strings->items[strings->count++] = value;
}

static Strings split(Arena *arena, const char *text, const char *delimiter) {
    Strings result = {0};
    size_t length = strlen(delimiter);
    const char *start = text, *next;
    while ((next = strstr(start, delimiter))) {
        add_string(arena, &result, part(arena, start, (size_t)(next - start)));
        start = next + length;
    }
    add_string(arena, &result, copy(arena, start));
    return result;
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = malloc(capacity);
    int ch;
    if (!line) exit(1);
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (length + 1 >= capacity) {
            capacity *= 2;
            char *grown = realloc(line, capacity);
            if (!grown) exit(1);
            line = grown;
        }
        line[length++] = (char)ch;
    }
    if (ch == EOF && length == 0) {
        free(line);
        return NULL;
    }
    line[length] = '\0';
    return line;
}

static bool equal(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

static bool one_of(const char *value, const char *choices) {
    size_t length = strlen(value);
    const char *start = choices;
    while (*start) {
        const char *end = strchr(start, ' ');
        size_t n = end ? (size_t)(end - start) : strlen(start);
        if (n == length && memcmp(start, value, n) == 0) return true;
        if (!end) break;
        start = end + 1;
    }
    return false;
}

static bool integer(const char *value) {
    size_t n = strlen(value);
    if (n < 1 || n > 3) return false;
    for (size_t i = 0; i < n; i++) if (value[i] < '0' || value[i] > '9') return false;
    return true;
}

static bool positive(const char *value) {
    return integer(value) && atoi(value) > 0;
}

static bool signed_integer(const char *value) {
    return integer(value) || (value[0] == '-' && integer(value + 1));
}

static bool percentage(const char *value) {
    size_t n = strlen(value);
    return n > 1 && value[n - 1] == '%' && integer(part(&work, value, n - 1));
}

static int minimum(int a, int b) {
    return a < b ? a : b;
}

static int maximum(int a, int b) {
    return a > b ? a : b;
}

static int property_index(const char *name) {
    for (int i = 0; i <= GAP; i++) if (equal(name, property_names[i])) return i;
    return -1;
}

static int parse_declaration(int property, const char *value, Declaration result[4]) {
    if (property < 0) return 0;
    Strings tokens = split(&work, value, " ");
    if (property >= MARGIN) {
        bool gap = property == GAP;
        if (tokens.count < 1 || tokens.count > (gap ? 2 : 4)) return 0;
        for (int i = 0; i < tokens.count; i++) if (!integer(tokens.items[i]) || (property == BORDER && !one_of(tokens.items[i], "0 1"))) return 0;
        if (gap) {
            result[0] = (Declaration){ROW_GAP, tokens.items[0]};
            result[1] = (Declaration){COLUMN_GAP, tokens.items[tokens.count - 1]};
            return 2;
        }
        int first = property == MARGIN ? MT : property == PADDING ? PT : BT;
        int indices[] = {0, tokens.count > 1 ? 1 : 0, tokens.count > 2 ? 2 : 0, tokens.count > 3 ? 3 : tokens.count > 1 ? 1 : 0};
        for (int i = 0; i < 4; i++) result[i] = (Declaration){first + i, tokens.items[indices[i]]};
        return 4;
    }
    bool valid = false;
    if (property == COLUMNS || property == ROWS) {
        valid = true;
        if (!equal(value, "none")) for (int i = 0; i < tokens.count; i++) {
            char *token = tokens.items[i];
            size_t n = strlen(token);
            if (!integer(token) && !equal(token, "auto") && !(n > 2 && equal(token + n - 2, "fr") && positive(part(&work, token, n - 2)))) valid = false;
        }
    } else if (property == GRID_COLUMN || property == GRID_ROW) {
        char **t = tokens.items;
        valid = (tokens.count == 1 && (equal(value, "auto") || positive(value)))
                || (tokens.count == 2 && equal(t[0], "span") && positive(t[1]))
                || (tokens.count == 3 && positive(t[0]) && equal(t[1], "/") && positive(t[2]) && atoi(t[0]) < atoi(t[2]))
                || (tokens.count == 4 && positive(t[0]) && equal(t[1], "/") && equal(t[2], "span") && positive(t[3]));
    } else {
        if (tokens.count != 1) return 0;
        switch (property) {
            case DISPLAY:
                valid = one_of(value, "block flex grid none");
                break;
            case POSITION:
                valid = one_of(value, "static relative absolute");
                break;
            case BOX_SIZING:
                valid = one_of(value, "content-box border-box");
                break;
            case WIDTH:
            case HEIGHT:
            case BASIS:
                valid = equal(value, "auto") || integer(value) || percentage(value);
                break;
            case MIN_WIDTH:
            case MIN_HEIGHT:
                valid = integer(value) || percentage(value);
                break;
            case MAX_WIDTH:
            case MAX_HEIGHT:
                valid = equal(value, "none") || integer(value) || percentage(value);
                break;
            case TOP:
            case RIGHT:
            case BOTTOM:
            case LEFT:
                valid = equal(value, "auto") || signed_integer(value);
                break;
            case ORDER:
                valid = signed_integer(value);
                break;
            case DIRECTION:
                valid = one_of(value, "row row-reverse column column-reverse");
                break;
            case WRAP:
                valid = one_of(value, "nowrap wrap");
                break;
            case JUSTIFY:
                valid = one_of(value, "start end center space-between space-around space-evenly");
                break;
            case ALIGN_ITEMS:
                valid = one_of(value, "stretch start end center");
                break;
            case ALIGN_SELF:
                valid = one_of(value, "auto stretch start end center");
                break;
            default:
                valid = property >= BT && property <= BL ? one_of(value, "0 1") : integer(value);
                break;
        }
    }
    if (!valid) return 0;
    result[0] = (Declaration){property, (char *)value};
    return 1;
}

static int number(Element *e, int property) {
    return atoi(e->style[property]);
}

static int hf(Element *e) {
    return number(e, PL) + number(e, PR) + number(e, BL) + number(e, BR);
}

static int vf(Element *e) {
    return number(e, PT) + number(e, PB) + number(e, BT) + number(e, BB);
}

static int hm(Element *e) {
    return number(e, ML) + number(e, MR);
}

static int vm(Element *e) {
    return number(e, MT) + number(e, MB);
}

static int bw(Element *e) {
    return e->cw + hf(e);
}

static int bh(Element *e) {
    return e->ch + vf(e);
}

static int cx(Element *e) {
    return e->x + number(e, BL) + number(e, PL);
}

static int cy(Element *e) {
    return e->y + number(e, BT) + number(e, PT);
}

static ElementList flow(Element *e, bool sorted) {
    ElementList result = {0};
    for (int i = 0; i < e->child_count; i++) {
        Element *child = e->children[i];
        if (child->displayed && !equal(child->style[POSITION], "absolute")) result.items[result.count++] = child;
    }
    if (sorted) for (int i = 1; i < result.count; i++) {
        Element *item = result.items[i];
        int j = i;
        while (j > 0 && number(result.items[j - 1], ORDER) > number(item, ORDER)) {
            result.items[j] = result.items[j - 1];
            j--;
        }
        result.items[j] = item;
    }
    return result;
}

static int resolve(Element *e, int property, int reference, bool horizontal) {
    const char *value = e->style[property];
    size_t n = strlen(value);
    if (equal(value, "auto") || equal(value, "none")) return -1;
    int length;
    if (value[n - 1] == '%') {
        if (reference < 0) return -1;
        length = (int)((long long)reference * atoi(value) / 100);
    } else length = atoi(value);
    return equal(e->style[BOX_SIZING], "border-box") ? maximum(0, length - (horizontal ? hf(e) : vf(e))) : length;
}

static int clamp(Element *e, int value, int reference, bool horizontal) {
    int low = resolve(e, horizontal ? MIN_WIDTH : MIN_HEIGHT, reference, horizontal), high = resolve(e, horizontal ? MAX_WIDTH : MAX_HEIGHT, reference, horizontal);
    if (high >= 0) value = minimum(value, high);
    return maximum(value, maximum(0, low));
}

static int *distribute(int total, const long long *weights, int count) {
    int *result = allocate(&layout_memory, (size_t)count * sizeof *result);
    long long sum = 0;
    for (int i = 0; i < count; i++) sum += weights[i];
    if (!sum) return result;
    int remaining = total;
    for (int i = 0; i < count; i++) {
        result[i] = (int)((long long)total * weights[i] / sum);
        remaining -= result[i];
    }
    for (int i = 0; i < count && remaining > 0; i++) if (weights[i] > 0) {
        result[i]++;
        remaining--;
    }
    return result;
}

static void placement(const char *value, int *start, int *span) {
    Strings tokens = split(&layout_memory, value, " ");
    char **t = tokens.items;
    if (equal(value, "auto")) {
        *start = 0;
        *span = 1;
    } else if (equal(t[0], "span")) {
        *start = 0;
        *span = atoi(t[1]);
    } else {
        *start = atoi(t[0]);
        *span = tokens.count == 1 ? 1 : tokens.count == 3 ? atoi(t[2]) - *start : atoi(t[3]);
    }
}

static Track *tracks(const char *value, bool columns, int *count) {
    if (equal(value, "none")) {
        *count = columns ? 1 : 0;
        Track *result = allocate(&layout_memory, sizeof *result);
        result[0] = (Track){'a', 0};
        return result;
    }
    Strings tokens = split(&layout_memory, value, " ");
    *count = tokens.count;
    Track *result = allocate(&layout_memory, (size_t)*count * sizeof *result);
    for (int i = 0; i < *count; i++) {
        const char *token = tokens.items[i];
        size_t n = strlen(token);
        result[i] = equal(token, "auto") ? (Track){'a', 0} : n > 2 && equal(token + n - 2, "fr") ? (Track){'f', atoi(token)} : (Track){'n', atoi(token)};
    }
    return result;
}

static bool overlaps(Grid *grid, GridItem *item, int row, int column) {
    for (int i = 0; i < grid->count; i++) {
        GridItem *other = &grid->items[i];
        if (other->placed && row < other->row + other->rows && other->row < row + item->rows && column < other->column + other->columns && other->column < column + item->columns) return true;
    }
    return false;
}

static Grid place_grid(Element *e) {
    Grid result = {0};
    ElementList children = flow(e, true);
    tracks(e->style[COLUMNS], true, &result.columns);
    tracks(e->style[ROWS], false, &result.rows);
    for (int i = 0; i < children.count; i++) {
        GridItem *item = &result.items[result.count++];
        item->element = children.items[i];
        placement(item->element->style[GRID_COLUMN], &item->column, &item->columns);
        placement(item->element->style[GRID_ROW], &item->row, &item->rows);
        result.columns = maximum(result.columns, item->column ? item->column + item->columns - 1 : item->columns);
    }
    for (int i = 0; i < result.count; i++) {
        GridItem *item = &result.items[i];
        if (item->row && item->column) item->placed = true;
    }
    int cr = 1, cc = 1;
    for (int i = 0; i < result.count; i++) {
        GridItem *item = &result.items[i];
        if (item->placed) continue;
        if (item->row) {
            int c = 1;
            while (c <= result.columns - item->columns + 1 && overlaps(&result, item, item->row, c)) c++;
            item->column = c <= result.columns - item->columns + 1 ? c : 1;
        } else if (item->column) {
            if (item->column < cc) cr++;
            int r = cr;
            while (overlaps(&result, item, r, item->column)) r++;
            item->row = r;
            cr = r;
            cc = item->column + item->columns;
        } else {
            int r = cr, c = cc;
            while (true) {
                if (c + item->columns - 1 > result.columns) {
                    r++;
                    c = 1;
                } else if (overlaps(&result, item, r, c)) c++;
                else break;
            }
            item->row = r;
            item->column = c;
            cr = r;
            cc = c + item->columns;
        }
        item->placed = true;
    }
    for (int i = 0; i < result.count; i++) result.rows = maximum(result.rows, result.items[i].row + result.items[i].rows - 1);
    return result;
}
static int contribution(Element *e);

static int *track_sizes(Element *e, Grid *grid, bool columns, int available, bool intrinsic) {
    int count = columns ? grid->columns : grid->rows, explicit_count;
    Track *explicit_tracks = tracks(e->style[columns ? COLUMNS : ROWS], columns, &explicit_count), *specs = allocate(&layout_memory, (size_t)count * sizeof *specs);
    for (int i = 0; i < count; i++) specs[i] = i < explicit_count ? explicit_tracks[i] : (Track){'a', 0};
    int *sizes = allocate(&layout_memory, (size_t)count * sizeof *sizes);
    for (int i = 0; i < count; i++) {
        if (specs[i].kind == 'n') sizes[i] = specs[i].value;
        else if (specs[i].kind == 'a' || available < 0) for (int j = 0; j < grid->count; j++) {
            GridItem *item = &grid->items[j];
            if ((columns ? item->column : item->row) == i + 1 && (columns ? item->columns : item->rows) == 1) sizes[i] = maximum(sizes[i], intrinsic ? contribution(item->element) : item->contribution);
        }
    }
    int gap = number(e, columns ? COLUMN_GAP : ROW_GAP), leftover = available - gap * maximum(0, count - 1);
    for (int i = 0; i < count; i++) leftover -= sizes[i];
    if (available >= 0 && leftover > 0) {
        bool fr = false;
        for (int i = 0; i < count; i++) if (specs[i].kind == 'f') fr = true;
        long long *weights = allocate(&layout_memory, (size_t)count * sizeof *weights);
        for (int i = 0; i < count; i++) if (fr ? specs[i].kind == 'f' : specs[i].kind == 'a') weights[i] = fr ? specs[i].value : 1;
        int *extra = distribute(leftover, weights, count);
        for (int i = 0; i < count; i++) sizes[i] += extra[i];
    }
    return sizes;
}

static int max_content(Element *e) {
    if (e->intrinsic >= 0) return e->intrinsic;
    int result = 0;
    if (e->text) result = (int)strlen(e->text);
    else if (equal(e->style[DISPLAY], "flex") && strncmp(e->style[DIRECTION], "row", 3) == 0) {
        ElementList children = flow(e, false);
        for (int i = 0; i < children.count; i++) result += contribution(children.items[i]);
        result += number(e, COLUMN_GAP) * maximum(0, children.count - 1);
    } else if (equal(e->style[DISPLAY], "grid")) {
        Grid grid = place_grid(e);
        int *sizes = track_sizes(e, &grid, true, -1, true);
        result = number(e, COLUMN_GAP) * (grid.columns - 1);
        for (int i = 0; i < grid.columns; i++) result += sizes[i];
    } else {
        ElementList children = flow(e, false);
        for (int i = 0; i < children.count; i++) result = maximum(result, contribution(children.items[i]));
    }
    e->intrinsic = result;
    return result;
}

static int contribution(Element *e) {
    int width = resolve(e, WIDTH, -1, true);
    return clamp(e, width < 0 ? max_content(e) : width, -1, true) + hf(e) + hm(e);
}

static const char *align(Element *parent, Element *child) {
    return equal(child->style[ALIGN_SELF], "auto") ? parent->style[ALIGN_ITEMS] : child->style[ALIGN_SELF];
}

static int offset(const char *alignment, int space) {
    return space <= 0 ? 0 : equal(alignment, "end") ? space : equal(alignment, "center") ? space / 2 : 0;
}

static void position(Element *parent, Element *child, int x, int y) {
    child->rx = number(parent, BL) + number(parent, PL) + x;
    child->ry = number(parent, BT) + number(parent, PT) + y;
}
static int layout(Element *e, int width_reference, int height_reference, int forced_width, int forced_height);

static int flex(Element *e, int k, int height_reference) {
    bool horizontal = strncmp(e->style[DIRECTION], "row", 3) == 0, reverse = strstr(e->style[DIRECTION], "reverse") != NULL;
    int reference = horizontal ? e->cw : k, gap = number(e, horizontal ? COLUMN_GAP : ROW_GAP);
    ElementList children = flow(e, true);
    FlexItem items[60] = {0};
    for (int i = 0; i < children.count; i++) {
        FlexItem *item = &items[i];
        Element *child = children.items[i];
        item->element = child;
        item->outer = horizontal ? hm(child) + hf(child) : vm(child) + vf(child);
        if (!horizontal) {
            int r = maximum(0, e->cw - hm(child) - hf(child)), width = resolve(child, WIDTH, e->cw, true);
            item->cross = clamp(child, width >= 0 ? width : equal(align(e, child), "stretch") ? r : minimum(max_content(child), r), e->cw, true);
        }
        item->base = resolve(child, BASIS, reference, horizontal);
        if (item->base < 0) item->base = resolve(child, horizontal ? WIDTH : HEIGHT, reference, horizontal);
        if (item->base < 0) item->base = horizontal ? max_content(child) : layout(child, e->cw, k, item->cross, -1);
        item->hypothetical = clamp(child, item->base, reference, horizontal);
    }
    int length = reference;
    if (length < 0) {
        length = gap * maximum(0, children.count - 1);
        for (int i = 0; i < children.count; i++) length += items[i].hypothetical + items[i].outer;
        length = clamp(e, length, height_reference, false);
    }
    int starts[60], ends[60], line_count = 0, occupied = 0;
    for (int i = 0; i < children.count; i++) {
        FlexItem *item = &items[i];
        if (line_count == 0 || (horizontal && equal(e->style[WRAP], "wrap") && occupied + gap + item->hypothetical + item->outer > length)) {
            starts[line_count] = i;
            ends[line_count] = i;
            line_count++;
            occupied = 0;
        }
        if (ends[line_count - 1] > starts[line_count - 1]) occupied += gap;
        occupied += item->hypothetical + item->outer;
        ends[line_count - 1] = i + 1;
    }
    int cross_start = 0;
    for (int line = 0; line < line_count; line++) {
        int start = starts[line], end = ends[line], count = end - start, total = gap * (count - 1);
        for (int i = start; i < end; i++) total += items[i].hypothetical + items[i].outer;
        bool grow = total < length;
        for (int i = start; i < end; i++) {
            FlexItem *item = &items[i];
            item->weight = grow ? number(item->element, GROW) : (long long)number(item->element, SHRINK) * item->base;
            item->size = item->hypothetical;
            item->frozen = item->weight == 0 || (grow ? item->base > item->hypothetical : item->base < item->hypothetical);
        }
        while (true) {
            int free_space = length - gap * (count - 1), remaining = 0;
            long long weights[60] = {0};
            for (int i = start; i < end; i++) {
                FlexItem *item = &items[i];
                free_space -= (item->frozen ? item->size : item->base) + item->outer;
                if (!item->frozen) {
                    weights[i - start] = item->weight;
                    remaining++;
                }
            }
            if (!remaining) break;
            int *shares = distribute(maximum(0, grow ? free_space : -free_space), weights, count), violations[60] = {0}, violation = 0;
            for (int i = start; i < end; i++) {
                FlexItem *item = &items[i];
                if (!item->frozen) {
                    int tentative = item->base + (grow ? shares[i - start] : -shares[i - start]);
                    item->size = clamp(item->element, tentative, reference, horizontal);
                    violations[i - start] = item->size - tentative;
                    violation += violations[i - start];
                }
            }
            for (int i = start; i < end; i++) if (violation == 0 || (violation > 0 && violations[i - start] > 0) || (violation < 0 && violations[i - start] < 0)) items[i].frozen = true;
        }
        int lc = horizontal ? 0 : e->cw;
        if (horizontal) {
            for (int i = start; i < end; i++) {
                FlexItem *item = &items[i];
                layout(item->element, e->cw, k, item->size, -1);
                item->cross = item->element->ch;
                lc = maximum(lc, item->cross + vf(item->element) + vm(item->element));
            }
            if (line_count == 1) lc = k >= 0 ? k : clamp(e, lc, height_reference, false);
        }
        int used = gap * (count - 1);
        for (int i = start; i < end; i++) used += items[i].size + items[i].outer;
        int space = length - used, *before = allocate(&layout_memory, (size_t)(count + 1) * sizeof *before);
        if (space > 0) {
            const char *justify = e->style[JUSTIFY];
            if (equal(justify, "end")) before[0] = space;
            else if (equal(justify, "center")) before[0] = space / 2;
            else if (strncmp(justify, "space-", 6) == 0) {
                long long weights[61];
                for (int i = 0; i <= count; i++) weights[i] = 1;
                if (equal(justify, "space-between")) weights[0] = weights[count] = 0;
                else if (equal(justify, "space-around")) for (int i = 1; i < count; i++) weights[i] = 2;
                before = distribute(space, weights, count + 1);
            }
        }
        int cursor = 0;
        for (int i = start; i < end; i++) {
            FlexItem *item = &items[i];
            Element *child = item->element;
            const char *alignment = align(e, child);
            if (horizontal) {
                if (equal(alignment, "stretch") && equal(child->style[HEIGHT], "auto")) {
                    item->cross = clamp(child, maximum(0, lc - vm(child) - vf(child)), k, false);
                    layout(child, e->cw, k, item->size, item->cross);
                } else layout(child, e->cw, k, item->size, -1);
            } else layout(child, e->cw, k, item->cross, item->size);
            int cross = cross_start + offset(alignment, lc - item->cross - (horizontal ? vf(child) + vm(child) : hf(child) + hm(child))) + number(child, horizontal ? MT : ML);
            cursor += before[i - start];
            int main = reverse ? length - cursor - number(child, horizontal ? MR : MB) - item->size - (horizontal ? hf(child) : vf(child)) : cursor + number(child, horizontal ? ML : MT);
            position(e, child, horizontal ? main : cross, horizontal ? cross : main);
            cursor += item->size + item->outer + gap;
        }
        cross_start += lc + number(e, ROW_GAP);
    }
    return horizontal ? line_count ? cross_start - number(e, ROW_GAP) : 0 : length;
}

static int prefix(const int *sizes, int count, int gap) {
    int result = count * gap;
    for (int i = 0; i < count; i++) result += sizes[i];
    return result;
}

static int area(const int *sizes, int start, int span, int gap) {
    int result = gap * (span - 1);
    for (int i = start - 1; i < start - 1 + span; i++) result += sizes[i];
    return result;
}

static int grid_layout(Element *e, int k) {
    Grid grid = place_grid(e);
    int cg = number(e, COLUMN_GAP), rg = number(e, ROW_GAP), *columns = track_sizes(e, &grid, true, e->cw, true);
    for (int i = 0; i < grid.count; i++) {
        GridItem *item = &grid.items[i];
        Element *child = item->element;
        item->aw = area(columns, item->column, item->columns, cg);
        item->ax = prefix(columns, item->column - 1, cg);
        int width = resolve(child, WIDTH, item->aw, true);
        item->width = clamp(child, width < 0 ? maximum(0, item->aw - hm(child) - hf(child)) : width, item->aw, true);
        layout(child, item->aw, -1, item->width, -1);
        item->contribution = bh(child) + vm(child);
    }
    int *rows = track_sizes(e, &grid, false, k, false);
    for (int i = 0; i < grid.count; i++) {
        GridItem *item = &grid.items[i];
        Element *child = item->element;
        int ah = area(rows, item->row, item->rows, rg), ay = prefix(rows, item->row - 1, rg);
        const char *alignment = align(e, child);
        int forced_height = equal(alignment, "stretch") && equal(child->style[HEIGHT], "auto") ? clamp(child, maximum(0, ah - vm(child) - vf(child)), ah, false) : -1;
        layout(child, item->aw, ah, item->width, forced_height);
        position(e, child, item->ax + number(child, ML), ay + offset(alignment, ah - bh(child) - vm(child)) + number(child, MT));
    }
    int result = rg * maximum(0, grid.rows - 1);
    for (int i = 0; i < grid.rows; i++) result += rows[i];
    return result;
}

static int layout(Element *e, int width_reference, int height_reference, int forced_width, int forced_height) {
    int width = resolve(e, WIDTH, width_reference, true);
    e->cw = forced_width >= 0 ? forced_width : clamp(e, width < 0 ? maximum(0, width_reference - hm(e) - hf(e)) : width, width_reference, true);
    if (forced_height < 0) {
        int height = resolve(e, HEIGHT, height_reference, false);
        if (height >= 0) forced_height = clamp(e, height, height_reference, false);
    }
    int a;
    if (e->text) {
        e->lines = (Strings){0};
        Strings words = split(&layout_memory, e->text, " ");
        char *current = words.items[0];
        for (int i = 1; i < words.count; i++) {
            char *word = words.items[i];
            size_t length = strlen(current), word_length = strlen(word);
            if (length + 1 + word_length <= (size_t)e->cw) {
                char *joined = allocate(&layout_memory, length + word_length + 2);
                memcpy(joined, current, length);
                joined[length] = ' ';
                memcpy(joined + length + 1, word, word_length + 1);
                current = joined;
            } else {
                add_string(&layout_memory, &e->lines, current);
                current = word;
            }
        }
        add_string(&layout_memory, &e->lines, current);
        a = e->lines.count;
    } else if (equal(e->style[DISPLAY], "flex")) a = flex(e, forced_height, height_reference);
    else if (equal(e->style[DISPLAY], "grid")) a = grid_layout(e, forced_height);
    else {
        a = 0;
        int previous_bottom = 0;
        ElementList children = flow(e, false);
        for (int i = 0; i < children.count; i++) {
            Element *child = children.items[i];
            layout(child, e->cw, forced_height, -1, -1);
            int y = a + (i == 0 ? number(child, MT) : maximum(previous_bottom, number(child, MT)));
            position(e, child, number(child, ML), y);
            a = y + bh(child);
            previous_bottom = number(child, MB);
        }
        if (children.count) a += previous_bottom;
    }
    e->ch = forced_height >= 0 ? forced_height : clamp(e, a, height_reference, false);
    return a;
}

static void relayout(void) {
    clear_arena(&layout_memory);
    for (int i = 0; i < element_count; i++) {
        Element *e = &elements[i];
        e->displayed = !equal(e->style[DISPLAY], "none") && (!e->parent || e->parent->displayed);
        e->intrinsic = -1;
        e->containing = NULL;
        e->lines = (Strings){0};
    }
    Element *root = &elements[0];
    if (root->displayed && !equal(root->style[POSITION], "absolute")) {
        layout(root, viewport_width, viewport_height, -1, -1);
        root->rx = number(root, ML);
        root->ry = number(root, MT);
    }
    for (int i = 0; i < element_count; i++) {
        Element *e = &elements[i];
        if (!e->displayed || !equal(e->style[POSITION], "absolute")) continue;
        Element *cb = e->parent;
        while (cb && equal(cb->style[POSITION], "static")) cb = cb->parent;
        e->containing = cb;
        int width = cb ? cb->cw + number(cb, PL) + number(cb, PR) : viewport_width, height = cb ? cb->ch + number(cb, PT) + number(cb, PB) : viewport_height;
        int left = equal(e->style[LEFT], "auto") ? 0 : number(e, LEFT), right = equal(e->style[RIGHT], "auto") ? 0 : number(e, RIGHT), top = equal(e->style[TOP], "auto") ? 0 : number(e, TOP), bottom = equal(e->style[BOTTOM], "auto") ? 0 : number(e, BOTTOM);
        int w = resolve(e, WIDTH, width, true);
        if (equal(e->style[WIDTH], "auto")) {
            int r = maximum(0, width - left - right - hm(e) - hf(e));
            w = !equal(e->style[LEFT], "auto") && !equal(e->style[RIGHT], "auto") ? r : minimum(max_content(e), r);
        }
        int h = equal(e->style[HEIGHT], "auto") && !equal(e->style[TOP], "auto") && !equal(e->style[BOTTOM], "auto") ? clamp(e, maximum(0, height - top - bottom - vm(e) - vf(e)), height, false) : -1;
        layout(e, width, height, clamp(e, w, width, true), h);
        e->rx = !equal(e->style[LEFT], "auto") ? left + number(e, ML) : !equal(e->style[RIGHT], "auto") ? width - right - number(e, MR) - bw(e) : number(e, ML);
        e->ry = !equal(e->style[TOP], "auto") ? top + number(e, MT) : !equal(e->style[BOTTOM], "auto") ? height - bottom - number(e, MB) - bh(e) : number(e, MT);
    }
    for (int i = 0; i < element_count; i++) {
        Element *e = &elements[i];
        if (!e->displayed) continue;
        bool absolute = equal(e->style[POSITION], "absolute");
        Element *reference = absolute ? e->containing : e->parent;
        e->x = e->rx + (reference ? reference->x + (absolute ? number(reference, BL) : 0) : 0);
        e->y = e->ry + (reference ? reference->y + (absolute ? number(reference, BT) : 0) : 0);
        if (equal(e->style[POSITION], "relative")) {
            e->x += !equal(e->style[LEFT], "auto") ? number(e, LEFT) : !equal(e->style[RIGHT], "auto") ? -number(e, RIGHT) : 0;
            e->y += !equal(e->style[TOP], "auto") ? number(e, TOP) : !equal(e->style[BOTTOM], "auto") ? -number(e, BOTTOM) : 0;
        }
    }
}

static Box box(Element *e) {
    return (Box){e->displayed, e->x, e->y, bw(e), bh(e)};
}

static void snapshot(Box boxes[60]) {
    for (int i = 0; i < element_count; i++) boxes[i] = box(&elements[i]);
}

static void print_changes(const Box before[60]) {
    bool any = false;
    for (int i = 0; i < element_count; i++) {
        Box now = box(&elements[i]), old = before[i];
        if (old.displayed != now.displayed || (now.displayed && (old.x != now.x || old.y != now.y || old.width != now.width || old.height != now.height))) {
            printf("%s%s", any ? " " : "", elements[i].id);
            any = true;
        }
    }
    if (!any) printf("no change");
    putchar('\n');
}

static void rectangle(const char *name, int x, int y, int width, int height) {
    printf("%s %d %d %d %d\n", name, x, y, width, height);
}

static void render(void) {
    char screen[40][81];
    for (int y = 0; y < viewport_height; y++) {
        memset(screen[y], '.', (size_t)viewport_width);
        screen[y][viewport_width] = '\0';
    }
    for (int i = 0; i < element_count; i++) {
        Element *e = &elements[i];
        if (!e->displayed) continue;
        for (int y = maximum(0, e->y); y < minimum(viewport_height, e->y + bh(e)); y++) for (int x = maximum(0, e->x); x < minimum(viewport_width, e->x + bw(e)); x++) {
            bool horizontal = (number(e, BT) == 1 && y == e->y) || (number(e, BB) == 1 && y == e->y + bh(e) - 1), vertical = (number(e, BL) == 1 && x == e->x) || (number(e, BR) == 1 && x == e->x + bw(e) - 1);
            screen[y][x] = horizontal ? vertical ? '+' : '-' : vertical ? '|' : ' ';
        }
        if (e->text) for (int line = 0; line < e->lines.count; line++) {
            int y = cy(e) + line;
            if (y < 0 || y >= viewport_height) continue;
            const char *text = e->lines.items[line];
            for (int j = 0; text[j]; j++) {
                int x = cx(e) + j;
                if (x >= 0 && x < viewport_width) screen[y][x] = text[j];
            }
        }
    }
    printf("render %dx%d\n", viewport_width, viewport_height);
    for (int x = 0; x < viewport_width + 2; x++) putchar('#');
    putchar('\n');
    for (int y = 0; y < viewport_height; y++) printf("#%s#\n", screen[y]);
    for (int x = 0; x < viewport_width + 2; x++) putchar('#');
    putchar('\n');
}

static Element *find_element(const char *id) {
    for (int i = 0; i < element_count; i++) if (equal(elements[i].id, id)) return &elements[i];
    return NULL;
}

static void command(const char *line) {
    Strings tokens = split(&work, line, " ");
    char **t = tokens.items;
    Element *e = tokens.count > 1 ? find_element(t[1]) : NULL;
    if (equal(t[0], "LAYOUT")) {
        printf("layout %dx%d\n", viewport_width, viewport_height);
        for (int i = 0; i < element_count; i++) {
            Element *item = &elements[i];
            for (int n = 0; n < item->depth * 2; n++) putchar(' ');
            if (item->displayed) rectangle(item->id, item->x, item->y, bw(item), bh(item));
            else printf("%s none\n", item->id);
        }
    } else if (equal(t[0], "BOX")) {
        if (!e) printf("error: unknown element %s\n", t[1]);
        else if (!e->displayed) printf("box %s: none\n", e->id);
        else {
            printf("box %s\n", e->id);
            rectangle("margin", e->x - number(e, ML), e->y - number(e, MT), bw(e) + hm(e), bh(e) + vm(e));
            rectangle("border", e->x, e->y, bw(e), bh(e));
            rectangle("padding", e->x + number(e, BL), e->y + number(e, BT), e->cw + number(e, PL) + number(e, PR), e->ch + number(e, PT) + number(e, PB));
            rectangle("content", cx(e), cy(e), e->cw, e->ch);
        }
    } else if (equal(t[0], "RENDER")) render();
    else if (equal(t[0], "HIT")) {
        int x = atoi(t[1]), y = atoi(t[2]);
        if (x >= viewport_width || y >= viewport_height) printf("error: point %d %d outside viewport\n", x, y);
        else {
            Element *hit = NULL, *path[11];
            int count = 0;
            for (int i = 0; i < element_count; i++) {
                Element *item = &elements[i];
                if (item->displayed && x >= item->x && x < item->x + bw(item) && y >= item->y && y < item->y + bh(item)) hit = item;
            }
            printf("hit %d %d: ", x, y);
            for (; hit; hit = hit->parent) path[count++] = hit;
            if (!count) printf("none");
            for (int i = count - 1; i >= 0; i--) printf("%s%s", i == count - 1 ? "" : " > ", path[i]->id);
            putchar('\n');
        }
    } else if (equal(t[0], "SET")) {
        const char *value = line + strlen(t[0]) + strlen(t[1]) + strlen(t[2]) + 3;
        int property = property_index(t[2]);
        Declaration values[4];
        if (!e) printf("error: unknown element %s\n", t[1]);
        else if (property < 0) printf("error: unknown property %s\n", t[2]);
        else {
            int count = parse_declaration(property, value, values);
            if (!count) printf("error: invalid value for %s: %s\n", t[2], value);
            else {
                Box old[60];
                snapshot(old);
                for (int i = 0; i < count; i++) e->style[values[i].property] = copy(&permanent, values[i].value);
                relayout();
                printf("set %s %s %s: ", e->id, t[2], value);
                print_changes(old);
            }
        }
    } else if (equal(t[0], "VIEWPORT")) {
        int width = atoi(t[1]), height = atoi(t[2]);
        if (width < 1 || width > 80 || height < 1 || height > 40) printf("error: invalid viewport %d %d\n", width, height);
        else {
            Box old[60];
            snapshot(old);
            viewport_width = width;
            viewport_height = height;
            relayout();
            printf("viewport %d %d: ", width, height);
            print_changes(old);
        }
    } else if (equal(t[0], "OVERFLOW")) {
        bool any = false;
        printf("overflow: ");
        for (int i = 0; i < element_count; i++) {
            Element *item = &elements[i];
            if (!item->displayed) continue;
            bool overflow = false;
            if (item->text) {
                overflow = item->lines.count > item->ch;
                for (int j = 0; j < item->lines.count; j++) if ((int)strlen(item->lines.items[j]) > item->cw) overflow = true;
            } else {
                ElementList children = flow(item, false);
                for (int j = 0; j < children.count; j++) {
                    Element *child = children.items[j];
                    if (child->x - number(child, ML) < cx(item) || child->y - number(child, MT) < cy(item) || child->x + bw(child) + number(child, MR) > cx(item) + item->cw || child->y + bh(child) + number(child, MB) > cy(item) + item->ch) overflow = true;
                }
            }
            if (overflow) {
                printf("%s%s", any ? " " : "", item->id);
                any = true;
            }
        }
        if (!any) printf("none");
        putchar('\n');
    } else printf("error: unknown command %s\n", t[0]);
}

static void read_rule(const char *line) {
    Rule *rule = &rules[rule_count++];
    const char *brace = strstr(line, " { ");
    char *selector_text = part(&permanent, line, (size_t)(brace - line));
    rule->selectors = split(&permanent, selector_text, ", ");
    Strings declarations = split(&work, part(&work, brace + 3, strlen(brace + 3) - 2), "; ");
    for (int i = 0; i < declarations.count; i++) {
        const char *raw = declarations.items[i], *colon = strstr(raw, ": ");
        int property = property_index(part(&work, raw, (size_t)(colon - raw)));
        Declaration values[4];
        int count = parse_declaration(property, colon + 2, values);
        for (int j = 0; j < count; j++) rule->declarations[rule->count++] = (Declaration){values[j].property, copy(&permanent, values[j].value)};
    }
}

static void read_element(const char *line, Element *ancestors[11]) {
    int spaces = 0;
    while (line[spaces] == ' ') spaces++;
    Element *e = &elements[element_count];
    e->index = element_count++;
    e->depth = spaces / 2;
    const char *body = line + spaces, *space = strchr(body, ' ');
    char *head = space ? part(&work, body, (size_t)(space - body)) : copy(&work, body);
    if (space) e->text = part(&permanent, space + 2, strlen(space + 2) - 1);
    char *hash = strchr(head, '#');
    e->type = part(&permanent, head, (size_t)(hash - head));
    Strings parts = split(&permanent, hash + 1, ".");
    e->id = parts.items[0];
    for (int i = 1; i < parts.count; i++) add_string(&permanent, &e->classes, parts.items[i]);
    if (e->depth > 0) {
        e->parent = ancestors[e->depth - 1];
        e->parent->children[e->parent->child_count++] = e;
    }
    ancestors[e->depth] = e;
    int scores[PROPERTY_COUNT];
    for (int i = 0; i < PROPERTY_COUNT; i++) {
        scores[i] = -1;
        e->style[i] = initial_values[i];
    }
    for (int i = 0; i < rule_count; i++) {
        Rule *rule = &rules[i];
        int score = -1;
        for (int j = 0; j < rule->selectors.count; j++) {
            const char *selector = rule->selectors.items[j];
            if (selector[0] == '#' && equal(selector + 1, e->id)) score = maximum(score, 2);
            else if (selector[0] == '.') {
                for (int k = 0; k < e->classes.count; k++) if (equal(selector + 1, e->classes.items[k])) score = maximum(score, 1);
            } else if (equal(selector, e->type)) score = maximum(score, 0);
        }
        if (score >= 0) for (int j = 0; j < rule->count; j++) {
            Declaration d = rule->declarations[j];
            if (score >= scores[d.property]) {
                e->style[d.property] = d.value;
                scores[d.property] = score;
            }
        }
    }
}

int main(void) {
    char *line = read_line();
    if (!line) return 0;
    sscanf(line, "%d %d", &viewport_width, &viewport_height);
    free(line);
    while ((line = read_line()) && !equal(line, "---")) {
        read_rule(line);
        free(line);
        clear_arena(&work);
    }
    free(line);
    Element *ancestors[11] = {0};
    while ((line = read_line()) && !equal(line, "===")) {
        read_element(line, ancestors);
        free(line);
        clear_arena(&work);
    }
    free(line);
    relayout();
    while ((line = read_line()) && !equal(line, "END")) {
        command(line);
        free(line);
        clear_arena(&work);
    }
    free(line);
    clear_arena(&layout_memory);
    clear_arena(&work);
    clear_arena(&permanent);
    return 0;
}
