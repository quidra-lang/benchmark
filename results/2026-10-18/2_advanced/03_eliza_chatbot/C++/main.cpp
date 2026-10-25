#include "eliza.hpp"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <numeric>
#include <sstream>

Words words(const std::string& text) {
    std::istringstream input(text);
    Words result;
    for (std::string value; input >> value;) result.push_back(value);
    return result;
}
std::string join(const Words& values, const std::string& separator) {
    std::string result;
    for (const std::string& value : values) { if (!result.empty()) result += separator; result += value; }
    return result;
}
Words readLines(const std::string& path) {
    std::ifstream input(path);
    Words result;
    for (std::string line; std::getline(input, line);) result.push_back(line);
    return result;
}
namespace {
void append(Words& target, const Words& source) { target.insert(target.end(), source.begin(), source.end()); }
Clauses normalize(const std::string& text) {
    Clauses result;
    Words clause;
    std::string token;
    auto finishWord = [&] {
        std::size_t start = token.find_first_not_of('\'');
        if (start != std::string::npos) clause.push_back(token.substr(start, token.find_last_not_of('\'') - start + 1));
        token.clear();
    };
    for (char c : text) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '\'') token += c;
        else {
            finishWord();
            if (std::string(",.?!;").find(c) != std::string::npos && !clause.empty()) { result.push_back(clause); clause.clear(); }
        }
    }
    finishWord();
    if (!clause.empty()) result.push_back(clause);
    return result;
}
Words flatten(const Clauses& clauses) { Words result; for (const Words& clause : clauses) append(result, clause); return result; }
Words grouped(const Words& values, std::size_t count) {
    Words result;
    for (std::size_t i = 0; i < values.size(); i += count) result.push_back(join(Words(values.begin() + i, values.begin() + std::min(values.size(), i + count))));
    return result;
}
const std::array<std::string, 5> sources{"keyword", "memory", "question", "default", "repeat"};
std::string sourceLine(int turns, const std::array<int, 5>& counts) {
    std::string line = "turns=" + std::to_string(turns);
    for (std::size_t i = 0; i < sources.size(); ++i) line += " " + sources[i] + "=" + std::to_string(counts[i]);
    return line;
}
std::string rankedCounts(const std::map<std::string, int>& counts) {
    std::vector<std::pair<std::string, int>> ranked(counts.begin(), counts.end());
    std::sort(ranked.begin(), ranked.end(), [](const auto& a, const auto& b) { return a.second != b.second ? a.second > b.second : a.first < b.first; });
    Words values;
    for (std::size_t i = 0; i < std::min<std::size_t>(5, ranked.size()); ++i) values.push_back(ranked[i].first + " " + std::to_string(ranked[i].second));
    return values.empty() ? "none" : join(values, ", ");
}
struct Found { int number, rule; Clauses bindings; };
struct Entry { std::string kind; int number, rule; };

class Chatbot {
    Script script;
    State state;
    Words transcript;
    int totalTurns = 0;
    std::array<int, 5> totals{};

    bool available(const std::string& name) const { auto p = script.texts.find(name); return p != script.texts.end() && !p->second.empty(); }
    std::string prefix() const { return state.session.name + " " + std::to_string(state.session.turns); }
    void resetCycles() { std::fill(state.positions.begin(), state.positions.end(), 0); for (const auto& name : {"DEFAULT", "QUESTION", "REPEAT"}) state.lists[name] = 0; }
    std::string takeText(const std::string& name) {
        const Words& texts = script.texts.at(name);
        int position = state.lists[name]; state.lists[name] = (position + 1) % static_cast<int>(texts.size()); return texts[position];
    }
    std::pair<int, int> takeItem(int r) {
        const Rule& rule = script.rules[r]; int p = state.positions[r]; int item = rule.items[p];
        ++state.itemUses[item]; state.positions[r] = (p + 1) % static_cast<int>(rule.items.size()); return {p + 1, item};
    }
    Clauses prepared(const std::string& text) const { Clauses result = normalize(text); for (Words& clause : result) clause = reflect(clause, script.pre); return result; }
    bool quit(const std::string& text) const { Words values = flatten(normalize(text)); return values.size() == 1 && script.quit.count(values[0]); }
    std::optional<std::pair<int, Words>> select(const Clauses& clauses) const {
        for (std::size_t i = 0; i < clauses.size(); ++i) for (const std::string& value : clauses[i]) if (script.keywordIndex.count(value)) return std::make_pair(static_cast<int>(i) + 1, clauses[i]);
        return std::nullopt;
    }
    std::vector<int> keywordList(const Words& values) const {
        std::vector<int> result; std::set<int> seen;
        for (const std::string& value : values) { auto p = script.keywordIndex.find(value); if (p != script.keywordIndex.end() && seen.insert(p->second).second) result.push_back(p->second); }
        std::stable_sort(result.begin(), result.end(), [&](int a, int b) { return script.keywords[a].rank > script.keywords[b].rank; });
        return result;
    }
    std::optional<Found> findRule(const std::vector<int>& rules, const Words& values) const {
        for (std::size_t i = 0; i < rules.size(); ++i) { auto bindings = match(script.rules[rules[i]].pattern, values, script.groups); if (bindings) return Found{static_cast<int>(i) + 1, rules[i], *bindings}; }
        return std::nullopt;
    }
    std::vector<Entry> entries(const Keyword& key) const {
        std::vector<Entry> result;
        for (const auto& [name, rules] : std::vector<std::pair<std::string, std::vector<int>>>{{"memory", key.memories}, {"decomp", key.decomps}})
            for (std::size_t i = 0; i < rules.size(); ++i) result.push_back({name, static_cast<int>(i) + 1, rules[i]});
        return result;
    }
    std::optional<std::string> keywordReply(const Clauses& clauses, Words& trace) {
        auto selected = select(clauses);
        if (!selected) { trace.push_back("CLAUSE none"); return std::nullopt; }
        const Words& original = selected->second;
        trace.push_back("CLAUSE " + std::to_string(selected->first) + " " + join(original));
        std::vector<int> keys = keywordList(original); Words labels;
        for (int k : keys) labels.push_back(script.keywords[k].word);
        trace.push_back("KEYS " + join(labels));
        const Keyword& first = script.keywords[keys.front()];
        auto memory = findRule(first.memories, original);
        if (memory) {
            trace.push_back("MEMORY " + first.word + " " + std::to_string(memory->number)); ++state.hits[memory->rule];
            if (!script.rules[memory->rule].items.empty()) {
                int item = takeItem(memory->rule).second;
                std::string text = buildReply(script.items[item].text, memory->bindings, script.post);
                if (state.memory.store(prefix(), first.word, text)) ++state.session.stored;
            }
        }
        std::set<int> entered;
        for (int initial : keys) {
            if (entered.count(initial)) continue;
            trace.push_back("ENTER " + script.keywords[initial].word);
            Words current = original;
            int k = initial;
            while (true) {
                const Keyword& key = script.keywords[k]; entered.insert(k); ++state.keywordUses[k];
                auto found = findRule(key.decomps, current);
                if (!found) { trace.push_back("NOMATCH " + key.word); break; }
                ++state.hits[found->rule];
                if (script.rules[found->rule].items.empty()) { trace.push_back("DECOMP " + key.word + " " + std::to_string(found->number) + " 0"); break; }
                auto [number, itemId] = takeItem(found->rule); const Item& item = script.items[itemId];
                trace.push_back("DECOMP " + key.word + " " + std::to_string(found->number) + " " + std::to_string(number));
                if (item.kind == "REASM") { ++state.keywordReplies[k]; ++state.session.topics[key.word]; return buildReply(item.text, found->bindings, script.post); }
                if (item.kind == "NEWKEY") break;
                const std::string& target = item.arguments[0]; auto next = script.keywordIndex.find(target);
                if (next == script.keywordIndex.end() || entered.count(next->second)) { trace.push_back("BLOCKED " + target); break; }
                if (item.kind == "RESTATE") { current = restate(Words(item.arguments.begin() + 1, item.arguments.end()), found->bindings); trace.push_back("RESTATE " + target + (current.empty() ? "" : " " + join(current))); }
                else trace.push_back("GOTO " + target);
                k = next->second;
            }
        }
        return std::nullopt;
    }
    std::pair<std::string, Words> decide(const std::string& text) {
        Clauses clauses = normalize(text); Words trace; std::string reply; int source;
        if (available("REPEAT") && !clauses.empty() && state.session.previous && clauses == *state.session.previous) { trace.push_back("REPEAT"); reply = takeText("REPEAT"); source = 4; }
        else {
            Clauses pre = clauses; for (Words& clause : pre) clause = reflect(clause, script.pre);
            auto result = keywordReply(pre, trace);
            if (result) { reply = *result; source = 0; }
            else if (!state.memory.texts.empty()) { reply = state.memory.recall(prefix()); ++state.session.recalled; source = 1; }
            else if (!text.empty() && text.back() == '?' && available("QUESTION")) { reply = takeText("QUESTION"); source = 2; }
            else { reply = takeText("DEFAULT"); source = 3; }
        }
        trace.push_back("REPLY " + sources[source]); state.session.previous = clauses; ++state.session.sources[source];
        if (source == 2 || source == 3) state.session.unrecognized.push_back(state.session.turns);
        return {reply, trace};
    }
    Words command(const std::string& line) {
        std::size_t space = line.find(' '); std::string name = line.substr(0, space);
        std::string text = space == std::string::npos ? "" : line.substr(space + 1); Words args = words(text);
        const std::set<std::string> noArgs{":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo"};
        const std::set<std::string> textArgs{":prepare", ":reflect", ":say", ":explain"};
        const std::set<std::string> single{":groups", ":find", ":script", ":cycles", ":coverage"};
        const std::set<std::string> keyArgs{":script", ":cycles", ":coverage", ":test"};
        if (!noArgs.count(name) && !textArgs.count(name) && !single.count(name) && name != ":trace" && name != ":test") return {"unknown command " + name};
        if ((noArgs.count(name) && !args.empty()) || (textArgs.count(name) && text.empty()) || (single.count(name) && args.size() != 1) || (name == ":trace" && (args.size() != 1 || (args[0] != "on" && args[0] != "off"))) || (name == ":test" && args.size() < 2)) return {"bad arguments"};
        if (keyArgs.count(name) && !script.keywordIndex.count(args[0])) return {"unknown keyword " + args[0]};
        Words result;
        if (name == ":prepare") {
            Clauses clauses = prepared(text);
            for (std::size_t i = 0; i < clauses.size(); ++i) result.push_back("clause " + std::to_string(i + 1) + ": " + join(clauses[i]));
            if (clauses.empty()) result.push_back("no words");
            auto selected = select(clauses);
            if (!selected) result.push_back("selected none");
            else { result.push_back("selected " + std::to_string(selected->first)); Words labels; for (int k : keywordList(selected->second)) labels.push_back(script.keywords[k].word + "/" + std::to_string(script.keywords[k].rank)); result.push_back("keys " + join(labels)); }
        } else if (name == ":test" || name == ":cycles" || name == ":coverage") {
            const Keyword& key = script.keywords[script.keywordIndex.at(args[0])];
            Words values; if (name == ":test") values = flatten(prepared(text.substr(text.find(' ') + 1)));
            for (const Entry& entry : entries(key)) {
                const Rule& rule = script.rules[entry.rule]; std::string value;
                if (name == ":test") {
                    auto bindings = match(rule.pattern, values, script.groups);
                    if (!bindings) value = "no match";
                    else if (bindings->empty()) value = "match";
                    else { Words pieces; for (const Words& bound : *bindings) pieces.push_back("[" + join(bound) + "]"); value = join(pieces); }
                } else if (name == ":cycles") value = rule.items.empty() ? "empty" : "next " + std::to_string(state.positions[entry.rule] + 1) + "/" + std::to_string(rule.items.size());
                else { Words uses; for (int i : rule.items) uses.push_back(std::to_string(state.itemUses[i])); value = "hits " + std::to_string(state.hits[entry.rule]) + " entries " + (uses.empty() ? "-" : join(uses)); }
                result.push_back(entry.kind + " " + std::to_string(entry.number) + ": " + value);
            }
            if (result.empty()) result.push_back("no rules");
        } else if (name == ":reflect") { for (const Words& clause : prepared(text)) result.push_back(join(reflect(clause, script.post))); if (result.empty()) result.push_back("no words"); }
        else if (name == ":keys") {
            std::vector<int> order(script.keywords.size()); std::iota(order.begin(), order.end(), 0);
            std::sort(order.begin(), order.end(), [&](int a, int b) { const Keyword& x = script.keywords[a]; const Keyword& y = script.keywords[b]; return x.rank != y.rank ? x.rank > y.rank : x.word < y.word; });
            Words labels; for (int k : order) labels.push_back(script.keywords[k].word + "/" + std::to_string(script.keywords[k].rank)); result = grouped(labels, 8);
        } else if (name == ":groups") {
            Words names; for (const auto& [group, members] : script.groups) if (members.count(args[0])) names.push_back(group); result.push_back(names.empty() ? "none" : join(names));
        } else if (name == ":find") {
            const std::string& w = args[0];
            if (script.keywordIndex.count(w)) result.push_back("keyword rank " + std::to_string(script.keywords[script.keywordIndex.at(w)].rank));
            for (const auto& [label, substitutions] : std::vector<std::pair<std::string, std::vector<Substitution>>>{{"pre", script.pres}, {"post", script.posts}})
                for (const Substitution& s : substitutions) if (s.source == w || std::find(s.replacement.begin(), s.replacement.end(), w) != s.replacement.end()) result.push_back(label + " " + std::to_string(s.line) + ": " + s.source + " -> " + join(s.replacement));
            for (const Group& g : script.groupList) if (g.members.count(w)) result.push_back("group " + g.name + " line " + std::to_string(g.line));
            for (const Keyword& key : script.keywords) for (const Entry& entry : entries(key)) if (std::find(script.rules[entry.rule].pattern.begin(), script.rules[entry.rule].pattern.end(), w) != script.rules[entry.rule].pattern.end()) result.push_back("pattern " + key.word + " " + entry.kind + " " + std::to_string(entry.number));
            if (script.stop.count(w)) result.push_back("stop word"); if (script.quit.count(w)) result.push_back("quit word"); if (result.empty()) result.push_back("not found");
        } else if (name == ":script") {
            const Keyword& key = script.keywords[script.keywordIndex.at(args[0])]; std::vector<int> lines{key.line};
            for (const Entry& entry : entries(key)) { lines.push_back(script.rules[entry.rule].line); for (int i : script.rules[entry.rule].items) lines.push_back(script.items[i].line); }
            std::sort(lines.begin(), lines.end()); for (int n : lines) result.push_back(std::to_string(n) + " " + script.lines[n - 1]);
        } else if (name == ":why") result = state.session.lastTrace ? *state.session.lastTrace : Words{"no reply yet"};
        else if (name == ":trace") { state.session.trace = args[0] == "on"; result = {"trace " + args[0]}; }
        else if (name == ":history") { const Words& history = state.session.history; result = history.empty() ? Words{"no turns yet"} : Words(history.begin() + (history.size() > 5 ? history.size() - 5 : 0), history.end()); }
        else if (name == ":memory") { result.push_back("memory " + std::to_string(state.memory.texts.size()) + "/" + std::to_string(state.memory.capacity)); for (std::size_t i = 0; i < state.memory.texts.size(); ++i) result.push_back(std::to_string(i + 1) + ": " + state.memory.texts[i]); }
        else if (name == ":forget") { result.push_back("forgot " + std::to_string(state.memory.texts.size())); state.memory.clear(prefix()); }
        else if (name == ":reset") { resetCycles(); result = {"cycles reset"}; }
        else if (name == ":unused") {
            Words unused; for (std::size_t i = 0; i < script.items.size(); ++i) if (state.itemUses[i] == 0) unused.push_back(std::to_string(script.items[i].line)); result.push_back("unused " + std::to_string(unused.size())); append(result, grouped(unused, 12));
        } else if (name == ":stats") result = {sourceLine(state.session.turns, state.session.sources)};
        else if (name == ":say" || name == ":explain") {
            if (quit(text)) return {"would quit"}; State saved = state; auto [reply, trace] = decide(text); state = std::move(saved); result = name == ":say" ? Words{reply} : trace;
        } else if (name == ":undo") {
            if (!state.session.undo) result = {"nothing to undo"};
            else { std::shared_ptr<State> snapshot = state.session.undo; state = *snapshot; result = {"undone turn " + std::to_string(state.session.turns + 1)}; }
        }
        return result;
    }
    void notes() {
        const Session& s = state.session;
        transcript.push_back("NOTES " + s.name); transcript.push_back("  " + sourceLine(s.turns, s.sources));
        transcript.push_back("  topics: " + rankedCounts(s.topics)); transcript.push_back("  words: " + rankedCounts(s.words));
        transcript.push_back("  memory: stored=" + std::to_string(s.stored) + " recalled=" + std::to_string(s.recalled) + " pending=" + std::to_string(state.memory.texts.size()));
        Words unrecognized; for (int n : s.unrecognized) unrecognized.push_back(std::to_string(n)); transcript.push_back("  unrecognized: " + (unrecognized.empty() ? "none" : join(unrecognized)));
        totalTurns += s.turns; for (std::size_t i = 0; i < totals.size(); ++i) totals[i] += s.sources[i];
    }
public:
    explicit Chatbot(Script value) : script(std::move(value)) {
        state.positions.resize(script.rules.size()); state.hits.resize(script.rules.size()); state.itemUses.resize(script.items.size());
        state.keywordUses.resize(script.keywords.size()); state.keywordReplies.resize(script.keywords.size()); state.memory.capacity = script.capacity; resetCycles();
    }
    void run(const Words& input) {
        int sessions = 0;
        for (const std::string& line : input) {
            if (line.rfind("SESSION ", 0) == 0) {
                if (sessions != 0) { notes(); transcript.push_back(""); }
                std::string name = line.substr(8);
                if (sessions != 0) { if (!script.persist.count("cycles")) resetCycles(); if (!script.persist.count("memory")) state.memory.clear(name + " 0"); }
                state.session = Session{}; state.session.name = name; ++sessions; transcript.push_back(line);
                const Words& initial = script.texts.at("INITIAL"); append(transcript, elizaLines(initial[(sessions - 1) % initial.size()]));
            } else if (line.front() == ':') { transcript.push_back(line); for (const std::string& value : command(line)) transcript.push_back("  " + value); }
            else {
                transcript.push_back("YOU: " + line);
                if (quit(line)) { const Words& final = script.texts.at("FINAL"); append(transcript, elizaLines(final[(sessions - 1) % final.size()])); continue; }
                State snapshot = state; snapshot.session.undo.reset(); state.session.undo = std::make_shared<State>(std::move(snapshot)); ++state.session.turns;
                for (const std::string& value : flatten(normalize(line))) if (!script.stop.count(value)) ++state.session.words[value];
                state.session.history.push_back(std::to_string(state.session.turns) + ": " + line);
                auto [reply, trace] = decide(line); append(transcript, elizaLines(reply)); state.session.lastTrace = trace;
                if (state.session.trace) for (const std::string& value : trace) transcript.push_back("  " + value);
            }
        }
        notes(); transcript.push_back(""); transcript.push_back("SUMMARY sessions=" + std::to_string(sessions) + " " + sourceLine(totalTurns, totals));
    }
    Words statistics() const {
        std::vector<int> order(script.keywords.size()); std::iota(order.begin(), order.end(), 0);
        std::sort(order.begin(), order.end(), [&](int a, int b) { return state.keywordUses[a] != state.keywordUses[b] ? state.keywordUses[a] > state.keywordUses[b] : script.keywords[a].word < script.keywords[b].word; });
        Words result{"keyword,rank,uses,replies,decomposition_hits"};
        for (int k : order) { const Keyword& key = script.keywords[k]; Words hits; for (int r : key.decomps) hits.push_back(std::to_string(state.hits[r])); result.push_back(key.word + "," + std::to_string(key.rank) + "," + std::to_string(state.keywordUses[k]) + "," + std::to_string(state.keywordReplies[k]) + "," + (hits.empty() ? "-" : join(hits, "/"))); }
        return result;
    }
    void write() const {
        auto save = [](const std::string& name, const Words& lines) { std::ofstream output("output/" + name, std::ios::binary); for (const std::string& line : lines) output << line << '\n'; };
        std::filesystem::create_directories("output"); save("lint.txt", lintLines(lint(script))); save("transcript.txt", transcript); save("keyword_stats.csv", statistics()); save("memory_log.txt", state.memory.log);
    }
};
}
int main() { Chatbot bot(loadScript("input/script.txt")); bot.run(readLines("input/dialogue.txt")); bot.write(); }
