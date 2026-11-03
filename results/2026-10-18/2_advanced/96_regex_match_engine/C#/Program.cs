global using System;
global using System.Collections.Generic;
global using System.Linq;
global using System.IO;
global using System.Text;
using System.Globalization;
sealed record Flags(bool I, bool M, bool S);
abstract record Instruction;
sealed record CharInstruction(int Code) : Instruction;
sealed record AnyInstruction : Instruction;
sealed record ClassInstruction(HashSet<int> Set, bool Negated) : Instruction;
sealed record SplitInstruction(int X, int Y) : Instruction;
sealed record JumpInstruction(int Target) : Instruction;
sealed record SaveInstruction(int Slot) : Instruction;
sealed record AssertInstruction(string Kind) : Instruction;
sealed record BackrefInstruction(int Group) : Instruction;
sealed record LookInstruction(string Kind, int Target) : Instruction;
sealed record MatchInstruction : Instruction;
abstract record Node;
sealed record LiteralNode(int Code) : Node;
sealed record AnyNode : Node;
sealed record ClassNode(HashSet<int> Set, bool Negated) : Node;
sealed record AssertNode(string Kind) : Node;
sealed record BackrefNode(int Group) : Node;
sealed record NamedNode(string Name) : Node;
sealed record GroupNode(int Group, Node Content) : Node;
sealed record LookNode(bool Positive, Node Content) : Node;
sealed record ConcatNode(List<Node> Nodes) : Node;
sealed record AlternateNode(List<Node> Nodes) : Node;
sealed record RepeatNode(Node Content, int Minimum, int? Maximum, string Kind) : Node;
sealed class PatternError(string reason, int column) : Exception(reason) {
    public int Column {
        get;
    } = column;
}
sealed record RegexPattern(string Name, string FlagsText, Flags Flags, string Text, int Groups, Dictionary<string, int> Names, Node? Root, List<Instruction> Code, PatternError? Error, bool Pike);
sealed class PatternParser(string text) {
    int index;
    public int Groups {
        get;
        private set;
    }
    public Dictionary<string, int> Names {
        get;
    } = new(StringComparer.Ordinal);
    readonly List<(int Column, int? Number, string Name)> references = new();
    int? Peek => index < text.Length ? text[index] : null;
    static bool OneOf(string values, int? c) => c.HasValue && values.Contains((char)c.Value);
    static PatternError Error(string message, int at) => new(message, at + 1);
    Node Alternation() {
        List<Node> nodes = new() {
            Concatenation()
        };
        while (Peek == 124) {
            index++;
            nodes.Add(Concatenation());
        }
        return nodes.Count == 1 ? nodes[0] : new AlternateNode(nodes);
    }
    Node Concatenation() {
        List<Node> nodes = new();
        while (Peek != null && !OneOf("|)", Peek)) nodes.Add(Quantified());
        return nodes.Count == 1 ? nodes[0] : new ConcatNode(nodes);
    }
    Node Quantified() {
        if (OneOf("*+?{", Peek)) throw Error("nothing to repeat", index);
        Node node = Element();
        if (!OneOf("*+?{", Peek)) return node;
        if (node is AssertNode or LookNode) throw Error("nothing to repeat", index);
        int minimum;
        int? maximum;
        if (Peek == 123) (minimum, maximum) = Braces();
        else {
            int c = text[index++];
            minimum = c == 43 ? 1 : 0;
            maximum = c == 63 ? 1 : null;
        }
        string kind;
        if (Peek == 63) {
            index++;
            kind = "lazy";
        } else if (Peek == 43) {
            index++;
            kind = "possessive";
        } else kind = "greedy";
        if (OneOf("*+?{", Peek)) throw Error("nested quantifier", index);
        return new RepeatNode(node, minimum, maximum, kind);
    }
    int? Digits() {
        int start = index;
        while (Peek.HasValue && Charset.Digit(Peek.Value)) index++;
        return start == index ? null : int.Parse(text[start..index]);
    }
    (int, int?) Braces() {
        int start = index++;
        int minimum = Digits() ?? throw Error("invalid quantifier", start);
        int? maximum;
        if (Peek == 125) maximum = minimum;
        else if (Peek == 44) {
            index++;
            maximum = Peek == 125 ? null : Digits() ?? throw Error("invalid quantifier", start);
        }
        else throw Error("invalid quantifier", start);
        if (Peek != 125) throw Error("invalid quantifier", start);
        index++;
        if (minimum > 100 || maximum.HasValue && maximum.Value > 100) throw Error("quantifier too large", start);
        if (maximum.HasValue && minimum > maximum.Value) throw Error("quantifier range out of order", start);
        return (minimum, maximum);
    }
    string Name() {
        int start = index;
        if (Peek.HasValue && (Charset.Letter(Peek.Value) || Peek == 95)) {
            index++;
            while (Peek.HasValue && Charset.Word(Peek.Value)) index++;
        }
        if (index == start || Peek != 62) throw Error("invalid group name", index);
        string name = text[start..index];
        index++;
        return name;
    }
    Node Group() {
        int start = index++;
        string mode = "capture";
        string? named = null;
        if (Peek == 63) {
            index++;
            mode = Peek switch {
                58 => "plain", 61 => "ahead", 33 => "negative", 60 => "capture", _ => throw Error("invalid group", start)
            };
            bool namedGroup = Peek == 60;
            index++;
            if (namedGroup) {
                int nameStart = index;
                string name = Name();
                if (Names.ContainsKey(name)) throw Error("duplicate group name", nameStart);
                named = name;
            }
        }
        int? number = null;
        if (mode == "capture") {
            Groups++;
            number = Groups;
            if (named != null) Names[named] = Groups;
        }
        Node content = Alternation();
        if (Peek != 41) throw Error("missing )", start);
        index++;
        return number.HasValue ? new GroupNode(number.Value, content) : mode == "plain" ? content : new LookNode(mode == "ahead", content);
    }
    (HashSet<int> Set, bool IsSet) ClassItem() {
        int start = index, c = Peek ?? throw Error("missing ]", start);
        index++;
        if (c != 92) return (new() {
            c
        }, false);
        int escaped = Peek ?? throw Error("trailing backslash", start);
        index++;
        if (OneOf("dDwWsS", escaped)) return (Charset.Base(escaped), true);
        if (escaped == 110) return (new() {
            10
        }, false);
        if (escaped == 116) return (new() {
            9
        }, false);
        if (Charset.Letter(escaped) || Charset.Digit(escaped)) throw Error("invalid escape", start);
        return (new() {
            escaped
        }, false);
    }
    Node CharacterClass() {
        int start = index++;
        bool negated = Peek == 94;
        if (negated) index++;
        if (Peek == 93) throw Error("empty class", index);
        HashSet<int> set = new();
        while (true) {
            if (!Peek.HasValue) throw Error("missing ]", start);
            if (Peek == 93) {
                index++;
                break;
            }
            var (left, leftSet) = ClassItem();
            if (Peek == 45 && index + 1 < text.Length && text[index + 1] != 93) {
                int hyphen = index++;
                if (leftSet) throw Error("invalid range", hyphen);
                var (right, rightSet) = ClassItem();
                int a = left.First(), b = right.First();
                if (rightSet || a > b) throw Error("invalid range", hyphen);
                for (int c = a; c <= b; c++) set.Add(c);
            } else set.UnionWith(left);
        }
        return new ClassNode(set, negated);
    }
    Node Escape() {
        int start = index++, c = Peek ?? throw Error("trailing backslash", start);
        index++;
        if (OneOf("dDwWsS", c)) return new ClassNode(Charset.Base(c >= 65 && c <= 90 ? c + 32 : c), c >= 65 && c <= 90);
        switch (c) {
            case 98: return new AssertNode("WORD");
            case 66: return new AssertNode("NOTWORD");
            case 110: return new LiteralNode(10);
            case 116: return new LiteralNode(9);
            case >= 49 and <= 57: index--;
            int number = Digits()!.Value;
            references.Add((start, number, ""));
            return new BackrefNode(number);
            case 107:
            if (Peek != 60) throw Error("invalid escape", start);
            index++;
            string name = Name();
            references.Add((start, null, name));
            return new NamedNode(name);
            default:
            if (Charset.Letter(c) || Charset.Digit(c)) throw Error("invalid escape", start);
            return new LiteralNode(c);
        }
    }
    Node Element() {
        int c = Peek!.Value;
        if (c == 40) return Group();
        if (c == 91) return CharacterClass();
        if (c == 92) return Escape();
        index++;
        return c switch {
            46 => new AnyNode(), 94 => new AssertNode("BOL"), 36 => new AssertNode("EOL"), _ => new LiteralNode(c)
        };
    }
    public Node Parse() {
        Node root = Alternation();
        if (index < text.Length) throw Error("unmatched )", index);
        foreach (var reference in references) {
            if (reference.Number.HasValue) {
                if (reference.Number.Value > Groups) throw Error("invalid group reference", reference.Column);
            }
            else if (!Names.ContainsKey(reference.Name)) throw Error("unknown group name", reference.Column);
        }
        return root;
    }
}
static class Program {
    static void Compile(Node node, List<Instruction> code, Dictionary<string, int> names) {
        switch (node) {
            case LiteralNode n: code.Add(new CharInstruction(n.Code));
            break;
            case AnyNode: code.Add(new AnyInstruction());
            break;
            case ClassNode n: code.Add(new ClassInstruction(n.Set, n.Negated));
            break;
            case AssertNode n: code.Add(new AssertInstruction(n.Kind));
            break;
            case BackrefNode n: code.Add(new BackrefInstruction(n.Group));
            break;
            case NamedNode n: code.Add(new BackrefInstruction(names[n.Name]));
            break;
            case GroupNode n: code.Add(new SaveInstruction(2 * n.Group));
            Compile(n.Content, code, names);
            code.Add(new SaveInstruction(2 * n.Group + 1));
            break;
            case LookNode n: {
                int start = code.Count;
                string kind = n.Positive ? "AHEAD" : "NOT";
                code.Add(new LookInstruction(kind, 0));
                Compile(n.Content, code, names);
                code.Add(new MatchInstruction());
                code[start] = new LookInstruction(kind, code.Count);
                break;
            }
            case ConcatNode n: foreach (Node child in n.Nodes) Compile(child, code, names);
            break;
            case AlternateNode n: {
                List<int> jumps = new();
                foreach (Node child in n.Nodes.SkipLast(1)) {
                    int split = code.Count;
                    code.Add(new SplitInstruction(split + 1, 0));
                    Compile(child, code, names);
                    jumps.Add(code.Count);
                    code.Add(new JumpInstruction(0));
                    code[split] = new SplitInstruction(split + 1, code.Count);
                }
                Compile(n.Nodes.Last(), code, names);
                int end = code.Count;
                foreach (int jump in jumps) code[jump] = new JumpInstruction(end);
                break;
            }
            case RepeatNode n: {
                if (n.Kind == "possessive") {
                    int start = code.Count;
                    code.Add(new LookInstruction("ATOMIC", 0));
                    Compile(n with {
                        Kind = "greedy"
                    }, code, names);
                    code.Add(new MatchInstruction());
                    code[start] = new LookInstruction("ATOMIC", code.Count);
                    break;
                }
                bool greedy = n.Kind == "greedy";
                if (n.Maximum.HasValue) {
                    for (int i = 0; i < n.Minimum; i++) Compile(n.Content, code, names);
                    List<int> splits = new();
                    for (int i = n.Minimum; i < n.Maximum.Value; i++) {
                        splits.Add(code.Count);
                        code.Add(new SplitInstruction(0, 0));
                        Compile(n.Content, code, names);
                    }
                    int end = code.Count;
                    foreach (int split in splits) code[split] = greedy ? new SplitInstruction(split + 1, end) : new SplitInstruction(end, split + 1);
                } else if (n.Minimum == 0) {
                    int split = code.Count;
                    code.Add(new SplitInstruction(0, 0));
                    Compile(n.Content, code, names);
                    code.Add(new JumpInstruction(split));
                    code[split] = greedy ? new SplitInstruction(split + 1, code.Count) : new SplitInstruction(code.Count, split + 1);
                } else {
                    for (int i = 0; i + 1 < n.Minimum; i++) Compile(n.Content, code, names);
                    int start = code.Count;
                    Compile(n.Content, code, names);
                    int end = code.Count + 1;
                    code.Add(greedy ? new SplitInstruction(start, end) : new SplitInstruction(end, start));
                }
                break;
            }
        }
    }
    static (int Minimum, int? Maximum) Length(Node node) {
        switch (node) {
            case LiteralNode or AnyNode or ClassNode: return (1, 1);
            case AssertNode or LookNode: return (0, 0);
            case BackrefNode or NamedNode: return (0, null);
            case GroupNode n: return Length(n.Content);
            case ConcatNode n: {
                var ranges = n.Nodes.Select(Length).ToList();
                return (ranges.Sum(x => x.Minimum), ranges.Any(x => !x.Maximum.HasValue) ? null : ranges.Sum(x => x.Maximum!.Value));
            }
            case AlternateNode n: {
                var ranges = n.Nodes.Select(Length).ToList();
                return (ranges.Min(x => x.Minimum), ranges.Any(x => !x.Maximum.HasValue) ? null : ranges.Max(x => x.Maximum!.Value));
            }
            case RepeatNode n: {
                var (a, b) = Length(n.Content);
                return (n.Minimum * a, b == 0 ? 0 : !b.HasValue || !n.Maximum.HasValue ? null : n.Maximum.Value * b.Value);
            }
            default: throw new InvalidOperationException();
        }
    }
    static (HashSet<int> Set, bool Nullable) First(Node node, Flags flags) {
        switch (node) {
            case LiteralNode n: return (flags.I && Charset.Letter(n.Code) ? new() {
                n.Code, Charset.Swap(n.Code)
            } : new() {
                n.Code
            }, false);
            case AnyNode: return (Enumerable.Range(0, 128).Where(c => flags.S || c != 10).ToHashSet(), false);
            case ClassNode n: return (Enumerable.Range(0, 128).Where(c => Charset.ClassMatches(c, n.Set, n.Negated, flags)).ToHashSet(), false);
            case AssertNode or LookNode: return (new(), true);
            case BackrefNode or NamedNode: return (Enumerable.Range(0, 128).ToHashSet(), true);
            case GroupNode n: return First(n.Content, flags);
            case ConcatNode n: {
                HashSet<int> set = new();
                foreach (Node child in n.Nodes) {
                    var (part, nullable) = First(child, flags);
                    set.UnionWith(part);
                    if (!nullable) return (set, false);
                } return (set, true);
            }
            case AlternateNode n: {
                var parts = n.Nodes.Select(child => First(child, flags)).ToList();
                return (parts.SelectMany(x => x.Set).ToHashSet(), parts.Any(x => x.Nullable));
            }
            case RepeatNode n: {
                if (n.Maximum == 0) return (new(), true);
                var (set, nullable) = First(n.Content, flags);
                return (set, nullable || n.Minimum == 0);
            }
            default: throw new InvalidOperationException();
        }
    }
    public static bool Consumes(Instruction instruction, List<int> subject, int q, Flags flags) {
        if (q == subject.Count) return false;
        return instruction switch {
            CharInstruction n => Charset.Equal(n.Code, subject[q], flags), AnyInstruction => flags.S || subject[q] != 10, ClassInstruction n => Charset.ClassMatches(subject[q], n.Set, n.Negated, flags), _ => false
        };
    }
    static RegexPattern ReadPattern(string line) {
        string[] f = line.Split(' ', 3);
        PatternParser parser = new(f[2]);
        Flags flags = new(f[1].Contains('i'), f[1].Contains('m'), f[1].Contains('s'));
        Node? root = null;
        PatternError? error = null;
        List<Instruction> code = new();
        try {
            root = parser.Parse();
            code.Add(new SaveInstruction(0));
            Compile(root, code, parser.Names);
            code.Add(new SaveInstruction(1));
            code.Add(new MatchInstruction());
        }
        catch (PatternError failure) {
            error = failure;
        }
        bool pike = !code.Any(instruction => instruction is BackrefInstruction or LookInstruction);
        return new(f[0], f[1], flags, f[2], parser.Groups, new(parser.Names, StringComparer.Ordinal), root, code, error, pike);
    }
    static List<int> Decode(string quoted) {
        List<int> result = new();
        int i = 1;
        while (i + 1 < quoted.Length) {
            if (quoted[i] == 92) {
                i++;
                result.Add(quoted[i] == 'n' ? 10 : quoted[i] == 't' ? 9 : quoted[i]);
            } else result.Add(quoted[i]);
            i++;
        }
        return result;
    }
    abstract record TemplatePart;
    sealed record CharacterPart(int Code) : TemplatePart;
    sealed record GroupPart(int Group) : TemplatePart;
    static List<TemplatePart>? Template(List<int> bytes, RegexPattern pattern) {
        List<TemplatePart> parts = new();
        int i = 0;
        while (i < bytes.Count) {
            if (bytes[i] != 36) {
                parts.Add(new CharacterPart(bytes[i++]));
                continue;
            }
            i++;
            if (i < bytes.Count && bytes[i] == 36) {
                parts.Add(new CharacterPart(36));
                i++;
                continue;
            }
            int number;
            if (i < bytes.Count && Charset.Digit(bytes[i])) number = bytes[i++] - 48;
            else if (i < bytes.Count && bytes[i] == 123) {
                i++;
                int end = bytes.FindIndex(i, c => c == 125);
                if (end < 0) return null;
                string name = new(bytes.Skip(i).Take(end - i).Select(c => (char)c).ToArray());
                i = end + 1;
                if (name.Length > 0 && name.All(c => Charset.Digit(c))) number = int.Parse(name);
                else if (!pattern.Names.TryGetValue(name, out number)) return null;
            } else return null;
            if (number > pattern.Groups) return null;
            parts.Add(new GroupPart(number));
        }
        return parts;
    }
    static List<int>? Group(int?[] capture, int k, List<int> subject) {
        int? a = capture[2 * k], b = capture[2 * k + 1];
        return a.HasValue && b.HasValue ? subject.GetRange(a.Value, b.Value - a.Value) : null;
    }
    static List<string> MatchLines(int?[] capture, RegexPattern pattern, List<int> subject) {
        List<string> lines = new();
        for (int k = 0; k <= pattern.Groups; k++) {
            string heading = k == 0 ? "match" : $"group {k}";
            List<int>? value = Group(capture, k, subject);
            lines.Add(value == null ? heading + " -" : $"{heading} {capture[2 * k]}-{capture[2 * k + 1]} {Formatter.Quote(value)}");
        }
        return lines;
    }
    static List<int?[]> ScanBacktrack(Backtrack vm, int length, bool scan) {
        List<int?[]> matches = new();
        int start = 0;
        while (start <= length) {
            int?[]? capture = vm.Search(start);
            if (capture == null) break;
            matches.Add(capture);
            start = capture[1]!.Value + (capture[0] == capture[1] ? 1 : 0);
            if (!scan) break;
        }
        return matches;
    }
    static List<int?[]> ScanPike(Pike vm, int length, bool scan) {
        List<int?[]> matches = new();
        int start = 0;
        while (start <= length) {
            int?[]? capture = vm.Search(start);
            if (capture == null) break;
            matches.Add(capture);
            start = capture[1]!.Value + (capture[0] == capture[1] ? 1 : 0);
            if (!scan) break;
        }
        return matches;
    }
    static List<string> ListPattern(RegexPattern pattern) {
        List<string> names = pattern.Names.OrderBy(pair => pair.Value).Select(pair => $"{pair.Key}:{pair.Value}").ToList();
        var (minimum, maximum) = Length(pattern.Root!);
        var (set, _) = First(pattern.Root!, pattern.Flags);
        List<string> lines = new() {
            "=== " + pattern.Name, $"flags={pattern.FlagsText} groups={pattern.Groups} names={(names.Count == 0 ? "-" : string.Join(",", names))} length={minimum}..{(maximum.HasValue ? maximum.Value.ToString() : "inf")} first={(set.Count == 0 ? "-" : Formatter.Set(set))} pike={(pattern.Pike ? "yes" : "no")} size={pattern.Code.Count}"
        };
        lines.AddRange(pattern.Code.Select((instruction, i) => $"{i} {Formatter.Instruction(instruction)}"));
        return lines;
    }
    static string[] ReadLines(string name) => File.ReadAllLines("input/" + name);
    static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n");
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        List<RegexPattern> patterns = ReadLines("patterns.txt").Select(ReadPattern).ToList();
        Dictionary<string, RegexPattern> byName = patterns.ToDictionary(pattern => pattern.Name, StringComparer.Ordinal);
        Dictionary<string, List<int>> subjects = new(StringComparer.Ordinal);
        foreach (string line in ReadLines("subjects.txt")) {
            string[] f = line.Split(' ', 2);
            subjects[f[0]] = Decode(f[1]);
        }
        List<string> errors = new(), results = new(), programs = new(), steps = new() {
            "command,engine,steps"
        };
        foreach (RegexPattern pattern in patterns) {
            if (pattern.Error is PatternError error) errors.AddRange(new[] {
                $"{pattern.Name}: {error.Message} at column {error.Column}", "  " + pattern.Text, new string(' ', error.Column + 1) + "^"
            });
        }
        if (errors.Count == 0) errors.Add("no errors");
        string[] commands = ReadLines("commands.txt");
        for (int index = 0; index < commands.Length; index++) {
            string line = commands[index];
            results.Add($"#{index + 1} {line}");
            string[] f = line.Split(' ', 5);
            string command = f[0];
            bool replacing = command == "REPLACE";
            RegexPattern pattern = byName[f[replacing ? 2 : 1]];
            if (pattern.Error != null) {
                results.Add("invalid pattern");
                continue;
            }
            if (command == "LIST") {
                results.Add($"instructions {pattern.Code.Count}");
                programs.AddRange(ListPattern(pattern));
                continue;
            }
            List<int> subject = subjects[f[replacing ? 3 : 2]];
            List<TemplatePart> parts;
            if (replacing) {
                List<TemplatePart>? parsed = Template(Decode(f[4]), pattern);
                if (parsed == null) {
                    results.Add("invalid template");
                    continue;
                } parts = parsed;
            } else parts = new();
            bool scan = command is "FINDALL" or "SPLIT" || replacing && f[1] == "ALL", full = command == "MATCH";
            Backtrack backtrack = new(pattern.Code, subject, pattern.Flags, pattern.Groups, full);
            List<int?[]>? backtrackMatches;
            try {
                backtrackMatches = ScanBacktrack(backtrack, subject.Count, scan);
            } catch (StepLimit) {
                backtrackMatches = null;
            }
            steps.Add($"{index + 1},backtrack,{backtrack.Steps}");
            List<int?[]> matches;
            string label;
            if (pattern.Pike) {
                Pike pike = new(pattern.Code, subject, pattern.Flags, pattern.Groups, full);
                List<int?[]> found = ScanPike(pike, subject.Count, scan);
                steps.Add($"{index + 1},pike,{pike.Steps}");
                if (backtrackMatches != null && (backtrackMatches.Count != found.Count || backtrackMatches.Where((capture, i) => !capture.SequenceEqual(found[i])).Any())) {
                    results.Add("MISMATCH");
                    continue;
                }
                matches = found;
                label = backtrackMatches == null ? "pike (backtrack: TOO_MANY_STEPS)" : "both";
            } else {
                if (backtrackMatches == null) {
                    results.Add("TOO_MANY_STEPS");
                    continue;
                } matches = backtrackMatches;
                label = "backtrack";
            }
            results.Add("engine " + label);
            if (command is "MATCH" or "SEARCH") {
                if (matches.Count == 0) results.Add("no match");
                else results.AddRange(MatchLines(matches[0], pattern, subject));
            }
            else if (command == "FINDALL") {
                results.Add($"matches {matches.Count}");
                foreach (int?[] capture in matches) results.AddRange(MatchLines(capture, pattern, subject));
            }
            else if (replacing) {
                List<int> result = new();
                int last = 0;
                foreach (int?[] capture in matches) {
                    result.AddRange(subject.GetRange(last, capture[0]!.Value - last));
                    foreach (TemplatePart part in parts) {
                        if (part is CharacterPart c) result.Add(c.Code);
                        else if (part is GroupPart g) result.AddRange(Group(capture, g.Group, subject) ?? new());
                    }
                    last = capture[1]!.Value;
                }
                result.AddRange(subject.Skip(last));
                results.AddRange(new[] {
                    $"replacements {matches.Count}", "result " + Formatter.Quote(result)
                });
            } else {
                results.AddRange(new[] {
                    $"pieces {matches.Count + 1}", "piece " + Formatter.Quote(subject.Take(matches.Count == 0 ? subject.Count : matches[0][0]!.Value))
                });
                for (int i = 0; i < matches.Count; i++) {
                    int?[] capture = matches[i];
                    for (int k = 1; k <= pattern.Groups; k++) {
                        List<int>? value = Group(capture, k, subject);
                        results.Add($"group {k} " + (value == null ? "-" : Formatter.Quote(value)));
                    }
                    int end = i + 1 < matches.Count ? matches[i + 1][0]!.Value : subject.Count;
                    results.Add("piece " + Formatter.Quote(subject.GetRange(capture[1]!.Value, end - capture[1]!.Value)));
                }
            }
        }
        if (programs.Count == 0) programs.Add("no programs");
        Write("results.txt", results);
        Write("programs.txt", programs);
        Write("steps.csv", steps);
        Write("errors.txt", errors);
    }
}
