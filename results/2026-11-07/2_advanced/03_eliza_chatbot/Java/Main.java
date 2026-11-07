import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

final class Helpers {
    static List<String> words(String text) { return text.isBlank() ? new ArrayList<>() : new ArrayList<>(Arrays.asList(text.strip().split(" +"))); }
    static List<String> flatten(List<List<String>> clauses) { List<String> result = new ArrayList<>(); for (List<String> clause : clauses) result.addAll(clause); return result; }
    static List<String> grouped(List<String> values, int size) {
        List<String> result = new ArrayList<>(); for (int i = 0; i < values.size(); i += size) result.add(String.join(" ", values.subList(i, Math.min(values.size(), i + size)))); return result;
    }
    static void save(String name, List<String> lines) throws IOException {
        StringBuilder text = new StringBuilder(); for (String line : lines) text.append(line).append('\n'); Files.writeString(Path.of("output", name), text, StandardCharsets.US_ASCII);
    }
}
final class Session {
    String name = "";
    int turns, stored, recalled;
    final int[] sources = new int[5];
    List<List<String>> previous;
    final List<String> history = new ArrayList<>();
    List<String> lastTrace;
    boolean trace;
    final Map<String, Integer> topics = new LinkedHashMap<>(), words = new LinkedHashMap<>();
    final List<Integer> unrecognized = new ArrayList<>();
    State undo;
    Session() {}
    Session(Session source) {
        name = source.name; turns = source.turns; stored = source.stored; recalled = source.recalled; trace = source.trace; undo = source.undo;
        System.arraycopy(source.sources, 0, sources, 0, sources.length);
        if (source.previous != null) { previous = new ArrayList<>(); for (List<String> clause : source.previous) previous.add(new ArrayList<>(clause)); }
        history.addAll(source.history); lastTrace = source.lastTrace == null ? null : new ArrayList<>(source.lastTrace);
        topics.putAll(source.topics); words.putAll(source.words); unrecognized.addAll(source.unrecognized);
    }
}
final class State {
    final int[] positions, hits, itemUses, keywordUses, keywordReplies;
    final Map<String, Integer> lists = new LinkedHashMap<>();
    final Memory memory;
    Session session;
    State(Script script) {
        positions = new int[script.rules.size()]; hits = new int[script.rules.size()]; itemUses = new int[script.items.size()];
        keywordUses = new int[script.keywords.size()]; keywordReplies = new int[script.keywords.size()]; memory = new Memory(script.capacity); session = new Session();
        for (String name : List.of("DEFAULT", "QUESTION", "REPEAT")) lists.put(name, 0);
    }
    State(State source, boolean snapshot) {
        positions = source.positions.clone(); hits = source.hits.clone(); itemUses = source.itemUses.clone(); keywordUses = source.keywordUses.clone(); keywordReplies = source.keywordReplies.clone();
        lists.putAll(source.lists); memory = new Memory(source.memory); session = new Session(source.session); if (snapshot) session.undo = null;
    }
}
record Selection(int number, List<String> words) {}
record Found(int number, Rule rule, List<List<String>> bindings) {}
record Entry(String kind, int number, Rule rule) {}
record Decision(String reply, List<String> trace) {}
final class Chatbot {
    private static final List<String> SOURCES = List.of("keyword", "memory", "question", "default", "repeat");
    private static final Set<String> NO_ARGS = Set.of(":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo");
    private static final Set<String> TEXT_ARGS = Set.of(":prepare", ":reflect", ":say", ":explain");
    private static final Set<String> SINGLE = Set.of(":groups", ":find", ":script", ":cycles", ":coverage");
    private static final Set<String> KEY_ARGS = Set.of(":script", ":cycles", ":coverage", ":test");
    private final Script script;
    private State state;
    private final List<String> transcript = new ArrayList<>();
    private int totalTurns;
    private final int[] totals = new int[5];
    Chatbot(Script script) { this.script = script; state = new State(script); }
    private static List<List<String>> normalize(String text) {
        List<List<String>> clauses = new ArrayList<>();
        for (String part : text.toLowerCase(Locale.ROOT).split("[,.?!;]", -1)) {
            StringBuilder cleaned = new StringBuilder();
            for (int i = 0; i < part.length(); i++) { char c = part.charAt(i); cleaned.append(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '\'' ? c : ' '); }
            List<String> words = new ArrayList<>();
            for (String piece : Helpers.words(cleaned.toString())) {
                int start = 0, end = piece.length(); while (start < end && piece.charAt(start) == '\'') start++; while (end > start && piece.charAt(end - 1) == '\'') end--;
                if (start < end) words.add(piece.substring(start, end));
            }
            if (!words.isEmpty()) clauses.add(words);
        }
        return clauses;
    }
    private List<List<String>> prepared(String text) { List<List<String>> result = new ArrayList<>(); for (List<String> clause : normalize(text)) result.add(Responder.reflect(clause, script.pre)); return result; }
    private boolean quit(String text) { List<String> values = Helpers.flatten(normalize(text)); return values.size() == 1 && script.quit.contains(values.getFirst()); }
    private static void increment(Map<String, Integer> values, String word) { values.merge(word, 1, Integer::sum); }
    private String prefix() { return state.session.name + " " + state.session.turns; }
    private void resetCycles() { Arrays.fill(state.positions, 0); for (String name : List.of("DEFAULT", "QUESTION", "REPEAT")) state.lists.put(name, 0); }
    private String takeText(String name) { int position = state.lists.get(name); List<String> values = script.texts.get(name); state.lists.put(name, (position + 1) % values.size()); return values.get(position); }
    private Item takeItem(Rule rule) { int position = state.positions[rule.index]; Item item = rule.items.get(position); state.itemUses[item.index()]++; state.positions[rule.index] = (position + 1) % rule.items.size(); return item; }
    private Selection select(List<List<String>> clauses) {
        for (int i = 0; i < clauses.size(); i++) if (clauses.get(i).stream().anyMatch(script.keywordMap::containsKey)) return new Selection(i + 1, clauses.get(i)); return null;
    }
    private List<Keyword> keywordList(List<String> words) {
        Set<String> seen = new HashSet<>(); List<Keyword> result = new ArrayList<>();
        for (String word : words) if (script.keywordMap.containsKey(word) && seen.add(word)) result.add(script.keywordMap.get(word));
        result.sort(Comparator.comparingInt((Keyword k) -> k.rank).reversed()); return result;
    }
    private Found findRule(List<Rule> rules, List<String> words) {
        for (int i = 0; i < rules.size(); i++) { List<List<String>> bindings = Matcher.match(rules.get(i).pattern, words, script.groups); if (bindings != null) return new Found(i + 1, rules.get(i), bindings); } return null;
    }
    private static List<Entry> entries(Keyword key) {
        List<Entry> result = new ArrayList<>(); for (int i = 0; i < key.memories.size(); i++) result.add(new Entry("memory", i + 1, key.memories.get(i))); for (int i = 0; i < key.decomps.size(); i++) result.add(new Entry("decomp", i + 1, key.decomps.get(i))); return result;
    }
    private String keywordReply(List<List<String>> clauses, List<String> trace) {
        Selection selected = select(clauses);
        if (selected == null) { trace.add("CLAUSE none"); return null; }
        List<String> original = selected.words(); trace.add("CLAUSE " + selected.number() + " " + String.join(" ", original));
        List<Keyword> keys = keywordList(original); trace.add("KEYS " + String.join(" ", keys.stream().map(k -> k.word).toList()));
        Keyword first = keys.getFirst(); Found memory = findRule(first.memories, original);
        if (memory != null) {
            trace.add("MEMORY " + first.word + " " + memory.number()); state.hits[memory.rule().index]++;
            if (!memory.rule().items.isEmpty()) {
                Item item = takeItem(memory.rule()); String text = Responder.build(item.text(), memory.bindings(), script.post);
                if (state.memory.store(prefix(), first.word, text)) state.session.stored++;
            }
        }
        Set<String> entered = new HashSet<>();
        for (Keyword initial : keys) {
            if (entered.contains(initial.word)) continue;
            trace.add("ENTER " + initial.word); Keyword key = initial; List<String> current = original;
            while (true) {
                entered.add(key.word); state.keywordUses[key.index]++;
                Found found = findRule(key.decomps, current);
                if (found == null) { trace.add("NOMATCH " + key.word); break; }
                state.hits[found.rule().index]++;
                if (found.rule().items.isEmpty()) { trace.add("DECOMP " + key.word + " " + found.number() + " 0"); break; }
                int number = state.positions[found.rule().index] + 1; Item item = takeItem(found.rule()); trace.add("DECOMP " + key.word + " " + found.number() + " " + number);
                if (item.kind().equals("REASM")) { state.keywordReplies[key.index]++; increment(state.session.topics, key.word); return Responder.build(item.text(), found.bindings(), script.post); }
                if (item.kind().equals("NEWKEY")) break;
                String target = item.arguments().getFirst(); Keyword next = script.keywordMap.get(target);
                if (next == null || entered.contains(target)) { trace.add("BLOCKED " + target); break; }
                if (item.kind().equals("RESTATE")) { current = Responder.restate(item.arguments().subList(1, item.arguments().size()), found.bindings()); trace.add("RESTATE " + target + (current.isEmpty() ? "" : " " + String.join(" ", current))); }
                else trace.add("GOTO " + target);
                key = next;
            }
        }
        return null;
    }
    private Decision decide(String text) {
        List<List<String>> clauses = normalize(text); List<String> trace = new ArrayList<>(); String reply; int source;
        if (!script.texts.get("REPEAT").isEmpty() && !clauses.isEmpty() && clauses.equals(state.session.previous)) { trace.add("REPEAT"); reply = takeText("REPEAT"); source = 4; }
        else {
            List<List<String>> pre = new ArrayList<>(); for (List<String> clause : clauses) pre.add(Responder.reflect(clause, script.pre)); reply = keywordReply(pre, trace);
            if (reply != null) source = 0;
            else if (!state.memory.texts.isEmpty()) { reply = state.memory.recall(prefix()); state.session.recalled++; source = 1; }
            else if (text.endsWith("?") && !script.texts.get("QUESTION").isEmpty()) { reply = takeText("QUESTION"); source = 2; }
            else { reply = takeText("DEFAULT"); source = 3; }
        }
        trace.add("REPLY " + SOURCES.get(source)); state.session.previous = clauses; state.session.sources[source]++;
        if (source == 2 || source == 3) state.session.unrecognized.add(state.session.turns);
        return new Decision(reply, trace);
    }
    private static String sourceLine(int turns, int[] counts) {
        StringBuilder line = new StringBuilder("turns=" + turns); for (int i = 0; i < counts.length; i++) line.append(' ').append(SOURCES.get(i)).append('=').append(counts[i]); return line.toString();
    }
    private static String ranked(Map<String, Integer> counts) {
        List<String> values = counts.entrySet().stream().sorted(Map.Entry.<String, Integer>comparingByValue().reversed().thenComparing(Map.Entry.comparingByKey())).limit(5).map(p -> p.getKey() + " " + p.getValue()).toList(); return values.isEmpty() ? "none" : String.join(", ", values);
    }
    private List<String> command(String line) {
        int space = line.indexOf(' '); String name = space < 0 ? line : line.substring(0, space), text = space < 0 ? "" : line.substring(space + 1); List<String> args = Helpers.words(text);
        if (!NO_ARGS.contains(name) && !TEXT_ARGS.contains(name) && !SINGLE.contains(name) && !name.equals(":trace") && !name.equals(":test")) return List.of("unknown command " + name);
        if (NO_ARGS.contains(name) && !args.isEmpty() || TEXT_ARGS.contains(name) && text.isEmpty() || SINGLE.contains(name) && args.size() != 1 || name.equals(":trace") && (args.size() != 1 || !Set.of("on", "off").contains(args.getFirst())) || name.equals(":test") && args.size() < 2) return List.of("bad arguments");
        if (KEY_ARGS.contains(name) && !script.keywordMap.containsKey(args.getFirst())) return List.of("unknown keyword " + args.getFirst());
        List<String> result = new ArrayList<>();
        switch (name) {
            case ":prepare" -> {
                List<List<String>> clauses = prepared(text); for (int i = 0; i < clauses.size(); i++) result.add("clause " + (i + 1) + ": " + String.join(" ", clauses.get(i))); if (clauses.isEmpty()) result.add("no words");
                Selection selected = select(clauses);
                if (selected == null) result.add("selected none");
                else { result.add("selected " + selected.number()); result.add("keys " + String.join(" ", keywordList(selected.words()).stream().map(k -> k.word + "/" + k.rank).toList())); }
            }
            case ":test", ":cycles", ":coverage" -> {
                List<String> values = name.equals(":test") ? Helpers.flatten(prepared(text.substring(text.indexOf(' ') + 1))) : List.of();
                for (Entry entry : entries(script.keywordMap.get(args.getFirst()))) {
                    Rule rule = entry.rule(); String value;
                    if (name.equals(":test")) {
                        List<List<String>> bindings = Matcher.match(rule.pattern, values, script.groups);
                        value = bindings == null ? "no match" : bindings.isEmpty() ? "match" : String.join(" ", bindings.stream().map(b -> "[" + String.join(" ", b) + "]").toList());
                    } else if (name.equals(":cycles")) value = rule.items.isEmpty() ? "empty" : "next " + (state.positions[rule.index] + 1) + "/" + rule.items.size();
                    else value = "hits " + state.hits[rule.index] + " entries " + (rule.items.isEmpty() ? "-" : String.join(" ", rule.items.stream().map(i -> Integer.toString(state.itemUses[i.index()])).toList()));
                    result.add(entry.kind() + " " + entry.number() + ": " + value);
                }
                if (result.isEmpty()) result.add("no rules");
            }
            case ":reflect" -> { for (List<String> clause : prepared(text)) result.add(String.join(" ", Responder.reflect(clause, script.post))); if (result.isEmpty()) result.add("no words"); }
            case ":keys" -> result.addAll(Helpers.grouped(script.keywords.stream().sorted(Comparator.comparingInt((Keyword k) -> k.rank).reversed().thenComparing(k -> k.word)).map(k -> k.word + "/" + k.rank).toList(), 8));
            case ":groups" -> { List<String> names = script.groupList.stream().filter(g -> g.members().contains(args.getFirst())).map(Group::name).sorted().toList(); result.add(names.isEmpty() ? "none" : String.join(" ", names)); }
            case ":find" -> {
                String word = args.getFirst(); Keyword key = script.keywordMap.get(word); if (key != null) result.add("keyword rank " + key.rank);
                for (int i = 0; i < 2; i++) for (Substitution s : i == 0 ? script.pres : script.posts) if (s.source().equals(word) || s.replacement().contains(word)) result.add((i == 0 ? "pre" : "post") + " " + s.line() + ": " + s.source() + " -> " + String.join(" ", s.replacement()));
                for (Group g : script.groupList) if (g.members().contains(word)) result.add("group " + g.name() + " line " + g.line());
                for (Keyword k : script.keywords) for (Entry e : entries(k)) if (e.rule().pattern.contains(word)) result.add("pattern " + k.word + " " + e.kind() + " " + e.number());
                if (script.stop.contains(word)) result.add("stop word"); if (script.quit.contains(word)) result.add("quit word"); if (result.isEmpty()) result.add("not found");
            }
            case ":script" -> {
                Keyword key = script.keywordMap.get(args.getFirst()); List<Integer> numbers = new ArrayList<>(); numbers.add(key.line);
                for (Entry e : entries(key)) { numbers.add(e.rule().line); for (Item item : e.rule().items) numbers.add(item.line()); }
                numbers.sort(Comparator.naturalOrder()); for (int n : numbers) result.add(n + " " + script.lines.get(n - 1));
            }
            case ":why" -> result.addAll(state.session.lastTrace == null ? List.of("no reply yet") : state.session.lastTrace);
            case ":trace" -> { state.session.trace = args.getFirst().equals("on"); result.add("trace " + args.getFirst()); }
            case ":history" -> { List<String> history = state.session.history; result.addAll(history.isEmpty() ? List.of("no turns yet") : history.subList(Math.max(0, history.size() - 5), history.size())); }
            case ":memory" -> { result.add("memory " + state.memory.texts.size() + "/" + state.memory.capacity); for (int i = 0; i < state.memory.texts.size(); i++) result.add((i + 1) + ": " + state.memory.texts.get(i)); }
            case ":forget" -> { result.add("forgot " + state.memory.texts.size()); state.memory.clear(prefix()); }
            case ":reset" -> { resetCycles(); result.add("cycles reset"); }
            case ":unused" -> {
                List<String> unused = script.items.stream().filter(i -> state.itemUses[i.index()] == 0).sorted(Comparator.comparingInt(Item::line)).map(i -> Integer.toString(i.line())).toList(); result.add("unused " + unused.size()); result.addAll(Helpers.grouped(unused, 12));
            }
            case ":stats" -> result.add(sourceLine(state.session.turns, state.session.sources));
            case ":say", ":explain" -> {
                if (quit(text)) return List.of("would quit"); State saved = new State(state, false); Decision decision = decide(text); state = saved; result.addAll(name.equals(":say") ? List.of(decision.reply()) : decision.trace());
            }
            case ":undo" -> { if (state.session.undo == null) result.add("nothing to undo"); else { state = new State(state.session.undo, false); result.add("undone turn " + (state.session.turns + 1)); } }
            default -> throw new IllegalStateException(name);
        }
        return result;
    }
    private void notes() {
        Session s = state.session;
        transcript.add("NOTES " + s.name); transcript.add("  " + sourceLine(s.turns, s.sources)); transcript.add("  topics: " + ranked(s.topics)); transcript.add("  words: " + ranked(s.words));
        transcript.add("  memory: stored=" + s.stored + " recalled=" + s.recalled + " pending=" + state.memory.texts.size());
        transcript.add("  unrecognized: " + (s.unrecognized.isEmpty() ? "none" : String.join(" ", s.unrecognized.stream().map(Object::toString).toList())));
        totalTurns += s.turns; for (int i = 0; i < totals.length; i++) totals[i] += s.sources[i];
    }
    void run(List<String> lines) {
        int sessions = 0;
        for (String line : lines) {
            if (line.startsWith("SESSION ")) {
                if (sessions > 0) { notes(); transcript.add(""); }
                String name = line.substring(8);
                if (sessions > 0) { if (!script.persist.contains("cycles")) resetCycles(); if (!script.persist.contains("memory")) state.memory.clear(name + " 0"); }
                state.session = new Session(); state.session.name = name; sessions++; transcript.add(line);
                List<String> initial = script.texts.get("INITIAL"); transcript.addAll(Responder.wrap(initial.get((sessions - 1) % initial.size())));
            } else if (line.charAt(0) == ':') { transcript.add(line); for (String value : command(line)) transcript.add("  " + value); }
            else {
                transcript.add("YOU: " + line);
                if (quit(line)) { List<String> finals = script.texts.get("FINAL"); transcript.addAll(Responder.wrap(finals.get((sessions - 1) % finals.size()))); continue; }
                state.session.undo = new State(state, true); state.session.turns++;
                for (String word : Helpers.flatten(normalize(line))) if (!script.stop.contains(word)) increment(state.session.words, word);
                state.session.history.add(state.session.turns + ": " + line);
                Decision decision = decide(line); transcript.addAll(Responder.wrap(decision.reply())); state.session.lastTrace = decision.trace();
                if (state.session.trace) for (String value : decision.trace()) transcript.add("  " + value);
            }
        }
        notes(); transcript.add(""); transcript.add("SUMMARY sessions=" + sessions + " " + sourceLine(totalTurns, totals));
    }
    void write() throws IOException {
        List<String> stats = new ArrayList<>(List.of("keyword,rank,uses,replies,decomposition_hits"));
        List<Keyword> ranked = script.keywords.stream().sorted(Comparator.comparingInt((Keyword k) -> state.keywordUses[k.index]).reversed().thenComparing(k -> k.word)).toList();
        for (Keyword key : ranked) {
            String hits = key.decomps.isEmpty() ? "-" : String.join("/", key.decomps.stream().map(r -> Integer.toString(state.hits[r.index])).toList());
            stats.add(key.word + "," + key.rank + "," + state.keywordUses[key.index] + "," + state.keywordReplies[key.index] + "," + hits);
        }
        Files.createDirectories(Path.of("output")); Helpers.save("lint.txt", Linter.lines(Linter.check(script))); Helpers.save("transcript.txt", transcript); Helpers.save("keyword_stats.csv", stats); Helpers.save("memory_log.txt", state.memory.log);
    }
}
public class Main {
    public static void main(String[] args) throws IOException { Chatbot bot = new Chatbot(ScriptLoader.load("input/script.txt")); bot.run(Files.readAllLines(Path.of("input/dialogue.txt"), StandardCharsets.US_ASCII)); bot.write(); }
}
