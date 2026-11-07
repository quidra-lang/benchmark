import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Stream;

record Itemset(List<String> items) implements Comparable<Itemset> {
    Itemset { items = List.copyOf(items); }
    static Itemset of(Collection<String> items) { return new Itemset(items.stream().distinct().sorted().toList()); }
    static Itemset of(String... items) { return of(Arrays.asList(items)); }
    static Itemset empty() { return new Itemset(List.of()); }
    int size() { return items.size(); }
    boolean contains(Itemset subset) { return items.containsAll(subset.items); }
    Itemset union(Itemset other) { return of(Stream.concat(items.stream(), other.items.stream()).toList()); }
    @Override public int compareTo(Itemset other) {
        for (int j = 0; j < Math.min(size(), other.size()); j++) {
            int comparison = items.get(j).compareTo(other.items.get(j)); if (comparison != 0) return comparison;
        }
        return Integer.compare(size(), other.size());
    }
}
record Product(String name, String category, long price) {}
final class Transaction {
    final String tid, customer;
    final int day;
    final Map<String, Long> counts = new TreeMap<>();
    Transaction(String tid, String customer, int day) { this.tid = tid; this.customer = customer; this.day = day; }
    boolean add(String item) { boolean duplicate = counts.containsKey(item); counts.merge(item, 1L, Long::sum); return duplicate; }
    Itemset products() { return Itemset.of(counts.keySet()); }
    long units() { return counts.values().stream().mapToLong(Long::longValue).sum(); }
}
final class Baskets {
    static List<String[]> readRecords(String name) throws IOException { return Files.readAllLines(Path.of("input", name)).stream().skip(1).map(line -> line.split(",")).toList(); }
    static Itemset extended(Itemset basket, Map<String, String> taxonomy) { return Itemset.of(Stream.concat(basket.items().stream(), basket.items().stream().map(taxonomy::get)).toList()); }
}
