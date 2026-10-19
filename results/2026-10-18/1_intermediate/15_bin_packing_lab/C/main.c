#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define MAX_ITEMS 320
#define MAX_BINS 320
#define MAX_RECTS 26
#define MAX_PATTERNS 64

enum {
    NEXTFIT, FIRSTFIT, BESTFIT, WORSTFIT, ALMOSTWORST,
    HARMONIC, KBOUNDED, FFD, BFD, WFD
};

const char *METHODS[] = {
    "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
    "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"
};

typedef struct { int number, size; } Item;

typedef struct {
    Item items[MAX_ITEMS];
    int count, load, category;
} Bin;

typedef struct {
    Item item;
    int bin, inspected, opened, closed, category;
} Step;

typedef struct {
    int method, parameter, count, inspections, closes, steps_count;
    Bin *bins;
    Step *steps;
} Packing;

typedef struct {
    int alpha, j1, j2, j3, bound;
} BoundRow;

typedef struct {
    int first, second, count;
    BoundRow rows[41];
} Bounds;

typedef struct {
    int number, width, height;
} Rectangle;

typedef struct {
    Rectangle rectangle;
    int x, y, width, height, rotated;
} Placement;

typedef struct {
    int bottom, height, used, count;
    int item_numbers[MAX_RECTS], item_x[MAX_RECTS];
} Shelf;

typedef struct {
    int x, y, width, height;
} FreeRect;

typedef struct {
    FreeRect free[64];
    int free_count;
    Placement placed[MAX_RECTS];
    int placed_count, area;
} Sheet;

static Item items[40];
static int item_count = -1;
static int capacity = 0;

static int ceiling(int n, int d) {
    return (n + d - 1) / d;
}

static int total_size(const Item *list, int count) {
    int total = 0;
    for (int i = 0; i < count; ++i) total += list[i].size;
    return total;
}

static void put(Bin *bin, Item item) {
    bin->items[bin->count++] = item;
    bin->load += item.size;
}

static int compare_items(const void *left, const void *right) {
    const Item *a = left, *b = right;
    if (a->size != b->size) return a->size > b->size ? -1 : 1;
    return (a->number > b->number) - (a->number < b->number);
}

static void descending(Item *target, const Item *source, int count) {
    memcpy(target, source, sizeof(Item) * count);
    qsort(target, count, sizeof(Item), compare_items);
}

static void print_bin(int number, const Bin *bin, int cap, int show_class, int over) {
    printf("BIN %d load=%d/%d items=", number, bin->load, cap);
    for (int i = 0; i < bin->count; ++i) {
        if (i) putchar(' ');
        printf("%d:%d", bin->items[i].number, bin->items[i].size);
    }
    if (show_class) printf(" class=%d", bin->category);
    if (over) printf(" OVER");
    putchar('\n');
}

static int method_id(const char *name) {
    for (int i = 0; i < 10; ++i)
        if (strcmp(name, METHODS[i]) == 0) return i;
    return -1;
}

static int is_parameterized(int method) {
    return method == HARMONIC || method == KBOUNDED;
}

static void print_method_name(int method, int parameter) {
    printf("%s", METHODS[method]);
    if (is_parameterized(method)) printf(" k=%d", parameter);
}

static Packing pack(const Item *list, int count, int cap, int method, int k) {
    Packing result = {0};
    result.method = method;
    result.parameter = k;
    result.bins = calloc(MAX_BINS, sizeof(Bin));
    result.steps = calloc(MAX_ITEMS, sizeof(Step));
    Item order[MAX_ITEMS];
    if (method == FFD || method == BFD || method == WFD) {
        descending(order, list, count);
    } else {
        memcpy(order, list, sizeof(Item) * count);
    }
    int active[51] = {0}, active_count = 0;
    int current[51] = {0};
    for (int i = 0; i <= 50; ++i) current[i] = -1;

    for (int i = 0; i < count; ++i) {
        Item item = order[i];
        int before = result.inspections, chosen = -1, closed = -1, category = -1;

        if (method == NEXTFIT) {
            if (result.count) {
                result.inspections++;
                int last = result.count - 1;
                if (result.bins[last].load + item.size <= cap) chosen = last;
            }
        } else if (method == FIRSTFIT || method == FFD || method == KBOUNDED) {
            int candidates = method == KBOUNDED ? active_count : result.count;
            for (int b = 0; b < candidates; ++b) {
                int index = method == KBOUNDED ? active[b] : b;
                result.inspections++;
                if (result.bins[index].load + item.size <= cap) {
                    chosen = index;
                    break;
                }
            }
        } else if (method == HARMONIC) {
            category = cap / item.size < k ? cap / item.size : k;
            int index = current[category];
            if (index >= 0) {
                result.inspections++;
                if (result.bins[index].load + item.size <= cap) chosen = index;
            }
        } else {
            result.inspections += result.count;
            int fitting[MAX_BINS], fits = 0;
            for (int b = 0; b < result.count; ++b)
                if (result.bins[b].load + item.size <= cap) fitting[fits++] = b;
            if (fits) {
                chosen = fitting[0];
                if (method == BESTFIT || method == BFD) {
                    for (int b = 1; b < fits; ++b)
                        if (result.bins[fitting[b]].load > result.bins[chosen].load)
                            chosen = fitting[b];
                } else {
                    for (int b = 0; b < fits; ++b) {
                        for (int j = b + 1; j < fits; ++j) {
                            int a = fitting[b], c = fitting[j];
                            if (result.bins[c].load < result.bins[a].load ||
                                (result.bins[c].load == result.bins[a].load && c < a)) {
                                fitting[b] = c;
                                fitting[j] = a;
                            }
                        }
                    }
                    chosen = method == ALMOSTWORST && fits >= 2 ? fitting[1] : fitting[0];
                }
            }
        }
        int opened = chosen < 0;
        if (opened) {
            if (method == KBOUNDED && active_count == k) {
                int position = 0;
                for (int j = 1; j < active_count; ++j) {
                    int a = active[j], b = active[position];
                    if (result.bins[a].load > result.bins[b].load ||
                        (result.bins[a].load == result.bins[b].load && a < b)) position = j;
                }
                closed = active[position];
                memmove(&active[position], &active[position + 1],
                        (active_count - position - 1) * sizeof(int));
                active_count--;
                result.closes++;
            }
            chosen = result.count++;
            result.bins[chosen].category = category;
            if (method == KBOUNDED) active[active_count++] = chosen;
            if (method == HARMONIC) current[category] = chosen;
        }
        put(&result.bins[chosen], item);
        result.steps[result.steps_count++] =
            (Step){item, chosen, result.inspections - before, opened, closed, category};
    }
    return result;
}

static void dispose(Packing *result) {
    free(result->bins);
    free(result->steps);
}

static void print_header(const Packing *result, int cap, int total) {
    print_method_name(result->method, result->parameter);
    printf(" bins=%d inspections=%d waste=%d",
           result->count, result->inspections, result->count * cap - total);
    if (result->method == KBOUNDED) printf(" closes=%d", result->closes);
    putchar('\n');
}

static void print_bins(const Bin *bins, int count, int cap, int classes) {
    for (int i = 0; i < count; ++i)
        print_bin(i + 1, &bins[i], cap, classes, 0);
}

static Bounds calculate_bounds(const Item *list, int count, int cap) {
    Bounds result = {0};
    int alpha[41], alpha_count = 1;
    alpha[0] = 0;
    for (int i = 0; i < count; ++i) {
        if (2 * list[i].size > cap) continue;
        int exists = 0;
        for (int j = 0; j < alpha_count; ++j)
            if (alpha[j] == list[i].size) exists = 1;
        if (!exists) alpha[alpha_count++] = list[i].size;
    }
    for (int i = 0; i < alpha_count; ++i)
        for (int j = i + 1; j < alpha_count; ++j)
            if (alpha[j] < alpha[i]) {
                int tmp = alpha[i]; alpha[i] = alpha[j]; alpha[j] = tmp;
            }
    result.first = ceiling(total_size(list, count), cap);
    for (int i = 0; i < alpha_count; ++i) {
        int j1 = 0, j2 = 0, j3 = 0, second = 0, third = 0;
        for (int j = 0; j < count; ++j) {
            int size = list[j].size;
            if (size > cap - alpha[i]) j1++;
            else if (2 * size > cap) { j2++; second += size; }
            if (2 * size <= cap && size >= alpha[i]) { j3++; third += size; }
        }
        int excess = third - (j2 * cap - second);
        int bound = j1 + j2 + (excess > 0 ? ceiling(excess, cap) : 0);
        result.rows[result.count++] = (BoundRow){alpha[i], j1, j2, j3, bound};
        if (bound > result.second) result.second = bound;
    }
    return result;
}

typedef struct {
    Item sorted[20];
    int size, capacity, limit, lower, total;
    int remaining[21], nodes, status;
    Bin live[21], best[21];
    int live_count, best_count;
} Exact;

static void visit(Exact *search, int index) {
    if (search->status) return;
    if (search->nodes == search->limit) {
        search->status = 2;
        return;
    }
    search->nodes++;
    int count = search->live_count;
    int used = search->total - search->remaining[index];
    int free_space = count * search->capacity - used;
    int excess = search->remaining[index] - free_space;
    int minimum = count +
        (excess > 0 ? ceiling(excess, search->capacity) : 0);
    if (minimum >= search->best_count) return;
    if (index == search->size) {
        search->best_count = count;
        memcpy(search->best, search->live, count * sizeof(Bin));
        printf("IMPROVE bins=%d nodes=%d\n", count, search->nodes);
        if (count == search->lower) search->status = 1;
        return;
    }
    Item item = search->sorted[index];
    int seen[21], seen_count = 0;
    for (int b = 0; b < search->live_count; ++b) {
        Bin *bin = &search->live[b];
        int old = bin->load, repeated = 0;
        for (int j = 0; j < seen_count; ++j)
            if (seen[j] == old) repeated = 1;
        if (repeated) continue;
        seen[seen_count++] = old;
        if (old + item.size > search->capacity) continue;
        put(bin, item);
        visit(search, index + 1);
        bin->count--;
        bin->load = old;
        if (search->status) return;
    }
    if (count + 1 < search->best_count) {
        Bin *bin = &search->live[search->live_count++];
        memset(bin, 0, sizeof(Bin));
        put(bin, item);
        visit(search, index + 1);
        search->live_count--;
    }
}

static void run_exact(int limit) {
    if (limit == 0) { puts("ERROR BAD PARAMETER"); return; }
    if (item_count >= 21) { puts("ERROR TOO MANY ITEMS"); return; }
    Packing ffd = pack(items, item_count, capacity, FFD, 0);
    Bounds lower = calculate_bounds(items, item_count, capacity);
    printf("EXACT ffd=%d L2=%d\n", ffd.count, lower.second);
    Exact *search = calloc(1, sizeof(Exact));
    search->size = item_count;
    search->capacity = capacity;
    search->limit = limit;
    search->lower = lower.second;
    search->best_count = ffd.count;
    search->total = total_size(items, item_count);
    memcpy(search->best, ffd.bins, ffd.count * sizeof(Bin));
    descending(search->sorted, items, item_count);
    for (int i = item_count - 1; i >= 0; --i)
        search->remaining[i] = search->remaining[i + 1] + search->sorted[i].size;
    if (ffd.count == lower.second) search->status = 1;
    else visit(search, 0);
    printf("RESULT bins=%d nodes=%d status=%s\n", search->best_count,
           search->nodes, search->status == 1 ? "bound" :
           search->status == 2 ? "limit" : "complete");
    print_bins(search->best, search->best_count, capacity, 0);
    free(search);
    dispose(&ffd);
}

static void run_method(int method, int k) {
    if (is_parameterized(method) && !k) { puts("ERROR BAD PARAMETER"); return; }
    Packing result = pack(items, item_count, capacity, method, k);
    print_header(&result, capacity, total_size(items, item_count));
    print_bins(result.bins, result.count, capacity, method == HARMONIC);
    dispose(&result);
}

static void run_trace(int method, int k) {
    if (is_parameterized(method) && !k) { puts("ERROR BAD PARAMETER"); return; }
    Packing result = pack(items, item_count, capacity, method, k);
    printf("TRACE ");
    print_header(&result, capacity, total_size(items, item_count));
    for (int i = 0; i < result.steps_count; ++i) {
        Step *step = &result.steps[i];
        printf("STEP %d item=%d:%d bin=%d inspected=%d", i + 1,
               step->item.number, step->item.size, step->bin + 1, step->inspected);
        if (step->opened) printf(" new");
        if (step->closed >= 0) printf(" closed=%d", step->closed + 1);
        if (step->category >= 0) printf(" class=%d", step->category);
        putchar('\n');
    }
    dispose(&result);
}

typedef struct {
    int source, load, count;
    Item item[40];
    int destination[40];
} Elimination;

static void run_reduce(int method, int k) {
    if (is_parameterized(method) && !k) { puts("ERROR BAD PARAMETER"); return; }
    Packing result = pack(items, item_count, capacity, method, k);
    int before = result.count, event_count = 0;
    Elimination events[40];
    for (;;) {
        int eliminated = 0;
        int order[40];
        for (int i = 0; i < result.count; ++i) order[i] = i;
        for (int i = 0; i < result.count; ++i)
            for (int j = i + 1; j < result.count; ++j) {
                int a = order[i], b = order[j];
                if (result.bins[b].load < result.bins[a].load ||
                    (result.bins[b].load == result.bins[a].load && b < a)) {
                    order[i] = b; order[j] = a;
                }
            }
        for (int index = 0; index < result.count; ++index) {
            int source = order[index], loads[40], count = 0, valid = 1;
            Item sorted[40];
            int destinations[40];
            for (int b = 0; b < result.count; ++b) loads[b] = result.bins[b].load;
            descending(sorted, result.bins[source].items, result.bins[source].count);
            for (int j = 0; j < result.bins[source].count; ++j) {
                int dest = -1;
                for (int b = 0; b < result.count; ++b) {
                    if (b == source || loads[b] + sorted[j].size > capacity) continue;
                    if (dest < 0 || loads[b] > loads[dest] ||
                        (loads[b] == loads[dest] && b < dest)) dest = b;
                }
                if (dest < 0) { valid = 0; break; }
                loads[dest] += sorted[j].size;
                destinations[count++] = dest;
            }
            if (!valid) continue;
            Elimination *event = &events[event_count++];
            event->source = source;
            event->load = result.bins[source].load;
            event->count = count;
            for (int j = 0; j < count; ++j) {
                event->item[j] = sorted[j];
                event->destination[j] = destinations[j];
                put(&result.bins[destinations[j]], sorted[j]);
            }
            memmove(&result.bins[source], &result.bins[source + 1],
                    (result.count - source - 1) * sizeof(Bin));
            result.count--;
            eliminated = 1;
            break;
        }
        if (!eliminated) break;
    }
    printf("REDUCE ");
    print_method_name(method, k);
    printf(" before=%d after=%d eliminated=%d\n",
           before, result.count, before - result.count);
    for (int i = 0; i < event_count; ++i) {
        Elimination *event = &events[i];
        printf("ELIMINATE bin=%d load=%d moves=", event->source + 1, event->load);
        for (int j = 0; j < event->count; ++j) {
            if (j) putchar(' ');
            printf("%d:%d->%d", event->item[j].number,
                   event->item[j].size, event->destination[j] + 1);
        }
        putchar('\n');
    }
    print_bins(result.bins, result.count, capacity, method == HARMONIC);
    dispose(&result);
}

static void run_bounds(void) {
    Bounds result = calculate_bounds(items, item_count, capacity);
    printf("BOUNDS total=%d L1=%d L2=%d\n",
           total_size(items, item_count), result.first, result.second);
    for (int i = 0; i < result.count; ++i) {
        BoundRow row = result.rows[i];
        printf("ALPHA %d j1=%d j2=%d j3=%d bound=%d\n",
               row.alpha, row.j1, row.j2, row.j3, row.bound);
    }
}

typedef struct {
    int method, bins, inspections;
} Comparison;

static void run_compare(int k) {
    if (!k) { puts("ERROR BAD PARAMETER"); return; }
    Bounds bound = calculate_bounds(items, item_count, capacity);
    Comparison rows[10];
    for (int method = 0; method < 10; ++method) {
        Packing result = pack(items, item_count, capacity, method, k);
        rows[method] = (Comparison){method, result.count, result.inspections};
        dispose(&result);
    }
    for (int i = 0; i < 10; ++i)
        for (int j = i + 1; j < 10; ++j)
            if (rows[j].bins < rows[i].bins ||
                (rows[j].bins == rows[i].bins &&
                 strcmp(METHODS[rows[j].method], METHODS[rows[i].method]) < 0)) {
                Comparison temp = rows[i]; rows[i] = rows[j]; rows[j] = temp;
            }
    printf("COMPARE k=%d L1=%d L2=%d\n", k, bound.first, bound.second);
    int total = total_size(items, item_count);
    for (int i = 0; i < 10; ++i)
        printf("%s bins=%d gap=%d waste=%d inspections=%d\n",
               METHODS[rows[i].method], rows[i].bins, rows[i].bins - bound.second,
               rows[i].bins * capacity - total, rows[i].inspections);
}

static void run_check(char **args, int count) {
    if (count != item_count) { puts("ERROR BAD ASSIGNMENT"); return; }
    int used[41] = {0};
    for (int i = 0; i < count; ++i) {
        int label = atoi(args[i]);
        if (label == 0) { puts("ERROR BAD ASSIGNMENT"); return; }
        used[label] = 1;
    }
    Bin *bins = calloc(41, sizeof(Bin));
    int bin_count = 0, over = 0;
    for (int i = 0; i < count; ++i)
        put(&bins[atoi(args[i])], items[i]);
    for (int i = 1; i <= 40; ++i) {
        if (!used[i]) continue;
        bin_count++;
        if (bins[i].load > capacity) over++;
    }
    Bounds bound = calculate_bounds(items, item_count, capacity);
    printf("CHECK bins=%d over=%d L2=%d status=%s\n",
           bin_count, over, bound.second, over ? "invalid" : "valid");
    for (int i = 1; i <= 40; ++i)
        if (used[i]) print_bin(i, &bins[i], capacity, 0, bins[i].load > capacity);
    free(bins);
}

static void print_cover(const char *name, const Bin *bins, int count) {
    int covered = 0, rest = -1;
    for (int i = 0; i < count; ++i) {
        if (bins[i].load >= capacity) covered++;
        else rest = i;
    }
    printf("%s covered=%d rest=%d\n",
           name, covered, rest >= 0 ? bins[rest].load : 0);
    int number = 0;
    for (int i = 0; i < count; ++i)
        if (bins[i].load >= capacity)
            print_bin(++number, &bins[i], capacity, 0, 0);
    if (rest >= 0) {
        printf("REST items=");
        for (int i = 0; i < bins[rest].count; ++i) {
            if (i) putchar(' ');
            printf("%d:%d", bins[rest].items[i].number, bins[rest].items[i].size);
        }
        putchar('\n');
    }
}

static void run_cover(void) {
    printf("COVER total=%d upper=%d\n",
           total_size(items, item_count), total_size(items, item_count) / capacity);
    Bin *bins = calloc(40, sizeof(Bin));
    int count = 0;
    for (int i = 0; i < item_count; ++i) {
        if (!count || bins[count - 1].load >= capacity) count++;
        put(&bins[count - 1], items[i]);
    }
    print_cover("DNF", bins, count);
    memset(bins, 0, 40 * sizeof(Bin));
    Item order[40];
    descending(order, items, item_count);
    int left = 0, right = item_count - 1;
    count = 0;
    while (left <= right) {
        Bin *bin = &bins[count++];
        put(bin, order[left++]);
        while (bin->load < capacity && left <= right) put(bin, order[right--]);
    }
    print_cover("BIGSMALL", bins, count);
    free(bins);
}

static void print_machines(const Bin *bins, int count) {
    for (int i = 0; i < count; ++i) {
        printf("MACHINE %d load=%d items=", i + 1, bins[i].load);
        if (!bins[i].count) printf("-");
        for (int j = 0; j < bins[i].count; ++j) {
            if (j) putchar(' ');
            printf("%d:%d", bins[i].items[j].number, bins[i].items[j].size);
        }
        putchar('\n');
    }
}

static void run_multifit(int count) {
    if (!count) { puts("ERROR BAD PARAMETER"); return; }
    int total = total_size(items, item_count), largest = 0;
    for (int i = 0; i < item_count; ++i)
        if (items[i].size > largest) largest = items[i].size;
    int lo = ceiling(total, count), hi = ceiling(2 * total, count);
    if (lo < largest) lo = largest;
    if (hi < largest) hi = largest;
    printf("MULTIFIT m=%d lower=%d upper=%d\n", count, lo, hi);
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        Packing result = pack(items, item_count, mid, FFD, 0);
        int bins = result.count, ok = bins <= count;
        printf("TRY cap=%d bins=%d %s\n", mid, bins, ok ? "ok" : "fail");
        dispose(&result);
        if (ok) hi = mid;
        else lo = mid + 1;
    }
    Packing result = pack(items, item_count, hi, FFD, 0);
    int makespan = 0;
    Bin *machines = calloc(count, sizeof(Bin));
    for (int i = 0; i < result.count; ++i)
        machines[i] = result.bins[i];
    for (int i = 0; i < count; ++i)
        if (machines[i].load > makespan) makespan = machines[i].load;
    printf("RESULT cap=%d makespan=%d\n", hi, makespan);
    print_machines(machines, count);
    memset(machines, 0, count * sizeof(Bin));
    Item sorted[40];
    descending(sorted, items, item_count);
    for (int i = 0; i < item_count; ++i) {
        int chosen = 0;
        for (int j = 1; j < count; ++j)
            if (machines[j].load < machines[chosen].load) chosen = j;
        put(&machines[chosen], sorted[i]);
    }
    makespan = 0;
    for (int i = 0; i < count; ++i)
        if (machines[i].load > makespan) makespan = machines[i].load;
    printf("LPT makespan=%d\n", makespan);
    print_machines(machines, count);
    free(machines);
    dispose(&result);
}

typedef struct { int size, demand; } Piece;
typedef struct { int counts[6], trim; } Pattern;

static Piece pieces[6];
static Pattern patterns[MAX_PATTERNS];
static int piece_count, pattern_count;

static void enumerate_patterns(int index, int remaining, int *prefix) {
    int maximum = remaining / pieces[index].size;
    if (index == piece_count - 1) {
        Pattern *pattern = &patterns[pattern_count++];
        memcpy(pattern->counts, prefix, index * sizeof(int));
        pattern->counts[index] = maximum;
        pattern->trim = remaining - maximum * pieces[index].size;
        return;
    }
    for (int count = maximum; count >= 0; --count) {
        prefix[index] = count;
        enumerate_patterns(index + 1, remaining - count * pieces[index].size, prefix);
    }
}

static int compare_pieces(const void *left, const void *right) {
    const Piece *a = left, *b = right;
    return (a->size < b->size) - (a->size > b->size);
}

static void run_cutstock(char **args, int count) {
    int cap = atoi(args[0]);
    if (!cap) { puts("ERROR BAD CAPACITY"); return; }
    piece_count = count - 1;
    for (int i = 0; i < piece_count; ++i) {
        int size = 0, demand = 0;
        sscanf(args[i + 1], "%d:%d", &size, &demand);
        if (!size || size > cap || !demand) {
            printf("ERROR BAD PIECE %d\n", i + 1); return;
        }
        for (int j = 0; j < i; ++j)
            if (pieces[j].size == size) {
                printf("ERROR DUPLICATE PIECE %d\n", i + 1); return;
            }
        pieces[i] = (Piece){size, demand};
    }
    qsort(pieces, piece_count, sizeof(Piece), compare_pieces);
    pattern_count = 0;
    int prefix[6] = {0};
    enumerate_patterns(0, cap, prefix);
    int remaining[6], uses[MAX_PATTERNS] = {0}, cut[6] = {0};
    int quantity = 0, bars = 0, trim = 0, surplus = 0;
    for (int i = 0; i < piece_count; ++i) {
        remaining[i] = pieces[i].demand;
        quantity += pieces[i].size * pieces[i].demand;
    }
    for (;;) {
        int needed = 0, chosen = 0, best = -1;
        for (int j = 0; j < piece_count; ++j)
            if (remaining[j]) needed = 1;
        if (!needed) break;
        for (int p = 0; p < pattern_count; ++p) {
            int useful = 0;
            for (int j = 0; j < piece_count; ++j) {
                int value = patterns[p].counts[j];
                useful += value < remaining[j] ? value : remaining[j];
            }
            if (useful > best) { best = useful; chosen = p; }
        }
        uses[chosen]++;
        for (int j = 0; j < piece_count; ++j) {
            remaining[j] -= patterns[chosen].counts[j];
            if (remaining[j] < 0) remaining[j] = 0;
        }
    }
    printf("CUTSTOCK L=%d pieces=%d patterns=%d\n", cap, piece_count, pattern_count);
    for (int p = 0; p < pattern_count; ++p) {
        printf("PATTERN %d ", p + 1);
        int printed = 0;
        for (int j = 0; j < piece_count; ++j) {
            int n = patterns[p].counts[j];
            if (n) {
                if (printed++) putchar('+');
                printf("%dx%d", n, pieces[j].size);
            }
            cut[j] += uses[p] * n;
        }
        printf(" rest=%d\n", patterns[p].trim);
        if (uses[p]) { bars += uses[p]; trim += uses[p] * patterns[p].trim; }
    }
    for (int p = 0; p < pattern_count; ++p)
        if (uses[p]) printf("USE %d bars=%d\n", p + 1, uses[p]);
    for (int j = 0; j < piece_count; ++j) {
        printf("PIECE %d demand=%d cut=%d\n",
               pieces[j].size, pieces[j].demand, cut[j]);
        surplus += cut[j] - pieces[j].demand;
    }
    printf("TOTAL bars=%d trim=%d surplus=%d waste=%d\n",
           bars, trim, surplus, bars * cap - quantity);
    Item comparison[MAX_ITEMS];
    int k = 0;
    for (int j = 0; j < piece_count; ++j)
        for (int n = 0; n < pieces[j].demand; ++n)
            {
                comparison[k] = (Item){k + 1, pieces[j].size};
            k++;
            }
    Packing firstfit = pack(comparison, k, cap, FIRSTFIT, 0);
    printf("FFD bars=%d waste=%d\n", firstfit.count, firstfit.count * cap - quantity);
    printf("LOWER bars=%d\n", ceiling(quantity, cap));
    dispose(&firstfit);
}

static int compare_shelf_rects(const void *left, const void *right) {
    const Rectangle *a = left, *b = right;
    if (a->height != b->height) return a->height > b->height ? -1 : 1;
    if (a->width != b->width) return a->width > b->width ? -1 : 1;
    return a->number - b->number;
}

static int compare_area_rects(const void *left, const void *right) {
    const Rectangle *a = left, *b = right;
    int area_a = a->width * a->height, area_b = b->width * b->height;
    if (area_a != area_b) return area_a > area_b ? -1 : 1;
    return a->number - b->number;
}

static void draw(int width, int height, const Placement *places, int count) {
    char grid[400][41];
    for (int y = 0; y < height; ++y) {
        memset(grid[y], '.', width);
        grid[y][width] = '\0';
    }
    for (int i = 0; i < count; ++i) {
        Placement p = places[i];
        for (int y = p.y; y < p.y + p.height; ++y)
            for (int x = p.x; x < p.x + p.width; ++x)
                grid[y][x] = 'A' + p.rectangle.number - 1;
    }
    for (int y = height - 1; y >= 0; --y) puts(grid[y]);
}

static void run_shelf_method(int method, int width, Rectangle *rects, int count, int area) {
    const char *names[] = {"NFDH", "FFDH", "BFDH"};
    Shelf shelves[MAX_RECTS] = {0};
    Placement placed[MAX_RECTS];
    int shelf_count = 0;
    for (int i = 0; i < count; ++i) {
        Rectangle rect = rects[i];
        int chosen = -1;
        if (method == 0) {
            if (shelf_count && shelves[shelf_count - 1].used + rect.width <= width)
                chosen = shelf_count - 1;
        } else {
            for (int j = 0; j < shelf_count; ++j) {
                if (shelves[j].used + rect.width > width) continue;
                if (chosen < 0 || (method == 2 && shelves[j].used > shelves[chosen].used))
                    chosen = j;
            }
        }
        if (chosen < 0) {
            chosen = shelf_count++;
            shelves[chosen].bottom = chosen ?
                shelves[chosen - 1].bottom + shelves[chosen - 1].height : 0;
            shelves[chosen].height = rect.height;
        }
        Shelf *shelf = &shelves[chosen];
        shelf->item_numbers[shelf->count] = rect.number;
        shelf->item_x[shelf->count++] = shelf->used;
        placed[i] = (Placement){rect, shelf->used, shelf->bottom,
                                rect.width, rect.height, 0};
        shelf->used += rect.width;
    }
    int height = shelves[shelf_count - 1].bottom + shelves[shelf_count - 1].height;
    printf("%s height=%d shelves=%d util=%d\n", names[method],
           height, shelf_count, area * 100 / (width * height));
    for (int s = 0; s < shelf_count; ++s) {
        Shelf *shelf = &shelves[s];
        printf("LEVEL %d y=%d h=%d used=%d items=",
               s + 1, shelf->bottom, shelf->height, shelf->used);
        for (int j = 0; j < shelf->count; ++j) {
            if (j) putchar(' ');
            printf("%c@%d", 'A' + shelf->item_numbers[j] - 1, shelf->item_x[j]);
        }
        putchar('\n');
    }
    draw(width, height, placed, count);
}

static int read_rectangles(char **args, int count, Rectangle *rects) {
    for (int i = 0; i < count; ++i) {
        int width, height;
        sscanf(args[i], "%dx%d", &width, &height);
        rects[i] = (Rectangle){i + 1, width, height};
    }
    return count;
}

static void run_shelf(char **args, int count) {
    int width = atoi(args[0]);
    if (!width) { puts("ERROR BAD CAPACITY"); return; }
    Rectangle rects[MAX_RECTS];
    int n = read_rectangles(args + 1, count - 1, rects);
    for (int i = 0; i < n; ++i)
        if (!rects[i].width || !rects[i].height || rects[i].width > width) {
            printf("ERROR BAD RECT %d\n", i + 1); return;
        }
    qsort(rects, n, sizeof(Rectangle), compare_shelf_rects);
    int area = 0;
    for (int i = 0; i < n; ++i) area += rects[i].width * rects[i].height;
    printf("SHELF W=%d rects=%d area=%d\n", width, n, area);
    for (int method = 0; method < 3; ++method)
        run_shelf_method(method, width, rects, n, area);

    int heights[40] = {0}, height = 0;
    Placement placed[MAX_RECTS];
    for (int i = 0; i < n; ++i) {
        Rectangle rect = rects[i];
        int chosen_x = 0, chosen_y = 2147483647;
        for (int x = 0; x + rect.width <= width; ++x) {
            int y = 0;
            for (int j = x; j < x + rect.width; ++j)
                if (heights[j] > y) y = heights[j];
            if (y < chosen_y) { chosen_x = x; chosen_y = y; }
        }
        for (int j = chosen_x; j < chosen_x + rect.width; ++j)
            heights[j] = chosen_y + rect.height;
        placed[i] = (Placement){rect, chosen_x, chosen_y, rect.width, rect.height, 0};
    }
    for (int x = 0; x < width; ++x)
        if (heights[x] > height) height = heights[x];
    printf("SKYLINE height=%d util=%d\n", height, area * 100 / (width * height));
    for (int i = 0; i < n; ++i) {
        Placement p = placed[i];
        printf("PLACE %c x=%d y=%d w=%d h=%d\n",
               'A' + p.rectangle.number - 1, p.x, p.y, p.width, p.height);
    }
    draw(width, height, placed, n);
}

static int free_rectangle(Sheet *sheets, int count, int width, int height,
                          int rotate, int rule, int *sheet_index, int *free_index) {
    int best = -1;
    for (int s = 0; s < count; ++s) {
        for (int i = 0; i < sheets[s].free_count; ++i) {
            FreeRect rect = sheets[s].free[i];
            int fits = width <= rect.width && height <= rect.height;
            int rotated = rotate && height <= rect.width && width <= rect.height;
            if (!fits && !rotated) continue;
            if (rule == 0) {
                *sheet_index = s; *free_index = i; return 1;
            }
            int area = rect.width * rect.height;
            if (best < 0 || area < best) {
                best = area;
                *sheet_index = s; *free_index = i;
            }
        }
    }
    return best >= 0;
}

static void run_guillotine(char **args, int count) {
    int width = atoi(args[0]), height = atoi(args[1]);
    if (!width || !height) { puts("ERROR BAD CAPACITY"); return; }
    int rotate = strcmp(args[2], "ROTATE") == 0;
    int rule = strcmp(args[3], "FIRST") == 0 ? 0 : 1;
    Rectangle rects[MAX_RECTS];
    int n = read_rectangles(args + 4, count - 4, rects);
    for (int i = 0; i < n; ++i) {
        Rectangle rect = rects[i];
        int fits = rect.width <= width && rect.height <= height;
        int rotated = rotate && rect.height <= width && rect.width <= height;
        if (!rect.width || !rect.height || (!fits && !rotated)) {
            printf("ERROR BAD RECT %d\n", i + 1); return;
        }
    }
    qsort(rects, n, sizeof(Rectangle), compare_area_rects);
    Sheet sheets[MAX_RECTS] = {0};
    int sheet_count = 0, rotated_count = 0, area = 0;
    for (int i = 0; i < n; ++i) {
        Rectangle rect = rects[i];
        int sheet_index = 0, free_index = 0;
        if (!free_rectangle(sheets, sheet_count, rect.width, rect.height,
                            rotate, rule, &sheet_index, &free_index)) {
            sheet_index = sheet_count++;
            sheets[sheet_index].free[sheets[sheet_index].free_count++] =
                (FreeRect){0, 0, width, height};
        }
        Sheet *sheet = &sheets[sheet_index];
        FreeRect free_rect = sheet->free[free_index];
        memmove(&sheet->free[free_index], &sheet->free[free_index + 1],
                (sheet->free_count - free_index - 1) * sizeof(FreeRect));
        sheet->free_count--;
        int rotated = !(rect.width <= free_rect.width && rect.height <= free_rect.height);
        int pw = rotated ? rect.height : rect.width;
        int ph = rotated ? rect.width : rect.height;
        rotated_count += rotated;
        sheet->placed[sheet->placed_count++] =
            (Placement){rect, free_rect.x, free_rect.y, pw, ph, rotated};
        sheet->area += rect.width * rect.height;
        area += rect.width * rect.height;
        int rw = free_rect.width - pw, rh = free_rect.height - ph;
        FreeRect top, right;
        if (rw <= rh) {
            top = (FreeRect){free_rect.x, free_rect.y + ph, free_rect.width, rh};
            right = (FreeRect){free_rect.x + pw, free_rect.y, rw, ph};
        } else {
            top = (FreeRect){free_rect.x, free_rect.y + ph, pw, rh};
            right = (FreeRect){free_rect.x + pw, free_rect.y, rw, free_rect.height};
        }
        if (top.width && top.height) sheet->free[sheet->free_count++] = top;
        if (right.width && right.height) sheet->free[sheet->free_count++] = right;
    }
    printf("GUILLOTINE W=%d H=%d mode=%s rule=%s rects=%d sheets=%d "
           "rotated=%d util=%d\n", width, height, args[2], args[3],
           n, sheet_count, rotated_count, area * 100 / (sheet_count * width * height));
    for (int s = 0; s < sheet_count; ++s) {
        Sheet *sheet = &sheets[s];
        printf("SHEET %d placed=%d area=%d\n", s + 1, sheet->placed_count, sheet->area);
        for (int j = 0; j < sheet->placed_count; ++j) {
            Placement p = sheet->placed[j];
            printf("PLACE %c x=%d y=%d w=%d h=%d",
                   'A' + p.rectangle.number - 1, p.x, p.y, p.width, p.height);
            if (p.rotated) printf(" rotated");
            putchar('\n');
        }
        printf("FREE");
        if (!sheet->free_count) printf(" none");
        for (int j = 0; j < sheet->free_count; ++j) {
            FreeRect f = sheet->free[j];
            printf(" %d,%d,%dx%d", f.x, f.y, f.width, f.height);
        }
        putchar('\n');
        draw(width, height, sheet->placed, sheet->placed_count);
    }
}

static void handle(const char *command, char **args, int count) {
    if (strcmp(command, "ITEMS") == 0) {
        int cap = atoi(args[0]);
        if (!cap) { puts("ERROR BAD CAPACITY"); return; }
        Item next[40];
        for (int i = 1; i < count; ++i) {
            int size = atoi(args[i]);
            if (!size || size > cap) {
                printf("ERROR BAD ITEM %d\n", i); return;
            }
            next[i - 1] = (Item){i, size};
        }
        capacity = cap;
        item_count = count - 1;
        memcpy(items, next, item_count * sizeof(Item));
        printf("ITEMS count=%d capacity=%d total=%d\n",
               item_count, capacity, total_size(items, item_count));
        return;
    }
    if (strcmp(command, "RANDOM") == 0) {
        int n = atoi(args[0]), cap = atoi(args[1]);
        int64_t state = strtoll(args[2], NULL, 10);
        if (!n || n > 40) { puts("ERROR BAD COUNT"); return; }
        if (!cap) { puts("ERROR BAD CAPACITY"); return; }
        if (!state || state >= 2147483647) { puts("ERROR BAD SEED"); return; }
        Item next[40];
        for (int i = 0; i < n; ++i) {
            state = 48271 * state % 2147483647;
            next[i] = (Item){i + 1, state % cap + 1};
        }
        capacity = cap;
        item_count = n;
        memcpy(items, next, n * sizeof(Item));
        printf("RANDOM count=%d capacity=%d total=%d\n", n, cap, total_size(items, n));
        printf("SIZES");
        for (int i = 0; i < n; ++i) printf(" %d", items[i].size);
        putchar('\n');
        return;
    }
    if (strcmp(command, "CUTSTOCK") == 0) { run_cutstock(args, count); return; }
    if (strcmp(command, "SHELF") == 0) { run_shelf(args, count); return; }
    if (strcmp(command, "GUILLOTINE") == 0) { run_guillotine(args, count); return; }

    if (item_count < 0) { puts("ERROR NO ITEMS"); return; }
    int method = method_id(command);
    if (method >= 0) {
        run_method(method, is_parameterized(method) ? atoi(args[0]) : 0);
    } else if (strcmp(command, "TRACE") == 0) {
        method = method_id(args[0]);
        run_trace(method, is_parameterized(method) ? atoi(args[1]) : 0);
    } else if (strcmp(command, "REDUCE") == 0) {
        method = method_id(args[0]);
        run_reduce(method, is_parameterized(method) ? atoi(args[1]) : 0);
    } else if (strcmp(command, "BOUNDS") == 0) {
        run_bounds();
    } else if (strcmp(command, "COMPARE") == 0) {
        run_compare(atoi(args[0]));
    } else if (strcmp(command, "EXACT") == 0) {
        run_exact(atoi(args[0]));
    } else if (strcmp(command, "CHECK") == 0) {
        run_check(args, count);
    } else if (strcmp(command, "COVER") == 0) {
        run_cover();
    } else if (strcmp(command, "MULTIFIT") == 0) {
        run_multifit(atoi(args[0]));
    }
}

int main(void) {
    int commands;
    if (scanf("%d", &commands) != 1) return 0;
    int c;
    while ((c = getchar()) != '\n' && c != EOF) {}
    char line[8192];
    for (int k = 0; k < commands && fgets(line, sizeof(line), stdin); ++k) {
        char *args[320];
        int count = 0;
        char *command = strtok(line, " \r\n");
        char *token;
        while ((token = strtok(NULL, " \r\n")) != NULL) args[count++] = token;
        handle(command, args, count);
    }
    return 0;
}
