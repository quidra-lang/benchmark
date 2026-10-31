#include "coherence.hpp"
Cache::Cache(int number_sets, int ways, std::string replacement)
    : ways(ways), replacement(std::move(replacement)), sets(number_sets) {
    for (CacheSet &set : sets) {
        set.entries.resize(ways);
        set.touched.resize(ways);
    }
}
int Cache::locate(Number block) const {
    const CacheSet &row = sets[block % sets.size()];
    for (int way = 0; way < ways; ++way)
        if (row.entries[way] && row.entries[way]->block == block)
            return way;
    return -1;
}
char Cache::state(Number block) const {
    int way = locate(block);
    return way < 0 ? 'I' : sets[block % sets.size()].entries[way]->state;
}
void Cache::change(Number block, char state) {
    int way = locate(block);
    if (way >= 0)
        sets[block % sets.size()].entries[way]->state = state;
}
void Cache::touch_way(int row, int way, bool fill) {
    CacheSet &set = sets[row];
    if (replacement == "LRU" || (replacement == "FIFO" && fill))
        set.touched[way] = ++clock;
    else if (replacement == "PLRU") {
        int lo = 0, hi = ways, node = 1;
        while (hi - lo > 1) {
            int mid = (lo + hi) / 2;
            if (way < mid) {
                set.bits[node] = 1;
                hi = mid;
                node *= 2;
            } else {
                set.bits[node] = 0;
                lo = mid;
                node = 2 * node + 1;
            }
        }
    }
}
void Cache::touch(Number block) {
    int way = locate(block);
    if (way >= 0)
        touch_way(int(block % sets.size()), way, false);
}
int Cache::victim(int row) const {
    const CacheSet &set = sets[row];
    if (replacement == "PLRU") {
        int lo = 0, hi = ways, node = 1;
        while (hi - lo > 1) {
            int mid = (lo + hi) / 2;
            if (set.bits[node] == 0) {
                hi = mid;
                node *= 2;
            } else {
                lo = mid;
                node = 2 * node + 1;
            }
        }
        return lo;
    }
    int best = 0;
    for (int way = 1; way < ways; ++way)
        if (set.touched[way] < set.touched[best])
            best = way;
    return best;
}
std::optional<Entry> Cache::fill(Number block, char state) {
    int row = int(block % sets.size()), way = -1;
    CacheSet &set = sets[row];
    for (int i = 0; i < ways; ++i)
        if (!set.entries[i]) {
            way = i;
            break;
        }
    if (way < 0)
        way = victim(row);
    std::optional<Entry> old = set.entries[way];
    if (old)
        ++set.evictions;
    set.entries[way] = Entry{block, state};
    ++set.fills;
    touch_way(row, way, true);
    return old;
}
std::optional<Entry> Cache::remove(Number block) {
    int way = locate(block);
    if (way < 0)
        return {};
    auto &entry = sets[block % sets.size()].entries[way];
    std::optional<Entry> old = entry;
    entry.reset();
    return old;
}
std::string Cache::order(int row) const {
    const CacheSet &set = sets[row];
    if (replacement == "PLRU") {
        if (ways == 1)
            return "-";
        std::string out;
        for (int i = 1; i < ways; ++i)
            out += char('0' + set.bits[i]);
        return out;
    }
    std::vector<int> active;
    for (int i = 0; i < ways; ++i)
        if (set.entries[i])
            active.push_back(i);
    std::sort(active.begin(), active.end(), [&](int a, int b) {
        return set.touched[a] != set.touched[b] ? set.touched[a] > set.touched[b] : a < b;
    });
    Lines values;
    for (int i : active)
        values.push_back(std::to_string(i));
    return values.empty() ? "-" : join(values);
}
