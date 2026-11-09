using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

sealed record Diagnostic(int Line, string Code, string Message);
sealed record Substitution(string Source, List<string> Replacement, int Line);
sealed record Group(string Name, HashSet<string> Members, int Line);
sealed record Item(string Kind, string Text, List<string> Arguments, int Line, int Index);
sealed record Rule(string Kind, List<string> Pattern, int Line, int Index)
{
    public List<Item> Items { get; } = [];
}
sealed record Keyword(string Word, int Rank, int Line, int Index)
{
    public List<Rule> Memories { get; } = [];
    public List<Rule> Decomps { get; } = [];
}
sealed class Script
{
    public string[] Lines = [];
    public Dictionary<string, List<string>> Texts = new(StringComparer.Ordinal);
    public HashSet<string> Quit = new(StringComparer.Ordinal), Stop = new(StringComparer.Ordinal), Persist = new(StringComparer.Ordinal);
    public int Capacity = 3;
    public List<Substitution> Pres = [], Posts = [];
    public Dictionary<string, List<string>> Pre = new(StringComparer.Ordinal), Post = new(StringComparer.Ordinal);
    public List<Group> GroupList = [];
    public Dictionary<string, HashSet<string>> Groups = new(StringComparer.Ordinal);
    public List<Keyword> Keywords = [];
    public Dictionary<string, Keyword> KeywordMap = new(StringComparer.Ordinal);
    public List<Rule> Rules = [];
    public List<Item> Items = [];
    public List<Diagnostic> Diagnostics = [];
}
static class ScriptLoader
{
    static readonly HashSet<string> Globals = ["INITIAL", "FINAL", "QUIT", "STOP", "DEFAULT", "QUESTION", "REPEAT", "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON"];
    static readonly HashSet<string> TextNames = ["INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT"];
    static readonly HashSet<string> ItemNames = ["REASM", "GOTO", "NEWKEY", "RESTATE"];
    public static bool IsWord(string text) => text.Length > 0 && text[0] != '\'' && text[^1] != '\'' && text.All(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '\'');
    public static bool IsReference(string text) => text.Length == 3 && text[0] == '(' && text[1] is >= '0' and <= '9' && text[2] == ')';
    static bool IsNumber(string text) => text.Length is >= 1 and <= 2 && text.All(c => c is >= '0' and <= '9');
    static bool IsElement(string text) => text is "*" or "#" || (text[0] == '@' ? IsWord(text[1..]) : IsWord(text));
    static bool Formed(string name, List<string> a) => name switch
    {
        "INITIAL" or "FINAL" or "DEFAULT" or "QUESTION" or "REPEAT" or "REASM" => a.Count >= 1,
        "QUIT" or "STOP" => a.Count >= 1 && a.All(IsWord),
        "MEMSIZE" => a.Count == 1 && IsNumber(a[0]) && int.Parse(a[0]) is >= 1 and <= 20,
        "PERSIST" => a.Count == 1 && a[0] is "cycles" or "memory",
        "PRE" or "SYNON" => a.Count >= 2 && a.All(IsWord),
        "POST" => a.Count >= 2 && IsWord(a[0]),
        "KEY" => a.Count == 2 && IsWord(a[0]) && IsNumber(a[1]),
        "DECOMP" or "MEMORY" => a.Count >= 1 && a.All(IsElement),
        "GOTO" => a.Count == 1 && IsWord(a[0]),
        "NEWKEY" => a.Count == 0,
        "RESTATE" => a.Count >= 2 && IsWord(a[0]) && a.Skip(1).All(x => IsWord(x) || IsReference(x)),
        _ => false
    };
    public static Script Load(string path)
    {
        Script script = new() { Lines = File.ReadAllLines(path) };
        foreach (string name in TextNames) script.Texts[name] = [];
        Dictionary<string, int> first = new(StringComparer.Ordinal);
        Keyword? keyword = null;
        Rule? rule = null;
        bool ignoring = false;
        for (int index = 0; index < script.Lines.Length; index++)
        {
            string line = script.Lines[index];
            if (line.Length == 0 || line[0] == '#') continue;
            int number = index + 1, space = line.IndexOf(' ');
            string name = space < 0 ? line : line[..space], text = space < 0 ? "" : line[(space + 1)..];
            List<string> a = Helpers.Words(text);
            bool isRule = name is "DECOMP" or "MEMORY", isItem = ItemNames.Contains(name);
            if (Globals.Contains(name) || name == "KEY") { keyword = null; rule = null; ignoring = false; }
            else if (isRule || isItem) { if (ignoring) continue; if (isRule) rule = null; }
            string definition = "";
            if (name == "MEMSIZE") definition = name;
            else if (a.Count > 0 && name is "KEY" or "SYNON" or "PRE" or "POST" or "PERSIST") definition = name + " " + a[0];
            string code = "", message = "";
            if (!Globals.Contains(name) && name != "KEY" && !isRule && !isItem) { code = "SYNTAX"; message = "unknown directive " + name; }
            else if (!Formed(name, a)) { code = "SYNTAX"; message = "bad arguments for " + name; }
            else if (isRule && keyword is null) { code = "ORPHAN"; message = name + " without KEY"; }
            else if (name == "REASM" && rule is null) { code = "ORPHAN"; message = "REASM without DECOMP or MEMORY"; }
            else if (isItem && name != "REASM" && (rule is null || rule.Kind == "MEMORY")) { code = "ORPHAN"; message = name + " without DECOMP"; }
            else if (definition.Length > 0 && first.TryGetValue(definition, out int original)) { code = "DUPLICATE"; message = definition + " first defined at line " + original; }
            if (code.Length > 0)
            {
                script.Diagnostics.Add(new(number, code, message));
                if (code == "DUPLICATE" && name == "KEY") ignoring = true;
                continue;
            }
            if (definition.Length > 0) first[definition] = number;
            if (TextNames.Contains(name)) script.Texts[name].Add(text);
            else if (name is "QUIT" or "STOP") (name == "QUIT" ? script.Quit : script.Stop).UnionWith(a);
            else if (name == "MEMSIZE") script.Capacity = int.Parse(a[0]);
            else if (name == "PERSIST") script.Persist.Add(a[0]);
            else if (name is "PRE" or "POST")
            {
                List<string> replacement = a.Skip(1).ToList();
                (name == "PRE" ? script.Pres : script.Posts).Add(new(a[0], replacement, number));
                (name == "PRE" ? script.Pre : script.Post)[a[0]] = replacement;
            }
            else if (name == "SYNON")
            {
                HashSet<string> members = new(a, StringComparer.Ordinal);
                script.GroupList.Add(new(a[0], members, number)); script.Groups[a[0]] = members;
            }
            else if (name == "KEY")
            {
                keyword = new(a[0], int.Parse(a[1]), number, script.Keywords.Count);
                script.Keywords.Add(keyword); script.KeywordMap[a[0]] = keyword;
            }
            else if (isRule)
            {
                rule = new(name, a, number, script.Rules.Count); script.Rules.Add(rule);
                (name == "MEMORY" ? keyword!.Memories : keyword!.Decomps).Add(rule);
            }
            else
            {
                Item item = new(name, text, a, number, script.Items.Count);
                script.Items.Add(item); rule!.Items.Add(item);
            }
        }
        return script;
    }
}
