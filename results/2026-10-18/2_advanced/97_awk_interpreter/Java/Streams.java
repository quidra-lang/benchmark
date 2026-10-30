import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
final class Streams {
    record Option(String name, String value) {}
    static final class Operand {
        final boolean file;
        final String name, value;
        int records;
        Operand(boolean file, String name, String value) {
            this.file = file;
            this.name = name;
            this.value = value;
        }
    }
    record Arguments(List<Option> options, List<Operand> operands) {}
    record Read(int status, String line) {}
    static boolean validName(String name) {
        if (name.isEmpty() || !Lexer.letter(name.charAt(0)))
            return false;
        for (int i = 1; i < name.length(); i++)
            if (!Lexer.letter(name.charAt(i)) && !Lexer.digit(name.charAt(i)))
                return false;
        return true;
    }
    static boolean validFilename(String name) {
        if (name.isEmpty() || name.charAt(0) == '.')
            return false;
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            if (!Lexer.letter(c) && !Lexer.digit(c) && ".-".indexOf(c) < 0)
                return false;
        }
        return true;
    }
    static List<String> lines(String text) {
        List<String> result = new ArrayList<>();
        int start = 0;
        for (int i = 0; i < text.length(); i++)
            if (text.charAt(i) == '\n') {
                result.add(text.substring(start, i));
                start = i + 1;
            }
        if (start < text.length())
            result.add(text.substring(start));
        return result;
    }
    static List<String> records(String name) throws IOException {
        return lines(Files.readString(Path.of("input", name), StandardCharsets.US_ASCII));
    }
    static Arguments parse(String text) {
        List<Option> options = new ArrayList<>();
        List<Operand> operands = new ArrayList<>();
        for (String line : lines(text)) {
            int equal = line.indexOf('=');
            if (line.startsWith("-F "))
                options.add(new Option("FS", line.substring(3)));
            else if (line.startsWith("-v ")) {
                equal = line.indexOf('=', 3);
                options.add(new Option(line.substring(3, equal), line.substring(equal + 1)));
            } else if (equal >= 0 && validName(line.substring(0, equal)))
                operands.add(
                    new Operand(false, line.substring(0, equal), line.substring(equal + 1)));
            else
                operands.add(new Operand(true, line, null));
        }
        return new Arguments(options, operands);
    }
    static final class Output {
        final StringBuilder content = new StringBuilder();
        boolean open;
        int writes;
        void append(String text) {
            content.append(text);
            writes++;
        }
    }
    static final class Input {
        boolean open, everOpened;
        List<String> lines = List.of();
        int position, reads;
    }
    final Output stdout = new Output();
    final LinkedHashMap<String, Output> outputs = new LinkedHashMap<>();
    final LinkedHashMap<String, Input> inputs = new LinkedHashMap<>();
    void write(String text, String name, String mode, Lexer.Position pos) {
        if (name == null) {
            stdout.append(text);
            return;
        }
        if (!validFilename(name) || name.equals("stdout.txt") || name.equals("stats.txt"))
            throw new Builtins.RuntimeIssue(pos, "invalid output file name");
        Output output = outputs.computeIfAbsent(name, key -> new Output());
        if (!output.open) {
            output.open = true;
            if (mode.equals(">"))
                output.content.setLength(0);
        }
        output.append(text);
    }
    Read getline(String name) throws IOException {
        Input input = inputs.computeIfAbsent(name, key -> new Input());
        if (!input.open) {
            if (!validFilename(name) || !Files.isRegularFile(Path.of("input", name)))
                return new Read(-1, null);
            input.lines = records(name);
            input.position = 0;
            input.open = true;
            input.everOpened = true;
        }
        if (input.position == input.lines.size())
            return new Read(0, null);
        input.reads++;
        return new Read(1, input.lines.get(input.position++));
    }
    int close(String name) {
        boolean closed = false;
        Output output = outputs.get(name);
        if (output != null && output.open) {
            output.open = false;
            closed = true;
        }
        Input input = inputs.get(name);
        if (input != null && input.open) {
            input.open = false;
            closed = true;
        }
        return closed ? 0 : -1;
    }
    void save() throws IOException {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output/stdout.txt"), stdout.content, StandardCharsets.US_ASCII);
        for (var entry : outputs.entrySet())
            Files.writeString(Path.of("output", entry.getKey()), entry.getValue().content,
                              StandardCharsets.US_ASCII);
    }
}
