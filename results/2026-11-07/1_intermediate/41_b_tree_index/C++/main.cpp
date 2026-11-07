#include <algorithm>
#include <functional>
#include <iostream>
#include <map>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

template<class... Parts>
std::string text(const Parts&... parts) {
    std::ostringstream stream;
    (stream << ... << parts);
    return stream.str();
}

std::string join(const std::vector<std::string>& words, const std::string& separator) {
    std::string result;
    for (const auto& word : words) {
        if (!result.empty()) result += separator;
        result += word;
    }
    return result;
}

struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const std::string& reason) { throw CommandError(reason); }
using Trace = std::vector<std::string>;
void emit(Trace* trace, const std::string& line) { if (trace) trace->push_back(line); }

struct Entry {
    int key;
    std::string value;
    std::string display() const { return text(key, '=', value); }
    bool operator==(const Entry& other) const { return key == other.key && value == other.value; }
};

struct Node {
    std::vector<Entry> entries;
    std::vector<int> children;
    bool leaf() const { return children.empty(); }
    int count() const { return static_cast<int>(entries.size()); }
    int position(int key) const {
        int index = 0;
        while (index < count() && entries[index].key < key) ++index;
        return index;
    }
    std::string notation() const {
        std::vector<std::string> keys;
        for (const auto& entry : entries) keys.push_back(std::to_string(entry.key));
        return '[' + join(keys, " ") + ']';
    }
    bool operator==(const Node& other) const { return entries == other.entries && children == other.children; }
};

struct SearchResult {
    int page = -1, index = -1;
    std::vector<std::string> path;
    bool found() const { return page >= 0; }
};

class Tree {
public:
    using Snapshot = std::map<int, Node>;
    struct Changes { int writes = 0, frees = 0; };
    struct Scan { std::vector<Entry> entries; int visited = 0; };
    struct Upsert { bool inserted; std::string old; };
    int degree, root = 0, splits = 0, merges = 0, borrows = 0;
    Snapshot pages{{0, Node{}}};

    explicit Tree(int degree) : degree(degree) {}
    std::vector<Entry> entries() const {
        std::vector<Entry> result;
        std::function<void(int)> visit = [&](int page) {
            const auto& node = pages.at(page);
            if (!node.leaf()) visit(node.children[0]);
            for (int index = 0; index < node.count(); ++index) {
                result.push_back(node.entries[index]);
                if (!node.leaf()) visit(node.children[index + 1]);
            }
        };
        visit(root);
        return result;
    }
    int height() const {
        int height = 0, page = root;
        while (!pages.at(page).leaf()) { ++height; page = pages.at(page).children[0]; }
        return height;
    }
    Changes changes(const Snapshot& before) const {
        Changes result;
        for (const auto& [page, node] : pages) {
            auto previous = before.find(page);
            if (previous == before.end() || !(previous->second == node)) ++result.writes;
        }
        for (const auto& [page, node] : before) if (!pages.count(page)) ++result.frees;
        return result;
    }
    int allocate(Node node) {
        int page = 0;
        while (pages.count(page)) ++page;
        pages.emplace(page, std::move(node));
        return page;
    }
    SearchResult search(int key) const {
        SearchResult result;
        int page = root;
        while (true) {
            const auto& node = pages.at(page);
            result.path.push_back(node.notation());
            int index = node.position(key);
            if (index < node.count() && node.entries[index].key == key) {
                result.page = page; result.index = index; return result;
            }
            if (node.leaf()) return result;
            page = node.children[index];
        }
    }
    std::optional<std::string> violation() const {
        int referenceDepth = -1;
        std::function<std::optional<std::string>(int, const std::string&, int, std::optional<int>, std::optional<int>)> visit;
        visit = [&](int page, const std::string& location, int depth, std::optional<int> low, std::optional<int> high)
                -> std::optional<std::string> {
            const auto& node = pages.at(page);
            int minimum = page == root ? (node.leaf() ? 0 : 1) : degree - 1, maximum = 2 * degree - 1;
            auto at = text("at=", location, " node=", node.notation());
            if (node.count() < minimum || node.count() > maximum)
                return text("COUNT ", at, " keys=", node.count(), " allowed=", minimum, "..", maximum);
            for (int index = 0; index + 1 < node.count(); ++index) {
                if (node.entries[index].key >= node.entries[index + 1].key)
                    return text("ORDER ", at, ' ', node.entries[index].key, ">=", node.entries[index + 1].key);
            }
            for (const auto& entry : node.entries) {
                if ((low && entry.key <= *low) || (high && entry.key >= *high))
                    return text("RANGE ", at, " key=", entry.key, " low=", low ? std::to_string(*low) : "-inf",
                                " high=", high ? std::to_string(*high) : "+inf");
            }
            if (node.leaf()) {
                if (referenceDepth < 0) referenceDepth = depth;
                else if (depth != referenceDepth) return text("DEPTH ", at, " depth=", depth, " expected=", referenceDepth);
            }
            for (int index = 0; index < static_cast<int>(node.children.size()); ++index) {
                auto problem = visit(node.children[index], text(location, '.', index), depth + 1,
                    index == 0 ? low : std::optional<int>(node.entries[index - 1].key),
                    index == node.count() ? high : std::optional<int>(node.entries[index].key));
                if (problem) return problem;
            }
            return std::nullopt;
        };
        return visit(root, "root", 0, std::nullopt, std::nullopt);
    }
    static Tree load(int degree, const std::vector<std::string>& tokens) {
        Tree tree(degree);
        tree.pages.clear();
        std::size_t position = 0;
        int nextPage = 0;
        auto unexpected = [&] { fail(text("SYNTAX ", position + 1)); };
        auto readEntry = [&]() -> Entry {
            if (position == tokens.size() || tokens[position] == "(" || tokens[position] == ")") unexpected();
            const auto& token = tokens[position++];
            auto equals = token.find('=');
            return {std::stoi(token.substr(0, equals)), token.substr(equals + 1)};
        };
        std::function<int()> parse = [&]() {
            if (position == tokens.size() || tokens[position] != "(") unexpected();
            ++position;
            int page = nextPage++;
            Node node;
            if (position < tokens.size() && tokens[position] == "(") {
                node.children.push_back(parse());
                while (position == tokens.size() || tokens[position] != ")") {
                    node.entries.push_back(readEntry()); node.children.push_back(parse());
                }
            } else {
                while (position == tokens.size() || tokens[position] != ")") node.entries.push_back(readEntry());
            }
            ++position;
            tree.pages.emplace(page, std::move(node));
            return page;
        };
        tree.root = parse();
        if (position != tokens.size()) unexpected();
        return tree;
    }
    void split(int parentPage, int index, Trace* trace) {
        auto& parent = pages.at(parentPage);
        int childPage = parent.children[index];
        auto& child = pages.at(childPage);
        auto before = child.notation();
        Entry middle = child.entries[degree - 1];
        Node right;
        right.entries.assign(child.entries.begin() + degree, child.entries.end());
        if (!child.leaf()) right.children.assign(child.children.begin() + degree, child.children.end());
        int newPage = allocate(std::move(right));
        child.entries.resize(degree - 1);
        if (!child.leaf()) child.children.resize(degree);
        parent.entries.insert(parent.entries.begin() + index, middle);
        parent.children.insert(parent.children.begin() + index + 1, newPage);
        ++splits;
        emit(trace, text("STEP split page=", childPage, " keys=", before, " up=", middle.key, " new=", newPage));
    }
    Upsert upsert(int key, const std::string& value, Trace* trace = nullptr) {
        auto found = search(key);
        if (found.found()) {
            auto& entry = pages.at(found.page).entries[found.index];
            auto old = entry.value;
            entry.value = value;
            return {false, old};
        }
        if (pages.at(root).count() == 2 * degree - 1) {
            root = allocate(Node{{}, {root}});
            emit(trace, text("STEP grow page=", root));
            split(root, 0, trace);
        }
        int page = root;
        while (!pages.at(page).leaf()) {
            auto& node = pages.at(page);
            int index = node.position(key);
            if (pages.at(node.children[index]).count() == 2 * degree - 1) {
                split(page, index, trace);
                if (key > node.entries[index].key) ++index;
            }
            page = node.children[index];
        }
        auto& node = pages.at(page);
        node.entries.insert(node.entries.begin() + node.position(key), Entry{key, value});
        emit(trace, text("STEP place page=", page, " keys=", node.notation()));
        return {true, {}};
    }
    int merge(int parentPage, int index, const std::string& caseName, Trace* trace) {
        auto& parent = pages.at(parentPage);
        int leftPage = parent.children[index], rightPage = parent.children[index + 1];
        auto& left = pages.at(leftPage);
        const auto& right = pages.at(rightPage);
        left.entries.push_back(parent.entries[index]);
        left.entries.insert(left.entries.end(), right.entries.begin(), right.entries.end());
        left.children.insert(left.children.end(), right.children.begin(), right.children.end());
        parent.entries.erase(parent.entries.begin() + index);
        parent.children.erase(parent.children.begin() + index + 1);
        pages.erase(rightPage); ++merges;
        emit(trace, text("STEP ", caseName, " page=", parentPage, " merge=", leftPage, '+', rightPage, " keys=", left.notation()));
        if (parentPage == root && parent.entries.empty()) {
            root = leftPage; pages.erase(parentPage);
            emit(trace, text("STEP shrink page=", root));
        }
        return leftPage;
    }
    void removeAt(int page, int key, std::vector<std::string>& cases, Trace* trace) {
        auto& node = pages.at(page);
        int index = node.position(key);
        if (index < node.count() && node.entries[index].key == key) {
            if (node.leaf()) {
                cases.push_back("1"); node.entries.erase(node.entries.begin() + index);
                emit(trace, text("STEP 1 page=", page, " keys=", node.notation()));
                return;
            }
            int left = node.children[index], right = node.children[index + 1];
            if (pages.at(left).count() >= degree) {
                int last = left;
                while (!pages.at(last).leaf()) last = pages.at(last).children.back();
                Entry predecessor = pages.at(last).entries.back();
                cases.push_back("2a"); emit(trace, text("STEP 2a page=", page, " pred=", predecessor.key));
                removeAt(left, predecessor.key, cases, trace);
                node.entries[index] = predecessor;
            } else if (pages.at(right).count() >= degree) {
                int first = right;
                while (!pages.at(first).leaf()) first = pages.at(first).children[0];
                Entry successor = pages.at(first).entries[0];
                cases.push_back("2b"); emit(trace, text("STEP 2b page=", page, " succ=", successor.key));
                removeAt(right, successor.key, cases, trace);
                node.entries[index] = successor;
            } else {
                cases.push_back("2c");
                int child = merge(page, index, "2c", trace);
                removeAt(child, key, cases, trace);
            }
            return;
        }
        int childPage = node.children[index];
        if (pages.at(childPage).count() == degree - 1) {
            int leftPage = index > 0 ? node.children[index - 1] : -1;
            int rightPage = index < node.count() ? node.children[index + 1] : -1;
            auto& child = pages.at(childPage);
            if (leftPage >= 0 && pages.at(leftPage).count() >= degree) {
                auto& left = pages.at(leftPage);
                cases.push_back("3a-left");
                child.entries.insert(child.entries.begin(), node.entries[index - 1]);
                node.entries[index - 1] = left.entries.back(); left.entries.pop_back();
                if (!left.leaf()) {
                    child.children.insert(child.children.begin(), left.children.back()); left.children.pop_back();
                }
                ++borrows;
                emit(trace, text("STEP 3a-left page=", page, " child=", childPage, " from=", leftPage, " keys=", child.notation()));
            } else if (rightPage >= 0 && pages.at(rightPage).count() >= degree) {
                auto& right = pages.at(rightPage);
                cases.push_back("3a-right");
                child.entries.push_back(node.entries[index]);
                node.entries[index] = right.entries[0]; right.entries.erase(right.entries.begin());
                if (!right.leaf()) {
                    child.children.push_back(right.children[0]); right.children.erase(right.children.begin());
                }
                ++borrows;
                emit(trace, text("STEP 3a-right page=", page, " child=", childPage, " from=", rightPage, " keys=", child.notation()));
            } else if (leftPage >= 0) {
                cases.push_back("3b-left"); childPage = merge(page, index - 1, "3b-left", trace);
            } else {
                cases.push_back("3b-right"); childPage = merge(page, index, "3b-right", trace);
            }
        }
        removeAt(childPage, key, cases, trace);
    }
    void remove(int key) {
        std::vector<std::string> cases;
        removeAt(root, key, cases, nullptr);
    }
    Scan scan(int low, int high) const {
        Scan result;
        std::function<void(int)> visit = [&](int page) {
            ++result.visited;
            const auto& node = pages.at(page);
            for (int index = 0; index <= node.count(); ++index) {
                if (!node.leaf() && (index == 0 || node.entries[index - 1].key < high)
                    && (index == node.count() || node.entries[index].key > low)) visit(node.children[index]);
                if (index < node.count() && low <= node.entries[index].key && node.entries[index].key <= high)
                    result.entries.push_back(node.entries[index]);
            }
        };
        visit(root);
        return result;
    }
    std::string dump() const {
        std::vector<std::string> tokens;
        std::function<void(int)> visit = [&](int page) {
            const auto& node = pages.at(page);
            tokens.push_back("(");
            if (!node.leaf()) visit(node.children[0]);
            for (int index = 0; index < node.count(); ++index) {
                tokens.push_back(node.entries[index].display());
                if (!node.leaf()) visit(node.children[index + 1]);
            }
            tokens.push_back(")");
        };
        visit(root);
        return join(tokens, " ");
    }
    void compact() {
        auto source = entries();
        std::vector<int> children;
        std::vector<Node> built;
        int oldRoot;
        while (true) {
            int groups = (static_cast<int>(source.size()) + 2 * degree) / (2 * degree);
            int keys = static_cast<int>(source.size()) - groups + 1, size = keys / groups, extra = keys % groups;
            std::vector<int> nodes;
            std::vector<Entry> separators;
            int entryIndex = 0, childIndex = 0;
            for (int group = 0; group < groups; ++group) {
                int count = size + (group < extra ? 1 : 0);
                Node node;
                node.entries.assign(source.begin() + entryIndex, source.begin() + entryIndex + count);
                if (!children.empty()) node.children.assign(children.begin() + childIndex, children.begin() + childIndex + count + 1);
                nodes.push_back(static_cast<int>(built.size())); built.push_back(std::move(node));
                entryIndex += count; childIndex += count + 1;
                if (group + 1 < groups) separators.push_back(source[entryIndex++]);
            }
            if (groups == 1) { oldRoot = nodes[0]; break; }
            source = std::move(separators); children = std::move(nodes);
        }
        Snapshot replacement;
        int nextPage = 0;
        std::function<int(int)> renumber = [&](int oldPage) {
            int page = nextPage++;
            Node node = built[oldPage];
            for (int& child : node.children) child = renumber(child);
            replacement.emplace(page, std::move(node));
            return page;
        };
        root = renumber(oldRoot); pages = std::move(replacement);
        splits = merges = borrows = 0;
    }
};

enum class Verb {
    Create, Load, Insert, BulkLoad, Delete, DelRange, Get, Range, Count, Min, Max,
    Floor, Ceil, Rank, Select, Seek, Next, Prev, Print, Pages, Dump, Height, Stats,
    Verify, Rebuild, Compact, Save, Restore, Trace
};

const std::map<std::string, Verb> verbs{
    {"CREATE", Verb::Create}, {"LOAD", Verb::Load}, {"INSERT", Verb::Insert}, {"BULKLOAD", Verb::BulkLoad},
    {"DELETE", Verb::Delete}, {"DELRANGE", Verb::DelRange}, {"GET", Verb::Get}, {"RANGE", Verb::Range},
    {"COUNT", Verb::Count}, {"MIN", Verb::Min}, {"MAX", Verb::Max}, {"FLOOR", Verb::Floor}, {"CEIL", Verb::Ceil},
    {"RANK", Verb::Rank}, {"SELECT", Verb::Select}, {"SEEK", Verb::Seek}, {"NEXT", Verb::Next}, {"PREV", Verb::Prev},
    {"PRINT", Verb::Print}, {"PAGES", Verb::Pages}, {"DUMP", Verb::Dump}, {"HEIGHT", Verb::Height}, {"STATS", Verb::Stats},
    {"VERIFY", Verb::Verify}, {"REBUILD", Verb::Rebuild}, {"COMPACT", Verb::Compact}, {"SAVE", Verb::Save},
    {"RESTORE", Verb::Restore}, {"TRACE", Verb::Trace}
};

bool requiresValidTree(Verb verb) {
    switch (verb) {
    case Verb::Insert: case Verb::BulkLoad: case Verb::Delete: case Verb::DelRange: case Verb::Range: case Verb::Count:
    case Verb::Min: case Verb::Max: case Verb::Floor: case Verb::Ceil: case Verb::Rank: case Verb::Select:
    case Verb::Seek: case Verb::Next: case Verb::Prev: case Verb::Height: case Verb::Compact:
        return true;
    default: return false;
    }
}

enum class CursorKind { Unset, Key, Begin, End };
struct Cursor { CursorKind kind = CursorKind::Unset; int key = 0; };

class Workbench {
    std::optional<Tree> index, saved;
    Cursor cursor;
    bool trace = false;
    std::string summary(const std::string& prefix) const {
        return text(prefix, " nodes=", index->pages.size(), " keys=", index->entries().size(),
                    index->violation() ? " DAMAGED" : " OK");
    }
public:
    std::vector<std::string> command(const std::string& line) {
        std::istringstream input(line);
        std::string name, word;
        input >> name;
        std::vector<std::string> args;
        while (input >> word) args.push_back(word);
        Verb verb = verbs.at(name);
        if (verb == Verb::Trace) {
            trace = args[0] == "ON";
            return {text("TRACE ", args[0])};
        }
        int first = args.empty() ? 0 : std::stoi(args[0]);
        bool range = verb == Verb::DelRange || verb == Verb::Range || verb == Verb::Count;
        int second = range ? std::stoi(args[1]) : 0;
        if (verb == Verb::Create || verb == Verb::Load) {
            if (first < 2 || first > 5) fail(text("BAD DEGREE ", first));
            Tree replacement = verb == Verb::Create ? Tree(first)
                : Tree::load(first, std::vector<std::string>(args.begin() + 1, args.end()));
            index = std::move(replacement); cursor = {};
            return {verb == Verb::Create ? text("CREATE t=", first) : summary(text("LOAD t=", first))};
        }
        if (!index) fail("NO INDEX");
        Tree& tree = *index;
        if (requiresValidTree(verb) && tree.violation()) fail("DAMAGED");
        auto entries = tree.entries();
        if (range && first > second) fail(text("BAD RANGE ", first, ' ', second));
        if (verb == Verb::Select && (first < 1 || first > static_cast<int>(entries.size()))) fail(text("BAD POSITION ", first));
        if ((verb == Verb::Next || verb == Verb::Prev) && cursor.kind == CursorKind::Unset) fail("NO CURSOR");
        if (verb == Verb::Restore && !saved) fail("NO SAVE");
        std::vector<std::string> output;
        switch (verb) {
        case Verb::Insert: {
            auto before = tree.pages;
            int splits = tree.splits;
            auto result = tree.upsert(first, args[1], trace ? &output : nullptr);
            int writes = tree.changes(before).writes;
            output.push_back(result.inserted
                ? text("INSERT ", first, " NEW splits=", tree.splits - splits, " height=", tree.height(), " writes=", writes)
                : text("INSERT ", first, " UPDATED old=", result.old, " writes=", writes));
            break;
        }
        case Verb::BulkLoad: {
            auto before = tree.pages;
            int splits = tree.splits, inserted = 0, updated = 0;
            for (std::size_t position = 0; position < args.size(); position += 2) {
                if (tree.upsert(std::stoi(args[position]), args[position + 1]).inserted) ++inserted;
                else ++updated;
            }
            output.push_back(text("BULKLOAD pairs=", args.size() / 2, " new=", inserted, " updated=", updated,
                " splits=", tree.splits - splits, " height=", tree.height(), " writes=", tree.changes(before).writes));
            break;
        }
        case Verb::Delete: {
            auto found = tree.search(first);
            if (!found.found()) { output.push_back(text("DELETE ", first, " NOT FOUND")); break; }
            auto value = tree.pages.at(found.page).entries[found.index].value;
            auto before = tree.pages;
            std::vector<std::string> cases;
            tree.removeAt(tree.root, first, cases, trace ? &output : nullptr);
            auto changes = tree.changes(before);
            output.push_back(text("DELETE ", first, " REMOVED value=", value, " cases=", join(cases, ","),
                " height=", tree.height(), " writes=", changes.writes, " frees=", changes.frees));
            break;
        }
        case Verb::DelRange: {
            auto before = tree.pages;
            int merges = tree.merges, borrows = tree.borrows, removed = 0;
            for (const auto& entry : entries) if (first <= entry.key && entry.key <= second) { tree.remove(entry.key); ++removed; }
            auto changes = tree.changes(before);
            output.push_back(text("DELRANGE ", first, ' ', second, " removed=", removed, " merges=", tree.merges - merges,
                " borrows=", tree.borrows - borrows, " height=", tree.height(), " writes=", changes.writes, " frees=", changes.frees));
            break;
        }
        case Verb::Get: {
            auto found = tree.search(first);
            auto result = found.found() ? text("FOUND value=", tree.pages.at(found.page).entries[found.index].value) : "NOT FOUND";
            output.push_back(text("GET ", first, ' ', result, " path=", join(found.path, " -> ")));
            break;
        }
        case Verb::Range: case Verb::Count: {
            auto result = tree.scan(first, second);
            auto line = text(name, ' ', first, ' ', second, " count=", result.entries.size(), " visited=", result.visited);
            if (verb == Verb::Range) for (const auto& entry : result.entries) line += ' ' + entry.display();
            output.push_back(line);
            break;
        }
        case Verb::Min: case Verb::Max:
            output.push_back(text(name, ' ', entries.empty() ? "EMPTY" : (verb == Verb::Min ? entries.front() : entries.back()).display()));
            break;
        case Verb::Floor: case Verb::Ceil: {
            std::optional<Entry> selected;
            for (const auto& entry : entries) {
                if (verb == Verb::Floor && entry.key <= first) selected = entry;
                if (verb == Verb::Ceil && entry.key >= first) { selected = entry; break; }
            }
            output.push_back(text(name, ' ', first, ' ', selected ? selected->display() : "NONE"));
            break;
        }
        case Verb::Rank:
            output.push_back(text("RANK ", first, ' ', std::count_if(entries.begin(), entries.end(), [&](const Entry& entry) { return entry.key < first; })));
            break;
        case Verb::Select:
            output.push_back(text("SELECT ", first, ' ', entries[first - 1].display()));
            break;
        case Verb::Seek: {
            auto selected = std::find_if(entries.begin(), entries.end(), [&](const Entry& entry) { return entry.key >= first; });
            cursor = selected == entries.end() ? Cursor{CursorKind::End} : Cursor{CursorKind::Key, selected->key};
            output.push_back(text("SEEK ", first, ' ', selected == entries.end() ? "END" : selected->display()));
            break;
        }
        case Verb::Next: case Verb::Prev: {
            std::optional<Entry> selected;
            if (verb == Verb::Next) {
                for (const auto& entry : entries) {
                    if (cursor.kind == CursorKind::Begin || (cursor.kind == CursorKind::Key && entry.key > cursor.key)) { selected = entry; break; }
                }
                cursor = selected ? Cursor{CursorKind::Key, selected->key} : Cursor{CursorKind::End};
            } else {
                for (auto it = entries.rbegin(); it != entries.rend(); ++it) {
                    if (cursor.kind == CursorKind::End || (cursor.kind == CursorKind::Key && it->key < cursor.key)) { selected = *it; break; }
                }
                cursor = selected ? Cursor{CursorKind::Key, selected->key} : Cursor{CursorKind::Begin};
            }
            output.push_back(text(name, ' ', selected ? selected->display() : (verb == Verb::Next ? "END" : "BEGIN")));
            break;
        }
        case Verb::Print: {
            std::vector<int> level{tree.root};
            int depth = 0;
            while (!level.empty()) {
                auto line = text("LEVEL ", depth++);
                std::vector<int> next;
                for (int page : level) {
                    const auto& node = tree.pages.at(page);
                    line += ' ' + node.notation();
                    next.insert(next.end(), node.children.begin(), node.children.end());
                }
                output.push_back(line); level = std::move(next);
            }
            break;
        }
        case Verb::Pages:
            for (const auto& [page, node] : tree.pages) {
                std::vector<std::string> children;
                for (int child : node.children) children.push_back(std::to_string(child));
                output.push_back(text("PAGE ", page, ' ', node.notation(), " kids=", node.leaf() ? "-" : join(children, ",")));
            }
            break;
        case Verb::Dump: output.push_back(text("DUMP ", tree.degree, ' ', tree.dump())); break;
        case Verb::Height: output.push_back(text("HEIGHT ", tree.height())); break;
        case Verb::Stats: {
            int leaves = 0;
            for (const auto& [page, node] : tree.pages) if (node.leaf()) ++leaves;
            auto fill = 100 * entries.size() / ((2 * tree.degree - 1) * tree.pages.size());
            output.push_back(text("STATS t=", tree.degree, " nodes=", tree.pages.size(), " leaves=", leaves, " keys=", entries.size(),
                " fill=", fill, "% splits=", tree.splits, " merges=", tree.merges, " borrows=", tree.borrows));
            break;
        }
        case Verb::Verify: {
            auto problem = tree.violation();
            output.push_back(problem ? "VERIFY FAIL " + *problem : "VERIFY OK");
            break;
        }
        case Verb::Rebuild: {
            Tree replacement(tree.degree);
            for (const auto& entry : entries) replacement.upsert(entry.key, entry.value);
            index = std::move(replacement);
            output.push_back(text("REBUILD entries=", entries.size(), " keys=", index->entries().size(), " nodes=", index->pages.size(),
                " splits=", index->splits, " height=", index->height()));
            break;
        }
        case Verb::Compact: {
            auto nodes = tree.pages.size();
            tree.compact();
            output.push_back(text("COMPACT nodes=", nodes, "->", tree.pages.size(), " height=", tree.height()));
            break;
        }
        case Verb::Save: saved = tree; output.push_back(summary("SAVE")); break;
        case Verb::Restore: index = *saved; output.push_back(summary("RESTORE")); break;
        case Verb::Create: case Verb::Load: case Verb::Trace: break;
        }
        return output;
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Workbench workbench;
    for (int index = 0; index < count; ++index) {
        std::getline(std::cin, line);
        try { for (const auto& result : workbench.command(line)) std::cout << result << '\n'; }
        catch (const CommandError& error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
}
