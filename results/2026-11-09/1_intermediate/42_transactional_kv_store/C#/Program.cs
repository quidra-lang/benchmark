using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

abstract record Value
{
    public abstract string Kind { get; }
    public virtual bool Empty => false;
    public abstract Value Copy();
}
sealed record TextValue(string Text) : Value
{
    public override string Kind => "string";
    public override Value Copy() => this;
}
sealed record ListValue(List<string> Items) : Value
{
    public override string Kind => "list";
    public override bool Empty => Items.Count == 0;
    public override Value Copy() => new ListValue([.. Items]);
}
sealed record HashValue(Dictionary<string, string> Fields) : Value
{
    public override string Kind => "hash";
    public override bool Empty => Fields.Count == 0;
    public override Value Copy() => new HashValue(new(Fields, StringComparer.Ordinal));
}
sealed record SetValue(HashSet<string> Members) : Value
{
    public override string Kind => "set";
    public override bool Empty => Members.Count == 0;
    public override Value Copy() => new SetValue(new(Members, StringComparer.Ordinal));
}
sealed record SortedSetValue(Dictionary<string, int> Scores) : Value
{
    public override string Kind => "zset";
    public override bool Empty => Scores.Count == 0;
    public override Value Copy() => new SortedSetValue(new(Scores, StringComparer.Ordinal));
}
sealed record Entry(Value Value, int? Expiry);
sealed class CommandError(string message) : Exception(message);

static class Replies
{
    public static string Quote(string value) => "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    public static List<string> Status(string text) => [text];
    public static List<string> Integer(int value) => [$"(integer) {value}"];
    public static List<string> Text(string? value) => [value is null ? "(nil)" : Quote(value)];
    public static List<string> Array(IEnumerable<string?> source)
    {
        string?[] values = source.ToArray();
        if (values.Length == 0) return ["(empty array)"];
        int width = values.Length.ToString().Length;
        return values.Select((value, index) =>
            (index + 1).ToString().PadLeft(width) + ") " + (value is null ? "(nil)" : Quote(value))).ToList();
    }
}

enum PatternKind { Literal, Any, Star, Class }
sealed record PatternPart(PatternKind Kind, char Literal = '\0', HashSet<char>? Characters = null, bool Negated = false);
enum BoundKind { NegativeInfinity, Finite, PositiveInfinity }
readonly record struct Bound(BoundKind Kind, int Number = 0, bool Inclusive = true)
{
    public bool Accepts(int score, bool lower) => Kind switch
    {
        BoundKind.NegativeInfinity => lower,
        BoundKind.PositiveInfinity => !lower,
        _ => lower ? (Inclusive ? score >= Number : score > Number) : (Inclusive ? score <= Number : score < Number)
    };
}
enum Group { Text, List, Hash, Set, SortedSet, Key, Control }
readonly record struct CommandSpec(Group Group, int Minimum, int Maximum, int Parity);

static class Syntax
{
    public const string WrongType = "WRONGTYPE Operation against a key holding the wrong kind of value";
    public const string NotInteger = "ERR value is not an integer or out of range";
    public const string Overflow = "ERR increment or decrement would overflow";
    public const string BadSyntax = "ERR syntax error";
    public const string Positive = "ERR value is out of range, must be positive";
    public const string NoKey = "ERR no such key";

    public static int Number(string text, string error = NotInteger)
    {
        if (text == "0") return 0;
        int start = text.StartsWith('-') ? 1 : 0;
        int digits = text.Length - start;
        if (digits is < 1 or > 9 || text[start] is < '1' or > '9') throw new CommandError(error);
        int value = 0;
        for (int i = start; i < text.Length; i++)
        {
            if (text[i] is < '0' or > '9') throw new CommandError(error);
            value = value * 10 + text[i] - '0';
        }
        return start == 0 ? value : -value;
    }
    public static int Add(int value, int delta)
    {
        int result = value + delta;
        if (result is < -999999999 or > 999999999) throw new CommandError(Overflow);
        return result;
    }
    public static (int Start, int Count) Range(int length, int start, int stop)
    {
        if (start < 0) start += length;
        if (stop < 0) stop += length;
        start = Math.Max(0, start);
        stop = Math.Min(length - 1, stop);
        return start <= stop ? (start, stop - start + 1) : (0, 0);
    }
    public static List<string>? Split(string line)
    {
        var words = new List<string>();
        int position = 0;
        while (position < line.Length)
        {
            if (line[position] == ' ') { position++; continue; }
            if (line[position] != '"')
            {
                int start = position;
                while (position < line.Length && line[position] != ' ') position++;
                words.Add(line[start..position]);
                continue;
            }
            position++;
            var value = new StringBuilder();
            bool closed = false;
            while (position < line.Length)
            {
                char c = line[position++];
                if (c == '"') { closed = true; break; }
                if (c == '\\')
                {
                    if (position == line.Length || line[position] is not ('"' or '\\')) return null;
                    c = line[position++];
                }
                value.Append(c);
            }
            if (!closed || position < line.Length && line[position] != ' ') return null;
            words.Add(value.ToString());
        }
        return words;
    }
    public static List<PatternPart> Pattern(string text)
    {
        var parts = new List<PatternPart>();
        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];
            if (c == '\\')
            {
                if (++i == text.Length) throw new CommandError("ERR invalid pattern");
                parts.Add(new(PatternKind.Literal, text[i]));
            }
            else if (c == '[')
            {
                int end = text.IndexOf(']', i + 1);
                if (end < 0) throw new CommandError("ERR invalid pattern");
                int start = i + 1;
                bool negated = start < end && text[start] == '^';
                if (negated) start++;
                if (start == end) throw new CommandError("ERR invalid pattern");
                var characters = new HashSet<char>();
                for (int j = start; j < end;)
                {
                    if (j + 2 < end && text[j + 1] == '-')
                    {
                        int first = Math.Min(text[j], text[j + 2]), last = Math.Max(text[j], text[j + 2]);
                        for (int code = first; code <= last; code++) characters.Add((char)code);
                        j += 3;
                    }
                    else characters.Add(text[j++]);
                }
                parts.Add(new(PatternKind.Class, Characters: characters, Negated: negated));
                i = end;
            }
            else parts.Add(c switch
            {
                '*' => new(PatternKind.Star),
                '?' => new(PatternKind.Any),
                _ => new(PatternKind.Literal, c)
            });
        }
        return parts;
    }
    public static bool Matches(List<PatternPart> parts, string value)
    {
        var previous = new bool[value.Length + 1];
        previous[0] = true;
        foreach (var part in parts)
        {
            var current = new bool[previous.Length];
            if (part.Kind == PatternKind.Star)
            {
                current[0] = previous[0];
                for (int i = 1; i < current.Length; i++) current[i] = previous[i] || current[i - 1];
            }
            else
                for (int i = 0; i < value.Length; i++)
                {
                    bool accepts = part.Kind == PatternKind.Any || (part.Kind == PatternKind.Literal
                        ? part.Literal == value[i] : part.Characters!.Contains(value[i]) != part.Negated);
                    current[i + 1] = previous[i] && accepts;
                }
            previous = current;
        }
        return previous[^1];
    }
    public static Bound ScoreBound(string word)
    {
        if (word == "-inf") return new(BoundKind.NegativeInfinity);
        if (word == "+inf") return new(BoundKind.PositiveInfinity);
        bool inclusive = !word.StartsWith('(');
        return new(BoundKind.Finite, Number(inclusive ? word : word[1..], "ERR min or max is not a float"), inclusive);
    }

    public static readonly Dictionary<string, CommandSpec> Commands = BuildCommands();
    static Dictionary<string, CommandSpec> BuildCommands()
    {
        var result = new Dictionary<string, CommandSpec>(StringComparer.Ordinal);
        void Add(Group group, string names, int minimum, int maximum = -1, int parity = -1)
        {
            foreach (string name in names.Split(' ')) result.Add(name, new(group, minimum, maximum, parity));
        }
        Add(Group.Text, "SET", 2);
        Add(Group.Text, "GET INCR DECR STRLEN", 1, 1);
        Add(Group.Text, "MSET", 2, parity: 0);
        Add(Group.Text, "MGET", 1);
        Add(Group.Text, "INCRBY DECRBY APPEND", 2, 2);
        Add(Group.Text, "GETRANGE", 3, 3);
        Add(Group.List, "LPUSH RPUSH", 2);
        Add(Group.List, "LPOP RPOP", 1, 2);
        Add(Group.List, "LRANGE LSET LREM LTRIM", 3, 3);
        Add(Group.List, "LLEN", 1, 1);
        Add(Group.List, "LINDEX", 2, 2);
        Add(Group.List, "LINSERT", 4, 4);
        Add(Group.Hash, "HSET", 3, parity: 1);
        Add(Group.Hash, "HGET HEXISTS", 2, 2);
        Add(Group.Hash, "HDEL", 2);
        Add(Group.Hash, "HGETALL HLEN HKEYS HVALS", 1, 1);
        Add(Group.Hash, "HINCRBY", 3, 3);
        Add(Group.Set, "SADD SREM", 2);
        Add(Group.Set, "SISMEMBER", 2, 2);
        Add(Group.Set, "SMEMBERS SCARD", 1, 1);
        Add(Group.Set, "SINTER SUNION SDIFF", 1);
        Add(Group.Set, "SINTERSTORE SUNIONSTORE SDIFFSTORE", 2);
        Add(Group.SortedSet, "ZADD", 3, parity: 1);
        Add(Group.SortedSet, "ZSCORE ZRANK", 2, 2);
        Add(Group.SortedSet, "ZINCRBY", 3, 3);
        Add(Group.SortedSet, "ZREM", 2);
        Add(Group.SortedSet, "ZCARD", 1, 1);
        Add(Group.SortedSet, "ZRANGE ZRANGEBYSCORE", 3, 4);
        Add(Group.Key, "DEL EXISTS", 1);
        Add(Group.Key, "TYPE KEYS TTL PERSIST TICK", 1, 1);
        Add(Group.Key, "RENAME RENAMENX", 2, 2);
        Add(Group.Key, "EXPIRE", 2, 3);
        Add(Group.Key, "TIME DBSIZE FLUSH INFO", 0, 0);
        Add(Group.Control, "BEGIN COMMIT ROLLBACK", 0, 0);
        Add(Group.Control, "SNAPSHOT RESTORE", 1, 1);
        return result;
    }
}

sealed class Store
{
    Dictionary<string, Entry> database = new(StringComparer.Ordinal);
    readonly Stack<Dictionary<string, Entry>> transactions = new();
    readonly Dictionary<string, Dictionary<string, Entry>> snapshots = new(StringComparer.Ordinal);
    int time;

    static Dictionary<string, Entry> Copy(Dictionary<string, Entry> source) =>
        source.ToDictionary(pair => pair.Key, pair => new Entry(pair.Value.Value.Copy(), pair.Value.Expiry), StringComparer.Ordinal);
    T Read<T>(string key, T empty) where T : Value
    {
        if (!database.TryGetValue(key, out var entry)) return empty;
        if (entry.Value is not T value) throw new CommandError(Syntax.WrongType);
        return (T)value.Copy();
    }
    void Replace(string key, Value value, int? expiry = null)
    {
        if (value.Empty) database.Remove(key);
        else database[key] = new(value, expiry);
    }
    void Update(string key, Value value) => Replace(key, value, database.GetValueOrDefault(key)?.Expiry);
    int Purge()
    {
        string[] expired = database.Where(pair => pair.Value.Expiry is int expiry && expiry <= time).Select(pair => pair.Key).ToArray();
        foreach (string key in expired) database.Remove(key);
        return expired.Length;
    }
    static IEnumerable<string> Ordered(IEnumerable<string> values) => values.OrderBy(value => value, StringComparer.Ordinal);

    List<string> TextCommand(string command, string[] args)
    {
        string key = args[0];
        if (command == "SET")
        {
            var options = new HashSet<string>(StringComparer.Ordinal);
            string? secondsWord = null;
            for (int i = 2; i < args.Length; i++)
            {
                string option = args[i].ToUpperInvariant();
                if (option is not ("NX" or "XX" or "EX" or "KEEPTTL" or "GET") || !options.Add(option))
                    throw new CommandError(Syntax.BadSyntax);
                if (option == "EX")
                {
                    if (++i == args.Length) throw new CommandError(Syntax.BadSyntax);
                    secondsWord = args[i];
                }
            }
            if (options.Contains("NX") && options.Contains("XX") || options.Contains("EX") && options.Contains("KEEPTTL"))
                throw new CommandError(Syntax.BadSyntax);
            int? expiry = null;
            if (secondsWord is not null)
            {
                int seconds = Syntax.Number(secondsWord);
                if (seconds <= 0) throw new CommandError("ERR invalid expire time in 'set' command");
                expiry = time + seconds;
            }
            bool exists = database.TryGetValue(key, out var entry);
            string? old = null;
            if (options.Contains("GET"))
            {
                var value = Read(key, new TextValue(""));
                if (exists) old = value.Text;
            }
            if (options.Contains("KEEPTTL") && exists) expiry = entry!.Expiry;
            bool changed = !(options.Contains("NX") && exists) && !(options.Contains("XX") && !exists);
            if (changed) Replace(key, new TextValue(args[1]), expiry);
            return options.Contains("GET") ? Replies.Text(old) : changed ? Replies.Status("OK") : Replies.Text(null);
        }
        if (command == "MSET")
        {
            for (int i = 0; i < args.Length; i += 2) Replace(args[i], new TextValue(args[i + 1]));
            return Replies.Status("OK");
        }
        if (command == "MGET")
            return Replies.Array(args.Select(name => database.GetValueOrDefault(name)?.Value is TextValue text ? text.Text : null));
        if (command is "INCR" or "DECR" or "INCRBY" or "DECRBY")
        {
            int delta = args.Length == 2 ? Syntax.Number(args[1]) : 1;
            if (command is "DECR" or "DECRBY") delta = -delta;
            string text = Read(key, new TextValue("")).Text;
            int result = Syntax.Add(database.ContainsKey(key) ? Syntax.Number(text) : 0, delta);
            Update(key, new TextValue(result.ToString()));
            return Replies.Integer(result);
        }
        if (command == "GETRANGE")
        {
            int start = Syntax.Number(args[1]), stop = Syntax.Number(args[2]);
            string text = Read(key, new TextValue("")).Text;
            var range = Syntax.Range(text.Length, start, stop);
            return Replies.Text(text.Substring(range.Start, range.Count));
        }
        string current = Read(key, new TextValue("")).Text;
        if (command == "GET") return Replies.Text(database.ContainsKey(key) ? current : null);
        if (command == "STRLEN") return Replies.Integer(current.Length);
        current += args[1];
        Update(key, new TextValue(current));
        return Replies.Integer(current.Length);
    }

    List<string> ListCommand(string command, string[] args)
    {
        string key = args[0];
        if (command is "LPOP" or "RPOP")
        {
            bool counted = args.Length == 2;
            int count = counted ? Syntax.Number(args[1], Syntax.Positive) : 1;
            if (count < 0) throw new CommandError(Syntax.Positive);
            var value = Read(key, new ListValue([]));
            if (!database.ContainsKey(key)) return Replies.Text(null);
            var removed = new List<string>();
            count = Math.Min(count, value.Items.Count);
            for (int i = 0; i < count; i++)
            {
                int position = command == "LPOP" ? 0 : value.Items.Count - 1;
                removed.Add(value.Items[position]);
                value.Items.RemoveAt(position);
            }
            Update(key, value);
            return counted ? Replies.Array(removed) : Replies.Text(removed[0]);
        }
        if (command is "LRANGE" or "LTRIM")
        {
            int start = Syntax.Number(args[1]), stop = Syntax.Number(args[2]);
            var value = Read(key, new ListValue([]));
            var range = Syntax.Range(value.Items.Count, start, stop);
            var kept = value.Items.GetRange(range.Start, range.Count);
            if (command == "LRANGE") return Replies.Array(kept);
            Update(key, new ListValue(kept));
            return Replies.Status("OK");
        }
        if (command is "LINDEX" or "LSET")
        {
            int index = Syntax.Number(args[1]);
            var value = Read(key, new ListValue([]));
            if (index < 0) index += value.Items.Count;
            bool inside = index >= 0 && index < value.Items.Count;
            if (command == "LINDEX") return Replies.Text(inside ? value.Items[index] : null);
            if (!database.ContainsKey(key)) throw new CommandError(Syntax.NoKey);
            if (!inside) throw new CommandError("ERR index out of range");
            value.Items[index] = args[2];
            Update(key, value);
            return Replies.Status("OK");
        }
        if (command == "LREM")
        {
            int count = Syntax.Number(args[1]);
            var value = Read(key, new ListValue([]));
            if (count < 0) value.Items.Reverse();
            int limit = count == 0 ? value.Items.Count : Math.Abs(count), removed = 0;
            var kept = new List<string>();
            foreach (string element in value.Items)
                if (element == args[2] && removed < limit) removed++;
                else kept.Add(element);
            if (count < 0) kept.Reverse();
            Update(key, new ListValue(kept));
            return Replies.Integer(removed);
        }
        if (command == "LINSERT")
        {
            string where = args[1].ToUpperInvariant();
            if (where is not ("BEFORE" or "AFTER")) throw new CommandError(Syntax.BadSyntax);
            var value = Read(key, new ListValue([]));
            if (!database.ContainsKey(key)) return Replies.Integer(0);
            int pivot = value.Items.IndexOf(args[2]);
            if (pivot < 0) return Replies.Integer(-1);
            value.Items.Insert(pivot + (where == "AFTER" ? 1 : 0), args[3]);
            Update(key, value);
            return Replies.Integer(value.Items.Count);
        }
        var list = Read(key, new ListValue([]));
        if (command == "LLEN") return Replies.Integer(list.Items.Count);
        foreach (string element in args.Skip(1))
            if (command == "LPUSH") list.Items.Insert(0, element);
            else list.Items.Add(element);
        Update(key, list);
        return Replies.Integer(list.Items.Count);
    }

    List<string> HashCommand(string command, string[] args)
    {
        string key = args[0];
        if (command == "HINCRBY")
        {
            int delta = Syntax.Number(args[2]);
            var value = Read(key, new HashValue(new(StringComparer.Ordinal)));
            int old = value.Fields.TryGetValue(args[1], out string? text)
                ? Syntax.Number(text, "ERR hash value is not an integer") : 0;
            int result = Syntax.Add(old, delta);
            value.Fields[args[1]] = result.ToString();
            Update(key, value);
            return Replies.Integer(result);
        }
        var hash = Read(key, new HashValue(new(StringComparer.Ordinal)));
        if (command == "HSET")
        {
            int added = 0;
            for (int i = 1; i < args.Length; i += 2)
            {
                if (!hash.Fields.ContainsKey(args[i])) added++;
                hash.Fields[args[i]] = args[i + 1];
            }
            Update(key, hash);
            return Replies.Integer(added);
        }
        if (command == "HGET") return Replies.Text(hash.Fields.GetValueOrDefault(args[1]));
        if (command == "HDEL")
        {
            int removed = 0;
            foreach (string field in args.Skip(1)) if (hash.Fields.Remove(field)) removed++;
            Update(key, hash);
            return Replies.Integer(removed);
        }
        if (command == "HLEN") return Replies.Integer(hash.Fields.Count);
        if (command == "HEXISTS") return Replies.Integer(hash.Fields.ContainsKey(args[1]) ? 1 : 0);
        var output = new List<string>();
        foreach (string field in Ordered(hash.Fields.Keys))
        {
            if (command != "HVALS") output.Add(field);
            if (command != "HKEYS") output.Add(hash.Fields[field]);
        }
        return Replies.Array(output);
    }

    List<string> SetCommand(string command, string[] args)
    {
        bool storing = command.EndsWith("STORE", StringComparison.Ordinal);
        string operation = storing ? command[..^5] : command;
        if (operation is "SINTER" or "SUNION" or "SDIFF")
        {
            var sources = new List<HashSet<string>>();
            foreach (string key in args.Skip(storing ? 1 : 0))
                sources.Add(Read(key, new SetValue(new(StringComparer.Ordinal))).Members);
            var result = sources[0];
            foreach (var source in sources.Skip(1))
            {
                if (operation == "SINTER") result.IntersectWith(source);
                else if (operation == "SUNION") result.UnionWith(source);
                else result.ExceptWith(source);
            }
            if (storing)
            {
                Replace(args[0], new SetValue(result));
                return Replies.Integer(result.Count);
            }
            return Replies.Array(Ordered(result));
        }
        var set = Read(args[0], new SetValue(new(StringComparer.Ordinal)));
        if (command == "SCARD") return Replies.Integer(set.Members.Count);
        if (command == "SMEMBERS") return Replies.Array(Ordered(set.Members));
        if (command == "SISMEMBER") return Replies.Integer(set.Members.Contains(args[1]) ? 1 : 0);
        int changed = 0;
        foreach (string member in args.Skip(1))
            if (command == "SADD" ? set.Members.Add(member) : set.Members.Remove(member)) changed++;
        Update(args[0], set);
        return Replies.Integer(changed);
    }

    List<string> SortedSetCommand(string command, string[] args)
    {
        string key = args[0];
        if (command == "ZADD")
        {
            var scores = new List<int>();
            for (int i = 1; i < args.Length; i += 2) scores.Add(Syntax.Number(args[i]));
            var value = Read(key, new SortedSetValue(new(StringComparer.Ordinal)));
            int added = 0;
            for (int i = 0; i < scores.Count; i++)
            {
                string member = args[2 * i + 2];
                if (!value.Scores.ContainsKey(member)) added++;
                value.Scores[member] = scores[i];
            }
            Update(key, value);
            return Replies.Integer(added);
        }
        if (command == "ZINCRBY")
        {
            int delta = Syntax.Number(args[1]);
            var value = Read(key, new SortedSetValue(new(StringComparer.Ordinal)));
            int result = Syntax.Add(value.Scores.GetValueOrDefault(args[2]), delta);
            value.Scores[args[2]] = result;
            Update(key, value);
            return Replies.Text(result.ToString());
        }
        bool byIndex = command == "ZRANGE", byScore = command == "ZRANGEBYSCORE", withScores = args.Length == 4;
        int start = 0, stop = 0;
        Bound minimum = new(BoundKind.NegativeInfinity), maximum = new(BoundKind.PositiveInfinity);
        if (byIndex || byScore)
        {
            if (withScores && args[3].ToUpperInvariant() != "WITHSCORES") throw new CommandError(Syntax.BadSyntax);
            if (byIndex) { start = Syntax.Number(args[1]); stop = Syntax.Number(args[2]); }
            else { minimum = Syntax.ScoreBound(args[1]); maximum = Syntax.ScoreBound(args[2]); }
        }
        var members = Read(key, new SortedSetValue(new(StringComparer.Ordinal)));
        if (command == "ZSCORE")
            return Replies.Text(members.Scores.TryGetValue(args[1], out int score) ? score.ToString() : null);
        if (command == "ZREM")
        {
            int removed = 0;
            foreach (string member in args.Skip(1)) if (members.Scores.Remove(member)) removed++;
            Update(key, members);
            return Replies.Integer(removed);
        }
        if (command == "ZCARD") return Replies.Integer(members.Scores.Count);
        var ordered = members.Scores.OrderBy(pair => pair.Value).ThenBy(pair => pair.Key, StringComparer.Ordinal).ToList();
        if (command == "ZRANK")
        {
            int rank = ordered.FindIndex(pair => pair.Key == args[1]);
            return rank < 0 ? Replies.Text(null) : Replies.Integer(rank);
        }
        if (byIndex)
        {
            var range = Syntax.Range(ordered.Count, start, stop);
            ordered = ordered.GetRange(range.Start, range.Count);
        }
        var output = new List<string>();
        foreach (var pair in ordered)
        {
            if (byScore && (!minimum.Accepts(pair.Value, true) || !maximum.Accepts(pair.Value, false))) continue;
            output.Add(pair.Key);
            if (withScores) output.Add(pair.Value.ToString());
        }
        return Replies.Array(output);
    }

    List<string> KeyCommand(string command, string[] args)
    {
        if (command is "DEL" or "EXISTS")
        {
            int count = 0;
            foreach (string name in args)
                if (command == "DEL" ? database.Remove(name) : database.ContainsKey(name)) count++;
            return Replies.Integer(count);
        }
        if (command == "KEYS")
        {
            var pattern = Syntax.Pattern(args[0]);
            return Replies.Array(Ordered(database.Keys.Where(name => Syntax.Matches(pattern, name))));
        }
        if (command == "EXPIRE")
        {
            string condition = args.Length == 3 ? args[2].ToUpperInvariant() : "";
            if (args.Length == 3 && condition is not ("NX" or "XX" or "GT" or "LT"))
                throw new CommandError("ERR Unsupported option " + args[2]);
            int seconds = Syntax.Number(args[1]);
            if (!database.TryGetValue(args[0], out var entry)) return Replies.Integer(0);
            int? old = entry.Expiry;
            int expiry = time + seconds;
            bool rejected = condition switch
            {
                "NX" => old is not null,
                "XX" => old is null,
                "GT" => old is null || expiry <= old.Value,
                "LT" => old is not null && expiry >= old.Value,
                _ => false
            };
            if (rejected) return Replies.Integer(0);
            if (seconds <= 0) database.Remove(args[0]);
            else database[args[0]] = entry with { Expiry = expiry };
            return Replies.Integer(1);
        }
        if (command == "TICK")
        {
            int ticks = Syntax.Number(args[0]);
            if (ticks <= 0) throw new CommandError(Syntax.Positive);
            time += ticks;
            return Replies.Integer(Purge());
        }
        if (command == "TIME") return Replies.Integer(time);
        if (command == "DBSIZE") return Replies.Integer(database.Count);
        if (command == "FLUSH") { database.Clear(); return Replies.Status("OK"); }
        if (command == "INFO")
        {
            int Count(string kind) => database.Values.Count(entry => entry.Value.Kind == kind);
            return Replies.Status($"keys={database.Count},expires={database.Values.Count(entry => entry.Expiry is not null)}" +
                $",string={Count("string")},list={Count("list")},hash={Count("hash")},set={Count("set")},zset={Count("zset")}" +
                $",time={time},depth={transactions.Count},snapshots={snapshots.Count}");
        }
        string key = args[0];
        database.TryGetValue(key, out var current);
        if (command == "TYPE") return Replies.Status(current?.Value.Kind ?? "none");
        if (command == "TTL") return Replies.Integer(current is null ? -2 : current.Expiry is int deadline ? deadline - time : -1);
        if (command == "PERSIST")
        {
            if (current?.Expiry is null) return Replies.Integer(0);
            database[key] = current with { Expiry = null };
            return Replies.Integer(1);
        }
        if (current is null) throw new CommandError(Syntax.NoKey);
        if (command == "RENAMENX" && database.ContainsKey(args[1])) return Replies.Integer(0);
        if (key != args[1]) { database[args[1]] = current; database.Remove(key); }
        return command == "RENAME" ? Replies.Status("OK") : Replies.Integer(1);
    }

    List<string> ControlCommand(string command, string[] args)
    {
        if (command == "BEGIN") { transactions.Push(Copy(database)); return Replies.Status("OK"); }
        if (command is "COMMIT" or "ROLLBACK")
        {
            if (transactions.Count == 0) throw new CommandError("ERR no transaction");
            var saved = transactions.Pop();
            if (command == "ROLLBACK") { database = saved; Purge(); }
            return Replies.Status("OK");
        }
        if (command == "SNAPSHOT") { snapshots[args[0]] = Copy(database); return Replies.Status("OK"); }
        if (!snapshots.TryGetValue(args[0], out var snapshot)) throw new CommandError("ERR no such snapshot");
        database = Copy(snapshot);
        Purge();
        return Replies.Status("OK");
    }

    public List<string> Execute(string line)
    {
        var words = Syntax.Split(line);
        if (words is null) return Replies.Status("Invalid argument(s)");
        string command = words[0].ToUpperInvariant();
        if (!Syntax.Commands.TryGetValue(command, out var spec)) throw new CommandError($"ERR unknown command '{words[0]}'");
        string[] args = words.Skip(1).ToArray();
        if (args.Length < spec.Minimum || spec.Maximum >= 0 && args.Length > spec.Maximum ||
            spec.Parity >= 0 && args.Length % 2 != spec.Parity)
            throw new CommandError($"ERR wrong number of arguments for '{command.ToLowerInvariant()}' command");
        return spec.Group switch
        {
            Group.Text => TextCommand(command, args),
            Group.List => ListCommand(command, args),
            Group.Hash => HashCommand(command, args),
            Group.Set => SetCommand(command, args),
            Group.SortedSet => SortedSetCommand(command, args),
            Group.Key => KeyCommand(command, args),
            _ => ControlCommand(command, args)
        };
    }
}

static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        var store = new Store();
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine()!;
            try { foreach (string output in store.Execute(line)) Console.WriteLine(output); }
            catch (CommandError error) { Console.WriteLine("(error) " + error.Message); }
        }
    }
}
