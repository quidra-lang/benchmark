using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class DocumentParser {
    public static readonly HashSet<string> BODY =
        new HashSet<string> { "paragraph", "item", "enum", "quote", "term" };
    public static readonly HashSet<string>
        PREAMBLE = new HashSet<string> { "page", "header", "footer" },
        EMPTY = new HashSet<string> { "newpage", "verbatim", "toc", "lot", "index", "bibliography" },
        NAMES = new HashSet<string> { "width",    "indent",      "align", "page",  "header",      "footer",
                                      "newpage",  "hyphenation", "bib",   "title", "author",      "h1",
                                      "h2",       "item",        "enum",  "quote", "term",        "table",
                                      "verbatim", "toc",         "lot",   "index", "bibliography" };
    public sealed record Source(int line, string text);
    public sealed record Warning(int line, string text);
    public sealed class Bib {
        public int line;
        public string key, author, year, title, baseLabel, label;
        public bool cited;
        public Bib(int line, string key, string author, string year, string title) {
            this.line = line;
            this.key = key;
            this.author = author;
            this.year = year;
            this.title = title;
        }
    }
    public sealed class Block {
        public string kind, argument, align, term = "", columns = "", caption = "", text = "", label,
                                             number = "";
        public int line, width, indent, id, paragraph;
        public bool pageBreak;
        public readonly List<Source> body = new(), inner = new();
        public readonly List<Program.Token> tokens = new();
        public List<List<string>> tableRows = new();
        public List<string> tableLines = new();
    }
    public sealed class Document {
        public int height = 40, width = 60;
        public string[] header = { "", "", "" }, footer = { "", "", "" };
        public readonly List<Block> blocks = new();
        public readonly List<Warning> warnings = new();
        public readonly List<string> additions = new();
        public readonly List<Bib> bibliography = new();
    }
    public static bool Valid(string name, string argument) {
        if (new HashSet<string> { "width", "indent", "page" }.Contains(name)) {
            if (!argument.Matches("[0-9]{1,9}"))
                return false;
            int value = int.Parse(argument);
            return name.Equals("width")    ? value >= 20 && value <= 80
                   : name.Equals("indent") ? value <= 8
                                           : value >= 10 && value <= 100;
        }
        if (name.Equals("align"))
            return new HashSet<string> { "left", "right", "center", "justify" }.Contains(argument);
        if (name.Equals("header") || name.Equals("footer"))
            return argument.Split('|').Length == 3;
        if (EMPTY.Contains(name))
            return argument.Length == 0;
        if (name.Equals("hyphenation"))
            return argument.Matches("[a-z]+(-[a-z]+)*( [a-z]+(-[a-z]+)*)*");
        if (name.Equals("bib")) {
            int space = argument.IndexOf(' ');
            if (space < 0 || !argument.Substring(0, (space) - (0)).Matches("[a-z0-9]+"))
                return false;
            string[] fields = argument.Substring(space + 1).Split('|');
            return fields.Length == 3 && fields[0].Length != 0 && fields[1].Matches("[0-9]{4}") &&
                   fields[2].Length != 0;
        }
        if (name.Equals("term")) {
            int separator = argument.IndexOf('|');
            return separator > 0 && separator + 1 < argument.Length;
        }
        if (name.Equals("table"))
            return argument.Split(' ') [0].Matches("[lrc]+");
        return argument.Length != 0;
    }
    public sealed class State {
        public readonly Document document = new Document();
        public int width = 60, indent;
        public string align = "left";
        public bool pending;
        public Block Create(string kind, int line, string argument) {
            if (document.blocks.Count == 0)
                document.width = width;
            Block block = new Block();
            block.kind = kind;
            block.line = line;
            block.argument = argument;
            block.width = width;
            block.indent = indent;
            block.align = align;
            block.pageBreak = pending;
            pending = false;
            document.blocks.Add(block);
            return block;
        }
    }
    public static Document Parse(List<string> lines) {
        State state = new State();
        Document document = state.document;
        HashSet<string> accepted = new();
        Block open = null;
        for (int index = 0; index < lines.Count; index++) {
            string line = lines[index];
            int number = index + 1;
            if (line.Length == 0) {
                open = null;
                continue;
            }
            if (!line.StartsWith(".")) {
                if (open == null)
                    open = state.Create("paragraph", number, "");
                open.body.Add(new Source(number, line));
                continue;
            }
            open = null;
            int space = line.IndexOf(' ');
            string name = line.Substring(1, (space < 0 ? line.Length : space) - (1)),
                   argument = space < 0 ? "" : line.Substring(space + 1), warning = null;
            if (!NAMES.Contains(name))
                warning = "unknown directive ." + name;
            else if (!Valid(name, argument))
                warning = "bad argument for ." + name;
            else if (PREAMBLE.Contains(name) && document.blocks.Count != 0)
                warning = "." + name + " ignored after the preamble";
            else if (PREAMBLE.Contains(name) && accepted.Contains(name))
                warning = "duplicate ." + name;
            if (warning != null) {
                document.warnings.Add(new Warning(number, warning));
                continue;
            }
            if (name.Equals("width"))
                state.width = int.Parse(argument);
            else if (name.Equals("indent"))
                state.indent = int.Parse(argument);
            else if (name.Equals("align"))
                state.align = argument;
            else if (PREAMBLE.Contains(name)) {
                accepted.Add(name);
                if (name.Equals("page"))
                    document.height = int.Parse(argument);
                else if (name.Equals("header"))
                    document.header = argument.Split('|');
                else
                    document.footer = argument.Split('|');
            } else if (name.Equals("newpage"))
                state.pending = true;
            else if (name.Equals("hyphenation"))
                document.additions.AddRange([argument.Split(" ")]);
            else if (name.Equals("bib")) {
                int separator = argument.IndexOf(' ');
                string[] fields = argument.Substring(separator + 1).Split('|');
                document.bibliography.Add(new Bib(number, argument.Substring(0, (separator) - (0)), fields[0],
                                                  fields[1], fields[2]));
            } else {
                Block block = state.Create(name, number, argument);
                if (new HashSet<string> { "item", "enum", "quote" }.Contains(name)) {
                    block.body.Add(new Source(number, argument));
                    open = block;
                } else if (name.Equals("term")) {
                    int separator = argument.IndexOf('|');
                    block.term = argument.Substring(0, (separator) - (0));
                    block.body.Add(new Source(number, argument.Substring(separator + 1)));
                    open = block;
                } else if (name.Equals("verbatim") || name.Equals("table")) {
                    if (name.Equals("table")) {
                        int separator = argument.IndexOf(' ');
                        block.columns = separator < 0 ? argument : argument.Substring(0, (separator) - (0));
                        block.caption = separator < 0 ? "" : argument.Substring(separator + 1);
                    }
                    index++;
                    while (index < lines.Count && !lines[index].Equals(".end")) {
                        block.inner.Add(new Source(index + 1, lines[index]));
                        index++;
                    }
                    if (index == lines.Count)
                        document.warnings.Add(new Warning(number, "unterminated " + name));
                }
            }
        }
        return document;
    }
}
