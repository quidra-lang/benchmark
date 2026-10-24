using System.Text;
using System.Text.RegularExpressions;

var dictionary = new Dictionary<string, int>();
int wordCount = int.Parse(Console.ReadLine()!);
for (int i = 0; i < wordCount; i++)
{
    string[] parts = Console.ReadLine()!.Split(' ');
    dictionary[parts[0]] = int.Parse(parts[1]);
}
var checker = new SpellChecker(dictionary);
int commandCount = int.Parse(Console.ReadLine()!);
for (int i = 0; i < commandCount; i++)
{
    checker.Execute(Console.ReadLine() ?? "");
}
Console.Out.Write(string.Join("\n", checker.Output) + "\n");

sealed class CommandException(string message) : Exception(message);

sealed record UndoRecord(
    string Name,
    Dictionary<string, int> Dictionary,
    HashSet<string> Ignored,
    Dictionary<string, string> Rules);

sealed record Token(int Number, string Text, int End, string Gap, bool SentenceStart, bool Repeat)
{
    const string SentenceMarks = ".!?";

    public string Word { get; } = Text.ToLowerInvariant();

    public bool MixedCase => Text.Skip(1).Any(char.IsUpper) && !Text.All(char.IsUpper);

    public static List<Token> Tokenize(string text)
    {
        var tokens = new List<Token>();
        int position = 0;
        foreach (Match match in Regex.Matches(text, "[A-Za-z]+"))
        {
            string gap = text[position..match.Index];
            string word = match.Value.ToLowerInvariant();
            Token? previous = tokens.Count > 0 ? tokens[^1] : null;
            bool sentenceStart = previous is null || gap.Any(mark => SentenceMarks.Contains(mark));
            bool repeat = previous is not null && previous.Word == word && gap.All(c => c == ' ');
            position = match.Index + match.Length;
            tokens.Add(
                new Token(tokens.Count + 1, match.Value, position, gap, sentenceStart, repeat));
        }
        return tokens;
    }
}

static class EditDistance
{
    static readonly string[] AdjacentKeys =
    [
        "qswz", "ghnv", "dfvx", "cefrsx", "drsw", "cdgrtv", "bfhtvy", "bgjnuy", "jkou", "hikmnu",
        "ijlmo", "kop", "jkn", "bhjm", "iklp", "lo", "aw", "deft", "adewxz", "fgry", "hijy",
        "bcfg", "aeqs", "cdsz", "ghtu", "asx",
    ];

    public static int GapCost(bool keyboard) => keyboard ? 2 : 1;

    static int SubstitutionCost(char first, char second, bool keyboard)
    {
        if (first == second)
            return 0;
        if (!keyboard)
            return 1;
        return AdjacentKeys[first - 'a'].Contains(second) ? 1 : 2;
    }

    static bool IsSwap(string first, string second, int i, int j) =>
        i >= 2 && j >= 2 && first[i - 1] == second[j - 2] && first[i - 2] == second[j - 1];

    static int[,] Table(string first, string second, bool keyboard)
    {
        int gap = GapCost(keyboard);
        var table = new int[first.Length + 1, second.Length + 1];
        for (int i = 0; i <= first.Length; i++)
            table[i, 0] = i * gap;
        for (int j = 0; j <= second.Length; j++)
            table[0, j] = j * gap;
        for (int i = 1; i <= first.Length; i++)
        {
            for (int j = 1; j <= second.Length; j++)
            {
                int best = Math.Min(table[i - 1, j] + gap, table[i, j - 1] + gap);
                int substitution = SubstitutionCost(first[i - 1], second[j - 1], keyboard);
                best = Math.Min(best, table[i - 1, j - 1] + substitution);
                if (IsSwap(first, second, i, j))
                    best = Math.Min(best, table[i - 2, j - 2] + 1);
                table[i, j] = best;
            }
        }
        return table;
    }

    public static int Compute(string first, string second, bool keyboard) =>
        Table(first, second, keyboard)[first.Length, second.Length];

    public static int Prefix(string word, string other, bool keyboard)
    {
        int[,] table = Table(word, other, keyboard);
        return Enumerable.Range(0, other.Length + 1).Min(j => table[word.Length, j]);
    }

    public static (int Distance, List<string> Operations) Operations(
        string first, string second, bool keyboard)
    {
        int[,] table = Table(first, second, keyboard);
        int gap = GapCost(keyboard);
        var operations = new List<string>();
        int i = first.Length;
        int j = second.Length;
        while (i > 0 || j > 0)
        {
            if (i >= 1 && j >= 1
                && table[i, j] == table[i - 1, j - 1]
                    + SubstitutionCost(first[i - 1], second[j - 1], keyboard))
            {
                if (first[i - 1] != second[j - 1])
                    operations.Add($"sub:{first[i - 1]}>{second[j - 1]}");
                i--;
                j--;
            }
            else if (IsSwap(first, second, i, j) && table[i, j] == table[i - 2, j - 2] + 1)
            {
                operations.Add($"swap:{first[i - 2]}{first[i - 1]}");
                i -= 2;
                j -= 2;
            }
            else if (i >= 1 && table[i, j] == table[i - 1, j] + gap)
            {
                operations.Add($"del:{first[i - 1]}");
                i--;
            }
            else
            {
                operations.Add($"ins:{second[j - 1]}");
                j--;
            }
        }
        operations.Reverse();
        return (table[first.Length, second.Length], operations);
    }
}

static class Soundex
{
    // h and w map to 0: that is their value as a first letter, and they are skipped elsewhere
    const string Digits = "01230120022455012623010202";

    public static string Encode(string word)
    {
        var code = new StringBuilder().Append(char.ToUpperInvariant(word[0]));
        char previous = Digits[word[0] - 'a'];
        foreach (char letter in word[1..])
        {
            if (letter is 'h' or 'w')
                continue;
            char digit = Digits[letter - 'a'];
            if (digit != '0' && digit != previous)
                code.Append(digit);
            previous = digit;
        }
        return code.Append("000").ToString()[..4];
    }
}

sealed class SpellChecker
{
    const int MaxWordLength = 30;
    const int MaxFrequency = 1000000;
    const int MaxListed = 20;
    const int ReportSize = 10;
    static readonly string[] FindingKinds = ["unknown", "case", "capital", "repeats"];
    static readonly string[] CounterNames =
        ["checked", "unknown", "case", "capital", "repeats", "corrected"];
    static readonly Dictionary<string, int> OptionMaximums =
        new() { ["LIMIT"] = 3, ["SUGGESTIONS"] = 10 };

    Dictionary<string, int> dictionary;
    HashSet<string> ignored = [];
    Dictionary<string, string> rules = [];
    bool keyboard;
    int baseLimit = 2;
    int suggestionCount = 5;
    readonly List<UndoRecord> undoHistory = [];
    readonly Dictionary<string, int> unknownLog = [];
    readonly Dictionary<(string Word, string Correction), int> correctionLog = [];
    readonly Dictionary<string, int> counters = CounterNames.ToDictionary(name => name, _ => 0);
    readonly Dictionary<string, Action<string>> textCommands;
    readonly Dictionary<string, (int Arity, Action<string[]> Run)> commands;

    public List<string> Output { get; } = [];

    public SpellChecker(Dictionary<string, int> dictionary)
    {
        this.dictionary = dictionary;
        textCommands = new()
        {
            ["CHECK"] = Check,
            ["CORRECT"] = Correct,
            ["FIX"] = Fix,
            ["PROFILE"] = Profile,
            ["LEARN"] = Learn,
        };
        commands = new()
        {
            ["SUGGEST"] = (1, Suggest),
            ["DIST"] = (2, Dist),
            ["SOUNDEX"] = (1, SoundexCode),
            ["SOUNDS"] = (1, Sounds),
            ["SPLIT"] = (1, Split),
            ["PREFIX"] = (2, Prefix),
            ["COMPLETE"] = (2, Complete),
            ["LIST"] = (2, ListWords),
            ["WORD"] = (1, WordInfo),
            ["ADD"] = (2, Add),
            ["REMOVE"] = (1, Remove),
            ["IGNORE"] = (1, Ignore),
            ["UNIGNORE"] = (1, Unignore),
            ["RULE"] = (2, Rule),
            ["UNRULE"] = (1, Unrule),
            ["RULES"] = (0, _ => ShowRules()),
            ["KEYBOARD"] = (1, KeyboardMode),
            ["SET"] = (2, SetOption),
            ["UNDO"] = (0, _ => Undo()),
            ["REPORT"] = (0, _ => Report()),
            ["HISTORY"] = (0, _ => History()),
            ["STATS"] = (0, _ => Stats()),
        };
    }

    static string WordArgument(string text) =>
        Regex.IsMatch(text, "^[A-Za-z]{1,30}$")
            ? text.ToLowerInvariant()
            : throw new CommandException($"BAD WORD {text}");

    static int NumberArgument(string text, int minimum, int maximum)
    {
        if (!Regex.IsMatch(text, "^[0-9]{1,7}$"))
            throw new CommandException($"BAD NUMBER {text}");
        int value = int.Parse(text);
        if (value < minimum || value > maximum)
            throw new CommandException($"BAD NUMBER {text}");
        return value;
    }

    static string DecimalText(long numerator, long denominator, int digits)
    {
        long scale = (long)Math.Pow(10, digits);
        long value = (2 * numerator * scale + denominator) / (2 * denominator);
        return $"{value / scale}.{(value % scale).ToString($"D{digits}")}";
    }

    static string CapitalizeFirst(string word) => char.ToUpperInvariant(word[0]) + word[1..];

    static string ApplyCase(string tokenText, string word)
    {
        if (tokenText.Length >= 2 && tokenText.All(char.IsUpper))
            return word.ToUpperInvariant();
        if (char.IsUpper(tokenText[0]))
            return CapitalizeFirst(word);
        return word;
    }

    static (long Ways, List<string>? Best) Segment(string word, Dictionary<string, int> dictionary)
    {
        int length = word.Length;
        var ways = new long[length + 1];
        var best = new List<string>?[length + 1];
        ways[length] = 1;
        best[length] = [];
        for (int start = length - 1; start >= 0; start--)
        {
            for (int end = start + 1; end <= length; end++)
            {
                string piece = word[start..end];
                if (!dictionary.ContainsKey(piece) || ways[end] == 0)
                    continue;
                ways[start] += ways[end];
                List<string> candidate = [piece, .. best[end]!];
                // pieces share their start: with equal counts the earlier, shorter one is smaller
                if (best[start] is not { } current || candidate.Count < current.Count)
                    best[start] = candidate;
            }
        }
        return (ways[0], best[0]);
    }

    void Emit(params IEnumerable<string> parts) => Output.Add(string.Join(" ", parts));

    int Limit => keyboard ? 2 * baseLimit : baseLimit;

    bool IsKnown(string word) => dictionary.ContainsKey(word) || ignored.Contains(word);

    List<string> FrequencyOrder() =>
        dictionary
            .OrderByDescending(entry => entry.Value)
            .ThenBy(entry => entry.Key, StringComparer.Ordinal)
            .Select(entry => entry.Key)
            .ToList();

    int RequireEntry(string word) =>
        dictionary.TryGetValue(word, out int frequency)
            ? frequency
            : throw new CommandException($"NOT FOUND {word}");

    List<(string Word, int Distance)> InDistanceOrder(
        IEnumerable<(string Word, int Distance)> found) =>
        found
            .OrderBy(item => item.Distance)
            .ThenByDescending(item => dictionary[item.Word])
            .ThenBy(item => item.Word, StringComparer.Ordinal)
            .ToList();

    List<(string Word, int Distance)> Candidates(string word)
    {
        int limit = Limit;
        int gap = EditDistance.GapCost(keyboard);
        return InDistanceOrder(
            dictionary.Keys
                .Where(other =>
                    other != word && Math.Abs(other.Length - word.Length) * gap <= limit)
                .Select(other =>
                    (Word: other, Distance: EditDistance.Compute(word, other, keyboard)))
                .Where(item => item.Distance <= limit));
    }

    string? Correction(string word)
    {
        if (IsKnown(word))
            return null;
        if (rules.TryGetValue(word, out string? target))
            return target;
        var found = Candidates(word);
        return found.Count > 0 ? found[0].Word : null;
    }

    void RecordUndo(string name) =>
        undoHistory.Add(new UndoRecord(name, new(dictionary), new(ignored), new(rules)));

    void LogCorrection(string word, string replacement)
    {
        var key = (word, replacement);
        correctionLog[key] = correctionLog.GetValueOrDefault(key) + 1;
        counters["corrected"]++;
    }

    string UnknownFinding(Token token)
    {
        string prefix = $"UNKNOWN {token.Number} {token.Text}";
        if (rules.TryGetValue(token.Word, out string? target))
            return $"{prefix} RULE {target}";
        var found = Candidates(token.Word);
        if (found.Count == 0)
            return $"{prefix} NONE";
        var words = found.Take(suggestionCount).Select(item => item.Word);
        return string.Join(" ", [prefix, "SUGGEST", .. words]);
    }

    void Check(string text)
    {
        var tokens = Token.Tokenize(text);
        var findings = new List<(string Kind, string Line)>();
        foreach (var token in tokens)
        {
            if (!IsKnown(token.Word))
            {
                findings.Add(("unknown", UnknownFinding(token)));
                unknownLog[token.Word] = unknownLog.GetValueOrDefault(token.Word) + 1;
            }
            if (token.MixedCase)
                findings.Add(("case", $"CASE {token.Number} {token.Text}"));
            if (token.SentenceStart && char.IsLower(token.Text[0]))
                findings.Add(("capital", $"CAPITAL {token.Number} {token.Text}"));
            if (token.Repeat)
                findings.Add(("repeats", $"REPEAT {token.Number} {token.Text}"));
        }
        var counts = FindingKinds.ToDictionary(
            kind => kind, kind => findings.Count(finding => finding.Kind == kind));
        counters["checked"] += tokens.Count;
        foreach (string kind in FindingKinds)
            counters[kind] += counts[kind];
        var shown = FindingKinds.Select(kind => $"{kind}={counts[kind]}");
        Emit(["CHECK", $"words={tokens.Count}", .. shown]);
        foreach (var (_, line) in findings)
            Emit(line);
    }

    void Correct(string text)
    {
        var result = new StringBuilder();
        int position = 0;
        int changed = 0;
        foreach (var token in Token.Tokenize(text))
        {
            string? replacement = Correction(token.Word);
            result.Append(token.Gap);
            if (replacement is null)
            {
                result.Append(token.Text);
            }
            else
            {
                result.Append(ApplyCase(token.Text, replacement));
                LogCorrection(token.Word, replacement);
                changed++;
            }
            position = token.End;
        }
        result.Append(text[position..]);
        Emit($"CORRECT changed={changed}:", result.ToString());
    }

    void Fix(string text)
    {
        var result = new StringBuilder();
        int position = 0;
        int removed = 0;
        int replaced = 0;
        int recased = 0;
        foreach (var token in Token.Tokenize(text))
        {
            position = token.End;
            if (token.Repeat)
            {
                removed++;
                continue;
            }
            string? replacement = Correction(token.Word);
            string fixedWord = ApplyCase(token.Text, replacement ?? token.Word);
            if (token.SentenceStart && char.IsLower(fixedWord[0]))
                fixedWord = CapitalizeFirst(fixedWord);
            if (replacement is not null)
            {
                LogCorrection(token.Word, replacement);
                replaced++;
            }
            else if (fixedWord != token.Text)
            {
                recased++;
            }
            result.Append(token.Gap).Append(fixedWord);
        }
        result.Append(text[position..]);
        Emit(
            "FIX", $"removed={removed}", $"replaced={replaced}", $"recased={recased}:",
            result.ToString());
    }

    void Profile(string text)
    {
        var tokens = Token.Tokenize(text);
        int distinct = tokens.Select(token => token.Word).Distinct().Count();
        int unknown = tokens.Count(token => !IsKnown(token.Word));
        int sentences = tokens.Count(token => token.SentenceStart);
        string rate = "0.0";
        string average = "0.00";
        string longest = "-";
        if (tokens.Count > 0)
        {
            int characters = tokens.Sum(token => token.Text.Length);
            rate = DecimalText(100 * unknown, tokens.Count, 1);
            average = DecimalText(characters, tokens.Count, 2);
            longest = tokens.MaxBy(token => token.Text.Length)!.Word;
        }
        Emit(
            "PROFILE", $"words={tokens.Count}", $"distinct={distinct}", $"unknown={unknown}",
            $"rate={rate}", $"avglen={average}", $"longest={longest}", $"sentences={sentences}");
    }

    void Learn(string text)
    {
        RecordUndo("LEARN");
        int updated = 0;
        int added = 0;
        int skipped = 0;
        foreach (var token in Token.Tokenize(text))
        {
            if (token.Word.Length > MaxWordLength)
            {
                skipped++;
            }
            else if (dictionary.ContainsKey(token.Word))
            {
                dictionary[token.Word]++;
                updated++;
            }
            else
            {
                dictionary[token.Word] = 1;
                ignored.Remove(token.Word);
                added++;
            }
        }
        Emit("LEARN", $"updated={updated}", $"added={added}", $"skipped={skipped}");
    }

    void Suggest(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        if (IsKnown(word))
        {
            Emit("SUGGEST", word, "KNOWN");
        }
        else if (rules.TryGetValue(word, out string? target))
        {
            Emit("SUGGEST", word, "RULE", target);
        }
        else
        {
            var found = Candidates(word);
            var shown = found.Take(suggestionCount).Select(item => $"{item.Word}:{item.Distance}");
            Emit(["SUGGEST", word, $"found={found.Count}", .. shown]);
        }
    }

    void Dist(string[] arguments)
    {
        string first = WordArgument(arguments[0]);
        string second = WordArgument(arguments[1]);
        var (distance, operations) = EditDistance.Operations(first, second, keyboard);
        Emit(["DIST", first, second, $"{distance}", .. operations]);
    }

    void SoundexCode(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        Emit("SOUNDEX", word, Soundex.Encode(word));
    }

    void Sounds(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        string code = Soundex.Encode(word);
        var matches = FrequencyOrder()
            .Where(other => other != word && Soundex.Encode(other) == code)
            .ToList();
        Emit(["SOUNDS", word, code, $"count={matches.Count}", .. matches.Take(ReportSize)]);
    }

    void Split(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        var (ways, best) = Segment(word, dictionary);
        if (ways == 0)
            Emit("SPLIT", word, "ways=0", "->", "NONE");
        else
            Emit(["SPLIT", word, $"ways={ways}", "->", .. best!]);
    }

    void Prefix(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        int count = NumberArgument(arguments[1], 1, MaxListed);
        var matches = FrequencyOrder()
            .Where(other => other.StartsWith(word, StringComparison.Ordinal))
            .ToList();
        var shown = matches.Take(count).Select(other => $"{other}:{dictionary[other]}");
        Emit(["PREFIX", word, $"count={matches.Count}", .. shown]);
    }

    void Complete(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        int count = NumberArgument(arguments[1], 1, MaxListed);
        int threshold = Limit / 2;
        var matches = InDistanceOrder(
            dictionary.Keys
                .Select(other =>
                    (Word: other, Distance: EditDistance.Prefix(word, other, keyboard)))
                .Where(item => item.Distance <= threshold));
        var shown = matches.Take(count).Select(item => $"{item.Word}:{item.Distance}");
        Emit(["COMPLETE", word, $"count={matches.Count}", .. shown]);
    }

    void ListWords(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        int count = NumberArgument(arguments[1], 1, MaxListed);
        var matches = dictionary.Keys
            .Where(other => string.CompareOrdinal(other, word) >= 0)
            .Order(StringComparer.Ordinal)
            .ToList();
        var shown = matches.Take(count).Select(other => $"{other}:{dictionary[other]}");
        Emit(["LIST", word, $"count={matches.Count}", .. shown]);
    }

    void WordInfo(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        int frequency = RequireEntry(word);
        int rank = FrequencyOrder().IndexOf(word) + 1;
        Emit(
            "WORD", word, $"freq={frequency}", $"rank={rank}", $"soundex={Soundex.Encode(word)}",
            $"neighbors={Candidates(word).Count}");
    }

    void Add(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        int frequency = NumberArgument(arguments[1], 1, MaxFrequency);
        if (dictionary.ContainsKey(word))
            throw new CommandException($"DUPLICATE {word}");
        RecordUndo("ADD");
        dictionary[word] = frequency;
        ignored.Remove(word);
        Emit("ADD", word, $"{frequency}");
    }

    void Remove(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        int frequency = RequireEntry(word);
        RecordUndo("REMOVE");
        dictionary.Remove(word);
        Emit("REMOVE", word, $"{frequency}");
    }

    void Ignore(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        if (dictionary.ContainsKey(word))
            throw new CommandException($"IN DICTIONARY {word}");
        if (ignored.Contains(word))
            throw new CommandException($"ALREADY IGNORED {word}");
        RecordUndo("IGNORE");
        ignored.Add(word);
        Emit("IGNORE", word);
    }

    void Unignore(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        if (!ignored.Contains(word))
            throw new CommandException($"NOT IGNORED {word}");
        RecordUndo("UNIGNORE");
        ignored.Remove(word);
        Emit("UNIGNORE", word);
    }

    void Rule(string[] arguments)
    {
        string source = WordArgument(arguments[0]);
        string target = WordArgument(arguments[1]);
        if (dictionary.ContainsKey(source))
            throw new CommandException($"IN DICTIONARY {source}");
        if (!dictionary.ContainsKey(target))
            throw new CommandException($"NOT FOUND {target}");
        RecordUndo("RULE");
        bool existed = rules.TryGetValue(source, out string? previous);
        rules[source] = target;
        if (existed)
            Emit("RULE", source, target, "REPLACED", previous!);
        else
            Emit("RULE", source, target);
    }

    void Unrule(string[] arguments)
    {
        string word = WordArgument(arguments[0]);
        if (!rules.ContainsKey(word))
            throw new CommandException($"NO RULE {word}");
        RecordUndo("UNRULE");
        rules.Remove(word, out string? target);
        Emit("UNRULE", word, target!);
    }

    void ShowRules()
    {
        var shown = rules
            .OrderBy(rule => rule.Key, StringComparer.Ordinal)
            .Select(rule => $"{rule.Key}>{rule.Value}");
        Emit(["RULES", $"count={rules.Count}", .. shown]);
    }

    void KeyboardMode(string[] arguments)
    {
        string mode = arguments[0];
        if (mode is not ("ON" or "OFF"))
            throw new CommandException($"BAD MODE {mode}");
        keyboard = mode == "ON";
        Emit("KEYBOARD", mode);
    }

    void SetOption(string[] arguments)
    {
        string option = arguments[0];
        if (!OptionMaximums.TryGetValue(option, out int maximum))
            throw new CommandException($"BAD OPTION {option}");
        int value = NumberArgument(arguments[1], 1, maximum);
        if (option == "LIMIT")
            baseLimit = value;
        else
            suggestionCount = value;
        Emit("SET", option, $"{value}");
    }

    void Undo()
    {
        if (undoHistory.Count == 0)
            throw new CommandException("NOTHING TO UNDO");
        var record = undoHistory[^1];
        undoHistory.RemoveAt(undoHistory.Count - 1);
        dictionary = record.Dictionary;
        ignored = record.Ignored;
        rules = record.Rules;
        Emit("UNDO", record.Name);
    }

    void Report()
    {
        var entries = unknownLog
            .OrderByDescending(entry => entry.Value)
            .ThenBy(entry => entry.Key, StringComparer.Ordinal)
            .ToList();
        var shown = entries.Take(ReportSize).Select(entry => $"{entry.Key}:{entry.Value}");
        Emit(["REPORT", $"distinct={entries.Count}", .. shown]);
    }

    void History()
    {
        var entries = correctionLog
            .OrderByDescending(entry => entry.Value)
            .ThenBy(entry => entry.Key.Word, StringComparer.Ordinal)
            .ThenBy(entry => entry.Key.Correction, StringComparer.Ordinal)
            .ToList();
        var shown = entries
            .Take(ReportSize)
            .Select(entry => $"{entry.Key.Word}>{entry.Key.Correction}:{entry.Value}");
        Emit(["HISTORY", $"distinct={entries.Count}", .. shown]);
    }

    void Stats()
    {
        string top = FrequencyOrder()[0];
        int characters = dictionary.Keys.Sum(word => word.Length);
        Emit(
            "STATS", $"words={dictionary.Count}", $"total={dictionary.Values.Sum()}",
            $"avglen={DecimalText(characters, dictionary.Count, 2)}",
            $"top={top}:{dictionary[top]}",
            $"ignored={ignored.Count}", $"rules={rules.Count}",
            $"keyboard={(keyboard ? "ON" : "OFF")}", $"limit={Limit}",
            $"suggestions={suggestionCount}", $"undo={undoHistory.Count}");
        Emit(["SESSION", .. CounterNames.Select(name => $"{name}={counters[name]}")]);
    }

    public void Execute(string line)
    {
        int space = line.IndexOf(' ');
        string name = space < 0 ? line : line[..space];
        string? rest = space < 0 ? null : line[(space + 1)..];
        try
        {
            if (textCommands.TryGetValue(name, out var runText))
            {
                if (rest is null)
                    throw new CommandException($"BAD ARGUMENTS {name}");
                runText(rest);
            }
            else if (commands.TryGetValue(name, out var command))
            {
                string[] arguments = rest is null ? [] : rest.Split(' ');
                if (arguments.Length != command.Arity)
                    throw new CommandException($"BAD ARGUMENTS {name}");
                command.Run(arguments);
            }
            else
            {
                throw new CommandException($"UNKNOWN COMMAND {name}");
            }
        }
        catch (CommandException error)
        {
            Emit($"ERROR {error.Message}");
        }
    }
}
