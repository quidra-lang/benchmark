using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

enum NodeKind { Directory, File, Link }
abstract class Node(int inode, int modified)
{
    public int Inode { get; } = inode;
    public int Modified { get; set; } = modified;
    public DirectoryNode Parent { get; set; } = null!;
    public string Name { get; set; } = "";
    public abstract NodeKind Kind { get; }
    public abstract long Size { get; }
    public virtual int Links => 1;
    public char Tag => Kind switch { NodeKind.Directory => 'd', NodeKind.File => 'f', _ => 'l' };
}
sealed class DirectoryNode(int inode, int modified) : Node(inode, modified)
{
    public SortedDictionary<string, Node> Entries { get; } = new(StringComparer.Ordinal);
    public override NodeKind Kind => NodeKind.Directory;
    public override long Size => Entries.Count;
    public override int Links => 2 + Entries.Values.Count(node => node is DirectoryNode);
}
sealed class FileNode(int inode, int modified, IEnumerable<string>? lines = null) : Node(inode, modified)
{
    public List<string> Lines { get; set; } = lines?.ToList() ?? [];
    public override NodeKind Kind => NodeKind.File;
    public override long Size => Lines.Sum(line => (long)line.Length + 1);
}
sealed class LinkNode(int inode, int modified, string target) : Node(inode, modified)
{
    public string Target { get; } = target;
    public override NodeKind Kind => NodeKind.Link;
    public override long Size => Target.Length;
}
enum Failure { None, Missing, NotDirectory, TooManyLinks }
sealed record Resolution(Node? Node, Failure Error = Failure.None, DirectoryNode? CreationParent = null, string CreationName = "")
{
    public string Reason => Error switch
    {
        Failure.Missing => "No such file or directory",
        Failure.NotDirectory => "Not a directory",
        Failure.TooManyLinks => "Too many levels of symbolic links",
        _ => ""
    };
}
sealed record Options(HashSet<char> Flags, string[] Paths)
{
    public bool Has(char option) => Flags.Contains(option);
    public static Options Parse(string[] arguments)
    {
        var flags = new HashSet<char>();
        int position = 0;
        while (position < arguments.Length && arguments[position].StartsWith('-'))
            foreach (char flag in arguments[position++][1..]) flags.Add(flag);
        return new(flags, arguments[position..]);
    }
}

sealed class Shell
{
    readonly DirectoryNode root = new(1, 0);
    readonly Action<string> terminal;
    DirectoryNode current;
    string? previous;
    int clock;
    int nextInode = 2;

    public Shell(Action<string> terminal)
    {
        this.terminal = terminal;
        root.Parent = root;
        current = root;
    }
    string Absolute(Node node)
    {
        var names = new List<string>();
        while (node != root) { names.Add(node.Name); node = node.Parent; }
        names.Reverse();
        return "/" + string.Join("/", names);
    }
    bool Descendant(Node node, Node ancestor)
    {
        while (true)
        {
            if (node == ancestor) return true;
            if (node == root) return false;
            node = node.Parent;
        }
    }
    static string Join(string path, string name) => path == "/" ? "/" + name : path + "/" + name;
    static string Last(string path) => path[(path.LastIndexOf('/') + 1)..];
    static bool InvalidSource(string name) => name is "" or "." or "..";
    void Add(DirectoryNode parent, string name, Node node)
    {
        parent.Entries[name] = node;
        parent.Modified = clock;
        node.Parent = parent;
        node.Name = name;
    }
    Node Create(DirectoryNode parent, string name, NodeKind kind, IEnumerable<string>? lines = null, string target = "")
    {
        Node node = kind switch
        {
            NodeKind.Directory => new DirectoryNode(nextInode++, clock),
            NodeKind.File => new FileNode(nextInode++, clock, lines),
            _ => new LinkNode(nextInode++, clock, target)
        };
        Add(parent, name, node);
        return node;
    }
    void Detach(Node node)
    {
        node.Parent.Entries.Remove(node.Name);
        node.Parent.Modified = clock;
    }
    void Write(FileNode file, IEnumerable<string> lines, bool append = false)
    {
        if (append) file.Lines.AddRange(lines);
        else file.Lines = lines.ToList();
        file.Modified = clock;
    }
    Resolution Resolve(string path, bool follow = true, bool makeParents = false)
    {
        int expansions = 0;
        Resolution Walk(string text, DirectoryNode basis, bool finalLink, bool original)
        {
            Node node = text.StartsWith('/') ? root : basis;
            string[] components = text.Split('/', StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < components.Length; i++)
            {
                if (node is not DirectoryNode directory) return new(null, Failure.NotDirectory);
                string name = components[i];
                if (name == ".") continue;
                if (name == "..") { node = node.Parent; continue; }
                if (!directory.Entries.TryGetValue(name, out Node? child))
                {
                    if (original && makeParents && i + 1 < components.Length) child = Create(directory, name, NodeKind.Directory);
                    else return new(null, Failure.Missing, original && i + 1 == components.Length ? directory : null, name);
                }
                if (child is LinkNode link && (i + 1 < components.Length || finalLink))
                {
                    if (++expansions > 8) return new(null, Failure.TooManyLinks);
                    Resolution expanded = Walk(link.Target, directory, true, false);
                    if (expanded.Node is null) return expanded;
                    child = expanded.Node;
                }
                node = child;
            }
            return new(node);
        }
        return Walk(path, current, follow, true);
    }
    void Clone(Node source, DirectoryNode parent, string name)
    {
        Node clone = Create(parent, name, source.Kind, (source as FileNode)?.Lines, (source as LinkNode)?.Target ?? "");
        if (source is DirectoryNode directory)
            foreach (var (childName, child) in directory.Entries) Clone(child, (DirectoryNode)clone, childName);
    }
    static void WalkNodes(Node node, string path, Action<Node, string, int> visit, int depth = 0, int limit = 1000)
    {
        visit(node, path, depth);
        if (node is DirectoryNode directory && depth < limit)
            foreach (var (name, child) in directory.Entries) WalkNodes(child, Join(path, name), visit, depth + 1, limit);
    }
    void ReadInputs(string command, string[] paths, IReadOnlyList<string> input, Action<IReadOnlyList<string>, string?> consume)
    {
        if (paths.Length == 0) { consume(input, null); return; }
        foreach (string path in paths)
        {
            Resolution result = Resolve(path);
            if (result.Node is null) terminal($"{command}: {path}: {result.Reason}");
            else if (result.Node is DirectoryNode) terminal($"{command}: {path}: Is a directory");
            else consume(((FileNode)result.Node).Lines, path);
        }
    }
    void Move(string[] paths)
    {
        string destination = paths[^1];
        if (paths.Length > 2 && Resolve(destination).Node is not DirectoryNode)
        {
            terminal($"mv: target '{destination}' is not a directory");
            return;
        }
        foreach (string sourcePath in paths[..^1])
        {
            string basename = Last(sourcePath);
            void Problem(string displayPath, string reason) => terminal($"mv: cannot move '{sourcePath}' to '{displayPath}': {reason}");
            if (InvalidSource(basename)) { Problem(destination, "Invalid argument"); continue; }
            Resolution sourceResult = Resolve(sourcePath, false);
            Node? source = sourceResult.Node;
            if (source is null) { terminal($"mv: cannot stat '{sourcePath}': {sourceResult.Reason}"); continue; }
            DirectoryNode parent;
            string name, target;
            if (Resolve(destination).Node is DirectoryNode directory)
            {
                parent = directory;
                name = basename;
                target = Join(destination, basename);
            }
            else
            {
                Resolution result = Resolve(destination, false);
                if (result.Node is { } node) { parent = node.Parent; name = node.Name; }
                else if (result.CreationParent is { } creation) { parent = creation; name = result.CreationName; }
                else { Problem(destination, result.Reason); continue; }
                target = destination;
            }
            parent.Entries.TryGetValue(name, out Node? existing);
            if (source is DirectoryNode && Descendant(parent, source))
                terminal($"mv: cannot move '{sourcePath}' to a subdirectory of itself, '{target}'");
            else if (existing == source) terminal($"mv: '{sourcePath}' and '{target}' are the same file");
            else if (existing is not null && source is DirectoryNode && existing is not DirectoryNode)
                terminal($"mv: cannot overwrite non-directory '{target}' with directory '{sourcePath}'");
            else if (source is not DirectoryNode && existing is DirectoryNode)
                terminal($"mv: cannot overwrite directory '{target}' with non-directory '{sourcePath}'");
            else if (existing is DirectoryNode occupied && occupied.Entries.Count > 0) Problem(target, "Directory not empty");
            else if (existing == current) Problem(target, "Device or resource busy");
            else
            {
                if (existing is not null) Detach(existing);
                Detach(source);
                Add(parent, name, source);
            }
        }
    }
    void Copy(Options options)
    {
        string[] paths = options.Paths;
        string destination = paths[^1];
        if (paths.Length > 2 && Resolve(destination).Node is not DirectoryNode)
        {
            terminal($"cp: target '{destination}' is not a directory");
            return;
        }
        foreach (string sourcePath in paths[..^1])
        {
            string basename = Last(sourcePath);
            void Problem(string displayPath, string reason) => terminal($"cp: cannot copy '{sourcePath}' to '{displayPath}': {reason}");
            if (InvalidSource(basename)) { Problem(destination, "Invalid argument"); continue; }
            Resolution sourceResult = Resolve(sourcePath);
            Node? source = sourceResult.Node;
            if (source is null) { terminal($"cp: cannot stat '{sourcePath}': {sourceResult.Reason}"); continue; }
            if (source is DirectoryNode && !options.Has('r'))
            {
                terminal($"cp: -r not specified; omitting directory '{sourcePath}'");
                continue;
            }
            Resolution destinationResult = Resolve(destination);
            if (destinationResult.Node is null && destinationResult.CreationParent is null) { Problem(destination, destinationResult.Reason); continue; }
            string target = destinationResult.Node is DirectoryNode ? Join(destination, basename) : destination;
            Resolution result = Resolve(target, source is not DirectoryNode);
            if (source is DirectoryNode)
            {
                if (result.Node is not null) Problem(target, "File exists");
                else if (result.CreationParent is { } parent)
                {
                    if (Descendant(parent, source)) terminal($"cp: cannot copy a directory, '{sourcePath}', into itself, '{target}'");
                    else Clone(source, parent, result.CreationName);
                }
                else Problem(target, result.Reason);
            }
            else if (result.CreationParent is { } creation) Create(creation, result.CreationName, NodeKind.File, ((FileNode)source).Lines);
            else if (result.Node is null) Problem(target, result.Reason);
            else if (result.Node == source) terminal($"cp: '{sourcePath}' and '{target}' are the same file");
            else if (result.Node is DirectoryNode) terminal($"cp: cannot overwrite directory '{target}' with non-directory '{sourcePath}'");
            else Write((FileNode)result.Node, ((FileNode)source).Lines);
        }
    }
    void Listing(Options options, Action<string> output)
    {
        string[] paths = options.Paths.Length == 0 ? ["."] : options.Paths;
        foreach (string path in paths)
        {
            Resolution result = Resolve(path, !options.Has('l'));
            if (result.Node is null) { terminal($"ls: cannot access '{path}': {result.Reason}"); continue; }
            Node node = result.Node;
            var entries = new List<(string Name, Node Node)>();
            if (node is not DirectoryNode directory) entries.Add((path, node));
            else
            {
                if (paths.Length > 1) output(path + ":");
                if (options.Has('a')) { entries.Add((".", directory)); entries.Add(("..", directory.Parent)); }
                entries.AddRange(directory.Entries.Where(pair => options.Has('a') || !pair.Key.StartsWith('.')).Select(pair => (pair.Key, pair.Value)));
                if (options.Has('t')) entries = entries.OrderByDescending(entry => entry.Node.Modified).ToList();
                if (options.Has('r')) entries.Reverse();
            }
            static string[] Numbers(Node item) => [item.Links.ToString(), item.Size.ToString(), item.Modified.ToString()];
            var widths = new int[3];
            foreach (var entry in entries)
            {
                string[] values = Numbers(entry.Node);
                for (int i = 0; i < 3; i++) widths[i] = Math.Max(widths[i], values[i].Length);
            }
            foreach (var (name, item) in entries)
            {
                if (!options.Has('l')) { output(name); continue; }
                string line = item is FileNode ? "-" : item.Tag.ToString();
                string[] values = Numbers(item);
                for (int i = 0; i < 3; i++) line += " " + values[i].PadLeft(widths[i]);
                line += " " + name;
                if (item is LinkNode link) line += " -> " + link.Target;
                output(line);
            }
        }
    }
    static bool GlobMatches(string pattern, string text)
    {
        var previous = new bool[text.Length + 1];
        previous[0] = true;
        foreach (char c in pattern)
        {
            var next = new bool[previous.Length];
            if (c == '*')
            {
                next[0] = previous[0];
                for (int i = 0; i < text.Length; i++) next[i + 1] = previous[i + 1] || next[i];
            }
            else
                for (int i = 0; i < text.Length; i++) next[i + 1] = previous[i] && (c == '?' || c == text[i]);
            previous = next;
        }
        return previous[^1];
    }
    void Find(string[] arguments, Action<string> output)
    {
        int position = arguments.Length > 0 && !arguments[0].StartsWith('-') ? 1 : 0;
        string path = position == 1 ? arguments[0] : ".";
        string? pattern = null, type = null;
        int limit = 1000;
        for (; position < arguments.Length; position += 2)
        {
            switch (arguments[position])
            {
                case "-name": pattern = arguments[position + 1]; break;
                case "-type": type = arguments[position + 1]; break;
                case "-maxdepth": limit = int.Parse(arguments[position + 1]); break;
            }
        }
        Resolution result = Resolve(path);
        if (result.Node is null) { terminal($"find: '{path}': {result.Reason}"); return; }
        WalkNodes(result.Node, path, (node, display, depth) =>
        {
            string name = depth == 0 ? (path == "/" ? "/" : Last(path)) : node.Name;
            if ((pattern is null || GlobMatches(pattern, name)) && (type is null || type[0] == node.Tag)) output(display);
        }, limit: limit);
    }
    void DiskUsage(Options options, Action<string> output)
    {
        long Report(Node node, string path, bool show)
        {
            long usage = node is DirectoryNode ? 0 : node.Size;
            if (node is DirectoryNode directory)
                foreach (var (name, child) in directory.Entries)
                    usage += Report(child, Join(path, name), show && !options.Has('s') && (child is DirectoryNode || options.Has('a')));
            if (show) output($"{usage} {path}");
            return usage;
        }
        string[] paths = options.Paths.Length == 0 ? ["."] : options.Paths;
        foreach (string path in paths)
        {
            Resolution result = Resolve(path);
            if (result.Node is null) terminal($"du: cannot access '{path}': {result.Reason}");
            else Report(result.Node, path, true);
        }
    }
    void Tree(Options options, Action<string> output)
    {
        string path = options.Paths.FirstOrDefault() ?? ".";
        Resolution result = Resolve(path);
        if (result.Node is null) { terminal($"tree: {path}: {result.Reason}"); return; }
        if (result.Node is not DirectoryNode directory) { terminal($"tree: {path}: Not a directory"); return; }
        int directories = 0, files = 0;
        void Draw(DirectoryNode parent, string prefix)
        {
            var entries = parent.Entries.Where(pair => options.Has('a') || !pair.Key.StartsWith('.')).ToArray();
            for (int i = 0; i < entries.Length; i++)
            {
                var (name, child) = entries[i];
                bool last = i + 1 == entries.Length;
                string line = prefix + (last ? "`-- " : "|-- ") + name;
                if (child is LinkNode link) line += " -> " + link.Target;
                output(line);
                if (child is DirectoryNode nested) { directories++; Draw(nested, prefix + (last ? "    " : "|   ")); }
                else files++;
            }
        }
        output(path);
        Draw(directory, "");
        output($"{directories} {(directories == 1 ? "directory" : "directories")}, {files} {(files == 1 ? "file" : "files")}");
    }
    void Execute(string text, IReadOnlyList<string> input, Action<string> output)
    {
        string[] words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        string command = words[0];
        string[] arguments = words[1..];
        Options options = Options.Parse(arguments);
        switch (command)
        {
            case "pwd": output(Absolute(current)); break;
            case "echo": output(text[5..]); break;
            case "cd":
            {
                string path = arguments.FirstOrDefault() ?? "/";
                bool old = path == "-";
                if (old)
                {
                    if (previous is null) { terminal("cd: OLDPWD not set"); return; }
                    path = previous;
                }
                Resolution result = Resolve(path);
                if (result.Node is null) terminal($"cd: {path}: {result.Reason}");
                else if (result.Node is not DirectoryNode directory) terminal($"cd: {path}: Not a directory");
                else
                {
                    previous = Absolute(current);
                    current = directory;
                    if (old) output(Absolute(current));
                }
                break;
            }
            case "mkdir":
                foreach (string path in options.Paths)
                {
                    Resolution result = Resolve(path, false, options.Has('p'));
                    if (result.CreationParent is { } parent) Create(parent, result.CreationName, NodeKind.Directory);
                    else if (result.Node is null) terminal($"mkdir: cannot create directory '{path}': {result.Reason}");
                    else if (!options.Has('p') || Resolve(path).Node is not DirectoryNode)
                        terminal($"mkdir: cannot create directory '{path}': File exists");
                }
                break;
            case "touch":
                foreach (string path in arguments)
                {
                    Resolution result = Resolve(path);
                    if (result.CreationParent is { } parent) Create(parent, result.CreationName, NodeKind.File);
                    else if (result.Node is { } node) node.Modified = clock;
                    else terminal($"touch: cannot touch '{path}': {result.Reason}");
                }
                break;
            case "ls": Listing(options, output); break;
            case "stat":
                foreach (string path in arguments)
                {
                    Resolution result = Resolve(path, false);
                    if (result.Node is null) { terminal($"stat: cannot stat '{path}': {result.Reason}"); continue; }
                    Node node = result.Node;
                    string type = node switch
                    {
                        DirectoryNode => "directory",
                        LinkNode => "symbolic link",
                        FileNode file => file.Lines.Count == 0 ? "regular empty file" : "regular file",
                        _ => throw new InvalidOperationException()
                    };
                    output($"{path}: {type}, size {node.Size}, inode {node.Inode}, links {node.Links}, modified {node.Modified}");
                }
                break;
            case "rm":
                foreach (string path in options.Paths)
                {
                    void Problem(string reason) => terminal($"rm: cannot remove '{path}': {reason}");
                    if (Last(path) is "." or "..") { terminal($"rm: refusing to remove '.' or '..' directory: skipping '{path}'"); continue; }
                    Resolution result = Resolve(path, false);
                    if (result.Node is null)
                    {
                        if (!options.Has('f') || result.Error != Failure.Missing) Problem(result.Reason);
                    }
                    else if (result.Node is DirectoryNode && !options.Has('r')) Problem("Is a directory");
                    else if (Descendant(current, result.Node)) Problem("Device or resource busy");
                    else Detach(result.Node);
                }
                break;
            case "rmdir":
                foreach (string path in arguments)
                {
                    void Problem(string reason) => terminal($"rmdir: failed to remove '{path}': {reason}");
                    if (Last(path) is "." or "..") { Problem("Invalid argument"); continue; }
                    Resolution result = Resolve(path, false);
                    if (result.Node is null) Problem(result.Reason);
                    else if (result.Node is not DirectoryNode directory) Problem("Not a directory");
                    else if (Descendant(current, directory)) Problem("Device or resource busy");
                    else if (directory.Entries.Count > 0) Problem("Directory not empty");
                    else Detach(directory);
                }
                break;
            case "mv": Move(arguments); break;
            case "cp": Copy(options); break;
            case "ln":
            {
                string path = arguments[2];
                Resolution result = Resolve(path, false);
                if (result.CreationParent is { } parent) Create(parent, result.CreationName, NodeKind.Link, target: arguments[1]);
                else terminal($"ln: failed to create symbolic link '{path}': {(result.Node is null ? result.Reason : "File exists")}");
                break;
            }
            case "readlink":
            case "realpath":
            {
                string path = arguments[0];
                Resolution result = Resolve(path, command == "realpath");
                if (result.Node is null) terminal($"{command}: {path}: {result.Reason}");
                else if (command == "realpath") output(Absolute(result.Node));
                else if (result.Node is LinkNode link) output(link.Target);
                else terminal($"readlink: {path}: Invalid argument");
                break;
            }
            case "find": Find(arguments, output); break;
            case "du": DiskUsage(options, output); break;
            case "tree": Tree(options, output); break;
            case "cat":
            case "wc":
            case "head":
            case "tail":
            case "grep":
            case "sort":
            case "uniq": TextCommand(command, arguments, input, output); break;
            default: terminal(command + ": command not found"); break;
        }
    }
    static int NumericValue(string text)
    {
        int position = text.StartsWith('-') ? 1 : 0;
        int value = 0;
        while (position < text.Length && text[position] is >= '0' and <= '9') value = value * 10 + text[position++] - '0';
        return text.StartsWith('-') ? -value : value;
    }
    void TextCommand(string command, string[] arguments, IReadOnlyList<string> input, Action<string> output)
    {
        Options options = Options.Parse(arguments);
        string[] paths = options.Paths;
        if (command == "grep")
        {
            string pattern = paths[0];
            paths = paths[1..];
            if (options.Has('i')) pattern = pattern.ToLowerInvariant();
            bool named = paths.Length > 1 || options.Has('r');
            void Consume(IReadOnlyList<string> lines, string? name)
            {
                string prefix = named ? name + ":" : "";
                long count = 0;
                for (int i = 0; i < lines.Count; i++)
                {
                    string comparison = options.Has('i') ? lines[i].ToLowerInvariant() : lines[i];
                    if (comparison.Contains(pattern, StringComparison.Ordinal) == options.Has('v')) continue;
                    count++;
                    if (!options.Has('c')) output(prefix + (options.Has('n') ? $"{i + 1}:" : "") + lines[i]);
                }
                if (options.Has('c')) output(prefix + count);
            }
            if (!options.Has('r')) ReadInputs(command, paths, input, Consume);
            else
            {
                if (paths.Length == 0) paths = ["."];
                foreach (string path in paths)
                {
                    Resolution result = Resolve(path);
                    if (result.Node is null) { terminal($"grep: {path}: {result.Reason}"); continue; }
                    WalkNodes(result.Node, path, (node, display, _) =>
                    {
                        if (node is FileNode file) Consume(file.Lines, display);
                    });
                }
            }
            return;
        }
        if (command == "sort")
        {
            var lines = new List<string>();
            ReadInputs(command, paths, input, (part, _) => lines.AddRange(part));
            lines.Sort((a, b) =>
            {
                if (options.Has('n'))
                {
                    int difference = NumericValue(a).CompareTo(NumericValue(b));
                    if (difference != 0) return difference;
                }
                return StringComparer.Ordinal.Compare(a, b);
            });
            if (options.Has('r')) lines.Reverse();
            foreach (string line in lines) output(line);
            return;
        }
        string countText = "10";
        if (command is "head" or "tail")
        {
            int offset = arguments.Length > 0 && arguments[0] == "-n" ? 2 : 0;
            if (offset > 0) countText = arguments[1];
            paths = arguments[offset..];
        }
        var totals = new long[3];
        void ReportCounts(long[] counts, string? name)
        {
            var values = new List<string>();
            for (int i = 0; i < 3; i++)
                if (options.Flags.Count == 0 || options.Has("lwc"[i])) values.Add(counts[i].ToString());
            output(string.Join(" ", values) + (name is null ? "" : " " + name));
        }
        ReadInputs(command, paths, input, (lines, name) =>
        {
            if (command == "cat")
            {
                foreach (string line in lines) output(line);
            }
            else if (command == "wc")
            {
                long[] counts = [lines.Count, 0, 0];
                foreach (string line in lines)
                {
                    counts[2] += (long)line.Length + 1;
                    bool inside = false;
                    foreach (char c in line)
                    {
                        if (c != ' ' && !inside) counts[1]++;
                        inside = c != ' ';
                    }
                }
                for (int i = 0; i < 3; i++) totals[i] += counts[i];
                ReportCounts(counts, name);
            }
            else if (command is "head" or "tail")
            {
                int count = int.Parse(countText[0] is '-' or '+' ? countText[1..] : countText);
                int first = 0, last = lines.Count;
                if (command == "head") last = countText[0] == '-' ? Math.Max(0, last - count) : Math.Min(last, count);
                else first = countText[0] == '+' ? Math.Min(last, Math.Max(0, count - 1)) : Math.Max(0, last - count);
                for (int i = first; i < last; i++) output(lines[i]);
            }
            else
            {
                for (int first = 0; first < lines.Count;)
                {
                    int last = first + 1;
                    while (last < lines.Count && lines[last] == lines[first]) last++;
                    output((options.Has('c') ? $"{last - first} " : "") + lines[first]);
                    first = last;
                }
            }
        });
        if (command == "wc" && paths.Length > 1) ReportCounts(totals, "total");
    }
    public void Process(string line)
    {
        clock++;
        terminal(Absolute(current) + "$ " + line);
        int redirect = line.IndexOf(" >> ", StringComparison.Ordinal);
        bool append = redirect >= 0;
        if (!append) redirect = line.IndexOf(" > ", StringComparison.Ordinal);
        FileNode? redirectFile = null;
        string pipeline = line;
        if (redirect >= 0)
        {
            string path = line[(redirect + (append ? 4 : 3))..];
            pipeline = line[..redirect];
            Resolution result = Resolve(path);
            if (result.CreationParent is { } parent) redirectFile = (FileNode)Create(parent, result.CreationName, NodeKind.File);
            else if (result.Node is null) { terminal($"sh: {path}: {result.Reason}"); return; }
            else if (result.Node is not FileNode file) { terminal($"sh: {path}: Is a directory"); return; }
            else
            {
                redirectFile = file;
                if (!append) Write(file, []);
            }
        }
        string[] commands = pipeline.Split(" | ", StringSplitOptions.None);
        var input = new List<string>();
        for (int i = 0; i < commands.Length; i++)
        {
            var output = new List<string>();
            Execute(commands[i], input, text =>
            {
                if (i + 1 == commands.Length && redirectFile is null) terminal(text);
                else output.Add(text);
            });
            input = output;
        }
        if (redirectFile is not null && input.Count > 0) Write(redirectFile, input, true);
    }
}

static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var shell = new Shell(Console.WriteLine);
        while (Console.ReadLine() is { } line && line != "exit") shell.Process(line);
    }
}
