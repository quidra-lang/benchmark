#ifndef REGEX_ENGINE_HPP
#define REGEX_ENGINE_HPP
#include <algorithm>
#include <bitset>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using CharSet = std::bitset<128>;
bool letter(unsigned char);
bool digit(unsigned char);
unsigned char swapped(unsigned char);
CharSet standard_set(unsigned char);
bool char_matches(unsigned char, unsigned char, const std::string &);
bool class_matches(const CharSet &, bool, unsigned char, const std::string &);
bool assertion(const std::string &, const std::string &, int, const std::string &);
struct Instruction {
    std::string op, kind;
    int x = 0, y = 0, number = 0;
    unsigned char character = 0;
    CharSet set;
    bool negated = false;
};
bool consumes(const Instruction &, const std::string &, int, const std::string &);
std::string character_display(unsigned char);
std::string set_notation(const CharSet &, bool = false);
std::string instruction_notation(const Instruction &);
std::string quote(const std::string &);
struct Node {
    std::string kind, value, mode, name;
    unsigned char character = 0;
    CharSet set;
    bool negated = false, positive = false;
    int number = 0, column = 0, lower = 0, upper = -1;
    std::unique_ptr<Node> child;
    std::vector<std::unique_ptr<Node>> children;
};
struct PatternError {
    std::string message;
    int column;
};
struct Pattern {
    std::string name, flags, source;
    std::unique_ptr<Node> root;
    int groups = 0;
    std::map<std::string, int> names;
    std::optional<PatternError> error;
    std::vector<Instruction> program;
    bool pike = true;
};
using Captures = std::vector<int>;
Captures unset_captures(int);
struct BacktrackResult {
    Captures captures;
    int position;
};
struct TooManySteps {};
struct BacktrackVM {
    const Pattern &pattern;
    const std::string &text;
    bool full;
    int64_t steps = 0;
    bool aborted = false;
    std::optional<BacktrackResult> execute(int, int, Captures, bool);
    std::optional<Captures> search(int);
};
struct PikeThread {
    int pc;
    Captures captures;
};
struct ThreadList {
    std::vector<PikeThread> threads;
    std::bitset<300> marks;
};
struct PikeVM {
    const Pattern &pattern;
    const std::string &text;
    bool full;
    int64_t steps = 0;
    void add(ThreadList &, int, const Captures &, int);
    std::optional<Captures> search(int);
};
#endif
