#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAX_PACKAGES 50
#define MAX_VERSIONS 300
#define MAX_CLAUSES 8
#define MAX_ADVISORIES 50
#define MAX_CONSTRAINT 50
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
static jmp_buf command_error;

static void *allocate(size_t size) {
    void *p = calloc(1, size ? size : 1);
    Allocation *a = malloc(sizeof *a);
    if (!p || !a) exit(EXIT_FAILURE);
    *a = (Allocation){p, allocations};
    allocations = a;
    return p;
}

static void fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("error: ", stdout);
    vprintf(format, args);
    putchar('\n');
    va_end(args);
    longjmp(command_error, 1);
}
typedef struct {
    int core[3];
    char pre[MAX_CONSTRAINT + 1], text[MAX_CONSTRAINT + 30];
} Version;
typedef struct {
    int op;
    Version version;
} Comparator;
typedef struct {
    Comparator *comparators;
    int count;
    int (*pre_cores)[3], pre_count;
} Alternative;
typedef struct {
    Alternative *alternatives;
    int count;
} Constraint;
typedef struct {
    char name[13], text[MAX_CONSTRAINT + 1];
    Constraint *constraint;
} Clause;
typedef struct {
    char name[13];
    Version version;
    Clause dependencies[MAX_CLAUSES], conflicts[MAX_CLAUSES];
    int dependency_count, conflict_count;
    bool yanked;
} Package;
typedef struct Requirement {
    Clause *clause;
    Package *origin;
    struct Requirement *parent;
} Requirement;
typedef struct {
    char **items;
    int count;
} Lines;
typedef struct Snapshot {
    Clause *requests[MAX_PACKAGES];
    int request_count;
    Package *installed[MAX_PACKAGES];
    struct Snapshot *previous;
} Snapshot;
typedef struct {
    char id[13];
    Clause clause;
} Advisory;
static char known_names[MAX_PACKAGES][13];
static int known_count, version_count, request_count, advisory_count, history_count;
static Package *registry[MAX_VERSIONS], *installed[MAX_PACKAGES];
static Clause *requests[MAX_PACKAGES];
static bool held[MAX_PACKAGES];
static Advisory advisories[MAX_ADVISORIES];
static Snapshot *history;
static const char *operators[] = {"=", ">", ">=", "<", "<="};

static bool digits(const char *text) {
    if (!*text) return false;
    for (const char *p = text; *p; p++) if (*p < '0' || *p > '9') return false;
    return true;
}

static bool number(const char *text) {
    size_t n = strlen(text);
    return n >= 1 && n <= 4 && digits(text) && (n == 1 || text[0] != '0');
}

static void version_text(Version *v) {
    snprintf(v->text, sizeof v->text, "%d.%d.%d%s%s", v->core[0], v->core[1], v->core[2], *v->pre ? "-" : "", v->pre);
}

static int split(char *text, char separator, char **parts) {
    int count = 0;
    parts[count++] = text;
    for (char *p = text; *p; p++) if (*p == separator) {
        *p = '\0';
        parts[count++] = p + 1;
    }
    return count;
}

static bool parse_version(const char *text, Version *v) {
    memset(v, 0, sizeof *v);
    char copy[MAX_CONSTRAINT + 1];
    if (strlen(text) > MAX_CONSTRAINT) return false;
    strcpy(copy, text);
    char *dash = strchr(copy, '-');
    if (dash) {
        *dash++ = '\0';
        if (!*dash) return false;
        strcpy(v->pre, dash);
        char pre[MAX_CONSTRAINT + 1], *ids[MAX_CONSTRAINT + 1];
        strcpy(pre, dash);
        int count = split(pre, '.', ids);
        for (int i = 0; i < count; i++) {
            if (!*ids[i]) return false;
            for (char *p = ids[i]; *p; p++) if (!(*p >= 'a' && *p <= 'z') && !(*p >= '0' && *p <= '9')) return false;
            if (digits(ids[i]) && !number(ids[i])) return false;
        }
    }
    char *parts[MAX_CONSTRAINT + 1];
    int count = split(copy, '.', parts);
    if (count != 3) return false;
    for (int i = 0; i < 3; i++) {
        if (!number(parts[i])) return false;
        v->core[i] = atoi(parts[i]);
    }
    version_text(v);
    return true;
}

static Version checked_version(const char *text) {
    Version v;
    if (!parse_version(text, &v)) fail("invalid version '%s'", text);
    return v;
}

static int identifier_compare(const char *a, int na, const char *b, int nb) {
    bool an = true, bn = true;
    for (int i = 0; i < na; i++) if (a[i] < '0' || a[i] > '9') an = false;
    for (int i = 0; i < nb; i++) if (b[i] < '0' || b[i] > '9') bn = false;
    if (an != bn) return an ? -1 : 1;
    if (an && na != nb) return na < nb ? -1 : 1;
    int length = na < nb ? na : nb, c = strncmp(a, b, (size_t)length);
    return c ? c : (na > nb) - (na < nb);
}

static int version_compare(const Version *a, const Version *b) {
    for (int i = 0; i < 3; i++) if (a->core[i] != b->core[i]) return a->core[i] < b->core[i] ? -1 : 1;
    if (!*a->pre || !*b->pre) return (!*a->pre) - (!*b->pre);
    const char *x = a->pre, *y = b->pre;
    while (*x && *y) {
        const char *xe = strchr(x, '.'), *ye = strchr(y, '.');
        int nx = xe ? (int)(xe - x) : (int)strlen(x), ny = ye ? (int)(ye - y) : (int)strlen(y);
        int c = identifier_compare(x, nx, y, ny);
        if (c) return c;
        x += nx;
        y += ny;
        if (*x) x++;
        if (*y) y++;
    }
    return (*x != '\0') - (*y != '\0');
}

static bool same_core(const int *a, const int *b) {
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
}

static void add_comparator(Alternative *a, int op, Version v) {
    a->comparators[a->count++] = (Comparator){op, v};
}

static Constraint *parse_constraint(const char *text) {
    Constraint *result = allocate(sizeof *result);
    int branches = 1;
    for (const char *p = text; (p = strstr(p, " || ")) != NULL; p += 4) branches++;
    result->alternatives = allocate((size_t)branches * sizeof *result->alternatives);
    char copy[MAX_CONSTRAINT + 1];
    strcpy(copy, text);
    char *branch = copy;
    for (;;) {
        char *next = strstr(branch, " || ");
        if (next) {
            *next = '\0';
            next += 4;
        }
        Alternative *a = &result->alternatives[result->count++];
        char *terms[MAX_CONSTRAINT + 1];
        int term_count = split(branch, ' ', terms);
        a->comparators = allocate((size_t)(2 * term_count) * sizeof *a->comparators);
        a->pre_cores = allocate((size_t)term_count * sizeof *a->pre_cores);
        for (int t = 0; t < term_count; t++) {
            char *pattern = terms[t];
            int op = -1;
            if (!*pattern) return NULL;
            const char *prefixes[] = {">=", "<=", ">", "<", "=", "^", "~"};
            const int codes[] = {2, 4, 1, 3, 0, 5, 6};
            for (int i = 0; i < 7; i++) if (!strncmp(pattern, prefixes[i], strlen(prefixes[i]))) {
                op = codes[i];
                pattern += strlen(prefixes[i]);
                break;
            }
            Version lower;
            int count;
            if (parse_version(pattern, &lower) && *lower.pre) {
                count = 3;
                memcpy(a->pre_cores[a->pre_count++], lower.core, sizeof lower.core);
            } else {
                char parts_copy[MAX_CONSTRAINT + 1], *parts[MAX_CONSTRAINT + 1];
                strcpy(parts_copy, pattern);
                int parts_count = split(parts_copy, '.', parts);
                if (parts_count < 1 || parts_count > 3) return NULL;
                memset(&lower, 0, sizeof lower);
                count = 0;
                bool wildcard = false;
                for (int i = 0; i < parts_count; i++) {
                    if (!strcmp(parts[i], "x") || !strcmp(parts[i], "*")) wildcard = true;
                    else {
                        if (wildcard || !number(parts[i])) return NULL;
                        lower.core[i] = atoi(parts[i]);
                        count++;
                    }
                }
                version_text(&lower);
            }
            if (count == 0) {
                if (op == 1 || op == 3) {
                    Version smallest = {0};
                    strcpy(smallest.pre, "0");
                    version_text(&smallest);
                    add_comparator(a, 3, smallest);
                }
                continue;
            }
            Version upper[3];
            for (int i = 0; i < 3; i++) {
                upper[i] = lower;
                upper[i].pre[0] = '\0';
                upper[i].core[i]++;
                for (int j = i + 1; j < 3; j++) upper[i].core[j] = 0;
                version_text(&upper[i]);
            }
            if (op == -1 || op == 0) {
                if (count == 3) add_comparator(a, 0, lower);
                else {
                    add_comparator(a, 2, lower);
                    add_comparator(a, 3, upper[count - 1]);
                }
            } else if (op == 1) add_comparator(a, count == 3 ? 1 : 2, count == 3 ? lower : upper[count - 1]);
            else if (op == 4) add_comparator(a, count == 3 ? 4 : 3, count == 3 ? lower : upper[count - 1]);
            else if (op == 2 || op == 3) add_comparator(a, op, lower);
            else if (op == 6) {
                add_comparator(a, 2, lower);
                add_comparator(a, 3, upper[count == 1 ? 0 : 1]);
            } else {
                int i = lower.core[0] != 0 || count == 1 ? 0 : lower.core[1] != 0 || count == 2 ? 1 : 2;
                add_comparator(a, 2, lower);
                add_comparator(a, 3, upper[i]);
            }
        }
        if (!next) break;
        branch = next;
    }
    return result;
}

static Constraint *checked_constraint(const char *text) {
    Constraint *c = parse_constraint(text);
    if (!c) fail("invalid constraint '%s'", text);
    return c;
}

static bool matches(Constraint *c, const Version *v) {
    for (int i = 0; i < c->count; i++) {
        Alternative *a = &c->alternatives[i];
        bool allowed = !*v->pre;
        for (int j = 0; j < a->pre_count; j++) if (same_core(a->pre_cores[j], v->core)) allowed = true;
        if (!allowed) continue;
        bool valid = true;
        for (int j = 0; j < a->count; j++) {
            Comparator *cmp = &a->comparators[j];
            int order = version_compare(v, &cmp->version);
            bool passes = cmp->op == 0 ? order == 0 : cmp->op == 1 ? order > 0 : cmp->op == 2 ? order >= 0 : cmp->op == 3 ? order < 0 : order <= 0;
            if (!passes) {
                valid = false;
                break;
            }
        }
        if (valid) return true;
    }
    return false;
}

static Clause *new_clause(const char *name, const char *text) {
    Constraint *c = checked_constraint(text);
    Clause *d = allocate(sizeof *d);
    strcpy(d->name, name);
    strcpy(d->text, text);
    d->constraint = c;
    return d;
}

static int known(const char *name) {
    for (int i = 0; i < known_count; i++) if (!strcmp(known_names[i], name)) return i;
    return -1;
}

static void name_order(int *order) {
    for (int i = 0; i < known_count; i++) order[i] = i;
    for (int i = 1; i < known_count; i++) {
        int v = order[i], j = i;
        while (j && strcmp(known_names[order[j - 1]], known_names[v]) > 0) {
            order[j] = order[j - 1];
            j--;
        }
        order[j] = v;
    }
}

static int package_compare(const void *a, const void *b) {
    return -version_compare(&(*(Package *const *)a)->version, &(*(Package *const *)b)->version);
}

static int versions(const char *name, Package **result) {
    int count = 0;
    for (int i = 0; i < version_count; i++) if (!strcmp(registry[i]->name, name)) result[count++] = registry[i];
    qsort(result, (size_t)count, sizeof *result, package_compare);
    return count;
}

static Package *registered(const char *name, const char *version) {
    for (int i = 0; i < version_count; i++) if (!strcmp(registry[i]->name, name) && !strcmp(registry[i]->version.text, version)) return registry[i];
    return NULL;
}

static Package *checked_package(const char *name, const char *version) {
    Package *p = registered(name, version);
    if (!p) fail("%s@%s is not registered", name, version);
    return p;
}

static bool applies(Advisory *a, Package *p) {
    return !strcmp(a->clause.name, p->name) && matches(a->clause.constraint, &p->version);
}

static bool vulnerable(Package *p) {
    for (int i = 0; i < advisory_count; i++) if (applies(&advisories[i], p)) return true;
    return false;
}

static int advisory_compare(const void *a, const void *b) {
    return strcmp(((const Advisory *)a)->id, ((const Advisory *)b)->id);
}

static void display(Package *p) {
    int i = known(p->name);
    bool current = installed[i] == p;
    printf("%s@%s%s\n", p->name, p->version.text, p->yanked ? current ? " (yanked, installed)" : " (yanked)" : current ? " (installed)" : "");
}

static void append_line(Lines *lines, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *line = malloc((size_t)length + 1);
    char **items = realloc(lines->items, (size_t)(lines->count + 1) * sizeof *items);
    if (!line || !items) exit(EXIT_FAILURE);
    vsnprintf(line, (size_t)length + 1, format, args);
    va_end(args);
    lines->items = items;
    lines->items[lines->count++] = line;
}

static void clear_lines(Lines *lines) {
    for (int i = 0; i < lines->count; i++) free(lines->items[i]);
    free(lines->items);
    *lines = (Lines){0};
}

static void requirement_chain(Lines *lines, Requirement *r, const char *indent) {
    if (r->parent) requirement_chain(lines, r->parent, indent);
    Clause *d = r->clause;
    if (r->origin) append_line(lines, "%s%s@%s requires %s %s", indent, r->origin->name, r->origin->version.text, d->name, d->text);
    else append_line(lines, "%srequested %s %s", indent, d->name, d->text);
}
typedef struct {
    Package *selected[MAX_PACKAGES];
    Requirement *reasons[MAX_PACKAGES];
    bool preferred[MAX_PACKAGES], audit;
    int failure_depth;
    Lines failure;
} Resolution;

static bool usable(Resolution *r, Package *p) {
    return (!p->yanked || installed[known(p->name)] == p) && (!r->audit || !vulnerable(p));
}

static void record_failure(Resolution *r, Requirement *requirement, int kind, Package *p, Package *q) {
    int count = 0;
    for (int i = 0; i < known_count; i++) count += r->selected[i] != NULL;
    if (count <= r->failure_depth) return;
    r->failure_depth = count;
    clear_lines(&r->failure);
    append_line(&r->failure, "UNSATISFIABLE");
    requirement_chain(&r->failure, requirement, "  ");
    if (kind == 0) append_line(&r->failure, "  %s@%s was selected by:", p->name, p->version.text);
    else if (kind == 1) append_line(&r->failure, "  %s@%s is held", p->name, p->version.text);
    else if (kind == 2) append_line(&r->failure, "  no version of %s matches %s", requirement->clause->name, requirement->clause->text);
    else append_line(&r->failure, "  %s@%s conflicts with %s@%s, which was selected by:", p->name, p->version.text, q->name, q->version.text);
    if (kind == 0 || kind == 3) requirement_chain(&r->failure, r->reasons[known(kind == 0 ? p->name : q->name)], "    ");
}

static bool conflicts(Package *p, Package *q) {
    for (int i = 0; i < p->conflict_count; i++) if (!strcmp(p->conflicts[i].name, q->name) && matches(p->conflicts[i].constraint, &q->version)) return true;
    for (int i = 0; i < q->conflict_count; i++) if (!strcmp(q->conflicts[i].name, p->name) && matches(q->conflicts[i].constraint, &p->version)) return true;
    return false;
}

static bool search(Resolution *r, Requirement **pending, int count) {
    if (!count) return true;
    Requirement *requirement = pending[0];
    Clause *d = requirement->clause;
    int n = known(d->name);
    if (n >= 0 && r->selected[n]) {
        Package *p = r->selected[n];
        if (matches(d->constraint, &p->version)) return search(r, pending + 1, count - 1);
        record_failure(r, requirement, 0, p, NULL);
        return false;
    }
    Package *candidates[MAX_VERSIONS];
    int candidate_count = 0;
    if (n >= 0 && held[n]) {
        Package *p = installed[n];
        if (!matches(d->constraint, &p->version) || !usable(r, p)) {
            record_failure(r, requirement, 1, p, NULL);
            return false;
        }
        candidates[candidate_count++] = p;
    } else {
        Package *all[MAX_VERSIONS];
        int all_count = versions(d->name, all);
        for (int i = 0; i < all_count; i++) if (matches(d->constraint, &all[i]->version) && usable(r, all[i])) candidates[candidate_count++] = all[i];
        if (n >= 0 && r->preferred[n]) for (int i = 0; i < candidate_count; i++) if (candidates[i] == installed[n]) {
            Package *p = candidates[i];
            memmove(candidates + 1, candidates, (size_t)i * sizeof *candidates);
            candidates[0] = p;
            break;
        }
        if (!candidate_count) {
            record_failure(r, requirement, 2, NULL, NULL);
            return false;
        }
    }
    int order[MAX_PACKAGES];
    name_order(order);
    for (int i = 0; i < candidate_count; i++) {
        Package *p = candidates[i], *conflict = NULL;
        for (int j = 0; j < known_count; j++) {
            Package *q = r->selected[order[j]];
            if (q && conflicts(p, q)) {
                conflict = q;
                break;
            }
        }
        if (conflict) {
            record_failure(r, requirement, 3, p, conflict);
            continue;
        }
        r->selected[n] = p;
        r->reasons[n] = requirement;
        Requirement children[MAX_CLAUSES];
        int next_count = p->dependency_count + count - 1;
        Requirement **next = malloc((size_t)(next_count ? next_count : 1) * sizeof *next);
        if (!next) exit(EXIT_FAILURE);
        for (int j = 0; j < p->dependency_count; j++) {
            children[j] = (Requirement){&p->dependencies[j], p, requirement};
            next[j] = &children[j];
        }
        for (int j = 1; j < count; j++) next[p->dependency_count + j - 1] = pending[j];
        bool success = search(r, next, next_count);
        free(next);
        if (success) return true;
        r->selected[n] = NULL;
        r->reasons[n] = NULL;
    }
    return false;
}

static void plan(Package **next) {
    int order[MAX_PACKAGES];
    name_order(order);
    bool arranged[MAX_PACKAGES] = {false}, removed[MAX_PACKAGES] = {false};
    int counts[4] = {0}, total = 0;
    for (int i = 0; i < known_count; i++) {
        total += next[i] != NULL;
        removed[i] = installed[i] && !next[i];
    }
    for (int step = 0; step < total; step++) {
        int n = -1;
        for (int j = 0; j < known_count; j++) {
            int i = order[j];
            if (!next[i] || arranged[i]) continue;
            bool ready = true;
            for (int k = 0; k < next[i]->dependency_count; k++) if (!arranged[known(next[i]->dependencies[k].name)]) ready = false;
            if (ready) {
                n = i;
                break;
            }
        }
        arranged[n] = true;
        Package *p = next[n], *old = installed[n];
        if (!old) {
            printf("install %s@%s\n", p->name, p->version.text);
            counts[0]++;
        } else if (old != p) {
            bool newer = version_compare(&p->version, &old->version) > 0;
            printf("%s %s %s -> %s\n", newer ? "upgrade" : "downgrade", p->name, old->version.text, p->version.text);
            counts[newer ? 1 : 2]++;
        }
    }
    for (;;) {
        int n = -1;
        for (int j = 0; j < known_count; j++) {
            int i = order[j];
            if (!removed[i]) continue;
            bool ready = true;
            for (int q = 0; q < known_count; q++) if (removed[q]) for (int k = 0; k < installed[q]->dependency_count; k++) if (!strcmp(installed[q]->dependencies[k].name, known_names[i])) ready = false;
            if (ready) {
                n = i;
                break;
            }
        }
        if (n < 0) break;
        printf("remove %s@%s\n", installed[n]->name, installed[n]->version.text);
        counts[3]++;
        removed[n] = false;
    }
    if (counts[0] + counts[1] + counts[2] + counts[3]) printf("%d installed, %d upgraded, %d downgraded, %d removed\n", counts[0], counts[1], counts[2], counts[3]);
    else puts("no changes");
}

static void prune_holds(void) {
    for (int i = 0; i < known_count; i++) if (!installed[i]) held[i] = false;
}

static void update(Clause **list, int count, Package **next) {
    Snapshot *snapshot = calloc(1, sizeof *snapshot);
    if (!snapshot) exit(EXIT_FAILURE);
    memcpy(snapshot->requests, requests, sizeof requests);
    snapshot->request_count = request_count;
    memcpy(snapshot->installed, installed, sizeof installed);
    snapshot->previous = history;
    history = snapshot;
    history_count++;
    memmove(requests, list, (size_t)count * sizeof *requests);
    request_count = count;
    memmove(installed, next, sizeof installed);
    prune_holds();
}

static void resolve(Clause **list, int count, bool *preferred, bool audit, bool change) {
    Resolution r = {0};
    r.audit = audit;
    r.failure_depth = -1;
    memcpy(r.preferred, preferred, sizeof r.preferred);
    Requirement requirements[MAX_PACKAGES], *pending[MAX_PACKAGES];
    for (int i = 0; i < count; i++) {
        requirements[i] = (Requirement){list[i], NULL, NULL};
        pending[i] = &requirements[i];
    }
    if (search(&r, pending, count)) {
        plan(r.selected);
        if (change) update(list, count, r.selected);
    } else for (int i = 0; i < r.failure.count; i++) puts(r.failure.items[i]);
    clear_lines(&r.failure);
}

static int request_index(const char *name) {
    for (int i = 0; i < request_count; i++) if (!strcmp(requests[i]->name, name)) return i;
    return -1;
}

static const char *required_by(const char *name) {
    int order[MAX_PACKAGES];
    name_order(order);
    for (int j = 0; j < known_count; j++) {
        Package *p = installed[order[j]];
        if (!p) continue;
        for (int i = 0; i < p->dependency_count; i++) if (!strcmp(p->dependencies[i].name, name)) return p->name;
    }
    return "";
}

static void reachable(Clause **list, int count, bool *seen) {
    int queue[MAX_PACKAGES], head = 0, tail = 0;
    memset(seen, 0, MAX_PACKAGES * sizeof *seen);
    for (int i = 0; i < count; i++) {
        int n = known(list[i]->name);
        if (!seen[n]) {
            seen[n] = true;
            queue[tail++] = n;
        }
    }
    while (head < tail) {
        Package *p = installed[queue[head++]];
        for (int i = 0; i < p->dependency_count; i++) {
            int n = known(p->dependencies[i].name);
            if (!seen[n]) {
                seen[n] = true;
                queue[tail++] = n;
            }
        }
    }
}

static void tree(int n, const char *constraint, const char *prefix, const char *indent, bool *seen) {
    Package *p = installed[n];
    printf("%s%s@%s", prefix, p->name, p->version.text);
    if (constraint) printf(" [%s]", constraint);
    if (seen[n]) {
        puts(" (*)");
        return;
    }
    putchar('\n');
    seen[n] = true;
    for (int i = 0; i < p->dependency_count; i++) {
        Clause *d = &p->dependencies[i];
        bool last = i + 1 == p->dependency_count;
        char child_prefix[4 * MAX_PACKAGES + 5], child_indent[4 * MAX_PACKAGES + 5];
        snprintf(child_prefix, sizeof child_prefix, "%s%s", indent, last ? "`-- " : "|-- ");
        snprintf(child_indent, sizeof child_indent, "%s%s", indent, last ? "    " : "|   ");
        tree(known(d->name), d->text, child_prefix, child_indent, seen);
    }
}

static char *token(char **rest) {
    char *result = *rest, *space = strchr(result, ' ');
    if (space) {
        *space = '\0';
        *rest = space + 1;
    } else *rest = result + strlen(result);
    return result;
}

static void command(char *line) {
    char *rest = line, *c = token(&rest);
    if (!strcmp(c, "PKG")) {
        char *clauses[MAX_CLAUSES], *next = strstr(rest, "; ");
        int count = 0;
        if (next) {
            *next = '\0';
            next += 2;
        }
        char *name = token(&rest), *version = rest;
        Version v = checked_version(version);
        if (registered(name, version)) fail("%s@%s is already registered", name, version);
        while (next) {
            clauses[count++] = next;
            char *p = strstr(next, "; ");
            if (p) {
                *p = '\0';
                next = p + 2;
            } else next = NULL;
        }
        Package *p = allocate(sizeof *p);
        strcpy(p->name, name);
        p->version = v;
        for (int i = 0; i < count; i++) {
            char *r = clauses[i], *kind = token(&r), *other = token(&r);
            Clause *d = new_clause(other, r);
            if (!strcmp(kind, "DEP")) p->dependencies[p->dependency_count++] = *d;
            else p->conflicts[p->conflict_count++] = *d;
        }
        if (known(name) < 0) strcpy(known_names[known_count++], name);
        registry[version_count++] = p;
        printf("registered %s@%s\n", p->name, p->version.text);
    } else if (!strcmp(c, "YANK") || !strcmp(c, "INFO")) {
        char *name = token(&rest);
        Package *p = checked_package(name, rest);
        if (!strcmp(c, "YANK")) {
            if (p->yanked) fail("%s@%s is already yanked", p->name, p->version.text);
            p->yanked = true;
            printf("yanked %s@%s\n", p->name, p->version.text);
        } else {
            display(p);
            for (int i = 0; i < p->dependency_count; i++) printf("  requires %s %s\n", p->dependencies[i].name, p->dependencies[i].text);
            for (int i = 0; i < p->conflict_count; i++) printf("  conflicts with %s %s\n", p->conflicts[i].name, p->conflicts[i].text);
            for (int i = 0; i < advisory_count; i++) if (applies(&advisories[i], p)) printf("  advisory %s\n", advisories[i].id);
        }
    } else if (!strcmp(c, "VERSIONS") || !strcmp(c, "INSTALL") || !strcmp(c, "SIMULATE")) {
        char *name = token(&rest);
        Constraint *constraint = *rest ? checked_constraint(rest) : NULL;
        if (known(name) < 0) fail("unknown package %s", name);
        if (!strcmp(c, "VERSIONS")) {
            Package *list[MAX_VERSIONS];
            int count = versions(name, list), shown = 0;
            for (int i = 0; i < count; i++) if (!constraint || matches(constraint, &list[i]->version)) {
                display(list[i]);
                shown++;
            }
            if (!shown) puts("no matching versions");
        } else {
            Clause *r;
            if (!constraint) r = new_clause(name, "*");
            else {
                r = allocate(sizeof *r);
                strcpy(r->name, name);
                strcpy(r->text, rest);
                r->constraint = constraint;
            }
            Clause *list[MAX_PACKAGES];
            memcpy(list, requests, sizeof list);
            int count = request_count, i = request_index(name);
            if (i < 0) list[count++] = r;
            else list[i] = r;
            bool preferred[MAX_PACKAGES] = {false};
            for (int j = 0; j < known_count; j++) preferred[j] = installed[j] != NULL;
            resolve(list, count, preferred, false, !strcmp(c, "INSTALL"));
        }
    } else if (!strcmp(c, "DEPENDENTS")) {
        char *name = token(&rest);
        bool specified = *rest != '\0';
        Version v = {0};
        if (specified) v = checked_version(rest);
        int order[MAX_PACKAGES], shown = 0;
        name_order(order);
        for (int n = 0; n < known_count; n++) {
            Package *list[MAX_VERSIONS];
            int count = versions(known_names[order[n]], list);
            for (int j = 0; j < count; j++) for (int i = 0; i < list[j]->dependency_count; i++) {
                Clause *d = &list[j]->dependencies[i];
                if (!strcmp(d->name, name) && (!specified || matches(d->constraint, &v))) {
                    printf("%s@%s requires %s %s\n", list[j]->name, list[j]->version.text, name, d->text);
                    shown++;
                }
            }
        }
        if (!shown) puts("no dependents");
    } else if (!strcmp(c, "COMPARE")) {
        char *first = token(&rest);
        Version a = checked_version(first), b = checked_version(rest);
        int order = version_compare(&a, &b);
        printf("%s %c %s\n", first, order < 0 ? '<' : order > 0 ? '>' : '=', rest);
    } else if (!strcmp(c, "MATCH")) {
        char *text = token(&rest);
        Version v = checked_version(text);
        Constraint *constraint = checked_constraint(rest);
        puts(matches(constraint, &v) ? "yes" : "no");
    } else if (!strcmp(c, "RANGE")) {
        Constraint *constraint = checked_constraint(rest);
        for (int i = 0; i < constraint->count; i++) {
            Alternative *a = &constraint->alternatives[i];
            if (i) fputs(" || ", stdout);
            if (!a->count) putchar('*');
            for (int j = 0; j < a->count; j++) {
                if (j) putchar(' ');
                printf("%s%s", operators[a->comparators[j].op], a->comparators[j].version.text);
            }
        }
        putchar('\n');
    } else if (!strcmp(c, "REMOVE")) {
        int index = request_index(rest), n = known(rest);
        if (index < 0) {
            if (n >= 0 && installed[n]) fail("%s is required by %s", rest, required_by(rest));
            fail("%s is not installed", rest);
        }
        Clause *list[MAX_PACKAGES];
        int count = 0;
        for (int i = 0; i < request_count; i++) if (i != index) list[count++] = requests[i];
        bool keep[MAX_PACKAGES];
        reachable(list, count, keep);
        if (keep[n]) {
            printf("%s@%s is still required by %s\n", rest, installed[n]->version.text, required_by(rest));
            update(list, count, installed);
        } else {
            Package *next[MAX_PACKAGES] = {0};
            for (int i = 0; i < known_count; i++) if (keep[i]) next[i] = installed[i];
            plan(next);
            update(list, count, next);
        }
    } else if (!strcmp(c, "UPGRADE")) {
        int n = *rest ? known(rest) : -1;
        if (*rest && (n < 0 || !installed[n])) fail("%s is not installed", rest);
        bool preferred[MAX_PACKAGES] = {false};
        if (*rest) for (int i = 0; i < known_count; i++) preferred[i] = installed[i] && i != n;
        resolve(requests, request_count, preferred, false, true);
    } else if (!strcmp(c, "ROLLBACK")) {
        if (!history) fail("nothing to roll back");
        Snapshot *snapshot = history;
        history = snapshot->previous;
        history_count--;
        plan(snapshot->installed);
        memcpy(requests, snapshot->requests, sizeof requests);
        request_count = snapshot->request_count;
        memcpy(installed, snapshot->installed, sizeof installed);
        prune_holds();
        free(snapshot);
    } else if (!strcmp(c, "HOLD")) {
        int n = known(rest);
        if (n < 0 || !installed[n]) fail("%s is not installed", rest);
        if (held[n]) fail("%s is already held", rest);
        held[n] = true;
        printf("held %s@%s\n", rest, installed[n]->version.text);
    } else if (!strcmp(c, "UNHOLD")) {
        int n = known(rest);
        if (n < 0 || !held[n]) fail("%s is not held", rest);
        held[n] = false;
        printf("released %s\n", rest);
    } else if (!strcmp(c, "WHY")) {
        int n = known(rest);
        if (n < 0 || !installed[n]) fail("%s is not installed", rest);
        if (request_index(rest) >= 0) printf("%s@%s is explicitly installed\n", rest, installed[n]->version.text);
        else {
            int parent[MAX_PACKAGES], queue[MAX_PACKAGES], head = 0, tail = 0, order[MAX_PACKAGES];
            name_order(order);
            for (int i = 0; i < known_count; i++) parent[i] = -2;
            for (int j = 0; j < known_count; j++) {
                int i = order[j];
                if (request_index(known_names[i]) >= 0) {
                    parent[i] = -1;
                    queue[tail++] = i;
                }
            }
            while (head < tail) {
                int u = queue[head++];
                Package *p = installed[u];
                for (int j = 0; j < known_count; j++) {
                    int v = order[j];
                    if (parent[v] != -2) continue;
                    for (int i = 0; i < p->dependency_count; i++) if (!strcmp(p->dependencies[i].name, known_names[v])) {
                        parent[v] = u;
                        queue[tail++] = v;
                        break;
                    }
                }
            }
            int path[MAX_PACKAGES], count = 0;
            for (int v = n; v >= 0; v = parent[v]) path[count++] = v;
            for (int i = count - 1; i >= 0; i--) {
                Package *p = installed[path[i]];
                if (i != count - 1) fputs(" -> ", stdout);
                printf("%s@%s", p->name, p->version.text);
            }
            putchar('\n');
        }
    } else if (!strcmp(c, "TREE")) {
        bool seen[MAX_PACKAGES] = {false};
        if (*rest) {
            int n = known(rest);
            if (n < 0 || !installed[n]) fail("%s is not installed", rest);
            int r = request_index(rest);
            tree(n, r < 0 ? NULL : requests[r]->text, "", "", seen);
        } else if (!request_count) puts("(empty)");
        else {
            int order[MAX_PACKAGES];
            name_order(order);
            for (int j = 0; j < known_count; j++) {
                int n = order[j], r = request_index(known_names[n]);
                if (r >= 0) tree(n, requests[r]->text, "", "", seen);
            }
        }
    } else if (!strcmp(c, "OUTDATED")) {
        int order[MAX_PACKAGES], shown = 0;
        name_order(order);
        for (int j = 0; j < known_count; j++) {
            int n = order[j];
            Package *p = installed[n];
            if (!p) continue;
            Package *list[MAX_VERSIONS], *wanted = NULL, *latest = NULL;
            int count = versions(p->name, list), r = request_index(p->name);
            for (int k = 0; k < count; k++) {
                Package *q = list[k];
                if (!latest && !q->yanked && !*q->version.pre) latest = q;
                if (wanted || (q->yanked && q != p)) continue;
                bool valid = r < 0 || matches(requests[r]->constraint, &q->version);
                for (int u = 0; u < known_count && valid; u++) if (installed[u]) for (int i = 0; i < installed[u]->dependency_count; i++) {
                    Clause *d = &installed[u]->dependencies[i];
                    if (!strcmp(d->name, p->name) && !matches(d->constraint, &q->version)) valid = false;
                }
                if (valid) wanted = q;
            }
            if (wanted != p || (latest && version_compare(&latest->version, &p->version) > 0)) {
                printf("%s %s %s %s\n", p->name, p->version.text, wanted->version.text, latest ? latest->version.text : "-");
                shown++;
            }
        }
        if (!shown) puts("all packages are up to date");
    } else if (!strcmp(c, "LOCK")) {
        int order[MAX_PACKAGES], count = 0;
        name_order(order);
        for (int j = 0; j < known_count; j++) {
            Package *p = installed[order[j]];
            if (p) {
                printf("%s@%s\n", p->name, p->version.text);
                count++;
            }
        }
        if (!count) puts("(empty)");
    } else if (!strcmp(c, "STATUS")) {
        for (int i = 0; i < request_count; i++) {
            Clause *r = requests[i];
            printf("%s %s -> %s\n", r->name, r->text, installed[known(r->name)]->version.text);
        }
        if (!request_count) puts("no requests");
        int count = 0, held_count = 0;
        for (int i = 0; i < known_count; i++) {
            count += installed[i] != NULL;
            held_count += held[i];
        }
        printf("%d installed, %d held, %d snapshots\n", count, held_count, history_count);
    } else if (!strcmp(c, "ADVISORY")) {
        char *id = token(&rest), *name = token(&rest);
        for (int i = 0; i < advisory_count; i++) if (!strcmp(advisories[i].id, id)) fail("advisory %s already exists", id);
        Clause *d = new_clause(name, rest);
        Advisory *a = &advisories[advisory_count++];
        strcpy(a->id, id);
        a->clause = *d;
        qsort(advisories, (size_t)advisory_count, sizeof *advisories, advisory_compare);
        printf("advisory %s recorded\n", id);
    } else if (!strcmp(c, "AUDIT")) {
        if (!strcmp(rest, "FIX")) {
            bool preferred[MAX_PACKAGES] = {false};
            for (int i = 0; i < known_count; i++) preferred[i] = installed[i] != NULL;
            resolve(requests, request_count, preferred, true, true);
        } else {
            int order[MAX_PACKAGES], shown = 0;
            name_order(order);
            for (int j = 0; j < known_count; j++) {
                Package *p = installed[order[j]];
                if (!p || !vulnerable(p)) continue;
                printf("%s@%s: ", p->name, p->version.text);
                bool first = true;
                for (int i = 0; i < advisory_count; i++) if (applies(&advisories[i], p)) {
                    if (!first) fputs(", ", stdout);
                    fputs(advisories[i].id, stdout);
                    first = false;
                }
                Package *list[MAX_VERSIONS], *fix = NULL;
                int count = versions(p->name, list);
                for (int k = 0; k < count; k++) {
                    Package *q = list[k];
                    if (version_compare(&q->version, &p->version) > 0 && !*q->version.pre && !q->yanked && !vulnerable(q)) fix = q;
                }
                if (fix) printf(" (fix: %s)\n", fix->version.text);
                else puts(" (no fix)");
                shown++;
            }
            if (!shown) puts("no known vulnerabilities");
        }
    }
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = malloc(capacity);
    int ch;
    if (!line) exit(EXIT_FAILURE);
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            char *p = realloc(line, capacity);
            if (!p) exit(EXIT_FAILURE);
            line = p;
        }
        line[length++] = (char)ch;
    }
    line[length] = '\0';
    return line;
}
int main(void) {
    char *line = read_line();
    int n = atoi(line);
    free(line);
    for (int i = 0; i < n; i++) {
        line = read_line();
        if (setjmp(command_error) == 0) command(line);
        free(line);
    }
    while (history) {
        Snapshot *previous = history->previous;
        free(history);
        history = previous;
    }
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->pointer);
        free(allocations);
        allocations = next;
    }
    return 0;
}
