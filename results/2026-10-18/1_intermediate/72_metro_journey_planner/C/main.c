#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define APPEND(a, n, v) do { (a) = resize((a), ((n) + 1) * sizeof(*(a))); (a)[(n)++] = (v); } while (0)
typedef struct {
    char *data;
    size_t length, capacity;
} Buffer;
typedef struct Station Station;
typedef struct Line Line;
typedef struct {
    Station *neighbor;
    int minutes;
} Walk;
struct Station {
    char *id, *name;
    int zone, transfer;
    size_t index;
    bool closed;
    Walk *walks;
    size_t walk_count;
};
struct Line {
    char *id;
    int first, last, headway, delay;
    bool suspended;
    Station **stops;
    int *cumulative;
    size_t count;
};
typedef struct {
    Station *a, *b;
} Segment;
typedef struct {
    char kind;
    Line *line;
    Station *terminal, *from, *to;
    int departure, arrival, stops;
} Leg;
typedef struct Node Node;
struct Node {
    Leg leg;
    Node *previous, *allocated_next;
};
typedef struct {
    bool present;
    int time;
    Node *journey;
} Label;
typedef struct {
    Label *labels;
    Node *allocated;
} Search;
typedef struct {
    Label **labels;
    size_t count;
    Node *allocated;
} Rounds;
typedef struct {
    int time, direction;
    Line *line;
} Departure;
typedef struct {
    char **items;
    size_t count;
} Strings;
static Station **stations;
static Line **lines;
static Segment *closed_segments;
static size_t station_count, line_count, closed_count;
static int *prices, discount, window;
static size_t price_count;
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

static Station *find_station(const char *id) {
    for (size_t i = 0; i < station_count; i++) if (!strcmp(stations[i]->id, id)) return stations[i];
    return NULL;
}

static Station *station(const char *id) {
    Station *result = find_station(id);
    if (!result) error("unknown station %s", id);
    return result;
}

static Line *find_line(const char *id) {
    for (size_t i = 0; i < line_count; i++) if (!strcmp(lines[i]->id, id)) return lines[i];
    return NULL;
}

static Line *line(const char *id) {
    Line *result = find_line(id);
    if (!result) error("unknown line %s", id);
    return result;
}

static int station_compare(const void *a, const void *b) {
    return strcmp((*(Station *const *)a)->id, (*(Station *const *)b)->id);
}

static int line_compare(const void *a, const void *b) {
    return strcmp((*(Line *const *)a)->id, (*(Line *const *)b)->id);
}

static int walk_compare(const void *a, const void *b) {
    return strcmp(((const Walk *)a)->neighbor->id, ((const Walk *)b)->neighbor->id);
}

static int time_value(const char *text) {
    return atoi(text) * 60 + atoi(text + 3);
}

static char *clock_text(int time) {
    return format("%02d:%02d", time / 60, time % 60);
}

static Segment segment(Station *a, Station *b) {
    return strcmp(a->id, b->id) <= 0 ? (Segment){a, b} : (Segment){b, a};
}

static bool same_segment(Segment a, Segment b) {
    return a.a == b.a && a.b == b.b;
}

static bool blocked(Station *a, Station *b) {
    Segment key = segment(a, b);
    for (size_t i = 0; i < closed_count; i++) if (same_segment(key, closed_segments[i])) return true;
    return false;
}

static int segment_compare(const void *a, const void *b) {
    const Segment *x = a, *y = b;
    int order = strcmp(x->a->id, y->a->id);
    return order ? order : strcmp(x->b->id, y->b->id);
}

static int total(Line *line) {
    return line->cumulative[line->count - 1];
}

static int trips(Line *line) {
    return (line->last - line->first) / line->headway + 1;
}

static Station *stop(Line *line, int direction, int index) {
    return line->stops[direction ? line->count - 1 - (size_t)index : (size_t)index];
}

static int offset(Line *line, int direction, int index) {
    return direction ? total(line) - line->cumulative[line->count - 1 - (size_t)index] : line->cumulative[index];
}

static int position(Line *line, int direction, Station *station) {
    for (size_t i = 0; i < line->count; i++) if (line->stops[i] == station) return direction ? (int)(line->count - 1 - i) : (int)i;
    return -1;
}

static int train_time(Line *line, int direction, int index, int train) {
    return line->first + line->delay + train * line->headway + offset(line, direction, index);
}

static int next_train(Line *line, int direction, int index, int ready) {
    int start = train_time(line, direction, index, 0), train = ready <= start ? 0 : (ready - start + line->headway - 1) / line->headway;
    return train < trips(line) ? train : -1;
}

static int direction(Line *line, const char *terminal) {
    if (strcmp(line->stops[0]->id, terminal) && strcmp(line->stops[line->count - 1]->id, terminal)) error("%s is not a terminal of line %s", terminal, line->id);
    return !strcmp(line->stops[line->count - 1]->id, terminal) ? 0 : 1;
}

static Node *add_leg(Node **allocated, Node *previous, Leg leg) {
    Node *node = allocate(sizeof(*node));
    *node = (Node){leg, previous, *allocated};
    *allocated = node;
    return node;
}

static void free_nodes(Node *node) {
    while (node) {
        Node *next = node->allocated_next;
        free(node);
        node = next;
    }
}

static void free_search(Search result) {
    free_nodes(result.allocated);
    free(result.labels);
}

static Label *copy_labels(Label *source) {
    Label *result = allocate(station_count * sizeof(*result));
    memcpy(result, source, station_count * sizeof(*result));
    return result;
}

static bool better(Label *labels, Station *station, int arrival) {
    return !labels[station->index].present || labels[station->index].time > arrival;
}

static void relax(Label *labels, Node **allocated, Station *station, int arrival, Node *journey, Leg leg) {
    if (better(labels, station, arrival)) labels[station->index] = (Label){true, arrival, add_leg(allocated, journey, leg)};
}

static Search earliest(Station *origin, int departure) {
    Search result = {.labels = allocate(station_count * sizeof(*result.labels))};
    bool *settled = allocate(station_count * sizeof(*settled));
    result.labels[origin->index] = (Label){true, departure, NULL};
    while (true) {
        Station *selected = NULL;
        for (size_t i = 0; i < station_count; i++) {
            Station *s = stations[i];
            if (!settled[s->index] && result.labels[s->index].present && (!selected || result.labels[s->index].time < result.labels[selected->index].time)) selected = s;
        }
        if (!selected) break;
        Station *u = selected;
        settled[u->index] = true;
        Label label = result.labels[u->index];
        int ready = label.time + (u == origin ? 0 : u->transfer);
        for (size_t l = 0; l < line_count; l++) {
            Line *current = lines[l];
            if (current->suspended || position(current, 0, u) < 0) continue;
            for (int d = 0; d < 2; d++) {
                int i = position(current, d, u), last = (int)current->count - 1;
                if (i == last) continue;
                int train = next_train(current, d, i, ready);
                if (train < 0) continue;
                int start = train_time(current, d, i, train);
                for (int j = i + 1; j <= last; j++) {
                    Station *v = stop(current, d, j);
                    if (blocked(stop(current, d, j - 1), v)) break;
                    if (v->closed) continue;
                    int arrival = train_time(current, d, j, train);
                    relax(result.labels, &result.allocated, v, arrival, label.journey, (Leg){'R', current, stop(current, d, last), u, v, start, arrival, j - i});
                }
            }
        }
        for (size_t i = 0; i < u->walk_count; i++) {
            Walk walk = u->walks[i];
            int arrival = label.time + walk.minutes;
            if (!walk.neighbor->closed && arrival <= 1440) relax(result.labels, &result.allocated, walk.neighbor, arrival, label.journey, (Leg){'W', NULL, NULL, u, walk.neighbor, label.time, arrival, 0});
        }
    }
    free(settled);
    return result;
}

static void walk_step(Label *labels, bool *origins, bool *marked, Node **allocated) {
    // Walks use a snapshot taken after all ride updates in this round.
    Label *recorded = copy_labels(labels);
    for (size_t i = 0; i < station_count; i++) {
        Station *u = stations[i];
        if (!origins[u->index]) continue;
        Label label = recorded[u->index];
        for (size_t j = 0; j < u->walk_count; j++) {
            Walk walk = u->walks[j];
            int arrival = label.time + walk.minutes;
            if (!walk.neighbor->closed && arrival <= 1440 && better(labels, walk.neighbor, arrival)) {
                relax(labels, allocated, walk.neighbor, arrival, label.journey, (Leg){'W', NULL, NULL, u, walk.neighbor, label.time, arrival, 0});
                marked[walk.neighbor->index] = true;
            }
        }
    }
    free(recorded);
}

static bool any_marked(bool *marked) {
    for (size_t i = 0; i < station_count; i++) if (marked[i]) return true;
    return false;
}

static Rounds rounds(Station *origin, int departure) {
    Rounds result = {0};
    Label *previous = allocate(station_count * sizeof(*previous));
    previous[origin->index] = (Label){true, departure, NULL};
    bool *marked = allocate(station_count * sizeof(*marked)), *initial = allocate(station_count * sizeof(*initial));
    marked[origin->index] = initial[origin->index] = true;
    walk_step(previous, initial, marked, &result.allocated);
    free(initial);
    APPEND(result.labels, result.count, previous);
    while (any_marked(marked)) {
        Label *current = copy_labels(previous);
        bool *updated = allocate(station_count * sizeof(*updated)), *walks = allocate(station_count * sizeof(*walks));
        for (size_t l = 0; l < line_count; l++) {
            Line *line = lines[l];
            if (line->suspended) continue;
            for (int d = 0; d < 2; d++) {
                int boarded = -1, board_index = -1, board_time = 0, last = (int)line->count - 1;
                Node *board_journey = NULL;
                for (int j = 0; j <= last; j++) {
                    Station *u = stop(line, d, j);
                    if (j && blocked(stop(line, d, j - 1), u)) boarded = -1;
                    if (u->closed) continue;
                    if (boarded >= 0) {
                        int arrival = train_time(line, d, j, boarded);
                        if (better(current, u, arrival)) {
                            relax(current, &result.allocated, u, arrival, board_journey, (Leg){'R', line, stop(line, d, last), stop(line, d, board_index), u, board_time, arrival, j - board_index});
                            walks[u->index] = updated[u->index] = true;
                        }
                    }
                    if (j < last && marked[u->index]) {
                        Label label = previous[u->index];
                        int ready = label.time + (u == origin ? 0 : u->transfer), train = next_train(line, d, j, ready);
                        if (train >= 0 && (boarded < 0 || train < boarded)) {
                            boarded = train;
                            board_index = j;
                            board_time = train_time(line, d, j, train);
                            board_journey = label.journey;
                        }
                    }
                }
            }
        }
        walk_step(current, walks, updated, &result.allocated);
        free(walks);
        free(marked);
        marked = updated;
        APPEND(result.labels, result.count, current);
        previous = current;
    }
    free(marked);
    return result;
}

static void free_rounds(Rounds result) {
    for (size_t i = 0; i < result.count; i++) free(result.labels[i]);
    free(result.labels);
    free_nodes(result.allocated);
}

static int rides(Node *journey) {
    int count = 0;
    for (; journey; journey = journey->previous) if (journey->leg.kind == 'R') count++;
    return count;
}

static Leg *journey_legs(Node *journey, size_t *count) {
    *count = 0;
    for (Node *node = journey; node; node = node->previous) (*count)++;
    Leg *result = allocate(*count * sizeof(*result));
    size_t at = *count;
    for (; journey; journey = journey->previous) result[--at] = journey->leg;
    return result;
}

static void print_journey(const char *heading, int departure, Label label) {
    size_t count;
    Leg *legs = journey_legs(label.journey, &count);
    int walks = 0;
    for (size_t i = 0; i < count; i++) if (legs[i].kind == 'W') walks++;
    printf("%s %s -> %s total %d rides %d walks %d\n", heading, clock_text(departure), clock_text(label.time), label.time - departure, rides(label.journey), walks);
    int previous = departure;
    for (size_t i = 0; i < count; i++) {
        Leg leg = legs[i];
        if (leg.kind == 'R') printf("RIDE %s toward %s %s %s -> %s %s wait %d stops %d\n", leg.line->id, leg.terminal->id, leg.from->id, clock_text(leg.departure), leg.to->id, clock_text(leg.arrival), leg.departure - previous, leg.stops);
        else if (leg.kind == 'W') printf("WALK %s %s -> %s %s\n", leg.from->id, clock_text(leg.departure), leg.to->id, clock_text(leg.arrival));
        else printf("STAY %s %s -> %s\n", leg.from->id, clock_text(leg.departure), clock_text(leg.arrival));
        previous = leg.arrival;
    }
    free(legs);
}

static void search_check(Station *origin, Station *destination) {
    if (origin == destination) error("origin and destination are the same");
    if (origin->closed) error("station %s is closed", origin->id);
    if (destination->closed) error("station %s is closed", destination->id);
}

static int half(int value) {
    return (value + 19) / 20 * 10;
}

static void fare(const char *heading, Station *origin, Station *destination, int departure, bool child) {
    Search result = earliest(origin, departure);
    Label label = result.labels[destination->index];
    if (!label.present) {
        printf("%s unreachable\n", heading);
        free_search(result);
        return;
    }
    Strings tickets = {0};
    size_t count;
    Leg *legs = journey_legs(label.journey, &count);
    int total_payment = 0, last_ride = -1;
    for (size_t i = 0; i < count; i++) {
        Leg leg = legs[i];
        if (leg.kind != 'R') continue;
        int a = position(leg.line, 0, leg.from), b = position(leg.line, 0, leg.to), first = a < b ? a : b, last = a > b ? a : b;
        bool seen[10] = {0};
        int zones = 0;
        for (int j = first; j <= last; j++) {
            int zone = leg.line->stops[j]->zone;
            if (!seen[zone]) zones++;
            seen[zone] = true;
        }
        int price = prices[(size_t)zones <= price_count ? (size_t)zones - 1 : price_count - 1];
        if (child) price = half(price);
        int reduction = 0, cap = child ? half(discount) : discount;
        if (last_ride >= 0 && leg.departure - last_ride <= window) reduction = cap < price ? cap : price;
        int pay = price - reduction;
        total_payment += pay;
        APPEND(tickets.items, tickets.count, format("TICKET %s %s %s zones %d price %d discount %d pay %d", leg.line->id, leg.from->id, leg.to->id, zones, price, reduction, pay));
        last_ride = leg.arrival;
    }
    printf("%s rides %d total %d\n", heading, rides(label.journey), total_payment);
    for (size_t i = 0; i < tickets.count; i++) puts(tickets.items[i]);
    free(legs);
    free_search(result);
}

static void set_walk(Station *a, Station *b, int minutes) {
    for (size_t i = 0; i < a->walk_count; i++) if (a->walks[i].neighbor == b) {
        a->walks[i].minutes = minutes;
        return;
    }
    APPEND(a->walks, a->walk_count, ((Walk){b, minutes}));
    qsort(a->walks, a->walk_count, sizeof(*a->walks), walk_compare);
}

static int departure_compare(const void *a, const void *b) {
    const Departure *x = a, *y = b;
    if (x->time != y->time) return x->time - y->time;
    int order = strcmp(x->line->id, y->line->id);
    return order ? order : x->direction - y->direction;
}

static Strings split(const char *text) {
    Strings result = {0};
    size_t start = 0;
    for (size_t i = 0;; i++) if (!text[i] || text[i] == ' ') {
        APPEND(result.items, result.count, slice(text + start, i - start));
        start = i + 1;
        if (!text[i]) break;
    }
    return result;
}

static void command(char **w, size_t argc) {
    char *cmd = w[0];
    if (!strcmp(cmd, "STATION")) {
        if (find_station(w[1])) error("station %s already exists", w[1]);
        Station *added = allocate(sizeof(*added));
        added->id = w[1];
        added->name = w[3];
        added->zone = atoi(w[2]);
        added->index = station_count;
        APPEND(stations, station_count, added);
        qsort(stations, station_count, sizeof(*stations), station_compare);
        printf("STATION %s zone %s %s\n", w[1], w[2], w[3]);
        return;
    }
    if (!strcmp(cmd, "LINE")) {
        if (find_line(w[1])) error("line %s already exists", w[1]);
        Station **stops = NULL;
        size_t count = 0;
        for (size_t i = 5; i < argc; i += 2) APPEND(stops, count, station(w[i]));
        for (size_t i = 0; i < count; i++) for (size_t j = 0; j < i; j++) if (stops[i] == stops[j]) error("station %s appears twice on line %s", stops[i]->id, w[1]);
        int first = time_value(w[2]), last = time_value(w[3]);
        if (first > last) error("line %s first departure is after last departure", w[1]);
        int *cumulative = allocate(count * sizeof(*cumulative));
        for (size_t i = 1; i < count; i++) cumulative[i] = cumulative[i - 1] + atoi(w[4 + 2 * i]);
        if (last + cumulative[count - 1] > 1440) error("line %s runs past 24:00", w[1]);
        Line *added = allocate(sizeof(*added));
        *added = (Line){.id = w[1], .first = first, .last = last, .headway = atoi(w[4]), .stops = stops, .cumulative = cumulative, .count = count};
        APPEND(lines, line_count, added);
        qsort(lines, line_count, sizeof(*lines), line_compare);
        printf("LINE %s stops %zu time %d trips %d\n", added->id, count, total(added), trips(added));
        return;
    }
    if (!strcmp(cmd, "TRANSFER")) {
        Station *s = station(w[1]);
        s->transfer = atoi(w[2]);
        printf("TRANSFER %s %s\n", w[1], w[2]);
        return;
    }
    if (!strcmp(cmd, "WALK")) {
        Station *a = station(w[1]), *b = station(w[2]);
        if (a == b) error("walk from %s to itself", a->id);
        int before = -1;
        for (size_t i = 0; i < a->walk_count; i++) if (a->walks[i].neighbor == b) before = a->walks[i].minutes;
        int minutes = atoi(w[3]);
        set_walk(a, b, minutes);
        set_walk(b, a, minutes);
        printf("WALK %s %s %d", a->id, b->id, minutes);
        if (before >= 0) printf(" was %d", before);
        putchar('\n');
        return;
    }
    if (!strcmp(cmd, "TARIFF")) {
        size_t count = argc - 3;
        int *added = allocate(count * sizeof(*added));
        for (size_t i = 0; i < count; i++) {
            added[i] = atoi(w[i + 3]);
            if (i && added[i] < added[i - 1]) error("tariff prices must not decrease");
        }
        prices = added;
        price_count = count;
        discount = atoi(w[1]);
        window = atoi(w[2]);
        printf("TARIFF zones %zu discount %d window %d\n", count, discount, window);
        return;
    }
    if (!strcmp(cmd, "CLOSE") || !strcmp(cmd, "OPEN")) {
        Station *a = station(w[1]);
        bool close = !strcmp(cmd, "CLOSE");
        if (argc == 2) {
            if (close == a->closed) error("station %s is %sclosed", a->id, close ? "already " : "not ");
            a->closed = close;
            printf("%s %s\n", cmd, a->id);
        } else {
            Station *b = station(w[2]);
            Segment key = segment(a, b);
            Strings containing = {0};
            if (close) {
                for (size_t l = 0; l < line_count; l++) for (size_t i = 1; i < lines[l]->count; i++) if (same_segment(segment(lines[l]->stops[i - 1], lines[l]->stops[i]), key)) {
                    APPEND(containing.items, containing.count, lines[l]->id);
                    break;
                }
                if (!containing.count) error("no segment %s-%s", a->id, b->id);
            }
            if (close == blocked(a, b)) error("segment %s-%s is %sclosed", a->id, b->id, close ? "already " : "not ");
            if (close) APPEND(closed_segments, closed_count, key);
            else {
                size_t next = 0;
                for (size_t i = 0; i < closed_count; i++) if (!same_segment(closed_segments[i], key)) closed_segments[next++] = closed_segments[i];
                closed_count = next;
            }
            printf("%s %s-%s", cmd, a->id, b->id);
            if (close) {
                printf(" lines");
                for (size_t i = 0; i < containing.count; i++) printf(" %s", containing.items[i]);
            }
            putchar('\n');
        }
        return;
    }
    if (!strcmp(cmd, "DELAY")) {
        Line *current = line(w[1]);
        int delay = atoi(w[2]);
        if (current->last + delay + total(current) > 1440) error("line %s runs past 24:00", current->id);
        current->delay = delay;
        printf("DELAY %s %d\n", current->id, delay);
        return;
    }
    if (!strcmp(cmd, "SUSPEND") || !strcmp(cmd, "RESUME")) {
        Line *current = line(w[1]);
        bool suspend = !strcmp(cmd, "SUSPEND");
        if (suspend == current->suspended) error("line %s is %ssuspended", current->id, suspend ? "already " : "not ");
        current->suspended = suspend;
        printf("%s %s\n", cmd, current->id);
        return;
    }
    if (!strcmp(cmd, "VIA")) {
        Station *origin = station(w[1]), *via = station(w[2]), *destination = station(w[3]);
        if (origin == destination) error("origin and destination are the same");
        if (via == origin || via == destination) error("via station %s must differ from origin and destination", via->id);
        if (origin->closed) error("station %s is closed", origin->id);
        if (via->closed) error("station %s is closed", via->id);
        if (destination->closed) error("station %s is closed", destination->id);
        int departure = time_value(w[4]);
        char *heading = format("VIA %s %s %s", origin->id, via->id, destination->id);
        Search first = earliest(origin, departure);
        Label first_label = first.labels[via->index];
        bool found = false;
        if (first_label.present) {
            int ready = first_label.time + via->transfer;
            Search second = earliest(via, ready);
            Label second_label = second.labels[destination->index];
            if (second_label.present) {
                Node *allocated = NULL, *journey = add_leg(&allocated, first_label.journey, (Leg){'S', NULL, NULL, via, via, first_label.time, ready, 0});
                size_t count;
                Leg *legs = journey_legs(second_label.journey, &count);
                for (size_t i = 0; i < count; i++) journey = add_leg(&allocated, journey, legs[i]);
                print_journey(heading, departure, (Label){true, second_label.time, journey});
                free(legs);
                free_nodes(allocated);
                found = true;
            }
            free_search(second);
        }
        if (!found) printf("%s %s unreachable\n", heading, clock_text(departure));
        free_search(first);
        return;
    }
    if (!strcmp(cmd, "REACH")) {
        Station *origin = station(w[1]);
        if (origin->closed) error("station %s is closed", origin->id);
        int departure = time_value(w[2]), limit = departure + atoi(w[3]);
        Search result = earliest(origin, departure);
        Station **selected = NULL;
        size_t count = 0;
        for (size_t i = 0; i < station_count; i++) {
            Station *s = stations[i];
            if (result.labels[s->index].present && result.labels[s->index].time <= limit) {
                APPEND(selected, count, s);
                size_t j = count - 1;
                while (j && result.labels[selected[j - 1]->index].time > result.labels[s->index].time) {
                    selected[j] = selected[j - 1];
                    j--;
                }
                selected[j] = s;
            }
        }
        printf("REACH %s %s %s count %zu\n", origin->id, w[2], w[3], count);
        for (size_t i = 0; i < count; i++) {
            Station *s = selected[i];
            Label label = result.labels[s->index];
            printf("%s %s %s %d rides %d\n", s->id, s->name, clock_text(label.time), label.time - departure, rides(label.journey));
        }
        free(selected);
        free_search(result);
        return;
    }
    if (!strcmp(cmd, "TIMETABLE")) {
        Station *s = station(w[1]);
        Line *current = line(w[2]);
        int pos = position(current, 0, s);
        if (pos < 0) error("station %s is not on line %s", s->id, current->id);
        int d = direction(current, w[3]);
        if (!strcmp(s->id, w[3])) error("no departures from %s toward %s", s->id, w[3]);
        if (current->suspended) error("line %s is suspended", current->id);
        if (s->closed) error("station %s is closed", s->id);
        pos = position(current, d, s);
        int start = next_train(current, d, pos, time_value(w[4])), count = start < 0 ? 0 : trips(current) - start;
        if (count > atoi(w[5])) count = atoi(w[5]);
        printf("TIMETABLE %s %s toward %s %s next %d", s->id, current->id, w[3], w[4], count);
        for (int q = start; q < start + count; q++) printf(" %s", clock_text(train_time(current, d, pos, q)));
        putchar('\n');
        return;
    }
    if (!strcmp(cmd, "DEPARTURES") || !strcmp(cmd, "ARRIVALS")) {
        Station *s = station(w[1]);
        if (s->closed) error("station %s is closed", s->id);
        bool arrivals = !strcmp(cmd, "ARRIVALS");
        Departure *selected = NULL;
        size_t count = 0;
        for (size_t l = 0; l < line_count; l++) {
            Line *current = lines[l];
            if (current->suspended || position(current, 0, s) < 0) continue;
            for (int d = 0; d < 2; d++) {
                int pos = position(current, d, s);
                if (arrivals ? pos == 0 : pos == (int)current->count - 1) continue;
                int start = next_train(current, d, pos, time_value(w[2]));
                if (start >= 0) for (int q = start; q < trips(current); q++) APPEND(selected, count, ((Departure){train_time(current, d, pos, q), d, current}));
            }
        }
        if (count) qsort(selected, count, sizeof(*selected), departure_compare);
        if (count > (size_t)atoi(w[3])) count = (size_t)atoi(w[3]);
        printf("%s %s %s count %zu\n", cmd, s->id, w[2], count);
        for (size_t i = 0; i < count; i++) {
            Departure entry = selected[i];
            printf("%s %s %s %s\n", clock_text(entry.time), entry.line->id, arrivals ? "from" : "toward", stop(entry.line, entry.direction, arrivals ? 0 : (int)entry.line->count - 1)->id);
        }
        free(selected);
        return;
    }
    if (!strcmp(cmd, "TRIP")) {
        Line *current = line(w[1]);
        int d = direction(current, w[2]);
        if (current->suspended) error("line %s is suspended", current->id);
        int train = next_train(current, d, 0, time_value(w[3]));
        char *heading = format("TRIP %s toward %s %s", current->id, w[2], w[3]);
        if (train < 0) printf("%s none\n", heading);
        else {
            printf("%s trip %d departs %s\n", heading, train + 1, clock_text(train_time(current, d, 0, train)));
            for (int j = 0; j < (int)current->count; j++) {
                Station *s = stop(current, d, j);
                printf("%s %s%s%s\n", clock_text(train_time(current, d, j, train)), s->id, s->closed ? " closed" : "", j && blocked(stop(current, d, j - 1), s) ? " blocked" : "");
            }
        }
        return;
    }
    if (!strcmp(cmd, "SHOWLINE")) {
        Line *current = line(w[1]);
        printf("SHOWLINE %s %s first %s last %s headway %d delay %d trips %d\n", current->id, current->suspended ? "suspended" : "running", clock_text(current->first), clock_text(current->last), current->headway, current->delay, trips(current));
        for (size_t j = 0; j < current->count; j++) {
            Station *s = current->stops[j];
            printf("%d %s zone %d%s%s\n", current->cumulative[j], s->id, s->zone, s->closed ? " closed" : "", j && blocked(current->stops[j - 1], s) ? " blocked" : "");
        }
        return;
    }
    if (!strcmp(cmd, "INFO")) {
        Station *s = station(w[1]);
        printf("INFO %s %s zone %d transfer %d %s\nLINES", s->id, s->name, s->zone, s->transfer, s->closed ? "closed" : "open");
        bool any = false;
        for (size_t i = 0; i < line_count; i++) if (position(lines[i], 0, s) >= 0) {
            printf(" %s", lines[i]->id);
            any = true;
        }
        if (!any) printf(" none");
        printf("\nWALKS");
        if (!s->walk_count) printf(" none");
        for (size_t i = 0; i < s->walk_count; i++) printf(" %s %d", s->walks[i].neighbor->id, s->walks[i].minutes);
        putchar('\n');
        return;
    }
    if (!strcmp(cmd, "STATUS")) {
        size_t walks = 0;
        for (size_t i = 0; i < station_count; i++) walks += stations[i]->walk_count;
        printf("STATUS stations %zu lines %zu walks %zu\n", station_count, line_count, walks / 2);
        for (size_t i = 0; i < station_count; i++) if (stations[i]->closed) printf("CLOSED %s\n", stations[i]->id);
        if (closed_count) qsort(closed_segments, closed_count, sizeof(*closed_segments), segment_compare);
        for (size_t i = 0; i < closed_count; i++) printf("CLOSED %s-%s\n", closed_segments[i].a->id, closed_segments[i].b->id);
        for (size_t i = 0; i < line_count; i++) if (lines[i]->suspended) printf("SUSPENDED %s\n", lines[i]->id);
        for (size_t i = 0; i < line_count; i++) if (lines[i]->delay) printf("DELAYED %s %d\n", lines[i]->id, lines[i]->delay);
        return;
    }
    Station *origin = station(w[1]), *destination = station(w[2]);
    search_check(origin, destination);
    char *heading = format("%s %s %s", cmd, origin->id, destination->id);
    if (!strcmp(cmd, "FARE")) {
        if (strcmp(w[4], "ADULT") && strcmp(w[4], "CHILD")) error("unknown fare class %s", w[4]);
        if (!prices) error("no tariff");
        fare(format("%s %s %s", heading, w[3], w[4]), origin, destination, time_value(w[3]), !strcmp(w[4], "CHILD"));
        return;
    }
    if (!strcmp(cmd, "LASTTRAIN") || !strcmp(cmd, "ARRIVEBY")) {
        int deadline = !strcmp(cmd, "LASTTRAIN") ? 1440 : time_value(w[3]);
        if (!strcmp(cmd, "ARRIVEBY")) heading = format("%s by %s", heading, w[3]);
        for (int t = deadline - 1; t >= 0; t--) {
            Search result = earliest(origin, t);
            Label label = result.labels[destination->index];
            if (label.present && label.time <= deadline) {
                print_journey(heading, t, label);
                free_search(result);
                return;
            }
            free_search(result);
        }
        printf("%s none\n", heading);
        return;
    }
    int departure = time_value(w[3]);
    if (!strcmp(cmd, "PROFILE")) {
        int last = time_value(w[4]);
        if (departure > last) error("empty interval %s %s", w[3], w[4]);
        size_t length = (size_t)(last - departure + 1);
        int *arrivals = allocate(length * sizeof(*arrivals));
        for (int t = departure; t <= last; t++) {
            Search result = earliest(origin, t);
            Label label = result.labels[destination->index];
            arrivals[t - departure] = label.present ? label.time : -1;
            free_search(result);
        }
        size_t count = 0;
        for (size_t i = 0; i < length; i++) if (arrivals[i] >= 0 && (i + 1 == length || arrivals[i + 1] < 0 || arrivals[i] < arrivals[i + 1])) count++;
        printf("%s %s %s count %zu\n", heading, w[3], w[4], count);
        for (size_t i = 0; i < length; i++) if (arrivals[i] >= 0 && (i + 1 == length || arrivals[i + 1] < 0 || arrivals[i] < arrivals[i + 1])) printf("%s -> %s total %d\n", clock_text(departure + (int)i), clock_text(arrivals[i]), arrivals[i] - departure - (int)i);
        free(arrivals);
        return;
    }
    if (!strcmp(cmd, "FEWEST") || !strcmp(cmd, "PARETO")) {
        Rounds result = rounds(origin, departure);
        size_t *options = NULL, count = 0;
        for (size_t k = 0; k < result.count; k++) {
            Label label = result.labels[k][destination->index], previous = k ? result.labels[k - 1][destination->index] : (Label){0};
            if (label.present && (!previous.present || previous.time > label.time)) APPEND(options, count, k);
        }
        if (!strcmp(cmd, "FEWEST")) {
            if (!count) printf("%s %s unreachable\n", heading, w[3]);
            else {
                size_t k = options[0];
                print_journey(format("%s trips %zu", heading, k), departure, result.labels[k][destination->index]);
            }
        } else {
            printf("%s %s options %zu\n", heading, w[3], count);
            for (size_t i = 0; i < count; i++) {
                size_t k = options[i];
                print_journey(format("OPTION trips %zu", k), departure, result.labels[k][destination->index]);
            }
        }
        free(options);
        free_rounds(result);
        return;
    }
    Search result = earliest(origin, departure);
    Label label = result.labels[destination->index];
    if (label.present) print_journey(heading, departure, label);
    else printf("%s %s unreachable\n", heading, w[3]);
    free_search(result);
}

static char *read_line(void) {
    Buffer b = {0};
    int c;
    while ((c = getchar()) != EOF && c != '\n') append(&b, (char[]){(char)c, 0});
    if (c == EOF && !b.length) return NULL;
    return finish(&b);
}
int main(void) {
    int count = atoi(read_line());
    for (int i = 0; i < count; i++) {
        Strings words = split(read_line());
        if (setjmp(failure)) printf("ERROR %s\n", error_reason);
        else command(words.items, words.count);
    }
    return 0;
}
