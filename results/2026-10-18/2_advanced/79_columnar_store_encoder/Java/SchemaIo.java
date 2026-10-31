import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.*;
final class SchemaIo {
    static final List<String> TYPES = List.of("INT", "STRING", "BOOL", "DATE");
    sealed interface Value permits NumberValue, TextValue, BoolValue, Unknown {}
    record NumberValue(long value) implements Value {}
    record TextValue(String value) implements Value {}
    record BoolValue(boolean value) implements Value {}
    enum Unknown implements Value { CELL }
    record Column(String name, String kind, boolean nullable) {}
    record Options(int rowGroupSize, int pageSize, int dictionaryLimit,
                   Map<String, String> encodings) {}
    record Inputs(List<Column> columns, List<Value[]> rows, Options options, List<String> queries,
                  byte[] damaged) {}
    static int dayNumber(String text) { return (int)LocalDate.parse(text).toEpochDay(); }
    static Value parseValue(String kind, String field) {
        if (field.isEmpty())
            return null;
        return switch (kind) {
            case "INT" -> new NumberValue(Long.parseLong(field));
            case "DATE" -> new NumberValue(dayNumber(field));
            case "BOOL" -> new BoolValue(field.equals("true"));
            default -> new TextValue(field);
        };
    }
    static int compare(Value a, Value b) {
        if (a == b)
            return 0;
        if (a == null)
            return -1;
        if (b == null)
            return 1;
        if (a instanceof NumberValue x)
            return Long.compare(x.value(), ((NumberValue)b).value());
        if (a instanceof TextValue x)
            return x.value().compareTo(((TextValue)b).value());
        return Boolean.compare(((BoolValue)a).value(), ((BoolValue)b).value());
    }
    static String valueText(String kind, Value value, String nullText) {
        if (value == null)
            return nullText;
        if (value instanceof NumberValue n)
            return kind.equals("DATE") ? LocalDate.ofEpochDay(n.value()).toString()
                                       : Long.toString(n.value());
        if (value instanceof BoolValue b)
            return b.value() ? "true" : "false";
        return ((TextValue)value).value();
    }
    static String valueText(String kind, Value value) { return valueText(kind, value, "NULL"); }
    static List<String> read(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Inputs readInputs() throws Exception {
        List<Column> columns = new ArrayList<>();
        for (String line : read("schema.txt")) {
            String[] f = line.split(" ");
            columns.add(new Column(f[0], f[1], f[2].equals("NULLABLE")));
        }
        List<Value[]> rows = new ArrayList<>();
        List<String> table = read("table.csv");
        for (String line : table.subList(1, table.size())) {
            String[] f = line.split(",", -1);
            Value[] row = new Value[columns.size()];
            for (int i = 0; i < row.length; i++)
                row[i] = parseValue(columns.get(i).kind(), f[i]);
            rows.add(row);
        }
        List<String> options = read("options.txt");
        Map<String, String> encodings = new HashMap<>();
        for (String line : options.subList(3, options.size())) {
            String[] f = line.split(" ");
            encodings.put(f[1], f[2]);
        }
        Options settings = new Options(Integer.parseInt(options.get(0).split(" ")[1]),
                                       Integer.parseInt(options.get(1).split(" ")[1]),
                                       Integer.parseInt(options.get(2).split(" ")[1]), encodings);
        String damaged = String.join("", read("damaged.hex"));
        byte[] bytes = HexFormat.of().parseHex(damaged);
        return new Inputs(columns, rows, settings, read("queries.txt"), bytes);
    }
    static void writeOutputs(Map<String, List<String>> outputs) throws Exception {
        Files.createDirectories(Path.of("output"));
        for (Map.Entry<String, List<String>> entry : outputs.entrySet())
            Files.writeString(
                Path.of("output", entry.getKey()),
                entry.getValue().isEmpty() ? "" : String.join("\n", entry.getValue()) + "\n",
                StandardCharsets.US_ASCII);
    }
}
