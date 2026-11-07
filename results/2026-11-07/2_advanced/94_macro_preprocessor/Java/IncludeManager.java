import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class IncludeManager {
    static final Set<String> STARTS = Set.of("if", "ifdef", "ifndef"),
                             BRANCHES = Set.of("elif", "elifdef", "elifndef", "else");
    static String directiveName(List<Lexer.Token> tokens) {
        return tokens.size() >= 2 && tokens.get(0).spelling().equals("#") &&
                tokens.get(1).kind().equals("identifier")
            ? tokens.get(1).spelling()
            : null;
    }
    static String guard(List<Lexer.LogicalLine> lines) {
        List<List<Lexer.Token>> nonempty = new ArrayList<>();
        for (Lexer.LogicalLine line : lines)
            if (!line.tokens().isEmpty())
                nonempty.add(line.tokens());
        if (nonempty.isEmpty())
            return null;
        List<Lexer.Token> first = nonempty.getFirst(), last = nonempty.getLast();
        if (first.size() != 3 || !"ifndef".equals(directiveName(first)) ||
            !first.get(2).kind().equals("identifier"))
            return null;
        if (last.size() != 2 || !"endif".equals(directiveName(last)))
            return null;
        int depth = 0;
        for (int i = 0; i < nonempty.size(); i++) {
            String name = directiveName(nonempty.get(i));
            if (name != null && BRANCHES.contains(name) && depth == 1)
                return null;
            if (name != null && STARTS.contains(name))
                depth++;
            else if ("endif".equals(name))
                depth--;
            if (depth == 0 && i != nonempty.size() - 1)
                return null;
        }
        return depth == 0 ? first.get(2).spelling() : null;
    }
    static final class SourceFile {
        String path, guard;
        int physicalLines, entered, skipped, outputLines, skippedLines;
        boolean once;
        List<Lexer.LogicalLine> lines;
        SourceFile(String path, String content) {
            this.path = path;
            for (int i = 0; i < content.length(); i++)
                if (content.charAt(i) == '\n')
                    physicalLines++;
            lines = Lexer.source(content);
            guard = IncludeManager.guard(lines);
        }
    }
    Map<String, SourceFile> files = new LinkedHashMap<>();
    String search(String name, boolean quoted) {
        List<String> paths = quoted ? List.of(name, "include/" + name) : List.of("include/" + name);
        for (String path : paths)
            if (Files.isRegularFile(Path.of("input", path)))
                return path;
        return null;
    }
    SourceFile load(String path) throws Exception {
        SourceFile source = files.get(path);
        if (source == null) {
            source = new SourceFile(
                path, Files.readString(Path.of("input", path), StandardCharsets.US_ASCII));
            files.put(path, source);
        }
        return source;
    }
}
