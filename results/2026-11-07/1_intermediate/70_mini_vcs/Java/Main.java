import java.io.*;
import java.util.*;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super(message);
        }
    }

    static class Commit {
        final String id, message;
        final int sequence;
        final List<Commit> parents;
        final TreeMap<String, String> tree;
        Commit(String id, int sequence, List<Commit> parents, Map<String, String> tree, String message) {
            this.id = id;
            this.sequence = sequence;
            this.parents = List.copyOf(parents);
            this.tree = new TreeMap<>(tree);
            this.message = message;
        }
    }

    record Merge(TreeMap<String, String> tree, TreeSet<String> conflicts, Map<String, String> contents) {}

    record Stash(String label, Commit base, TreeMap<String, String> tree) {}

    record Replay(Commit original, TreeMap<String, String> tree, boolean pick) {}

    static final LinkedHashMap<String, Commit> commits = new LinkedHashMap<>();
    static final TreeMap<String, Commit> branches = new TreeMap<>(), tags = new TreeMap<>();
    static final TreeMap<String, String> working = new TreeMap<>(), index = new TreeMap<>();
    static final TreeSet<String> conflicts = new TreeSet<>();
    static final List<Stash> stashes = new ArrayList<>();
    static final List<String> ignores = new ArrayList<>();

    static String branch = "main", operation;

    static Commit detached, target;

    static int nextSequence;

    static Commit head() {
        return branch == null ? detached : branches.get(branch);
    }

    static void moveHead(Commit commit) {
        if (branch == null) detached = commit;
        else branches.put(branch, commit);
    }

    static void require(boolean condition, String message) {
        if (!condition) throw new Problem(message);
    }

    static TreeSet<String> paths(Map<String, String>... trees) {
        TreeSet<String> result = new TreeSet<>();
        for (Map<String, String> tree : trees) result.addAll(tree.keySet());
        return result;
    }

    static boolean agree(Map<String, String> a, Map<String, String> b, String path) {
        return Objects.equals(a.get(path), b.get(path));
    }

    static TreeSet<String> differences(Map<String, String> a, Map<String, String> b) {
        TreeSet<String> result = paths(a, b);
        result.removeIf(path -> agree(a, b, path));
        return result;
    }

    static void match(Map<String, String> destination, Map<String, String> source, String path) {
        if (source.containsKey(path)) destination.put(path, source.get(path));
        else destination.remove(path);
    }

    static Commit create(List<Commit> parents, Map<String, String> tree, String message) {
        int sequence = nextSequence++;
        StringBuilder text = new StringBuilder("commit " + sequence + "\n");
        for (Commit parent : parents) text.append("parent ").append(parent.id).append('\n');
        for (String path : new TreeSet<>(tree.keySet())) text.append("file ").append(path).append(' ').append(tree.get(path)).append('\n');
        text.append("message ").append(message).append('\n');
        long hash = 0;
        for (int i = 0; i < text.length(); i++) hash = (hash * 131 + text.charAt(i)) % 2147483647L;
        String id = String.format(Locale.ROOT, "%08x", hash);
        Commit commit = new Commit(id, sequence, parents, tree, message);
        commits.put(id, commit);
        return commit;
    }

    static void record(List<Commit> parents, Map<String, String> tree, String message) {
        Commit commit = create(parents, tree, message);
        int added = 0, modified = 0, deleted = 0;
        Map<String, String> before = parents.getFirst().tree;
        for (String path : differences(before, tree)) {
            if (!before.containsKey(path)) added++;
            else if (!tree.containsKey(path)) deleted++;
            else modified++;
        }
        moveHead(commit);
        System.out.println("[" + (branch == null ? "detached HEAD" : branch) + " " + commit.id + "] " + message + " (" + added + " added, " + modified + " modified, " + deleted + " deleted)");
    }

    static Commit resolve(String revision) {
        String[] parts = revision.split("~");
        String anchor = parts[0];
        Commit commit = anchor.equals("HEAD") ? head() : branches.containsKey(anchor) ? branches.get(anchor) : tags.containsKey(anchor) ? tags.get(anchor) : commits.get(anchor);
        int steps = parts.length == 1 ? 0 : Integer.parseInt(parts[1]);
        while (commit != null && steps-- > 0) commit = commit.parents.isEmpty() ? null : commit.parents.getFirst();
        require(commit != null, "error: unknown revision '" + revision + "'");
        return commit;
    }

    static Map<Commit, Integer> distances(Commit start) {
        Map<Commit, Integer> result = new HashMap<>();
        ArrayDeque<Commit> queue = new ArrayDeque<>();
        result.put(start, 0);
        queue.add(start);
        while (!queue.isEmpty()) {
            Commit commit = queue.remove();
            for (Commit parent : commit.parents) if (!result.containsKey(parent)) {
                result.put(parent, result.get(commit) + 1);
                queue.add(parent);
            }
        }
        return result;
    }

    static boolean ancestor(Commit a, Commit b) {
        return distances(b).containsKey(a);
    }

    static Commit mergeBase(Commit a, Commit b) {
        Map<Commit, Integer> x = distances(a), y = distances(b);
        List<Commit> common = x.keySet().stream().filter(y::containsKey).toList();
        Commit best = null;
        int bestDistance = Integer.MAX_VALUE;
        for (Commit candidate : common) {
            if (common.stream().anyMatch(other -> other != candidate && ancestor(candidate, other))) continue;
            int distance = Math.max(x.get(candidate), y.get(candidate));
            if (best == null || distance < bestDistance || distance == bestDistance && candidate.sequence > best.sequence) {
                best = candidate;
                bestDistance = distance;
            }
        }
        return best;
    }

    static String summary(Commit commit) {
        List<String> refs = new ArrayList<>();
        if (head() == commit) refs.add(branch == null ? "HEAD" : "HEAD -> " + branch);
        branches.forEach((name, value) -> {
            if (value == commit && !name.equals(branch)) refs.add(name);
        });
        tags.forEach((name, value) -> {
            if (value == commit) refs.add("tag: " + name);
        });
        return commit.id + (refs.isEmpty() ? "" : " (" + String.join(", ", refs) + ")") + " " + commit.message;
    }

    static void changes(Map<String, String> a, Map<String, String> b) {
        var paths = differences(a, b);
        if (paths.isEmpty()) System.out.println("(no changes)");
        for (String path : paths) System.out.println(!a.containsKey(path) ? "A " + path + ": " + b.get(path) : !b.containsKey(path) ? "D " + path + ": " + a.get(path) : "M " + path + ": " + a.get(path) + " -> " + b.get(path));
    }

    static void progressCheck() {
        require(operation == null, "error: " + operation + " in progress");
    }

    static boolean dirty() {
        return !index.equals(head().tree) || index.keySet().stream().anyMatch(path -> !agree(working, index, path));
    }

    static void cleanCheck() {
        require(!dirty(), "error: uncommitted changes");
    }

    static void overwriteCheck(Collection<String> paths) {
        for (String path : new TreeSet<>(paths)) require(agree(index, head().tree, path) && agree(working, head().tree, path), "error: local changes to '" + path + "' would be overwritten");
    }

    static void switchTree(Map<String, String> tree) {
        var paths = differences(head().tree, tree);
        overwriteCheck(paths);
        for (String path : paths) {
            match(index, tree, path);
            match(working, tree, path);
        }
    }

    static Merge merge(Map<String, String> base, Map<String, String> ours, Map<String, String> theirs) {
        TreeMap<String, String> result = new TreeMap<>();
        TreeSet<String> problems = new TreeSet<>();
        Map<String, String> contents = new HashMap<>();
        for (String path : paths(base, ours, theirs)) {
            if (agree(theirs, base, path) || agree(ours, theirs, path)) match(result, ours, path);
            else if (agree(ours, base, path)) match(result, theirs, path);
            else {
                problems.add(path);
                match(result, ours, path);
                contents.put(path, "<<<<<<< " + ours.getOrDefault(path, "(deleted)") + " ======= " + theirs.getOrDefault(path, "(deleted)") + " >>>>>>>");
            }
        }
        return new Merge(result, problems, contents);
    }

    static void apply(Map<String, String> base, Map<String, String> theirs, String kind, Commit chosen, String message, List<Commit> parents, Commit mergeBase) {
        Merge result = merge(base, head().tree, theirs);
        var changed = differences(head().tree, result.tree());
        TreeSet<String> checked = new TreeSet<>(changed);
        checked.addAll(result.conflicts());
        overwriteCheck(checked);
        if (kind.equals("merge")) System.out.println("Merge base " + mergeBase.id);
        else if (result.conflicts().isEmpty() && changed.isEmpty()) {
            System.out.println("nothing to commit");
            return;
        }
        for (String path : changed) {
            match(index, result.tree(), path);
            match(working, result.tree(), path);
        }
        if (result.conflicts().isEmpty()) record(parents, result.tree(), message);
        else {
            for (String path : result.conflicts()) {
                working.put(path, result.contents().get(path));
                System.out.println("CONFLICT " + path);
            }
            conflicts.clear();
            conflicts.addAll(result.conflicts());
            operation = kind;
            target = chosen;
            System.out.println(kind.equals("merge") ? "Automatic merge failed; fix conflicts and then commit the result." : kind.equals("revert") ? "error: could not revert " + chosen.id : "error: could not apply " + chosen.id);
        }
    }

    static boolean glob(String pattern, String path) {
        boolean[][] dp = new boolean[pattern.length() + 1][path.length() + 1];
        dp[0][0] = true;
        for (int i = 0; i < pattern.length(); i++) for (int j = 0; j <= path.length(); j++) {
            if (pattern.charAt(i) == '*') dp[i + 1][j] = dp[i][j] || j > 0 && dp[i + 1][j - 1];
            else if (j > 0) dp[i + 1][j] = dp[i][j - 1] && (pattern.charAt(i) == '?' || pattern.charAt(i) == path.charAt(j - 1));
        }
        return dp[pattern.length()][path.length()];
    }

    static boolean ignored(String path) {
        return !index.containsKey(path) && !conflicts.contains(path) && ignores.stream().anyMatch(pattern -> glob(pattern, path));
    }

    static void pathspec(boolean valid, String path) {
        require(valid, "error: pathspec '" + path + "' did not match any files");
    }

    static Set<Commit> reachable(boolean extra) {
        Set<Commit> result = new HashSet<>();
        List<Commit> roots = new ArrayList<>(branches.values());
        roots.addAll(tags.values());
        roots.add(head());
        if (extra) {
            for (Stash stash : stashes) roots.add(stash.base());
            if (operation != null) roots.add(target);
        }
        for (Commit root : roots) result.addAll(distances(root).keySet());
        return result;
    }

    static void command(String line) {
        String[] words = line.split(" ");
        String command = words[0], path = words.length > 1 ? words[1] : null;
        switch (command) {
            case "WRITE":
                working.put(path, line.substring(line.indexOf(' ', line.indexOf(' ') + 1) + 1));
                break;
            case "REMOVE":
                require(working.containsKey(path), "error: no such file '" + path + "'");
                working.remove(path);
                break;
            case "IGNORE":
                ignores.add(path);
                break;
            case "ADD":
                if (path.equals("ALL")) {
                    List<String> selected = paths(working, index).stream().filter(p -> !ignored(p)).toList();
                    for (String p : selected) match(index, working, p);
                    conflicts.clear();
                } else {
                    require(!working.containsKey(path) || !ignored(path), "error: path '" + path + "' is ignored");
                    pathspec(working.containsKey(path) || index.containsKey(path) || conflicts.contains(path), path);
                    match(index, working, path);
                    conflicts.remove(path);
                }
                break;
            case "RM":
                pathspec(index.containsKey(path), path);
                index.remove(path);
                working.remove(path);
                conflicts.remove(path);
                break;
            case "UNSTAGE":
                pathspec(index.containsKey(path) || head().tree.containsKey(path), path);
                match(index, head().tree, path);
                break;
            case "RESTORE":
                if (words.length == 2) {
                    pathspec(index.containsKey(path), path);
                    working.put(path, index.get(path));
                } else {
                    Commit chosen = resolve(words[2]);
                    require(chosen.tree.containsKey(path), "error: path '" + path + "' does not exist in '" + words[2] + "'");
                    match(index, chosen.tree, path);
                    match(working, chosen.tree, path);
                    conflicts.remove(path);
                }
                break;
            case "COMMIT":
                require(conflicts.isEmpty(), "error: unresolved conflicts");
                if (!"merge".equals(operation) && index.equals(head().tree)) {
                    System.out.println("nothing to commit");
                    break;
                }
                record("merge".equals(operation) ? List.of(head(), target) : List.of(head()), index, line.substring(7));
                operation = null;
                target = null;
                break;
            case "AMEND":
                progressCheck();
                require(!head().parents.isEmpty(), "error: cannot amend the root commit");
                record(head().parents, index, line.substring(6));
                break;
            case "STATUS":
                {
                    System.out.println(branch == null ? "HEAD detached at " + head().id : "On branch " + branch);
                    if (operation != null) System.out.println((operation.equals("merge") ? "Merging " : operation.equals("revert") ? "Reverting " : "Cherry-picking ") + target.id);
                    var all = paths(head().tree, index, working);
                    all.addAll(conflicts);
                    boolean any = false;
                    for (String p : all) {
                        if (conflicts.contains(p)) {
                            System.out.println("UU " + p);
                            any = true;
                        } else if (index.containsKey(p)) {
                            char x = !head().tree.containsKey(p) ? 'A' : agree(head().tree, index, p) ? '.' : 'M';
                            char y = !working.containsKey(p) ? 'D' : agree(working, index, p) ? '.' : 'M';
                            if (x != '.' || y != '.') {
                                System.out.println("" + x + y + " " + p);
                                any = true;
                            }
                        } else {
                            if (head().tree.containsKey(p)) {
                                System.out.println("D. " + p);
                                any = true;
                            }
                            if (working.containsKey(p) && !ignored(p)) {
                                System.out.println("?? " + p);
                                any = true;
                            }
                        }
                    }
                    if (!any) System.out.println("nothing to commit, working tree clean");
                    break;
                }
            case "LS":
                {
                    Map<String, String> tree = words.length == 1 ? working : resolve(path).tree;
                    if (tree.isEmpty()) System.out.println("(empty)");
                    else tree.forEach((p, text) -> System.out.println(p + " " + text));
                    break;
                }
            case "CAT":
                {
                    Map<String, String> tree = words.length == 2 ? working : resolve(words[2]).tree;
                    require(tree.containsKey(path), words.length == 2 ? "error: no such file '" + path + "'" : "error: path '" + path + "' does not exist in '" + words[2] + "'");
                    System.out.println(tree.get(path));
                    break;
                }
            case "DIFF":
                if (words.length == 1) {
                    TreeMap<String, String> tracked = new TreeMap<>(working);
                    tracked.keySet().retainAll(index.keySet());
                    changes(index, tracked);
                } else if (words.length == 2) changes(head().tree, index);
                else {
                    Commit a = resolve(path), b = resolve(words[2]);
                    changes(a.tree, b.tree);
                }
                break;
            case "LOG":
                {
                    int limit = words.length == 1 ? Integer.MAX_VALUE : Integer.parseInt(path);
                    Commit chosen = head();
                    while (limit-- > 0) {
                        System.out.println(summary(chosen));
                        if (chosen.parents.isEmpty()) break;
                        chosen = chosen.parents.getFirst();
                    }
                    break;
                }
            case "SHOW":
                {
                    Commit chosen = resolve(words.length == 1 ? "HEAD" : path);
                    System.out.println("commit " + summary(chosen));
                    System.out.println("parents: " + (chosen.parents.isEmpty() ? "none" : String.join(" ", chosen.parents.stream().map(p -> p.id).toList())));
                    changes(chosen.parents.isEmpty() ? Map.of() : chosen.parents.getFirst().tree, chosen.tree);
                    break;
                }
            case "BLAME":
                {
                    require(head().tree.containsKey(path), "error: path '" + path + "' does not exist in 'HEAD'");
                    Commit chosen = head();
                    String text = chosen.tree.get(path);
                    while (!chosen.parents.isEmpty() && Objects.equals(chosen.parents.getFirst().tree.get(path), text)) chosen = chosen.parents.getFirst();
                    System.out.println(chosen.id + " (" + chosen.message + ") " + text);
                    break;
                }
            case "BRANCH":
            case "TAG":
                {
                    boolean tag = command.equals("TAG");
                    var refs = tag ? tags : branches;
                    String noun = tag ? "tag" : "branch";
                    if (path.equals("-d")) {
                        String name = words[2];
                        require(refs.containsKey(name), "error: no such " + noun + " '" + name + "'");
                        Commit chosen = refs.get(name);
                        if (!tag) {
                            require(!name.equals(branch), "error: cannot delete current branch '" + name + "'");
                            require(ancestor(chosen, head()), "error: branch '" + name + "' is not fully merged");
                        }
                        refs.remove(name);
                        System.out.println("Deleted " + noun + " " + name + " (was " + chosen.id + ")");
                    } else {
                        require(!refs.containsKey(path), "error: " + noun + " '" + path + "' already exists");
                        Commit chosen = resolve(words.length == 2 ? "HEAD" : words[2]);
                        refs.put(path, chosen);
                        System.out.println("Created " + noun + " " + path + " at " + chosen.id);
                    }
                    break;
                }
            case "BRANCHES":
                if (branch == null) System.out.println("* (HEAD detached at " + head().id + ")");
                branches.forEach((name, chosen) -> System.out.println((name.equals(branch) ? "* " : "  ") + name + " " + chosen.id + " " + chosen.message));
                break;
            case "TAGS":
                if (tags.isEmpty()) System.out.println("(no tags)");
                else tags.forEach((name, chosen) -> System.out.println(name + " " + chosen.id + " " + chosen.message));
                break;
            case "SWITCH":
                {
                    require(branches.containsKey(path), "error: no such branch '" + path + "'");
                    if (path.equals(branch)) {
                        System.out.println("Already on '" + path + "'");
                        break;
                    }
                    progressCheck();
                    switchTree(branches.get(path).tree);
                    branch = path;
                    System.out.println("Switched to branch '" + path + "'");
                    break;
                }
            case "DETACH":
                {
                    Commit chosen = resolve(path);
                    progressCheck();
                    switchTree(chosen.tree);
                    branch = null;
                    detached = chosen;
                    System.out.println("HEAD is now at " + chosen.id + " " + chosen.message);
                    break;
                }
            case "MERGEBASE":
                {
                    Commit a = resolve(path), b = resolve(words[2]);
                    System.out.println(mergeBase(a, b).id);
                    break;
                }
            case "MERGE":
                {
                    Commit chosen = resolve(path), before = head();
                    progressCheck();
                    if (ancestor(chosen, before)) {
                        System.out.println("Already up to date");
                        break;
                    }
                    if (ancestor(before, chosen)) {
                        switchTree(chosen.tree);
                        moveHead(chosen);
                        System.out.println("Fast-forward " + before.id + ".." + chosen.id);
                        break;
                    }
                    cleanCheck();
                    Commit base = mergeBase(before, chosen);
                    apply(base.tree, chosen.tree, "merge", chosen, "Merge " + path, List.of(before, chosen), base);
                    break;
                }
            case "RESET":
                {
                    Commit chosen = resolve(words[2]);
                    if (path.equals("HARD")) {
                        var all = paths(index, chosen.tree);
                        all.addAll(conflicts);
                        for (String p : all) match(working, chosen.tree, p);
                    }
                    if (!path.equals("SOFT")) {
                        index.clear();
                        index.putAll(chosen.tree);
                    }
                    moveHead(chosen);
                    conflicts.clear();
                    operation = null;
                    target = null;
                    System.out.println("HEAD is now at " + chosen.id + " " + chosen.message);
                    break;
                }
            case "REVERT":
            case "CHERRYPICK":
                {
                    Commit chosen = resolve(path);
                    progressCheck();
                    cleanCheck();
                    Map<String, String> parent = chosen.parents.isEmpty() ? Map.of() : chosen.parents.getFirst().tree;
                    boolean revert = command.equals("REVERT");
                    apply(revert ? chosen.tree : parent, revert ? parent : chosen.tree, revert ? "revert" : "cherry-pick", chosen, revert ? "Revert \"" + chosen.message + "\"" : chosen.message, List.of(head()), null);
                    break;
                }
            case "REBASE":
                {
                    Commit upstream = resolve(path);
                    progressCheck();
                    if (ancestor(upstream, head())) {
                        System.out.println("Already up to date");
                        break;
                    }
                    cleanCheck();
                    List<Commit> old = new ArrayList<>();
                    Commit cursor = head();
                    while (!ancestor(cursor, upstream)) {
                        old.add(cursor);
                        cursor = cursor.parents.getFirst();
                    }
                    Collections.reverse(old);
                    List<Replay> replay = new ArrayList<>();
                    TreeMap<String, String> tree = new TreeMap<>(upstream.tree);
                    for (Commit commit : old) {
                        Merge result = merge(commit.parents.getFirst().tree, tree, commit.tree);
                        require(result.conflicts().isEmpty(), "error: could not rebase " + commit.id + ": conflict in '" + (result.conflicts().isEmpty() ? "" : result.conflicts().first()) + "'");
                        boolean pick = !tree.equals(result.tree());
                        replay.add(new Replay(commit, result.tree(), pick));
                        tree = result.tree();
                    }
                    switchTree(tree);
                    Commit current = upstream;
                    for (Replay item : replay) if (item.pick()) {
                        Commit created = create(List.of(current), item.tree(), item.original().message);
                        System.out.println("pick " + item.original().id + " -> " + created.id + " " + created.message);
                        current = created;
                    } else System.out.println("skip " + item.original().id + " " + item.original().message);
                    moveHead(current);
                    System.out.println("HEAD is now at " + current.id + " " + current.message);
                    break;
                }
            case "STASH":
                {
                    if (words.length > 1 && path.equals("LIST")) {
                        if (stashes.isEmpty()) System.out.println("(no stash entries)");
                        for (int i = 0; i < stashes.size(); i++) System.out.println("stash@{" + i + "}: " + stashes.get(i).label());
                        break;
                    }
                    if (words.length > 1) {
                        require(!stashes.isEmpty(), "error: no stash entries");
                        Stash stash = stashes.getFirst();
                        if (path.equals("DROP")) {
                            stashes.removeFirst();
                            System.out.println("Dropped stash@{0}: " + stash.label());
                            break;
                        }
                        progressCheck();
                        cleanCheck();
                        Merge result = merge(stash.base().tree, head().tree, stash.tree());
                        require(result.conflicts().isEmpty(), "error: stash conflict in '" + (result.conflicts().isEmpty() ? "" : result.conflicts().first()) + "'");
                        var changed = differences(head().tree, result.tree());
                        overwriteCheck(changed);
                        for (String p : changed) match(working, result.tree(), p);
                        stashes.removeFirst();
                        System.out.println("Restored stash@{0}: " + stash.label());
                        changes(head().tree, result.tree());
                    } else {
                        progressCheck();
                        if (!dirty()) {
                            System.out.println("No local changes to save");
                            break;
                        }
                        TreeMap<String, String> saved = new TreeMap<>();
                        var tracked = paths(index, head().tree);
                        for (String p : tracked) if (working.containsKey(p)) saved.put(p, working.get(p));
                        for (String p : tracked) match(working, head().tree, p);
                        index.clear();
                        index.putAll(head().tree);
                        String label = "WIP on " + (branch == null ? "(no branch)" : branch) + ": " + head().id + " " + head().message;
                        stashes.addFirst(new Stash(label, head(), saved));
                        System.out.println("Saved stash@{0}: " + label);
                    }
                    break;
                }
            case "GRAPH":
                {
                    List<Commit> ordered = new ArrayList<>(reachable(false));
                    ordered.sort(Comparator.comparingInt((Commit c) -> c.sequence).reversed());
                    List<Commit> lanes = new ArrayList<>();
                    for (Commit commit : ordered) {
                        if (!lanes.contains(commit)) lanes.add(commit);
                        int first = lanes.indexOf(commit);
                        List<String> symbols = new ArrayList<>();
                        for (int i = 0; i < lanes.size(); i++) symbols.add(i == first ? "*" : lanes.get(i) == commit ? "/" : "|");
                        System.out.println(String.join(" ", symbols) + " " + summary(commit));
                        for (int i = lanes.size() - 1; i > first; i--) if (lanes.get(i) == commit) lanes.remove(i);
                        if (commit.parents.isEmpty()) lanes.remove(first);
                        else {
                            lanes.set(first, commit.parents.getFirst());
                            if (commit.parents.size() == 2 && !lanes.contains(commit.parents.get(1))) lanes.add(first + 1, commit.parents.get(1));
                        }
                    }
                    break;
                }
            case "DESCRIBE":
                {
                    Commit chosen = resolve(words.length == 1 ? "HEAD" : path);
                    var distance = distances(chosen);
                    String best = null;
                    int minimum = Integer.MAX_VALUE;
                    for (var entry : tags.entrySet()) if (distance.containsKey(entry.getValue()) && distance.get(entry.getValue()) < minimum) {
                        best = entry.getKey();
                        minimum = distance.get(entry.getValue());
                    }
                    require(best != null, "error: no tag can describe '" + chosen.id + "'");
                    System.out.println(best + (minimum == 0 ? "" : "-" + minimum + "-g" + chosen.id));
                    break;
                }
            case "GC":
                {
                    Set<Commit> keep = reachable(true);
                    int before = commits.size();
                    commits.values().removeIf(commit -> !keep.contains(commit));
                    System.out.println("Removed unreachable commits: " + (before - commits.size()));
                    break;
                }
        }
    }
    public static void main(String[] args) throws IOException {
        branches.put("main", create(List.of(), Map.of(), "init"));
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        String line;
        while (!(line = input.readLine()).equals("EXIT")) try {
            command(line);
        } catch (Problem problem) {
            System.out.println(problem.getMessage());
        }
    }
}
