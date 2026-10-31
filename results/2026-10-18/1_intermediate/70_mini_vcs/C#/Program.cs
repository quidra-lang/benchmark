using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

class Program
{
    class Problem(string message) : Exception(message) { }

    class Tree : SortedDictionary<string, string>
    {
        public Tree() : base(StringComparer.Ordinal) { }

        public Tree(IDictionary<string, string> source) : this()
        {
            foreach (var entry in source) Add(entry.Key, entry.Value);
        }
    }

    class Commit(string id, int sequence, List<Commit> parents, Tree tree, string message)
    {
        public readonly string Id = id, Message = message;
        public readonly int Sequence = sequence;
        public readonly List<Commit> Parents = [.. parents];
        public readonly Tree Files = new(tree);
    }

    record MergeResult(Tree Files, SortedSet<string> Conflicts, Dictionary<string, string> Contents);

    record Stash(string Label, Commit Base, Tree Files);

    record Replay(Commit Original, Tree Files, bool Pick);
    static readonly Dictionary<string, Commit> Commits = new(StringComparer.Ordinal);
    static readonly SortedDictionary<string, Commit> Branches = new(StringComparer.Ordinal), Tags = new(StringComparer.Ordinal);
    static readonly Tree Working = new(), Index = new();
    static readonly SortedSet<string> Conflicts = new(StringComparer.Ordinal);
    static readonly List<Stash> Stashes = [];
    static readonly List<string> Ignores = [];

    static string? branch = "main", operation;

    static Commit? detached, target;

    static int nextSequence;

    static Commit Head => branch is null ? detached! : Branches[branch];

    static void MoveHead(Commit commit)
    {
        if (branch is null) detached = commit;
        else Branches[branch] = commit;
    }

    static void Require(bool condition, string reason)
    {
        if (!condition) throw new Problem(reason);
    }

    static SortedSet<string> Paths(params Tree[] trees)
    {
        SortedSet<string> result = new(StringComparer.Ordinal);
        foreach (Tree tree in trees) result.UnionWith(tree.Keys);
        return result;
    }

    static bool Agree(Tree left, Tree right, string path) => left.GetValueOrDefault(path) == right.GetValueOrDefault(path);

    static SortedSet<string> Differences(Tree left, Tree right)
    {
        var result = Paths(left, right);
        result.RemoveWhere(path => Agree(left, right, path));
        return result;
    }

    static bool Equal(Tree left, Tree right) => left.Count == right.Count && left.All(entry => right.GetValueOrDefault(entry.Key) == entry.Value);

    static void Match(Tree destination, Tree source, string path)
    {
        if (source.TryGetValue(path, out string? text)) destination[path] = text;
        else destination.Remove(path);
    }

    static void Replace(Tree destination, Tree source)
    {
        destination.Clear();
        foreach (var entry in source) destination[entry.Key] = entry.Value;
    }

    static Commit Create(List<Commit> parents, Tree tree, string message)
    {
        int sequence = nextSequence++;
        StringBuilder text = new($"commit {sequence}\n");
        foreach (Commit parent in parents) text.Append("parent ").Append(parent.Id).Append('\n');
        foreach (var entry in tree) text.Append("file ").Append(entry.Key).Append(' ').Append(entry.Value).Append('\n');
        text.Append("message ").Append(message).Append('\n');
        long hash = 0;
        foreach (char c in text.ToString()) hash = (hash * 131 + c) % 2147483647;
        Commit commit = new(hash.ToString("x8", CultureInfo.InvariantCulture), sequence, parents, tree, message);
        Commits.Add(commit.Id, commit);
        return commit;
    }

    static void Record(List<Commit> parents, Tree tree, string message)
    {
        Commit commit = Create(parents, tree, message);
        Tree before = parents[0].Files;
        int added = 0, modified = 0, deleted = 0;
        foreach (string path in Differences(before, tree))
        {
            if (!before.ContainsKey(path)) added++;
            else if (!tree.ContainsKey(path)) deleted++;
            else modified++;
        }
        MoveHead(commit);
        Console.WriteLine($"[{branch ?? "detached HEAD"} {commit.Id}] {message} ({added} added, {modified} modified, {deleted} deleted)");
    }

    static Commit Resolve(string revision)
    {
        string[] parts = revision.Split('~');
        string anchor = parts[0];
        Commit? commit = anchor == "HEAD" ? Head : Branches.GetValueOrDefault(anchor) ?? Tags.GetValueOrDefault(anchor) ?? Commits.GetValueOrDefault(anchor);
        int steps = parts.Length == 1 ? 0 : int.Parse(parts[1]);
        while (commit is not null && steps-- > 0) commit = commit.Parents.Count == 0 ? null : commit.Parents[0];
        Require(commit is not null, $"error: unknown revision '{revision}'");
        return commit!;
    }

    static Dictionary<Commit, int> Distances(Commit start)
    {
        Dictionary<Commit, int> result = new() { [start] = 0 };
        Queue<Commit> queue = new();
        queue.Enqueue(start);
        while (queue.Count > 0)
        {
            Commit commit = queue.Dequeue();
            foreach (Commit parent in commit.Parents) if (result.TryAdd(parent, result[commit] + 1)) queue.Enqueue(parent);
        }
        return result;
    }

    static bool Ancestor(Commit ancestor, Commit descendant) => Distances(descendant).ContainsKey(ancestor);

    static Commit MergeBase(Commit left, Commit right)
    {
        var a = Distances(left);
        var b = Distances(right);
        var common = a.Keys.Where(b.ContainsKey).ToList();
        Commit? best = null;
        int smallest = int.MaxValue;
        foreach (Commit candidate in common)
        {
            if (common.Any(other => other != candidate && Ancestor(candidate, other))) continue;
            int distance = Math.Max(a[candidate], b[candidate]);
            if (best is null || distance < smallest || distance == smallest && candidate.Sequence > best.Sequence)
            {
                best = candidate;
                smallest = distance;
            }
        }
        return best!;
    }

    static string Summary(Commit commit)
    {
        List<string> refs = [];
        if (Head == commit) refs.Add(branch is null ? "HEAD" : "HEAD -> " + branch);
        foreach (var entry in Branches) if (entry.Value == commit && entry.Key != branch) refs.Add(entry.Key);
        foreach (var entry in Tags) if (entry.Value == commit) refs.Add("tag: " + entry.Key);
        return commit.Id + (refs.Count == 0 ? "" : " (" + string.Join(", ", refs) + ")") + " " + commit.Message;
    }

    static void Changes(Tree before, Tree after)
    {
        var paths = Differences(before, after);
        if (paths.Count == 0) Console.WriteLine("(no changes)");
        foreach (string path in paths) Console.WriteLine(!before.ContainsKey(path) ? $"A {path}: {after[path]}" : !after.ContainsKey(path) ? $"D {path}: {before[path]}" : $"M {path}: {before[path]} -> {after[path]}");
    }

    static void ProgressCheck() => Require(operation is null, $"error: {operation} in progress");

    static bool Dirty() => !Equal(Index, Head.Files) || Index.Keys.Any(path => !Agree(Working, Index, path));

    static void CleanCheck() => Require(!Dirty(), "error: uncommitted changes");

    static void OverwriteCheck(IEnumerable<string> paths)
    {
        foreach (string path in paths.OrderBy(candidate => candidate, StringComparer.Ordinal)) Require(Agree(Index, Head.Files, path) && Agree(Working, Head.Files, path), $"error: local changes to '{path}' would be overwritten");
    }

    static void SwitchTree(Tree tree)
    {
        var paths = Differences(Head.Files, tree);
        OverwriteCheck(paths);
        foreach (string path in paths)
        {
            Match(Index, tree, path);
            Match(Working, tree, path);
        }
    }

    static MergeResult Merge(Tree baseTree, Tree ours, Tree theirs)
    {
        Tree result = new();
        SortedSet<string> problems = new(StringComparer.Ordinal);
        Dictionary<string, string> contents = new(StringComparer.Ordinal);
        foreach (string path in Paths(baseTree, ours, theirs)) if (Agree(theirs, baseTree, path) || Agree(ours, theirs, path)) Match(result, ours, path);
        else if (Agree(ours, baseTree, path)) Match(result, theirs, path);
        else
        {
            problems.Add(path);
            Match(result, ours, path);
            contents[path] = "<<<<<<< " + ours.GetValueOrDefault(path, "(deleted)") + " ======= " + theirs.GetValueOrDefault(path, "(deleted)") + " >>>>>>>";
        }
        return new(result, problems, contents);
    }

    static void Apply(Tree baseTree, Tree theirs, string kind, Commit chosen, string message, List<Commit> parents, Commit? mergeBase)
    {
        MergeResult result = Merge(baseTree, Head.Files, theirs);
        var changed = Differences(Head.Files, result.Files);
        SortedSet<string> checkedPaths = new(changed, StringComparer.Ordinal);
        checkedPaths.UnionWith(result.Conflicts);
        OverwriteCheck(checkedPaths);
        if (kind == "merge") Console.WriteLine("Merge base " + mergeBase!.Id);
        else if (result.Conflicts.Count == 0 && changed.Count == 0)
        {
            Console.WriteLine("nothing to commit");
            return;
        }
        foreach (string path in changed)
        {
            Match(Index, result.Files, path);
            Match(Working, result.Files, path);
        }
        if (result.Conflicts.Count == 0) Record(parents, result.Files, message);
        else
        {
            foreach (string path in result.Conflicts)
            {
                Working[path] = result.Contents[path];
                Console.WriteLine("CONFLICT " + path);
            }
            Conflicts.Clear();
            Conflicts.UnionWith(result.Conflicts);
            operation = kind;
            target = chosen;
            Console.WriteLine(kind == "merge" ? "Automatic merge failed; fix conflicts and then commit the result." : kind == "revert" ? "error: could not revert " + chosen.Id : "error: could not apply " + chosen.Id);
        }
    }

    static bool Glob(string pattern, string path)
    {
        bool[,] dp = new bool[pattern.Length + 1, path.Length + 1];
        dp[0, 0] = true;
        for (int i = 0; i < pattern.Length; i++) for (int j = 0; j <= path.Length; j++) if (pattern[i] == '*') dp[i + 1, j] = dp[i, j] || j > 0 && dp[i + 1, j - 1];
        else if (j > 0) dp[i + 1, j] = dp[i, j - 1] && (pattern[i] == '?' || pattern[i] == path[j - 1]);
        return dp[pattern.Length, path.Length];
    }

    static bool Ignored(string path) => !Index.ContainsKey(path) && !Conflicts.Contains(path) && Ignores.Any(pattern => Glob(pattern, path));

    static void Pathspec(bool valid, string path) => Require(valid, $"error: pathspec '{path}' did not match any files");

    static HashSet<Commit> Reachable(bool extra)
    {
        HashSet<Commit> result = [];
        List<Commit> roots = [.. Branches.Values, .. Tags.Values, Head];
        if (extra)
        {
            roots.AddRange(Stashes.Select(stash => stash.Base));
            if (operation is not null) roots.Add(target!);
        }
        foreach (Commit root in roots) result.UnionWith(Distances(root).Keys);
        return result;
    }

    static void Command(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0], path = words.Length > 1 ? words[1] : "";
        switch (command)
        {
            case "WRITE":
                Working[path] = line[(line.IndexOf(' ', line.IndexOf(' ') + 1) + 1)..];
                break;
            case "REMOVE":
                Require(Working.ContainsKey(path), $"error: no such file '{path}'");
                Working.Remove(path);
                break;
            case "IGNORE":
                Ignores.Add(path);
                break;
            case "ADD":
                if (path == "ALL")
                {
                    var selected = Paths(Working, Index).Where(entry => !Ignored(entry)).ToList();
                    foreach (string entry in selected) Match(Index, Working, entry);
                    Conflicts.Clear();
                }
                else
                {
                    Require(!Working.ContainsKey(path) || !Ignored(path), $"error: path '{path}' is ignored");
                    Pathspec(Working.ContainsKey(path) || Index.ContainsKey(path) || Conflicts.Contains(path), path);
                    Match(Index, Working, path);
                    Conflicts.Remove(path);
                }
                break;
            case "RM":
                Pathspec(Index.ContainsKey(path), path);
                Index.Remove(path);
                Working.Remove(path);
                Conflicts.Remove(path);
                break;
            case "UNSTAGE":
                Pathspec(Index.ContainsKey(path) || Head.Files.ContainsKey(path), path);
                Match(Index, Head.Files, path);
                break;
            case "RESTORE":
                if (words.Length == 2)
                {
                    Pathspec(Index.ContainsKey(path), path);
                    Working[path] = Index[path];
                }
                else
                {
                    Commit chosen = Resolve(words[2]);
                    Require(chosen.Files.ContainsKey(path), $"error: path '{path}' does not exist in '{words[2]}'");
                    Match(Index, chosen.Files, path);
                    Match(Working, chosen.Files, path);
                    Conflicts.Remove(path);
                }
                break;
            case "COMMIT":
                Require(Conflicts.Count == 0, "error: unresolved conflicts");
                if (operation != "merge" && Equal(Index, Head.Files))
                {
                    Console.WriteLine("nothing to commit");
                    break;
                }
                Record(operation == "merge" ? [Head, target!] : [Head], Index, line[7..]);
                operation = null;
                target = null;
                break;
            case "AMEND":
                ProgressCheck();
                Require(Head.Parents.Count > 0, "error: cannot amend the root commit");
                Record(Head.Parents, Index, line[6..]);
                break;
            case "STATUS":
            {
                Console.WriteLine(branch is null ? "HEAD detached at " + Head.Id : "On branch " + branch);
                if (operation is not null) Console.WriteLine((operation == "merge" ? "Merging " : operation == "revert" ? "Reverting " : "Cherry-picking ") + target!.Id);
                var all = Paths(Head.Files, Index, Working);
                all.UnionWith(Conflicts);
                bool any = false;
                foreach (string entry in all) if (Conflicts.Contains(entry))
                {
                    Console.WriteLine("UU " + entry);
                    any = true;
                }
                else if (Index.ContainsKey(entry))
                {
                    char x = !Head.Files.ContainsKey(entry) ? 'A' : Agree(Head.Files, Index, entry) ? '.' : 'M';
                    char y = !Working.ContainsKey(entry) ? 'D' : Agree(Working, Index, entry) ? '.' : 'M';
                    if (x != '.' || y != '.')
                    {
                        Console.WriteLine($"{x}{y} {entry}");
                        any = true;
                    }
                }
                else
                {
                    if (Head.Files.ContainsKey(entry))
                    {
                        Console.WriteLine("D. " + entry);
                        any = true;
                    }
                    if (Working.ContainsKey(entry) && !Ignored(entry))
                    {
                        Console.WriteLine("?? " + entry);
                        any = true;
                    }
                }
                if (!any) Console.WriteLine("nothing to commit, working tree clean");
                break;
            }
            case "LS":
            {
                Tree tree = words.Length == 1 ? Working : Resolve(path).Files;
                if (tree.Count == 0) Console.WriteLine("(empty)");
                foreach (var entry in tree) Console.WriteLine(entry.Key + " " + entry.Value);
                break;
            }
            case "CAT":
            {
                Tree tree = words.Length == 2 ? Working : Resolve(words[2]).Files;
                Require(tree.ContainsKey(path), words.Length == 2 ? $"error: no such file '{path}'" : $"error: path '{path}' does not exist in '{words[2]}'");
                Console.WriteLine(tree[path]);
                break;
            }
            case "DIFF":
                if (words.Length == 1)
                {
                    Tree tracked = new();
                    foreach (string entry in Index.Keys) if (Working.ContainsKey(entry)) tracked[entry] = Working[entry];
                    Changes(Index, tracked);
                }
                else if (words.Length == 2) Changes(Head.Files, Index);
                else
                {
                    Commit left = Resolve(path), right = Resolve(words[2]);
                    Changes(left.Files, right.Files);
                }
                break;
            case "LOG":
            {
                int limit = words.Length == 1 ? int.MaxValue : int.Parse(path);
                Commit chosen = Head;
                while (limit-- > 0)
                {
                    Console.WriteLine(Summary(chosen));
                    if (chosen.Parents.Count == 0) break;
                    chosen = chosen.Parents[0];
                }
                break;
            }
            case "SHOW":
            {
                Commit chosen = Resolve(words.Length == 1 ? "HEAD" : path);
                Console.WriteLine("commit " + Summary(chosen));
                Console.WriteLine("parents: " + (chosen.Parents.Count == 0 ? "none" : string.Join(" ", chosen.Parents.Select(parent => parent.Id))));
                Changes(chosen.Parents.Count == 0 ? new() : chosen.Parents[0].Files, chosen.Files);
                break;
            }
            case "BLAME":
            {
                Require(Head.Files.ContainsKey(path), $"error: path '{path}' does not exist in 'HEAD'");
                Commit chosen = Head;
                string text = chosen.Files[path];
                while (chosen.Parents.Count > 0 && chosen.Parents[0].Files.GetValueOrDefault(path) == text) chosen = chosen.Parents[0];
                Console.WriteLine($"{chosen.Id} ({chosen.Message}) {text}");
                break;
            }
            case "BRANCH":
            case "TAG":
            {
                bool tag = command == "TAG";
                var refs = tag ? Tags : Branches;
                string noun = tag ? "tag" : "branch";
                if (path == "-d")
                {
                    string name = words[2];
                    Require(refs.ContainsKey(name), $"error: no such {noun} '{name}'");
                    Commit chosen = refs[name];
                    if (!tag)
                    {
                        Require(name != branch, $"error: cannot delete current branch '{name}'");
                        Require(Ancestor(chosen, Head), $"error: branch '{name}' is not fully merged");
                    }
                    refs.Remove(name);
                    Console.WriteLine($"Deleted {noun} {name} (was {chosen.Id})");
                }
                else
                {
                    Require(!refs.ContainsKey(path), $"error: {noun} '{path}' already exists");
                    Commit chosen = Resolve(words.Length == 2 ? "HEAD" : words[2]);
                    refs[path] = chosen;
                    Console.WriteLine($"Created {noun} {path} at {chosen.Id}");
                }
                break;
            }
            case "BRANCHES":
                if (branch is null) Console.WriteLine($"* (HEAD detached at {Head.Id})");
                foreach (var entry in Branches) Console.WriteLine((entry.Key == branch ? "* " : "  ") + entry.Key + " " + entry.Value.Id + " " + entry.Value.Message);
                break;
            case "TAGS":
                if (Tags.Count == 0) Console.WriteLine("(no tags)");
                foreach (var entry in Tags) Console.WriteLine(entry.Key + " " + entry.Value.Id + " " + entry.Value.Message);
                break;
            case "SWITCH":
                Require(Branches.ContainsKey(path), $"error: no such branch '{path}'");
                if (path == branch)
                {
                    Console.WriteLine($"Already on '{path}'");
                    break;
                }
                ProgressCheck();
                SwitchTree(Branches[path].Files);
                branch = path;
                Console.WriteLine($"Switched to branch '{path}'");
                break;
            case "DETACH":
            {
                Commit chosen = Resolve(path);
                ProgressCheck();
                SwitchTree(chosen.Files);
                branch = null;
                detached = chosen;
                Console.WriteLine($"HEAD is now at {chosen.Id} {chosen.Message}");
                break;
            }
            case "MERGEBASE":
            {
                Commit left = Resolve(path), right = Resolve(words[2]);
                Console.WriteLine(MergeBase(left, right).Id);
                break;
            }
            case "MERGE":
            {
                Commit chosen = Resolve(path), before = Head;
                ProgressCheck();
                if (Ancestor(chosen, before))
                {
                    Console.WriteLine("Already up to date");
                    break;
                }
                if (Ancestor(before, chosen))
                {
                    SwitchTree(chosen.Files);
                    MoveHead(chosen);
                    Console.WriteLine($"Fast-forward {before.Id}..{chosen.Id}");
                    break;
                }
                CleanCheck();
                Commit baseCommit = MergeBase(before, chosen);
                Apply(baseCommit.Files, chosen.Files, "merge", chosen, "Merge " + path, [before, chosen], baseCommit);
                break;
            }
            case "RESET":
            {
                Commit chosen = Resolve(words[2]);
                if (path == "HARD")
                {
                    var all = Paths(Index, chosen.Files);
                    all.UnionWith(Conflicts);
                    foreach (string entry in all) Match(Working, chosen.Files, entry);
                }
                if (path != "SOFT") Replace(Index, chosen.Files);
                MoveHead(chosen);
                Conflicts.Clear();
                operation = null;
                target = null;
                Console.WriteLine($"HEAD is now at {chosen.Id} {chosen.Message}");
                break;
            }
            case "REVERT":
            case "CHERRYPICK":
            {
                Commit chosen = Resolve(path);
                ProgressCheck();
                CleanCheck();
                Tree parent = chosen.Parents.Count == 0 ? new() : chosen.Parents[0].Files;
                bool revert = command == "REVERT";
                Apply(revert ? chosen.Files : parent, revert ? parent : chosen.Files, revert ? "revert" : "cherry-pick", chosen, revert ? "Revert \"" + chosen.Message + "\"" : chosen.Message, [Head], null);
                break;
            }
            case "REBASE":
            {
                Commit upstream = Resolve(path);
                ProgressCheck();
                if (Ancestor(upstream, Head))
                {
                    Console.WriteLine("Already up to date");
                    break;
                }
                CleanCheck();
                List<Commit> old = [];
                Commit cursor = Head;
                while (!Ancestor(cursor, upstream))
                {
                    old.Add(cursor);
                    cursor = cursor.Parents[0];
                }
                old.Reverse();
                List<Replay> replay = [];
                Tree tree = new(upstream.Files);
                foreach (Commit chosen in old)
                {
                    MergeResult result = Merge(chosen.Parents[0].Files, tree, chosen.Files);
                    Require(result.Conflicts.Count == 0, $"error: could not rebase {chosen.Id}: conflict in '{result.Conflicts.FirstOrDefault()}'");
                    replay.Add(new(chosen, result.Files, !Equal(tree, result.Files)));
                    tree = result.Files;
                }
                SwitchTree(tree);
                Commit current = upstream;
                foreach (Replay item in replay) if (item.Pick)
                {
                    Commit created = Create([current], item.Files, item.Original.Message);
                    Console.WriteLine($"pick {item.Original.Id} -> {created.Id} {created.Message}");
                    current = created;
                }
                else Console.WriteLine($"skip {item.Original.Id} {item.Original.Message}");
                MoveHead(current);
                Console.WriteLine($"HEAD is now at {current.Id} {current.Message}");
                break;
            }
            case "STASH":
            {
                if (words.Length > 1 && path == "LIST")
                {
                    if (Stashes.Count == 0) Console.WriteLine("(no stash entries)");
                    for (int i = 0; i < Stashes.Count; i++) Console.WriteLine($"stash@{{{i}}}: {Stashes[i].Label}");
                    break;
                }
                if (words.Length > 1)
                {
                    Require(Stashes.Count > 0, "error: no stash entries");
                    Stash stash = Stashes[0];
                    if (path == "DROP")
                    {
                        Stashes.RemoveAt(0);
                        Console.WriteLine("Dropped stash@{0}: " + stash.Label);
                        break;
                    }
                    ProgressCheck();
                    CleanCheck();
                    MergeResult result = Merge(stash.Base.Files, Head.Files, stash.Files);
                    Require(result.Conflicts.Count == 0, $"error: stash conflict in '{result.Conflicts.FirstOrDefault()}'");
                    var changed = Differences(Head.Files, result.Files);
                    OverwriteCheck(changed);
                    foreach (string entry in changed) Match(Working, result.Files, entry);
                    Stashes.RemoveAt(0);
                    Console.WriteLine("Restored stash@{0}: " + stash.Label);
                    Changes(Head.Files, result.Files);
                }
                else
                {
                    ProgressCheck();
                    if (!Dirty())
                    {
                        Console.WriteLine("No local changes to save");
                        break;
                    }
                    Tree saved = new();
                    var tracked = Paths(Index, Head.Files);
                    foreach (string entry in tracked) if (Working.ContainsKey(entry)) saved[entry] = Working[entry];
                    foreach (string entry in tracked) Match(Working, Head.Files, entry);
                    Replace(Index, Head.Files);
                    string label = $"WIP on {branch ?? "(no branch)"}: {Head.Id} {Head.Message}";
                    Stashes.Insert(0, new(label, Head, saved));
                    Console.WriteLine("Saved stash@{0}: " + label);
                }
                break;
            }
            case "GRAPH":
            {
                List<Commit> lanes = [];
                foreach (Commit chosen in Reachable(false).OrderByDescending(commit => commit.Sequence))
                {
                    if (!lanes.Contains(chosen)) lanes.Add(chosen);
                    int first = lanes.IndexOf(chosen);
                    Console.WriteLine(string.Join(" ", lanes.Select((commit, i) => i == first ? "*" : commit == chosen ? "/" : "|")) + " " + Summary(chosen));
                    for (int i = lanes.Count - 1; i > first; i--) if (lanes[i] == chosen) lanes.RemoveAt(i);
                    if (chosen.Parents.Count == 0) lanes.RemoveAt(first);
                    else
                    {
                        lanes[first] = chosen.Parents[0];
                        if (chosen.Parents.Count == 2 && !lanes.Contains(chosen.Parents[1])) lanes.Insert(first + 1, chosen.Parents[1]);
                    }
                }
                break;
            }
            case "DESCRIBE":
            {
                Commit chosen = Resolve(words.Length == 1 ? "HEAD" : path);
                var distances = Distances(chosen);
                string? best = null;
                int smallest = int.MaxValue;
                foreach (var entry in Tags) if (distances.TryGetValue(entry.Value, out int distance) && distance < smallest)
                {
                    best = entry.Key;
                    smallest = distance;
                }
                Require(best is not null, $"error: no tag can describe '{chosen.Id}'");
                Console.WriteLine(best + (smallest == 0 ? "" : $"-{smallest}-g{chosen.Id}"));
                break;
            }
            case "GC":
            {
                var keep = Reachable(true);
                var removed = Commits.Where(entry => !keep.Contains(entry.Value)).Select(entry => entry.Key).ToList();
                foreach (string id in removed) Commits.Remove(id);
                Console.WriteLine($"Removed unreachable commits: {removed.Count}");
                break;
            }
        }
    }

    static void Main()
    {
        Branches["main"] = Create([], new(), "init");
        string line;
        while ((line = Console.ReadLine()!) != "EXIT") try
        {
            Command(line);
        }
        catch (Problem error)
        {
            Console.WriteLine(error.Message);
        }
    }
}
