#include <inttypes.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Line {
    size_t references, length;
    char text[];
} Line;
typedef struct { Line **items; size_t count, capacity; } Lines;
typedef struct Node Node;
typedef struct { Node **items; size_t count, capacity; } Nodes;
typedef enum { DIRECTORY, FILE_NODE, LINK } Kind;
struct Node {
    Kind kind;
    int inode, modified;
    Node *parent;
    char *name;
    union { Nodes children; Lines lines; char *target; } data;
};
typedef struct {
    Node *root, *current;
    char *previous;
    int clock, next_inode;
    Nodes retired;
} Shell;
typedef enum { RESOLVED, MISSING, NOT_DIRECTORY, TOO_MANY_LINKS } Failure;
typedef struct {
    Node *node, *creation_parent;
    char creation_name[17];
    Failure failure;
} Resolution;
typedef struct { bool terminal; Lines lines; } Output;
typedef struct { bool flags[128]; char **paths; int count; } Options;

static void *allocate(size_t size) {
    void *memory = malloc(size);
    if (!memory) abort();
    return memory;
}
static void *resize(void *memory, size_t size) {
    void *result = realloc(memory, size);
    if (!result) abort();
    return result;
}
static char *copy_text(const char *text) {
    size_t size = strlen(text) + 1;
    char *result = allocate(size);
    memcpy(result, text, size);
    return result;
}
static char *concatenate(const char *first, const char *last) {
    size_t a = strlen(first), b = strlen(last);
    char *result = allocate(a + b + 1);
    memcpy(result, first, a);
    memcpy(result + a, last, b + 1);
    return result;
}
static void release_line(Line *line) {
    if (--line->references == 0) free(line);
}
static void push_line(Lines *lines, Line *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 8;
        lines->items = resize(lines->items, lines->capacity * sizeof(*lines->items));
    }
    line->references++;
    lines->items[lines->count++] = line;
}
static void clear_lines(Lines *lines) {
    for (size_t i = 0; i < lines->count; i++) release_line(lines->items[i]);
    free(lines->items);
    *lines = (Lines){0};
}
static void append_lines(Lines *destination, const Lines *source) {
    for (size_t i = 0; i < source->count; i++) push_line(destination, source->items[i]);
}
static void emit_line(Output *output, Line *line) {
    if (output->terminal) puts(line->text);
    else push_line(&output->lines, line);
}
static void emit(Output *output, const char *format, ...) {
    va_list args, measured;
    va_start(args, format);
    va_copy(measured, args);
    int length = vsnprintf(NULL, 0, format, measured);
    va_end(measured);
    if (length < 0) abort();
    Line *line = allocate(sizeof(*line) + (size_t)length + 1);
    line->references = 1;
    line->length = (size_t)length;
    vsnprintf(line->text, line->length + 1, format, args);
    va_end(args);
    emit_line(output, line);
    release_line(line);
}
static void error(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    putchar('\n');
}
static void push_node(Nodes *nodes, Node *node) {
    if (nodes->count == nodes->capacity) {
        nodes->capacity = nodes->capacity ? nodes->capacity * 2 : 8;
        nodes->items = resize(nodes->items, nodes->capacity * sizeof(*nodes->items));
    }
    nodes->items[nodes->count++] = node;
}
static Node *child(Node *directory, const char *name) {
    for (size_t i = 0; i < directory->data.children.count; i++) {
        Node *node = directory->data.children.items[i];
        if (strcmp(node->name, name) == 0) return node;
    }
    return NULL;
}
static void add_node(Shell *shell, Node *parent, const char *name, Node *node) {
    char *owned_name = copy_text(name);
    free(node->name);
    node->name = owned_name;
    node->parent = parent;
    Nodes *children = &parent->data.children;
    push_node(children, node);
    size_t index = children->count - 1;
    while (index && strcmp(children->items[index - 1]->name, owned_name) > 0) {
        children->items[index] = children->items[index - 1];
        index--;
    }
    children->items[index] = node;
    parent->modified = shell->clock;
}
static Node *create_node(Shell *shell, Node *parent, const char *name, Kind kind, const char *target) {
    Node *node = allocate(sizeof(*node));
    *node = (Node){.kind = kind, .inode = shell->next_inode++, .modified = shell->clock};
    if (kind == LINK) node->data.target = copy_text(target);
    else if (kind == FILE_NODE) node->data.lines = (Lines){0};
    add_node(shell, parent, name, node);
    return node;
}
static void detach_node(Shell *shell, Node *node) {
    Nodes *children = &node->parent->data.children;
    size_t index = 0;
    while (children->items[index] != node) index++;
    memmove(children->items + index, children->items + index + 1,
            (children->count - index - 1) * sizeof(*children->items));
    children->count--;
    node->parent->modified = shell->clock;
}
static void remove_node(Shell *shell, Node *node) {
    detach_node(shell, node);
    push_node(&shell->retired, node);
}
static void free_node(Node *node) {
    if (node->kind == DIRECTORY) {
        for (size_t i = 0; i < node->data.children.count; i++) free_node(node->data.children.items[i]);
        free(node->data.children.items);
    } else if (node->kind == FILE_NODE) clear_lines(&node->data.lines);
    else free(node->data.target);
    free(node->name);
    free(node);
}
static void write_file(Shell *shell, Node *file, const Lines *lines, bool append) {
    if (append) append_lines(&file->data.lines, lines);
    else {
        Lines replacement = {0};
        append_lines(&replacement, lines);
        clear_lines(&file->data.lines);
        file->data.lines = replacement;
    }
    file->modified = shell->clock;
}
static bool descendant(const Shell *shell, Node *node, Node *ancestor) {
    for (;;) {
        if (node == ancestor) return true;
        if (node == shell->root) return false;
        node = node->parent;
    }
}
static char *absolute(const Shell *shell, Node *node) {
    size_t length = 0;
    for (Node *part = node; part != shell->root; part = part->parent) length += strlen(part->name) + 1;
    if (!length) return copy_text("/");
    char *result = allocate(length + 1);
    result[length] = '\0';
    while (node != shell->root) {
        size_t size = strlen(node->name);
        length -= size;
        memcpy(result + length, node->name, size);
        result[--length] = '/';
        node = node->parent;
    }
    return result;
}
static const char *last_component(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}
static char *join(const char *path, const char *name) {
    char *prefix = strcmp(path, "/") == 0 ? copy_text(path) : concatenate(path, "/");
    char *result = concatenate(prefix, name);
    free(prefix);
    return result;
}
static const char *reason(Resolution result) {
    switch (result.failure) {
        case MISSING: return "No such file or directory";
        case NOT_DIRECTORY: return "Not a directory";
        case TOO_MANY_LINKS: return "Too many levels of symbolic links";
        default: return "";
    }
}
static Resolution walk(Shell *shell, const char *path, Node *base, bool follow,
                       bool original, bool make_parents, int *expansions) {
    Node *node = path[0] == '/' ? shell->root : base;
    const char *position = path;
    while (*position) {
        if (*position == '/') { position++; continue; }
        if (node->kind != DIRECTORY) return (Resolution){.failure = NOT_DIRECTORY};
        const char *end = strchr(position, '/');
        if (!end) end = position + strlen(position);
        char name[17];
        size_t length = (size_t)(end - position);
        memcpy(name, position, length);
        name[length] = '\0';
        bool last = !*end;
        position = end;
        if (strcmp(name, ".") == 0) continue;
        if (strcmp(name, "..") == 0) { node = node->parent; continue; }
        Node *next = child(node, name);
        if (!next) {
            if (original && make_parents && !last) next = create_node(shell, node, name, DIRECTORY, NULL);
            else {
                Resolution missing = {.failure = MISSING};
                if (original && last) {
                    missing.creation_parent = node;
                    strcpy(missing.creation_name, name);
                }
                return missing;
            }
        }
        if (next->kind == LINK && (!last || follow)) {
            if (++*expansions > 8) return (Resolution){.failure = TOO_MANY_LINKS};
            Resolution expanded = walk(shell, next->data.target, node, true, false, false, expansions);
            if (!expanded.node) return expanded;
            next = expanded.node;
        }
        node = next;
    }
    return (Resolution){.node = node};
}
static Resolution resolve(Shell *shell, const char *path, bool follow, bool parents) {
    int expansions = 0;
    return walk(shell, path, shell->current, follow, true, parents, &expansions);
}
static int64_t node_size(const Node *node) {
    if (node->kind == DIRECTORY) return (int64_t)node->data.children.count;
    if (node->kind == LINK) return (int64_t)strlen(node->data.target);
    int64_t size = 0;
    for (size_t i = 0; i < node->data.lines.count; i++) size += (int64_t)node->data.lines.items[i]->length + 1;
    return size;
}
static int link_count(const Node *node) {
    if (node->kind != DIRECTORY) return 1;
    int count = 2;
    for (size_t i = 0; i < node->data.children.count; i++) count += node->data.children.items[i]->kind == DIRECTORY;
    return count;
}
static char tag(const Node *node) { return node->kind == DIRECTORY ? 'd' : node->kind == FILE_NODE ? 'f' : 'l'; }
static Options options(char **arguments, int count) {
    Options result = {0};
    int position = 0;
    while (position < count && arguments[position][0] == '-') {
        for (const char *c = arguments[position++] + 1; *c; c++) result.flags[(unsigned char)*c] = true;
    }
    result.paths = arguments + position;
    result.count = count - position;
    return result;
}
static bool invalid_source(const char *name) {
    return !*name || strcmp(name, ".") == 0 || strcmp(name, "..") == 0;
}
static void clone_node(Shell *shell, Node *source, Node *parent, const char *name) {
    Node *copy = create_node(shell, parent, name, source->kind, source->kind == LINK ? source->data.target : NULL);
    if (source->kind == FILE_NODE) append_lines(&copy->data.lines, &source->data.lines);
    else if (source->kind == DIRECTORY)
        for (size_t i = 0; i < source->data.children.count; i++) {
            Node *entry = source->data.children.items[i];
            clone_node(shell, entry, copy, entry->name);
        }
}
static void move_one(Shell *shell, const char *source_path, const char *destination) {
    const char *basename = last_component(source_path);
    if (invalid_source(basename)) { error("mv: cannot move '%s' to '%s': Invalid argument", source_path, destination); return; }
    Resolution source_result = resolve(shell, source_path, false, false);
    Node *source = source_result.node;
    if (!source) { error("mv: cannot stat '%s': %s", source_path, reason(source_result)); return; }
    Resolution destination_result = resolve(shell, destination, true, false);
    Node *parent;
    char name[17];
    char *target;
    if (destination_result.node && destination_result.node->kind == DIRECTORY) {
        parent = destination_result.node;
        strcpy(name, basename);
        target = join(destination, basename);
    } else {
        Resolution result = resolve(shell, destination, false, false);
        if (result.node) { parent = result.node->parent; strcpy(name, result.node->name); }
        else if (result.creation_parent) { parent = result.creation_parent; strcpy(name, result.creation_name); }
        else { error("mv: cannot move '%s' to '%s': %s", source_path, destination, reason(result)); return; }
        target = copy_text(destination);
    }
    Node *existing = child(parent, name);
    if (source->kind == DIRECTORY && descendant(shell, parent, source))
        error("mv: cannot move '%s' to a subdirectory of itself, '%s'", source_path, target);
    else if (existing == source) error("mv: '%s' and '%s' are the same file", source_path, target);
    else if (existing && source->kind == DIRECTORY && existing->kind != DIRECTORY)
        error("mv: cannot overwrite non-directory '%s' with directory '%s'", target, source_path);
    else if (existing && source->kind != DIRECTORY && existing->kind == DIRECTORY)
        error("mv: cannot overwrite directory '%s' with non-directory '%s'", target, source_path);
    else if (existing && existing->kind == DIRECTORY && existing->data.children.count)
        error("mv: cannot move '%s' to '%s': Directory not empty", source_path, target);
    else if (existing == shell->current) error("mv: cannot move '%s' to '%s': Device or resource busy", source_path, target);
    else {
        if (existing) remove_node(shell, existing);
        detach_node(shell, source);
        add_node(shell, parent, name, source);
    }
    free(target);
}
static void copy_one(Shell *shell, const char *source_path, const char *destination, bool recursive) {
    const char *basename = last_component(source_path);
    if (invalid_source(basename)) { error("cp: cannot copy '%s' to '%s': Invalid argument", source_path, destination); return; }
    Resolution source_result = resolve(shell, source_path, true, false);
    Node *source = source_result.node;
    if (!source) { error("cp: cannot stat '%s': %s", source_path, reason(source_result)); return; }
    if (source->kind == DIRECTORY && !recursive) { error("cp: -r not specified; omitting directory '%s'", source_path); return; }
    Resolution destination_result = resolve(shell, destination, true, false);
    if (!destination_result.node && !destination_result.creation_parent) {
        error("cp: cannot copy '%s' to '%s': %s", source_path, destination, reason(destination_result));
        return;
    }
    char *target = destination_result.node && destination_result.node->kind == DIRECTORY ? join(destination, basename) : copy_text(destination);
    Resolution result = resolve(shell, target, source->kind != DIRECTORY, false);
    if (source->kind == DIRECTORY) {
        if (result.node) error("cp: cannot copy '%s' to '%s': File exists", source_path, target);
        else if (!result.creation_parent) error("cp: cannot copy '%s' to '%s': %s", source_path, target, reason(result));
        else if (descendant(shell, result.creation_parent, source)) error("cp: cannot copy a directory, '%s', into itself, '%s'", source_path, target);
        else clone_node(shell, source, result.creation_parent, result.creation_name);
    } else if (result.creation_parent) {
        Node *copy = create_node(shell, result.creation_parent, result.creation_name, FILE_NODE, NULL);
        append_lines(&copy->data.lines, &source->data.lines);
    } else if (!result.node) error("cp: cannot copy '%s' to '%s': %s", source_path, target, reason(result));
    else if (result.node == source) error("cp: '%s' and '%s' are the same file", source_path, target);
    else if (result.node->kind == DIRECTORY) error("cp: cannot overwrite directory '%s' with non-directory '%s'", target, source_path);
    else write_file(shell, result.node, &source->data.lines, false);
    free(target);
}

typedef struct { const char *name; Node *node; size_t order; } ListingEntry;
static int compare_modified(const void *left, const void *right) {
    const ListingEntry *a = left, *b = right;
    if (a->node->modified != b->node->modified) return a->node->modified > b->node->modified ? -1 : 1;
    return (a->order > b->order) - (a->order < b->order);
}
static int digits(int64_t number) {
    int width = 1;
    while (number >= 10) { width++; number /= 10; }
    return width;
}
static void listing(Shell *shell, Options opts, Output *output) {
    char *default_path = ".";
    if (!opts.count) { opts.paths = &default_path; opts.count = 1; }
    for (int path_index = 0; path_index < opts.count; path_index++) {
        const char *path = opts.paths[path_index];
        Resolution result = resolve(shell, path, !opts.flags['l'], false);
        if (!result.node) { error("ls: cannot access '%s': %s", path, reason(result)); continue; }
        Node *node = result.node;
        size_t capacity = node->kind == DIRECTORY ? node->data.children.count + 2 : 1;
        ListingEntry *entries = allocate(capacity * sizeof(*entries));
        size_t count = 0;
        if (node->kind != DIRECTORY) entries[count++] = (ListingEntry){path, node, 0};
        else {
            if (opts.count > 1) emit(output, "%s:", path);
            if (opts.flags['a']) {
                entries[count++] = (ListingEntry){".", node, 0};
                entries[count++] = (ListingEntry){"..", node->parent, 1};
            }
            for (size_t i = 0; i < node->data.children.count; i++) {
                Node *entry = node->data.children.items[i];
                if (!opts.flags['a'] && entry->name[0] == '.') continue;
                entries[count] = (ListingEntry){entry->name, entry, count};
                count++;
            }
            if (opts.flags['t']) qsort(entries, count, sizeof(*entries), compare_modified);
        }
        int link_width = 1, size_width = 1, time_width = 1;
        for (size_t i = 0; i < count; i++) {
            int a = digits(link_count(entries[i].node)), b = digits(node_size(entries[i].node)), c = digits(entries[i].node->modified);
            if (a > link_width) link_width = a;
            if (b > size_width) size_width = b;
            if (c > time_width) time_width = c;
        }
        for (size_t i = 0; i < count; i++) {
            ListingEntry entry = entries[opts.flags['r'] ? count - i - 1 : i];
            Node *item = entry.node;
            if (!opts.flags['l']) emit(output, "%s", entry.name);
            else emit(output, "%c %*d %*" PRId64 " %*d %s%s%s", item->kind == FILE_NODE ? '-' : tag(item),
                      link_width, link_count(item), size_width, node_size(item), time_width, item->modified,
                      entry.name, item->kind == LINK ? " -> " : "", item->kind == LINK ? item->data.target : "");
        }
        free(entries);
    }
}
typedef void (*Visitor)(Node *, const char *, int, void *);
static void visit_tree(Node *node, const char *path, int depth, int limit, Visitor visit, void *context) {
    visit(node, path, depth, context);
    if (node->kind == DIRECTORY && depth < limit)
        for (size_t i = 0; i < node->data.children.count; i++) {
            Node *entry = node->data.children.items[i];
            char *display = join(path, entry->name);
            visit_tree(entry, display, depth + 1, limit, visit, context);
            free(display);
        }
}
static bool glob_matches(const char *pattern, const char *text) {
    size_t length = strlen(text);
    bool previous[18] = {true};
    for (const char *c = pattern; *c; c++) {
        bool next[18] = {false};
        if (*c == '*') {
            next[0] = previous[0];
            for (size_t i = 0; i < length; i++) next[i + 1] = previous[i + 1] || next[i];
        } else
            for (size_t i = 0; i < length; i++) next[i + 1] = previous[i] && (*c == '?' || *c == text[i]);
        memcpy(previous, next, sizeof(previous));
    }
    return previous[length];
}
typedef struct { Output *output; const char *pattern, *root_name; char type; } FindContext;
static void find_visit(Node *node, const char *path, int depth, void *context) {
    FindContext *find = context;
    const char *name = depth ? node->name : find->root_name;
    if ((!find->pattern || glob_matches(find->pattern, name)) && (!find->type || tag(node) == find->type)) emit(find->output, "%s", path);
}
static void find_nodes(Shell *shell, char **arguments, int count, Output *output) {
    int position = count && arguments[0][0] != '-' ? 1 : 0;
    const char *path = position ? arguments[0] : ".";
    FindContext find = {.output = output, .root_name = strcmp(path, "/") == 0 ? "/" : last_component(path)};
    int limit = 1000;
    for (; position < count; position += 2) {
        const char *test = arguments[position], *value = arguments[position + 1];
        if (strcmp(test, "-name") == 0) find.pattern = value;
        else if (strcmp(test, "-type") == 0) find.type = value[0];
        else limit = atoi(value);
    }
    Resolution result = resolve(shell, path, true, false);
    if (!result.node) error("find: '%s': %s", path, reason(result));
    else visit_tree(result.node, path, 0, limit, find_visit, &find);
}
static int64_t usage(Node *node, const char *path, bool show, Options opts, Output *output) {
    int64_t total = node->kind == DIRECTORY ? 0 : node_size(node);
    if (node->kind == DIRECTORY)
        for (size_t i = 0; i < node->data.children.count; i++) {
            Node *entry = node->data.children.items[i];
            char *display = join(path, entry->name);
            total += usage(entry, display, show && !opts.flags['s'] && (entry->kind == DIRECTORY || opts.flags['a']), opts, output);
            free(display);
        }
    if (show) emit(output, "%" PRId64 " %s", total, path);
    return total;
}
static void disk_usage(Shell *shell, Options opts, Output *output) {
    char *default_path = ".";
    if (!opts.count) { opts.paths = &default_path; opts.count = 1; }
    for (int i = 0; i < opts.count; i++) {
        Resolution result = resolve(shell, opts.paths[i], true, false);
        if (!result.node) error("du: cannot access '%s': %s", opts.paths[i], reason(result));
        else usage(result.node, opts.paths[i], true, opts, output);
    }
}
static void draw_tree(Node *node, const char *prefix, bool all, int *directories, int *files, Output *output) {
    size_t visible = 0;
    for (size_t i = 0; i < node->data.children.count; i++) visible += all || node->data.children.items[i]->name[0] != '.';
    for (size_t i = 0; i < node->data.children.count; i++) {
        Node *entry = node->data.children.items[i];
        if (!all && entry->name[0] == '.') continue;
        bool last = --visible == 0;
        emit(output, "%s%s%s%s%s", prefix, last ? "`-- " : "|-- ", entry->name,
             entry->kind == LINK ? " -> " : "", entry->kind == LINK ? entry->data.target : "");
        if (entry->kind == DIRECTORY) {
            (*directories)++;
            char *next = concatenate(prefix, last ? "    " : "|   ");
            draw_tree(entry, next, all, directories, files, output);
            free(next);
        } else (*files)++;
    }
}
static void tree(Shell *shell, Options opts, Output *output) {
    const char *path = opts.count ? opts.paths[0] : ".";
    Resolution result = resolve(shell, path, true, false);
    if (!result.node) { error("tree: %s: %s", path, reason(result)); return; }
    if (result.node->kind != DIRECTORY) { error("tree: %s: Not a directory", path); return; }
    int directories = 0, files = 0;
    emit(output, "%s", path);
    draw_tree(result.node, "", opts.flags['a'], &directories, &files, output);
    emit(output, "%d %s, %d %s", directories, directories == 1 ? "directory" : "directories", files, files == 1 ? "file" : "files");
}

typedef struct {
    const char *command, *pattern, *count_text;
    Options options;
    Output *output;
    bool named;
    int64_t totals[3];
    Lines sorted;
} TextJob;
static char lower_ascii(char character) { return character >= 'A' && character <= 'Z' ? character + ('a' - 'A') : character; }
static bool contains(const char *text, const char *pattern, bool insensitive) {
    if (!insensitive) return strstr(text, pattern) != NULL;
    for (; *text; text++) {
        size_t i = 0;
        while (text[i] && pattern[i] && lower_ascii(text[i]) == lower_ascii(pattern[i])) i++;
        if (!pattern[i]) return true;
    }
    return false;
}
static void report_counts(TextJob *job, const int64_t counts[3], const char *name) {
    char numbers[80];
    size_t used = 0;
    bool all = !job->options.flags['l'] && !job->options.flags['w'] && !job->options.flags['c'];
    for (int i = 0; i < 3; i++)
        if (all || job->options.flags[(unsigned char)"lwc"[i]])
            used += (size_t)snprintf(numbers + used, sizeof(numbers) - used, "%s%" PRId64, used ? " " : "", counts[i]);
    emit(job->output, "%s%s%s", numbers, name ? " " : "", name ? name : "");
}
static void consume_input(TextJob *job, const Lines *lines, const char *name) {
    const char *command = job->command;
    Output *output = job->output;
    if (strcmp(command, "sort") == 0) { append_lines(&job->sorted, lines); return; }
    if (strcmp(command, "cat") == 0) {
        for (size_t i = 0; i < lines->count; i++) emit_line(output, lines->items[i]);
    } else if (strcmp(command, "wc") == 0) {
        int64_t counts[3] = {(int64_t)lines->count, 0, 0};
        for (size_t i = 0; i < lines->count; i++) {
            Line *line = lines->items[i];
            counts[2] += (int64_t)line->length + 1;
            bool inside = false;
            for (const char *c = line->text; *c; c++) {
                if (*c != ' ' && !inside) counts[1]++;
                inside = *c != ' ';
            }
        }
        for (int i = 0; i < 3; i++) job->totals[i] += counts[i];
        report_counts(job, counts, name);
    } else if (strcmp(command, "head") == 0 || strcmp(command, "tail") == 0) {
        const char *count_text = job->count_text;
        size_t count = (size_t)atoi(count_text + (count_text[0] == '-' || count_text[0] == '+'));
        size_t first = 0, last = lines->count;
        if (strcmp(command, "head") == 0) last = count_text[0] == '-' ? (last > count ? last - count : 0) : (last < count ? last : count);
        else if (count_text[0] == '+') { first = count ? count - 1 : 0; if (first > last) first = last; }
        else first = last > count ? last - count : 0;
        for (size_t i = first; i < last; i++) emit_line(output, lines->items[i]);
    } else if (strcmp(command, "grep") == 0) {
        size_t selected = 0;
        for (size_t i = 0; i < lines->count; i++) {
            Line *line = lines->items[i];
            if (contains(line->text, job->pattern, job->options.flags['i']) == job->options.flags['v']) continue;
            selected++;
            if (!job->options.flags['c']) {
                if (job->options.flags['n']) emit(output, "%s%s%zu:%s", job->named ? name : "", job->named ? ":" : "", i + 1, line->text);
                else if (job->named) emit(output, "%s:%s", name, line->text);
                else emit_line(output, line);
            }
        }
        if (job->options.flags['c']) emit(output, "%s%s%zu", job->named ? name : "", job->named ? ":" : "", selected);
    } else {
        for (size_t first = 0; first < lines->count;) {
            size_t last = first + 1;
            while (last < lines->count && strcmp(lines->items[first]->text, lines->items[last]->text) == 0) last++;
            if (job->options.flags['c']) emit(output, "%zu %s", last - first, lines->items[first]->text);
            else emit_line(output, lines->items[first]);
            first = last;
        }
    }
}
static void grep_visit(Node *node, const char *path, int depth, void *context) {
    (void)depth;
    if (node->kind == FILE_NODE) consume_input(context, &node->data.lines, path);
}
static int numeric_value(const char *text) {
    bool negative = *text == '-';
    if (negative) text++;
    int value = 0;
    while (*text >= '0' && *text <= '9') value = value * 10 + *text++ - '0';
    return negative ? -value : value;
}
static int compare_lines(const void *left, const void *right) {
    Line *const *a = left, *const *b = right;
    return strcmp((*a)->text, (*b)->text);
}
static int compare_numbers(const void *left, const void *right) {
    Line *const *a = left, *const *b = right;
    int x = numeric_value((*a)->text), y = numeric_value((*b)->text);
    return x == y ? compare_lines(left, right) : (x > y) - (x < y);
}
static void text_command(Shell *shell, const char *command, char **arguments, int count, const Lines *input, Output *output) {
    Options opts = options(arguments, count);
    TextJob job = {.command = command, .options = opts, .output = output, .count_text = "10"};
    char **paths = opts.paths;
    int path_count = opts.count;
    bool recursive = false;
    if (strcmp(command, "grep") == 0) {
        job.pattern = *paths++;
        path_count--;
        recursive = opts.flags['r'];
        job.named = path_count > 1 || recursive;
    } else if (strcmp(command, "head") == 0 || strcmp(command, "tail") == 0) {
        int offset = count && strcmp(arguments[0], "-n") == 0 ? 2 : 0;
        if (offset) job.count_text = arguments[1];
        paths = arguments + offset;
        path_count = count - offset;
    }
    char *default_path = ".";
    if (recursive && !path_count) { paths = &default_path; path_count = 1; }
    if (!path_count) consume_input(&job, input, NULL);
    for (int i = 0; i < path_count; i++) {
        Resolution result = resolve(shell, paths[i], true, false);
        if (!result.node) error("%s: %s: %s", command, paths[i], reason(result));
        else if (recursive) visit_tree(result.node, paths[i], 0, 1000, grep_visit, &job);
        else if (result.node->kind == DIRECTORY) error("%s: %s: Is a directory", command, paths[i]);
        else consume_input(&job, &result.node->data.lines, paths[i]);
    }
    if (strcmp(command, "wc") == 0 && path_count > 1) report_counts(&job, job.totals, "total");
    if (strcmp(command, "sort") == 0) {
        if (job.sorted.count > 1) qsort(job.sorted.items, job.sorted.count, sizeof(*job.sorted.items), opts.flags['n'] ? compare_numbers : compare_lines);
        for (size_t i = 0; i < job.sorted.count; i++) emit_line(output, job.sorted.items[opts.flags['r'] ? job.sorted.count - i - 1 : i]);
        clear_lines(&job.sorted);
    }
}

static void execute(Shell *shell, char *text, const Lines *input, Output *output) {
    if (strncmp(text, "echo ", 5) == 0) { emit(output, "%s", text + 5); return; }
    char *words[101];
    int length = 0;
    for (char *word = strtok(text, " "); word; word = strtok(NULL, " ")) words[length++] = word;
    const char *command = words[0];
    char **arguments = words + 1;
    int count = length - 1;
    Options opts = options(arguments, count);
    if (strcmp(command, "pwd") == 0) {
        char *path = absolute(shell, shell->current);
        emit(output, "%s", path);
        free(path);
    } else if (strcmp(command, "cd") == 0) {
        const char *path = count ? arguments[0] : "/";
        bool previous = strcmp(path, "-") == 0;
        if (previous) {
            if (!shell->previous) { error("cd: OLDPWD not set"); return; }
            path = shell->previous;
        }
        Resolution result = resolve(shell, path, true, false);
        if (!result.node) error("cd: %s: %s", path, reason(result));
        else if (result.node->kind != DIRECTORY) error("cd: %s: Not a directory", path);
        else {
            char *old = absolute(shell, shell->current);
            free(shell->previous);
            shell->previous = old;
            shell->current = result.node;
            if (previous) {
                char *current_path = absolute(shell, shell->current);
                emit(output, "%s", current_path);
                free(current_path);
            }
        }
    } else if (strcmp(command, "mkdir") == 0) {
        for (int i = 0; i < opts.count; i++) {
            const char *path = opts.paths[i];
            Resolution result = resolve(shell, path, false, opts.flags['p']);
            if (result.creation_parent) create_node(shell, result.creation_parent, result.creation_name, DIRECTORY, NULL);
            else if (!result.node) error("mkdir: cannot create directory '%s': %s", path, reason(result));
            else {
                Resolution followed = opts.flags['p'] ? resolve(shell, path, true, false) : (Resolution){0};
                if (!followed.node || followed.node->kind != DIRECTORY) error("mkdir: cannot create directory '%s': File exists", path);
            }
        }
    } else if (strcmp(command, "touch") == 0) {
        for (int i = 0; i < count; i++) {
            Resolution result = resolve(shell, arguments[i], true, false);
            if (result.creation_parent) create_node(shell, result.creation_parent, result.creation_name, FILE_NODE, NULL);
            else if (result.node) result.node->modified = shell->clock;
            else error("touch: cannot touch '%s': %s", arguments[i], reason(result));
        }
    } else if (strcmp(command, "ls") == 0) listing(shell, opts, output);
    else if (strcmp(command, "stat") == 0) {
        for (int i = 0; i < count; i++) {
            Resolution result = resolve(shell, arguments[i], false, false);
            Node *node = result.node;
            if (!node) { error("stat: cannot stat '%s': %s", arguments[i], reason(result)); continue; }
            const char *type = node->kind == DIRECTORY ? "directory" : node->kind == LINK ? "symbolic link" :
                               node->data.lines.count ? "regular file" : "regular empty file";
            emit(output, "%s: %s, size %" PRId64 ", inode %d, links %d, modified %d", arguments[i], type,
                 node_size(node), node->inode, link_count(node), node->modified);
        }
    } else if (strcmp(command, "rm") == 0 || strcmp(command, "rmdir") == 0) {
        bool directory_only = strcmp(command, "rmdir") == 0;
        for (int i = 0; i < opts.count; i++) {
            const char *path = opts.paths[i], *last = last_component(path), *problem = NULL;
            bool dot = strcmp(last, ".") == 0 || strcmp(last, "..") == 0;
            if (dot && !directory_only) {
                error("rm: refusing to remove '.' or '..' directory: skipping '%s'", path);
                continue;
            }
            if (dot) problem = "Invalid argument";
            else {
                Resolution result = resolve(shell, path, false, false);
                Node *node = result.node;
                if (!node) {
                    if (!directory_only && opts.flags['f'] && result.failure == MISSING) continue;
                    problem = reason(result);
                } else if (directory_only && node->kind != DIRECTORY) problem = "Not a directory";
                else if (!directory_only && node->kind == DIRECTORY && !opts.flags['r']) problem = "Is a directory";
                else if (descendant(shell, shell->current, node)) problem = "Device or resource busy";
                else if (directory_only && node->data.children.count) problem = "Directory not empty";
                else remove_node(shell, node);
            }
            if (problem) {
                if (directory_only) error("rmdir: failed to remove '%s': %s", path, problem);
                else error("rm: cannot remove '%s': %s", path, problem);
            }
        }
    } else if (strcmp(command, "mv") == 0 || strcmp(command, "cp") == 0) {
        const char *destination = opts.paths[opts.count - 1];
        if (opts.count > 2) {
            Resolution result = resolve(shell, destination, true, false);
            if (!result.node || result.node->kind != DIRECTORY) {
                error("%s: target '%s' is not a directory", command, destination);
                return;
            }
        }
        for (int i = 0; i + 1 < opts.count; i++) {
            if (strcmp(command, "mv") == 0) move_one(shell, opts.paths[i], destination);
            else copy_one(shell, opts.paths[i], destination, opts.flags['r']);
        }
    } else if (strcmp(command, "ln") == 0) {
        const char *path = arguments[2];
        Resolution result = resolve(shell, path, false, false);
        if (result.creation_parent) create_node(shell, result.creation_parent, result.creation_name, LINK, arguments[1]);
        else error("ln: failed to create symbolic link '%s': %s", path, result.node ? "File exists" : reason(result));
    } else if (strcmp(command, "readlink") == 0 || strcmp(command, "realpath") == 0) {
        bool canonical = strcmp(command, "realpath") == 0;
        Resolution result = resolve(shell, arguments[0], canonical, false);
        if (!result.node) error("%s: %s: %s", command, arguments[0], reason(result));
        else if (canonical) {
            char *path = absolute(shell, result.node);
            emit(output, "%s", path);
            free(path);
        } else if (result.node->kind == LINK) emit(output, "%s", result.node->data.target);
        else error("readlink: %s: Invalid argument", arguments[0]);
    } else if (strcmp(command, "find") == 0) find_nodes(shell, arguments, count, output);
    else if (strcmp(command, "du") == 0) disk_usage(shell, opts, output);
    else if (strcmp(command, "tree") == 0) tree(shell, opts, output);
    else if (strcmp(command, "cat") == 0 || strcmp(command, "wc") == 0 || strcmp(command, "head") == 0 ||
             strcmp(command, "tail") == 0 || strcmp(command, "grep") == 0 || strcmp(command, "sort") == 0 || strcmp(command, "uniq") == 0)
        text_command(shell, command, arguments, count, input, output);
    else error("%s: command not found", command);
}
static void process(Shell *shell, char *line) {
    shell->clock++;
    char *path = absolute(shell, shell->current);
    printf("%s$ %s\n", path, line);
    free(path);
    char *redirect = strstr(line, " >> ");
    bool append = redirect != NULL;
    if (!redirect) redirect = strstr(line, " > ");
    Node *redirect_file = NULL;
    if (redirect) {
        const char *destination = redirect + (append ? 4 : 3);
        *redirect = '\0';
        Resolution result = resolve(shell, destination, true, false);
        if (result.creation_parent) redirect_file = create_node(shell, result.creation_parent, result.creation_name, FILE_NODE, NULL);
        else if (!result.node) { error("sh: %s: %s", destination, reason(result)); return; }
        else if (result.node->kind != FILE_NODE) { error("sh: %s: Is a directory", destination); return; }
        else {
            redirect_file = result.node;
            if (!append) { Lines empty = {0}; write_file(shell, redirect_file, &empty, false); }
        }
    }
    char *commands[5];
    int count = 0;
    char *command = line;
    for (;;) {
        commands[count++] = command;
        char *separator = strstr(command, " | ");
        if (!separator) break;
        *separator = '\0';
        command = separator + 3;
    }
    Lines input = {0};
    for (int i = 0; i < count; i++) {
        Output output = {.terminal = i + 1 == count && !redirect_file};
        execute(shell, commands[i], &input, &output);
        clear_lines(&input);
        input = output.lines;
    }
    if (redirect_file && input.count) write_file(shell, redirect_file, &input, true);
    clear_lines(&input);
    for (size_t i = 0; i < shell->retired.count; i++) free_node(shell->retired.items[i]);
    shell->retired.count = 0;
}
int main(void) {
    Node *root = allocate(sizeof(*root));
    *root = (Node){.kind = DIRECTORY, .inode = 1, .parent = root, .name = copy_text("")};
    Shell shell = {.root = root, .current = root, .next_inode = 2};
    char line[202];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (strcmp(line, "exit") == 0) break;
        process(&shell, line);
    }
    free_node(root);
    free(shell.previous);
    free(shell.retired.items);
    return 0;
}
