import java.util.*;
final class DocumentParser {
    static final Set<String> BODY = Set.of("paragraph", "item", "enum", "quote", "term");
    static final Set<String> PREAMBLE = Set.of("page", "header", "footer"),
                             EMPTY = Set.of("newpage", "verbatim", "toc", "lot", "index", "bibliography"),
                             NAMES = Set.of("width", "indent", "align", "page", "header", "footer", "newpage",
                                            "hyphenation", "bib", "title", "author", "h1", "h2", "item",
                                            "enum", "quote", "term", "table", "verbatim", "toc", "lot",
                                            "index", "bibliography");
    record Source(int line, String text) {}
    record Warning(int line, String text) {}
    static final class Bib {
        int line;
        String key, author, year, title, base, label;
        boolean cited;
        Bib(int line, String key, String author, String year, String title) {
            this.line = line;
            this.key = key;
            this.author = author;
            this.year = year;
            this.title = title;
        }
    }
    static final class Block {
        String kind, argument, align, term = "", columns = "", caption = "", text = "", label, number = "";
        int line, width, indent, id, paragraph;
        boolean pageBreak;
        final List<Source> body = new ArrayList<>(), inner = new ArrayList<>();
        final List<Main.Token> tokens = new ArrayList<>();
        List<List<String>> tableRows = new ArrayList<>();
        List<String> tableLines = new ArrayList<>();
    }
    static final class Document {
        int height = 40, width = 60;
        String[] header = {"", "", ""}, footer = {"", "", ""};
        final List<Block> blocks = new ArrayList<>();
        final List<Warning> warnings = new ArrayList<>();
        final List<String> additions = new ArrayList<>();
        final List<Bib> bibliography = new ArrayList<>();
    }
    static boolean valid(String name, String argument) {
        if (Set.of("width", "indent", "page").contains(name)) {
            if (!argument.matches("[0-9]{1,9}"))
                return false;
            int value = Integer.parseInt(argument);
            return name.equals("width") ? value >= 20 && value <= 80
            : name.equals("indent")     ? value <= 8
                                        : value >= 10 && value <= 100;
        }
        if (name.equals("align"))
            return Set.of("left", "right", "center", "justify").contains(argument);
        if (name.equals("header") || name.equals("footer"))
            return argument.split("\\|", -1).length == 3;
        if (EMPTY.contains(name))
            return argument.isEmpty();
        if (name.equals("hyphenation"))
            return argument.matches("[a-z]+(-[a-z]+)*( [a-z]+(-[a-z]+)*)*");
        if (name.equals("bib")) {
            int space = argument.indexOf(' ');
            if (space < 0 || !argument.substring(0, space).matches("[a-z0-9]+"))
                return false;
            String[] fields = argument.substring(space + 1).split("\\|", -1);
            return fields.length == 3 && !fields[0].isEmpty() && fields[1].matches("[0-9]{4}") &&
                !fields[2].isEmpty();
        }
        if (name.equals("term")) {
            int separator = argument.indexOf('|');
            return separator > 0 && separator + 1 < argument.length();
        }
        if (name.equals("table"))
            return argument.split(" ", -1)[0].matches("[lrc]+");
        return !argument.isEmpty();
    }
    static final class State {
        final Document document = new Document();
        int width = 60, indent;
        String align = "left";
        boolean pending;
        Block create(String kind, int line, String argument) {
            if (document.blocks.isEmpty())
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
            document.blocks.add(block);
            return block;
        }
    }
    static Document parse(List<String> lines) {
        State state = new State();
        Document document = state.document;
        Set<String> accepted = new HashSet<>();
        Block open = null;
        for (int index = 0; index < lines.size(); index++) {
            String line = lines.get(index);
            int number = index + 1;
            if (line.isEmpty()) {
                open = null;
                continue;
            }
            if (!line.startsWith(".")) {
                if (open == null)
                    open = state.create("paragraph", number, "");
                open.body.add(new Source(number, line));
                continue;
            }
            open = null;
            int space = line.indexOf(' ');
            String name = line.substring(1, space < 0 ? line.length() : space),
                   argument = space < 0 ? "" : line.substring(space + 1), warning = null;
            if (!NAMES.contains(name))
                warning = "unknown directive ." + name;
            else if (!valid(name, argument))
                warning = "bad argument for ." + name;
            else if (PREAMBLE.contains(name) && !document.blocks.isEmpty())
                warning = "." + name + " ignored after the preamble";
            else if (PREAMBLE.contains(name) && accepted.contains(name))
                warning = "duplicate ." + name;
            if (warning != null) {
                document.warnings.add(new Warning(number, warning));
                continue;
            }
            if (name.equals("width"))
                state.width = Integer.parseInt(argument);
            else if (name.equals("indent"))
                state.indent = Integer.parseInt(argument);
            else if (name.equals("align"))
                state.align = argument;
            else if (PREAMBLE.contains(name)) {
                accepted.add(name);
                if (name.equals("page"))
                    document.height = Integer.parseInt(argument);
                else if (name.equals("header"))
                    document.header = argument.split("\\|", -1);
                else
                    document.footer = argument.split("\\|", -1);
            } else if (name.equals("newpage"))
                state.pending = true;
            else if (name.equals("hyphenation"))
                document.additions.addAll(List.of(argument.split(" ")));
            else if (name.equals("bib")) {
                int separator = argument.indexOf(' ');
                String[] fields = argument.substring(separator + 1).split("\\|", -1);
                document.bibliography.add(
                    new Bib(number, argument.substring(0, separator), fields[0], fields[1], fields[2]));
            } else {
                Block block = state.create(name, number, argument);
                if (Set.of("item", "enum", "quote").contains(name)) {
                    block.body.add(new Source(number, argument));
                    open = block;
                } else if (name.equals("term")) {
                    int separator = argument.indexOf('|');
                    block.term = argument.substring(0, separator);
                    block.body.add(new Source(number, argument.substring(separator + 1)));
                    open = block;
                } else if (name.equals("verbatim") || name.equals("table")) {
                    if (name.equals("table")) {
                        int separator = argument.indexOf(' ');
                        block.columns = separator < 0 ? argument : argument.substring(0, separator);
                        block.caption = separator < 0 ? "" : argument.substring(separator + 1);
                    }
                    index++;
                    while (index < lines.size() && !lines.get(index).equals(".end")) {
                        block.inner.add(new Source(index + 1, lines.get(index)));
                        index++;
                    }
                    if (index == lines.size())
                        document.warnings.add(new Warning(number, "unterminated " + name));
                }
            }
        }
        return document;
    }
}
