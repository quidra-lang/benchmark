import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

public class Main {
    static final List<String> SYMMETRIES = List.of("rot180", "mirror", "none");
    static final int[] POINTS = {1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10};
    record Settings(int nodeBudget, int minimum, String symmetry, int relaxStep, int weakScore) {}
    record Issue(int line, String reason) {}
    record Duplicate(int line, String word, int first) {}
    record Unknown(int line, String word) {}
    static boolean ignored(String line) { return line.isEmpty() || line.startsWith("#"); }
    static List<String> read(String name) throws Exception { return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII); }
    static Settings settings(List<String> lines) {
        Map<String, String> values = new HashMap<>();
        for (String line : lines) if (!ignored(line)) { int split = line.indexOf(' '); values.put(line.substring(0, split), line.substring(split + 1)); }
        return new Settings(Integer.parseInt(values.get("node_budget")), Integer.parseInt(values.get("min_score")), values.get("symmetry"), Integer.parseInt(values.get("relax_step")), Integer.parseInt(values.get("weak_score")));
    }
    static String joined(List<String> values, String separator) { return values.isEmpty() ? "-" : String.join(separator, values); }
    static List<String> paragraphs(List<List<String>> paragraphs) {
        List<String> lines = new ArrayList<>();
        for (List<String> paragraph : paragraphs) { if (!lines.isEmpty()) lines.add(""); lines.addAll(paragraph); }
        return lines;
    }
    static final class WordList {
        final int lineCount;
        final Map<String, Integer> scores = new LinkedHashMap<>(), firstLines = new HashMap<>();
        final List<Issue> invalid = new ArrayList<>();
        final List<Duplicate> duplicates = new ArrayList<>();
        final WordIndex index;
        WordList(List<String> lines) {
            lineCount = lines.size();
            for (int i = 0; i < lines.size(); i++) {
                String text = lines.get(i), error = WordIndex.wordError(text);
                if (error != null) { invalid.add(new Issue(i + 1, error)); continue; }
                int split = text.indexOf(' '); String word = text.substring(0, split);
                if (scores.containsKey(word)) duplicates.add(new Duplicate(i + 1, word, firstLines.get(word)));
                else { scores.put(word, Integer.parseInt(text.substring(split + 1))); firstLines.put(word, i + 1); }
            }
            index = new WordIndex(scores);
        }
        List<String> report() {
            List<String> lines = new ArrayList<>(List.of("WORDLIST lines=" + lineCount + " valid=" + scores.size() + " invalid=" + invalid.size() + " duplicates=" + duplicates.size()));
            for (Issue issue : invalid) lines.add("invalid " + issue.line() + " " + issue.reason());
            for (Duplicate duplicate : duplicates) lines.add("duplicate " + duplicate.line() + " " + duplicate.word() + " first=" + duplicate.first());
            for (var entry : index.byLength.entrySet()) {
                List<String> words = entry.getValue(); int total = words.stream().mapToInt(scores::get).sum(); String best = words.getFirst();
                lines.add("length " + entry.getKey() + " words=" + words.size() + " average=" + Render.decimal(total, words.size(), 2) + " best=" + best + ":" + scores.get(best));
            }
            int[] bands = new int[5]; for (int score : scores.values()) bands[(score - 1) / 20]++;
            lines.add("bands 1-20=" + bands[0] + " 21-40=" + bands[1] + " 41-60=" + bands[2] + " 61-80=" + bands[3] + " 81-100=" + bands[4]);
            lines.add("top " + String.join(" ", index.ranked.stream().limit(5).map(word -> word + ":" + scores.get(word)).toList()));
            int[] frequency = new int[26]; for (String word : scores.keySet()) for (int i = 0; i < 26; i++) if (word.indexOf('A' + i) >= 0) frequency[i]++;
            List<Integer> letters = new ArrayList<>(); for (int i = 0; i < 26; i++) letters.add(i);
            letters.sort(Comparator.<Integer>comparingInt(letter -> frequency[letter]).thenComparingInt(letter -> letter));
            lines.add("rare_letters " + String.join(" ", letters.stream().limit(5).map(letter -> "" + (char) ('A' + letter) + ":" + frequency[letter]).toList())); return lines;
        }
    }
    static final class Clue {
        final String word, text;
        final int number;
        int uses;
        Clue(String word, int number, String text) { this.word = word; this.number = number; this.text = text; }
    }
    static final class ClueBook {
        int entries, added;
        final List<Issue> invalid = new ArrayList<>();
        final List<Unknown> unknown = new ArrayList<>();
        final Map<String, List<Clue>> clues = new TreeMap<>();
        ClueBook(List<String> lines, Map<String, Integer> scores) {
            for (int i = 0; i < lines.size(); i++) {
                String text = lines.get(i); if (ignored(text)) continue;
                entries++; String error = WordIndex.clueError(text);
                if (error != null) { invalid.add(new Issue(i + 1, error)); continue; }
                int split = text.indexOf('|'); String word = text.substring(0, split);
                if (!scores.containsKey(word)) { unknown.add(new Unknown(i + 1, word)); continue; }
                List<Clue> list = clues.computeIfAbsent(word, ignored -> new ArrayList<>()); list.add(new Clue(word, list.size() + 1, text.substring(split + 1))); added++;
            }
        }
        String choose(String word) {
            List<Clue> list = clues.get(word); if (list == null) return null;
            Clue chosen = list.getFirst(); for (Clue clue : list) if (clue.uses < chosen.uses) chosen = clue;
            chosen.uses++; return chosen.text;
        }
        List<String> report() {
            List<String> lines = new ArrayList<>(List.of("CLUES entries=" + entries + " valid=" + added + " invalid=" + invalid.size() + " unknown=" + unknown.size() + " words=" + clues.size()));
            for (Issue issue : invalid) lines.add("clue_invalid " + issue.line() + " " + issue.reason());
            for (Unknown issue : unknown) lines.add("clue_unknown " + issue.line() + " " + issue.word());
            List<Clue> all = clues.values().stream().flatMap(List::stream).toList(); long used = all.stream().filter(clue -> clue.uses > 0).count(), repeated = all.stream().filter(clue -> clue.uses >= 2).count();
            lines.add("CLUE_USE used=" + used + " unused=" + (all.size() - used) + " repeated=" + repeated);
            for (Clue clue : all) if (clue.uses >= 2) lines.add("repeated " + clue.word + " clue=" + clue.number + " uses=" + clue.uses); return lines;
        }
    }
    static final class Block {
        final String name;
        final List<String> options = new ArrayList<>(), rows = new ArrayList<>();
        Block(String name) { this.name = name; }
    }
    static List<Block> blocks(List<String> lines) {
        List<Block> blocks = new ArrayList<>(); Block current = null;
        for (String line : lines) {
            if (current == null) { if (line.startsWith("TEMPLATE ")) current = new Block(line.substring(9)); }
            else if (line.equals("END")) { blocks.add(current); current = null; }
            else if (line.indexOf(' ') >= 0) current.options.add(line);
            else current.rows.add(line);
        }
        return blocks;
    }
    static boolean validName(String name) { return !name.isEmpty() && name.length() <= 20 && name.chars().allMatch(c -> c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_'); }
    static boolean validRow(String row, int width) { return row.length() >= 3 && row.length() <= 15 && row.length() == width && row.chars().allMatch(c -> c == '#' || c == '.' || c >= 'A' && c <= 'Z'); }
    static final class Template {
        final String name;
        final List<String> options, rows;
        int budget, minimum;
        String symmetry, error;
        final List<String> themes = new ArrayList<>();
        Grid grid;
        Layout layout;
        GridState initial, state;
        final Set<Integer> themeSlots = new HashSet<>();
        final List<Attempt> attempts = new ArrayList<>();
        Attempt finalAttempt;
        String[] chosen;
        Template(Block block, Settings settings) { name = block.name; options = block.options; rows = block.rows; budget = settings.nodeBudget(); minimum = settings.minimum(); symmetry = settings.symmetry(); }
        void process(Set<String> names, WordIndex index, ClueBook clues, int relax) {
            error = check(names, index); if (error != null) return;
            int score = minimum;
            while (true) {
                Attempt attempt = new Attempt(layout, index, initial, score, budget); attempt.run(); attempts.add(attempt); finalAttempt = attempt;
                if (attempt.outcome.equals("filled") || relax < 1 || score <= 1) break;
                score = Math.max(score - relax, 1);
            }
            state = finalAttempt.finalState(); chosen = new String[layout.slots.size()];
            for (boolean across : new boolean[] {true, false}) for (Slot slot : layout.slots) if (slot.across == across && state.words[slot.index] != null) chosen[slot.index] = clues.choose(state.words[slot.index]);
        }
        int readOptions() {
            Set<String> seen = new HashSet<>();
            for (int i = 0; i < options.size(); i++) {
                String text = options.get(i); int split = text.indexOf(' '); String key = text.substring(0, split), value = text.substring(split + 1);
                if (key.equals("theme")) { if (!WordIndex.validWord(value) || themes.contains(value)) return i + 1; themes.add(value); }
                else if (seen.contains(key) || !applyOption(key, value)) return i + 1;
                seen.add(key);
            }
            return -1;
        }
        boolean applyOption(String key, String value) {
            if (key.equals("node_budget") && WordIndex.validInteger(value, 1, 100000)) budget = Integer.parseInt(value);
            else if (key.equals("min_score") && WordIndex.validInteger(value, 1, 100)) minimum = Integer.parseInt(value);
            else if (key.equals("symmetry") && SYMMETRIES.contains(value)) symmetry = value;
            else return false;
            return true;
        }
        String check(Set<String> names, WordIndex index) {
            if (!validName(name)) return "bad name";
            if (names.contains(name)) return "duplicate name";
            int bad = readOptions(); if (bad >= 0) return "bad option " + bad;
            if (rows.size() < 3 || rows.size() > 15) return "bad height";
            for (int i = 0; i < rows.size(); i++) if (!validRow(rows.get(i), rows.getFirst().length())) return "bad row " + (i + 1);
            grid = new Grid(rows);
            if (!symmetry.equals("none")) { int cell = grid.asymmetric(symmetry); if (cell >= 0) return "asymmetric at " + grid.location(cell); }
            int components = grid.components(); if (components != 1) return "disconnected components=" + components;
            ShortRun shortRun = Slots.shortRun(grid); if (shortRun != null) return "short slot at " + grid.location(shortRun.cell()) + " " + shortRun.direction();
            layout = new Layout(grid); int orphan = layout.orphan(); if (orphan >= 0) return "orphan cell " + grid.location(orphan);
            GridState state = new GridState(grid.cells.clone(), new String[layout.slots.size()]);
            for (int i = 0; i < themes.size(); i++) {
                String word = themes.get(i); if (!index.scores.containsKey(word)) return "unknown theme " + (i + 1);
                Slot fitting = null;
                for (Slot slot : layout.slots) if (state.words[slot.index] == null && slot.length == word.length() && WordIndex.matches(word, state.pattern(slot))) { fitting = slot; break; }
                if (fitting == null) return "theme " + (i + 1) + " does not fit";
                state.assign(fitting, word); themeSlots.add(fitting.index);
            }
            initial = state; return null;
        }
        boolean filled() { return error == null && finalAttempt.outcome.equals("filled"); }
        int totalScore(Map<String, Integer> scores) { int total = 0; for (String word : state.words) total += scores.get(word); return total; }
        String entry(Slot slot, Map<String, Integer> scores) { String word = state.words[slot.index]; return slot.label + ":" + word + ":" + scores.get(word); }
        List<Integer> lengths() { return layout.slots.stream().map(slot -> slot.length).distinct().sorted().toList(); }
        List<String> gridParagraph() {
            List<String> lines = new ArrayList<>(List.of("TEMPLATE " + name));
            if (error != null) { lines.add("error " + error); return lines; }
            lines.add("outcome=" + finalAttempt.outcome + " attempts=" + attempts.size() + " min_score=" + finalAttempt.minimum);
            lines.addAll(Render.gridLines(grid, state.letters)); lines.add("numbers"); lines.addAll(Render.numberLines(layout)); return lines;
        }
        List<String> clueParagraph(Map<String, Integer> scores) {
            List<String> lines = new ArrayList<>(List.of("TEMPLATE " + name)); int clued = 0, missing = 0, unfilled = 0;
            for (boolean across : new boolean[] {true, false}) {
                List<Slot> group = layout.slots.stream().filter(slot -> slot.across == across).toList(); if (!group.isEmpty()) lines.add(across ? "ACROSS" : "DOWN");
                for (Slot slot : group) {
                    String word = state.words[slot.index];
                    if (word == null) { unfilled++; lines.add(Render.listLine(slot, "(unfilled)", state.pattern(slot), "-", false)); }
                    else { String clue = chosen[slot.index]; if (clue == null) { missing++; clue = "(no clue)"; } else clued++; lines.add(Render.listLine(slot, clue, word, "" + scores.get(word), themeSlots.contains(slot.index))); }
                }
            }
            lines.add("clued=" + clued + " missing=" + missing + " unfilled=" + unfilled); return lines;
        }
        String gridSummary() {
            List<Integer> whites = grid.whites(); int blacks = grid.size() - whites.size(), givens = (int) whites.stream().filter(grid::given).count();
            List<String> holding = List.of("rot180", "mirror").stream().filter(symmetry -> grid.asymmetric(symmetry) < 0).toList();
            return "grid size=" + grid.width + "x" + grid.height + " blocks=" + blacks + " white=" + whites.size() + " density=" + Render.decimal(100 * blacks, grid.size(), 1) + " givens=" + givens + " required=" + symmetry + " symmetry=" + (holding.isEmpty() ? "none" : String.join(",", holding));
        }
        String slotSummary() {
            int across = 0, totalLength = 0, longest = 0, unchecked = 0; Map<Integer, Integer> counts = new TreeMap<>();
            for (Slot slot : layout.slots) { if (slot.across) across++; totalLength += slot.length; longest = Math.max(longest, slot.length); counts.merge(slot.length, 1, Integer::sum); }
            for (int cell : grid.whites()) if (layout.owners(cell) == 1) unchecked++;
            List<String> lengths = new ArrayList<>(); for (var count : counts.entrySet()) lengths.add(count.getKey() + ":" + count.getValue());
            return "slots across=" + across + " down=" + (layout.slots.size() - across) + " total=" + layout.slots.size() + " lengths=" + String.join(",", lengths) + " avg_length=" + Render.decimal(totalLength, layout.slots.size(), 2) + " longest=" + longest + " unchecked=" + unchecked;
        }
        String coverage(WordIndex index) {
            List<String> parts = new ArrayList<>();
            for (int length : lengths()) parts.add(length + ":" + index.byLength.getOrDefault(length, List.of()).stream().filter(word -> index.scores.get(word) >= minimum).count());
            return "coverage " + String.join(" ", parts);
        }
        String tightest(WordIndex index) {
            List<int[]> counts = new ArrayList<>();
            for (Slot slot : layout.slots) if (!themeSlots.contains(slot.index)) counts.add(new int[] {index.candidates(initial.pattern(slot), minimum, initial.used).size(), slot.index});
            counts.sort(Comparator.<int[]>comparingInt(value -> value[0]).thenComparingInt(value -> value[1]));
            return "tightest " + joined(counts.stream().limit(3).map(value -> layout.slots.get(value[1]).label + ":" + value[0]).toList(), " ");
        }
        String hotspots() {
            List<Slot> failed = layout.slots.stream().filter(slot -> finalAttempt.failures[slot.index] > 0)
                .sorted(Comparator.<Slot>comparingInt(slot -> finalAttempt.failures[slot.index]).reversed().thenComparingInt(slot -> slot.index)).limit(3).toList();
            return "hotspots " + joined(failed.stream().map(slot -> slot.label + ":" + finalAttempt.failures[slot.index]).toList(), " ");
        }
        String worstCrossing(Map<String, Integer> scores) {
            int worst = -1, worstSum = 0;
            for (int cell : grid.whites()) {
                int across = layout.acrossSlot[cell], down = layout.downSlot[cell]; if (across < 0 || down < 0) continue;
                int sum = scores.get(state.words[across]) + scores.get(state.words[down]); if (worst < 0 || sum < worstSum) { worst = cell; worstSum = sum; }
            }
            if (worst < 0) return "-";
            Slot across = layout.slots.get(layout.acrossSlot[worst]), down = layout.slots.get(layout.downSlot[worst]);
            return grid.location(worst) + " " + across.label + ":" + state.words[across.index] + "+" + down.label + ":" + state.words[down.index] + "=" + worstSum;
        }
        List<String> quality(Map<String, Integer> scores, int weakScore) {
            int total = totalScore(scores); Slot weakest = layout.slots.getFirst(); List<String> weak = new ArrayList<>();
            for (Slot slot : layout.slots) { if (scores.get(state.words[slot.index]) < scores.get(state.words[weakest.index])) weakest = slot; if (scores.get(state.words[slot.index]) < weakScore) weak.add(entry(slot, scores)); }
            Set<Character> distinct = new HashSet<>(); int points = 0; for (int cell : grid.whites()) { char letter = state.letters[cell]; distinct.add(letter); points += POINTS[letter - 'A']; }
            StringBuilder missing = new StringBuilder(); for (char letter = 'A'; letter <= 'Z'; letter++) if (!distinct.contains(letter)) missing.append(letter);
            return List.of("quality total=" + total + " average=" + Render.decimal(total, layout.slots.size(), 2) + " weakest=" + entry(weakest, scores) + " weak=" + joined(weak, ","),
                "letters distinct=" + distinct.size() + " pangram=" + (missing.isEmpty() ? "yes" : "no") + " missing=" + (missing.isEmpty() ? "-" : missing) + " scrabble=" + Render.decimal(points, grid.whites().size(), 2) + " worst_crossing=" + worstCrossing(scores));
        }
        String partial(WordIndex index) {
            int assigned = 0, lettered = 0; for (String word : state.words) if (word != null) assigned++; for (int cell : grid.whites()) if (state.letters[cell] != '.') lettered++;
            List<String> blocked = new ArrayList<>(); for (Slot slot : layout.slots) if (state.words[slot.index] == null && index.candidates(state.pattern(slot), finalAttempt.minimum, state.used).isEmpty()) blocked.add(slot.label);
            return "partial assigned=" + assigned + "/" + layout.slots.size() + " letters=" + lettered + "/" + grid.whites().size() + " blocked=" + joined(blocked, ",");
        }
        List<String> stats(WordIndex index, int weakScore) {
            List<String> lines = new ArrayList<>(List.of("TEMPLATE " + name, gridSummary(), slotSummary()));
            if (!themeSlots.isEmpty()) lines.add("themes " + String.join(" ", layout.slots.stream().filter(slot -> themeSlots.contains(slot.index)).map(slot -> entry(slot, index.scores)).toList()));
            lines.add(coverage(index)); lines.add(tightest(index));
            for (int i = 0; i < attempts.size(); i++) { Attempt a = attempts.get(i); lines.add("attempt " + (i + 1) + " min_score=" + a.minimum + " budget=" + a.budget + " outcome=" + a.outcome + " nodes=" + a.nodes + " backtracks=" + a.backtracks + " prunes=" + a.prunes + " dead_ends=" + a.deadEnds + " max_depth=" + a.maxDepth); }
            lines.add("trace " + joined(finalAttempt.trace, " ")); lines.add(hotspots());
            if (filled()) { lines.add("order " + joined(finalAttempt.sequence.stream().map(slot -> slot.label).toList(), " ")); lines.addAll(quality(index.scores, weakScore)); }
            else lines.add(partial(index)); return lines;
        }
    }
    static List<String> ranking(List<Template> filled, Map<String, Integer> scores) {
        List<Template> ranked = new ArrayList<>(filled);
        ranked.sort((a, b) -> { int left = a.totalScore(scores) * b.layout.slots.size(), right = b.totalScore(scores) * a.layout.slots.size(); return left != right ? Integer.compare(right, left) : a.name.compareTo(b.name); });
        List<String> lines = new ArrayList<>(List.of("RANKING"));
        for (int i = 0; i < ranked.size(); i++) { Template t = ranked.get(i); int total = t.totalScore(scores), entries = t.layout.slots.size(); lines.add("rank " + (i + 1) + " " + t.name + " average=" + Render.decimal(total, entries, 2) + " total=" + total + " entries=" + entries); } return lines;
    }
    static List<String> reuse(List<Template> filled) {
        Map<String, List<String>> appearances = new HashMap<>(); for (Template t : filled) for (String word : t.state.words) appearances.computeIfAbsent(word, ignored -> new ArrayList<>()).add(t.name);
        List<String> words = appearances.keySet().stream().filter(word -> appearances.get(word).size() >= 2).sorted(Comparator.<String>comparingInt(word -> appearances.get(word).size()).reversed().thenComparing(Comparator.naturalOrder())).toList();
        List<String> lines = new ArrayList<>(List.of("REUSE")); for (String word : words) lines.add("reused " + word + " " + appearances.get(word).size() + " " + String.join(",", appearances.get(word))); return lines;
    }
    static List<String> summary(List<Template> templates) {
        int invalid = 0, filled = 0, unfillable = 0, budget = 0, attempts = 0, nodes = 0;
        for (Template t : templates) {
            if (t.error != null) { invalid++; continue; }
            switch (t.finalAttempt.outcome) { case "filled" -> filled++; case "unfillable" -> unfillable++; case "budget" -> budget++; }
            attempts += t.attempts.size(); for (Attempt attempt : t.attempts) nodes += attempt.nodes;
        }
        return List.of("SUMMARY templates=" + templates.size() + " invalid=" + invalid + " filled=" + filled + " unfillable=" + unfillable + " budget=" + budget + " attempts=" + attempts + " nodes=" + nodes);
    }
    public static void main(String[] args) throws Exception {
        Settings settings = settings(read("params.txt")); WordList words = new WordList(read("words.txt")); ClueBook clues = new ClueBook(read("clues.txt"), words.scores);
        List<Template> templates = new ArrayList<>(); Set<String> names = new HashSet<>();
        for (Block block : blocks(read("templates.txt"))) { Template template = new Template(block, settings); template.process(names, words.index, clues, settings.relaxStep()); names.add(block.name); templates.add(template); }
        List<Template> valid = templates.stream().filter(t -> t.error == null).toList(), filled = valid.stream().filter(Template::filled).toList();
        List<List<String>> stats = new ArrayList<>(); for (Template t : valid) stats.add(t.stats(words.index, settings.weakScore())); stats.add(ranking(filled, words.scores)); stats.add(reuse(filled)); stats.add(summary(templates));
        List<String> wordReport = words.report(); wordReport.addAll(clues.report()); Map<String, List<String>> files = new LinkedHashMap<>();
        files.put("grid.txt", paragraphs(templates.stream().map(Template::gridParagraph).toList())); files.put("clues.txt", paragraphs(valid.stream().map(t -> t.clueParagraph(words.scores)).toList())); files.put("search_stats.txt", paragraphs(stats)); files.put("wordlist.txt", wordReport);
        Files.createDirectories(Path.of("output"));
        for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), entry.getValue().isEmpty() ? "" : String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
    }
}
