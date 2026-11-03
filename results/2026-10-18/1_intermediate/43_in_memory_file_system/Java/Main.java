import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.function.Consumer;

public class Main {
    sealed abstract static class Node permits Directory, FileNode, Link {
        final int inode;
        int modified;
        Directory parent;
        String name = "";
        Node(int inode, int modified) { this.inode = inode; this.modified = modified; }
        abstract long size();
        abstract char tag();
        int links() { return 1; }
    }

    static final class Directory extends Node {
        final NavigableMap<String, Node> entries = new TreeMap<>();
        Directory(int inode, int modified) { super(inode, modified); }
        long size() { return entries.size(); }
        char tag() { return 'd'; }
        int links() {
            int result = 2;
            for (Node child : entries.values()) if (child instanceof Directory) result++;
            return result;
        }
    }

    static final class FileNode extends Node {
        List<String> lines;
        FileNode(int inode, int modified, List<String> lines) {
            super(inode, modified);
            this.lines = new ArrayList<>(lines);
        }
        long size() {
            long result = 0;
            for (String line : lines) result += (long) line.length() + 1;
            return result;
        }
        char tag() { return 'f'; }
    }

    static final class Link extends Node {
        final String target;
        Link(int inode, int modified, String target) {
            super(inode, modified);
            this.target = target;
        }
        long size() { return target.length(); }
        char tag() { return 'l'; }
    }

    enum Failure {
        NONE(""), MISSING("No such file or directory"),
        NOT_DIRECTORY("Not a directory"), LOOP("Too many levels of symbolic links");
        final String reason;
        Failure(String reason) { this.reason = reason; }
    }
    record Resolution(Node node, Failure failure, Directory creationParent, String creationName) {
        static Resolution found(Node node) { return new Resolution(node, Failure.NONE, null, ""); }
        static Resolution failed(Failure failure) { return new Resolution(null, failure, null, ""); }
        boolean absent() { return creationParent != null; }
        String reason() { return failure.reason; }
    }
    record Options(Set<Character> flags, List<String> paths) {
        boolean has(char flag) { return flags.contains(flag); }
    }
    record Listed(String name, Node node) {}
    record Input(List<String> lines, String name) {}
    @FunctionalInterface interface Visitor { void accept(Node node, String path, int depth); }

    static final class Output {
        final PrintWriter terminal;
        final boolean direct;
        final List<String> lines = new ArrayList<>();
        Output(PrintWriter terminal, boolean direct) { this.terminal = terminal; this.direct = direct; }
        void emit(String line) {
            if (direct) terminal.print(line + "\n");
            else lines.add(line);
        }
        void print(String format, Object... args) { emit(String.format(Locale.ROOT, format, args)); }
        void error(String format, Object... args) { terminal.printf(Locale.ROOT, format + "\n", args); }
    }

    static Options options(List<String> args) {
        Set<Character> flags = new HashSet<>();
        int at = 0;
        while (at < args.size() && args.get(at).startsWith("-")) {
            String word = args.get(at++);
            for (int i = 1; i < word.length(); i++) flags.add(word.charAt(i));
        }
        return new Options(Set.copyOf(flags), args.subList(at, args.size()));
    }
    static String lastComponent(String path) { return path.substring(path.lastIndexOf('/') + 1); }
    static boolean invalidSource(String path) {
        return switch (lastComponent(path)) { case "", ".", ".." -> true; default -> false; };
    }
    static String joinPath(String path, String name) { return path.equals("/") ? "/" + name : path + "/" + name; }

    static final class Shell {
        final Directory root = new Directory(1, 0);
        Directory current = root;
        String previous;
        int clock, nextInode = 2;

        Shell() { root.parent = root; }
        String absolute(Node node) {
            List<String> parts = new ArrayList<>();
            while (node != root) { parts.add(node.name); node = node.parent; }
            Collections.reverse(parts);
            return "/" + String.join("/", parts);
        }
        boolean descendant(Node node, Node ancestor) {
            while (true) {
                if (node == ancestor) return true;
                if (node == root) return false;
                node = node.parent;
            }
        }
        void add(Directory parent, String name, Node node) {
            parent.entries.put(name, node);
            parent.modified = clock;
            node.parent = parent;
            node.name = name;
        }
        Directory makeDirectory(Directory parent, String name) {
            Directory node = new Directory(nextInode++, clock);
            add(parent, name, node);
            return node;
        }
        FileNode makeFile(Directory parent, String name, List<String> lines) {
            FileNode node = new FileNode(nextInode++, clock, lines);
            add(parent, name, node);
            return node;
        }
        void detach(Node node) {
            node.parent.entries.remove(node.name);
            node.parent.modified = clock;
        }
        void write(FileNode file, List<String> lines, boolean append) {
            if (append) file.lines.addAll(lines);
            else file.lines = new ArrayList<>(lines);
            file.modified = clock;
        }

        final class Resolver {
            final boolean parents;
            int expansions;
            Resolver(boolean parents) { this.parents = parents; }
            Resolution walk(String path, Directory base, boolean follow, boolean original) {
                Node node = path.startsWith("/") ? root : base;
                String[] parts = path.split("/");
                for (int i = 0; i < parts.length; i++) {
                    String part = parts[i];
                    if (part.isEmpty()) continue;
                    if (!(node instanceof Directory directory)) return Resolution.failed(Failure.NOT_DIRECTORY);
                    if (part.equals(".")) continue;
                    if (part.equals("..")) { node = node.parent; continue; }
                    boolean last = i + 1 == parts.length;
                    Node child = directory.entries.get(part);
                    if (child == null) {
                        if (original && last) return new Resolution(null, Failure.MISSING, directory, part);
                        if (original && parents) child = makeDirectory(directory, part);
                        else return Resolution.failed(Failure.MISSING);
                    }
                    if (child instanceof Link link && (!last || follow)) {
                        if (++expansions > 8) return Resolution.failed(Failure.LOOP);
                        Resolution result = walk(link.target, directory, true, false);
                        if (result.node == null) return result;
                        child = result.node;
                    }
                    node = child;
                }
                return Resolution.found(node);
            }
        }
        Resolution resolve(String path, boolean follow, boolean parents) {
            return new Resolver(parents).walk(path, current, follow, true);
        }
        Resolution resolve(String path, boolean follow) { return resolve(path, follow, false); }
        Resolution resolve(String path) { return resolve(path, true); }

        void cloneNode(Node source, Directory parent, String name) {
            switch (source) {
                case Directory directory -> {
                    Directory copy = makeDirectory(parent, name);
                    for (Node child : directory.entries.values()) cloneNode(child, copy, child.name);
                }
                case FileNode file -> makeFile(parent, name, file.lines);
                case Link link -> add(parent, name, new Link(nextInode++, clock, link.target));
            }
        }
        void move(String sourcePath, String destination, Output out) {
            if (invalidSource(sourcePath)) {
                out.error("mv: cannot move '%s' to '%s': Invalid argument", sourcePath, destination);
                return;
            }
            Resolution result = resolve(sourcePath, false);
            Node source = result.node;
            if (source == null) { out.error("mv: cannot stat '%s': %s", sourcePath, result.reason()); return; }
            Directory parent;
            String name, target;
            if (resolve(destination).node instanceof Directory directory) {
                parent = directory;
                name = lastComponent(sourcePath);
                target = joinPath(destination, name);
            } else {
                result = resolve(destination, false);
                if (result.absent()) { parent = result.creationParent; name = result.creationName; }
                else if (result.node != null) { parent = result.node.parent; name = result.node.name; }
                else { out.error("mv: cannot move '%s' to '%s': %s", sourcePath, destination, result.reason()); return; }
                target = destination;
            }
            Node existing = parent.entries.get(name);
            if (source instanceof Directory && descendant(parent, source)) {
                out.error("mv: cannot move '%s' to a subdirectory of itself, '%s'", sourcePath, target);
            } else if (existing == source) {
                out.error("mv: '%s' and '%s' are the same file", sourcePath, target);
            } else if (existing != null && source instanceof Directory && !(existing instanceof Directory)) {
                out.error("mv: cannot overwrite non-directory '%s' with directory '%s'", target, sourcePath);
            } else if (!(source instanceof Directory) && existing instanceof Directory) {
                out.error("mv: cannot overwrite directory '%s' with non-directory '%s'", target, sourcePath);
            } else if (existing instanceof Directory directory && !directory.entries.isEmpty()) {
                out.error("mv: cannot move '%s' to '%s': Directory not empty", sourcePath, target);
            } else if (existing == current) {
                out.error("mv: cannot move '%s' to '%s': Device or resource busy", sourcePath, target);
            } else {
                if (existing != null) detach(existing);
                detach(source);
                add(parent, name, source);
            }
        }
        void copy(String sourcePath, String destination, boolean recursive, Output out) {
            if (invalidSource(sourcePath)) {
                out.error("cp: cannot copy '%s' to '%s': Invalid argument", sourcePath, destination);
                return;
            }
            Resolution result = resolve(sourcePath);
            Node source = result.node;
            if (source == null) { out.error("cp: cannot stat '%s': %s", sourcePath, result.reason()); return; }
            if (source instanceof Directory && !recursive) {
                out.error("cp: -r not specified; omitting directory '%s'", sourcePath);
                return;
            }
            result = resolve(destination);
            if (result.node == null && !result.absent()) {
                out.error("cp: cannot copy '%s' to '%s': %s", sourcePath, destination, result.reason());
                return;
            }
            String target = result.node instanceof Directory ? joinPath(destination, lastComponent(sourcePath)) : destination;
            result = resolve(target, !(source instanceof Directory));
            if (source instanceof Directory) {
                if (result.node != null) out.error("cp: cannot copy '%s' to '%s': File exists", sourcePath, target);
                else if (descendant(result.creationParent, source)) {
                    out.error("cp: cannot copy a directory, '%s', into itself, '%s'", sourcePath, target);
                } else cloneNode(source, result.creationParent, result.creationName);
            } else if (result.absent()) {
                makeFile(result.creationParent, result.creationName, ((FileNode) source).lines);
            } else if (result.node == source) {
                out.error("cp: '%s' and '%s' are the same file", sourcePath, target);
            } else if (result.node instanceof Directory) {
                out.error("cp: cannot overwrite directory '%s' with non-directory '%s'", target, sourcePath);
            } else if (result.node instanceof FileNode file) {
                write(file, ((FileNode) source).lines, false);
            } else out.error("cp: cannot copy '%s' to '%s': %s", sourcePath, target, result.reason());
        }

        void listing(Options options, Output out) {
            List<String> paths = options.paths.isEmpty() ? List.of(".") : options.paths;
            for (String path : paths) {
                Resolution result = resolve(path, !options.has('l'));
                if (result.node == null) { out.error("ls: cannot access '%s': %s", path, result.reason()); continue; }
                List<Listed> entries = new ArrayList<>();
                if (result.node instanceof Directory directory) {
                    if (paths.size() > 1) out.emit(path + ":");
                    if (options.has('a')) {
                        entries.add(new Listed(".", directory));
                        entries.add(new Listed("..", directory.parent));
                    }
                    for (Node child : directory.entries.values()) {
                        if (options.has('a') || !child.name.startsWith(".")) entries.add(new Listed(child.name, child));
                    }
                } else entries.add(new Listed(path, result.node));
                if (options.has('t')) entries.sort(Comparator.comparingInt((Listed entry) -> entry.node.modified).reversed());
                if (options.has('r')) Collections.reverse(entries);
                int[] widths = {1, 1, 1};
                for (Listed entry : entries) {
                    long[] numbers = {entry.node.links(), entry.node.size(), entry.node.modified};
                    for (int i = 0; i < 3; i++) widths[i] = Math.max(widths[i], Long.toString(numbers[i]).length());
                }
                for (Listed entry : entries) {
                    if (!options.has('l')) { out.emit(entry.name); continue; }
                    Node node = entry.node;
                    String format = "%c %" + widths[0] + "d %" + widths[1] + "d %" + widths[2] + "d %s%s";
                    out.print(format, node instanceof FileNode ? '-' : node.tag(), node.links(), node.size(), node.modified,
                        entry.name, node instanceof Link link ? " -> " + link.target : "");
                }
            }
        }
        void walk(Node node, String path, int depth, int limit, Visitor visit) {
            visit.accept(node, path, depth);
            if (node instanceof Directory directory && depth < limit) {
                for (Node child : directory.entries.values()) walk(child, joinPath(path, child.name), depth + 1, limit, visit);
            }
        }
        void find(List<String> args, Output out) {
            boolean explicit = !args.isEmpty() && !args.getFirst().startsWith("-");
            String path = explicit ? args.getFirst() : ".";
            Map<String, String> tests = new HashMap<>();
            for (int i = explicit ? 1 : 0; i < args.size(); i += 2) tests.put(args.get(i), args.get(i + 1));
            Resolution result = resolve(path);
            if (result.node == null) { out.error("find: '%s': %s", path, result.reason()); return; }
            int limit = Integer.parseInt(tests.getOrDefault("-maxdepth", "1000"));
            walk(result.node, path, 0, limit, (node, display, depth) -> {
                String name = depth == 0 ? (path.equals("/") ? "/" : lastComponent(path)) : node.name;
                if ((!tests.containsKey("-name") || globMatch(tests.get("-name"), name)) &&
                    (!tests.containsKey("-type") || tests.get("-type").charAt(0) == node.tag())) out.emit(display);
            });
        }
        long usage(Node node, String path, boolean show, Options options, Output out) {
            long total;
            if (node instanceof Directory directory) {
                total = 0;
                for (Node child : directory.entries.values()) {
                    total += usage(child, joinPath(path, child.name),
                        show && !options.has('s') && (child instanceof Directory || options.has('a')), options, out);
                }
            } else total = node.size();
            if (show) out.print("%d %s", total, path);
            return total;
        }
        void diskUsage(Options options, Output out) {
            for (String path : options.paths.isEmpty() ? List.of(".") : options.paths) {
                Resolution result = resolve(path);
                if (result.node == null) out.error("du: cannot access '%s': %s", path, result.reason());
                else usage(result.node, path, true, options, out);
            }
        }
        void drawTree(Directory directory, String prefix, boolean all, int[] counts, Output out) {
            List<Node> children = directory.entries.values().stream().filter(node -> all || !node.name.startsWith(".")).toList();
            for (int i = 0; i < children.size(); i++) {
                Node child = children.get(i);
                boolean last = i + 1 == children.size();
                out.emit(prefix + (last ? "`-- " : "|-- ") + child.name + (child instanceof Link link ? " -> " + link.target : ""));
                if (child instanceof Directory nested) {
                    counts[0]++;
                    drawTree(nested, prefix + (last ? "    " : "|   "), all, counts, out);
                } else counts[1]++;
            }
        }
        void tree(Options options, Output out) {
            String path = options.paths.isEmpty() ? "." : options.paths.getFirst();
            Resolution result = resolve(path);
            if (result.node == null) { out.error("tree: %s: %s", path, result.reason()); return; }
            if (!(result.node instanceof Directory directory)) { out.error("tree: %s: Not a directory", path); return; }
            out.emit(path);
            int[] counts = {0, 0};
            drawTree(directory, "", options.has('a'), counts, out);
            out.print("%d %s, %d %s", counts[0], counts[0] == 1 ? "directory" : "directories",
                counts[1], counts[1] == 1 ? "file" : "files");
        }
        void readInputs(String command, List<String> paths, List<String> input, Output out, Consumer<Input> consume) {
            if (paths.isEmpty()) { consume.accept(new Input(input, null)); return; }
            for (String path : paths) {
                Resolution result = resolve(path);
                if (result.node == null) out.error("%s: %s: %s", command, path, result.reason());
                else if (result.node instanceof FileNode file) consume.accept(new Input(file.lines, path));
                else out.error("%s: %s: Is a directory", command, path);
            }
        }
        void textCommand(String command, List<String> args, List<String> input, Output out) {
            Options options = options(args);
            switch (command) {
                case "grep" -> {
                    String pattern = options.has('i') ? options.paths.getFirst().toLowerCase(Locale.ROOT) : options.paths.getFirst();
                    List<String> paths = options.paths.subList(1, options.paths.size());
                    boolean named = options.has('r') || paths.size() > 1;
                    Consumer<Input> consume = part -> {
                        String prefix = named ? part.name + ":" : "";
                        long selected = 0;
                        for (int i = 0; i < part.lines.size(); i++) {
                            String line = part.lines.get(i);
                            String comparison = options.has('i') ? line.toLowerCase(Locale.ROOT) : line;
                            if (comparison.contains(pattern) == options.has('v')) continue;
                            selected++;
                            if (!options.has('c')) out.emit(prefix + (options.has('n') ? (i + 1) + ":" : "") + line);
                        }
                        if (options.has('c')) out.emit(prefix + selected);
                    };
                    if (!options.has('r')) readInputs(command, paths, input, out, consume);
                    else for (String path : paths.isEmpty() ? List.of(".") : paths) {
                        Resolution result = resolve(path);
                        if (result.node == null) out.error("grep: %s: %s", path, result.reason());
                        else walk(result.node, path, 0, 1000, (node, display, depth) -> {
                            if (node instanceof FileNode file) consume.accept(new Input(file.lines, display));
                        });
                    }
                }
                case "sort" -> {
                    List<String> lines = new ArrayList<>();
                    readInputs(command, options.paths, input, out, part -> lines.addAll(part.lines));
                    lines.sort((a, b) -> {
                        int comparison = options.has('n') ? Long.compare(numericPrefix(a), numericPrefix(b)) : 0;
                        return comparison != 0 ? comparison : a.compareTo(b);
                    });
                    if (options.has('r')) Collections.reverse(lines);
                    lines.forEach(out::emit);
                }
                case "wc" -> {
                    boolean all = !options.has('l') && !options.has('w') && !options.has('c');
                    long[] totals = new long[3];
                    java.util.function.BiConsumer<long[], String> report = (counts, name) -> {
                        StringJoiner numbers = new StringJoiner(" ");
                        for (int i = 0; i < 3; i++) if (all || options.has("lwc".charAt(i))) numbers.add(Long.toString(counts[i]));
                        out.emit(numbers + (name == null ? "" : " " + name));
                    };
                    readInputs(command, options.paths, input, out, part -> {
                        long[] counts = {part.lines.size(), 0, 0};
                        for (String line : part.lines) {
                            counts[2] += (long) line.length() + 1;
                            boolean inside = false;
                            for (int i = 0; i < line.length(); i++) {
                                if (line.charAt(i) != ' ' && !inside) counts[1]++;
                                inside = line.charAt(i) != ' ';
                            }
                        }
                        for (int i = 0; i < 3; i++) totals[i] += counts[i];
                        report.accept(counts, part.name);
                    });
                    if (options.paths.size() > 1) report.accept(totals, "total");
                }
                case "head", "tail" -> {
                    boolean explicit = !args.isEmpty() && args.getFirst().equals("-n");
                    String raw = explicit ? args.get(1) : "10";
                    boolean special = raw.startsWith("-") || raw.startsWith("+");
                    int count = Integer.parseInt(special ? raw.substring(1) : raw);
                    readInputs(command, args.subList(explicit ? 2 : 0, args.size()), input, out, part -> {
                        int first = 0, end = part.lines.size();
                        if (command.equals("head")) end = special ? Math.max(0, end - count) : Math.min(end, count);
                        else first = special ? Math.min(end, Math.max(0, count - 1)) : Math.max(0, end - count);
                        for (int i = first; i < end; i++) out.emit(part.lines.get(i));
                    });
                }
                default -> readInputs(command, options.paths, input, out, part -> {
                    if (command.equals("cat")) { part.lines.forEach(out::emit); return; }
                    for (int first = 0; first < part.lines.size();) {
                        int end = first + 1;
                        while (end < part.lines.size() && part.lines.get(first).equals(part.lines.get(end))) end++;
                        out.emit((options.has('c') ? (end - first) + " " : "") + part.lines.get(first));
                        first = end;
                    }
                });
            }
        }
        void execute(String text, List<String> input, Output out) {
            List<String> words = Arrays.asList(text.split(" "));
            String command = words.getFirst();
            List<String> args = words.subList(1, words.size());
            Options options = options(args);
            switch (command) {
                case "pwd" -> out.emit(absolute(current));
                case "echo" -> out.emit(text.substring(5));
                case "cd" -> {
                    String path = args.isEmpty() ? "/" : args.getFirst();
                    boolean back = path.equals("-");
                    if (back) {
                        if (previous == null) { out.error("cd: OLDPWD not set"); return; }
                        path = previous;
                    }
                    Resolution result = resolve(path);
                    if (result.node == null) out.error("cd: %s: %s", path, result.reason());
                    else if (!(result.node instanceof Directory directory)) out.error("cd: %s: Not a directory", path);
                    else {
                        previous = absolute(current);
                        current = directory;
                        if (back) out.emit(absolute(current));
                    }
                }
                case "mkdir" -> {
                    for (String path : options.paths) {
                        Resolution result = resolve(path, false, options.has('p'));
                        if (result.absent()) makeDirectory(result.creationParent, result.creationName);
                        else if (result.node == null) out.error("mkdir: cannot create directory '%s': %s", path, result.reason());
                        else if (!options.has('p') || !(resolve(path).node instanceof Directory)) {
                            out.error("mkdir: cannot create directory '%s': File exists", path);
                        }
                    }
                }
                case "touch" -> {
                    for (String path : args) {
                        Resolution result = resolve(path);
                        if (result.absent()) makeFile(result.creationParent, result.creationName, List.of());
                        else if (result.node != null) result.node.modified = clock;
                        else out.error("touch: cannot touch '%s': %s", path, result.reason());
                    }
                }
                case "ls" -> listing(options, out);
                case "stat" -> {
                    for (String path : args) {
                        Resolution result = resolve(path, false);
                        Node node = result.node;
                        if (node == null) { out.error("stat: cannot stat '%s': %s", path, result.reason()); continue; }
                        String kind = switch (node) {
                            case Directory directory -> "directory";
                            case Link link -> "symbolic link";
                            case FileNode file -> file.lines.isEmpty() ? "regular empty file" : "regular file";
                        };
                        out.print("%s: %s, size %d, inode %d, links %d, modified %d", path, kind, node.size(), node.inode, node.links(), node.modified);
                    }
                }
                case "rm", "rmdir" -> {
                    boolean directoryOnly = command.equals("rmdir");
                    for (String path : options.paths) {
                        String last = lastComponent(path);
                        boolean dot = last.equals(".") || last.equals("..");
                        if (dot && !directoryOnly) {
                            out.error("rm: refusing to remove '.' or '..' directory: skipping '%s'", path);
                            continue;
                        }
                        String problem = "";
                        if (dot) problem = "Invalid argument";
                        else {
                            Resolution result = resolve(path, false);
                            Node node = result.node;
                            if (node == null) {
                                if (!directoryOnly && options.has('f') && result.failure == Failure.MISSING) continue;
                                problem = result.reason();
                            } else if (directoryOnly && !(node instanceof Directory)) problem = "Not a directory";
                            else if (!directoryOnly && node instanceof Directory && !options.has('r')) problem = "Is a directory";
                            else if (descendant(current, node)) problem = "Device or resource busy";
                            else if (directoryOnly && !((Directory) node).entries.isEmpty()) problem = "Directory not empty";
                            else detach(node);
                        }
                        if (!problem.isEmpty()) out.error(directoryOnly ? "rmdir: failed to remove '%s': %s" : "rm: cannot remove '%s': %s", path, problem);
                    }
                }
                case "mv", "cp" -> {
                    String destination = options.paths.getLast();
                    if (options.paths.size() > 2 && !(resolve(destination).node instanceof Directory)) {
                        out.error("%s: target '%s' is not a directory", command, destination);
                        return;
                    }
                    for (String source : options.paths.subList(0, options.paths.size() - 1)) {
                        if (command.equals("mv")) move(source, destination, out);
                        else copy(source, destination, options.has('r'), out);
                    }
                }
                case "ln" -> {
                    String path = args.get(2);
                    Resolution result = resolve(path, false);
                    if (result.absent()) add(result.creationParent, result.creationName, new Link(nextInode++, clock, args.get(1)));
                    else out.error("ln: failed to create symbolic link '%s': %s", path, result.node == null ? result.reason() : "File exists");
                }
                case "readlink", "realpath" -> {
                    String path = args.getFirst();
                    Resolution result = resolve(path, command.equals("realpath"));
                    if (result.node == null) out.error("%s: %s: %s", command, path, result.reason());
                    else if (command.equals("realpath")) out.emit(absolute(result.node));
                    else if (result.node instanceof Link link) out.emit(link.target);
                    else out.error("readlink: %s: Invalid argument", path);
                }
                case "find" -> find(args, out);
                case "du" -> diskUsage(options, out);
                case "tree" -> tree(options, out);
                case "cat", "wc", "head", "tail", "grep", "sort", "uniq" -> textCommand(command, args, input, out);
                default -> out.error("%s: command not found", command);
            }
        }
        void process(String line, PrintWriter terminal) {
            clock++;
            terminal.print(absolute(current) + "$ " + line + "\n");
            String pipeline = line;
            FileNode redirect = null;
            int marker = line.indexOf(" >");
            if (marker >= 0) {
                pipeline = line.substring(0, marker);
                boolean append = line.startsWith(" >> ", marker);
                String path = line.substring(marker + (append ? 4 : 3));
                Resolution result = resolve(path);
                if (result.absent()) redirect = makeFile(result.creationParent, result.creationName, List.of());
                else if (result.node instanceof FileNode file) {
                    redirect = file;
                    if (!append) write(file, List.of(), false);
                } else {
                    terminal.print("sh: " + path + ": " + (result.node == null ? result.reason() : "Is a directory") + "\n");
                    return;
                }
            }
            String[] commands = pipeline.split(" \\| ");
            List<String> input = List.of();
            for (int i = 0; i < commands.length; i++) {
                Output out = new Output(terminal, i + 1 == commands.length && redirect == null);
                execute(commands[i], input, out);
                input = out.lines;
            }
            if (redirect != null && !input.isEmpty()) write(redirect, input, true);
        }
    }

    static boolean globMatch(String pattern, String text) {
        boolean[] previous = new boolean[text.length() + 1];
        previous[0] = true;
        for (char character : pattern.toCharArray()) {
            boolean[] next = new boolean[previous.length];
            next[0] = character == '*' && previous[0];
            for (int i = 0; i < text.length(); i++) {
                next[i + 1] = character == '*' ? previous[i + 1] || next[i] :
                    previous[i] && (character == '?' || character == text.charAt(i));
            }
            previous = next;
        }
        return previous[text.length()];
    }
    static long numericPrefix(String text) {
        boolean negative = text.startsWith("-");
        int at = negative ? 1 : 0;
        long value = 0;
        while (at < text.length() && text.charAt(at) >= '0' && text.charAt(at) <= '9') value = value * 10 + text.charAt(at++) - '0';
        return negative ? -value : value;
    }
    public static void main(String[] args) throws IOException {
        Shell shell = new Shell();
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8)));
        for (String line; (line = input.readLine()) != null && !line.equals("exit");) shell.process(line, output);
        output.flush();
    }
}
