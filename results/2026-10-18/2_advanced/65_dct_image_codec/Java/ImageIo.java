import java.nio.file.*;
import java.util.*;
final class ImageIo {
    record Image(int width, int height, int[] pixels) {}
    record Plane(int width, int height, int[] pixels) {}
    record Tables(int[] transform, int[][] basic, Entropy.Table[][] huffman) {}
    static final class Parameters {
        Map<String, List<String>> values = new HashMap<>();
        int integer(String name) { return Integer.parseInt(values.get(name).get(0)); }
        String text(String name) { return values.get(name).get(0); }
        int[] integers(String name) { return parse(String.join(" ", values.get(name))); }
    }
    static int[] parse(String line) {
        String[] w = line.split(" ");
        int[] values = new int[w.length];
        for (int i = 0; i < values.length; i++)
            values[i] = Integer.parseInt(w[i]);
        return values;
    }
    static List<String> lines(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name));
    }
    static Image readImage() throws Exception {
        List<String> lines = lines("image.ppm");
        int[] size = parse(lines.get(1));
        int[] pixels = new int[3 * size[0] * size[1]];
        for (int y = 0; y < size[1]; y++) {
            int[] row = parse(lines.get(y + 3));
            System.arraycopy(row, 0, pixels, 3 * y * size[0], row.length);
        }
        return new Image(size[0], size[1], pixels);
    }
    static Parameters parameters() throws Exception {
        Parameters p = new Parameters();
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            p.values.put(w[0], new ArrayList<>(Arrays.asList(w).subList(1, w.length)));
        }
        return p;
    }
    static Tables tables() throws Exception {
        List<String> lines = lines("tables.txt");
        int[] c = new int[64];
        int[][] basic = new int[2][64];
        for (int y = 0; y < 8; y++) {
            System.arraycopy(parse(lines.get(y + 1)), 0, c, 8 * y, 8);
            for (int t = 0; t < 2; t++)
                System.arraycopy(parse(lines.get(10 + 9 * t + y)), 0, basic[t], 8 * y, 8);
        }
        Entropy.Table[][] tables = new Entropy.Table[2][16];
        for (int i = 27; i < 39; i += 3) {
            String[] key = lines.get(i).split(" ");
            tables[Integer.parseInt(key[1])][Integer.parseInt(key[2])] =
                new Entropy.Table(parse(lines.get(i + 1)), parse(lines.get(i + 2)));
        }
        return new Tables(c, basic, tables);
    }
    static int[] readHex() throws Exception {
        String s = String.join("", lines("stream.hex"));
        int[] data = new int[s.length() / 2];
        for (int i = 0; i < data.length; i++)
            data[i] = Integer.parseInt(s.substring(2 * i, 2 * i + 2), 16);
        return data;
    }
    static void text(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
    static void writeImage(String name, Image image) throws Exception {
        List<String> lines =
            new ArrayList<>(List.of("P3", image.width() + " " + image.height(), "255"));
        for (int y = 0; y < image.height(); y++) {
            StringJoiner row = new StringJoiner(" ");
            for (int x = 0; x < 3 * image.width(); x++)
                row.add(Integer.toString(image.pixels()[3 * y * image.width() + x]));
            lines.add(row.toString());
        }
        text(name, lines);
    }
    static void writeHex(String name, int[] data) throws Exception {
        List<String> lines = new ArrayList<>();
        for (int i = 0; i < data.length; i += 32) {
            StringBuilder row = new StringBuilder();
            for (int j = i; j < Math.min(i + 32, data.length); j++)
                row.append(String.format(Locale.ROOT, "%02x", data[j]));
            lines.add(row.toString());
        }
        text(name, lines);
    }
}
