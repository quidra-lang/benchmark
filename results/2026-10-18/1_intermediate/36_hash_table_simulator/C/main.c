#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { CHAIN, LINEAR, QUADRATIC, DOUBLE, ROBINHOOD, CUCKOO } Mode;
static const char *const MODE_NAMES[] = {"CHAIN", "LINEAR", "QUADRATIC", "DOUBLE", "ROBINHOOD", "CUCKOO"};

typedef struct { char key[11]; int64_t value; } Item;
typedef struct Node { Item item; struct Node *next; } Node;
typedef enum { EMPTY, LIVE, TOMB } SlotState;
typedef struct { SlotState state; Item item; } Slot;
typedef struct {
    int64_t probes, rehashes, inserts, updates, hits, misses, deletes, absent;
} Counters;
typedef struct {
    Mode mode;
    int cap, size, tomb;
    Slot *slots;
    Node **heads, **tails;
    Counters counters;
} Table;
typedef struct { int maxload, minload; bool trace; } Settings;
typedef struct { char *data; size_t length, capacity; } String;
typedef struct { char data[40]; } Text;
typedef struct {
    bool found;
    int position, probes, first_tomb, empty;
    Node *node, *previous;
    String path;
} Search;
typedef struct {
    bool success, reused;
    int position, movements;
    Item homeless;
} Placement;
typedef struct { Item item; int position, cost; } Record;
typedef struct { int longest; int64_t sum; } Costs;

static void *allocate(size_t count, size_t size) {
    void *memory = calloc(count ? count : 1, size);
    if (!memory) exit(EXIT_FAILURE);
    return memory;
}

static void append(String *text, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int added = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    size_t needed = text->length + (size_t)added + 1;
    if (needed > text->capacity) {
        size_t capacity = text->capacity ? text->capacity : 64;
        while (capacity < needed) capacity *= 2;
        char *memory = realloc(text->data, capacity);
        if (!memory) exit(EXIT_FAILURE);
        text->data = memory;
        text->capacity = capacity;
    }
    vsnprintf(text->data + text->length, text->capacity - text->length, format, args);
    text->length += (size_t)added;
    va_end(args);
}

static const char *string_data(const String *text) { return text->data ? text->data : ""; }
static Item item_make(const char *key, int64_t value) {
    Item item = {.value = value};
    strcpy(item.key, key);
    return item;
}
static int hash(const char *key, int base, int modulus) {
    int value = 0;
    for (const unsigned char *p = (const unsigned char *)key; *p; p++) value = (value * base + *p) % modulus;
    return value;
}
static bool prime(int value) {
    if (value < 2) return false;
    for (int divisor = 2; divisor <= value / divisor; divisor++) if (value % divisor == 0) return false;
    return true;
}
static int next_prime(int value) {
    if (value < 2) value = 2;
    while (!prime(value)) value++;
    return value;
}
static int slot_count(const Table *table) { return table->cap * (table->mode == CUCKOO ? 2 : 1); }
static int distance(const Table *table, const Item *item, int position) {
    return (position - hash(item->key, 31, table->cap) + table->cap) % table->cap;
}
static Text position_text(const Table *table, int position) {
    Text text;
    if (table->mode == CUCKOO) snprintf(text.data, sizeof(text.data), "T%d.%d", position / table->cap + 1, position % table->cap);
    else snprintf(text.data, sizeof(text.data), "%d", position);
    return text;
}
static Text decimal(int64_t numerator, int64_t denominator) {
    int64_t value = denominator ? 100 * numerator / denominator : 0;
    Text text;
    snprintf(text.data, sizeof(text.data), "%" PRId64 ".%02" PRId64, value / 100, value % 100);
    return text;
}

static Table table_new(Mode mode, int cap) {
    Table table = {.mode = mode, .cap = cap};
    if (mode == CHAIN) {
        table.heads = allocate((size_t)cap, sizeof(Node *));
        table.tails = allocate((size_t)cap, sizeof(Node *));
    } else table.slots = allocate((size_t)slot_count(&table), sizeof(Slot));
    return table;
}
static void table_destroy(Table *table) {
    if (table->mode == CHAIN) {
        for (int i = 0; i < table->cap; i++) {
            Node *node = table->heads[i];
            while (node) { Node *next = node->next; free(node); node = next; }
        }
        free(table->heads);
        free(table->tails);
    } else free(table->slots);
}
static void replace_table(Table *table, Table replacement) {
    Counters counters = table->counters;
    table_destroy(table);
    *table = replacement;
    table->counters = counters;
}

static void observe(Search *search, const Table *table, int position, const char *content, bool record_path) {
    search->probes++;
    if (record_path) append(&search->path, "%s%s:%s", search->path.length ? " " : "", position_text(table, position).data, content);
}
static Search search_key(const Table *table, const char *key, bool record_path) {
    Search search = {.position = -1, .first_tomb = -1, .empty = -1};
    int home = hash(key, 31, table->cap);
    if (table->mode == CHAIN) {
        search.position = home;
        for (Node *node = table->heads[home]; node; node = node->next) {
            observe(&search, table, home, node->item.key, record_path);
            if (strcmp(node->item.key, key) == 0) { search.found = true; search.node = node; break; }
            search.previous = node;
        }
        return search;
    }
    int step = table->mode == DOUBLE ? 1 + hash(key, 37, table->cap - 1) : 1;
    int limit = table->mode == CUCKOO ? 2 : table->cap;
    for (int i = 0; i < limit; i++) {
        int position;
        if (table->mode == CUCKOO) position = i == 0 ? home : table->cap + hash(key, 37, table->cap);
        else position = (home + (table->mode == QUADRATIC ? i * i : i * step)) % table->cap;
        const Slot *slot = &table->slots[position];
        const char *content = slot->state == LIVE ? slot->item.key : slot->state == TOMB ? "D" : "-";
        observe(&search, table, position, content, record_path);
        if (slot->state == LIVE && strcmp(slot->item.key, key) == 0) {
            search.found = true;
            search.position = position;
            break;
        }
        if (table->mode == CUCKOO) continue;
        if (slot->state == EMPTY) { search.empty = position; break; }
        if (slot->state == TOMB && search.first_tomb < 0) search.first_tomb = position;
        if (table->mode == ROBINHOOD && distance(table, &slot->item, position) < i) break;
    }
    return search;
}
static Item *found_item(Table *table, const Search *search) {
    return table->mode == CHAIN ? &search->node->item : &table->slots[search->position].item;
}

static Placement place(Table *table, Item item, const Search *initial, String *events) {
    Placement result = {.position = -1};
    int home = hash(item.key, 31, table->cap);
    if (table->mode == CHAIN) {
        Node *node = allocate(1, sizeof(Node));
        node->item = item;
        if (table->tails[home]) table->tails[home]->next = node;
        else table->heads[home] = node;
        table->tails[home] = node;
        result.success = true;
        result.position = home;
    } else if (table->mode == ROBINHOOD) {
        Item carried = item;
        int position = home, traveled = 0, from = -1;
        for (;;) {
            Slot *slot = &table->slots[position];
            if (slot->state == EMPTY) {
                if (from >= 0 && events) append(events, "SHIFT %s %d -> %d\n", carried.key, from, position);
                slot->state = LIVE;
                slot->item = carried;
                if (result.position < 0) result.position = position;
                result.success = true;
                break;
            }
            int resident_distance = distance(table, &slot->item, position);
            if (resident_distance < traveled) {
                if (from >= 0 && events) append(events, "SHIFT %s %d -> %d\n", carried.key, from, position);
                Item displaced = slot->item;
                slot->item = carried;
                carried = displaced;
                if (result.position < 0) result.position = position;
                from = position;
                traveled = resident_distance;
                result.movements++;
            }
            position = (position + 1) % table->cap;
            traveled++;
        }
    } else if (table->mode == CUCKOO) {
        Item carried = item;
        int part = 0;
        for (;;) {
            int position = part * table->cap + hash(carried.key, part == 0 ? 31 : 37, table->cap);
            Slot *slot = &table->slots[position];
            if (slot->state == EMPTY) {
                slot->state = LIVE;
                slot->item = carried;
                result.success = true;
                result.position = search_key(table, item.key, false).position;
                break;
            }
            if (result.movements == table->cap) { result.homeless = carried; break; }
            Item displaced = slot->item;
            if (events) append(events, "KICK %s %s\n", displaced.key, position_text(table, position).data);
            slot->item = carried;
            carried = displaced;
            result.movements++;
            part = 1 - part;
        }
    } else {
        Search own = {0};
        if (!initial) { own = search_key(table, item.key, false); initial = &own; }
        int position = initial->first_tomb >= 0 ? initial->first_tomb : initial->empty;
        if (position >= 0) {
            result.reused = table->slots[position].state == TOMB;
            if (result.reused) table->tomb--;
            table->slots[position] = (Slot){.state = LIVE, .item = item};
            result.position = position;
            result.success = true;
        } else result.homeless = item;
    }
    return result;
}

static int delete_item(Table *table, const Search *search, String *events) {
    int shifted = 0, position = search->position;
    if (table->mode == CHAIN) {
        Node *node = search->node;
        if (search->previous) search->previous->next = node->next;
        else table->heads[position] = node->next;
        if (table->tails[position] == node) table->tails[position] = search->previous;
        free(node);
    } else if (table->mode == LINEAR || table->mode == QUADRATIC || table->mode == DOUBLE) {
        table->slots[position].state = TOMB;
        table->tomb++;
    } else {
        table->slots[position].state = EMPTY;
        if (table->mode == ROBINHOOD) {
            int source = (position + 1) % table->cap;
            while (table->slots[source].state == LIVE && distance(table, &table->slots[source].item, source) > 0) {
                int destination = (source + table->cap - 1) % table->cap;
                if (events) append(events, "SHIFT %s %d -> %d\n", table->slots[source].item.key, source, destination);
                table->slots[destination] = table->slots[source];
                table->slots[source].state = EMPTY;
                shifted++;
                source = (source + 1) % table->cap;
            }
        }
    }
    table->size--;
    return shifted;
}

static Item *old_order(const Table *table, const Item *pending, int *count) {
    Item *items = allocate((size_t)table->size + (pending != NULL), sizeof(Item));
    int length = 0;
    if (table->mode == CHAIN) {
        for (int i = 0; i < table->cap; i++) for (Node *node = table->heads[i]; node; node = node->next) items[length++] = node->item;
    } else {
        for (int i = 0; i < slot_count(table); i++) if (table->slots[i].state == LIVE) items[length++] = table->slots[i].item;
    }
    if (pending) items[length++] = *pending;
    *count = length;
    return items;
}
static bool rebuild(Table *table, Mode mode, int cap, const Item *items, int count) {
    Table trial = table_new(mode, cap);
    for (int i = 0; i < count; i++) {
        Placement result = place(&trial, items[i], NULL, NULL);
        if (!result.success) { table_destroy(&trial); return false; }
        trial.size++;
    }
    replace_table(table, trial);
    return true;
}
static void automatic_rebuild(Table *table, int cap, const char *reason, const Item *pending, FILE *output) {
    int count, old_cap = table->cap;
    Item *items = old_order(table, pending, &count);
    while (!rebuild(table, table->mode, cap, items, count)) cap = next_prime(2 * cap);
    table->counters.rehashes++;
    if (output) fprintf(output, "REHASH %s %d -> %d\n", reason, old_cap, cap);
    free(items);
}
static void load_check(Table *table, const Settings *settings, FILE *output) {
    int64_t limit = (int64_t)settings->maxload * slot_count(table);
    if ((int64_t)(table->size + table->tomb) * 100 <= limit) return;
    bool grow = (int64_t)table->size * 200 > limit;
    automatic_rebuild(table, grow ? next_prime(2 * table->cap) : table->cap, grow ? "load" : "tomb", NULL, output);
}
static void shrink_check(Table *table, const Settings *settings, FILE *output) {
    int cap = next_prime(table->cap / 2);
    int slots = cap * (table->mode == CUCKOO ? 2 : 1);
    if ((int64_t)table->size * 100 >= (int64_t)settings->minload * slot_count(table) || cap >= table->cap ||
        (int64_t)table->size * 100 > (int64_t)settings->maxload * slots) return;
    int count, old_cap = table->cap;
    Item *items = old_order(table, NULL, &count);
    if (rebuild(table, table->mode, cap, items, count)) {
        table->counters.rehashes++;
        if (output) fprintf(output, "REHASH shrink %d -> %d\n", old_cap, cap);
    }
    free(items);
}

static void trace_lines(FILE *output, const Search *search, const String *events) {
    fprintf(output, "PATH %s\n", search->path.length ? search->path.data : "none");
    fputs(string_data(events), output);
}
static bool put_item(Table *table, Item item, bool add_value, const Settings *settings, FILE *output, bool details) {
    bool trace = details && settings->trace;
    Search search = search_key(table, item.key, trace);
    table->counters.probes += search.probes;
    const char *command = add_value ? "ADD" : "PUT";
    String events = {0};
    if (search.found) {
        Item *stored = found_item(table, &search);
        int64_t old = stored->value;
        stored->value = add_value ? old + item.value : item.value;
        table->counters.updates++;
        if (details) fprintf(output, "%s %s=%" PRId64 " UPDATED old=%" PRId64 " at=%s probes=%d\n",
            command, item.key, stored->value, old, position_text(table, search.position).data, search.probes);
        if (trace) trace_lines(output, &search, &events);
        free(search.path.data);
        return false;
    }
    Placement result = place(table, item, &search, trace ? &events : NULL);
    table->counters.inserts++;
    if (details) {
        fprintf(output, "%s %s=%" PRId64 " NEW", command, item.key, item.value);
        if (result.success) {
            fprintf(output, " at=%s probes=%d", position_text(table, result.position).data, search.probes);
            if (result.reused) fputs(" reused", output);
            if (table->mode == ROBINHOOD) fprintf(output, " shifted=%d", result.movements);
            if (table->mode == CUCKOO) fprintf(output, " kicks=%d", result.movements);
        } else {
            fprintf(output, " probes=%d", search.probes);
            if (table->mode == QUADRATIC) fputs(" full", output);
            else fprintf(output, " kicks=%d failed", result.movements);
        }
        fputc('\n', output);
    }
    if (trace) trace_lines(output, &search, &events);
    free(search.path.data);
    free(events.data);
    if (result.success) table->size++;
    else automatic_rebuild(table, next_prime(2 * table->cap), table->mode == QUADRATIC ? "full" : "kicks", &result.homeless, output);
    load_check(table, settings, output);
    return true;
}
static bool remove_key(Table *table, const char *key, const Settings *settings, FILE *output, bool details) {
    bool trace = details && settings->trace;
    Search search = search_key(table, key, trace);
    String events = {0};
    table->counters.probes += search.probes;
    if (search.found) {
        int shifted = delete_item(table, &search, trace ? &events : NULL);
        table->counters.deletes++;
        if (details) {
            fprintf(output, "DEL %s OK at=%s probes=%d", key, position_text(table, search.position).data, search.probes);
            if (table->mode == ROBINHOOD) fprintf(output, " shifted=%d", shifted);
            fputc('\n', output);
        }
    } else {
        table->counters.absent++;
        if (details) fprintf(output, "DEL %s NOT FOUND probes=%d\n", key, search.probes);
    }
    if (trace) trace_lines(output, &search, &events);
    free(search.path.data);
    free(events.data);
    if (search.found) shrink_check(table, settings, output);
    return search.found;
}
static void get_key(Table *table, const char *key, const Settings *settings) {
    Search search = search_key(table, key, settings->trace);
    table->counters.probes += search.probes;
    if (search.found) {
        table->counters.hits++;
        printf("GET %s=%" PRId64 " at=%s probes=%d\n", key, found_item(table, &search)->value,
            position_text(table, search.position).data, search.probes);
    } else {
        table->counters.misses++;
        printf("GET %s NOT FOUND probes=%d\n", key, search.probes);
    }
    if (settings->trace) trace_lines(stdout, &search, &(String){0});
    free(search.path.data);
}
static int item_cost(const Table *table, const Item *item, int position) {
    if (table->mode == CUCKOO) return position / table->cap + 1;
    if (table->mode == LINEAR || table->mode == ROBINHOOD) return distance(table, item, position) + 1;
    return search_key(table, item->key, false).probes;
}
static Record *records(const Table *table) {
    Record *result = allocate((size_t)table->size, sizeof(Record));
    int count = 0;
    if (table->mode == CHAIN) {
        for (int i = 0; i < table->cap; i++) {
            int cost = 0;
            for (Node *node = table->heads[i]; node; node = node->next) {
                result[count++] = (Record){.item = node->item, .position = i, .cost = ++cost};
            }
        }
    } else {
        for (int i = 0; i < slot_count(table); i++) if (table->slots[i].state == LIVE) {
            const Item *item = &table->slots[i].item;
            result[count++] = (Record){.item = *item, .position = i, .cost = item_cost(table, item, i)};
        }
    }
    return result;
}
static Costs costs(const Table *table) {
    Record *items = records(table);
    Costs result = {0};
    for (int i = 0; i < table->size; i++) {
        result.sum += items[i].cost;
        if (items[i].cost > result.longest) result.longest = items[i].cost;
    }
    free(items);
    return result;
}
static int compare_items(const void *left, const void *right) {
    const Item *a = left, *b = right;
    return strcmp(a->key, b->key);
}
static int compare_costs(const void *left, const void *right) {
    const Record *a = left, *b = right;
    if (a->cost != b->cost) return a->cost > b->cost ? -1 : 1;
    return strcmp(a->item.key, b->item.key);
}

static void dump(const Table *table) {
    printf("DUMP %s cap=%d size=%d tomb=%d\n", MODE_NAMES[table->mode], table->cap, table->size, table->tomb);
    if (table->mode == CHAIN) {
        for (int i = 0; i < table->cap; i++) {
            printf("%d", i);
            if (!table->heads[i]) fputs(" -", stdout);
            for (Node *node = table->heads[i]; node; node = node->next) printf(" %s=%" PRId64, node->item.key, node->item.value);
            putchar('\n');
        }
    } else {
        for (int i = 0; i < slot_count(table); i++) {
            if (table->mode == CUCKOO) printf("T%d %d ", i / table->cap + 1, i % table->cap);
            else printf("%d ", i);
            const Slot *slot = &table->slots[i];
            if (slot->state == EMPTY) putchar('-');
            else if (slot->state == TOMB) putchar('D');
            else {
                printf("%s=%" PRId64, slot->item.key, slot->item.value);
                if (table->mode == ROBINHOOD) printf(" d=%d", distance(table, &slot->item, i));
            }
            putchar('\n');
        }
    }
}
static char gauge(int value) { return value < 10 ? (char)('0' + value) : '+'; }
static void map_table(const Table *table) {
    printf("MAP %s cap=%d\n", MODE_NAMES[table->mode], table->cap);
    int parts = table->mode == CUCKOO ? 2 : 1;
    for (int part = 0; part < parts; part++) {
        for (int start = 0; start < table->cap; start += 40) {
            char text[41];
            int length = table->cap - start < 40 ? table->cap - start : 40;
            for (int j = 0; j < length; j++) {
                int i = start + j;
                if (table->mode == CHAIN) {
                    int count = 0;
                    for (Node *node = table->heads[i]; node; node = node->next) count++;
                    text[j] = count ? gauge(count) : '.';
                } else {
                    int position = part * table->cap + i;
                    const Slot *slot = &table->slots[position];
                    text[j] = slot->state == EMPTY ? '.' : slot->state == TOMB ? 'D' : table->mode == CUCKOO ? '#'
                        : gauge(item_cost(table, &slot->item, position) - 1);
                }
            }
            text[length] = '\0';
            if (table->mode == CUCKOO) printf("T%d ", part + 1);
            printf("%05d %s\n", start, text);
        }
    }
}
static void statistics(const Table *table) {
    Costs result = costs(table);
    const Counters *c = &table->counters;
    printf("STATS %s size=%d cap=%d slots=%d tomb=%d load=%s%% longest=%d avg=%s probes=%" PRId64 " rehashes=%" PRId64 "\n",
        MODE_NAMES[table->mode], table->size, table->cap, slot_count(table), table->tomb,
        decimal((int64_t)table->size * 100, slot_count(table)).data, result.longest, decimal(result.sum, table->size).data, c->probes, c->rehashes);
    printf("OPS inserts=%" PRId64 " updates=%" PRId64 " hits=%" PRId64 " misses=%" PRId64 " deletes=%" PRId64 " absent=%" PRId64 "\n",
        c->inserts, c->updates, c->hits, c->misses, c->deletes, c->absent);
}
static void histogram(const int *values, int count) {
    int maximum = 0;
    for (int i = 0; i < count; i++) if (values[i] > maximum) maximum = values[i];
    int *frequencies = allocate((size_t)maximum + 1, sizeof(int));
    for (int i = 0; i < count; i++) frequencies[values[i]]++;
    for (int value = 0; value <= maximum; value++) if (frequencies[value]) {
        int frequency = frequencies[value];
        printf("%d %d ", value, frequency);
        for (int j = 0; j < frequency && j < 50; j++) putchar('#');
        if (frequency > 50) putchar('+');
        putchar('\n');
    }
    free(frequencies);
}
static void clusters(const Table *table) {
    int *runs = allocate((size_t)slot_count(table), sizeof(int));
    int count = 0, longest = 0;
    if (table->mode == CHAIN) {
        for (int i = 0; i < table->cap; i++) {
            int length = 0;
            for (Node *node = table->heads[i]; node; node = node->next) length++;
            if (length) runs[count++] = length;
        }
    } else {
        int parts = table->mode == CUCKOO ? 2 : 1;
        for (int part = 0; part < parts; part++) {
            int base = part * table->cap, empty = -1;
            for (int i = 0; i < table->cap; i++) if (table->slots[base + i].state == EMPTY) { empty = i; break; }
            if (empty < 0) runs[count++] = table->cap;
            else {
                int length = 0;
                for (int offset = 1; offset <= table->cap; offset++) {
                    int i = (empty + offset) % table->cap;
                    if (table->slots[base + i].state != EMPTY) length++;
                    else if (length) { runs[count++] = length; length = 0; }
                }
            }
        }
    }
    for (int i = 0; i < count; i++) if (runs[i] > longest) longest = runs[i];
    printf("CLUSTERS runs=%d longest=%d\n", count, longest);
    histogram(runs, count);
    free(runs);
}
static void distribution(const Table *table) {
    Record *items = records(table);
    int *values = allocate((size_t)table->size, sizeof(int));
    int longest = 0;
    for (int i = 0; i < table->size; i++) {
        values[i] = items[i].cost;
        if (values[i] > longest) longest = values[i];
    }
    printf("DIST keys=%d longest=%d\n", table->size, longest);
    histogram(values, table->size);
    free(values);
    free(items);
}
static void scan(const Table *table, int cursor, int limit) {
    String keys = {0};
    int count = 0, end = cursor, slots = slot_count(table);
    while (end < slots && count < limit) {
        if (table->mode == CHAIN) {
            for (Node *node = table->heads[end]; node; node = node->next) { append(&keys, " %s", node->item.key); count++; }
        } else if (table->slots[end].state == LIVE) { append(&keys, " %s", table->slots[end].item.key); count++; }
        end++;
    }
    printf("SCAN next=%d%s\n", end == slots ? 0 : end, string_data(&keys));
    free(keys.data);
}

typedef char Key[11];
static Key *generate_keys(int count, int length, int64_t seed) {
    Key *keys = allocate((size_t)count, sizeof(Key));
    int64_t state = seed;
    for (int i = 0; i < count; i++) {
        for (int j = 0; j < length; j++) {
            state = 48271 * state % 2147483647;
            keys[i][j] = (char)('a' + state % 26);
        }
        keys[i][length] = '\0';
    }
    return keys;
}
static void compare_modes(const Table *table, int cap, const Settings *settings) {
    int count;
    Item *items = old_order(table, NULL, &count);
    qsort(items, (size_t)count, sizeof(Item), compare_items);
    printf("COMPARE keys=%d cap=%d\n", count, cap);
    for (Mode mode = CHAIN; mode <= CUCKOO; mode++) {
        Table trial = table_new(mode, cap);
        for (int i = 0; i < count; i++) put_item(&trial, items[i], false, settings, NULL, false);
        Costs result = costs(&trial);
        printf("%s cap=%d longest=%d avg=%s probes=%" PRId64 " rehashes=%" PRId64 "\n", MODE_NAMES[mode], trial.cap,
            result.longest, decimal(result.sum, trial.size).data, trial.counters.probes, trial.counters.rehashes);
        table_destroy(&trial);
    }
    free(items);
}
static void benchmark(int cap, int count, int length, int64_t seed, const Settings *settings) {
    Key *keys = generate_keys(2 * count, length, seed);
    printf("BENCH cap=%d count=%d len=%d seed=%" PRId64 "\n", cap, count, length, seed);
    for (Mode mode = CHAIN; mode <= CUCKOO; mode++) {
        Table trial = table_new(mode, cap);
        for (int i = 0; i < count; i++) put_item(&trial, item_make(keys[i], i + 1), false, settings, NULL, false);
        int misses = 0;
        int64_t miss_probes = 0;
        for (int i = count; i < 2 * count; i++) {
            Search search = search_key(&trial, keys[i], false);
            if (!search.found) { misses++; miss_probes += search.probes; }
        }
        Costs result = costs(&trial);
        printf("%s cap=%d keys=%d hit=%s misses=%d miss=%s rehashes=%" PRId64 "\n", MODE_NAMES[mode], trial.cap, trial.size,
            decimal(result.sum, trial.size).data, misses, decimal(miss_probes, misses).data, trial.counters.rehashes);
        table_destroy(&trial);
    }
    free(keys);
}

typedef enum {
    CREATE, MAXLOAD, MINLOAD, TRACE, HASH, PUT, ADD, GET, DEL, PROBE, GEN, GENDEL,
    RESIZE, CONVERT, CLEAR, DUMP, MAP, STATS, KEYS, TOP, SCAN, CLUSTERS, DIST, COMPARE, BENCH, UNKNOWN
} Command;
static const char *const COMMAND_NAMES[] = {
    "CREATE", "MAXLOAD", "MINLOAD", "TRACE", "HASH", "PUT", "ADD", "GET", "DEL", "PROBE", "GEN", "GENDEL",
    "RESIZE", "CONVERT", "CLEAR", "DUMP", "MAP", "STATS", "KEYS", "TOP", "SCAN", "CLUSTERS", "DIST", "COMPARE", "BENCH"
};
static Command command_parse(const char *word) {
    for (int i = CREATE; i < UNKNOWN; i++) if (strcmp(word, COMMAND_NAMES[i]) == 0) return (Command)i;
    return UNKNOWN;
}
static bool mode_parse(const char *word, Mode *mode) {
    for (int i = CHAIN; i <= CUCKOO; i++) if (strcmp(word, MODE_NAMES[i]) == 0) { *mode = (Mode)i; return true; }
    return false;
}
static int64_t number(const char *word) { return strtoll(word, NULL, 10); }
static bool valid_capacity(int64_t cap) { return cap >= 2 && cap <= 10000; }
static bool valid_generation(int64_t count, int64_t length, int64_t seed) {
    return count >= 1 && count <= 500 && length >= 1 && length <= 10 && seed >= 1 && seed <= 2147483646;
}

static void execute(Table **current, Settings *settings, char **words) {
    Command command = command_parse(words[0]);
    if (command == UNKNOWN) { printf("ERROR UNKNOWN COMMAND %s\n", words[0]); return; }
    if (command == CREATE) {
        Mode mode;
        if (!mode_parse(words[1], &mode)) { printf("ERROR BAD MODE %s\n", words[1]); return; }
        int64_t capacity = number(words[2]);
        if (!valid_capacity(capacity)) { puts("ERROR BAD CAPACITY"); return; }
        if (*current) table_destroy(*current);
        else *current = allocate(1, sizeof(Table));
        **current = table_new(mode, next_prime((int)capacity));
        printf("CREATE %s cap=%d\n", MODE_NAMES[mode], (*current)->cap);
        return;
    }
    if (command == MAXLOAD || command == MINLOAD) {
        int64_t value = number(words[1]);
        if (value < (command == MAXLOAD ? 10 : 0) || value > (command == MAXLOAD ? 95 : 40)) { puts("ERROR BAD LOAD"); return; }
        if (command == MAXLOAD) settings->maxload = (int)value;
        else settings->minload = (int)value;
        printf("%s %" PRId64 "\n", words[0], value);
        return;
    }
    if (command == TRACE) {
        if (strcmp(words[1], "ON") != 0 && strcmp(words[1], "OFF") != 0) { puts("ERROR BAD ARGUMENT"); return; }
        settings->trace = strcmp(words[1], "ON") == 0;
        printf("TRACE %s\n", words[1]);
        return;
    }
    if (command == HASH) {
        int64_t capacity = number(words[2]);
        if (!valid_capacity(capacity)) { puts("ERROR BAD CAPACITY"); return; }
        int m = (int)capacity;
        printf("HASH %s m=%d h31=%d h37=%d step=%d\n", words[1], m, hash(words[1], 31, m), hash(words[1], 37, m), 1 + hash(words[1], 37, m - 1));
        return;
    }
    if (command == BENCH) {
        int64_t capacity = number(words[1]);
        if (!valid_capacity(capacity)) { puts("ERROR BAD CAPACITY"); return; }
        int64_t count = number(words[2]), length = number(words[3]), seed = number(words[4]);
        if (!valid_generation(count, length, seed)) { puts("ERROR BAD ARGUMENT"); return; }
        benchmark(next_prime((int)capacity), (int)count, (int)length, seed, settings);
        return;
    }
    Table *table = *current;
    if (!table) { puts("ERROR NO TABLE"); return; }
    switch (command) {
        case PUT: case ADD:
            put_item(table, item_make(words[1], number(words[2])), command == ADD, settings, stdout, true);
            break;
        case GET:
            get_key(table, words[1], settings);
            break;
        case DEL:
            remove_key(table, words[1], settings, stdout, true);
            break;
        case PROBE: {
            Search search = search_key(table, words[1], true);
            printf("PROBE %s", words[1]);
            if (search.path.length) printf(" %s", search.path.data);
            printf(" %s probes=%d\n", search.found ? "FOUND" : "MISS", search.probes);
            free(search.path.data);
            break;
        }
        case GEN: case GENDEL: {
            int64_t count = number(words[1]), length = number(words[2]), seed = number(words[3]);
            if (!valid_generation(count, length, seed)) { puts("ERROR BAD ARGUMENT"); return; }
            Key *keys = generate_keys((int)count, (int)length, seed);
            int changed = 0;
            for (int i = 0; i < count; i++) {
                if (command == GEN) changed += put_item(table, item_make(keys[i], i + 1), false, settings, stdout, false);
                else changed += remove_key(table, keys[i], settings, stdout, false);
            }
            if (command == GEN) printf("GEN %" PRId64 " new=%d updated=%" PRId64 "\n", count, changed, count - changed);
            else printf("GENDEL %" PRId64 " deleted=%d missing=%" PRId64 "\n", count, changed, count - changed);
            free(keys);
            break;
        }
        case RESIZE: case CONVERT: {
            int cap = table->cap, old_cap = table->cap;
            Mode mode = table->mode, old_mode = table->mode;
            if (command == RESIZE) {
                int64_t capacity = number(words[1]);
                if (!valid_capacity(capacity)) { puts("ERROR BAD CAPACITY"); return; }
                cap = next_prime((int)capacity);
            } else if (!mode_parse(words[1], &mode)) { printf("ERROR BAD MODE %s\n", words[1]); return; }
            int slots = cap * (mode == CUCKOO ? 2 : 1);
            if ((int64_t)table->size * 100 > (int64_t)settings->maxload * slots) { puts("ERROR TOO SMALL"); return; }
            int count;
            Item *items = old_order(table, NULL, &count);
            bool success = rebuild(table, mode, cap, items, count);
            free(items);
            if (!success) { puts("ERROR REBUILD FAILED"); return; }
            if (command == RESIZE) printf("RESIZE %d -> %d\n", old_cap, cap);
            else printf("CONVERT %s -> %s cap=%d\n", MODE_NAMES[old_mode], MODE_NAMES[mode], cap);
            break;
        }
        case CLEAR:
            printf("CLEAR %d\n", table->size);
            replace_table(table, table_new(table->mode, table->cap));
            break;
        case DUMP:
            dump(table);
            break;
        case MAP:
            map_table(table);
            break;
        case STATS:
            statistics(table);
            break;
        case KEYS: {
            int count;
            Item *items = old_order(table, NULL, &count);
            qsort(items, (size_t)count, sizeof(Item), compare_items);
            printf("KEYS %d", count);
            for (int i = 0; i < count; i++) printf(" %s", items[i].key);
            putchar('\n');
            free(items);
            break;
        }
        case TOP: {
            int64_t limit = number(words[1]);
            if (limit < 1 || limit > 100) { puts("ERROR BAD ARGUMENT"); return; }
            Record *items = records(table);
            qsort(items, (size_t)table->size, sizeof(Record), compare_costs);
            int count = table->size < limit ? table->size : (int)limit;
            printf("TOP %d\n", count);
            for (int i = 0; i < count; i++) printf("%s cost=%d at=%s\n", items[i].item.key, items[i].cost, position_text(table, items[i].position).data);
            free(items);
            break;
        }
        case SCAN: {
            int64_t cursor = number(words[1]), limit = number(words[2]);
            if (limit < 1 || limit > 100) { puts("ERROR BAD ARGUMENT"); return; }
            if (cursor >= slot_count(table)) { puts("ERROR BAD CURSOR"); return; }
            scan(table, (int)cursor, (int)limit);
            break;
        }
        case CLUSTERS:
            clusters(table);
            break;
        case DIST:
            distribution(table);
            break;
        case COMPARE: {
            int64_t capacity = number(words[1]);
            if (!valid_capacity(capacity)) { puts("ERROR BAD CAPACITY"); return; }
            compare_modes(table, next_prime((int)capacity), settings);
            break;
        }
        default: break;
    }
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = allocate(capacity, 1);
    int ch;
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            char *memory = realloc(line, capacity);
            if (!memory) exit(EXIT_FAILURE);
            line = memory;
        }
        line[length++] = (char)ch;
    }
    if (ch == EOF && length == 0) { free(line); return NULL; }
    if (length && line[length - 1] == '\r') length--;
    line[length] = '\0';
    return line;
}

int main(void) {
    char *line = read_line();
    if (!line) return 0;
    int count = (int)number(line);
    free(line);
    Table *table = NULL;
    Settings settings = {.maxload = 75};
    for (int i = 0; i < count; i++) {
        line = read_line();
        if (!line) break;
        char *words[5];
        int size = 0;
        char *word = strtok(line, " ");
        while (word && size < 5) { words[size++] = word; word = strtok(NULL, " "); }
        execute(&table, &settings, words);
        free(line);
    }
    if (table) { table_destroy(table); free(table); }
    return 0;
}
