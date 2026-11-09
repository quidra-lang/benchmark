#include <algorithm>
#include <array>
#include <cstddef>
#include <functional>
#include <iostream>
#include <map>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

[[noreturn]] static void fail(const std::string& message) {
    throw std::runtime_error(message);
}

static std::vector<std::string> split(const std::string& text, const std::string& separator) {
    std::vector<std::string> parts;
    std::size_t start = 0;
    while (true) {
        std::size_t end = text.find(separator, start);
        parts.push_back(text.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos) return parts;
        start = end + separator.size();
    }
}

static std::string joined(const std::vector<std::string>& parts, const std::string& separator) {
    std::string text;
    for (const std::string& part : parts) {
        if (!text.empty()) text += separator;
        text += part;
    }
    return text;
}

static bool digits(const std::string& text) {
    return !text.empty() && std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}

static bool number(const std::string& text) {
    return text.size() <= 4 && digits(text) && (text.size() == 1 || text[0] != '0');
}

struct Version {
    std::array<int, 3> core{};
    std::vector<std::string> prerelease;

    std::string text() const {
        std::string result = std::to_string(core[0]) + '.' + std::to_string(core[1]) + '.' + std::to_string(core[2]);
        if (!prerelease.empty()) result += '-' + joined(prerelease, ".");
        return result;
    }
};

static std::optional<Version> parseVersion(const std::string& text) {
    std::size_t dash = text.find('-');
    std::vector<std::string> core = split(text.substr(0, dash), ".");
    if (core.size() != 3) return std::nullopt;
    Version version;
    for (std::size_t i = 0; i < core.size(); ++i) {
        if (!number(core[i])) return std::nullopt;
        version.core[i] = std::stoi(core[i]);
    }
    if (dash != std::string::npos) {
        version.prerelease = split(text.substr(dash + 1), ".");
        for (const std::string& identifier : version.prerelease) {
            if (identifier.empty() || !std::all_of(identifier.begin(), identifier.end(), [](char c) {
                return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
            })) return std::nullopt;
            if (digits(identifier) && !number(identifier)) return std::nullopt;
        }
    }
    return version;
}

static int compare(const Version& a, const Version& b) {
    if (a.core != b.core) return a.core < b.core ? -1 : 1;
    if (a.prerelease.empty() || b.prerelease.empty()) {
        if (a.prerelease.empty() == b.prerelease.empty()) return 0;
        return a.prerelease.empty() ? 1 : -1;
    }
    for (std::size_t i = 0; i < std::min(a.prerelease.size(), b.prerelease.size()); ++i) {
        const std::string& left = a.prerelease[i];
        const std::string& right = b.prerelease[i];
        if (left == right) continue;
        bool numericLeft = digits(left), numericRight = digits(right);
        if (numericLeft != numericRight) return numericLeft ? -1 : 1;
        if (numericLeft) return std::stoi(left) < std::stoi(right) ? -1 : 1;
        return left < right ? -1 : 1;
    }
    if (a.prerelease.size() == b.prerelease.size()) return 0;
    return a.prerelease.size() < b.prerelease.size() ? -1 : 1;
}

struct Comparator {
    std::string operation;
    Version version;
};

struct Alternative {
    std::vector<Comparator> comparisons;
    std::set<std::array<int, 3>> prereleaseCores;
};

struct Constraint {
    std::vector<Alternative> alternatives;

    bool matches(const Version& version) const {
        for (const Alternative& alternative : alternatives) {
            if (!version.prerelease.empty() && !alternative.prereleaseCores.count(version.core)) continue;
            bool accepts = true;
            for (const Comparator& item : alternative.comparisons) {
                int relation = compare(version, item.version);
                if ((item.operation == "=" && relation != 0) || (item.operation == ">" && relation <= 0)
                    || (item.operation == ">=" && relation < 0) || (item.operation == "<" && relation >= 0)
                    || (item.operation == "<=" && relation > 0)) accepts = false;
            }
            if (accepts) return true;
        }
        return false;
    }

    std::string normal() const {
        std::vector<std::string> choices;
        for (const Alternative& alternative : alternatives) {
            std::vector<std::string> terms;
            for (const Comparator& item : alternative.comparisons) terms.push_back(item.operation + item.version.text());
            choices.push_back(terms.empty() ? "*" : joined(terms, " "));
        }
        return joined(choices, " || ");
    }
};

static std::optional<Constraint> parseConstraint(const std::string& text) {
    Constraint constraint;
    for (const std::string& choice : split(text, " || ")) {
        Alternative alternative;
        for (const std::string& term : split(choice, " ")) {
            if (term.empty()) return std::nullopt;
            std::string operation, pattern = term;
            for (const std::string& prefix : {">=", "<=", ">", "<", "=", "^", "~"}) {
                if (term.compare(0, prefix.size(), prefix) == 0) {
                    operation = prefix;
                    pattern = term.substr(prefix.size());
                    break;
                }
            }
            Version lower;
            int count = 0;
            std::optional<Version> parsed = parseVersion(pattern);
            if (parsed && !parsed->prerelease.empty()) {
                lower = *parsed;
                count = 3;
                alternative.prereleaseCores.insert(lower.core);
            } else {
                std::vector<std::string> parts = split(pattern, ".");
                if (parts.size() > 3) return std::nullopt;
                bool wildcard = false;
                for (std::size_t i = 0; i < parts.size(); ++i) {
                    if (parts[i] == "x" || parts[i] == "*") wildcard = true;
                    else {
                        if (wildcard || !number(parts[i])) return std::nullopt;
                        lower.core[i] = std::stoi(parts[i]);
                        ++count;
                    }
                }
            }
            auto upper = [&](int index) {
                Version result = lower;
                result.prerelease.clear();
                ++result.core[index - 1];
                for (int i = index; i < 3; ++i) result.core[i] = 0;
                return result;
            };
            auto add = [&](const std::string& op, const Version& version) { alternative.comparisons.push_back({op, version}); };
            if (count == 0) {
                if (operation == ">" || operation == "<") add("<", Version{{0, 0, 0}, {"0"}});
            } else if (operation.empty() || operation == "=") {
                if (count == 3) add("=", lower);
                else {
                    add(">=", lower);
                    add("<", upper(count));
                }
            } else if (operation == ">") add(count == 3 ? ">" : ">=", count == 3 ? lower : upper(count));
            else if (operation == "<=") add(count == 3 ? "<=" : "<", count == 3 ? lower : upper(count));
            else if (operation == ">=" || operation == "<") add(operation, lower);
            else {
                add(">=", lower);
                int index = operation == "~" ? (count == 1 ? 1 : 2)
                          : (lower.core[0] != 0 || count == 1 ? 1 : (lower.core[1] != 0 || count == 2 ? 2 : 3));
                add("<", upper(index));
            }
        }
        constraint.alternatives.push_back(std::move(alternative));
    }
    return constraint;
}

static Version checkedVersion(const std::string& text) {
    std::optional<Version> version = parseVersion(text);
    if (!version) fail("invalid version '" + text + "'");
    return *version;
}

static Constraint checkedConstraint(const std::string& text) {
    std::optional<Constraint> constraint = parseConstraint(text);
    if (!constraint) fail("invalid constraint '" + text + "'");
    return *constraint;
}

struct Clause {
    std::string name;
    std::string raw;
    Constraint constraint;
};

struct Package {
    Version version;
    std::vector<Clause> dependencies;
    std::vector<Clause> conflicts;
    bool yanked = false;
};

using Installation = std::map<std::string, std::string>;
using Requests = std::vector<Clause>;

struct Snapshot {
    Requests requests;
    Installation installed;
};

struct Requirement {
    Clause clause;
    std::vector<std::string> chain;
};

struct Failure {
    int depth;
    std::vector<std::string> chain;
    std::string reason;
    std::vector<std::string> previous;
};

class Manager {
    std::map<std::string, std::map<std::string, Package>> registry;
    Requests requests;
    Installation installed;
    std::set<std::string> held;
    std::map<std::string, Clause> advisories;
    std::vector<Snapshot> history;

    const Package& package(const std::string& name, const std::string& version) const {
        auto group = registry.find(name);
        if (group == registry.end() || !group->second.count(version)) fail(name + '@' + version + " is not registered");
        return group->second.at(version);
    }

    std::vector<const Package*> versions(const std::string& name) const {
        std::vector<const Package*> result;
        auto group = registry.find(name);
        if (group == registry.end()) return result;
        for (const auto& [raw, item] : group->second) result.push_back(&item);
        std::sort(result.begin(), result.end(), [](const Package* a, const Package* b) { return compare(a->version, b->version) > 0; });
        return result;
    }

    std::vector<std::string> applicable(const std::string& name, const Version& version) const {
        std::vector<std::string> result;
        for (const auto& [id, advisory] : advisories) {
            if (advisory.name == name && advisory.constraint.matches(version)) result.push_back(id);
        }
        return result;
    }

    std::string display(const std::string& name, const Package& item) const {
        std::string version = item.version.text(), text = name + '@' + version;
        auto found = installed.find(name);
        bool active = found != installed.end() && found->second == version;
        if (item.yanked && active) text += " (yanked, installed)";
        else if (item.yanked) text += " (yanked)";
        else if (active) text += " (installed)";
        return text;
    }

    std::set<std::string> installedNames() const {
        std::set<std::string> names;
        for (const auto& [name, version] : installed) names.insert(name);
        return names;
    }

    bool resolve(const Requests& wanted, const std::set<std::string>& preferred, bool audit, Installation& result) const {
        Installation selected;
        std::map<std::string, std::vector<std::string>> chains;
        std::optional<Failure> failure;
        auto record = [&](const Requirement& requirement, const std::string& reason, const std::vector<std::string>& previous = std::vector<std::string>{}) {
            int depth = static_cast<int>(selected.size());
            if (!failure || depth > failure->depth) failure = Failure{depth, requirement.chain, reason, previous};
        };
        auto usable = [&](const std::string& name, const Package& item) {
            auto current = installed.find(name);
            bool active = current != installed.end() && current->second == item.version.text();
            return (!item.yanked || active) && (!audit || applicable(name, item.version).empty());
        };
        std::function<bool(const std::vector<Requirement>&)> search = [&](const std::vector<Requirement>& requirements) {
            if (requirements.empty()) return true;
            const Requirement& requirement = requirements.front();
            const Clause& clause = requirement.clause;
            std::vector<Requirement> rest(requirements.begin() + 1, requirements.end());
            auto chosen = selected.find(clause.name);
            if (chosen != selected.end()) {
                if (clause.constraint.matches(package(clause.name, chosen->second).version)) return search(rest);
                record(requirement, clause.name + '@' + chosen->second + " was selected by:", chains.at(clause.name));
                return false;
            }
            std::vector<const Package*> candidates;
            if (held.count(clause.name)) {
                const Package& item = package(clause.name, installed.at(clause.name));
                if (!clause.constraint.matches(item.version) || !usable(clause.name, item)) {
                    record(requirement, clause.name + '@' + installed.at(clause.name) + " is held");
                    return false;
                }
                candidates.push_back(&item);
            } else {
                for (const Package* item : versions(clause.name)) {
                    if (clause.constraint.matches(item->version) && usable(clause.name, *item)) candidates.push_back(item);
                }
                if (preferred.count(clause.name) && installed.count(clause.name)) {
                    auto current = std::find_if(candidates.begin(), candidates.end(), [&](const Package* item) { return item->version.text() == installed.at(clause.name); });
                    if (current != candidates.end()) std::rotate(candidates.begin(), current, current + 1);
                }
                if (candidates.empty()) {
                    record(requirement, "no version of " + clause.name + " matches " + clause.raw);
                    return false;
                }
            }
            for (const Package* item : candidates) {
                std::string conflict;
                for (const auto& [other, version] : selected) {
                    const Package& previous = package(other, version);
                    bool conflicts = false;
                    for (const Clause& declaration : item->conflicts) {
                        if (declaration.name == other && declaration.constraint.matches(previous.version)) conflicts = true;
                    }
                    for (const Clause& declaration : previous.conflicts) {
                        if (declaration.name == clause.name && declaration.constraint.matches(item->version)) conflicts = true;
                    }
                    if (conflicts) {
                        conflict = other;
                        break;
                    }
                }
                std::string raw = item->version.text();
                if (!conflict.empty()) {
                    record(requirement, clause.name + '@' + raw + " conflicts with " + conflict + '@' + selected.at(conflict) + ", which was selected by:", chains.at(conflict));
                    continue;
                }
                selected[clause.name] = raw;
                chains[clause.name] = requirement.chain;
                std::vector<Requirement> expanded;
                for (const Clause& dependency : item->dependencies) {
                    std::vector<std::string> chain = requirement.chain;
                    chain.push_back(clause.name + '@' + raw + " requires " + dependency.name + ' ' + dependency.raw);
                    expanded.push_back({dependency, std::move(chain)});
                }
                expanded.insert(expanded.end(), rest.begin(), rest.end());
                if (search(expanded)) return true;
                selected.erase(clause.name);
                chains.erase(clause.name);
            }
            return false;
        };
        std::vector<Requirement> initial;
        for (const Clause& request : wanted) initial.push_back({request, {"requested " + request.name + ' ' + request.raw}});
        if (search(initial)) {
            result = std::move(selected);
            return true;
        }
        std::cout << "UNSATISFIABLE\n";
        for (const std::string& line : failure->chain) std::cout << "  " << line << '\n';
        std::cout << "  " << failure->reason << '\n';
        for (const std::string& line : failure->previous) std::cout << "    " << line << '\n';
        return false;
    }

    void plan(const Installation& next) const {
        int added = 0, upgraded = 0, downgraded = 0, removed = 0;
        std::set<std::string> arranged;
        while (arranged.size() < next.size()) {
            for (const auto& [name, version] : next) {
                if (arranged.count(name)) continue;
                bool ready = true;
                for (const Clause& dependency : package(name, version).dependencies) {
                    if (!arranged.count(dependency.name)) ready = false;
                }
                if (!ready) continue;
                auto old = installed.find(name);
                if (old == installed.end()) {
                    std::cout << "install " << name << '@' << version << '\n';
                    ++added;
                } else if (old->second != version) {
                    bool newer = compare(package(name, version).version, package(name, old->second).version) > 0;
                    std::cout << (newer ? "upgrade " : "downgrade ") << name << ' ' << old->second << " -> " << version << '\n';
                    newer ? ++upgraded : ++downgraded;
                }
                arranged.insert(name);
                break;
            }
        }
        std::set<std::string> obsolete;
        for (const auto& [name, version] : installed) {
            if (!next.count(name)) obsolete.insert(name);
        }
        while (!obsolete.empty()) {
            for (const std::string& name : obsolete) {
                bool ready = true;
                for (const std::string& other : obsolete) {
                    for (const Clause& dependency : package(other, installed.at(other)).dependencies) {
                        if (dependency.name == name) ready = false;
                    }
                }
                if (!ready) continue;
                std::cout << "remove " << name << '@' << installed.at(name) << '\n';
                ++removed;
                obsolete.erase(name);
                break;
            }
        }
        if (added + upgraded + downgraded + removed == 0) std::cout << "no changes\n";
        else std::cout << added << " installed, " << upgraded << " upgraded, " << downgraded << " downgraded, " << removed << " removed\n";
    }

    void trimHeld() {
        for (auto position = held.begin(); position != held.end();) {
            if (!installed.count(*position)) position = held.erase(position);
            else ++position;
        }
    }

    void update(Requests nextRequests, Installation nextInstalled) {
        history.push_back({requests, installed});
        requests = std::move(nextRequests);
        installed = std::move(nextInstalled);
        trimHeld();
    }

    std::string requiredBy(const std::string& name) const {
        for (const auto& [other, version] : installed) {
            for (const Clause& dependency : package(other, version).dependencies) {
                if (dependency.name == name) return other;
            }
        }
        return "";
    }

    void remove(const std::string& name) {
        auto request = std::find_if(requests.begin(), requests.end(), [&](const Clause& item) { return item.name == name; });
        if (request == requests.end()) {
            if (!installed.count(name)) fail(name + " is not installed");
            fail(name + " is required by " + requiredBy(name));
        }
        Requests nextRequests = requests;
        nextRequests.erase(nextRequests.begin() + (request - requests.begin()));
        std::set<std::string> reached;
        std::vector<std::string> pending;
        for (const Clause& item : nextRequests) {
            if (reached.insert(item.name).second) pending.push_back(item.name);
        }
        for (std::size_t i = 0; i < pending.size(); ++i) {
            for (const Clause& dependency : package(pending[i], installed.at(pending[i])).dependencies) {
                if (reached.insert(dependency.name).second) pending.push_back(dependency.name);
            }
        }
        if (reached.count(name)) {
            std::cout << name << '@' << installed.at(name) << " is still required by " << requiredBy(name) << '\n';
            update(std::move(nextRequests), installed);
        } else {
            Installation next;
            for (const std::string& item : reached) next[item] = installed.at(item);
            plan(next);
            update(std::move(nextRequests), std::move(next));
        }
    }

    void why(const std::string& name) const {
        if (!installed.count(name)) fail(name + " is not installed");
        std::map<std::string, std::string> parents;
        std::set<std::string> roots;
        for (const Clause& item : requests) roots.insert(item.name);
        if (roots.count(name)) {
            std::cout << name << '@' << installed.at(name) << " is explicitly installed\n";
            return;
        }
        std::queue<std::string> queue;
        for (const std::string& root : roots) {
            parents[root] = "";
            queue.push(root);
        }
        while (!queue.empty()) {
            std::string current = queue.front();
            queue.pop();
            std::vector<std::string> children;
            for (const Clause& dependency : package(current, installed.at(current)).dependencies) children.push_back(dependency.name);
            std::sort(children.begin(), children.end());
            for (const std::string& child : children) {
                if (parents.count(child)) continue;
                parents[child] = current;
                queue.push(child);
            }
        }
        std::vector<std::string> path;
        for (std::string current = name; !current.empty(); current = parents.at(current)) path.push_back(current + '@' + installed.at(current));
        std::reverse(path.begin(), path.end());
        std::cout << joined(path, " -> ") << '\n';
    }

    void tree(const std::string& name) const {
        if (!name.empty() && !installed.count(name)) fail(name + " is not installed");
        std::map<std::string, std::string> constraints;
        for (const Clause& item : requests) constraints[item.name] = item.raw;
        std::vector<std::string> roots;
        if (!name.empty()) roots.push_back(name);
        else for (const auto& [root, raw] : constraints) roots.push_back(root);
        if (roots.empty()) {
            std::cout << "(empty)\n";
            return;
        }
        std::set<std::string> displayed;
        std::function<void(const std::string&, const std::optional<std::string>&, const std::string&, const std::string&)> show;
        show = [&](const std::string& current, const std::optional<std::string>& constraint, const std::string& prefix, const std::string& indent) {
            std::cout << prefix << current << '@' << installed.at(current);
            if (constraint) std::cout << " [" << *constraint << ']';
            if (!displayed.insert(current).second) {
                std::cout << " (*)\n";
                return;
            }
            std::cout << '\n';
            const std::vector<Clause>& children = package(current, installed.at(current)).dependencies;
            for (std::size_t i = 0; i < children.size(); ++i) {
                bool last = i + 1 == children.size();
                show(children[i].name, children[i].raw, indent + (last ? "`-- " : "|-- "), indent + (last ? "    " : "|   "));
            }
        };
        for (const std::string& root : roots) {
            auto found = constraints.find(root);
            show(root, found == constraints.end() ? std::nullopt : std::optional<std::string>(found->second), "", "");
        }
    }

    void outdated() const {
        bool any = false;
        for (const auto& [name, current] : installed) {
            std::vector<Constraint> relevant;
            for (const Clause& item : requests) {
                if (item.name == name) relevant.push_back(item.constraint);
            }
            for (const auto& [other, version] : installed) {
                for (const Clause& item : package(other, version).dependencies) {
                    if (item.name == name) relevant.push_back(item.constraint);
                }
            }
            std::string wanted, latest;
            for (const Package* item : versions(name)) {
                std::string raw = item->version.text();
                if (!item->yanked && item->version.prerelease.empty() && latest.empty()) latest = raw;
                if (wanted.empty() && (!item->yanked || raw == current)
                    && std::all_of(relevant.begin(), relevant.end(), [&](const Constraint& constraint) { return constraint.matches(item->version); })) wanted = raw;
            }
            if (wanted != current || (!latest.empty() && compare(package(name, latest).version, package(name, current).version) > 0)) {
                std::cout << name << ' ' << current << ' ' << wanted << ' ' << (latest.empty() ? "-" : latest) << '\n';
                any = true;
            }
        }
        if (!any) std::cout << "all packages are up to date\n";
    }

    void audit() const {
        bool any = false;
        for (const auto& [name, current] : installed) {
            const Version& version = package(name, current).version;
            std::vector<std::string> ids = applicable(name, version);
            if (ids.empty()) continue;
            std::string fix;
            for (const Package* item : versions(name)) {
                if (compare(item->version, version) > 0 && item->version.prerelease.empty() && !item->yanked && applicable(name, item->version).empty()) fix = item->version.text();
            }
            std::cout << name << '@' << current << ": " << joined(ids, ", ")
                      << (fix.empty() ? " (no fix)" : " (fix: " + fix + ')') << '\n';
            any = true;
        }
        if (!any) std::cout << "no known vulnerabilities\n";
    }

public:
    void execute(const std::string& line) {
        std::vector<std::string> clauses = split(line, "; ");
        std::vector<std::string> words = split(clauses[0], " ");
        const std::string& command = words[0];
        auto tail = [&](std::size_t first) {
            return joined(std::vector<std::string>(words.begin() + static_cast<std::ptrdiff_t>(first), words.end()), " ");
        };
        if (command == "PKG") {
            Version version = checkedVersion(words[2]);
            if (registry.count(words[1]) && registry.at(words[1]).count(words[2])) fail(words[1] + '@' + words[2] + " is already registered");
            Package item{version, {}, {}, false};
            for (std::size_t i = 1; i < clauses.size(); ++i) {
                std::size_t first = clauses[i].find(' '), second = clauses[i].find(' ', first + 1);
                std::string name = clauses[i].substr(first + 1, second - first - 1), raw = clauses[i].substr(second + 1);
                Clause declaration{name, raw, checkedConstraint(raw)};
                (clauses[i].substr(0, first) == "DEP" ? item.dependencies : item.conflicts).push_back(std::move(declaration));
            }
            registry[words[1]].emplace(words[2], std::move(item));
            std::cout << "registered " << words[1] << '@' << words[2] << '\n';
        } else if (command == "YANK" || command == "INFO") {
            const Package& item = package(words[1], words[2]);
            if (command == "YANK") {
                if (item.yanked) fail(words[1] + '@' + words[2] + " is already yanked");
                registry.at(words[1]).at(words[2]).yanked = true;
                std::cout << "yanked " << words[1] << '@' << words[2] << '\n';
            } else {
                std::cout << display(words[1], item) << '\n';
                for (const Clause& dependency : item.dependencies) std::cout << "  requires " << dependency.name << ' ' << dependency.raw << '\n';
                for (const Clause& conflict : item.conflicts) std::cout << "  conflicts with " << conflict.name << ' ' << conflict.raw << '\n';
                for (const std::string& id : applicable(words[1], item.version)) std::cout << "  advisory " << id << '\n';
            }
        } else if (command == "VERSIONS") {
            std::optional<Constraint> constraint;
            if (words.size() > 2) constraint = checkedConstraint(tail(2));
            if (!registry.count(words[1])) fail("unknown package " + words[1]);
            bool any = false;
            for (const Package* item : versions(words[1])) {
                if (!constraint || constraint->matches(item->version)) {
                    std::cout << display(words[1], *item) << '\n';
                    any = true;
                }
            }
            if (!any) std::cout << "no matching versions\n";
        } else if (command == "DEPENDENTS") {
            std::optional<Version> version;
            if (words.size() == 3) version = checkedVersion(words[2]);
            bool any = false;
            for (const auto& [name, group] : registry) {
                for (const Package* item : versions(name)) {
                    for (const Clause& dependency : item->dependencies) {
                        if (dependency.name == words[1] && (!version || dependency.constraint.matches(*version))) {
                            std::cout << name << '@' << item->version.text() << " requires " << words[1] << ' ' << dependency.raw << '\n';
                            any = true;
                        }
                    }
                }
            }
            if (!any) std::cout << "no dependents\n";
        } else if (command == "COMPARE") {
            Version a = checkedVersion(words[1]), b = checkedVersion(words[2]);
            int order = compare(a, b);
            std::cout << words[1] << (order < 0 ? " < " : (order > 0 ? " > " : " = ")) << words[2] << '\n';
        } else if (command == "MATCH") {
            Version version = checkedVersion(words[1]);
            Constraint constraint = checkedConstraint(tail(2));
            std::cout << (constraint.matches(version) ? "yes\n" : "no\n");
        } else if (command == "RANGE") std::cout << checkedConstraint(tail(1)).normal() << '\n';
        else if (command == "INSTALL" || command == "SIMULATE") {
            std::string raw = words.size() > 2 ? tail(2) : "*";
            Clause request{words[1], raw, checkedConstraint(raw)};
            if (!registry.count(request.name)) fail("unknown package " + request.name);
            Requests nextRequests = requests;
            auto found = std::find_if(nextRequests.begin(), nextRequests.end(), [&](const Clause& item) { return item.name == request.name; });
            if (found == nextRequests.end()) nextRequests.push_back(request);
            else *found = request;
            Installation next;
            if (resolve(nextRequests, installedNames(), false, next)) {
                plan(next);
                if (command == "INSTALL") update(std::move(nextRequests), std::move(next));
            }
        } else if (command == "REMOVE") remove(words[1]);
        else if (command == "UPGRADE" || (command == "AUDIT" && words.size() == 2)) {
            bool fixing = command == "AUDIT";
            if (!fixing && words.size() == 2 && !installed.count(words[1])) fail(words[1] + " is not installed");
            std::set<std::string> preferred;
            if (fixing || words.size() == 2) {
                preferred = installedNames();
                if (!fixing) preferred.erase(words[1]);
            }
            Installation next;
            if (resolve(requests, preferred, fixing, next)) {
                plan(next);
                update(requests, std::move(next));
            }
        } else if (command == "ROLLBACK") {
            if (history.empty()) fail("nothing to roll back");
            Snapshot snapshot = std::move(history.back());
            history.pop_back();
            plan(snapshot.installed);
            requests = std::move(snapshot.requests);
            installed = std::move(snapshot.installed);
            trimHeld();
        } else if (command == "HOLD") {
            if (!installed.count(words[1])) fail(words[1] + " is not installed");
            if (!held.insert(words[1]).second) fail(words[1] + " is already held");
            std::cout << "held " << words[1] << '@' << installed.at(words[1]) << '\n';
        } else if (command == "UNHOLD") {
            if (!held.erase(words[1])) fail(words[1] + " is not held");
            std::cout << "released " << words[1] << '\n';
        } else if (command == "WHY") why(words[1]);
        else if (command == "TREE") tree(words.size() == 2 ? words[1] : "");
        else if (command == "OUTDATED") outdated();
        else if (command == "LOCK") {
            if (installed.empty()) std::cout << "(empty)\n";
            for (const auto& [name, version] : installed) std::cout << name << '@' << version << '\n';
        } else if (command == "STATUS") {
            if (requests.empty()) std::cout << "no requests\n";
            for (const Clause& item : requests) std::cout << item.name << ' ' << item.raw << " -> " << installed.at(item.name) << '\n';
            std::cout << installed.size() << " installed, " << held.size() << " held, " << history.size() << " snapshots\n";
        } else if (command == "ADVISORY") {
            if (advisories.count(words[1])) fail("advisory " + words[1] + " already exists");
            std::string raw = tail(3);
            Clause advisory{words[2], raw, checkedConstraint(raw)};
            advisories.emplace(words[1], std::move(advisory));
            std::cout << "advisory " << words[1] << " recorded\n";
        } else if (command == "AUDIT") audit();
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Manager manager;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            manager.execute(line);
        } catch (const std::runtime_error& error) {
            std::cout << "error: " << error.what() << '\n';
        }
    }
}
