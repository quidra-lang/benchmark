#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

public sealed record Statement(string Kind, int Line, string Target, string Value = "");

public sealed class Document
{
    public List<Statement> Statements { get; } = new();
    public List<Diagnostic> Diagnostics { get; } = new();
}

public sealed class IniParser
{
    private readonly string documentName;
    private readonly Document document = new();
    private readonly Dictionary<string, int> assigned = new(StringComparer.Ordinal);
    private string? section;
    private string? baseSection;

    private IniParser(string name) => documentName = name;

    public static bool IsName(string text) => Regex.IsMatch(text, @"\A[a-z][a-z0-9_]*\z");
    public static bool IsSection(string text) =>
        Regex.IsMatch(text, @"\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*\z");

    public static Document Parse(string name, IReadOnlyList<string> lines)
    {
        var parser = new IniParser(name);
        foreach (LogicalLine line in Lexer.Read(lines))
            parser.Interpret(line);
        return parser.document;
    }

    private void Report(int line, string code, string message) =>
        document.Diagnostics.Add(new Diagnostic(new Origin(documentName, line), code, message));

    private void Add(string kind, int line, string target, string value = "") =>
        document.Statements.Add(new Statement(kind, line, target, value));

    private static List<string> Trimmed(IEnumerable<string> segments)
    {
        List<string> result = segments.ToList();
        result[0] = result[0].TrimStart(' ');
        result[^1] = result[^1].TrimEnd(' ');
        return result;
    }

    private void Interpret(LogicalLine line)
    {
        if (line.Error is { } error)
        {
            Report(line.Number, error.Code, error.Message);
            return;
        }
        List<string> segments = Trimmed(line.Segments);
        string first = segments[0];
        if (segments.Count == 1 && first == "")
            return;
        if (first.StartsWith('['))
            Header(line.Number, segments);
        else if (first.StartsWith('@'))
            Directive(line.Number, segments);
        else
            Assignment(line.Number, segments);
    }

    private void BadHeader(int line, string message)
    {
        Report(line, "E_SECTION", message);
        section = null;
    }

    private void Header(int line, List<string> segments)
    {
        string text = segments[0];
        if (segments.Count != 1 || !text.EndsWith(']'))
        {
            BadHeader(line, "invalid section header");
            return;
        }
        string inside = text[1..^1];
        int colon = inside.IndexOf(':');
        string name = (colon < 0 ? inside : inside[..colon]).Trim(' ');
        string? parent = colon < 0 ? null : inside[(colon + 1)..].Trim(' ');
        bool relative = name.StartsWith('.') && IsSection(name[1..]);
        if ((parent != null && !IsSection(parent)) || (!relative && !IsSection(name)))
            BadHeader(line, "invalid section header");
        else if (relative && baseSection == null)
            BadHeader(line, "relative section without base");
        else
        {
            if (relative)
                section = baseSection + name;
            else
                section = baseSection = name;
            if (parent != null)
                Add("inherit", line, section!, parent);
        }
    }

    private void Directive(int line, List<string> segments)
    {
        string[] words = segments[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Count != 1 || words.Length != 2 ||
            (words[0] != "@include" && words[0] != "@unset") || !IsName(words[1]))
            Report(line, "E_SYNTAX", "invalid directive");
        else if (words[0] == "@include")
            Add("include", line, words[1]);
        else if (section == null)
            Report(line, "E_NO_SECTION", "no current section");
        else
            Add("unset", line, section + "." + words[1]);
    }

    private void Assignment(int line, List<string> segments)
    {
        bool hasEquals = segments.Where((_, index) => index % 2 == 0).Any(s => s.Contains('='));
        int equals = segments[0].IndexOf('=');
        if (!hasEquals)
        {
            Report(line, "E_SYNTAX", "invalid line");
            return;
        }
        if (equals < 0)
        {
            Report(line, "E_SYNTAX", "invalid key");
            return;
        }
        string key = segments[0][..equals].Trim(' ');
        bool append = key.EndsWith('+');
        if (append)
            key = key[..^1].TrimEnd(' ');
        if (!IsName(key))
        {
            Report(line, "E_SYNTAX", "invalid key");
            return;
        }
        segments[0] = segments[0][(equals + 1)..];
        List<string> parts = Trimmed(segments);
        string? value = parts.Count == 1 ? parts[0] :
            parts.Count == 3 && parts[0] == "" && parts[2] == "" ? parts[1] : null;
        if (value == null)
            Report(line, "E_SYNTAX", "invalid value");
        else if (section == null)
            Report(line, "E_NO_SECTION", "no current section");
        else
        {
            string fullKey = section + "." + key;
            if (!append)
            {
                if (assigned.TryGetValue(fullKey, out int previous))
                    Report(line, "W_DUPLICATE", $"{fullKey} already set at line {previous}");
                assigned[fullKey] = line;
            }
            Add(append ? "append" : "assign", line, fullKey, value);
        }
    }
}
