#include <algorithm>
#include <array>
#include <cstdint>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <variant>
#include <vector>

using Strings = std::vector<std::string>;
using Int = std::int64_t;
using Output = std::function<void(const std::string&)>;
struct Node;
using NodePtr = std::shared_ptr<Node>;
struct Directory { std::map<std::string, NodePtr> entries; };
struct File { Strings lines; };
struct Link { std::string target; };
using Content = std::variant<Directory, File, Link>;
enum class Kind { Directory, File, Link };
struct Node {
    int inode, modified;
    std::weak_ptr<Node> parent;
    std::string name;
    Content content;
    Node(int number, int time, Content data) : inode(number), modified(time), content(std::move(data)) {}
    Kind kind() const { return static_cast<Kind>(content.index()); }
    const std::map<std::string, NodePtr>& entries() const { return std::get<Directory>(content).entries; }
    const Strings& lines() const { return std::get<File>(content).lines; }
    const std::string& target() const { return std::get<Link>(content).target; }
    Int size() const {
        if (kind() == Kind::Directory) return static_cast<Int>(entries().size());
        if (kind() == Kind::Link) return static_cast<Int>(target().size());
        return std::accumulate(lines().begin(), lines().end(), Int{0}, [](Int total, const auto& line) { return total + static_cast<Int>(line.size()) + 1; });
    }
    int links() const {
        if (kind() != Kind::Directory) return 1;
        return 2 + static_cast<int>(std::count_if(entries().begin(), entries().end(), [](const auto& entry) { return entry.second->kind() == Kind::Directory; }));
    }
    char tag() const { return kind() == Kind::Directory ? 'd' : kind() == Kind::File ? 'f' : 'l'; }
};
enum class Reason { None, Missing, NotDirectory, TooManyLinks };
std::string reasonText(Reason reason) {
    switch (reason) {
        case Reason::None: return "";
        case Reason::Missing: return "No such file or directory";
        case Reason::NotDirectory: return "Not a directory";
        case Reason::TooManyLinks: return "Too many levels of symbolic links";
    }
    return "";
}
struct Resolution {
    NodePtr node;
    Reason reason = Reason::None;
    NodePtr creationParent;
    std::string creationName;
};
struct Options { std::set<char> flags; Strings paths; };
Options options(const Strings& arguments) {
    Options result;
    std::size_t position = 0;
    while (position < arguments.size() && !arguments[position].empty() && arguments[position][0] == '-') {
        result.flags.insert(arguments[position].begin() + 1, arguments[position].end()); ++position;
    }
    result.paths.assign(arguments.begin() + position, arguments.end());
    return result;
}
Strings split(const std::string& text, const std::string& separator) {
    Strings result;
    std::size_t position = 0;
    while (true) {
        auto end = text.find(separator, position);
        result.push_back(text.substr(position, end == std::string::npos ? end : end - position));
        if (end == std::string::npos) return result;
        position = end + separator.size();
    }
}
std::string join(const std::string& path, const std::string& name) { return path == "/" ? "/" + name : path + "/" + name; }
std::string lastComponent(const std::string& path) {
    auto position = path.find_last_of('/');
    return position == std::string::npos ? path : path.substr(position + 1);
}
bool invalidSource(const std::string& name) { return name.empty() || name == "." || name == ".."; }
bool globMatches(const std::string& pattern, const std::string& name) {
    std::vector<bool> previous(name.size() + 1, false);
    previous[0] = true;
    for (char character : pattern) {
        std::vector<bool> current(name.size() + 1, false);
        if (character == '*') {
            current[0] = previous[0];
            for (std::size_t index = 1; index <= name.size(); ++index) current[index] = previous[index] || current[index - 1];
        } else {
            for (std::size_t index = 0; index < name.size(); ++index) current[index + 1] = previous[index] && (character == '?' || character == name[index]);
        }
        previous = std::move(current);
    }
    return previous.back();
}
std::string lower(std::string text) {
    for (char& character : text) if ('A' <= character && character <= 'Z') character = static_cast<char>(character - 'A' + 'a');
    return text;
}

class Shell {
    NodePtr root = std::make_shared<Node>(1, 0, Directory{});
    NodePtr current = root;
    std::optional<std::string> previous;
    int clock = 0, nextInode = 2;
    Output terminal;

    std::string absolute(NodePtr node) const {
        Strings names;
        while (node != root) { names.push_back(node->name); node = node->parent.lock(); }
        std::string result;
        for (auto name = names.rbegin(); name != names.rend(); ++name) result += "/" + *name;
        return result.empty() ? "/" : result;
    }
    bool descendant(NodePtr node, const NodePtr& ancestor) const {
        while (true) {
            if (node == ancestor) return true;
            if (node == root) return false;
            node = node->parent.lock();
        }
    }
    void add(const NodePtr& parent, const std::string& name, const NodePtr& node) {
        std::get<Directory>(parent->content).entries[name] = node;
        parent->modified = clock;
        node->parent = parent; node->name = name;
    }
    NodePtr create(const NodePtr& parent, const std::string& name, Content content) {
        auto node = std::make_shared<Node>(nextInode++, clock, std::move(content));
        add(parent, name, node);
        return node;
    }
    void detach(const NodePtr& node) {
        auto parent = node->parent.lock();
        std::get<Directory>(parent->content).entries.erase(node->name);
        parent->modified = clock;
    }
    void write(const NodePtr& node, const Strings& lines, bool append = false) {
        auto& content = std::get<File>(node->content).lines;
        if (append) content.insert(content.end(), lines.begin(), lines.end());
        else content = lines;
        node->modified = clock;
    }
    Resolution resolve(const std::string& path, bool follow = true, bool makeParents = false) {
        int expansions = 0;
        std::function<Resolution(const std::string&, NodePtr, bool, bool)> walk;
        walk = [&](const std::string& text, NodePtr base, bool finalLink, bool original) -> Resolution {
            auto node = text[0] == '/' ? root : base;
            auto components = split(text, "/");
            components.erase(std::remove(components.begin(), components.end(), ""), components.end());
            for (std::size_t index = 0; index < components.size(); ++index) {
                if (node->kind() != Kind::Directory) return {nullptr, Reason::NotDirectory, nullptr, ""};
                const auto& name = components[index];
                if (name == ".") continue;
                if (name == "..") { node = node->parent.lock(); continue; }
                auto found = node->entries().find(name);
                NodePtr child;
                if (found != node->entries().end()) child = found->second;
                else if (original && makeParents && index + 1 < components.size()) child = create(node, name, Directory{});
                else return {nullptr, Reason::Missing, original && index + 1 == components.size() ? node : nullptr, name};
                if (child->kind() == Kind::Link && (index + 1 < components.size() || finalLink)) {
                    if (++expansions > 8) return {nullptr, Reason::TooManyLinks, nullptr, ""};
                    auto expanded = walk(child->target(), node, true, false);
                    if (!expanded.node) return expanded;
                    child = expanded.node;
                }
                node = child;
            }
            return {node, Reason::None, nullptr, ""};
        };
        return walk(path, current, follow, true);
    }
    NodePtr clone(const NodePtr& source, const NodePtr& parent, const std::string& name) {
        Content content = source->kind() == Kind::Directory ? Content{Directory{}} : source->content;
        auto copy = create(parent, name, std::move(content));
        if (source->kind() == Kind::Directory) {
            for (const auto& [childName, child] : source->entries()) clone(child, copy, childName);
        }
        return copy;
    }
    template<class Visitor>
    void walkNodes(const NodePtr& node, const std::string& path, int depth, int limit, const Visitor& visit) {
        visit(node, path, depth);
        if (node->kind() == Kind::Directory && depth < limit) {
            for (const auto& [name, child] : node->entries()) walkNodes(child, join(path, name), depth + 1, limit, visit);
        }
    }
    template<class Consumer>
    void inputs(const std::string& command, const Strings& paths, const Strings& input, const Consumer& consume) {
        if (paths.empty()) { consume(input, std::nullopt); return; }
        for (const auto& path : paths) {
            auto result = resolve(path);
            if (!result.node) terminal(command + ": " + path + ": " + reasonText(result.reason));
            else if (result.node->kind() == Kind::Directory) terminal(command + ": " + path + ": Is a directory");
            else consume(result.node->lines(), std::optional<std::string>(path));
        }
    }
    void move(const Strings& paths) {
        const auto& destination = paths.back();
        if (paths.size() > 2) {
            auto result = resolve(destination);
            if (!result.node || result.node->kind() != Kind::Directory) {
                terminal("mv: target '" + destination + "' is not a directory"); return;
            }
        }
        for (std::size_t index = 0; index + 1 < paths.size(); ++index) {
            const auto& sourcePath = paths[index];
            auto basename = lastComponent(sourcePath);
            auto problem = [&](const std::string& target, const std::string& reason) { terminal("mv: cannot move '" + sourcePath + "' to '" + target + "': " + reason); };
            if (invalidSource(basename)) { problem(destination, "Invalid argument"); continue; }
            auto sourceResult = resolve(sourcePath, false);
            if (!sourceResult.node) { terminal("mv: cannot stat '" + sourcePath + "': " + reasonText(sourceResult.reason)); continue; }
            auto source = sourceResult.node, targetResult = resolve(destination).node;
            NodePtr parent;
            std::string name, target;
            if (targetResult && targetResult->kind() == Kind::Directory) {
                parent = targetResult; name = basename; target = join(destination, name);
            } else {
                auto result = resolve(destination, false);
                if (result.node) { parent = result.node->parent.lock(); name = result.node->name; }
                else if (result.creationParent) { parent = result.creationParent; name = result.creationName; }
                else { problem(destination, reasonText(result.reason)); continue; }
                target = destination;
            }
            auto found = parent->entries().find(name);
            NodePtr existing = found == parent->entries().end() ? nullptr : found->second;
            if (source->kind() == Kind::Directory && descendant(parent, source)) {
                terminal("mv: cannot move '" + sourcePath + "' to a subdirectory of itself, '" + target + "'");
            } else if (existing == source) {
                terminal("mv: '" + sourcePath + "' and '" + target + "' are the same file");
            } else if (existing && source->kind() == Kind::Directory && existing->kind() != Kind::Directory) {
                terminal("mv: cannot overwrite non-directory '" + target + "' with directory '" + sourcePath + "'");
            } else if (existing && source->kind() != Kind::Directory && existing->kind() == Kind::Directory) {
                terminal("mv: cannot overwrite directory '" + target + "' with non-directory '" + sourcePath + "'");
            } else if (existing && existing->kind() == Kind::Directory && !existing->entries().empty()) {
                problem(target, "Directory not empty");
            } else if (existing == current) {
                problem(target, "Device or resource busy");
            } else {
                if (existing) detach(existing);
                detach(source); add(parent, name, source);
            }
        }
    }
    void copy(const Options& parsed) {
        const auto& paths = parsed.paths;
        const auto& destination = paths.back();
        if (paths.size() > 2) {
            auto result = resolve(destination);
            if (!result.node || result.node->kind() != Kind::Directory) {
                terminal("cp: target '" + destination + "' is not a directory"); return;
            }
        }
        for (std::size_t index = 0; index + 1 < paths.size(); ++index) {
            const auto& sourcePath = paths[index];
            auto basename = lastComponent(sourcePath);
            auto problem = [&](const std::string& target, const std::string& reason) { terminal("cp: cannot copy '" + sourcePath + "' to '" + target + "': " + reason); };
            if (invalidSource(basename)) { problem(destination, "Invalid argument"); continue; }
            auto sourceResult = resolve(sourcePath);
            if (!sourceResult.node) { terminal("cp: cannot stat '" + sourcePath + "': " + reasonText(sourceResult.reason)); continue; }
            auto source = sourceResult.node;
            if (source->kind() == Kind::Directory && !parsed.flags.count('r')) {
                terminal("cp: -r not specified; omitting directory '" + sourcePath + "'"); continue;
            }
            auto destinationResult = resolve(destination);
            if (!destinationResult.node && !destinationResult.creationParent) { problem(destination, reasonText(destinationResult.reason)); continue; }
            auto target = destinationResult.node && destinationResult.node->kind() == Kind::Directory ? join(destination, basename) : destination;
            auto result = resolve(target, source->kind() != Kind::Directory);
            if (source->kind() == Kind::Directory) {
                if (result.node) problem(target, "File exists");
                else if (!result.creationParent) problem(target, reasonText(result.reason));
                else if (descendant(result.creationParent, source)) terminal("cp: cannot copy a directory, '" + sourcePath + "', into itself, '" + target + "'");
                else clone(source, result.creationParent, result.creationName);
            } else {
                if (result.creationParent) create(result.creationParent, result.creationName, File{source->lines()});
                else if (!result.node) problem(target, reasonText(result.reason));
                else if (result.node == source) terminal("cp: '" + sourcePath + "' and '" + target + "' are the same file");
                else if (result.node->kind() == Kind::Directory) terminal("cp: cannot overwrite directory '" + target + "' with non-directory '" + sourcePath + "'");
                else write(result.node, source->lines());
            }
        }
    }
    void listing(const Options& parsed, const Output& output) {
        auto paths = parsed.paths.empty() ? Strings{"."} : parsed.paths;
        for (const auto& path : paths) {
            auto result = resolve(path, !parsed.flags.count('l'));
            if (!result.node) { terminal("ls: cannot access '" + path + "': " + reasonText(result.reason)); continue; }
            auto node = result.node;
            std::vector<std::pair<std::string, NodePtr>> list;
            if (node->kind() != Kind::Directory) list.emplace_back(path, node);
            else {
                if (paths.size() > 1) output(path + ":");
                if (parsed.flags.count('a')) { list.emplace_back(".", node); list.emplace_back("..", node->parent.lock()); }
                for (const auto& entry : node->entries()) if (parsed.flags.count('a') || entry.first[0] != '.') list.push_back(entry);
                if (parsed.flags.count('t')) std::stable_sort(list.begin(), list.end(), [](const auto& left, const auto& right) { return left.second->modified > right.second->modified; });
                if (parsed.flags.count('r')) std::reverse(list.begin(), list.end());
            }
            std::array<std::size_t, 3> widths{};
            auto values = [](const NodePtr& item) { return std::array<std::string, 3>{std::to_string(item->links()), std::to_string(item->size()), std::to_string(item->modified)}; };
            for (const auto& [name, item] : list) {
                auto numbers = values(item);
                for (std::size_t index = 0; index < widths.size(); ++index) widths[index] = std::max(widths[index], numbers[index].size());
            }
            for (const auto& [name, item] : list) {
                if (!parsed.flags.count('l')) { output(name); continue; }
                std::string line(1, item->kind() == Kind::File ? '-' : item->tag());
                auto numbers = values(item);
                for (std::size_t index = 0; index < widths.size(); ++index) line += " " + std::string(widths[index] - numbers[index].size(), ' ') + numbers[index];
                line += " " + name;
                if (item->kind() == Kind::Link) line += " -> " + item->target();
                output(line);
            }
        }
    }
    void find(const Strings& arguments, const Output& output) {
        std::size_t position = !arguments.empty() && arguments[0][0] != '-' ? 1 : 0;
        std::string path = position ? arguments[0] : ".";
        std::optional<std::string> pattern, type;
        int limit = 1000;
        for (; position < arguments.size(); position += 2) {
            if (arguments[position] == "-name") pattern = arguments[position + 1];
            else if (arguments[position] == "-type") type = arguments[position + 1];
            else limit = std::stoi(arguments[position + 1]);
        }
        auto result = resolve(path);
        if (!result.node) { terminal("find: '" + path + "': " + reasonText(result.reason)); return; }
        walkNodes(result.node, path, 0, limit, [&](const NodePtr& node, const std::string& display, int depth) {
            auto name = depth == 0 ? (path == "/" ? "/" : lastComponent(path)) : node->name;
            if (pattern && !globMatches(*pattern, name)) return;
            if (type && (*type)[0] != node->tag()) return;
            output(display);
        });
    }
    void diskUsage(const Options& parsed, const Output& output) {
        auto paths = parsed.paths.empty() ? Strings{"."} : parsed.paths;
        std::function<Int(const NodePtr&, const std::string&, bool)> report;
        report = [&](const NodePtr& node, const std::string& path, bool show) {
            Int usage = node->kind() == Kind::Directory ? 0 : node->size();
            if (node->kind() == Kind::Directory) {
                for (const auto& [name, child] : node->entries()) {
                    usage += report(child, join(path, name), show && !parsed.flags.count('s') && (child->kind() == Kind::Directory || parsed.flags.count('a')));
                }
            }
            if (show) output(std::to_string(usage) + " " + path);
            return usage;
        };
        for (const auto& path : paths) {
            auto result = resolve(path);
            if (!result.node) terminal("du: cannot access '" + path + "': " + reasonText(result.reason));
            else report(result.node, path, true);
        }
    }
    void tree(const Options& parsed, const Output& output) {
        auto path = parsed.paths.empty() ? "." : parsed.paths[0];
        auto result = resolve(path);
        if (!result.node) { terminal("tree: " + path + ": " + reasonText(result.reason)); return; }
        if (result.node->kind() != Kind::Directory) { terminal("tree: " + path + ": Not a directory"); return; }
        int directories = 0, files = 0;
        std::function<void(const NodePtr&, const std::string&)> draw;
        draw = [&](const NodePtr& node, const std::string& prefix) {
            std::vector<std::pair<std::string, NodePtr>> list;
            for (const auto& entry : node->entries()) if (parsed.flags.count('a') || entry.first[0] != '.') list.push_back(entry);
            for (std::size_t index = 0; index < list.size(); ++index) {
                const auto& [name, child] = list[index];
                bool last = index + 1 == list.size();
                output(prefix + (last ? "`-- " : "|-- ") + name + (child->kind() == Kind::Link ? " -> " + child->target() : ""));
                if (child->kind() == Kind::Directory) { ++directories; draw(child, prefix + (last ? "    " : "|   ")); }
                else ++files;
            }
        };
        output(path); draw(result.node, "");
        output(std::to_string(directories) + (directories == 1 ? " directory, " : " directories, ") + std::to_string(files) + (files == 1 ? " file" : " files"));
    }
    void execute(const std::string& text, const Strings& input, const Output& output) {
        std::istringstream words(text);
        std::string command;
        words >> command;
        Strings arguments;
        for (std::string word; words >> word;) arguments.push_back(word);
        auto parsed = options(arguments);
        if (command == "pwd") output(absolute(current));
        else if (command == "echo") output(text.substr(text.find(' ') + 1));
        else if (command == "cd") {
            std::string path = arguments.empty() ? "/" : arguments[0];
            bool old = path == "-";
            if (old) {
                if (!previous) { terminal("cd: OLDPWD not set"); return; }
                path = *previous;
            }
            auto result = resolve(path);
            if (!result.node) terminal("cd: " + path + ": " + reasonText(result.reason));
            else if (result.node->kind() != Kind::Directory) terminal("cd: " + path + ": Not a directory");
            else {
                previous = absolute(current); current = result.node;
                if (old) output(absolute(current));
            }
        } else if (command == "mkdir") {
            for (const auto& path : parsed.paths) {
                auto result = resolve(path, false, parsed.flags.count('p') != 0);
                if (result.creationParent) create(result.creationParent, result.creationName, Directory{});
                else if (!result.node) terminal("mkdir: cannot create directory '" + path + "': " + reasonText(result.reason));
                else {
                    auto followed = parsed.flags.count('p') ? resolve(path).node : nullptr;
                    if (!followed || followed->kind() != Kind::Directory) terminal("mkdir: cannot create directory '" + path + "': File exists");
                }
            }
        } else if (command == "touch") {
            for (const auto& path : arguments) {
                auto result = resolve(path);
                if (result.creationParent) create(result.creationParent, result.creationName, File{});
                else if (result.node) result.node->modified = clock;
                else terminal("touch: cannot touch '" + path + "': " + reasonText(result.reason));
            }
        } else if (command == "ls") listing(parsed, output);
        else if (command == "stat") {
            for (const auto& path : arguments) {
                auto result = resolve(path, false);
                if (!result.node) { terminal("stat: cannot stat '" + path + "': " + reasonText(result.reason)); continue; }
                auto node = result.node;
                std::string kind = node->kind() == Kind::Directory ? "directory" : node->kind() == Kind::Link ? "symbolic link"
                    : node->lines().empty() ? "regular empty file" : "regular file";
                output(path + ": " + kind + ", size " + std::to_string(node->size()) + ", inode " + std::to_string(node->inode)
                    + ", links " + std::to_string(node->links()) + ", modified " + std::to_string(node->modified));
            }
        } else if (command == "rm") {
            for (const auto& path : parsed.paths) {
                auto problem = [&](const std::string& reason) { terminal("rm: cannot remove '" + path + "': " + reason); };
                auto last = lastComponent(path);
                if (last == "." || last == "..") { terminal("rm: refusing to remove '.' or '..' directory: skipping '" + path + "'"); continue; }
                auto result = resolve(path, false);
                if (!result.node) { if (!(parsed.flags.count('f') && result.reason == Reason::Missing)) problem(reasonText(result.reason)); }
                else if (result.node->kind() == Kind::Directory && !parsed.flags.count('r')) problem("Is a directory");
                else if (descendant(current, result.node)) problem("Device or resource busy");
                else detach(result.node);
            }
        } else if (command == "rmdir") {
            for (const auto& path : arguments) {
                auto problem = [&](const std::string& reason) { terminal("rmdir: failed to remove '" + path + "': " + reason); };
                auto last = lastComponent(path);
                if (last == "." || last == "..") { problem("Invalid argument"); continue; }
                auto result = resolve(path, false);
                if (!result.node) problem(reasonText(result.reason));
                else if (result.node->kind() != Kind::Directory) problem("Not a directory");
                else if (descendant(current, result.node)) problem("Device or resource busy");
                else if (!result.node->entries().empty()) problem("Directory not empty");
                else detach(result.node);
            }
        } else if (command == "mv") move(arguments);
        else if (command == "cp") copy(parsed);
        else if (command == "ln") {
            const auto& path = arguments[2];
            auto result = resolve(path, false);
            if (result.creationParent) create(result.creationParent, result.creationName, Link{arguments[1]});
            else terminal("ln: failed to create symbolic link '" + path + "': " + (result.node ? "File exists" : reasonText(result.reason)));
        } else if (command == "readlink" || command == "realpath") {
            const auto& path = arguments[0];
            auto result = resolve(path, command == "realpath");
            if (!result.node) terminal(command + ": " + path + ": " + reasonText(result.reason));
            else if (command == "realpath") output(absolute(result.node));
            else if (result.node->kind() == Kind::Link) output(result.node->target());
            else terminal("readlink: " + path + ": Invalid argument");
        } else if (command == "find") find(arguments, output);
        else if (command == "du") diskUsage(parsed, output);
        else if (command == "tree") tree(parsed, output);
        else if (command == "cat" || command == "wc" || command == "head" || command == "tail" || command == "grep" || command == "sort" || command == "uniq") textCommand(command, arguments, input, output);
        else terminal(command + ": command not found");
    }
    static int numericValue(const std::string& line) {
        std::size_t position = !line.empty() && line[0] == '-' ? 1 : 0;
        int value = 0;
        while (position < line.size() && '0' <= line[position] && line[position] <= '9') value = value * 10 + line[position++] - '0';
        return !line.empty() && line[0] == '-' ? -value : value;
    }
    void textCommand(const std::string& command, const Strings& arguments, const Strings& input, const Output& output) {
        auto parsed = options(arguments);
        const auto& flags = parsed.flags;
        auto paths = parsed.paths;
        if (command == "grep") {
            auto pattern = paths.front();
            paths.erase(paths.begin());
            if (flags.count('i')) pattern = lower(pattern);
            bool named = paths.size() > 1 || flags.count('r');
            auto consume = [&](const Strings& lines, const std::optional<std::string>& name) {
                auto prefix = named ? *name + ":" : "";
                int count = 0;
                for (std::size_t index = 0; index < lines.size(); ++index) {
                    auto comparison = flags.count('i') ? lower(lines[index]) : lines[index];
                    bool matches = comparison.find(pattern) != std::string::npos;
                    if (matches == (flags.count('v') != 0)) continue;
                    ++count;
                    if (!flags.count('c')) output(prefix + (flags.count('n') ? std::to_string(index + 1) + ":" : "") + lines[index]);
                }
                if (flags.count('c')) output(prefix + std::to_string(count));
            };
            if (!flags.count('r')) inputs(command, paths, input, consume);
            else {
                if (paths.empty()) paths.push_back(".");
                for (const auto& path : paths) {
                    auto result = resolve(path);
                    if (!result.node) { terminal("grep: " + path + ": " + reasonText(result.reason)); continue; }
                    walkNodes(result.node, path, 0, 1000, [&](const NodePtr& node, const std::string& display, int) {
                        if (node->kind() == Kind::File) consume(node->lines(), display);
                    });
                }
            }
            return;
        }
        if (command == "sort") {
            Strings lines;
            inputs(command, paths, input, [&](const Strings& part, const std::optional<std::string>&) { lines.insert(lines.end(), part.begin(), part.end()); });
            std::sort(lines.begin(), lines.end(), [&](const auto& left, const auto& right) {
                if (flags.count('n')) {
                    int a = numericValue(left), b = numericValue(right);
                    if (a != b) return a < b;
                }
                return left < right;
            });
            if (flags.count('r')) std::reverse(lines.begin(), lines.end());
            for (const auto& line : lines) output(line);
            return;
        }
        std::string countText = "10";
        if (command == "head" || command == "tail") {
            std::size_t position = !arguments.empty() && arguments[0] == "-n" ? 2 : 0;
            if (position) countText = arguments[1];
            paths.assign(arguments.begin() + position, arguments.end());
        }
        std::array<Int, 3> totals{};
        auto reportCounts = [&](const std::array<Int, 3>& counts, const std::optional<std::string>& name) {
            std::string line;
            for (std::size_t index = 0; index < counts.size(); ++index) {
                if (flags.empty() || flags.count("lwc"[index])) {
                    if (!line.empty()) line += " ";
                    line += std::to_string(counts[index]);
                }
            }
            if (name) line += " " + *name;
            output(line);
        };
        inputs(command, paths, input, [&](const Strings& lines, const std::optional<std::string>& name) {
            if (command == "cat") {
                for (const auto& line : lines) output(line);
            } else if (command == "wc") {
                std::array<Int, 3> counts{static_cast<Int>(lines.size()), 0, 0};
                for (const auto& line : lines) {
                    counts[2] += static_cast<Int>(line.size()) + 1;
                    bool inside = false;
                    for (char character : line) {
                        if (character != ' ' && !inside) ++counts[1];
                        inside = character != ' ';
                    }
                }
                for (std::size_t index = 0; index < counts.size(); ++index) totals[index] += counts[index];
                reportCounts(counts, name);
            } else if (command == "head" || command == "tail") {
                int count = std::stoi(countText[0] == '-' || countText[0] == '+' ? countText.substr(1) : countText);
                int size = static_cast<int>(lines.size()), begin = 0, end = size;
                if (command == "head") end = countText[0] == '-' ? std::max(0, size - count) : std::min(size, count);
                else begin = countText[0] == '+' ? std::min(size, std::max(0, count - 1)) : std::max(0, size - count);
                for (int index = begin; index < end; ++index) output(lines[index]);
            } else {
                for (std::size_t begin = 0; begin < lines.size();) {
                    auto end = begin + 1;
                    while (end < lines.size() && lines[end] == lines[begin]) ++end;
                    output((flags.count('c') ? std::to_string(end - begin) + " " : "") + lines[begin]);
                    begin = end;
                }
            }
        });
        if (command == "wc" && paths.size() > 1) reportCounts(totals, "total");
    }

public:
    explicit Shell(Output print) : terminal(std::move(print)) { root->parent = root; }
    void process(const std::string& line) {
        ++clock;
        terminal(absolute(current) + "$ " + line);
        auto redirect = line.find(" >> ");
        bool append = redirect != std::string::npos;
        if (!append) redirect = line.find(" > ");
        NodePtr redirectFile;
        std::string pipeline = line;
        if (redirect != std::string::npos) {
            auto path = line.substr(redirect + (append ? 4 : 3));
            pipeline = line.substr(0, redirect);
            auto result = resolve(path);
            if (result.creationParent) redirectFile = create(result.creationParent, result.creationName, File{});
            else if (!result.node) { terminal("sh: " + path + ": " + reasonText(result.reason)); return; }
            else if (result.node->kind() == Kind::Directory) { terminal("sh: " + path + ": Is a directory"); return; }
            else {
                redirectFile = result.node;
                if (!append) write(redirectFile, {});
            }
        }
        auto commands = split(pipeline, " | ");
        Strings input;
        for (std::size_t index = 0; index < commands.size(); ++index) {
            Strings output;
            execute(commands[index], input, [&](const std::string& text) {
                if (index + 1 == commands.size() && !redirectFile) terminal(text);
                else output.push_back(text);
            });
            input = std::move(output);
        }
        if (redirectFile && !input.empty()) write(redirectFile, input, true);
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    Shell shell([](const std::string& line) { std::cout << line << '\n'; });
    for (std::string line; std::getline(std::cin, line) && line != "exit";) shell.process(line);
}
