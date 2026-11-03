#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iomanip>
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

using Tree = std::map<std::string, std::string>;
using Paths = std::set<std::string>;

static bool agree(const Tree& a, const Tree& b, const std::string& path) {
    Tree::const_iterator x = a.find(path);
    Tree::const_iterator y = b.find(path);
    return x == a.end() ? y == b.end() : y != b.end() && x->second == y->second;
}

static Paths pathsOf(const Tree& tree) {
    Paths paths;
    for (const auto& [path, content] : tree) paths.insert(path);
    return paths;
}

static Paths unite(Paths a, const Paths& b) {
    a.insert(b.begin(), b.end());
    return a;
}

static Paths differing(const Tree& a, const Tree& b) {
    Paths result;
    for (const std::string& path : unite(pathsOf(a), pathsOf(b))) {
        if (!agree(a, b, path)) result.insert(path);
    }
    return result;
}

static void matchPath(Tree& target, const Tree& source, const std::string& path) {
    Tree::const_iterator found = source.find(path);
    if (found == source.end()) target.erase(path);
    else target[path] = found->second;
}

static void changes(const Tree& oldTree, const Tree& newTree) {
    Paths paths = differing(oldTree, newTree);
    if (paths.empty()) std::cout << "(no changes)\n";
    for (const std::string& path : paths) {
        if (!oldTree.count(path)) std::cout << "A " << path << ": " << newTree.at(path) << '\n';
        else if (!newTree.count(path)) std::cout << "D " << path << ": " << oldTree.at(path) << '\n';
        else std::cout << "M " << path << ": " << oldTree.at(path) << " -> " << newTree.at(path) << '\n';
    }
}

struct MergeResult {
    Tree tree;
    Paths conflicts;
};

static MergeResult mergeTrees(const Tree& base, const Tree& ours, const Tree& theirs) {
    MergeResult result;
    Paths paths = unite(unite(pathsOf(base), pathsOf(ours)), pathsOf(theirs));
    for (const std::string& path : paths) {
        if (agree(theirs, base, path) || agree(ours, theirs, path)) {
            matchPath(result.tree, ours, path);
        } else if (agree(ours, base, path)) {
            matchPath(result.tree, theirs, path);
        } else {
            result.conflicts.insert(path);
            matchPath(result.tree, ours, path);
        }
    }
    return result;
}

static bool glob(const std::string& pattern, const std::string& path) {
    std::vector<bool> previous(path.size() + 1, false);
    previous[0] = true;
    for (char ch : pattern) {
        std::vector<bool> current(path.size() + 1, false);
        current[0] = ch == '*' && previous[0];
        for (std::size_t i = 1; i <= path.size(); ++i) {
            current[i] = ch == '*' ? previous[i] || current[i - 1]
                                  : previous[i - 1] && (ch == '?' || ch == path[i - 1]);
        }
        previous = current;
    }
    return previous[path.size()];
}

struct Commit {
    std::string id;
    std::vector<int> parents;
    Tree tree;
    std::string message;
    bool alive = true;
};

struct Stash {
    std::string label;
    int base;
    Tree tree;
};

class Repository {
    std::vector<Commit> commits;
    std::map<std::string, int> ids;
    std::map<std::string, int> branches;
    std::map<std::string, int> tags;
    std::string branch = "main";
    int detached = 0;
    Tree working;
    Tree index;
    Paths conflicts;
    std::string operation;
    int operationTarget = 0;
    std::vector<Stash> stashes;
    std::vector<std::string> ignores;

    [[noreturn]] static void fail(const std::string& message) {
        throw std::runtime_error(message);
    }

    int head() const {
        return branch.empty() ? detached : branches.at(branch);
    }

    const Tree& headTree() const {
        return commits[head()].tree;
    }

    void moveHead(int commit) {
        if (branch.empty()) detached = commit;
        else branches[branch] = commit;
    }

    int createCommit(std::vector<int> parents, Tree tree, std::string message) {
        std::ostringstream canonical;
        canonical << "commit " << commits.size() << '\n';
        for (int parent : parents) canonical << "parent " << commits[parent].id << '\n';
        for (const auto& [path, content] : tree) canonical << "file " << path << ' ' << content << '\n';
        canonical << "message " << message << '\n';
        std::int64_t hash = 0;
        for (unsigned char ch : canonical.str()) hash = (hash * 131 + ch) % 2147483647;
        std::ostringstream formatted;
        formatted << std::hex << std::setfill('0') << std::setw(8) << hash;
        int position = static_cast<int>(commits.size());
        commits.push_back({formatted.str(), std::move(parents), std::move(tree), std::move(message)});
        ids[commits.back().id] = position;
        return position;
    }

    void record(std::vector<int> parents, Tree tree, const std::string& message) {
        const Tree& oldTree = commits[parents[0]].tree;
        int added = 0;
        int modified = 0;
        int deleted = 0;
        for (const std::string& path : differing(oldTree, tree)) {
            if (!oldTree.count(path)) ++added;
            else if (!tree.count(path)) ++deleted;
            else ++modified;
        }
        int commit = createCommit(std::move(parents), std::move(tree), message);
        moveHead(commit);
        std::cout << '[' << (branch.empty() ? "detached HEAD" : branch) << ' '
                  << commits[commit].id << "] " << message << " (" << added << " added, "
                  << modified << " modified, " << deleted << " deleted)\n";
    }

    int resolve(const std::string& revision) const {
        std::size_t tilde = revision.find('~');
        std::string anchor = revision.substr(0, tilde);
        int commit;
        if (anchor == "HEAD") commit = head();
        else if (branches.count(anchor)) commit = branches.at(anchor);
        else if (tags.count(anchor)) commit = tags.at(anchor);
        else if (ids.count(anchor)) commit = ids.at(anchor);
        else fail("unknown revision '" + revision + "'");
        int steps = tilde == std::string::npos ? 0 : std::stoi(revision.substr(tilde + 1));
        while (steps-- > 0) {
            if (commits[commit].parents.empty()) fail("unknown revision '" + revision + "'");
            commit = commits[commit].parents[0];
        }
        return commit;
    }

    std::vector<int> distances(int start) const {
        std::vector<int> result(commits.size(), -1);
        std::queue<int> pending;
        result[start] = 0;
        pending.push(start);
        while (!pending.empty()) {
            int commit = pending.front();
            pending.pop();
            for (int parent : commits[commit].parents) {
                if (result[parent] < 0) {
                    result[parent] = result[commit] + 1;
                    pending.push(parent);
                }
            }
        }
        return result;
    }

    bool ancestor(int candidate, int commit) const {
        return distances(commit)[candidate] >= 0;
    }

    int mergeBase(int first, int second) const {
        std::vector<int> a = distances(first);
        std::vector<int> b = distances(second);
        std::vector<bool> excluded(commits.size(), false);
        for (std::size_t i = 0; i < commits.size(); ++i) {
            if (a[i] >= 0 && b[i] >= 0) {
                for (int parent : commits[i].parents) excluded[parent] = true;
            }
        }
        int best = -1;
        for (std::size_t i = 0; i < commits.size(); ++i) {
            if (a[i] < 0 || b[i] < 0 || excluded[i]) continue;
            if (best < 0 || std::max(a[i], b[i]) < std::max(a[best], b[best]) ||
                (std::max(a[i], b[i]) == std::max(a[best], b[best]) && static_cast<int>(i) > best)) {
                best = static_cast<int>(i);
            }
        }
        return best;
    }

    std::string summary(int commit) const {
        std::vector<std::string> references;
        if (head() == commit) references.push_back(branch.empty() ? "HEAD" : "HEAD -> " + branch);
        for (const auto& [name, target] : branches) {
            if (target == commit && name != branch) references.push_back(name);
        }
        for (const auto& [name, target] : tags) {
            if (target == commit) references.push_back("tag: " + name);
        }
        std::string text = commits[commit].id;
        if (!references.empty()) {
            text += " (";
            for (std::size_t i = 0; i < references.size(); ++i) {
                if (i > 0) text += ", ";
                text += references[i];
            }
            text += ')';
        }
        return text + ' ' + commits[commit].message;
    }

    bool ignored(const std::string& path) const {
        if (index.count(path) || conflicts.count(path)) return false;
        return std::any_of(ignores.begin(), ignores.end(), [&](const std::string& pattern) {
            return glob(pattern, path);
        });
    }

    void checkProgress() const {
        if (!operation.empty()) fail(operation + " in progress");
    }

    bool uncommitted() const {
        if (index != headTree()) return true;
        for (const auto& [path, content] : index) {
            if (!agree(working, index, path)) return true;
        }
        return false;
    }

    void checkUncommitted() const {
        if (uncommitted()) fail("uncommitted changes");
    }

    void checkOverwrite(const Paths& paths) const {
        for (const std::string& path : paths) {
            if (!agree(index, headTree(), path) || !agree(working, headTree(), path)) {
                fail("local changes to '" + path + "' would be overwritten");
            }
        }
    }

    void switchTree(const Tree& tree) {
        Paths changed = differing(headTree(), tree);
        checkOverwrite(changed);
        for (const std::string& path : changed) {
            matchPath(index, tree, path);
            matchPath(working, tree, path);
        }
    }

    void apply(const Tree& base, const Tree& theirs, const std::string& kind,
               int target, const std::string& message, std::vector<int> parents,
               int mergeBaseCommit = -1) {
        Tree ours = headTree();
        MergeResult result = mergeTrees(base, ours, theirs);
        Paths changed = differing(ours, result.tree);
        checkOverwrite(unite(changed, result.conflicts));
        if (kind == "merge") std::cout << "Merge base " << commits[mergeBaseCommit].id << '\n';
        if (kind != "merge" && result.conflicts.empty() && result.tree == ours) {
            std::cout << "nothing to commit\n";
            return;
        }
        for (const std::string& path : changed) {
            matchPath(index, result.tree, path);
            matchPath(working, result.tree, path);
        }
        if (result.conflicts.empty()) {
            record(std::move(parents), result.tree, message);
            return;
        }
        for (const std::string& path : result.conflicts) {
            std::string ourText = ours.count(path) ? ours.at(path) : "(deleted)";
            std::string theirText = theirs.count(path) ? theirs.at(path) : "(deleted)";
            working[path] = "<<<<<<< " + ourText + " ======= " + theirText + " >>>>>>>";
            std::cout << "CONFLICT " << path << '\n';
        }
        conflicts = result.conflicts;
        operation = kind;
        operationTarget = target;
        if (kind == "merge") std::cout << "Automatic merge failed; fix conflicts and then commit the result.\n";
        else std::cout << "error: could not " << (kind == "revert" ? "revert " : "apply ") << commits[target].id << '\n';
    }

    void status() const {
        if (branch.empty()) std::cout << "HEAD detached at " << commits[head()].id << '\n';
        else std::cout << "On branch " << branch << '\n';
        if (!operation.empty()) {
            std::string title = operation == "merge" ? "Merging" : operation == "revert" ? "Reverting" : "Cherry-picking";
            std::cout << title << ' ' << commits[operationTarget].id << '\n';
        }
        bool printed = false;
        Paths all = unite(unite(unite(pathsOf(headTree()), pathsOf(index)), pathsOf(working)), conflicts);
        for (const std::string& path : all) {
            if (conflicts.count(path)) {
                std::cout << "UU " << path << '\n';
                printed = true;
            } else if (index.count(path)) {
                char x = !headTree().count(path) ? 'A' : agree(headTree(), index, path) ? '.' : 'M';
                char y = !working.count(path) ? 'D' : agree(working, index, path) ? '.' : 'M';
                if (x != '.' || y != '.') {
                    std::cout << x << y << ' ' << path << '\n';
                    printed = true;
                }
            } else {
                if (headTree().count(path)) {
                    std::cout << "D. " << path << '\n';
                    printed = true;
                }
                if (working.count(path) && !ignored(path)) {
                    std::cout << "?? " << path << '\n';
                    printed = true;
                }
            }
        }
        if (!printed) std::cout << "nothing to commit, working tree clean\n";
    }

    std::vector<int> roots(bool includeSaved) const {
        std::vector<int> result = {head()};
        for (const auto& [name, commit] : branches) result.push_back(commit);
        for (const auto& [name, commit] : tags) result.push_back(commit);
        if (includeSaved) {
            for (const Stash& stash : stashes) result.push_back(stash.base);
            if (!operation.empty()) result.push_back(operationTarget);
        }
        return result;
    }

    std::set<int> reachable(bool includeSaved) const {
        std::set<int> result;
        for (int root : roots(includeSaved)) {
            std::vector<int> depth = distances(root);
            for (std::size_t i = 0; i < depth.size(); ++i) {
                if (depth[i] >= 0) result.insert(static_cast<int>(i));
            }
        }
        return result;
    }

    void graph() const {
        std::set<int> visible = reachable(false);
        std::vector<int> lanes;
        for (auto it = visible.rbegin(); it != visible.rend(); ++it) {
            int commit = *it;
            auto lane = std::find(lanes.begin(), lanes.end(), commit);
            if (lane == lanes.end()) {
                lanes.push_back(commit);
                lane = lanes.end() - 1;
            }
            std::size_t first = static_cast<std::size_t>(lane - lanes.begin());
            for (std::size_t i = 0; i < lanes.size(); ++i) {
                if (i > 0) std::cout << ' ';
                std::cout << (i == first ? '*' : lanes[i] == commit ? '/' : '|');
            }
            std::cout << ' ' << summary(commit) << '\n';
            for (std::size_t i = lanes.size(); i-- > first + 1;) {
                if (lanes[i] == commit) lanes.erase(lanes.begin() + static_cast<std::ptrdiff_t>(i));
            }
            const std::vector<int>& parents = commits[commit].parents;
            if (parents.empty()) lanes.erase(lanes.begin() + static_cast<std::ptrdiff_t>(first));
            else {
                lanes[first] = parents[0];
                if (parents.size() == 2 && std::find(lanes.begin(), lanes.end(), parents[1]) == lanes.end()) {
                    lanes.insert(lanes.begin() + static_cast<std::ptrdiff_t>(first + 1), parents[1]);
                }
            }
        }
    }

    void rebase(int upstream) {
        checkProgress();
        if (ancestor(upstream, head())) {
            std::cout << "Already up to date\n";
            return;
        }
        checkUncommitted();
        std::vector<int> old;
        for (int commit = head(); !ancestor(commit, upstream); commit = commits[commit].parents[0]) {
            old.push_back(commit);
        }
        std::reverse(old.begin(), old.end());
        Tree result = commits[upstream].tree;
        std::vector<std::optional<Tree>> replay;
        for (int commit : old) {
            MergeResult merged = mergeTrees(commits[commits[commit].parents[0]].tree, result, commits[commit].tree);
            if (!merged.conflicts.empty()) {
                fail("could not rebase " + commits[commit].id + ": conflict in '" + *merged.conflicts.begin() + "'");
            }
            if (merged.tree == result) replay.push_back(std::nullopt);
            else replay.push_back(merged.tree);
            result = std::move(merged.tree);
        }
        switchTree(result);
        int target = upstream;
        for (std::size_t i = 0; i < old.size(); ++i) {
            int source = old[i];
            if (!replay[i]) std::cout << "skip " << commits[source].id << ' ' << commits[source].message << '\n';
            else {
                std::string message = commits[source].message;
                int replacement = createCommit({target}, *replay[i], message);
                std::cout << "pick " << commits[source].id << " -> " << commits[replacement].id << ' ' << message << '\n';
                target = replacement;
            }
        }
        moveHead(target);
        std::cout << "HEAD is now at " << commits[target].id << ' ' << commits[target].message << '\n';
    }

    void stash(const std::vector<std::string>& words) {
        if (words.size() == 1) {
            checkProgress();
            if (!uncommitted()) {
                std::cout << "No local changes to save\n";
                return;
            }
            Tree saved;
            for (const std::string& path : unite(pathsOf(index), pathsOf(headTree()))) {
                matchPath(saved, working, path);
                matchPath(working, headTree(), path);
            }
            index = headTree();
            std::string label = "WIP on " + (branch.empty() ? "(no branch)" : branch) + ": " + commits[head()].id + ' ' + commits[head()].message;
            stashes.insert(stashes.begin(), {label, head(), saved});
            std::cout << "Saved stash@{0}: " << label << '\n';
        } else if (words[1] == "LIST") {
            if (stashes.empty()) std::cout << "(no stash entries)\n";
            for (std::size_t i = 0; i < stashes.size(); ++i) {
                std::cout << "stash@{" << i << "}: " << stashes[i].label << '\n';
            }
        } else {
            if (stashes.empty()) fail("no stash entries");
            Stash saved = stashes.front();
            if (words[1] == "DROP") {
                stashes.erase(stashes.begin());
                std::cout << "Dropped stash@{0}: " << saved.label << '\n';
                return;
            }
            checkProgress();
            checkUncommitted();
            MergeResult result = mergeTrees(commits[saved.base].tree, headTree(), saved.tree);
            if (!result.conflicts.empty()) fail("stash conflict in '" + *result.conflicts.begin() + "'");
            Paths changed = differing(headTree(), result.tree);
            checkOverwrite(changed);
            for (const std::string& path : changed) matchPath(working, result.tree, path);
            stashes.erase(stashes.begin());
            std::cout << "Restored stash@{0}: " << saved.label << '\n';
            changes(headTree(), result.tree);
        }
    }

public:
    Repository() {
        branches["main"] = createCommit({}, {}, "init");
    }

    void execute(const std::string& line) {
        std::istringstream input(line);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(word);
        const std::string& command = words[0];
        std::string path = words.size() > 1 ? words[1] : "";
        if (command == "WRITE") {
            working[path] = line.substr(line.find(' ', line.find(' ') + 1) + 1);
        } else if (command == "REMOVE") {
            if (!working.count(path)) fail("no such file '" + path + "'");
            working.erase(path);
        } else if (command == "ADD") {
            if (path == "ALL") {
                Paths allowed;
                for (const std::string& candidate : unite(pathsOf(working), pathsOf(index))) {
                    if (!ignored(candidate)) allowed.insert(candidate);
                }
                for (const std::string& candidate : allowed) matchPath(index, working, candidate);
                conflicts.clear();
            } else {
                if (working.count(path) && ignored(path)) fail("path '" + path + "' is ignored");
                if (!working.count(path) && !index.count(path) && !conflicts.count(path)) {
                    fail("pathspec '" + path + "' did not match any files");
                }
                matchPath(index, working, path);
                conflicts.erase(path);
            }
        } else if (command == "RM") {
            if (!index.count(path)) fail("pathspec '" + path + "' did not match any files");
            index.erase(path);
            working.erase(path);
            conflicts.erase(path);
        } else if (command == "UNSTAGE") {
            if (!index.count(path) && !headTree().count(path)) fail("pathspec '" + path + "' did not match any files");
            matchPath(index, headTree(), path);
        } else if (command == "RESTORE") {
            if (words.size() == 2) {
                if (!index.count(path)) fail("pathspec '" + path + "' did not match any files");
                working[path] = index.at(path);
            } else {
                const Tree& tree = commits[resolve(words[2])].tree;
                if (!tree.count(path)) fail("path '" + path + "' does not exist in '" + words[2] + "'");
                index[path] = working[path] = tree.at(path);
                conflicts.erase(path);
            }
        } else if (command == "IGNORE") {
            ignores.push_back(path);
        } else if (command == "COMMIT" || command == "AMEND") {
            std::string message = line.substr(line.find(' ') + 1);
            int old = head();
            if (command == "AMEND") {
                checkProgress();
                if (commits[old].parents.empty()) fail("cannot amend the root commit");
                record(commits[old].parents, index, message);
            } else {
                if (!conflicts.empty()) fail("unresolved conflicts");
                if (operation == "merge") record({old, operationTarget}, index, message);
                else if (index == headTree()) {
                    std::cout << "nothing to commit\n";
                    return;
                } else record({old}, index, message);
                operation.clear();
            }
        } else if (command == "STATUS") {
            status();
        } else if (command == "LS") {
            const Tree& tree = words.size() == 1 ? working : commits[resolve(path)].tree;
            if (tree.empty()) std::cout << "(empty)\n";
            for (const auto& [name, content] : tree) std::cout << name << ' ' << content << '\n';
        } else if (command == "CAT") {
            const Tree& tree = words.size() == 2 ? working : commits[resolve(words[2])].tree;
            if (!tree.count(path)) {
                if (words.size() == 2) fail("no such file '" + path + "'");
                fail("path '" + path + "' does not exist in '" + words[2] + "'");
            }
            std::cout << tree.at(path) << '\n';
        } else if (command == "DIFF") {
            if (words.size() == 1) {
                Tree tracked;
                for (const auto& [name, content] : working) {
                    if (index.count(name)) tracked[name] = content;
                }
                changes(index, tracked);
            } else if (path == "STAGED") changes(headTree(), index);
            else {
                int first = resolve(path);
                int second = resolve(words[2]);
                changes(commits[first].tree, commits[second].tree);
            }
        } else if (command == "LOG") {
            int limit = words.size() == 1 ? static_cast<int>(commits.size()) : std::stoi(path);
            int commit = head();
            while (limit-- > 0) {
                std::cout << summary(commit) << '\n';
                if (commits[commit].parents.empty()) break;
                commit = commits[commit].parents[0];
            }
        } else if (command == "SHOW") {
            int commit = resolve(words.size() == 1 ? "HEAD" : path);
            std::cout << "commit " << summary(commit) << "\nparents:";
            if (commits[commit].parents.empty()) std::cout << " none";
            for (int parent : commits[commit].parents) std::cout << ' ' << commits[parent].id;
            std::cout << '\n';
            Tree before = commits[commit].parents.empty() ? Tree{} : commits[commits[commit].parents[0]].tree;
            changes(before, commits[commit].tree);
        } else if (command == "BLAME") {
            if (!headTree().count(path)) fail("path '" + path + "' does not exist in 'HEAD'");
            std::string content = headTree().at(path);
            int commit = head();
            while (!commits[commit].parents.empty()) {
                int parent = commits[commit].parents[0];
                if (!commits[parent].tree.count(path) || commits[parent].tree.at(path) != content) break;
                commit = parent;
            }
            std::cout << commits[commit].id << " (" << commits[commit].message << ") " << content << '\n';
        } else if (command == "BRANCH" || command == "TAG") {
            bool isBranch = command == "BRANCH";
            std::map<std::string, int>& references = isBranch ? branches : tags;
            std::string kind = isBranch ? "branch" : "tag";
            if (path == "-d") {
                std::string name = words[2];
                if (!references.count(name)) fail("no such " + kind + " '" + name + "'");
                if (isBranch && branch == name) fail("cannot delete current branch '" + name + "'");
                int commit = references.at(name);
                if (isBranch && !ancestor(commit, head())) fail("branch '" + name + "' is not fully merged");
                references.erase(name);
                std::cout << "Deleted " << kind << ' ' << name << " (was " << commits[commit].id << ")\n";
            } else {
                if (references.count(path)) fail(kind + " '" + path + "' already exists");
                int commit = resolve(words.size() == 2 ? "HEAD" : words[2]);
                references[path] = commit;
                std::cout << "Created " << kind << ' ' << path << " at " << commits[commit].id << '\n';
            }
        } else if (command == "BRANCHES") {
            if (branch.empty()) std::cout << "* (HEAD detached at " << commits[head()].id << ")\n";
            for (const auto& [name, commit] : branches) {
                std::cout << (name == branch ? "* " : "  ") << name << ' ' << commits[commit].id << ' ' << commits[commit].message << '\n';
            }
        } else if (command == "TAGS") {
            if (tags.empty()) std::cout << "(no tags)\n";
            for (const auto& [name, commit] : tags) std::cout << name << ' ' << commits[commit].id << ' ' << commits[commit].message << '\n';
        } else if (command == "SWITCH") {
            if (!branches.count(path)) fail("no such branch '" + path + "'");
            if (path == branch) {
                std::cout << "Already on '" << path << "'\n";
                return;
            }
            checkProgress();
            switchTree(commits[branches.at(path)].tree);
            branch = path;
            std::cout << "Switched to branch '" << path << "'\n";
        } else if (command == "DETACH") {
            int commit = resolve(path);
            checkProgress();
            switchTree(commits[commit].tree);
            branch.clear();
            detached = commit;
            std::cout << "HEAD is now at " << commits[commit].id << ' ' << commits[commit].message << '\n';
        } else if (command == "MERGE") {
            int target = resolve(path);
            checkProgress();
            int old = head();
            if (ancestor(target, old)) std::cout << "Already up to date\n";
            else if (ancestor(old, target)) {
                switchTree(commits[target].tree);
                moveHead(target);
                std::cout << "Fast-forward " << commits[old].id << ".." << commits[target].id << '\n';
            } else {
                checkUncommitted();
                int base = mergeBase(old, target);
                apply(commits[base].tree, commits[target].tree, "merge", target, "Merge " + path, {old, target}, base);
            }
        } else if (command == "MERGEBASE") {
            int first = resolve(path);
            int second = resolve(words[2]);
            std::cout << commits[mergeBase(first, second)].id << '\n';
        } else if (command == "REBASE") {
            rebase(resolve(path));
        } else if (command == "RESET") {
            int commit = resolve(words[2]);
            const Tree& tree = commits[commit].tree;
            if (path == "HARD") {
                for (const std::string& name : unite(unite(pathsOf(index), pathsOf(tree)), conflicts)) {
                    matchPath(working, tree, name);
                }
            }
            if (path != "SOFT") index = tree;
            moveHead(commit);
            conflicts.clear();
            operation.clear();
            std::cout << "HEAD is now at " << commits[commit].id << ' ' << commits[commit].message << '\n';
        } else if (command == "REVERT" || command == "CHERRYPICK") {
            int commit = resolve(path);
            checkProgress();
            checkUncommitted();
            Tree before = commits[commit].parents.empty() ? Tree{} : commits[commits[commit].parents[0]].tree;
            std::string message = commits[commit].message;
            if (command == "REVERT") apply(commits[commit].tree, before, "revert", commit, "Revert \"" + message + '"', {head()});
            else apply(before, commits[commit].tree, "cherry-pick", commit, message, {head()});
        } else if (command == "STASH") {
            stash(words);
        } else if (command == "GRAPH") {
            graph();
        } else if (command == "DESCRIBE") {
            int commit = resolve(words.size() == 1 ? "HEAD" : path);
            std::vector<int> depth = distances(commit);
            std::string selected;
            int best = -1;
            for (const auto& [name, target] : tags) {
                if (depth[target] >= 0 && (best < 0 || depth[target] < best)) {
                    selected = name;
                    best = depth[target];
                }
            }
            if (best < 0) fail("no tag can describe '" + commits[commit].id + "'");
            std::cout << selected;
            if (best != 0) std::cout << '-' << best << "-g" << commits[commit].id;
            std::cout << '\n';
        } else if (command == "GC") {
            std::set<int> keep = reachable(true);
            int removed = 0;
            for (std::size_t i = 0; i < commits.size(); ++i) {
                if (commits[i].alive && !keep.count(static_cast<int>(i))) {
                    commits[i].alive = false;
                    ids.erase(commits[i].id);
                    ++removed;
                }
            }
            std::cout << "Removed unreachable commits: " << removed << '\n';
        }
    }
};

int main() {
    Repository repository;
    for (std::string line; std::getline(std::cin, line) && line != "EXIT";) {
        try {
            repository.execute(line);
        } catch (const std::runtime_error& error) {
            std::cout << "error: " << error.what() << '\n';
        }
    }
}
