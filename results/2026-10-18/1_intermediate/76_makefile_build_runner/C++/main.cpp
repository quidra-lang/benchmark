#include <algorithm>
#include <cstddef>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Files = std::map<std::string, int>;

static std::string trim(const std::string& text) {
    std::size_t first = text.find_first_not_of(' ');
    return first == std::string::npos ? "" : text.substr(first, text.find_last_not_of(' ') - first + 1);
}

static std::string leftTrim(const std::string& text) {
    std::size_t first = text.find_first_not_of(' ');
    return first == std::string::npos ? "" : text.substr(first);
}

static std::vector<std::string> words(const std::string& text) {
    std::vector<std::string> result;
    std::istringstream input(text);
    for (std::string word; input >> word;) result.push_back(word);
    return result;
}

static std::string join(const std::vector<std::string>& parts) {
    std::string text;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i) text += ' ';
        text += parts[i];
    }
    return text;
}

static std::vector<std::string> unique(const std::vector<std::string>& parts) {
    std::set<std::string> seen;
    std::vector<std::string> result;
    for (const std::string& part : parts) {
        if (seen.insert(part).second) result.push_back(part);
    }
    return result;
}

static bool numeric(const std::string& text) {
    return !text.empty() && std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}

static std::optional<std::string> match(const std::string& pattern, const std::string& word) {
    std::size_t mark = pattern.find('%');
    if (mark == std::string::npos) return word == pattern ? std::optional<std::string>("") : std::nullopt;
    std::string before = pattern.substr(0, mark), after = pattern.substr(mark + 1);
    if (word.size() < before.size() + after.size() || word.compare(0, before.size(), before) != 0
        || word.compare(word.size() - after.size(), after.size(), after) != 0) return std::nullopt;
    return word.substr(before.size(), word.size() - before.size() - after.size());
}

static std::string substitute(const std::string& text, const std::string& stem) {
    std::size_t mark = text.find('%');
    return mark == std::string::npos ? text : text.substr(0, mark) + stem + text.substr(mark + 1);
}

static std::string replacePattern(const std::string& word, const std::string& pattern, const std::string& replacement) {
    std::optional<std::string> stem = match(pattern, word);
    if (!stem) return word;
    return pattern.find('%') == std::string::npos ? replacement : substitute(replacement, *stem);
}

static bool glob(const std::string& pattern, const std::string& name) {
    std::vector<bool> previous(name.size() + 1, false), next(name.size() + 1, false);
    previous[0] = true;
    for (char c : pattern) {
        std::fill(next.begin(), next.end(), false);
        if (c == '*') next[0] = previous[0];
        for (std::size_t i = 1; i <= name.size(); ++i) {
            if (c == '*') next[i] = previous[i] || (name[i - 1] != '/' && next[i - 1]);
            else next[i] = previous[i - 1] && (c == '?' ? name[i - 1] != '/' : c == name[i - 1]);
        }
        previous.swap(next);
    }
    return previous.back();
}

static std::vector<std::string> wildcard(const std::string& pattern, const Files& files) {
    std::vector<std::string> result;
    if (pattern.find_first_of("*?") == std::string::npos) {
        if (files.count(pattern)) result.push_back(pattern);
    } else {
        for (const auto& [name, time] : files) {
            if (glob(pattern, name)) result.push_back(name);
        }
    }
    return result;
}

struct Problem {
    std::string location;
    std::string reason;
};

static void report(const Problem& problem) {
    std::cout << problem.location << ": *** " << problem.reason << ".  Stop.\n";
}

struct Variable {
    bool simple;
    std::string value;
};

using Variables = std::map<std::string, Variable>;

class Expansion {
    struct Scope {
        bool call;
        std::string name;
        std::vector<std::string> values;
    };

    const Variables& variables;
    const Files& files;
    std::string location;
    std::map<std::string, std::string> automatic;
    std::vector<Scope> scopes;
    std::set<std::string> active;

    [[noreturn]] void error(const std::string& reason) const { throw Problem{location, reason}; }

    static const std::map<std::string, std::pair<int, int>>& functions() {
        static const std::map<std::string, std::pair<int, int>> table = {
            {"subst", {3, 3}}, {"patsubst", {3, 3}}, {"strip", {1, 1}}, {"findstring", {2, 2}},
            {"filter", {2, 2}}, {"filter-out", {2, 2}}, {"sort", {1, 1}}, {"word", {2, 2}},
            {"wordlist", {3, 3}}, {"words", {1, 1}}, {"firstword", {1, 1}}, {"lastword", {1, 1}},
            {"dir", {1, 1}}, {"notdir", {1, 1}}, {"suffix", {1, 1}}, {"basename", {1, 1}},
            {"addsuffix", {2, 2}}, {"addprefix", {2, 2}}, {"wildcard", {1, 1}}, {"foreach", {3, 3}},
            {"if", {2, 3}}, {"call", {1, 0}}, {"value", {1, 1}}, {"info", {1, 1}},
            {"warning", {1, 1}}, {"error", {1, 1}}
        };
        return table;
    }

    std::string function(const std::string& name, const std::string& text, char opening) {
        auto [minimum, maximum] = functions().at(name);
        char closing = opening == '(' ? ')' : '}';
        std::vector<std::string> args;
        std::size_t start = 0;
        int depth = 0;
        for (std::size_t i = 0; i < text.size(); ++i) {
            if (text[i] == opening) ++depth;
            else if (text[i] == closing) --depth;
            else if (text[i] == ',' && depth == 0 && (maximum == 0 || args.size() < static_cast<std::size_t>(maximum - 1))) {
                args.push_back(text.substr(start, i - start));
                start = i + 1;
            }
        }
        args.push_back(text.substr(start));
        if (args.size() < static_cast<std::size_t>(minimum)) error("insufficient number of arguments (" + std::to_string(args.size()) + ") to function '" + name + "'");
        if (name == "if") {
            bool condition = !trim(expand(args[0])).empty();
            return condition ? expand(args[1]) : (args.size() == 3 ? expand(args[2]) : "");
        }
        if (name == "foreach") {
            std::string variable = trim(expand(args[0]));
            std::vector<std::string> list = words(expand(args[1])), results;
            for (const std::string& word : list) {
                scopes.push_back({false, variable, {word}});
                results.push_back(expand(args[2]));
                scopes.pop_back();
            }
            return join(results);
        }
        for (std::string& argument : args) {
            argument = expand(argument);
            if (name != "subst" && name != "call") argument = trim(argument);
        }
        if (name == "call") {
            std::string variable = trim(args[0]);
            auto found = variables.find(variable);
            if (found == variables.end()) return "";
            if (found->second.simple) return found->second.value;
            args[0] = variable;
            scopes.push_back({true, "", args});
            std::string result = expand(found->second.value);
            scopes.pop_back();
            return result;
        }
        if (name == "value") {
            auto found = variables.find(args[0]);
            return found == variables.end() ? "" : found->second.value;
        }
        if (name == "info" || name == "warning" || name == "error") {
            if (name == "error") error(args[0]);
            if (name == "warning") std::cout << location << ": ";
            std::cout << args[0] << '\n';
            return "";
        }
        if (name == "subst") {
            if (args[0].empty()) return args[2];
            std::string result;
            std::size_t position = 0;
            while (true) {
                std::size_t found = args[2].find(args[0], position);
                result += args[2].substr(position, found == std::string::npos ? found : found - position);
                if (found == std::string::npos) break;
                result += args[1];
                position = found + args[0].size();
            }
            return result;
        }
        if (name == "findstring") return args[1].find(args[0]) == std::string::npos ? "" : args[0];
        std::vector<std::string> list = words(args.back()), result;
        if (name == "strip") return join(list);
        if (name == "words") return std::to_string(list.size());
        if (name == "firstword") return list.empty() ? "" : list.front();
        if (name == "lastword") return list.empty() ? "" : list.back();
        if (name == "sort") {
            std::sort(list.begin(), list.end());
            list.erase(std::unique(list.begin(), list.end()), list.end());
            return join(list);
        }
        if (name == "word" || name == "wordlist") {
            if (!numeric(args[0])) error("non-numeric first argument to '" + name + "' function: '" + args[0] + "'");
            if (name == "wordlist" && !numeric(args[1])) error("non-numeric second argument to 'wordlist' function: '" + args[1] + "'");
            int first = std::stoi(args[0]);
            if (first == 0) error(name == "word" ? "first argument to 'word' function must be greater than 0" : "invalid first argument to 'wordlist' function: '" + args[0] + "'");
            int last = name == "word" ? first : std::stoi(args[1]);
            for (int i = first; i <= last && i <= static_cast<int>(list.size()); ++i) result.push_back(list[i - 1]);
            return join(result);
        }
        if (name == "patsubst") {
            for (const std::string& word : list) result.push_back(replacePattern(word, args[0], args[1]));
        } else if (name == "filter" || name == "filter-out") {
            std::vector<std::string> patterns = words(args[0]);
            for (const std::string& word : list) {
                bool accepted = std::any_of(patterns.begin(), patterns.end(), [&](const std::string& pattern) { return match(pattern, word).has_value(); });
                if (accepted == (name == "filter")) result.push_back(word);
            }
        } else if (name == "wildcard") {
            for (const std::string& word : list) {
                std::vector<std::string> names = wildcard(word, files);
                result.insert(result.end(), names.begin(), names.end());
            }
        } else if (name == "addprefix" || name == "addsuffix") {
            for (const std::string& word : list) result.push_back(name == "addprefix" ? args[0] + word : word + args[0]);
        } else {
            for (const std::string& word : list) {
                std::size_t slash = word.rfind('/'), dot = word.rfind('.');
                bool extension = dot != std::string::npos && (slash == std::string::npos || dot > slash);
                if (name == "dir") result.push_back(slash == std::string::npos ? "./" : word.substr(0, slash + 1));
                else if (name == "notdir") result.push_back(slash == std::string::npos ? word : word.substr(slash + 1));
                else if (name == "suffix") {
                    if (extension) result.push_back(word.substr(dot));
                } else if (name == "basename") result.push_back(extension ? word.substr(0, dot) : word);
            }
        }
        return join(result);
    }

    std::string reference(const std::string& content, char opening) {
        std::size_t space = content.find(' ');
        if (space != std::string::npos && functions().count(content.substr(0, space))) return function(content.substr(0, space), leftTrim(content.substr(space + 1)), opening);
        std::string name = expand(content);
        std::size_t colon = name.find(':'), equal = colon == std::string::npos ? std::string::npos : name.find('=', colon + 1);
        if (equal == std::string::npos) return value(name);
        std::string pattern = name.substr(colon + 1, equal - colon - 1), replacement = name.substr(equal + 1);
        if (pattern.find('%') == std::string::npos) {
            pattern = '%' + pattern;
            replacement = '%' + replacement;
        }
        std::vector<std::string> result;
        for (const std::string& word : words(value(name.substr(0, colon)))) result.push_back(replacePattern(word, pattern, replacement));
        return join(result);
    }

public:
    Expansion(const Variables& values, const Files& table, std::string where = "make", std::map<std::string, std::string> autos = {})
        : variables(values), files(table), location(std::move(where)), automatic(std::move(autos)) {}

    std::string value(const std::string& name) {
        for (auto scope = scopes.rbegin(); scope != scopes.rend(); ++scope) {
            if (scope->call && numeric(name)) {
                std::size_t index = static_cast<std::size_t>(std::stoi(name));
                return index < scope->values.size() ? scope->values[index] : "";
            }
            if (!scope->call && scope->name == name) return scope->values[0];
        }
        auto special = automatic.find(name);
        if (special != automatic.end()) return special->second;
        auto found = variables.find(name);
        if (found == variables.end()) return "";
        if (found->second.simple) return found->second.value;
        if (!active.insert(name).second) error("Recursive variable '" + name + "' references itself (eventually)");
        std::string result = expand(found->second.value);
        active.erase(name);
        return result;
    }

    std::string expand(const std::string& text) {
        std::string result;
        for (std::size_t i = 0; i < text.size();) {
            if (text[i] != '$') result += text[i++];
            else if (++i == text.size()) break;
            else if (text[i] == '$') {
                result += '$';
                ++i;
            } else if (text[i] == '(' || text[i] == '{') {
                char opening = text[i], closing = opening == '(' ? ')' : '}';
                std::size_t begin = ++i;
                int depth = 1;
                while (i < text.size()) {
                    if (text[i] == opening) ++depth;
                    else if (text[i] == closing && --depth == 0) break;
                    ++i;
                }
                if (i == text.size()) error("unterminated variable reference");
                result += reference(text.substr(begin, i - begin), opening);
                ++i;
            } else result += value(std::string(1, text[i++]));
        }
        return result;
    }
};

struct RecipeLine {
    int line;
    std::string text;
};

using Recipe = std::shared_ptr<std::vector<RecipeLine>>;

struct Rule {
    std::vector<std::string> prerequisites;
    Recipe recipe;
    std::string stem;
};

struct Pattern {
    std::string target;
    Rule rule;
};

class Simulator {
    Files files;
    int clock = 0;
    Variables variables;
    std::map<std::string, Rule> explicitRules;
    std::vector<Pattern> patterns;
    std::set<std::string> phony;
    std::string goal;
    bool loaded = false;

    void clearMakefile() {
        variables.clear();
        explicitRules.clear();
        patterns.clear();
        phony.clear();
        goal.clear();
        loaded = false;
    }

    static std::optional<std::size_t> outside(const std::string& text, char wanted, const std::string& location) {
        std::optional<std::size_t> found;
        for (std::size_t i = 0; i < text.size();) {
            if (text[i] != '$') {
                if (text[i] == wanted && !found) found = i;
                ++i;
            } else if (++i < text.size()) {
                if (text[i] != '(' && text[i] != '{') ++i;
                else {
                    char opening = text[i], closing = opening == '(' ? ')' : '}';
                    int depth = 1;
                    ++i;
                    for (; i < text.size() && depth > 0; ++i) {
                        if (text[i] == opening) ++depth;
                        else if (text[i] == closing) --depth;
                    }
                    if (depth != 0) throw Problem{location, "unterminated variable reference"};
                }
            }
        }
        return found;
    }

    void registerTarget(const std::string& name, const std::vector<std::string>& prerequisites) {
        Rule& rule = explicitRules[name];
        for (const std::string& item : unique(prerequisites)) {
            if (std::find(rule.prerequisites.begin(), rule.prerequisites.end(), item) == rule.prerequisites.end()) rule.prerequisites.push_back(item);
        }
        if (goal.empty() && name[0] != '.') goal = name;
    }

    struct Current {
        std::vector<std::string> targets;
        std::vector<std::size_t> patternIndices;
        Recipe recipe;
    };

    void addRecipe(Current& current, int line, const std::string& text) {
        if (current.targets.empty() && current.patternIndices.empty()) return;
        if (!current.recipe) {
            current.recipe = std::make_shared<std::vector<RecipeLine>>();
            for (const std::string& name : current.targets) {
                Rule& rule = explicitRules.at(name);
                if (rule.recipe) {
                    std::cout << "Makefile:" << line << ": warning: overriding recipe for target '" << name << "'\n"
                              << "Makefile:" << rule.recipe->front().line << ": warning: ignoring old recipe for target '" << name << "'\n";
                }
                rule.recipe = current.recipe;
            }
            for (std::size_t index : current.patternIndices) patterns[index].rule.recipe = current.recipe;
        }
        current.recipe->push_back({line, text});
    }

    void load(const std::vector<std::string>& body) {
        clearMakefile();
        struct Condition {
            bool outer;
            bool value;
            bool otherwise;
            int line;
        };
        std::vector<Condition> conditions;
        std::optional<Current> current;
        auto active = [&] { return conditions.empty() || (conditions.back().outer && conditions.back().value); };
        try {
            for (std::size_t i = 0; i < body.size(); ++i) {
                int lineNumber = static_cast<int>(i) + 1;
                std::string location = "Makefile:" + std::to_string(lineNumber), text = body[i];
                if (!text.empty() && text[0] == '>') {
                    if (!active()) continue;
                    if (!current) throw Problem{location, "recipe commences before first target"};
                    addRecipe(*current, lineNumber, leftTrim(text.substr(1)));
                    continue;
                }
                while (!text.empty() && text.back() == '\\' && i + 1 < body.size()) {
                    text.pop_back();
                    while (!text.empty() && text.back() == ' ') text.pop_back();
                    text += ' ' + leftTrim(body[++i]);
                }
                text = trim(text.substr(0, text.find('#')));
                std::size_t space = text.find(' ');
                std::string first = text.substr(0, space), rest = space == std::string::npos ? "" : trim(text.substr(space + 1));
                Expansion expansion(variables, files, location);
                if (first == "else") {
                    if (conditions.empty()) throw Problem{location, "extraneous 'else'"};
                    if (conditions.back().otherwise) throw Problem{location, "only one 'else' per conditional"};
                    conditions.back().value = !conditions.back().value;
                    conditions.back().otherwise = true;
                } else if (first == "endif") {
                    if (conditions.empty()) throw Problem{location, "extraneous 'endif'"};
                    conditions.pop_back();
                } else if (first == "ifdef" || first == "ifndef" || first == "ifeq" || first == "ifneq") {
                    bool outer = active(), condition = false;
                    if (outer) {
                        if (first == "ifdef" || first == "ifndef") {
                            std::string name = trim(expansion.expand(rest));
                            auto found = variables.find(name);
                            condition = found != variables.end() && !found->second.value.empty();
                            if (first == "ifndef") condition = !condition;
                        } else {
                            if (rest.size() < 2 || rest.front() != '(' || rest.back() != ')') throw Problem{location, "invalid syntax in conditional"};
                            std::string inner = rest.substr(1, rest.size() - 2);
                            int depth = 0;
                            std::size_t comma = std::string::npos;
                            for (std::size_t j = 0; j < inner.size(); ++j) {
                                if (inner[j] == '(') ++depth;
                                else if (inner[j] == ')') --depth;
                                else if (inner[j] == ',' && depth == 0) {
                                    comma = j;
                                    break;
                                }
                            }
                            if (comma == std::string::npos) throw Problem{location, "invalid syntax in conditional"};
                            std::string left = trim(expansion.expand(inner.substr(0, comma)));
                            std::string right = trim(expansion.expand(inner.substr(comma + 1)));
                            condition = left == right;
                            if (first == "ifneq") condition = !condition;
                        }
                    }
                    conditions.push_back({outer, condition, false, lineNumber});
                } else if (!text.empty() && active()) {
                    std::optional<std::size_t> equal = outside(text, '=', location), colon = outside(text, ':', location);
                    if (equal && (!colon || *colon + 1 >= *equal)) {
                        char modifier = *equal > 0 ? text[*equal - 1] : '\0';
                        bool combined = modifier == ':' || modifier == '+' || modifier == '?';
                        std::string name = trim(text.substr(0, *equal - (combined ? 1 : 0)));
                        std::string value = trim(text.substr(*equal + 1));
                        if (name.empty()) throw Problem{location, "empty variable name"};
                        auto found = variables.find(name);
                        if (modifier == ':' && combined) variables[name] = {true, expansion.expand(value)};
                        else if (modifier == '?' && combined) {
                            if (found == variables.end()) variables[name] = {false, value};
                        } else if (modifier == '+' && combined && found != variables.end()) {
                            std::string addition = found->second.simple ? expansion.expand(value) : value;
                            found->second.value = found->second.value.empty() ? addition : found->second.value + ' ' + addition;
                        } else variables[name] = {false, value};
                        current.reset();
                    } else if (colon) {
                        std::vector<std::string> targets = unique(words(expansion.expand(text.substr(0, *colon))));
                        std::string remainder = text.substr(*colon + 1);
                        std::optional<std::string> inlineRecipe;
                        std::optional<std::size_t> semicolon = outside(remainder, ';', location);
                        if (semicolon) {
                            inlineRecipe = leftTrim(remainder.substr(*semicolon + 1));
                            remainder = remainder.substr(0, *semicolon);
                        }
                        std::optional<std::size_t> secondColon = outside(remainder, ':', location);
                        std::string targetPattern;
                        if (secondColon) {
                            targetPattern = trim(expansion.expand(remainder.substr(0, *secondColon)));
                            remainder = remainder.substr(*secondColon + 1);
                        }
                        std::vector<std::string> prerequisites = words(expansion.expand(remainder));
                        Current rule;
                        if (targets.size() == 1 && targets[0] == ".PHONY") phony.insert(prerequisites.begin(), prerequisites.end());
                        else if (secondColon) {
                            if (targetPattern.find('%') == std::string::npos) throw Problem{location, "target pattern contains no '%'"};
                            for (const std::string& name : targets) {
                                std::optional<std::string> stem = match(targetPattern, name);
                                if (!stem || stem->empty()) {
                                    std::cout << location << ": target '" << name << "' doesn't match the target pattern\n";
                                    continue;
                                }
                                std::vector<std::string> substituted;
                                for (const std::string& item : prerequisites) substituted.push_back(substitute(item, *stem));
                                registerTarget(name, substituted);
                                explicitRules.at(name).stem = *stem;
                                rule.targets.push_back(name);
                            }
                        } else if (std::any_of(targets.begin(), targets.end(), [](const std::string& name) { return name.find('%') != std::string::npos; })) {
                            if (std::any_of(targets.begin(), targets.end(), [](const std::string& name) { return name.find('%') == std::string::npos; })) throw Problem{location, "mixed implicit and normal rules"};
                            for (const std::string& name : targets) {
                                rule.patternIndices.push_back(patterns.size());
                                patterns.push_back({name, Rule{prerequisites, nullptr, ""}});
                            }
                        } else {
                            for (const std::string& name : targets) registerTarget(name, prerequisites);
                            rule.targets = targets;
                        }
                        current = std::move(rule);
                        if (inlineRecipe) addRecipe(*current, lineNumber, *inlineRecipe);
                    } else if (!trim(expansion.expand(text)).empty()) throw Problem{location, "missing separator"};
                }
            }
            if (!conditions.empty()) throw Problem{"Makefile:" + std::to_string(conditions.back().line), "missing 'endif'"};
            loaded = true;
            int count = 0;
            for (const Pattern& pattern : patterns) count += pattern.rule.recipe != nullptr;
            std::cout << "Makefile loaded: lines=" << body.size() << " variables=" << variables.size() << " targets="
                      << explicitRules.size() << " patterns=" << count << " goal=" << (goal.empty() ? "(none)" : goal) << '\n';
        } catch (const Problem& problem) {
            report(problem);
            clearMakefile();
        }
    }

    struct Choice {
        int kind;
        Rule rule;
    };

    Choice determine(const std::string& target) const {
        auto explicitRule = explicitRules.find(target);
        if (explicitRule != explicitRules.end() && explicitRule->second.recipe) return {2, explicitRule->second};
        if (!phony.count(target)) {
            std::optional<Rule> chosen;
            std::size_t shortest = 0;
            for (const Pattern& pattern : patterns) {
                if (!pattern.rule.recipe) continue;
                std::optional<std::string> stem = match(pattern.target, target);
                if (!stem || stem->empty() || (chosen && stem->size() >= shortest)) continue;
                Rule rule{{}, pattern.rule.recipe, *stem};
                bool usable = true;
                for (const std::string& item : pattern.rule.prerequisites) {
                    std::string prerequisite = substitute(item, *stem);
                    if (!files.count(prerequisite) && !explicitRules.count(prerequisite)) usable = false;
                    rule.prerequisites.push_back(prerequisite);
                }
                if (!usable) continue;
                if (explicitRule != explicitRules.end()) rule.prerequisites.insert(rule.prerequisites.end(), explicitRule->second.prerequisites.begin(), explicitRule->second.prerequisites.end());
                rule.prerequisites = unique(rule.prerequisites);
                shortest = stem->size();
                chosen = std::move(rule);
            }
            if (chosen) return {2, *chosen};
        }
        if (explicitRule != explicitRules.end()) return {2, explicitRule->second};
        if (phony.count(target)) return {2, Rule{}};
        return {files.count(target) ? 1 : 0, Rule{}};
    }

    void touch(const std::string& name) { files[name] = ++clock; }

    int executeRecipe(const std::string& text) {
        std::vector<std::string> parts = words(text);
        if (parts[0] == "echo") std::cout << join(std::vector<std::string>(parts.begin() + 1, parts.end())) << '\n';
        else if (parts[0] == "touch") {
            for (std::size_t i = 1; i < parts.size(); ++i) touch(parts[i]);
        } else if (parts[0] == "rm") {
            bool forced = parts.size() > 1 && parts[1] == "-f";
            int result = 0;
            for (std::size_t i = forced ? 2 : 1; i < parts.size(); ++i) {
                std::vector<std::string> names = wildcard(parts[i], files);
                if (names.empty()) names.push_back(parts[i]);
                for (const std::string& name : names) {
                    if (!files.erase(name) && !forced) {
                        std::cout << "rm: cannot remove '" << name << "': No such file or directory\n";
                        result = 1;
                    }
                }
            }
            return result;
        } else if (parts[0] == "false") return 1;
        else if (parts[0] == "exit") return parts.size() > 1 ? std::stoi(parts[1]) : 0;
        return 0;
    }

    struct Abort {};

    void make(const std::vector<std::string>& args) {
        std::set<char> options;
        std::vector<std::string> goals;
        for (const std::string& argument : args) {
            if (argument[0] != '-') goals.push_back(argument);
            else for (std::size_t i = 1; i < argument.size(); ++i) {
                if (std::string("nBkis").find(argument[i]) == std::string::npos) {
                    std::cout << "make: invalid option -- '" << argument[i] << "'\n";
                    return;
                }
                options.insert(argument[i]);
            }
        }
        if (goals.empty()) {
            if (!loaded) {
                std::cout << "make: *** No targets specified and no makefile found.  Stop.\n";
                return;
            }
            if (goal.empty()) {
                std::cout << "make: *** No targets.  Stop.\n";
                return;
            }
            goals.push_back(goal);
        }
        Files originalFiles;
        int originalClock = clock;
        if (options.count('n')) originalFiles = files;
        std::map<std::string, int> results;
        std::map<std::string, Choice> choices;
        std::set<std::string> building;
        int recipeCount = 0;
        auto time = [&](const std::string& name) -> std::optional<int> {
            auto found = files.find(name);
            return phony.count(name) || found == files.end() ? std::nullopt : std::optional<int>(found->second);
        };
        std::function<int(const std::string&, const std::string&)> build = [&](const std::string& target, const std::string& parent) {
            if (results.count(target)) return results.at(target);
            Choice choice = determine(target);
            choices[target] = choice;
            if (choice.kind == 0) {
                std::cout << "make: *** No rule to make target '" << target << '\'';
                if (!parent.empty()) std::cout << ", needed by '" << parent << '\'';
                std::cout << '.' << (options.count('k') ? "\n" : "  Stop.\n");
                results[target] = 1;
                if (!options.count('k')) throw Abort{};
                return 1;
            }
            if (choice.kind == 1) return results[target] = 0;
            building.insert(target);
            std::vector<std::string> kept;
            bool failed = false;
            for (const std::string& prerequisite : choice.rule.prerequisites) {
                if (building.count(prerequisite)) std::cout << "make: Circular " << target << " <- " << prerequisite << " dependency dropped.\n";
                else {
                    kept.push_back(prerequisite);
                    if (build(prerequisite, target) != 0) failed = true;
                }
            }
            building.erase(target);
            if (failed) return results[target] = 2;
            std::optional<int> targetTime = time(target);
            std::vector<std::string> newer;
            for (const std::string& prerequisite : kept) {
                std::optional<int> prerequisiteTime = time(prerequisite);
                if (options.count('B') || !targetTime || !prerequisiteTime || *prerequisiteTime > *targetTime) newer.push_back(prerequisite);
            }
            if (!choice.rule.recipe || (!options.count('B') && targetTime && newer.empty())) return results[target] = 0;
            ++recipeCount;
            std::map<std::string, std::string> automatic = {
                {"@", target}, {"<", kept.empty() ? "" : kept[0]}, {"^", join(kept)}, {"?", join(newer)}, {"*", choice.rule.stem}
            };
            std::vector<RecipeLine> expanded;
            for (const RecipeLine& line : *choice.rule.recipe) {
                Expansion expansion(variables, files, "Makefile:" + std::to_string(line.line), automatic);
                expanded.push_back({line.line, expansion.expand(line.text)});
            }
            for (const RecipeLine& line : expanded) {
                std::size_t first = line.text.find_first_not_of(" @-");
                std::string prefix = line.text.substr(0, first);
                std::string command = first == std::string::npos ? "" : trim(line.text.substr(first));
                if (command.empty()) continue;
                if (options.count('n') || (prefix.find('@') == std::string::npos && !options.count('s'))) std::cout << command << '\n';
                if (options.count('n')) continue;
                int exitCode = executeRecipe(command);
                if (exitCode == 0) continue;
                bool ignored = prefix.find('-') != std::string::npos || options.count('i');
                std::cout << (ignored ? "make: [Makefile:" : "make: *** [Makefile:") << line.line << ": " << target << "] Error " << exitCode;
                if (ignored) std::cout << " (ignored)\n";
                else {
                    std::cout << '\n';
                    results[target] = 1;
                    if (!options.count('k')) throw Abort{};
                    return 1;
                }
            }
            if (!phony.count(target)) touch(target);
            return results[target] = 0;
        };
        try {
            for (const std::string& target : goals) {
                int before = recipeCount;
                int result = build(target, "");
                if (result == 0 && recipeCount == before) {
                    if (phony.count(target) || !choices.at(target).rule.recipe) std::cout << "make: Nothing to be done for '" << target << "'.\n";
                    else std::cout << "make: '" << target << "' is up to date.\n";
                } else if (result == 2) std::cout << "make: Target '" << target << "' not remade because of errors.\n";
            }
        } catch (const Problem& problem) {
            report(problem);
        }
        catch (const Abort&) {}
        if (options.count('n')) {
            files = std::move(originalFiles);
            clock = originalClock;
        }
    }

public:
    void run() {
        std::string line;
        std::getline(std::cin, line);
        while (std::getline(std::cin, line) && line != "END FILES") {
            std::vector<std::string> parts = words(line);
            int value = std::stoi(parts[1]);
            files[parts[0]] = value;
            clock = std::max(clock, value);
        }
        while (std::getline(std::cin, line) && line != "QUIT") {
            std::cout << "$ " << line << '\n';
            std::vector<std::string> parts = words(line);
            const std::string& command = parts[0];
            if (command == "MAKEFILE") {
                std::vector<std::string> body;
                while (std::getline(std::cin, line) && line != "END MAKEFILE") body.push_back(line);
                load(body);
            } else if (command == "MAKE") make(std::vector<std::string>(parts.begin() + 1, parts.end()));
            else if (command == "TOUCH" || command == "RM") {
                for (std::size_t i = 1; i < parts.size(); ++i) {
                    if (command == "TOUCH") touch(parts[i]);
                    else if (!files.erase(parts[i])) std::cout << "rm: cannot remove '" << parts[i] << "': No such file or directory\n";
                }
            } else if (command == "FILES") {
                std::cout << "clock " << clock << '\n';
                for (const auto& [name, value] : files) std::cout << name << ' ' << value << '\n';
            } else if (command == "RULES") {
                auto print = [&](const std::string& name, const Rule& rule) {
                    std::cout << name << ':';
                    for (const std::string& prerequisite : rule.prerequisites) std::cout << ' ' << prerequisite;
                    std::cout << '\n';
                    if (rule.recipe) for (const RecipeLine& recipe : *rule.recipe) std::cout << '>' << recipe.text << '\n';
                };
                for (const auto& [name, rule] : explicitRules) print(name, rule);
                for (const Pattern& pattern : patterns) {
                    if (pattern.rule.recipe) print(pattern.target, pattern.rule);
                }
                if (!phony.empty()) std::cout << ".PHONY: " << join(std::vector<std::string>(phony.begin(), phony.end())) << '\n';
            } else {
                try {
                    if (command == "VARS") {
                        for (const auto& [name, variable] : variables) {
                            Expansion expansion(variables, files);
                            std::string value = trim(expansion.value(name));
                            std::cout << name << (variable.simple ? " :=" : " =");
                            if (!value.empty()) std::cout << ' ' << value;
                            std::cout << '\n';
                        }
                    } else if (command == "EXPAND") {
                        Expansion expansion(variables, files);
                        std::string value = expansion.expand(line.substr(7));
                        std::cout << '[' << value << "]\n";
                    }
                } catch (const Problem& problem) {
                    report(problem);
                }
            }
        }
    }
};

int main() {
    Simulator simulator;
    simulator.run();
}
