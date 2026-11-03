import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

record Repetition(String text, List<Integer> positions, List<Integer> gaps, int gcd) {}

record KasiskiData(List<Repetition> repeats, List<Integer> gaps) {
    int count(int period) {
        int result = 0;
        for (int gap : gaps) if (gap % period == 0) result++;
        return result;
    }
}

final class Analysis {
    private Analysis() {}

    static int[] frequencies(String text) {
        int[] counts = new int[26];
        for (int i = 0; i < text.length(); i++) counts[text.charAt(i) - 'A']++;
        return counts;
    }

    static int ioc(String text) {
        if (text.length() < 2) return 0;
        long sum = 0;
        for (int count : frequencies(text)) sum += (long) count * (count - 1);
        return (int)(100000L * sum / ((long) text.length() * (text.length() - 1)));
    }

    static String column(String text, int period, int offset) {
        StringBuilder result = new StringBuilder();
        for (int i = offset; i < text.length(); i += period) result.append(text.charAt(i));
        return result.toString();
    }

    static int[] columnIOCs(String text, int period) {
        int[] counts = new int[period];
        for (int i = 0; i < period; i++) counts[i] = ioc(column(text, period, i));
        return counts;
    }

    static int averageIOC(String text, int period) {
        return Arrays.stream(columnIOCs(text, period)).sum() / period;
    }

    static int gcd(int a, int b) {
        while (b != 0) {
            int next = a % b;
            a = b;
            b = next;
        }
        return a;
    }

    static KasiskiData kasiski(String text) {
        Map<String, List<Integer>> occurrences = new TreeMap<>();
        for (int i = 0; i + 2 < text.length(); i++)
            occurrences.computeIfAbsent(text.substring(i, i + 3),
                ignored -> new ArrayList<>()).add(i + 1);
        List<Repetition> repeats = new ArrayList<>();
        List<Integer> allGaps = new ArrayList<>();
        for (var entry : occurrences.entrySet()) {
            List<Integer> positions = entry.getValue();
            if (positions.size() < 2) continue;
            List<Integer> gaps = new ArrayList<>();
            int divisor = 0;
            for (int i = 1; i < positions.size(); i++) {
                int gap = positions.get(i) - positions.get(i - 1);
                gaps.add(gap);
                divisor = gcd(divisor, gap);
            }
            allGaps.addAll(gaps);
            repeats.add(new Repetition(entry.getKey(), positions, gaps, divisor));
        }
        return new KasiskiData(repeats, allGaps);
    }

    static String numbers(List<Integer> values) {
        return values.stream().map(String::valueOf).collect(Collectors.joining(","));
    }

    static List<String> periodTable(String text, int maxlen, KasiskiData data) {
        List<String> lines = new ArrayList<>();
        for (int period = 1; period <= maxlen; period++) {
            int[] columns = columnIOCs(text, period);
            List<Integer> values = Arrays.stream(columns).boxed().toList();
            lines.add("L=" + period + " ioc=" + Arrays.stream(columns).sum() / period
                + " kasiski=" + data.count(period) + " cols=" + numbers(values));
        }
        return lines;
    }

    static List<String> kasiskiTable(KasiskiData data) {
        List<String> lines = new ArrayList<>();
        lines.add("kasiski repeats=" + data.repeats().size() + " spacings=" + data.gaps().size());
        for (Repetition item : data.repeats())
            lines.add(item.text() + " at=" + numbers(item.positions())
                + " gaps=" + numbers(item.gaps()) + " gcd=" + item.gcd());
        return lines;
    }

    static String topPairs(String text, boolean digraphs) {
        Map<String, Integer> counts = new HashMap<>();
        int step = digraphs ? 2 : 1;
        for (int i = 0; i + 1 < text.length(); i += step) {
            String pair = text.substring(i, i + 2);
            counts.merge(pair, 1, Integer::sum);
        }
        return counts.keySet().stream()
            .sorted(Comparator.<String>comparingInt(key -> counts.get(key)).reversed()
                .thenComparing(Comparator.naturalOrder()))
            .limit(10).map(key -> key + ":" + counts.get(key))
            .collect(Collectors.joining(" "));
    }

    static String percentage(int count, int total) {
        int tenth = (2000 * count + total) / (2 * total);
        return (tenth / 10) + "." + (tenth % 10);
    }

    static List<String> report(int job, String source, String text, Weights weights, int maxlen) {
        KasiskiData info = kasiski(text);
        int[] counts = frequencies(text);
        int doubles = 0, pairDoubles = 0, distinct = 0;
        for (int value : counts) if (value > 0) distinct++;
        for (int i = 0; i + 1 < text.length(); i++) {
            if (text.charAt(i) == text.charAt(i + 1)) {
                doubles++;
                if (i % 2 == 0) pairDoubles++;
            }
        }
        List<String> lines = new ArrayList<>();
        lines.add("JOB " + job + " ANALYZE source=" + source);
        lines.add("letters=" + text.length());
        lines.add("ioc=" + ioc(text) + " mono=" + Scoring.monogram(text, weights.mono())
            + " bigram=" + Scoring.bigram(text, weights.bi()));
        lines.add("doubles=" + doubles + " pair_doubles=" + pairDoubles + " distinct=" + distinct);
        for (int i = 0; i < 26; i++)
            lines.add(Scoring.upper(i) + " " + counts[i] + " " + percentage(counts[i], text.length()));
        lines.add("bigrams " + topPairs(text, false));
        lines.addAll(periodTable(text, maxlen, info));
        lines.addAll(kasiskiTable(info));
        return lines;
    }
}
