import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
public final class Main {
    record Token(String kind, String argument, int number) {}
    record Mark(int word, int position, boolean footnote, int number) {}
    record RawMark(int position, boolean footnote, int number) {}
    record Expanded(List<String> words, List<Mark> marks) {}
    static final class Break {
        int sw, sc, ew, ec;
        boolean mid, hyphen;
        Break(int sw, int sc, int ew, int ec, boolean mid, boolean hyphen) {
            this.sw = sw;
            this.sc = sc;
            this.ew = ew;
            this.ec = ec;
            this.mid = mid;
            this.hyphen = hyphen;
        }
    }
    static final class Measure {
        int start, end, slack;
        boolean last, mid;
        List<String> pieces = new ArrayList<>();
        List<int[]> ranges = new ArrayList<>();
    }
    static final class Metrics {
        final List<String> words;
        final int first, later;
        final int[] offsets;
        final List<Break> breaks = new ArrayList<>();
        Metrics(List<String> words, int first, int later, Hyphenation dictionary) {
            this.words = words;
            this.first = first;
            this.later = later;
            offsets = new int[words.size()];
            breaks.add(new Break(0, 0, 0, 0, false, false));
            int offset = 0;
            for (int i = 0; i < words.size(); i++) {
                String word = words.get(i);
                offsets[i] = offset;
                offset += word.length() + 1;
                for (Map.Entry<Integer, Boolean> split : dictionary.points(word).entrySet())
                    breaks.add(new Break(i, split.getKey(), i, split.getKey(), true, split.getValue()));
                breaks.add(new Break(i + 1, 0, i, word.length(), false, false));
            }
        }
        int end() {
            return breaks.size() - 1;
        }
        int slack(int start, int end) {
            Break a = breaks.get(start), b = breaks.get(end);
            int length = offsets[b.ew] + b.ec - offsets[a.sw] - a.sc + (b.hyphen ? 1 : 0);
            return (start == 0 ? first : later) - length;
        }
        Measure measure(int start, int end) {
            Measure result = new Measure();
            result.start = start;
            result.end = end;
            result.slack = slack(start, end);
            result.last = end == end();
            result.mid = breaks.get(end).mid;
            Break a = breaks.get(start), b = breaks.get(end);
            for (int word = a.sw; word <= b.ew; word++) {
                int first = word == a.sw ? a.sc : 0, last = word == b.ew ? b.ec : words.get(word).length();
                result.pieces.add(words.get(word).substring(first, last));
                result.ranges.add(new int[] {word, first, last});
            }
            if (b.hyphen)
                result.pieces.set(result.pieces.size() - 1, result.pieces.getLast() + "-");
            return result;
        }
    }
    static final class Line {
        String text;
        DocumentParser.Block origin;
        boolean first;
        final List<Integer> footnotes = new ArrayList<>(), indexes = new ArrayList<>();
        Line(String text) {
            this.text = text;
        }
    }
    static final class Broken {
        String name, align;
        boolean body;
        int cost;
        final List<Measure> measures = new ArrayList<>();
        final List<Line> lines = new ArrayList<>();
    }
    static final class LayoutBlock {
        String kind;
        boolean list, forced;
        List<Line> lines;
        LayoutBlock(String kind, boolean list, boolean forced, List<Line> lines) {
            this.kind = kind;
            this.list = list;
            this.forced = forced;
            this.lines = lines;
        }
    }
    static final class Page {
        List<Line> content = new ArrayList<>();
        List<Integer> notes = new ArrayList<>();
        List<String> body = new ArrayList<>();
        int height, serial;
        boolean forced, blank;
        String header = "", footer = "", display = "";
    }
    static final class IndexEntry {
        String name;
        final List<Integer> marks = new ArrayList<>();
        final SortedSet<String> see = new TreeSet<>();
        final Map<String, IndexEntry> children = new HashMap<>();
        IndexEntry(String name) {
            this.name = name;
        }
    }
    record Deferred(String kind, DocumentParser.Block block, List<Line> lines) {}
    static final class Layout {
        List<Page> pages;
        final Map<String, String> labels = new HashMap<>();
        final Map<Integer, Broken> bodies = new HashMap<>();
        final List<Broken> broken = new ArrayList<>();
        final List<String> warnings = new ArrayList<>();
    }
    static List<String> words(String text) {
        List<String> result = new ArrayList<>();
        for (String word : text.split(" "))
            if (!word.isEmpty())
                result.add(word);
        return result;
    }
    static List<Line> lines(List<String> text, DocumentParser.Block origin) {
        List<Line> result = new ArrayList<>();
        for (int i = 0; i < text.size(); i++) {
            Line line = new Line(text.get(i));
            line.origin = origin;
            line.first = i == 0;
            result.add(line);
        }
        return result;
    }
    static String[] splitLabel(String text) {
        int position = text.lastIndexOf(" {#");
        return text.endsWith("}") && position >= 0
            ? new String[] {text.substring(0, position), text.substring(position + 3, text.length() - 1)}
            : new String[] {text, null};
    }
    static String roman(int number) {
        String[] small = {"", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"};
        return "x".repeat(number / 10) + small[number % 10];
    }
    static final class Typesetter {
        final DocumentParser.Document document;
        final Map<String, Integer> params;
        final Hyphenation dictionary;
        final Map<String, DocumentParser.Block> labels = new HashMap<>();
        final Map<String, DocumentParser.Bib> bibliography = new LinkedHashMap<>();
        final List<DocumentParser.Bib> cited = new ArrayList<>();
        final List<DocumentParser.Block> bodies = new ArrayList<>(), headings = new ArrayList<>(),
                                         tables = new ArrayList<>();
        final List<String> footnotes = new ArrayList<>(), indexMarks = new ArrayList<>();
        final Map<String, IndexEntry> index = new HashMap<>();
        Typesetter(DocumentParser.Document document, Map<String, Integer> params, List<String> hyphenation) {
            this.document = document;
            this.params = params;
            dictionary = new Hyphenation(hyphenation, document.additions, params.get("left_min"),
                                         params.get("right_min"));
            register();
            check();
            bibliographyLabels();
            prepareIndex();
            document.warnings.sort(Comparator.comparingInt(DocumentParser.Warning::line));
        }
        void warn(int line, String text) {
            document.warnings.add(new DocumentParser.Warning(line, text));
        }
        void register() {
            int chapter = 0, section = 0, table = 0;
            DocumentParser.Block previous = null;
            for (int i = 0; i < document.blocks.size(); i++) {
                DocumentParser.Block block = document.blocks.get(i);
                block.id = i;
                if (block.kind.equals("h1") || block.kind.equals("h2")) {
                    String[] parts = splitLabel(block.argument);
                    block.text = parts[0];
                    block.label = parts[1];
                    if (block.kind.equals("h1")) {
                        chapter++;
                        section = 0;
                        block.number = Integer.toString(chapter);
                        if (i > 0)
                            block.pageBreak = true;
                    } else {
                        section++;
                        block.number = chapter + "." + section;
                    }
                    headings.add(block);
                } else if (block.kind.equals("enum"))
                    block.number = Integer.toString(previous != null && previous.kind.equals("enum")
                                                        ? Integer.parseInt(previous.number) + 1
                                                        : 1);
                else if (block.kind.equals("table")) {
                    String[] parts = splitLabel(block.caption);
                    block.caption = parts[0];
                    block.label = parts[1];
                    if (!block.caption.isEmpty()) {
                        table++;
                        block.number = Integer.toString(table);
                        tables.add(block);
                    }
                }
                if (block.label != null) {
                    if (labels.containsKey(block.label)) {
                        warn(block.line, "duplicate label " + block.label);
                        block.label = null;
                    } else
                        labels.put(block.label, block);
                }
                if (block.kind.equals("paragraph") && previous != null &&
                    (previous.kind.equals("h1") || previous.kind.equals("h2")))
                    block.indent = 0;
                if (DocumentParser.BODY.contains(block.kind)) {
                    bodies.add(block);
                    block.paragraph = bodies.size();
                }
                previous = block;
            }
            for (DocumentParser.Bib entry : document.bibliography) {
                if (bibliography.containsKey(entry.key))
                    warn(entry.line, "duplicate bibliography key " + entry.key);
                else
                    bibliography.put(entry.key, entry);
            }
        }
        Token command(String kind, String argument, int line) {
            if ((kind.equals("ref") || kind.equals("page")) && !labels.containsKey(argument))
                warn(line, "undefined label " + argument);
            if (kind.equals("cite"))
                for (String key : argument.split(",")) {
                    if (bibliography.containsKey(key))
                        bibliography.get(key).cited = true;
                    else
                        warn(line, "undefined citation " + key);
                }
            if (kind.equals("fn")) {
                footnotes.add(argument);
                return new Token(kind, "", footnotes.size());
            }
            if (kind.equals("idx")) {
                indexMarks.add(argument);
                return new Token(kind, "", indexMarks.size());
            }
            return new Token(kind, argument, 0);
        }
        void parseBody(DocumentParser.Block block, DocumentParser.Source source) {
            String text = source.text();
            int position = 0;
            while (position < text.length()) {
                int opening = text.indexOf('{', position);
                if (opening < 0) {
                    block.tokens.add(new Token("", text.substring(position), 0));
                    break;
                }
                if (opening > position)
                    block.tokens.add(new Token("", text.substring(position, opening), 0));
                int closing = text.indexOf('}', opening + 1);
                if (closing < 0) {
                    warn(source.line(), "unclosed brace");
                    block.tokens.add(new Token("", text.substring(opening), 0));
                    break;
                }
                String content = text.substring(opening + 1, closing);
                int colon = content.indexOf(':');
                String name = colon < 0 ? content : content.substring(0, colon),
                       argument = colon < 0 ? "" : content.substring(colon + 1);
                if (Set.of("ref", "page", "fn", "idx", "cite").contains(name) && colon >= 0 &&
                    !argument.isEmpty())
                    block.tokens.add(command(name, argument, source.line()));
                else
                    warn(source.line(), "bad command {" + content + "}");
                position = closing + 1;
            }
        }
        void check() {
            for (DocumentParser.Block block : document.blocks) {
                if (block.kind.equals("table")) {
                    int columns = block.columns.length();
                    for (DocumentParser.Source source : block.inner) {
                        String[] cells = source.text().split("\\|", -1);
                        if (cells.length != columns)
                            warn(source.line(),
                                 "table row has " + cells.length + " cells, expected " + columns);
                        List<String> row = new ArrayList<>();
                        for (int i = 0; i < columns; i++)
                            row.add(i < cells.length ? cells[i].strip() : "");
                        block.tableRows.add(row);
                    }
                    block.tableLines =
                        Renderer.table(block.tableRows, block.columns, block.caption, block.number);
                    int width = 0;
                    for (String line : block.tableLines)
                        width = Math.max(width, line.length());
                    if (width > block.width)
                        warn(block.line, "table too wide by " + (width - block.width));
                } else if (block.kind.equals("verbatim")) {
                    for (DocumentParser.Source source : block.inner)
                        if (source.text().length() > block.width)
                            warn(source.line(),
                                 "verbatim line too long by " + (source.text().length() - block.width));
                } else if (DocumentParser.BODY.contains(block.kind))
                    for (int i = 0; i < block.body.size(); i++) {
                        if (i > 0)
                            block.tokens.add(new Token("", " ", 0));
                        parseBody(block, block.body.get(i));
                    }
            }
            for (DocumentParser.Bib entry : bibliography.values())
                if (!entry.cited)
                    warn(entry.line, "unused bibliography entry " + entry.key);
        }
        void bibliographyLabels() {
            for (DocumentParser.Bib entry : bibliography.values())
                if (entry.cited) {
                    String[] names = entry.author.split(" and ", -1);
                    String base;
                    if (names.length == 1)
                        base = names[0].substring(0, Math.min(3, names[0].length()));
                    else {
                        StringBuilder text = new StringBuilder();
                        for (int i = 0; i < Math.min(names.length, names.length >= 5 ? 3 : 4); i++)
                            text.append(names[i].charAt(0));
                        if (names.length >= 5)
                            text.append('+');
                        base = text.toString();
                    }
                    entry.base = base + entry.year.substring(2);
                    cited.add(entry);
                }
            cited.sort(Comparator.comparing((DocumentParser.Bib e) -> e.base)
                           .thenComparing(e -> e.author)
                           .thenComparing(e -> e.title)
                           .thenComparing(e -> e.key));
            for (int start = 0; start < cited.size();) {
                int end = start + 1;
                while (end < cited.size() && cited.get(end).base.equals(cited.get(start).base))
                    end++;
                for (int i = start; i < end; i++)
                    cited.get(i).label =
                        cited.get(i).base +
                        (end - start == 1 ? "" : Character.toString((char)('a' + i - start)));
                start = end;
            }
        }
        void prepareIndex() {
            for (int i = 0; i < indexMarks.size(); i++) {
                String phrase = indexMarks.get(i);
                int pipe = phrase.indexOf('|');
                String entryPart = pipe < 0 ? phrase : phrase.substring(0, pipe),
                       reference = pipe < 0 ? null : phrase.substring(pipe + 1);
                int bang = entryPart.indexOf('!');
                String parent = bang < 0 ? entryPart : entryPart.substring(0, bang),
                       child = bang < 0 ? null : entryPart.substring(bang + 1);
                IndexEntry entry = index.computeIfAbsent(parent, IndexEntry::new);
                if (child != null)
                    entry = entry.children.computeIfAbsent(child, IndexEntry::new);
                if (reference != null)
                    entry.see.add(reference);
                else
                    entry.marks.add(i + 1);
            }
        }
        Expanded expand(DocumentParser.Block block, Map<String, String> pages) {
            StringBuilder text = new StringBuilder();
            List<RawMark> marks = new ArrayList<>();
            for (Token token : block.tokens) {
                if (token.kind.isEmpty())
                    text.append(token.argument);
                else if (token.kind.equals("ref"))
                    text.append(labels.containsKey(token.argument) ? labels.get(token.argument).number
                                                                   : "??");
                else if (token.kind.equals("page"))
                    text.append(pages.getOrDefault(token.argument, "??"));
                else if (token.kind.equals("fn")) {
                    marks.add(new RawMark(text.length(), true, token.number));
                    text.append('[').append(token.number).append(']');
                } else if (token.kind.equals("idx"))
                    marks.add(new RawMark(text.length() - 1, false, token.number));
                else {
                    SortedSet<String> citations = new TreeSet<>();
                    boolean missing = false;
                    for (String key : token.argument.split(",")) {
                        DocumentParser.Bib entry = bibliography.get(key);
                        if (entry == null)
                            missing = true;
                        else
                            citations.add(entry.label);
                    }
                    List<String> values = new ArrayList<>(citations);
                    if (missing)
                        values.add("?");
                    text.append('[').append(String.join(", ", values)).append(']');
                }
            }
            List<String> words = new ArrayList<>();
            List<Integer> starts = new ArrayList<>();
            String value = text.toString();
            int position = 0;
            while (position < value.length()) {
                if (value.charAt(position) == ' ') {
                    position++;
                    continue;
                }
                int start = position;
                while (position < value.length() && value.charAt(position) != ' ')
                    position++;
                starts.add(start);
                words.add(value.substring(start, position));
            }
            List<Mark> located = new ArrayList<>();
            for (RawMark mark : marks) {
                int word = 0;
                while (word + 1 < starts.size() && starts.get(word + 1) <= mark.position)
                    word++;
                located.add(new Mark(word, mark.position - starts.get(word), mark.footnote, mark.number));
            }
            return new Expanded(words, located);
        }
        Broken breakText(List<String> words, List<Mark> marks, int first, int later, String alignment,
                         String firstPrefix, String laterPrefix, String name, boolean body, boolean optimal) {
            Metrics metrics = new Metrics(words, first, later, dictionary);
            LineBreaker.Result result = LineBreaker.split(metrics, optimal, params);
            Broken broken = new Broken();
            broken.name = name;
            broken.align = alignment;
            broken.body = body;
            broken.cost = result.cost();
            int start = 0;
            for (int end : result.breaks()) {
                Measure measure = metrics.measure(start, end);
                Line line =
                    new Line((start == 0 ? firstPrefix : laterPrefix) +
                             Renderer.display(measure.pieces, measure.slack, alignment, measure.last));
                for (Mark mark : marks)
                    for (int[] range : measure.ranges)
                        if (range[0] == mark.word && range[1] <= mark.position && mark.position < range[2]) {
                            if (mark.footnote)
                                line.footnotes.add(mark.number);
                            else
                                line.indexes.add(mark.number);
                        }
                broken.measures.add(measure);
                broken.lines.add(line);
                start = end;
            }
            return broken;
        }
        String pageList(SortedSet<Integer> pages) {
            List<Integer> ordered = new ArrayList<>(pages);
            List<String> parts = new ArrayList<>();
            for (int start = 0; start < ordered.size();) {
                int end = start;
                while (end + 1 < ordered.size() && ordered.get(end + 1) == ordered.get(end) + 1)
                    end++;
                if (end - start + 1 >= 3)
                    parts.add(ordered.get(start) + "-" + ordered.get(end));
                else
                    for (int i = start; i <= end; i++)
                        parts.add(Integer.toString(ordered.get(i)));
                start = end + 1;
            }
            return String.join(", ", parts);
        }
        String indexLine(IndexEntry entry, boolean child, int[] markPages) {
            SortedSet<Integer> pages = new TreeSet<>();
            for (int mark : entry.marks)
                pages.add(markPages[mark]);
            String line = (child ? "  " : "") + entry.name;
            if (!pages.isEmpty())
                line += ", " + pageList(pages);
            if (!entry.see.isEmpty())
                line += ", see " + String.join(", ", entry.see);
            return line;
        }
        List<String> sortedNames(Set<String> names) {
            List<String> result = new ArrayList<>(names);
            result.sort(Comparator.comparing((String name) -> name.toLowerCase(Locale.ROOT))
                            .thenComparing(Comparator.naturalOrder()));
            return result;
        }
        List<String> indexLines(int[] markPages) {
            List<String> result = new ArrayList<>();
            String previous = null;
            for (String name : sortedNames(index.keySet())) {
                IndexEntry entry = index.get(name);
                char first = name.charAt(0);
                String group =
                    Hyphenation.letter(first) ? Character.toString(Character.toUpperCase(first)) : "Symbols";
                if (!group.equals(previous)) {
                    result.add(group);
                    previous = group;
                }
                result.add(indexLine(entry, false, markPages));
                for (String child : sortedNames(entry.children.keySet()))
                    result.add(indexLine(entry.children.get(child), true, markPages));
            }
            return result;
        }
        List<String> entries(String kind, int width, int[] blockPages, List<Page> pages) {
            List<String> result = new ArrayList<>();
            for (DocumentParser.Block block : kind.equals("toc") ? headings : tables) {
                String left = kind.equals("toc")
                                  ? (block.kind.equals("h2") ? "  " : "") + block.number + " " + block.text
                                  : "Table " + block.number + ". " + block.caption,
                       number = blockPages == null ? "??" : pages.get(blockPages[block.id] - 1).display;
                result.add(left + " "
                           + ".".repeat(width - left.length() - number.length() - 2) + " " + number);
            }
            return result;
        }
        Layout once(boolean optimal, Map<String, String> pageValues) {
            Layout layout = new Layout();
            List<LayoutBlock> blocks = new ArrayList<>();
            List<Deferred> deferred = new ArrayList<>();
            Map<Integer, List<Line>> footnoteLines = new HashMap<>();
            List<Broken> footnoteBroken = new ArrayList<>();
            for (int i = 0; i < footnotes.size(); i++) {
                String prefix = "[" + (i + 1) + "] ";
                Broken broken =
                    breakText(words(footnotes.get(i)), List.of(), document.width - prefix.length(),
                              document.width - prefix.length(), "left", prefix, " ".repeat(prefix.length()),
                              "footnote " + (i + 1), false, optimal);
                footnoteLines.put(i + 1, broken.lines);
                footnoteBroken.add(broken);
            }
            int referenceWidth = 3;
            for (DocumentParser.Bib entry : cited)
                referenceWidth = Math.max(referenceWidth, entry.label.length() + 3);
            for (DocumentParser.Block block : document.blocks) {
                int start = blocks.size();
                String kind = block.kind;
                if (DocumentParser.BODY.contains(kind)) {
                    Expanded expanded = expand(block, pageValues);
                    int first = block.width, later = block.width;
                    String firstPrefix = "", laterPrefix = "";
                    if (kind.equals("paragraph")) {
                        first -= block.indent;
                        firstPrefix = " ".repeat(block.indent);
                    } else if (kind.equals("item")) {
                        first -= 2;
                        later = first;
                        firstPrefix = "- ";
                        laterPrefix = "  ";
                    } else if (kind.equals("enum")) {
                        first -= 4;
                        later = first;
                        firstPrefix = " ".repeat(2 - block.number.length()) + block.number + ". ";
                        laterPrefix = "    ";
                    } else if (kind.equals("quote")) {
                        first -= 8;
                        later = first;
                        firstPrefix = "    ";
                        laterPrefix = firstPrefix;
                    } else {
                        first -= 12;
                        later = first;
                        firstPrefix = block.term.length() <= 10
                                          ? block.term + " ".repeat(12 - block.term.length())
                                          : "            ";
                        laterPrefix = "            ";
                    }
                    Broken broken =
                        breakText(expanded.words, expanded.marks, first, later, block.align, firstPrefix,
                                  laterPrefix, "paragraph " + block.paragraph, true, optimal);
                    layout.bodies.put(block.paragraph, broken);
                    layout.broken.add(broken);
                    List<Line> body = new ArrayList<>();
                    if (kind.equals("term") && block.term.length() >= 11)
                        body.add(new Line(block.term));
                    body.addAll(broken.lines);
                    for (int i = 0; i < body.size(); i++) {
                        body.get(i).origin = block;
                        body.get(i).first = i == 0;
                    }
                    blocks.add(
                        new LayoutBlock("flow", Set.of("item", "enum", "term").contains(kind), false, body));
                } else if (kind.equals("title") || kind.equals("author")) {
                    String text =
                        kind.equals("title") ? block.argument.toUpperCase(Locale.ROOT) : block.argument;
                    blocks.add(new LayoutBlock(
                        "heading", false, false,
                        lines(List.of(" ".repeat((block.width - text.length()) / 2) + text), block)));
                } else if (kind.equals("h1") || kind.equals("h2")) {
                    String text = block.number + " " +
                                  (kind.equals("h1") ? block.text.toUpperCase(Locale.ROOT) : block.text);
                    blocks.add(new LayoutBlock(
                        "heading", false, false,
                        lines(List.of(text, (kind.equals("h1") ? "=" : "-").repeat(text.length())), block)));
                } else if (kind.equals("table"))
                    blocks.add(new LayoutBlock("solid", false, false, lines(block.tableLines, block)));
                else if (kind.equals("verbatim")) {
                    List<String> text = new ArrayList<>();
                    for (DocumentParser.Source source : block.inner)
                        text.add(source.text());
                    blocks.add(new LayoutBlock("flow", false, false, lines(text, block)));
                } else {
                    String title = kind.equals("toc")     ? "CONTENTS"
                                   : kind.equals("lot")   ? "TABLES"
                                   : kind.equals("index") ? "INDEX"
                                                          : "REFERENCES";
                    blocks.add(new LayoutBlock("heading", false, false,
                                               lines(List.of(title, "=".repeat(title.length())), block)));
                    if (kind.equals("bibliography")) {
                        for (DocumentParser.Bib entry : cited) {
                            String prefix = "[" + entry.label + "]";
                            prefix += " ".repeat(referenceWidth - prefix.length());
                            Broken broken = breakText(
                                words(entry.author + ". " + entry.year + ". " + entry.title), List.of(),
                                block.width - referenceWidth, block.width - referenceWidth, "left", prefix,
                                " ".repeat(referenceWidth), "reference " + entry.label, false, optimal);
                            layout.broken.add(broken);
                            for (Line line : broken.lines)
                                line.origin = block;
                            blocks.add(new LayoutBlock("flow", true, false, broken.lines));
                        }
                    } else {
                        List<String> text = kind.equals("index") ? indexLines(new int[indexMarks.size() + 1])
                                                                 : entries(kind, block.width, null, null);
                        List<Line> entryLines = lines(text, block);
                        blocks.add(new LayoutBlock("flow", false, false, entryLines));
                        deferred.add(new Deferred(kind, block, entryLines));
                    }
                }
                if (blocks.size() > start)
                    blocks.get(start).forced = block.pageBreak;
            }
            layout.broken.addAll(footnoteBroken);
            List<Page> raw = PageBuilder.build(blocks, footnoteLines, document.height,
                                               params.get("orphan_lines"), params.get("widow_lines"));
            List<Page> pages = new ArrayList<>();
            for (Page page : raw) {
                boolean chapter = !page.content.isEmpty() && page.content.getFirst().first &&
                                  page.content.getFirst().origin != null &&
                                  page.content.getFirst().origin.kind.equals("h1");
                if (chapter && (pages.size() + 1) % 2 == 0) {
                    Page blank = new Page();
                    blank.blank = true;
                    pages.add(blank);
                }
                pages.add(page);
            }
            layout.pages = pages;
            int front = 0;
            boolean foundChapter = false;
            int[] blockPages = new int[document.blocks.size()], markPages = new int[indexMarks.size() + 1];
            for (int i = 0; i < pages.size(); i++) {
                Page page = pages.get(i);
                page.serial = i + 1;
                for (Line line : page.content)
                    if (line.first && line.origin != null) {
                        if (blockPages[line.origin.id] == 0)
                            blockPages[line.origin.id] = page.serial;
                        if (!foundChapter && line.origin.kind.equals("h1")) {
                            front = page.serial - 1;
                            foundChapter = true;
                        }
                    }
            }
            for (Page page : pages) {
                page.display =
                    page.serial <= front ? roman(page.serial) : Integer.toString(page.serial - front);
                for (Line line : page.content)
                    for (int mark : line.indexes)
                        markPages[mark] = page.serial - front;
            }
            for (Map.Entry<String, DocumentParser.Block> entry : labels.entrySet())
                layout.labels.put(entry.getKey(), pages.get(blockPages[entry.getValue().id] - 1).display);
            for (Deferred item : deferred) {
                List<String> text = item.kind.equals("index")
                                        ? indexLines(markPages)
                                        : entries(item.kind, item.block.width, blockPages, pages);
                for (int i = 0; i < text.size(); i++)
                    item.lines.get(i).text = text.get(i);
            }
            String chapter = "", section = "";
            int heading = 0;
            for (Page page : pages) {
                if (page.blank) {
                    for (int i = 0; i < document.height; i++)
                        page.body.add("");
                    continue;
                }
                while (heading < headings.size() && blockPages[headings.get(heading).id] <= page.serial) {
                    DocumentParser.Block block = headings.get(heading++);
                    if (block.kind.equals("h1")) {
                        chapter = block.number + " " + block.text;
                        section = "";
                    } else
                        section = block.number + " " + block.text;
                }
                Map<String, String> values =
                    Map.of("page", page.display, "pages", Integer.toString(pages.size() - front), "chapter",
                           chapter, "section", section);
                boolean chapterPage = !page.content.isEmpty() && page.content.getFirst().first &&
                                      page.content.getFirst().origin != null &&
                                      page.content.getFirst().origin.kind.equals("h1");
                page.header =
                    chapterPage ? "" : Renderer.head(document.header, values, document.width, page.serial);
                page.footer = Renderer.head(document.footer, values, document.width, page.serial);
                for (Line line : page.content)
                    page.body.add(line.text);
                while (page.body.size() < document.height - (page.notes.isEmpty() ? 0 : 1) -
                                              footnoteHeight(page.notes, footnoteLines))
                    page.body.add("");
                if (!page.notes.isEmpty()) {
                    page.body.add("----------");
                    for (int number : page.notes)
                        for (Line line : footnoteLines.get(number))
                            page.body.add(line.text);
                }
            }
            return layout;
        }
        int footnoteHeight(List<Integer> numbers, Map<Integer, List<Line>> lines) {
            int total = 0;
            for (int number : numbers)
                total += lines.get(number).size();
            return total;
        }
        Layout layout(boolean optimal) {
            Map<String, String> values = new HashMap<>();
            for (String label : labels.keySet())
                values.put(label, "??");
            Layout result;
            while (true) {
                result = once(optimal, values);
                if (result.labels.equals(values))
                    break;
                values = result.labels;
            }
            String prefix = optimal ? "kp: " : "greedy: ";
            int hyphenated = 0;
            for (Broken broken : result.broken)
                for (int i = 0; i < broken.measures.size(); i++) {
                    Measure line = broken.measures.get(i);
                    if (broken.body && line.mid)
                        hyphenated++;
                    if (line.slack < 0)
                        result.warnings.add(prefix + broken.name + " line " + (i + 1) + ": overfull by " +
                                            (-line.slack));
                    else if (broken.body && broken.align.equals("justify") && !line.last &&
                             line.slack >= params.get("underfull_slack"))
                        result.warnings.add(prefix + broken.name + " line " + (i + 1) +
                                            ": underfull, slack " + line.slack);
                }
            for (Page page : result.pages)
                if (!page.blank && !page.forced &&
                    document.height - page.height >= params.get("underfull_page"))
                    result.warnings.add(prefix + "page " + page.serial + ": underfull, " +
                                        (document.height - page.height) + " empty lines");
            result.warnings.add(prefix + result.pages.size() + " pages, " + hyphenated + " hyphenated lines");
            return result;
        }
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Map<String, Integer> params = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
            String[] parts = line.split(" ");
            params.put(parts[0], Integer.parseInt(parts[1]));
        }
        DocumentParser.Document document = DocumentParser.parse(
            Files.readAllLines(Path.of("input/document.txt"), StandardCharsets.US_ASCII));
        Typesetter typesetter =
            new Typesetter(document, params,
                           Files.readAllLines(Path.of("input/hyphenation.txt"), StandardCharsets.US_ASCII));
        Layout kp = typesetter.layout(true), greedy = typesetter.layout(false);
        List<String> stats = new ArrayList<>(List.of("paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"));
        int[] totals = new int[4];
        for (DocumentParser.Block block : typesetter.bodies) {
            Broken a = kp.bodies.get(block.paragraph), b = greedy.bodies.get(block.paragraph);
            int[] values = {a.measures.size(), a.cost, b.measures.size(), b.cost};
            String line = Integer.toString(block.paragraph);
            for (int i = 0; i < 4; i++) {
                totals[i] += values[i];
                line += "," + values[i];
            }
            stats.add(line);
        }
        stats.add("total," + totals[0] + "," + totals[1] + "," + totals[2] + "," + totals[3]);
        List<String> log = new ArrayList<>();
        for (DocumentParser.Warning warning : document.warnings)
            log.add("line " + warning.line() + ": " + warning.text());
        log.addAll(kp.warnings);
        log.addAll(greedy.warnings);
        Files.createDirectories(Path.of("output"));
        write("pages.txt", Renderer.pages(kp.pages));
        write("greedy_pages.txt", Renderer.pages(greedy.pages));
        write("stats.csv", stats);
        write("log.txt", log);
    }
}
