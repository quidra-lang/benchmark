import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

record Observation(String ident, String label, double[] values) {}
record InputData(String[] features, List<Observation> observations, Map<String, List<String>> settings) {}

final class Dataset {
    static InputData read() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input", "data.csv"), StandardCharsets.US_ASCII);
        String[] header = lines.getFirst().split(",");
        String[] features = Arrays.copyOfRange(header, 2, header.length);
        List<Observation> observations = new ArrayList<>();
        for (String line : lines.subList(1, lines.size())) {
            String[] fields = line.split(",");
            double[] values = Arrays.stream(fields).skip(2).mapToDouble(Double::parseDouble).toArray();
            observations.add(new Observation(fields[0], fields[1], values));
        }
        Map<String, List<String>> settings = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input", "params.txt"), StandardCharsets.US_ASCII)) {
            List<String> fields = List.of(line.split(" "));
            settings.put(fields.getFirst(), fields.subList(1, fields.size()));
        }
        return new InputData(features, observations, settings);
    }

    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n", StandardCharsets.US_ASCII);
    }
}
