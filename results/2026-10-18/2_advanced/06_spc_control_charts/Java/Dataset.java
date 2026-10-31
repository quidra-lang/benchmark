import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

record Constants(double a2, double a3, double b3, double b4, double d3, double d4, double d2, double c4) {}
final class Settings {
    String characteristic;
    int lsl, usl, target, size, phase1, passes, span, gap, bin, window, step;
    double cusumK, cusumH, weight, ewmaL, ciZ;
    final List<List<Integer>> rules = new ArrayList<>();
    Settings() { for (int j = 0; j < 7; j++) rules.add(new ArrayList<>()); }
}
record Lot(int number, long inspected, long defectives, long defects) {}
record Input(Settings settings, long[] values, List<Lot> lots) {}
final class Dataset {
    private static final Constants[] TABLE = {
        new Constants(1.880,2.659,0,3.267,0,3.267,1.128,0.7979),
        new Constants(1.023,1.954,0,2.568,0,2.574,1.693,0.8862),
        new Constants(0.729,1.628,0,2.266,0,2.282,2.059,0.9213),
        new Constants(0.577,1.427,0,2.089,0,2.114,2.326,0.9400),
        new Constants(0.483,1.287,0.030,1.970,0,2.004,2.534,0.9515),
        new Constants(0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594),
        new Constants(0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650),
        new Constants(0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693),
        new Constants(0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727)
    };
    static Constants controlConstants(int size) { return TABLE[size - 2]; }
    static Input read() throws IOException {
        Settings s = new Settings();
        Map<String, String> fields = new HashMap<>();
        List<String> names = List.of("XBAR_R", "R", "XBAR_S", "S", "I", "MR", "STD");
        for (String line : Files.readAllLines(Path.of("input/spec.txt"))) {
            String[] parts = line.split(" ");
            if (parts[0].equals("rules")) s.rules.set(names.indexOf(parts[1]), Arrays.stream(parts).skip(2).map(Integer::parseInt).toList());
            else fields.put(parts[0], parts[1]);
        }
        s.characteristic = fields.get("characteristic");
        s.lsl = Integer.parseInt(fields.get("lsl")); s.usl = Integer.parseInt(fields.get("usl")); s.target = Integer.parseInt(fields.get("target"));
        s.size = Integer.parseInt(fields.get("subgroup_size")); s.phase1 = Integer.parseInt(fields.get("phase1_subgroups")); s.passes = Integer.parseInt(fields.get("max_passes"));
        s.span = Integer.parseInt(fields.get("ma_span")); s.gap = Integer.parseInt(fields.get("event_gap")); s.bin = Integer.parseInt(fields.get("histogram_bin"));
        s.window = Integer.parseInt(fields.get("rolling_window")); s.step = Integer.parseInt(fields.get("rolling_step"));
        s.cusumK = Double.parseDouble(fields.get("cusum_k")); s.cusumH = Double.parseDouble(fields.get("cusum_h"));
        s.weight = Double.parseDouble(fields.get("ewma_lambda")); s.ewmaL = Double.parseDouble(fields.get("ewma_l")); s.ciZ = Double.parseDouble(fields.get("ci_z"));
        long[] values = Files.readAllLines(Path.of("input/measurements.csv")).stream().skip(1).mapToLong(line -> Long.parseLong(line.split(",")[2])).toArray();
        List<Lot> lots = new ArrayList<>();
        List<String> attributeLines = Files.readAllLines(Path.of("input/attributes.csv"));
        for (String line : attributeLines.subList(1, attributeLines.size())) {
            long[] parts = Arrays.stream(line.split(",")).mapToLong(Long::parseLong).toArray();
            lots.add(new Lot((int)parts[0], parts[1], parts[2], parts[3]));
        }
        return new Input(s, values, lots);
    }
}
