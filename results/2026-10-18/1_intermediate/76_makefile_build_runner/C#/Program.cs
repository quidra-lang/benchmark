using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

class ExpansionError(string message) : Exception(message) { }

class AbortBuild : Exception { }

record Variable(bool Simple, string Value);

record RecipeLine(int Number, string Text);

class Recipe
{
    public List<RecipeLine> Lines = [];
}

class Rule(string name, bool pattern)
{
    public string Name = name, Stem = "";
    public bool Pattern = pattern;
    public List<string> Prerequisites = [];
    public Recipe? Recipe;
}

class Group
{
    public List<Rule> Rules = [];
    public Recipe? Recipe;
}

class Condition(bool outer, bool value, int line)
{
    public bool Outer = outer, Value = value, Alternative;
    public int Line = line;
}

record Scope(string? Name, string? Value, List<string>? Arguments);

class Choice
{
    public List<string> Prerequisites = [];
    public Recipe? Recipe;
    public string Stem = "";
    public bool Source, Missing;
}

class Program
{
    SortedDictionary<string, int> files = new(StringComparer.Ordinal);
    int clock;
    readonly SortedDictionary<string, Variable> variables = new(StringComparer.Ordinal);
    readonly SortedDictionary<string, Rule> rules = new(StringComparer.Ordinal);
    readonly List<Rule> patterns = [];
    readonly SortedSet<string> phony = new(StringComparer.Ordinal);
    bool loaded;
    string? goal;
    string location = "make";
    readonly List<Scope> scopes = [];
    readonly HashSet<string> expanding = new(StringComparer.Ordinal);
    Dictionary<string, string>? automatic;
    List<string> output = [];
    static readonly Dictionary<string, (int Min, int Max)> Functions = CreateFunctions();

    static Dictionary<string, (int, int)> CreateFunctions()
    {
        Dictionary<string, (int, int)> result = new(StringComparer.Ordinal);
        foreach (string name in new[] { "strip", "sort", "words", "firstword", "lastword", "dir", "notdir", "suffix", "basename", "wildcard", "value", "info", "warning", "error" }) result[name] = (1, 1);
        foreach (string name in new[] { "findstring", "filter", "filter-out", "word", "addsuffix", "addprefix" }) result[name] = (2, 2);
        foreach (string name in new[] { "subst", "patsubst", "wordlist", "foreach" }) result[name] = (3, 3);
        result["if"] = (2, 3);
        result["call"] = (1, int.MaxValue);
        return result;
    }

    static void Error(string message) => throw new ExpansionError(message);

    static string LeftTrim(string text) => text.TrimStart(' ');

    static string RightTrim(string text) => text.TrimEnd(' ');

    static string Trim(string text) => text.Trim(' ');

    static List<string> Words(string text) => text.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToList();

    static List<string> Unique(IEnumerable<string> values) => values.Distinct(StringComparer.Ordinal).ToList();

    static bool Numeric(string text) => text.Length != 0 && text.All(c => c >= '0' && c <= '9');

    static string? Stem(string pattern, string word)
    {
        int p = pattern.IndexOf('%');
        if (p < 0) return pattern == word ? "" : null;
        string prefix = pattern[..p], suffix = pattern[(p + 1)..];
        return word.Length >= prefix.Length + suffix.Length && word.StartsWith(prefix, StringComparison.Ordinal) && word.EndsWith(suffix, StringComparison.Ordinal) ? word[prefix.Length..(word.Length - suffix.Length)] : null;
    }

    static string Substitute(string pattern, string value)
    {
        int p = pattern.IndexOf('%');
        return p < 0 ? pattern : pattern[..p] + value + pattern[(p + 1)..];
    }

    static string Replacement(string word, string pattern, string replacement)
    {
        string? stem = Stem(pattern, word);
        return stem == null ? word : pattern.Contains('%') ? Substitute(replacement, stem) : replacement;
    }

    static bool Wildcard(string pattern, string name)
    {
        bool[,] match = new bool[pattern.Length + 1, name.Length + 1];
        match[0, 0] = true;
        for (int i = 0; i < pattern.Length; i++) for (int j = 0; j <= name.Length; j++) if (match[i, j])
        {
            char c = pattern[i];
            if (c == '*')
            {
                match[i + 1, j] = true;
                if (j < name.Length && name[j] != '/') match[i, j + 1] = true;
            }
            else if (j < name.Length && (c == '?' ? name[j] != '/' : c == name[j])) match[i + 1, j + 1] = true;
        }
        return match[pattern.Length, name.Length];
    }
    void NewTime(string name) => files[name] = ++clock;

    void Discard()
    {
        loaded = false;
        variables.Clear();
        rules.Clear();
        patterns.Clear();
        phony.Clear();
        goal = null;
    }
    void ExpansionMessage(ExpansionError e) => output.Add($"{location}: *** {e.Message}.  Stop.");

    void CleanExpansion()
    {
        scopes.Clear();
        expanding.Clear();
        automatic = null;
        location = "make";
    }

    List<string> WildcardExpansion(string pattern)
    {
        if (!pattern.Contains('*') && !pattern.Contains('?')) return files.ContainsKey(pattern) ? [pattern] : [];
        return files.Keys.Where(name => Wildcard(pattern, name)).ToList();
    }

    static int BracketEnd(string text, int opening)
    {
        char open = text[opening], close = open == '(' ? ')' : '}';
        int depth = 0;
        for (int i = opening; i < text.Length; i++)
        {
            if (text[i] == open) depth++;
            else if (text[i] == close)
            {
                depth--;
                if (depth == 0) return i;
            }
        }
        Error("unterminated variable reference");
        return -1;
    }

    string Expand(string text)
    {
        StringBuilder result = new();
        for (int i = 0; i < text.Length;)
        {
            char c = text[i++];
            if (c != '$')
            {
                result.Append(c);
                continue;
            }
            if (i == text.Length) break;
            c = text[i++];
            if (c == '$') result.Append('$');
            else if (c is '(' or '{')
            {
                int end = BracketEnd(text, i - 1);
                result.Append(Reference(text[i..end], c));
                i = end + 1;
            }
            else result.Append(Value(c.ToString()));
        }
        return result.ToString();
    }

    string Value(string name)
    {
        for (int i = scopes.Count - 1; i >= 0; i--)
        {
            Scope scope = scopes[i];
            if (scope.Arguments == null)
            {
                if (scope.Name == name) return scope.Value!;
            }
            else if (Numeric(name))
            {
                int index = int.Parse(name);
                return index < scope.Arguments.Count ? scope.Arguments[index] : "";
            }
        }
        if (automatic != null && automatic.TryGetValue(name, out string? auto)) return auto;
        if (!variables.TryGetValue(name, out Variable? variable)) return "";
        if (variable.Simple) return variable.Value;
        if (!expanding.Add(name)) Error($"Recursive variable '{name}' references itself (eventually)");
        try
        {
            return Expand(variable.Value);
        }
        finally
        {
            expanding.Remove(name);
        }
    }

    string Reference(string content, char opening)
    {
        int first = content.IndexOf(' ');
        if (first >= 0 && Functions.ContainsKey(content[..first])) return Function(content[..first], LeftTrim(content[(first + 1)..]), opening);
        string name = Expand(content);
        int colon = name.IndexOf(':'), equal = colon < 0 ? -1 : name.IndexOf('=', colon + 1);
        if (equal >= 0)
        {
            string pattern = name[(colon + 1)..equal], replacement = name[(equal + 1)..];
            if (!pattern.Contains('%'))
            {
                pattern = "%" + pattern;
                replacement = "%" + replacement;
            }
            return string.Join(" ", Words(Value(name[..colon])).Select(word => Replacement(word, pattern, replacement)));
        }
        return Value(name);
    }

    static List<string> Arguments(string text, int maximum, char opening)
    {
        char closing = opening == '(' ? ')' : '}';
        List<string> result = [];
        int depth = 0, start = 0;
        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];
            if (c == opening) depth++;
            else if (c == closing) depth--;
            else if (c == ',' && depth == 0 && result.Count < maximum - 1)
            {
                result.Add(text[start..i]);
                start = i + 1;
            }
        }
        result.Add(text[start..]);
        return result;
    }

    string Function(string name, string text, char opening)
    {
        var limits = Functions[name];
        List<string> raw = Arguments(text, limits.Max, opening);
        if (raw.Count < limits.Min) Error($"insufficient number of arguments ({raw.Count}) to function '{name}'");
        if (name == "foreach")
        {
            string variable = Trim(Expand(raw[0]));
            List<string> list = Words(Expand(raw[1])), result = [];
            foreach (string word in list)
            {
                scopes.Add(new(variable, word, null));
                try
                {
                    result.Add(Expand(raw[2]));
                }
                finally
                {
                    scopes.RemoveAt(scopes.Count - 1);
                }
            }
            return string.Join(" ", result);
        }
        if (name == "if")
        {
            bool condition = Trim(Expand(raw[0])).Length != 0;
            return condition ? Expand(raw[1]) : raw.Count == 3 ? Expand(raw[2]) : "";
        }
        List<string> a = [];
        foreach (string arg in raw)
        {
            string v = Expand(arg);
            a.Add(name is "subst" or "call" ? v : Trim(v));
        }
        if (name == "call")
        {
            string variable = Trim(a[0]);
            if (!variables.TryGetValue(variable, out Variable? v)) return "";
            if (v.Simple) return v.Value;
            a[0] = variable;
            scopes.Add(new(null, null, a));
            try
            {
                return Expand(v.Value);
            }
            finally
            {
                scopes.RemoveAt(scopes.Count - 1);
            }
        }
        if (name == "value") return variables.GetValueOrDefault(a[0])?.Value ?? "";
        if (name == "info")
        {
            output.Add(a[0]);
            return "";
        }
        if (name == "warning")
        {
            output.Add(location + ": " + a[0]);
            return "";
        }
        if (name == "error")
        {
            Error(a[0]);
            return "";
        }
        if (name == "subst") return a[0].Length == 0 ? a[2] : a[2].Replace(a[0], a[1], StringComparison.Ordinal);
        if (name == "findstring") return a[1].Contains(a[0], StringComparison.Ordinal) ? a[0] : "";
        if (name == "word")
        {
            string n = a[0];
            if (!Numeric(n)) Error($"non-numeric first argument to 'word' function: '{n}'");
            int index = int.Parse(n);
            if (index == 0) Error("first argument to 'word' function must be greater than 0");
            List<string> list = Words(a[1]);
            return index <= list.Count ? list[index - 1] : "";
        }
        if (name == "wordlist")
        {
            if (!Numeric(a[0])) Error($"non-numeric first argument to 'wordlist' function: '{a[0]}'");
            if (!Numeric(a[1])) Error($"non-numeric second argument to 'wordlist' function: '{a[1]}'");
            int start = int.Parse(a[0]), end = int.Parse(a[1]);
            if (start == 0) Error($"invalid first argument to 'wordlist' function: '{a[0]}'");
            List<string> list = Words(a[2]);
            return start > end || start > list.Count ? "" : string.Join(" ", list.Skip(start - 1).Take(end - start + 1));
        }
        List<string> values = Words(a[^1]), resultWords = [];
        switch (name)
        {
            case "patsubst":
                resultWords.AddRange(values.Select(word => Replacement(word, a[0], a[1])));
                break;
            case "filter":
            case "filter-out":
            {
                List<string> filters = Words(a[0]);
                resultWords.AddRange(values.Where(word => filters.Any(p => Stem(p, word) != null) == (name == "filter")));
                break;
            }
            case "strip":
                resultWords.AddRange(values);
                break;
            case "sort":
                resultWords.AddRange(values.Distinct(StringComparer.Ordinal).OrderBy(v => v, StringComparer.Ordinal));
                break;
            case "words":
                return values.Count.ToString();
            case "firstword":
                return values.FirstOrDefault() ?? "";
            case "lastword":
                return values.LastOrDefault() ?? "";
            case "dir":
            case "notdir":
            case "suffix":
            case "basename":
                foreach (string word in values)
                {
                    int slash = word.LastIndexOf('/'), dot = word.LastIndexOf('.');
                    bool extension = dot > slash;
                    switch (name)
                    {
                        case "dir":
                            resultWords.Add(slash < 0 ? "./" : word[..(slash + 1)]);
                            break;
                        case "notdir":
                            resultWords.Add(word[(slash + 1)..]);
                            break;
                        case "suffix":
                            if (extension) resultWords.Add(word[dot..]);
                            break;
                        default:
                            resultWords.Add(extension ? word[..dot] : word);
                            break;
                    }
                }
                break;
            case "addsuffix":
                resultWords.AddRange(values.Select(word => word + a[0]));
                break;
            case "addprefix":
                resultWords.AddRange(values.Select(word => a[0] + word));
                break;
            case "wildcard":
                foreach (string word in values) resultWords.AddRange(WildcardExpansion(word));
                break;
        }
        return string.Join(" ", resultWords);
    }

    static (int Equal, int Colon, int Semicolon) Outside(string text)
    {
        int equal = -1, colon = -1, semicolon = -1;
        for (int i = 0; i < text.Length;)
        {
            char c = text[i];
            if (c == '$')
            {
                if (i + 1 < text.Length && text[i + 1] is '(' or '{') i = BracketEnd(text, i + 1) + 1;
                else i += Math.Min(2, text.Length - i);
            }
            else
            {
                if (c == '=' && equal < 0) equal = i;
                if (c == ':' && colon < 0) colon = i;
                if (c == ';' && semicolon < 0) semicolon = i;
                i++;
            }
        }
        return (equal, colon, semicolon);
    }

    Rule Register(string target, List<string> prerequisites)
    {
        if (!rules.TryGetValue(target, out Rule? rule)) rules[target] = rule = new(target, false);
        foreach (string p in Unique(prerequisites)) if (!rule.Prerequisites.Contains(p)) rule.Prerequisites.Add(p);
        if (goal == null && !target.StartsWith('.')) goal = target;
        return rule;
    }

    void AddRecipe(Group group, int number, string text)
    {
        if (group.Rules.Count == 0) return;
        if (group.Recipe == null)
        {
            group.Recipe = new();
            foreach (Rule rule in group.Rules)
            {
                if (!rule.Pattern && rule.Recipe != null)
                {
                    output.Add($"Makefile:{number}: warning: overriding recipe for target '{rule.Name}'");
                    output.Add($"Makefile:{rule.Recipe.Lines[0].Number}: warning: ignoring old recipe for target '{rule.Name}'");
                }
                rule.Recipe = group.Recipe;
            }
        }
        group.Recipe.Lines.Add(new(number, text));
    }

    static bool Active(List<Condition> conditions) => conditions.Count == 0 || conditions[^1].Outer && conditions[^1].Value;

    void Conditional(string name, string rest, int line, List<Condition> conditions)
    {
        if (name == "else")
        {
            if (conditions.Count == 0) Error("extraneous 'else'");
            Condition top = conditions[^1];
            if (top.Alternative) Error("only one 'else' per conditional");
            top.Value = !top.Value;
            top.Alternative = true;
            return;
        }
        if (name == "endif")
        {
            if (conditions.Count == 0) Error("extraneous 'endif'");
            conditions.RemoveAt(conditions.Count - 1);
            return;
        }
        bool outer = Active(conditions), condition = false;
        if (outer)
        {
            if (name is "ifdef" or "ifndef")
            {
                Variable? v = variables.GetValueOrDefault(Trim(Expand(rest)));
                condition = v != null && v.Value.Length != 0;
                if (name == "ifndef") condition = !condition;
            }
            else
            {
                if (rest.Length < 2 || !rest.StartsWith('(') || !rest.EndsWith(')')) Error("invalid syntax in conditional");
                string inside = rest[1..^1];
                int depth = 0, comma = -1;
                for (int i = 0; i < inside.Length; i++)
                {
                    char c = inside[i];
                    if (c == '(') depth++;
                    else if (c == ')') depth--;
                    else if (c == ',' && depth == 0)
                    {
                        comma = i;
                        break;
                    }
                }
                if (comma < 0) Error("invalid syntax in conditional");
                string a = Trim(Expand(inside[..comma])), b = Trim(Expand(inside[(comma + 1)..]));
                condition = a == b;
                if (name == "ifneq") condition = !condition;
            }
        }
        conditions.Add(new(outer, condition, line));
    }

    void Load(List<string> body)
    {
        Discard();
        Group? current = null;
        List<Condition> conditions = [];
        try
        {
            for (int i = 0; i < body.Count; i++)
            {
                int number = i + 1;
                location = "Makefile:" + number;
                string line = body[i];
                if (line.StartsWith('>'))
                {
                    if (!Active(conditions)) continue;
                    if (current == null) Error("recipe commences before first target");
                    AddRecipe(current!, number, LeftTrim(line[1..]));
                    continue;
                }
                while (line.EndsWith('\\') && i + 1 < body.Count) line = RightTrim(line[..^1]) + " " + LeftTrim(body[++i]);
                int comment = line.IndexOf('#');
                string t = Trim(comment < 0 ? line : line[..comment]);
                int space = t.IndexOf(' ');
                string first = space < 0 ? t : t[..space], rest = space < 0 ? "" : Trim(t[(space + 1)..]);
                if (new[] { "ifeq", "ifneq", "ifdef", "ifndef", "else", "endif" }.Contains(first))
                {
                    Conditional(first, rest, number, conditions);
                    continue;
                }
                if (t.Length == 0 || !Active(conditions)) continue;
                var positions = Outside(t);
                int equal = positions.Equal, colon = positions.Colon;
                if (equal >= 0 && (colon < 0 || colon >= equal - 1))
                {
                    char op = equal > 0 && ":+?".Contains(t[equal - 1]) ? t[equal - 1] : '=';
                    string name = Trim(t[..(equal - (op == '=' ? 0 : 1))]), rhs = Trim(t[(equal + 1)..]);
                    if (name.Length == 0) Error("empty variable name");
                    Variable? old = variables.GetValueOrDefault(name);
                    if (op == ':') variables[name] = new(true, Expand(rhs));
                    else if (op == '+' && old != null)
                    {
                        string add = old.Simple ? Expand(rhs) : rhs;
                        variables[name] = new(old.Simple, old.Value.Length == 0 ? add : old.Value + " " + add);
                    }
                    else if (op != '?' || old == null) variables[name] = new(false, rhs);
                    current = null;
                }
                else if (colon >= 0)
                {
                    List<string> targets = Unique(Words(Expand(t[..colon])));
                    string r = t[(colon + 1)..];
                    string? inline = null;
                    int semicolon = Outside(r).Semicolon;
                    if (semicolon >= 0)
                    {
                        inline = LeftTrim(r[(semicolon + 1)..]);
                        r = r[..semicolon];
                    }
                    int staticColon = Outside(r).Colon;
                    string? targetPattern = null;
                    if (staticColon >= 0)
                    {
                        targetPattern = Trim(Expand(r[..staticColon]));
                        r = r[(staticColon + 1)..];
                    }
                    List<string> prerequisites = Words(Expand(r));
                    current = new();
                    if (targets.Count == 1 && targets[0] == ".PHONY") phony.UnionWith(prerequisites);
                    else if (targetPattern != null)
                    {
                        if (!targetPattern.Contains('%')) Error("target pattern contains no '%'");
                        foreach (string target in targets)
                        {
                            string? stem = Stem(targetPattern, target);
                            if (stem == null || stem.Length == 0) output.Add($"{location}: target '{target}' doesn't match the target pattern");
                            else
                            {
                                Rule rule = Register(target, prerequisites.Select(p => Substitute(p, stem)).ToList());
                                rule.Stem = stem;
                                current.Rules.Add(rule);
                            }
                        }
                    }
                    else if (targets.Any(p => p.Contains('%')))
                    {
                        if (targets.Any(p => !p.Contains('%'))) Error("mixed implicit and normal rules");
                        foreach (string target in targets)
                        {
                            Rule rule = new(target, true);
                            rule.Prerequisites.AddRange(prerequisites);
                            patterns.Add(rule);
                            current.Rules.Add(rule);
                        }
                    }
                    else foreach (string target in targets) current.Rules.Add(Register(target, prerequisites));
                    if (inline != null) AddRecipe(current, number, inline);
                }
                else if (Trim(Expand(t)).Length != 0) Error("missing separator");
            }
            if (conditions.Count != 0)
            {
                location = "Makefile:" + conditions[^1].Line;
                Error("missing 'endif'");
            }
            loaded = true;
            output.Add($"Makefile loaded: lines={body.Count} variables={variables.Count} targets={rules.Count} patterns={patterns.Count(p => p.Recipe != null)} goal={goal ?? "(none)"}");
        }
        catch (ExpansionError e)
        {
            ExpansionMessage(e);
            Discard();
        }
        finally
        {
            CleanExpansion();
        }
    }

    Choice Determine(string target)
    {
        Rule? explicitRule = rules.GetValueOrDefault(target);
        Choice choice = new();
        if (explicitRule?.Recipe != null)
        {
            choice.Prerequisites.AddRange(explicitRule.Prerequisites);
            choice.Recipe = explicitRule.Recipe;
            choice.Stem = explicitRule.Stem;
            return choice;
        }
        if (!phony.Contains(target))
        {
            Rule? best = null;
            string? bestStem = null;
            foreach (Rule pattern in patterns) if (pattern.Recipe != null)
            {
                string? stem = Stem(pattern.Name, target);
                if (stem == null || stem.Length == 0 || bestStem != null && stem.Length >= bestStem.Length) continue;
                bool usable = pattern.Prerequisites.All(p => files.ContainsKey(Substitute(p, stem)) || rules.ContainsKey(Substitute(p, stem)));
                if (usable)
                {
                    best = pattern;
                    bestStem = stem;
                }
            }
            if (best != null)
            {
                choice.Prerequisites.AddRange(best.Prerequisites.Select(p => Substitute(p, bestStem!)));
                if (explicitRule != null) choice.Prerequisites.AddRange(explicitRule.Prerequisites);
                choice.Prerequisites = Unique(choice.Prerequisites);
                choice.Recipe = best.Recipe;
                choice.Stem = bestStem!;
                return choice;
            }
        }
        if (explicitRule != null || phony.Contains(target))
        {
            if (explicitRule != null)
            {
                choice.Prerequisites.AddRange(explicitRule.Prerequisites);
                choice.Stem = explicitRule.Stem;
            }
            return choice;
        }
        if (files.ContainsKey(target)) choice.Source = true;
        else choice.Missing = true;
        return choice;
    }
    int? TargetTime(string target) => phony.Contains(target) || !files.TryGetValue(target, out int value) ? null : value;

    int Execute(string command)
    {
        List<string> w = Words(command);
        switch (w[0])
        {
            case "echo":
                output.Add(string.Join(" ", w.Skip(1)));
                return 0;
            case "touch":
                foreach (string name in w.Skip(1)) NewTime(name);
                return 0;
            case "rm":
            {
                bool force = w.Count > 1 && w[1] == "-f";
                int status = 0;
                foreach (string pattern in w.Skip(force ? 2 : 1))
                {
                    List<string> names = WildcardExpansion(pattern);
                    if (names.Count == 0) names = [pattern];
                    foreach (string name in names) if (!files.Remove(name) && !force)
                    {
                        output.Add($"rm: cannot remove '{name}': No such file or directory");
                        status = 1;
                    }
                }
                return status;
            }
            case "false":
                return 1;
            case "exit":
                return w.Count > 1 ? int.Parse(w[1]) : 0;
            default:
                return 0;
        }
    }

    class Build(Program runner, HashSet<char> options)
    {
        readonly Dictionary<string, int> results = new(StringComparer.Ordinal);
        readonly HashSet<string> building = new(StringComparer.Ordinal);
        public Dictionary<string, Choice> Choices = new(StringComparer.Ordinal);
        public int Runs;
        bool Has(char option) => options.Contains(option);
        public int Target(string name, string? parent)
        {
            if (results.TryGetValue(name, out int recorded)) return recorded;
            Choice choice = runner.Determine(name);
            Choices[name] = choice;
            if (choice.Missing)
            {
                results[name] = 1;
                runner.output.Add($"make: *** No rule to make target '{name}'" + (parent == null ? "." : $", needed by '{parent}'.") + (Has('k') ? "" : "  Stop."));
                if (!Has('k')) throw new AbortBuild();
                return 1;
            }
            if (choice.Source)
            {
                results[name] = 0;
                return 0;
            }
            building.Add(name);
            bool failed = false;
            List<string> kept = [];
            foreach (string p in choice.Prerequisites)
            {
                if (building.Contains(p)) runner.output.Add($"make: Circular {name} <- {p} dependency dropped.");
                else
                {
                    kept.Add(p);
                    if (Target(p, name) != 0) failed = true;
                }
            }
            choice.Prerequisites = kept;
            building.Remove(name);
            int result = failed ? 2 : Update(name, choice);
            results[name] = result;
            return result;
        }
        int Update(string target, Choice choice)
        {
            int? old = runner.TargetTime(target);
            List<string> fresh = [];
            foreach (string p in choice.Prerequisites)
            {
                int? time = runner.TargetTime(p);
                if (Has('B') || !old.HasValue || !time.HasValue || time.Value > old.Value) fresh.Add(p);
            }
            if (choice.Recipe == null || !Has('B') && old.HasValue && fresh.Count == 0) return 0;
            Runs++;
            List<RecipeLine> expanded = [];
            runner.automatic = new(StringComparer.Ordinal) { ["@"] = target, ["<"] = choice.Prerequisites.FirstOrDefault() ?? "", ["^"] = string.Join(" ", choice.Prerequisites), ["?"] = string.Join(" ", fresh), ["*"] = choice.Stem };
            try
            {
                foreach (RecipeLine line in choice.Recipe.Lines)
                {
                    runner.location = "Makefile:" + line.Number;
                    expanded.Add(new(line.Number, runner.Expand(line.Text)));
                }
            }
            finally
            {
                runner.automatic = null;
            }
            foreach (RecipeLine line in expanded)
            {
                int i = 0;
                bool silent = false, ignore = false;
                while (i < line.Text.Length && " @-".Contains(line.Text[i]))
                {
                    silent |= line.Text[i] == '@';
                    ignore |= line.Text[i] == '-';
                    i++;
                }
                string command = RightTrim(line.Text[i..]);
                if (command.Length == 0) continue;
                if (Has('n') || !silent && !Has('s')) runner.output.Add(command);
                if (Has('n')) continue;
                int status = runner.Execute(command);
                if (status != 0)
                {
                    if (ignore || Has('i')) runner.output.Add($"make: [Makefile:{line.Number}: {target}] Error {status} (ignored)");
                    else
                    {
                        runner.output.Add($"make: *** [Makefile:{line.Number}: {target}] Error {status}");
                        if (!Has('k')) throw new AbortBuild();
                        return 1;
                    }
                }
            }
            if (!runner.phony.Contains(target)) runner.NewTime(target);
            return 0;
        }
    }

    void Make(string args)
    {
        List<string> goals = [];
        HashSet<char> options = [];
        foreach (string word in Words(args))
        {
            if (word.StartsWith('-'))
            {
                foreach (char option in word.Skip(1))
                {
                    if (!"nBkis".Contains(option))
                    {
                        output.Add($"make: invalid option -- '{option}'");
                        return;
                    }
                    options.Add(option);
                }
            }
            else goals.Add(word);
        }
        if (goals.Count == 0)
        {
            if (!loaded)
            {
                output.Add("make: *** No targets specified and no makefile found.  Stop.");
                return;
            }
            if (goal == null)
            {
                output.Add("make: *** No targets.  Stop.");
                return;
            }
            goals.Add(goal);
        }
        SortedDictionary<string, int>? saved = options.Contains('n') ? new(files, StringComparer.Ordinal) : null;
        int oldClock = clock;
        Build build = new(this, options);
        try
        {
            foreach (string name in goals)
            {
                int previous = build.Runs, result = build.Target(name, null);
                if (result == 0 && previous == build.Runs) output.Add(phony.Contains(name) || build.Choices[name].Recipe == null ? $"make: Nothing to be done for '{name}'." : $"make: '{name}' is up to date.");
                else if (result == 2) output.Add($"make: Target '{name}' not remade because of errors.");
            }
        }
        catch (AbortBuild) { } catch (ExpansionError e)
        {
            ExpansionMessage(e);
        }
        finally
        {
            if (saved != null)
            {
                files = saved;
                clock = oldClock;
            }
            CleanExpansion();
        }
    }

    void Command(string line, List<string> body)
    {
        output = ["$ " + line];
        int space = line.IndexOf(' ');
        string c = space < 0 ? line : line[..space], rest = space < 0 ? "" : line[(space + 1)..];
        try
        {
            switch (c)
            {
                case "MAKEFILE":
                    Load(body);
                    break;
                case "MAKE":
                    Make(rest);
                    break;
                case "TOUCH":
                    foreach (string name in Words(rest)) NewTime(name);
                    break;
                case "RM":
                    foreach (string name in Words(rest)) if (!files.Remove(name)) output.Add($"rm: cannot remove '{name}': No such file or directory");
                    break;
                case "FILES":
                    output.Add("clock " + clock);
                    foreach ((string name, int value) in files) output.Add($"{name} {value}");
                    break;
                case "VARS":
                    if (loaded) foreach ((string name, Variable variable) in variables)
                    {
                        string value = Trim(Value(name));
                        output.Add(name + (variable.Simple ? " :=" : " =") + (value.Length == 0 ? "" : " " + value));
                    }
                    break;
                case "RULES":
                    if (loaded)
                    {
                        List<Rule> all = [.. rules.Values, .. patterns.Where(p => p.Recipe != null)];
                        foreach (Rule rule in all)
                        {
                            output.Add(rule.Name + ":" + (rule.Prerequisites.Count == 0 ? "" : " " + string.Join(" ", rule.Prerequisites)));
                            if (rule.Recipe != null) foreach (RecipeLine recipe in rule.Recipe.Lines) output.Add(">" + recipe.Text);
                        }
                        if (phony.Count != 0) output.Add(".PHONY: " + string.Join(" ", phony));
                    }
                    break;
                case "EXPAND":
                    output.Add("[" + Expand(rest) + "]");
                    break;
            }
        }
        catch (ExpansionError e)
        {
            ExpansionMessage(e);
        }
        finally
        {
            CleanExpansion();
        }
        foreach (string row in output) Console.WriteLine(row);
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program runner = new();
        Console.ReadLine();
        string line;
        while ((line = Console.ReadLine()!) != "END FILES")
        {
            int space = line.IndexOf(' '), value = int.Parse(line[(space + 1)..]);
            runner.files[line[..space]] = value;
            runner.clock = Math.Max(runner.clock, value);
        }
        while ((line = Console.ReadLine()!) != "QUIT")
        {
            List<string> body = [];
            if (line == "MAKEFILE")
            {
                string row;
                while ((row = Console.ReadLine()!) != "END MAKEFILE") body.Add(row);
            }
            runner.Command(line, body);
        }
    }
}
