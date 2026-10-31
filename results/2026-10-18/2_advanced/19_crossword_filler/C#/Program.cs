using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program {
    static readonly string[] Symmetries = ["rot180", "mirror", "none"];
    static readonly int[] Points = [1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10];
    sealed record Settings(int NodeBudget, int Minimum, string Symmetry, int RelaxStep, int WeakScore);
    sealed record Issue(int Line, string Reason);
    sealed record Duplicate(int Line, string Word, int First);
    sealed record Unknown(int Line, string Word);
    static bool Ignored(string line) => line.Length == 0 || line.StartsWith('#');
    static List<string> Read(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    static Settings ReadSettings(List<string> lines) {
        Dictionary<string, string> values = new(StringComparer.Ordinal);
        foreach (string line in lines) if (!Ignored(line)) {
            int split = line.IndexOf(' ');
            values[line[..split]] = line[(split + 1)..];
        }
        return new Settings(int.Parse(values["node_budget"]), int.Parse(values["min_score"]), values["symmetry"], int.Parse(values["relax_step"]), int.Parse(values["weak_score"]));
    }
    static string Joined(IEnumerable<string> values, string separator) {
        List<string> list = values.ToList();
        return list.Count == 0 ? "-" : string.Join(separator, list);
    }
    static List<string> Paragraphs(IEnumerable<List<string>> paragraphs) {
        List<string> lines = new();
        foreach (List<string> paragraph in paragraphs) {
            if (lines.Count > 0) lines.Add("");
            lines.AddRange(paragraph);
        }
        return lines;
    }
    sealed class WordList {
        readonly int lineCount;
        public readonly Dictionary<string, int> Scores = new(StringComparer.Ordinal);
        readonly Dictionary<string, int> firstLines = new(StringComparer.Ordinal);
        readonly List<Issue> invalid = new();
        readonly List<Duplicate> duplicates = new();
        public readonly WordIndex Index;
        public WordList(List<string> lines) {
            lineCount = lines.Count;
            for (int i = 0; i < lines.Count; i++) {
                string text = lines[i], error = WordIndex.WordError(text);
                if (error != null) { invalid.Add(new Issue(i + 1, error)); continue; }
                int split = text.IndexOf(' ');
                string word = text[..split];
                if (Scores.ContainsKey(word)) duplicates.Add(new Duplicate(i + 1, word, firstLines[word]));
                else { Scores.Add(word, int.Parse(text[(split + 1)..])); firstLines.Add(word, i + 1); }
            }
            Index = new WordIndex(Scores);
        }
        public List<string> Report() {
            List<string> lines = ["WORDLIST lines=" + lineCount + " valid=" + Scores.Count + " invalid=" + invalid.Count + " duplicates=" + duplicates.Count];
            foreach (Issue issue in invalid) lines.Add("invalid " + issue.Line + " " + issue.Reason);
            foreach (Duplicate duplicate in duplicates) lines.Add("duplicate " + duplicate.Line + " " + duplicate.Word + " first=" + duplicate.First);
            foreach (var pair in Index.ByLength) {
                List<string> words = pair.Value;
                int total = words.Sum(word => Scores[word]);
                string best = words[0];
                lines.Add("length " + pair.Key + " words=" + words.Count + " average=" + Render.Decimal(total, words.Count, 2) + " best=" + best + ":" + Scores[best]);
            }
            int[] bands = new int[5];
            foreach (int score in Scores.Values) bands[(score - 1) / 20]++;
            lines.Add("bands 1-20=" + bands[0] + " 21-40=" + bands[1] + " 41-60=" + bands[2] + " 61-80=" + bands[3] + " 81-100=" + bands[4]);
            lines.Add("top " + string.Join(" ", Index.Ranked.Take(5).Select(word => word + ":" + Scores[word])));
            int[] frequency = new int[26];
            foreach (string word in Scores.Keys) for (int i = 0; i < 26; i++) if (word.Contains((char)('A' + i))) frequency[i]++;
            List<int> letters = Enumerable.Range(0, 26).OrderBy(letter => frequency[letter]).ThenBy(letter => letter).Take(5).ToList();
            lines.Add("rare_letters " + string.Join(" ", letters.Select(letter => "" + (char)('A' + letter) + ":" + frequency[letter])));
            return lines;
        }
    }
    sealed class Clue {
        public readonly string Word, Text;
        public readonly int Number;
        public int Uses;
        public Clue(string word, int number, string text) { Word = word; Number = number; Text = text; }
    }
    sealed class ClueBook {
        int entries, added;
        readonly List<Issue> invalid = new();
        readonly List<Unknown> unknown = new();
        readonly SortedDictionary<string, List<Clue>> clues = new(StringComparer.Ordinal);
        public ClueBook(List<string> lines, Dictionary<string, int> scores) {
            for (int i = 0; i < lines.Count; i++) {
                string text = lines[i];
                if (Ignored(text)) continue;
                entries++;
                string error = WordIndex.ClueError(text);
                if (error != null) { invalid.Add(new Issue(i + 1, error)); continue; }
                int split = text.IndexOf('|');
                string word = text[..split];
                if (!scores.ContainsKey(word)) { unknown.Add(new Unknown(i + 1, word)); continue; }
                if (!clues.TryGetValue(word, out List<Clue> list)) clues[word] = list = new();
                list.Add(new Clue(word, list.Count + 1, text[(split + 1)..]));
                added++;
            }
        }
        public string Choose(string word) {
            if (!clues.TryGetValue(word, out List<Clue> list)) return null;
            Clue chosen = list[0];
            foreach (Clue clue in list) if (clue.Uses < chosen.Uses) chosen = clue;
            chosen.Uses++;
            return chosen.Text;
        }
        public List<string> Report() {
            List<string> lines = ["CLUES entries=" + entries + " valid=" + added + " invalid=" + invalid.Count + " unknown=" + unknown.Count + " words=" + clues.Count];
            foreach (Issue issue in invalid) lines.Add("clue_invalid " + issue.Line + " " + issue.Reason);
            foreach (Unknown issue in unknown) lines.Add("clue_unknown " + issue.Line + " " + issue.Word);
            List<Clue> all = clues.Values.SelectMany(list => list).ToList();
            int used = all.Count(clue => clue.Uses > 0), repeated = all.Count(clue => clue.Uses >= 2);
            lines.Add("CLUE_USE used=" + used + " unused=" + (all.Count - used) + " repeated=" + repeated);
            foreach (Clue clue in all) if (clue.Uses >= 2) lines.Add("repeated " + clue.Word + " clue=" + clue.Number + " uses=" + clue.Uses);
            return lines;
        }
    }
    sealed class Block {
        public readonly string Name;
        public readonly List<string> Options = new(), Rows = new();
        public Block(string name) { Name = name; }
    }
    static List<Block> Blocks(List<string> lines) {
        List<Block> blocks = new();
        Block current = null;
        foreach (string line in lines) {
            if (current == null) { if (line.StartsWith("TEMPLATE ", StringComparison.Ordinal)) current = new Block(line[9..]); }
            else if (line == "END") { blocks.Add(current); current = null; }
            else if (line.Contains(' ')) current.Options.Add(line);
            else current.Rows.Add(line);
        }
        return blocks;
    }
    static bool ValidName(string name) => name.Length >= 1 && name.Length <= 20 && name.All(c => c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_');
    static bool ValidRow(string row, int width) => row.Length >= 3 && row.Length <= 15 && row.Length == width && row.All(c => c == '#' || c == '.' || c >= 'A' && c <= 'Z');
    sealed class Template {
        public readonly string Name;
        readonly List<string> options, rows;
        int budget, minimum;
        string symmetry;
        public string Error;
        readonly List<string> themes = new();
        Grid grid;
        public Layout Layout;
        GridState initial;
        public GridState State;
        readonly HashSet<int> themeSlots = new();
        public readonly List<Attempt> Attempts = new();
        public Attempt FinalAttempt;
        string[] chosen;
        public Template(Block block, Settings settings) {
            Name = block.Name; options = block.Options; rows = block.Rows;
            budget = settings.NodeBudget; minimum = settings.Minimum; symmetry = settings.Symmetry;
        }
        public void Process(HashSet<string> names, WordIndex index, ClueBook clues, int relax) {
            Error = Check(names, index);
            if (Error != null) return;
            int score = minimum;
            while (true) {
                Attempt attempt = new(Layout, index, initial, score, budget);
                attempt.Run(); Attempts.Add(attempt); FinalAttempt = attempt;
                if (attempt.Outcome == "filled" || relax < 1 || score <= 1) break;
                score = Math.Max(score - relax, 1);
            }
            State = FinalAttempt.FinalState();
            chosen = new string[Layout.Slots.Count];
            foreach (bool across in new[] { true, false }) foreach (Slot slot in Layout.Slots)
                if (slot.Across == across && State.Words[slot.Index] != null) chosen[slot.Index] = clues.Choose(State.Words[slot.Index]);
        }
        int ReadOptions() {
            HashSet<string> seen = new(StringComparer.Ordinal);
            for (int i = 0; i < options.Count; i++) {
                string text = options[i];
                int split = text.IndexOf(' ');
                string key = text[..split], value = text[(split + 1)..];
                if (key == "theme") {
                    if (!WordIndex.ValidWord(value) || themes.Contains(value)) return i + 1;
                    themes.Add(value);
                }
                else if (seen.Contains(key) || !ApplyOption(key, value)) return i + 1;
                seen.Add(key);
            }
            return -1;
        }
        bool ApplyOption(string key, string value) {
            if (key == "node_budget" && WordIndex.ValidInteger(value, 1, 100000)) budget = int.Parse(value);
            else if (key == "min_score" && WordIndex.ValidInteger(value, 1, 100)) minimum = int.Parse(value);
            else if (key == "symmetry" && Symmetries.Contains(value)) symmetry = value;
            else return false;
            return true;
        }
        string Check(HashSet<string> names, WordIndex index) {
            if (!ValidName(Name)) return "bad name";
            if (names.Contains(Name)) return "duplicate name";
            int bad = ReadOptions();
            if (bad >= 0) return "bad option " + bad;
            if (rows.Count < 3 || rows.Count > 15) return "bad height";
            for (int i = 0; i < rows.Count; i++) if (!ValidRow(rows[i], rows[0].Length)) return "bad row " + (i + 1);
            grid = new Grid(rows);
            if (symmetry != "none") {
                int cell = grid.Asymmetric(symmetry);
                if (cell >= 0) return "asymmetric at " + grid.Location(cell);
            }
            int components = grid.Components();
            if (components != 1) return "disconnected components=" + components;
            ShortRun shortRun = SlotFinder.FindShort(grid);
            if (shortRun != null) return "short slot at " + grid.Location(shortRun.Cell) + " " + shortRun.Direction;
            Layout = new Layout(grid);
            int orphan = Layout.Orphan();
            if (orphan >= 0) return "orphan cell " + grid.Location(orphan);
            GridState state = new((char[])grid.Cells.Clone(), new string[Layout.Slots.Count]);
            for (int i = 0; i < themes.Count; i++) {
                string word = themes[i];
                if (!index.Scores.ContainsKey(word)) return "unknown theme " + (i + 1);
                Slot fitting = null;
                foreach (Slot slot in Layout.Slots) if (state.Words[slot.Index] == null && slot.Length == word.Length && WordIndex.Matches(word, state.Pattern(slot))) { fitting = slot; break; }
                if (fitting == null) return "theme " + (i + 1) + " does not fit";
                state.Assign(fitting, word); themeSlots.Add(fitting.Index);
            }
            initial = state;
            return null;
        }
        public bool Filled() => Error == null && FinalAttempt.Outcome == "filled";
        public int TotalScore(Dictionary<string, int> scores) => State.Words.Sum(word => scores[word]);
        string Entry(Slot slot, Dictionary<string, int> scores) {
            string word = State.Words[slot.Index];
            return slot.Label + ":" + word + ":" + scores[word];
        }
        List<int> Lengths() => Layout.Slots.Select(slot => slot.Length).Distinct().Order().ToList();
        public List<string> GridParagraph() {
            List<string> lines = ["TEMPLATE " + Name];
            if (Error != null) { lines.Add("error " + Error); return lines; }
            lines.Add("outcome=" + FinalAttempt.Outcome + " attempts=" + Attempts.Count + " min_score=" + FinalAttempt.Minimum);
            lines.AddRange(Render.GridLines(grid, State.Letters));
            lines.Add("numbers"); lines.AddRange(Render.NumberLines(Layout));
            return lines;
        }
        public List<string> ClueParagraph(Dictionary<string, int> scores) {
            List<string> lines = ["TEMPLATE " + Name];
            int clued = 0, missing = 0, unfilled = 0;
            foreach (bool across in new[] { true, false }) {
                List<Slot> group = Layout.Slots.Where(slot => slot.Across == across).ToList();
                if (group.Count > 0) lines.Add(across ? "ACROSS" : "DOWN");
                foreach (Slot slot in group) {
                    string word = State.Words[slot.Index];
                    if (word == null) { unfilled++; lines.Add(Render.ListLine(slot, "(unfilled)", State.Pattern(slot), "-", false)); }
                    else {
                        string clue = chosen[slot.Index];
                        if (clue == null) { missing++; clue = "(no clue)"; } else clued++;
                        lines.Add(Render.ListLine(slot, clue, word, scores[word].ToString(), themeSlots.Contains(slot.Index)));
                    }
                }
            }
            lines.Add("clued=" + clued + " missing=" + missing + " unfilled=" + unfilled);
            return lines;
        }
        string GridSummary() {
            List<int> whites = grid.Whites();
            int blacks = grid.Size - whites.Count, givens = whites.Count(grid.Given);
            List<string> holding = new[] { "rot180", "mirror" }.Where(value => grid.Asymmetric(value) < 0).ToList();
            return "grid size=" + grid.Width + "x" + grid.Height + " blocks=" + blacks + " white=" + whites.Count + " density=" + Render.Decimal(100 * blacks, grid.Size, 1) + " givens=" + givens + " required=" + symmetry + " symmetry=" + (holding.Count == 0 ? "none" : string.Join(",", holding));
        }
        string SlotSummary() {
            int across = 0, totalLength = 0, longest = 0;
            SortedDictionary<int, int> counts = new();
            foreach (Slot slot in Layout.Slots) {
                if (slot.Across) across++;
                totalLength += slot.Length; longest = Math.Max(longest, slot.Length);
                counts[slot.Length] = counts.GetValueOrDefault(slot.Length) + 1;
            }
            int uncheckedCells = grid.Whites().Count(cell => Layout.Owners(cell) == 1);
            return "slots across=" + across + " down=" + (Layout.Slots.Count - across) + " total=" + Layout.Slots.Count + " lengths=" + string.Join(",", counts.Select(pair => pair.Key + ":" + pair.Value)) + " avg_length=" + Render.Decimal(totalLength, Layout.Slots.Count, 2) + " longest=" + longest + " unchecked=" + uncheckedCells;
        }
        string Coverage(WordIndex index) => "coverage " + string.Join(" ", Lengths().Select(length => length + ":" + index.ByLength.GetValueOrDefault(length, new()).Count(word => index.Scores[word] >= minimum)));
        string Tightest(WordIndex index) {
            var counts = Layout.Slots.Where(slot => !themeSlots.Contains(slot.Index)).Select(slot => (Slot: slot, Count: index.Candidates(initial.Pattern(slot), minimum, initial.Used).Count)).OrderBy(value => value.Count).ThenBy(value => value.Slot.Index).Take(3);
            return "tightest " + Joined(counts.Select(value => value.Slot.Label + ":" + value.Count), " ");
        }
        string Hotspots() => "hotspots " + Joined(Layout.Slots.Where(slot => FinalAttempt.Failures[slot.Index] > 0).OrderByDescending(slot => FinalAttempt.Failures[slot.Index]).ThenBy(slot => slot.Index).Take(3).Select(slot => slot.Label + ":" + FinalAttempt.Failures[slot.Index]), " ");
        string WorstCrossing(Dictionary<string, int> scores) {
            int worst = -1, worstSum = 0;
            foreach (int cell in grid.Whites()) {
                int acrossIndex = Layout.AcrossSlot[cell], downIndex = Layout.DownSlot[cell];
                if (acrossIndex < 0 || downIndex < 0) continue;
                int sum = scores[State.Words[acrossIndex]] + scores[State.Words[downIndex]];
                if (worst < 0 || sum < worstSum) { worst = cell; worstSum = sum; }
            }
            if (worst < 0) return "-";
            Slot across = Layout.Slots[Layout.AcrossSlot[worst]], down = Layout.Slots[Layout.DownSlot[worst]];
            return grid.Location(worst) + " " + across.Label + ":" + State.Words[across.Index] + "+" + down.Label + ":" + State.Words[down.Index] + "=" + worstSum;
        }
        List<string> Quality(Dictionary<string, int> scores, int weakScore) {
            int total = TotalScore(scores);
            Slot weakest = Layout.Slots[0];
            List<string> weak = new();
            foreach (Slot slot in Layout.Slots) {
                if (scores[State.Words[slot.Index]] < scores[State.Words[weakest.Index]]) weakest = slot;
                if (scores[State.Words[slot.Index]] < weakScore) weak.Add(Entry(slot, scores));
            }
            HashSet<char> distinct = new();
            int points = 0;
            foreach (int cell in grid.Whites()) { char letter = State.Letters[cell]; distinct.Add(letter); points += Points[letter - 'A']; }
            string missing = new(Enumerable.Range('A', 26).Select(value => (char)value).Where(letter => !distinct.Contains(letter)).ToArray());
            return ["quality total=" + total + " average=" + Render.Decimal(total, Layout.Slots.Count, 2) + " weakest=" + Entry(weakest, scores) + " weak=" + Joined(weak, ","),
                "letters distinct=" + distinct.Count + " pangram=" + (missing.Length == 0 ? "yes" : "no") + " missing=" + (missing.Length == 0 ? "-" : missing) + " scrabble=" + Render.Decimal(points, grid.Whites().Count, 2) + " worst_crossing=" + WorstCrossing(scores)];
        }
        string Partial(WordIndex index) {
            int assigned = State.Words.Count(word => word != null), lettered = grid.Whites().Count(cell => State.Letters[cell] != '.');
            List<string> blocked = Layout.Slots.Where(slot => State.Words[slot.Index] == null && index.Candidates(State.Pattern(slot), FinalAttempt.Minimum, State.Used).Count == 0).Select(slot => slot.Label).ToList();
            return "partial assigned=" + assigned + "/" + Layout.Slots.Count + " letters=" + lettered + "/" + grid.Whites().Count + " blocked=" + Joined(blocked, ",");
        }
        public List<string> Stats(WordIndex index, int weakScore) {
            List<string> lines = ["TEMPLATE " + Name, GridSummary(), SlotSummary()];
            if (themeSlots.Count > 0) lines.Add("themes " + string.Join(" ", Layout.Slots.Where(slot => themeSlots.Contains(slot.Index)).Select(slot => Entry(slot, index.Scores))));
            lines.Add(Coverage(index)); lines.Add(Tightest(index));
            for (int i = 0; i < Attempts.Count; i++) {
                Attempt a = Attempts[i];
                lines.Add("attempt " + (i + 1) + " min_score=" + a.Minimum + " budget=" + a.Budget + " outcome=" + a.Outcome + " nodes=" + a.Nodes + " backtracks=" + a.Backtracks + " prunes=" + a.Prunes + " dead_ends=" + a.DeadEnds + " max_depth=" + a.MaxDepth);
            }
            lines.Add("trace " + Joined(FinalAttempt.Trace, " ")); lines.Add(Hotspots());
            if (Filled()) { lines.Add("order " + Joined(FinalAttempt.Sequence.Select(slot => slot.Label), " ")); lines.AddRange(Quality(index.Scores, weakScore)); }
            else lines.Add(Partial(index));
            return lines;
        }
    }
    static List<string> Ranking(List<Template> filled, Dictionary<string, int> scores) {
        List<Template> ranked = new(filled);
        ranked.Sort((a, b) => {
            int left = a.TotalScore(scores) * b.Layout.Slots.Count, right = b.TotalScore(scores) * a.Layout.Slots.Count;
            return left != right ? right.CompareTo(left) : StringComparer.Ordinal.Compare(a.Name, b.Name);
        });
        List<string> lines = ["RANKING"];
        for (int i = 0; i < ranked.Count; i++) {
            Template t = ranked[i]; int total = t.TotalScore(scores), entries = t.Layout.Slots.Count;
            lines.Add("rank " + (i + 1) + " " + t.Name + " average=" + Render.Decimal(total, entries, 2) + " total=" + total + " entries=" + entries);
        }
        return lines;
    }
    static List<string> Reuse(List<Template> filled) {
        Dictionary<string, List<string>> appearances = new(StringComparer.Ordinal);
        foreach (Template t in filled) foreach (string word in t.State.Words) {
            if (!appearances.TryGetValue(word, out List<string> names)) appearances[word] = names = new();
            names.Add(t.Name);
        }
        List<string> words = appearances.Keys.Where(word => appearances[word].Count >= 2).OrderByDescending(word => appearances[word].Count).ThenBy(word => word, StringComparer.Ordinal).ToList();
        List<string> lines = ["REUSE"];
        foreach (string word in words) lines.Add("reused " + word + " " + appearances[word].Count + " " + string.Join(",", appearances[word]));
        return lines;
    }
    static List<string> Summary(List<Template> templates) {
        int invalid = 0, filled = 0, unfillable = 0, budget = 0, attempts = 0, nodes = 0;
        foreach (Template t in templates) {
            if (t.Error != null) { invalid++; continue; }
            switch (t.FinalAttempt.Outcome) { case "filled": filled++; break; case "unfillable": unfillable++; break; case "budget": budget++; break; }
            attempts += t.Attempts.Count; nodes += t.Attempts.Sum(attempt => attempt.Nodes);
        }
        return ["SUMMARY templates=" + templates.Count + " invalid=" + invalid + " filled=" + filled + " unfillable=" + unfillable + " budget=" + budget + " attempts=" + attempts + " nodes=" + nodes];
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Settings settings = ReadSettings(Read("params.txt"));
        WordList words = new(Read("words.txt"));
        ClueBook clues = new(Read("clues.txt"), words.Scores);
        List<Template> templates = new();
        HashSet<string> names = new(StringComparer.Ordinal);
        foreach (Block block in Blocks(Read("templates.txt"))) {
            Template template = new(block, settings);
            template.Process(names, words.Index, clues, settings.RelaxStep);
            names.Add(block.Name); templates.Add(template);
        }
        List<Template> valid = templates.Where(t => t.Error == null).ToList(), filled = valid.Where(t => t.Filled()).ToList();
        List<List<string>> stats = valid.Select(t => t.Stats(words.Index, settings.WeakScore)).ToList();
        stats.Add(Ranking(filled, words.Scores)); stats.Add(Reuse(filled)); stats.Add(Summary(templates));
        List<string> wordReport = words.Report();
        wordReport.AddRange(clues.Report());
        Dictionary<string, List<string>> files = new() {
            ["grid.txt"] = Paragraphs(templates.Select(t => t.GridParagraph())),
            ["clues.txt"] = Paragraphs(valid.Select(t => t.ClueParagraph(words.Scores))),
            ["search_stats.txt"] = Paragraphs(stats),
            ["wordlist.txt"] = wordReport
        };
        Directory.CreateDirectory("output");
        foreach (var pair in files) File.WriteAllText(Path.Combine("output", pair.Key), pair.Value.Count == 0 ? "" : string.Join("\n", pair.Value) + "\n", Encoding.ASCII);
    }
}
