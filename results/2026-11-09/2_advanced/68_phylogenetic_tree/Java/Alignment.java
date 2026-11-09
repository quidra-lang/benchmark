import java.nio.file.*;
import java.util.*;
final class Alignment {
    static final String BASES = "ACGT", AMBIGUOUS = "RYSWKMBDHV";
    static final Map<Character, Integer> SETS = Map.ofEntries(
        Map.entry('A', 1), Map.entry('C', 2), Map.entry('G', 4), Map.entry('T', 8),
        Map.entry('R', 5), Map.entry('Y', 10), Map.entry('S', 6), Map.entry('W', 9),
        Map.entry('K', 12), Map.entry('M', 3), Map.entry('B', 14), Map.entry('D', 13),
        Map.entry('H', 11), Map.entry('V', 7), Map.entry('N', 15), Map.entry('-', 15));
    record Record(int line, String name, String sequence) {}
    static List<Record> read() throws Exception {
        List<Record> records = new ArrayList<>();
        String name = null;
        StringBuilder sequence = new StringBuilder();
        int header = 0;
        List<String> lines = Files.readAllLines(Path.of("input", "alignment.fasta"));
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            if (line.startsWith(">")) {
                if (name != null)
                    records.add(
                        new Record(header, name, sequence.toString().toUpperCase(Locale.ROOT)));
                name = line.substring(1).split(" ", 2)[0];
                header = i + 1;
                sequence.setLength(0);
            } else
                sequence.append(line);
        }
        records.add(new Record(header, name, sequence.toString().toUpperCase(Locale.ROOT)));
        return records;
    }
    static final class Patterns {
        List<String> patterns = new ArrayList<>();
        List<int[]> encoded = new ArrayList<>();
        int[] columns;
        List<Integer> weights = new ArrayList<>();
        Patterns(List<String> sequences) {
            int length = sequences.getFirst().length();
            columns = new int[length];
            Map<String, Integer> numbers = new HashMap<>();
            for (int c = 0; c < length; c++) {
                StringBuilder p = new StringBuilder();
                for (String sequence : sequences)
                    p.append(sequence.charAt(c));
                String pattern = p.toString();
                Integer index = numbers.get(pattern);
                if (index == null) {
                    index = patterns.size();
                    numbers.put(pattern, index);
                    patterns.add(pattern);
                    weights.add(0);
                    int[] value = new int[sequences.size()];
                    for (int i = 0; i < value.length; i++)
                        value[i] = SETS.get(pattern.charAt(i));
                    encoded.add(value);
                }
                columns[c] = index;
                weights.set(index, weights.get(index) + 1);
            }
        }
    }
    static int[] classify(List<String> sequences) {
        int[] totals = new int[5];
        for (int c = 0; c < sequences.getFirst().length(); c++) {
            int[] counts = new int[4];
            boolean gap = false;
            for (String sequence : sequences) {
                char value = sequence.charAt(c);
                int base = BASES.indexOf(value);
                if (base >= 0)
                    counts[base]++;
                if (value == '-')
                    gap = true;
            }
            int kinds = 0, repeated = 0;
            for (int n : counts) {
                if (n > 0)
                    kinds++;
                if (n >= 2)
                    repeated++;
            }
            totals[kinds == 0 ? 4 : kinds == 1 ? 0 : 1]++;
            if (repeated >= 2)
                totals[2]++;
            if (gap)
                totals[3]++;
        }
        return totals;
    }
}
