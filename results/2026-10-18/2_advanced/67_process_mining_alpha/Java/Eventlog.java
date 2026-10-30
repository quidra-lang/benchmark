import java.nio.file.*;
import java.util.*;
final class Eventlog {
    record Row(int line, String caseId, String activity, String timestamp, String resource) {}
    record Event(int line, String caseId, String activity, String timestamp, String resource,
                 int time) {}
    static final class Case {
        String id;
        List<Event> events;
        List<String> trace;
        int duration;
        Case(String id, List<Event> events) {
            this.id = id;
            this.events = new ArrayList<>(events);
            this.events.sort(Comparator.comparingInt(Event::time).thenComparingInt(Event::line));
            List<String> names = new ArrayList<>();
            for (Event event : this.events)
                names.add(event.activity());
            trace = List.copyOf(names);
            duration = this.events.getLast().time() - this.events.getFirst().time();
        }
    }
    record Input(List<Row> rows, Map<String, String> parameters) {}
    static Input read() throws Exception {
        List<String> lines = Files.readAllLines(Path.of("input", "eventlog.csv"));
        List<Row> rows = new ArrayList<>();
        for (int i = 1; i < lines.size(); i++) {
            String[] w = lines.get(i).split(",");
            rows.add(new Row(i + 1, w[0], w[1], w[2], w[3]));
        }
        Map<String, String> parameters = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input", "params.txt"))) {
            String[] w = line.split(" ");
            parameters.put(w[0], w[1]);
        }
        return new Input(rows, parameters);
    }
    static int timestamp(String value) {
        int[] days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
        int month = Integer.parseInt(value.substring(5, 7)),
            day = Integer.parseInt(value.substring(8, 10)),
            hour = Integer.parseInt(value.substring(11, 13)),
            minute = Integer.parseInt(value.substring(14, 16));
        if (month < 1 || month > 12 || day < 1 || day > days[month - 1] || hour > 23 || minute > 59)
            return -1;
        int prior = 0;
        for (int m = 0; m < month - 1; m++)
            prior += days[m];
        return ((prior + day - 1) * 24 + hour) * 60 + minute;
    }
    static List<Case> group(List<Event> events) {
        TreeMap<String, List<Event>> grouped = new TreeMap<>();
        for (Event event : events)
            grouped.computeIfAbsent(event.caseId(), key -> new ArrayList<>()).add(event);
        List<Case> cases = new ArrayList<>();
        for (var entry : grouped.entrySet())
            cases.add(new Case(entry.getKey(), entry.getValue()));
        return cases;
    }
    static Report.Fraction median(List<Integer> input) {
        List<Integer> values = new ArrayList<>(input);
        values.sort(Integer::compare);
        int n = values.size();
        return n % 2 == 1 ? new Report.Fraction(values.get(n / 2), 1)
                          : new Report.Fraction((long)values.get(n / 2 - 1) + values.get(n / 2), 2);
    }
}
