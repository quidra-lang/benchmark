import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

record Pixel(int x, int y) {}
record Image(String name, int width, int height, int maxval, int[][] pixels) {}
final class PgmReader {
    static List<String> lines(String path) throws IOException { return Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII); }
    static List<Image> read(String path) throws IOException {
        List<String> words = new ArrayList<>();
        for (String line : lines(path)) {
            String text = line.split("#", 2)[0].trim();
            if (!text.isEmpty()) words.addAll(List.of(text.split(" +")));
        }
        List<Image> images = new ArrayList<>();
        int position = 0;
        while (position < words.size()) {
            String name = words.get(position + 1);
            int width = Integer.parseInt(words.get(position + 3)), height = Integer.parseInt(words.get(position + 4)), maxval = Integer.parseInt(words.get(position + 5));
            position += 6;
            int[][] pixels = new int[height][width];
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) pixels[y][x] = Integer.parseInt(words.get(position++));
            images.add(new Image(name, width, height, maxval, pixels));
        }
        return images;
    }
}
