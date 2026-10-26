#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TYPES 8
#define IDS 100
#define MAX_PROCESSES 12

typedef struct {
    int max[TYPES], allocation[TYPES], created, exists;
} Process;
typedef struct {
    int id, vector[TYPES], since;
} Waiting;
typedef struct {
    int time, kind, id, vector[TYPES], wait;
} Event;
typedef struct {
    int m, total[TYPES], available[TYPES];
    Process p[IDS];
    Waiting queue[MAX_PROCESSES];
    int queued;
    Event *history;
    size_t events, capacity;
} State;
typedef struct Snapshot {
    char name[11];
    State state;
    struct Snapshot *next;
} Snapshot;
typedef struct {
    int sequence[IDS], count, left[IDS], remaining;
} Check;
static State state;
static Snapshot *snapshots;
static int mode, policy, tracing, automatic, now;
static const char *kinds[] = {"granted",  "blocked", "unblocked", "released",
                              "finished", "aborted", "cancelled"};
static void vector(const int *v) {
    putchar('(');
    for (int j = 0; j < state.m; ++j)
        printf("%s%d", j ? "," : "", v[j]);
    putchar(')');
}
static void list(const int *ids, int n) {
    for (int i = 0; i < n; ++i)
        printf("%sP%d", i ? " " : "", ids[i]);
}
static void error(const char *text) {
    printf("error: %s\n", text);
}
static int le(const int *a, const int *b) {
    for (int j = 0; j < state.m; ++j)
        if (a[j] > b[j])
            return 0;
    return 1;
}
static int zero(const int *v) {
    for (int j = 0; j < state.m; ++j)
        if (v[j])
            return 0;
    return 1;
}
static void change(int *a, const int *b, int sign) {
    for (int j = 0; j < state.m; ++j)
        a[j] += sign * b[j];
}
static int sum(const int *v) {
    int s = 0;
    for (int j = 0; j < state.m; ++j)
        s += v[j];
    return s;
}
static void need(const Process *p, int *v) {
    for (int j = 0; j < state.m; ++j)
        v[j] = p->max[j] - p->allocation[j];
}
static int blocked(const State *s, int id) {
    for (int i = 0; i < s->queued; ++i)
        if (s->queue[i].id == id)
            return i;
    return -1;
}
static State copy_state(const State *s) {
    State result = *s;
    result.capacity = result.events;
    result.history = result.events ? malloc(result.events * sizeof(Event)) : NULL;
    if (result.events)
        memcpy(result.history, s->history, result.events * sizeof(Event));
    return result;
}
static void record(int kind, int id, const int *v, int wait) {
    if (state.events == state.capacity) {
        state.capacity = state.capacity ? state.capacity * 2 : 16;
        state.history = realloc(state.history, state.capacity * sizeof(Event));
    }
    Event *e = &state.history[state.events++];
    *e = (Event){.time = now, .kind = kind, .id = id, .wait = wait};
    memcpy(e->vector, v, state.m * sizeof(int));
}
static Check check(const State *s, int detect, int verbose) {
    Check c = {0};
    int work[TYPES], done[IDS] = {0}, idle[IDS], idle_count = 0;
    memcpy(work, s->available, sizeof(work));
    for (int id = 0; id < IDS; ++id) {
        if (!s->p[id].exists)
            done[id] = 1;
        else if (detect && zero(s->p[id].allocation)) {
            done[id] = 1;
            idle[idle_count++] = id;
        }
    }
    const char *tag = detect ? "[detect]" : "[safety]";
    if (verbose) {
        printf("%s start work=", tag);
        vector(work);
        if (idle_count) {
            printf(" idle ");
            list(idle, idle_count);
        }
        putchar('\n');
    }
    for (;;) {
        int chosen = -1;
        for (int id = 0; id < IDS; ++id)
            if (!done[id]) {
                int v[TYPES] = {0}, q = blocked(s, id);
                if (!detect)
                    need(&s->p[id], v);
                else if (q >= 0)
                    memcpy(v, s->queue[q].vector, sizeof(v));
                if (le(v, work)) {
                    chosen = id;
                    break;
                }
            }
        if (chosen < 0)
            break;
        done[chosen] = 1;
        c.sequence[c.count++] = chosen;
        change(work, s->p[chosen].allocation, 1);
        if (verbose) {
            printf("%s P%d can finish, work=", tag, chosen);
            vector(work);
            putchar('\n');
        }
    }
    for (int id = 0; id < IDS; ++id)
        if (!done[id])
            c.left[c.remaining++] = id;
    if (verbose && c.remaining) {
        printf("%s stuck work=", tag);
        vector(work);
        printf(" remaining ");
        list(c.left, c.remaining);
        putchar('\n');
    }
    return c;
}
static const char *rejection(int id, const int *v, char *message) {
    if (blocked(&state, id) >= 0) {
        sprintf(message, "process P%d is blocked", id);
        return message;
    }
    if (zero(v))
        return "zero vector";
    int n[TYPES];
    need(&state.p[id], n);
    if (!le(v, n))
        return "request exceeds need";
    if (mode == 2) {
        int last = -1;
        for (int j = 0; j < state.m; ++j)
            if (state.p[id].allocation[j])
                last = j;
        for (int j = 0; j <= last; ++j)
            if (v[j])
                return "resource order violation";
    }
    return NULL;
}
static const char *decision(int id, const int *v, int verbose, Check *result) {
    if (!le(v, state.available))
        return "insufficient resources";
    if (mode != 0)
        return NULL;
    State tentative = state;
    change(tentative.available, v, -1);
    change(tentative.p[id].allocation, v, 1);
    *result = check(&tentative, 0, verbose);
    return result->remaining ? "unsafe state" : NULL;
}
static void allocate(int id, const int *v) {
    change(state.available, v, -1);
    change(state.p[id].allocation, v, 1);
}
static void remove_queue(int i) {
    memmove(&state.queue[i], &state.queue[i + 1], (state.queued - i - 1) * sizeof(Waiting));
    --state.queued;
}
static void retry(void) {
    for (int i = 0; i < state.queued;) {
        Waiting q = state.queue[i];
        Check result;
        if (decision(q.id, q.vector, tracing, &result)) {
            ++i;
            continue;
        }
        allocate(q.id, q.vector);
        remove_queue(i);
        printf("unblocked P%d ", q.id);
        vector(q.vector);
        putchar('\n');
        record(2, q.id, q.vector, now - q.since);
    }
}
static void terminate(int id, int kind, int do_retry) {
    int v[TYPES];
    memcpy(v, state.p[id].allocation, sizeof(v));
    change(state.available, v, 1);
    state.p[id].exists = 0;
    int q = blocked(&state, id);
    if (q >= 0)
        remove_queue(q);
    printf("%s P%d released ", kinds[kind], id);
    vector(v);
    putchar('\n');
    record(kind, id, v, 0);
    if (do_retry)
        retry();
}
static int sequence_limit, sequence_count, sequence_rows[50][MAX_PROCESSES], sequence_saved,
    sequence_size;
static void permutations(int *path, int depth, int *used, int *work) {
    if (depth == sequence_size) {
        ++sequence_count;
        if (sequence_saved < sequence_limit)
            memcpy(sequence_rows[sequence_saved++], path, depth * sizeof(int));
        return;
    }
    for (int id = 0; id < IDS; ++id)
        if (state.p[id].exists && !used[id]) {
            int n[TYPES];
            need(&state.p[id], n);
            if (!le(n, work))
                continue;
            used[id] = 1;
            path[depth] = id;
            change(work, state.p[id].allocation, 1);
            permutations(path, depth + 1, used, work);
            change(work, state.p[id].allocation, -1);
            used[id] = 0;
        }
}
static void sequences(int limit) {
    sequence_size = 0;
    for (int id = 0; id < IDS; ++id)
        sequence_size += state.p[id].exists;
    if (!sequence_size) {
        puts("safe sequences: no processes");
        return;
    }
    sequence_count = sequence_saved = 0;
    sequence_limit = limit;
    int path[MAX_PROCESSES], used[IDS] = {0}, work[TYPES];
    memcpy(work, state.available, sizeof(work));
    permutations(path, 0, used, work);
    printf("safe sequences: %d\n", sequence_count);
    for (int i = 0; i < sequence_saved; ++i) {
        list(sequence_rows[i], sequence_size);
        putchar('\n');
    }
}
static void victims(void) {
    Check dead = check(&state, 1, 0);
    if (!dead.remaining) {
        puts("no deadlock");
        return;
    }
    int best = 0, best_count = IDS, best_sum = 0;
    for (int mask = 1; mask < (1 << dead.remaining); ++mask) {
        State candidate = state;
        int count = 0, amount = 0;
        for (int i = 0; i < dead.remaining; ++i)
            if (mask & (1 << i)) {
                int id = dead.left[i];
                ++count;
                amount += sum(candidate.p[id].allocation);
                change(candidate.available, candidate.p[id].allocation, 1);
                candidate.p[id].exists = 0;
                int q = blocked(&candidate, id);
                if (q >= 0) {
                    memmove(&candidate.queue[q], &candidate.queue[q + 1],
                            (candidate.queued - q - 1) * sizeof(Waiting));
                    --candidate.queued;
                }
            }
        int preferred = count < best_count || (count == best_count && amount < best_sum);
        if (count == best_count && amount == best_sum) {
            for (int i = 0; i < dead.remaining; ++i)
                if ((mask & (1 << i)) != (best & (1 << i))) {
                    preferred = (mask & (1 << i)) != 0;
                    break;
                }
        }
        if (preferred && !check(&candidate, 1, 0).remaining) {
            best = mask;
            best_count = count;
            best_sum = amount;
        }
    }
    int ids[IDS], n = 0;
    for (int i = 0; i < dead.remaining; ++i)
        if (best & (1 << i))
            ids[n++] = dead.left[i];
    printf("victims: ");
    list(ids, n);
    putchar('\n');
}
static int wait_edges[IDS][IDS], resource_edges[IDS][TYPES], owner[TYPES], visited[IDS], path[IDS],
    type_path[IDS], graph_resource, cycle_count;
static void cycles(int start, int at, int depth) {
    for (int element = 0; element < (graph_resource ? state.m : IDS); ++element) {
        int next = graph_resource ? owner[element] : element;
        if (graph_resource ? !resource_edges[at][element] || next < 0 : !wait_edges[at][next])
            continue;
        if (next == start && (graph_resource || depth >= 2)) {
            printf("cycle: P%d", start);
            for (int i = 1; i < depth; ++i) {
                if (graph_resource)
                    printf(" -> %c", 'A' + type_path[i - 1]);
                printf(" -> P%d", path[i]);
            }
            if (graph_resource)
                printf(" -> %c", 'A' + element);
            printf(" -> P%d\n", start);
            ++cycle_count;
        } else if (next > start && !visited[next]) {
            visited[next] = 1;
            path[depth] = next;
            type_path[depth - 1] = element;
            cycles(start, next, depth + 1);
            visited[next] = 0;
        }
    }
}
static void graph(int resource) {
    graph_resource = resource;
    cycle_count = 0;
    memset(wait_edges, 0, sizeof(wait_edges));
    memset(resource_edges, 0, sizeof(resource_edges));
    if (resource) {
        for (int j = 0; j < state.m; ++j)
            if (state.total[j] != 1) {
                error("not single-instance");
                return;
            }
        for (int j = 0; j < state.m; ++j) {
            owner[j] = -1;
            for (int id = 0; id < IDS; ++id)
                if (state.p[id].exists && state.p[id].allocation[j]) {
                    owner[j] = id;
                    printf("assign %c -> P%d\n", 'A' + j, id);
                }
        }
        for (int id = 0; id < IDS; ++id)
            if (state.p[id].exists) {
                int q = blocked(&state, id);
                for (int j = 0; j < state.m; ++j)
                    if (q >= 0 && state.queue[q].vector[j]) {
                        resource_edges[id][j] = 1;
                        printf("request P%d -> %c\n", id, 'A' + j);
                    }
            }
        for (int id = 0; id < IDS; ++id)
            if (state.p[id].exists) {
                int n[TYPES];
                need(&state.p[id], n);
                for (int j = 0; j < state.m; ++j)
                    if (n[j] && !resource_edges[id][j])
                        printf("claim P%d -> %c\n", id, 'A' + j);
            }
    } else {
        int edges = 0;
        for (int id = 0; id < IDS; ++id) {
            int q = blocked(&state, id);
            if (q < 0)
                continue;
            for (int other = 0; other < IDS; ++other)
                if (other != id && state.p[other].exists) {
                    int labels[TYPES], n = 0;
                    for (int j = 0; j < state.m; ++j)
                        if (state.queue[q].vector[j] > state.available[j] &&
                            state.p[other].allocation[j])
                            labels[n++] = j;
                    if (!n)
                        continue;
                    wait_edges[id][other] = 1;
                    ++edges;
                    printf("P%d -> P%d on ", id, other);
                    for (int i = 0; i < n; ++i)
                        printf("%s%c", i ? "," : "", 'A' + labels[i]);
                    putchar('\n');
                }
        }
        if (!edges)
            puts("no wait edges");
    }
    for (int id = 0; id < IDS; ++id)
        if (state.p[id].exists) {
            memset(visited, 0, sizeof(visited));
            visited[id] = 1;
            path[0] = id;
            cycles(id, id, 1);
        }
    if (!cycle_count)
        puts("no cycles");
}
static void table_form(char *out, const int *v, const int *widths) {
    int offset = 0;
    for (int j = 0; j < state.m; ++j)
        offset += sprintf(out + offset, "%s%*d", j ? " " : "", widths[j], v[j]);
}
static void row(const char *heading, char cells[4][32], const int *widths) {
    char line[256];
    int offset = sprintf(line, "%-9s", heading);
    for (int i = 0; i < 4; ++i)
        offset += sprintf(line + offset, "  %-*s", widths[i], cells[i]);
    while (offset && line[offset - 1] == ' ')
        --offset;
    line[offset] = 0;
    puts(line);
}
static void table(void) {
    int widths[TYPES], columns[] = {10, 3, 4, 7}, length = 0;
    char names[32] = "", cells[4][32];
    for (int j = 0; j < state.m; ++j) {
        widths[j] = state.total[j] < 10 ? 1 : 2;
        length += sprintf(names + length, "%s%*c", j ? " " : "", widths[j], 'A' + j);
    }
    for (int i = 0; i < 4; ++i)
        if (columns[i] < length)
            columns[i] = length;
    strcpy(cells[0], "Allocation");
    strcpy(cells[1], "Max");
    strcpy(cells[2], "Need");
    strcpy(cells[3], "Request");
    row("Process", cells, columns);
    for (int i = 0; i < 4; ++i)
        strcpy(cells[i], names);
    row("", cells, columns);
    for (int id = 0; id < IDS; ++id)
        if (state.p[id].exists) {
            int n[TYPES], z[TYPES] = {0}, q = blocked(&state, id);
            char heading[16];
            need(&state.p[id], n);
            sprintf(heading, "P%d", id);
            table_form(cells[0], state.p[id].allocation, widths);
            table_form(cells[1], state.p[id].max, widths);
            table_form(cells[2], n, widths);
            table_form(cells[3], q >= 0 ? state.queue[q].vector : z, widths);
            row(heading, cells, columns);
        }
    for (int i = 1; i < 4; ++i)
        cells[i][0] = 0;
    table_form(cells[0], state.available, widths);
    row("Available", cells, columns);
    table_form(cells[0], state.total, widths);
    row("Total", cells, columns);
    printf("blocked queue: ");
    if (!state.queued)
        printf("empty");
    for (int i = 0; i < state.queued; ++i) {
        Waiting q = state.queue[i];
        printf("%sP%d ", i ? ", " : "", q.id);
        vector(q.vector);
        printf(" since t=%d", q.since);
    }
    putchar('\n');
}
int main(void) {
    char line[256], *words[16];
    int n;
    if (!fgets(line, sizeof(line), stdin))
        return 0;
    n = atoi(line);
    for (now = 1; now <= n; ++now) {
        if (!fgets(line, sizeof(line), stdin))
            break;
        int argc = 0;
        for (char *p = strtok(line, " \r\n"); p; p = strtok(NULL, " \r\n"))
            words[argc++] = p;
        char *cmd = words[0];
        if (!strcmp(cmd, "RESOURCES")) {
            free(state.history);
            memset(&state, 0, sizeof(state));
            state.m = argc - 1;
            for (int j = 0; j < state.m; ++j)
                state.total[j] = state.available[j] = atoi(words[j + 1]);
            printf("resources ");
            vector(state.total);
            putchar('\n');
            continue;
        }
        if (!strcmp(cmd, "MODE") || !strcmp(cmd, "POLICY") || !strcmp(cmd, "TRACE") ||
            !strcmp(cmd, "AUTODETECT")) {
            const char *label;
            if (!strcmp(cmd, "MODE")) {
                mode = !strcmp(words[1], "AVOID") ? 0 : !strcmp(words[1], "DETECT") ? 1 : 2;
                label = "mode";
            } else if (!strcmp(cmd, "POLICY")) {
                policy = !strcmp(words[1], "ALLOC") ? 0 : !strcmp(words[1], "NEED") ? 1 : 2;
                label = "policy";
            } else if (!strcmp(cmd, "TRACE")) {
                tracing = !strcmp(words[1], "ON");
                label = "trace";
            } else {
                automatic = !strcmp(words[1], "ON");
                label = "autodetect";
            }
            printf("%s %s\n", label, words[1]);
            continue;
        }
        if (!strcmp(cmd, "SNAPSHOT") || !strcmp(cmd, "RESTORE")) {
            Snapshot *snap = snapshots;
            while (snap && strcmp(snap->name, words[1]))
                snap = snap->next;
            if (!strcmp(cmd, "SNAPSHOT")) {
                if (!snap) {
                    snap = calloc(1, sizeof(*snap));
                    strcpy(snap->name, words[1]);
                    snap->next = snapshots;
                    snapshots = snap;
                } else
                    free(snap->state.history);
                snap->state = copy_state(&state);
                printf("saved %s\n", words[1]);
            } else if (!snap)
                printf("error: unknown snapshot %s\n", words[1]);
            else {
                free(state.history);
                state = copy_state(&snap->state);
                printf("restored %s\n", words[1]);
            }
            continue;
        }
        if (!strcmp(cmd, "STATE")) {
            table();
            continue;
        }
        if (!strcmp(cmd, "GRAPH") || !strcmp(cmd, "WAITGRAPH")) {
            graph(!strcmp(cmd, "GRAPH"));
            continue;
        }
        if (!strcmp(cmd, "SEQUENCES")) {
            sequences(atoi(words[1]));
            continue;
        }
        if (!strcmp(cmd, "VICTIMS")) {
            victims();
            continue;
        }
        if (!strcmp(cmd, "SAFE") || !strcmp(cmd, "DETECT")) {
            int count = 0, detect = !strcmp(cmd, "DETECT");
            for (int id = 0; id < IDS; ++id)
                count += state.p[id].exists;
            if (!detect && !count) {
                puts("safe: no processes");
                continue;
            }
            Check c = check(&state, detect, tracing);
            if (detect && !c.remaining)
                puts("no deadlock");
            else if (detect) {
                printf("deadlocked: ");
                list(c.left, c.remaining);
                putchar('\n');
            } else if (c.remaining) {
                printf("unsafe: ");
                list(c.left, c.remaining);
                puts(" cannot finish");
            } else {
                printf("safe: ");
                list(c.sequence, c.count);
                putchar('\n');
            }
            continue;
        }
        if (!strcmp(cmd, "RECOVER")) {
            int count = 0;
            for (;;) {
                Check c = check(&state, 1, tracing);
                if (!c.remaining)
                    break;
                if (argc > 1) {
                    for (int i = 0; i < c.remaining; ++i)
                        terminate(c.left[i], 5, 0);
                    count += c.remaining;
                    retry();
                    break;
                }
                int victim = c.left[0], best;
                int v[TYPES];
                need(&state.p[victim], v);
                best = policy == 0   ? -sum(state.p[victim].allocation)
                       : policy == 1 ? sum(v)
                                     : state.p[victim].created;
                for (int i = 1; i < c.remaining; ++i) {
                    int id = c.left[i];
                    need(&state.p[id], v);
                    int rank = policy == 0   ? -sum(state.p[id].allocation)
                               : policy == 1 ? sum(v)
                                             : state.p[id].created;
                    if (rank > best || (rank == best && id > victim)) {
                        best = rank;
                        victim = id;
                    }
                }
                terminate(victim, 5, 1);
                ++count;
            }
            if (count)
                printf("recovered: %d aborted\n", count);
            else
                puts("no deadlock");
            continue;
        }
        if (!strcmp(cmd, "DEFICIT")) {
            printf("deficit: (");
            for (int j = 0; j < state.m; ++j) {
                int bound = 0, found = -1;
                for (int id = 0; id < IDS; ++id)
                    if (state.p[id].exists)
                        bound += state.p[id].max[j] - state.p[id].allocation[j];
                for (int x = 0; x <= bound; ++x) {
                    State candidate = state;
                    candidate.available[j] += x;
                    if (!check(&candidate, 0, 0).remaining) {
                        found = x;
                        break;
                    }
                }
                if (j)
                    putchar(',');
                if (found < 0)
                    putchar('-');
                else
                    printf("%d", found);
            }
            puts(")");
            continue;
        }
        if (!strcmp(cmd, "HISTORY")) {
            int count = 0;
            for (size_t i = 0; i < state.events; ++i) {
                Event e = state.history[i];
                if (argc > 1 && strcmp(words[1], kinds[e.kind]) &&
                    !(words[1][0] >= '0' && words[1][0] <= '9' && atoi(words[1]) == e.id))
                    continue;
                printf("t=%d %s P%d ", e.time, kinds[e.kind], e.id);
                vector(e.vector);
                if (e.kind == 2)
                    printf(" waited %d", e.wait);
                putchar('\n');
                ++count;
            }
            if (!count)
                puts("no events");
            continue;
        }
        if (!strcmp(cmd, "STATS")) {
            int counts[7] = {0}, waits = 0;
            for (int j = 0; j < state.m; ++j) {
                int used = state.total[j] - state.available[j],
                    percent = used * 1000 / state.total[j], requested = 0;
                for (int i = 0; i < state.queued; ++i)
                    requested += state.queue[i].vector[j];
                printf("%c: allocated %d/%d (%d.%d%%), requested %d\n", 'A' + j, used,
                       state.total[j], percent / 10, percent % 10, requested);
            }
            for (size_t i = 0; i < state.events; ++i) {
                ++counts[state.history[i].kind];
                if (state.history[i].kind == 2)
                    waits += state.history[i].wait;
            }
            printf("events: ");
            for (int k = 0; k < 7; ++k)
                printf("%s%s %d", k ? ", " : "", kinds[k], counts[k]);
            putchar('\n');
            if (!counts[2])
                puts("waits: none");
            else {
                int average = waits * 100 / counts[2];
                printf("waits: %d unblocked, total %d, average %d.%02d\n", counts[2], waits,
                       average / 100, average % 100);
            }
            continue;
        }
        int resource = !strcmp(cmd, "ADD") || !strcmp(cmd, "REMOVE");
        int has_vector = resource || !strcmp(cmd, "PROCESS") || !strcmp(cmd, "CLAIM") ||
                         !strcmp(cmd, "REQUEST") || !strcmp(cmd, "WHATIF") ||
                         !strcmp(cmd, "RELEASE");
        int id = resource ? 0 : atoi(words[1]), v[TYPES] = {0};
        if (has_vector && argc - (resource ? 1 : 2) != state.m) {
            error("wrong vector length");
            continue;
        }
        if (has_vector)
            for (int j = 0; j < state.m; ++j)
                v[j] = atoi(words[j + (resource ? 1 : 2)]);
        if (!resource && strcmp(cmd, "PROCESS") && !state.p[id].exists) {
            printf("error: unknown process P%d\n", id);
            continue;
        }
        if (!strcmp(cmd, "PROCESS")) {
            if (state.p[id].exists)
                printf("error: duplicate process P%d\n", id);
            else if (!le(v, state.total))
                error("max exceeds total");
            else {
                state.p[id] = (Process){.created = now, .exists = 1};
                memcpy(state.p[id].max, v, sizeof(v));
                printf("process P%d max ", id);
                vector(v);
                putchar('\n');
            }
            continue;
        }
        if (!strcmp(cmd, "REQUEST") || !strcmp(cmd, "WHATIF")) {
            char message[64];
            const char *reason = rejection(id, v, message);
            Check c = {0};
            if (reason) {
                if (!strcmp(cmd, "REQUEST"))
                    error(reason);
                else {
                    printf("whatif P%d ", id);
                    vector(v);
                    printf(": rejected (%s)\n", reason);
                }
                continue;
            }
            reason = decision(id, v, tracing, &c);
            if (!strcmp(cmd, "WHATIF")) {
                printf("whatif P%d ", id);
                vector(v);
                if (reason)
                    printf(": blocked (%s)\n", reason);
                else {
                    printf(": granted");
                    if (!mode) {
                        printf(", safe sequence ");
                        list(c.sequence, c.count);
                    }
                    putchar('\n');
                }
            } else if (!reason) {
                allocate(id, v);
                printf("granted P%d ", id);
                vector(v);
                putchar('\n');
                record(0, id, v, 0);
            } else {
                Waiting *q = &state.queue[state.queued++];
                *q = (Waiting){.id = id, .since = now};
                memcpy(q->vector, v, sizeof(v));
                printf("blocked P%d ", id);
                vector(v);
                printf(": %s\n", reason);
                record(1, id, v, 0);
                if (automatic) {
                    Check d = check(&state, 1, tracing);
                    if (d.remaining) {
                        printf("deadlock detected: ");
                        list(d.left, d.remaining);
                        putchar('\n');
                    }
                }
            }
            continue;
        }
        if (!resource && strcmp(cmd, "ABORT") && strcmp(cmd, "CANCEL") &&
            blocked(&state, id) >= 0) {
            printf("error: process P%d is blocked\n", id);
            continue;
        }
        if (!strcmp(cmd, "FINISH") || !strcmp(cmd, "ABORT")) {
            terminate(id, !strcmp(cmd, "FINISH") ? 4 : 5, 1);
            continue;
        }
        if (!strcmp(cmd, "CANCEL")) {
            int q = blocked(&state, id);
            if (q < 0)
                printf("error: process P%d is not blocked\n", id);
            else {
                Waiting w = state.queue[q];
                remove_queue(q);
                printf("cancelled P%d ", id);
                vector(w.vector);
                putchar('\n');
                record(6, id, w.vector, 0);
            }
            continue;
        }
        if (!strcmp(cmd, "MAXGRANT")) {
            int answer[TYPES] = {0}, nvec[TYPES];
            need(&state.p[id], nvec);
            for (int j = 0; j < state.m; ++j)
                for (int x = nvec[j]; x > 0; --x) {
                    int request[TYPES] = {0};
                    request[j] = x;
                    char message[64];
                    Check c;
                    if (!rejection(id, request, message) && !decision(id, request, 0, &c)) {
                        answer[j] = x;
                        break;
                    }
                }
            printf("maxgrant P%d: ", id);
            vector(answer);
            putchar('\n');
            continue;
        }
        if (!strcmp(cmd, "CLAIM")) {
            if (!le(state.p[id].allocation, v)) {
                error("claim below allocation");
                continue;
            }
            if (!le(v, state.total)) {
                error("max exceeds total");
                continue;
            }
            State candidate = state;
            memcpy(candidate.p[id].max, v, sizeof(v));
            if (!mode && check(&candidate, 0, tracing).remaining) {
                error("claim makes state unsafe");
                continue;
            }
            memcpy(state.p[id].max, v, sizeof(v));
            printf("claim P%d max ", id);
            vector(v);
            putchar('\n');
            retry();
            continue;
        }
        if (zero(v)) {
            error("zero vector");
            continue;
        }
        if (!strcmp(cmd, "RELEASE")) {
            if (!le(v, state.p[id].allocation)) {
                error("release exceeds allocation");
                continue;
            }
            change(state.p[id].allocation, v, -1);
            change(state.available, v, 1);
            printf("released P%d ", id);
            vector(v);
            putchar('\n');
            record(3, id, v, 0);
            retry();
        } else if (!strcmp(cmd, "ADD")) {
            change(state.total, v, 1);
            change(state.available, v, 1);
            printf("added ");
            vector(v);
            printf(" total ");
            vector(state.total);
            putchar('\n');
            retry();
        } else {
            if (!le(v, state.available)) {
                error("remove exceeds available");
                continue;
            }
            State candidate = state;
            change(candidate.total, v, -1);
            change(candidate.available, v, -1);
            int bad = 0;
            for (int j = 0; j < state.m; ++j)
                if (!candidate.total[j])
                    bad = 1;
            if (bad) {
                error("total must stay positive");
                continue;
            }
            for (int p = 0; p < IDS; ++p)
                if (state.p[p].exists && !le(state.p[p].max, candidate.total))
                    bad = 1;
            if (bad) {
                error("max exceeds total");
                continue;
            }
            if (!mode && check(&candidate, 0, tracing).remaining) {
                error("removal makes state unsafe");
                continue;
            }
            state = candidate;
            printf("removed ");
            vector(v);
            printf(" total ");
            vector(state.total);
            putchar('\n');
        }
    }
    free(state.history);
    while (snapshots) {
        Snapshot *next = snapshots->next;
        free(snapshots->state.history);
        free(snapshots);
        snapshots = next;
    }
    return 0;
}
