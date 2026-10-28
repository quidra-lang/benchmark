#pragma once
#include <algorithm>
#include <cstdint>
#include <deque>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Integer = std::int64_t;
struct Pair {
    Integer count = 0, words = 0;
    void add(int size) {
        ++count;
        words += size;
    }
    void merge(Pair pair) {
        count += pair.count;
        words += pair.words;
    }
};
struct Object {
    int id, p, d, address = 0, age = 0, moves = 0, references = 0;
    bool present = true, marked = false;
    std::vector<int> fields;
    int size() const {
        return 1 + p + d;
    }
};
struct Collection {
    int number, line, request;
    std::string kind;
    Pair live, freed, moved, promoted;
    Integer stack = 0, work = 0;
    std::pair<int, int> before, after;
};
struct Collector {
    std::string name, type;
    int young = 0, promotion_age = 0;
};
struct Config {
    int heap, width;
    std::vector<Collector> collectors;
    std::vector<std::string> maps;
    std::vector<int> windows;
};
struct Command {
    int line;
    std::string kind, label, error;
    std::vector<int> args;
    int object = 0;
};
Config read_config();
std::vector<Command> read_commands();
struct Heap {
    int size, base = 0, top = 0;
    Collector collector;
    std::vector<Object> objects;
    std::vector<int> roots;
    std::set<int> remembered;
    Integer barriers = 0, remembers = 0;
    Object &object(int id) {
        return objects[id - 1];
    }
    const Object &object(int id) const {
        return objects[id - 1];
    }
};
std::vector<int> address_order(const Heap &);
std::vector<std::pair<int, int>> free_blocks(const Heap &, int, int);
std::vector<std::pair<int, int>> free_blocks(const Heap &);
std::pair<int, int> free_amount(const Heap &);
int first_fit(const Heap &, int, int, int);
int used(const Heap &);
std::string dec2(Integer, Integer);
std::string pct(Integer, Integer);
std::string class_table(const std::vector<int> &);
std::string heap_map(const Heap &, const std::set<int> &);
void marking(Heap &, Collection &);
void sweeping(Heap &, Collection &, bool old_only = false);
void collect_sweep(Heap &, Collection &);
void collect_compact(Heap &, Collection &);
void collect_copy(Heap &, Collection &);
void barrier(Heap &, int, int);
bool collect_generational(Heap &, Collection &);
