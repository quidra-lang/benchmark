import java.util.*;
final class Decomposition {
    record Form(int pair, List<List<Integer>> sets) {}
    static final Map<String, List<Form>> CACHE = new LinkedHashMap<>(16384, 0.75f, true) {
        protected boolean removeEldestEntry(Map.Entry<String, List<Form>> entry) {
            return size() > 16384;
        }
    };
    static final Comparator<List<Integer>> SET_ORDER =
        Comparator.<List<Integer>>comparingInt(block -> block.getFirst())
            .thenComparingInt(block -> block.getFirst().equals(block.getLast()) ? 0 : 1);
    static void visit(int[] remaining, int pair, int needed, List<List<Integer>> sets,
                      Set<Form> found) {
        if (sets.size() == needed) {
            for (int count : remaining)
                if (count != 0)
                    return;
            List<List<Integer>> ordered = new ArrayList<>(sets);
            ordered.sort(SET_ORDER);
            found.add(new Form(pair, List.copyOf(ordered)));
            return;
        }
        int first = -1;
        for (int i = 0; i < remaining.length; i++)
            if (remaining[i] > 0) {
                first = i;
                break;
            }
        if (first < 0)
            return;
        if (remaining[first] >= 3) {
            remaining[first] -= 3;
            sets.add(List.of(first, first, first));
            visit(remaining, pair, needed, sets, found);
            sets.removeLast();
            remaining[first] += 3;
        }
        if (first < 27 && first % 9 <= 6 && remaining[first + 1] > 0 && remaining[first + 2] > 0) {
            for (int i = first; i <= first + 2; i++)
                remaining[i]--;
            sets.add(List.of(first, first + 1, first + 2));
            visit(remaining, pair, needed, sets, found);
            sets.removeLast();
            for (int i = first; i <= first + 2; i++)
                remaining[i]++;
        }
    }
    static List<Form> standard(int[] counts, int meldCount) {
        String key = Tiles.key(counts) + ":" + meldCount;
        if (CACHE.containsKey(key))
            return CACHE.get(key);
        int needed = 4 - meldCount, total = 0;
        for (int count : counts)
            total += count;
        if (total != 3 * needed + 2)
            return List.of();
        int[] remaining = counts.clone();
        Set<Form> found = new LinkedHashSet<>();
        for (int pair = 0; pair < 34; pair++)
            if (remaining[pair] >= 2) {
                remaining[pair] -= 2;
                visit(remaining, pair, needed, new ArrayList<>(), found);
                remaining[pair] += 2;
            }
        List<Form> result = new ArrayList<>(found);
        CACHE.put(key, result);
        return result;
    }
    static boolean sevenPairs(int[] counts) {
        int pairs = 0;
        for (int count : counts) {
            if (count != 0 && count != 2)
                return false;
            if (count == 2)
                pairs++;
        }
        return pairs == 7;
    }
    static boolean thirteenOrphans(int[] counts) {
        int total = 0;
        for (int kind = 0; kind < 34; kind++) {
            total += counts[kind];
            if (Tiles.YAOCHUU.contains(kind)) {
                if (counts[kind] == 0)
                    return false;
            } else if (counts[kind] != 0)
                return false;
        }
        return total == 14;
    }
    static boolean winning(int[] counts, int meldCount) {
        return !standard(counts, meldCount).isEmpty() ||
            meldCount == 0 && (sevenPairs(counts) || thirteenOrphans(counts));
    }
    static List<Integer> waitingTiles(int[] hand, int[] meld, int meldCount) {
        List<Integer> waiting = new ArrayList<>();
        int[] concealed = hand.clone();
        for (int kind = 0; kind < 34; kind++) {
            if (hand[kind] + meld[kind] >= 4)
                continue;
            concealed[kind]++;
            if (winning(concealed, meldCount))
                waiting.add(kind);
            concealed[kind]--;
        }
        return waiting;
    }
    static String waitShape(String form, List<Integer> block, int winning, int[] hand) {
        if (form.equals("chiitoitsu"))
            return "tanki";
        if (form.equals("kokushi")) {
            for (int kind : Tiles.YAOCHUU)
                if (hand[kind] != 1)
                    return "single";
            return "thirteen";
        }
        if (block.size() == 2)
            return "tanki";
        if (block.getFirst().equals(block.getLast()))
            return "shanpon";
        int first = block.getFirst();
        if (winning == first + 1)
            return "kanchan";
        if (first % 9 == 0 && winning == first + 2 || first % 9 == 6 && winning == first)
            return "penchan";
        return "ryanmen";
    }
}
