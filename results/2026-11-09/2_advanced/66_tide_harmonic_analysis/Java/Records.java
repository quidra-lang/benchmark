import java.nio.file.*;
import java.time.*;
import java.time.format.*;
import java.time.temporal.*;
import java.util.*;
final class Records {
    static final DateTimeFormatter FORMAT =
        DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm", Locale.ROOT);
    record Constituent(String name, double speed) {}
    static final class Station {
        String code, name;
        int rows;
        TreeMap<Integer, Integer> values = new TreeMap<>();
        Station(String code, String name) {
            this.code = code;
            this.name = name;
        }
    }
    static final class Settings {
        LocalDateTime epoch, start;
        int ts;
        Map<String, List<String>> values = new HashMap<>();
        int integer(String key, int index) { return Integer.parseInt(values.get(key).get(index)); }
        double real(String key, int index) {
            return Double.parseDouble(values.get(key).get(index));
        }
        String text(String key, int index) { return values.get(key).get(index); }
    }
    record Data(Settings settings, List<Station> stations, List<Constituent> constituents) {}
    static LocalDateTime parse(String text) { return LocalDateTime.parse(text, FORMAT); }
    static int hours(LocalDateTime epoch, LocalDateTime value) {
        return (int)ChronoUnit.HOURS.between(epoch, value);
    }
    static String hour(Settings s, int t) { return s.epoch.plusHours(t).format(FORMAT); }
    static String minute(Settings s, int m) { return s.epoch.plusMinutes(m).format(FORMAT); }
    static LocalDate dateHour(Settings s, int t) { return s.epoch.plusHours(t).toLocalDate(); }
    static LocalDate dateMinute(Settings s, int m) { return s.epoch.plusMinutes(m).toLocalDate(); }
    static int noon(Settings s, LocalDate date) { return hours(s.epoch, date.atTime(12, 0)); }
    static Data read() throws Exception {
        Settings s = new Settings();
        List<Station> stations = new ArrayList<>();
        List<String> lines = Files.readAllLines(Path.of("input", "params.txt"));
        s.epoch = parse(lines.getFirst().substring(6));
        for (int i = 1; i < lines.size(); i++) {
            String line = lines.get(i);
            String[] w = line.split(" ");
            if (w[0].equals("station"))
                stations.add(new Station(w[1], line.substring(12)));
            else
                s.values.put(w[0], new ArrayList<>(Arrays.asList(w).subList(1, w.length)));
        }
        s.start = parse(s.text("predict", 0) + " " + s.text("predict", 1));
        s.ts = hours(s.epoch, s.start);
        List<Constituent> constituents = new ArrayList<>();
        lines = Files.readAllLines(Path.of("input", "constituents.txt"));
        for (int i = 1; i < lines.size(); i++) {
            String[] w = lines.get(i).split(" ");
            constituents.add(new Constituent(w[0], Double.parseDouble(w[1])));
        }
        lines = Files.readAllLines(Path.of("input", "observations.csv"));
        for (int i = 1; i < lines.size(); i++) {
            String[] w = lines.get(i).split(",");
            Station station = null;
            for (Station candidate : stations)
                if (candidate.code.equals(w[0]))
                    station = candidate;
            int t = hours(s.epoch, parse(w[1]));
            station.values.put(t,
                               w[2].equals("NA") ? null : Integer.valueOf(w[2].replace(".", "")));
            station.rows++;
        }
        return new Data(s, stations, constituents);
    }
}
