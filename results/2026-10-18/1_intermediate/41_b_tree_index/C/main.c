#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

enum { MAX_PAGES = 752, MAX_ENTRIES = 500, MAX_PATH = 12 };

typedef struct { int key; char value[13]; } Entry;
typedef struct Node Node;
struct Node {
    int page, count, capacity, child_count, child_capacity;
    Entry *entries;
    Node **children;
};
typedef struct {
    int degree, splits, merges, borrows;
    Node *root, *pages[MAX_PAGES];
} Tree;
typedef struct { Entry entries[MAX_ENTRIES]; int count; } Entries;
typedef struct { Node *node, *path[MAX_PATH]; int position, depth; } Search;
typedef struct { int nodes, leaves, keys; } Statistics;
typedef struct { int writes, frees; } Changes;
typedef enum { UNSET, AT_KEY, BEGIN, END } CursorState;
typedef struct { CursorState state; int key; } Cursor;
typedef enum { VALID, BAD_COUNT, BAD_ORDER, BAD_RANGE, BAD_DEPTH } ViolationKind;
typedef struct {
    ViolationKind kind;
    const Node *node;
    char location[64];
    int low, high, minimum, index, depth, expected;
} Violation;
typedef struct { bool trace; char cases[256]; size_t length; } Deletion;
typedef struct { Tree *tree; char **tokens; int count, position, error; } Parser;
typedef struct { Tree *tree, *saved; Cursor cursor; bool trace; } Laboratory;
typedef enum {
    CREATE, LOAD, INSERT, BULKLOAD, DELETE, DELRANGE, GET, RANGE, COUNT, MIN, MAX,
    FLOOR, CEIL, RANK, SELECT, SEEK, NEXT, PREV, PRINT, PAGES, DUMP, HEIGHT, STATS,
    VERIFY, REBUILD, COMPACT, SAVE, RESTORE, TRACE
} Command;

static const char *const COMMANDS[] = {
    "CREATE", "LOAD", "INSERT", "BULKLOAD", "DELETE", "DELRANGE", "GET", "RANGE", "COUNT",
    "MIN", "MAX", "FLOOR", "CEIL", "RANK", "SELECT", "SEEK", "NEXT", "PREV", "PRINT",
    "PAGES", "DUMP", "HEIGHT", "STATS", "VERIFY", "REBUILD", "COMPACT", "SAVE", "RESTORE", "TRACE"
};

static void *allocate(size_t bytes) {
    void *result = calloc(1, bytes);
    if (!result) exit(EXIT_FAILURE);
    return result;
}

static void *resize(void *memory, size_t bytes) {
    void *result = realloc(memory, bytes);
    if (!result) exit(EXIT_FAILURE);
    return result;
}

static Entry entry(int key, const char *value) {
    Entry result = {.key = key};
    strcpy(result.value, value);
    return result;
}

static void insert_entry(Node *node, int at, Entry value) {
    if (node->count == node->capacity) {
        node->capacity = node->capacity ? node->capacity * 2 : 8;
        node->entries = resize(node->entries, (size_t)node->capacity * sizeof(Entry));
    }
    memmove(node->entries + at + 1, node->entries + at, (size_t)(node->count - at) * sizeof(Entry));
    node->entries[at] = value;
    ++node->count;
}

static Entry remove_entry(Node *node, int at) {
    Entry result = node->entries[at];
    --node->count;
    memmove(node->entries + at, node->entries + at + 1, (size_t)(node->count - at) * sizeof(Entry));
    return result;
}

static void insert_child(Node *node, int at, Node *child) {
    if (node->child_count == node->child_capacity) {
        node->child_capacity = node->child_capacity ? node->child_capacity * 2 : 8;
        node->children = resize(node->children, (size_t)node->child_capacity * sizeof(Node *));
    }
    memmove(node->children + at + 1, node->children + at, (size_t)(node->child_count - at) * sizeof(Node *));
    node->children[at] = child;
    ++node->child_count;
}

static Node *remove_child(Node *node, int at) {
    Node *result = node->children[at];
    --node->child_count;
    memmove(node->children + at, node->children + at + 1, (size_t)(node->child_count - at) * sizeof(Node *));
    return result;
}

static Node *new_node(Tree *tree) {
    int page = 0;
    while (tree->pages[page]) ++page;
    Node *node = allocate(sizeof(Node));
    node->page = page;
    tree->pages[page] = node;
    return node;
}

static void release_node(Tree *tree, Node *node) {
    tree->pages[node->page] = NULL;
    free(node->entries);
    free(node->children);
    free(node);
}

static Tree *new_tree(int degree) {
    Tree *tree = allocate(sizeof(Tree));
    tree->degree = degree;
    tree->root = new_node(tree);
    return tree;
}

static void release_tree(Tree *tree) {
    if (!tree) return;
    for (int page = 0; page < MAX_PAGES; ++page)
        if (tree->pages[page]) release_node(tree, tree->pages[page]);
    free(tree);
}

static Tree *copy_tree(const Tree *source) {
    Tree *result = allocate(sizeof(Tree));
    result->degree = source->degree;
    result->splits = source->splits;
    result->merges = source->merges;
    result->borrows = source->borrows;
    for (int page = 0; page < MAX_PAGES; ++page) {
        const Node *old = source->pages[page];
        if (!old) continue;
        Node *node = allocate(sizeof(Node));
        node->page = page;
        for (int i = 0; i < old->count; ++i) insert_entry(node, node->count, old->entries[i]);
        result->pages[page] = node;
    }
    for (int page = 0; page < MAX_PAGES; ++page) {
        const Node *old = source->pages[page];
        if (!old) continue;
        Node *node = result->pages[page];
        for (int i = 0; i < old->child_count; ++i)
            insert_child(node, node->child_count, result->pages[old->children[i]->page]);
    }
    result->root = result->pages[source->root->page];
    return result;
}

static bool same_content(const Node *a, const Node *b) {
    if (a->count != b->count || a->child_count != b->child_count) return false;
    for (int i = 0; i < a->count; ++i)
        if (a->entries[i].key != b->entries[i].key || strcmp(a->entries[i].value, b->entries[i].value)) return false;
    for (int i = 0; i < a->child_count; ++i)
        if (a->children[i]->page != b->children[i]->page) return false;
    return true;
}

static Changes changes(const Tree *before, const Tree *after) {
    Changes result = {0};
    for (int page = 0; page < MAX_PAGES; ++page) {
        const Node *old = before->pages[page], *now = after->pages[page];
        if (now && (!old || !same_content(old, now))) ++result.writes;
        if (old && !now) ++result.frees;
    }
    return result;
}

static Statistics statistics(const Tree *tree) {
    Statistics result = {0};
    for (int page = 0; page < MAX_PAGES; ++page) {
        const Node *node = tree->pages[page];
        if (!node) continue;
        ++result.nodes;
        result.keys += node->count;
        if (!node->child_count) ++result.leaves;
    }
    return result;
}

static int height(const Tree *tree) {
    int result = 0;
    const Node *node = tree->root;
    while (node->child_count) { node = node->children[0]; ++result; }
    return result;
}

static void notation(const Node *node) {
    putchar('[');
    for (int i = 0; i < node->count; ++i) printf("%s%d", i ? " " : "", node->entries[i].key);
    putchar(']');
}

static bool inspect_node(const Tree *tree, const Node *node, const char *location,
                         int depth, int low, int high, int *reference, Violation *result) {
    int minimum = node == tree->root ? (node->child_count ? 1 : 0) : tree->degree - 1;
    result->kind = VALID;
    result->minimum = minimum;
    if (node->count < minimum || node->count > 2 * tree->degree - 1) result->kind = BAD_COUNT;
    for (int i = 0; result->kind == VALID && i + 1 < node->count; ++i) {
        if (node->entries[i].key >= node->entries[i + 1].key) { result->kind = BAD_ORDER; result->index = i; }
    }
    for (int i = 0; result->kind == VALID && i < node->count; ++i) {
        if (node->entries[i].key <= low || node->entries[i].key >= high) { result->kind = BAD_RANGE; result->index = i; }
    }
    if (result->kind == VALID && !node->child_count) {
        if (*reference < 0) *reference = depth;
        else if (depth != *reference) result->kind = BAD_DEPTH;
    }
    if (result->kind != VALID) {
        result->node = node;
        strcpy(result->location, location);
        result->depth = depth; result->expected = *reference;
        result->low = low; result->high = high;
        return false;
    }
    for (int j = 0; j < node->child_count; ++j) {
        char child_location[64];
        snprintf(child_location, sizeof(child_location), "%s.%d", location, j);
        int child_low = j ? node->entries[j - 1].key : low;
        int child_high = j < node->count ? node->entries[j].key : high;
        if (!inspect_node(tree, node->children[j], child_location, depth + 1, child_low, child_high, reference, result)) return false;
    }
    return true;
}

static Violation inspect(const Tree *tree) {
    Violation result = {0};
    int reference = -1;
    inspect_node(tree, tree->root, "root", 0, INT_MIN, INT_MAX, &reference, &result);
    return result;
}

static const char *status(const Tree *tree) { return inspect(tree).kind == VALID ? "OK" : "DAMAGED"; }

static int position(const Node *node, int key) {
    int at = 0;
    while (at < node->count && node->entries[at].key < key) ++at;
    return at;
}

static Search search(const Tree *tree, int key) {
    Search result = {0};
    Node *node = tree->root;
    while (true) {
        result.path[result.depth++] = node;
        int at = position(node, key);
        if (at < node->count && node->entries[at].key == key) {
            result.node = node; result.position = at;
            return result;
        }
        if (!node->child_count) return result;
        node = node->children[at];
    }
}

static void inorder(const Node *node, Entries *result) {
    for (int i = 0; i <= node->count; ++i) {
        if (node->child_count) inorder(node->children[i], result);
        if (i < node->count) result->entries[result->count++] = node->entries[i];
    }
}

static void scan(const Node *node, int low, int high, Entries *result, int *visited) {
    ++*visited;
    for (int i = 0; i <= node->count; ++i) {
        if (node->child_count && (!i || node->entries[i - 1].key < high) &&
            (i == node->count || node->entries[i].key > low)) scan(node->children[i], low, high, result, visited);
        if (i < node->count && node->entries[i].key >= low && node->entries[i].key <= high)
            result->entries[result->count++] = node->entries[i];
    }
}

static void split_child(Tree *tree, Node *parent, int at, bool trace) {
    int t = tree->degree;
    Node *left = parent->children[at], *right = new_node(tree);
    Entry middle = left->entries[t - 1];
    if (trace) {
        printf("STEP split page=%d keys=", left->page); notation(left);
        printf(" up=%d new=%d\n", middle.key, right->page);
    }
    for (int i = t; i < left->count; ++i) insert_entry(right, right->count, left->entries[i]);
    for (int i = t; i < left->child_count; ++i) insert_child(right, right->child_count, left->children[i]);
    left->count = t - 1;
    if (left->child_count) left->child_count = t;
    insert_entry(parent, at, middle);
    insert_child(parent, at + 1, right);
    ++tree->splits;
}

static bool put_entry(Tree *tree, Entry value, bool trace) {
    Search found = search(tree, value.key);
    if (found.node) { found.node->entries[found.position] = value; return false; }
    if (tree->root->count == 2 * tree->degree - 1) {
        Node *old = tree->root, *root = new_node(tree);
        insert_child(root, 0, old);
        tree->root = root;
        if (trace) printf("STEP grow page=%d\n", root->page);
        split_child(tree, root, 0, trace);
    }
    Node *node = tree->root;
    while (node->child_count) {
        int at = position(node, value.key);
        if (node->children[at]->count == 2 * tree->degree - 1) {
            split_child(tree, node, at, trace);
            if (value.key > node->entries[at].key) ++at;
        }
        node = node->children[at];
    }
    insert_entry(node, position(node, value.key), value);
    if (trace) { printf("STEP place page=%d keys=", node->page); notation(node); putchar('\n'); }
    return true;
}

static void add_case(Deletion *operation, const char *name) {
    if (!operation) return;
    if (operation->length) operation->cases[operation->length++] = ',';
    strcpy(operation->cases + operation->length, name);
    operation->length += strlen(name);
}

static Node *merge_children(Tree *tree, Node *parent, int at, const char *name, Deletion *operation) {
    Node *left = parent->children[at], *right = parent->children[at + 1];
    int parent_page = parent->page, right_page = right->page;
    bool shrink = parent == tree->root && parent->count == 1;
    insert_entry(left, left->count, parent->entries[at]);
    for (int i = 0; i < right->count; ++i) insert_entry(left, left->count, right->entries[i]);
    for (int i = 0; i < right->child_count; ++i) insert_child(left, left->child_count, right->children[i]);
    remove_entry(parent, at); remove_child(parent, at + 1);
    release_node(tree, right);
    ++tree->merges;
    if (shrink) { tree->root = left; release_node(tree, parent); }
    if (operation && operation->trace) {
        printf("STEP %s page=%d merge=%d+%d keys=", name, parent_page, left->page, right_page);
        notation(left); putchar('\n');
        if (shrink) printf("STEP shrink page=%d\n", left->page);
    }
    return left;
}

static Entry extreme(Node *node, bool maximum) {
    while (node->child_count) node = node->children[maximum ? node->child_count - 1 : 0];
    return node->entries[maximum ? node->count - 1 : 0];
}

static void delete_key(Tree *tree, Node *node, int key, Deletion *operation) {
    int at = position(node, key), t = tree->degree;
    bool trace = operation && operation->trace;
    if (at < node->count && node->entries[at].key == key) {
        if (!node->child_count) {
            add_case(operation, "1"); remove_entry(node, at);
            if (trace) { printf("STEP 1 page=%d keys=", node->page); notation(node); putchar('\n'); }
            return;
        }
        Node *left = node->children[at], *right = node->children[at + 1];
        if (left->count >= t) {
            Entry predecessor = extreme(left, true);
            add_case(operation, "2a");
            if (trace) printf("STEP 2a page=%d pred=%d\n", node->page, predecessor.key);
            delete_key(tree, left, predecessor.key, operation);
            node->entries[at] = predecessor;
        } else if (right->count >= t) {
            Entry successor = extreme(right, false);
            add_case(operation, "2b");
            if (trace) printf("STEP 2b page=%d succ=%d\n", node->page, successor.key);
            delete_key(tree, right, successor.key, operation);
            node->entries[at] = successor;
        } else {
            add_case(operation, "2c");
            Node *merged = merge_children(tree, node, at, "2c", operation);
            delete_key(tree, merged, key, operation);
        }
        return;
    }
    Node *child = node->children[at];
    if (child->count == t - 1) {
        Node *left = at ? node->children[at - 1] : NULL;
        Node *right = at < node->count ? node->children[at + 1] : NULL;
        if (left && left->count >= t) {
            add_case(operation, "3a-left");
            insert_entry(child, 0, node->entries[at - 1]);
            node->entries[at - 1] = remove_entry(left, left->count - 1);
            if (left->child_count) insert_child(child, 0, remove_child(left, left->child_count - 1));
            ++tree->borrows;
            if (trace) {
                printf("STEP 3a-left page=%d child=%d from=%d keys=", node->page, child->page, left->page);
                notation(child); putchar('\n');
            }
        } else if (right && right->count >= t) {
            add_case(operation, "3a-right");
            insert_entry(child, child->count, node->entries[at]);
            node->entries[at] = remove_entry(right, 0);
            if (right->child_count) insert_child(child, child->child_count, remove_child(right, 0));
            ++tree->borrows;
            if (trace) {
                printf("STEP 3a-right page=%d child=%d from=%d keys=", node->page, child->page, right->page);
                notation(child); putchar('\n');
            }
        } else if (left) {
            add_case(operation, "3b-left");
            child = merge_children(tree, node, at - 1, "3b-left", operation);
        } else {
            add_case(operation, "3b-right");
            child = merge_children(tree, node, at, "3b-right", operation);
        }
    }
    delete_key(tree, child, key, operation);
}

static Node *parse_node(Parser *parser) {
    if (parser->position == parser->count || strcmp(parser->tokens[parser->position], "(")) {
        parser->error = parser->position + 1;
        return NULL;
    }
    ++parser->position;
    Node *node = new_node(parser->tree);
    if (parser->position == parser->count) { parser->error = parser->position + 1; return NULL; }
    bool internal = !strcmp(parser->tokens[parser->position], "(");
    if (internal) {
        Node *child = parse_node(parser);
        if (!child) return NULL;
        insert_child(node, node->child_count, child);
    }
    while (parser->position < parser->count && strcmp(parser->tokens[parser->position], ")")) {
        const char *token = parser->tokens[parser->position];
        if (!strcmp(token, "(")) { parser->error = parser->position + 1; return NULL; }
        insert_entry(node, node->count, entry(atoi(token), strchr(token, '=') + 1));
        ++parser->position;
        if (internal) {
            Node *child = parse_node(parser);
            if (!child) return NULL;
            insert_child(node, node->child_count, child);
        }
    }
    if (parser->position == parser->count) { parser->error = parser->position + 1; return NULL; }
    ++parser->position;
    return node;
}

static void number_preorder(Tree *tree, Node *node, int *next) {
    node->page = *next;
    tree->pages[(*next)++] = node;
    for (int i = 0; i < node->child_count; ++i) number_preorder(tree, node->children[i], next);
}

static Tree *compact(const Tree *source) {
    Entries entries = {0};
    inorder(source->root, &entries);
    Tree *tree = allocate(sizeof(Tree));
    tree->degree = source->degree;
    Node *candidates[MAX_PAGES];
    int child_count = 0;
    while (true) {
        int groups = (entries.count + 2 * tree->degree) / (2 * tree->degree);
        int keys = entries.count - groups + 1, size = keys / groups, remainder = keys % groups;
        Entries separators = {0};
        Node *level[MAX_PAGES];
        int at = 0, child = 0;
        for (int i = 0; i < groups; ++i) {
            Node *node = new_node(tree);
            int count = size + (i < remainder);
            for (int j = 0; j < count; ++j) insert_entry(node, node->count, entries.entries[at++]);
            if (child_count) for (int j = 0; j <= count; ++j) insert_child(node, node->child_count, candidates[child++]);
            level[i] = node;
            if (i + 1 < groups) separators.entries[separators.count++] = entries.entries[at++];
        }
        if (groups == 1) { tree->root = level[0]; break; }
        entries = separators;
        memcpy(candidates, level, (size_t)groups * sizeof(Node *));
        child_count = groups;
    }
    memset(tree->pages, 0, sizeof(tree->pages));
    int next = 0;
    number_preorder(tree, tree->root, &next);
    return tree;
}

static void dump_node(const Node *node) {
    putchar('(');
    for (int i = 0; i <= node->count; ++i) {
        if (node->child_count) { putchar(' '); dump_node(node->children[i]); }
        if (i < node->count) printf(" %d=%s", node->entries[i].key, node->entries[i].value);
    }
    printf(" )");
}

static void print_levels(const Tree *tree) {
    Node *queue[MAX_PAGES];
    int begin = 0, end = 1, depth = 0;
    queue[0] = tree->root;
    while (begin < end) {
        int next = end;
        printf("LEVEL %d", depth++);
        while (begin < next) {
            Node *node = queue[begin++];
            putchar(' '); notation(node);
            for (int i = 0; i < node->child_count; ++i) queue[end++] = node->children[i];
        }
        putchar('\n');
    }
}

static void print_violation(const Tree *tree, Violation violation) {
    static const char *const names[] = {"", "COUNT", "ORDER", "RANGE", "DEPTH"};
    if (violation.kind == VALID) { puts("VERIFY OK"); return; }
    const Node *node = violation.node;
    printf("VERIFY FAIL %s at=%s node=", names[violation.kind], violation.location); notation(node);
    switch (violation.kind) {
        case BAD_COUNT: printf(" keys=%d allowed=%d..%d", node->count, violation.minimum, 2 * tree->degree - 1); break;
        case BAD_ORDER: printf(" %d>=%d", node->entries[violation.index].key, node->entries[violation.index + 1].key); break;
        case BAD_RANGE:
            printf(" key=%d low=", node->entries[violation.index].key);
            if (violation.low == INT_MIN) printf("-inf"); else printf("%d", violation.low);
            printf(" high=");
            if (violation.high == INT_MAX) printf("+inf"); else printf("%d", violation.high);
            break;
        case BAD_DEPTH: printf(" depth=%d expected=%d", violation.depth, violation.expected); break;
        case VALID: break;
    }
    putchar('\n');
}

static bool needs_valid(Command command) {
    switch (command) {
        case INSERT: case BULKLOAD: case DELETE: case DELRANGE: case RANGE: case COUNT:
        case MIN: case MAX: case FLOOR: case CEIL: case RANK: case SELECT: case SEEK:
        case NEXT: case PREV: case HEIGHT: case COMPACT: return true;
        default: return false;
    }
}

static void process(Laboratory *lab, Command command, char **args, int count) {
    if (command == TRACE) {
        lab->trace = !strcmp(args[0], "ON");
        printf("TRACE %s\n", args[0]);
        return;
    }
    if (command == CREATE || command == LOAD) {
        int degree = atoi(args[0]);
        if (degree < 2 || degree > 5) { printf("ERROR BAD DEGREE %d\n", degree); return; }
        Tree *replacement;
        if (command == CREATE) replacement = new_tree(degree);
        else {
            replacement = allocate(sizeof(Tree));
            replacement->degree = degree;
            Parser parser = {.tree = replacement, .tokens = args + 1, .count = count - 1};
            replacement->root = parse_node(&parser);
            if (!parser.error && parser.position != parser.count) parser.error = parser.position + 1;
            if (parser.error) {
                printf("ERROR SYNTAX %d\n", parser.error); release_tree(replacement); return;
            }
        }
        release_tree(lab->tree); lab->tree = replacement;
        lab->cursor = (Cursor){.state = UNSET};
        if (command == CREATE) printf("CREATE t=%d\n", degree);
        else {
            Statistics stats = statistics(replacement);
            printf("LOAD t=%d nodes=%d keys=%d %s\n", degree, stats.nodes, stats.keys, status(replacement));
        }
        return;
    }
    Tree *tree = lab->tree;
    if (!tree) { puts("ERROR NO INDEX"); return; }
    Violation violation = inspect(tree);
    if (needs_valid(command) && violation.kind != VALID) { puts("ERROR DAMAGED"); return; }
    int first = count ? atoi(args[0]) : 0;
    int second = command == DELRANGE || command == RANGE || command == COUNT ? atoi(args[1]) : 0;
    if ((command == DELRANGE || command == RANGE || command == COUNT) && first > second) {
        printf("ERROR BAD RANGE %d %d\n", first, second); return;
    }
    Statistics stats = statistics(tree);
    if (command == SELECT && (first < 1 || first > stats.keys)) { printf("ERROR BAD POSITION %d\n", first); return; }
    if ((command == NEXT || command == PREV) && lab->cursor.state == UNSET) { puts("ERROR NO CURSOR"); return; }
    if (command == RESTORE && !lab->saved) { puts("ERROR NO SAVE"); return; }

    if (command == INSERT || command == BULKLOAD || command == DELETE || command == DELRANGE) {
        Search found = {0};
        if (command == INSERT || command == DELETE) found = search(tree, first);
        if (command == DELETE && !found.node) { printf("DELETE %d NOT FOUND\n", first); return; }
        Tree *before = copy_tree(tree);
        int old_splits = tree->splits, old_merges = tree->merges, old_borrows = tree->borrows;
        if (command == INSERT) {
            Entry previous = {0};
            if (found.node) previous = found.node->entries[found.position];
            bool added = put_entry(tree, entry(first, args[1]), lab->trace);
            Changes delta = changes(before, tree);
            if (added) printf("INSERT %d NEW splits=%d height=%d writes=%d\n", first, tree->splits - old_splits, height(tree), delta.writes);
            else printf("INSERT %d UPDATED old=%s writes=%d\n", first, previous.value, delta.writes);
        } else if (command == BULKLOAD) {
            int added = 0;
            for (int i = 0; i < count; i += 2) added += put_entry(tree, entry(atoi(args[i]), args[i + 1]), false);
            Changes delta = changes(before, tree);
            printf("BULKLOAD pairs=%d new=%d updated=%d splits=%d height=%d writes=%d\n",
                   count / 2, added, count / 2 - added, tree->splits - old_splits, height(tree), delta.writes);
        } else if (command == DELETE) {
            Entry previous = found.node->entries[found.position];
            Deletion operation = {.trace = lab->trace};
            delete_key(tree, tree->root, first, &operation);
            Changes delta = changes(before, tree);
            printf("DELETE %d REMOVED value=%s cases=%s height=%d writes=%d frees=%d\n",
                   first, previous.value, operation.cases, height(tree), delta.writes, delta.frees);
        } else {
            Entries selected = {0};
            int visited = 0;
            scan(tree->root, first, second, &selected, &visited);
            for (int i = 0; i < selected.count; ++i) delete_key(tree, tree->root, selected.entries[i].key, NULL);
            Changes delta = changes(before, tree);
            printf("DELRANGE %d %d removed=%d merges=%d borrows=%d height=%d writes=%d frees=%d\n",
                   first, second, selected.count, tree->merges - old_merges, tree->borrows - old_borrows,
                   height(tree), delta.writes, delta.frees);
        }
        release_tree(before);
        return;
    }
    if (command == GET) {
        Search found = search(tree, first);
        printf("GET %d ", first);
        if (found.node) printf("FOUND value=%s path=", found.node->entries[found.position].value);
        else printf("NOT FOUND path=");
        for (int i = 0; i < found.depth; ++i) { if (i) printf(" -> "); notation(found.path[i]); }
        putchar('\n'); return;
    }
    if (command == RANGE || command == COUNT) {
        Entries result = {0};
        int visited = 0;
        scan(tree->root, first, second, &result, &visited);
        printf("%s %d %d count=%d visited=%d", COMMANDS[command], first, second, result.count, visited);
        if (command == RANGE) for (int i = 0; i < result.count; ++i) printf(" %d=%s", result.entries[i].key, result.entries[i].value);
        putchar('\n'); return;
    }
    if (command >= MIN && command <= PREV) {
        Entries all = {0}; inorder(tree->root, &all);
        const char *name = COMMANDS[command];
        int selected = -1;
        if (command == MIN || command == MAX) {
            if (!all.count) { printf("%s EMPTY\n", name); return; }
            selected = command == MIN ? 0 : all.count - 1;
        } else if (command == FLOOR || command == CEIL || command == SEEK) {
            for (int i = 0; i < all.count; ++i) {
                if (command == FLOOR) { if (all.entries[i].key <= first) selected = i; }
                else if (all.entries[i].key >= first) { selected = i; break; }
            }
        } else if (command == RANK) {
            int rank = 0; while (rank < all.count && all.entries[rank].key < first) ++rank;
            printf("RANK %d %d\n", first, rank); return;
        } else if (command == SELECT) selected = first - 1;
        else if (command == NEXT) {
            for (int i = 0; i < all.count; ++i)
                if (lab->cursor.state == BEGIN || (lab->cursor.state == AT_KEY && all.entries[i].key > lab->cursor.key)) { selected = i; break; }
        } else {
            for (int i = all.count - 1; i >= 0; --i)
                if (lab->cursor.state == END || (lab->cursor.state == AT_KEY && all.entries[i].key < lab->cursor.key)) { selected = i; break; }
        }
        if (command == SEEK || command == NEXT || command == PREV) {
            lab->cursor.state = selected >= 0 ? AT_KEY : command == PREV ? BEGIN : END;
            if (selected >= 0) lab->cursor.key = all.entries[selected].key;
        }
        printf("%s", name);
        if (command == FLOOR || command == CEIL || command == SELECT || command == SEEK) printf(" %d", first);
        if (selected >= 0) printf(" %d=%s\n", all.entries[selected].key, all.entries[selected].value);
        else printf(" %s\n", command == PREV ? "BEGIN" : command == NEXT || command == SEEK ? "END" : "NONE");
        return;
    }
    switch (command) {
        case PRINT: print_levels(tree); break;
        case PAGES:
            for (int page = 0; page < MAX_PAGES; ++page) {
                Node *node = tree->pages[page];
                if (!node) continue;
                printf("PAGE %d ", page); notation(node); printf(" kids=");
                if (!node->child_count) putchar('-');
                for (int i = 0; i < node->child_count; ++i) printf("%s%d", i ? "," : "", node->children[i]->page);
                putchar('\n');
            }
            break;
        case DUMP: printf("DUMP %d ", tree->degree); dump_node(tree->root); putchar('\n'); break;
        case HEIGHT: printf("HEIGHT %d\n", height(tree)); break;
        case STATS:
            printf("STATS t=%d nodes=%d leaves=%d keys=%d fill=%d%% splits=%d merges=%d borrows=%d\n",
                   tree->degree, stats.nodes, stats.leaves, stats.keys, 100 * stats.keys / ((2 * tree->degree - 1) * stats.nodes),
                   tree->splits, tree->merges, tree->borrows);
            break;
        case VERIFY: print_violation(tree, violation); break;
        case REBUILD: {
            Entries all = {0}; inorder(tree->root, &all);
            Tree *replacement = new_tree(tree->degree);
            for (int i = 0; i < all.count; ++i) put_entry(replacement, all.entries[i], false);
            release_tree(tree); lab->tree = replacement;
            Statistics now = statistics(replacement);
            printf("REBUILD entries=%d keys=%d nodes=%d splits=%d height=%d\n", all.count, now.keys, now.nodes, replacement->splits, height(replacement));
            break;
        }
        case COMPACT: {
            Tree *replacement = compact(tree);
            release_tree(tree); lab->tree = replacement;
            printf("COMPACT nodes=%d->%d height=%d\n", stats.nodes, statistics(replacement).nodes, height(replacement));
            break;
        }
        case SAVE:
            release_tree(lab->saved); lab->saved = copy_tree(tree);
            printf("SAVE nodes=%d keys=%d %s\n", stats.nodes, stats.keys, status(tree));
            break;
        case RESTORE:
            release_tree(tree); lab->tree = copy_tree(lab->saved);
            stats = statistics(lab->tree);
            printf("RESTORE nodes=%d keys=%d %s\n", stats.nodes, stats.keys, status(lab->tree));
            break;
        default: break;
    }
}

int main(void) {
    char line[4002];
    if (!fgets(line, sizeof(line), stdin)) return 0;
    int commands = atoi(line);
    Laboratory laboratory = {0};
    for (int i = 0; i < commands; ++i) {
        if (!fgets(line, sizeof(line), stdin)) break;
        line[strcspn(line, "\r\n")] = '\0';
        char *words[1503];
        int count = 0;
        for (char *word = strtok(line, " "); word; word = strtok(NULL, " ")) words[count++] = word;
        int command = 0;
        while (strcmp(words[0], COMMANDS[command])) ++command;
        process(&laboratory, (Command)command, words + 1, count - 1);
    }
    release_tree(laboratory.tree);
    release_tree(laboratory.saved);
    return 0;
}
