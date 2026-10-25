using System;
using System.Collections.Generic;
using System.Linq;

static class Linter
{
    static readonly string[] Codes = ["SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED", "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"];
    static readonly HashSet<string> Errors = ["SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE"];
    static bool Move(Item item) => item.Kind is "GOTO" or "RESTATE";
    static bool Unknown(Rule rule, Script script) => rule.Pattern.Any(e => e[0] == '@' && !script.Groups.ContainsKey(e[1..]));
    public static List<Diagnostic> Check(Script script)
    {
        List<Diagnostic> found = new(script.Diagnostics);
        void Add(int line, string code, string message) => found.Add(new(line, code, message));
        HashSet<string> replacements = script.Pres.SelectMany(p => p.Replacement).ToHashSet(StringComparer.Ordinal);
        HashSet<string> targets = script.Items.Where(Move).Select(i => i.Arguments[0]).ToHashSet(StringComparer.Ordinal);
        HashSet<string> used = script.Rules.SelectMany(r => r.Pattern).Where(e => e[0] == '@').Select(e => e[1..]).ToHashSet(StringComparer.Ordinal);
        Dictionary<string, List<string>> graph = script.Keywords.ToDictionary(k => k.Word, k => k.Decomps.SelectMany(r => r.Items).Where(i => Move(i) && script.KeywordMap.ContainsKey(i.Arguments[0])).Select(i => i.Arguments[0]).ToList(), StringComparer.Ordinal);
        bool Reaches(string start, string goal)
        {
            HashSet<string> seen = new(StringComparer.Ordinal); Stack<string> pending = new(); pending.Push(start);
            while (pending.TryPop(out string? current)) { if (current == goal) return true; if (!seen.Add(current)) continue; foreach (string next in graph[current]) pending.Push(next); }
            return false;
        }
        foreach (Keyword key in script.Keywords)
        {
            if (key.Decomps.Count == 0) Add(key.Line, "KEY_NO_DECOMP", "keyword " + key.Word + " has no DECOMP");
            if (script.Pre.ContainsKey(key.Word) && !replacements.Contains(key.Word) && !targets.Contains(key.Word)) Add(key.Line, "KEY_UNREACHABLE", "keyword " + key.Word + " is replaced by PRE");
        }
        foreach (Group group in script.GroupList) if (!used.Contains(group.Name)) Add(group.Line, "SYNON_UNUSED", "group " + group.Name + " is never used");
        foreach (Substitution pre in script.Pres) foreach (string word in pre.Replacement) if (script.Pre.ContainsKey(word)) Add(pre.Line, "PRE_CHAIN", "replacement " + word + " is itself replaced by PRE");
        foreach (Keyword key in script.Keywords) foreach (List<Rule> rules in new[] { key.Memories, key.Decomps }) for (int index = 0; index < rules.Count; index++)
        {
            Rule rule = rules[index];
            foreach (string element in rule.Pattern) if (element[0] == '@' && !script.Groups.ContainsKey(element[1..])) Add(rule.Line, "SYNON_UNKNOWN", "unknown group " + element[1..]);
            if (rule.Items.Count == 0) Add(rule.Line, "RULE_NO_REASM", "rule has no reassembly");
            if (!Unknown(rule, script)) foreach (Rule earlier in rules.Take(index)) if (!Unknown(earlier, script) && Matcher.Covers(earlier.Pattern, rule.Pattern, script.Groups)) { Add(rule.Line, "RULE_SHADOWED", "pattern is shadowed by line " + earlier.Line); break; }
            int wildcards = rule.Pattern.Count(Matcher.Wildcard);
            foreach (Item item in rule.Items)
            {
                List<int> refs = [];
                if (item.Kind == "REASM") for (int p = 0; p + 3 <= item.Text.Length; p++) if (ScriptLoader.IsReference(item.Text.Substring(p, 3))) refs.Add(item.Text[p + 1] - '0');
                if (item.Kind == "RESTATE") refs.AddRange(item.Arguments.Skip(1).Where(ScriptLoader.IsReference).Select(a => a[1] - '0'));
                foreach (int n in refs) if (n == 0 || n > wildcards) Add(item.Line, "REF_UNBOUND", "reference (" + n + ") is not bound");
                if (!Move(item)) continue;
                string target = item.Arguments[0];
                if (!script.KeywordMap.ContainsKey(target)) Add(item.Line, "TARGET_UNDEFINED", "target " + target + " is not a keyword");
                else if (Reaches(target, key.Word)) Add(item.Line, "TARGET_CYCLE", "edge " + key.Word + " -> " + target + " is on a cycle");
            }
        }
        return found.OrderBy(d => d.Line).ThenBy(d => Array.IndexOf(Codes, d.Code)).ToList();
    }
    public static List<string> Lines(List<Diagnostic> diagnostics)
    {
        if (diagnostics.Count == 0) return ["OK"];
        List<string> result = diagnostics.Select(d => $"{d.Line} {d.Code} {d.Message}").ToList();
        int errors = diagnostics.Count(d => Errors.Contains(d.Code));
        result.Add($"TOTAL {diagnostics.Count} errors={errors} warnings={diagnostics.Count - errors}"); return result;
    }
}
