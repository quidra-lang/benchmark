#include "layout.h"
void *allocate(size_t size) {
    void *data = calloc(1, size ? size : 1);
    if (!data)
        exit(EXIT_FAILURE);
    return data;
}
void *resize(void *data, size_t size) {
    void *next = realloc(data, size ? size : 1);
    if (!next)
        exit(EXIT_FAILURE);
    return next;
}
char *copy_text(const char *text) {
    size_t size = strlen(text) + 1;
    char *out = allocate(size);
    memcpy(out, text, size);
    return out;
}
char *format_text(const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *out = allocate((size_t)length + 1);
    vsnprintf(out, (size_t)length + 1, format, args);
    va_end(args);
    return out;
}
void int_push(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof *list->data);
    }
    list->data[list->count++] = value;
}
bool int_has(const IntList *list, int value) {
    for (int i = 0; i < list->count; ++i)
        if (list->data[i] == value)
            return true;
    return false;
}
void int_add(IntList *list, int value) {
    if (!int_has(list, value))
        int_push(list, value);
}
IntList int_copy(const IntList *list) {
    IntList out = {0};
    if (list->count) {
        out.count = out.capacity = list->count;
        out.data = allocate((size_t)out.count * sizeof *out.data);
        memcpy(out.data, list->data, (size_t)out.count * sizeof *out.data);
    }
    return out;
}
void int_free(IntList *list) {
    free(list->data);
    *list = (IntList){0};
}
void lines_push(TextLines *lines, char *text) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 16;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof *lines->data);
    }
    lines->data[lines->count++] = text;
}
void lines_add(TextLines *lines, const char *text) { lines_push(lines, copy_text(text)); }
void lines_append(TextLines *lines, const TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_add(lines, from->data[i]);
}
void lines_free(TextLines *lines) {
    for (int i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (TextLines){0};
}
TextLines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    if (!input)
        exit(EXIT_FAILURE);
    TextLines out = {0};
    char *line = NULL;
    size_t length = 0, capacity = 0;
    int c;
    while ((c = fgetc(input)) != EOF) {
        if (c == '\n') {
            if (!line)
                line = allocate(1);
            line[length] = 0;
            lines_push(&out, line);
            line = NULL;
            length = capacity = 0;
        } else {
            if (length + 1 >= capacity) {
                capacity = capacity ? capacity * 2 : 128;
                line = resize(line, capacity);
            }
            line[length++] = (char)c;
        }
    }
    if (ferror(input))
        exit(EXIT_FAILURE);
    if (length) {
        line[length] = 0;
        lines_push(&out, line);
    } else
        free(line);
    fclose(input);
    return out;
}
char *join_texts(const TextLines *texts, const char *separator) {
    size_t size = 1, separator_size = strlen(separator);
    for (int i = 0; i < texts->count; ++i)
        size += strlen(texts->data[i]) + (i ? separator_size : 0);
    char *out = allocate(size), *at = out;
    for (int i = 0; i < texts->count; ++i) {
        if (i) {
            memcpy(at, separator, separator_size);
            at += separator_size;
        }
        size_t length = strlen(texts->data[i]);
        memcpy(at, texts->data[i], length);
        at += length;
    }
    *at = 0;
    return out;
}

const char *setting_names[13] = {"layering", "width",     "promotion", "heuristic", "sweeps",
                                 "node_sep", "dummy_sep", "layer_gap", "direction", "sifting",
                                 "reduce",   "restarts",  "seed"};
const char *direction_name(Direction direction) {
    static const char *names[] = {"TB", "BT", "LR", "RL"};
    return names[direction];
}
bool vertical(Direction direction) { return direction == DIR_TB || direction == DIR_BT; }
TextLines split_words(const char *text) {
    TextLines out = {0};
    const char *at = text;
    while (*at) {
        while (*at == ' ')
            ++at;
        if (!*at)
            break;
        const char *start = at;
        while (*at && *at != ' ')
            ++at;
        size_t length = (size_t)(at - start);
        char *word = allocate(length + 1);
        memcpy(word, start, length);
        word[length] = 0;
        lines_push(&out, word);
    }
    return out;
}
static Settings defaults(void) {
    return (Settings){false, false, false, false, false, 4, 12, 2, 1, 3, 0, 1, DIR_TB};
}
TextLines settings_values(Settings settings) {
    TextLines out = {0};
    lines_add(&out, settings.coffman ? "coffman" : "longest");
    lines_push(&out, format_text("%d", settings.width));
    lines_add(&out, settings.promotion ? "on" : "off");
    lines_add(&out, settings.median ? "median" : "barycenter");
    lines_push(&out, format_text("%d", settings.sweeps));
    lines_push(&out, format_text("%d", settings.node_sep));
    lines_push(&out, format_text("%d", settings.dummy_sep));
    lines_push(&out, format_text("%d", settings.layer_gap));
    lines_add(&out, direction_name(settings.direction));
    lines_add(&out, settings.sifting ? "on" : "off");
    lines_add(&out, settings.reduce ? "on" : "off");
    lines_push(&out, format_text("%d", settings.restarts));
    lines_push(&out, format_text("%lld", (long long)settings.seed));
    return out;
}
static bool set_setting(Settings *settings, const char *name, const char *value) {
    if (!strcmp(name, "layering")) {
        if (strcmp(value, "longest") && strcmp(value, "coffman"))
            return false;
        settings->coffman = !strcmp(value, "coffman");
        return true;
    }
    if (!strcmp(name, "heuristic")) {
        if (strcmp(value, "barycenter") && strcmp(value, "median"))
            return false;
        settings->median = !strcmp(value, "median");
        return true;
    }
    if (!strcmp(name, "direction")) {
        for (int i = 0; i < 4; ++i)
            if (!strcmp(value, direction_name((Direction)i))) {
                settings->direction = (Direction)i;
                return true;
            }
        return false;
    }
    if (!strcmp(name, "promotion") || !strcmp(name, "sifting") || !strcmp(name, "reduce")) {
        if (strcmp(value, "on") && strcmp(value, "off"))
            return false;
        bool enabled = !strcmp(value, "on");
        if (!strcmp(name, "promotion"))
            settings->promotion = enabled;
        else if (!strcmp(name, "sifting"))
            settings->sifting = enabled;
        else
            settings->reduce = enabled;
        return true;
    }
    int index = -1;
    for (int i = 0; i < 13; ++i)
        if (!strcmp(name, setting_names[i])) {
            index = i;
            break;
        }
    if (index < 0 || !*value || strlen(value) > 10)
        return false;
    int64_t number = 0;
    for (const char *at = value; *at; ++at) {
        if (*at < '0' || *at > '9')
            return false;
        number = number * 10 + (*at - '0');
    }
    static const int64_t low[] = {0, 1, 0, 0, 0, 1, 1, 2, 0, 0, 0, 0, 1};
    static const int64_t high[] = {0, 40, 0, 0, 50, 9, 9, 9, 0, 0, 0, 9, 2147483646};
    if (number < low[index] || number > high[index])
        return false;
    if (index == 1)
        settings->width = (int)number;
    else if (index == 4)
        settings->sweeps = (int)number;
    else if (index == 5)
        settings->node_sep = (int)number;
    else if (index == 6)
        settings->dummy_sep = (int)number;
    else if (index == 7)
        settings->layer_gap = (int)number;
    else if (index == 11)
        settings->restarts = (int)number;
    else if (index == 12)
        settings->seed = number;
    else
        return false;
    return true;
}
static int compare_nodes(const void *left, const void *right) {
    const NodeData *a = left, *b = right;
    return (a->id > b->id) - (a->id < b->id);
}
Block *read_blocks(int *count) {
    Settings settings = defaults();
    TextLines params = read_lines("input/params.txt");
    for (int i = 0; i < params.count; ++i) {
        if (!params.data[i][0] || params.data[i][0] == '#')
            continue;
        TextLines words = split_words(params.data[i]);
        set_setting(&settings, words.data[0], words.data[1]);
        lines_free(&words);
    }
    lines_free(&params);
    TextLines lines = read_lines("input/graphs.txt");
    Block *blocks = allocate(30 * sizeof *blocks);
    *count = 0;
    bool declared[1000] = {0};
    Block *block = NULL;
    for (int i = 0; i < lines.count; ++i) {
        if (!lines.data[i][0] || lines.data[i][0] == '#')
            continue;
        TextLines words = split_words(lines.data[i]);
        const char *kind = words.data[0];
        if (!strcmp(kind, "GRAPH")) {
            block = &blocks[(*count)++];
            strcpy(block->name, words.data[1]);
            block->settings = settings;
            memset(declared, 0, sizeof declared);
            lines_free(&words);
            continue;
        }
        if (block->error) {
            lines_free(&words);
            continue;
        }
        const char *reason = NULL;
        if (!strcmp(kind, "OPTION")) {
            if (!set_setting(&block->settings, words.data[1], words.data[2]))
                reason = "bad_option";
        } else if (!strcmp(kind, "NODE")) {
            int id = atoi(words.data[1]);
            if (declared[id])
                reason = "duplicate_node";
            else if (block->node_count == 40)
                reason = "too_many_nodes";
            else {
                declared[id] = true;
                NodeData *node = &block->nodes[block->node_count++];
                node->id = id;
                strcpy(node->label, words.data[2]);
            }
        } else if (!strcmp(kind, "EDGE") || !strcmp(kind, "PATH")) {
            int from = atoi(words.data[1]), to = atoi(words.data[2]);
            if (!declared[from] || !declared[to])
                reason = "unknown_node";
            else if (!strcmp(kind, "PATH")) {
                block->has_path = true;
                block->path_from = from;
                block->path_to = to;
            } else if (from == to)
                ++block->self_loops;
            else {
                bool duplicate = false;
                for (int j = 0; j < block->edge_count; ++j)
                    if (block->edges[j].from == from && block->edges[j].to == to)
                        duplicate = true;
                if (duplicate)
                    ++block->duplicates;
                else
                    block->edges[block->edge_count++] = (RawEdge){from, to};
            }
        } else if (!strcmp(kind, "END") && !block->node_count)
            reason = "no_nodes";
        if (reason) {
            block->error = reason;
            block->error_line = i + 1;
        }
        lines_free(&words);
    }
    lines_free(&lines);
    for (int i = 0; i < *count; ++i)
        qsort(blocks[i].nodes, (size_t)blocks[i].node_count, sizeof *blocks[i].nodes,
              compare_nodes);
    return blocks;
}
