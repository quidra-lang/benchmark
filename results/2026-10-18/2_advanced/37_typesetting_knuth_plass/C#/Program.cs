using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    static IndexEntry GetEntry(Dictionary<string, IndexEntry> entries, string name) {
        if (!entries.TryGetValue(name, out IndexEntry entry)) {
            entry = new IndexEntry(name);
            entries[name] = entry;
        }
        return entry;
    }
    static int CompareBibliography(DocumentParser.Bib a, DocumentParser.Bib b) {
        int order = string.CompareOrdinal(a.baseLabel, b.baseLabel);
        if (order == 0)
            order = string.CompareOrdinal(a.author, b.author);
        if (order == 0)
            order = string.CompareOrdinal(a.title, b.title);
        if (order == 0)
            order = string.CompareOrdinal(a.key, b.key);
        return order;
    }

    public sealed record Token(string kind, string argument, int number);
    public sealed record Mark(int word, int position, bool footnote, int number);
    public sealed record RawMark(int position, bool footnote, int number);
    public sealed record Expanded(List<string> words, List<Mark> marks);
    public sealed class Break {
        public int sw, sc, ew, ec;
        public bool mid, hyphen;
        public Break(int sw, int sc, int ew, int ec, bool mid, bool hyphen) {
            this.sw = sw;
            this.sc = sc;
            this.ew = ew;
            this.ec = ec;
            this.mid = mid;
            this.hyphen = hyphen;
        }
    }
    public sealed class Measure {
        public int start, end, slack;
        public bool last, mid;
        public List<string> pieces = new();
        public List<int[]> ranges = new();
    }
    public sealed class Metrics {
        public readonly List<string> words;
        public readonly int first, later;
        public readonly int[] offsets;
        public readonly List<Break> breaks = new();
        public Metrics(List<string> words, int first, int later, Hyphenation dictionary) {
            this.words = words;
            this.first = first;
            this.later = later;
            offsets = new int[words.Count];
            breaks.Add(new Break(0, 0, 0, 0, false, false));
            int offset = 0;
            for (int i = 0; i < words.Count; i++) {
                string word = words[i];
                offsets[i] = offset;
                offset += word.Length + 1;
                foreach (KeyValuePair<int, bool> split in dictionary.Points(word))
                    breaks.Add(new Break(i, split.Key, i, split.Key, true, split.Value));
                breaks.Add(new Break(i + 1, 0, i, word.Length, false, false));
            }
        }
        public int End() {
            return breaks.Count - 1;
        }
        public int Slack(int start, int end) {
            Break a = breaks[start], b = breaks[end];
            int length = offsets[b.ew] + b.ec - offsets[a.sw] - a.sc + (b.hyphen ? 1 : 0);
            return (start == 0 ? first : later) - length;
        }
        public Measure Measure(int start, int end) {
            Measure result = new Measure();
            result.start = start;
            result.end = end;
            result.slack = Slack(start, end);
            result.last = end == End();
            result.mid = breaks[end].mid;
            Break a = breaks[start], b = breaks[end];
            for (int word = a.sw; word <= b.ew; word++) {
                int first = word == a.sw ? a.sc : 0, last = word == b.ew ? b.ec : words[word].Length;
                result.pieces.Add(words[word].Substring(first, (last) - (first)));
                result.ranges.Add(new int[] { word, first, last });
            }
            if (b.hyphen)
                result.pieces[result.pieces.Count - 1] = result.pieces[^1] + "-";
            return result;
        }
    }
    public sealed class Line {
        public string text;
        public DocumentParser.Block origin;
        public bool first;
        public readonly List<int> footnotes = new(), indexes = new();
        public Line(string text) {
            this.text = text;
        }
    }
    public sealed class Broken {
        public string name, align;
        public bool body;
        public int cost;
        public readonly List<Measure> measures = new();
        public readonly List<Line> lines = new();
    }
    public sealed class LayoutBlock {
        public string kind;
        public bool list, forced;
        public List<Line> lines;
        public LayoutBlock(string kind, bool list, bool forced, List<Line> lines) {
            this.kind = kind;
            this.list = list;
            this.forced = forced;
            this.lines = lines;
        }
    }
    public sealed class Page {
        public List<Line> content = new();
        public List<int> notes = new();
        public List<string> body = new();
        public int height, serial;
        public bool forced, blank;
        public string header = "", footer = "", display = "";
    }
    public sealed class IndexEntry {
        public string name;
        public readonly List<int> marks = new();
        public readonly SortedSet<string> see = new(StringComparer.Ordinal);
        public readonly Dictionary<string, IndexEntry> children = new();
        public IndexEntry(string name) {
            this.name = name;
        }
    }
    public sealed record Deferred(string kind, DocumentParser.Block block, List<Line> lines);
    public sealed class Layout {
        public List<Page> pages;
        public readonly Dictionary<string, string> labels = new();
        public readonly Dictionary<int, Broken> bodies = new();
        public readonly List<Broken> broken = new();
        public readonly List<string> warnings = new();
    }
    public static List<string> Words(string text) {
        List<string> result = new();
        foreach (string word in text.Split(" "))
            if (word.Length != 0)
                result.Add(word);
        return result;
    }
    public static List<Line> Lines(List<string> text, DocumentParser.Block origin) {
        List<Line> result = new();
        for (int i = 0; i < text.Count; i++) {
            Line line = new Line(text[i]);
            line.origin = origin;
            line.first = i == 0;
            result.Add(line);
        }
        return result;
    }
    public static string[] SplitLabel(string text) {
        int position = text.lastIndexOf(" {#");
        return text.endsWith("}") && position >= 0
                   ? new string[] { text.Substring(0, (position) - (0)),
                                    text.Substring(position + 3, (text.Length - 1) - (position + 3)) }
                   : new string[] { text, null };
    }
    public static string Roman(int number) {
        string[] small = { "", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix" };
        return "x".Repeat(number / 10) + small[number % 10];
    }
    public sealed class Typesetter {
        public readonly DocumentParser.Document document;
        public readonly Dictionary<string, int> parameters;
        public readonly Hyphenation dictionary;
        public readonly Dictionary<string, DocumentParser.Block> labels = new();
        public readonly Dictionary<string, DocumentParser.Bib> bibliography = new();
        public readonly List<DocumentParser.Bib> cited = new();
        public readonly List<DocumentParser.Block> bodies = new(), headings = new(), tables = new();
        public readonly List<string> footnotes = new(), indexMarks = new();
        public readonly Dictionary<string, IndexEntry> index = new();
        public Typesetter(DocumentParser.Document document, Dictionary<string, int> parameters,
                          List<string> hyphenation) {
            this.document = document;
            this.parameters = parameters;
            dictionary = new Hyphenation(hyphenation, document.additions, parameters["left_min"],
                                         parameters["right_min"]);
            Register();
            Check();
            BibliographyLabels();
            PrepareIndex();
            List<DocumentParser.Warning> orderedWarnings =
                document.warnings.OrderBy(warning => warning.line).ToList();
            document.warnings.Clear();
            document.warnings.AddRange(orderedWarnings);
        }
        public void Warn(int line, string text) {
            document.warnings.Add(new DocumentParser.Warning(line, text));
        }
        public void Register() {
            int chapter = 0, section = 0, table = 0;
            DocumentParser.Block previous = null;
            for (int i = 0; i < document.blocks.Count; i++) {
                DocumentParser.Block block = document.blocks[i];
                block.id = i;
                if (block.kind.Equals("h1") || block.kind.Equals("h2")) {
                    string[] parts = SplitLabel(block.argument);
                    block.text = parts[0];
                    block.label = parts[1];
                    if (block.kind.Equals("h1")) {
                        chapter++;
                        section = 0;
                        block.number = Convert.ToString(chapter);
                        if (i > 0)
                            block.pageBreak = true;
                    } else {
                        section++;
                        block.number = chapter + "." + section;
                    }
                    headings.Add(block);
                } else if (block.kind.Equals("enum"))
                    block.number = Convert.ToString(previous != null && previous.kind.Equals("enum")
                                                        ? int.Parse(previous.number) + 1
                                                        : 1);
                else if (block.kind.Equals("table")) {
                    string[] parts = SplitLabel(block.caption);
                    block.caption = parts[0];
                    block.label = parts[1];
                    if (block.caption.Length != 0) {
                        table++;
                        block.number = Convert.ToString(table);
                        tables.Add(block);
                    }
                }
                if (block.label != null) {
                    if (labels.ContainsKey(block.label)) {
                        Warn(block.line, "duplicate label " + block.label);
                        block.label = null;
                    } else
                        labels[block.label] = block;
                }
                if (block.kind.Equals("paragraph") && previous != null &&
                    (previous.kind.Equals("h1") || previous.kind.Equals("h2")))
                    block.indent = 0;
                if (DocumentParser.BODY.Contains(block.kind)) {
                    bodies.Add(block);
                    block.paragraph = bodies.Count;
                }
                previous = block;
            }
            foreach (DocumentParser.Bib entry in document.bibliography) {
                if (bibliography.ContainsKey(entry.key))
                    Warn(entry.line, "duplicate bibliography key " + entry.key);
                else
                    bibliography[entry.key] = entry;
            }
        }
        public Token Command(string kind, string argument, int line) {
            if ((kind.Equals("ref") || kind.Equals("page")) && !labels.ContainsKey(argument))
                Warn(line, "undefined label " + argument);
            if (kind.Equals("cite"))
                foreach (string key in argument.Split(",")) {
                    if (bibliography.ContainsKey(key))
                        bibliography[key].cited = true;
                    else
                        Warn(line, "undefined citation " + key);
                }
            if (kind.Equals("fn")) {
                footnotes.Add(argument);
                return new Token(kind, "", footnotes.Count);
            }
            if (kind.Equals("idx")) {
                indexMarks.Add(argument);
                return new Token(kind, "", indexMarks.Count);
            }
            return new Token(kind, argument, 0);
        }
        public void ParseBody(DocumentParser.Block block, DocumentParser.Source source) {
            string text = source.text;
            int position = 0;
            while (position < text.Length) {
                int opening = text.IndexOf('{', position);
                if (opening < 0) {
                    block.tokens.Add(new Token("", text.Substring(position), 0));
                    break;
                }
                if (opening > position)
                    block.tokens.Add(new Token("", text.Substring(position, (opening) - (position)), 0));
                int closing = text.IndexOf('}', opening + 1);
                if (closing < 0) {
                    Warn(source.line, "unclosed brace");
                    block.tokens.Add(new Token("", text.Substring(opening), 0));
                    break;
                }
                string content = text.Substring(opening + 1, (closing) - (opening + 1));
                int colon = content.IndexOf(':');
                string name = colon < 0 ? content : content.Substring(0, (colon) - (0)),
                       argument = colon < 0 ? "" : content.Substring(colon + 1);
                if (new HashSet<string> { "ref", "page", "fn", "idx", "cite" }.Contains(name) && colon >= 0 &&
                    argument.Length != 0)
                    block.tokens.Add(Command(name, argument, source.line));
                else
                    Warn(source.line, "bad command {" + content + "}");
                position = closing + 1;
            }
        }
        public void Check() {
            foreach (DocumentParser.Block block in document.blocks) {
                if (block.kind.Equals("table")) {
                    int columns = block.columns.Length;
                    foreach (DocumentParser.Source source in block.inner) {
                        string[] cells = source.text.Split('|');
                        if (cells.Length != columns)
                            Warn(source.line,
                                 "table row has " + cells.Length + " cells, expected " + columns);
                        List<string> row = new();
                        for (int i = 0; i < columns; i++)
                            row.Add(i < cells.Length ? cells[i].Trim() : "");
                        block.tableRows.Add(row);
                    }
                    block.tableLines =
                        Renderer.Table(block.tableRows, block.columns, block.caption, block.number);
                    int width = 0;
                    foreach (string line in block.tableLines)
                        width = Math.Max(width, line.Length);
                    if (width > block.width)
                        Warn(block.line, "table too wide by " + (width - block.width));
                } else if (block.kind.Equals("verbatim")) {
                    foreach (DocumentParser.Source source in block.inner)
                        if (source.text.Length > block.width)
                            Warn(source.line,
                                 "verbatim line too long by " + (source.text.Length - block.width));
                } else if (DocumentParser.BODY.Contains(block.kind))
                    for (int i = 0; i < block.body.Count; i++) {
                        if (i > 0)
                            block.tokens.Add(new Token("", " ", 0));
                        ParseBody(block, block.body[i]);
                    }
            }
            foreach (DocumentParser.Bib entry in bibliography.Values)
                if (!entry.cited)
                    Warn(entry.line, "unused bibliography entry " + entry.key);
        }
        public void BibliographyLabels() {
            foreach (DocumentParser.Bib entry in bibliography.Values)
                if (entry.cited) {
                    string[] names = entry.author.Split(" and ", StringSplitOptions.None);
                    string baseLabel;
                    if (names.Length == 1)
                        baseLabel = names[0].Substring(0, (Math.Min(3, names[0].Length)) - (0));
                    else {
                        StringBuilder text = new StringBuilder();
                        for (int i = 0; i < Math.Min(names.Length, names.Length >= 5 ? 3 : 4); i++)
                            text.Append(names[i][0]);
                        if (names.Length >= 5)
                            text.Append('+');
                        baseLabel = text.ToString();
                    }
                    entry.baseLabel = baseLabel + entry.year.Substring(2);
                    cited.Add(entry);
                }
            cited.Sort(CompareBibliography);
            for (int start = 0; start < cited.Count;) {
                int end = start + 1;
                while (end < cited.Count && cited[end].baseLabel.Equals(cited[start].baseLabel))
                    end++;
                for (int i = start; i < end; i++)
                    cited[i].label = cited[i].baseLabel +
                                     (end - start == 1 ? "" : Convert.ToString((char)('a' + i - start)));
                start = end;
            }
        }
        public void PrepareIndex() {
            for (int i = 0; i < indexMarks.Count; i++) {
                string phrase = indexMarks[i];
                int pipe = phrase.IndexOf('|');
                string entryPart = pipe < 0 ? phrase : phrase.Substring(0, (pipe) - (0)),
                       reference = pipe < 0 ? null : phrase.Substring(pipe + 1);
                int bang = entryPart.IndexOf('!');
                string parent = bang < 0 ? entryPart : entryPart.Substring(0, (bang) - (0)),
                       child = bang < 0 ? null : entryPart.Substring(bang + 1);
                IndexEntry entry = GetEntry(index, parent);
                if (child != null)
                    entry = GetEntry(entry.children, child);
                if (reference != null)
                    entry.see.Add(reference);
                else
                    entry.marks.Add(i + 1);
            }
        }
        public Expanded Expand(DocumentParser.Block block, Dictionary<string, string> pages) {
            StringBuilder text = new StringBuilder();
            List<RawMark> marks = new();
            foreach (Token token in block.tokens) {
                if (token.kind.Length == 0)
                    text.Append(token.argument);
                else if (token.kind.Equals("ref"))
                    text.Append(labels.ContainsKey(token.argument) ? labels[token.argument].number : "??");
                else if (token.kind.Equals("page"))
                    text.Append(pages.GetValueOrDefault(token.argument, "??"));
                else if (token.kind.Equals("fn")) {
                    marks.Add(new RawMark(text.Length, true, token.number));
                    text.Append('[').Append(token.number).Append(']');
                } else if (token.kind.Equals("idx"))
                    marks.Add(new RawMark(text.Length - 1, false, token.number));
                else {
                    SortedSet<string> citations = new(StringComparer.Ordinal);
                    bool missing = false;
                    foreach (string key in token.argument.Split(",")) {
                        DocumentParser.Bib entry = bibliography.GetValueOrDefault(key);
                        if (entry == null)
                            missing = true;
                        else
                            citations.Add(entry.label);
                    }
                    List<string> values = new(citations);
                    if (missing)
                        values.Add("?");
                    text.Append('[').Append(string.Join(", ", values)).Append(']');
                }
            }
            List<string> words = new();
            List<int> starts = new();
            string value = text.ToString();
            int position = 0;
            while (position < value.Length) {
                if (value[position] == ' ') {
                    position++;
                    continue;
                }
                int start = position;
                while (position < value.Length && value[position] != ' ')
                    position++;
                starts.Add(start);
                words.Add(value.Substring(start, (position) - (start)));
            }
            List<Mark> located = new();
            foreach (RawMark mark in marks) {
                int word = 0;
                while (word + 1 < starts.Count && starts[word + 1] <= mark.position)
                    word++;
                located.Add(new Mark(word, mark.position - starts[word], mark.footnote, mark.number));
            }
            return new Expanded(words, located);
        }
        public Broken BreakText(List<string> words, List<Mark> marks, int first, int later, string alignment,
                                string firstPrefix, string laterPrefix, string name, bool body,
                                bool optimal) {
            Metrics metrics = new Metrics(words, first, later, dictionary);
            LineBreaker.Result result = LineBreaker.Split(metrics, optimal, parameters);
            Broken broken = new Broken();
            broken.name = name;
            broken.align = alignment;
            broken.body = body;
            broken.cost = result.cost;
            int start = 0;
            foreach (int end in result.breaks) {
                Measure measure = metrics.Measure(start, end);
                Line line =
                    new Line((start == 0 ? firstPrefix : laterPrefix) +
                             Renderer.Display(measure.pieces, measure.slack, alignment, measure.last));
                foreach (Mark mark in marks)
                    foreach (int[] range in measure.ranges)
                        if (range[0] == mark.word && range[1] <= mark.position && mark.position < range[2]) {
                            if (mark.footnote)
                                line.footnotes.Add(mark.number);
                            else
                                line.indexes.Add(mark.number);
                        }
                broken.measures.Add(measure);
                broken.lines.Add(line);
                start = end;
            }
            return broken;
        }
        public string PageList(SortedSet<int> pages) {
            List<int> ordered = new(pages);
            List<string> parts = new();
            for (int start = 0; start < ordered.Count;) {
                int end = start;
                while (end + 1 < ordered.Count && ordered[end + 1] == ordered[end] + 1)
                    end++;
                if (end - start + 1 >= 3)
                    parts.Add(ordered[start] + "-" + ordered[end]);
                else
                    for (int i = start; i <= end; i++)
                        parts.Add(Convert.ToString(ordered[i]));
                start = end + 1;
            }
            return string.Join(", ", parts);
        }
        public string IndexLine(IndexEntry entry, bool child, int[] markPages) {
            SortedSet<int> pages = new();
            foreach (int mark in entry.marks)
                pages.Add(markPages[mark]);
            string line = (child ? "  " : "") + entry.name;
            if (pages.Count != 0)
                line += ", " + PageList(pages);
            if (entry.see.Count != 0)
                line += ", see " + string.Join(", ", entry.see);
            return line;
        }
        public List<string> SortedNames(HashSet<string> names) {
            List<string> result = new(names);
            result.Sort((a, b) => {
                int order = string.CompareOrdinal(a.ToLowerInvariant(), b.ToLowerInvariant());
                return order != 0 ? order : string.CompareOrdinal(a, b);
            });
            return result;
        }
        public List<string> IndexLines(int[] markPages) {
            List<string> result = new();
            string previous = null;
            foreach (string name in SortedNames(index.Keys)) {
                IndexEntry entry = index[name];
                char first = name[0];
                string group =
                    Hyphenation.Letter(first) ? Convert.ToString(char.ToUpperInvariant(first)) : "Symbols";
                if (!group.Equals(previous)) {
                    result.Add(group);
                    previous = group;
                }
                result.Add(IndexLine(entry, false, markPages));
                foreach (string child in SortedNames(entry.children.Keys))
                    result.Add(IndexLine(entry.children[child], true, markPages));
            }
            return result;
        }
        public List<string> Entries(string kind, int width, int[] blockPages, List<Page> pages) {
            List<string> result = new();
            foreach (DocumentParser.Block block in kind.Equals("toc") ? headings : tables) {
                string left = kind.Equals("toc")
                                  ? (block.kind.Equals("h2") ? "  " : "") + block.number + " " + block.text
                                  : "Table " + block.number + ". " + block.caption,
                       number = blockPages == null ? "??" : pages[blockPages[block.id] - 1].display;
                result.Add(left + " " + ".".Repeat(width - left.Length - number.Length - 2) + " " + number);
            }
            return result;
        }
        public Layout Once(bool optimal, Dictionary<string, string> pageValues) {
            Layout layout = new Layout();
            List<LayoutBlock> blocks = new();
            List<Deferred> deferred = new();
            Dictionary<int, List<Line>> footnoteLines = new();
            List<Broken> footnoteBroken = new();
            for (int i = 0; i < footnotes.Count; i++) {
                string prefix = "[" + (i + 1) + "] ";
                Broken broken = BreakText(Words(footnotes[i]), [], document.width - prefix.Length,
                                          document.width - prefix.Length, "left", prefix,
                                          " ".Repeat(prefix.Length), "footnote " + (i + 1), false, optimal);
                footnoteLines[i + 1] = broken.lines;
                footnoteBroken.Add(broken);
            }
            int referenceWidth = 3;
            foreach (DocumentParser.Bib entry in cited)
                referenceWidth = Math.Max(referenceWidth, entry.label.Length + 3);
            foreach (DocumentParser.Block block in document.blocks) {
                int start = blocks.Count;
                string kind = block.kind;
                if (DocumentParser.BODY.Contains(kind)) {
                    Expanded expanded = Expand(block, pageValues);
                    int first = block.width, later = block.width;
                    string firstPrefix = "", laterPrefix = "";
                    if (kind.Equals("paragraph")) {
                        first -= block.indent;
                        firstPrefix = " ".Repeat(block.indent);
                    } else if (kind.Equals("item")) {
                        first -= 2;
                        later = first;
                        firstPrefix = "- ";
                        laterPrefix = "  ";
                    } else if (kind.Equals("enum")) {
                        first -= 4;
                        later = first;
                        firstPrefix = " ".Repeat(2 - block.number.Length) + block.number + ". ";
                        laterPrefix = "    ";
                    } else if (kind.Equals("quote")) {
                        first -= 8;
                        later = first;
                        firstPrefix = "    ";
                        laterPrefix = firstPrefix;
                    } else {
                        first -= 12;
                        later = first;
                        firstPrefix = block.term.Length <= 10
                                          ? block.term + " ".Repeat(12 - block.term.Length)
                                          : "            ";
                        laterPrefix = "            ";
                    }
                    Broken broken =
                        BreakText(expanded.words, expanded.marks, first, later, block.align, firstPrefix,
                                  laterPrefix, "paragraph " + block.paragraph, true, optimal);
                    layout.bodies[block.paragraph] = broken;
                    layout.broken.Add(broken);
                    List<Line> body = new();
                    if (kind.Equals("term") && block.term.Length >= 11)
                        body.Add(new Line(block.term));
                    body.AddRange(broken.lines);
                    for (int i = 0; i < body.Count; i++) {
                        body[i].origin = block;
                        body[i].first = i == 0;
                    }
                    blocks.Add(new LayoutBlock(
                        "flow", new HashSet<string> { "item", "enum", "term" }.Contains(kind), false, body));
                } else if (kind.Equals("title") || kind.Equals("author")) {
                    string text = kind.Equals("title") ? block.argument.ToUpperInvariant() : block.argument;
                    blocks.Add(
                        new LayoutBlock("heading", false, false,
                                        Lines([" ".Repeat((block.width - text.Length) / 2) + text], block)));
                } else if (kind.Equals("h1") || kind.Equals("h2")) {
                    string text =
                        block.number + " " + (kind.Equals("h1") ? block.text.ToUpperInvariant() : block.text);
                    blocks.Add(new LayoutBlock(
                        "heading", false, false,
                        Lines([text, (kind.Equals("h1") ? "=" : "-").Repeat(text.Length)], block)));
                } else if (kind.Equals("table"))
                    blocks.Add(new LayoutBlock("solid", false, false, Lines(block.tableLines, block)));
                else if (kind.Equals("verbatim")) {
                    List<string> text = new();
                    foreach (DocumentParser.Source source in block.inner)
                        text.Add(source.text);
                    blocks.Add(new LayoutBlock("flow", false, false, Lines(text, block)));
                } else {
                    string title = kind.Equals("toc")     ? "CONTENTS"
                                   : kind.Equals("lot")   ? "TABLES"
                                   : kind.Equals("index") ? "INDEX"
                                                          : "REFERENCES";
                    blocks.Add(new LayoutBlock("heading", false, false,
                                               Lines([title, "=".Repeat(title.Length)], block)));
                    if (kind.Equals("bibliography")) {
                        foreach (DocumentParser.Bib entry in cited) {
                            string prefix = "[" + entry.label + "]";
                            prefix += " ".Repeat(referenceWidth - prefix.Length);
                            Broken broken = BreakText(
                                Words(entry.author + ". " + entry.year + ". " + entry.title), [],
                                block.width - referenceWidth, block.width - referenceWidth, "left", prefix,
                                " ".Repeat(referenceWidth), "reference " + entry.label, false, optimal);
                            layout.broken.Add(broken);
                            foreach (Line line in broken.lines)
                                line.origin = block;
                            blocks.Add(new LayoutBlock("flow", true, false, broken.lines));
                        }
                    } else {
                        List<string> text = kind.Equals("index") ? IndexLines(new int[indexMarks.Count + 1])
                                                                 : Entries(kind, block.width, null, null);
                        List<Line> entryLines = Lines(text, block);
                        blocks.Add(new LayoutBlock("flow", false, false, entryLines));
                        deferred.Add(new Deferred(kind, block, entryLines));
                    }
                }
                if (blocks.Count > start)
                    blocks[start].forced = block.pageBreak;
            }
            layout.broken.AddRange(footnoteBroken);
            List<Page> raw = PageBuilder.Build(blocks, footnoteLines, document.height,
                                               parameters["orphan_lines"], parameters["widow_lines"]);
            List<Page> pages = new();
            foreach (Page page in raw) {
                bool chapter = page.content.Count != 0 && page.content[0].first &&
                               page.content[0].origin != null && page.content[0].origin.kind.Equals("h1");
                if (chapter && (pages.Count + 1) % 2 == 0) {
                    Page blank = new Page();
                    blank.blank = true;
                    pages.Add(blank);
                }
                pages.Add(page);
            }
            layout.pages = pages;
            int front = 0;
            bool foundChapter = false;
            int[] blockPages = new int[document.blocks.Count], markPages = new int[indexMarks.Count + 1];
            for (int i = 0; i < pages.Count; i++) {
                Page page = pages[i];
                page.serial = i + 1;
                foreach (Line line in page.content)
                    if (line.first && line.origin != null) {
                        if (blockPages[line.origin.id] == 0)
                            blockPages[line.origin.id] = page.serial;
                        if (!foundChapter && line.origin.kind.Equals("h1")) {
                            front = page.serial - 1;
                            foundChapter = true;
                        }
                    }
            }
            foreach (Page page in pages) {
                page.display =
                    page.serial <= front ? Roman(page.serial) : Convert.ToString(page.serial - front);
                foreach (Line line in page.content)
                    foreach (int mark in line.indexes)
                        markPages[mark] = page.serial - front;
            }
            foreach (KeyValuePair<string, DocumentParser.Block> entry in labels)
                layout.labels[entry.Key] = pages[blockPages[entry.Value.id] - 1].display;
            foreach (Deferred item in deferred) {
                List<string> text = item.kind.Equals("index")
                                        ? IndexLines(markPages)
                                        : Entries(item.kind, item.block.width, blockPages, pages);
                for (int i = 0; i < text.Count; i++)
                    item.lines[i].text = text[i];
            }
            string chapter = "", section = "";
            int heading = 0;
            foreach (Page page in pages) {
                if (page.blank) {
                    for (int i = 0; i < document.height; i++)
                        page.body.Add("");
                    continue;
                }
                while (heading < headings.Count && blockPages[headings[heading].id] <= page.serial) {
                    DocumentParser.Block block = headings[heading++];
                    if (block.kind.Equals("h1")) {
                        chapter = block.number + " " + block.text;
                        section = "";
                    } else
                        section = block.number + " " + block.text;
                }
                Dictionary<string, string> values =
                    new Dictionary<string, string> { ["page"] = page.display,
                                                     ["pages"] = Convert.ToString(pages.Count - front),
                                                     ["chapter"] = chapter, ["section"] = section };
                bool chapterPage = page.content.Count != 0 && page.content[0].first &&
                                   page.content[0].origin != null && page.content[0].origin.kind.Equals("h1");
                page.header =
                    chapterPage ? "" : Renderer.Head(document.header, values, document.width, page.serial);
                page.footer = Renderer.Head(document.footer, values, document.width, page.serial);
                foreach (Line line in page.content)
                    page.body.Add(line.text);
                while (page.body.Count < document.height - (page.notes.Count == 0 ? 0 : 1) -
                                             FootnoteHeight(page.notes, footnoteLines))
                    page.body.Add("");
                if (page.notes.Count != 0) {
                    page.body.Add("----------");
                    foreach (int number in page.notes)
                        foreach (Line line in footnoteLines[number])
                            page.body.Add(line.text);
                }
            }
            return layout;
        }
        public int FootnoteHeight(List<int> numbers, Dictionary<int, List<Line>> lines) {
            int total = 0;
            foreach (int number in numbers)
                total += lines[number].Count;
            return total;
        }
        public Layout Layout(bool optimal) {
            Dictionary<string, string> values = new();
            foreach (string label in labels.Keys)
                values[label] = "??";
            Layout result;
            while (true) {
                result = Once(optimal, values);
                if (result.labels.Count == values.Count &&
                    result.labels.All(entry => values.TryGetValue(entry.Key, out string value) &&
                                               entry.Value == value))
                    break;
                values = result.labels;
            }
            string prefix = optimal ? "kp: " : "greedy: ";
            int hyphenated = 0;
            foreach (Broken broken in result.broken)
                for (int i = 0; i < broken.measures.Count; i++) {
                    Measure line = broken.measures[i];
                    if (broken.body && line.mid)
                        hyphenated++;
                    if (line.slack < 0)
                        result.warnings.Add(prefix + broken.name + " line " + (i + 1) + ": overfull by " +
                                            (-line.slack));
                    else if (broken.body && broken.align.Equals("justify") && !line.last &&
                             line.slack >= parameters["underfull_slack"])
                        result.warnings.Add(prefix + broken.name + " line " + (i + 1) +
                                            ": underfull, slack " + line.slack);
                }
            foreach (Page page in result.pages)
                if (!page.blank && !page.forced &&
                    document.height - page.height >= parameters["underfull_page"])
                    result.warnings.Add(prefix + "page " + page.serial + ": underfull, " +
                                        (document.height - page.height) + " empty lines");
            result.warnings.Add(prefix + result.pages.Count + " pages, " + hyphenated + " hyphenated lines");
            return result;
        }
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Dictionary<string, int> parameters = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)
                     .ToList()) {
            string[] parts = line.Split(" ");
            parameters[parts[0]] = int.Parse(parts[1]);
        }
        DocumentParser.Document document = DocumentParser.Parse(
            File.ReadAllLines(Path.Combine("input/document.txt"), Encoding.ASCII).ToList());
        Typesetter typesetter =
            new Typesetter(document, parameters,
                           File.ReadAllLines(Path.Combine("input/hyphenation.txt"), Encoding.ASCII).ToList());
        Layout kp = typesetter.Layout(true), greedy = typesetter.Layout(false);
        List<string> stats = new(["paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"]);
        int[] totals = new int[4];
        foreach (DocumentParser.Block block in typesetter.bodies) {
            Broken a = kp.bodies[block.paragraph], b = greedy.bodies[block.paragraph];
            int[] values = { a.measures.Count, a.cost, b.measures.Count, b.cost };
            string line = Convert.ToString(block.paragraph);
            for (int i = 0; i < 4; i++) {
                totals[i] += values[i];
                line += "," + values[i];
            }
            stats.Add(line);
        }
        stats.Add("total," + totals[0] + "," + totals[1] + "," + totals[2] + "," + totals[3]);
        List<string> log = new();
        foreach (DocumentParser.Warning warning in document.warnings)
            log.Add("line " + warning.line + ": " + warning.text);
        log.AddRange(kp.warnings);
        log.AddRange(greedy.warnings);
        Directory.CreateDirectory(Path.Combine("output"));
        Write("pages.txt", Renderer.Pages(kp.pages));
        Write("greedy_pages.txt", Renderer.Pages(greedy.pages));
        Write("stats.csv", stats);
        Write("log.txt", log);
    }
}
