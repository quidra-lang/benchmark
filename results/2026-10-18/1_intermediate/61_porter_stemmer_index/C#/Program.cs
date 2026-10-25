using System.Text;
using System.Text.RegularExpressions;

var lines = new List<string>();
while (Console.ReadLine() is { } inputLine)
{
    lines.Add(inputLine);
}

var stopwords = lines[0].Split(' ', StringSplitOptions.RemoveEmptyEntries).Skip(1);
var engine = new SearchEngine([.. stopwords]);
var index = 1;
while (lines[index].StartsWith("DOC ", StringComparison.Ordinal))
{
    var document = engine.AddDocument(int.Parse(lines[index][4..]));
    index++;
    while (lines[index] != "ENDDOC")
    {
        document.AddLine(lines[index]);
        index++;
    }
    index++;
}
foreach (var command in lines.Skip(index).TakeWhile(text => text != "END"))
{
    engine.Execute(command);
}
Console.Out.Write(string.Join("\n", engine.Output) + "\n");

static class Patterns
{
    public static readonly Regex Token = new("[A-Za-z]+");
    public static readonly Regex Word = new("^[A-Za-z]{1,30}$");
    public static readonly Regex Number = new("^[0-9]{1,7}$");
    public static readonly Regex PrefixTerm = new(@"^[A-Za-z]{1,30}\*$");
    public static readonly Regex Lexeme = new("[()]|[^ ()]+");
}

class CommandException(string message) : Exception(message);

static class Porter
{
    const string Vowels = "aeiou";
    static readonly string[] StepNames = ["1a", "1b", "1c", "2", "3", "4", "5a", "5b"];
    static readonly string[] Step4Suffixes =
    [
        "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
        "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize",
    ];

    static readonly Dictionary<string, Rule[]> RuleTables = new()
    {
        ["1a"] = RulesWith(_ => true, ("sses", "ss"), ("ies", "i"), ("ss", "ss"), ("s", "")),
        ["1b"] =
        [
            new("eed", "ee", MeasureAboveZero), new("ed", "", HasVowel), new("ing", "", HasVowel),
        ],
        ["1c"] = [new("y", "i", HasVowel)],
        ["2"] = RulesWith(
            MeasureAboveZero,
            ("ational", "ate"), ("tional", "tion"), ("enci", "ence"), ("anci", "ance"),
            ("izer", "ize"), ("abli", "able"), ("alli", "al"), ("entli", "ent"), ("eli", "e"),
            ("ousli", "ous"), ("ization", "ize"), ("ation", "ate"), ("ator", "ate"),
            ("alism", "al"), ("iveness", "ive"), ("fulness", "ful"), ("ousness", "ous"),
            ("aliti", "al"), ("iviti", "ive"), ("biliti", "ble")),
        ["3"] = RulesWith(
            MeasureAboveZero,
            ("icate", "ic"), ("ative", ""), ("alize", "al"), ("iciti", "ic"),
            ("ical", "ic"), ("ful", ""), ("ness", "")),
        ["4"] =
        [
            .. Step4Suffixes.Select(suffix =>
                new Rule(suffix, "", suffix == "ion" ? IonCondition : MeasureAboveOne)),
        ],
        ["5a"] = [new("e", "", FinalECondition)],
    };

    static readonly Dictionary<string, string> Cache = [];

    sealed record Rule(string Suffix, string Replacement, Func<string, bool> Condition);

    static Rule[] RulesWith(
        Func<string, bool> condition, params (string Suffix, string Replacement)[] rules) =>
        [.. rules.Select(rule => new Rule(rule.Suffix, rule.Replacement, condition))];

    static bool EndsWith(string word, string suffix) =>
        word.EndsWith(suffix, StringComparison.Ordinal);

    public static string LetterPattern(string word)
    {
        var kinds = new StringBuilder();
        for (var index = 0; index < word.Length; index++)
        {
            var letter = word[index];
            var vowel = Vowels.Contains(letter)
                || (letter == 'y' && index > 0 && kinds[index - 1] == 'C');
            kinds.Append(vowel ? 'V' : 'C');
        }
        return kinds.ToString();
    }

    public static int Measure(string word) => LetterPattern(word).Split("VC").Length - 1;

    public static bool HasVowel(string word) => LetterPattern(word).Contains('V');

    public static bool EndsDouble(string word) =>
        EndsWith(LetterPattern(word), "CC") && word[^1] == word[^2];

    public static bool EndsCvc(string word) =>
        EndsWith(LetterPattern(word), "CVC") && !"wxy".Contains(word[^1]);

    static bool MeasureAboveZero(string remainder) => Measure(remainder) > 0;

    static bool MeasureAboveOne(string remainder) => Measure(remainder) > 1;

    static bool IonCondition(string remainder) =>
        Measure(remainder) > 1 && (remainder.EndsWith('s') || remainder.EndsWith('t'));

    static bool FinalECondition(string remainder)
    {
        var value = Measure(remainder);
        return value > 1 || (value == 1 && !EndsCvc(remainder));
    }

    static (string Word, string? Suffix) ApplyRules(string word, Rule[] rules)
    {
        var rule = rules
            .Where(candidate => EndsWith(word, candidate.Suffix))
            .MaxBy(candidate => candidate.Suffix.Length);
        if (rule is null)
        {
            return (word, null);
        }
        var remainder = word[..^rule.Suffix.Length];
        if (!rule.Condition(remainder))
        {
            return (word, null);
        }
        return (remainder + rule.Replacement, rule.Suffix);
    }

    static string TidyStep1b(string word)
    {
        if (EndsWith(word, "at") || EndsWith(word, "bl") || EndsWith(word, "iz"))
        {
            return word + "e";
        }
        if (EndsDouble(word) && !"lsz".Contains(word[^1]))
        {
            return word[..^1];
        }
        if (Measure(word) == 1 && EndsCvc(word))
        {
            return word + "e";
        }
        return word;
    }

    static string ApplyStep(string name, string word)
    {
        if (name == "5b")
        {
            return Measure(word) > 1 && EndsDouble(word) && word.EndsWith('l') ? word[..^1] : word;
        }
        var (result, suffix) = ApplyRules(word, RuleTables[name]);
        return name == "1b" && suffix is "ed" or "ing" ? TidyStep1b(result) : result;
    }

    public static (string Stem, List<(string Name, string Result)> Changes) StemmingSteps(
        string word)
    {
        var changes = new List<(string Name, string Result)>();
        if (word.Length > 2)
        {
            foreach (var name in StepNames)
            {
                var result = ApplyStep(name, word);
                if (result != word)
                {
                    changes.Add((name, result));
                }
                word = result;
            }
        }
        return (word, changes);
    }

    public static string Stem(string word)
    {
        if (!Cache.TryGetValue(word, out var stem))
        {
            stem = StemmingSteps(word).Stem;
            Cache[word] = stem;
        }
        return stem;
    }
}

record Token(string Text, int Line, int Position, int Start)
{
    public string Form { get; } = Text.ToLowerInvariant();

    public int End => Start + Text.Length;
}

class Document(int number)
{
    public int Number => number;

    public List<string> Lines { get; } = [];

    public List<Token> Tokens { get; } = [];

    public List<Token> AddLine(string text)
    {
        Lines.Add(text);
        var added = Patterns.Token.Matches(text)
            .Select((match, offset) =>
                new Token(match.Value, Lines.Count, Tokens.Count + offset + 1, match.Index))
            .ToList();
        Tokens.AddRange(added);
        return added;
    }

    public List<Token> LineTokens(int lineNumber) =>
        [.. Tokens.Where(token => token.Line == lineNumber)];

    public string Reference(Token token) => $"{Number}:{token.Line}:{token.Position}";
}

enum LexemeKind
{
    And,
    Or,
    Not,
    Open,
    Close,
    Term,
    Prefix,
}

record Lexeme(LexemeKind Kind, string Spelling);

class QueryParser(List<Lexeme> items, Dictionary<int, HashSet<string>> stemSets)
{
    int position;

    LexemeKind? Peek() => position < items.Count ? items[position].Kind : null;

    Lexeme Take() => position < items.Count
        ? items[position++]
        : throw new CommandException("SYNTAX");

    public (string Canonical, HashSet<int> Documents) Parse()
    {
        var result = Expression();
        if (position < items.Count)
        {
            throw new CommandException("SYNTAX");
        }
        return result;
    }

    (string Canonical, HashSet<int> Documents) Expression()
    {
        var (canonical, documents) = Conjunction();
        while (Peek() == LexemeKind.Or)
        {
            position++;
            var (right, rightDocuments) = Conjunction();
            canonical = $"({canonical} OR {right})";
            documents.UnionWith(rightDocuments);
        }
        return (canonical, documents);
    }

    (string Canonical, HashSet<int> Documents) Conjunction()
    {
        var (canonical, documents) = Negation();
        while (Peek() is LexemeKind.And or LexemeKind.Not or LexemeKind.Open or LexemeKind.Term
            or LexemeKind.Prefix)
        {
            if (Peek() == LexemeKind.And)
            {
                position++;
            }
            var (right, rightDocuments) = Negation();
            canonical = $"({canonical} AND {right})";
            documents.IntersectWith(rightDocuments);
        }
        return (canonical, documents);
    }

    (string Canonical, HashSet<int> Documents) Negation()
    {
        if (Peek() == LexemeKind.Not)
        {
            position++;
            var (canonical, documents) = Negation();
            var complement = stemSets.Keys.Where(number => !documents.Contains(number)).ToHashSet();
            return ($"(NOT {canonical})", complement);
        }
        return Element();
    }

    (string Canonical, HashSet<int> Documents) Element()
    {
        var item = Take();
        switch (item.Kind)
        {
            case LexemeKind.Open:
            {
                var result = Expression();
                if (Take().Kind != LexemeKind.Close)
                {
                    throw new CommandException("SYNTAX");
                }
                return result;
            }
            case LexemeKind.Term:
            {
                var stem = Porter.Stem(item.Spelling);
                return (stem, Matching(stems => stems.Contains(stem)));
            }
            case LexemeKind.Prefix:
            {
                var documents = Matching(stems => stems.Any(candidate =>
                    candidate.StartsWith(item.Spelling, StringComparison.Ordinal)));
                return ($"{item.Spelling}*", documents);
            }
            default:
                throw new CommandException("SYNTAX");
        }
    }

    HashSet<int> Matching(Func<HashSet<string>, bool> predicate) =>
        stemSets.Where(pair => predicate(pair.Value)).Select(pair => pair.Key).ToHashSet();
}

readonly record struct Fraction(int Numerator, int Denominator) : IComparable<Fraction>
{
    public static Fraction Create(int numerator, int denominator)
    {
        var divisor = Gcd(numerator, denominator);
        return new Fraction(numerator / divisor, denominator / divisor);
    }

    static int Gcd(int a, int b) => b == 0 ? a : Gcd(b, a % b);

    public int CompareTo(Fraction other) =>
        (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);

    public override string ToString() => $"{Numerator}/{Denominator}";
}

class SearchEngine
{
    const int KwicWidth = 30;
    const int MaxCount = 100;
    const int MaxDocumentNumber = 999;
    const int MaxLineNumber = 999;

    readonly HashSet<string> stopwords;
    readonly SortedDictionary<int, Document> documents = [];
    readonly Dictionary<string, (int Minimum, int Maximum, Action<string[]> Handler)> handlers;

    public SearchEngine(HashSet<string> stopwords)
    {
        this.stopwords = stopwords;
        handlers = new()
        {
            ["STEM"] = (1, 10, StemWords),
            ["STEPS"] = (1, 1, ShowSteps),
            ["MEASURE"] = (1, 1, ShowMeasure),
            ["INDEX"] = (0, 1, ShowIndex),
            ["SEARCH"] = (1, 1, Search),
            ["PHRASE"] = (2, 10, Phrase),
            ["NEAR"] = (3, 3, Near),
            ["TOP"] = (1, 2, Top),
            ["KWIC"] = (1, 1, Kwic),
            ["TF"] = (2, 2, TermFrequency),
            ["DF"] = (1, 1, DocumentFrequency),
            ["VARIANTS"] = (1, 1, Variants),
            ["SIMILAR"] = (2, 2, Similar),
            ["RANK"] = (2, 11, Rank),
            ["INFO"] = (1, 1, Info),
            ["LINE"] = (2, 2, ShowLine),
            ["STATS"] = (0, 0, Stats),
            ["STOP"] = (1, 1, Stop),
            ["UNSTOP"] = (1, 1, Unstop),
            ["APPEND"] = (2, 2, Append),
            ["DELETE"] = (1, 1, Delete),
        };
    }

    public List<string> Output { get; } = [];

    void Emit(params IEnumerable<object> parts) => Output.Add(string.Join(" ", parts));

    public Document AddDocument(int number)
    {
        var document = new Document(number);
        documents[number] = document;
        return document;
    }

    static string YesNo(bool flag) => flag ? "YES" : "NO";

    static string WordArgument(string text) => Patterns.Word.IsMatch(text)
        ? text.ToLowerInvariant()
        : throw new CommandException($"BAD WORD {text}");

    static int NumberArgument(string text, int minimum, int maximum)
    {
        if (!Patterns.Number.IsMatch(text))
        {
            throw new CommandException($"BAD NUMBER {text}");
        }
        var value = int.Parse(text);
        if (value < minimum || value > maximum)
        {
            throw new CommandException($"BAD NUMBER {text}");
        }
        return value;
    }

    static string[] SplitArguments(string name, string rest) => name switch
    {
        "SEARCH" => [rest],
        "APPEND" => rest.Split(' ', 2),
        _ => rest.Split(' '),
    };

    static IEnumerable<KeyValuePair<string, int>> ByCount(Dictionary<string, int> counts) =>
        counts
            .OrderByDescending(pair => pair.Value)
            .ThenBy(pair => pair.Key, StringComparer.Ordinal);

    static int DocumentCount(List<(Document Document, Token Token)> occurrences) =>
        occurrences.Select(occurrence => occurrence.Document.Number).Distinct().Count();

    static int? ClosestDistance(List<int> positions, List<int> others, bool sameStem)
    {
        IEnumerable<int> gaps;
        if (sameStem)
        {
            gaps = positions.Zip(positions.Skip(1), (earlier, later) => later - earlier);
        }
        else
        {
            var merged = positions
                .Select(position => (Position: position, Kind: 0))
                .Concat(others.Select(other => (Position: other, Kind: 1)))
                .OrderBy(entry => entry.Position)
                .ToList();
            gaps = merged
                .Zip(merged.Skip(1))
                .Where(pair => pair.First.Kind != pair.Second.Kind)
                .Select(pair => pair.Second.Position - pair.First.Position);
        }
        return gaps.Select(gap => (int?)gap).Min();
    }

    static Lexeme Classify(string text) => text switch
    {
        "AND" => new(LexemeKind.And, text),
        "OR" => new(LexemeKind.Or, text),
        "NOT" => new(LexemeKind.Not, text),
        "(" => new(LexemeKind.Open, text),
        ")" => new(LexemeKind.Close, text),
        _ when Patterns.Word.IsMatch(text) => new(LexemeKind.Term, text.ToLowerInvariant()),
        _ when Patterns.PrefixTerm.IsMatch(text) =>
            new(LexemeKind.Prefix, text[..^1].ToLowerInvariant()),
        _ => throw new CommandException($"BAD TERM {text}"),
    };

    bool IsIndexed(Token token) => !stopwords.Contains(token.Form);

    IEnumerable<Token> IndexedTokens(Document document) => document.Tokens.Where(IsIndexed);

    Dictionary<string, int> TermFrequencies(Document document) =>
        IndexedTokens(document).CountBy(token => Porter.Stem(token.Form)).ToDictionary();

    HashSet<string> StemSet(Document document) =>
        IndexedTokens(document).Select(token => Porter.Stem(token.Form)).ToHashSet();

    Dictionary<string, int> TotalFrequencies() =>
        documents.Values.SelectMany(IndexedTokens).CountBy(token => Porter.Stem(token.Form))
            .ToDictionary();

    Dictionary<string, List<(Document Document, Token Token)>> OccurrenceMap() =>
        documents.Values
            .SelectMany(document => IndexedTokens(document).Select(token => (document, token)))
            .GroupBy(occurrence => Porter.Stem(occurrence.token.Form))
            .ToDictionary(group => group.Key, group => group.ToList());

    List<(Document Document, Token Token)> Occurrences(string stem) =>
        OccurrenceMap().GetValueOrDefault(stem, []);

    List<int> StemPositions(Document document, string stem) =>
    [
        .. IndexedTokens(document)
            .Where(token => Porter.Stem(token.Form) == stem)
            .Select(token => token.Position),
    ];

    int FormCount(string form) =>
        documents.Values.Sum(document => document.Tokens.Count(token => token.Form == form));

    bool TokenMatches(Token token, string target) =>
        target == "?" || (IsIndexed(token) && Porter.Stem(token.Form) == target);

    string DescribeToken(Token token) =>
        IsIndexed(token) ? $"{token.Form}/{Porter.Stem(token.Form)}" : $"{token.Form}/-";

    string TermArgument(string text)
    {
        var word = WordArgument(text);
        if (stopwords.Contains(word))
        {
            throw new CommandException($"STOPWORD {word}");
        }
        return Porter.Stem(word);
    }

    Document DocumentArgument(string text)
    {
        var number = NumberArgument(text, 1, MaxDocumentNumber);
        return documents.GetValueOrDefault(number)
            ?? throw new CommandException($"NO DOC {number}");
    }

    void StemWords(string[] arguments)
    {
        var words = arguments.Select(WordArgument).ToList();
        Emit(["STEM", .. words.Select(word => $"{word}:{Porter.Stem(word)}")]);
    }

    void ShowSteps(string[] arguments)
    {
        var word = WordArgument(arguments[0]);
        var changes = Porter.StemmingSteps(word).Changes;
        if (changes.Count == 0)
        {
            Emit("STEPS", word, "NONE");
        }
        else
        {
            Emit(["STEPS", word, .. changes.Select(change => $"{change.Name}:{change.Result}")]);
        }
    }

    void ShowMeasure(string[] arguments)
    {
        var word = WordArgument(arguments[0]);
        Emit(
            "MEASURE", word, Porter.LetterPattern(word), $"m={Porter.Measure(word)}",
            $"vowel={YesNo(Porter.HasVowel(word))}", $"double={YesNo(Porter.EndsDouble(word))}",
            $"cvc={YesNo(Porter.EndsCvc(word))}");
    }

    void ShowIndex(string[] arguments)
    {
        var prefix = arguments.Length > 0 ? WordArgument(arguments[0]) : "";
        var occurrences = OccurrenceMap();
        var stems = occurrences.Keys
            .Where(stem => stem.StartsWith(prefix, StringComparison.Ordinal))
            .Order(StringComparer.Ordinal)
            .ToList();
        Emit("INDEX", $"stems={stems.Count}");
        foreach (var stem in stems)
        {
            var found = occurrences[stem];
            Emit(
            [
                stem, $"df={DocumentCount(found)}",
                .. found.Select(occurrence => occurrence.Document.Reference(occurrence.Token)),
            ]);
        }
    }

    void Search(string[] arguments)
    {
        var items = Patterns.Lexeme.Matches(arguments[0]).Select(match => Classify(match.Value))
            .ToList();
        var stemSets = documents.Values.ToDictionary(document => document.Number, StemSet);
        var (canonical, matches) = new QueryParser(items, stemSets).Parse();
        var stopword = items.FirstOrDefault(item =>
            item.Kind == LexemeKind.Term && stopwords.Contains(item.Spelling));
        if (stopword is not null)
        {
            throw new CommandException($"STOPWORD {stopword.Spelling}");
        }
        Emit(["SEARCH", canonical, $"count={matches.Count}", .. matches.Order()]);
    }

    void Phrase(string[] arguments)
    {
        var words = arguments.Select(WordArgument).ToList();
        if (words.All(stopwords.Contains))
        {
            throw new CommandException("STOPWORDS ONLY");
        }
        var targets = words.Select(word => stopwords.Contains(word) ? "?" : Porter.Stem(word))
            .ToList();
        var matches = new List<string>();
        foreach (var document in documents.Values)
        {
            var tokens = document.Tokens;
            for (var start = 0; start <= tokens.Count - targets.Count; start++)
            {
                if (Enumerable.Range(0, targets.Count)
                    .All(offset => TokenMatches(tokens[start + offset], targets[offset])))
                {
                    matches.Add(document.Reference(tokens[start]));
                }
            }
        }
        Emit([$"PHRASE \"{string.Join(" ", targets)}\"", $"matches={matches.Count}", .. matches]);
    }

    void Near(string[] arguments)
    {
        var first = TermArgument(arguments[0]);
        var second = TermArgument(arguments[1]);
        var limit = NumberArgument(arguments[2], 1, MaxCount);
        var found = new List<string>();
        foreach (var document in documents.Values)
        {
            var distance = ClosestDistance(
                StemPositions(document, first), StemPositions(document, second), first == second);
            if (distance is int value && value <= limit)
            {
                found.Add($"{document.Number}:{value}");
            }
        }
        Emit(["NEAR", first, second, limit, $"count={found.Count}", .. found]);
    }

    void Top(string[] arguments)
    {
        var limit = NumberArgument(arguments[0], 1, MaxCount);
        Dictionary<string, int> counts;
        string header;
        if (arguments.Length == 2)
        {
            var document = DocumentArgument(arguments[1]);
            counts = TermFrequencies(document);
            header = $"TOP {limit} doc={document.Number}";
        }
        else
        {
            counts = TotalFrequencies();
            header = $"TOP {limit}";
        }
        var ranked = ByCount(counts).Take(limit);
        Emit([header, .. ranked.Select(pair => $"{pair.Key}:{pair.Value}")]);
    }

    void Kwic(string[] arguments)
    {
        var stem = TermArgument(arguments[0]);
        var found = Occurrences(stem);
        Emit("KWIC", stem, $"count={found.Count}");
        foreach (var (document, token) in found)
        {
            var text = document.Lines[token.Line - 1];
            var before = text[Math.Max(0, token.Start - KwicWidth)..token.Start].PadLeft(KwicWidth);
            var after = text[token.End..Math.Min(text.Length, token.End + KwicWidth)]
                .PadRight(KwicWidth);
            Emit($"|{before}[{token.Text}]{after}|", document.Reference(token));
        }
    }

    void TermFrequency(string[] arguments)
    {
        var document = DocumentArgument(arguments[0]);
        var stem = TermArgument(arguments[1]);
        Emit("TF", document.Number, stem, TermFrequencies(document).GetValueOrDefault(stem));
    }

    void DocumentFrequency(string[] arguments)
    {
        var stem = TermArgument(arguments[0]);
        Emit("DF", stem, DocumentCount(Occurrences(stem)));
    }

    void Variants(string[] arguments)
    {
        var stem = TermArgument(arguments[0]);
        var forms = Occurrences(stem)
            .CountBy(occurrence => occurrence.Token.Form)
            .OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .ToList();
        Emit(
        [
            "VARIANTS", stem, $"count={forms.Count}",
            .. forms.Select(pair => $"{pair.Key}:{pair.Value}"),
        ]);
    }

    void Similar(string[] arguments)
    {
        var document = DocumentArgument(arguments[0]);
        var limit = NumberArgument(arguments[1], 1, MaxCount);
        var stems = StemSet(document);
        var scores = new List<(Fraction Score, int Number)>();
        foreach (var other in documents.Values)
        {
            if (other == document)
            {
                continue;
            }
            var otherStems = StemSet(other);
            var union = stems.Union(otherStems).Count();
            var score = union > 0
                ? Fraction.Create(stems.Intersect(otherStems).Count(), union)
                : new Fraction(0, 1);
            scores.Add((score, other.Number));
        }
        var ranked = scores
            .OrderByDescending(entry => entry.Score)
            .ThenBy(entry => entry.Number)
            .Take(limit);
        Emit(
        [
            "SIMILAR", document.Number,
            .. ranked.Select(entry => $"{entry.Number}:{entry.Score}"),
        ]);
    }

    void Rank(string[] arguments)
    {
        var limit = NumberArgument(arguments[0], 1, MaxCount);
        var query = arguments.Skip(1).Select(TermArgument).ToHashSet();
        var ranked = new List<(int Matched, int Total, int Number)>();
        foreach (var document in documents.Values)
        {
            var counts = TermFrequencies(document);
            var matched = query.Count(counts.ContainsKey);
            var total = query.Sum(stem => counts.GetValueOrDefault(stem));
            if (matched > 0)
            {
                ranked.Add((matched, total, document.Number));
            }
        }
        var selected = ranked
            .OrderByDescending(entry => entry.Matched)
            .ThenByDescending(entry => entry.Total)
            .ThenBy(entry => entry.Number)
            .Take(limit);
        Emit(
        [
            $"RANK count={ranked.Count}",
            .. selected.Select(entry => $"{entry.Number}:{entry.Matched}:{entry.Total}"),
        ]);
    }

    void Info(string[] arguments)
    {
        var document = DocumentArgument(arguments[0]);
        var counts = TermFrequencies(document);
        var top = "-";
        if (counts.Count > 0)
        {
            var (stem, count) = ByCount(counts).First();
            top = $"{stem}:{count}";
        }
        Emit(
            "INFO", document.Number, $"lines={document.Lines.Count}",
            $"tokens={document.Tokens.Count}", $"indexed={counts.Values.Sum()}",
            $"stems={counts.Count}", $"top={top}");
    }

    void ShowLine(string[] arguments)
    {
        var document = DocumentArgument(arguments[0]);
        var lineNumber = NumberArgument(arguments[1], 1, MaxLineNumber);
        if (lineNumber > document.Lines.Count)
        {
            throw new CommandException($"NO LINE {document.Number}:{lineNumber}");
        }
        var tokens = document.LineTokens(lineNumber);
        Emit(
        [
            $"LINE {document.Number}:{lineNumber}", $"tokens={tokens.Count}",
            .. tokens.Select(DescribeToken),
        ]);
    }

    void Stats(string[] arguments)
    {
        Emit(
            "STATS", $"docs={documents.Count}",
            $"lines={documents.Values.Sum(document => document.Lines.Count)}",
            $"tokens={documents.Values.Sum(document => document.Tokens.Count)}",
            $"indexed={documents.Values.Sum(document => IndexedTokens(document).Count())}",
            $"stems={TotalFrequencies().Count}", $"stopwords={stopwords.Count}");
    }

    void Stop(string[] arguments)
    {
        var word = WordArgument(arguments[0]);
        if (!stopwords.Add(word))
        {
            throw new CommandException($"ALREADY STOPWORD {word}");
        }
        Emit("STOP", word, $"unindexed={FormCount(word)}");
    }

    void Unstop(string[] arguments)
    {
        var word = WordArgument(arguments[0]);
        if (!stopwords.Remove(word))
        {
            throw new CommandException($"NOT STOPWORD {word}");
        }
        Emit("UNSTOP", word, $"indexed={FormCount(word)}");
    }

    void Append(string[] arguments)
    {
        var number = NumberArgument(arguments[0], 1, MaxDocumentNumber);
        var created = !documents.ContainsKey(number);
        var document = created ? AddDocument(number) : documents[number];
        var tokens = document.AddLine(arguments[1]);
        Emit(
            "APPEND", number, $"line={document.Lines.Count}", $"tokens={tokens.Count}",
            $"indexed={tokens.Count(IsIndexed)}", $"new={YesNo(created)}");
    }

    void Delete(string[] arguments)
    {
        var document = DocumentArgument(arguments[0]);
        documents.Remove(document.Number);
        Emit(
            "DELETE", document.Number, $"lines={document.Lines.Count}",
            $"tokens={document.Tokens.Count}");
    }

    public void Execute(string line)
    {
        var separator = line.IndexOf(' ');
        var name = separator < 0 ? line : line[..separator];
        try
        {
            if (!handlers.TryGetValue(name, out var command))
            {
                throw new CommandException($"UNKNOWN COMMAND {name}");
            }
            string[] arguments = separator < 0 ? [] : SplitArguments(name, line[(separator + 1)..]);
            if (arguments.Length < command.Minimum || arguments.Length > command.Maximum)
            {
                throw new CommandException($"BAD ARGUMENTS {name}");
            }
            command.Handler(arguments);
        }
        catch (CommandException error)
        {
            Emit("ERROR", error.Message);
        }
    }
}
