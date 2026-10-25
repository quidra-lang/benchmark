using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

static class Helpers
{
    public static List<string> Words(string text) => text.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToList();
    public static List<string> Grouped(List<string> values, int size) => values.Chunk(size).Select(x => string.Join(" ", x)).ToList();
}
sealed class Session
{
    public string Name = "";
    public int Turns, Stored, Recalled;
    public int[] Sources = new int[5];
    public List<List<string>>? Previous;
    public List<string> History = [];
    public List<string>? LastTrace;
    public bool Trace;
    public Dictionary<string, int> Topics = new(StringComparer.Ordinal), Words = new(StringComparer.Ordinal);
    public List<int> Unrecognized = [];
    public State? Undo;
    public Session Copy()
    {
        Session copy = (Session)MemberwiseClone();
        copy.Sources = (int[])Sources.Clone(); copy.Previous = Previous?.Select(x => new List<string>(x)).ToList();
        copy.History = new(History); copy.LastTrace = LastTrace is null ? null : new(LastTrace);
        copy.Topics = new(Topics, StringComparer.Ordinal); copy.Words = new(Words, StringComparer.Ordinal); copy.Unrecognized = new(Unrecognized);
        return copy;
    }
}
sealed class State
{
    public int[] Positions, Hits, ItemUses, KeywordUses, KeywordReplies;
    public Dictionary<string, int> Lists = new(StringComparer.Ordinal) { ["DEFAULT"] = 0, ["QUESTION"] = 0, ["REPEAT"] = 0 };
    public Memory Memory;
    public Session Session = new();
    public State(Script script)
    {
        Positions = new int[script.Rules.Count]; Hits = new int[script.Rules.Count]; ItemUses = new int[script.Items.Count];
        KeywordUses = new int[script.Keywords.Count]; KeywordReplies = new int[script.Keywords.Count]; Memory = new(script.Capacity);
    }
    public State Copy(bool snapshot = false)
    {
        State copy = (State)MemberwiseClone();
        copy.Positions = (int[])Positions.Clone(); copy.Hits = (int[])Hits.Clone(); copy.ItemUses = (int[])ItemUses.Clone();
        copy.KeywordUses = (int[])KeywordUses.Clone(); copy.KeywordReplies = (int[])KeywordReplies.Clone();
        copy.Lists = new(Lists, StringComparer.Ordinal); copy.Memory = Memory.Copy(); copy.Session = Session.Copy();
        if (snapshot) copy.Session.Undo = null;
        return copy;
    }
}
sealed class Chatbot
{
    static readonly string[] Sources = ["keyword", "memory", "question", "default", "repeat"];
    readonly Script script;
    State state;
    readonly List<string> transcript = [];
    int totalTurns;
    readonly int[] totals = new int[5];
    public Chatbot(Script script) { this.script = script; state = new(script); }
    static List<List<string>> Normalize(string text)
    {
        List<List<string>> clauses = [];
        foreach (string part in text.ToLowerInvariant().Split([',', '.', '?', '!', ';']))
        {
            string cleaned = new(part.Select(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '\'' ? c : ' ').ToArray());
            List<string> words = Helpers.Words(cleaned).Select(w => w.Trim('\'')).Where(w => w.Length > 0).ToList();
            if (words.Count > 0) clauses.Add(words);
        }
        return clauses;
    }
    List<List<string>> Prepared(string text) => Normalize(text).Select(c => Responder.Reflect(c, script.Pre)).ToList();
    bool Quit(string text) { List<string> words = Normalize(text).SelectMany(c => c).ToList(); return words.Count == 1 && script.Quit.Contains(words[0]); }
    static void Increment(Dictionary<string, int> counts, string word) => counts[word] = counts.GetValueOrDefault(word) + 1;
    string Prefix => state.Session.Name + " " + state.Session.Turns;
    void ResetCycles() { Array.Clear(state.Positions); foreach (string name in new[] { "DEFAULT", "QUESTION", "REPEAT" }) state.Lists[name] = 0; }
    string TakeText(string name) { int position = state.Lists[name]; state.Lists[name] = (position + 1) % script.Texts[name].Count; return script.Texts[name][position]; }
    (int Number, Item Item) TakeItem(Rule rule)
    {
        int position = state.Positions[rule.Index]; Item item = rule.Items[position];
        state.ItemUses[item.Index]++; state.Positions[rule.Index] = (position + 1) % rule.Items.Count; return (position + 1, item);
    }
    (int Number, List<string> Words)? Select(List<List<string>> clauses)
    {
        for (int index = 0; index < clauses.Count; index++) if (clauses[index].Any(script.KeywordMap.ContainsKey)) return (index + 1, clauses[index]);
        return null;
    }
    List<Keyword> KeywordList(List<string> words) => words.Distinct(StringComparer.Ordinal).Where(script.KeywordMap.ContainsKey).Select(w => script.KeywordMap[w]).OrderByDescending(k => k.Rank).ToList();
    (int Number, Rule Rule, List<List<string>> Bindings)? FindRule(List<Rule> rules, List<string> words)
    {
        for (int index = 0; index < rules.Count; index++) { var bindings = Matcher.Match(rules[index].Pattern, words, script.Groups); if (bindings is not null) return (index + 1, rules[index], bindings); }
        return null;
    }
    static IEnumerable<(string Kind, int Number, Rule Rule)> Entries(Keyword key)
    {
        for (int i = 0; i < key.Memories.Count; i++) yield return ("memory", i + 1, key.Memories[i]);
        for (int i = 0; i < key.Decomps.Count; i++) yield return ("decomp", i + 1, key.Decomps[i]);
    }
    string? KeywordReply(List<List<string>> clauses, List<string> trace)
    {
        var selected = Select(clauses);
        if (selected is null) { trace.Add("CLAUSE none"); return null; }
        List<string> original = selected.Value.Words;
        trace.Add($"CLAUSE {selected.Value.Number} {string.Join(" ", original)}");
        List<Keyword> keys = KeywordList(original); trace.Add("KEYS " + string.Join(" ", keys.Select(k => k.Word)));
        Keyword first = keys[0]; var memory = FindRule(first.Memories, original);
        if (memory is not null)
        {
            var found = memory.Value; trace.Add($"MEMORY {first.Word} {found.Number}"); state.Hits[found.Rule.Index]++;
            if (found.Rule.Items.Count > 0)
            {
                Item item = TakeItem(found.Rule).Item;
                if (state.Memory.Store(Prefix, first.Word, Responder.Build(item.Text, found.Bindings, script.Post))) state.Session.Stored++;
            }
        }
        HashSet<string> entered = new(StringComparer.Ordinal);
        foreach (Keyword initial in keys)
        {
            if (entered.Contains(initial.Word)) continue;
            trace.Add("ENTER " + initial.Word); Keyword key = initial; List<string> current = original;
            while (true)
            {
                entered.Add(key.Word); state.KeywordUses[key.Index]++;
                var found = FindRule(key.Decomps, current);
                if (found is null) { trace.Add("NOMATCH " + key.Word); break; }
                var match = found.Value; state.Hits[match.Rule.Index]++;
                if (match.Rule.Items.Count == 0) { trace.Add($"DECOMP {key.Word} {match.Number} 0"); break; }
                var taken = TakeItem(match.Rule); Item item = taken.Item;
                trace.Add($"DECOMP {key.Word} {match.Number} {taken.Number}");
                if (item.Kind == "REASM") { state.KeywordReplies[key.Index]++; Increment(state.Session.Topics, key.Word); return Responder.Build(item.Text, match.Bindings, script.Post); }
                if (item.Kind == "NEWKEY") break;
                string target = item.Arguments[0];
                if (!script.KeywordMap.TryGetValue(target, out Keyword? next) || entered.Contains(target)) { trace.Add("BLOCKED " + target); break; }
                if (item.Kind == "RESTATE") { current = Responder.Restate(item.Arguments.Skip(1), match.Bindings); trace.Add("RESTATE " + target + (current.Count == 0 ? "" : " " + string.Join(" ", current))); }
                else trace.Add("GOTO " + target);
                key = next;
            }
        }
        return null;
    }
    (string Reply, List<string> Trace) Decide(string text)
    {
        List<List<string>> clauses = Normalize(text); List<string> trace = [];
        string? reply; int source;
        bool same = state.Session.Previous is { } previous && clauses.Count == previous.Count && clauses.Zip(previous).All(p => p.First.SequenceEqual(p.Second));
        if (script.Texts["REPEAT"].Count > 0 && clauses.Count > 0 && same) { trace.Add("REPEAT"); reply = TakeText("REPEAT"); source = 4; }
        else
        {
            reply = KeywordReply(clauses.Select(c => Responder.Reflect(c, script.Pre)).ToList(), trace);
            if (reply is not null) source = 0;
            else if (state.Memory.Texts.Count > 0) { reply = state.Memory.Recall(Prefix); state.Session.Recalled++; source = 1; }
            else if (text.EndsWith('?') && script.Texts["QUESTION"].Count > 0) { reply = TakeText("QUESTION"); source = 2; }
            else { reply = TakeText("DEFAULT"); source = 3; }
        }
        trace.Add("REPLY " + Sources[source]); state.Session.Previous = clauses; state.Session.Sources[source]++;
        if (source is 2 or 3) state.Session.Unrecognized.Add(state.Session.Turns);
        return (reply, trace);
    }
    static string SourceLine(int turns, int[] counts) => "turns=" + turns + " " + string.Join(" ", Sources.Select((s, i) => s + "=" + counts[i]));
    static string Ranked(Dictionary<string, int> counts)
    {
        var values = counts.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).Take(5).Select(p => p.Key + " " + p.Value).ToList();
        return values.Count == 0 ? "none" : string.Join(", ", values);
    }
    List<string> Command(string line)
    {
        int space = line.IndexOf(' '); string name = space < 0 ? line : line[..space], text = space < 0 ? "" : line[(space + 1)..]; List<string> args = Helpers.Words(text);
        HashSet<string> noArgs = [":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo"];
        HashSet<string> textArgs = [":prepare", ":reflect", ":say", ":explain"];
        HashSet<string> single = [":groups", ":find", ":script", ":cycles", ":coverage"];
        HashSet<string> keyArgs = [":script", ":cycles", ":coverage", ":test"];
        if (!noArgs.Contains(name) && !textArgs.Contains(name) && !single.Contains(name) && name is not ":trace" and not ":test") return ["unknown command " + name];
        if (noArgs.Contains(name) && args.Count != 0 || textArgs.Contains(name) && text.Length == 0 || single.Contains(name) && args.Count != 1 || name == ":trace" && (args.Count != 1 || args[0] is not "on" and not "off") || name == ":test" && args.Count < 2) return ["bad arguments"];
        if (keyArgs.Contains(name) && !script.KeywordMap.ContainsKey(args[0])) return ["unknown keyword " + args[0]];
        List<string> output = [];
        switch (name)
        {
            case ":prepare":
                var clauses = Prepared(text);
                output.AddRange(clauses.Select((c, i) => $"clause {i + 1}: {string.Join(" ", c)}"));
                if (clauses.Count == 0) output.Add("no words");
                var selected = Select(clauses);
                if (selected is null) output.Add("selected none");
                else { output.Add("selected " + selected.Value.Number); output.Add("keys " + string.Join(" ", KeywordList(selected.Value.Words).Select(k => k.Word + "/" + k.Rank))); }
                break;
            case ":test": case ":cycles": case ":coverage":
                List<string> values = name == ":test" ? Prepared(text[(text.IndexOf(' ') + 1)..]).SelectMany(c => c).ToList() : [];
                foreach (var entry in Entries(script.KeywordMap[args[0]]))
                {
                    Rule rule = entry.Rule; string result;
                    if (name == ":test")
                    {
                        var bindings = Matcher.Match(rule.Pattern, values, script.Groups);
                        result = bindings is null ? "no match" : bindings.Count == 0 ? "match" : string.Join(" ", bindings.Select(b => "[" + string.Join(" ", b) + "]"));
                    }
                    else if (name == ":cycles") result = rule.Items.Count == 0 ? "empty" : $"next {state.Positions[rule.Index] + 1}/{rule.Items.Count}";
                    else result = $"hits {state.Hits[rule.Index]} entries " + (rule.Items.Count == 0 ? "-" : string.Join(" ", rule.Items.Select(i => state.ItemUses[i.Index])));
                    output.Add($"{entry.Kind} {entry.Number}: {result}");
                }
                if (output.Count == 0) output.Add("no rules");
                break;
            case ":reflect":
                output.AddRange(Prepared(text).Select(c => string.Join(" ", Responder.Reflect(c, script.Post)))); if (output.Count == 0) output.Add("no words"); break;
            case ":keys":
                output = Helpers.Grouped(script.Keywords.OrderByDescending(k => k.Rank).ThenBy(k => k.Word, StringComparer.Ordinal).Select(k => k.Word + "/" + k.Rank).ToList(), 8); break;
            case ":groups":
                var names = script.GroupList.Where(g => g.Members.Contains(args[0])).Select(g => g.Name).OrderBy(x => x, StringComparer.Ordinal).ToList(); output.Add(names.Count == 0 ? "none" : string.Join(" ", names)); break;
            case ":find":
                string w = args[0];
                if (script.KeywordMap.TryGetValue(w, out Keyword? key)) output.Add("keyword rank " + key.Rank);
                foreach (var pair in new[] { ("pre", script.Pres), ("post", script.Posts) }) foreach (Substitution sub in pair.Item2) if (sub.Source == w || sub.Replacement.Contains(w)) output.Add($"{pair.Item1} {sub.Line}: {sub.Source} -> {string.Join(" ", sub.Replacement)}");
                foreach (Group group in script.GroupList) if (group.Members.Contains(w)) output.Add($"group {group.Name} line {group.Line}");
                foreach (Keyword keyword in script.Keywords) foreach (var entry in Entries(keyword)) if (entry.Rule.Pattern.Contains(w)) output.Add($"pattern {keyword.Word} {entry.Kind} {entry.Number}");
                if (script.Stop.Contains(w)) output.Add("stop word"); if (script.Quit.Contains(w)) output.Add("quit word"); if (output.Count == 0) output.Add("not found"); break;
            case ":script":
                Keyword keywordScript = script.KeywordMap[args[0]]; List<int> numbers = [keywordScript.Line];
                foreach (var entry in Entries(keywordScript)) { numbers.Add(entry.Rule.Line); numbers.AddRange(entry.Rule.Items.Select(i => i.Line)); }
                output.AddRange(numbers.Order().Select(n => n + " " + script.Lines[n - 1])); break;
            case ":why": output = state.Session.LastTrace is null ? ["no reply yet"] : new(state.Session.LastTrace); break;
            case ":trace": state.Session.Trace = args[0] == "on"; output.Add("trace " + args[0]); break;
            case ":history": output = state.Session.History.Count == 0 ? ["no turns yet"] : state.Session.History.TakeLast(5).ToList(); break;
            case ":memory":
                output.Add($"memory {state.Memory.Texts.Count}/{state.Memory.Capacity}"); output.AddRange(state.Memory.Texts.Select((t, i) => $"{i + 1}: {t}")); break;
            case ":forget": output.Add("forgot " + state.Memory.Texts.Count); state.Memory.Clear(Prefix); break;
            case ":reset": ResetCycles(); output.Add("cycles reset"); break;
            case ":unused":
                List<string> unused = script.Items.Where(i => state.ItemUses[i.Index] == 0).OrderBy(i => i.Line).Select(i => i.Line.ToString()).ToList(); output.Add("unused " + unused.Count); output.AddRange(Helpers.Grouped(unused, 12)); break;
            case ":stats": output.Add(SourceLine(state.Session.Turns, state.Session.Sources)); break;
            case ":say": case ":explain":
                if (Quit(text)) return ["would quit"];
                State saved = state.Copy(); var decision = Decide(text); state = saved; output = name == ":say" ? [decision.Reply] : decision.Trace; break;
            case ":undo":
                if (state.Session.Undo is null) output.Add("nothing to undo");
                else { state = state.Session.Undo.Copy(); output.Add("undone turn " + (state.Session.Turns + 1)); }
                break;
        }
        return output;
    }
    void Notes()
    {
        Session s = state.Session; transcript.Add("NOTES " + s.Name); transcript.Add("  " + SourceLine(s.Turns, s.Sources));
        transcript.Add("  topics: " + Ranked(s.Topics)); transcript.Add("  words: " + Ranked(s.Words));
        transcript.Add($"  memory: stored={s.Stored} recalled={s.Recalled} pending={state.Memory.Texts.Count}");
        transcript.Add("  unrecognized: " + (s.Unrecognized.Count == 0 ? "none" : string.Join(" ", s.Unrecognized)));
        totalTurns += s.Turns; for (int i = 0; i < totals.Length; i++) totals[i] += s.Sources[i];
    }
    public void Run(string[] lines)
    {
        int sessions = 0;
        foreach (string line in lines)
        {
            if (line.StartsWith("SESSION ", StringComparison.Ordinal))
            {
                if (sessions > 0) { Notes(); transcript.Add(""); }
                string name = line[8..];
                if (sessions > 0) { if (!script.Persist.Contains("cycles")) ResetCycles(); if (!script.Persist.Contains("memory")) state.Memory.Clear(name + " 0"); }
                state.Session = new() { Name = name }; sessions++; transcript.Add(line);
                transcript.AddRange(Responder.Wrap(script.Texts["INITIAL"][(sessions - 1) % script.Texts["INITIAL"].Count]));
            }
            else if (line[0] == ':') { transcript.Add(line); transcript.AddRange(Command(line).Select(t => "  " + t)); }
            else
            {
                transcript.Add("YOU: " + line);
                if (Quit(line)) { transcript.AddRange(Responder.Wrap(script.Texts["FINAL"][(sessions - 1) % script.Texts["FINAL"].Count])); continue; }
                state.Session.Undo = state.Copy(true); state.Session.Turns++;
                foreach (string word in Normalize(line).SelectMany(c => c)) if (!script.Stop.Contains(word)) Increment(state.Session.Words, word);
                state.Session.History.Add(state.Session.Turns + ": " + line);
                var decision = Decide(line); transcript.AddRange(Responder.Wrap(decision.Reply)); state.Session.LastTrace = decision.Trace;
                if (state.Session.Trace) transcript.AddRange(decision.Trace.Select(t => "  " + t));
            }
        }
        Notes(); transcript.Add(""); transcript.Add("SUMMARY sessions=" + sessions + " " + SourceLine(totalTurns, totals));
    }
    public void Write()
    {
        List<string> stats = ["keyword,rank,uses,replies,decomposition_hits"];
        foreach (Keyword key in script.Keywords.OrderByDescending(k => state.KeywordUses[k.Index]).ThenBy(k => k.Word, StringComparer.Ordinal))
        {
            string hits = key.Decomps.Count == 0 ? "-" : string.Join("/", key.Decomps.Select(r => state.Hits[r.Index]));
            stats.Add($"{key.Word},{key.Rank},{state.KeywordUses[key.Index]},{state.KeywordReplies[key.Index]},{hits}");
        }
        Directory.CreateDirectory("output");
        void Save(string name, IEnumerable<string> lines) => File.WriteAllText(Path.Combine("output", name), string.Concat(lines.Select(line => line + "\n")), Encoding.ASCII);
        Save("lint.txt", Linter.Lines(Linter.Check(script))); Save("transcript.txt", transcript); Save("keyword_stats.csv", stats); Save("memory_log.txt", state.Memory.Log);
    }
}
static class Program
{
    static void Main() { Chatbot chatbot = new(ScriptLoader.Load("input/script.txt")); chatbot.Run(File.ReadAllLines("input/dialogue.txt")); chatbot.Write(); }
}
