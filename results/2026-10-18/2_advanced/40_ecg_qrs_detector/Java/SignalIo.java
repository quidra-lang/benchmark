import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;

final class SignalIo {
    static final class Annotation {
        int sample;
        String label;
        Main.Beat beat;
        Annotation(int sample, String label) {
            this.sample = sample;
            this.label = label;
        }
    }
    static long[] ecg() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input/ecg.csv"), StandardCharsets.US_ASCII);
        long[] result = new long[lines.size() - 1];
        for (int i = 1; i < lines.size(); i++)
            result[i - 1] = Long.parseLong(lines.get(i).split(",")[1]);
        return result;
    }
    static List<Annotation> annotations() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input/annotations.csv"), StandardCharsets.US_ASCII);
        List<Annotation> result = new ArrayList<>();
        for (int i = 1; i < lines.size(); i++) {
            String[] w = lines.get(i).split(",");
            result.add(new Annotation(Integer.parseInt(w[0]), w[1]));
        }
        return result;
    }
    static Map<String, Integer> parameters() throws IOException {
        Map<String, Integer> result = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
            String[] w = line.split(" ");
            result.put(w[0], Integer.parseInt(w[1]));
        }
        return result;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
