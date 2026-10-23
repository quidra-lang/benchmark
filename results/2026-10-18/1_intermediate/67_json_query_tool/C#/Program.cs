using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using JsonObject = System.Collections.Generic.OrderedDictionary<string, object?>;

class Program
{
    const string Identifier = "[A-Za-z_][A-Za-z0-9_]*";
    static readonly object Missing = new();
    static readonly HashSet<string> Commands = ["GET", "COMPACT", "PRETTY", "TYPE", "LENGTH", "KEYS", "FLATTEN", "COUNT", "SUM", "MIN", "MAX", "AVG", "FILTER", "SET", "DELETE", "INSERT", "MERGE", "SORT", "RENAME", "UNDO"];

    static object? document;
    static readonly List<object?> History = [];

    class Problem(string message) : Exception(message) { }

    class ParseError(int position, string reason) : Exception(reason)
    {
        public int Position = position;
    }

    static bool Matches(string text, string pattern) => Regex.IsMatch(text, @"\A(?:" + pattern + @")\z");

    static bool Letter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';

    static bool Digit(char c) => c is >= '0' and <= '9';

    static bool IntegerNotation(string text) => Matches(text, "0|-?[1-9][0-9]{0,8}");

    static string Quote(string text, char delimiter)
    {
        StringBuilder output = new();
        output.Append(delimiter);
        foreach (char c in text) if (c == delimiter || c == '\\') output.Append('\\').Append(c);
        else output.Append(c switch { '\b' => "\\b", '\f' => "\\f", '\n' => "\\n", '\r' => "\\r", '\t' => "\\t", _ => c < 32 || c == 127 ? "\\u" + ((int)c).ToString("x4", CultureInfo.InvariantCulture) : c.ToString() });
        return output.Append(delimiter).ToString();
    }

    class Parser(string text)
    {
        protected readonly string Text = text;
        public int Position;
        public char Peek => Position == Text.Length ? '\0' : Text[Position];
        void Fail(string reason) => throw new ParseError(Position, reason);
        void Whitespace()
        {
            while (Peek is ' ' or '\n') Position++;
        }
        void NeedCharacter()
        {
            if (Position == Text.Length) Fail("unexpected end of input");
        }
        public string String(char delimiter)
        {
            Position++;
            StringBuilder output = new();
            while (true)
            {
                if (Position == Text.Length || Peek == '\n') Fail("unterminated string");
                char c = Peek;
                if (c == delimiter)
                {
                    Position++;
                    return output.ToString();
                }
                if (c != '\\')
                {
                    output.Append(c);
                    Position++;
                    continue;
                }
                int start = Position++;
                if (Position == Text.Length || Peek == '\n') Fail("unterminated string");
                char escaped = Peek;
                if (escaped == 'u')
                {
                    if (Position + 4 >= Text.Length || !Matches(Text.Substring(Position + 1, 4), "[0-9A-Fa-f]{4}")) throw new ParseError(start, "bad unicode escape");
                    int value = int.Parse(Text.AsSpan(Position + 1, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                    if (value > 127) throw new ParseError(start, "non-ascii escape");
                    output.Append((char)value);
                    Position += 5;
                }
                else
                {
                    char value = escaped switch { '\\' or '/' => escaped, 'b' => '\b', 'f' => '\f', 'n' => '\n', 'r' => '\r', 't' => '\t', _ => escaped == delimiter ? delimiter : '\0' };
                    if (value == '\0') throw new ParseError(start, $"invalid escape '\\{escaped}'");
                    output.Append(value);
                    Position++;
                }
            }
        }
        object? Value()
        {
            Whitespace();
            NeedCharacter();
            char c = Peek;
            if (c == '"') return String('"');
            if (c == '{')
            {
                Position++;
                Whitespace();
                JsonObject map = new(StringComparer.Ordinal);
                if (Peek == '}')
                {
                    Position++;
                    return map;
                }
                while (true)
                {
                    Whitespace();
                    NeedCharacter();
                    if (Peek != '"') Fail("expected key");
                    int start = Position;
                    string key = String('"');
                    if (map.ContainsKey(key)) throw new ParseError(start, "duplicate key " + Quote(key, '"'));
                    Whitespace();
                    NeedCharacter();
                    if (Peek != ':') Fail("expected ':'");
                    Position++;
                    map.Add(key, Value());
                    Whitespace();
                    if (Peek == '}')
                    {
                        Position++;
                        return map;
                    }
                    NeedCharacter();
                    if (Peek != ',') Fail("expected ',' or '}'");
                    Position++;
                    Whitespace();
                    if (Peek == '}') Fail("trailing comma");
                }
            }
            if (c == '[')
            {
                Position++;
                Whitespace();
                List<object?> list = [];
                if (Peek == ']')
                {
                    Position++;
                    return list;
                }
                while (true)
                {
                    list.Add(Value());
                    Whitespace();
                    if (Peek == ']')
                    {
                        Position++;
                        return list;
                    }
                    NeedCharacter();
                    if (Peek != ',') Fail("expected ',' or ']'");
                    Position++;
                    Whitespace();
                    if (Peek == ']') Fail("trailing comma");
                }
            }
            if (c == '-' || Digit(c))
            {
                int start = Position;
                if (c == '-') Position++;
                int digits = Position;
                while (Digit(Peek)) Position++;
                if (Position == digits) throw new ParseError(start, "invalid number");
                if (Position - digits >= 2 && Text[digits] == '0') throw new ParseError(digits, "leading zero");
                if (Peek == '.') Fail("fraction not allowed");
                if (Peek is 'e' or 'E') Fail("exponent not allowed");
                if (Position - digits >= 10) throw new ParseError(start, "number out of range");
                return int.Parse(Text[start..Position], CultureInfo.InvariantCulture);
            }
            if (Letter(c))
            {
                int start = Position;
                while (Letter(Peek)) Position++;
                string word = Text[start..Position];
                return word switch { "true" => true, "false" => false, "null" => null, _ => throw new ParseError(start, $"invalid literal '{word}'") };
            }
            Fail($"unexpected character '{c}'");
            return null;
        }
        public object? Whole()
        {
            object? value = Value();
            Whitespace();
            if (Position != Text.Length) Fail("trailing characters");
            return value;
        }
    }

    static object? Copy(object? value)
    {
        if (value is JsonObject map)
        {
            JsonObject result = new(StringComparer.Ordinal);
            foreach (var entry in map) result.Add(entry.Key, Copy(entry.Value));
            return result;
        }
        return value is List<object?> list ? list.Select(Copy).ToList() : value;
    }

    static string Compact(object? value) => value switch { null => "null", string text => Quote(text, '"'), bool b => b ? "true" : "false", int n => n.ToString(CultureInfo.InvariantCulture), JsonObject map => "{" + string.Join(",", map.Select(entry => Quote(entry.Key, '"') + ":" + Compact(entry.Value))) + "}", List<object?> list => "[" + string.Join(",", list.Select(Compact)) + "]", _ => throw new InvalidOperationException() };

    static string Pretty(object? value, string indent)
    {
        if (value is JsonObject { Count: > 0 } || value is List<object?> { Count: > 0 })
        {
            string child = indent + "  ";
            List<string> parts = [];
            if (value is JsonObject map) foreach (var entry in map) parts.Add(child + Quote(entry.Key, '"') + ": " + Pretty(entry.Value, child));
            else foreach (object? item in (List<object?>)value) parts.Add(child + Pretty(item, child));
            return (value is JsonObject ? "{" : "[") + "\n" + string.Join(",\n", parts) + "\n" + indent + (value is JsonObject ? "}" : "]");
        }
        return Compact(value);
    }

    static string TypeName(object? value) => value switch { null => "null", JsonObject => "object", List<object?> => "array", string => "string", int => "number", _ => "boolean" };

    record Selector(char Kind, string? Key, int? First, int? Last, bool Descendant);

    class PathReader(string text) : Parser(text)
    {
        string IdentifierName()
        {
            int start = Position;
            if (!Letter(Peek) && Peek != '_') throw new Problem("");
            Position++;
            while (Letter(Peek) || Digit(Peek) || Peek == '_') Position++;
            return Text[start..Position];
        }
        public List<Selector> Read(bool field)
        {
            if (Peek != (field ? '@' : '$')) throw new Problem("");
            Position++;
            List<Selector> selectors = [];
            while (Position < Text.Length)
            {
                bool descendant = false;
                if (Peek == '.')
                {
                    Position++;
                    if (Peek == '.')
                    {
                        if (field) throw new Problem("");
                        descendant = true;
                        Position++;
                    }
                    if (Peek == '*')
                    {
                        if (field) throw new Problem("");
                        Position++;
                        selectors.Add(new('A', null, null, null, descendant));
                        continue;
                    }
                    if (!(descendant && Peek == '['))
                    {
                        selectors.Add(new('K', IdentifierName(), null, null, descendant));
                        continue;
                    }
                }
                else if (Peek != '[') throw new Problem("");
                if (Peek != '[') throw new Problem("");
                Position++;
                if (Peek == '\'')
                {
                    string key = String('\'');
                    if (Peek != ']') throw new Problem("");
                    Position++;
                    selectors.Add(new('K', key, null, null, descendant));
                    continue;
                }
                int end = Text.IndexOf(']', Position);
                if (end < 0) throw new Problem("");
                string content = Text[Position..end];
                Position = end + 1;
                if (content == "*" && !field) selectors.Add(new('A', null, null, null, descendant));
                else if (IntegerNotation(content)) selectors.Add(new('I', null, int.Parse(content), null, descendant));
                else if (!field && content.Contains(':'))
                {
                    string[] parts = content.Split(':');
                    if (parts.Length != 2 || parts[0].Length > 0 && !IntegerNotation(parts[0]) || parts[1].Length > 0 && !IntegerNotation(parts[1])) throw new Problem("");
                    selectors.Add(new('S', null, parts[0].Length == 0 ? null : int.Parse(parts[0]), parts[1].Length == 0 ? null : int.Parse(parts[1]), descendant));
                }
                else throw new Problem("");
            }
            return selectors;
        }
    }

    static List<Selector> Path(string text, bool field)
    {
        try
        {
            return new PathReader(text).Read(field);
        }
        catch (Exception error) when (error is Problem or ParseError)
        {
            throw new Problem("ERROR bad " + (field ? "field" : "path"));
        }
    }

    static string Key(string text)
    {
        if (Matches(text, Identifier)) return text;
        try
        {
            Parser reader = new(text);
            if (reader.Peek != '\'') throw new Problem("");
            string key = reader.String('\'');
            if (reader.Position != text.Length) throw new Problem("");
            return key;
        }
        catch (Exception error) when (error is Problem or ParseError)
        {
            throw new Problem("ERROR bad key");
        }
    }

    record Step(object Key, int Position);

    record Match(object? Value, List<Step> Location);

    static Match Child(Match parent, object key, int position)
    {
        List<Step> location = [.. parent.Location, new(key, position)];
        return new(key is string name ? ((JsonObject)parent.Value!)[name] : ((List<object?>)parent.Value!)[(int)key], location);
    }

    static List<Match> Children(Match parent)
    {
        List<Match> result = [];
        if (parent.Value is JsonObject map)
        {
            int i = 0;
            foreach (string key in map.Keys) result.Add(Child(parent, key, i++));
        }
        else if (parent.Value is List<object?> list) for (int i = 0; i < list.Count; i++) result.Add(Child(parent, i, i));
        return result;
    }

    static void Preorder(Match match, List<Match> result)
    {
        result.Add(match);
        foreach (Match child in Children(match)) Preorder(child, result);
    }

    static List<Match> Select(Match match, Selector selector)
    {
        List<Match> result = [];
        if (selector.Kind == 'K' && match.Value is JsonObject map && map.ContainsKey(selector.Key!)) result.Add(Child(match, selector.Key!, map.Keys.ToList().IndexOf(selector.Key!)));
        else if (selector.Kind == 'A') result.AddRange(Children(match));
        else if (match.Value is List<object?> list && selector.Kind is 'I' or 'S')
        {
            int count = list.Count;
            if (selector.Kind == 'I')
            {
                int i = selector.First!.Value < 0 ? count + selector.First.Value : selector.First.Value;
                if (i >= 0 && i < count) result.Add(Child(match, i, i));
            }
            else
            {
                int first = selector.First ?? 0, last = selector.Last ?? count;
                if (first < 0) first += count;
                if (last < 0) last += count;
                first = Math.Clamp(first, 0, count);
                last = Math.Clamp(last, 0, count);
                for (int i = first; i < last; i++) result.Add(Child(match, i, i));
            }
        }
        return result;
    }

    static List<Match> Apply(List<Match> matches, Selector selector)
    {
        List<Match> result = [];
        foreach (Match match in matches)
        {
            List<Match> bases = [];
            if (selector.Descendant) Preorder(match, bases);
            else bases.Add(match);
            foreach (Match basis in bases) result.AddRange(Select(basis, selector));
        }
        return result;
    }

    static List<Match> Evaluate(IEnumerable<Selector> selectors)
    {
        List<Match> matches = [new(document, [])];
        foreach (Selector selector in selectors) matches = Apply(matches, selector);
        return matches;
    }

    static string Location(List<Step> steps)
    {
        StringBuilder output = new("$");
        foreach (Step step in steps) if (step.Key is string key) output.Append(Matches(key, Identifier) ? "." + key : "[" + Quote(key, '\'') + "]");
        else output.Append('[').Append(step.Key).Append(']');
        return output.ToString();
    }

    static object? At(object? root, IEnumerable<Step> steps)
    {
        object? value = root;
        foreach (Step step in steps) value = step.Key is string key ? ((JsonObject)value!)[key] : ((List<object?>)value!)[(int)step.Key];
        return value;
    }

    static object? Field(object? value, List<Selector> selectors)
    {
        foreach (Selector selector in selectors)
        {
            var selected = Select(new(value, []), selector);
            if (selected.Count == 0) return Missing;
            value = selected[0].Value;
        }
        return value;
    }

    static bool Equal(object? left, object? right)
    {
        if (left is JsonObject a && right is JsonObject b) return a.Count == b.Count && a.All(entry => b.ContainsKey(entry.Key) && Equal(entry.Value, b[entry.Key]));
        if (left is List<object?> x && right is List<object?> y) return x.Count == y.Count && x.Zip(y).All(pair => Equal(pair.First, pair.Second));
        return Equals(left, right);
    }

    static int Rank(object? value) => value switch { null => 0, int => 1, string => 2, _ => 3 };

    static int Compare(object? left, object? right)
    {
        int order = Rank(left).CompareTo(Rank(right));
        if (order != 0) return order;
        return Rank(left) switch { 1 => ((int)left!).CompareTo((int)right!), 2 => StringComparer.Ordinal.Compare((string)left!, (string)right!), _ => 0 };
    }

    static void Merge(JsonObject target, JsonObject source)
    {
        foreach (var entry in source) if (target.TryGetValue(entry.Key, out object? old) && old is JsonObject oldMap && entry.Value is JsonObject newMap) Merge(oldMap, newMap);
        else target[entry.Key] = Copy(entry.Value);
    }

    static int CompareLocations(Match left, Match right)
    {
        for (int i = 0; i < Math.Min(left.Location.Count, right.Location.Count); i++)
        {
            int order = left.Location[i].Position.CompareTo(right.Location[i].Position);
            if (order != 0) return order;
        }
        return left.Location.Count.CompareTo(right.Location.Count);
    }

    static List<Match> Targets(List<Match> matches)
    {
        Dictionary<string, Match> unique = new(StringComparer.Ordinal);
        foreach (Match match in matches) unique.TryAdd(Location(match.Location), match);
        return unique.Values.OrderByDescending(match => match, Comparer<Match>.Create(CompareLocations)).ToList();
    }

    static void Require(bool condition, string message)
    {
        if (!condition) throw new Problem(message);
    }

    static void RequireType(List<Match> matches, string type)
    {
        foreach (Match match in matches) Require(TypeName(match.Value) == type, "ERROR not an " + type + " at " + Location(match.Location));
    }

    static object? JsonValue(string text)
    {
        try
        {
            return new Parser(text).Whole();
        }
        catch (ParseError error)
        {
            throw new Problem($"PARSE ERROR col {error.Position + 1}: {error.Message}");
        }
    }

    static List<string> Execute(string line)
    {
        int space = line.IndexOf(' ');
        string command = space < 0 ? line : line[..space];
        string? argument = space < 0 ? null : line[(space + 1)..];
        Require(Commands.Contains(command), $"ERROR unknown command '{command}'");
        int limit = command is "SET" or "MERGE" ? 2 : command == "INSERT" ? 3 : command == "FILTER" ? 4 : int.MaxValue;
        string[] args = argument is null ? [] : argument.Split(' ', limit);
        bool shape = command switch { "SET" or "MERGE" or "RENAME" => args.Length == 2, "INSERT" => args.Length == 3, "FILTER" => args.Length >= 3 && (args[2] == "EXISTS" ? args.Length == 3 : args.Length == 4), "COMPACT" or "PRETTY" or "FLATTEN" => args.Length <= 1, "UNDO" => args.Length == 0, "SORT" => args.Length is >= 1 and <= 3 && (args.Length < 3 || args[1] != "DESC" && args[2] == "DESC"), _ => args.Length == 1 };
        Require(shape, "ERROR bad arguments");
        if (command == "UNDO")
        {
            Require(History.Count > 0, "ERROR nothing to undo");
            document = History[^1];
            History.RemoveAt(History.Count - 1);
            return [$"UNDO {History.Count}"];
        }
        var selectors = Path(args.Length == 0 ? "$" : args[0], false);
        List<Selector> fields = [];
        object? value = null;
        int index = 0;
        string? rename = null, op = null;
        if (command == "FILTER")
        {
            fields = Path(args[1], true);
            op = args[2];
            Require(op is "==" or "!=" or "<" or "<=" or ">" or ">=" or "EXISTS", "ERROR bad operator");
            if (op != "EXISTS") value = JsonValue(args[3]);
        }
        else if (command == "SORT") fields = Path(args.Length >= 2 && args[1] != "DESC" ? args[1] : "@", true);
        else if (command == "RENAME") rename = Key(args[1]);
        else if (command == "INSERT")
        {
            Require(IntegerNotation(args[1]), "ERROR bad index");
            index = int.Parse(args[1]);
            value = JsonValue(args[2]);
        }
        else if (command is "SET" or "MERGE") value = JsonValue(args[1]);
        if (command == "MERGE") Require(value is JsonObject, "ERROR merge value is not an object");
        if (command == "DELETE") Require(selectors.Count > 0, "ERROR cannot delete root");
        List<Match> matches = Evaluate(selectors);
        if (command is "FILTER" or "INSERT" or "SORT") RequireType(matches, "array");
        if (command is "KEYS" or "MERGE") RequireType(matches, "object");
        if (command == "LENGTH") foreach (Match match in matches) Require(match.Value is JsonObject or List<object?> or string, "ERROR no length at " + Location(match.Location));
        if (command == "INSERT") foreach (Match match in matches) Require(index >= -((List<object?>)match.Value!).Count - 1 && index <= ((List<object?>)match.Value!).Count, "ERROR index out of range at " + Location(match.Location));
        if (command == "RENAME") foreach (Match match in matches) Require(match.Location.Count > 0 && match.Location[^1].Key is string, "ERROR not a member at " + Location(match.Location));
        List<string> output = [];
        if (command is "SET" or "DELETE" or "INSERT" or "MERGE" or "SORT" or "RENAME")
        {
            if (command == "SET" && selectors.Count > 0)
            {
                Selector last = selectors[^1];
                if (last.Kind == 'K' && !last.Descendant)
                {
                    matches = [];
                    foreach (Match parent in Evaluate(selectors.Take(selectors.Count - 1))) if (parent.Value is JsonObject map)
                    {
                        int position = map.Keys.ToList().IndexOf(last.Key!);
                        matches.Add(new(null, [.. parent.Location, new Step(last.Key!, position < 0 ? map.Count : position)]));
                    }
                }
            }
            var targets = Targets(matches);
            object? changed = Copy(document);
            foreach (Match target in targets)
            {
                var place = target.Location;
                object? current = command == "SET" ? null : At(changed, place);
                if (command == "SET")
                {
                    if (place.Count == 0) changed = Copy(value);
                    else
                    {
                        object? parent = At(changed, place.Take(place.Count - 1));
                        if (place[^1].Key is string key) ((JsonObject)parent!)[key] = Copy(value);
                        else ((List<object?>)parent!)[(int)place[^1].Key] = Copy(value);
                    }
                }
                else if (command == "DELETE")
                {
                    object? parent = At(changed, place.Take(place.Count - 1));
                    if (place[^1].Key is string key) ((JsonObject)parent!).Remove(key);
                    else ((List<object?>)parent!).RemoveAt((int)place[^1].Key);
                }
                else if (command == "INSERT")
                {
                    var list = (List<object?>)current!;
                    list.Insert(index < 0 ? list.Count + 1 + index : index, Copy(value));
                }
                else if (command == "MERGE") Merge((JsonObject)current!, (JsonObject)value!);
                else if (command == "SORT")
                {
                    bool descending = args[^1] == "DESC";
                    var list = (List<object?>)current!;
                    var sorted = list.OrderBy(item => Field(item, fields), Comparer<object?>.Create((left, right) => (descending ? -1 : 1) * Compare(left, right))).ToList();
                    list.Clear();
                    list.AddRange(sorted);
                }
                else
                {
                    var parent = (JsonObject)At(changed, place.Take(place.Count - 1))!;
                    string old = (string)place[^1].Key;
                    Require(old == rename || !parent.ContainsKey(rename!), "ERROR key exists at " + Location(place));
                    var entries = parent.Select(entry => KeyValuePair.Create(entry.Key == old ? rename! : entry.Key, entry.Value)).ToList();
                    parent.Clear();
                    foreach (var entry in entries) parent.Add(entry.Key, entry.Value);
                }
            }
            History.Add(Copy(document));
            document = changed;
            return [$"{command} {targets.Count}"];
        }
        if (command == "COUNT") return [$"COUNT {matches.Count}"];
        if (command is "SUM" or "MIN" or "MAX" or "AVG")
        {
            long total = 0;
            int? minimum = null, maximum = null;
            int count = 0;
            foreach (Match match in matches) if (match.Value is int number)
            {
                total += number;
                count++;
                minimum = minimum is null ? number : Math.Min(minimum.Value, number);
                maximum = maximum is null ? number : Math.Max(maximum.Value, number);
            }
            string result = command == "SUM" ? total.ToString(CultureInfo.InvariantCulture) : command == "MIN" ? minimum?.ToString(CultureInfo.InvariantCulture) ?? "null" : command == "MAX" ? maximum?.ToString(CultureInfo.InvariantCulture) ?? "null" : "null";
            if (command == "AVG" && count > 0)
            {
                long q = (Math.Abs(total) * 200 + count) / (2L * count);
                result = (total < 0 && q > 0 ? "-" : "") + (q / 100).ToString(CultureInfo.InvariantCulture) + "." + (q % 100).ToString("D2", CultureInfo.InvariantCulture);
            }
            return [$"{command} {result}"];
        }
        if (command == "FILTER")
        {
            foreach (Match match in matches) foreach (Match child in Children(match))
            {
                object? f = Field(child.Value, fields);
                bool equality = f != Missing && Equal(f, value), pass;
                if (op == "EXISTS") pass = f != Missing;
                else if (op is "==" or "!=") pass = (op == "==") == equality;
                else
                {
                    bool comparable = f is int && value is int || f is string && value is string;
                    int order = comparable ? Compare(f, value) : 0;
                    pass = comparable && (op switch { "<" => order < 0, "<=" => order <= 0, ">" => order > 0, _ => order >= 0 });
                }
                if (pass) output.Add(Location(child.Location) + " = " + Compact(child.Value));
            }
        }
        else foreach (Match match in matches)
        {
            string place = Location(match.Location);
            object? item = match.Value;
            switch (command)
            {
                case "GET":
                    output.Add(place + " = " + Compact(item));
                    break;
                case "COMPACT":
                    output.Add(Compact(item));
                    break;
                case "PRETTY":
                    output.Add(Pretty(item, ""));
                    break;
                case "TYPE":
                    output.Add(place + " " + TypeName(item));
                    break;
                case "LENGTH":
                    output.Add(place + " " + (item is JsonObject map ? map.Count : item is List<object?> list ? list.Count : ((string)item!).Length));
                    break;
                    case "KEYS": output.Add(place + " " + Compact(((JsonObject)item!).Keys.Select(key => (object?)key).ToList()));
                    break;
                case "FLATTEN":
                    List<Match> descendants = [];
                    Preorder(match, descendants);
                    foreach (Match leaf in descendants) if (Children(leaf).Count == 0) output.Add(Location(leaf.Location) + " = " + Compact(leaf.Value));
                    break;
            }
        }
        return output.Count == 0 ? ["no match"] : output;
    }

    static (int Count, int Depth) Size(object? value)
    {
        int count = 1, depth = 1;
        foreach (Match child in Children(new(value, [])))
        {
            var size = Size(child.Value);
            count += size.Count;
            depth = Math.Max(depth, size.Depth + 1);
        }
        return (count, depth);
    }

    static void Load(List<string> lines)
    {
        string text = string.Join("\n", lines);
        try
        {
            object? value = new Parser(text).Whole();
            History.Add(Copy(document));
            document = value;
            var size = Size(value);
            Console.WriteLine($"LOADED nodes={size.Count} depth={size.Depth}");
        }
        catch (ParseError error)
        {
            int line = 1, column = 1;
            for (int i = 0; i < error.Position; i++) if (text[i] == '\n')
            {
                line++;
                column = 1;
            }
            else column++;
            Console.WriteLine($"PARSE ERROR line {line} col {column}: {error.Message}");
        }
    }

    static void Main()
    {
        List<string> body = [];
        string line;
        while ((line = Console.ReadLine()!) != "%%") body.Add(line);
        Load(body);
        while ((line = Console.ReadLine()!) != "END") if (line == "LOAD")
        {
            body = [];
            while ((line = Console.ReadLine()!) != "%%") body.Add(line);
            Load(body);
        }
        else try
        {
            Execute(line).ForEach(Console.WriteLine);
        }
        catch (Problem error)
        {
            Console.WriteLine(error.Message);
        }
    }
}
