#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

public sealed record Definition(string Value, Origin Origin, int Number, IReadOnlyList<Origin> History);

public sealed class CheckError : Exception
{
    public string Code { get; }
    public CheckError(string code, string message) : base(message) => Code = code;
}

public static class Types
{
    private static Match Match(string text, string pattern) => Regex.Match(text, @"\A(?:" + pattern + @")\z");

    public static object? Parse(string kind, string text, IReadOnlyList<string> values)
    {
        switch (kind)
        {
            case "string": return text;
            case "enum": return values.FirstOrDefault(v => v.Equals(text, StringComparison.OrdinalIgnoreCase));
            case "bool":
                return text.ToLowerInvariant() switch
                {
                    "true" or "yes" or "on" or "1" => true,
                    "false" or "no" or "off" or "0" => false,
                    _ => null
                };
            case "int": return Integer(text);
            case "size": return Size(text);
            case "duration": return Duration(text);
            case "host": return Host(text);
            case "path": return PathValue(text);
            case "url": return Url(text);
            case "date": return Date(text);
            default: throw new ArgumentException("Unknown scalar type", nameof(kind));
        }
    }

    private static long? Integer(string text)
    {
        Match match = Match(text, @"([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*))");
        if (!match.Success)
            return null;
        long value;
        if (match.Groups[2].Success)
            value = Convert.ToInt64(match.Groups[2].Value, 16);
        else
        {
            string digits = match.Groups[3].Value.Replace("_", "");
            if (digits.Length > 12)
                return null;
            value = long.Parse(digits, CultureInfo.InvariantCulture);
        }
        return match.Groups[1].Value == "-" ? -value : value;
    }

    private static long? Size(string text)
    {
        Match match = Match(text, @"([0-9]{1,6})(?:\.([0-9]{1,3}))?([A-Za-z]*)");
        if (!match.Success)
            return null;
        long factor = match.Groups[3].Value.ToLowerInvariant() switch
        {
            "" or "b" => 1, "kb" => 1024, "mb" => 1048576, "gb" => 1073741824, _ => 0
        };
        if (factor == 0)
            return null;
        long result = long.Parse(match.Groups[1].Value) * factor;
        if (match.Groups[2].Success)
        {
            string fraction = match.Groups[2].Value;
            long numerator = long.Parse(fraction) * factor;
            long divisor = new long[] { 1, 10, 100, 1000 }[fraction.Length];
            if (numerator % divisor != 0)
                return null;
            result += numerator / divisor;
        }
        return result;
    }

    private static long? Duration(string text)
    {
        if (Match(text, "[0-9]{1,6}").Success)
            return long.Parse(text);
        Match match = Match(text, @"(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?");
        if (text == "" || !match.Success)
            return null;
        long Part(int index) => match.Groups[index].Success ? long.Parse(match.Groups[index].Value) : 0;
        return Part(1) * 3600 + Part(2) * 60 + Part(3);
    }

    private static string? Host(string text)
    {
        string[] parts = text.Split('.');
        if (text.All(c => c is >= '0' and <= '9' || c == '.'))
        {
            if (parts.Length != 4 || parts.Any(part => !Match(part, "[0-9]{1,3}").Success ||
                (part.Length > 1 && part[0] == '0') || int.Parse(part) > 255))
                return null;
            return text;
        }
        if (text.Length > 253 || parts.Any(part =>
            !Match(part, "[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?").Success))
            return null;
        return text.ToLowerInvariant();
    }

    private static string? PathValue(string text)
    {
        if (text == "" || text.IndexOfAny(new[] { ' ', '\n', '\t' }) >= 0)
            return null;
        bool absolute = text.StartsWith('/');
        var parts = new List<string>();
        foreach (string part in text.Split('/'))
        {
            if (part is "" or ".")
                continue;
            if (part != "..")
                parts.Add(part);
            else if (parts.Count > 0 && parts[^1] != "..")
                parts.RemoveAt(parts.Count - 1);
            else if (absolute)
                return null;
            else
                parts.Add(part);
        }
        string joined = string.Join('/', parts);
        return absolute ? "/" + joined : parts.Count == 0 ? "." : joined;
    }

    private static string? Url(string text)
    {
        int separator = text.IndexOf("://", StringComparison.Ordinal);
        if (separator < 0 || !Match(text[..separator], "[A-Za-z][A-Za-z0-9+.-]*").Success)
            return null;
        string scheme = text[..separator].ToLowerInvariant();
        string rest = text[(separator + 3)..];
        if (rest.Contains('?') || rest.Contains('#'))
            return null;
        int slash = rest.IndexOf('/');
        string authority = slash < 0 ? rest : rest[..slash];
        string path = slash < 0 ? "" : rest[(slash + 1)..];
        int colon = authority.IndexOf(':');
        string host = colon < 0 ? authority : authority[..colon];
        string? hostValue = Host(host), pathValue = PathValue("/" + path);
        if (hostValue == null || pathValue == null)
            return null;
        string result = scheme + "://" + hostValue;
        if (colon >= 0)
        {
            string port = authority[(colon + 1)..];
            if (!Match(port, "[1-9][0-9]{0,4}").Success || int.Parse(port) > 65535)
                return null;
            int defaultPort = scheme == "http" ? 80 : scheme == "https" ? 443 : -1;
            if (int.Parse(port) != defaultPort)
                result += ":" + port;
        }
        return result + pathValue;
    }

    private static string? Date(string text)
    {
        if (!Match(text, "[0-9]{4}-[0-9]{2}-[0-9]{2}").Success)
            return null;
        int year = int.Parse(text[..4]), month = int.Parse(text[5..7]), day = int.Parse(text[8..]);
        if (year < 1 || month < 1 || month > 12)
            return null;
        int days = new[] { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }[month - 1];
        if (month == 2 && (year % 4 == 0 && year % 100 != 0 || year % 400 == 0))
            days = 29;
        return day >= 1 && day <= days ? text : null;
    }

    public static int Compare(object left, object right) => left is string text
        ? StringComparer.Ordinal.Compare(text, (string)right) : ((long)left).CompareTo((long)right);

    public static CheckError Invalid(string key, string kind, Spec spec, string text, bool item = false)
    {
        string display = (item ? "item " : "") + (spec.Secret ? Emitter.Mask : Emitter.StringNotation(text));
        return kind == "enum"
            ? new CheckError("E_ENUM", $"{key}: {display} is not one of {string.Join(',', spec.Values)}")
            : new CheckError("E_TYPE", $"{key}: {display} is not a valid {kind}");
    }

    private static object? Bound(string kind, string text) => text == "" ? null :
        kind is "string" or "list" ? long.Parse(text) : Parse(kind, text, Array.Empty<string>());

    public static void CheckRange(string key, Spec spec, object value)
    {
        if (spec.Range is not { } range)
            return;
        object? lower = Bound(spec.Kind, range.Lower), upper = Bound(spec.Kind, range.Upper);
        object measure = value;
        string display;
        if (spec.Kind == "string")
        {
            measure = (long)((string)value).Length;
            display = $"length {measure}";
        }
        else if (spec.Kind == "list")
        {
            measure = (long)((List<object>)value).Count;
            display = $"count {measure}";
        }
        else
            display = spec.Secret ? Emitter.Mask : Emitter.ValueNotation(spec.Kind, spec.Item, value);
        if ((lower != null && Compare(measure, lower) < 0) || (upper != null && Compare(measure, upper) > 0))
            throw new CheckError("E_RANGE", $"{key}: {display} is out of range {lower}..{upper}");
    }
}

public sealed class DocumentLibrary
{
    private readonly Dictionary<string, Document?> documents = new(StringComparer.Ordinal);
    public Document? Find(string name)
    {
        if (!documents.TryGetValue(name, out Document? document))
        {
            string path = Path.Combine("input", "conf", name + ".ini");
            document = File.Exists(path) ? IniParser.Parse(name, File.ReadAllLines(path)) : null;
            documents[name] = document;
        }
        return document;
    }
}

public sealed class Profile
{
    public string Name { get; }
    private readonly string root;
    private readonly int manifestLine;
    private readonly string[] overrides;
    private readonly Dictionary<string, Definition> configuration = new(StringComparer.Ordinal);
    private readonly Dictionary<string, (string Parent, Origin Origin)> parents = new(StringComparer.Ordinal);
    private readonly HashSet<Diagnostic> reported = new();
    private int definitionNumber;
    public Dictionary<string, OutputKey> Outputs { get; } = new(StringComparer.Ordinal);
    public List<(int Depth, string Text)> Tree { get; } = new();
    public List<Diagnostic> Diagnostics { get; private set; } = new();
    public List<(string Key, IReadOnlyList<Origin> History)> Overridden { get; } = new();
    public int Errors { get; private set; }
    public int Warnings { get; private set; }
    public int DocumentKeys { get; private set; }
    public int ManifestKeys { get; private set; }
    public int DefaultKeys { get; private set; }
    public int Dropped { get; private set; }

    public Profile(int number, string line)
    {
        string[] words = line.Split(' ');
        Name = words[0];
        root = words[1];
        manifestLine = number;
        overrides = words.Skip(2).ToArray();
    }

    private void Report(Origin origin, string code, string message) =>
        reported.Add(new Diagnostic(origin, code, message));

    private void Define(string key, string value, Origin origin)
    {
        var history = configuration.TryGetValue(key, out Definition? previous)
            ? previous.History.ToList() : new List<Origin>();
        if (history.Count == 0 || history[^1] != origin)
            history.Add(origin);
        configuration[key] = new Definition(value, origin, ++definitionNumber, history);
    }

    public void Process(Schema schema, DocumentLibrary library, IReadOnlyList<Profile> earlier)
    {
        Apply(library, root, new List<string> { root });
        foreach (string entry in overrides)
        {
            int equals = entry.IndexOf('=');
            Define(entry[..equals], entry[(equals + 1)..], new Origin("manifest", manifestLine));
        }
        Inherit();
        ResolveAliases(schema);
        var sections = configuration.Keys.Select(KeyNames.Section).ToHashSet(StringComparer.Ordinal);
        foreach (Spec spec in schema.Specs.Where(s => s.Default != null))
            foreach (string key in schema.TargetKeys(spec, sections))
                if (!configuration.ContainsKey(key))
                    Define(key, spec.Default!, new Origin("schema", spec.Line));
        var configured = configuration.Keys.ToHashSet(StringComparer.Ordinal);
        var expander = new Expander(configuration.ToDictionary(p => p.Key, p => p.Value.Value),
            configuration.ToDictionary(p => p.Key, p => p.Value.Origin));
        foreach (string key in KeyNames.Sorted(configured))
            expander.Expand(key);
        reported.UnionWith(expander.Diagnostics);
        CheckTypes(schema, expander.Results);
        CheckOrder();
        CheckRequired(schema, sections, configured);
        CheckFixed(earlier);
        Summarize(configured.Count);
    }

    private void Apply(DocumentLibrary library, string name, List<string> chain)
    {
        Document document = library.Find(name)!;
        Tree.Add((chain.Count - 1, name));
        reported.UnionWith(document.Diagnostics);
        foreach (Statement statement in document.Statements)
        {
            var origin = new Origin(name, statement.Line);
            string key = statement.Target;
            switch (statement.Kind)
            {
                case "assign": Define(key, statement.Value, origin); break;
                case "append":
                    string value = statement.Value;
                    if (configuration.TryGetValue(key, out Definition? current) && current.Value != "")
                        value = current.Value + "," + value;
                    Define(key, value, origin);
                    break;
                case "unset":
                    if (!configuration.Remove(key))
                        Report(origin, "W_UNSET", $"{key} is not set");
                    break;
                case "inherit": parents[key] = (statement.Value, origin); break;
                case "include":
                    int start = chain.IndexOf(key);
                    if (start >= 0)
                    {
                        string path = string.Join(" -> ", chain.Skip(start).Append(key));
                        Report(origin, "E_INCLUDE_CYCLE", "include cycle " + path);
                        Tree.Add((chain.Count, key + " (cycle)"));
                    }
                    else if (library.Find(key) == null)
                    {
                        Report(origin, "E_INCLUDE_MISSING", "missing document " + key);
                        Tree.Add((chain.Count, key + " (missing)"));
                    }
                    else
                        Apply(library, key, chain.Append(key).ToList());
                    break;
            }
        }
    }

    private void Inherit()
    {
        var own = configuration.GroupBy(p => KeyNames.Section(p.Key))
            .ToDictionary(g => g.Key, g => g.Select(p => (Name: KeyNames.Name(p.Key), p.Value)).ToList());
        foreach (var declaration in parents)
        {
            string section = declaration.Key, parent = declaration.Value.Parent;
            Origin origin = declaration.Value.Origin;
            var chain = new List<string> { section };
            while (parents.TryGetValue(chain[^1], out var next) && !chain.Contains(next.Parent))
                chain.Add(next.Parent);
            if (parents.TryGetValue(chain[^1], out var last))
            {
                string path = string.Join(" -> ", chain.Append(last.Parent));
                Report(origin, "E_INHERIT_CYCLE", "inheritance cycle " + path);
                continue;
            }
            if (!parents.ContainsKey(parent) && !own.ContainsKey(parent))
                Report(origin, "W_PARENT_EMPTY", $"section {section} inherits from empty section {parent}");
            foreach (string ancestor in chain.Skip(1))
                if (own.TryGetValue(ancestor, out var keys))
                    foreach (var item in keys)
                        configuration.TryAdd(section + "." + item.Name, item.Value);
        }
    }

    private void ResolveAliases(Schema schema)
    {
        foreach (Spec spec in schema.Specs)
        {
            string[] aliases = spec.Aliases.Where(configuration.ContainsKey).ToArray();
            if (aliases.Length == 0)
                continue;
            string[] candidates = new[] { spec.Pattern }.Concat(aliases).Where(configuration.ContainsKey).ToArray();
            string winner = candidates[0];
            foreach (string candidate in candidates.Skip(1))
                if (configuration[candidate].Number > configuration[winner].Number)
                    winner = candidate;
            Definition chosen = configuration[winner];
            foreach (string candidate in candidates)
            {
                Origin origin = configuration[candidate].Origin;
                if (candidate != spec.Pattern)
                    Report(origin, "W_DEPRECATED", $"{candidate} is deprecated, use {spec.Pattern}");
                if (candidate != winner)
                    Report(origin, "W_SHADOWED", $"{candidate} is superseded by {winner} at {chosen.Origin}");
            }
            configuration[spec.Pattern] = chosen;
            foreach (string alias in aliases)
                configuration.Remove(alias);
        }
    }

    private object Normalize(string key, Spec spec, string text, Origin origin)
    {
        object value;
        if (spec.Kind != "list")
            value = Types.Parse(spec.Kind, text, spec.Values) ?? throw Types.Invalid(key, spec.Kind, spec, text);
        else
        {
            var items = new List<object>();
            if (text.Trim(' ') != "")
            {
                string[] raw = text.Split(',').Select(item => item.Trim(' ')).ToArray();
                if (raw.Contains(""))
                    Report(origin, "W_EMPTY_ITEM", $"{key}: empty list item ignored");
                foreach (string item in raw.Where(item => item != ""))
                    items.Add(Types.Parse(spec.Item, item, spec.Values) ?? throw Types.Invalid(key, spec.Item, spec, item, true));
                if (spec.Unique)
                {
                    var seen = new HashSet<string>(StringComparer.Ordinal);
                    List<object> unique = items.Where(item => seen.Add(Emitter.ValueNotation(spec.Item, "string", item))).ToList();
                    if (unique.Count < items.Count)
                        Report(origin, "W_DUPLICATE_ITEM", $"{key}: duplicate items removed");
                    items = unique;
                }
            }
            value = items;
        }
        Types.CheckRange(key, spec, value);
        return value;
    }

    private void CheckTypes(Schema schema, IReadOnlyDictionary<string, string?> results)
    {
        foreach (string key in KeyNames.Sorted(results.Keys))
        {
            string? text = results[key];
            if (text == null)
                continue;
            Definition definition = configuration[key];
            Spec? spec = schema.SpecFor(key);
            try
            {
                if (spec == null)
                    Report(definition.Origin, "W_UNKNOWN", $"{key} is not in the schema");
                object value = spec == null ? text : Normalize(key, spec, text, definition.Origin);
                Outputs[key] = new OutputKey(definition, spec, value);
            }
            catch (CheckError error)
            {
                Report(definition.Origin, error.Code, error.Message);
            }
        }
    }

    private void CheckOrder()
    {
        var remove = new List<string>();
        foreach (string key in KeyNames.Sorted(Outputs.Keys))
        {
            OutputKey output = Outputs[key];
            if (output.Spec?.Le is not { } le)
                continue;
            string limitKey = KeyNames.Section(key) + "." + le;
            if (Outputs.TryGetValue(limitKey, out OutputKey? limit) && output.Value is long number &&
                limit.Value is long bound && number > bound)
            {
                Report(output.Definition.Origin, "E_ORDER", $"{key}: {Emitter.Shown(output)} is greater than {limitKey} ({Emitter.Shown(limit)})");
                remove.Add(key);
            }
        }
        foreach (string key in remove)
            Outputs.Remove(key);
    }

    private void CheckRequired(Schema schema, HashSet<string> sections, HashSet<string> configured)
    {
        foreach (Spec spec in schema.Specs.Where(s => s.Required))
            foreach (string key in schema.TargetKeys(spec, sections))
            {
                if (configured.Contains(key))
                    continue;
                var origin = new Origin(root, 0);
                if (spec.When == null)
                    Report(origin, "E_REQUIRED", $"{key} is required");
                else
                {
                    string condition = KeyNames.Section(key) + "." + spec.When;
                    if (Outputs.TryGetValue(condition, out OutputKey? output) && output.Value is true)
                        Report(origin, "E_REQUIRED", $"{key} is required when {condition} is true");
                }
            }
    }

    private void CheckFixed(IReadOnlyList<Profile> earlier)
    {
        foreach (string key in KeyNames.Sorted(Outputs.Keys).ToArray())
        {
            OutputKey output = Outputs[key];
            if (output.Spec?.Fixed != true)
                continue;
            Profile? reference = earlier.FirstOrDefault(profile => profile.Outputs.ContainsKey(key));
            if (reference != null && reference.Outputs[key].Notation != output.Notation)
            {
                Report(output.Definition.Origin, "E_FIXED", $"{key}: value differs from profile {reference.Name}");
                Outputs.Remove(key);
            }
        }
    }

    private void Summarize(int configuredCount)
    {
        Diagnostics = reported.OrderBy(d => d.Origin.Document, StringComparer.Ordinal)
            .ThenBy(d => d.Origin.Line).ThenBy(d => d.Code, StringComparer.Ordinal)
            .ThenBy(d => d.Message, StringComparer.Ordinal).ToList();
        Errors = Diagnostics.Count(d => d.Code.StartsWith("E_", StringComparison.Ordinal));
        Warnings = Diagnostics.Count - Errors;
        foreach (string key in KeyNames.Sorted(Outputs.Keys))
        {
            Definition definition = Outputs[key].Definition;
            if (definition.History.Count >= 2)
                Overridden.Add((key, definition.History));
            if (definition.Origin.Document == "manifest") ManifestKeys++;
            else if (definition.Origin.Document == "schema") DefaultKeys++;
            else DocumentKeys++;
        }
        Dropped = configuredCount - Outputs.Count;
    }
}

public sealed record DiffEntry(char Sign, string Key, OutputKey? Before, OutputKey? After);

public sealed class ProfileDiff
{
    public string First { get; }
    public string Second { get; }
    public int Added { get; private set; }
    public int Removed { get; private set; }
    public int Changed { get; private set; }
    public List<DiffEntry> Entries { get; } = new();

    public ProfileDiff(Profile first, Profile second)
    {
        First = first.Name;
        Second = second.Name;
        foreach (string key in KeyNames.Sorted(first.Outputs.Keys.Union(second.Outputs.Keys)))
        {
            first.Outputs.TryGetValue(key, out OutputKey? before);
            second.Outputs.TryGetValue(key, out OutputKey? after);
            if (before == null)
            {
                Added++;
                Entries.Add(new DiffEntry('+', key, before, after));
            }
            else if (after == null)
            {
                Removed++;
                Entries.Add(new DiffEntry('-', key, before, after));
            }
            else if (before.Notation != after.Notation)
            {
                Changed++;
                Entries.Add(new DiffEntry('~', key, before, after));
            }
        }
    }
}

public static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var schema = new Schema(Path.Combine("input", "schema.txt"));
        var library = new DocumentLibrary();
        var profiles = new List<Profile>();
        string[] lines = File.ReadAllLines(Path.Combine("input", "manifest.txt"));
        for (int index = 0; index < lines.Length; index++)
        {
            var profile = new Profile(index + 1, lines[index]);
            profile.Process(schema, library, profiles);
            profiles.Add(profile);
        }
        var diffs = new List<ProfileDiff>();
        for (int index = 1; index < profiles.Count; index++)
            diffs.Add(new ProfileDiff(profiles[index - 1], profiles[index]));
        Emitter.WriteOutputs("output", profiles, diffs);
    }
}
