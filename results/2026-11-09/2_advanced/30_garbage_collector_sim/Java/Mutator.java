import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

record CollectorEntry(String name, String type, int young, int age) {}
final class Config {
    int heap, width;
    final List<CollectorEntry> collectors = new ArrayList<>();
    List<String> maps = new ArrayList<>();
    final List<Integer> windows = new ArrayList<>();
}
final class Command {
    final int line;
    final String name;
    int pointers, data, slot, field, count;
    int source = -1;
    String label = "";
    Command(int line, String name) {
        this.line = line;
        this.name = name;
    }
}
record Parsed(Command command, String error) {}
final class Mutator {
    static final String[] NAMES = {"ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT"};
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Config config() throws IOException {
        Config config = new Config();
        for (String line : lines("config.txt")) {
            String[] fields = line.split(" ");
            switch (fields[0]) {
            case "HEAP" -> config.heap = Integer.parseInt(fields[1]);
            case "COLLECTOR" ->
                config.collectors.add(new CollectorEntry(
                    fields[1], fields[2], fields.length > 3 ? Integer.parseInt(fields[3]) : 0,
                    fields.length > 4 ? Integer.parseInt(fields[4]) : 0));
            case "MAPS" -> config.maps = List.of(Arrays.copyOfRange(fields, 1, fields.length));
            case "MMU" -> {
                for (int i = 1; i < fields.length; i++)
                    config.windows.add(Integer.parseInt(fields[i]));
            }
            default -> config.width = Integer.parseInt(fields[1]);
            }
        }
        return config;
    }
    static Parsed parse(int line, String text) {
        String[] tokens = text.split(" ", -1);
        String form = switch (tokens[0]) {
            case "ALLOC", "LOAD", "OVERWRITE" -> "nn";
            case "PUSH" -> "r";
            case "POP" -> "n";
            case "SET" -> "nnr";
            case "CHECKPOINT" -> "l";
            default -> "";
        };
        if (tokens[0].equals("OVERWRITE"))
            form = "nr";
        if (form.isEmpty() || tokens.length != form.length() + 1)
            return new Parsed(null, "syntax");
        for (int i = 0; i < form.length(); i++) {
            String token = tokens[i + 1];
            char kind = form.charAt(i);
            if (kind == 'l') {
                if (!token.matches("[a-z0-9_]{1,16}"))
                    return new Parsed(null, "syntax");
            } else if (!(kind == 'r' && token.equals("-")) && !token.matches("0|[1-9][0-9]{0,3}"))
                return new Parsed(null, "syntax");
        }
        Command command = new Command(line, tokens[0]);
        switch (command.name) {
        case "ALLOC" -> {
            command.pointers = Integer.parseInt(tokens[1]);
            command.data = Integer.parseInt(tokens[2]);
        }
        case "PUSH" -> command.source = tokens[1].equals("-") ? -1 : Integer.parseInt(tokens[1]);
        case "POP" -> command.count = Integer.parseInt(tokens[1]);
        case "LOAD", "SET" -> {
            command.slot = Integer.parseInt(tokens[1]);
            command.field = Integer.parseInt(tokens[2]);
            if (command.name.equals("SET"))
                command.source = tokens[3].equals("-") ? -1 : Integer.parseInt(tokens[3]);
        }
        case "OVERWRITE" -> {
            command.slot = Integer.parseInt(tokens[1]);
            command.source = tokens[2].equals("-") ? -1 : Integer.parseInt(tokens[2]);
        }
        default -> command.label = tokens[1];
        }
        if (command.name.equals("ALLOC") && (command.pointers > 6 || command.data > 24) ||
            command.name.equals("POP") && command.count == 0)
            return new Parsed(command, "range");
        return new Parsed(command, "");
    }
}
