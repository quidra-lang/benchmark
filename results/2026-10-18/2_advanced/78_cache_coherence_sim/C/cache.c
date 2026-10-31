#include "coherence.h"
const char *replacement_names[3] = {"LRU", "FIFO", "PLRU"};
Cache cache_create(int sets, int ways, Replacement replacement) {
    return (Cache){.set_count = sets,
                   .ways = ways,
                   .replacement = replacement,
                   .sets = allocate((size_t)sets * sizeof(CacheSet))};
}
int cache_locate(const Cache *cache, Number block) {
    const CacheSet *row = &cache->sets[block % cache->set_count];
    for (int i = 0; i < cache->ways; ++i)
        if (row->entries[i].valid && row->entries[i].block == block)
            return i;
    return -1;
}
char cache_state(const Cache *cache, Number block) {
    int way = cache_locate(cache, block);
    return way < 0 ? 'I' : cache->sets[block % cache->set_count].entries[way].state;
}
void cache_change(Cache *cache, Number block, char state) {
    int way = cache_locate(cache, block);
    if (way >= 0)
        cache->sets[block % cache->set_count].entries[way].state = state;
}
static void touch_way(Cache *cache, int row, int way, bool fill) {
    CacheSet *set = &cache->sets[row];
    if (cache->replacement == LRU || (cache->replacement == FIFO && fill))
        set->touched[way] = ++cache->clock;
    else if (cache->replacement == PLRU) {
        int lo = 0, hi = cache->ways, node = 1;
        while (hi - lo > 1) {
            int mid = (lo + hi) / 2;
            if (way < mid) {
                set->bits[node] = 1;
                hi = mid;
                node *= 2;
            } else {
                set->bits[node] = 0;
                lo = mid;
                node = node * 2 + 1;
            }
        }
    }
}
void cache_touch(Cache *cache, Number block) {
    int way = cache_locate(cache, block);
    if (way >= 0)
        touch_way(cache, (int)(block % cache->set_count), way, false);
}
static int victim(const Cache *cache, int row) {
    const CacheSet *set = &cache->sets[row];
    if (cache->replacement == PLRU) {
        int lo = 0, hi = cache->ways, node = 1;
        while (hi - lo > 1) {
            int mid = (lo + hi) / 2;
            if (set->bits[node] == 0) {
                hi = mid;
                node *= 2;
            } else {
                lo = mid;
                node = node * 2 + 1;
            }
        }
        return lo;
    }
    int best = 0;
    for (int i = 1; i < cache->ways; ++i)
        if (set->touched[i] < set->touched[best])
            best = i;
    return best;
}
Entry cache_fill(Cache *cache, Number block, char state) {
    int row = (int)(block % cache->set_count), way = -1;
    CacheSet *set = &cache->sets[row];
    for (int i = 0; i < cache->ways; ++i)
        if (!set->entries[i].valid) {
            way = i;
            break;
        }
    if (way < 0)
        way = victim(cache, row);
    Entry old = set->entries[way];
    set->evictions += old.valid;
    set->entries[way] = (Entry){true, block, state};
    ++set->fills;
    touch_way(cache, row, way, true);
    return old;
}
Entry cache_remove(Cache *cache, Number block) {
    int way = cache_locate(cache, block);
    if (way < 0)
        return (Entry){0};
    Entry *entry = &cache->sets[block % cache->set_count].entries[way], old = *entry;
    entry->valid = false;
    return old;
}
char *cache_order(const Cache *cache, int row) {
    const CacheSet *set = &cache->sets[row];
    if (cache->replacement == PLRU) {
        if (cache->ways == 1)
            return "-";
        char *out = allocate((size_t)cache->ways);
        for (int i = 1; i < cache->ways; ++i)
            out[i - 1] = (char)('0' + set->bits[i]);
        return out;
    }
    int active[16], count = 0;
    for (int way = 0; way < cache->ways; ++way)
        if (set->entries[way].valid) {
            int at = count++;
            while (at > 0 &&
                   (set->touched[active[at - 1]] < set->touched[way] ||
                    (set->touched[active[at - 1]] == set->touched[way] && active[at - 1] > way))) {
                active[at] = active[at - 1];
                --at;
            }
            active[at] = way;
        }
    Names values = {0};
    for (int i = 0; i < count; ++i)
        Names_add(&values, format("%d", active[i]));
    return count ? join(values, " ") : "-";
}
