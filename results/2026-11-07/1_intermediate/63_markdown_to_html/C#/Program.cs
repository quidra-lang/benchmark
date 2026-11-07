using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

static class Program
{
    const string Punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
    const string TocMarker = "\u0001toc\u0002";
    static bool Has(string set, char c) => set.Contains(c);
    static bool Alphanumeric(char c) =>
        c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9';
    static bool LabelCharacter(char c) => Alphanumeric(c) || c == '-' || c == '_';
    static bool Whitespace(char c) => c == ' ' || c == '\n';
    static bool Matches(string text, string pattern) => Regex.IsMatch(text,
                                                                      "\\A(?:" + pattern + ")\\z");
    static string Trim(string text) => text.Trim(' ');
    static string EscapeHtml(string text) => text.Replace("&", "&amp;")
                                                 .Replace("<", "&lt;")
                                                 .Replace(">", "&gt;")
                                                 .Replace("\"", "&quot;");
    static string StripTags(string text) => Regex.Replace(text, "<[^>]*>", "");
    static string Normalize(string text)
    {
        var result = new StringBuilder();
        bool space = false;
        foreach (char ch in text)
        {
            if (Whitespace(ch))
                space = result.Length > 0;
            else
            {
                if (space)
                    result.Append(' ');
                result.Append(char.ToLowerInvariant(ch));
                space = false;
            }
        }
        return result.ToString();
    }
    static int SkipSpace(string text, int at)
    {
        while (at < text.Length && Whitespace(text[at]))
            at++;
        return at;
    }
    sealed record Read(string Text, int End);
    static Read EscapedRead(string text, int at, string stops)
    {
        var result = new StringBuilder();
        while (at < text.Length && !Has(stops, text[at]))
        {
            if (text[at] == '\\' && at + 1 < text.Length && Has(Punctuation, text[at + 1]))
                at++;
            result.Append(text[at++]);
        }
        return new(result.ToString(), at);
    }
    enum Kind
    {
        Heading,
        Paragraph,
        Rule,
        Code,
        Quote,
        Alert,
        List,
        Table,
        Toc
    }
    sealed class Block
    {
        public Kind Kind;
        public string Text;
        public int Number;
        public bool Ordered;
        public List<string> Lines = new(), Alignments = new();
        public List<Block> Children = new();
        public List<List<Block>> Items = new();
        public List<List<string>> Rows = new();
        public Block(Kind kind, string text = "", int number = 0)
        {
            Kind = kind;
            Text = text;
            Number = number;
        }
    }
    sealed record Reference(string Url, string? Title);
    sealed record Fence(char Character, int Length, string Info);
    sealed record ListMarker(char Marker, bool Ordered, int Number, string Content);
    static Fence? OpeningFence(string line)
    {
        if (line.Length == 0 || !Has("`~", line[0]))
            return null;
        int end = 1;
        while (end < line.Length && line[end] == line[0])
            end++;
        if (end < 3)
            return null;
        string info = Trim(line[end..]);
        if (line[0] == '`' && info.Contains('`'))
            return null;
        return new(line[0], end, info);
    }
    static Block? AtxHeading(string line)
    {
        int n = 0;
        while (n < line.Length && line[n] == '#')
            n++;
        if (n < 1 || n > 6 || n < line.Length && line[n] != ' ')
            return null;
        string text = Trim(line[n..]);
        int end = text.Length;
        while (end > 0 && text[end - 1] == '#')
            end--;
        if (end == 0 || text[end - 1] == ' ')
            text = Trim(text[..end]);
        return new(Kind.Heading, text, n);
    }
    static bool IsRule(string line)
    {
        string compact = line.Replace(" ", "");
        return compact.Length >= 3 && Has("-*_", compact[0]) && compact.All(c => c == compact[0]);
    }
    static readonly Regex ListItem = new("\\A(?:([-*+])|([0-9]{1,9})([.)])) +");
    static ListMarker? Marker(string line)
    {
        if (IsRule(line))
            return null;
        Match match = ListItem.Match(line);
        if (!match.Success)
            return null;
        bool ordered = match.Groups[2].Success;
        return new((ordered ? match.Groups[3].Value : match.Groups[1].Value)[0], ordered,
                   ordered ? int.Parse(match.Groups[2].Value) : 1, line[match.Length..]);
    }
    static bool Interrupts(string line) => line.Length > 0 && line[0] != ' ' &&
                                           (OpeningFence(line) != null ||
                                            AtxHeading(line) != null || IsRule(line) ||
                                            line[0] == '>' || Marker(line) != null);
    static List<string> SplitCells(string line)
    {
        string text = Trim(line);
        int at = text.StartsWith('|') ? 1 : 0;
        var cells = new List<string>();
        var cell = new StringBuilder();
        bool finalSeparator = false;
        while (at < text.Length)
        {
            char ch = text[at++];
            finalSeparator = false;
            if (ch == '\\' && at < text.Length)
            {
                if (text[at] != '|')
                    cell.Append('\\');
                cell.Append(text[at++]);
            }
            else if (ch == '|')
            {
                cells.Add(Trim(cell.ToString()));
                cell.Clear();
                finalSeparator = true;
            }
            else
                cell.Append(ch);
        }
        if (!finalSeparator)
            cells.Add(Trim(cell.ToString()));
        return cells;
    }
    sealed class BlockParser
    {
        public readonly Dictionary<string, Reference> References = new();
        public readonly Dictionary<string, string> Footnotes = new();
        bool Definition(string line)
        {
            Match footnote = Regex.Match(line, "\\A\\[\\^([A-Za-z0-9_-]+)\\]:(.*)\\z");
            if (footnote.Success && Trim(footnote.Groups[2].Value).Length > 0)
            {
                Footnotes.TryAdd(footnote.Groups[1].Value.ToLowerInvariant(),
                                 Trim(footnote.Groups[2].Value));
                return true;
            }
            if (!line.StartsWith('['))
                return false;
            int close = line.IndexOf(']');
            if (close < 0 || close + 1 >= line.Length || line[close + 1] != ':')
                return false;
            string label = line[1..close];
            if (label.Contains('[') || Trim(label).Length == 0 || label.StartsWith('^'))
                return false;
            Read url = EscapedRead(line, SkipSpace(line, close + 2), " ");
            if (url.Text.Length == 0)
                return false;
            int at = SkipSpace(line, url.End);
            string? title = null;
            if (at < line.Length)
            {
                if (at == url.End || !Has("\"'", line[at]))
                    return false;
                Read quoted = EscapedRead(line, at + 1, line[at].ToString());
                if (quoted.End != line.Length - 1)
                    return false;
                title = quoted.Text;
            }
            References.TryAdd(Normalize(label), new(url.Text, title));
            return true;
        }
        public List<Block> Parse(List<string> lines)
        {
            var blocks = new List<Block>();
            int at = 0;
            while (at < lines.Count)
            {
                string line = lines[at];
                if (line.Length == 0)
                {
                    at++;
                    continue;
                }
                if (line.StartsWith("    "))
                {
                    var code = new Block(Kind.Code);
                    int end = at;
                    while (end < lines.Count &&
                           (lines[end].Length == 0 || lines[end].StartsWith("    ")))
                        end++;
                    while (end > at && lines[end - 1].Length == 0)
                        end--;
                    while (at < end)
                    {
                        string row = lines[at++];
                        code.Lines.Add(row.Length == 0 ? "" : row[4..]);
                    }
                    blocks.Add(code);
                    continue;
                }
                if (line[0] != ' ')
                {
                    Fence? fence = OpeningFence(line);
                    if (fence != null)
                    {
                        var code = new Block(Kind.Code, fence.Info.Split(' ')[0]);
                        at++;
                        while (at < lines.Count)
                        {
                            string row = lines[at++];
                            if (row.Length >= fence.Length && row.All(c => c == fence.Character))
                                break;
                            code.Lines.Add(row);
                        }
                        blocks.Add(code);
                        continue;
                    }
                    Block? heading = AtxHeading(line);
                    if (heading != null)
                    {
                        blocks.Add(heading);
                        at++;
                        continue;
                    }
                    if (IsRule(line))
                    {
                        blocks.Add(new(Kind.Rule));
                        at++;
                        continue;
                    }
                    if (line.StartsWith('>'))
                    {
                        var content = new List<string>();
                        while (at < lines.Count && lines[at].StartsWith('>'))
                        {
                            string row = lines[at++][1..];
                            if (row.StartsWith(' '))
                                row = row[1..];
                            content.Add(row);
                        }
                        var quote = new Block(Kind.Quote);
                        if (Matches(content[0], "\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]"))
                        {
                            quote.Kind = Kind.Alert;
                            quote.Text = content[0][2.. ^ 1];
                            content.RemoveAt(0);
                        }
                        quote.Children = Parse(content);
                        blocks.Add(quote);
                        continue;
                    }
                    ListMarker? marker = Marker(line);
                    if (marker != null)
                    {
                        var list = new Block(Kind.List, "", marker.Number);
                        list.Ordered = marker.Ordered;
                        char kind = marker.Marker;
                        while (true)
                        {
                            var content = new List<string> { marker.Content };
                            at++;
                            while (at < lines.Count && lines[at].StartsWith("  "))
                                content.Add(lines[at++][2..]);
                            list.Items.Add(Parse(content));
                            int next = at;
                            while (next < lines.Count && lines[next].Length == 0)
                                next++;
                            marker = next < lines.Count ? Marker(lines[next]) : null;
                            if (marker == null || marker.Marker != kind ||
                                marker.Ordered != list.Ordered)
                                break;
                            at = next;
                        }
                        blocks.Add(list);
                        continue;
                    }
                    if (Definition(line))
                    {
                        at++;
                        continue;
                    }
                    if (at + 1 < lines.Count && line.Contains('|') && lines[at + 1].Contains('|'))
                    {
                        List<string> header = SplitCells(line),
                                     delimiters = SplitCells(lines[at + 1]);
                        if (header.Count == delimiters.Count &&
                            delimiters.All(c => Matches(c, ":?-+:?")))
                        {
                            var table = new Block(Kind.Table);
                            table.Lines = header;
                            foreach (string cell in delimiters)
                            {
                                bool left = cell.StartsWith(':'), right = cell.EndsWith(':');
                                table.Alignments.Add(left ? (right ? "center" : "left")
                                                          : (right ? "right" : ""));
                            }
                            at += 2;
                            while (at < lines.Count && lines[at].Contains('|'))
                            {
                                List<string> row = SplitCells(lines[at++]);
                                while (row.Count < delimiters.Count)
                                    row.Add("");
                                table.Rows.Add(row.Take(delimiters.Count).ToList());
                            }
                            blocks.Add(table);
                            continue;
                        }
                    }
                }
                var text = new List<string> { line.TrimStart(' ') };
                at++;
                int level = 0;
                while (at < lines.Count && lines[at].Length > 0)
                {
                    string row = lines[at];
                    if (Matches(row, "={3,}|-{3,}"))
                    {
                        level = row[0] == '=' ? 1 : 2;
                        at++;
                        break;
                    }
                    if (Interrupts(row))
                        break;
                    text.Add(row.TrimStart(' '));
                    at++;
                }
                string combined = string.Join("\n", text);
                blocks.Add(new(level != 0            ? Kind.Heading
                               : combined == "[TOC]" ? Kind.Toc
                                                     : Kind.Paragraph,
                               combined, level));
            }
            return blocks;
        }
    }
    static int RunEnd(string text, int at)
    {
        char ch = text[at++];
        while (at < text.Length && text[at] == ch)
            at++;
        return at;
    }
    static int BacktickCloser(string text, int at, int length)
    {
        while ((at = text.IndexOf('`', at)) >= 0)
        {
            int end = RunEnd(text, at);
            if (end - at == length)
                return at;
            at = end;
        }
        return -1;
    }
    static int ClosingBracket(string text, int at)
    {
        int depth = 0;
        while (at < text.Length)
        {
            char ch = text[at];
            if (ch == '\\')
            {
                at += 2;
                continue;
            }
            if (ch == '`')
            {
                int end = RunEnd(text, at), close = BacktickCloser(text, end, end - at);
                at = close < 0 ? end : close + end - at;
                continue;
            }
            if (ch == '[')
                depth++;
            if (ch == ']' && --depth == 0)
                return at;
            at++;
        }
        return -1;
    }
    sealed record Piece(string Html, char Delimiter = '\0', int Length = 0, bool CanOpen = false,
                        bool CanClose = false);
    static void Emphasis(StringBuilder html, List<Piece> pieces, int begin, int end)
    {
        for (int at = begin; at < end; at++)
        {
            Piece piece = pieces[at];
            if (piece.Delimiter == 0)
            {
                html.Append(piece.Html);
                continue;
            }
            int close = at + 1;
            if (piece.CanOpen)
            {
                while (close < end &&
                       !(pieces[close].Delimiter == piece.Delimiter &&
                         pieces[close].Length == piece.Length && pieces[close].CanClose))
                    close++;
            }
            else
                close = end;
            if (close == end)
            {
                html.Append(piece.Delimiter, piece.Length);
                continue;
            }
            string open, shut;
            if (piece.Delimiter == '~')
            {
                open = "<del>";
                shut = "</del>";
            }
            else if (piece.Length == 1)
            {
                open = "<em>";
                shut = "</em>";
            }
            else if (piece.Length == 2)
            {
                open = "<strong>";
                shut = "</strong>";
            }
            else
            {
                open = "<em><strong>";
                shut = "</strong></em>";
            }
            html.Append(open);
            Emphasis(html, pieces, at + 1, close);
            html.Append(shut);
            at = close;
        }
    }
    sealed record Destination(Reference Reference, int End);
    sealed class Heading
    {
        public int Level;
        public string Id, Label;
        public List<Heading> Children = new();
        public Heading(int level, string id, string label)
        {
            Level = level;
            Id = id;
            Label = label;
        }
    }
    sealed class Note
    {
        public string Name;
        public int Count;
        public Note(string name)
        {
            Name = name;
        }
    }
    sealed class Renderer
    {
        readonly BlockParser parser;
        readonly HashSet<string> usedIds = new();
        readonly List<Heading> headings = new();
        readonly Dictionary<string, int> noteNumbers = new();
        readonly List<Note> notes = new();
        public Renderer(BlockParser parser)
        {
            this.parser = parser;
        }
        static string ReferenceId(int number, int count) => "fnref-" + number +
                                                            (count == 1 ? "" : "-" + count);
        string FootnoteReference(string name)
        {
            if (!noteNumbers.ContainsKey(name))
            {
                noteNumbers[name] = notes.Count;
                notes.Add(new(name));
            }
            int index = noteNumbers[name], number = index + 1;
            Note note = notes[index];
            return "<sup id=\"" + ReferenceId(number, ++note.Count) + "\"><a href=\"#fn-" + number +
                   "\">" + number + "</a></sup>";
        }
        Destination? GetDestination(string text, int at, string label)
        {
            if (at < text.Length && text[at] == '[')
            {
                int close = text.IndexOf(']', at + 1);
                if (close >= 0 && !text[(at + 1)..close].Contains('['))
                {
                    string key = text[(at + 1)..close];
                    key = Normalize(key.Length == 0 ? label : key);
                    if (parser.References.TryGetValue(key, out Reference? reference))
                        return new(reference, close + 1);
                    return null;
                }
            }
            else if (at < text.Length && text[at] == '(')
            {
                Read url = EscapedRead(text, SkipSpace(text, at + 1), " \n)");
                int next = SkipSpace(text, url.End);
                string? title = null;
                bool valid = true;
                if (next > url.End && next < text.Length && Has("\"'", text[next]))
                {
                    Read quoted = EscapedRead(text, next + 1, text[next].ToString());
                    if (quoted.End == text.Length)
                        valid = false;
                    else
                    {
                        title = quoted.Text;
                        next = SkipSpace(text, quoted.End + 1);
                    }
                }
                if (valid && next < text.Length && text[next] == ')')
                    return new(new(url.Text, title), next + 1);
            }
            if (parser.References.TryGetValue(Normalize(label), out Reference? shortcut))
                return new(shortcut, at);
            return null;
        }
        string Inline(string text, bool links = true, bool footnotes = true)
        {
            var pieces = new List<Piece>();
            int at = 0;
            while (at < text.Length)
            {
                char ch = text[at];
                if (ch == '\\')
                {
                    if (at + 1 < text.Length && Has(Punctuation, text[at + 1]))
                    {
                        pieces.Add(new(EscapeHtml(text.Substring(at + 1, 1))));
                        at += 2;
                    }
                    else if (at + 1 < text.Length && text[at + 1] == '\n')
                    {
                        pieces.Add(new("<br />\n"));
                        at += 2;
                    }
                    else
                    {
                        pieces.Add(new("\\"));
                        at++;
                    }
                    continue;
                }
                if (ch == '`')
                {
                    int end = RunEnd(text, at), close = BacktickCloser(text, end, end - at);
                    if (close < 0)
                    {
                        pieces.Add(new(text[at..end]));
                        at = end;
                    }
                    else
                    {
                        string code = text[end..close].Replace('\n', ' ');
                        if (code.StartsWith(' ') && code.EndsWith(' ') && Trim(code).Length > 0)
                            code = code[1.. ^ 1];
                        pieces.Add(new("<code>" + EscapeHtml(code) + "</code>"));
                        at = close + end - at;
                    }
                    continue;
                }
                if (links && ch == '<')
                {
                    int close = text.IndexOf('>', at + 1);
                    if (close >= 0)
                    {
                        string target = text[(at + 1)..close];
                        string? href = null;
                        if (!target.Any(c => Has(" \n<", c)) &&
                            (target.StartsWith("http://", StringComparison.Ordinal) &&
                                 target.Length > 7 ||
                             target.StartsWith("https://", StringComparison.Ordinal) &&
                                 target.Length > 8))
                            href = target;
                        if (href == null &&
                            Matches(target, "[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+"))
                            href = "mailto:" + target;
                        if (href != null)
                        {
                            pieces.Add(new("<a href=\"" + EscapeHtml(href) + "\">" +
                                           EscapeHtml(target) + "</a>"));
                            at = close + 1;
                            continue;
                        }
                    }
                }
                if (links &&
                    (text.AsSpan(at).StartsWith("http://", StringComparison.Ordinal) ||
                     text.AsSpan(at).StartsWith("https://", StringComparison.Ordinal)) &&
                    (at == 0 || Has(" \n*_~(", text[at - 1])))
                {
                    int end = at;
                    while (end < text.Length && !Has(" \n<", text[end]))
                        end++;
                    while (end > at && Has(".,:;!?*_~)", text[end - 1]))
                        end--;
                    string url = text[at..end];
                    if (url != "http://" && url != "https://")
                    {
                        string escaped = EscapeHtml(url);
                        pieces.Add(new("<a href=\"" + escaped + "\">" + escaped + "</a>"));
                        at = end;
                        continue;
                    }
                }
                if (ch == '[' || ch == '!' && at + 1 < text.Length && text[at + 1] == '[')
                {
                    if (links && footnotes &&
                        text.AsSpan(at).StartsWith("[^", StringComparison.Ordinal))
                    {
                        int close = text.IndexOf(']', at + 2);
                        if (close >= 0)
                        {
                            string name = text[(at + 2)..close].ToLowerInvariant();
                            if (parser.Footnotes.ContainsKey(name))
                            {
                                pieces.Add(new(FootnoteReference(name)));
                                at = close + 1;
                                continue;
                            }
                        }
                    }
                    bool image = ch == '!';
                    int opening = at + (image ? 1 : 0), closing = ClosingBracket(text, opening);
                    if ((image || links) && closing >= 0)
                    {
                        string label = text[(opening + 1)..closing];
                        Destination? dest = GetDestination(text, closing + 1, label);
                        if (dest != null)
                        {
                            string content = Inline(label, false, false),
                                   url = EscapeHtml(dest.Reference.Url);
                            string title =
                                dest.Reference.Title == null
                                    ? ""
                                    : " title=\"" + EscapeHtml(dest.Reference.Title) + "\"";
                            pieces.Add(new(image ? "<img src=\"" + url + "\" alt=\"" +
                                                       StripTags(content) + "\"" + title + " />"
                                                 : "<a href=\"" + url + "\"" + title + ">" +
                                                       content + "</a>"));
                            at = dest.End;
                            continue;
                        }
                    }
                }
                if (Has("*_~", ch))
                {
                    int end = RunEnd(text, at), length = end - at;
                    char before = at == 0 ? ' ' : text[at - 1],
                         after = end == text.Length ? ' ' : text[end];
                    bool open = !Whitespace(after), close = !Whitespace(before);
                    if (ch == '_' && Alphanumeric(before) && Alphanumeric(after))
                        open = close = false;
                    pieces.Add(ch != '~' && length <= 3 || ch == '~' && length == 2
                                   ? new("", ch, length, open, close)
                                   : new(text[at..end]));
                    at = end;
                    continue;
                }
                pieces.Add(new(EscapeHtml(text.Substring(at, 1))));
                at++;
            }
            var html = new StringBuilder();
            Emphasis(html, pieces, 0, pieces.Count);
            return html.ToString();
        }
        string RenderBlocks(List<Block> blocks)
        {
            var html = new StringBuilder();
            foreach (Block block in blocks)
                html.Append(Render(block)).Append('\n');
            return html.ToString();
        }
        string RenderHeading(Block block)
        {
            string text = block.Text;
            string? id = null;
            int explicitId = text.LastIndexOf(" {#", StringComparison.Ordinal);
            if (text.EndsWith('}') && explicitId >= 0)
            {
                string candidate = text[(explicitId + 3)..^ 1];
                if (candidate.Length > 0 && candidate.All(LabelCharacter))
                {
                    id = candidate;
                    text = text[..explicitId].TrimEnd(' ');
                }
            }
            if (id == null)
            {
                var slug = new StringBuilder();
                foreach (char original in text)
                {
                    char c = char.ToLowerInvariant(original);
                    if (LabelCharacter(c))
                        slug.Append(c);
                    else if (Whitespace(c))
                        slug.Append('-');
                }
                string baseId = slug.Length == 0 ? "heading" : slug.ToString();
                id = baseId;
                for (int suffix = 1; usedIds.Contains(id); suffix++)
                    id = baseId + "-" + suffix;
            }
            usedIds.Add(id);
            string html = Inline(text);
            headings.Add(new(block.Number, id, StripTags(html)));
            return "<h" + block.Number + " id=\"" + id + "\">" + html + "</h" + block.Number + ">";
        }
        string RenderItem(List<Block> blocks)
        {
            var html = new StringBuilder("<li>");
            for (int i = 0; i < blocks.Count; i++)
            {
                Block block = blocks[i];
                if (block.Kind == Kind.Paragraph)
                {
                    string text = block.Text;
                    if (i == 0 && text.Length > 4 &&
                        (text.StartsWith("[ ] ") || text.StartsWith("[x] ") ||
                         text.StartsWith("[X] ")))
                    {
                        html.Append(
                            text[1] == ' '
                                ? "<input type=\"checkbox\" disabled=\"\" /> "
                                : "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ");
                        text = text[4..];
                    }
                    html.Append(Inline(text));
                }
                else
                {
                    if (html[html.Length - 1] != '\n')
                        html.Append('\n');
                    html.Append(Render(block)).Append('\n');
                }
            }
            return html.Append("</li>").ToString();
        }
        string TableCells(string tag, Block table, List<string> cells)
        {
            var html = new StringBuilder();
            for (int i = 0; i < cells.Count; i++)
            {
                string alignment = table.Alignments[i];
                html.Append('<').Append(tag);
                if (alignment.Length > 0)
                    html.Append(" style=\"text-align:").Append(alignment).Append('"');
                html.Append('>').Append(Inline(cells[i])).Append("</").Append(tag).Append(">\n");
            }
            return html.ToString();
        }
        string Render(Block block)
        {
            switch (block.Kind)
            {
            case Kind.Heading:
                return RenderHeading(block);
            case Kind.Paragraph:
                return "<p>" + Inline(block.Text) + "</p>";
            case Kind.Rule:
                return "<hr />";
            case Kind.Code: {
                var html = new StringBuilder("<pre><code");
                if (block.Text.Length > 0)
                    html.Append(" class=\"language-").Append(EscapeHtml(block.Text)).Append('"');
                html.Append('>');
                foreach (string line in block.Lines)
                    html.Append(EscapeHtml(line)).Append('\n');
                return html.Append("</code></pre>").ToString();
            }
            case Kind.Quote:
                return "<blockquote>\n" + RenderBlocks(block.Children) + "</blockquote>";
            case Kind.Alert: {
                string name = block.Text.ToLowerInvariant(),
                       title = char.ToUpperInvariant(name[0]) + name[1..];
                return "<div class=\"alert alert-" + name + "\">\n<p class=\"alert-title\">" +
                       title + "</p>\n" + RenderBlocks(block.Children) + "</div>";
            }
            case Kind.List: {
                string tag = block.Ordered ? "ol" : "ul";
                var html = new StringBuilder("<" + tag);
                if (block.Ordered && block.Number != 1)
                    html.Append(" start=\"").Append(block.Number).Append('"');
                html.Append(">\n");
                foreach (List<Block> item in block.Items)
                    html.Append(RenderItem(item)).Append('\n');
                return html.Append("</").Append(tag).Append('>').ToString();
            }
            case Kind.Table: {
                var html = new StringBuilder("<table>\n<thead>\n<tr>\n");
                html.Append(TableCells("th", block, block.Lines)).Append("</tr>\n</thead>\n");
                if (block.Rows.Count > 0)
                {
                    html.Append("<tbody>\n");
                    foreach (List<string> row in block.Rows)
                        html.Append("<tr>\n")
                            .Append(TableCells("td", block, row))
                            .Append("</tr>\n");
                    html.Append("</tbody>\n");
                }
                return html.Append("</table>").ToString();
            }
            case Kind.Toc:
                return TocMarker;
            default:
                throw new InvalidOperationException();
            }
        }
        string TocList(List<Heading> entries)
        {
            var html = new StringBuilder("<ul>\n");
            foreach (Heading entry in entries)
            {
                html.Append("<li><a href=\"#")
                    .Append(entry.Id)
                    .Append("\">")
                    .Append(entry.Label)
                    .Append("</a>");
                if (entry.Children.Count > 0)
                    html.Append('\n').Append(TocList(entry.Children)).Append('\n');
                html.Append("</li>\n");
            }
            return html.Append("</ul>").ToString();
        }
        string TableOfContents()
        {
            if (headings.Count == 0)
                return "<nav class=\"toc\">\n</nav>";
            var roots = new List<Heading>();
            var parents = new List<Heading>();
            foreach (Heading heading in headings)
            {
                while (parents.Count > 0 && parents[^1].Level >= heading.Level)
                    parents.RemoveAt(parents.Count - 1);
                if (parents.Count == 0)
                    roots.Add(heading);
                else
                    parents[^1].Children.Add(heading);
                parents.Add(heading);
            }
            return "<nav class=\"toc\">\n" + TocList(roots) + "\n</nav>";
        }
        string FootnoteList()
        {
            var html = new StringBuilder("<section class=\"footnotes\">\n<ol>\n");
            for (int i = 0; i < notes.Count; i++)
            {
                Note note = notes[i];
                int number = i + 1;
                html.Append("<li id=\"fn-")
                    .Append(number)
                    .Append("\">")
                    .Append(Inline(parser.Footnotes[note.Name], true, false));
                for (int count = 1; count <= note.Count; count++)
                    html.Append(" <a href=\"#")
                        .Append(ReferenceId(number, count))
                        .Append("\">&#8617;</a>");
                html.Append("</li>\n");
            }
            return html.Append("</ol>\n</section>\n").ToString();
        }
        public string Document(List<Block> blocks)
        {
            string html = RenderBlocks(blocks);
            html = html.Replace(TocMarker, TableOfContents());
            return notes.Count == 0 ? html : html + FootnoteList();
        }
    }
    static void Main()
    {
        var lines = new List<string>();
        string? line;
        while ((line = Console.ReadLine()) != null && line != "@@END@@")
            lines.Add(line);
        var parser = new BlockParser();
        List<Block> blocks = parser.Parse(lines);
        Console.Write(new Renderer(parser).Document(blocks));
    }
}
