using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError(string message) : Exception(message) {}
readonly record struct Entry(int Key, string Value)
{
    public override string ToString() => $"{Key}={Value}";
}
readonly record struct SearchResult(int? Page, int Position, List<string> Path);

sealed class Node
{
    public List<Entry> Entries { get; } = [];
    public List<int> Children { get; } = [];
    public bool Leaf => Children.Count == 0;
    public string Notation => "[" + string.Join(" ", Entries.Select(entry => entry.Key)) + "]";
    public int Position(int key)
    {
        int position = 0;
        while (position < Entries.Count && key > Entries[position].Key) position++;
        return position;
    }
    public Node Copy()
    {
        Node node = new();
        node.Entries.AddRange(Entries); node.Children.AddRange(Children);
        return node;
    }
    public bool SameContent(Node other) => Entries.SequenceEqual(other.Entries) && Children.SequenceEqual(other.Children);
}

sealed class Trace(bool enabled)
{
    public List<string> Lines { get; } = [];
    public void Emit(string line) { if (enabled) Lines.Add(line); }
}

sealed class Tree(int degree)
{
    public int Degree { get; } = degree;
    public int Root { get; private set; }
    public Dictionary<int, Node> Pages { get; private set; } = new() { [0] = new Node() };
    public int Splits { get; private set; }
    public int Merges { get; private set; }
    public int Borrows { get; private set; }

    public Dictionary<int, Node> CopyPages() => Pages.ToDictionary(pair => pair.Key, pair => pair.Value.Copy());
    public Tree Copy() => new(Degree) { Root = Root, Pages = CopyPages(), Splits = Splits, Merges = Merges, Borrows = Borrows };
    public (int Writes, int Frees) Changes(Dictionary<int, Node> before)
    {
        int writes = Pages.Count(pair => !before.TryGetValue(pair.Key, out Node? old) || !pair.Value.SameContent(old));
        int frees = before.Keys.Count(page => !Pages.ContainsKey(page));
        return (writes, frees);
    }
    private int Allocate(Node node)
    {
        int page = 0;
        while (Pages.ContainsKey(page)) page++;
        Pages.Add(page, node);
        return page;
    }
    public int Height
    {
        get
        {
            int height = 0, page = Root;
            while (!Pages[page].Leaf) { page = Pages[page].Children[0]; height++; }
            return height;
        }
    }
    public List<Entry> Entries()
    {
        List<Entry> result = [];
        void Visit(int page)
        {
            Node node = Pages[page];
            if (!node.Leaf) Visit(node.Children[0]);
            for (int i = 0; i < node.Entries.Count; i++)
            {
                result.Add(node.Entries[i]);
                if (!node.Leaf) Visit(node.Children[i + 1]);
            }
        }
        Visit(Root);
        return result;
    }
    public SearchResult Search(int key)
    {
        int page = Root;
        List<string> path = [];
        while (true)
        {
            Node node = Pages[page];
            int position = node.Position(key);
            path.Add(node.Notation);
            if (position < node.Entries.Count && node.Entries[position].Key == key) return new(page, position, path);
            if (node.Leaf) return new(null, -1, path);
            page = node.Children[position];
        }
    }
    public string? Violation()
    {
        int? referenceDepth = null;
        string? Visit(int page, string location, int depth, int? low, int? high)
        {
            Node node = Pages[page];
            int count = node.Entries.Count, minimum = page == Root ? (node.Leaf ? 0 : 1) : Degree - 1, maximum = 2 * Degree - 1;
            string at = $"at={location} node={node.Notation}";
            if (count < minimum || count > maximum) return $"COUNT {at} keys={count} allowed={minimum}..{maximum}";
            for (int i = 0; i + 1 < count; i++)
                if (node.Entries[i].Key >= node.Entries[i + 1].Key) return $"ORDER {at} {node.Entries[i].Key}>={node.Entries[i + 1].Key}";
            foreach (Entry entry in node.Entries)
                if ((low.HasValue && entry.Key <= low.Value) || (high.HasValue && entry.Key >= high.Value))
                    return $"RANGE {at} key={entry.Key} low={low?.ToString() ?? "-inf"} high={high?.ToString() ?? "+inf"}";
            if (node.Leaf)
            {
                if (referenceDepth is int expected && depth != expected) return $"DEPTH {at} depth={depth} expected={expected}";
                referenceDepth ??= depth;
            }
            for (int i = 0; i < node.Children.Count; i++)
            {
                string? problem = Visit(node.Children[i], $"{location}.{i}", depth + 1,
                    i == 0 ? low : node.Entries[i - 1].Key, i == count ? high : node.Entries[i].Key);
                if (problem is not null) return problem;
            }
            return null;
        }
        return Visit(Root, "root", 0, null, null);
    }
    public static Tree Load(int degree, string[] tokens)
    {
        Tree tree = new(degree);
        tree.Pages.Clear();
        int position = 0, nextPage = 0;
        CommandError Syntax() => new($"SYNTAX {position + 1}");
        Entry ReadEntry()
        {
            if (position == tokens.Length || tokens[position] is "(" or ")") throw Syntax();
            string[] pair = tokens[position++].Split('=');
            return new(int.Parse(pair[0]), pair[1]);
        }
        int ReadNode()
        {
            if (position == tokens.Length || tokens[position] != "(") throw Syntax();
            position++;
            int page = nextPage++;
            Node node = new();
            tree.Pages.Add(page, node);
            if (position < tokens.Length && tokens[position] == "(")
            {
                node.Children.Add(ReadNode());
                while (position == tokens.Length || tokens[position] != ")")
                {
                    node.Entries.Add(ReadEntry()); node.Children.Add(ReadNode());
                }
            }
            else while (position == tokens.Length || tokens[position] != ")") node.Entries.Add(ReadEntry());
            position++;
            return page;
        }
        tree.Root = ReadNode();
        if (position != tokens.Length) throw Syntax();
        return tree;
    }
    private void Split(int parentPage, int position, Trace trace)
    {
        Node parent = Pages[parentPage];
        int childPage = parent.Children[position];
        Node child = Pages[childPage], right = new();
        string before = child.Notation;
        Entry middle = child.Entries[Degree - 1];
        right.Entries.AddRange(child.Entries.Skip(Degree));
        right.Children.AddRange(child.Children.Skip(Degree));
        int newPage = Allocate(right);
        child.Entries.RemoveRange(Degree - 1, Degree);
        if (!child.Leaf) child.Children.RemoveRange(Degree, Degree);
        parent.Entries.Insert(position, middle); parent.Children.Insert(position + 1, newPage);
        Splits++;
        trace.Emit($"STEP split page={childPage} keys={before} up={middle.Key} new={newPage}");
    }
    public string? Upsert(int key, string value, Trace trace)
    {
        SearchResult found = Search(key);
        if (found.Page is int existing)
        {
            Entry old = Pages[existing].Entries[found.Position];
            Pages[existing].Entries[found.Position] = new(key, value);
            return old.Value;
        }
        if (Pages[Root].Entries.Count == 2 * Degree - 1)
        {
            Node root = new(); root.Children.Add(Root);
            Root = Allocate(root);
            trace.Emit($"STEP grow page={Root}");
            Split(Root, 0, trace);
        }
        int page = Root;
        while (!Pages[page].Leaf)
        {
            Node node = Pages[page];
            int position = node.Position(key);
            if (Pages[node.Children[position]].Entries.Count == 2 * Degree - 1)
            {
                Split(page, position, trace);
                if (key > node.Entries[position].Key) position++;
            }
            page = node.Children[position];
        }
        Node leaf = Pages[page];
        leaf.Entries.Insert(leaf.Position(key), new(key, value));
        trace.Emit($"STEP place page={page} keys={leaf.Notation}");
        return null;
    }
    private int Merge(int parentPage, int position, string caseName, Trace trace)
    {
        Node parent = Pages[parentPage];
        int leftPage = parent.Children[position], rightPage = parent.Children[position + 1];
        Node left = Pages[leftPage], right = Pages[rightPage];
        left.Entries.Add(parent.Entries[position]); left.Entries.AddRange(right.Entries); left.Children.AddRange(right.Children);
        parent.Entries.RemoveAt(position); parent.Children.RemoveAt(position + 1);
        Pages.Remove(rightPage); Merges++;
        trace.Emit($"STEP {caseName} page={parentPage} merge={leftPage}+{rightPage} keys={left.Notation}");
        if (parentPage == Root && parent.Entries.Count == 0)
        {
            Root = leftPage; Pages.Remove(parentPage);
            trace.Emit($"STEP shrink page={Root}");
        }
        return leftPage;
    }
    private void RemoveAt(int page, int key, List<string> cases, Trace trace)
    {
        Node node = Pages[page];
        int position = node.Position(key);
        if (position < node.Entries.Count && node.Entries[position].Key == key)
        {
            if (node.Leaf)
            {
                cases.Add("1"); node.Entries.RemoveAt(position);
                trace.Emit($"STEP 1 page={page} keys={node.Notation}");
                return;
            }
            int left = node.Children[position], right = node.Children[position + 1];
            if (Pages[left].Entries.Count >= Degree)
            {
                int last = left;
                while (!Pages[last].Leaf) last = Pages[last].Children[^1];
                Entry predecessor = Pages[last].Entries[^1];
                cases.Add("2a"); trace.Emit($"STEP 2a page={page} pred={predecessor.Key}");
                RemoveAt(left, predecessor.Key, cases, trace);
                node.Entries[position] = predecessor;
            }
            else if (Pages[right].Entries.Count >= Degree)
            {
                int first = right;
                while (!Pages[first].Leaf) first = Pages[first].Children[0];
                Entry successor = Pages[first].Entries[0];
                cases.Add("2b"); trace.Emit($"STEP 2b page={page} succ={successor.Key}");
                RemoveAt(right, successor.Key, cases, trace);
                node.Entries[position] = successor;
            }
            else
            {
                cases.Add("2c");
                int child = Merge(page, position, "2c", trace);
                RemoveAt(child, key, cases, trace);
            }
            return;
        }
        int childPage = node.Children[position];
        Node target = Pages[childPage];
        if (target.Entries.Count == Degree - 1)
        {
            int? leftPage = position > 0 ? node.Children[position - 1] : null;
            int? rightPage = position < node.Entries.Count ? node.Children[position + 1] : null;
            if (leftPage is int left && Pages[left].Entries.Count >= Degree)
            {
                Node sibling = Pages[left];
                cases.Add("3a-left"); target.Entries.Insert(0, node.Entries[position - 1]);
                node.Entries[position - 1] = sibling.Entries[^1]; sibling.Entries.RemoveAt(sibling.Entries.Count - 1);
                if (!sibling.Leaf) { target.Children.Insert(0, sibling.Children[^1]); sibling.Children.RemoveAt(sibling.Children.Count - 1); }
                Borrows++;
                trace.Emit($"STEP 3a-left page={page} child={childPage} from={left} keys={target.Notation}");
            }
            else if (rightPage is int right && Pages[right].Entries.Count >= Degree)
            {
                Node sibling = Pages[right];
                cases.Add("3a-right"); target.Entries.Add(node.Entries[position]);
                node.Entries[position] = sibling.Entries[0]; sibling.Entries.RemoveAt(0);
                if (!sibling.Leaf) { target.Children.Add(sibling.Children[0]); sibling.Children.RemoveAt(0); }
                Borrows++;
                trace.Emit($"STEP 3a-right page={page} child={childPage} from={right} keys={target.Notation}");
            }
            else if (leftPage.HasValue) { cases.Add("3b-left"); childPage = Merge(page, position - 1, "3b-left", trace); }
            else { cases.Add("3b-right"); childPage = Merge(page, position, "3b-right", trace); }
        }
        RemoveAt(childPage, key, cases, trace);
    }
    public List<string> Remove(int key, Trace trace)
    {
        List<string> cases = [];
        RemoveAt(Root, key, cases, trace);
        return cases;
    }
    public (List<Entry> Entries, int Visited) Scan(int low, int high)
    {
        List<Entry> result = [];
        int visited = 0;
        void Visit(int page)
        {
            visited++;
            Node node = Pages[page];
            int count = node.Entries.Count;
            for (int i = 0; i <= count; i++)
            {
                if (!node.Leaf && (i == 0 || node.Entries[i - 1].Key < high) && (i == count || node.Entries[i].Key > low)) Visit(node.Children[i]);
                if (i < count && low <= node.Entries[i].Key && node.Entries[i].Key <= high) result.Add(node.Entries[i]);
            }
        }
        Visit(Root);
        return (result, visited);
    }
    public string Dump()
    {
        List<string> tokens = [];
        void Visit(int page)
        {
            Node node = Pages[page];
            tokens.Add("(");
            if (!node.Leaf) Visit(node.Children[0]);
            for (int i = 0; i < node.Entries.Count; i++)
            {
                tokens.Add(node.Entries[i].ToString());
                if (!node.Leaf) Visit(node.Children[i + 1]);
            }
            tokens.Add(")");
        }
        Visit(Root);
        return string.Join(" ", tokens);
    }
    public void Compact()
    {
        List<Entry> source = Entries();
        List<int> children = [];
        List<Node> built = [];
        int oldRoot;
        while (true)
        {
            int groups = (source.Count + 2 * Degree) / (2 * Degree), keys = source.Count - groups + 1;
            int size = keys / groups, extra = keys % groups, entryIndex = 0, childIndex = 0;
            List<int> nodes = [];
            List<Entry> separators = [];
            for (int group = 0; group < groups; group++)
            {
                int count = size + (group < extra ? 1 : 0);
                Node node = new();
                node.Entries.AddRange(source.GetRange(entryIndex, count));
                if (children.Count > 0) node.Children.AddRange(children.GetRange(childIndex, count + 1));
                nodes.Add(built.Count); built.Add(node);
                entryIndex += count; childIndex += count + 1;
                if (group + 1 < groups) separators.Add(source[entryIndex++]);
            }
            if (groups == 1) { oldRoot = nodes[0]; break; }
            source = separators; children = nodes;
        }
        Dictionary<int, Node> replacement = [];
        int nextPage = 0;
        int Renumber(int oldPage)
        {
            int page = nextPage++;
            Node old = built[oldPage], node = new();
            node.Entries.AddRange(old.Entries);
            foreach (int child in old.Children) node.Children.Add(Renumber(child));
            replacement.Add(page, node);
            return page;
        }
        Root = Renumber(oldRoot); Pages = replacement;
        Splits = Merges = Borrows = 0;
    }
}

enum CursorKind { Unset, Key, Begin, End }
readonly record struct Cursor(CursorKind Kind, int Key = 0);

sealed class Workbench
{
    private Tree? index;
    private Tree? saved;
    private Cursor cursor = new(CursorKind.Unset);
    private bool trace;
    private static readonly HashSet<string> NeedsValid = ["INSERT", "BULKLOAD", "DELETE", "DELRANGE", "RANGE", "COUNT", "MIN", "MAX",
        "FLOOR", "CEIL", "RANK", "SELECT", "SEEK", "NEXT", "PREV", "HEIGHT", "COMPACT"];

    private static Entry? Find(List<Entry> entries, Func<Entry, bool> predicate, bool last = false)
    {
        Entry? result = null;
        foreach (Entry entry in entries)
        {
            if (!predicate(entry)) continue;
            result = entry;
            if (!last) break;
        }
        return result;
    }
    private static string Summary(string prefix, Tree tree) => $"{prefix} nodes={tree.Pages.Count} keys={tree.Entries().Count} {(tree.Violation() is null ? "OK" : "DAMAGED")}";
    public List<string> Process(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0];
        if (command == "TRACE") { trace = words[1] == "ON"; return [$"TRACE {words[1]}"]; }
        int first = words.Length > 1 ? int.Parse(words[1]) : 0;
        bool ranged = command is "DELRANGE" or "RANGE" or "COUNT";
        int second = ranged ? int.Parse(words[2]) : 0;
        if (command is "CREATE" or "LOAD")
        {
            if (first < 2 || first > 5) throw new CommandError($"BAD DEGREE {first}");
            Tree replacement = command == "CREATE" ? new(first) : Tree.Load(first, words[2..]);
            index = replacement; cursor = new(CursorKind.Unset);
            return [command == "CREATE" ? $"CREATE t={first}" : Summary($"LOAD t={first}", replacement)];
        }
        Tree tree = index ?? throw new CommandError("NO INDEX");
        if (NeedsValid.Contains(command) && tree.Violation() is not null) throw new CommandError("DAMAGED");
        List<Entry> entries = tree.Entries();
        if (ranged && first > second) throw new CommandError($"BAD RANGE {first} {second}");
        if (command == "SELECT" && (first < 1 || first > entries.Count)) throw new CommandError($"BAD POSITION {first}");
        if ((command is "NEXT" or "PREV") && cursor.Kind == CursorKind.Unset) throw new CommandError("NO CURSOR");
        if (command == "RESTORE" && saved is null) throw new CommandError("NO SAVE");
        List<string> output = [];
        Trace steps = new(trace && (command is "INSERT" or "DELETE"));
        switch (command)
        {
            case "INSERT":
            {
                Dictionary<int, Node> before = tree.CopyPages();
                int splits = tree.Splits;
                string? old = tree.Upsert(first, words[2], steps);
                int writes = tree.Changes(before).Writes;
                output.AddRange(steps.Lines);
                output.Add(old is null ? $"INSERT {first} NEW splits={tree.Splits - splits} height={tree.Height} writes={writes}"
                    : $"INSERT {first} UPDATED old={old} writes={writes}");
                break;
            }
            case "BULKLOAD":
            {
                Dictionary<int, Node> before = tree.CopyPages();
                int splits = tree.Splits, inserted = 0, updated = 0;
                for (int i = 1; i < words.Length; i += 2)
                    if (tree.Upsert(int.Parse(words[i]), words[i + 1], steps) is null) inserted++; else updated++;
                output.Add($"BULKLOAD pairs={(words.Length - 1) / 2} new={inserted} updated={updated} splits={tree.Splits - splits} height={tree.Height} writes={tree.Changes(before).Writes}");
                break;
            }
            case "DELETE":
            {
                SearchResult found = tree.Search(first);
                if (found.Page is int page)
                {
                    string value = tree.Pages[page].Entries[found.Position].Value;
                    Dictionary<int, Node> before = tree.CopyPages();
                    List<string> cases = tree.Remove(first, steps);
                    (int writes, int frees) = tree.Changes(before);
                    output.AddRange(steps.Lines);
                    output.Add($"DELETE {first} REMOVED value={value} cases={string.Join(",", cases)} height={tree.Height} writes={writes} frees={frees}");
                }
                else output.Add($"DELETE {first} NOT FOUND");
                break;
            }
            case "DELRANGE":
            {
                Dictionary<int, Node> before = tree.CopyPages();
                int merges = tree.Merges, borrows = tree.Borrows, removed = 0;
                foreach (Entry entry in entries)
                    if (first <= entry.Key && entry.Key <= second) { tree.Remove(entry.Key, steps); removed++; }
                (int writes, int frees) = tree.Changes(before);
                output.Add($"DELRANGE {first} {second} removed={removed} merges={tree.Merges - merges} borrows={tree.Borrows - borrows} height={tree.Height} writes={writes} frees={frees}");
                break;
            }
            case "GET":
            {
                SearchResult found = tree.Search(first);
                string result = found.Page is int page ? "FOUND value=" + tree.Pages[page].Entries[found.Position].Value : "NOT FOUND";
                output.Add($"GET {first} {result} path={string.Join(" -> ", found.Path)}");
                break;
            }
            case "RANGE": case "COUNT":
            {
                (List<Entry> selected, int visited) = tree.Scan(first, second);
                string suffix = command == "RANGE" ? string.Concat(selected.Select(entry => " " + entry)) : "";
                output.Add($"{command} {first} {second} count={selected.Count} visited={visited}{suffix}");
                break;
            }
            case "MIN": case "MAX":
                output.Add($"{command} {(entries.Count == 0 ? "EMPTY" : (command == "MIN" ? entries[0] : entries[^1]).ToString())}");
                break;
            case "FLOOR": case "CEIL":
            {
                Entry? entry = command == "FLOOR" ? Find(entries, value => value.Key <= first, true) : Find(entries, value => value.Key >= first);
                output.Add($"{command} {first} {entry?.ToString() ?? "NONE"}");
                break;
            }
            case "RANK": output.Add($"RANK {first} {entries.Count(entry => entry.Key < first)}"); break;
            case "SELECT": output.Add($"SELECT {first} {entries[first - 1]}"); break;
            case "SEEK":
            {
                Entry? entry = Find(entries, value => value.Key >= first);
                cursor = entry is Entry found ? new(CursorKind.Key, found.Key) : new(CursorKind.End);
                output.Add($"SEEK {first} {entry?.ToString() ?? "END"}");
                break;
            }
            case "NEXT": case "PREV":
            {
                Entry? entry = null;
                if (command == "NEXT")
                {
                    if (cursor.Kind == CursorKind.Begin) entry = Find(entries, _ => true);
                    else if (cursor.Kind == CursorKind.Key) entry = Find(entries, value => value.Key > cursor.Key);
                }
                else
                {
                    if (cursor.Kind == CursorKind.End) entry = Find(entries, _ => true, true);
                    else if (cursor.Kind == CursorKind.Key) entry = Find(entries, value => value.Key < cursor.Key, true);
                }
                cursor = entry is Entry found ? new(CursorKind.Key, found.Key) : new(command == "NEXT" ? CursorKind.End : CursorKind.Begin);
                output.Add($"{command} {entry?.ToString() ?? (command == "NEXT" ? "END" : "BEGIN")}");
                break;
            }
            case "PRINT":
            {
                List<int> level = [tree.Root];
                int depth = 0;
                while (level.Count > 0)
                {
                    output.Add($"LEVEL {depth} " + string.Join(" ", level.Select(page => tree.Pages[page].Notation)));
                    level = level.SelectMany(page => tree.Pages[page].Children).ToList(); depth++;
                }
                break;
            }
            case "PAGES":
                foreach (int page in tree.Pages.Keys.Order())
                {
                    Node node = tree.Pages[page];
                    output.Add($"PAGE {page} {node.Notation} kids={(node.Leaf ? "-" : string.Join(",", node.Children))}");
                }
                break;
            case "DUMP": output.Add($"DUMP {tree.Degree} {tree.Dump()}"); break;
            case "HEIGHT": output.Add($"HEIGHT {tree.Height}"); break;
            case "STATS":
            {
                int leaves = tree.Pages.Values.Count(node => node.Leaf);
                int fill = 100 * entries.Count / ((2 * tree.Degree - 1) * tree.Pages.Count);
                output.Add($"STATS t={tree.Degree} nodes={tree.Pages.Count} leaves={leaves} keys={entries.Count} fill={fill}% splits={tree.Splits} merges={tree.Merges} borrows={tree.Borrows}");
                break;
            }
            case "VERIFY": output.Add(tree.Violation() is string problem ? "VERIFY FAIL " + problem : "VERIFY OK"); break;
            case "REBUILD":
                tree = new(tree.Degree);
                foreach (Entry entry in entries) tree.Upsert(entry.Key, entry.Value, steps);
                output.Add($"REBUILD entries={entries.Count} keys={tree.Entries().Count} nodes={tree.Pages.Count} splits={tree.Splits} height={tree.Height}");
                break;
            case "COMPACT":
            {
                int nodes = tree.Pages.Count;
                tree.Compact();
                output.Add($"COMPACT nodes={nodes}->{tree.Pages.Count} height={tree.Height}");
                break;
            }
            case "SAVE": saved = tree.Copy(); output.Add(Summary("SAVE", tree)); break;
            case "RESTORE": tree = saved!.Copy(); output.Add(Summary("RESTORE", tree)); break;
        }
        index = tree;
        return output;
    }
}

static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        Workbench workbench = new();
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine()!;
            try { foreach (string output in workbench.Process(line)) Console.WriteLine(output); }
            catch (CommandError error) { Console.WriteLine("ERROR " + error.Message); }
        }
    }
}
