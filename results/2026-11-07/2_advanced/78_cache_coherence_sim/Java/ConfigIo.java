import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class ConfigIo {
    record Scenario(String name, String protocol, String l1, String l2, int order) {}
    record Region(String name, int start, int end) {}
    static final class Config {
        int cores, line, l1Size, l1Ways, l1Sets, l2Size, l2Ways, l2Sets, t1, t2, tm, tb, interval,
            top, cap;
        String primary;
        List<Scenario> scenarios = new ArrayList<>();
        List<Region> regions = new ArrayList<>();
        List<Integer> watch = new ArrayList<>();
    }
    static boolean decimalInteger(String text, int maximum) {
        if (text.isEmpty() || maximum > 0 && text.length() > maximum ||
            text.length() > 1 && text.charAt(0) == '0')
            return false;
        for (int i = 0; i < text.length(); i++)
            if (text.charAt(i) < '0' || text.charAt(i) > '9')
                return false;
        return true;
    }
    static boolean validHexAddress(String text) {
        if (text.length() != 8)
            return false;
        for (int i = 0; i < 8; i++)
            if ("0123456789abcdef".indexOf(text.charAt(i)) < 0)
                return false;
        return true;
    }
    static String hexAddress(int value) {
        String text = Integer.toHexString(value);
        return "0".repeat(8 - text.length()) + text;
    }
    static Config readConfig() throws Exception {
        Config c = new Config();
        for (String line :
             Files.readAllLines(Path.of("input/config.txt"), StandardCharsets.US_ASCII)) {
            String[] f = line.split(" ");
            switch (f[0]) {
            case "CORES":
                c.cores = Integer.parseInt(f[1]);
                break;
            case "LINE":
                c.line = Integer.parseInt(f[1]);
                break;
            case "L1":
                c.l1Size = Integer.parseInt(f[1]);
                c.l1Ways = Integer.parseInt(f[2]);
                break;
            case "L2":
                c.l2Size = Integer.parseInt(f[1]);
                c.l2Ways = Integer.parseInt(f[2]);
                break;
            case "LATENCY":
                c.t1 = Integer.parseInt(f[1]);
                c.t2 = Integer.parseInt(f[2]);
                c.tm = Integer.parseInt(f[3]);
                c.tb = Integer.parseInt(f[4]);
                break;
            case "SCENARIO":
                c.scenarios.add(new Scenario(f[1], f[2], f[3], f[4], c.scenarios.size()));
                break;
            case "PRIMARY":
                c.primary = f[1];
                break;
            case "INTERVAL":
                c.interval = Integer.parseInt(f[1]);
                break;
            case "TOP":
                c.top = Integer.parseInt(f[1]);
                break;
            case "REGION":
                c.regions.add(
                    new Region(f[1], Integer.parseInt(f[2], 16), Integer.parseInt(f[3], 16)));
                break;
            case "WATCH":
                c.watch.add(Integer.parseInt(f[1], 16) / c.line);
                break;
            }
        }
        c.l1Sets = c.l1Size / (c.line * c.l1Ways);
        c.l2Sets = c.l2Size / (c.line * c.l2Ways);
        c.cap = c.l1Sets * c.l1Ways;
        return c;
    }
    static List<String> readTrace() throws Exception {
        return Files.readAllLines(Path.of("input/trace.txt"), StandardCharsets.US_ASCII);
    }
    static void writeLines(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name),
                          lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
