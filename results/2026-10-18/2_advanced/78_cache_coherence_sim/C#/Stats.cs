using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
public static class Stats {
    public static readonly List<string> TRANSACTIONS =
                                            new() { "BusRd", "BusRdX", "BusUpgr", "BusWr", "WB" },
                                        SERVICES = new() { "l1",    "upgrade", "through",
                                                           "cache", "l2",      "memory" },
                                        MISSES = new() { "compulsory", "capacity", "conflict",
                                                         "coherence" },
                                        SNOOP_COUNTERS =
                                            new() { "invalidations_sent", "invalidations_received",
                                                    "supplied", "back_invalidations" };
    public sealed class Counts {
        public Dictionary<string, int> values = new();
        public int Get(string key) => values.GetValueOrDefault(key, 0);
        public void Add(string key, int amount) { values[key] = Get(key) + amount; }
        public string Named(List<string> keys) => string.Join(" ", keys.Select(key => key + " " +
                                                                                      Get(key)));
    }
    public sealed class Core {
        public Counts simple = new(), misses = new(), service = new(), bus = new(), snoop = new();
        public int finish;
    }
    public static Core Total(List<Core> cores) {
        Core total = new();
        foreach (Core core in cores) {
            Counts[] source = { core.simple, core.misses, core.service, core.bus, core.snoop },
                     destination = { total.simple, total.misses, total.service, total.bus,
                                     total.snoop };
            for (int i = 0; i < source.Length; i++)
                foreach (var e in source[i].values)
                    destination[i].Add(e.Key, e.Value);
            total.finish = Math.Max(total.finish, core.finish);
        }
        return total;
    }
    public static string Fraction(int p, int q) {
        int a = p, b = q;
        while (b != 0) {
            int next = a % b;
            a = b;
            b = next;
        }
        return p / a + "/" + q / a;
    }
    public static string Decimal(int p, int q) {
        int value = (2 * p * 100 + q) / (2 * q);
        return value / 100 + "." + (value % 100).ToString("D2", CultureInfo.InvariantCulture);
    }
    public static string CoreString(IEnumerable<int> cores) {
        StringBuilder result = new();
        foreach (int core in cores.Distinct().Order())
            result.Append(core);
        return result.Length == 0 ? "-" : result.ToString();
    }
    public static string Ranges(int[] counts, List<string> labels) =>
        string.Join(" ", counts.Select((count, i) => labels[i] + ":" + count));
    public static List<string> SixLines(string label, Core entry) {
        Counts s = entry.simple;
        int length = s.Get("latency"), accesses = s.Get("accesses");
        return new() {
            label + " " +
                s.Named(new() { "accesses", "reads", "writes", "hits", "misses", "fences" }),
            label + " misses " +
                entry.misses.Named(new() { "compulsory", "capacity", "conflict", "coherence",
                                           "true_sharing", "false_sharing" }),
            label + " service " + entry.service.Named(SERVICES),
            label + " bus " + entry.bus.Named(TRANSACTIONS),
            label + " snoop " + entry.snoop.Named(SNOOP_COUNTERS),
            label + " time latency " + length + " amat " + Fraction(length, accesses) + " " +
                Decimal(length, accesses) + " fence_stall " + s.Get("fence_stall") + " finish " +
                entry.finish
        };
    }
}
