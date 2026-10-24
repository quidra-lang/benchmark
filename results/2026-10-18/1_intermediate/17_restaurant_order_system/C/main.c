#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int64_t Money;
typedef struct { char text[32]; } Text;
typedef enum { GRILL, FRY, COLD, BAR } StationName;
typedef enum { DRINK, STARTER, MAIN, DESSERT } Course;
typedef enum { ORDERED, QUEUED, COOKING, READY, SERVED, VOID } State;
typedef struct Check Check;
typedef struct Order Order;
typedef struct { Order **items; int count, capacity; } OrderList;
typedef struct { int number, seats; Check *check; } Table;
typedef struct { char name[11]; int load, parties; Money sales, tips; } Server;
typedef struct { char name[11]; int size, since; } Waiting;
typedef struct {
    char name[13];
    StationName station;
    Course course;
    int prep, stock, served;
    Money price;
} MenuItem;
struct Check {
    char party[11];
    int size, seated, discount;
    Table *table;
    Server *server;
    OrderList orders;
    Money paid;
    bool closed;
};
struct Order {
    int id, seat, quantity, prep, fired, ready;
    Check *check;
    MenuItem *item;
    StationName station;
    Course course;
    State state;
    Money price;
    char comp[13];
    bool started;
};
typedef struct {
    bool up;
    OrderList queue, cooking;
    int tickets, ticket_total, ticket_max, remakes;
} Station;
typedef struct { Money subtotal, discount, service, tax, total; } Totals;
typedef struct { bool present[21]; Money amounts[21]; } Seats;
typedef struct {
    int covers, parties, turns, stay_total, comps, voids;
    Money sales[4], cash, card, tips, comp_amount;
    Totals totals;
} Statistics;

static const char *station_names[] = { "GRILL", "FRY", "COLD", "BAR" };
static const char *course_names[] = { "DRINK", "STARTER", "MAIN", "DESSERT" };
static const char *state_names[] = { "ORDERED", "QUEUED", "COOKING", "READY", "SERVED", "VOID" };
static Table tables[100];
static Server servers[1000];
static Waiting waiting[1000];
static MenuItem menu[1000];
static Check checks[1000];
static Order orders[1000];
static Station stations[4];
static Statistics stats;
static int now, server_count, waiting_count, menu_count, check_count, order_count;
static int happy_rate, happy_end;

static bool equal(const char *a, const char *b) { return strcmp(a, b) == 0; }
static Money rounded(Money value, int rate) { return (value * rate + 50) / 100; }
static Money charge(const Order *o) { return o->comp[0] ? 0 : o->price * o->quantity; }

static Money cents(const char *text) {
    return strtoll(text, NULL, 10) * 100 + atoi(strchr(text, '.') + 1);
}

static Text money(Money value) {
    Text result;
    snprintf(result.text, sizeof result.text, "%" PRId64 ".%02" PRId64, value / 100, value % 100);
    return result;
}

static Text clock_text(int time) {
    Text result;
    int minutes = 660 + time;
    snprintf(result.text, sizeof result.text, "%02d:%02d", minutes / 60, minutes % 60);
    return result;
}

static bool fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("ERROR ", stdout);
    vprintf(format, args);
    putchar('\n');
    va_end(args);
    return false;
}

static void insert_order(OrderList *list, int index, Order *order) {
    if (list->count == list->capacity) {
        int capacity = list->capacity ? list->capacity * 2 : 8;
        Order **items = realloc(list->items, (size_t)capacity * sizeof *items);
        if (!items) exit(EXIT_FAILURE);
        list->items = items;
        list->capacity = capacity;
    }
    memmove(list->items + index + 1, list->items + index, (size_t)(list->count - index) * sizeof *list->items);
    list->items[index] = order;
    ++list->count;
}

static void append_order(OrderList *list, Order *order) { insert_order(list, list->count, order); }

static Order *remove_at(OrderList *list, int index) {
    Order *order = list->items[index];
    --list->count;
    memmove(list->items + index, list->items + index + 1, (size_t)(list->count - index) * sizeof *list->items);
    return order;
}

static void remove_order(OrderList *list, Order *order) {
    for (int i = 0; i < list->count; ++i) {
        if (list->items[i] == order) { remove_at(list, i); return; }
    }
}

static Waiting remove_waiting(int index) {
    Waiting party = waiting[index];
    --waiting_count;
    memmove(waiting + index, waiting + index + 1, (size_t)(waiting_count - index) * sizeof *waiting);
    return party;
}

static int station_index(const char *name) {
    for (int i = 0; i < 4; ++i) if (equal(name, station_names[i])) return i;
    fail("unknown station %s", name);
    return -1;
}

static int course_index(const char *name) {
    for (int i = 0; i < 4; ++i) if (equal(name, course_names[i])) return i;
    fail("unknown course %s", name);
    return -1;
}

static Table *table(const char *text) {
    Table *t = &tables[atoi(text)];
    if (!t->number) { fail("unknown table %s", text); return NULL; }
    return t;
}

static Check *check(const char *text) {
    Table *t = table(text);
    if (!t) return NULL;
    if (!t->check) { fail("table %s is free", text); return NULL; }
    return t->check;
}

static Order *order(const char *text) {
    int id = atoi(text);
    if (id < 1 || id > order_count) { fail("unknown line %s", text); return NULL; }
    return &orders[id - 1];
}

static MenuItem *find_item(const char *name) {
    for (int i = 0; i < menu_count; ++i) if (equal(name, menu[i].name)) return &menu[i];
    return NULL;
}

static MenuItem *item(const char *name) {
    MenuItem *m = find_item(name);
    if (!m) fail("unknown item %s", name);
    return m;
}

static bool unlocked(Check *c) {
    return !c->paid || fail("check for table %d is locked", c->table->number);
}

static bool modifiable(Order *o) {
    if (o->state == VOID) return fail("#%d is void", o->id);
    if (o->check->closed) return fail("#%d is on a closed check", o->id);
    return unlocked(o->check);
}

static bool valid_seat(Check *c, int seat) {
    return seat <= c->size || fail("seat %d out of range for table %d", seat, c->table->number);
}

static bool all_served(Check *c) {
    int count = 0;
    for (int i = 0; i < c->orders.count; ++i) {
        State state = c->orders.items[i]->state;
        count += state != VOID && state != SERVED;
    }
    return !count || fail("table %d has %d unserved items", c->table->number, count);
}

static int active_count(Check *c) {
    int count = 0;
    for (int i = 0; i < c->orders.count; ++i) count += c->orders.items[i]->state != VOID;
    return count;
}

static Totals totals(Check *c) {
    Totals t = { 0 };
    for (int i = 0; i < c->orders.count; ++i) {
        Order *o = c->orders.items[i];
        if (o->state != VOID) t.subtotal += charge(o);
    }
    t.discount = rounded(t.subtotal, c->discount);
    Money net = t.subtotal - t.discount;
    t.service = c->size >= 6 ? rounded(net, 18) : 0;
    t.tax = rounded(net, 8);
    t.total = net + t.service + t.tax;
    return t;
}

static Seats seats(Check *c) {
    Seats result = { 0 };
    for (int i = 0; i < c->orders.count; ++i) {
        Order *o = c->orders.items[i];
        if (o->state == VOID) continue;
        result.present[o->seat] = true;
        result.amounts[o->seat] += charge(o);
    }
    return result;
}

static void allocate(const Money *values, const bool *present, int rate, Money *result) {
    Money total = 0, assigned = 0;
    bool used[21] = { false };
    for (int seat = 1; seat <= 20; ++seat) {
        result[seat] = present[seat] ? values[seat] * rate / 100 : 0;
        if (present[seat]) total += values[seat];
        assigned += result[seat];
    }
    Money remaining = rounded(total, rate) - assigned;
    while (remaining-- > 0) {
        int best = 0;
        for (int seat = 1; seat <= 20; ++seat) {
            if (!present[seat] || used[seat]) continue;
            if (!best || values[seat] * rate % 100 > values[best] * rate % 100) best = seat;
        }
        ++result[best];
        used[best] = true;
    }
}

static Table *choose_table(int size) {
    Table *best = NULL;
    for (int i = 1; i <= 99; ++i) {
        Table *t = &tables[i];
        if (!t->number || t->check || t->seats < size) continue;
        if (!best || t->seats < best->seats) best = t;
    }
    return best;
}

static Check *seat_party(Waiting party, Table *t) {
    Server *server = &servers[0];
    for (int i = 1; i < server_count; ++i) if (servers[i].load < server->load) server = &servers[i];
    Check *c = &checks[check_count++];
    *c = (Check){ .size = party.size, .seated = now, .table = t, .server = server };
    strcpy(c->party, party.name);
    t->check = c;
    ++server->load;
    ++server->parties;
    stats.covers += party.size;
    ++stats.parties;
    return c;
}

static void seat_waiting(void) {
    int i = 0;
    while (i < waiting_count) {
        Table *t = choose_table(waiting[i].size);
        if (!t) { ++i; continue; }
        Waiting party = remove_waiting(i);
        Check *c = seat_party(party, t);
        printf("SEATED %s %d table %d server %s waited %d\n", party.name, party.size, t->number, c->server->name, now - party.since);
    }
}

static void close_check(Check *c) {
    Totals t = totals(c);
    stats.totals.subtotal += t.subtotal;
    stats.totals.discount += t.discount;
    stats.totals.service += t.service;
    stats.totals.tax += t.tax;
    stats.totals.total += t.total;
    for (int i = 0; i < c->orders.count; ++i) {
        Order *o = c->orders.items[i];
        if (o->state != VOID) stats.sales[o->course] += charge(o);
    }
    c->server->sales += t.total;
    --c->server->load;
    ++stats.turns;
    stats.stay_total += now - c->seated;
    c->closed = true;
    c->table->check = NULL;
    printf("FREE table %d %s stayed %d\n", c->table->number, c->party, now - c->seated);
    seat_waiting();
}

static void start_cooking(int index, int time) {
    Station *s = &stations[index];
    int capacity = index == BAR ? 2 : 1;
    while (s->up && s->queue.count && s->cooking.count < capacity) {
        Order *o = remove_at(&s->queue, 0);
        o->state = COOKING;
        o->started = true;
        o->ready = time + o->prep;
        append_order(&s->cooking, o);
    }
}

static int order_by_id(const void *left, const void *right) {
    const Order *a = *(Order *const *)left, *b = *(Order *const *)right;
    return a->id - b->id;
}

static int order_by_ready(const void *left, const void *right) {
    const Order *a = *(Order *const *)left, *b = *(Order *const *)right;
    return a->ready != b->ready ? a->ready - b->ready : a->id - b->id;
}

static void tick(int target) {
    printf("TICK %s\n", clock_text(target).text);
    for (;;) {
        int next = INT_MAX;
        for (int i = 0; i < 4; ++i)
            for (int j = 0; j < stations[i].cooking.count; ++j)
                if (stations[i].cooking.items[j]->ready < next) next = stations[i].cooking.items[j]->ready;
        if (next > target) break;
        for (int i = 0; i < 4; ++i) {
            Station *s = &stations[i];
            if (s->cooking.count > 1) qsort(s->cooking.items, (size_t)s->cooking.count, sizeof *s->cooking.items, order_by_id);
            int j = 0;
            while (j < s->cooking.count) {
                Order *o = s->cooking.items[j];
                if (o->ready != next) { ++j; continue; }
                remove_at(&s->cooking, j);
                o->state = READY;
                int ticket = next - o->fired;
                ++s->tickets;
                s->ticket_total += ticket;
                if (ticket > s->ticket_max) s->ticket_max = ticket;
                printf("READY %s %s #%d %s x%d table %d seat %d\n", clock_text(next).text, station_names[i], o->id, o->item->name, o->quantity, o->check->table->number, o->seat);
            }
        }
        for (int i = 0; i < 4; ++i) start_cooking(i, next);
    }
    now = target;
}

static void bill(Check *c) {
    Seats by_seat = seats(c);
    printf("BILL table %d %s guests %d\n", c->table->number, c->party, c->size);
    for (int seat = 1; seat <= 20; ++seat) {
        if (!by_seat.present[seat]) continue;
        printf("SEAT %d %s\n", seat, money(by_seat.amounts[seat]).text);
        for (int i = 0; i < c->orders.count; ++i) {
            Order *o = c->orders.items[i];
            if (o->state == VOID || o->seat != seat) continue;
            printf("#%d %s x%d %s", o->id, o->item->name, o->quantity, money(charge(o)).text);
            if (o->comp[0]) printf(" COMP %s", o->comp);
            putchar('\n');
        }
    }
    Totals t = totals(c);
    printf("SUBTOTAL %s\n", money(t.subtotal).text);
    if (c->discount) printf("DISCOUNT %d%% %s\n", c->discount, money(t.discount).text);
    if (c->size >= 6) printf("SERVICE %s\n", money(t.service).text);
    printf("TAX %s\nTOTAL %s\n", money(t.tax).text, money(t.total).text);
    if (c->paid) printf("PAID %s\nDUE %s\n", money(c->paid).text, money(t.total - c->paid).text);
}

static void split(Check *c, char **args) {
    Totals t = totals(c);
    Money due = t.total - c->paid;
    if (!due) { fail("nothing to split for table %d", c->table->number); return; }
    if (equal(args[0], "EVEN")) {
        int k = atoi(args[1]);
        if (k > c->size) { fail("cannot split table %d %d ways", c->table->number, k); return; }
        printf("SPLIT table %d EVEN %d due %s\n", c->table->number, k, money(due).text);
        for (int i = 1; i <= k; ++i) printf("PAYER %d %s\n", i, money(due / k + (i <= due % k)).text);
    } else {
        if (c->paid) { fail("table %d has payments", c->table->number); return; }
        Seats by_seat = seats(c);
        Money discounts[21] = { 0 }, net[21] = { 0 }, service[21] = { 0 }, tax[21] = { 0 };
        allocate(by_seat.amounts, by_seat.present, c->discount, discounts);
        for (int i = 1; i <= 20; ++i) net[i] = by_seat.amounts[i] - discounts[i];
        allocate(net, by_seat.present, c->size >= 6 ? 18 : 0, service);
        allocate(net, by_seat.present, 8, tax);
        printf("SPLIT table %d BYSEAT total %s\n", c->table->number, money(t.total).text);
        for (int i = 1; i <= 20; ++i) {
            if (!by_seat.present[i]) continue;
            printf("SEAT %d subtotal %s discount %s service %s tax %s total %s\n", i, money(by_seat.amounts[i]).text,
                   money(discounts[i]).text, money(service[i]).text, money(tax[i]).text, money(net[i] + service[i] + tax[i]).text);
        }
    }
}

static int menu_order(const void *left, const void *right) {
    const MenuItem *a = *(MenuItem *const *)left, *b = *(MenuItem *const *)right;
    return a->course != b->course ? (int)a->course - (int)b->course : strcmp(a->name, b->name);
}

static int popularity_order(const void *left, const void *right) {
    const MenuItem *a = *(MenuItem *const *)left, *b = *(MenuItem *const *)right;
    return a->served != b->served ? b->served - a->served : strcmp(a->name, b->name);
}

static void report(void) {
    printf("REPORT %s\nCOVERS %d parties %d\nTURNS %d avg_stay ", clock_text(now).text, stats.covers, stats.parties, stats.turns);
    if (stats.turns) printf("%d\n", stats.stay_total / stats.turns);
    else puts("-");
    printf("SALES DRINK %s STARTER %s MAIN %s DESSERT %s\n", money(stats.sales[0]).text, money(stats.sales[1]).text, money(stats.sales[2]).text, money(stats.sales[3]).text);
    Totals t = stats.totals;
    printf("TOTALS subtotal %s discount %s service %s tax %s total %s\n", money(t.subtotal).text, money(t.discount).text, money(t.service).text, money(t.tax).text, money(t.total).text);
    printf("PAYMENTS cash %s card %s tips %s\nCOMPS %d %s VOIDS %d\n", money(stats.cash).text, money(stats.card).text, money(stats.tips).text, stats.comps, money(stats.comp_amount).text, stats.voids);
    MenuItem *items[1000];
    for (int i = 0; i < menu_count; ++i) items[i] = &menu[i];
    qsort(items, (size_t)menu_count, sizeof *items, popularity_order);
    for (int i = 0; i < menu_count && i < 3 && items[i]->served; ++i)
        printf("TOP %d %s %d\n", i + 1, items[i]->name, items[i]->served);
    for (int i = 0; i < 4; ++i) {
        Station *s = &stations[i];
        printf("%s tickets %d avg ", station_names[i], s->tickets);
        if (s->tickets) printf("%d max %d", s->ticket_total / s->tickets, s->ticket_max);
        else fputs("- max -", stdout);
        printf(" remakes %d\n", s->remakes);
    }
    for (int i = 0; i < server_count; ++i) {
        Server *s = &servers[i];
        printf("SERVER %s tables %d parties %d sales %s tips %s\n", s->name, s->load, s->parties, money(s->sales).text, money(s->tips).text);
    }
}

static void execute(char **a) {
    const char *op = a[0];
    if (equal(op, "TABLE")) {
        int number = atoi(a[1]);
        Table *t = &tables[number];
        if (t->number) { fail("table %d already exists", number); return; }
        t->number = number;
        t->seats = atoi(a[2]);
        printf("TABLE %d seats %d\n", number, t->seats);
        seat_waiting();
    } else if (equal(op, "STAFF")) {
        for (int i = 0; i < server_count; ++i)
            if (equal(servers[i].name, a[1])) { fail("%s is already on duty", a[1]); return; }
        strcpy(servers[server_count++].name, a[1]);
        printf("STAFF %s\n", a[1]);
    } else if (equal(op, "SEAT")) {
        for (int i = 1; i <= 99; ++i) {
            if (tables[i].check && equal(tables[i].check->party, a[1])) {
                fail("%s is already seated at table %d", a[1], i); return;
            }
        }
        for (int i = 0; i < waiting_count; ++i)
            if (equal(waiting[i].name, a[1])) { fail("%s is already waiting", a[1]); return; }
        int size = atoi(a[2]);
        bool fits = false;
        for (int i = 1; i <= 99; ++i) if (tables[i].number && tables[i].seats >= size) fits = true;
        if (!fits) { fail("no table for party of %d", size); return; }
        if (!server_count) { fail("no server on duty"); return; }
        Waiting party = { .size = size, .since = now };
        strcpy(party.name, a[1]);
        Table *t = choose_table(size);
        if (t) {
            Check *c = seat_party(party, t);
            printf("SEAT %s %d table %d server %s\n", party.name, size, t->number, c->server->name);
        } else {
            waiting[waiting_count++] = party;
            printf("WAIT %s %d position %d\n", party.name, size, waiting_count);
        }
    } else if (equal(op, "CANCEL")) {
        int i = 0;
        while (i < waiting_count && !equal(waiting[i].name, a[1])) ++i;
        if (i == waiting_count) { fail("%s is not waiting", a[1]); return; }
        Waiting party = remove_waiting(i);
        printf("CANCEL %s %d waited %d\n", party.name, party.size, now - party.since);
    } else if (equal(op, "MOVE")) {
        Table *from = table(a[1]);
        if (!from) return;
        Table *to = table(a[2]);
        if (!to) return;
        Check *c = from->check;
        if (!c) { fail("table %s is free", a[1]); return; }
        if (to->check) { fail("table %s is occupied", a[2]); return; }
        if (to->seats < c->size) { fail("table %s is too small for %s", a[2], c->party); return; }
        from->check = NULL;
        to->check = c;
        c->table = to;
        printf("MOVE %s table %d -> %d\n", c->party, from->number, to->number);
        seat_waiting();
    } else if (equal(op, "MENU")) {
        int station = station_index(a[2]);
        if (station < 0) return;
        int course = course_index(a[5]);
        if (course < 0) return;
        MenuItem *m = find_item(a[1]);
        bool existing = m != NULL;
        if (!m) {
            m = &menu[menu_count++];
            strcpy(m->name, a[1]);
            m->stock = -1;
        }
        m->station = (StationName)station;
        m->course = (Course)course;
        m->prep = atoi(a[3]);
        m->price = cents(a[4]);
        printf("MENU %s %s %s %d %s %s\n", existing ? "UPDATE" : "ADD", m->name, a[2], m->prep, money(m->price).text, a[5]);
    } else if (equal(op, "STOCK")) {
        MenuItem *m = item(a[1]);
        if (!m) return;
        m->stock = atoi(a[2]);
        printf("STOCK %s %d\n", m->name, m->stock);
    } else if (equal(op, "HAPPY")) {
        happy_rate = atoi(a[1]);
        happy_end = now + atoi(a[2]);
        printf("HAPPY %d%% until %s\n", happy_rate, clock_text(happy_end).text);
    } else if (equal(op, "ITEMS")) {
        MenuItem *items[1000];
        for (int i = 0; i < menu_count; ++i) items[i] = &menu[i];
        qsort(items, (size_t)menu_count, sizeof *items, menu_order);
        printf("ITEMS %d\n", menu_count);
        for (int i = 0; i < menu_count; ++i) {
            MenuItem *m = items[i];
            printf("%s %s %s %d %s ", course_names[m->course], m->name, station_names[m->station], m->prep, money(m->price).text);
            if (m->stock < 0) puts("-");
            else printf("%d\n", m->stock);
        }
    } else if (equal(op, "TICK")) {
        tick(now + atoi(a[1]));
    } else if (equal(op, "STATION")) {
        int index = station_index(a[1]);
        if (index < 0) return;
        Station *s = &stations[index];
        bool up = equal(a[2], "UP");
        if (s->up == up) { fail("station %s is %s", a[1], up ? "not down" : "already down"); return; }
        s->up = up;
        if (up) start_cooking(index, now);
        printf("STATION %s %s\n", a[1], a[2]);
    } else if (equal(op, "RUSH") || equal(op, "REMAKE") || equal(op, "VOID") || equal(op, "COMP") || equal(op, "TRANSFER")) {
        Order *o = order(a[1]);
        if (!o) return;
        Station *s = &stations[o->station];
        if (equal(op, "RUSH")) {
            if (o->state != QUEUED) { fail("#%d is not queued", o->id); return; }
            remove_order(&s->queue, o);
            insert_order(&s->queue, 0, o);
            printf("RUSH #%d %s\n", o->id, station_names[o->station]);
        } else if (equal(op, "REMAKE")) {
            if (o->check->closed) { fail("#%d is on a closed check", o->id); return; }
            if (o->state != READY && o->state != SERVED) { fail("#%d is not ready or served", o->id); return; }
            o->state = QUEUED;
            o->fired = now;
            insert_order(&s->queue, 0, o);
            ++s->remakes;
            printf("REMAKE #%d %s %s\n", o->id, o->item->name, station_names[o->station]);
            start_cooking(o->station, now);
        } else if (equal(op, "VOID")) {
            if (o->state == VOID) { fail("#%d is already void", o->id); return; }
            if (o->started) { fail("#%d has already started", o->id); return; }
            if (o->state == QUEUED) remove_order(&s->queue, o);
            o->state = VOID;
            if (o->item->stock >= 0) o->item->stock += o->quantity;
            ++stats.voids;
            printf("VOID #%d %s x%d\n", o->id, o->item->name, o->quantity);
        } else if (equal(op, "COMP")) {
            if (!modifiable(o)) return;
            if (o->comp[0]) { fail("#%d is already comped", o->id); return; }
            Money value = charge(o);
            printf("COMP #%d %s %s %s\n", o->id, o->item->name, money(value).text, a[2]);
            ++stats.comps;
            stats.comp_amount += value;
            strcpy(o->comp, a[2]);
        } else {
            if (!modifiable(o)) return;
            int seat = atoi(a[2]);
            if (!valid_seat(o->check, seat)) return;
            if (seat == o->seat) { fail("#%d is already on seat %d", o->id, seat); return; }
            printf("TRANSFER #%d seat %d -> %d\n", o->id, o->seat, seat);
            o->seat = seat;
        }
    } else if (equal(op, "KITCHEN")) {
        printf("KITCHEN %s\n", clock_text(now).text);
        for (int i = 0; i < 4; ++i) {
            Station *s = &stations[i];
            Order *cooking[2];
            for (int j = 0; j < s->cooking.count; ++j) cooking[j] = s->cooking.items[j];
            qsort(cooking, (size_t)s->cooking.count, sizeof *cooking, order_by_ready);
            printf("%s %s cooking", station_names[i], s->up ? "up" : "down");
            for (int j = 0; j < s->cooking.count; ++j) printf(" #%d@%s", cooking[j]->id, clock_text(cooking[j]->ready).text);
            if (!s->cooking.count) fputs(" -", stdout);
            fputs(" queue", stdout);
            for (int j = 0; j < s->queue.count; ++j) printf(" #%d", s->queue.items[j]->id);
            if (!s->queue.count) fputs(" -", stdout);
            putchar('\n');
        }
    } else if (equal(op, "FLOOR")) {
        int free_tables = 0, occupied = 0;
        for (int i = 1; i <= 99; ++i) {
            if (!tables[i].number) continue;
            if (tables[i].check) ++occupied;
            else ++free_tables;
        }
        printf("FLOOR %s free %d seated %d waiting %d\n", clock_text(now).text, free_tables, occupied, waiting_count);
        for (int i = 1; i <= 99; ++i) {
            Table *t = &tables[i];
            if (!t->number) continue;
            printf("table %d seats %d", i, t->seats);
            Check *c = t->check;
            if (!c) fputs(" free", stdout);
            else {
                printf(" %s guests %d server %s since %s items %d total %s", c->party, c->size, c->server->name, clock_text(c->seated).text, active_count(c), money(totals(c).total).text);
                if (c->paid) printf(" paid %s", money(c->paid).text);
            }
            putchar('\n');
        }
        for (int i = 0; i < waiting_count; ++i)
            printf("WAITING %d %s %d since %s\n", i + 1, waiting[i].name, waiting[i].size, clock_text(waiting[i].since).text);
    } else if (equal(op, "REPORT")) {
        report();
    } else {
        Check *c = check(a[1]);
        if (!c) return;
        int number = c->table->number;
        if (equal(op, "ORDER")) {
            if (!unlocked(c)) return;
            int seat = atoi(a[2]);
            if (!valid_seat(c, seat)) return;
            MenuItem *m = item(a[3]);
            if (!m) return;
            int quantity = atoi(a[4]);
            if (m->stock >= 0 && m->stock < quantity) { fail("only %d %s left", m->stock, m->name); return; }
            bool happy = m->course == DRINK && now < happy_end;
            Order *o = &orders[order_count];
            *o = (Order){ .id = order_count + 1, .seat = seat, .quantity = quantity, .prep = m->prep,
                .check = c, .item = m, .station = m->station, .course = m->course,
                .state = ORDERED, .price = m->price - (happy ? rounded(m->price, happy_rate) : 0) };
            ++order_count;
            append_order(&c->orders, o);
            printf("ORDER #%d table %d seat %d %s x%d %s%s\n", o->id, number, seat, m->name, quantity, money(charge(o)).text, happy ? " HAPPY" : "");
            if (m->stock >= 0) {
                m->stock -= quantity;
                if (!m->stock) printf("SOLDOUT %s\n", m->name);
            }
        } else if (equal(op, "FIRE")) {
            int course = course_index(a[2]);
            if (course < 0) return;
            bool found = false;
            for (int i = 0; i < c->orders.count; ++i)
                if (c->orders.items[i]->course == (Course)course && c->orders.items[i]->state == ORDERED) found = true;
            if (!found) { fail("nothing to fire for %s at table %d", a[2], number); return; }
            if (course == MAIN || course == DESSERT) {
                for (int earlier = STARTER; earlier < course; ++earlier) {
                    for (int i = 0; i < c->orders.count; ++i) {
                        Order *o = c->orders.items[i];
                        if (o->course == (Course)earlier && o->state == ORDERED) { fail("fire %s first", course_names[earlier]); return; }
                    }
                }
            }
            printf("FIRE table %d %s", number, a[2]);
            for (int i = 0; i < c->orders.count; ++i) {
                Order *o = c->orders.items[i];
                if (o->course != (Course)course || o->state != ORDERED) continue;
                o->state = QUEUED;
                o->fired = now;
                append_order(&stations[o->station].queue, o);
                printf(" #%d", o->id);
            }
            putchar('\n');
            for (int i = 0; i < 4; ++i) start_cooking(i, now);
        } else if (equal(op, "SERVE")) {
            bool found = false;
            for (int i = 0; i < c->orders.count; ++i) if (c->orders.items[i]->state == READY) found = true;
            if (!found) { fail("nothing ready for table %d", number); return; }
            printf("SERVE table %d", number);
            for (int i = 0; i < c->orders.count; ++i) {
                Order *o = c->orders.items[i];
                if (o->state != READY) continue;
                o->state = SERVED;
                o->item->served += o->quantity;
                printf(" #%d", o->id);
            }
            putchar('\n');
        } else if (equal(op, "DISCOUNT")) {
            if (!unlocked(c)) return;
            c->discount = atoi(a[2]);
            printf("DISCOUNT table %d %d%%\n", number, c->discount);
        } else if (equal(op, "BILL")) bill(c);
        else if (equal(op, "SPLIT")) split(c, a + 2);
        else if (equal(op, "PAY")) {
            bool cash = equal(a[2], "CASH");
            if (!cash && !equal(a[2], "CARD")) { fail("unknown method %s", a[2]); return; }
            if (!all_served(c)) return;
            Money due = totals(c).total - c->paid;
            if (!due) { fail("nothing to pay for table %d", number); return; }
            Money paid = cents(a[3]), applied = paid < due ? paid : due;
            c->paid += applied;
            if (cash) stats.cash += applied;
            else stats.card += applied;
            if (paid < due) printf("PAY table %d %s %s remaining %s\n", number, a[2], money(paid).text, money(due - paid).text);
            else {
                if (!cash) { stats.tips += paid - due; c->server->tips += paid - due; }
                printf("PAY table %d %s %s %s %s\n", number, a[2], money(paid).text, cash ? "change" : "tip", money(paid - due).text);
                close_check(c);
            }
        } else if (equal(op, "CLOSE")) {
            if (!all_served(c)) return;
            Money due = totals(c).total - c->paid;
            if (due) { fail("table %d still owes %s", number, money(due).text); return; }
            close_check(c);
        } else if (equal(op, "STATUS")) {
            printf("STATUS table %d %s guests %d since %s\n", number, c->party, c->size, clock_text(c->seated).text);
            for (int i = 0; i < c->orders.count; ++i) {
                Order *o = c->orders.items[i];
                printf("#%d seat %d %s x%d %s %s", o->id, o->seat, o->item->name, o->quantity, course_names[o->course], state_names[o->state]);
                if (o->state == COOKING) printf(" until %s", clock_text(o->ready).text);
                if (o->comp[0]) printf(" COMP %s", o->comp);
                putchar('\n');
            }
        }
    }
}

int main(void) {
    char line[256];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < 4; ++i) stations[i].up = true;
    for (int command = 0; command < count; ++command) {
        if (!fgets(line, sizeof line, stdin)) return EXIT_FAILURE;
        char *args[8];
        int length = 0;
        for (char *word = strtok(line, " \n"); word; word = strtok(NULL, " \n")) args[length++] = word;
        execute(args);
    }
    for (int i = 0; i < check_count; ++i) free(checks[i].orders.items);
    for (int i = 0; i < 4; ++i) { free(stations[i].queue.items); free(stations[i].cooking.items); }
    return 0;
}
