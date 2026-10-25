import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.stream.Collectors;

final class PpmWriter {
    static void writePpm(String path, Rgb[][] image) throws IOException {
        StringBuilder text = new StringBuilder("P3\n" + image[0].length + " " + image.length + "\n255\n"); for (Rgb[] row : image) text.append(Arrays.stream(row).map(Rgb::toString).collect(Collectors.joining(" "))).append('\n'); Files.writeString(Path.of(path),text.toString(),StandardCharsets.US_ASCII);
    }
    static void writePreview(String path, Rgb[][] image) throws IOException {
        String ramp = "@%#*+=-:,."; StringBuilder text = new StringBuilder();
        for (int top = 0; top < image.length; top += 4) { for (int left = 0; left < image[0].length; left += 2) { int total = 0; for (int y = top; y < top + 4; y++) for (int x = left; x < left + 2; x++) { Rgb c = image[y][x]; total += 299 * c.r() + 587 * c.g() + 114 * c.b(); } text.append(ramp.charAt((total / 8000) * 10 / 256)); } text.append('\n'); } Files.writeString(Path.of(path),text.toString(),StandardCharsets.US_ASCII);
    }
}
