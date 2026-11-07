using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using static TextRules;

enum Style { APA, IEEE, CHICAGO, MLA }

sealed class CommandError(string message) : Exception(message);
sealed class LoadError(int line, string message) : Exception(message)
{
    public int Line { get; } = line;
}

static class TextRules
{
    public static readonly string[] KnownFields =
        "author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note".Split(' ');
    public static readonly HashSet<string> SmallWords = new(
        "a an and as at but by for from in into nor of on or over per so the to up via with yet".Split(' '), StringComparer.Ordinal);
    public static readonly string[] MonthNames =
        "January February March April May June July August September October November December".Split(' ');
    public static readonly string[] MonthShort =
        "Jan. Feb. Mar. Apr. May June July Aug. Sep. Oct. Nov. Dec.".Split(' ');

    public static bool Letter(char c) => c is >= 'a' and <= 'z' or >= 'A' and <= 'Z';
    public static bool Digit(char c) => c is >= '0' and <= '9';
    public static bool Digits(string text) => text.Length > 0 && text.All(Digit);
    public static char Lower(char c) => c is >= 'A' and <= 'Z' ? (char)(c + 32) : c;
    public static char Upper(char c) => c is >= 'a' and <= 'z' ? (char)(c - 32) : c;
    public static string Lower(string text) => new(text.Select(Lower).ToArray());
    public static string Plain(string text) => text.Replace("{", "").Replace("}", "");
    public static string Letters(string text) => new(text.Where(Letter).ToArray());

    public static List<string> SplitTop(string text, string separator)
    {
        List<string> result = [];
        int depth = 0, start = 0, i = 0;
        while (i < text.Length)
        {
            if (depth == 0 && text.AsSpan(i).StartsWith(separator, StringComparison.Ordinal))
            {
                result.Add(text[start..i]);
                i += separator.Length;
                start = i;
                continue;
            }
            if (text[i] == '{') depth++;
            if (text[i] == '}') depth--;
            i++;
        }
        result.Add(text[start..]);
        return result;
    }

    static bool Accent(string text, int i, out char value, out int length)
    {
        value = default;
        length = 0;
        if (i + 1 >= text.Length || text[i] != '\\') return false;
        char command = text[i + 1];
        if (command == '&') { value = '&'; length = 2; return true; }
        bool symbol = "'\"`^~=.".Contains(command);
        if (i + 4 < text.Length && (symbol || "cuvH".Contains(command)) &&
            text[i + 2] == '{' && Letter(text[i + 3]) && text[i + 4] == '}')
        {
            value = text[i + 3]; length = 5; return true;
        }
        if (symbol && i + 2 < text.Length && Letter(text[i + 2]))
        {
            value = text[i + 2]; length = 3; return true;
        }
        return false;
    }

    public static string Normalize(string text)
    {
        StringBuilder accents = new();
        for (int i = 0; i < text.Length;)
        {
            if (text[i] == '{' && Accent(text, i + 1, out char wrapped, out int count) &&
                i + count + 1 < text.Length && text[i + count + 1] == '}')
            {
                accents.Append(wrapped);
                i += count + 2;
            }
            else if (Accent(text, i, out char value, out int length))
            {
                accents.Append(value);
                i += length;
            }
            else accents.Append(text[i++]);
        }
        StringBuilder result = new();
        bool space = false;
        foreach (char c in accents.ToString())
        {
            if (c is ' ' or '~') space = result.Length > 0;
            else
            {
                if (space) result.Append(' ');
                result.Append(c);
                space = false;
            }
        }
        return result.ToString();
    }

    static string LowerOutside(string word)
    {
        char[] result = word.ToCharArray();
        int depth = 0;
        for (int i = 0; i < result.Length; i++)
        {
            if (result[i] == '{') depth++;
            else if (result[i] == '}') depth--;
            else if (depth == 0) result[i] = Lower(result[i]);
        }
        return new string(result);
    }

    public static string Title(string text, Style style)
    {
        if (style == Style.IEEE) return text;
        if (style == Style.APA)
        {
            char[] result = text.ToCharArray();
            int depth = 0;
            for (int i = 0; i < result.Length; i++)
            {
                if (text[i] == '{') depth++;
                else if (text[i] == '}') depth--;
                else if (depth == 0 && Letter(text[i]))
                    result[i] = i == 0 || i >= 2 && text[i - 2] == ':' && text[i - 1] == ' ' ? Upper(text[i]) : Lower(text[i]);
            }
            return new string(result);
        }
        List<string> words = SplitTop(text, " ");
        for (int i = 0; i < words.Count; i++)
        {
            string word = words[i];
            if (word.StartsWith('{')) continue;
            if (i > 0 && i + 1 < words.Count && !words[i - 1].EndsWith(':') && SmallWords.Contains(Lower(Letters(word))))
            {
                words[i] = LowerOutside(word);
                continue;
            }
            int depth = 0;
            for (int j = 0; j < word.Length; j++)
            {
                if (word[j] == '{') depth++;
                else if (word[j] == '}') depth--;
                else if (Letter(word[j]))
                {
                    if (depth == 0) words[i] = word[..j] + Upper(word[j]) + word[(j + 1)..];
                    break;
                }
            }
        }
        return string.Join(' ', words);
    }

    public static string ListNames(string[] names, string conjunction, bool listB = false)
    {
        if (names.Length == 1) return names[0];
        if (listB && names.Length == 2) return names[0] + " " + conjunction + " " + names[1];
        return string.Join(", ", names[..^1]) + ", " + conjunction + " " + names[^1];
    }
}

sealed record Person(string First, string Von, string Last, string Jr)
{
    public string Surname => Plain(Von.Length == 0 ? Last : Von + " " + Last);
    public string Initials => string.Join(' ', Plain(First).Split(' ', StringSplitOptions.RemoveEmptyEntries)
        .Select(word => string.Join('-', word.Split('-').Select(piece => Upper(piece.First(Letter)) + "."))));

    public string Format(bool inverted, bool initials)
    {
        string given = initials ? Initials : Plain(First);
        string result = Surname;
        if (First.Length > 0) result = inverted ? result + ", " + given : given + " " + result;
        if (Jr.Length > 0) result += ", " + Plain(Jr);
        return result;
    }

    public static Person Parse(string text)
    {
        string[] parts = SplitTop(text, ",").Select(part => part.Trim(' ')).ToArray();
        List<string> words = SplitTop(parts[0], " ");
        int firstLower = -1, lastLower = -1;
        for (int i = 0; i + 1 < words.Count; i++)
            if (words[i][0] is >= 'a' and <= 'z')
            {
                if (firstLower < 0) firstLower = i;
                lastLower = i;
            }
        string Join(int first, int end) => string.Join(' ', words.Skip(first).Take(end - first));
        if (parts.Length == 1)
            return firstLower < 0
                ? new Person(Join(0, words.Count - 1), "", words[^1], "")
                : new Person(Join(0, firstLower), Join(firstLower, lastLower + 1), Join(lastLower + 1, words.Count), "");
        string von = lastLower < 0 ? "" : Join(0, lastLower + 1);
        string last = Join(lastLower + 1, words.Count);
        return new Person(parts[^1], von, last, parts.Length == 3 ? parts[1] : "");
    }
}

sealed record NameList(Person[] Names, bool EtAl)
{
    public bool Single => Names.Length == 1 && !EtAl;
    public bool Same(NameList other) => EtAl == other.EtAl && Names.SequenceEqual(other.Names);
    public static NameList Parse(string text)
    {
        List<string> parts = SplitTop(text, " and ");
        bool etAl = parts[^1] == "others";
        if (etAl) parts.RemoveAt(parts.Count - 1);
        return new NameList(parts.Select(Person.Parse).ToArray(), etAl);
    }

    public string Authors(Style style)
    {
        bool initials = style is Style.APA or Style.IEEE;
        string[] values = Names.Select((name, i) => name.Format(style == Style.APA || style != Style.IEEE && i == 0, initials)).ToArray();
        return style switch
        {
            Style.APA when EtAl => string.Join(", ", values) + ", et al.",
            Style.APA when values.Length > 20 => string.Join(", ", values[..19]) + ", . . . " + values[^1],
            Style.APA => ListNames(values, "&"),
            Style.IEEE when EtAl || values.Length >= 7 => values[0] + " et al.",
            Style.IEEE => ListNames(values, "and", true),
            Style.CHICAGO when EtAl || values.Length >= 11 => string.Join(", ", values.Take(7)) + ", et al.",
            Style.CHICAGO => ListNames(values, "and"),
            Style.MLA when EtAl || values.Length >= 3 => values[0] + ", et al.",
            _ => ListNames(values, "and")
        };
    }

    public string Editors(Style style)
    {
        string[] values = Names.Select(name => name.Format(false, style is Style.APA or Style.IEEE)).ToArray();
        return EtAl ? values[0] + " et al." : ListNames(values, style == Style.APA ? "&" : "and", true);
    }
}

sealed class Entry(string type, string key, Dictionary<string, string> fields)
{
    public string Type { get; } = type;
    public string Key { get; } = key;
    public Dictionary<string, string> Fields { get; } = fields;
    public NameList? Authors { get; } = fields.TryGetValue("author", out string? author) ? NameList.Parse(author) : null;
    public NameList? Editors { get; } = fields.TryGetValue("editor", out string? editor) ? NameList.Parse(editor) : null;
    public NameList Primary => Authors ?? Editors!;
    public string Suffix { get; set; } = "";
    public string Value(string field) => Plain(Fields.GetValueOrDefault(field, ""));
    public string SortTitle
    {
        get
        {
            string title = Lower(Value("title"));
            foreach (string prefix in new[] { "a ", "an ", "the " })
                if (title.StartsWith(prefix, StringComparison.Ordinal)) return title[prefix.Length..];
            return title;
        }
    }
    public string Year(Style style) => Value("year") + (style is Style.APA or Style.CHICAGO ? Suffix : "");
    public static int Compare(Entry a, Entry b)
    {
        string[] left = [Lower(Plain(a.Primary.Names[0].Last)), a.Value("year"), a.SortTitle, a.Key];
        string[] right = [Lower(Plain(b.Primary.Names[0].Last)), b.Value("year"), b.SortTitle, b.Key];
        for (int i = 0; i < left.Length; i++)
        {
            int order = string.CompareOrdinal(left[i], right[i]);
            if (order != 0) return order;
        }
        return 0;
    }
    public static readonly IComparer<Entry> BibliographyComparer = Comparer<Entry>.Create(Compare);
}

sealed class Database
{
    static readonly Dictionary<string, string[]> Required = new(StringComparer.Ordinal)
    {
        ["article"] = ["author", "title", "journal", "year"],
        ["book"] = ["author", "title", "publisher", "year"],
        ["inproceedings"] = ["author", "title", "booktitle", "year"],
        ["incollection"] = ["author", "title", "booktitle", "publisher", "year"],
        ["techreport"] = ["author", "title", "institution", "year"],
        ["phdthesis"] = ["author", "title", "school", "year"],
        ["misc"] = ["author", "title", "year"]
    };
    readonly Dictionary<string, string> macros = new(StringComparer.Ordinal);
    public List<Entry> Entries { get; } = [];
    public Dictionary<string, Entry> ByKey { get; } = new(StringComparer.Ordinal);
    public List<string> Messages { get; } = [];
    int macroCount;

    public Database(IReadOnlyList<string> lines)
    {
        string[] monthKeys = "jan feb mar apr may jun jul aug sep oct nov dec".Split(' ');
        for (int i = 0; i < monthKeys.Length; i++) macros[monthKeys[i]] = MonthNames[i];
        for (int i = 0; i < lines.Count; i++)
        {
            string line = lines[i];
            if (line.Length == 0 || line.StartsWith('%')) continue;
            if (line.StartsWith("@string{", StringComparison.Ordinal))
            {
                int separator = line.IndexOf(" = ", StringComparison.Ordinal);
                string name = line[8..separator];
                try
                {
                    string value = Evaluate(line[(separator + 3)..^1], i + 1);
                    if (macros.ContainsKey(name)) throw new LoadError(i + 1, "duplicate macro");
                    macros[name] = value;
                    macroCount++;
                }
                catch (LoadError error) { Report(name, error); }
            }
            else
            {
                int end = i + 1;
                while (lines[end] != "}") end++;
                int brace = line.IndexOf('{');
                string type = line[1..brace], key = line[(brace + 1)..^1];
                try { ReadEntry(lines, i, end, type, key); }
                catch (LoadError error) { Report(key, error); }
                i = end;
            }
        }
        AssignSuffixes();
        Messages.Add($"LOADED entries={Entries.Count} macros={macroCount} errors={Messages.Count}");
    }

    void Report(string name, LoadError error) => Messages.Add($"ERROR line {error.Line}: {name}: {error.Message}");

    string Evaluate(string expression, int line)
    {
        int depth = 0;
        foreach (char c in expression)
        {
            if (c == '{') depth++;
            else if (c == '}') depth--;
            if (depth < 0) throw new LoadError(line, "unbalanced braces");
        }
        if (depth != 0) throw new LoadError(line, "unbalanced braces");
        StringBuilder result = new();
        foreach (string term in expression.Split(" # ", StringSplitOptions.None))
        {
            if (term[0] is '{' or '"') result.Append(term[1..^1]);
            else if (Digit(term[0])) result.Append(term);
            else if (macros.TryGetValue(term, out string? value)) result.Append(value);
            else throw new LoadError(line, $"unknown macro '{term}'");
        }
        return result.ToString();
    }

    void ReadEntry(IReadOnlyList<string> lines, int start, int end, string type, string key)
    {
        if (!Required.TryGetValue(type, out string[]? required)) throw new LoadError(start + 1, $"unknown type '{type}'");
        if (ByKey.ContainsKey(key)) throw new LoadError(start + 1, "duplicate key");
        Dictionary<string, string> fields = new(StringComparer.Ordinal);
        for (int i = start + 1; i < end; i++)
        {
            string line = lines[i];
            int separator = line.IndexOf(" = ", StringComparison.Ordinal);
            string name = line[2..separator], expression = line[(separator + 3)..];
            if (expression.EndsWith(',')) expression = expression[..^1];
            string value = Evaluate(expression, i + 1);
            if (fields.ContainsKey(name)) throw new LoadError(i + 1, $"duplicate field '{name}'");
            fields[name] = Normalize(value);
        }
        foreach (string field in required)
            if (!fields.ContainsKey(field) && !(type == "book" && field == "author" && fields.ContainsKey("editor")))
                throw new LoadError(end + 1, $"missing field '{field}'");
        Entry entry = new(type, key, fields);
        Entries.Add(entry);
        ByKey[key] = entry;
    }

    void AssignSuffixes()
    {
        HashSet<Entry> done = [];
        foreach (Entry entry in Entries)
        {
            if (done.Contains(entry)) continue;
            Entry[] group = Entries.Where(other => other.Primary.Same(entry.Primary) && other.Fields["year"] == entry.Fields["year"])
                .OrderBy(other => other.SortTitle, StringComparer.Ordinal).ThenBy(other => other.Key, StringComparer.Ordinal).ToArray();
            for (int i = 0; i < group.Length; i++)
            {
                done.Add(group[i]);
                if (group.Length > 1) group[i].Suffix = ((char)('a' + i)).ToString();
            }
        }
    }
}

abstract record TemplatePart;
sealed record LiteralPart(char Character) : TemplatePart;
sealed record FieldPart(string Name) : TemplatePart;
sealed record OptionalPart(TemplatePart[] Parts) : TemplatePart;

static class ReferenceFormatter
{
    static readonly string[][] Templates =
    [
        [
            "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
            "{author}. ({year}). {title}< ({edition})>. {publisher}.",
            "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
            "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
            "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
            "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>"
        ],
        [
            """{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.""",
            "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
            """{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.""",
            """{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.""",
            """{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.""",
            """{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>"""
        ],
        [
            """{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>""",
            "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
            """{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>""",
            "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
            """{author}. {year}. "{title}." PhD diss., {school}.""",
            "{author}. {year}. {title}.< {howpublished}.>< {note}.>"
        ],
        [
            """{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>""",
            "{author}. {title}.< {edition},> {publisher}, {year}.",
            """{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.""",
            "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
            "{author}. {title}. {year}. {school}, PhD dissertation.",
            "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>"
        ]
    ];
    static readonly TemplatePart[][][] Parsed = Templates.Select(style => style.Select(Parse).ToArray()).ToArray();

    static TemplatePart[] Parse(string text)
    {
        int i = 0;
        TemplatePart[] Read()
        {
            List<TemplatePart> parts = [];
            while (i < text.Length && text[i] != '>')
            {
                if (text[i] == '{')
                {
                    int end = text.IndexOf('}', i);
                    parts.Add(new FieldPart(text[(i + 1)..end]));
                    i = end + 1;
                }
                else if (text[i] == '<')
                {
                    i++;
                    parts.Add(new OptionalPart(Read()));
                    i++;
                }
                else parts.Add(new LiteralPart(text[i++]));
            }
            return parts.ToArray();
        }
        return Read();
    }

    static string EditorSuffix(Entry entry, Style style)
    {
        if (entry.Authors is not null) return "";
        bool single = entry.Primary.Single;
        return style switch
        {
            Style.APA => single ? " (Ed.)" : " (Eds.)",
            Style.IEEE => single ? ", Ed." : ", Eds.",
            Style.CHICAGO => single ? ", ed." : ", eds.",
            _ => single ? ", editor" : ", editors"
        };
    }

    static string Edition(string value)
    {
        if (!Digits(value)) return value + " ed.";
        int number = int.Parse(value);
        string suffix = number % 100 is 11 or 12 or 13 ? "th" : (number % 10) switch { 1 => "st", 2 => "nd", 3 => "rd", _ => "th" };
        return value + suffix + " ed.";
    }

    static Dictionary<string, string> Values(Entry entry, Style style, bool repeated)
    {
        Dictionary<string, string> result = entry.Fields.ToDictionary(pair => pair.Key, pair => Plain(pair.Value), StringComparer.Ordinal);
        result["author"] = (repeated ? "---" : entry.Primary.Authors(style)) + EditorSuffix(entry, style);
        result["editor"] = entry.Editors?.Editors(style) ?? "";
        result["eds"] = entry.Editors is null ? "" : entry.Editors.Single ? "Ed." : "Eds.";
        result["title"] = Plain(Title(entry.Fields["title"], style));
        result["year"] = entry.Year(style);
        result["pp"] = "";
        if (entry.Fields.ContainsKey("pages"))
        {
            result["pages"] = entry.Value("pages").Replace("--", "-");
            result["pp"] = (result["pages"].Contains('-') ? "pp. " : "p. ") + result["pages"];
        }
        if (entry.Fields.ContainsKey("edition")) result["edition"] = Edition(entry.Value("edition"));
        string month = entry.Value("month");
        int index = Array.IndexOf(MonthNames, month);
        result["mon"] = index < 0 ? month : MonthShort[index];
        return result;
    }

    public static string Format(Entry entry, Style style, int number = 0, bool repeated = false)
    {
        Dictionary<string, string> values = Values(entry, style, repeated);
        StringBuilder result = new();
        void Render(TemplatePart[] parts)
        {
            foreach (TemplatePart part in parts)
                switch (part)
                {
                    case FieldPart field:
                        result.Append(values.GetValueOrDefault(field.Name, ""));
                        break;
                    case OptionalPart optional:
                        if (optional.Parts.OfType<FieldPart>().All(placeholder => values.GetValueOrDefault(placeholder.Name, "").Length > 0)) Render(optional.Parts);
                        break;
                    case LiteralPart literal:
                        if (literal.Character != '.' || result.Length == 0 || result[^1] is not ('.' or '?' or '!')) result.Append(literal.Character);
                        break;
                }
        }
        int type = entry.Type switch { "article" => 0, "book" => 1, "inproceedings" or "incollection" => 2, "techreport" => 3, "phdthesis" => 4, _ => 5 };
        Render(Parsed[(int)style][type]);
        return (style == Style.IEEE ? $"[{number}] " : "") + result;
    }
}

sealed record Citation(int Start, int End, string Kind, Entry[] Entries);

sealed class CitationManager(Database database)
{
    readonly List<Entry> record = [];
    readonly HashSet<Entry> recorded = [];

    Entry Lookup(string key) => database.ByKey.TryGetValue(key, out Entry? entry) ? entry : throw new CommandError($"unknown key '{key}'");

    Entry[] IeeeOrder() => record.Concat(database.Entries.Where(entry => !recorded.Contains(entry))
        .OrderBy(entry => entry.Key, StringComparer.Ordinal)).ToArray();

    Dictionary<Entry, int> IeeeNumbers() => IeeeOrder().Select((entry, i) => (entry, number: i + 1))
        .ToDictionary(item => item.entry, item => item.number);

    static string ShortName(Entry entry, Style style, bool parenthetical)
    {
        string[] names = entry.Primary.Names.Select(name => name.Surname).ToArray();
        if (entry.Primary.EtAl || names.Length >= (style == Style.CHICAGO ? 4 : 3)) return names[0] + " et al.";
        if (names.Length == 3) return names[0] + ", " + names[1] + ", and " + names[2];
        if (names.Length == 2) return names[0] + (style == Style.APA && parenthetical ? " & " : " and ") + names[1];
        return names[0];
    }

    static string NumberRanges(int[] numbers)
    {
        Array.Sort(numbers);
        List<string> parts = [];
        for (int i = 0; i < numbers.Length;)
        {
            int end = i;
            while (end + 1 < numbers.Length && numbers[end + 1] == numbers[end] + 1) end++;
            if (end - i >= 2) parts.Add($"[{numbers[i]}]-[{numbers[end]}]");
            else for (int j = i; j <= end; j++) parts.Add($"[{numbers[j]}]");
            i = end + 1;
        }
        return string.Join(", ", parts);
    }

    static string CitationText(Citation citation, Style style, Dictionary<Entry, int> numbers)
    {
        Entry[] entries = citation.Entries;
        if (citation.Kind == "citeauthor") return string.Join("; ", entries.Select(entry => ShortName(entry, style, false)));
        if (citation.Kind == "citeyear") return string.Join(", ", entries.Select(entry => entry.Year(style)));
        bool parenthetical = citation.Kind != "citet";
        if (style == Style.IEEE)
            return parenthetical ? NumberRanges(entries.Select(entry => numbers[entry]).ToArray())
                : string.Join("; ", entries.Select(entry => ShortName(entry, style, false) + $" [{numbers[entry]}]"));
        if (style == Style.MLA)
        {
            string text = string.Join("; ", entries.Select(entry => ShortName(entry, style, parenthetical)));
            return parenthetical ? "(" + text + ")" : text;
        }
        if (parenthetical) entries = entries.OrderBy(entry => entry, Entry.BibliographyComparer).ToArray();
        List<string> groups = [];
        for (int i = 0; i < entries.Length;)
        {
            string name = ShortName(entries[i], style, parenthetical);
            int end = i + 1;
            while (end < entries.Length && ShortName(entries[end], style, parenthetical) == name) end++;
            string years = string.Join(", ", entries[i..end].Select(entry => entry.Year(style)));
            groups.Add(parenthetical ? name + (style == Style.APA ? ", " : " ") + years : name + " (" + years + ")");
            i = end;
        }
        string joined = string.Join("; ", groups);
        return parenthetical ? "(" + joined + ")" : joined;
    }

    string Cite(string text, Style style)
    {
        List<Citation> citations = [];
        for (int start = text.IndexOf('\\'); start >= 0;)
        {
            int brace = text.IndexOf('{', start), end = text.IndexOf('}', brace);
            HashSet<string> seen = new(StringComparer.Ordinal);
            List<Entry> entries = [];
            foreach (string key in text[(brace + 1)..end].Split(','))
                if (seen.Add(key)) entries.Add(Lookup(key));
            citations.Add(new Citation(start, end + 1, text[(start + 1)..brace], entries.ToArray()));
            start = text.IndexOf('\\', end + 1);
        }
        foreach (Citation citation in citations)
            foreach (Entry entry in citation.Entries)
                if (recorded.Add(entry)) record.Add(entry);
        Dictionary<Entry, int> numbers = IeeeNumbers();
        StringBuilder result = new();
        int position = 0;
        foreach (Citation citation in citations)
        {
            result.Append(text.AsSpan(position, citation.Start - position));
            result.Append(CitationText(citation, style, numbers));
            position = citation.End;
        }
        result.Append(text.AsSpan(position));
        return result.ToString();
    }

    static string BaseKey(Entry entry)
    {
        string surname = Lower(Letters(Plain(entry.Primary.Names[0].Last)));
        string year = new(entry.Fields["year"].Where(Digit).ToArray());
        string word = entry.Value("title").Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(part => Lower(Letters(part)))
            .FirstOrDefault(part => part.Length > 0 && !SmallWords.Contains(part)) ?? "";
        return surname + year + word;
    }

    IEnumerable<string> Keygen()
    {
        string[] bases = database.Entries.Select(BaseKey).ToArray();
        Dictionary<string, int> counts = bases.GroupBy(value => value, StringComparer.Ordinal).ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);
        Dictionary<string, int> used = new(StringComparer.Ordinal);
        for (int i = 0; i < bases.Length; i++)
        {
            string generated = bases[i];
            if (counts[generated] > 1)
            {
                int index = used.GetValueOrDefault(generated);
                used[generated] = index + 1;
                generated += (char)('a' + index);
            }
            yield return database.Entries[i].Key + " -> " + generated;
        }
    }

    static IEnumerable<string> Warnings(Entry entry, Dictionary<string, string> titles)
    {
        if (entry.Fields.ContainsKey("pages"))
        {
            string pages = entry.Value("pages");
            if (pages.Contains('-') && !pages.Contains("--", StringComparison.Ordinal)) yield return "pages use a single hyphen";
            string[] parts = pages.Split('-', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 2 && parts.All(Digits) && int.Parse(parts[0]) > int.Parse(parts[1])) yield return "pages are reversed";
        }
        string year = entry.Value("year");
        if (year.Length != 4 || !Digits(year)) yield return "year is not 4 digits";
        string title = entry.Value("title");
        if (!title.Any(c => c is >= 'a' and <= 'z') && title.Count(c => c is >= 'A' and <= 'Z') >= 2) yield return "title is all caps";
        if (entry.Type == "article" && !entry.Fields.ContainsKey("doi")) yield return "article has no doi";
        string lowered = Lower(title);
        if (titles.TryGetValue(lowered, out string? key)) yield return "same title as " + key;
        else titles[lowered] = entry.Key;
        foreach (string field in entry.Fields.Keys.Where(field => !KnownFields.Contains(field)).OrderBy(field => field, StringComparer.Ordinal))
            yield return $"unknown field '{field}'";
    }

    IEnumerable<string> Check()
    {
        Dictionary<string, string> titles = new(StringComparer.Ordinal);
        int count = 0;
        foreach (Entry entry in database.Entries)
            foreach (string warning in Warnings(entry, titles))
            {
                count++;
                yield return $"WARN {entry.Key}: {warning}";
            }
        yield return $"CHECK warnings={count}";
    }

    IEnumerable<string> Export(Entry entry)
    {
        yield return "@" + entry.Type + "{" + entry.Key + ",";
        string[] fields = KnownFields.Where(entry.Fields.ContainsKey).Concat(entry.Fields.Keys.Where(field => !KnownFields.Contains(field))
            .OrderBy(field => field, StringComparer.Ordinal)).ToArray();
        for (int i = 0; i < fields.Length; i++)
            yield return "  " + fields[i] + " = {" + entry.Fields[fields[i]] + "}" + (i + 1 == fields.Length ? "" : ",");
        yield return "}";
    }

    IEnumerable<string> Stats()
    {
        yield return $"ENTRIES {database.Entries.Count}";
        foreach (IGrouping<string, Entry> group in database.Entries.GroupBy(entry => entry.Type, StringComparer.Ordinal).OrderBy(group => group.Key, StringComparer.Ordinal))
            yield return $"TYPE {group.Key} {group.Count()}";
        foreach (IGrouping<string, Entry> group in database.Entries.GroupBy(entry => entry.Value("year"), StringComparer.Ordinal).OrderBy(group => group.Key, StringComparer.Ordinal))
            yield return $"YEAR {group.Key} {group.Count()}";
        HashSet<string> authors = new(StringComparer.Ordinal);
        Dictionary<(string First, string Second), int> pairs = [];
        foreach (Entry entry in database.Entries)
        {
            if (entry.Authors is null) continue;
            string[] names = entry.Authors.Names.Select(name => name.Format(false, false)).Distinct(StringComparer.Ordinal)
                .OrderBy(name => name, StringComparer.Ordinal).ToArray();
            authors.UnionWith(names);
            for (int i = 0; i < names.Length; i++)
                for (int j = i + 1; j < names.Length; j++)
                {
                    (string, string) pair = (names[i], names[j]);
                    pairs[pair] = pairs.GetValueOrDefault(pair) + 1;
                }
        }
        yield return $"AUTHORS {authors.Count}";
        if (pairs.Count == 0) yield return "PAIR none";
        else
        {
            KeyValuePair<(string First, string Second), int> best = pairs.OrderByDescending(pair => pair.Value)
                .ThenBy(pair => pair.Key.First, StringComparer.Ordinal).ThenBy(pair => pair.Key.Second, StringComparer.Ordinal).First();
            yield return $"PAIR {best.Key.First} & {best.Key.Second} {best.Value}";
        }
    }

    public List<string> Execute(string line)
    {
        int firstSpace = line.IndexOf(' ');
        string command = firstSpace < 0 ? line : line[..firstSpace];
        string[] words = command is "CITE" or "SEARCH" ? line.Split(' ', 3, StringSplitOptions.None) : line.Split(' ');
        int expected = command switch
        {
            "FORMAT" or "CITE" or "SEARCH" => 2,
            "BIBLIOGRAPHY" or "EXPORT" => 1,
            "KEYGEN" or "CHECK" or "STATS" => 0,
            _ => throw new CommandError($"unknown command '{command}'")
        };
        if (command == "FORMAT" ? words.Length - 1 < expected : words.Length - 1 != expected)
            throw new CommandError("wrong number of arguments");
        Style style = Style.APA;
        if (command is "FORMAT" or "BIBLIOGRAPHY" or "CITE")
            style = words[1] switch
            {
                "APA" => Style.APA, "IEEE" => Style.IEEE, "CHICAGO" => Style.CHICAGO, "MLA" => Style.MLA,
                _ => throw new CommandError($"unknown style '{words[1]}'")
            };
        List<string> output = [];
        switch (command)
        {
            case "FORMAT":
            {
                Dictionary<Entry, int> numbers = IeeeNumbers();
                foreach (string key in words[2..])
                    output.Add(database.ByKey.TryGetValue(key, out Entry? entry)
                        ? ReferenceFormatter.Format(entry, style, numbers[entry]) : $"ERROR unknown key '{key}'");
                break;
            }
            case "BIBLIOGRAPHY":
            {
                output.Add(style == Style.MLA ? "Works Cited" : "References");
                Dictionary<Entry, int> numbers = IeeeNumbers();
                Entry[] entries = style == Style.IEEE ? IeeeOrder() : database.Entries.OrderBy(entry => entry, Entry.BibliographyComparer).ToArray();
                NameList? previous = null;
                foreach (Entry entry in entries)
                {
                    bool repeated = (style is Style.CHICAGO or Style.MLA) && previous?.Same(entry.Primary) == true;
                    output.Add(ReferenceFormatter.Format(entry, style, numbers[entry], repeated));
                    previous = entry.Primary;
                }
                break;
            }
            case "CITE": output.Add(Cite(words[2], style)); break;
            case "KEYGEN": output.AddRange(Keygen()); break;
            case "CHECK": output.AddRange(Check()); break;
            case "SEARCH":
            {
                string needle = Lower(words[2]);
                string[] matches = database.Entries.Where(entry => entry.Fields.ContainsKey(words[1]) && Lower(entry.Value(words[1])).Contains(needle, StringComparison.Ordinal))
                    .Select(entry => entry.Key).ToArray();
                output.Add(matches.Length == 0 ? "MATCHES 0" : $"MATCHES {matches.Length}: " + string.Join(' ', matches));
                break;
            }
            case "EXPORT": output.AddRange(Export(Lookup(words[1]))); break;
            case "STATS": output.AddRange(Stats()); break;
        }
        return output;
    }
}

static class Program
{
    static void Main()
    {
        List<string> lines = [];
        string? line;
        while ((line = Console.ReadLine()) != "%%" && line is not null) lines.Add(line);
        Database database = new(lines);
        foreach (string message in database.Messages) Console.WriteLine(message);
        CitationManager manager = new(database);
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++)
        {
            try { foreach (string output in manager.Execute(Console.ReadLine()!)) Console.WriteLine(output); }
            catch (CommandError error) { Console.WriteLine("ERROR " + error.Message); }
        }
    }
}
