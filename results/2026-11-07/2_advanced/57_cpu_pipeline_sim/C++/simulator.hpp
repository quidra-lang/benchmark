#ifndef SIMULATOR_HPP
#define SIMULATOR_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using I = std::int64_t;
using Lines = std::vector<std::string>;
inline constexpr std::array<const char *, 7> classes{"ALU",    "MUL",  "LOAD", "STORE",
                                                     "BRANCH", "JUMP", "NOP"};
inline constexpr std::array<const char *, 4> causes{"control", "structural", "load_use", "raw"};
inline constexpr std::array<const char *, 3> misses{"direction", "btb_miss", "wrong_target"};
inline constexpr std::array<const char *, 5> stages{"IF", "ID", "EX", "MEM", "WB"};
enum Class { alu, multiply, load, store, branch, jump, nop };
struct Instruction {
    I pc = 0, target = 0, address = 0, next = 0;
    Class kind = alu;
    int rd = -1, rs1 = -1, rs2 = -1, line = 0;
    bool taken = false;
    bool control() const { return kind == branch || kind == jump; }
};
struct Predictor {
    std::string name, scheme;
    std::array<int, 4> parameters{};
};
struct Variant {
    std::string name;
    bool forwarding, id;
    int latency;
};
struct Config {
    int btb = 0, ras = 0, start = 0, end = 0, top = 0, interval = 0;
    std::vector<Predictor> predictors;
    std::vector<Variant> variants;
    std::string primary_variant, primary_predictor;
};
struct Input {
    Lines trace;
    Config config;
};
Input read_inputs();
std::optional<I> parse_hex(const std::string &text);
int parse_register(const std::string &text);
using Sources = std::vector<std::array<int, 2>>;
Sources dependencies(const std::vector<Instruction> &instructions);
bool id_resolved(const Instruction &instruction, const Variant &variant);
struct Timing {
    int f = 0, d = 0, x = 0, m = 0, w = 0;
};
int ready_cycle(const Instruction &consumer, const Instruction &producer, const Timing &time,
                const Variant &variant);
int forwarding_path(const Instruction &consumer, const Timing *producer, const Timing &time,
                    const Variant &variant);
struct Record {
    int cause, cycles, responsible, waiting, producer;
};
struct Run {
    std::vector<Timing> timings;
    std::vector<Record> records;
    int cycles = 0;
    std::array<I, 4> stalls{}, events{};
};
Run simulate(const std::vector<Instruction> &instructions, const Sources &sources,
             const Variant &variant, const std::vector<bool> &mispredicted);
class BTB {
    std::vector<std::optional<std::pair<I, I>>> entries;

  public:
    explicit BTB(int count) : entries(count) {}
    std::optional<I> lookup(I pc) const;
    void insert(I pc, I target);
};
class RAS {
    int depth;
    std::vector<I> stack;

  public:
    explicit RAS(int count) : depth(count) {}
    void push(I value);
    std::optional<I> pop();
};
class DirectionPredictor {
    Predictor definition;
    std::vector<int> table, local, global, chooser;
    int history = 0;

  public:
    explicit DirectionPredictor(Predictor value);
    bool prediction(I pc, I target) const;
    void update(I pc, bool taken);
    int bits() const;
};
std::string decimal(I p, I q), percentage(I p, I q), fraction(I p, I q), hexadecimal(I value),
    register_name(int value);
std::string cycle_heading(int start, int end);
std::string diagram_row(int number, I pc, const std::string &kind, const std::string &characters,
                        const std::string &annotation);
void save(const std::string &name, const Lines &lines);
template <typename... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
