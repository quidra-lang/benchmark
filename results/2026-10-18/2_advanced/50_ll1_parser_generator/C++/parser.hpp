#pragma once
#include <algorithm>
#include <array>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <memory>
#include <numeric>
#include <queue>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Lines = std::vector<std::string>;
using Sequence = std::vector<std::string>;
using Alternatives = std::vector<Sequence>;
using Ints = std::vector<int>;
bool nonterminal(const std::string &symbol);
std::string notation(const Sequence &sequence);
std::string production_text(const std::string &lhs, const Sequence &rhs);
struct Grammar {
    Lines order;
    std::map<std::string, Alternatives> rules;
    std::string start;
};
struct Parsed {
    Grammar grammar;
    Lines diagnostics;
    bool declarations = false;
    std::set<std::string> declared;
    std::map<std::string, int> word_first;
};
Parsed read_grammar(const Lines &lines);
Lines eliminate_recursion(Grammar &grammar);
Lines left_factor(Grammar &grammar);
struct TerminalOrder {
    bool operator()(const std::string &a, const std::string &b) const {
        return a == "$" ? false : b == "$" ? true : a < b;
    }
};
using Terminals = std::set<std::string, TerminalOrder>;
struct Sets {
    std::map<std::string, bool> nullable;
    std::map<std::string, Terminals> first, follow;
    int nullable_passes = 0, first_passes = 0, follow_passes = 0;
};
std::pair<Terminals, bool> first_sequence(const Sequence &sequence, const Sets &sets);
Sets first_follow(const Grammar &grammar);
struct Production {
    std::string lhs;
    Sequence rhs;
};
struct Table {
    std::vector<Production> productions;
    std::map<std::string, Ints> by_lhs;
    std::vector<Terminals> predict, first;
    std::map<std::pair<std::string, std::string>, Ints> cells;
    Lines terminals;
    std::map<std::pair<std::string, std::string>, int> chosen;
    int conflicts = 0;
};
Table build_table(const Grammar &grammar, const Sets &sets);
std::string reason(const Table &table, int production, const std::string &terminal);
std::string conflict_kind(const Table &table, const Ints &cell, const std::string &terminal);
struct InputToken {
    std::string name;
    int position;
};
struct Tree {
    std::string symbol, mark;
    std::vector<std::unique_ptr<Tree>> children;
};
enum class Action { accept, match, predict, skip, pop, missing };
struct Step {
    Sequence stack, input;
    std::string top, current;
    int position = 0, production = -1;
    Action action;
};
struct Parse {
    std::vector<Step> steps;
    Ints left_parse;
    std::unique_ptr<Tree> tree;
    int matches = 0, max_stack = 0, skip = 0, pop = 0, missing = 0;
};
Parse drive(const Grammar &grammar, const Sets &sets, const Table &table, std::vector<InputToken> tokens);
