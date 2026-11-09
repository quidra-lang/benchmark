#include "eliza.hpp"
#include <algorithm>
#include <functional>

namespace {
const Words codes{"SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED", "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"};
const std::set<std::string> errors{"SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"};
bool unknown(const Words& p, const Groups& groups) {
    return std::any_of(p.begin(), p.end(), [&](const std::string& e) { return e.front() == '@' && !groups.count(e.substr(1)); });
}
}
std::vector<Diagnostic> lint(const Script& s) {
    std::vector<Diagnostic> found = s.diagnostics;
    auto add = [&](int line, const std::string& code, const std::string& message) { found.push_back({line, code, message}); };
    std::set<std::string> replacements, targets, usedGroups;
    std::vector<std::vector<int>> graph(s.keywords.size());
    for (const Substitution& pre : s.pres) replacements.insert(pre.replacement.begin(), pre.replacement.end());
    for (const Item& item : s.items) if (item.kind == "GOTO" || item.kind == "RESTATE") targets.insert(item.arguments[0]);
    for (const Rule& rule : s.rules) for (const std::string& e : rule.pattern) if (e.front() == '@') usedGroups.insert(e.substr(1));
    for (std::size_t k = 0; k < s.keywords.size(); ++k) for (int r : s.keywords[k].decomps) for (int i : s.rules[r].items) {
        const Item& item = s.items[i];
        if ((item.kind == "GOTO" || item.kind == "RESTATE") && s.keywordIndex.count(item.arguments[0])) graph[k].push_back(s.keywordIndex.at(item.arguments[0]));
    }
    auto reaches = [&](int start, int goal) {
        std::set<int> seen;
        std::vector<int> pending{start};
        while (!pending.empty()) { int current = pending.back(); pending.pop_back(); if (current == goal) return true; if (!seen.insert(current).second) continue; pending.insert(pending.end(), graph[current].begin(), graph[current].end()); }
        return false;
    };
    for (const Keyword& key : s.keywords) {
        if (key.decomps.empty()) add(key.line, "KEY_NO_DECOMP", "keyword " + key.word + " has no DECOMP");
        if (s.pre.count(key.word) && !replacements.count(key.word) && !targets.count(key.word)) add(key.line, "KEY_UNREACHABLE", "keyword " + key.word + " is replaced by PRE");
    }
    for (const Group& g : s.groupList) if (!usedGroups.count(g.name)) add(g.line, "SYNON_UNUSED", "group " + g.name + " is never used");
    for (const Substitution& pre : s.pres) for (const std::string& value : pre.replacement) if (s.pre.count(value)) add(pre.line, "PRE_CHAIN", "replacement " + value + " is itself replaced by PRE");
    for (const Keyword& key : s.keywords) for (const auto& list : {key.memories, key.decomps}) for (std::size_t p = 0; p < list.size(); ++p) {
        const Rule& rule = s.rules[list[p]];
        for (const std::string& e : rule.pattern) if (e.front() == '@' && !s.groups.count(e.substr(1))) add(rule.line, "SYNON_UNKNOWN", "unknown group " + e.substr(1));
        if (rule.items.empty()) add(rule.line, "RULE_NO_REASM", "rule has no reassembly");
        if (!unknown(rule.pattern, s.groups)) for (std::size_t q = 0; q < p; ++q) {
            const Rule& previous = s.rules[list[q]];
            if (!unknown(previous.pattern, s.groups) && covers(previous.pattern, rule.pattern, s.groups)) { add(rule.line, "RULE_SHADOWED", "pattern is shadowed by line " + std::to_string(previous.line)); break; }
        }
        int wildcards = static_cast<int>(std::count_if(rule.pattern.begin(), rule.pattern.end(), wildcard));
        for (int i : rule.items) {
            const Item& item = s.items[i];
            std::vector<int> references;
            if (item.kind == "REASM") for (std::size_t j = 0; j < item.text.size(); ++j) if (reference(item.text.substr(j, 3))) references.push_back(item.text[j + 1] - '0');
            if (item.kind == "RESTATE") for (std::size_t j = 1; j < item.arguments.size(); ++j) if (reference(item.arguments[j])) references.push_back(item.arguments[j][1] - '0');
            for (int n : references) if (n == 0 || n > wildcards) add(item.line, "REF_UNBOUND", "reference (" + std::to_string(n) + ") is not bound");
            if (item.kind != "GOTO" && item.kind != "RESTATE") continue;
            const std::string& target = item.arguments[0];
            if (!s.keywordIndex.count(target)) add(item.line, "TARGET_UNDEFINED", "target " + target + " is not a keyword");
            else if (reaches(s.keywordIndex.at(target), s.keywordIndex.at(key.word))) add(item.line, "TARGET_CYCLE", "edge " + key.word + " -> " + target + " is on a cycle");
        }
    }
    std::stable_sort(found.begin(), found.end(), [](const Diagnostic& a, const Diagnostic& b) {
        return a.line != b.line ? a.line < b.line : std::find(codes.begin(), codes.end(), a.code) < std::find(codes.begin(), codes.end(), b.code);
    });
    return found;
}
Words lintLines(const std::vector<Diagnostic>& found) {
    if (found.empty()) return {"OK"};
    Words result;
    int count = 0;
    for (const Diagnostic& d : found) { result.push_back(std::to_string(d.line) + " " + d.code + " " + d.message); count += errors.count(d.code); }
    result.push_back("TOTAL " + std::to_string(found.size()) + " errors=" + std::to_string(count) + " warnings=" + std::to_string(found.size() - count));
    return result;
}
