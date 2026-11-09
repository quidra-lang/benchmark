import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;

final class PgmIo {
    record Point(int x, int y) {}
    static final class Params {
        Map<String, long[]> values = new HashMap<>();
        int get(String key) {
            return (int)values.get(key)[0];
        }
        long value(String key) {
            return values.get(key)[0];
        }
        long[] row(String key) {
            return values.get(key);
        }
    }
    record Data(int[][] image, int[][] trig, Params params) {}
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Data read() throws IOException {
        List<String> input = lines("image.pgm");
        String[] size = input.get(1).split(" ");
        int width = Integer.parseInt(size[0]), height = Integer.parseInt(size[1]);
        int[][] image = new int[height][width], trig = new int[180][2];
        for (int y = 0; y < height; y++) {
            String[] words = input.get(y + 3).split(" ");
            for (int x = 0; x < width; x++)
                image[y][x] = Integer.parseInt(words[x]);
        }
        List<String> table = lines("trig.txt");
        for (int t = 0; t < 180; t++) {
            String[] w = table.get(t).split(" ");
            trig[t][0] = Integer.parseInt(w[1]);
            trig[t][1] = Integer.parseInt(w[2]);
        }
        Params params = new Params();
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            long[] values = new long[w.length - 1];
            for (int i = 1; i < w.length; i++)
                values[i - 1] = Long.parseLong(w[i]);
            params.values.put(w[0], values);
        }
        return new Data(image, trig, params);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    static void pgm(String name, int[][] image) throws IOException {
        List<String> out = new ArrayList<>(List.of("P2", image[0].length + " " + image.length, "255"));
        for (int[] row : image) {
            List<String> words = new ArrayList<>();
            for (int value : row)
                words.add(Integer.toString(value));
            out.add(String.join(" ", words));
        }
        write(name, out);
    }
}
