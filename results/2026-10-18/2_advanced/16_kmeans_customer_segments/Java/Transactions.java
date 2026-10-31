import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

record Params(int referenceDay, int snapshotDay, int outcomeDays, int kMin, int kMax, List<String> methods,
              int restarts, int maxIterations, long seed, int subsamples, int subsamplePercent, double outlierSd,
              int overdueFactor, int[] orderBins, int topCategories, int topCustomers, int periodDays, int periods) {}
record Transaction(String customer, int day, String orderId, String category, int amount) {}
final class TransactionData {
    int rowCount, duplicates, free;
    final List<Transaction> validRows = new ArrayList<>();
    final Set<String> customers = new TreeSet<>();
}
final class Order {
    final String id, customer;
    int day, net;
    final List<Transaction> rows = new ArrayList<>();
    Order(Transaction row) { id = row.orderId(); customer = row.customer(); day = row.day(); }
    void add(Transaction row) { day = Math.min(day, row.day()); net += row.amount(); rows.add(row); }
    boolean valid() { return net > 0; }
}
final class Transactions {
    static List<String> lines(String path) throws IOException { return Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII); }
    static Params readParams(String path) throws IOException {
        Map<String, List<String>> values = new LinkedHashMap<>();
        for (String line : lines(path)) { List<String> fields = List.of(line.split(" ")); values.put(fields.getFirst(), fields.subList(1, fields.size())); }
        return new Params(value(values, "REFERENCE_DAY"), value(values, "SNAPSHOT_DAY"), value(values, "OUTCOME_DAYS"),
            value(values, "K_RANGE"), Integer.parseInt(values.get("K_RANGE").get(1)), values.get("METHODS"), value(values, "RESTARTS"),
            value(values, "MAX_ITERATIONS"), value(values, "SEED"), value(values, "SUBSAMPLES"), value(values, "SUBSAMPLE_PERCENT"),
            Double.parseDouble(values.get("OUTLIER_SD").getFirst()), value(values, "OVERDUE_FACTOR"),
            values.get("ORDER_BINS").stream().mapToInt(Integer::parseInt).toArray(), value(values, "TOP_CATEGORIES"),
            value(values, "TOP_CUSTOMERS"), value(values, "PERIOD_DAYS"), value(values, "PERIODS"));
    }
    private static int value(Map<String, List<String>> values, String key) { return Integer.parseInt(values.get(key).getFirst()); }
    static TransactionData read(String path) throws IOException {
        TransactionData data = new TransactionData();
        Set<String> seen = new HashSet<>();
        for (String line : lines(path).stream().skip(1).toList()) {
            String[] fields = line.split(",");
            Transaction row = new Transaction(fields[0], Integer.parseInt(fields[1]), fields[2], fields[3], Integer.parseInt(fields[4]));
            data.rowCount++; data.customers.add(row.customer());
            if (!seen.add(line)) data.duplicates++;
            else if (row.amount() == 0) data.free++;
            else data.validRows.add(row);
        }
        return data;
    }
    static List<Order> groupOrders(List<Transaction> rows, int first, int last) {
        Map<String, Order> orders = new LinkedHashMap<>();
        for (Transaction row : rows) if (row.day() >= first && row.day() <= last)
            orders.computeIfAbsent(row.orderId(), ignored -> new Order(row)).add(row);
        return new ArrayList<>(orders.values());
    }
    static Map<String, List<Order>> byCustomer(List<Order> orders) {
        Map<String, List<Order>> groups = new LinkedHashMap<>();
        for (Order order : orders) groups.computeIfAbsent(order.customer, ignored -> new ArrayList<>()).add(order);
        return groups;
    }
}
