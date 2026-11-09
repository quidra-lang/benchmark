import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

record Group(int number, String name, long[] values) {}
record PairedSample(long[] before, long[] after, long[] differences) {}
record Comparison(Group first, Group second) {}
record Settings(long seed, int bootstrap, int permutations, int confidence, int pilot,
                int powerSims, int powerPerms, int bins) {}
record Dataset(List<Group> groups, PairedSample paired, List<Comparison> pairs, Settings settings) {
    static List<String> lines(String path) throws IOException {
        return Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII);
    }
    static long hundredths(String text) {
        String[] parts = text.split("\\.", -1);
        return 100 * Long.parseLong(parts[0]) + (parts.length == 1 ? 0 : Long.parseLong((parts[1] + "00").substring(0, 2)));
    }
    static Dataset load(String directory) throws IOException {
        Map<String, List<Long>> values = new LinkedHashMap<>();
        for (String line : lines(directory + "/samples.csv").stream().skip(1).toList()) {
            String[] fields = line.split(",");
            values.computeIfAbsent(fields[0], ignored -> new ArrayList<>()).add(hundredths(fields[1]));
        }
        List<Group> groups = new ArrayList<>();
        Map<String, Group> names = new LinkedHashMap<>();
        for (var entry : values.entrySet()) {
            Group group = new Group(groups.size() + 1, entry.getKey(), entry.getValue().stream().mapToLong(Long::longValue).toArray());
            groups.add(group); names.put(group.name(), group);
        }
        List<String> pairedLines = lines(directory + "/paired.csv");
        long[] before = new long[pairedLines.size() - 1], after = new long[before.length], differences = new long[before.length];
        for (int i = 0; i < before.length; i++) {
            String[] fields = pairedLines.get(i + 1).split(",");
            before[i] = hundredths(fields[1]); after[i] = hundredths(fields[2]); differences[i] = after[i] - before[i];
        }
        Map<String, int[]> entries = new LinkedHashMap<>();
        List<Comparison> pairs = new ArrayList<>();
        for (String line : lines(directory + "/params.txt")) {
            String[] fields = line.split(" ");
            if (fields[0].equals("compare")) pairs.add(new Comparison(names.get(fields[1]), names.get(fields[2])));
            else entries.put(fields[0], Arrays.stream(fields).skip(1).mapToInt(Integer::parseInt).toArray());
        }
        Settings settings = new Settings(entries.get("seed")[0], entries.get("bootstrap")[0], entries.get("permutations")[0],
            entries.get("confidence")[0], entries.get("pilot")[0], entries.get("power")[0], entries.get("power")[1], entries.get("bins")[0]);
        return new Dataset(groups, new PairedSample(before, after, differences), pairs, settings);
    }
}
