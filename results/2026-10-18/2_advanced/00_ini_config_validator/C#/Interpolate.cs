#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

public sealed class Expander
{
    private readonly IReadOnlyDictionary<string, string> values;
    private readonly IReadOnlyDictionary<string, Origin> origins;
    private readonly List<string> inProgress = new();
    private readonly HashSet<string> cycleKeys = new(StringComparer.Ordinal);
    public Dictionary<string, string?> Results { get; } = new(StringComparer.Ordinal);
    public List<Diagnostic> Diagnostics { get; } = new();

    public Expander(IReadOnlyDictionary<string, string> values, IReadOnlyDictionary<string, Origin> origins)
    {
        this.values = values;
        this.origins = origins;
    }

    private void Report(Origin origin, string code, string message) =>
        Diagnostics.Add(new Diagnostic(origin, code, message));

    public string? Expand(string key)
    {
        if (Results.TryGetValue(key, out string? result))
            return result;
        inProgress.Add(key);
        result = Evaluate(key);
        inProgress.RemoveAt(inProgress.Count - 1);
        Results[key] = result;
        return result;
    }

    private string? Evaluate(string key)
    {
        string value = values[key];
        Origin origin = origins[key];
        var result = new StringBuilder();
        int position = 0;
        while (position < value.Length)
        {
            char c = value[position];
            if (c != '$' || position + 1 == value.Length || value[position + 1] != '{')
            {
                result.Append(c == Lexer.LiteralDollar ? '$' : c);
                position++;
                continue;
            }
            int close = value.IndexOf('}', position + 2);
            if (close < 0 || !IniParser.IsSection(value[(position + 2)..close]))
            {
                Report(origin, "E_BAD_REF", $"{key}: invalid reference");
                return null;
            }
            string reference = value[(position + 2)..close];
            string target = reference.Contains('.') ? reference : KeyNames.Section(key) + "." + reference;
            if (!values.ContainsKey(target))
            {
                Report(origin, "E_UNDEFINED", $"{key}: undefined reference {target}");
                return null;
            }
            string? expanded;
            int cycleStart = inProgress.IndexOf(target);
            if (cycleStart >= 0)
            {
                string[] path = inProgress.Skip(cycleStart).Append(target).ToArray();
                Report(origins[target], "E_CYCLE", "interpolation cycle " + string.Join(" -> ", path));
                cycleKeys.UnionWith(path);
                expanded = null;
            }
            else
                expanded = Expand(target);
            if (expanded == null)
            {
                if (!cycleKeys.Contains(key))
                    Report(origin, "E_DEPENDENCY", $"{key}: depends on failed key {target}");
                return null;
            }
            result.Append(expanded);
            position = close + 1;
        }
        return result.ToString();
    }
}
