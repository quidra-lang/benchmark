import java.nio.file.*;
import java.util.*;

final class TraceIO {
    record Predictor(String name, String scheme, int[] parameters) {}
    record Variant(String name, boolean forwarding, String stage, int latency) {}
    static final class Config {
        int btb, ras, first, last, top, interval;
        String primaryVariant, primaryPredictor;
        List<Predictor> predictors = new ArrayList<>();
        List<Variant> variants = new ArrayList<>();
    }
    static List<String> lines(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name));
    }
    static int hex(String value) {
        return value.matches("[0-9a-f]{8}") ? Integer.parseInt(value, 16) : -1;
    }
    static int register(String value) {
        return value.matches("r(?:[0-9]|[12][0-9]|3[01])") ? Integer.parseInt(value.substring(1)) : -1;
    }
    static Config read() throws Exception {
        Config c = new Config();
        for (String line : lines("config.txt")) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "BTB" -> c.btb = Integer.parseInt(w[1]);
            case "RAS" -> c.ras = Integer.parseInt(w[1]);
            case "TOP" -> c.top = Integer.parseInt(w[1]);
            case "INTERVAL" -> c.interval = Integer.parseInt(w[1]);
            case "PREDICTOR" -> {
                int[] p = new int[w.length - 3];
                for (int i = 0; i < p.length; i++)
                    p[i] = Integer.parseInt(w[i + 3]);
                c.predictors.add(new Predictor(w[1], w[2], p));
            }
            case "VARIANT" ->
                c.variants.add(new Variant(w[1], w[2].equals("ON"), w[3], Integer.parseInt(w[4])));
            case "PRIMARY" -> {
                c.primaryVariant = w[1];
                c.primaryPredictor = w[2];
            }
            case "WINDOW" -> {
                c.first = Integer.parseInt(w[1]);
                c.last = Integer.parseInt(w[2]);
            }
            }
        }
        return c;
    }
}
