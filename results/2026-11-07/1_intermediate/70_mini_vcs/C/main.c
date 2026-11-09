#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define APPEND(a, n, v) do { (a) = resize((a), ((n) + 1) * sizeof(*(a))); (a)[(n)++] = (v); } while (0)
typedef struct {
    char *data;
    size_t length, capacity;
} Buffer;
typedef struct {
    char *path, *text;
} File;
typedef struct {
    File *items;
    size_t count;
} Tree;
typedef struct {
    char **items;
    size_t count;
} Strings;
typedef struct Commit Commit;
struct Commit {
    char *id, *message;
    size_t sequence, parent_count;
    Commit *parents[2];
    Tree tree;
    bool alive;
};
typedef struct {
    char *name;
    Commit *commit;
} Ref;
typedef struct {
    Ref *items;
    size_t count;
} Refs;
typedef struct {
    Tree tree, contents;
    Strings conflicts;
} Merge;
typedef struct {
    char *label;
    Commit *base;
    Tree tree;
} Stash;
typedef struct {
    Commit *original;
    Tree tree;
    bool pick;
} Replay;
static Commit **commits, *detached, *target;
static size_t commit_count;
static Refs branches, tags;
static Tree working, index_tree;
static Strings conflicts, ignores;
static Stash *stashes;
static size_t stash_count;
static char *branch = "main", *operation;
static jmp_buf failure;
static char *error_reason;

static void *allocate(size_t size) {
    void *p = calloc(1, size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void *resize(void *p, size_t size) {
    p = realloc(p, size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static char *slice(const char *s, size_t n) {
    char *out = allocate(n + 1);
    memcpy(out, s, n);
    return out;
}

static char *copy(const char *s) {
    return slice(s, strlen(s));
}

static char *format(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    char *out = allocate((size_t)n + 1);
    vsnprintf(out, (size_t)n + 1, pattern, saved);
    va_end(saved);
    return out;
}

static void error(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    error_reason = allocate((size_t)n + 1);
    vsnprintf(error_reason, (size_t)n + 1, pattern, saved);
    va_end(saved);
    longjmp(failure, 1);
}

static void append(Buffer *b, const char *s) {
    size_t n = strlen(s);
    if (b->length + n + 1 > b->capacity) {
        b->capacity = (b->length + n + 1) * 2;
        b->data = resize(b->data, b->capacity);
    }
    memcpy(b->data + b->length, s, n);
    b->length += n;
    b->data[b->length] = 0;
}

static char *finish(Buffer *b) {
    return b->data ? b->data : copy("");
}

static int string_compare(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static bool contains(Strings set, const char *s) {
    for (size_t i = 0; i < set.count; i++) if (!strcmp(set.items[i], s)) return true;
    return false;
}

static void set_add(Strings *set, char *s) {
    if (!contains(*set, s)) APPEND(set->items, set->count, s);
}

static void set_remove(Strings *set, const char *s) {
    size_t next = 0;
    for (size_t i = 0; i < set->count; i++) if (strcmp(set->items[i], s)) set->items[next++] = set->items[i];
    set->count = next;
}

static Strings ordered(Strings set) {
    if (set.count) qsort(set.items, set.count, sizeof(*set.items), string_compare);
    return set;
}

static char *get(Tree tree, const char *path) {
    for (size_t i = 0; i < tree.count; i++) if (!strcmp(tree.items[i].path, path)) return tree.items[i].text;
    return NULL;
}

static void put(Tree *tree, char *path, char *text) {
    for (size_t i = 0; i < tree->count; i++) if (!strcmp(tree->items[i].path, path)) {
        tree->items[i].text = text;
        return;
    }
    APPEND(tree->items, tree->count, ((File){path, text}));
}

static void remove_file(Tree *tree, const char *path) {
    size_t next = 0;
    for (size_t i = 0; i < tree->count; i++) if (strcmp(tree->items[i].path, path)) tree->items[next++] = tree->items[i];
    tree->count = next;
}

static Tree clone(Tree tree) {
    Tree out = {.count = tree.count};
    out.items = allocate(out.count * sizeof(*out.items));
    if (out.count) memcpy(out.items, tree.items, out.count * sizeof(*out.items));
    return out;
}

static Strings keys(Tree tree) {
    Strings out = {0};
    for (size_t i = 0; i < tree.count; i++) APPEND(out.items, out.count, tree.items[i].path);
    return ordered(out);
}

static Strings paths(Tree a, Tree b) {
    Strings out = keys(a);
    for (size_t i = 0; i < b.count; i++) set_add(&out, b.items[i].path);
    return ordered(out);
}

static bool agree(Tree a, Tree b, const char *path) {
    char *x = get(a, path), *y = get(b, path);
    return (!x && !y) || (x && y && !strcmp(x, y));
}

static Strings differences(Tree a, Tree b) {
    Strings all = paths(a, b), out = {0};
    for (size_t i = 0; i < all.count; i++) if (!agree(a, b, all.items[i])) APPEND(out.items, out.count, all.items[i]);
    return out;
}

static bool equal(Tree a, Tree b) {
    if (a.count != b.count) return false;
    for (size_t i = 0; i < a.count; i++) if (!agree(a, b, a.items[i].path)) return false;
    return true;
}

static void match(Tree *destination, Tree source, char *path) {
    char *text = get(source, path);
    if (text) put(destination, path, text);
    else remove_file(destination, path);
}

static int ref_compare(const void *a, const void *b) {
    return strcmp(((const Ref *)a)->name, ((const Ref *)b)->name);
}

static Commit *ref_get(Refs refs, const char *name) {
    for (size_t i = 0; i < refs.count; i++) if (!strcmp(refs.items[i].name, name)) return refs.items[i].commit;
    return NULL;
}

static void ref_put(Refs *refs, char *name, Commit *commit) {
    for (size_t i = 0; i < refs->count; i++) if (!strcmp(refs->items[i].name, name)) {
        refs->items[i].commit = commit;
        return;
    }
    APPEND(refs->items, refs->count, ((Ref){name, commit}));
    qsort(refs->items, refs->count, sizeof(*refs->items), ref_compare);
}

static void ref_remove(Refs *refs, const char *name) {
    size_t next = 0;
    for (size_t i = 0; i < refs->count; i++) if (strcmp(refs->items[i].name, name)) refs->items[next++] = refs->items[i];
    refs->count = next;
}

static Commit *head(void) {
    return branch ? ref_get(branches, branch) : detached;
}

static void move_head(Commit *commit) {
    if (branch) ref_put(&branches, branch, commit);
    else detached = commit;
}

static Commit *create(Commit **parents, size_t count, Tree tree, char *message) {
    Buffer text = {0};
    append(&text, format("commit %zu\n", commit_count));
    for (size_t i = 0; i < count; i++) append(&text, format("parent %s\n", parents[i]->id));
    Strings sorted = keys(tree);
    for (size_t i = 0; i < sorted.count; i++) append(&text, format("file %s %s\n", sorted.items[i], get(tree, sorted.items[i])));
    append(&text, format("message %s\n", message));
    uint64_t hash = 0;
    for (size_t i = 0; i < text.length; i++) hash = (hash * 131 + (unsigned char)text.data[i]) % 2147483647;
    Commit *commit = allocate(sizeof(*commit));
    commit->id = format("%08llx", (unsigned long long)hash);
    commit->sequence = commit_count;
    commit->parent_count = count;
    for (size_t i = 0; i < count; i++) commit->parents[i] = parents[i];
    commit->tree = clone(tree);
    commit->message = message;
    commit->alive = true;
    APPEND(commits, commit_count, commit);
    return commit;
}

static void record(Commit **parents, size_t count, Tree tree, char *message) {
    Commit *commit = create(parents, count, tree, message);
    Tree before = parents[0]->tree;
    int added = 0, modified = 0, deleted = 0;
    Strings changed = differences(before, tree);
    for (size_t i = 0; i < changed.count; i++) {
        if (!get(before, changed.items[i])) added++;
        else if (!get(tree, changed.items[i])) deleted++;
        else modified++;
    }
    move_head(commit);
    printf("[%s %s] %s (%d added, %d modified, %d deleted)\n", branch ? branch : "detached HEAD", commit->id, message, added, modified, deleted);
}

static Commit *resolve(const char *revision) {
    const char *tilde = strchr(revision, '~');
    char *anchor = tilde ? slice(revision, (size_t)(tilde - revision)) : copy(revision);
    Commit *commit = !strcmp(anchor, "HEAD") ? head() : ref_get(branches, anchor);
    if (!commit) commit = ref_get(tags, anchor);
    if (!commit) for (size_t i = 0; i < commit_count; i++) if (commits[i]->alive && !strcmp(commits[i]->id, anchor)) commit = commits[i];
    int steps = tilde ? atoi(tilde + 1) : 0;
    while (commit && steps-- > 0) commit = commit->parent_count ? commit->parents[0] : NULL;
    if (!commit) error("error: unknown revision '%s'", revision);
    return commit;
}

static int *distances(Commit *start) {
    int *result = allocate(commit_count * sizeof(*result));
    for (size_t i = 0; i < commit_count; i++) result[i] = -1;
    Commit **queue = NULL;
    size_t count = 0, at = 0;
    APPEND(queue, count, start);
    result[start->sequence] = 0;
    while (at < count) {
        Commit *commit = queue[at++];
        for (size_t i = 0; i < commit->parent_count; i++) {
            Commit *parent = commit->parents[i];
            if (result[parent->sequence] < 0) {
                result[parent->sequence] = result[commit->sequence] + 1;
                APPEND(queue, count, parent);
            }
        }
    }
    free(queue);
    return result;
}

static bool ancestor(Commit *a, Commit *b) {
    int *d = distances(b);
    bool result = d[a->sequence] >= 0;
    free(d);
    return result;
}

static Commit *merge_base(Commit *a, Commit *b) {
    int *x = distances(a), *y = distances(b);
    Commit *best = NULL;
    int smallest = 0;
    for (size_t i = 0; i < commit_count; i++) if (x[i] >= 0 && y[i] >= 0) {
        bool candidate = true;
        for (size_t j = 0; j < commit_count && candidate; j++) if (j != i && x[j] >= 0 && y[j] >= 0 && ancestor(commits[i], commits[j])) candidate = false;
        if (!candidate) continue;
        int distance = x[i] > y[i] ? x[i] : y[i];
        if (!best || distance < smallest || (distance == smallest && i > best->sequence)) {
            best = commits[i];
            smallest = distance;
        }
    }
    free(x);
    free(y);
    return best;
}

static char *summary(Commit *commit) {
    Buffer refs = {0};
    if (head() == commit) append(&refs, branch ? format("HEAD -> %s", branch) : "HEAD");
    for (size_t i = 0; i < branches.count; i++) if (branches.items[i].commit == commit && (!branch || strcmp(branches.items[i].name, branch))) {
        if (refs.length) append(&refs, ", ");
        append(&refs, branches.items[i].name);
    }
    for (size_t i = 0; i < tags.count; i++) if (tags.items[i].commit == commit) {
        if (refs.length) append(&refs, ", ");
        append(&refs, format("tag: %s", tags.items[i].name));
    }
    return format("%s%s %s", commit->id, refs.length ? format(" (%s)", refs.data) : "", commit->message);
}

static void changes(Tree before, Tree after) {
    Strings changed = differences(before, after);
    if (!changed.count) puts("(no changes)");
    for (size_t i = 0; i < changed.count; i++) {
        char *path = changed.items[i], *a = get(before, path), *b = get(after, path);
        if (!a) printf("A %s: %s\n", path, b);
        else if (!b) printf("D %s: %s\n", path, a);
        else printf("M %s: %s -> %s\n", path, a, b);
    }
}

static void progress_check(void) {
    if (operation) error("error: %s in progress", operation);
}

static bool dirty(void) {
    if (!equal(index_tree, head()->tree)) return true;
    for (size_t i = 0; i < index_tree.count; i++) if (!agree(working, index_tree, index_tree.items[i].path)) return true;
    return false;
}

static void clean_check(void) {
    if (dirty()) error("error: uncommitted changes");
}

static void overwrite_check(Strings selected) {
    selected = ordered(selected);
    for (size_t i = 0; i < selected.count; i++) if (!agree(index_tree, head()->tree, selected.items[i]) || !agree(working, head()->tree, selected.items[i])) error("error: local changes to '%s' would be overwritten", selected.items[i]);
}

static void switch_tree(Tree tree) {
    Strings changed = differences(head()->tree, tree);
    overwrite_check(changed);
    for (size_t i = 0; i < changed.count; i++) {
        match(&index_tree, tree, changed.items[i]);
        match(&working, tree, changed.items[i]);
    }
}

static Merge merge(Tree base, Tree ours, Tree theirs) {
    Merge result = {0};
    Strings all = paths(base, ours);
    for (size_t i = 0; i < theirs.count; i++) set_add(&all, theirs.items[i].path);
    all = ordered(all);
    for (size_t i = 0; i < all.count; i++) {
        char *path = all.items[i];
        if (agree(theirs, base, path) || agree(ours, theirs, path)) match(&result.tree, ours, path);
        else if (agree(ours, base, path)) match(&result.tree, theirs, path);
        else {
            set_add(&result.conflicts, path);
            match(&result.tree, ours, path);
            char *a = get(ours, path), *b = get(theirs, path);
            put(&result.contents, path, format("<<<<<<< %s ======= %s >>>>>>>", a ? a : "(deleted)", b ? b : "(deleted)"));
        }
    }
    return result;
}

static void apply(Tree base, Tree theirs, char *kind, Commit *chosen, char *message, Commit **parents, size_t parent_count, Commit *base_commit) {
    Merge result = merge(base, head()->tree, theirs);
    Strings changed = differences(head()->tree, result.tree), checked = {0};
    for (size_t i = 0; i < changed.count; i++) set_add(&checked, changed.items[i]);
    for (size_t i = 0; i < result.conflicts.count; i++) set_add(&checked, result.conflicts.items[i]);
    overwrite_check(checked);
    if (!strcmp(kind, "merge")) printf("Merge base %s\n", base_commit->id);
    else if (!result.conflicts.count && !changed.count) {
        puts("nothing to commit");
        return;
    }
    for (size_t i = 0; i < changed.count; i++) {
        match(&index_tree, result.tree, changed.items[i]);
        match(&working, result.tree, changed.items[i]);
    }
    if (!result.conflicts.count) record(parents, parent_count, result.tree, message);
    else {
        for (size_t i = 0; i < result.conflicts.count; i++) {
            char *path = result.conflicts.items[i];
            put(&working, path, get(result.contents, path));
            printf("CONFLICT %s\n", path);
        }
        conflicts = result.conflicts;
        operation = kind;
        target = chosen;
        if (!strcmp(kind, "merge")) puts("Automatic merge failed; fix conflicts and then commit the result.");
        else printf("error: could not %s %s\n", !strcmp(kind, "revert") ? "revert" : "apply", chosen->id);
    }
}

static bool glob(const char *pattern, const char *path) {
    size_t n = strlen(path), m = strlen(pattern);
    bool *previous = allocate((n + 1) * sizeof(*previous));
    previous[0] = true;
    for (size_t i = 0; i < m; i++) {
        bool *next = allocate((n + 1) * sizeof(*next));
        for (size_t j = 0; j <= n; j++) next[j] = pattern[i] == '*' ? previous[j] || (j && next[j - 1]) : j && previous[j - 1] && (pattern[i] == '?' || pattern[i] == path[j - 1]);
        free(previous);
        previous = next;
    }
    bool result = previous[n];
    free(previous);
    return result;
}

static bool ignored(const char *path) {
    if (get(index_tree, path) || contains(conflicts, path)) return false;
    for (size_t i = 0; i < ignores.count; i++) if (glob(ignores.items[i], path)) return true;
    return false;
}

static void pathspec(bool valid, const char *path) {
    if (!valid) error("error: pathspec '%s' did not match any files", path);
}

static void mark_reachable(bool *keep, Commit *commit) {
    int *d = distances(commit);
    for (size_t i = 0; i < commit_count; i++) if (d[i] >= 0) keep[i] = true;
    free(d);
}

static bool *reachable(bool extra) {
    bool *keep = allocate(commit_count * sizeof(*keep));
    mark_reachable(keep, head());
    for (size_t i = 0; i < branches.count; i++) mark_reachable(keep, branches.items[i].commit);
    for (size_t i = 0; i < tags.count; i++) mark_reachable(keep, tags.items[i].commit);
    if (extra) {
        for (size_t i = 0; i < stash_count; i++) mark_reachable(keep, stashes[i].base);
        if (operation) mark_reachable(keep, target);
    }
    return keep;
}

static bool commit_in(Commit **array, size_t count, Commit *commit) {
    for (size_t i = 0; i < count; i++) if (array[i] == commit) return true;
    return false;
}

static Strings split(const char *line) {
    Strings out = {0};
    size_t start = 0;
    for (size_t i = 0;; i++) if (!line[i] || line[i] == ' ') {
        APPEND(out.items, out.count, slice(line + start, i - start));
        start = i + 1;
        if (!line[i]) break;
    }
    return out;
}

static void command(const char *line) {
    Strings words = split(line);
    char **w = words.items, *cmd = w[0], *path = words.count > 1 ? w[1] : "";
    if (!strcmp(cmd, "WRITE")) {
        const char *space = strchr(strchr(line, ' ') + 1, ' ');
        put(&working, path, copy(space + 1));
    } else if (!strcmp(cmd, "REMOVE")) {
        if (!get(working, path)) error("error: no such file '%s'", path);
        remove_file(&working, path);
    } else if (!strcmp(cmd, "IGNORE")) APPEND(ignores.items, ignores.count, path);
    else if (!strcmp(cmd, "ADD")) {
        if (!strcmp(path, "ALL")) {
            Strings all = paths(working, index_tree), selected = {0};
            for (size_t i = 0; i < all.count; i++) if (!ignored(all.items[i])) set_add(&selected, all.items[i]);
            for (size_t i = 0; i < selected.count; i++) match(&index_tree, working, selected.items[i]);
            conflicts.count = 0;
        } else {
            if (get(working, path) && ignored(path)) error("error: path '%s' is ignored", path);
            pathspec(get(working, path) || get(index_tree, path) || contains(conflicts, path), path);
            match(&index_tree, working, path);
            set_remove(&conflicts, path);
        }
    } else if (!strcmp(cmd, "RM")) {
        pathspec(get(index_tree, path) != NULL, path);
        remove_file(&index_tree, path);
        remove_file(&working, path);
        set_remove(&conflicts, path);
    } else if (!strcmp(cmd, "UNSTAGE")) {
        pathspec(get(index_tree, path) || get(head()->tree, path), path);
        match(&index_tree, head()->tree, path);
    } else if (!strcmp(cmd, "RESTORE")) {
        if (words.count == 2) {
            pathspec(get(index_tree, path) != NULL, path);
            put(&working, path, get(index_tree, path));
        } else {
            Commit *chosen = resolve(w[2]);
            if (!get(chosen->tree, path)) error("error: path '%s' does not exist in '%s'", path, w[2]);
            match(&index_tree, chosen->tree, path);
            match(&working, chosen->tree, path);
            set_remove(&conflicts, path);
        }
    } else if (!strcmp(cmd, "COMMIT")) {
        if (conflicts.count) error("error: unresolved conflicts");
        bool merging = operation && !strcmp(operation, "merge");
        if (!merging && equal(index_tree, head()->tree)) {
            puts("nothing to commit");
            return;
        }
        Commit *parents[] = {head(), target};
        record(parents, merging ? 2 : 1, index_tree, copy(strchr(line, ' ') + 1));
        operation = NULL;
        target = NULL;
    } else if (!strcmp(cmd, "AMEND")) {
        progress_check();
        Commit *before = head();
        if (!before->parent_count) error("error: cannot amend the root commit");
        record(before->parents, before->parent_count, index_tree, copy(strchr(line, ' ') + 1));
    } else if (!strcmp(cmd, "STATUS")) {
        if (branch) printf("On branch %s\n", branch);
        else printf("HEAD detached at %s\n", head()->id);
        if (operation) printf("%s %s\n", !strcmp(operation, "merge") ? "Merging" : !strcmp(operation, "revert") ? "Reverting" : "Cherry-picking", target->id);
        Strings all = paths(head()->tree, index_tree);
        for (size_t i = 0; i < working.count; i++) set_add(&all, working.items[i].path);
        for (size_t i = 0; i < conflicts.count; i++) set_add(&all, conflicts.items[i]);
        all = ordered(all);
        bool any = false;
        for (size_t i = 0; i < all.count; i++) {
            char *p = all.items[i];
            if (contains(conflicts, p)) {
                printf("UU %s\n", p);
                any = true;
            } else if (get(index_tree, p)) {
                char x = !get(head()->tree, p) ? 'A' : agree(head()->tree, index_tree, p) ? '.' : 'M', y = !get(working, p) ? 'D' : agree(working, index_tree, p) ? '.' : 'M';
                if (x != '.' || y != '.') {
                    printf("%c%c %s\n", x, y, p);
                    any = true;
                }
            } else {
                if (get(head()->tree, p)) {
                    printf("D. %s\n", p);
                    any = true;
                }
                if (get(working, p) && !ignored(p)) {
                    printf("?? %s\n", p);
                    any = true;
                }
            }
        }
        if (!any) puts("nothing to commit, working tree clean");
    } else if (!strcmp(cmd, "LS")) {
        Tree tree = words.count == 1 ? working : resolve(path)->tree;
        Strings all = keys(tree);
        if (!all.count) puts("(empty)");
        for (size_t i = 0; i < all.count; i++) printf("%s %s\n", all.items[i], get(tree, all.items[i]));
    } else if (!strcmp(cmd, "CAT")) {
        Tree tree = words.count == 2 ? working : resolve(w[2])->tree;
        char *text = get(tree, path);
        if (!text) {
            if (words.count == 2) error("error: no such file '%s'", path);
            else error("error: path '%s' does not exist in '%s'", path, w[2]);
        }
        puts(text);
    } else if (!strcmp(cmd, "DIFF")) {
        if (words.count == 1) {
            Tree tracked = {0};
            for (size_t i = 0; i < index_tree.count; i++) if (get(working, index_tree.items[i].path)) match(&tracked, working, index_tree.items[i].path);
            changes(index_tree, tracked);
        } else if (words.count == 2) changes(head()->tree, index_tree);
        else {
            Commit *a = resolve(path), *b = resolve(w[2]);
            changes(a->tree, b->tree);
        }
    } else if (!strcmp(cmd, "LOG")) {
        Commit *chosen = head();
        int left = words.count == 1 ? (int)commit_count : atoi(path);
        while (left-- > 0) {
            puts(summary(chosen));
            if (!chosen->parent_count) break;
            chosen = chosen->parents[0];
        }
    } else if (!strcmp(cmd, "SHOW")) {
        Commit *chosen = resolve(words.count == 1 ? "HEAD" : path);
        printf("commit %s\nparents:", summary(chosen));
        if (!chosen->parent_count) printf(" none");
        for (size_t i = 0; i < chosen->parent_count; i++) printf(" %s", chosen->parents[i]->id);
        putchar('\n');
        changes(chosen->parent_count ? chosen->parents[0]->tree : (Tree){0}, chosen->tree);
    } else if (!strcmp(cmd, "BLAME")) {
        Commit *chosen = head();
        char *text = get(chosen->tree, path);
        if (!text) error("error: path '%s' does not exist in 'HEAD'", path);
        while (chosen->parent_count && get(chosen->parents[0]->tree, path) && !strcmp(get(chosen->parents[0]->tree, path), text)) chosen = chosen->parents[0];
        printf("%s (%s) %s\n", chosen->id, chosen->message, text);
    } else if (!strcmp(cmd, "BRANCH") || !strcmp(cmd, "TAG")) {
        bool tag = !strcmp(cmd, "TAG");
        Refs *refs = tag ? &tags : &branches;
        char *noun = tag ? "tag" : "branch";
        if (!strcmp(path, "-d")) {
            char *name = w[2];
            Commit *chosen = ref_get(*refs, name);
            if (!chosen) error("error: no such %s '%s'", noun, name);
            if (!tag) {
                if (branch && !strcmp(branch, name)) error("error: cannot delete current branch '%s'", name);
                if (!ancestor(chosen, head())) error("error: branch '%s' is not fully merged", name);
            }
            ref_remove(refs, name);
            printf("Deleted %s %s (was %s)\n", noun, name, chosen->id);
        } else {
            if (ref_get(*refs, path)) error("error: %s '%s' already exists", noun, path);
            Commit *chosen = resolve(words.count == 2 ? "HEAD" : w[2]);
            ref_put(refs, path, chosen);
            printf("Created %s %s at %s\n", noun, path, chosen->id);
        }
    } else if (!strcmp(cmd, "BRANCHES")) {
        if (!branch) printf("* (HEAD detached at %s)\n", head()->id);
        for (size_t i = 0; i < branches.count; i++) printf("%s %s %s %s\n", branch && !strcmp(branch, branches.items[i].name) ? "*" : " ", branches.items[i].name, branches.items[i].commit->id, branches.items[i].commit->message);
    } else if (!strcmp(cmd, "TAGS")) {
        if (!tags.count) puts("(no tags)");
        for (size_t i = 0; i < tags.count; i++) printf("%s %s %s\n", tags.items[i].name, tags.items[i].commit->id, tags.items[i].commit->message);
    } else if (!strcmp(cmd, "SWITCH")) {
        Commit *chosen = ref_get(branches, path);
        if (!chosen) error("error: no such branch '%s'", path);
        if (branch && !strcmp(branch, path)) {
            printf("Already on '%s'\n", path);
            return;
        }
        progress_check();
        switch_tree(chosen->tree);
        branch = path;
        printf("Switched to branch '%s'\n", path);
    } else if (!strcmp(cmd, "DETACH")) {
        Commit *chosen = resolve(path);
        progress_check();
        switch_tree(chosen->tree);
        branch = NULL;
        detached = chosen;
        printf("HEAD is now at %s %s\n", chosen->id, chosen->message);
    } else if (!strcmp(cmd, "MERGEBASE")) {
        Commit *a = resolve(path), *b = resolve(w[2]);
        puts(merge_base(a, b)->id);
    } else if (!strcmp(cmd, "MERGE")) {
        Commit *chosen = resolve(path), *before = head();
        progress_check();
        if (ancestor(chosen, before)) {
            puts("Already up to date");
            return;
        }
        if (ancestor(before, chosen)) {
            switch_tree(chosen->tree);
            move_head(chosen);
            printf("Fast-forward %s..%s\n", before->id, chosen->id);
            return;
        }
        clean_check();
        Commit *base = merge_base(before, chosen), *parents[] = {before, chosen};
        apply(base->tree, chosen->tree, "merge", chosen, format("Merge %s", path), parents, 2, base);
    } else if (!strcmp(cmd, "RESET")) {
        Commit *chosen = resolve(w[2]);
        if (!strcmp(path, "HARD")) {
            Strings all = paths(index_tree, chosen->tree);
            for (size_t i = 0; i < conflicts.count; i++) set_add(&all, conflicts.items[i]);
            for (size_t i = 0; i < all.count; i++) match(&working, chosen->tree, all.items[i]);
        }
        if (strcmp(path, "SOFT")) index_tree = clone(chosen->tree);
        move_head(chosen);
        conflicts.count = 0;
        operation = NULL;
        target = NULL;
        printf("HEAD is now at %s %s\n", chosen->id, chosen->message);
    } else if (!strcmp(cmd, "REVERT") || !strcmp(cmd, "CHERRYPICK")) {
        Commit *chosen = resolve(path);
        progress_check();
        clean_check();
        Tree parent = chosen->parent_count ? chosen->parents[0]->tree : (Tree){0};
        bool revert = !strcmp(cmd, "REVERT");
        Commit *parents[] = {head()};
        apply(revert ? chosen->tree : parent, revert ? parent : chosen->tree, revert ? "revert" : "cherry-pick", chosen, revert ? format("Revert \"%s\"", chosen->message) : chosen->message, parents, 1, NULL);
    } else if (!strcmp(cmd, "REBASE")) {
        Commit *upstream = resolve(path);
        progress_check();
        if (ancestor(upstream, head())) {
            puts("Already up to date");
            return;
        }
        clean_check();
        Commit **old = NULL, *cursor = head();
        size_t count = 0;
        while (!ancestor(cursor, upstream)) {
            APPEND(old, count, cursor);
            cursor = cursor->parents[0];
        }
        Replay *replay = allocate(count * sizeof(*replay));
        Tree tree = clone(upstream->tree);
        for (size_t i = 0; i < count; i++) {
            Commit *chosen = old[count - i - 1];
            Merge result = merge(chosen->parents[0]->tree, tree, chosen->tree);
            if (result.conflicts.count) error("error: could not rebase %s: conflict in '%s'", chosen->id, result.conflicts.items[0]);
            replay[i] = (Replay){chosen, result.tree, !equal(tree, result.tree)};
            tree = result.tree;
        }
        switch_tree(tree);
        Commit *current = upstream;
        for (size_t i = 0; i < count; i++) if (replay[i].pick) {
            Commit *parents[] = {current};
            Commit *created = create(parents, 1, replay[i].tree, replay[i].original->message);
            printf("pick %s -> %s %s\n", replay[i].original->id, created->id, created->message);
            current = created;
        } else printf("skip %s %s\n", replay[i].original->id, replay[i].original->message);
        move_head(current);
        printf("HEAD is now at %s %s\n", current->id, current->message);
    } else if (!strcmp(cmd, "STASH")) {
        if (words.count > 1 && !strcmp(path, "LIST")) {
            if (!stash_count) puts("(no stash entries)");
            for (size_t i = 0; i < stash_count; i++) printf("stash@{%zu}: %s\n", i, stashes[i].label);
            return;
        }
        if (words.count > 1) {
            if (!stash_count) error("error: no stash entries");
            Stash stash = stashes[0];
            if (!strcmp(path, "DROP")) {
                memmove(stashes, stashes + 1, (--stash_count) * sizeof(*stashes));
                printf("Dropped stash@{0}: %s\n", stash.label);
                return;
            }
            progress_check();
            clean_check();
            Merge result = merge(stash.base->tree, head()->tree, stash.tree);
            if (result.conflicts.count) error("error: stash conflict in '%s'", result.conflicts.items[0]);
            Strings changed = differences(head()->tree, result.tree);
            overwrite_check(changed);
            for (size_t i = 0; i < changed.count; i++) match(&working, result.tree, changed.items[i]);
            memmove(stashes, stashes + 1, (--stash_count) * sizeof(*stashes));
            printf("Restored stash@{0}: %s\n", stash.label);
            changes(head()->tree, result.tree);
        } else {
            progress_check();
            if (!dirty()) {
                puts("No local changes to save");
                return;
            }
            Tree saved = {0};
            Strings tracked = paths(index_tree, head()->tree);
            for (size_t i = 0; i < tracked.count; i++) if (get(working, tracked.items[i])) match(&saved, working, tracked.items[i]);
            for (size_t i = 0; i < tracked.count; i++) match(&working, head()->tree, tracked.items[i]);
            index_tree = clone(head()->tree);
            char *label = format("WIP on %s: %s %s", branch ? branch : "(no branch)", head()->id, head()->message);
            stashes = resize(stashes, (stash_count + 1) * sizeof(*stashes));
            memmove(stashes + 1, stashes, stash_count * sizeof(*stashes));
            stashes[0] = (Stash){label, head(), saved};
            stash_count++;
            printf("Saved stash@{0}: %s\n", label);
        }
    } else if (!strcmp(cmd, "GRAPH")) {
        bool *keep = reachable(false);
        Commit **lanes = NULL;
        size_t count = 0;
        for (size_t sequence = commit_count; sequence; sequence--) {
            Commit *chosen = commits[sequence - 1];
            if (!keep[sequence - 1]) continue;
            if (!commit_in(lanes, count, chosen)) APPEND(lanes, count, chosen);
            size_t first = 0;
            while (lanes[first] != chosen) first++;
            for (size_t i = 0; i < count; i++) printf("%s%s", i ? " " : "", i == first ? "*" : lanes[i] == chosen ? "/" : "|");
            printf(" %s\n", summary(chosen));
            size_t next = 0;
            for (size_t i = 0; i < count; i++) if (i == first || lanes[i] != chosen) lanes[next++] = lanes[i];
            count = next;
            if (!chosen->parent_count) {
                memmove(lanes + first, lanes + first + 1, (count - first - 1) * sizeof(*lanes));
                count--;
            } else {
                lanes[first] = chosen->parents[0];
                if (chosen->parent_count == 2 && !commit_in(lanes, count, chosen->parents[1])) {
                    lanes = resize(lanes, (count + 1) * sizeof(*lanes));
                    memmove(lanes + first + 2, lanes + first + 1, (count - first - 1) * sizeof(*lanes));
                    lanes[first + 1] = chosen->parents[1];
                    count++;
                }
            }
        }
        free(keep);
        free(lanes);
    } else if (!strcmp(cmd, "DESCRIBE")) {
        Commit *chosen = resolve(words.count == 1 ? "HEAD" : path);
        int *d = distances(chosen), best_distance = 0;
        char *best = NULL;
        for (size_t i = 0; i < tags.count; i++) {
            int distance = d[tags.items[i].commit->sequence];
            if (distance >= 0 && (!best || distance < best_distance)) {
                best = tags.items[i].name;
                best_distance = distance;
            }
        }
        if (!best) error("error: no tag can describe '%s'", chosen->id);
        if (!best_distance) puts(best);
        else printf("%s-%d-g%s\n", best, best_distance, chosen->id);
        free(d);
    } else if (!strcmp(cmd, "GC")) {
        bool *keep = reachable(true);
        size_t removed = 0;
        for (size_t i = 0; i < commit_count; i++) if (commits[i]->alive && !keep[i]) {
            commits[i]->alive = false;
            removed++;
        }
        printf("Removed unreachable commits: %zu\n", removed);
        free(keep);
    }
}

static char *read_line(void) {
    Buffer b = {0};
    int c;
    while ((c = getchar()) != EOF && c != '\n') append(&b, (char[]){(char)c, 0});
    if (c == EOF && !b.length) return NULL;
    return finish(&b);
}
int main(void) {
    ref_put(&branches, "main", create(NULL, 0, (Tree){0}, "init"));
    char *line;
    while ((line = read_line()) && strcmp(line, "EXIT")) {
        if (setjmp(failure)) puts(error_reason);
        else command(line);
    }
    return 0;
}
