#include <limits.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define MAX_STOPS 30
#define MAX_ID 999

typedef struct {
    bool present;
    int x, y, demand, service, open, close;
} Stop;

typedef struct {
    int count, ids[MAX_STOPS];
} Route;

typedef struct {
    int count;
    Route routes[MAX_STOPS];
} Plan;

typedef struct {
    int a, b, value;
} Saving;

typedef struct {
    int returned, waiting, service, violations, lateness;
} Run;
static Stop stops[MAX_ID + 1];
static int stop_count, depot_x, depot_y, departure = 480, capacity;
static bool depot, has_tour, has_plan;
static Route tour;
static Plan plan;
static jmp_buf command_error;

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

static int time_value(const char *text) {
    return atoi(text) * 60 + atoi(text + 3);
}

static void print_time(int value) {
    printf("%02d:%02d", value / 60, value % 60);
}

static void location(int id) {
    if (id) printf("%d", id);
    else putchar('D');
}

static int ids(int *result) {
    int count = 0;
    for (int id = 1; id <= MAX_ID; id++) if (stops[id].present) result[count++] = id;
    return count;
}

static int distance(int a, int b) {
    int ax = a ? stops[a].x : depot_x, ay = a ? stops[a].y : depot_y;
    int bx = b ? stops[b].x : depot_x, by = b ? stops[b].y : depot_y;
    return abs(ax - bx) + abs(ay - by);
}

static int at(const Route *r, int position) {
    return position < 0 || position >= r->count ? 0 : r->ids[position];
}

static int length(const Route *r) {
    int total = 0, previous = 0;
    for (int i = 0; i < r->count; i++) {
        total += distance(previous, r->ids[i]);
        previous = r->ids[i];
    }
    return total + distance(previous, 0);
}

static int load(const Route *r) {
    int total = 0;
    for (int i = 0; i < r->count; i++) total += stops[r->ids[i]].demand;
    return total;
}

static int plan_length(void) {
    int total = 0;
    for (int i = 0; i < plan.count; i++) total += length(&plan.routes[i]);
    return total;
}

static void sequence(const Route *r) {
    putchar('D');
    for (int i = 0; i < r->count; i++) printf("-%d", r->ids[i]);
    fputs("-D", stdout);
}

static bool contains(const Route *r, int id) {
    for (int i = 0; i < r->count; i++) if (r->ids[i] == id) return true;
    return false;
}

static void remove_at(Route *r, int position) {
    memmove(r->ids + position, r->ids + position + 1, (size_t)(r->count - position - 1) * sizeof *r->ids);
    r->count--;
}

static void insert(Route *r, int position, int id) {
    memmove(r->ids + position + 1, r->ids + position, (size_t)(r->count - position) * sizeof *r->ids);
    r->ids[position] = id;
    r->count++;
}

static void reverse(Route *r, int first, int last) {
    while (first < last) {
        int id = r->ids[first];
        r->ids[first++] = r->ids[last];
        r->ids[last--] = id;
    }
}

static Route slice(const Route *r, int first, int last) {
    Route result = {0};
    result.count = last - first;
    memcpy(result.ids, r->ids + first, (size_t)result.count * sizeof *r->ids);
    return result;
}

static Route concatenate(const Route *a, const Route *b) {
    Route result = *a;
    memcpy(result.ids + result.count, b->ids, (size_t)b->count * sizeof *b->ids);
    result.count += b->count;
    return result;
}

static void remove_route(Plan *p, int index) {
    memmove(p->routes + index, p->routes + index + 1, (size_t)(p->count - index - 1) * sizeof *p->routes);
    p->count--;
}

static int smallest(const Route *r) {
    int result = r->ids[0];
    for (int i = 1; i < r->count; i++) result = minimum(result, r->ids[i]);
    return result;
}

static int route_compare(const void *a, const void *b) {
    return smallest(a) - smallest(b);
}

static void normalize(void) {
    for (int i = plan.count - 1; i >= 0; i--) if (!plan.routes[i].count) remove_route(&plan, i);
    for (int i = 0; i < plan.count; i++) {
        Route *r = &plan.routes[i];
        if (r->ids[0] > r->ids[r->count - 1]) reverse(r, 0, r->count - 1);
    }
    qsort(plan.routes, (size_t)plan.count, sizeof *plan.routes, route_compare);
}

static void network_check(void) {
    if (!depot) fail("no depot");
    if (!stop_count) fail("no stops");
}

static void tour_check(void) {
    if (!has_tour) fail("no tour");
}

static void plan_check(void) {
    if (!has_plan) fail("no plan");
}

static void capacity_check(int q) {
    for (int id = 1; id <= MAX_ID; id++) if (stops[id].present && stops[id].demand > q) fail("stop %d demand %d exceeds capacity %d", id, stops[id].demand, q);
}

static void route_lines(void) {
    for (int i = 0; i < plan.count; i++) {
        printf("route %d: ", i + 1);
        sequence(&plan.routes[i]);
        printf(" load %d length %d\n", load(&plan.routes[i]), length(&plan.routes[i]));
    }
}

static Run simulate(const Route *r, bool print) {
    Run run = {0};
    int t = departure, previous = 0;
    for (int i = 0; i < r->count; i++) {
        int id = r->ids[i];
        Stop *p = &stops[id];
        int arrival = t + distance(previous, id), wait = p->open < 0 ? 0 : maximum(0, p->open - arrival);
        int begin = arrival + wait, late = p->close < 0 ? 0 : maximum(0, arrival - p->close);
        t = begin + p->service;
        run.waiting += wait;
        run.service += p->service;
        run.lateness += late;
        run.violations += late > 0;
        if (print) {
            printf("%d arrive ", id);
            print_time(arrival);
            printf(" wait %d begin ", wait);
            print_time(begin);
            fputs(" leave ", stdout);
            print_time(t);
            if (late) printf(" late %d\n", late);
            else puts(" ok");
        }
        previous = id;
    }
    run.returned = t + distance(previous, 0);
    if (print) {
        fputs("return ", stdout);
        print_time(run.returned);
        printf(", travel %d, wait %d, service %d, violations %d, lateness %d\n", length(r), run.waiting, run.service, run.violations, run.lateness);
    }
    return run;
}

static int two_opt(Route *r, bool print) {
    int moves = 0;
    for (;;) {
        bool moved = false;
        for (int i = 0; i + 1 < r->count; i++) for (int j = i + 1; j < r->count; j++) {
            int a = r->ids[i], b = r->ids[j];
            int gain = distance(at(r, i - 1), a) + distance(b, at(r, j + 1)) - distance(at(r, i - 1), b) - distance(a, at(r, j + 1));
            if (gain > 0) {
                if (print) printf("reverse %d..%d gain %d\n", a, b, gain);
                reverse(r, i, j);
                moves++;
                moved = true;
                goto scan_done;
            }
        }
        scan_done: if (!moved) return moves;
    }
}

typedef struct {
    int count, ids[10], *memo;
} Exact;

static int exact_best(Exact *e, int mask, int last) {
    if (mask == (1 << e->count) - 1) return distance(last == e->count ? 0 : e->ids[last], 0);
    int *entry = &e->memo[mask * (e->count + 1) + last];
    if (*entry >= 0) return *entry;
    int value = INT_MAX, previous = last == e->count ? 0 : e->ids[last];
    for (int i = 0; i < e->count; i++) if (!(mask & (1 << i))) value = minimum(value, distance(previous, e->ids[i]) + exact_best(e, mask | (1 << i), i));
    return *entry = value;
}

static Route exact(void) {
    Exact e = {0};
    e.count = ids(e.ids);
    size_t cells = (size_t)(1 << e.count) * (e.count + 1);
    e.memo = malloc(cells * sizeof *e.memo);
    if (!e.memo) exit(EXIT_FAILURE);
    for (size_t i = 0; i < cells; i++) e.memo[i] = -1;
    Route result = {0};
    int mask = 0, last = e.count, full = (1 << e.count) - 1;
    while (mask != full) for (int i = 0; i < e.count; i++) if (!(mask & (1 << i)) && distance(last == e.count ? 0 : e.ids[last], e.ids[i]) + exact_best(&e, mask | (1 << i), i) == exact_best(&e, mask, last)) {
        result.ids[result.count++] = e.ids[i];
        mask |= 1 << i;
        last = i;
        break;
    }
    free(e.memo);
    return result;
}

static int angle_compare(const void *pa, const void *pb) {
    int a = *(const int *)pa, b = *(const int *)pb;
    int ax = stops[a].x - depot_x, ay = stops[a].y - depot_y, bx = stops[b].x - depot_x, by = stops[b].y - depot_y;
    bool az = ax == 0 && ay == 0, bz = bx == 0 && by == 0;
    if (az || bz) return az == bz ? a - b : az ? -1 : 1;
    int ah = ay > 0 || (ay == 0 && ax > 0) ? 0 : 1, bh = by > 0 || (by == 0 && bx > 0) ? 0 : 1;
    if (ah != bh) return ah - bh;
    int cross = ax * by - ay * bx;
    if (cross) return cross > 0 ? -1 : 1;
    int order = distance(0, a) - distance(0, b);
    return order ? order : a - b;
}

static int saving_compare(const void *pa, const void *pb) {
    const Saving *a = pa, *b = pb;
    return a->value != b->value ? b->value - a->value : a->a != b->a ? a->a - b->a : a->b - b->b;
}

static void bound(void) {
    int all[MAX_STOPS], n = ids(all), entered[MAX_STOPS + 1] = {0}, entered_count = 1, mst = 0, edges[MAX_STOPS][2];
    bool included[MAX_STOPS] = {false};
    for (int step = 0; step < n; step++) {
        int best = INT_MAX, chosen = -1, parent = 0;
        for (int i = 0; i < n; i++) if (!included[i]) for (int j = 0; j < entered_count; j++) if (distance(entered[j], all[i]) < best) {
            best = distance(entered[j], all[i]);
            chosen = i;
            parent = entered[j];
        }
        included[chosen] = true;
        entered[entered_count++] = all[chosen];
        mst += best;
        edges[step][0] = parent;
        edges[step][1] = all[chosen];
    }
    int one_tree;
    if (n == 1) one_tree = 2 * distance(0, all[0]);
    else {
        memset(included, 0, sizeof included);
        included[0] = true;
        int tree = 0;
        for (int step = 1; step < n; step++) {
            int best = INT_MAX, chosen = -1;
            for (int i = 0; i < n; i++) if (!included[i]) for (int j = 0; j < n; j++) if (included[j] && distance(all[j], all[i]) < best) {
                best = distance(all[j], all[i]);
                chosen = i;
            }
            included[chosen] = true;
            tree += best;
        }
        int first = INT_MAX, second = INT_MAX;
        for (int i = 0; i < n; i++) {
            int d = distance(0, all[i]);
            if (d < first) {
                second = first;
                first = d;
            } else if (d < second) second = d;
        }
        one_tree = tree + first + second;
    }
    fputs("mst:", stdout);
    for (int i = 0; i < n; i++) {
        putchar(' ');
        location(edges[i][0]);
        printf("-%d", edges[i][1]);
    }
    int lower = maximum(mst, one_tree);
    printf(" (length %d)\nbound: mst %d, one-tree %d, best %d\n", mst, mst, one_tree, lower);
    if (!has_tour) puts("gap: no tour");
    else {
        int value = length(&tour);
        long long rounded = lower ? (2000LL * (value - lower) + lower) / (2LL * lower) : 0;
        printf("gap: tour %d, %lld.%lld%%\n", value, rounded / 10, rounded % 10);
    }
}

static void improve_plan(const char *command) {
    int initial = plan_length(), old_count = plan.count, moves = 0;
    for (;;) {
        bool moved = false;
        for (int r = 0; r < plan.count; r++) {
            Route *a = &plan.routes[r];
            if (!strcmp(command, "RELOCATE")) {
                for (int p = 0; p < a->count; p++) for (int t = 0; t < plan.count; t++) if (t != r) {
                    Route *b = &plan.routes[t];
                    int c = a->ids[p];
                    if (load(b) + stops[c].demand > capacity) continue;
                    for (int j = 0; j <= b->count; j++) {
                        int u = at(b, j - 1), v = at(b, j);
                        int gain = distance(at(a, p - 1), c) + distance(c, at(a, p + 1)) - distance(at(a, p - 1), at(a, p + 1)) - distance(u, c) - distance(c, v) + distance(u, v);
                        if (gain > 0) {
                            printf("relocate %d from route %d to route %d after ", c, r + 1, t + 1);
                            location(u);
                            printf(" gain %d\n", gain);
                            remove_at(a, p);
                            insert(b, j, c);
                            moved = true;
                            goto scan_done;
                        }
                    }
                }
            } else for (int t = r + 1; t < plan.count; t++) {
                Route *b = &plan.routes[t];
                if (!strcmp(command, "EXCHANGE")) {
                    for (int p = 0; p < a->count; p++) for (int j = 0; j < b->count; j++) {
                        int c = a->ids[p], e = b->ids[j];
                        if (load(a) - stops[c].demand + stops[e].demand > capacity || load(b) - stops[e].demand + stops[c].demand > capacity) continue;
                        Route x = *a, y = *b;
                        x.ids[p] = e;
                        y.ids[j] = c;
                        int gain = length(a) + length(b) - length(&x) - length(&y);
                        if (gain > 0) {
                            printf("exchange %d (route %d) with %d (route %d) gain %d\n", c, r + 1, e, t + 1, gain);
                            *a = x;
                            *b = y;
                            moved = true;
                            goto scan_done;
                        }
                    }
                } else {
                    for (int i = 0; i <= a->count; i++) for (int j = 0; j <= b->count; j++) {
                        Route a_prefix = slice(a, 0, i), a_tail = slice(a, i, a->count), b_prefix = slice(b, 0, j), b_tail = slice(b, j, b->count);
                        Route x = concatenate(&a_prefix, &b_tail), y = concatenate(&b_prefix, &a_tail);
                        if (load(&x) > capacity || load(&y) > capacity) continue;
                        int gain = distance(at(a, i - 1), at(a, i)) + distance(at(b, j - 1), at(b, j)) - distance(at(a, i - 1), at(b, j)) - distance(at(b, j - 1), at(a, i));
                        if (gain > 0) {
                            printf("cross route %d after ", r + 1);
                            location(at(a, i - 1));
                            printf(" with route %d after ", t + 1);
                            location(at(b, j - 1));
                            printf(" gain %d\n", gain);
                            *a = x;
                            *b = y;
                            moved = true;
                            goto scan_done;
                        }
                    }
                }
            }
        }
        scan_done: if (!moved) break;
        moves++;
        normalize();
    }
    const char *name = !strcmp(command, "RELOCATE") ? "relocate" : !strcmp(command, "EXCHANGE") ? "exchange" : "cross";
    printf("%s: moves %d", name, moves);
    if (strcmp(command, "EXCHANGE")) printf(", routes %d -> %d", old_count, plan.count);
    printf(", length %d -> %d\n", initial, plan_length());
}

static void command(char *line) {
    char *w[MAX_STOPS + 2];
    int count = 0;
    for (char *p = strtok(line, " "); p; p = strtok(NULL, " ")) w[count++] = p;
    const char *c = w[0];
    if (!strcmp(c, "DEPOT")) {
        depot = true;
        depot_x = atoi(w[1]);
        depot_y = atoi(w[2]);
        printf("depot at (%d,%d)\n", depot_x, depot_y);
    } else if (!strcmp(c, "START")) {
        departure = time_value(w[1]);
        fputs("start ", stdout);
        print_time(departure);
        putchar('\n');
    } else if (!strcmp(c, "STOP")) {
        int id = atoi(w[1]);
        if (stops[id].present) fail("stop %d already exists", id);
        int open = count == 8 ? time_value(w[6]) : -1, close = count == 8 ? time_value(w[7]) : -1;
        if (open > close) fail("invalid window");
        stops[id] = (Stop){true, atoi(w[2]), atoi(w[3]), atoi(w[4]), atoi(w[5]), open, close};
        stop_count++;
        has_tour = has_plan = false;
        printf("stop %d added\n", id);
    } else if (!strcmp(c, "REMOVE")) {
        int id = atoi(w[1]);
        if (!stops[id].present) fail("unknown stop %d", id);
        stops[id].present = false;
        stop_count--;
        if (!stop_count) has_tour = has_plan = false;
        else {
            if (has_tour) for (int i = 0; i < tour.count; i++) if (tour.ids[i] == id) {
                remove_at(&tour, i);
                break;
            }
            if (has_plan) {
                for (int r = 0; r < plan.count; r++) for (int i = 0; i < plan.routes[r].count; i++) if (plan.routes[r].ids[i] == id) {
                    remove_at(&plan.routes[r], i);
                    break;
                }
                normalize();
            }
        }
        printf("stop %d removed\n", id);
    } else if (!strcmp(c, "LIST")) {
        if (depot) printf("depot (%d,%d)\n", depot_x, depot_y);
        else puts("depot none");
        fputs("start ", stdout);
        print_time(departure);
        printf("\nstops %d\n", stop_count);
        for (int id = 1; id <= MAX_ID; id++) if (stops[id].present) {
            Stop *p = &stops[id];
            printf("%d at (%d,%d) demand %d service %d window ", id, p->x, p->y, p->demand, p->service);
            if (p->open < 0) fputs("none", stdout);
            else {
                print_time(p->open);
                putchar('-');
                print_time(p->close);
            }
            putchar('\n');
        }
    } else if (!strcmp(c, "MATRIX")) {
        if (!depot) fail("no depot");
        int all[MAX_STOPS + 1] = {0}, n = ids(all + 1) + 1, width = 1;
        char text[16];
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) {
            int size = snprintf(text, sizeof text, "%d", distance(all[i], all[j]));
            width = maximum(width, size);
            if (all[i]) width = maximum(width, snprintf(text, sizeof text, "%d", all[i]));
        }
        printf("%*s", width, "");
        for (int i = 0; i < n; i++) {
            if (all[i]) snprintf(text, sizeof text, "%d", all[i]);
            else strcpy(text, "D");
            printf(" %*s", width, text);
        }
        putchar('\n');
        for (int i = 0; i < n; i++) {
            if (all[i]) snprintf(text, sizeof text, "%d", all[i]);
            else strcpy(text, "D");
            printf("%*s", width, text);
            for (int j = 0; j < n; j++) printf(" %*d", width, distance(all[i], all[j]));
            putchar('\n');
        }
    } else if (!strcmp(c, "ORDER")) {
        network_check();
        Route next = {0};
        next.count = count - 1;
        for (int i = 0; i < next.count; i++) {
            next.ids[i] = atoi(w[i + 1]);
            if (!stops[next.ids[i]].present) fail("unknown stop %d", next.ids[i]);
        }
        for (int i = 0; i < next.count; i++) for (int j = 0; j < i; j++) if (next.ids[i] == next.ids[j]) fail("duplicate stop %d", next.ids[i]);
        if (next.count != stop_count) fail("order has %d stops, expected %d", next.count, stop_count);
        tour = next;
        has_tour = true;
        fputs("order: ", stdout);
        sequence(&tour);
        printf(" length %d\n", length(&tour));
    } else if (!strcmp(c, "NEAREST") || !strcmp(c, "INSERTION") || !strcmp(c, "EXACT")) {
        network_check();
        if (!strcmp(c, "EXACT")) {
            if (stop_count > 10) fail("too many stops for exact (%d)", stop_count);
            tour = exact();
        } else {
            tour.count = 0;
            while (tour.count < stop_count) {
                int best = INT_MAX, chosen = 0, position = 0;
                for (int id = 1; id <= MAX_ID; id++) if (stops[id].present && !contains(&tour, id)) {
                    if (!strcmp(c, "NEAREST")) {
                        int value = distance(tour.count ? tour.ids[tour.count - 1] : 0, id);
                        if (value < best) {
                            best = value;
                            chosen = id;
                            position = tour.count;
                        }
                    } else for (int j = 0; j <= tour.count; j++) {
                        int value = distance(at(&tour, j - 1), id) + distance(id, at(&tour, j)) - distance(at(&tour, j - 1), at(&tour, j));
                        if (value < best) {
                            best = value;
                            chosen = id;
                            position = j;
                        }
                    }
                }
                insert(&tour, position, chosen);
            }
        }
        has_tour = true;
        fputs(!strcmp(c, "NEAREST") ? "nearest: " : !strcmp(c, "INSERTION") ? "insertion: " : "exact: ", stdout);
        sequence(&tour);
        printf(" length %d\n", length(&tour));
    } else if (!strcmp(c, "TOUR")) {
        tour_check();
        fputs("tour: ", stdout);
        sequence(&tour);
        printf(" length %d\n", length(&tour));
    } else if (!strcmp(c, "TWOOPT") || !strcmp(c, "OROPT") || !strcmp(c, "SWAP")) {
        tour_check();
        int initial = length(&tour), moves = 0;
        if (!strcmp(c, "TWOOPT")) moves = two_opt(&tour, true);
        else for (;;) {
            bool moved = false;
            if (!strcmp(c, "OROPT")) {
                for (int size = 1; size <= 3; size++) for (int i = 0; i + size <= tour.count; i++) {
                    Route segment = slice(&tour, i, i + size), rest = tour;
                    memmove(rest.ids + i, rest.ids + i + size, (size_t)(rest.count - i - size) * sizeof *rest.ids);
                    rest.count -= size;
                    for (int j = 0; j <= rest.count; j++) if (j != i) {
                        Route prefix = slice(&rest, 0, j), tail = slice(&rest, j, rest.count), first = concatenate(&prefix, &segment), next = concatenate(&first, &tail);
                        int gain = length(&tour) - length(&next);
                        if (gain > 0) {
                            fputs("move ", stdout);
                            for (int p = 0; p < segment.count; p++) {
                                if (p) putchar('-');
                                printf("%d", segment.ids[p]);
                            }
                            fputs(" after ", stdout);
                            location(at(&rest, j - 1));
                            printf(" gain %d\n", gain);
                            tour = next;
                            moves++;
                            moved = true;
                            goto tour_scan_done;
                        }
                    }
                }
            } else {
                for (int i = 0; i + 1 < tour.count; i++) for (int j = i + 1; j < tour.count; j++) {
                    Route next = tour;
                    next.ids[i] = tour.ids[j];
                    next.ids[j] = tour.ids[i];
                    int gain = length(&tour) - length(&next);
                    if (gain > 0) {
                        printf("swap %d and %d gain %d\n", tour.ids[i], tour.ids[j], gain);
                        tour = next;
                        moves++;
                        moved = true;
                        goto tour_scan_done;
                    }
                }
            }
            tour_scan_done: if (!moved) break;
        }
        printf("%s: moves %d, length %d -> %d\n", !strcmp(c, "TWOOPT") ? "twoopt" : !strcmp(c, "OROPT") ? "oropt" : "swap", moves, initial, length(&tour));
    } else if (!strcmp(c, "TIMECHECK")) {
        Route *route;
        if (count == 1) {
            tour_check();
            route = &tour;
            fputs("timecheck tour depart ", stdout);
        } else {
            plan_check();
            int r = atoi(w[1]);
            if (r > plan.count) fail("no route %d", r);
            route = &plan.routes[r - 1];
            printf("timecheck route %d depart ", r);
        }
        print_time(departure);
        putchar('\n');
        simulate(route, true);
    } else if (!strcmp(c, "BOUND")) {
        network_check();
        bound();
    } else if (!strcmp(c, "VRP") || !strcmp(c, "SPLIT") || !strcmp(c, "SWEEP")) {
        if (!strcmp(c, "SPLIT")) tour_check();
        else network_check();
        int q = atoi(w[1]);
        capacity_check(q);
        if (!strcmp(c, "VRP") && count == 3) for (int id = 1; id <= MAX_ID; id++) if (stops[id].present && 2 * distance(0, id) > atoi(w[2])) fail("stop %d too far for limit %s", id, w[2]);
        Plan next = {0};
        int merges = 0;
        if (!strcmp(c, "VRP")) {
            int all[MAX_STOPS], n = ids(all);
            Saving savings[MAX_STOPS * (MAX_STOPS - 1) / 2];
            int saving_count = 0;
            for (int i = 0; i < n; i++) {
                next.routes[next.count++] = (Route) {
                    1, {all[i]}
                };
                for (int j = i + 1; j < n; j++) {
                    int value = distance(0, all[i]) + distance(0, all[j]) - distance(all[i], all[j]);
                    if (value > 0) savings[saving_count++] = (Saving){all[i], all[j], value};
                }
            }
            qsort(savings, (size_t)saving_count, sizeof *savings, saving_compare);
            for (int i = 0; i < saving_count; i++) {
                Saving s = savings[i];
                int r = 0, t = 0;
                while (!contains(&next.routes[r], s.a)) r++;
                while (!contains(&next.routes[t], s.b)) t++;
                Route a = next.routes[r], b = next.routes[t];
                if (r == t || (a.ids[0] != s.a && a.ids[a.count - 1] != s.a) || (b.ids[0] != s.b && b.ids[b.count - 1] != s.b) || load(&a) + load(&b) > q) continue;
                if (a.ids[0] == s.a) reverse(&a, 0, a.count - 1);
                if (b.ids[b.count - 1] == s.b) reverse(&b, 0, b.count - 1);
                Route joined = concatenate(&a, &b);
                if (count == 3 && length(&joined) > atoi(w[2])) continue;
                remove_route(&next, maximum(r, t));
                remove_route(&next, minimum(r, t));
                next.routes[next.count++] = joined;
                merges++;
            }
        } else if (!strcmp(c, "SPLIT")) {
            int values[MAX_STOPS + 1], previous[MAX_STOPS + 1];
            values[0] = 0;
            for (int j = 1; j <= tour.count; j++) {
                values[j] = INT_MAX;
                for (int i = 0; i < j; i++) {
                    Route part = slice(&tour, i, j);
                    int candidate = values[i] + length(&part);
                    if (load(&part) <= q && candidate < values[j]) {
                        values[j] = candidate;
                        previous[j] = i;
                    }
                }
            }
            for (int j = tour.count; j > 0; j = previous[j]) next.routes[next.count++] = slice(&tour, previous[j], j);
        } else {
            int all[MAX_STOPS], n = ids(all);
            qsort(all, (size_t)n, sizeof *all, angle_compare);
            next.count = 1;
            for (int i = 0; i < n; i++) {
                Route *r = &next.routes[next.count - 1];
                if (load(r) + stops[all[i]].demand > q) r = &next.routes[next.count++];
                r->ids[r->count++] = all[i];
            }
        }
        plan = next;
        capacity = q;
        has_plan = true;
        normalize();
        printf("%s: capacity %d", !strcmp(c, "VRP") ? "vrp" : !strcmp(c, "SPLIT") ? "split" : "sweep", q);
        if (!strcmp(c, "VRP")) printf(", merges %d", merges);
        printf(", routes %d, length %d\n", plan.count, plan_length());
        route_lines();
    } else if (!strcmp(c, "ROUTES")) {
        plan_check();
        printf("plan: capacity %d, routes %d, length %d\n", capacity, plan.count, plan_length());
        route_lines();
    } else if (!strcmp(c, "RELOCATE") || !strcmp(c, "EXCHANGE") || !strcmp(c, "CROSS")) {
        plan_check();
        improve_plan(c);
    } else if (!strcmp(c, "ROUTEOPT")) {
        plan_check();
        int initial = plan_length();
        for (int i = 0; i < plan.count; i++) {
            int before = length(&plan.routes[i]), moves = two_opt(&plan.routes[i], false);
            printf("route %d: moves %d, length %d -> %d\n", i + 1, moves, before, length(&plan.routes[i]));
        }
        normalize();
        printf("routeopt: length %d -> %d\n", initial, plan_length());
    } else if (!strcmp(c, "REPORT")) {
        int demand = 0, service = 0, windows = 0;
        for (int id = 1; id <= MAX_ID; id++) if (stops[id].present) {
            demand += stops[id].demand;
            service += stops[id].service;
            windows += stops[id].open >= 0;
        }
        printf("report: stops %d, demand %d, service %d, windows %d\n", stop_count, demand, service, windows);
        if (!has_tour) puts("tour: none");
        else {
            Run run = simulate(&tour, false);
            printf("tour: length %d, return ", length(&tour));
            print_time(run.returned);
            printf(", violations %d, lateness %d\n", run.violations, run.lateness);
        }
        if (!has_plan) puts("plan: none");
        else {
            int returned = 0, violations = 0, lateness = 0;
            for (int i = 0; i < plan.count; i++) {
                Run run = simulate(&plan.routes[i], false);
                returned = maximum(returned, run.returned);
                violations += run.violations;
                lateness += run.lateness;
            }
            long long denominator = (long long)plan.count * capacity, utilization = (2000LL * demand + denominator) / (2 * denominator);
            printf("plan: capacity %d, routes %d, length %d, utilization %lld.%lld%%, return ", capacity, plan.count, plan_length(), utilization / 10, utilization % 10);
            print_time(returned);
            printf(", violations %d, lateness %d\n", violations, lateness);
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
    return 0;
}
