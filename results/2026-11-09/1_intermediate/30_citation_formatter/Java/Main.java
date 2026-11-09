import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.stream.Collectors;

public class Main {
    static final List<String> FIELDS = List.of("author", "editor", "title", "journal", "booktitle", "edition", "volume", "number", "pages", "publisher", "institution", "school", "address", "howpublished", "month", "year", "doi", "note");
    static final List<String> TYPES = List.of("article", "book", "inproceedings", "incollection", "techreport", "phdthesis", "misc");
    static final List<List<String>> REQUIRED = List.of(
        List.of("author", "title", "journal", "year"), List.of("author", "title", "publisher", "year"),
        List.of("author", "title", "booktitle", "year"), List.of("author", "title", "booktitle", "publisher", "year"),
        List.of("author", "title", "institution", "year"), List.of("author", "title", "school", "year"), List.of("author", "title", "year")
    );
    static final List<String> MONTHS = List.of("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December");
    static final List<String> MONTH_MACROS = List.of("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec");
    static final List<String> MONTH_SHORT = List.of("Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec.");
    static final Set<String> SMALL_WORDS = Set.of("a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "nor", "of", "on", "or", "over", "per", "so", "the", "to", "up", "via", "with", "yet");
    static boolean lower(int c) { return c >= 'a' && c <= 'z'; }
    static boolean upper(int c) { return c >= 'A' && c <= 'Z'; }
    static boolean letter(int c) { return lower(c) || upper(c); }
    static boolean digit(int c) { return c >= '0' && c <= '9'; }
    static char lowercase(char c) { return upper(c) ? (char)(c + 'a' - 'A') : c; }
    static char uppercase(char c) { return lower(c) ? (char)(c + 'A' - 'a') : c; }
    static String lowerText(String text) { return text.toLowerCase(Locale.ROOT); }
    static String plain(String text) { return text.replace("{", "").replace("}", ""); }
    static String letters(String text) {
        var result = new StringBuilder();
        text.chars().filter(Main::letter).forEach(c -> result.append(lowercase((char)c)));
        return result.toString();
    }
    static boolean digits(String text) { return !text.isEmpty() && text.chars().allMatch(Main::digit); }
    static List<String> splitDepth(String text, String separator) {
        var result = new ArrayList<String>();
        int start = 0, i = 0, depth = 0;
        while (i < text.length()) {
            if (depth == 0 && text.startsWith(separator, i)) { result.add(text.substring(start, i)); i += separator.length(); start = i; }
            else { if (text.charAt(i) == '{') depth++; if (text.charAt(i) == '}') depth--; i++; }
        }
        result.add(text.substring(start)); return result;
    }
    static class Problem extends RuntimeException { Problem(String message) { super(message); } }
    static class LoadError extends RuntimeException {
        final int line;
        LoadError(int line, String message) { super(message); this.line = line; }
    }
    static String evaluate(String expression, Map<String, String> macros, int line) {
        int depth = 0;
        for (char c : expression.toCharArray()) {
            if (c == '{') depth++; if (c == '}') depth--;
            if (depth < 0) throw new LoadError(line, "unbalanced braces");
        }
        if (depth != 0) throw new LoadError(line, "unbalanced braces");
        var result = new StringBuilder();
        for (String term : expression.split(" # ", -1)) {
            char first = term.charAt(0);
            if (first == '{' || first == '"') result.append(term, 1, term.length() - 1);
            else if (digit(first)) result.append(term);
            else {
                String value = macros.get(term);
                if (value == null) throw new LoadError(line, "unknown macro '" + term + "'");
                result.append(value);
            }
        }
        return result.toString();
    }
    record Accent(char value, int width) {}
    static Accent accent(String text, int at) {
        if (at + 1 >= text.length() || text.charAt(at) != '\\') return null;
        char command = text.charAt(at + 1);
        if (command == '&') return new Accent('&', 2);
        boolean symbol = "'\"`^~=.".indexOf(command) >= 0;
        if (symbol && at + 2 < text.length() && letter(text.charAt(at + 2))) return new Accent(text.charAt(at + 2), 3);
        if ((symbol || "cuvH".indexOf(command) >= 0) && at + 4 < text.length() && text.charAt(at + 2) == '{' && letter(text.charAt(at + 3)) && text.charAt(at + 4) == '}') return new Accent(text.charAt(at + 3), 5);
        return null;
    }
    static String normalize(String text) {
        var accents = new StringBuilder();
        for (int i = 0; i < text.length();) {
            Accent wrapped = text.charAt(i) == '{' ? accent(text, i + 1) : null;
            if (wrapped != null && i + wrapped.width + 1 < text.length() && text.charAt(i + wrapped.width + 1) == '}') { accents.append(wrapped.value); i += wrapped.width + 2; }
            else {
                Accent current = accent(text, i);
                if (current == null) accents.append(text.charAt(i++));
                else { accents.append(current.value); i += current.width; }
            }
        }
        return Arrays.stream(accents.toString().replace('~', ' ').split(" ", -1)).filter(s -> !s.isEmpty()).collect(Collectors.joining(" "));
    }

    record Name(String first, String von, String last, String jr) {
        static Name parse(String text) {
            List<String> parts = splitDepth(text, ",").stream().map(String::trim).toList();
            List<String> words = splitDepth(parts.getFirst(), " ");
            int firstLower = -1, lastLower = -1;
            for (int i = 0; i + 1 < words.size(); i++) if (lower(words.get(i).charAt(0))) { if (firstLower < 0) firstLower = i; lastLower = i; }
            if (parts.size() == 1) {
                if (firstLower < 0) return new Name(String.join(" ", words.subList(0, words.size() - 1)), "", words.getLast(), "");
                return new Name(String.join(" ", words.subList(0, firstLower)), String.join(" ", words.subList(firstLower, lastLower + 1)), String.join(" ", words.subList(lastLower + 1, words.size())), "");
            }
            String von = lastLower < 0 ? "" : String.join(" ", words.subList(0, lastLower + 1));
            String last = String.join(" ", words.subList(lastLower + 1, words.size()));
            return new Name(parts.getLast(), von, last, parts.size() == 3 ? parts.get(1) : "");
        }
        String surname() { return plain(von.isEmpty() ? last : von + " " + last); }
        String initials() {
            return Arrays.stream(plain(first).split(" ", -1)).filter(word -> !word.isEmpty()).map(word ->
                Arrays.stream(word.split("-", -1)).map(piece -> uppercase((char)piece.chars().filter(Main::letter).findFirst().orElseThrow()) + ".").collect(Collectors.joining("-"))
            ).collect(Collectors.joining(" "));
        }
        String text(boolean inverted, boolean abbreviated) {
            String given = abbreviated ? initials() : plain(first), result = surname();
            if (!first.isEmpty()) result = inverted ? result + ", " + given : given + " " + result;
            if (!jr.isEmpty()) result += ", " + plain(jr);
            return result;
        }
    }
    record NameList(List<Name> names, boolean etAl) {
        NameList { names = List.copyOf(names); }
        static NameList parse(String text) {
            List<String> parts = splitDepth(text, " and ");
            boolean etAl = parts.getLast().equals("others");
            if (etAl) parts.removeLast();
            return new NameList(parts.stream().map(Name::parse).toList(), etAl);
        }
        boolean single() { return names.size() == 1 && !etAl; }
    }
    enum Style { APA, IEEE, CHICAGO, MLA }
    static String titleCase(String title, Style style) {
        if (style == Style.IEEE) return title;
        if (style == Style.APA) {
            char[] result = title.toCharArray(); int depth = 0;
            for (int i = 0; i < result.length; i++) {
                char c = result[i];
                if (c == '{') depth++; else if (c == '}') depth--;
                else if (depth == 0 && letter(c)) result[i] = i == 0 || i >= 2 && title.substring(i - 2, i).equals(": ") ? uppercase(c) : lowercase(c);
            }
            return new String(result);
        }
        List<String> words = splitDepth(title, " ");
        for (int i = 0; i < words.size(); i++) {
            String word = words.get(i);
            if (word.startsWith("{")) continue;
            boolean makeLower = i > 0 && i + 1 < words.size() && !words.get(i - 1).endsWith(":") && SMALL_WORDS.contains(letters(word));
            char[] result = word.toCharArray(); int depth = 0; boolean firstLetter = true;
            for (int j = 0; j < result.length; j++) {
                char c = result[j];
                if (c == '{') depth++; else if (c == '}') depth--;
                else if (letter(c)) {
                    if (depth == 0 && makeLower) result[j] = lowercase(c); else if (depth == 0 && firstLetter) result[j] = uppercase(c);
                    firstLetter = false;
                }
            }
            words.set(i, new String(result));
        }
        return String.join(" ", words);
    }
    static String listed(List<String> names, String conjunction, boolean listB) {
        if (names.size() == 1) return names.getFirst();
        if (listB && names.size() == 2) return names.getFirst() + " " + conjunction + " " + names.getLast();
        return String.join(", ", names.subList(0, names.size() - 1)) + ", " + conjunction + " " + names.getLast();
    }
    static String renderNames(NameList list, Style style, boolean editor) {
        var names = new ArrayList<String>();
        for (int i = 0; i < list.names.size(); i++) names.add(list.names.get(i).text(!editor && (style == Style.APA || style != Style.IEEE && i == 0), style == Style.APA || style == Style.IEEE));
        if (editor) return list.etAl ? names.getFirst() + " et al." : listed(names, style == Style.APA ? "&" : "and", true);
        return switch (style) {
            case APA -> list.etAl ? String.join(", ", names) + ", et al." : names.size() >= 21 ? String.join(", ", names.subList(0, 19)) + ", . . . " + names.getLast() : listed(names, "&", false);
            case IEEE -> list.etAl || names.size() >= 7 ? names.getFirst() + " et al." : listed(names, "and", true);
            case CHICAGO -> list.etAl || names.size() >= 11 ? String.join(", ", names.subList(0, Math.min(7, names.size()))) + ", et al." : listed(names, "and", false);
            case MLA -> list.etAl || names.size() >= 3 ? names.getFirst() + ", et al." : listed(names, "and", false);
        };
    }

    static class Entry {
        final String key;
        final int kind;
        final SortedMap<String, String> fields;
        final NameList authors, editors;
        final String sortLast, year, sortTitle, plainTitle, lowerTitle, baseKey;
        String suffix = "";
        Entry(String key, int kind, Map<String, String> fields) {
            this.key = key; this.kind = kind; this.fields = Collections.unmodifiableSortedMap(new TreeMap<>(fields));
            authors = fields.containsKey("author") ? NameList.parse(fields.get("author")) : null;
            editors = fields.containsKey("editor") ? NameList.parse(fields.get("editor")) : null;
            Name lead = primary().names.getFirst();
            sortLast = lowerText(plain(lead.last)); year = plain(fields.get("year"));
            plainTitle = plain(fields.get("title")); lowerTitle = lowerText(plainTitle);
            String title = lowerTitle;
            for (String prefix : List.of("a ", "an ", "the ")) if (title.startsWith(prefix)) { title = title.substring(prefix.length()); break; }
            sortTitle = title;
            var base = new StringBuilder(letters(plain(lead.last)));
            fields.get("year").chars().filter(Main::digit).forEach(c -> base.append((char)c));
            base.append(Arrays.stream(plainTitle.split(" ", -1)).map(Main::letters).filter(word -> !word.isEmpty() && !SMALL_WORDS.contains(word)).findFirst().orElse(""));
            baseKey = base.toString();
        }
        NameList primary() { return authors != null ? authors : editors; }
        String yearLabel(Style style) { return year + (style == Style.APA || style == Style.CHICAGO ? suffix : ""); }
        String shortName(Style style, boolean parenthetical) {
            NameList list = primary();
            if (list.etAl || list.names.size() >= (style == Style.CHICAGO ? 4 : 3)) return list.names.getFirst().surname() + " et al.";
            return listed(list.names.stream().map(Name::surname).toList(), style == Style.APA && parenthetical ? "&" : "and", true);
        }
        List<String> unknownFields() { return fields.keySet().stream().filter(name -> !FIELDS.contains(name)).toList(); }
    }
    static final Comparator<Entry> BIBLIOGRAPHY = Comparator.comparing((Entry entry) -> entry.sortLast).thenComparing(entry -> entry.year).thenComparing(entry -> entry.sortTitle).thenComparing(entry -> entry.key);

    static final String[][] TEMPLATES = {
        {
            "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
            "{author}. ({year}). {title}< ({edition})>. {publisher}.",
            "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
            "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
            "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
            "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>"
        }, {
            "{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.",
            "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
            "{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.",
            "{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}.",
            "{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}.",
            "{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>"
        }, {
            "{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>",
            "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
            "{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>",
            "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
            "{author}. {year}. \"{title}.\" PhD diss., {school}.",
            "{author}. {year}. {title}.< {howpublished}.>< {note}.>"
        }, {
            "{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>",
            "{author}. {title}.< {edition},> {publisher}, {year}.",
            "{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.",
            "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
            "{author}. {title}. {year}. {school}, PhD dissertation.",
            "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>"
        }
    };
    static int optionalEnd(String pattern, int start) {
        int depth = 1;
        for (int i = start + 1;; i++) {
            if (pattern.charAt(i) == '<') depth++; if (pattern.charAt(i) == '>') depth--;
            if (depth == 0) return i;
        }
    }
    static boolean optionalPresent(String pattern, int start, int end, Map<String, String> values) {
        for (int i = start; i < end; i++) {
            if (pattern.charAt(i) == '<') i = optionalEnd(pattern, i);
            else if (pattern.charAt(i) == '{') {
                int close = pattern.indexOf('}', i);
                if (values.getOrDefault(pattern.substring(i + 1, close), "").isEmpty()) return false;
                i = close;
            }
        }
        return true;
    }
    static void renderTemplate(String pattern, int start, int end, Map<String, String> values, StringBuilder result) {
        for (int i = start; i < end; i++) {
            char c = pattern.charAt(i);
            if (c == '<') {
                int close = optionalEnd(pattern, i);
                if (optionalPresent(pattern, i + 1, close, values)) renderTemplate(pattern, i + 1, close, values, result);
                i = close;
            } else if (c == '{') {
                int close = pattern.indexOf('}', i);
                result.append(values.getOrDefault(pattern.substring(i + 1, close), "")); i = close;
            } else if (c != '.' || result.isEmpty() || ".?!".indexOf(result.charAt(result.length() - 1)) < 0) result.append(c);
        }
    }
    static String reference(Entry entry, Style style, int number, boolean repeated) {
        var values = new HashMap<String, String>();
        for (String name : FIELDS) values.put(name, plain(entry.fields.getOrDefault(name, "")));
        NameList names = entry.primary();
        String author = repeated ? "---" : renderNames(names, style, false);
        if (entry.authors == null) {
            String[][] annotations = {{" (Ed.)", " (Eds.)"}, {", Ed.", ", Eds."}, {", ed.", ", eds."}, {", editor", ", editors"}};
            author += annotations[style.ordinal()][names.single() ? 0 : 1];
        }
        values.put("author", author);
        if (entry.editors != null) { values.put("editor", renderNames(entry.editors, style, true)); values.put("eds", entry.editors.single() ? "Ed." : "Eds."); }
        values.put("title", plain(titleCase(entry.fields.get("title"), style))); values.put("year", entry.yearLabel(style));
        if (entry.fields.containsKey("pages")) {
            String pages = plain(entry.fields.get("pages")).replace("--", "-");
            values.put("pages", pages); values.put("pp", (pages.contains("-") ? "pp. " : "p. ") + pages);
        }
        if (entry.fields.containsKey("edition")) {
            String edition = plain(entry.fields.get("edition"));
            if (digits(edition)) {
                int n = Integer.parseInt(edition);
                String suffix = n % 100 >= 11 && n % 100 <= 13 ? "th" : switch (n % 10) { case 1 -> "st"; case 2 -> "nd"; case 3 -> "rd"; default -> "th"; };
                edition = n + suffix;
            }
            values.put("edition", edition + " ed.");
        }
        if (entry.fields.containsKey("month")) {
            String month = plain(entry.fields.get("month")); int index = MONTHS.indexOf(month);
            values.put("mon", index >= 0 ? MONTH_SHORT.get(index) : month);
        }
        int kind = entry.kind == 3 ? 2 : entry.kind > 3 ? entry.kind - 1 : entry.kind;
        String pattern = TEMPLATES[style.ordinal()][kind];
        var result = new StringBuilder(style == Style.IEEE ? "[" + number + "] " : "");
        renderTemplate(pattern, 0, pattern.length(), values, result); return result.toString();
    }
    record Numbering(List<Entry> order, Map<Entry, Integer> numbers) {}
    enum CitationKind { PARENTHETICAL, NARRATIVE, AUTHOR, YEAR }
    record Citation(int start, int end, CitationKind kind, List<Entry> entries) {}
    record Pair(String first, String second) implements Comparable<Pair> {
        public int compareTo(Pair other) { int order = first.compareTo(other.first); return order != 0 ? order : second.compareTo(other.second); }
    }
    static class Database {
        final List<Entry> entries = new ArrayList<>(), record = new ArrayList<>();
        final Map<String, Entry> lookup = new TreeMap<>();
        final Map<String, String> macros = new HashMap<>();
        final List<String> output = new ArrayList<>();
        int macroCount;
        Database(List<String> lines) {
            for (int i = 0; i < 12; i++) macros.put(MONTH_MACROS.get(i), MONTHS.get(i));
            for (int i = 0; i < lines.size(); i++) {
                String line = lines.get(i);
                if (line.isEmpty() || line.startsWith("%")) continue;
                if (line.startsWith("@string{")) {
                    int equals = line.indexOf(" = "); String name = line.substring(8, equals);
                    try {
                        String value = evaluate(line.substring(equals + 3, line.length() - 1), macros, i + 1);
                        if (macros.containsKey(name)) throw new LoadError(i + 1, "duplicate macro");
                        macros.put(name, value); macroCount++;
                    } catch (LoadError error) { report(name, error); }
                } else {
                    int end = i + 1;
                    while (!lines.get(end).equals("}")) end++;
                    int brace = line.indexOf('{'); String kind = line.substring(1, brace), key = line.substring(brace + 1, line.length() - 1);
                    try { readEntry(lines, i, end, kind, key); } catch (LoadError error) { report(key, error); }
                    i = end;
                }
            }
            output.add("LOADED entries=" + entries.size() + " macros=" + macroCount + " errors=" + output.size());
            var assigned = new HashSet<Entry>();
            for (Entry entry : entries) {
                if (assigned.contains(entry)) continue;
                List<Entry> group = entries.stream().filter(other -> entry.primary().equals(other.primary()) && entry.fields.get("year").equals(other.fields.get("year"))).sorted(Comparator.comparing((Entry e) -> e.sortTitle).thenComparing(e -> e.key)).toList();
                assigned.addAll(group);
                if (group.size() >= 2) for (int i = 0; i < group.size(); i++) group.get(i).suffix = String.valueOf((char)('a' + i));
            }
        }
        void report(String name, LoadError error) { output.add("ERROR line " + error.line + ": " + name + ": " + error.getMessage()); }
        void readEntry(List<String> lines, int start, int end, String kindName, String key) {
            int kind = TYPES.indexOf(kindName);
            if (kind < 0) throw new LoadError(start + 1, "unknown type '" + kindName + "'");
            if (lookup.containsKey(key)) throw new LoadError(start + 1, "duplicate key");
            var fields = new TreeMap<String, String>();
            for (int i = start + 1; i < end; i++) {
                String line = lines.get(i); int equals = line.indexOf(" = ");
                String name = line.substring(2, equals), expression = line.substring(equals + 3);
                if (expression.endsWith(",")) expression = expression.substring(0, expression.length() - 1);
                String value = evaluate(expression, macros, i + 1);
                if (fields.containsKey(name)) throw new LoadError(i + 1, "duplicate field '" + name + "'");
                fields.put(name, normalize(value));
            }
            for (String name : REQUIRED.get(kind)) if (!fields.containsKey(name) && !(kind == 1 && name.equals("author") && fields.containsKey("editor"))) throw new LoadError(end + 1, "missing field '" + name + "'");
            Entry entry = new Entry(key, kind, fields); entries.add(entry); lookup.put(key, entry);
        }
        Numbering numbering() {
            var cited = new HashSet<>(record); var order = new ArrayList<>(record);
            for (Entry entry : lookup.values()) if (!cited.contains(entry)) order.add(entry);
            var numbers = new HashMap<Entry, Integer>();
            for (int i = 0; i < order.size(); i++) numbers.put(order.get(i), i + 1);
            return new Numbering(order, numbers);
        }
        String citationText(Citation citation, Style style, Map<Entry, Integer> numbers) {
            boolean parenthetical = citation.kind == CitationKind.PARENTHETICAL;
            if (citation.kind == CitationKind.AUTHOR || citation.kind == CitationKind.YEAR || style == Style.MLA || style == Style.IEEE && !parenthetical) {
                String text = citation.entries.stream().map(entry -> citation.kind == CitationKind.YEAR ? entry.yearLabel(style) : entry.shortName(style, false) + (style == Style.IEEE && citation.kind == CitationKind.NARRATIVE ? " [" + numbers.get(entry) + "]" : "")).collect(Collectors.joining(citation.kind == CitationKind.YEAR ? ", " : "; "));
                return style == Style.MLA && parenthetical ? "(" + text + ")" : text;
            }
            var parts = new ArrayList<String>();
            if (style == Style.IEEE) {
                List<Integer> sorted = citation.entries.stream().map(numbers::get).sorted().toList();
                for (int i = 0; i < sorted.size();) {
                    int end = i + 1;
                    while (end < sorted.size() && sorted.get(end) == sorted.get(end - 1) + 1) end++;
                    if (end - i >= 3) parts.add("[" + sorted.get(i) + "]-[" + sorted.get(end - 1) + "]");
                    else for (int j = i; j < end; j++) parts.add("[" + sorted.get(j) + "]");
                    i = end;
                }
                return String.join(", ", parts);
            }
            var keys = new ArrayList<>(citation.entries);
            if (parenthetical) keys.sort(BIBLIOGRAPHY);
            for (int i = 0; i < keys.size();) {
                String name = keys.get(i).shortName(style, parenthetical); int end = i + 1;
                while (end < keys.size() && keys.get(end).shortName(style, parenthetical).equals(name)) end++;
                String years = keys.subList(i, end).stream().map(entry -> entry.yearLabel(style)).collect(Collectors.joining(", "));
                parts.add(parenthetical ? name + (style == Style.APA ? ", " : " ") + years : name + " (" + years + ")"); i = end;
            }
            String text = String.join("; ", parts); return parenthetical ? "(" + text + ")" : text;
        }
        String cite(Style style, String text) {
            var citations = new ArrayList<Citation>();
            for (int start = text.indexOf('\\'); start >= 0;) {
                int brace = text.indexOf('{', start), end = text.indexOf('}', brace);
                CitationKind kind = switch (text.substring(start + 1, brace)) { case "citet" -> CitationKind.NARRATIVE; case "citeauthor" -> CitationKind.AUTHOR; case "citeyear" -> CitationKind.YEAR; default -> CitationKind.PARENTHETICAL; };
                var seen = new LinkedHashSet<Entry>();
                for (String key : text.substring(brace + 1, end).split(",")) {
                    Entry entry = lookup.get(key);
                    if (entry == null) throw new Problem("unknown key '" + key + "'");
                    seen.add(entry);
                }
                citations.add(new Citation(start, end + 1, kind, List.copyOf(seen))); start = text.indexOf('\\', end + 1);
            }
            var recorded = new HashSet<>(record);
            for (Citation citation : citations) for (Entry entry : citation.entries) if (recorded.add(entry)) record.add(entry);
            Map<Entry, Integer> numbers = numbering().numbers; var result = new StringBuilder(); int position = 0;
            for (Citation citation : citations) { result.append(text, position, citation.start).append(citationText(citation, style, numbers)); position = citation.end; }
            return result.append(text, position, text.length()).toString();
        }
        List<String> keygen() {
            var counts = new HashMap<String, Integer>(); var used = new HashMap<String, Integer>();
            for (Entry entry : entries) counts.merge(entry.baseKey, 1, Integer::sum);
            var result = new ArrayList<String>();
            for (Entry entry : entries) {
                String key = entry.baseKey;
                if (counts.get(key) >= 2) { int index = used.getOrDefault(key, 0); used.put(key, index + 1); key += (char)('a' + index); }
                result.add(entry.key + " -> " + key);
            }
            return result;
        }
        List<String> check() {
            var result = new ArrayList<String>(); var titles = new HashMap<String, String>();
            for (Entry entry : entries) {
                var warnings = new ArrayList<String>();
                if (entry.fields.containsKey("pages")) {
                    String pages = plain(entry.fields.get("pages"));
                    if (pages.contains("-") && !pages.contains("--")) warnings.add("pages use a single hyphen");
                    List<String> parts = Arrays.stream(pages.split("-", -1)).filter(part -> !part.isEmpty()).toList();
                    if (parts.size() == 2 && parts.stream().allMatch(Main::digits) && Integer.parseInt(parts.getFirst()) > Integer.parseInt(parts.getLast())) warnings.add("pages are reversed");
                }
                if (entry.year.length() != 4 || !digits(entry.year)) warnings.add("year is not 4 digits");
                if (entry.plainTitle.chars().noneMatch(Main::lower) && entry.plainTitle.chars().filter(Main::upper).count() >= 2) warnings.add("title is all caps");
                if (entry.kind == 0 && !entry.fields.containsKey("doi")) warnings.add("article has no doi");
                if (titles.containsKey(entry.lowerTitle)) warnings.add("same title as " + titles.get(entry.lowerTitle));
                else titles.put(entry.lowerTitle, entry.key);
                for (String field : entry.unknownFields()) warnings.add("unknown field '" + field + "'");
                for (String warning : warnings) result.add("WARN " + entry.key + ": " + warning);
            }
            result.add("CHECK warnings=" + result.size()); return result;
        }
        List<String> export(String key) {
            Entry entry = lookup.get(key);
            if (entry == null) throw new Problem("unknown key '" + key + "'");
            var names = new ArrayList<String>();
            for (String name : FIELDS) if (entry.fields.containsKey(name)) names.add(name);
            names.addAll(entry.unknownFields());
            var result = new ArrayList<String>(); result.add("@" + TYPES.get(entry.kind) + "{" + key + ",");
            for (int i = 0; i < names.size(); i++) { String name = names.get(i); result.add("  " + name + " = {" + entry.fields.get(name) + "}" + (i + 1 == names.size() ? "" : ",")); }
            result.add("}"); return result;
        }
        List<String> stats() {
            var types = new TreeMap<String, Integer>(); var years = new TreeMap<String, Integer>();
            var authors = new HashSet<String>(); var pairs = new TreeMap<Pair, Integer>();
            for (Entry entry : entries) {
                types.merge(TYPES.get(entry.kind), 1, Integer::sum); years.merge(entry.year, 1, Integer::sum);
                if (entry.authors != null) {
                    var distinct = new TreeSet<String>();
                    for (Name name : entry.authors.names) distinct.add(name.text(false, false));
                    authors.addAll(distinct); var names = new ArrayList<>(distinct);
                    for (int a = 0; a < names.size(); a++) for (int b = a + 1; b < names.size(); b++) pairs.merge(new Pair(names.get(a), names.get(b)), 1, Integer::sum);
                }
            }
            var result = new ArrayList<String>(); result.add("ENTRIES " + entries.size());
            types.forEach((type, count) -> result.add("TYPE " + type + " " + count));
            years.forEach((year, count) -> result.add("YEAR " + year + " " + count));
            result.add("AUTHORS " + authors.size());
            Pair best = null; int count = 0;
            for (var pair : pairs.entrySet()) if (pair.getValue() > count) { best = pair.getKey(); count = pair.getValue(); }
            result.add(best == null ? "PAIR none" : "PAIR " + best.first + " & " + best.second + " " + count); return result;
        }
        List<String> command(String line) {
            String command = line.split(" ", 2)[0];
            String[] words = line.split(" ", command.equals("CITE") || command.equals("SEARCH") ? 3 : -1);
            int arity = switch (command) {
                case "FORMAT" -> -1; case "BIBLIOGRAPHY", "EXPORT" -> 1; case "CITE", "SEARCH" -> 2; case "KEYGEN", "CHECK", "STATS" -> 0;
                default -> throw new Problem("unknown command '" + command + "'");
            };
            if (arity == -1 ? words.length < 3 : words.length != arity + 1) throw new Problem("wrong number of arguments");
            Style style = Style.APA;
            if (command.equals("FORMAT") || command.equals("BIBLIOGRAPHY") || command.equals("CITE")) {
                style = switch (words[1]) { case "APA" -> Style.APA; case "IEEE" -> Style.IEEE; case "CHICAGO" -> Style.CHICAGO; case "MLA" -> Style.MLA; default -> throw new Problem("unknown style '" + words[1] + "'"); };
            }
            var result = new ArrayList<String>();
            switch (command) {
                case "FORMAT" -> {
                    Numbering numbering = numbering();
                    for (int i = 2; i < words.length; i++) {
                        Entry entry = lookup.get(words[i]);
                        result.add(entry == null ? "ERROR unknown key '" + words[i] + "'" : reference(entry, style, numbering.numbers.get(entry), false));
                    }
                }
                case "BIBLIOGRAPHY" -> {
                    Numbering numbering = numbering(); List<Entry> order = numbering.order;
                    if (style != Style.IEEE) order.sort(BIBLIOGRAPHY);
                    result.add(style == Style.MLA ? "Works Cited" : "References");
                    for (int i = 0; i < order.size(); i++) {
                        Entry entry = order.get(i);
                        boolean repeated = i > 0 && (style == Style.CHICAGO || style == Style.MLA) && entry.primary().equals(order.get(i - 1).primary());
                        result.add(reference(entry, style, numbering.numbers.get(entry), repeated));
                    }
                }
                case "CITE" -> result.add(cite(style, words[2]));
                case "KEYGEN" -> result.addAll(keygen()); case "CHECK" -> result.addAll(check()); case "EXPORT" -> result.addAll(export(words[1])); case "STATS" -> result.addAll(stats());
                case "SEARCH" -> {
                    String needle = lowerText(words[2]); var matches = new ArrayList<String>();
                    for (Entry entry : entries) if (entry.fields.containsKey(words[1]) && lowerText(plain(entry.fields.get(words[1]))).contains(needle)) matches.add(entry.key);
                    result.add(matches.isEmpty() ? "MATCHES 0" : "MATCHES " + matches.size() + ": " + String.join(" ", matches));
                }
                default -> throw new AssertionError();
            }
            return result;
        }
    }
    public static void main(String[] args) throws IOException {
        var reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.US_ASCII));
        var lines = new ArrayList<String>();
        for (String line = reader.readLine(); !line.equals("%%"); line = reader.readLine()) lines.add(line);
        var database = new Database(lines);
        var writer = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8));
        for (String line : database.output) { writer.write(line); writer.write('\n'); }
        int count = Integer.parseInt(reader.readLine());
        for (int i = 0; i < count; i++) {
            try { for (String line : database.command(reader.readLine())) { writer.write(line); writer.write('\n'); } }
            catch (Problem error) { writer.write("ERROR " + error.getMessage()); writer.write('\n'); }
        }
        writer.flush();
    }
}
