import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.YearMonth;
import java.util.*;

final class SeriesData {
    final String name;
    final List<String> periods = new ArrayList<>();
    final List<Integer> raw = new ArrayList<>();
    final Map<String, String> events = new HashMap<>();
    int onHand, lead, review;
    double service;
    SeriesData(String name) {
        this.name = name;
    }
}
final class SeriesIo {
    final List<SeriesData> series = new ArrayList<>();
    final Map<String, String[]> settings = new HashMap<>();
    SeriesIo() throws IOException {
        Map<String, SeriesData> named = new LinkedHashMap<>();
        List<String> lines = read("series.csv");
        for (String line : lines.subList(1, lines.size())) {
            String[] fields = line.split(",");
            SeriesData data = named.get(fields[0]);
            if (data == null) {
                data = new SeriesData(fields[0]);
                named.put(fields[0], data);
                series.add(data);
            }
            data.periods.add(fields[1]);
            data.raw.add(fields[2].equals("NA") ? -1 : Integer.parseInt(fields[2]));
        }
        lines = read("events.csv");
        for (String line : lines.subList(1, lines.size())) {
            String[] fields = line.split(",");
            named.get(fields[0]).events.put(fields[1], fields[2]);
        }
        lines = read("inventory.csv");
        for (String line : lines.subList(1, lines.size())) {
            String[] fields = line.split(",");
            SeriesData data = named.get(fields[0]);
            data.onHand = Integer.parseInt(fields[1]);
            data.lead = Integer.parseInt(fields[2]);
            data.review = Integer.parseInt(fields[3]);
            data.service = Double.parseDouble(fields[4]);
        }
        for (String line : read("params.txt")) {
            String[] fields = line.split(" ");
            settings.put(fields[0], Arrays.copyOfRange(fields, 1, fields.length));
        }
    }
    int integer(String key) {
        return Integer.parseInt(settings.get(key)[0]);
    }
    double number(String key) {
        return Double.parseDouble(settings.get(key)[0]);
    }
    double[] candidates(String key) {
        String[] values = settings.get(key);
        double[] result = new double[values.length];
        for (int i = 0; i < values.length; i++)
            result[i] = Double.parseDouble(values[i]);
        return result;
    }
    static List<String> read(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static String nextMonth(String period) {
        return YearMonth.parse(period).plusMonths(1).toString();
    }
    static String real(double value) {
        if (Double.isNaN(value))
            return "NA";
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
