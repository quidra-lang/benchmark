import java.util.*;

final class Vocabulary {
    record RankedTerm(String term, int frequency, double score, int bestClass) {}
    final int termCount;
    final int candidateCount;
    final List<RankedTerm> ranking;
    final String[] terms;
    final int[] frequencies;
    final Map<String, Integer> index = new HashMap<>();

    Vocabulary(List<List<String>> sequences, int[] labels, int classes, int minDf, int size) {
        Map<String, int[]> counts = new TreeMap<>();
        int[] classSizes = new int[classes];
        for (int i = 0; i < sequences.size(); i++) {
            classSizes[labels[i]]++;
            for (String term : new HashSet<>(sequences.get(i))) {
                counts.computeIfAbsent(term, key -> new int[classes])[labels[i]]++;
            }
        }
        termCount = counts.size();
        List<RankedTerm> candidates = new ArrayList<>();
        for (var entry : counts.entrySet()) {
            int frequency = Arrays.stream(entry.getValue()).sum();
            if (frequency < minDf) continue;
            int best = 0;
            double score = chiSquare(entry.getValue()[0], frequency, classSizes[0], labels.length);
            for (int c = 1; c < classes; c++) {
                double value = chiSquare(entry.getValue()[c], frequency, classSizes[c], labels.length);
                if (value > score) { best = c; score = value; }
            }
            candidates.add(new RankedTerm(entry.getKey(), frequency, score, best));
        }
        candidateCount = candidates.size();
        candidates.sort(Comparator.comparingDouble(RankedTerm::score).reversed().thenComparing(RankedTerm::term));
        ranking = new ArrayList<>(candidates.subList(0, size > 0 ? Math.min(size, candidates.size()) : candidates.size()));
        terms = ranking.stream().map(RankedTerm::term).sorted().toArray(String[]::new);
        frequencies = new int[terms.length];
        Map<String, Integer> dfs = new HashMap<>();
        for (RankedTerm term : ranking) dfs.put(term.term(), term.frequency());
        for (int i = 0; i < terms.length; i++) { index.put(terms[i], i); frequencies[i] = dfs.get(terms[i]); }
    }

    private static double chiSquare(long a, long df, long classSize, long total) {
        long b = df - a;
        long c = classSize - a;
        long e = total - classSize - b;
        long determinant = a * e - b * c;
        long numerator = total * determinant * determinant;
        long denominator = df * (total - df) * classSize * (total - classSize);
        return denominator == 0 ? 0.0 : (double) numerator / denominator;
    }

    int size() { return terms.length; }

    int[] encode(List<String> sequence) {
        return sequence.stream().filter(index::containsKey).mapToInt(index::get).toArray();
    }

    static int[] firstOccurrences(int[] sequence) {
        Set<Integer> seen = new LinkedHashSet<>();
        for (int term : sequence) seen.add(term);
        return seen.stream().mapToInt(Integer::intValue).toArray();
    }
}
