import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.function.Function;
import java.util.stream.Collectors;

public class Main {
    private static final List<String> METHODS =
        List.of("GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS");
    private static final List<String> REASONS =
        List.of("fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency");
    private static final List<String> CLASSES = List.of("1xx", "2xx", "3xx", "4xx", "5xx");
    private static final List<String> KEYS = List.of("METHOD", "STATUS", "IP", "PATH");
    private static final LocalDate EPOCH = LocalDate.of(2000, 1, 1);
    private static final Map<String, List<String>> FORMS = Map.ofEntries(
        Map.entry("SUMMARY", List.of()), Map.entry("MALFORMED", List.of()),
        Map.entry("STATUS", List.of()), Map.entry("METHODS", List.of()),
        Map.entry("TOP", List.of("kind", "limit")), Map.entry("HOURLY", List.of()),
        Map.entry("TIMELINE", List.of("minutes")), Map.entry("BANDWIDTH", List.of()),
        Map.entry("VISITORS", List.of()), Map.entry("LATENCY", List.of("path")),
        Map.entry("HISTOGRAM", List.of("width")), Map.entry("APDEX", List.of("threshold")),
        Map.entry("ERRORS", List.of()), Map.entry("SLOWEST", List.of("limit")),
        Map.entry("SESSIONS", List.of("ip", "minutes")),
        Map.entry("BURST", List.of("length", "times")),
        Map.entry("PEAK", List.of("length")), Map.entry("GAPS", List.of("length")),
        Map.entry("IP", List.of("ip")), Map.entry("RANGE", List.of("date", "time", "date", "time")),
        Map.entry("FILTER", List.of("key", "value")),
        Map.entry("UNFILTER", List.of("subject")), Map.entry("RESET", List.of()),
        Map.entry("STATE", List.of())
    );
    private static final Set<String> REQUIRED = Set.of(
        "STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH",
        "VISITORS", "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS"
    );
    private static final Map<String, int[]> RANGES = Map.of(
        "limit", new int[]{1, 100}, "minutes", new int[]{1, 1440},
        "width", new int[]{1, 100000}, "threshold", new int[]{1, 100000},
        "length", new int[]{1, 86400}, "times", new int[]{1, 1000}
    );
    private static final Map<String, String> ERRORS = Map.ofEntries(
        Map.entry("limit", "invalid number"), Map.entry("minutes", "invalid number"),
        Map.entry("width", "invalid number"), Map.entry("threshold", "invalid number"),
        Map.entry("length", "invalid number"), Map.entry("times", "invalid number"),
        Map.entry("kind", "invalid kind"), Map.entry("path", "invalid path"),
        Map.entry("ip", "invalid ip"), Map.entry("date", "invalid timestamp"),
        Map.entry("time", "invalid timestamp"), Map.entry("key", "invalid key"),
        Map.entry("subject", "invalid key"), Map.entry("value", "invalid value")
    );

    private static class QueryError extends RuntimeException {
        QueryError(String message) { super(message); }
    }

    private static void check(boolean ok, String reason) {
        if (!ok) throw new QueryError(reason);
    }

    private static List<String> tokens(String line) {
        String text = line.trim();
        return text.isEmpty() ? List.of() : Arrays.asList(text.split("\\s+"));
    }

    private static boolean digits(String text) {
        return text.matches("[0-9]+");
    }

    private static boolean canonical(String text, int maximum) {
        return text.length() > 0 && text.length() <= maximum && digits(text) &&
            (text.length() == 1 || text.charAt(0) != '0');
    }

    private static boolean validDate(String text) {
        if (!text.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}")) return false;
        int year = Integer.parseInt(text.substring(0, 4));
        if (year < 2000 || year > 2059) return false;
        try {
            LocalDate.parse(text);
            return true;
        } catch (DateTimeParseException error) {
            return false;
        }
    }

    private static boolean validTime(String text) {
        return text.matches("[0-9]{2}:[0-9]{2}:[0-9]{2}") &&
            Integer.parseInt(text.substring(0, 2)) < 24 &&
            Integer.parseInt(text.substring(3, 5)) < 60 &&
            Integer.parseInt(text.substring(6, 8)) < 60;
    }

    private static boolean validIp(String ip) {
        String[] parts = ip.split("\\.", -1);
        if (parts.length != 4) return false;
        for (String part : parts) {
            if (!canonical(part, 3) || Integer.parseInt(part) > 255) return false;
        }
        return true;
    }

    private static boolean validStatus(String text) {
        return text.matches("[0-9]{3}") &&
            Integer.parseInt(text) >= 100 && Integer.parseInt(text) <= 599;
    }

    private static boolean filterValue(String key, String value) {
        return switch (key) {
            case "METHOD" -> METHODS.contains(value);
            case "STATUS" -> CLASSES.contains(value) || validStatus(value);
            case "IP" -> validIp(value);
            default -> value.startsWith("/");
        };
    }

    private static boolean validArgument(String kind, String value, List<String> args) {
        int[] range = RANGES.get(kind);
        if (range != null) {
            if (!canonical(value, 6)) return false;
            int number = Integer.parseInt(value);
            return number >= range[0] && number <= range[1];
        }
        return switch (kind) {
            case "kind" -> value.equals("PATHS") || value.equals("IPS");
            case "path" -> value.startsWith("/");
            case "ip" -> validIp(value);
            case "date" -> validDate(value);
            case "time" -> validTime(value);
            case "key" -> KEYS.contains(value);
            case "subject" -> value.equals("RANGE") || KEYS.contains(value);
            default -> filterValue(args.get(0), value);
        };
    }

    private static String malformedReason(List<String> fields) {
        if (fields.size() != 8) return "fields";
        if (!validDate(fields.get(0))) return "date";
        if (!validTime(fields.get(1))) return "time";
        if (!validIp(fields.get(2))) return "ip";
        if (!METHODS.contains(fields.get(3))) return "method";
        if (!fields.get(4).startsWith("/")) return "path";
        if (!validStatus(fields.get(5))) return "status";
        if (!canonical(fields.get(6), 8)) return "bytes";
        if (!canonical(fields.get(7), 6)) return "latency";
        return null;
    }

    private static long secondsOf(String date, String time) {
        long days = ChronoUnit.DAYS.between(EPOCH, LocalDate.parse(date));
        return days * 86400 +
            Integer.parseInt(time.substring(0, 2)) * 3600 +
            Integer.parseInt(time.substring(3, 5)) * 60 +
            Integer.parseInt(time.substring(6, 8));
    }

    private static String intervalLabel(long seconds) {
        LocalDate date = EPOCH.plusDays(seconds / 86400);
        long minutes = seconds % 86400 / 60;
        return String.format(Locale.ROOT, "%s %02d:%02d",
            date, minutes / 60, minutes % 60);
    }

    private static String normalizePath(String raw) {
        String path = raw.split("\\?", 2)[0];
        List<String> parts = new ArrayList<>();
        for (String item : path.split("/", -1)) {
            if (item.equals("..")) {
                if (!parts.isEmpty()) parts.removeLast();
            } else if (!item.isEmpty() && !item.equals(".")) {
                parts.add(item);
            }
        }
        for (int i = 0; i < parts.size(); i++) {
            String item = parts.get(i);
            if (digits(item)) parts.set(i, "{id}");
            else if (item.length() >= 8 && item.matches("[0-9a-f]+") &&
                     item.matches(".*[0-9].*")) parts.set(i, "{hex}");
        }
        return "/" + String.join("/", parts);
    }

    private static int compareIp(String a, String b) {
        String[] left = a.split("\\."), right = b.split("\\.");
        for (int i = 0; i < 4; i++) {
            int n = Integer.compare(Integer.parseInt(left[i]), Integer.parseInt(right[i]));
            if (n != 0) return n;
        }
        return 0;
    }

    private static boolean statusMatches(String filter, int status) {
        return CLASSES.contains(filter) ?
            status / 100 == filter.charAt(0) - '0' : status == Integer.parseInt(filter);
    }

    private static String decimal(long numerator, long denominator, int places) {
        long scale = switch (places) { case 1 -> 10; case 2 -> 100; default -> 1000; };
        long number = numerator * scale / denominator;
        return number / scale + "." +
            String.format(Locale.ROOT, "%0" + places + "d", number % scale);
    }

    private static String percent(int part, int whole) {
        return decimal(part * 100L, whole, 2) + "%";
    }

    private static String bar(int count, int maximum) {
        return "#".repeat((count * 30 + maximum - 1) / maximum);
    }

    private static String bytesText(long bytes) {
        if (bytes >= 1073741824) return decimal(bytes, 1073741824, 1) + "GB";
        if (bytes >= 1048576) return decimal(bytes, 1048576, 1) + "MB";
        if (bytes >= 1024) return decimal(bytes, 1024, 1) + "KB";
        return bytes + "B";
    }

    private static Map<String, Integer> counts(Collection<String> values) {
        Map<String, Integer> result = new HashMap<>();
        for (String item : values) result.merge(item, 1, Integer::sum);
        return result;
    }

    private static List<String> byCount(Map<String, Integer> counts, Comparator<String> tie) {
        List<String> result = new ArrayList<>(counts.keySet());
        result.sort((a, b) -> {
            int n = Integer.compare(counts.get(b), counts.get(a));
            return n != 0 ? n : tie.compare(a, b);
        });
        return result;
    }

    private static List<String> byCount(Map<String, Integer> counts) {
        return byCount(counts, String::compareTo);
    }

    private static class Row {
        final int line, hour, status, latency;
        final String date, timestamp, ip, method, path;
        final long seconds, bytes;

        Row(int line, List<String> parts) {
            this.line = line;
            this.date = parts.get(0);
            this.timestamp = date + " " + parts.get(1);
            this.hour = Integer.parseInt(parts.get(1).substring(0, 2));
            this.seconds = secondsOf(date, parts.get(1));
            this.ip = parts.get(2);
            this.method = parts.get(3);
            this.path = normalizePath(parts.get(4));
            this.status = Integer.parseInt(parts.get(5));
            this.bytes = Long.parseLong(parts.get(6));
            this.latency = Integer.parseInt(parts.get(7));
        }
    }

    private static Map<String, List<Row>> groups(Collection<Row> rows, Function<Row, String> key) {
        Map<String, List<Row>> result = new HashMap<>();
        for (Row row : rows) {
            result.computeIfAbsent(key.apply(row), k -> new ArrayList<>()).add(row);
        }
        return result;
    }

    private static int[] classCounts(Collection<Row> rows) {
        int[] counts = new int[5];
        for (Row row : rows) counts[row.status / 100 - 1]++;
        return counts;
    }

    private record Buckets(long first, int[] counts) { }

    private static Buckets buckets(List<Long> values) {
        long first = Collections.min(values);
        long last = Collections.max(values);
        check(last - first + 1 <= 60, "too many buckets");
        int[] counts = new int[(int)(last - first + 1)];
        for (long value : values) counts[(int)(value - first)]++;
        return new Buckets(first, counts);
    }

    private static int percentile(List<Integer> values, int rank) {
        return values.get((rank * values.size() + 99) / 100 - 1);
    }

    private record Peak(int size, Row start, Row end) { }

    private static Peak peak(List<Row> rows, int width) {
        int first = 0, size = 0, start = 0, end = 0;
        for (int last = 0; last < rows.size(); last++) {
            while (rows.get(last).seconds - rows.get(first).seconds >= width) first++;
            if (last - first + 1 > size) {
                size = last - first + 1;
                start = first;
                end = last;
            }
        }
        return new Peak(size, rows.get(start), rows.get(end));
    }

    private record Apdex(int count, int satisfied, int tolerating, int frustrated,
                         long points, long total, String notation, String rating) { }

    private static Apdex apdex(List<Row> rows, int threshold) {
        int satisfied = 0, tolerating = 0;
        for (Row row : rows) {
            if (row.status >= 500) continue;
            if (row.latency <= threshold) satisfied++;
            else if (row.latency <= 4 * threshold) tolerating++;
        }
        int n = rows.size();
        long points = satisfied * 2L + tolerating, total = n * 2L;
        String rating = points * 100 >= total * 94 ? "excellent" :
            points * 100 >= total * 85 ? "good" :
            points * 100 >= total * 70 ? "fair" :
            points * 100 >= total * 50 ? "poor" : "unacceptable";
        return new Apdex(n, satisfied, tolerating, n - satisfied - tolerating,
                         points, total, decimal(points, total, 3), rating);
    }

    private static class Analyzer {
        private final List<Row> records = new ArrayList<>();
        private final List<Map.Entry<Integer, String>> malformed = new ArrayList<>();
        private final int lineCount;
        private final Map<String, String> filters = new HashMap<>();
        private Long from, to;
        private String fromLabel, toLabel;
        final List<String> output = new ArrayList<>();

        Analyzer(List<String> lines) {
            lineCount = lines.size();
            for (int i = 0; i < lines.size(); i++) {
                List<String> fields = tokens(lines.get(i));
                String reason = malformedReason(fields);
                if (reason != null) malformed.add(Map.entry(i + 1, reason));
                else records.add(new Row(i + 1, fields));
            }
            records.sort(Comparator.comparingLong((Row r) -> r.seconds)
                .thenComparingInt(r -> r.line));
            for (String key : KEYS) filters.put(key, null);
        }

        private void emit(Object... values) {
            output.add(Arrays.stream(values).map(String::valueOf)
                .collect(Collectors.joining(" ")));
        }

        private List<Row> selected() {
            return records.stream().filter(r ->
                (from == null || r.seconds >= from && r.seconds <= to) &&
                (filters.get("METHOD") == null || r.method.equals(filters.get("METHOD"))) &&
                (filters.get("STATUS") == null ||
                    statusMatches(filters.get("STATUS"), r.status)) &&
                (filters.get("IP") == null || r.ip.equals(filters.get("IP"))) &&
                (filters.get("PATH") == null || r.path.equals(filters.get("PATH"))))
                .collect(Collectors.toList());
        }

        private void barLine(String label, int count, int maximum) {
            if (count == 0) emit(label, count);
            else emit(label, count, bar(count, maximum));
        }

        void execute(String line) {
            List<String> parts = tokens(line);
            String name = parts.isEmpty() ? "" : parts.get(0);
            List<String> args = parts.isEmpty() ? List.of() : parts.subList(1, parts.size());
            try {
                check(FORMS.containsKey(name), "unknown query");
                List<String> form = FORMS.get(name);
                boolean optional = (name.equals("LATENCY") || name.equals("SESSIONS")) &&
                    args.size() == form.size() - 1;
                check(args.size() == form.size() || optional, "wrong arguments");
                for (int i = 0; i < args.size(); i++) {
                    check(validArgument(form.get(i), args.get(i), args), ERRORS.get(form.get(i)));
                }
                List<Row> rows = selected();
                if (REQUIRED.contains(name) && rows.isEmpty()) {
                    emit(name, "no records");
                    return;
                }
                run(name, args, rows);
            } catch (QueryError error) {
                emit("ERROR", error.getMessage());
            }
        }

        private void run(String name, List<String> a, List<Row> rows) {
            switch (name) {
                case "SUMMARY" -> {
                    emit("SUMMARY", "lines", lineCount, "valid", records.size(),
                        "malformed", malformed.size());
                    emit("requests", rows.size(), "bytes",
                        rows.stream().mapToLong(r -> r.bytes).sum(),
                        "ips", rows.stream().map(r -> r.ip).distinct().count(),
                        "paths", rows.stream().map(r -> r.path).distinct().count());
                    if (rows.isEmpty()) emit("span", "none");
                    else emit("span", rows.getFirst().timestamp, rows.getLast().timestamp,
                        rows.getLast().seconds - rows.getFirst().seconds);
                }
                case "MALFORMED" -> {
                    emit("MALFORMED", malformed.size());
                    for (String reason : REASONS) {
                        List<Integer> indices = malformed.stream()
                            .filter(x -> x.getValue().equals(reason))
                            .map(Map.Entry::getKey).toList();
                        if (!indices.isEmpty()) {
                            List<Object> parts = new ArrayList<>();
                            parts.add(reason);
                            parts.add(indices.size());
                            parts.addAll(indices);
                            emit(parts.toArray());
                        }
                    }
                }
                case "STATUS" -> {
                    emit("STATUS", rows.size());
                    int[] classes = classCounts(rows);
                    for (int i = 0; i < 5; i++)
                        emit(CLASSES.get(i), classes[i], percent(classes[i], rows.size()));
                    Map<Integer, Long> status = rows.stream().collect(
                        Collectors.groupingBy(r -> r.status, Collectors.counting()));
                    for (int code : new TreeSet<>(status.keySet())) {
                        int count = status.get(code).intValue();
                        emit(code, count, percent(count, rows.size()));
                    }
                }
                case "METHODS" -> {
                    Map<String, Integer> counts = counts(
                        rows.stream().map(r -> r.method).toList());
                    emit("METHODS", rows.size());
                    for (String method : byCount(counts))
                        emit(method, counts.get(method), percent(counts.get(method), rows.size()));
                }
                case "TOP" -> {
                    String kind = a.get(0);
                    Map<String, Integer> counts = counts(rows.stream()
                        .map(r -> kind.equals("PATHS") ? r.path : r.ip).toList());
                    List<String> ranked = byCount(counts,
                        kind.equals("IPS") ? Main::compareIp : String::compareTo);
                    int shown = Math.min(Integer.parseInt(a.get(1)), ranked.size());
                    emit("TOP", kind, shown, "of", ranked.size());
                    int rank = 0;
                    for (int i = 0; i < shown; i++) {
                        if (i == 0 || !counts.get(ranked.get(i)).equals(counts.get(ranked.get(i-1))))
                            rank = i + 1;
                        String value = ranked.get(i);
                        emit(rank, value, counts.get(value), percent(counts.get(value), rows.size()));
                    }
                }
                case "HOURLY" -> {
                    int[] counts = new int[24];
                    for (Row r : rows) counts[r.hour]++;
                    int maximum = Arrays.stream(counts).max().orElseThrow();
                    int first = 0;
                    while (counts[first] != maximum) first++;
                    emit("HOURLY", rows.size(), "peak",
                        String.format(Locale.ROOT, "%02d", first), maximum);
                    for (int h = 0; h < 24; h++)
                        barLine(String.format(Locale.ROOT, "%02d", h), counts[h], maximum);
                }
                case "TIMELINE" -> {
                    int minutes = Integer.parseInt(a.get(0));
                    long width = minutes * 60L;
                    Buckets buckets = buckets(rows.stream().map(r -> r.seconds / width).toList());
                    emit("TIMELINE", minutes, buckets.counts.length);
                    int maximum = Arrays.stream(buckets.counts).max().orElseThrow();
                    for (int i = 0; i < buckets.counts.length; i++)
                        barLine(intervalLabel((buckets.first + i) * width), buckets.counts[i], maximum);
                }
                case "BANDWIDTH" -> {
                    Map<String, List<Row>> days = groups(rows, r -> r.date);
                    long volume = rows.stream().mapToLong(r -> r.bytes).sum();
                    emit("BANDWIDTH", days.size(), volume, bytesText(volume));
                    for (String date : new TreeSet<>(days.keySet())) {
                        List<Row> part = days.get(date);
                        long bytes = part.stream().mapToLong(r -> r.bytes).sum();
                        emit(date, part.size(), bytes, bytesText(bytes));
                    }
                }
                case "VISITORS" -> {
                    Map<String, String> first = new HashMap<>();
                    for (Row r : rows) {
                        if (!first.containsKey(r.ip) || r.date.compareTo(first.get(r.ip)) < 0)
                            first.put(r.ip, r.date);
                    }
                    Map<String, List<Row>> days = groups(rows, r -> r.date);
                    emit("VISITORS", days.size(), first.size());
                    for (String date : new TreeSet<>(days.keySet())) {
                        Set<String> ips = days.get(date).stream()
                            .map(r -> r.ip).collect(Collectors.toSet());
                        long fresh = ips.stream().filter(ip -> first.get(ip).equals(date)).count();
                        emit(date, "unique", ips.size(), "new", fresh,
                            "returning", ips.size() - fresh);
                    }
                }
                case "LATENCY" -> {
                    String label = a.isEmpty() ? "all" : normalizePath(a.get(0));
                    List<Row> chosen = a.isEmpty() ? rows : rows.stream()
                        .filter(r -> r.path.equals(label)).toList();
                    if (chosen.isEmpty()) {
                        emit("LATENCY", "no records");
                        break;
                    }
                    List<Integer> numbers = chosen.stream().map(r -> r.latency)
                        .sorted().toList();
                    int n = numbers.size(), trim = n / 10;
                    List<Integer> trimmed = numbers.subList(trim, n-trim);
                    long sum = numbers.stream().mapToLong(i -> i).sum();
                    long trimmedSum = trimmed.stream().mapToLong(i -> i).sum();
                    emit("LATENCY", label, "count", n, "min", numbers.getFirst(),
                        "p50", percentile(numbers, 50), "p90", percentile(numbers, 90),
                        "p99", percentile(numbers, 99), "max", numbers.getLast(),
                        "mean", decimal(sum, n, 2),
                        "trimmed", decimal(trimmedSum, trimmed.size(), 2));
                }
                case "HISTOGRAM" -> {
                    int width = Integer.parseInt(a.get(0));
                    Buckets buckets = buckets(rows.stream()
                        .map(r -> (long)(r.latency / width)).toList());
                    emit("HISTOGRAM", width, buckets.counts.length);
                    int maximum = Arrays.stream(buckets.counts).max().orElseThrow();
                    for (int i = 0; i < buckets.counts.length; i++) {
                        long lower = (buckets.first + i) * width;
                        barLine(lower + "-" + (lower + width - 1), buckets.counts[i], maximum);
                    }
                }
                case "APDEX" -> {
                    int threshold = Integer.parseInt(a.get(0));
                    Apdex overall = apdex(rows, threshold);
                    emit("APDEX", threshold, overall.notation, overall.rating,
                        "satisfied", overall.satisfied, "tolerating", overall.tolerating,
                        "frustrated", overall.frustrated);
                    record PathScore(String path, Apdex score) { }
                    List<PathScore> paths = groups(rows, r -> r.path).entrySet().stream()
                        .map(e -> new PathScore(e.getKey(), apdex(e.getValue(), threshold)))
                        .collect(Collectors.toCollection(ArrayList::new));
                    paths.sort((x, y) -> {
                        int n = Long.compare(x.score.points * y.score.total,
                            y.score.points * x.score.total);
                        if (n != 0) return n;
                        n = Integer.compare(y.score.count, x.score.count);
                        return n != 0 ? n : x.path.compareTo(y.path);
                    });
                    for (PathScore p : paths)
                        emit(p.path, p.score.notation, p.score.rating, p.score.count);
                }
                case "ERRORS" -> {
                    long failed = rows.stream().filter(r -> r.status >= 400).count();
                    emit("ERRORS", failed, "of", rows.size(), percent((int)failed, rows.size()));
                    record ErrorPath(String path, int count, int client, int server) { }
                    List<ErrorPath> paths = new ArrayList<>();
                    for (var entry : groups(rows, r -> r.path).entrySet()) {
                        List<Row> group = entry.getValue();
                        int client = (int)group.stream().filter(r -> r.status / 100 == 4).count();
                        int server = (int)group.stream().filter(r -> r.status / 100 == 5).count();
                        if (client + server > 0)
                            paths.add(new ErrorPath(entry.getKey(), group.size(), client, server));
                    }
                    paths.sort((x, y) -> {
                        long af = x.client + x.server, bf = y.client + y.server;
                        int c = Long.compare(bf * x.count, af * y.count);
                        if (c != 0) return c;
                        c = Long.compare(bf, af);
                        return c != 0 ? c : x.path.compareTo(y.path);
                    });
                    for (ErrorPath p : paths)
                        emit(p.path, p.count, p.client, p.server,
                            percent(p.client + p.server, p.count));
                }
                case "SLOWEST" -> {
                    record Endpoint(String method, String path, int count, long sum, int max) { }
                    List<Endpoint> endpoints = new ArrayList<>();
                    for (var entry : groups(rows, r -> r.method + "\u0001" + r.path).entrySet()) {
                        String[] pair = entry.getKey().split("\u0001", 2);
                        List<Row> group = entry.getValue();
                        endpoints.add(new Endpoint(pair[0], pair[1], group.size(),
                            group.stream().mapToLong(r -> r.latency).sum(),
                            group.stream().mapToInt(r -> r.latency).max().orElseThrow()));
                    }
                    endpoints.sort((x, y) -> {
                        int n = Long.compare(y.sum * x.count, x.sum * y.count);
                        if (n != 0) return n;
                        n = Integer.compare(y.max, x.max);
                        if (n != 0) return n;
                        n = x.path.compareTo(y.path);
                        return n != 0 ? n : x.method.compareTo(y.method);
                    });
                    int limit = Math.min(Integer.parseInt(a.get(0)), endpoints.size());
                    emit("SLOWEST", limit, "of", endpoints.size());
                    for (int i = 0; i < limit; i++) {
                        Endpoint e = endpoints.get(i);
                        emit(i+1, e.method, e.path, "count", e.count,
                            "avg", decimal(e.sum, e.count, 2), "max", e.max);
                    }
                }
                case "SESSIONS" -> {
                    String ip = a.get(0);
                    int minutes = a.size() == 2 ? Integer.parseInt(a.get(1)) : 30;
                    List<Row> chosen = rows.stream().filter(r -> r.ip.equals(ip)).toList();
                    if (chosen.isEmpty()) {
                        emit("SESSIONS", "no records");
                        break;
                    }
                    List<List<Row>> sessions = new ArrayList<>();
                    sessions.add(new ArrayList<>(List.of(chosen.getFirst())));
                    for (int i = 1; i < chosen.size(); i++) {
                        Row next = chosen.get(i);
                        if (next.seconds - chosen.get(i-1).seconds <= minutes * 60L)
                            sessions.getLast().add(next);
                        else sessions.add(new ArrayList<>(List.of(next)));
                    }
                    long duration = 0;
                    for (List<Row> session : sessions)
                        duration += session.getLast().seconds - session.getFirst().seconds;
                    emit("SESSIONS", ip, "timeout", minutes, "count", sessions.size(),
                        "requests", chosen.size(),
                        "avg_duration", decimal(duration, sessions.size(), 1),
                        "avg_requests", decimal(chosen.size(), sessions.size(), 1));
                    for (int i = 0; i < sessions.size(); i++) {
                        List<Row> session = sessions.get(i);
                        emit(i + 1, session.getFirst().timestamp, session.getLast().timestamp,
                            session.getLast().seconds - session.getFirst().seconds,
                            session.size(), session.stream().map(r -> r.path).distinct().count());
                    }
                }
                case "BURST" -> {
                    int length = Integer.parseInt(a.get(0));
                    int threshold = Integer.parseInt(a.get(1));
                    record Burst(String ip, Peak window) { }
                    List<Burst> bursts = new ArrayList<>();
                    Map<String, List<Row>> failed = groups(
                        rows.stream().filter(r -> r.status >= 400).toList(), r -> r.ip);
                    for (var group : failed.entrySet()) {
                        Peak window = peak(group.getValue(), length);
                        if (window.size >= threshold) bursts.add(new Burst(group.getKey(), window));
                    }
                    bursts.sort((x, y) -> {
                        int n = Integer.compare(y.window.size, x.window.size);
                        return n != 0 ? n : compareIp(x.ip, y.ip);
                    });
                    emit("BURST", length, threshold, bursts.size());
                    for (Burst b : bursts)
                        emit(b.ip, b.window.size, b.window.start.timestamp, b.window.end.timestamp);
                }
                case "PEAK" -> {
                    int length = Integer.parseInt(a.get(0));
                    Peak window = peak(rows, length);
                    emit("PEAK", length, window.size, window.start.timestamp, window.end.timestamp);
                }
                case "GAPS" -> {
                    int length = Integer.parseInt(a.get(0));
                    List<Map.Entry<Row, Row>> gaps = new ArrayList<>();
                    for (int i = 1; i < rows.size(); i++) {
                        if (rows.get(i).seconds - rows.get(i-1).seconds >= length)
                            gaps.add(Map.entry(rows.get(i-1), rows.get(i)));
                    }
                    emit("GAPS", length, gaps.size());
                    for (var gap : gaps)
                        emit(gap.getKey().timestamp, gap.getValue().timestamp,
                            gap.getValue().seconds - gap.getKey().seconds);
                }
                case "IP" -> {
                    String ip = a.get(0);
                    List<Row> found = rows.stream().filter(r -> r.ip.equals(ip)).toList();
                    if (found.isEmpty()) {
                        emit("IP", "no records");
                        break;
                    }
                    Map<String, Integer> paths = counts(
                        found.stream().map(r -> r.path).toList());
                    emit("IP", ip, "requests", found.size(), "bytes",
                        found.stream().mapToLong(r -> r.bytes).sum(),
                        "errors", found.stream().filter(r -> r.status >= 400).count(),
                        "paths", paths.size());
                    emit("first", found.getFirst().timestamp, "last", found.getLast().timestamp);
                    Map<String, Integer> methods = counts(
                        found.stream().map(r -> r.method).toList());
                    List<Object> methodLine = new ArrayList<>(List.of("methods"));
                    for (String method : byCount(methods)) {
                        methodLine.add(method);
                        methodLine.add(methods.get(method));
                    }
                    emit(methodLine.toArray());
                    List<Object> classLine = new ArrayList<>(List.of("classes"));
                    int[] classes = classCounts(found);
                    for (int i = 0; i < 5; i++) {
                        classLine.add(CLASSES.get(i));
                        classLine.add(classes[i]);
                    }
                    emit(classLine.toArray());
                    for (String path : byCount(paths).stream().limit(3).toList())
                        emit("path", path, paths.get(path));
                }
                case "RANGE" -> {
                    long start = secondsOf(a.get(0), a.get(1));
                    long end = secondsOf(a.get(2), a.get(3));
                    check(start <= end, "invalid range");
                    from = start;
                    to = end;
                    fromLabel = a.get(0) + " " + a.get(1);
                    toLabel = a.get(2) + " " + a.get(3);
                    emit("RANGE", fromLabel, toLabel, "active", selected().size());
                }
                case "FILTER" -> {
                    String key = a.get(0);
                    String value = key.equals("PATH") ? normalizePath(a.get(1)) : a.get(1);
                    filters.put(key, value);
                    emit("FILTER", key, value, "active", selected().size());
                }
                case "UNFILTER" -> {
                    String key = a.get(0);
                    if (key.equals("RANGE")) {
                        check(from != null, "not filtered");
                        from = null;
                        to = null;
                        fromLabel = null;
                        toLabel = null;
                    } else {
                        check(filters.get(key) != null, "not filtered");
                        filters.put(key, null);
                    }
                    emit("UNFILTER", key, "active", selected().size());
                }
                case "RESET" -> {
                    from = null;
                    to = null;
                    fromLabel = null;
                    toLabel = null;
                    for (String key : KEYS) filters.put(key, null);
                    emit("RESET", "active", selected().size());
                }
                case "STATE" -> {
                    List<Object> parts = new ArrayList<>();
                    parts.addAll(List.of("STATE", "active", rows.size(), "range"));
                    parts.add(from == null ? "-" : fromLabel + " " + toLabel);
                    for (String key : KEYS) {
                        parts.add(key.toLowerCase(Locale.ROOT));
                        parts.add(filters.get(key) == null ? "-" : filters.get(key));
                    }
                    emit(parts.toArray());
                }
            }
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(
            new InputStreamReader(System.in, StandardCharsets.UTF_8));
        List<String> logs = new ArrayList<>();
        List<String> queries = new ArrayList<>();
        String line;
        boolean readingQueries = false;
        while ((line = input.readLine()) != null) {
            if (!readingQueries) {
                if (line.equals("---")) readingQueries = true;
                else logs.add(line);
            } else if (line.equals("END")) break;
            else queries.add(line);
        }
        Analyzer analyzer = new Analyzer(logs);
        for (String query : queries) analyzer.execute(query);
        if (!analyzer.output.isEmpty()) System.out.println(String.join("\n", analyzer.output));
    }
}
