#include "eliza.hpp"
#include <algorithm>

bool word(const std::string& text) {
    return !text.empty() && text.front() != '\'' && text.back() != '\'' &&
        std::all_of(text.begin(), text.end(), [](char c) {
            return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '\'';
        });
}
bool reference(const std::string& text) {
    return text.size() == 3 && text[0] == '(' && text[1] >= '0' && text[1] <= '9' && text[2] == ')';
}
namespace {
bool number(const std::string& text) {
    return !text.empty() && text.size() <= 2 && std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}
bool element(const std::string& text) {
    return text == "*" || text == "#" || (text.front() == '@' ? word(text.substr(1)) : word(text));
}
bool formed(const std::string& name, const Words& a) {
    std::size_t n = a.size();
    if (name == "INITIAL" || name == "FINAL" || name == "DEFAULT" || name == "QUESTION" || name == "REPEAT" || name == "REASM") return n >= 1;
    if (name == "QUIT" || name == "STOP") return n >= 1 && std::all_of(a.begin(), a.end(), word);
    if (name == "MEMSIZE") return n == 1 && number(a[0]) && std::stoi(a[0]) >= 1 && std::stoi(a[0]) <= 20;
    if (name == "PERSIST") return n == 1 && (a[0] == "cycles" || a[0] == "memory");
    if (name == "PRE" || name == "SYNON") return n >= 2 && std::all_of(a.begin(), a.end(), word);
    if (name == "POST") return n >= 2 && word(a[0]);
    if (name == "KEY") return n == 2 && word(a[0]) && number(a[1]);
    if (name == "DECOMP" || name == "MEMORY") return n >= 1 && std::all_of(a.begin(), a.end(), element);
    if (name == "GOTO") return n == 1 && word(a[0]);
    if (name == "NEWKEY") return n == 0;
    return n >= 2 && word(a[0]) && std::all_of(a.begin() + 1, a.end(), [](const std::string& s) { return word(s) || reference(s); });
}
}
Script loadScript(const std::string& path) {
    Script s;
    s.lines = readLines(path);
    const std::set<std::string> globals{"INITIAL", "FINAL", "QUIT", "STOP", "DEFAULT", "QUESTION", "REPEAT", "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON"};
    const std::set<std::string> textNames{"INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT"};
    const std::set<std::string> itemNames{"REASM", "GOTO", "NEWKEY", "RESTATE"};
    std::map<std::string, int> first;
    int keyword = -1, rule = -1;
    bool ignoring = false;
    for (std::size_t index = 0; index < s.lines.size(); ++index) {
        const std::string& line = s.lines[index];
        if (line.empty() || line[0] == '#') continue;
        int lineNumber = static_cast<int>(index) + 1;
        Words all = words(line);
        std::string name = all[0];
        Words a(all.begin() + 1, all.end());
        std::string text = line.find(' ') == std::string::npos ? "" : line.substr(line.find(' ') + 1);
        bool isRule = name == "DECOMP" || name == "MEMORY";
        bool isItem = itemNames.count(name) != 0;
        if (globals.count(name) || name == "KEY") { keyword = rule = -1; ignoring = false; }
        else if (isRule || isItem) { if (ignoring) continue; if (isRule) rule = -1; }
        std::string code, message, definition;
        if (name == "MEMSIZE") definition = name;
        else if (name == "KEY" || name == "SYNON" || name == "PRE" || name == "POST" || name == "PERSIST") {
            if (!a.empty()) definition = name + " " + a[0];
        }
        if (!globals.count(name) && name != "KEY" && !isRule && !isItem) { code = "SYNTAX"; message = "unknown directive " + name; }
        else if (!formed(name, a)) { code = "SYNTAX"; message = "bad arguments for " + name; }
        else if (isRule && keyword < 0) { code = "ORPHAN"; message = name + " without KEY"; }
        else if (name == "REASM" && rule < 0) { code = "ORPHAN"; message = "REASM without DECOMP or MEMORY"; }
        else if (isItem && name != "REASM" && (rule < 0 || s.rules[rule].kind == "MEMORY")) { code = "ORPHAN"; message = name + " without DECOMP"; }
        else if (!definition.empty() && first.count(definition)) { code = "DUPLICATE"; message = definition + " first defined at line " + std::to_string(first.at(definition)); }
        if (!code.empty()) {
            s.diagnostics.push_back({lineNumber, code, message});
            if (code == "DUPLICATE" && name == "KEY") ignoring = true;
            continue;
        }
        if (!definition.empty()) first[definition] = lineNumber;
        if (textNames.count(name)) s.texts[name].push_back(text);
        else if (name == "QUIT" || name == "STOP") { auto& set = name == "QUIT" ? s.quit : s.stop; set.insert(a.begin(), a.end()); }
        else if (name == "MEMSIZE") s.capacity = std::stoi(a[0]);
        else if (name == "PERSIST") s.persist.insert(a[0]);
        else if (name == "PRE" || name == "POST") {
            Words replacement(a.begin() + 1, a.end());
            auto& list = name == "PRE" ? s.pres : s.posts;
            auto& table = name == "PRE" ? s.pre : s.post;
            list.push_back({a[0], replacement, lineNumber}); table[a[0]] = replacement;
        } else if (name == "SYNON") {
            std::set<std::string> members(a.begin(), a.end());
            s.groupList.push_back({a[0], members, lineNumber}); s.groups[a[0]] = members;
        } else if (name == "KEY") {
            keyword = static_cast<int>(s.keywords.size());
            s.keywordIndex[a[0]] = keyword;
            s.keywords.push_back({a[0], std::stoi(a[1]), lineNumber, {}, {}});
        } else if (isRule) {
            rule = static_cast<int>(s.rules.size());
            s.rules.push_back({name, a, lineNumber, {}});
            auto& list = name == "MEMORY" ? s.keywords[keyword].memories : s.keywords[keyword].decomps;
            list.push_back(rule);
        } else {
            int item = static_cast<int>(s.items.size());
            s.items.push_back({name, text, a, lineNumber}); s.rules[rule].items.push_back(item);
        }
    }
    return s;
}
