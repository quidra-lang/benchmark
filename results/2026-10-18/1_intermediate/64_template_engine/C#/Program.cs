using System.Text;
using System.Text.RegularExpressions;

class Program
{
    const string Identifier = "[A-Za-z_][A-Za-z0-9_]*";
    const string Subscript = "(?:0|[1-9][0-9]*)";
    static readonly string NamePattern = @"(?:\.|@(?:index|number|first|last)|(?:" + Identifier + "|" + Subscript + @")(?:\.(?:" + Identifier + "|" + Subscript + "))*)";
    static readonly HashSet<string> Filters = ["upper", "lower", "title", "trim", "length", "first", "last", "reverse", "items", "comma", "sum", "min", "max", "default", "eq", "pad", "lpad", "truncate", "replace", "join", "sort", "pluck", "add", "sub", "mul", "div", "mod", "gt", "lt"];
    record SourceLine(int Number, string Text);
    record KeyPart(object Key, string Prefix);
    record Filter(string Name, List<object> Arguments);
    record Expression(string Name, List<Filter> Filters);
    class Failure(string reason, int line = 0) : Exception(reason)
    {
        public int Line { get; } = line;
    }
    class Node(char kind, int line, string text)
    {
        public char Kind = kind;
        public int Line = line;
        public string Text = text, Indentation = "";
        public Expression? Expression;
        public List<Node> Children = [];
    }
    static Dictionary<string, object?> root = new(StringComparer.Ordinal);
    static readonly Dictionary<string, List<SourceLine>> Partials = new(StringComparer.Ordinal);
    static readonly Dictionary<string, List<SourceLine>> Templates = new(StringComparer.Ordinal);
    static bool strict;
    static bool Matches(string text, string pattern) => Regex.IsMatch(text, @"\A(?:" + pattern + @")\z");
    static string Strip(string text) => text.Trim(' ');
    static bool Has(object? value, object key) => key is string name
        ? value is Dictionary<string, object?> map && map.ContainsKey(name)
        : value is List<object?> list && (int)key >= 0 && (int)key < list.Count;
    static object? Get(object? value, object key) => key is string name
        ? ((Dictionary<string, object?>)value!)[name] : ((List<object?>)value!)[(int)key];
    static void Put(object container, object key, object? value)
    {
        if (key is string name) ((Dictionary<string, object?>)container)[name] = value;
        else
        {
            var list = (List<object?>)container;
            if ((int)key == list.Count) list.Add(value); else list[(int)key] = value;
        }
    }
    static object? Copy(object? value) => value switch
    {
        Dictionary<string, object?> map => map.ToDictionary(pair => pair.Key, pair => Copy(pair.Value), StringComparer.Ordinal),
        List<object?> list => list.Select(Copy).ToList(),
        _ => value
    };
    static List<KeyPart> ParseKey(string key)
    {
        if (!Matches(key, Identifier + @"(?:\." + Identifier + @"|\[" + Subscript + @"\])*"))
            throw new Failure($"bad key '{key}'");
        List<KeyPart> parts = [];
        foreach (Match match in Regex.Matches(key, "(" + Identifier + @")|\[(" + Subscript + @")\]"))
            parts.Add(new(match.Groups[1].Success ? match.Groups[1].Value : int.Parse(match.Groups[2].Value), key[..(match.Index + match.Length)]));
        return parts;
    }
    class ValueReader(string text)
    {
        public int Position;
        object Scalar()
        {
            if (Position < text.Length && text[Position] == '"')
            {
                Position++;
                StringBuilder result = new();
                while (Position < text.Length)
                {
                    char c = text[Position++];
                    if (c == '"') return result.ToString();
                    if (c == '\\')
                    {
                        if (Position == text.Length) throw new Failure("");
                        c = text[Position++];
                        if (c == 'n') c = '\n';
                        else if (c is not ('"' or '\\')) throw new Failure("");
                    }
                    result.Append(c);
                }
                throw new Failure("");
            }
            int start = Position;
            while (Position < text.Length && text[Position] is not (',' or ']')) Position++;
            string word = text[start..Position];
            if (word is "true" or "false") return word == "true";
            if (!Matches(word, "0|-?[1-9][0-9]*")) throw new Failure("");
            return int.Parse(word);
        }
        public object Read()
        {
            if (text == "{}") { Position = 2; return new Dictionary<string, object?>(StringComparer.Ordinal); }
            if (text == "[]") { Position = 2; return new List<object?>(); }
            if (!text.StartsWith('[')) return Scalar();
            Position = 1;
            List<object?> result = [];
            while (true)
            {
                result.Add(Scalar());
                if (text[Position..].StartsWith(", ", StringComparison.Ordinal)) Position += 2;
                else if (text[Position..] == "]") { Position++; return result; }
                else throw new Failure("");
            }
        }
    }
    static object ParseValue(string notation)
    {
        try
        {
            ValueReader reader = new(notation);
            object result = reader.Read();
            if (reader.Position != notation.Length) throw new Failure("");
            return result;
        }
        catch (Exception error) when (error is Failure or OverflowException or FormatException)
        { throw new Failure($"bad value '{notation}'"); }
    }
    static void Data(List<SourceLine> lines)
    {
        int sets = 0, unsets = 0;
        List<string> errors = [];
        foreach (var line in lines)
        {
            string text = line.Text;
            if (text.Length == 0 || text.StartsWith('#')) continue;
            try
            {
                bool remove = text.StartsWith("UNSET ", StringComparison.Ordinal);
                int equal = text.IndexOf(" = ", StringComparison.Ordinal);
                if (!remove && equal < 0) throw new Failure("bad line");
                string key = remove ? text[6..] : text[..equal];
                var parts = ParseKey(key);
                object? item = remove ? null : ParseValue(text[(equal + 3)..]);
                var candidate = (Dictionary<string, object?>)Copy(root)!;
                object? container = candidate;
                for (int i = 0; i < parts.Count; i++)
                {
                    var part = parts[i];
                    bool found = Has(container, part.Key);
                    if (remove)
                    {
                        if (!found) throw new Failure($"no value at '{key}'");
                        if (i == parts.Count - 1)
                        {
                            if (part.Key is string name) ((Dictionary<string, object?>)container!).Remove(name);
                            else ((List<object?>)container!).RemoveAt((int)part.Key);
                        }
                        else container = Get(container, part.Key);
                    }
                    else
                    {
                        if (part.Key is int index && index > ((List<object?>)container!).Count)
                            throw new Failure($"index gap at '{part.Prefix}'");
                        if (i == parts.Count - 1) Put(container!, part.Key, item);
                        else
                        {
                            bool wantMap = parts[i + 1].Key is string;
                            if (found)
                            {
                                object? next = Get(container, part.Key);
                                if (wantMap ? next is not Dictionary<string, object?> : next is not List<object?>)
                                    throw new Failure($"type conflict at '{part.Prefix}'");
                                container = next;
                            }
                            else
                            {
                                object next = wantMap ? new Dictionary<string, object?>(StringComparer.Ordinal) : new List<object?>();
                                Put(container!, part.Key, next);
                                container = next;
                            }
                        }
                    }
                }
                root = candidate;
                if (remove) unsets++; else sets++;
            }
            catch (Failure error) { errors.Add($"ERROR line {line.Number}: {error.Message}"); }
        }
        Console.WriteLine($"DATA set={sets} unset={unsets} errors={errors.Count}");
        errors.ForEach(Console.WriteLine);
    }
    static List<string> SplitUnquoted(string text, char separator)
    {
        List<string> result = [];
        int start = 0;
        bool quoted = false;
        for (int i = 0; i < text.Length; i++)
            if (text[i] == '\'') quoted = !quoted;
            else if (text[i] == separator && !quoted) { result.Add(text[start..i]); start = i + 1; }
        result.Add(text[start..]);
        return result;
    }
    static bool ValidArguments(string name, List<object> args)
    {
        int count = args.Count;
        bool integer = count > 0 && args[0] is int;
        bool text = count > 0 && args[0] is string;
        return name switch
        {
            "default" or "eq" => count == 1,
            "pad" or "lpad" => count is 1 or 2 && integer && (int)args[0] >= 0 && (count == 1 || args[1] is string s && s.Length == 1),
            "truncate" => count == 1 && integer && (int)args[0] >= 0,
            "replace" => count == 2 && text && ((string)args[0]).Length > 0 && args[1] is string,
            "join" or "pluck" => count == 1 && text,
            "sort" => count == 0 || count == 1 && text,
            "div" or "mod" => count == 1 && integer && (int)args[0] != 0,
            "add" or "sub" or "mul" or "gt" or "lt" => count == 1 && integer,
            _ => count == 0
        };
    }
    static Expression ParseExpression(string text, int line)
    {
        var pieces = SplitUnquoted(text, '|');
        string name = Strip(pieces[0]);
        if (!Matches(name, NamePattern)) throw new Failure($"invalid name '{name}'", line);
        List<Filter> filters = [];
        foreach (string piece in pieces.Skip(1))
        {
            var fields = SplitUnquoted(Strip(piece), ':');
            string filter = fields[0];
            if (!Filters.Contains(filter)) throw new Failure($"unknown filter '{filter}'", line);
            List<object> arguments = [];
            bool valid = true;
            foreach (string argument in fields.Skip(1))
                if (Matches(argument, "'[^']*'")) arguments.Add(argument[1..^1]);
                else if (Matches(argument, "-?[0-9]{1,9}")) arguments.Add(int.Parse(argument));
                else valid = false;
            if (!valid || !ValidArguments(filter, arguments)) throw new Failure($"bad arguments for '{filter}'", line);
            filters.Add(new(filter, arguments));
        }
        return new(name, filters);
    }
    static List<Node> Analyze(List<SourceLine> source, string indentation)
    {
        List<Node> result = [];
        Stack<Node> open = new();
        Stack<List<Node>> levels = new();
        levels.Push(result);
        string opening = "{{", closing = "}}";
        foreach (var line in source)
        {
            string text = line.Text.Length == 0 ? "" : indentation + line.Text;
            List<Node> nodes = [];
            int position = 0, tags = 0;
            while (true)
            {
                int start = text.IndexOf(opening, position, StringComparison.Ordinal);
                if (start < 0) { nodes.Add(new('T', line.Number, text[position..])); break; }
                nodes.Add(new('T', line.Number, text[position..start]));
                int begin = start + opening.Length;
                bool triple = begin < text.Length && text[begin] == '{';
                if (triple) begin++;
                string endText = (triple ? "}" : "") + closing;
                int end = text.IndexOf(endText, begin, StringComparison.Ordinal);
                if (end < 0) throw new Failure("unclosed tag", line.Number);
                string content = Strip(text[begin..end]);
                char kind = triple ? 'R' : content.Length > 0 && "#^/!>&=".Contains(content[0]) ? content[0] : 'V';
                string argument = kind == 'V' || triple ? content : Strip(content[1..]);
                if (kind == '&') kind = 'R';
                Node node = new(kind, line.Number, argument);
                tags++;
                if (kind == '=')
                {
                    if (content.Length < 2 || !content.EndsWith('=')) throw new Failure("invalid delimiters", line.Number);
                    string[] pair = Strip(content[1..^1]).Split(' ', StringSplitOptions.RemoveEmptyEntries);
                    if (pair.Length != 2 || pair.Any(s => s.Contains('='))) throw new Failure("invalid delimiters", line.Number);
                    opening = pair[0]; closing = pair[1];
                }
                else if (kind is 'V' or 'R' or '#' or '^')
                {
                    node.Expression = ParseExpression(argument, line.Number);
                    if (kind is '#' or '^') open.Push(node);
                }
                else if (kind == '/')
                {
                    if (!Matches(argument, NamePattern)) throw new Failure($"invalid name '{argument}'", line.Number);
                    if (open.Count == 0) throw new Failure($"unexpected closing '{argument}'", line.Number);
                    string expected = open.Peek().Expression!.Name;
                    if (argument != expected) throw new Failure($"mismatched closing '{argument}', expected '{expected}'", line.Number);
                    open.Pop();
                }
                else if (kind == '>' && !Matches(argument, Identifier)) throw new Failure($"invalid name '{argument}'", line.Number);
                nodes.Add(node);
                position = end + endText.Length;
            }
            Node? only = nodes.FirstOrDefault(node => node.Kind != 'T');
            bool standalone = tags == 1 && nodes.Where(node => node.Kind == 'T').All(node => node.Text.All(c => c == ' ')) && "#^/!>=".Contains(only!.Kind);
            if (standalone && only!.Kind == '>') only.Indentation = nodes[0].Text;
            if (!standalone) nodes.Add(new('T', line.Number, "\n"));
            foreach (Node node in nodes)
            {
                if (standalone && node.Kind == 'T') continue;
                if (node.Kind == '/') levels.Pop();
                else
                {
                    levels.Peek().Add(node);
                    if (node.Kind is '#' or '^') levels.Push(node.Children);
                }
            }
        }
        if (open.Count > 0) throw new Failure($"unclosed section '{open.Peek().Expression!.Name}'", open.Peek().Line);
        return result;
    }
    static bool Truth(object? value) => value switch
    {
        null => false, bool b => b, int n => n != 0, string s => s.Length > 0,
        List<object?> list => list.Count > 0, Dictionary<string, object?> map => map.Count > 0,
        _ => throw new InvalidOperationException()
    };
    static string StringValue(object? value) => value switch
    {
        null => "", string s => s, bool b => b ? "true" : "false", int n => n.ToString(System.Globalization.CultureInfo.InvariantCulture),
        List<object?> list => string.Join(", ", list.Select(StringValue)),
        _ => throw new Failure("cannot render map")
    };
    static int Number(object? value, string filter) => value switch
    {
        null => 0, int n => n,
        string s when Matches(s, "-?[0-9]{1,9}") => int.Parse(s),
        _ => throw new Failure($"not a number for '{filter}'")
    };
    static int Rank(object? value) => value switch { null => 0, int => 1, string => 2, bool => 3, _ => 4 };
    static object? SortKey(object? value, List<object> args) => args.Count == 0 ? value
        : value is Dictionary<string, object?> map ? map.GetValueOrDefault((string)args[0]) : null;
    static int Compare(object? left, object? right)
    {
        int order = Rank(left).CompareTo(Rank(right));
        if (order != 0) return order;
        return Rank(left) switch { 1 => ((int)left!).CompareTo((int)right!), 2 => StringComparer.Ordinal.Compare((string)left!, (string)right!), 3 => ((bool)left!).CompareTo((bool)right!), _ => 0 };
    }
    static object? Apply(object? value, Filter filter)
    {
        string name = filter.Name;
        var args = filter.Arguments;
        switch (name)
        {
            case "default": return Truth(value) ? value : args[0];
            case "eq": return StringValue(value) == StringValue(args[0]);
            case "length": return value is Dictionary<string, object?> map ? map.Count : value is List<object?> list ? list.Count : StringValue(value).Length;
            case "first": case "last": return value is List<object?> items ? items.Count == 0 ? null : items[name == "first" ? 0 : items.Count - 1] : value;
            case "reverse": return value is List<object?> reversed ? reversed.AsEnumerable().Reverse().ToList() : value is string s ? new string(s.Reverse().ToArray()) : value;
            case "items":
                if (value is not Dictionary<string, object?> entries) return value;
                return entries.OrderBy(pair => pair.Key, StringComparer.Ordinal).Select(pair => (object?)new Dictionary<string, object?> { ["key"] = pair.Key, ["value"] = pair.Value }).ToList();
            case "sort": case "pluck":
                if (value is not List<object?> values) return value;
                if (name == "pluck") return values.Select(item => SortKey(item, args)).ToList();
                return values.OrderBy(item => SortKey(item, args), Comparer<object?>.Create(Compare)).ToList();
            case "sum": case "min": case "max":
                if (value is not List<object?> numbers) return Number(value, name);
                int? total = name == "sum" ? 0 : null;
                foreach (object? item in numbers)
                {
                    int n = Number(item, name);
                    total = total is null ? n : name == "sum" ? total + n : name == "min" ? Math.Min(total.Value, n) : Math.Max(total.Value, n);
                }
                return total;
            case "add": case "sub": case "mul": case "div": case "mod": case "gt": case "lt":
                int number = Number(value, name), argument = (int)args[0];
                int quotient = name is "div" or "mod" ? number / argument : 0;
                if (name is "div" or "mod" && number % argument != 0 && (number < 0) != (argument < 0)) quotient--;
                return name switch { "add" => number + argument, "sub" => number - argument, "mul" => number * argument, "div" => quotient, "mod" => number - argument * quotient, "gt" => number > argument, _ => number < argument };
            case "comma": return Number(value, name).ToString("N0", System.Globalization.CultureInfo.InvariantCulture);
            case "join": return value is List<object?> joined ? string.Join((string)args[0], joined.Select(StringValue)) : StringValue(value);
        }
        string text = StringValue(value);
        switch (name)
        {
            case "upper": return text.ToUpperInvariant();
            case "lower": return text.ToLowerInvariant();
            case "trim": return Strip(text);
            case "title":
                StringBuilder title = new();
                for (int i = 0; i < text.Length; i++) title.Append(i == 0 || text[i - 1] == ' ' ? char.ToUpperInvariant(text[i]) : char.ToLowerInvariant(text[i]));
                return title.ToString();
            case "pad": case "lpad":
                string padding = new(args.Count == 1 ? ' ' : ((string)args[1])[0], Math.Max(0, (int)args[0] - text.Length));
                return name == "pad" ? text + padding : padding + text;
            case "truncate": return text.Length > (int)args[0] ? text[..(int)args[0]] + "..." : text;
            case "replace": return text.Replace((string)args[0], (string)args[1], StringComparison.Ordinal);
            default: throw new InvalidOperationException();
        }
    }
    static object IndexPart(string part) => Matches(part, Subscript) ? int.TryParse(part, out int number) ? number : -1 : part;
    static (bool Found, object? Value) Resolve(string name, List<object?> contexts, List<(int Index, int Count)> loops)
    {
        if (name == ".") return (true, contexts[^1]);
        if (name.StartsWith('@'))
        {
            if (loops.Count == 0) return (false, null);
            var loop = loops[^1];
            object value = name switch { "@index" => loop.Index, "@number" => loop.Index + 1, "@first" => loop.Index == 0, _ => loop.Index == loop.Count - 1 };
            return (true, value);
        }
        string[] parts = name.Split('.');
        object? current = null;
        bool found = false;
        for (int i = contexts.Count - 1; i >= 0; i--)
            if (Has(contexts[i], IndexPart(parts[0]))) { current = contexts[i]; found = true; break; }
        if (!found) return (false, null);
        foreach (string part in parts)
        {
            object key = IndexPart(part);
            if (!Has(current, key)) return (false, null);
            current = Get(current, key);
        }
        return (true, current);
    }
    static string Html(string text) => text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;").Replace("'", "&#39;");
    static void Render(List<Node> nodes, List<object?> contexts, List<(int Index, int Count)> loops, int depth, StringBuilder output)
    {
        foreach (Node node in nodes)
        {
            try
            {
                if (node.Kind == 'T') { output.Append(node.Text); continue; }
                if (node.Kind == '>')
                {
                    if (!Partials.TryGetValue(node.Text, out var partial)) throw new Failure($"unknown partial '{node.Text}'");
                    if (depth == 8) throw new Failure($"partial depth exceeded at '{node.Text}'");
                    Render(Analyze(partial, node.Indentation), contexts, loops, depth + 1, output);
                    continue;
                }
                if (node.Expression is null) continue;
                var resolved = Resolve(node.Expression.Name, contexts, loops);
                if (strict && node.Kind is 'V' or 'R' && !resolved.Found) throw new Failure($"missing '{node.Expression.Name}'");
                object? value = resolved.Value;
                foreach (Filter filter in node.Expression.Filters) value = Apply(value, filter);
                if (node.Kind is 'V' or 'R') { string text = StringValue(value); output.Append(node.Kind == 'V' ? Html(text) : text); }
                else if (node.Kind == '^') { if (!Truth(value)) Render(node.Children, contexts, loops, depth, output); }
                else if (value is List<object?> items)
                {
                    for (int i = 0; i < items.Count; i++)
                    {
                        contexts.Add(items[i]); loops.Add((i, items.Count));
                        Render(node.Children, contexts, loops, depth, output);
                        contexts.RemoveAt(contexts.Count - 1); loops.RemoveAt(loops.Count - 1);
                    }
                }
                else if (Truth(value)) { contexts.Add(value); Render(node.Children, contexts, loops, depth, output); contexts.RemoveAt(contexts.Count - 1); }
            }
            catch (Failure error) when (error.Line == 0) { throw new Failure(error.Message, node.Line); }
        }
    }
    static void RenderTemplate(string name, int line)
    {
        try
        {
            if (!Templates.TryGetValue(name, out var body)) throw new Failure($"unknown template '{name}'", line);
            StringBuilder output = new();
            Render(Analyze(body, ""), [root], [], 0, output);
            string result = output.ToString();
            int count = result.Length == 0 ? 0 : result.Count(c => c == '\n') + (result.EndsWith('\n') ? 0 : 1);
            Console.WriteLine($"TEMPLATE {name} OK lines={count} chars={result.Length}");
            Console.Write(result);
            if (result.Length > 0 && !result.EndsWith('\n')) Console.WriteLine();
        }
        catch (Failure error) { Console.WriteLine($"TEMPLATE {name} ERROR line {error.Line}: {error.Message}"); }
    }
    static void Leaves(object? value, string path, List<string> output)
    {
        if (value is Dictionary<string, object?> map && map.Count > 0)
            foreach (var pair in map.OrderBy(pair => pair.Key, StringComparer.Ordinal)) Leaves(pair.Value, path.Length == 0 ? pair.Key : path + "." + pair.Key, output);
        else if (value is List<object?> list && list.Count > 0)
            for (int i = 0; i < list.Count; i++) Leaves(list[i], $"{path}[{i}]", output);
        else
        {
            string notation = value switch { string s => "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n") + "\"", Dictionary<string, object?> => "{}", List<object?> => "[]", _ => StringValue(value) };
            output.Add(path + " = " + notation);
        }
    }
    static void Main()
    {
        int number = 0;
        string? command;
        while ((command = Console.ReadLine()) is not null)
        {
            number++;
            if (command == "END") break;
            if (command == "DATA" || command.StartsWith("PARTIAL ", StringComparison.Ordinal) || command.StartsWith("TEMPLATE ", StringComparison.Ordinal))
            {
                string type = command.Split(' ')[0], name = type == "DATA" ? "" : command[(type.Length + 1)..];
                List<SourceLine> body = [];
                int start = number;
                string? text;
                while ((text = Console.ReadLine()) is not null) { number++; if (text == "END" + type) break; body.Add(new(number, text)); }
                if (type == "DATA") Data(body);
                else if (type == "TEMPLATE") { Templates[name] = body; RenderTemplate(name, start); }
                else
                {
                    try
                    {
                        Analyze(body, "");
                        bool existed = Partials.ContainsKey(name); Partials[name] = body;
                        Console.WriteLine($"PARTIAL {name} {(existed ? "REPLACED" : "DEFINED")} lines={body.Count}");
                    }
                    catch (Failure error) { Console.WriteLine($"PARTIAL {name} ERROR line {error.Line}: {error.Message}"); }
                }
            }
            else if (command.StartsWith("RENDER ", StringComparison.Ordinal)) RenderTemplate(command[7..], number);
            else if (command == "DUMP")
            {
                List<string> output = [];
                foreach (var pair in root.OrderBy(pair => pair.Key, StringComparer.Ordinal)) Leaves(pair.Value, pair.Key, output);
                Console.WriteLine($"DUMP leaves={output.Count}"); output.ForEach(Console.WriteLine);
            }
            else if (command == "RESET") { root = new(StringComparer.Ordinal); Partials.Clear(); Templates.Clear(); Console.WriteLine(command); }
            else { strict = command == "STRICT ON"; Console.WriteLine(command); }
        }
    }
}
