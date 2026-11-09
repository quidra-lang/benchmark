#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

public static class KeyNames
{
    public static string Section(string key) => key[..key.LastIndexOf('.')];
    public static string Name(string key) => key[(key.LastIndexOf('.') + 1)..];
    public static readonly IComparer<string> Order = Comparer<string>.Create((left, right) =>
    {
        int result = StringComparer.Ordinal.Compare(Section(left), Section(right));
        return result != 0 ? result : StringComparer.Ordinal.Compare(Name(left), Name(right));
    });
    public static IEnumerable<string> Sorted(IEnumerable<string> keys) => keys.OrderBy(k => k, Order);
}

public sealed class Spec
{
    public int Line { get; }
    public string Pattern { get; }
    public string Key { get; }
    public string[] SectionParts { get; }
    public bool Wildcard { get; }
    public string Kind { get; }
    public bool Required { get; private set; }
    public bool Secret { get; private set; }
    public bool Unique { get; private set; }
    public bool Fixed { get; private set; }
    public string? Default { get; private set; }
    public (string Lower, string Upper)? Range { get; private set; }
    public string[] Values { get; private set; } = Array.Empty<string>();
    public string Item { get; private set; } = "string";
    public string[] Aliases { get; private set; } = Array.Empty<string>();
    public string? When { get; private set; }
    public string? Le { get; private set; }

    public Spec(int line, string[] words)
    {
        Line = line;
        Pattern = words[0];
        Key = KeyNames.Name(Pattern);
        SectionParts = KeyNames.Section(Pattern).Split('.');
        Wildcard = SectionParts.Contains("*");
        Kind = words[1];
        foreach (string attribute in words.Skip(2))
        {
            int equals = attribute.IndexOf('=');
            string name = equals < 0 ? attribute : attribute[..equals];
            string value = equals < 0 ? "" : attribute[(equals + 1)..];
            switch (name)
            {
                case "required": Required = true; break;
                case "secret": Secret = true; break;
                case "unique": Unique = true; break;
                case "fixed": Fixed = true; break;
                case "default": Default = value; break;
                case "range":
                    int separator = value.IndexOf("..", StringComparison.Ordinal);
                    Range = (value[..separator], value[(separator + 2)..]);
                    break;
                case "values": Values = value.Split(','); break;
                case "item": Item = value; break;
                case "alias": Aliases = value.Split(','); break;
                case "when": When = value; break;
                case "le": Le = value; break;
            }
        }
    }

    public bool Matches(string section)
    {
        string[] parts = section.Split('.');
        if (parts.Length != SectionParts.Length)
            return false;
        for (int index = 0; index < parts.Length; index++)
            if (SectionParts[index] != "*" && SectionParts[index] != parts[index])
                return false;
        return true;
    }
}

public sealed class Schema
{
    public List<Spec> Specs { get; } = new();
    private readonly Dictionary<string, Spec> exact = new(StringComparer.Ordinal);

    public Schema(string path)
    {
        string[] lines = File.ReadAllLines(path);
        for (int index = 0; index < lines.Length; index++)
        {
            string line = lines[index];
            if (line.Trim(' ') == "" || line.StartsWith('#'))
                continue;
            var spec = new Spec(index + 1, line.Split(' '));
            Specs.Add(spec);
            if (!spec.Wildcard)
                exact.Add(spec.Pattern, spec);
        }
    }

    public Spec? SpecFor(string key)
    {
        if (exact.TryGetValue(key, out Spec? spec))
            return spec;
        string section = KeyNames.Section(key), name = KeyNames.Name(key);
        return Specs.FirstOrDefault(s => s.Wildcard && s.Key == name && s.Matches(section));
    }

    public IEnumerable<string> TargetKeys(Spec spec, IEnumerable<string> sections)
    {
        if (!spec.Wildcard)
        {
            yield return spec.Pattern;
            yield break;
        }
        foreach (string section in sections.OrderBy(s => s, StringComparer.Ordinal))
        {
            string key = section + "." + spec.Key;
            if (spec.Matches(section) && ReferenceEquals(SpecFor(key), spec))
                yield return key;
        }
    }
}
