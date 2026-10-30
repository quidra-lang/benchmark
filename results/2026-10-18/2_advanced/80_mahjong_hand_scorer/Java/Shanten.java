import java.util.*;
final class Shanten {
    record State(int sets, int partial, int pair) {}
    record Key(int sets, int pair) {}
    record Choice(int[] removed, int sets, int partial, int pair) {}
    static final Map<String, List<State>> PATTERNS = new LinkedHashMap<>(65536, 0.75f, true) {
        protected boolean removeEldestEntry(Map.Entry<String, List<State>> entry) {
            return size() > 65536;
        }
    };
    static final Map<String, int[]> NUMBERS = new LinkedHashMap<>(8192, 0.75f, true) {
        protected boolean removeEldestEntry(Map.Entry<String, int[]> entry) {
            return size() > 8192;
        }
    };
    static List<State> patterns(int[] counts, boolean suited) {
        String key = Tiles.key(counts) + (suited ? "s" : "h");
        if (PATTERNS.containsKey(key))
            return PATTERNS.get(key);
        int first = -1;
        for (int i = 0; i < counts.length; i++)
            if (counts[i] > 0) {
                first = i;
                break;
            }
        if (first < 0)
            return List.of(new State(0, 0, 0));
        List<Choice> choices = new ArrayList<>();
        choices.add(new Choice(new int[] {first}, 0, 0, 0));
        if (counts[first] >= 3)
            choices.add(new Choice(new int[] {first, first, first}, 1, 0, 0));
        if (counts[first] >= 2) {
            choices.add(new Choice(new int[] {first, first}, 0, 1, 0));
            choices.add(new Choice(new int[] {first, first}, 0, 0, 1));
        }
        if (suited) {
            if (first <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0)
                choices.add(new Choice(new int[] {first, first + 1, first + 2}, 1, 0, 0));
            for (int difference = 1; difference <= 2; difference++)
                if (first + difference < 9 && counts[first + difference] > 0)
                    choices.add(new Choice(new int[] {first, first + difference}, 0, 1, 0));
        }
        Map<Key, Integer> best = new HashMap<>();
        for (Choice choice : choices) {
            int[] remaining = counts.clone();
            for (int kind : choice.removed())
                remaining[kind]--;
            for (State local : patterns(remaining, suited)) {
                int sets = local.sets() + choice.sets(), pair = local.pair() + choice.pair();
                if (sets > 4 || pair > 1)
                    continue;
                int partial = Math.min(4, local.partial() + choice.partial());
                best.merge(new Key(sets, pair), partial, Math::max);
            }
        }
        List<State> result = new ArrayList<>();
        for (Map.Entry<Key, Integer> entry : best.entrySet())
            result.add(new State(entry.getKey().sets(), entry.getValue(), entry.getKey().pair()));
        PATTERNS.put(key, result);
        return result;
    }
    static int standard(int[] counts) {
        Map<Key, Integer> states = new HashMap<>();
        states.put(new Key(0, 0), 0);
        for (int start : new int[] {0, 9, 18, 27}) {
            List<State> local = patterns(
                Arrays.copyOfRange(counts, start, start == 27 ? 34 : start + 9), start < 27);
            Map<Key, Integer> combined = new HashMap<>();
            for (Map.Entry<Key, Integer> entry : states.entrySet())
                for (State part : local) {
                    int sets = entry.getKey().sets() + part.sets(),
                        pair = entry.getKey().pair() + part.pair();
                    if (sets > 4 || pair > 1)
                        continue;
                    int partial = Math.min(4, entry.getValue() + part.partial());
                    combined.merge(new Key(sets, pair), partial, Math::max);
                }
            states = combined;
        }
        int best = 8;
        for (Map.Entry<Key, Integer> entry : states.entrySet())
            best = Math.min(best, 8 - 2 * entry.getKey().sets() -
                                      Math.min(entry.getValue(), 4 - entry.getKey().sets()) -
                                      entry.getKey().pair());
        return best;
    }
    static int[] numbers(int[] counts) {
        String key = Tiles.key(counts);
        if (NUMBERS.containsKey(key))
            return NUMBERS.get(key);
        int pairs = 0, kinds = 0, orphans = 13;
        boolean orphanPair = false;
        for (int kind = 0; kind < 34; kind++) {
            if (counts[kind] >= 2)
                pairs++;
            if (counts[kind] > 0)
                kinds++;
            if (Tiles.YAOCHUU.contains(kind)) {
                if (counts[kind] > 0)
                    orphans--;
                if (counts[kind] >= 2)
                    orphanPair = true;
            }
        }
        if (orphanPair)
            orphans--;
        int[] result = {standard(counts), 6 - pairs + Math.max(0, 7 - kinds), orphans};
        NUMBERS.put(key, result);
        return result;
    }
}
