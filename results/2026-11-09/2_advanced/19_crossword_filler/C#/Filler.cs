using System.Collections.Generic;
using System.Linq;

sealed class GridState {
    public readonly char[] Letters;
    public readonly string[] Words;
    public readonly HashSet<string> Used;
    public GridState(char[] letters, string[] words) {
        Letters = letters; Words = words;
        Used = words.Where(word => word != null).ToHashSet(System.StringComparer.Ordinal);
    }
    public GridState Copy() => new((char[])Letters.Clone(), (string[])Words.Clone());
    public string Pattern(Slot slot) => new(slot.Cells.Select(cell => Letters[cell]).ToArray());
    public List<int> Assign(Slot slot, string word) {
        List<int> filled = new();
        for (int i = 0; i < slot.Length; i++) if (Letters[slot.Cells[i]] == '.') { Letters[slot.Cells[i]] = word[i]; filled.Add(slot.Cells[i]); }
        Words[slot.Index] = word; Used.Add(word);
        return filled;
    }
    public void Unassign(Slot slot, List<int> filled) {
        foreach (int cell in filled) Letters[cell] = '.';
        Used.Remove(Words[slot.Index]); Words[slot.Index] = null;
    }
}

sealed class Attempt {
    readonly Layout layout;
    readonly WordIndex index;
    public readonly GridState State;
    public readonly int Minimum, Budget;
    public int Nodes, Backtracks, Prunes, DeadEnds, MaxDepth;
    public readonly List<Slot> Sequence = new();
    public GridState Best;
    public readonly int[] Failures;
    public readonly List<string> Trace = new();
    public string Outcome;
    public Attempt(Layout layout, WordIndex index, GridState initial, int minimum, int budget) {
        this.layout = layout; this.index = index; Minimum = minimum; Budget = budget;
        State = initial.Copy(); Best = initial.Copy(); Failures = new int[layout.Slots.Count];
    }
    public void Run() => Outcome = Search() switch { "complete" => "filled", "fail" => "unfillable", _ => "budget" };
    public GridState FinalState() => Outcome == "filled" ? State : Best;
    List<string> Candidates(Slot slot) => index.Candidates(State.Pattern(slot), Minimum, State.Used);
    string Search() {
        Slot chosen = null;
        List<string> choices = null;
        foreach (Slot slot in layout.Slots) if (State.Words[slot.Index] == null) {
            List<string> words = Candidates(slot);
            if (chosen == null || words.Count < choices.Count) { chosen = slot; choices = words; }
        }
        if (chosen == null) return "complete";
        if (choices.Count == 0) { DeadEnds++; Failures[chosen.Index]++; return "fail"; }
        foreach (string word in choices) {
            if (Nodes == Budget) return "abort";
            Nodes++;
            List<int> filled = State.Assign(chosen, word);
            Sequence.Add(chosen);
            Slot wiped = null;
            foreach (int other in chosen.Crossings) if (State.Words[other] == null && Candidates(layout.Slots[other]).Count == 0) { wiped = layout.Slots[other]; break; }
            if (Nodes <= 10) Trace.Add(chosen.Label + "=" + word + (wiped == null ? "" : "!"));
            string result;
            if (wiped != null) { Prunes++; Failures[wiped.Index]++; result = "fail"; }
            else {
                if (Sequence.Count > MaxDepth) { MaxDepth = Sequence.Count; Best = State.Copy(); }
                result = Search();
            }
            if (result != "fail") return result;
            State.Unassign(chosen, filled); Sequence.RemoveAt(Sequence.Count - 1); Backtracks++;
        }
        return "fail";
    }
}
