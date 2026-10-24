#include <algorithm>
#include <array>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
enum class Mode { Chain, Linear, Quadratic, Double, RobinHood, Cuckoo };
const std::array<std::string, 6> modeNames{"CHAIN", "LINEAR", "QUADRATIC", "DOUBLE", "ROBINHOOD", "CUCKOO"};
const std::array<std::string, 25> commands{"CREATE", "MAXLOAD", "MINLOAD", "TRACE", "HASH", "PUT", "ADD", "GET", "DEL", "PROBE", "GEN", "GENDEL", "RESIZE", "CONVERT", "CLEAR", "DUMP", "MAP", "STATS", "KEYS", "TOP", "SCAN", "CLUSTERS", "DIST", "COMPARE", "BENCH"};
struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
struct Item { std::string key; Integer value; };
struct Tombstone {};
using Slot = std::variant<std::monostate, Item, Tombstone>;

std::string name(Mode mode) { return modeNames[static_cast<int>(mode)]; }
Mode parseMode(const std::string& word) {
    for (int i = 0; i < 6; ++i) if (word == modeNames[i]) return static_cast<Mode>(i);
    throw CommandError("BAD MODE " + word);
}
std::string join(const Lines& words, const std::string& separator = " ") {
    std::string result;
    for (const std::string& word : words) { if (!result.empty()) result += separator; result += word; }
    return result;
}
void append(Lines& target, const Lines& source) { target.insert(target.end(), source.begin(), source.end()); }
bool empty(const Slot& slot) { return std::holds_alternative<std::monostate>(slot); }
std::string content(const Slot& slot) {
    if (const Item* item = std::get_if<Item>(&slot)) return item->key;
    return empty(slot) ? "-" : "D";
}
std::string pairText(const Item& item) { return item.key + "=" + std::to_string(item.value); }
char gauge(int value) { return value < 10 ? static_cast<char>('0' + value) : '+'; }
int hash(const std::string& key, int base, int modulus) {
    int value = 0;
    for (unsigned char character : key) value = (value * base + character) % modulus;
    return value;
}
int prime(int value) {
    for (int candidate = std::max(2, value); ; ++candidate) {
        bool valid = true;
        for (int divisor = 2; divisor * divisor <= candidate; ++divisor) {
            if (candidate % divisor == 0) { valid = false; break; }
        }
        if (valid) return candidate;
    }
}
std::string decimal(Integer numerator, Integer denominator) {
    const Integer value = denominator == 0 ? 0 : 100 * numerator / denominator;
    return std::to_string(value / 100) + "." + (value % 100 < 10 ? "0" : "") + std::to_string(value % 100);
}
Lines generatedKeys(int count, int length, Integer seed) {
    Lines keys;
    for (int index = 0; index < count; ++index) {
        std::string key;
        for (int place = 0; place < length; ++place) {
            seed = 48271 * seed % 2147483647;
            key += static_cast<char>('a' + seed % 26);
        }
        keys.push_back(key);
    }
    return keys;
}
Lines histogram(const std::vector<int>& values) {
    std::map<int, int> counts;
    for (int value : values) ++counts[value];
    Lines rows;
    for (const auto& [value, count] : counts) {
        rows.push_back(std::to_string(value) + " " + std::to_string(count) + " " + std::string(std::min(count, 50), '#') + (count > 50 ? "+" : ""));
    }
    return rows;
}
std::vector<int> runs(const std::vector<Slot>& slots, int begin, int count) {
    int firstEmpty = -1;
    for (int i = 0; i < count; ++i) if (empty(slots[begin + i])) { firstEmpty = i; break; }
    if (firstEmpty < 0) return {count};
    std::vector<int> lengths;
    int length = 0;
    for (int offset = 1; offset <= count; ++offset) {
        if (!empty(slots[begin + (firstEmpty + offset) % count])) ++length;
        else if (length > 0) { lengths.push_back(length); length = 0; }
    }
    return lengths;
}
struct Counters {
    Integer probes = 0, rehashes = 0, inserts = 0, updates = 0;
    Integer hits = 0, misses = 0, deletes = 0, absent = 0;
};
struct Search {
    std::optional<Item> item;
    int position = -1, chainIndex = -1, probes = 0;
    std::optional<int> available;
    Lines path;
};
struct Placement {
    bool success = false, reused = false;
    int position = -1, shifted = 0, kicks = 0;
    std::optional<Item> homeless;
    Lines moves;
};
struct Removal { int shifted = 0; Lines moves; };
struct PutResult { bool fresh; Lines rehashes, rows; };
struct DeleteResult { bool deleted; Lines rehashes, rows; };
struct Cost { std::string key; int cost, position; };
struct Metrics { int longest; std::string average; };

class Table {
    std::vector<std::vector<Item>> buckets;
    std::vector<Slot> slots;
public:
    Mode mode;
    int cap, size = 0, tomb = 0;
    Counters counters;
    Table(Mode selected, int capacity)
        : buckets(selected == Mode::Chain ? capacity : 0),
          slots(selected == Mode::Chain ? 0 : capacity * (selected == Mode::Cuckoo ? 2 : 1)),
          mode(selected), cap(capacity) {}
    int slotCount() const { return cap * (mode == Mode::Cuckoo ? 2 : 1); }
    bool usesTombstones() const { return mode == Mode::Linear || mode == Mode::Quadratic || mode == Mode::Double; }
    std::string position(int index) const {
        return mode == Mode::Cuckoo ? "T" + std::to_string(index / cap + 1) + "." + std::to_string(index % cap) : std::to_string(index);
    }
    int distance(const std::string& key, int index) const { return (index - hash(key, 31, cap) + cap) % cap; }
    std::vector<Item> items() const {
        std::vector<Item> result;
        if (mode == Mode::Chain) {
            for (const std::vector<Item>& bucket : buckets) result.insert(result.end(), bucket.begin(), bucket.end());
        } else {
            for (const Slot& slot : slots) if (const Item* item = std::get_if<Item>(&slot)) result.push_back(*item);
        }
        return result;
    }
    Placement place(const Item& item, const Search* initial = nullptr, bool tracing = false) {
        Placement result;
        if (mode == Mode::Chain) {
            result.position = hash(item.key, 31, cap);
            buckets[result.position].push_back(item);
            result.success = true;
            return result;
        }
        if (usesTombstones()) {
            const Search fresh = initial ? Search{} : search(item.key);
            const Search& found = initial ? *initial : fresh;
            if (!found.available) { result.homeless = item; return result; }
            result.position = *found.available;
            result.reused = std::holds_alternative<Tombstone>(slots[result.position]);
            slots[result.position] = item;
            if (result.reused) --tomb;
            result.success = true;
            return result;
        }
        Item current = item;
        if (mode == Mode::RobinHood) {
            int index = hash(item.key, 31, cap), dist = 0;
            std::optional<int> from;
            for (;;) {
                Slot& slot = slots[index];
                if (empty(slot)) {
                    slot = current;
                    if (tracing && from) result.moves.push_back("SHIFT " + current.key + " " + std::to_string(*from) + " -> " + std::to_string(index));
                    if (result.position < 0) result.position = index;
                    result.success = true;
                    return result;
                }
                const Item occupant = std::get<Item>(slot);
                const int otherDistance = distance(occupant.key, index);
                if (otherDistance < dist) {
                    slot = current;
                    if (tracing && from) result.moves.push_back("SHIFT " + current.key + " " + std::to_string(*from) + " -> " + std::to_string(index));
                    if (result.position < 0) result.position = index;
                    current = occupant;
                    from = index;
                    dist = otherDistance;
                    ++result.shifted;
                }
                index = (index + 1) % cap;
                ++dist;
            }
        }
        int part = 0;
        for (;;) {
            const int index = part * cap + hash(current.key, part == 0 ? 31 : 37, cap);
            Slot& slot = slots[index];
            if (empty(slot)) {
                slot = current;
                result.success = true;
                result.position = search(item.key).position;
                return result;
            }
            if (result.kicks == cap) { result.homeless = current; return result; }
            const Item occupant = std::get<Item>(slot);
            slot = current;
            ++result.kicks;
            if (tracing) result.moves.push_back("KICK " + occupant.key + " " + position(index));
            current = occupant;
            part = 1 - part;
        }
    }
    Removal remove(const Search& found, bool tracing) {
        Removal result;
        if (mode == Mode::Chain) {
            std::vector<Item>& bucket = buckets[found.position];
            bucket.erase(bucket.begin() + found.chainIndex);
        } else if (usesTombstones()) {
            slots[found.position] = Tombstone{};
            ++tomb;
        } else {
            slots[found.position] = std::monostate{};
            if (mode == Mode::RobinHood) {
                int next = (found.position + 1) % cap;
                while (!empty(slots[next])) {
                    const Item item = std::get<Item>(slots[next]);
                    if (distance(item.key, next) == 0) break;
                    const int destination = (next - 1 + cap) % cap;
                    slots[destination] = item;
                    slots[next] = std::monostate{};
                    if (tracing) result.moves.push_back("SHIFT " + item.key + " " + std::to_string(next) + " -> " + std::to_string(destination));
                    ++result.shifted;
                    next = (next + 1) % cap;
                }
            }
        }
        --size;
        return result;
    }
    static std::unique_ptr<Table> rebuild(const std::vector<Item>& items, Mode mode, int capacity) {
        std::unique_ptr<Table> table = std::make_unique<Table>(mode, capacity);
        for (const Item& item : items) {
            if (!table->place(item).success) return nullptr;
            ++table->size;
        }
        return table;
    }
    void adopt(Table&& replacement) {
        const Counters saved = counters;
        *this = std::move(replacement);
        counters = saved;
    }
    std::string automatic(const std::string& reason, int capacity, const std::optional<Item>& pending = std::nullopt) {
        std::vector<Item> listed = items();
        if (pending) listed.push_back(*pending);
        const int old = cap;
        for (;;) {
            std::unique_ptr<Table> replacement = rebuild(listed, mode, capacity);
            if (replacement) {
                adopt(std::move(*replacement));
                ++counters.rehashes;
                return "REHASH " + reason + " " + std::to_string(old) + " -> " + std::to_string(cap);
            }
            capacity = prime(2 * capacity);
        }
    }
    Lines loadCheck(int maxLoad) {
        const Integer threshold = maxLoad * slotCount();
        if (100LL * (size + tomb) <= threshold) return {};
        const bool grow = 200LL * size > threshold;
        return {automatic(grow ? "load" : "tomb", grow ? prime(2 * cap) : cap)};
    }
    Lines shrinkCheck(int minLoad, int maxLoad) {
        const int capacity = prime(cap / 2), newSlots = capacity * (mode == Mode::Cuckoo ? 2 : 1);
        if (100LL * size >= minLoad * slotCount() || capacity >= cap || 100LL * size > maxLoad * newSlots) return {};
        std::unique_ptr<Table> replacement = rebuild(items(), mode, capacity);
        if (!replacement) return {};
        const int old = cap;
        adopt(std::move(*replacement));
        ++counters.rehashes;
        return {"REHASH shrink " + std::to_string(old) + " -> " + std::to_string(capacity)};
    }
    PutResult put(const std::string& key, Integer value, const std::string& command, int maxLoad, bool tracing = false) {
        const Search found = search(key, tracing);
        const Lines trace = tracing ? Lines{"PATH " + (found.path.empty() ? "none" : join(found.path))} : Lines{};
        counters.probes += found.probes;
        if (found.item) {
            const Integer old = found.item->value, next = command == "ADD" ? old + value : value;
            const Item item{key, next};
            if (mode == Mode::Chain) buckets[found.position][found.chainIndex] = item;
            else slots[found.position] = item;
            ++counters.updates;
            Lines rows{command + " " + pairText(item) + " UPDATED old=" + std::to_string(old) + " at=" + position(found.position) + " probes=" + std::to_string(found.probes)};
            append(rows, trace);
            return {false, {}, rows};
        }
        const Item item{key, value};
        const Placement placed = place(item, &found, tracing);
        ++size;
        ++counters.inserts;
        std::string row = command + " " + pairText(item) + " NEW";
        if (placed.success) {
            row += " at=" + position(placed.position) + " probes=" + std::to_string(found.probes);
            if (placed.reused) row += " reused";
            if (mode == Mode::RobinHood) row += " shifted=" + std::to_string(placed.shifted);
            if (mode == Mode::Cuckoo) row += " kicks=" + std::to_string(placed.kicks);
        } else {
            row += " probes=" + std::to_string(found.probes);
            row += mode == Mode::Cuckoo ? " kicks=" + std::to_string(placed.kicks) + " failed" : " full";
        }
        Lines rehashes;
        if (!placed.success) rehashes.push_back(automatic(mode == Mode::Cuckoo ? "kicks" : "full", prime(2 * cap), placed.homeless));
        append(rehashes, loadCheck(maxLoad));
        Lines rows{row};
        append(rows, trace); append(rows, placed.moves); append(rows, rehashes);
        return {true, rehashes, rows};
    }
    Lines get(const std::string& key, bool tracing) {
        const Search found = search(key, tracing);
        counters.probes += found.probes;
        std::string row;
        if (found.item) { ++counters.hits; row = "GET " + pairText(*found.item) + " at=" + position(found.position); }
        else { ++counters.misses; row = "GET " + key + " NOT FOUND"; }
        Lines rows{row + " probes=" + std::to_string(found.probes)};
        if (tracing) rows.push_back("PATH " + (found.path.empty() ? "none" : join(found.path)));
        return rows;
    }
    DeleteResult erase(const std::string& key, int minLoad, int maxLoad, bool tracing = false) {
        const Search found = search(key, tracing);
        const Lines trace = tracing ? Lines{"PATH " + (found.path.empty() ? "none" : join(found.path))} : Lines{};
        counters.probes += found.probes;
        if (!found.item) {
            ++counters.absent;
            Lines rows{"DEL " + key + " NOT FOUND probes=" + std::to_string(found.probes)};
            append(rows, trace);
            return {false, {}, rows};
        }
        const Removal removed = remove(found, tracing);
        ++counters.deletes;
        std::string row = "DEL " + key + " OK at=" + position(found.position) + " probes=" + std::to_string(found.probes);
        if (mode == Mode::RobinHood) row += " shifted=" + std::to_string(removed.shifted);
        const Lines rehashes = shrinkCheck(minLoad, maxLoad);
        Lines rows{row};
        append(rows, trace); append(rows, removed.moves); append(rows, rehashes);
        return {true, rehashes, rows};
    }
    Search search(const std::string& key, bool tracing = false) const {
        Search result;
        const int first = hash(key, 31, cap);
        const auto examine = [&](int index, const Slot& slot) {
            ++result.probes;
            if (tracing) result.path.push_back(position(index) + ":" + content(slot));
        };
        const auto found = [&](const Item& item, int index, int chainIndex = -1) {
            result.item = item; result.position = index; result.chainIndex = chainIndex;
        };
        if (mode == Mode::Chain) {
            const std::vector<Item>& bucket = buckets[first];
            for (int i = 0; i < static_cast<int>(bucket.size()); ++i) {
                examine(first, bucket[i]);
                if (bucket[i].key == key) { found(bucket[i], first, i); break; }
            }
            return result;
        }
        if (mode == Mode::Cuckoo) {
            for (int index : {first, cap + hash(key, 37, cap)}) {
                examine(index, slots[index]);
                const Item* item = std::get_if<Item>(&slots[index]);
                if (item && item->key == key) { found(*item, index); break; }
            }
            return result;
        }
        const int step = mode == Mode::Double ? 1 + hash(key, 37, cap - 1) : 1;
        for (int i = 0; i < cap; ++i) {
            const int offset = mode == Mode::Quadratic ? i * i : i * step;
            const int index = (first + offset) % cap;
            const Slot& slot = slots[index];
            examine(index, slot);
            if (empty(slot)) { if (!result.available) result.available = index; break; }
            if (std::holds_alternative<Tombstone>(slot)) { if (!result.available) result.available = index; continue; }
            const Item& item = std::get<Item>(slot);
            if (item.key == key) { found(item, index); break; }
            if (mode == Mode::RobinHood && distance(item.key, index) < i) break;
        }
        return result;
    }
    std::vector<Cost> costs() const {
        std::vector<Cost> result;
        if (mode == Mode::Chain) {
            for (int index = 0; index < cap; ++index) {
                const std::vector<Item>& bucket = buckets[index];
                for (int i = 0; i < static_cast<int>(bucket.size()); ++i) result.push_back({bucket[i].key, i + 1, index});
            }
        } else {
            for (int index = 0; index < slotCount(); ++index) if (const Item* item = std::get_if<Item>(&slots[index])) {
                const int cost = mode == Mode::Cuckoo ? (index < cap ? 1 : 2)
                    : mode == Mode::RobinHood || mode == Mode::Linear ? distance(item->key, index) + 1 : search(item->key).probes;
                result.push_back({item->key, cost, index});
            }
        }
        return result;
    }
    Metrics metrics() const {
        int longest = 0;
        Integer total = 0;
        for (const Cost& record : costs()) { longest = std::max(longest, record.cost); total += record.cost; }
        return {longest, decimal(total, size)};
    }
    Lines dump() const {
        Lines rows{"DUMP " + name(mode) + " cap=" + std::to_string(cap) + " size=" + std::to_string(size) + " tomb=" + std::to_string(tomb)};
        if (mode == Mode::Chain) {
            for (int index = 0; index < cap; ++index) {
                Lines words{std::to_string(index)};
                for (const Item& item : buckets[index]) words.push_back(pairText(item));
                if (buckets[index].empty()) words.push_back("-");
                rows.push_back(join(words));
            }
        } else {
            for (int index = 0; index < slotCount(); ++index) {
                const std::string prefix = mode == Mode::Cuckoo ? "T" + std::to_string(index / cap + 1) + " " + std::to_string(index % cap) : std::to_string(index);
                const Item* item = std::get_if<Item>(&slots[index]);
                std::string value = item ? pairText(*item) : content(slots[index]);
                if (mode == Mode::RobinHood && item) value += " d=" + std::to_string(distance(item->key, index));
                rows.push_back(prefix + " " + value);
            }
        }
        return rows;
    }
    Lines map() const {
        Lines rows{"MAP " + name(mode) + " cap=" + std::to_string(cap)};
        std::vector<int> costBySlot(slotCount());
        if (mode != Mode::Chain) for (const Cost& record : costs()) costBySlot[record.position] = record.cost;
        for (int part = 0; part < (mode == Mode::Cuckoo ? 2 : 1); ++part) {
            std::string characters;
            for (int index = 0; index < cap; ++index) {
                if (mode == Mode::Chain) characters += buckets[index].empty() ? '.' : gauge(static_cast<int>(buckets[index].size()));
                else {
                    const int flat = part * cap + index;
                    const Slot& slot = slots[flat];
                    characters += empty(slot) ? '.' : std::holds_alternative<Tombstone>(slot) ? 'D'
                        : mode == Mode::Cuckoo ? '#' : gauge(costBySlot[flat] - 1);
                }
            }
            for (int index = 0; index < cap; index += 40) {
                std::ostringstream line;
                if (mode == Mode::Cuckoo) line << "T" << part + 1 << ' ';
                line << std::setw(5) << std::setfill('0') << index << ' ' << characters.substr(index, 40);
                rows.push_back(line.str());
            }
        }
        return rows;
    }
    Lines statistics() const {
        const Metrics values = metrics();
        return {"STATS " + name(mode) + " size=" + std::to_string(size) + " cap=" + std::to_string(cap)
            + " slots=" + std::to_string(slotCount()) + " tomb=" + std::to_string(tomb) + " load=" + decimal(100LL * size, slotCount())
            + "% longest=" + std::to_string(values.longest) + " avg=" + values.average + " probes=" + std::to_string(counters.probes) + " rehashes=" + std::to_string(counters.rehashes),
            "OPS inserts=" + std::to_string(counters.inserts) + " updates=" + std::to_string(counters.updates)
            + " hits=" + std::to_string(counters.hits) + " misses=" + std::to_string(counters.misses)
            + " deletes=" + std::to_string(counters.deletes) + " absent=" + std::to_string(counters.absent)};
    }
    Lines scan(int cursor, int limit) const {
        Lines keys;
        int next = cursor;
        while (next < slotCount() && static_cast<int>(keys.size()) < limit) {
            if (mode == Mode::Chain) {
                for (const Item& item : buckets[next]) keys.push_back(item.key);
            } else if (const Item* item = std::get_if<Item>(&slots[next])) keys.push_back(item->key);
            ++next;
        }
        if (next == slotCount()) next = 0;
        Lines words{"SCAN next=" + std::to_string(next)};
        append(words, keys);
        return {join(words)};
    }
    Lines clusters() const {
        std::vector<int> lengths;
        if (mode == Mode::Chain) {
            for (const std::vector<Item>& bucket : buckets) if (!bucket.empty()) lengths.push_back(static_cast<int>(bucket.size()));
        } else {
            lengths = runs(slots, 0, cap);
            if (mode == Mode::Cuckoo) {
                const std::vector<int> second = runs(slots, cap, cap);
                lengths.insert(lengths.end(), second.begin(), second.end());
            }
        }
        const int longest = lengths.empty() ? 0 : *std::max_element(lengths.begin(), lengths.end());
        Lines rows{"CLUSTERS runs=" + std::to_string(lengths.size()) + " longest=" + std::to_string(longest)};
        append(rows, histogram(lengths));
        return rows;
    }
    Lines distribution() const {
        std::vector<int> values;
        for (const Cost& record : costs()) values.push_back(record.cost);
        const int longest = values.empty() ? 0 : *std::max_element(values.begin(), values.end());
        Lines rows{"DIST keys=" + std::to_string(size) + " longest=" + std::to_string(longest)};
        append(rows, histogram(values));
        return rows;
    }
};

void checkCapacity(int capacity) { if (capacity < 2 || capacity > 10000) throw CommandError("BAD CAPACITY"); }
void checkGeneration(int count, int length, Integer seed) {
    if (count < 1 || count > 500 || length < 1 || length > 10 || seed < 1 || seed > 2147483646) throw CommandError("BAD ARGUMENT");
}
class Simulator {
    std::optional<Table> table;
    int maxLoad = 75, minLoad = 0;
    bool tracing = false;
    Lines compare(int capacity) const {
        std::vector<Item> listed = table->items();
        std::sort(listed.begin(), listed.end(), [](const Item& a, const Item& b) { return a.key < b.key; });
        Lines rows{"COMPARE keys=" + std::to_string(listed.size()) + " cap=" + std::to_string(capacity)};
        for (int index = 0; index < 6; ++index) {
            const Mode mode = static_cast<Mode>(index);
            Table experiment(mode, capacity);
            for (const Item& item : listed) experiment.put(item.key, item.value, "PUT", maxLoad);
            const Metrics values = experiment.metrics();
            rows.push_back(name(mode) + " cap=" + std::to_string(experiment.cap) + " longest=" + std::to_string(values.longest)
                + " avg=" + values.average + " probes=" + std::to_string(experiment.counters.probes) + " rehashes=" + std::to_string(experiment.counters.rehashes));
        }
        return rows;
    }
    Lines bench(int capacity, int count, int length, Integer seed) const {
        const Lines keys = generatedKeys(2 * count, length, seed);
        Lines rows{"BENCH cap=" + std::to_string(capacity) + " count=" + std::to_string(count) + " len=" + std::to_string(length) + " seed=" + std::to_string(seed)};
        for (int index = 0; index < 6; ++index) {
            const Mode mode = static_cast<Mode>(index);
            Table experiment(mode, capacity);
            for (int i = 0; i < count; ++i) experiment.put(keys[i], i + 1, "PUT", maxLoad);
            int misses = 0;
            Integer probes = 0;
            for (int i = count; i < 2 * count; ++i) {
                const Search found = experiment.search(keys[i]);
                if (!found.item) { ++misses; probes += found.probes; }
            }
            rows.push_back(name(mode) + " cap=" + std::to_string(experiment.cap) + " keys=" + std::to_string(experiment.size)
                + " hit=" + experiment.metrics().average + " misses=" + std::to_string(misses) + " miss=" + decimal(probes, misses)
                + " rehashes=" + std::to_string(experiment.counters.rehashes));
        }
        return rows;
    }
public:
    Lines execute(const std::string& line) {
        std::istringstream input(line);
        std::string command, word;
        input >> command;
        Lines args;
        while (input >> word) args.push_back(word);
        if (std::find(commands.begin(), commands.end(), command) == commands.end()) throw CommandError("UNKNOWN COMMAND " + command);
        if (command == "CREATE") {
            const Mode mode = parseMode(args[0]);
            const int capacity = std::stoi(args[1]);
            checkCapacity(capacity);
            table.emplace(mode, prime(capacity));
            return {"CREATE " + name(mode) + " cap=" + std::to_string(table->cap)};
        }
        if (command == "MAXLOAD" || command == "MINLOAD") {
            const int value = std::stoi(args[0]);
            const bool maximum = command == "MAXLOAD";
            if (maximum ? value < 10 || value > 95 : value > 40) throw CommandError("BAD LOAD");
            if (maximum) maxLoad = value;
            else minLoad = value;
            return {command + " " + std::to_string(value)};
        }
        if (command == "TRACE") {
            if (args[0] != "ON" && args[0] != "OFF") throw CommandError("BAD ARGUMENT");
            tracing = args[0] == "ON";
            return {"TRACE " + args[0]};
        }
        if (command == "HASH") {
            const std::string& key = args[0];
            const int capacity = std::stoi(args[1]);
            checkCapacity(capacity);
            return {"HASH " + key + " m=" + std::to_string(capacity) + " h31=" + std::to_string(hash(key, 31, capacity))
                + " h37=" + std::to_string(hash(key, 37, capacity)) + " step=" + std::to_string(1 + hash(key, 37, capacity - 1))};
        }
        if (command == "BENCH") {
            const int capacity = std::stoi(args[0]), count = std::stoi(args[1]), length = std::stoi(args[2]);
            const Integer seed = std::stoll(args[3]);
            checkCapacity(capacity);
            checkGeneration(count, length, seed);
            return bench(prime(capacity), count, length, seed);
        }
        if (!table) throw CommandError("NO TABLE");
        Table& current = *table;
        if (command == "PUT" || command == "ADD") return current.put(args[0], std::stoll(args[1]), command, maxLoad, tracing).rows;
        if (command == "GET") return current.get(args[0], tracing);
        if (command == "DEL") return current.erase(args[0], minLoad, maxLoad, tracing).rows;
        if (command == "PROBE") {
            const Search found = current.search(args[0], true);
            Lines words{"PROBE " + args[0]};
            append(words, found.path);
            words.push_back(std::string(found.item ? "FOUND" : "MISS") + " probes=" + std::to_string(found.probes));
            return {join(words)};
        }
        if (command == "GEN" || command == "GENDEL") {
            const int count = std::stoi(args[0]), length = std::stoi(args[1]);
            const Integer seed = std::stoll(args[2]);
            checkGeneration(count, length, seed);
            const Lines keys = generatedKeys(count, length, seed);
            Lines rows;
            int successes = 0;
            for (int i = 0; i < count; ++i) {
                if (command == "GEN") {
                    const PutResult result = current.put(keys[i], i + 1, "PUT", maxLoad);
                    successes += result.fresh;
                    append(rows, result.rehashes);
                } else {
                    const DeleteResult result = current.erase(keys[i], minLoad, maxLoad);
                    successes += result.deleted;
                    append(rows, result.rehashes);
                }
            }
            rows.push_back(command + " " + std::to_string(count) + (command == "GEN" ? " new=" : " deleted=")
                + std::to_string(successes) + (command == "GEN" ? " updated=" : " missing=") + std::to_string(count - successes));
            return rows;
        }
        if (command == "RESIZE" || command == "CONVERT") {
            Mode mode = current.mode;
            int capacity = current.cap;
            if (command == "RESIZE") { capacity = std::stoi(args[0]); checkCapacity(capacity); capacity = prime(capacity); }
            else mode = parseMode(args[0]);
            const int slots = capacity * (mode == Mode::Cuckoo ? 2 : 1);
            if (100LL * current.size > maxLoad * slots) throw CommandError("TOO SMALL");
            std::unique_ptr<Table> replacement = Table::rebuild(current.items(), mode, capacity);
            if (!replacement) throw CommandError("REBUILD FAILED");
            const std::string row = command == "RESIZE" ? "RESIZE " + std::to_string(current.cap) + " -> " + std::to_string(capacity)
                : "CONVERT " + name(current.mode) + " -> " + name(mode) + " cap=" + std::to_string(capacity);
            current.adopt(std::move(*replacement));
            return {row};
        }
        if (command == "CLEAR") {
            const int size = current.size;
            current.adopt(Table(current.mode, current.cap));
            return {"CLEAR " + std::to_string(size)};
        }
        if (command == "DUMP") return current.dump();
        if (command == "MAP") return current.map();
        if (command == "STATS") return current.statistics();
        if (command == "KEYS") {
            Lines keys;
            for (const Item& item : current.items()) keys.push_back(item.key);
            std::sort(keys.begin(), keys.end());
            Lines words{"KEYS " + std::to_string(current.size)};
            append(words, keys);
            return {join(words)};
        }
        if (command == "TOP") {
            const int limit = std::stoi(args[0]);
            if (limit < 1 || limit > 100) throw CommandError("BAD ARGUMENT");
            std::vector<Cost> records = current.costs();
            std::sort(records.begin(), records.end(), [](const Cost& a, const Cost& b) { return a.cost != b.cost ? a.cost > b.cost : a.key < b.key; });
            const int count = std::min(limit, static_cast<int>(records.size()));
            Lines rows{"TOP " + std::to_string(count)};
            for (int i = 0; i < count; ++i) rows.push_back(records[i].key + " cost=" + std::to_string(records[i].cost) + " at=" + current.position(records[i].position));
            return rows;
        }
        if (command == "SCAN") {
            const int cursor = std::stoi(args[0]), limit = std::stoi(args[1]);
            if (limit < 1 || limit > 100) throw CommandError("BAD ARGUMENT");
            if (cursor >= current.slotCount()) throw CommandError("BAD CURSOR");
            return current.scan(cursor, limit);
        }
        if (command == "CLUSTERS") return current.clusters();
        if (command == "DIST") return current.distribution();
        if (command == "COMPARE") {
            const int capacity = std::stoi(args[0]);
            checkCapacity(capacity);
            return compare(prime(capacity));
        }
        throw std::logic_error("Unhandled command " + command);
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    if (!(std::cin >> count)) return 0;
    std::string line;
    std::getline(std::cin, line);
    Simulator simulator;
    for (int index = 0; index < count; ++index) {
        std::getline(std::cin, line);
        try { for (const std::string& row : simulator.execute(line)) std::cout << row << '\n'; }
        catch (const CommandError& error) { std::cout << "ERROR " << error.what() << '\n'; }
        std::cout.flush();
    }
}
