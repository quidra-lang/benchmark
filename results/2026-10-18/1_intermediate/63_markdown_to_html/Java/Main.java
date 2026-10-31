import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    static final String PUNCTUATION = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
    static final String TOC_MARKER = "\001toc\002";
    static boolean has(String set, char c) {
        return set.indexOf(c) >= 0;
    }
    static boolean alphanumeric(char c) {
        return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9';
    }
    static boolean labelCharacter(char c) {
        return alphanumeric(c) || c == '-' || c == '_';
    }
    static boolean whitespace(char c) {
        return c == ' ' || c == '\n';
    }
    static String lower(String s) {
        return s.toLowerCase(Locale.ROOT);
    }
    static String trim(String s) {
        int first = 0, end = s.length();
        while (first < end && s.charAt(first) == ' ')
            first++;
        while (end > first && s.charAt(end - 1) == ' ')
            end--;
        return s.substring(first, end);
    }
    static String leftTrim(String s) {
        int first = 0;
        while (first < s.length() && s.charAt(first) == ' ')
            first++;
        return s.substring(first);
    }
    static String rightTrim(String s) {
        int end = s.length();
        while (end > 0 && s.charAt(end - 1) == ' ')
            end--;
        return s.substring(0, end);
    }
    static String escapeHtml(String s) {
        var html = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            switch (s.charAt(i)) {
                case '&':
                    html.append("&amp;");
                    break;
                case '<':
                    html.append("&lt;");
                    break;
                case '>':
                    html.append("&gt;");
                    break;
                case '"':
                    html.append("&quot;");
                    break;
                default:
                    html.append(s.charAt(i));
            }
        }
        return html.toString();
    }
    static String stripTags(String s) {
        return s.replaceAll("<[^>]*>", "");
    }
    static String normalize(String s) {
        var result = new StringBuilder();
        boolean space = false;
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (whitespace(ch))
                space = result.length() > 0;
            else {
                if (space)
                    result.append(' ');
                result.append(Character.toLowerCase(ch));
                space = false;
            }
        }
        return result.toString();
    }
    static int skipSpace(String s, int at) {
        while (at < s.length() && whitespace(s.charAt(at)))
            at++;
        return at;
    }
    record Read(String text, int end) {}
    static Read escapedRead(String s, int at, String stops) {
        var result = new StringBuilder();
        while (at < s.length() && !has(stops, s.charAt(at))) {
            if (s.charAt(at) == '\\' && at + 1 < s.length() && has(PUNCTUATION, s.charAt(at + 1)))
                at++;
            result.append(s.charAt(at++));
        }
        return new Read(result.toString(), at);
    }
    enum Kind { HEADING, PARAGRAPH, RULE, CODE, QUOTE, ALERT, LIST, TABLE, TOC }
    static class Block {
        Kind kind;
        String text;
        int number;
        boolean ordered;
        List<String> lines = new ArrayList<>(), alignments = new ArrayList<>();
        List<Block> children = new ArrayList<>();
        List<List<Block>> items = new ArrayList<>();
        List<List<String>> rows = new ArrayList<>();
        Block(Kind kind) {
            this(kind, "", 0);
        }
        Block(Kind kind, String text, int number) {
            this.kind = kind;
            this.text = text;
            this.number = number;
        }
    }
    record Reference(String url, String title) {}
    record Fence(char character, int length, String info) {}
    record ListMarker(char marker, boolean ordered, int number, String content) {}
    static Fence openingFence(String line) {
        if (line.isEmpty() || !has("`~", line.charAt(0)))
            return null;
        int end = 1;
        while (end < line.length() && line.charAt(end) == line.charAt(0))
            end++;
        if (end < 3)
            return null;
        String info = trim(line.substring(end));
        if (line.charAt(0) == '`' && info.indexOf('`') >= 0)
            return null;
        return new Fence(line.charAt(0), end, info);
    }
    static Block atxHeading(String line) {
        int n = 0;
        while (n < line.length() && line.charAt(n) == '#')
            n++;
        if (n < 1 || n > 6 || n < line.length() && line.charAt(n) != ' ')
            return null;
        String text = trim(line.substring(n));
        int end = text.length();
        while (end > 0 && text.charAt(end - 1) == '#')
            end--;
        if (end == 0 || text.charAt(end - 1) == ' ')
            text = trim(text.substring(0, end));
        return new Block(Kind.HEADING, text, n);
    }
    static boolean isRule(String line) {
        String compact = line.replace(" ", "");
        if (compact.length() < 3 || !has("-*_", compact.charAt(0)))
            return false;
        for (int i = 1; i < compact.length(); i++)
            if (compact.charAt(i) != compact.charAt(0))
                return false;
        return true;
    }
    static final Pattern LIST_ITEM = Pattern.compile("(?:([-*+])|([0-9]{1,9})([.)])) +");
    static ListMarker listMarker(String line) {
        if (isRule(line))
            return null;
        Matcher m = LIST_ITEM.matcher(line);
        if (!m.lookingAt())
            return null;
        boolean ordered = m.group(2) != null;
        return new ListMarker((ordered ? m.group(3) : m.group(1)).charAt(0), ordered,
            ordered ? Integer.parseInt(m.group(2)) : 1, line.substring(m.end()));
    }
    static boolean interrupts(String line) {
        return !line.isEmpty() && line.charAt(0) != ' '
            && (openingFence(line) != null || atxHeading(line) != null || isRule(line)
                || line.charAt(0) == '>' || listMarker(line) != null);
    }
    static List<String> splitCells(String line) {
        String text = trim(line);
        int at = text.startsWith("|") ? 1 : 0;
        var cells = new ArrayList<String>();
        var cell = new StringBuilder();
        boolean finalSeparator = false;
        while (at < text.length()) {
            char ch = text.charAt(at++);
            finalSeparator = false;
            if (ch == '\\' && at < text.length()) {
                if (text.charAt(at) != '|')
                    cell.append('\\');
                cell.append(text.charAt(at++));
            } else if (ch == '|') {
                cells.add(trim(cell.toString()));
                cell.setLength(0);
                finalSeparator = true;
            } else
                cell.append(ch);
        }
        if (!finalSeparator)
            cells.add(trim(cell.toString()));
        return cells;
    }
    static class BlockParser {
        final Map<String, Reference> references = new HashMap<>();
        final Map<String, String> footnotes = new HashMap<>();
        boolean definition(String line) {
            Matcher footnote = Pattern.compile("\\[\\^([A-Za-z0-9_-]+)\\]:(.*)").matcher(line);
            if (footnote.matches() && !trim(footnote.group(2)).isEmpty()) {
                footnotes.putIfAbsent(lower(footnote.group(1)), trim(footnote.group(2)));
                return true;
            }
            if (!line.startsWith("["))
                return false;
            int close = line.indexOf(']');
            if (close < 0 || close + 1 >= line.length() || line.charAt(close + 1) != ':')
                return false;
            String label = line.substring(1, close);
            if (label.indexOf('[') >= 0 || trim(label).isEmpty() || label.startsWith("^"))
                return false;
            Read url = escapedRead(line, skipSpace(line, close + 2), " ");
            if (url.text.isEmpty())
                return false;
            int at = skipSpace(line, url.end);
            String title = null;
            if (at < line.length()) {
                if (at == url.end || !has("\"'", line.charAt(at)))
                    return false;
                Read quoted = escapedRead(line, at + 1, String.valueOf(line.charAt(at)));
                if (quoted.end != line.length() - 1)
                    return false;
                title = quoted.text;
            }
            references.putIfAbsent(normalize(label), new Reference(url.text, title));
            return true;
        }
        List<Block> parse(List<String> lines) {
            var blocks = new ArrayList<Block>();
            int at = 0;
            while (at < lines.size()) {
                String line = lines.get(at);
                if (line.isEmpty()) {
                    at++;
                    continue;
                }
                if (line.startsWith("    ")) {
                    Block code = new Block(Kind.CODE);
                    int end = at;
                    while (end < lines.size()
                        && (lines.get(end).isEmpty() || lines.get(end).startsWith("    ")))
                        end++;
                    while (end > at && lines.get(end - 1).isEmpty())
                        end--;
                    while (at < end) {
                        String row = lines.get(at++);
                        code.lines.add(row.isEmpty() ? "" : row.substring(4));
                    }
                    blocks.add(code);
                    continue;
                }
                if (line.charAt(0) != ' ') {
                    Fence fence = openingFence(line);
                    if (fence != null) {
                        String language = fence.info.split(" ", 2)[0];
                        Block code = new Block(Kind.CODE, language, 0);
                        at++;
                        while (at < lines.size()) {
                            String row = lines.get(at++);
                            boolean closing = row.length() >= fence.length;
                            for (int i = 0; closing && i < row.length(); i++)
                                if (row.charAt(i) != fence.character)
                                    closing = false;
                            if (closing)
                                break;
                            code.lines.add(row);
                        }
                        blocks.add(code);
                        continue;
                    }
                    Block heading = atxHeading(line);
                    if (heading != null) {
                        blocks.add(heading);
                        at++;
                        continue;
                    }
                    if (isRule(line)) {
                        blocks.add(new Block(Kind.RULE));
                        at++;
                        continue;
                    }
                    if (line.startsWith(">")) {
                        var content = new ArrayList<String>();
                        while (at < lines.size() && lines.get(at).startsWith(">")) {
                            String row = lines.get(at++).substring(1);
                            if (row.startsWith(" "))
                                row = row.substring(1);
                            content.add(row);
                        }
                        Block quote = new Block(Kind.QUOTE);
                        if (content.get(0).matches("\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]")) {
                            quote.kind = Kind.ALERT;
                            quote.text = content.remove(0);
                            quote.text = quote.text.substring(2, quote.text.length() - 1);
                        }
                        quote.children = parse(content);
                        blocks.add(quote);
                        continue;
                    }
                    ListMarker marker = listMarker(line);
                    if (marker != null) {
                        Block list = new Block(Kind.LIST, "", marker.number);
                        list.ordered = marker.ordered;
                        char kind = marker.marker;
                        while (true) {
                            var content = new ArrayList<String>();
                            content.add(marker.content);
                            at++;
                            while (at < lines.size() && lines.get(at).startsWith("  "))
                                content.add(lines.get(at++).substring(2));
                            list.items.add(parse(content));
                            int next = at;
                            while (next < lines.size() && lines.get(next).isEmpty())
                                next++;
                            marker = next < lines.size() ? listMarker(lines.get(next)) : null;
                            if (marker == null || marker.marker != kind
                                || marker.ordered != list.ordered)
                                break;
                            at = next;
                        }
                        blocks.add(list);
                        continue;
                    }
                    if (definition(line)) {
                        at++;
                        continue;
                    }
                    if (at + 1 < lines.size() && line.indexOf('|') >= 0
                        && lines.get(at + 1).indexOf('|') >= 0) {
                        List<String> header = splitCells(line),
                                     delimiters = splitCells(lines.get(at + 1));
                        if (header.size() == delimiters.size()
                            && delimiters.stream().allMatch(c -> c.matches(":?-+:?"))) {
                            Block table = new Block(Kind.TABLE);
                            table.lines = header;
                            for (String cell : delimiters) {
                                boolean left = cell.startsWith(":"), right = cell.endsWith(":");
                                table.alignments.add(
                                    left ? (right ? "center" : "left") : (right ? "right" : ""));
                            }
                            at += 2;
                            while (at < lines.size() && lines.get(at).indexOf('|') >= 0) {
                                List<String> row = splitCells(lines.get(at++));
                                while (row.size() < delimiters.size())
                                    row.add("");
                                table.rows.add(new ArrayList<>(row.subList(0, delimiters.size())));
                            }
                            blocks.add(table);
                            continue;
                        }
                    }
                }
                var text = new ArrayList<String>();
                text.add(leftTrim(line));
                at++;
                int level = 0;
                while (at < lines.size() && !lines.get(at).isEmpty()) {
                    String row = lines.get(at);
                    if (row.matches("={3,}|-{3,}")) {
                        level = row.charAt(0) == '=' ? 1 : 2;
                        at++;
                        break;
                    }
                    if (interrupts(row))
                        break;
                    text.add(leftTrim(row));
                    at++;
                }
                String combined = String.join("\n", text);
                blocks.add(new Block(level != 0    ? Kind.HEADING
                        : combined.equals("[TOC]") ? Kind.TOC
                                                   : Kind.PARAGRAPH,
                    combined, level));
            }
            return blocks;
        }
    }
    static int runEnd(String text, int at) {
        char ch = text.charAt(at++);
        while (at < text.length() && text.charAt(at) == ch)
            at++;
        return at;
    }
    static int backtickCloser(String text, int at, int length) {
        while ((at = text.indexOf('`', at)) >= 0) {
            int end = runEnd(text, at);
            if (end - at == length)
                return at;
            at = end;
        }
        return -1;
    }
    static int closingBracket(String text, int at) {
        int depth = 0;
        while (at < text.length()) {
            char ch = text.charAt(at);
            if (ch == '\\') {
                at += 2;
                continue;
            }
            if (ch == '`') {
                int end = runEnd(text, at), close = backtickCloser(text, end, end - at);
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
    record Piece(String html, char delimiter, int length, boolean canOpen, boolean canClose) {
        Piece(String html) {
            this(html, '\0', 0, false, false);
        }
    }
    static void emphasis(StringBuilder html, List<Piece> pieces, int begin, int end) {
        for (int at = begin; at < end; at++) {
            Piece p = pieces.get(at);
            if (p.delimiter == 0) {
                html.append(p.html);
                continue;
            }
            int close = at + 1;
            if (p.canOpen) {
                while (close < end
                    && !(pieces.get(close).delimiter == p.delimiter
                        && pieces.get(close).length == p.length && pieces.get(close).canClose))
                    close++;
            } else
                close = end;
            if (close == end) {
                html.append(String.valueOf(p.delimiter).repeat(p.length));
                continue;
            }
            String open, shut;
            if (p.delimiter == '~') {
                open = "<del>";
                shut = "</del>";
            } else if (p.length == 1) {
                open = "<em>";
                shut = "</em>";
            } else if (p.length == 2) {
                open = "<strong>";
                shut = "</strong>";
            } else {
                open = "<em><strong>";
                shut = "</strong></em>";
            }
            html.append(open);
            emphasis(html, pieces, at + 1, close);
            html.append(shut);
            at = close;
        }
    }
    record Destination(Reference reference, int end) {}
    static class Heading {
        int level;
        String id, label;
        List<Heading> children = new ArrayList<>();
        Heading(int level, String id, String label) {
            this.level = level;
            this.id = id;
            this.label = label;
        }
    }
    static class Note {
        String name;
        int count;
        Note(String name) {
            this.name = name;
        }
    }
    static class Renderer {
        final BlockParser parser;
        final Set<String> usedIds = new HashSet<>();
        final List<Heading> headings = new ArrayList<>();
        final Map<String, Integer> noteNumbers = new HashMap<>();
        final List<Note> notes = new ArrayList<>();
        Renderer(BlockParser parser) {
            this.parser = parser;
        }
        static String referenceId(int number, int count) {
            return "fnref-" + number + (count == 1 ? "" : "-" + count);
        }
        String footnoteReference(String name) {
            if (!noteNumbers.containsKey(name)) {
                noteNumbers.put(name, notes.size());
                notes.add(new Note(name));
            }
            int index = noteNumbers.get(name);
            Note note = notes.get(index);
            int number = index + 1;
            return "<sup id=\"" + referenceId(number, ++note.count) + "\"><a href=\"#fn-" + number
                + "\">" + number + "</a></sup>";
        }
        Destination destination(String text, int at, String label) {
            if (at < text.length() && text.charAt(at) == '[') {
                int close = text.indexOf(']', at + 1);
                if (close >= 0 && text.substring(at + 1, close).indexOf('[') < 0) {
                    String key = text.substring(at + 1, close);
                    key = normalize(key.isEmpty() ? label : key);
                    Reference reference = parser.references.get(key);
                    return reference == null ? null : new Destination(reference, close + 1);
                }
            } else if (at < text.length() && text.charAt(at) == '(') {
                Read url = escapedRead(text, skipSpace(text, at + 1), " \n)");
                int next = skipSpace(text, url.end);
                String title = null;
                boolean valid = true;
                if (next > url.end && next < text.length() && has("\"'", text.charAt(next))) {
                    Read quoted = escapedRead(text, next + 1, String.valueOf(text.charAt(next)));
                    if (quoted.end == text.length())
                        valid = false;
                    else {
                        title = quoted.text;
                        next = skipSpace(text, quoted.end + 1);
                    }
                }
                if (valid && next < text.length() && text.charAt(next) == ')')
                    return new Destination(new Reference(url.text, title), next + 1);
            }
            Reference reference = parser.references.get(normalize(label));
            return reference == null ? null : new Destination(reference, at);
        }
        String inline(String text) {
            return inline(text, true, true);
        }
        String inline(String text, boolean links, boolean footnotes) {
            var pieces = new ArrayList<Piece>();
            int at = 0;
            while (at < text.length()) {
                char ch = text.charAt(at);
                if (ch == '\\') {
                    if (at + 1 < text.length() && has(PUNCTUATION, text.charAt(at + 1))) {
                        pieces.add(new Piece(escapeHtml(text.substring(at + 1, at + 2))));
                        at += 2;
                    } else if (at + 1 < text.length() && text.charAt(at + 1) == '\n') {
                        pieces.add(new Piece("<br />\n"));
                        at += 2;
                    } else {
                        pieces.add(new Piece("\\"));
                        at++;
                    }
                    continue;
                }
                if (ch == '`') {
                    int end = runEnd(text, at), close = backtickCloser(text, end, end - at);
                    if (close < 0) {
                        pieces.add(new Piece(text.substring(at, end)));
                        at = end;
                    } else {
                        String code = text.substring(end, close).replace('\n', ' ');
                        if (code.startsWith(" ") && code.endsWith(" ") && !trim(code).isEmpty())
                            code = code.substring(1, code.length() - 1);
                        pieces.add(new Piece("<code>" + escapeHtml(code) + "</code>"));
                        at = close + end - at;
                    }
                    continue;
                }
                if (links && ch == '<') {
                    int close = text.indexOf('>', at + 1);
                    if (close >= 0) {
                        String target = text.substring(at + 1, close), href = null;
                        if (target.indexOf(' ') < 0 && target.indexOf('\n') < 0
                            && target.indexOf('<') < 0
                            && (target.startsWith("http://") && target.length() > 7
                                || target.startsWith("https://") && target.length() > 8))
                            href = target;
                        if (href == null
                            && target.matches(
                                "[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+"))
                            href = "mailto:" + target;
                        if (href != null) {
                            pieces.add(new Piece("<a href=\"" + escapeHtml(href) + "\">"
                                + escapeHtml(target) + "</a>"));
                            at = close + 1;
                            continue;
                        }
                    }
                }
                if (links && (text.startsWith("http://", at) || text.startsWith("https://", at))
                    && (at == 0 || has(" \n*_~(", text.charAt(at - 1)))) {
                    int end = at;
                    while (end < text.length() && !has(" \n<", text.charAt(end)))
                        end++;
                    while (end > at && has(".,:;!?*_~)", text.charAt(end - 1)))
                        end--;
                    String url = text.substring(at, end);
                    if (!url.equals("http://") && !url.equals("https://")) {
                        String escaped = escapeHtml(url);
                        pieces.add(new Piece("<a href=\"" + escaped + "\">" + escaped + "</a>"));
                        at = end;
                        continue;
                    }
                }
                if (ch == '['
                    || ch == '!' && at + 1 < text.length() && text.charAt(at + 1) == '[') {
                    if (links && footnotes && text.startsWith("[^", at)) {
                        int close = text.indexOf(']', at + 2);
                        if (close >= 0) {
                            String name = lower(text.substring(at + 2, close));
                            if (parser.footnotes.containsKey(name)) {
                                pieces.add(new Piece(footnoteReference(name)));
                                at = close + 1;
                                continue;
                            }
                        }
                    }
                    boolean image = ch == '!';
                    int opening = at + (image ? 1 : 0), close = closingBracket(text, opening);
                    if ((image || links) && close >= 0) {
                        String label = text.substring(opening + 1, close);
                        Destination dest = destination(text, close + 1, label);
                        if (dest != null) {
                            String content = inline(label, false, false),
                                   url = escapeHtml(dest.reference.url);
                            String title = dest.reference.title == null
                                ? ""
                                : " title=\"" + escapeHtml(dest.reference.title) + "\"";
                            pieces.add(new Piece(image
                                    ? "<img src=\"" + url + "\" alt=\"" + stripTags(content) + "\""
                                        + title + " />"
                                    : "<a href=\"" + url + "\"" + title + ">" + content + "</a>"));
                            at = dest.end;
                            continue;
                        }
                    }
                }
                if (has("*_~", ch)) {
                    int end = runEnd(text, at), length = end - at;
                    char before = at == 0 ? ' ' : text.charAt(at - 1),
                         after = end == text.length() ? ' ' : text.charAt(end);
                    boolean open = !whitespace(after), close = !whitespace(before);
                    if (ch == '_' && alphanumeric(before) && alphanumeric(after))
                        open = close = false;
                    pieces.add(ch != '~' && length <= 3 || ch == '~' && length == 2
                            ? new Piece("", ch, length, open, close)
                            : new Piece(text.substring(at, end)));
                    at = end;
                    continue;
                }
                pieces.add(new Piece(escapeHtml(text.substring(at, at + 1))));
                at++;
            }
            var html = new StringBuilder();
            emphasis(html, pieces, 0, pieces.size());
            return html.toString();
        }
        String renderBlocks(List<Block> blocks) {
            var html = new StringBuilder();
            for (Block block : blocks)
                html.append(render(block)).append('\n');
            return html.toString();
        }
        String heading(Block block) {
            String text = block.text, id = null;
            int explicit = text.lastIndexOf(" {#");
            if (text.endsWith("}") && explicit >= 0) {
                String candidate = text.substring(explicit + 3, text.length() - 1);
                if (!candidate.isEmpty()
                    && candidate.chars().allMatch(c -> labelCharacter((char) c))) {
                    id = candidate;
                    text = rightTrim(text.substring(0, explicit));
                }
            }
            if (id == null) {
                var slug = new StringBuilder();
                for (int i = 0; i < text.length(); i++) {
                    char c = Character.toLowerCase(text.charAt(i));
                    if (labelCharacter(c))
                        slug.append(c);
                    else if (whitespace(c))
                        slug.append('-');
                }
                String base = slug.isEmpty() ? "heading" : slug.toString();
                id = base;
                for (int suffix = 1; usedIds.contains(id); suffix++)
                    id = base + "-" + suffix;
            }
            usedIds.add(id);
            String html = inline(text);
            headings.add(new Heading(block.number, id, stripTags(html)));
            return "<h" + block.number + " id=\"" + id + "\">" + html + "</h" + block.number + ">";
        }
        String renderItem(List<Block> blocks) {
            var html = new StringBuilder("<li>");
            for (int i = 0; i < blocks.size(); i++) {
                Block block = blocks.get(i);
                if (block.kind == Kind.PARAGRAPH) {
                    String text = block.text;
                    if (i == 0 && text.length() > 4
                        && (text.startsWith("[ ] ") || text.startsWith("[x] ")
                            || text.startsWith("[X] "))) {
                        html.append(text.charAt(1) == ' '
                                ? "<input type=\"checkbox\" disabled=\"\" /> "
                                : "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ");
                        text = text.substring(4);
                    }
                    html.append(inline(text));
                } else {
                    if (html.charAt(html.length() - 1) != '\n')
                        html.append('\n');
                    html.append(render(block)).append('\n');
                }
            }
            return html.append("</li>").toString();
        }
        String tableCells(String tag, Block table, List<String> cells) {
            var html = new StringBuilder();
            for (int i = 0; i < cells.size(); i++) {
                String alignment = table.alignments.get(i);
                html.append('<').append(tag);
                if (!alignment.isEmpty())
                    html.append(" style=\"text-align:").append(alignment).append('"');
                html.append('>')
                    .append(inline(cells.get(i)))
                    .append("</")
                    .append(tag)
                    .append(">\n");
            }
            return html.toString();
        }
        String render(Block block) {
            switch (block.kind) {
                case HEADING:
                    return heading(block);
                case PARAGRAPH:
                    return "<p>" + inline(block.text) + "</p>";
                case RULE:
                    return "<hr />";
                case CODE: {
                    var html = new StringBuilder("<pre><code");
                    if (!block.text.isEmpty())
                        html.append(" class=\"language-")
                            .append(escapeHtml(block.text))
                            .append('"');
                    html.append('>');
                    for (String line : block.lines)
                        html.append(escapeHtml(line)).append('\n');
                    return html.append("</code></pre>").toString();
                }
                case QUOTE:
                    return "<blockquote>\n" + renderBlocks(block.children) + "</blockquote>";
                case ALERT: {
                    String name = lower(block.text),
                           title = Character.toUpperCase(name.charAt(0)) + name.substring(1);
                    return "<div class=\"alert alert-" + name + "\">\n<p class=\"alert-title\">"
                        + title + "</p>\n" + renderBlocks(block.children) + "</div>";
                }
                case LIST: {
                    String tag = block.ordered ? "ol" : "ul";
                    var html = new StringBuilder("<" + tag);
                    if (block.ordered && block.number != 1)
                        html.append(" start=\"").append(block.number).append('"');
                    html.append(">\n");
                    for (List<Block> item : block.items)
                        html.append(renderItem(item)).append('\n');
                    return html.append("</").append(tag).append('>').toString();
                }
                case TABLE: {
                    var html = new StringBuilder("<table>\n<thead>\n<tr>\n");
                    html.append(tableCells("th", block, block.lines)).append("</tr>\n</thead>\n");
                    if (!block.rows.isEmpty()) {
                        html.append("<tbody>\n");
                        for (List<String> row : block.rows)
                            html.append("<tr>\n")
                                .append(tableCells("td", block, row))
                                .append("</tr>\n");
                        html.append("</tbody>\n");
                    }
                    return html.append("</table>").toString();
                }
                case TOC:
                    return TOC_MARKER;
            }
            throw new IllegalStateException();
        }
        String tocList(List<Heading> entries) {
            var html = new StringBuilder("<ul>\n");
            for (Heading entry : entries) {
                html.append("<li><a href=\"#")
                    .append(entry.id)
                    .append("\">")
                    .append(entry.label)
                    .append("</a>");
                if (!entry.children.isEmpty())
                    html.append('\n').append(tocList(entry.children)).append('\n');
                html.append("</li>\n");
            }
            return html.append("</ul>").toString();
        }
        String tableOfContents() {
            if (headings.isEmpty())
                return "<nav class=\"toc\">\n</nav>";
            var roots = new ArrayList<Heading>();
            var parents = new ArrayList<Heading>();
            for (Heading heading : headings) {
                while (!parents.isEmpty() && parents.get(parents.size() - 1).level >= heading.level)
                    parents.remove(parents.size() - 1);
                if (parents.isEmpty())
                    roots.add(heading);
                else
                    parents.get(parents.size() - 1).children.add(heading);
                parents.add(heading);
            }
            return "<nav class=\"toc\">\n" + tocList(roots) + "\n</nav>";
        }
        String footnoteList() {
            var html = new StringBuilder("<section class=\"footnotes\">\n<ol>\n");
            for (int i = 0; i < notes.size(); i++) {
                Note note = notes.get(i);
                int number = i + 1;
                html.append("<li id=\"fn-")
                    .append(number)
                    .append("\">")
                    .append(inline(parser.footnotes.get(note.name), true, false));
                for (int count = 1; count <= note.count; count++)
                    html.append(" <a href=\"#")
                        .append(referenceId(number, count))
                        .append("\">&#8617;</a>");
                html.append("</li>\n");
            }
            return html.append("</ol>\n</section>\n").toString();
        }
        String document(List<Block> blocks) {
            String html = renderBlocks(blocks);
            html = html.replace(TOC_MARKER, tableOfContents());
            return notes.isEmpty() ? html : html + footnoteList();
        }
    }
    public static void main(String[] args) throws Exception {
        var input = new BufferedReader(new InputStreamReader(System.in));
        var lines = new ArrayList<String>();
        String line;
        while ((line = input.readLine()) != null && !line.equals("@@END@@"))
            lines.add(line);
        var parser = new BlockParser();
        List<Block> blocks = parser.parse(lines);
        System.out.print(new Renderer(parser).document(blocks));
    }
}
