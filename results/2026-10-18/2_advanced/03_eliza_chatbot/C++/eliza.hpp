#pragma once
#include <array>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

using Words = std::vector<std::string>;
using Clauses = std::vector<Words>;
using Groups = std::map<std::string, std::set<std::string>>;
using Substitutions = std::map<std::string, Words>;

Words words(const std::string& text);
std::string join(const Words& values, const std::string& separator = " ");
Words readLines(const std::string& path);
bool word(const std::string& text);
bool reference(const std::string& text);
bool wildcard(const std::string& element);
struct Diagnostic { int line; std::string code, message; };
struct Substitution { std::string source; Words replacement; int line; };
struct Group { std::string name; std::set<std::string> members; int line; };
struct Item { std::string kind, text; Words arguments; int line; };
struct Rule { std::string kind; Words pattern; int line; std::vector<int> items; };
struct Keyword { std::string word; int rank, line; std::vector<int> memories, decomps; };
struct Script {
    Words lines;
    std::map<std::string, Words> texts;
    std::set<std::string> quit, stop, persist;
    int capacity = 3;
    std::vector<Substitution> pres, posts;
    Substitutions pre, post;
    std::vector<Group> groupList;
    Groups groups;
    std::vector<Keyword> keywords;
    std::map<std::string, int> keywordIndex;
    std::vector<Rule> rules;
    std::vector<Item> items;
    std::vector<Diagnostic> diagnostics;
};
Script loadScript(const std::string& path);
std::vector<Diagnostic> lint(const Script& script);
Words lintLines(const std::vector<Diagnostic>& diagnostics);
std::optional<Clauses> match(const Words& pattern, const Words& text, const Groups& groups);
bool covers(const Words& earlier, const Words& later, const Groups& groups);
Words reflect(const Words& values, const Substitutions& substitutions);
std::string buildReply(const std::string& text, const Clauses& bindings, const Substitutions& post);
Words restate(const Words& arguments, const Clauses& bindings);
Words elizaLines(const std::string& text);
struct Memory {
    int capacity = 3;
    Words texts, log;
    bool store(const std::string& prefix, const std::string& keyword, const std::string& text);
    std::string recall(const std::string& prefix);
    void clear(const std::string& prefix);
};
struct State;
struct Session {
    std::string name;
    int turns = 0, stored = 0, recalled = 0;
    std::array<int, 5> sources{};
    std::optional<Clauses> previous;
    Words history;
    std::optional<Words> lastTrace;
    bool trace = false;
    std::map<std::string, int> topics, words;
    std::vector<int> unrecognized;
    std::shared_ptr<State> undo;
};
struct State {
    std::vector<int> positions, hits, itemUses, keywordUses, keywordReplies;
    std::map<std::string, int> lists;
    Memory memory;
    Session session;
};
