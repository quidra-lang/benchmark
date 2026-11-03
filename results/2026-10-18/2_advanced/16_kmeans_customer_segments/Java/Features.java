import java.util.List;
import java.util.Map;
import java.util.TreeMap;

final class Customer {
    final String id;
    final List<Order> orders;
    final int recency, frequency, spend, categories, tenure;
    final double monetary, basket;
    final Map<String, Integer> categorySpend = new TreeMap<>();
    Customer(String id, List<Order> orders, int day) {
        this.id = id; this.orders = orders;
        int latest = Integer.MIN_VALUE, earliest = Integer.MAX_VALUE, total = 0;
        for (Order order : orders) {
            latest = Math.max(latest, order.day); earliest = Math.min(earliest, order.day); total += order.net;
            for (Transaction row : order.rows) categorySpend.merge(row.category(), row.amount(), Integer::sum);
        }
        recency = day - latest; frequency = orders.size(); spend = total; monetary = spend / 100.0; basket = monetary / frequency;
        categories = (int) categorySpend.values().stream().filter(value -> value > 0).count(); tenure = day - earliest;
    }
    double[] values() { return new double[] {recency, frequency, monetary, basket, categories, tenure}; }
    double[] transformed() {
        double[] values = values();
        for (int i = 0; i < values.length; i++) if (Features.SQRT[i]) values[i] = Math.sqrt(values[i]);
        return values;
    }
}
record Standardization(double[] means, double[] sds) {}
final class Features {
    static final List<String> NAMES = List.of("recency", "frequency", "monetary", "basket", "categories", "tenure");
    static final boolean[] SQRT = {false, true, true, true, false, false};
    static List<Customer> eligible(List<Order> orders, int day) {
        Map<String, List<Order>> groups = Transactions.byCustomer(orders.stream().filter(Order::valid).toList());
        return groups.keySet().stream().sorted().map(id -> new Customer(id, groups.get(id), day)).toList();
    }
    static double sum(double[] values) { double total = 0; for (double value : values) total += value; return total; }
    static double mean(double[] values) { return sum(values) / values.length; }
    static double sampleSd(double[] values) {
        double mean = mean(values), total = 0;
        for (double value : values) { double difference = value - mean; total += difference * difference; }
        return Math.sqrt(total / (values.length - 1));
    }
    static Standardization standardization(List<double[]> rows) {
        double[] means = new double[6], sds = new double[6];
        for (int f = 0; f < 6; f++) {
            double[] column = new double[rows.size()];
            for (int i = 0; i < column.length; i++) column[i] = rows.get(i)[f];
            means[f] = mean(column); sds[f] = sampleSd(column);
        }
        return new Standardization(means, sds);
    }
    static double[] standardize(double[] values, double[] means, double[] sds) {
        double[] point = new double[values.length];
        for (int f = 0; f < point.length; f++) point[f] = sds[f] == 0 ? 0 : (values[f] - means[f]) / sds[f];
        return point;
    }
    static double correlation(List<double[]> points, int first, int second) {
        double total = 0;
        for (double[] point : points) total += point[first] * point[second];
        return total / (points.size() - 1);
    }
}
