#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAX_TASKS 30
#define MAX_DEPS 100
#define MAX_HOLIDAYS 100
#define MAX_PATHS 100
typedef struct {
    char name[9], resource[9];
    int base, units, not_before, crashed, crash_limit, crash_cost, estimate[3];
    bool has_crash, has_estimate;
} Task;
typedef struct {
    Task *a, *b;
    int kind, lag;
} Dependency;
typedef struct {
    char resource[9];
    int limit;
} Capacity;
typedef struct {
    int duration, es, ef, ls, lf, tf, free;
} Timing;
typedef struct {
    Timing times[MAX_TASKS];
    int total;
} Schedule;
typedef struct {
    int count, lengths[MAX_PATHS], vertices[MAX_PATHS][MAX_TASKS];
} Paths;
typedef struct {
    char name[9];
    int es, ef;
} BaselineTask;
typedef struct {
    char *resource;
    int *days, length;
} Load;
static Task *tasks[MAX_TASKS];
static int task_count, dep_count, holiday_count;
static Dependency dependencies[MAX_DEPS];
static int holidays[MAX_HOLIDAYS], start_date = -1, deadline = -1;
static Capacity *capacities;
static int capacity_count;
static BaselineTask baseline[MAX_TASKS];
static int baseline_count, baseline_total;
static bool has_baseline;
static jmp_buf command_error;
static const char *kinds[] = {"FS", "SS", "FF"};

static void *allocate(size_t size) {
    void *p = calloc(1, size);
    if (!p) exit(EXIT_FAILURE);
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

static int maximum(int a, int b) {
    return a > b ? a : b;
}

static int minimum(int a, int b) {
    return a < b ? a : b;
}

static int duration(Task *t) {
    return t->base - t->crashed;
}

static int task_compare(const void *a, const void *b) {
    return strcmp((*(Task *const *)a)->name, (*(Task *const *)b)->name);
}

static int string_compare(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static int int_compare(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}

static Task *find_task(const char *name) {
    for (int i = 0; i < task_count; i++) if (!strcmp(tasks[i]->name, name)) return tasks[i];
    return NULL;
}

static Task *task(const char *name) {
    Task *t = find_task(name);
    if (!t) fail("unknown task %s", name);
    return t;
}

static int index_of(Task *t) {
    for (int i = 0; i < task_count; i++) if (tasks[i] == t) return i;
    return -1;
}

static int dependency(Task *a, Task *b) {
    for (int i = 0; i < dep_count; i++) if (dependencies[i].a == a && dependencies[i].b == b) return i;
    return -1;
}

static int topological(int *order, bool *remaining) {
    for (int i = 0; i < task_count; i++) remaining[i] = true;
    int count = 0;
    for (;;) {
        int next = -1;
        for (int v = 0; v < task_count; v++) if (remaining[v]) {
            bool ready = true;
            for (int i = 0; i < dep_count; i++) if (dependencies[i].b == tasks[v] && remaining[index_of(dependencies[i].a)]) {
                ready = false;
                break;
            }
            if (ready) {
                next = v;
                break;
            }
        }
        if (next < 0) break;
        order[count++] = next;
        remaining[next] = false;
    }
    return count;
}

static bool cycle(char *text) {
    int order[MAX_TASKS];
    bool remaining[MAX_TASKS];
    if (topological(order, remaining) == task_count) return false;
    int current = 0;
    while (!remaining[current]) current++;
    int chain[MAX_TASKS], count = 0, repeated;
    for (;;) {
        repeated = -1;
        for (int i = 0; i < count; i++) if (chain[i] == current) {
            repeated = i;
            break;
        }
        if (repeated >= 0) break;
        chain[count++] = current;
        for (int u = 0; u < task_count; u++) if (remaining[u] && dependency(tasks[u], tasks[current]) >= 0) {
            current = u;
            break;
        }
    }
    int vertices[MAX_TASKS], length = 0, first = 0;
    vertices[length++] = current;
    for (int i = count - 1; i > repeated; i--) vertices[length++] = chain[i];
    for (int i = 1; i < length; i++) if (vertices[i] < vertices[first]) first = i;
    text[0] = '\0';
    for (int i = 0; i <= length; i++) {
        if (i) strcat(text, " -> ");
        strcat(text, tasks[vertices[(first + i) % length]]->name);
    }
    return true;
}

static int margin(Schedule *s, Dependency *d) {
    Timing *a = &s->times[index_of(d->a)], *b = &s->times[index_of(d->b)];
    return (d->kind == 2 ? b->ef : b->es) - (d->kind == 1 ? a->es : a->ef) - d->lag;
}

static Schedule compute(Task *changed, int changed_duration) {
    Schedule s = {0};
    int order[MAX_TASKS];
    bool remaining[MAX_TASKS];
    topological(order, remaining);
    for (int k = 0; k < task_count; k++) {
        int v = order[k];
        Task *t = tasks[v];
        Timing *x = &s.times[v];
        x->duration = t == changed ? changed_duration : duration(t);
        x->es = t->not_before;
        for (int i = 0; i < dep_count; i++) if (dependencies[i].b == t) {
            Dependency *d = &dependencies[i];
            Timing *a = &s.times[index_of(d->a)];
            int bound = (d->kind == 1 ? a->es : a->ef) + d->lag - (d->kind == 2 ? x->duration : 0);
            x->es = maximum(x->es, bound);
        }
        x->ef = x->es + x->duration;
        s.total = maximum(s.total, x->ef);
    }
    for (int k = task_count - 1; k >= 0; k--) {
        int v = order[k];
        Timing *x = &s.times[v];
        x->lf = s.total;
        for (int i = 0; i < dep_count; i++) if (dependencies[i].a == tasks[v]) {
            Dependency *d = &dependencies[i];
            Timing *b = &s.times[index_of(d->b)];
            int bound = (d->kind == 2 ? b->lf : b->ls) - d->lag + (d->kind == 1 ? x->duration : 0);
            x->lf = minimum(x->lf, bound);
        }
        x->ls = x->lf - x->duration;
        x->tf = x->ls - x->es;
        x->free = s.total - x->ef;
        for (int i = 0; i < dep_count; i++) if (dependencies[i].a == tasks[v]) x->free = minimum(x->free, margin(&s, &dependencies[i]));
    }
    return s;
}

static bool critical_dependency(Schedule *s, int a, int b) {
    int i = dependency(tasks[a], tasks[b]);
    return i >= 0 && s->times[a].tf == 0 && s->times[b].tf == 0 && margin(s, &dependencies[i]) == 0;
}

static void path_visit(Schedule *s, Paths *paths, int *path, int length, int v) {
    path[length++] = v;
    bool leaf = true;
    for (int w = 0; w < task_count; w++) if (critical_dependency(s, v, w)) {
        leaf = false;
        path_visit(s, paths, path, length, w);
    }
    if (leaf) {
        paths->lengths[paths->count] = length;
        memcpy(paths->vertices[paths->count++], path, (size_t)length * sizeof *path);
    }
}

static Paths critical_paths(Schedule *s) {
    Paths result = {0};
    int path[MAX_TASKS];
    for (int v = 0; v < task_count; v++) if (s->times[v].tf == 0) {
        bool root = true;
        for (int u = 0; u < task_count; u++) if (critical_dependency(s, u, v)) root = false;
        if (root) path_visit(s, &result, path, 0, v);
    }
    return result;
}

static void fraction(long long numerator, int denominator) {
    long long h = numerator * 100 / denominator;
    printf("%lld.%02lld", h / 100, h % 100);
}

static void name_list(const bool *included) {
    bool first = true;
    for (int i = 0; i < task_count; i++) if (included[i]) {
        if (!first) putchar(' ');
        fputs(tasks[i]->name, stdout);
        first = false;
    }
    if (first) fputs("none", stdout);
}

static bool leap(int year) {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

static int month_days(int year, int month) {
    const int lengths[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return lengths[month - 1] + (month == 2 && leap(year));
}

static int parse_date(const char *text) {
    int year, month, day;
    sscanf(text, "%d-%d-%d", &year, &month, &day);
    if (month < 1 || month > 12 || day < 1 || day > month_days(year, month)) fail("invalid date %s", text);
    int serial = day - 1;
    for (int y = 2000; y < year; y++) serial += leap(y) ? 366 : 365;
    for (int m = 1; m < month; m++) serial += month_days(year, m);
    return serial;
}

static void print_date(int serial) {
    const char *weekdays[] = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
    int year = 2000, month = 1, day = serial;
    while (day >= (leap(year) ? 366 : 365)) {
        day -= leap(year) ? 366 : 365;
        year++;
    }
    while (day >= month_days(year, month)) {
        day -= month_days(year, month);
        month++;
    }
    printf("%04d-%02d-%02d %s", year, month, day + 1, weekdays[(serial + 5) % 7]);
}

static bool weekday(int day) {
    return (day + 5) % 7 < 5;
}

static bool working(int day) {
    if (!weekday(day)) return false;
    for (int i = 0; i < holiday_count; i++) if (holidays[i] == day) return false;
    return true;
}

static int working_between(int a, int b) {
    int count = 0;
    for (int day = a + 1; day <= b; day++) count += working(day);
    return count;
}

static int capacity_index(const char *resource) {
    for (int i = 0; i < capacity_count; i++) if (!strcmp(capacities[i].resource, resource)) return i;
    return -1;
}

static int capacity(const char *resource, int fallback) {
    int i = capacity_index(resource);
    return i < 0 ? fallback : capacities[i].limit;
}

static int resources(char **names) {
    int count = 0;
    for (int i = 0; i < task_count; i++) {
        bool found = false;
        for (int j = 0; j < count; j++) if (!strcmp(names[j], tasks[i]->resource)) found = true;
        if (!found) names[count++] = tasks[i]->resource;
    }
    qsort(names, (size_t)count, sizeof *names, string_compare);
    return count;
}

static int *usage(Schedule *s, const char *resource) {
    int *load = allocate((size_t)s->total * sizeof *load);
    for (int i = 0; i < task_count; i++) if (!strcmp(tasks[i]->resource, resource)) for (int day = s->times[i].es; day < s->times[i].ef; day++) load[day] += tasks[i]->units;
    return load;
}

static int peak(const int *load, int count) {
    int result = 0;
    for (int i = 0; i < count; i++) result = maximum(result, load[i]);
    return result;
}

static void start_order(Schedule *s, int *order) {
    for (int i = 0; i < task_count; i++) order[i] = i;
    for (int i = 1; i < task_count; i++) {
        int v = order[i], j = i;
        while (j && (s->times[order[j - 1]].es > s->times[v].es || (s->times[order[j - 1]].es == s->times[v].es && order[j - 1] > v))) {
            order[j] = order[j - 1];
            j--;
        }
        order[j] = v;
    }
}

static void ensure_load(Load *load, int length) {
    if (load->length >= length) return;
    int size = maximum(length, maximum(16, load->length * 2));
    int *days = realloc(load->days, (size_t)size * sizeof *days);
    if (!days) exit(EXIT_FAILURE);
    memset(days + load->length, 0, (size_t)(size - load->length) * sizeof *days);
    load->days = days;
    load->length = size;
}

static void level(Schedule *s, int limit) {
    char *names[MAX_TASKS];
    int resource_count = resources(names);
    Load loads[MAX_TASKS] = {0};
    for (int i = 0; i < resource_count; i++) loads[i].resource = names[i];
    bool decided[MAX_TASKS] = {false};
    int starts[MAX_TASKS], finishes[MAX_TASKS], order[MAX_TASKS], total = 0;
    for (int step = 0; step < task_count; step++) {
        int v = -1;
        for (int i = 0; i < task_count; i++) if (!decided[i]) {
            bool ready = true;
            for (int j = 0; j < dep_count; j++) if (dependencies[j].b == tasks[i] && !decided[index_of(dependencies[j].a)]) ready = false;
            if (ready && (v < 0 || s->times[i].ls < s->times[v].ls)) v = i;
        }
        Task *t = tasks[v];
        int begin = t->not_before, d = duration(t), cap = capacity(t->resource, limit);
        for (int i = 0; i < dep_count; i++) if (dependencies[i].b == t) {
            Dependency *dep = &dependencies[i];
            int a = index_of(dep->a);
            begin = maximum(begin, (dep->kind == 1 ? starts[a] : finishes[a]) + dep->lag - (dep->kind == 2 ? d : 0));
        }
        int r = 0;
        while (strcmp(names[r], t->resource)) r++;
        Load *load = &loads[r];
        for (;;) {
            ensure_load(load, begin + d);
            bool fits = true;
            for (int k = begin; k < begin + d; k++) if (load->days[k] + t->units > cap) {
                fits = false;
                break;
            }
            if (fits) break;
            begin++;
        }
        starts[v] = begin;
        finishes[v] = begin + d;
        for (int k = begin; k < finishes[v]; k++) load->days[k] += t->units;
        order[step] = v;
        decided[v] = true;
        total = maximum(total, finishes[v]);
    }
    printf("level capacity %d: duration %d -> %d\n", limit, s->total, total);
    for (int i = 0; i < task_count; i++) {
        int v = order[i];
        printf("%s start %d finish %d shift %d\n", tasks[v]->name, starts[v], finishes[v], starts[v] - s->times[v].es);
    }
    for (int r = 0; r < resource_count; r++) {
        int *original = usage(s, names[r]);
        printf("resource %s capacity %d peak %d -> %d\n", names[r], capacity(names[r], limit), peak(original, s->total), peak(loads[r].days, loads[r].length));
        free(original);
        free(loads[r].days);
    }
}

static void analysis(const char *c, char **w) {
    if (!task_count) fail("no tasks");
    char cycle_text[(MAX_TASKS + 1) * 13];
    if (cycle(cycle_text)) fail("cycle %s", cycle_text);
    if (!strcmp(c, "CALENDAR") && start_date < 0) fail("no start date");
    if (!strcmp(c, "WHATIF")) task(w[1]);
    if (!strcmp(c, "VARIANCE") && !has_baseline) fail("no baseline");
    if (!strcmp(c, "LOAD")) {
        bool found = false;
        for (int i = 0; i < task_count; i++) if (!strcmp(tasks[i]->resource, w[1])) found = true;
        if (!found) fail("unknown resource %s", w[1]);
    }
    if (!strcmp(c, "LEVEL")) for (int i = 0; i < task_count; i++) {
        int cap = capacity(tasks[i]->resource, atoi(w[1]));
        if (tasks[i]->units > cap) fail("capacity %d too small for %s", cap, tasks[i]->name);
    }
    Schedule s = compute(NULL, 0);
    if (!strcmp(c, "CPM")) {
        int width = 4;
        for (int i = 0; i < task_count; i++) width = maximum(width, (int)strlen(tasks[i]->name));
        printf("%-*s%5s%5s%5s%5s%5s%5s%5s\n", width, "TASK", "DUR", "ES", "EF", "LS", "LF", "TF", "FF");
        for (int i = 0; i < task_count; i++) {
            Timing *x = &s.times[i];
            printf("%-*s%5d%5d%5d%5d%5d%5d%5d%s\n", width, tasks[i]->name, x->duration, x->es, x->ef, x->ls, x->lf, x->tf, x->free, x->tf == 0 ? " *" : "");
        }
        printf("project duration %d\n", s.total);
    } else if (!strcmp(c, "CRITICAL") || !strcmp(c, "PERTSUM")) {
        Paths paths = critical_paths(&s);
        if (!strcmp(c, "CRITICAL")) printf("critical paths: %d\n", paths.count);
        for (int i = 0; i < paths.count; i++) {
            long long expected = 0, variance = 0;
            for (int j = 0; j < paths.lengths[i]; j++) {
                Task *t = tasks[paths.vertices[i][j]];
                if (j) fputs(" -> ", stdout);
                fputs(t->name, stdout);
                int o = duration(t), m = o, p = o;
                if (t->has_estimate) {
                    o = t->estimate[0];
                    m = t->estimate[1];
                    p = t->estimate[2];
                }
                expected += o + 4LL * m + p;
                variance += (long long)(p - o) * (p - o);
            }
            if (!strcmp(c, "PERTSUM")) {
                fputs(": expected ", stdout);
                fraction(expected, 6);
                fputs(" variance ", stdout);
                fraction(variance, 36);
            }
            putchar('\n');
        }
    } else if (!strcmp(c, "SLACK")) {
        int floats[MAX_TASKS], count = 0;
        for (int i = 0; i < task_count; i++) {
            bool found = false;
            for (int j = 0; j < count; j++) if (floats[j] == s.times[i].tf) found = true;
            if (!found) floats[count++] = s.times[i].tf;
        }
        qsort(floats, (size_t)count, sizeof *floats, int_compare);
        for (int i = 0; i < count; i++) {
            bool included[MAX_TASKS] = {false};
            for (int j = 0; j < task_count; j++) included[j] = s.times[j].tf == floats[i];
            printf("float %d: ", floats[i]);
            name_list(included);
            putchar('\n');
        }
    } else if (!strcmp(c, "DRAG")) {
        for (int i = 0; i < task_count; i++) if (s.times[i].tf == 0) {
            Schedule after = compute(tasks[i], 0);
            printf("%s drag %d\n", tasks[i]->name, s.total - after.total);
        }
    } else if (!strcmp(c, "STATS")) {
        int critical = 0, total_float = 0, counts[3] = {0};
        for (int i = 0; i < task_count; i++) {
            critical += s.times[i].tf == 0;
            total_float += s.times[i].tf;
        }
        for (int i = 0; i < dep_count; i++) counts[dependencies[i].kind]++;
        printf("tasks %d, critical %d, dependencies %d (FS %d, SS %d, FF %d)\nwork ", task_count, critical, dep_count, counts[0], counts[1], counts[2]);
        char *names[MAX_TASKS];
        int count = resources(names);
        for (int r = 0; r < count; r++) {
            int work = 0;
            for (int i = 0; i < task_count; i++) if (!strcmp(tasks[i]->resource, names[r])) work += duration(tasks[i]) * tasks[i]->units;
            if (r) fputs(", ", stdout);
            printf("%s %d", names[r], work);
        }
        printf("\nfloat total %d, average ", total_float);
        fraction(total_float, task_count);
        printf("\nduration %d, critical share ", s.total);
        fraction(100LL * critical, task_count);
        puts("%");
    } else if (!strcmp(c, "CALENDAR")) {
        int *days = allocate((size_t)s.total * sizeof *days), count = 0;
        for (int day = start_date; count < s.total; day++) if (working(day)) days[count++] = day;
        int order[MAX_TASKS];
        start_order(&s, order);
        for (int i = 0; i < task_count; i++) {
            int v = order[i];
            printf("%s ", tasks[v]->name);
            print_date(days[s.times[v].es]);
            fputs(" - ", stdout);
            print_date(days[s.times[v].ef - 1]);
            putchar('\n');
        }
        int first = days[0], last = days[s.total - 1];
        fputs("project ", stdout);
        print_date(first);
        fputs(" - ", stdout);
        print_date(last);
        printf(", %d working days, %d calendar days\n", s.total, last - first + 1);
        if (deadline >= 0) {
            fputs("deadline ", stdout);
            print_date(deadline);
            if (last <= deadline) printf(" met, %d working days to spare\n", working_between(last, deadline));
            else printf(" missed by %d working days\n", working_between(deadline, last));
        }
        fputs("holidays in span: ", stdout);
        bool any = false;
        for (int i = 0; i < holiday_count; i++) if (weekday(holidays[i]) && holidays[i] >= first && holidays[i] <= last) {
            if (any) fputs(", ", stdout);
            print_date(holidays[i]);
            any = true;
        }
        if (!any) fputs("none", stdout);
        putchar('\n');
        free(days);
    } else if (!strcmp(c, "GANTT")) {
        if (s.total > 60) fail("chart too wide (%d days)", s.total);
        int width = 0, order[MAX_TASKS];
        for (int i = 0; i < task_count; i++) width = maximum(width, (int)strlen(tasks[i]->name));
        printf("%*s |", width, "");
        for (int day = 0; day < s.total; day++) printf("%d", day % 10);
        puts("|");
        start_order(&s, order);
        for (int i = 0; i < task_count; i++) {
            int v = order[i];
            Timing *x = &s.times[v];
            printf("%-*s |", width, tasks[v]->name);
            for (int day = 0; day < s.total; day++) putchar(x->es <= day && day < x->ef ? (x->tf == 0 ? '=' : '-') : x->ef <= day && day < x->lf ? '.' : ' ');
            puts("|");
        }
    } else if (!strcmp(c, "LEVEL")) level(&s, atoi(w[1]));
    else if (!strcmp(c, "LOAD")) {
        int *load = usage(&s, w[1]), highest = peak(load, s.total), day = 0;
        printf("load %s:", w[1]);
        for (int i = 0; i < s.total; i++) printf(" %d", load[i]);
        while (load[day] != highest) day++;
        printf("\npeak %d on day %d\n", highest, day);
        int cap_index = capacity_index(w[1]);
        if (cap_index >= 0) {
            int exceeded = 0, cap = capacities[cap_index].limit;
            for (int i = 0; i < s.total; i++) exceeded += load[i] > cap;
            printf("capacity %d exceeded on %d days\n", cap, exceeded);
        }
        free(load);
    } else if (!strcmp(c, "CRASH")) {
        int budget = atoi(w[1]), remaining = budget, initial = s.total, steps = 0;
        const char *reason;
        for (;;) {
            Task *candidate = NULL;
            for (int i = 0; i < task_count; i++) {
                Task *t = tasks[i];
                if (s.times[i].tf != 0 || !t->has_crash || t->crashed >= t->crash_limit) continue;
                Schedule after = compute(t, duration(t) - 1);
                if (after.total < s.total && (!candidate || t->crash_cost < candidate->crash_cost)) candidate = t;
            }
            if (!candidate) {
                reason = "no candidate";
                break;
            }
            if (candidate->crash_cost > remaining) {
                reason = "insufficient budget";
                break;
            }
            int before = duration(candidate);
            candidate->crashed++;
            remaining -= candidate->crash_cost;
            s = compute(NULL, 0);
            printf("step %d: %s %d -> %d, cost %d, project %d\n", ++steps, candidate->name, before, duration(candidate), candidate->crash_cost, s.total);
        }
        printf("crash done: %d days, cost %d, project %d -> %d, budget left %d, %s\n", steps, budget - remaining, initial, s.total, remaining, reason);
    } else if (!strcmp(c, "WHATIF")) {
        Task *t = task(w[1]);
        Schedule after = compute(t, atoi(w[2]));
        printf("whatif %s %d -> %s: project %d -> %d\n", t->name, duration(t), w[2], s.total, after.total);
        bool changed_critical = false;
        for (int i = 0; i < task_count; i++) {
            Timing *a = &s.times[i], *b = &after.times[i];
            changed_critical |= (a->tf == 0) != (b->tf == 0);
            if (a->es == b->es && a->ef == b->ef && a->tf == b->tf) continue;
            fputs(tasks[i]->name, stdout);
            if (a->es != b->es) printf(" ES %d->%d", a->es, b->es);
            if (a->ef != b->ef) printf(" EF %d->%d", a->ef, b->ef);
            if (a->tf != b->tf) printf(" TF %d->%d", a->tf, b->tf);
            putchar('\n');
        }
        if (changed_critical) {
            bool before[MAX_TASKS], later[MAX_TASKS];
            for (int i = 0; i < task_count; i++) {
                before[i] = s.times[i].tf == 0;
                later[i] = after.times[i].tf == 0;
            }
            fputs("critical ", stdout);
            name_list(before);
            fputs(" -> ", stdout);
            name_list(later);
            putchar('\n');
        }
    } else if (!strcmp(c, "BASELINE")) {
        baseline_count = task_count;
        baseline_total = s.total;
        has_baseline = true;
        for (int i = 0; i < task_count; i++) {
            strcpy(baseline[i].name, tasks[i]->name);
            baseline[i].es = s.times[i].es;
            baseline[i].ef = s.times[i].ef;
        }
        printf("baseline saved: %d tasks, duration %d\n", task_count, s.total);
    } else if (!strcmp(c, "VARIANCE")) {
        printf("variance: duration %d -> %d (%+d)\n", baseline_total, s.total, s.total - baseline_total);
        int a = 0, b = 0;
        bool changed = false;
        while (a < task_count || b < baseline_count) {
            int order = a == task_count ? 1 : b == baseline_count ? -1 : strcmp(tasks[a]->name, baseline[b].name);
            if (order < 0) {
                printf("%s new\n", tasks[a++]->name);
                changed = true;
            } else if (order > 0) {
                printf("%s removed\n", baseline[b++].name);
                changed = true;
            } else {
                Timing *x = &s.times[a];
                BaselineTask *old = &baseline[b];
                if (x->es != old->es || x->ef != old->ef) {
                    printf("%s start %+d finish %+d\n", tasks[a]->name, x->es - old->es, x->ef - old->ef);
                    changed = true;
                }
                a++;
                b++;
            }
        }
        if (!changed) puts("no task changes");
    }
}

static void command(char *line) {
    char *w[6];
    int count = 0;
    for (char *p = strtok(line, " "); p; p = strtok(NULL, " ")) w[count++] = p;
    const char *c = w[0];
    if (!strcmp(c, "TASK")) {
        if (find_task(w[1])) fail("task %s already exists", w[1]);
        Task *t = allocate(sizeof *t);
        strcpy(t->name, w[1]);
        strcpy(t->resource, w[3]);
        t->base = atoi(w[2]);
        t->units = atoi(w[4]);
        tasks[task_count++] = t;
        qsort(tasks, (size_t)task_count, sizeof *tasks, task_compare);
        printf("task %s added\n", t->name);
    } else if (!strcmp(c, "DEP") || !strcmp(c, "UNDEP")) {
        Task *a = task(w[1]), *b = task(w[2]);
        int i = dependency(a, b);
        if (!strcmp(c, "DEP")) {
            if (a == b) fail("self dependency %s", a->name);
            if (i >= 0) fail("dependency %s -> %s already exists", a->name, b->name);
            int kind = !strcmp(w[3], "FS") ? 0 : !strcmp(w[3], "SS") ? 1 : 2, lag = atoi(w[4]);
            dependencies[dep_count++] = (Dependency){a, b, kind, lag};
            printf("dependency %s -> %s %s%+d added\n", a->name, b->name, kinds[kind], lag);
        } else {
            if (i < 0) fail("no dependency %s -> %s", a->name, b->name);
            memmove(dependencies + i, dependencies + i + 1, (size_t)(dep_count - i - 1) * sizeof *dependencies);
            dep_count--;
            printf("dependency %s -> %s removed\n", a->name, b->name);
        }
    } else if (!strcmp(c, "REMOVE")) {
        Task *t = task(w[1]);
        int removed = 0;
        for (int i = dep_count - 1; i >= 0; i--) if (dependencies[i].a == t || dependencies[i].b == t) {
            memmove(dependencies + i, dependencies + i + 1, (size_t)(dep_count - i - 1) * sizeof *dependencies);
            dep_count--;
            removed++;
        }
        int i = index_of(t);
        memmove(tasks + i, tasks + i + 1, (size_t)(task_count - i - 1) * sizeof *tasks);
        task_count--;
        printf("task %s removed with %d dependencies\n", t->name, removed);
        free(t);
    } else if (!strcmp(c, "NOTBEFORE") || !strcmp(c, "CRASHCOST") || !strcmp(c, "UNCRASH") || !strcmp(c, "PERT")) {
        Task *t = task(w[1]);
        if (!strcmp(c, "NOTBEFORE")) {
            t->not_before = atoi(w[2]);
            printf("notbefore %s %d\n", t->name, t->not_before);
        } else if (!strcmp(c, "CRASHCOST")) {
            int limit = atoi(w[2]);
            if (limit >= t->base) fail("crash limit too large for %s", t->name);
            if (limit < t->crashed) fail("crash limit below used days for %s", t->name);
            t->has_crash = true;
            t->crash_limit = limit;
            t->crash_cost = atoi(w[3]);
            printf("crash %s max %d cost %d\n", t->name, limit, t->crash_cost);
        } else if (!strcmp(c, "UNCRASH")) {
            printf("uncrash %s restored %d days\n", t->name, t->crashed);
            t->crashed = 0;
        } else {
            int o = atoi(w[2]), m = atoi(w[3]), p = atoi(w[4]);
            if (o > m || m > p) fail("invalid estimate");
            t->has_estimate = true;
            t->estimate[0] = o;
            t->estimate[1] = m;
            t->estimate[2] = p;
            printf("pert %s expected ", t->name);
            fraction(o + 4LL * m + p, 6);
            fputs(" variance ", stdout);
            fraction((long long)(p - o) * (p - o), 36);
            putchar('\n');
        }
    } else if (!strcmp(c, "CAPACITY")) {
        int i = capacity_index(w[1]);
        if (i < 0) {
            Capacity *p = realloc(capacities, (size_t)(capacity_count + 1) * sizeof *p);
            if (!p) exit(EXIT_FAILURE);
            capacities = p;
            i = capacity_count++;
            strcpy(capacities[i].resource, w[1]);
        }
        capacities[i].limit = atoi(w[2]);
        printf("capacity %s %s\n", w[1], w[2]);
    } else if (!strcmp(c, "START") || !strcmp(c, "HOLIDAY") || !strcmp(c, "DEADLINE")) {
        int date = parse_date(w[1]);
        if (!strcmp(c, "HOLIDAY")) {
            for (int i = 0; i < holiday_count; i++) if (holidays[i] == date) fail("duplicate holiday %s", w[1]);
            holidays[holiday_count++] = date;
            qsort(holidays, (size_t)holiday_count, sizeof *holidays, int_compare);
            fputs("holiday ", stdout);
        } else if (!strcmp(c, "START")) {
            start_date = date;
            fputs("start ", stdout);
        } else {
            deadline = date;
            fputs("deadline ", stdout);
        }
        print_date(date);
        putchar('\n');
    } else if (!strcmp(c, "LIST")) {
        printf("tasks %d, dependencies %d, holidays %d\n", task_count, dep_count, holiday_count);
        for (int i = 0; i < task_count; i++) {
            Task *t = tasks[i];
            bool predecessors[MAX_TASKS] = {false};
            for (int j = 0; j < task_count; j++) predecessors[j] = dependency(tasks[j], t) >= 0;
            printf("%s duration %d resource %s units %d preds ", t->name, duration(t), t->resource, t->units);
            name_list(predecessors);
            putchar('\n');
        }
    } else if (!strcmp(c, "SHOW")) {
        Task *t = task(w[1]);
        printf("task %s duration %d resource %s units %d", t->name, duration(t), t->resource, t->units);
        if (t->not_before) printf(" notbefore %d", t->not_before);
        putchar('\n');
        for (int predecessors = 1; predecessors >= 0; predecessors--) {
            fputs(predecessors ? "preds: " : "succs: ", stdout);
            bool any = false;
            for (int j = 0; j < task_count; j++) {
                int i = predecessors ? dependency(tasks[j], t) : dependency(t, tasks[j]);
                if (i < 0) continue;
                if (any) fputs(", ", stdout);
                printf("%s %s%+d", tasks[j]->name, kinds[dependencies[i].kind], dependencies[i].lag);
                any = true;
            }
            if (!any) fputs("none", stdout);
            putchar('\n');
        }
        if (t->has_crash) printf("crash: max %d used %d cost %d\n", t->crash_limit, t->crashed, t->crash_cost);
        else puts("crash: none");
        if (t->has_estimate) printf("pert: %d %d %d\n", t->estimate[0], t->estimate[1], t->estimate[2]);
        else puts("pert: none");
        char cycle_text[(MAX_TASKS + 1) * 13];
        if (cycle(cycle_text)) puts("schedule: unavailable");
        else {
            Schedule s = compute(NULL, 0);
            Timing *x = &s.times[index_of(t)];
            printf("schedule: ES %d EF %d LS %d LF %d TF %d FF %d%s\n", x->es, x->ef, x->ls, x->lf, x->tf, x->free, x->tf == 0 ? " critical" : "");
        }
    } else if (!strcmp(c, "IMPACT")) {
        int v = index_of(task(w[1])), queue[MAX_TASKS], head = 0, tail = 0;
        bool seen[MAX_TASKS] = {false};
        seen[v] = true;
        queue[tail++] = v;
        while (head < tail) {
            int u = queue[head++];
            for (int j = 0; j < task_count; j++) if (!seen[j] && dependency(tasks[u], tasks[j]) >= 0) {
                seen[j] = true;
                queue[tail++] = j;
            }
        }
        seen[v] = false;
        printf("impact %s: ", w[1]);
        name_list(seen);
        putchar('\n');
    } else analysis(c, w);
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = allocate(capacity);
    int ch;
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
    for (int i = 0; i < task_count; i++) free(tasks[i]);
    free(capacities);
    return 0;
}
