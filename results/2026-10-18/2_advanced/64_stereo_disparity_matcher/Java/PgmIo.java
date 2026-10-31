import java.nio.file.*;
import java.util.*;
final class PgmIo {
    record Image(int width, int height, int[] pixels) {}
    static final class Parameters {
        Map<String, List<String>> values = new HashMap<>();
        List<int[]> samples = new ArrayList<>();
        int integer(String name) { return Integer.parseInt(values.get(name).get(0)); }
        String text(String name) { return values.get(name).get(0); }
        int[] integers(String name) {
            List<String> row = values.get(name);
            int[] result = new int[row.size()];
            for (int i = 0; i < result.length; i++)
                result[i] = Integer.parseInt(row.get(i));
            return result;
        }
    }
    static Image read(String name) throws Exception {
        List<String> lines = Files.readAllLines(Path.of("input", name));
        String[] size = lines.get(1).split(" ");
        int w = Integer.parseInt(size[0]), h = Integer.parseInt(size[1]);
        int[] pixels = new int[w * h];
        for (int y = 0; y < h; y++) {
            String[] row = lines.get(y + 3).split(" ");
            for (int x = 0; x < w; x++)
                pixels[y * w + x] = Integer.parseInt(row[x]);
        }
        return new Image(w, h, pixels);
    }
    static Parameters parameters() throws Exception {
        Parameters p = new Parameters();
        for (String line : Files.readAllLines(Path.of("input", "params.txt"))) {
            String[] w = line.split(" ");
            if (w[0].equals("sample"))
                p.samples.add(new int[] {Integer.parseInt(w[1]), Integer.parseInt(w[2])});
            else
                p.values.put(w[0], new ArrayList<>(Arrays.asList(w).subList(1, w.length)));
        }
        return p;
    }
    static void write(String name, int w, int h, int[] pixels) throws Exception {
        List<String> lines = new ArrayList<>(List.of("P2", w + " " + h, "255"));
        for (int y = 0; y < h; y++) {
            StringJoiner row = new StringJoiner(" ");
            for (int x = 0; x < w; x++)
                row.add(Integer.toString(pixels[y * w + x]));
            lines.add(row.toString());
        }
        text(name, lines);
    }
    static void text(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
}
