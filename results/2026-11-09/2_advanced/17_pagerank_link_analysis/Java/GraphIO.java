import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

record Page(int id, String host, String title, List<String> words) {}
record LinkRecord(int line, int source, int target) {}
record Query(int number, List<String> words, int[] seeds) {}
record Settings(double damping, int iterations, double tolerance, double[] sweep, int[] trusted,
                int spamTop, double spamThreshold, int hitsIterations, int topK, int rootLimit, int neighborLimit) {}
record InputData(List<Page> pages, List<LinkRecord> records, List<Query> queries, Settings settings) {}
final class GraphIO {
    static List<String> lines(String path) throws IOException {
        return Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII);
    }
    static InputData read(String directory) throws IOException {
        List<Page> pages = new ArrayList<>();
        for (String line : lines(directory + "/pages.csv").stream().skip(1).toList()) {
            String[] fields = line.split(",");
            pages.add(new Page(Integer.parseInt(fields[0]), fields[1], fields[2], List.of(fields[2].split(" "))));
        }
        List<LinkRecord> records = new ArrayList<>();
        List<String> links = lines(directory + "/links.csv");
        for (int i = 1; i < links.size(); i++) {
            String[] fields = links.get(i).split(",");
            records.add(new LinkRecord(i + 1, Integer.parseInt(fields[0]), Integer.parseInt(fields[1])));
        }
        List<Query> queries = new ArrayList<>();
        for (String line : lines(directory + "/queries.txt")) {
            String[] sides = line.split(" \\| ");
            queries.add(new Query(queries.size() + 1, List.of(sides[0].split(" ")),
                java.util.Arrays.stream(sides[1].split(" ")).mapToInt(Integer::parseInt).toArray()));
        }
        Map<String, List<String>> entries = new LinkedHashMap<>();
        for (String line : lines(directory + "/params.txt")) {
            List<String> fields = List.of(line.split(" "));
            entries.put(fields.getFirst(), fields.subList(1, fields.size()));
        }
        Settings settings = new Settings(real(entries, "DAMPING"), integer(entries, "PAGERANK_ITERATIONS"), real(entries, "TOLERANCE"),
            entries.get("DAMPING_SWEEP").stream().mapToDouble(Double::parseDouble).toArray(),
            entries.get("TRUSTED").stream().mapToInt(Integer::parseInt).toArray(), integer(entries, "SPAM_TOP"), real(entries, "SPAM_THRESHOLD"),
            integer(entries, "HITS_ITERATIONS"), integer(entries, "TOP_K"), integer(entries, "ROOT_LIMIT"), integer(entries, "NEIGHBOR_LIMIT"));
        return new InputData(pages, records, queries, settings);
    }
    private static int integer(Map<String, List<String>> entries, String key) { return Integer.parseInt(entries.get(key).getFirst()); }
    private static double real(Map<String, List<String>> entries, String key) { return Double.parseDouble(entries.get(key).getFirst()); }
}
