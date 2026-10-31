import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class GridState {
    final char[] letters;
    final String[] words;
    final Set<String> used = new HashSet<>();
    GridState(char[] letters, String[] words) { this.letters = letters; this.words = words; for (String word : words) if (word != null) used.add(word); }
    GridState copy() { return new GridState(letters.clone(), words.clone()); }
    String pattern(Slot slot) { StringBuilder text = new StringBuilder(); for (int cell : slot.cells) text.append(letters[cell]); return text.toString(); }
    List<Integer> assign(Slot slot, String word) {
        List<Integer> filled = new ArrayList<>();
        for (int i = 0; i < slot.length; i++) if (letters[slot.cells[i]] == '.') { letters[slot.cells[i]] = word.charAt(i); filled.add(slot.cells[i]); }
        words[slot.index] = word; used.add(word); return filled;
    }
    void unassign(Slot slot, List<Integer> filled) { for (int cell : filled) letters[cell] = '.'; used.remove(words[slot.index]); words[slot.index] = null; }
}
final class Attempt {
    final Layout layout;
    final WordIndex index;
    final GridState state;
    final int minimum, budget;
    int nodes, backtracks, prunes, deadEnds, maxDepth;
    final List<Slot> sequence = new ArrayList<>();
    GridState best;
    final int[] failures;
    final List<String> trace = new ArrayList<>();
    String outcome;
    Attempt(Layout layout, WordIndex index, GridState initial, int minimum, int budget) {
        this.layout = layout; this.index = index; this.minimum = minimum; this.budget = budget; state = initial.copy(); best = initial.copy(); failures = new int[layout.slots.size()];
    }
    void run() { outcome = switch (search()) { case "complete" -> "filled"; case "fail" -> "unfillable"; default -> "budget"; }; }
    GridState finalState() { return outcome.equals("filled") ? state : best; }
    List<String> candidates(Slot slot) { return index.candidates(state.pattern(slot), minimum, state.used); }
    String search() {
        Slot chosen = null; List<String> choices = null;
        for (Slot slot : layout.slots) if (state.words[slot.index] == null) {
            List<String> words = candidates(slot);
            if (chosen == null || words.size() < choices.size()) { chosen = slot; choices = words; }
        }
        if (chosen == null) return "complete";
        if (choices.isEmpty()) { deadEnds++; failures[chosen.index]++; return "fail"; }
        for (String word : choices) {
            if (nodes == budget) return "abort";
            nodes++; List<Integer> filled = state.assign(chosen, word); sequence.add(chosen); Slot wiped = null;
            for (int other : chosen.crossings) if (state.words[other] == null && candidates(layout.slots.get(other)).isEmpty()) { wiped = layout.slots.get(other); break; }
            if (nodes <= 10) trace.add(chosen.label + "=" + word + (wiped == null ? "" : "!"));
            String result;
            if (wiped != null) { prunes++; failures[wiped.index]++; result = "fail"; }
            else { if (sequence.size() > maxDepth) { maxDepth = sequence.size(); best = state.copy(); } result = search(); }
            if (!result.equals("fail")) return result;
            state.unassign(chosen, filled); sequence.removeLast(); backtracks++;
        }
        return "fail";
    }
}
