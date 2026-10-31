#ifndef COHERENCE_H
#define COHERENCE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef long long Number;
typedef struct MemoryBlock MemoryBlock;
typedef struct {
    MemoryBlock *head;
} Memory;
extern Memory permanent;
extern Memory *memory;
void *allocate(size_t size);
void clear_memory(Memory *pool);
char *substring(const char *source, size_t length), *copy_text(const char *source),
    *format(const char *pattern, ...);
#define VECTOR(Name, Type)                                                                         \
    typedef struct {                                                                               \
        Type *items;                                                                               \
        size_t count, capacity;                                                                    \
    } Name;                                                                                        \
    static inline void Name##_add(Name *list, Type item) {                                         \
        if (list->count == list->capacity) {                                                       \
            size_t capacity = list->capacity ? list->capacity * 2 : 8;                             \
            Type *items = allocate(capacity * sizeof(Type));                                       \
            if (list->count)                                                                       \
                memcpy(items, list->items, list->count * sizeof(Type));                            \
            list->items = items;                                                                   \
            list->capacity = capacity;                                                             \
        }                                                                                          \
        list->items[list->count++] = item;                                                         \
    }
VECTOR(Names, char *)
Names split(const char *source, const char *separator), read_lines(const char *path);
char *join(Names values, const char *separator), *trim(const char *source);
bool decimal_integer(const char *source, size_t maximum), valid_hex_address(const char *source);
Number hex_value(const char *source);
char *hex_address(Number value);
void write_lines(const char *filename, Names lines);
typedef enum { P_VI, P_MSI, P_MESI, P_MOESI } Protocol;
typedef enum { LRU, FIFO, PLRU } Replacement;
extern const char *protocol_names[4], *replacement_names[3];
typedef struct {
    char *name;
    Protocol protocol;
    Replacement l1, l2;
    int order;
} Scenario;
typedef struct {
    char *name;
    Number first, last;
} Region;
typedef struct {
    int cores, line_size, l1_size, l1_ways, l2_size, l2_ways, l1_sets, l2_sets, cap;
    Number t1, t2, tm, tb, interval;
    int top;
    Scenario scenarios[8];
    int scenario_count;
    char *primary;
    Region regions[16];
    int region_count;
    Number watch[8];
    int watch_count;
} Config;
Config read_config(void);
typedef struct {
    bool valid;
    Number block;
    char state;
} Entry;
typedef struct {
    Entry entries[16];
    Number touched[16];
    int bits[16];
    Number fills, evictions;
} CacheSet;
typedef struct {
    int set_count, ways;
    Replacement replacement;
    CacheSet *sets;
    Number clock;
} Cache;
Cache cache_create(int sets, int ways, Replacement replacement);
int cache_locate(const Cache *cache, Number block);
char cache_state(const Cache *cache, Number block);
void cache_change(Cache *cache, Number block, char state), cache_touch(Cache *cache, Number block);
Entry cache_remove(Cache *cache, Number block), cache_fill(Cache *cache, Number block, char state);
char *cache_order(const Cache *cache, int row);
typedef enum { TX_NONE = -1, BUS_RD, BUS_RDX, BUS_UPGR, BUS_WR, WB } TransactionKind;
extern const char *transaction_names[5], *service_names[6], *miss_names[4];
typedef struct {
    TransactionKind transaction;
    char state;
} RequestTransition;
typedef struct {
    char state;
    bool supply, flush;
} SnoopTransition;
bool dirty(char state);
RequestTransition requester(Protocol protocol, char old, char operation, bool other);
SnoopTransition snoop(Protocol protocol, char old, TransactionKind transaction);
typedef struct {
    Number number, start, block;
    int core;
    TransactionKind kind;
    char snoop_old[8], snoop_new[8], copies[8];
    int snoop_hits, invalidations, supplier;
    bool flushed, l2_hit, evicted, dirty_eviction;
    Number evicted_block;
    int source;
} Transaction;
VECTOR(Transactions, Transaction)
typedef struct {
    Number latency, free, wait;
    Transactions transactions;
} Bus;
Transaction *bus_assign(Bus *bus, int core, TransactionKind kind, Number block, Number requested);
char *bus_line(const Bus *bus, const Transaction *transaction, int line_size, int cores);
typedef struct {
    Number accesses, reads, writes, hits, misses, fences, latency, fence_stall, read_latency,
        write_latency, finish;
    Number miss_counts[6], service[6], bus[5], snoop[4];
} CoreStats;
CoreStats total_counters(const CoreStats *cores, int count);
char *fraction(Number p, Number q), *decimal(Number p, Number q), *core_string(unsigned cores);
char *range_counts(const char *const *names, const Number *counts, int count);
Names six_lines(const char *label, const CoreStats *entry);
#endif
