import java.util.*;
final class Stats {
    static final List<String> TRANSACTIONS = List.of("BusRd", "BusRdX", "BusUpgr", "BusWr", "WB"),
                              SERVICES =
                                  List.of("l1", "upgrade", "through", "cache", "l2", "memory"),
                              MISSES = List.of("compulsory", "capacity", "conflict", "coherence"),
                              SNOOP_COUNTERS =
                                  List.of("invalidations_sent", "invalidations_received",
                                          "supplied", "back_invalidations");
    static final class Counts {
        Map<String, Integer> values = new HashMap<>();
        int get(String key) { return values.getOrDefault(key, 0); }
        void add(String key, int amount) { values.put(key, get(key) + amount); }
        String named(List<String> keys) {
            List<String> parts = new ArrayList<>();
            for (String key : keys)
                parts.add(key + " " + get(key));
            return String.join(" ", parts);
        }
    }
    static final class Core {
        Counts simple = new Counts(), misses = new Counts(), service = new Counts(),
               bus = new Counts(), snoop = new Counts();
        int finish;
    }
    static Core total(List<Core> cores) {
        Core total = new Core();
        for (Core core : cores) {
            List<Counts> source =
                             List.of(core.simple, core.misses, core.service, core.bus, core.snoop),
                         destination = List.of(total.simple, total.misses, total.service, total.bus,
                                               total.snoop);
            for (int i = 0; i < source.size(); i++)
                for (Map.Entry<String, Integer> e : source.get(i).values.entrySet())
                    destination.get(i).add(e.getKey(), e.getValue());
            total.finish = Math.max(total.finish, core.finish);
        }
        return total;
    }
    static String fraction(int p, int q) {
        int a = p, b = q;
        while (b != 0) {
            int next = a % b;
            a = b;
            b = next;
        }
        return p / a + "/" + q / a;
    }
    static String decimal(int p, int q) {
        int value = (2 * p * 100 + q) / (2 * q);
        return value / 100 + "." + (value % 100 < 10 ? "0" : "") + value % 100;
    }
    static String coreString(Collection<Integer> cores) {
        StringBuilder result = new StringBuilder();
        for (int core : new TreeSet<>(cores))
            result.append(core);
        return result.isEmpty() ? "-" : result.toString();
    }
    static String ranges(int[] counts, List<String> labels) {
        List<String> parts = new ArrayList<>();
        for (int i = 0; i < counts.length; i++)
            parts.add(labels.get(i) + ":" + counts[i]);
        return String.join(" ", parts);
    }
    static List<String> sixLines(String label, Core entry) {
        Counts s = entry.simple;
        int length = s.get("latency"), accesses = s.get("accesses");
        return List.of(
            label + " " +
                s.named(List.of("accesses", "reads", "writes", "hits", "misses", "fences")),
            label + " misses " +
                entry.misses.named(List.of("compulsory", "capacity", "conflict", "coherence",
                                           "true_sharing", "false_sharing")),
            label + " service " + entry.service.named(SERVICES),
            label + " bus " + entry.bus.named(TRANSACTIONS),
            label + " snoop " + entry.snoop.named(SNOOP_COUNTERS),
            label + " time latency " + length + " amat " + fraction(length, accesses) + " " +
                decimal(length, accesses) + " fence_stall " + s.get("fence_stall") + " finish " +
                entry.finish);
    }
}
