#ifndef COHERENCE_HPP
#define COHERENCE_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <memory>
#include <iterator>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Number = std::int64_t;
using Lines = std::vector<std::string>;
template <class... T> std::string text(const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
template <class... T> void line(Lines &out, const T &...values) { out.push_back(text(values...)); }
Lines split(const std::string &source), read_lines(const std::string &path);
std::string join(const Lines &values, const std::string &separator = " ");
void extend(Lines &out, const Lines &other);
bool decimal_integer(const std::string &source, std::size_t maximum = 1000000),
    valid_hex_address(const std::string &source);
Number hex_value(const std::string &source);
std::string hex_address(Number value);
void write_lines(const std::string &filename, const Lines &lines);
struct Scenario {
    std::string name, protocol, l1, l2;
    int order;
};
struct Region {
    std::string name;
    Number first, last;
};
struct Config {
    int cores, line_size, l1_size, l1_ways, l2_size, l2_ways, l1_sets, l2_sets, cap;
    Number t1, t2, tm, tb, interval;
    int top;
    std::vector<Scenario> scenarios;
    std::string primary;
    std::vector<Region> regions;
    std::vector<Number> watch;
};
Config read_config();
struct Entry {
    Number block;
    char state;
};
struct CacheSet {
    std::vector<std::optional<Entry>> entries;
    std::vector<Number> touched;
    std::array<int, 16> bits{};
    Number fills = 0, evictions = 0;
};
class Cache {
    Number clock = 0;
    void touch_way(int row, int way, bool fill);
    int victim(int row) const;

  public:
    int ways;
    std::string replacement;
    std::vector<CacheSet> sets;
    Cache(int number_sets, int ways, std::string replacement);
    int locate(Number block) const;
    char state(Number block) const;
    void change(Number block, char state), touch(Number block);
    std::optional<Entry> remove(Number block), fill(Number block, char state);
    std::string order(int row) const;
};
enum class TransactionKind { None = -1, BusRd, BusRdX, BusUpgr, BusWr, WB };
const std::array<std::string, 5> transaction_names{"BusRd", "BusRdX", "BusUpgr", "BusWr", "WB"};
const std::array<std::string, 6> service_names{"l1", "upgrade", "through", "cache", "l2", "memory"};
const std::array<std::string, 4> miss_names{"compulsory", "capacity", "conflict", "coherence"};
struct RequestTransition {
    TransactionKind transaction;
    char state;
};
struct SnoopTransition {
    char state;
    bool supply = false, flush = false;
};
bool dirty(char state);
RequestTransition requester(const std::string &protocol, char old, char operation, bool other);
SnoopTransition snoop(const std::string &protocol, char old, TransactionKind transaction);
struct Transaction {
    Number number, start;
    int core;
    TransactionKind kind;
    Number block;
    Lines snoops, copies;
    int snoop_hits = 0, invalidations = 0;
    std::optional<int> supplier;
    bool flushed = false, l2_hit = false;
    std::optional<Number> evicted;
    bool dirty_eviction = false;
    std::string source;
};
struct Bus {
    Number latency, free = 0, wait = 0;
    std::vector<Transaction> transactions;
    explicit Bus(Number latency) : latency(latency) {}
    Transaction &assign(int core, TransactionKind kind, Number block, Number requested);
    std::string log_line(const Transaction &transaction, int line_size) const;
};
struct CoreStats {
    Number accesses = 0, reads = 0, writes = 0, hits = 0, misses = 0, fences = 0, latency = 0,
           fence_stall = 0, read_latency = 0, write_latency = 0, finish = 0;
    std::array<Number, 6> miss_counts{}, service{};
    std::array<Number, 5> bus{};
    std::array<Number, 4> snoop{};
};
CoreStats total_counters(const std::vector<CoreStats> &cores);
std::string fraction(Number p, Number q), decimal(Number p, Number q), core_string(unsigned cores);
std::string range_counts(const Lines &names, const std::vector<Number> &counts);
Lines six_lines(const std::string &label, const CoreStats &entry);
#endif
