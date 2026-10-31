import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

final class Report {
    static String fraction(long a, long b) {
        long x = a, y = b;
        while (y != 0) {
            long rest = x % y;
            x = y;
            y = rest;
        }
        return a / x + "/" + b / x;
    }
    static String ids(List<Dataset.Obj> objects) {
        if (objects.isEmpty())
            return "-";
        List<String> words = new ArrayList<>();
        for (Dataset.Obj object : objects)
            words.add(Integer.toString(object.id()));
        return String.join(" ", words);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
