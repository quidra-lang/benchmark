import java.io.*;
import java.util.*;

public class Main {
    enum Mode { CHAIN, LINEAR, QUADRATIC, DOUBLE, ROBINHOOD, CUCKOO }
    enum Reporting {
        SILENT, REHASHES, FULL, TRACE;
        boolean trace() { return this == TRACE; }
        boolean details() { return this == FULL || this == TRACE; }
    }
    static final class CommandError extends RuntimeException {
        CommandError(String reason) { super(reason); }
    }
    record Item(String key, long value) {
        @Override public String toString() { return key + "=" + value; }
    }
    record Slot(Item item, boolean deleted) {
        static final Slot EMPTY = new Slot(null, false), TOMB = new Slot(null, true);
        Slot(Item item) { this(item, false); }
        boolean empty() { return item == null && !deleted; }
        String content() { return item != null ? item.key : deleted ? "D" : "-"; }
    }
    static final class Counters {
        long probes, rehashes, inserts, updates, hits, misses, deletes, absent;
    }
    static final class Search {
        Item item;
        int position = -1, chainIndex = -1, available = -1, probes;
        final List<String> path = new ArrayList<>();
    }
    static final class Placement {
        int position = -1, movements;
        boolean reused;
        Item pending;
        final List<String> moves = new ArrayList<>();
    }
    record Removal(int shifted, List<String> moves) {}
    record Mutation(boolean changed, List<String> lines) {}
    record Cost(String key, int position, int probes) {}
    record Metrics(int longest, String average) {}

    static Mode parseMode(String word) {
        for (Mode mode : Mode.values()) if (mode.name().equals(word)) return mode;
        throw new CommandError("BAD MODE " + word);
    }
    static int hash(String key, int base, int modulus) {
        int value = 0;
        for (int i = 0; i < key.length(); i++) value = (value * base + key.charAt(i)) % modulus;
        return value;
    }
    static int prime(int value) {
        for (int candidate = Math.max(value, 2); ; candidate++) {
            boolean valid = true;
            for (int divisor = 2; divisor <= candidate / divisor; divisor++) {
                if (candidate % divisor == 0) { valid = false; break; }
            }
            if (valid) return candidate;
        }
    }
    static String decimal(long numerator, long denominator) {
        long value = denominator == 0 ? 0 : 100 * numerator / denominator;
        return "%d.%02d".formatted(value / 100, value % 100);
    }
    static char gauge(int value) { return value < 10 ? (char) ('0' + value) : '+'; }
    static List<String> histogram(List<Integer> values) {
        var frequencies = new TreeMap<Integer, Integer>();
        for (int value : values) frequencies.merge(value, 1, Integer::sum);
        var lines = new ArrayList<String>();
        frequencies.forEach((value, count) -> lines.add(value + " " + count + " " + "#".repeat(Math.min(50, count)) + (count > 50 ? "+" : "")));
        return lines;
    }
    static List<String> generate(int count, int length, long seed) {
        var keys = new ArrayList<String>(count);
        for (int i = 0; i < count; i++) {
            var key = new StringBuilder(length);
            for (int j = 0; j < length; j++) {
                seed = 48271 * seed % 2147483647;
                key.append((char) ('a' + seed % 26));
            }
            keys.add(key.toString());
        }
        return keys;
    }
    static int capacity(long value) {
        if (value < 2 || value > 10000) throw new CommandError("BAD CAPACITY");
        return (int) value;
    }
    static void checkGeneration(long count, long length, long seed) {
        if (count < 1 || count > 500 || length < 1 || length > 10 || seed < 1 || seed > 2147483646) throw new CommandError("BAD ARGUMENT");
    }

    static final class HashTable {
        Mode mode;
        int cap, size, tomb;
        List<List<Item>> buckets;
        Slot[] slots;
        final Counters counters = new Counters();

        HashTable(Mode mode, int cap) {
            this.mode = mode;
            this.cap = cap;
            buckets = new ArrayList<>();
            if (mode == Mode.CHAIN) {
                for (int i = 0; i < cap; i++) buckets.add(new ArrayList<>());
                slots = new Slot[0];
            } else {
                slots = new Slot[slotCount()];
                Arrays.fill(slots, Slot.EMPTY);
            }
        }
        int slotCount() { return cap * (mode == Mode.CUCKOO ? 2 : 1); }
        String position(int index) { return mode == Mode.CUCKOO ? "T" + (index / cap + 1) + "." + index % cap : Integer.toString(index); }
        int distance(Item item, int index) { return (index + cap - hash(item.key, 31, cap)) % cap; }
        List<Item> items() {
            var items = new ArrayList<Item>(size);
            if (mode == Mode.CHAIN) for (var bucket : buckets) items.addAll(bucket);
            else for (Slot slot : slots) if (slot.item != null) items.add(slot.item);
            return items;
        }
        void observe(Search search, int position, String content, boolean trace) {
            search.probes++;
            if (trace) search.path.add(position(position) + ":" + content);
        }
        Search search(String key, boolean trace) {
            var result = new Search();
            int home = hash(key, 31, cap);
            if (mode == Mode.CHAIN) {
                var bucket = buckets.get(home);
                for (int index = 0; index < bucket.size(); index++) {
                    Item item = bucket.get(index);
                    observe(result, home, item.key, trace);
                    if (item.key.equals(key)) {
                        result.item = item;
                        result.position = home;
                        result.chainIndex = index;
                        break;
                    }
                }
                return result;
            }
            int step = mode == Mode.DOUBLE ? 1 + hash(key, 37, cap - 1) : 1;
            int limit = mode == Mode.CUCKOO ? 2 : cap;
            for (int i = 0; i < limit; i++) {
                int index = mode == Mode.CUCKOO ? (i == 0 ? home : cap + hash(key, 37, cap))
                    : (int) ((home + (mode == Mode.QUADRATIC ? (long) i * i : (long) i * step)) % cap);
                Slot slot = slots[index];
                observe(result, index, slot.content(), trace);
                if (slot.item != null && slot.item.key.equals(key)) {
                    result.item = slot.item;
                    result.position = index;
                    break;
                }
                if (mode == Mode.CUCKOO) continue;
                if (slot.empty()) { if (result.available < 0) result.available = index; break; }
                if (slot.deleted) { if (result.available < 0) result.available = index; continue; }
                if (mode == Mode.ROBINHOOD && distance(slot.item, index) < i) break;
            }
            return result;
        }
        Placement place(Item item, Search initial, boolean trace) {
            var result = new Placement();
            int home = hash(item.key, 31, cap);
            if (mode == Mode.CHAIN) {
                buckets.get(home).add(item);
                result.position = home;
                return result;
            }
            if (mode == Mode.LINEAR || mode == Mode.QUADRATIC || mode == Mode.DOUBLE) {
                int index = (initial == null ? search(item.key, false) : initial).available;
                if (index < 0) { result.pending = item; return result; }
                result.reused = slots[index].deleted;
                if (result.reused) tomb--;
                slots[index] = new Slot(item);
                result.position = index;
                return result;
            }
            Item carried = item;
            if (mode == Mode.ROBINHOOD) {
                int index = home, traveled = 0, from = -1;
                while (true) {
                    Item resident = slots[index].item;
                    if (resident == null) {
                        if (trace && from >= 0) result.moves.add("SHIFT " + carried.key + " " + from + " -> " + index);
                        slots[index] = new Slot(carried);
                        if (result.position < 0) result.position = index;
                        return result;
                    }
                    int residentDistance = distance(resident, index);
                    if (residentDistance < traveled) {
                        if (trace && from >= 0) result.moves.add("SHIFT " + carried.key + " " + from + " -> " + index);
                        slots[index] = new Slot(carried);
                        carried = resident;
                        if (result.position < 0) result.position = index;
                        from = index;
                        traveled = residentDistance;
                        result.movements++;
                    }
                    index = (index + 1) % cap;
                    traveled++;
                }
            }
            int part = 0;
            while (true) {
                int index = part * cap + hash(carried.key, part == 0 ? 31 : 37, cap);
                Item resident = slots[index].item;
                if (resident == null) {
                    slots[index] = new Slot(carried);
                    result.position = search(item.key, false).position;
                    return result;
                }
                if (result.movements == cap) { result.pending = carried; return result; }
                if (trace) result.moves.add("KICK " + resident.key + " " + position(index));
                slots[index] = new Slot(carried);
                carried = resident;
                result.movements++;
                part = 1 - part;
            }
        }
        Removal remove(Search found, boolean trace) {
            int shifted = 0;
            var moves = new ArrayList<String>();
            if (mode == Mode.CHAIN) buckets.get(found.position).remove(found.chainIndex);
            else if (mode == Mode.LINEAR || mode == Mode.QUADRATIC || mode == Mode.DOUBLE) {
                slots[found.position] = Slot.TOMB;
                tomb++;
            } else {
                slots[found.position] = Slot.EMPTY;
                if (mode == Mode.ROBINHOOD) {
                    int source = (found.position + 1) % cap;
                    while (slots[source].item != null && distance(slots[source].item, source) > 0) {
                        int destination = (source + cap - 1) % cap;
                        if (trace) moves.add("SHIFT " + slots[source].item.key + " " + source + " -> " + destination);
                        slots[destination] = slots[source];
                        slots[source] = Slot.EMPTY;
                        shifted++;
                        source = (source + 1) % cap;
                    }
                }
            }
            size--;
            return new Removal(shifted, moves);
        }
        static HashTable rebuild(Mode mode, int cap, List<Item> items) {
            var trial = new HashTable(mode, cap);
            for (Item item : items) {
                if (trial.place(item, null, false).position < 0) return null;
                trial.size++;
            }
            return trial;
        }
        void adopt(HashTable replacement) {
            mode = replacement.mode;
            cap = replacement.cap;
            size = replacement.size;
            tomb = replacement.tomb;
            buckets = replacement.buckets;
            slots = replacement.slots;
        }
        String automatic(int capacity, String reason, Item pending) {
            int old = cap;
            var items = items();
            if (pending != null) items.add(pending);
            while (true) {
                HashTable trial = rebuild(mode, capacity, items);
                if (trial != null) {
                    adopt(trial);
                    counters.rehashes++;
                    return "REHASH " + reason + " " + old + " -> " + cap;
                }
                capacity = prime(2 * capacity);
            }
        }
        String loadCheck(int maximum) {
            long threshold = (long) maximum * slotCount();
            if ((size + tomb) * 100L <= threshold) return null;
            boolean grow = size * 200L > threshold;
            return automatic(grow ? prime(2 * cap) : cap, grow ? "load" : "tomb", null);
        }
        String shrinkCheck(int minimum, int maximum) {
            int capacity = prime(cap / 2), slots = capacity * (mode == Mode.CUCKOO ? 2 : 1);
            if (size * 100L >= (long) minimum * slotCount() || capacity >= cap || size * 100L > (long) maximum * slots) return null;
            HashTable trial = rebuild(mode, capacity, items());
            if (trial == null) return null;
            int old = cap;
            adopt(trial);
            counters.rehashes++;
            return "REHASH shrink " + old + " -> " + cap;
        }
        static String pathLine(Search found) { return "PATH " + (found.path.isEmpty() ? "none" : String.join(" ", found.path)); }
        Mutation put(Item item, boolean add, int maximum, Reporting reporting) {
            Search found = search(item.key, reporting.trace());
            counters.probes += found.probes;
            String command = add ? "ADD" : "PUT";
            var lines = new ArrayList<String>();
            if (found.item != null) {
                long old = found.item.value;
                Item stored = new Item(item.key, add ? old + item.value : item.value);
                if (mode == Mode.CHAIN) buckets.get(found.position).set(found.chainIndex, stored);
                else slots[found.position] = new Slot(stored);
                counters.updates++;
                if (reporting.details()) lines.add(command + " " + stored + " UPDATED old=" + old + " at=" + position(found.position) + " probes=" + found.probes);
                if (reporting.trace()) lines.add(pathLine(found));
                return new Mutation(false, lines);
            }
            Placement placed = place(item, found, reporting.trace());
            counters.inserts++;
            if (reporting.details()) {
                String row = command + " " + item + " NEW";
                if (placed.position >= 0) {
                    row += " at=" + position(placed.position) + " probes=" + found.probes;
                    if (placed.reused) row += " reused";
                    if (mode == Mode.ROBINHOOD) row += " shifted=" + placed.movements;
                    if (mode == Mode.CUCKOO) row += " kicks=" + placed.movements;
                } else {
                    row += " probes=" + found.probes;
                    row += mode == Mode.QUADRATIC ? " full" : " kicks=" + placed.movements + " failed";
                }
                lines.add(row);
            }
            if (reporting.trace()) { lines.add(pathLine(found)); lines.addAll(placed.moves); }
            if (placed.position >= 0) size++;
            else {
                String rehash = automatic(prime(2 * cap), mode == Mode.QUADRATIC ? "full" : "kicks", placed.pending);
                if (reporting != Reporting.SILENT) lines.add(rehash);
            }
            String rehash = loadCheck(maximum);
            if (rehash != null && reporting != Reporting.SILENT) lines.add(rehash);
            return new Mutation(true, lines);
        }
        Mutation delete(String key, int minimum, int maximum, Reporting reporting) {
            Search found = search(key, reporting.trace());
            counters.probes += found.probes;
            var lines = new ArrayList<String>();
            if (found.item == null) {
                counters.absent++;
                if (reporting.details()) lines.add("DEL " + key + " NOT FOUND probes=" + found.probes);
                if (reporting.trace()) lines.add(pathLine(found));
                return new Mutation(false, lines);
            }
            Removal removed = remove(found, reporting.trace());
            counters.deletes++;
            if (reporting.details()) {
                String row = "DEL " + key + " OK at=" + position(found.position) + " probes=" + found.probes;
                if (mode == Mode.ROBINHOOD) row += " shifted=" + removed.shifted;
                lines.add(row);
            }
            if (reporting.trace()) { lines.add(pathLine(found)); lines.addAll(removed.moves); }
            String rehash = shrinkCheck(minimum, maximum);
            if (rehash != null && reporting != Reporting.SILENT) lines.add(rehash);
            return new Mutation(true, lines);
        }
        List<String> get(String key, boolean trace) {
            Search found = search(key, trace);
            counters.probes += found.probes;
            String row;
            if (found.item != null) {
                counters.hits++;
                row = "GET " + found.item + " at=" + position(found.position) + " probes=" + found.probes;
            } else {
                counters.misses++;
                row = "GET " + key + " NOT FOUND probes=" + found.probes;
            }
            var lines = new ArrayList<>(List.of(row));
            if (trace) lines.add(pathLine(found));
            return lines;
        }
        List<Cost> costs() {
            var costs = new ArrayList<Cost>(size);
            if (mode == Mode.CHAIN) {
                for (int position = 0; position < cap; position++) {
                    var bucket = buckets.get(position);
                    for (int index = 0; index < bucket.size(); index++) costs.add(new Cost(bucket.get(index).key, position, index + 1));
                }
            } else {
                for (int position = 0; position < slots.length; position++) {
                    Item item = slots[position].item;
                    if (item == null) continue;
                    int probes = switch (mode) {
                        case CUCKOO -> position / cap + 1;
                        case LINEAR, ROBINHOOD -> distance(item, position) + 1;
                        default -> search(item.key, false).probes;
                    };
                    costs.add(new Cost(item.key, position, probes));
                }
            }
            return costs;
        }
        Metrics metrics() {
            int longest = 0;
            long total = 0;
            for (Cost cost : costs()) { longest = Math.max(longest, cost.probes); total += cost.probes; }
            return new Metrics(longest, decimal(total, size));
        }
        List<String> dump() {
            var lines = new ArrayList<String>();
            lines.add("DUMP " + mode + " cap=" + cap + " size=" + size + " tomb=" + tomb);
            if (mode == Mode.CHAIN) {
                for (int position = 0; position < cap; position++) {
                    var row = new StringBuilder().append(position);
                    var bucket = buckets.get(position);
                    if (bucket.isEmpty()) row.append(" -");
                    for (Item item : bucket) row.append(' ').append(item);
                    lines.add(row.toString());
                }
            } else {
                for (int position = 0; position < slots.length; position++) {
                    Slot slot = slots[position];
                    String prefix = mode == Mode.CUCKOO ? "T" + (position / cap + 1) + " " + position % cap : Integer.toString(position);
                    String value = slot.item == null ? slot.content() : slot.item.toString();
                    if (mode == Mode.ROBINHOOD && slot.item != null) value += " d=" + distance(slot.item, position);
                    lines.add(prefix + " " + value);
                }
            }
            return lines;
        }
        List<String> map() {
            var lines = new ArrayList<String>();
            lines.add("MAP " + mode + " cap=" + cap);
            int[] costs = new int[slotCount()];
            if (mode != Mode.CHAIN) for (Cost cost : costs()) costs[cost.position] = cost.probes;
            for (int part = 0; part < (mode == Mode.CUCKOO ? 2 : 1); part++) {
                for (int start = 0; start < cap; start += 40) {
                    var text = new StringBuilder();
                    for (int index = start; index < Math.min(start + 40, cap); index++) {
                        char ch;
                        if (mode == Mode.CHAIN) ch = buckets.get(index).isEmpty() ? '.' : gauge(buckets.get(index).size());
                        else {
                            int position = part * cap + index;
                            Slot slot = slots[position];
                            ch = slot.empty() ? '.' : slot.deleted ? 'D' : mode == Mode.CUCKOO ? '#' : gauge(costs[position] - 1);
                        }
                        text.append(ch);
                    }
                    String prefix = mode == Mode.CUCKOO ? "T" + (part + 1) + " " : "";
                    lines.add(prefix + "%05d %s".formatted(start, text));
                }
            }
            return lines;
        }
        List<String> statistics() {
            Metrics values = metrics();
            return List.of("STATS " + mode + " size=" + size + " cap=" + cap + " slots=" + slotCount() + " tomb=" + tomb
                + " load=" + decimal(100L * size, slotCount()) + "% longest=" + values.longest + " avg=" + values.average
                + " probes=" + counters.probes + " rehashes=" + counters.rehashes,
                "OPS inserts=" + counters.inserts + " updates=" + counters.updates + " hits=" + counters.hits
                + " misses=" + counters.misses + " deletes=" + counters.deletes + " absent=" + counters.absent);
        }
        String scan(int cursor, int limit) {
            var keys = new ArrayList<String>();
            while (cursor < slotCount() && keys.size() < limit) {
                if (mode == Mode.CHAIN) for (Item item : buckets.get(cursor)) keys.add(item.key);
                else if (slots[cursor].item != null) keys.add(slots[cursor].item.key);
                cursor++;
            }
            if (cursor == slotCount()) cursor = 0;
            return "SCAN next=" + cursor + (keys.isEmpty() ? "" : " " + String.join(" ", keys));
        }
        List<String> clusters() {
            var runs = new ArrayList<Integer>();
            if (mode == Mode.CHAIN) {
                for (var bucket : buckets) if (!bucket.isEmpty()) runs.add(bucket.size());
            } else {
                for (int base = 0; base < slots.length; base += cap) {
                    int firstEmpty = -1;
                    for (int i = 0; i < cap; i++) if (slots[base + i].empty()) { firstEmpty = i; break; }
                    if (firstEmpty < 0) { runs.add(cap); continue; }
                    int length = 0;
                    for (int offset = 1; offset <= cap; offset++) {
                        if (!slots[base + (firstEmpty + offset) % cap].empty()) length++;
                        else if (length > 0) { runs.add(length); length = 0; }
                    }
                }
            }
            var lines = new ArrayList<String>();
            lines.add("CLUSTERS runs=" + runs.size() + " longest=" + runs.stream().mapToInt(Integer::intValue).max().orElse(0));
            lines.addAll(histogram(runs));
            return lines;
        }
        List<String> distribution() {
            var values = costs().stream().map(Cost::probes).toList();
            var lines = new ArrayList<String>();
            lines.add("DIST keys=" + size + " longest=" + values.stream().mapToInt(Integer::intValue).max().orElse(0));
            lines.addAll(histogram(values));
            return lines;
        }
    }

    static List<String> compare(HashTable table, int cap, int maximum) {
        var items = table.items();
        items.sort(Comparator.comparing(Item::key));
        var lines = new ArrayList<String>();
        lines.add("COMPARE keys=" + items.size() + " cap=" + cap);
        for (Mode mode : Mode.values()) {
            var trial = new HashTable(mode, cap);
            for (Item item : items) trial.put(item, false, maximum, Reporting.SILENT);
            Metrics values = trial.metrics();
            lines.add(mode + " cap=" + trial.cap + " longest=" + values.longest + " avg=" + values.average
                + " probes=" + trial.counters.probes + " rehashes=" + trial.counters.rehashes);
        }
        return lines;
    }
    static List<String> benchmark(int cap, int count, int length, long seed, int maximum) {
        var keys = generate(2 * count, length, seed);
        var lines = new ArrayList<String>();
        lines.add("BENCH cap=" + cap + " count=" + count + " len=" + length + " seed=" + seed);
        for (Mode mode : Mode.values()) {
            var trial = new HashTable(mode, cap);
            for (int i = 0; i < count; i++) trial.put(new Item(keys.get(i), i + 1), false, maximum, Reporting.SILENT);
            int misses = 0;
            long probes = 0;
            for (String key : keys.subList(count, 2 * count)) {
                Search found = trial.search(key, false);
                if (found.item == null) { misses++; probes += found.probes; }
            }
            lines.add(mode + " cap=" + trial.cap + " keys=" + trial.size + " hit=" + trial.metrics().average
                + " misses=" + misses + " miss=" + decimal(probes, misses) + " rehashes=" + trial.counters.rehashes);
        }
        return lines;
    }

    static final class Simulator {
        static final Set<String> COMMANDS = Set.of("CREATE", "MAXLOAD", "MINLOAD", "TRACE", "HASH", "PUT", "ADD", "GET", "DEL", "PROBE", "GEN", "GENDEL",
            "RESIZE", "CONVERT", "CLEAR", "DUMP", "MAP", "STATS", "KEYS", "TOP", "SCAN", "CLUSTERS", "DIST", "COMPARE", "BENCH");
        HashTable table;
        int maximum = 75, minimum;
        boolean trace;

        List<String> execute(String line) {
            String[] words = line.split(" ");
            String command = words[0];
            if (!COMMANDS.contains(command)) throw new CommandError("UNKNOWN COMMAND " + command);
            switch (command) {
                case "CREATE" -> {
                    Mode mode = parseMode(words[1]);
                    int cap = prime(capacity(Long.parseLong(words[2])));
                    table = new HashTable(mode, cap);
                    return List.of("CREATE " + mode + " cap=" + cap);
                }
                case "MAXLOAD", "MINLOAD" -> {
                    long value = Long.parseLong(words[1]);
                    if (command.equals("MAXLOAD") ? value < 10 || value > 95 : value < 0 || value > 40) throw new CommandError("BAD LOAD");
                    if (command.equals("MAXLOAD")) maximum = (int) value; else minimum = (int) value;
                    return List.of(command + " " + value);
                }
                case "TRACE" -> {
                    if (!words[1].equals("ON") && !words[1].equals("OFF")) throw new CommandError("BAD ARGUMENT");
                    trace = words[1].equals("ON");
                    return List.of("TRACE " + words[1]);
                }
                case "HASH" -> {
                    int cap = capacity(Long.parseLong(words[2]));
                    String key = words[1];
                    return List.of("HASH " + key + " m=" + cap + " h31=" + hash(key, 31, cap) + " h37=" + hash(key, 37, cap) + " step=" + (1 + hash(key, 37, cap - 1)));
                }
                case "BENCH" -> {
                    int cap = prime(capacity(Long.parseLong(words[1])));
                    long count = Long.parseLong(words[2]), length = Long.parseLong(words[3]), seed = Long.parseLong(words[4]);
                    checkGeneration(count, length, seed);
                    return benchmark(cap, (int) count, (int) length, seed, maximum);
                }
            }
            if (table == null) throw new CommandError("NO TABLE");
            Reporting reporting = trace ? Reporting.TRACE : Reporting.FULL;
            return switch (command) {
                case "PUT", "ADD" -> table.put(new Item(words[1], Long.parseLong(words[2])), command.equals("ADD"), maximum, reporting).lines;
                case "GET" -> table.get(words[1], trace);
                case "DEL" -> table.delete(words[1], minimum, maximum, reporting).lines;
                case "PROBE" -> {
                    Search found = table.search(words[1], true);
                    String path = found.path.isEmpty() ? "" : " " + String.join(" ", found.path);
                    yield List.of("PROBE " + words[1] + path + (found.item == null ? " MISS" : " FOUND") + " probes=" + found.probes);
                }
                case "GEN", "GENDEL" -> {
                    long count = Long.parseLong(words[1]), length = Long.parseLong(words[2]), seed = Long.parseLong(words[3]);
                    checkGeneration(count, length, seed);
                    var lines = new ArrayList<String>();
                    int index = 0, changed = 0;
                    for (String key : generate((int) count, (int) length, seed)) {
                        index++;
                        Mutation result = command.equals("GEN") ? table.put(new Item(key, index), false, maximum, Reporting.REHASHES)
                            : table.delete(key, minimum, maximum, Reporting.REHASHES);
                        if (result.changed) changed++;
                        lines.addAll(result.lines);
                    }
                    lines.add(command.equals("GEN") ? "GEN " + count + " new=" + changed + " updated=" + (count - changed)
                        : "GENDEL " + count + " deleted=" + changed + " missing=" + (count - changed));
                    yield lines;
                }
                case "RESIZE", "CONVERT" -> {
                    int cap = command.equals("RESIZE") ? prime(capacity(Long.parseLong(words[1]))) : table.cap;
                    Mode mode = command.equals("CONVERT") ? parseMode(words[1]) : table.mode;
                    int slots = cap * (mode == Mode.CUCKOO ? 2 : 1);
                    if (table.size * 100L > (long) maximum * slots) throw new CommandError("TOO SMALL");
                    HashTable replacement = HashTable.rebuild(mode, cap, table.items());
                    if (replacement == null) throw new CommandError("REBUILD FAILED");
                    String row = command.equals("RESIZE") ? "RESIZE " + table.cap + " -> " + cap : "CONVERT " + table.mode + " -> " + mode + " cap=" + cap;
                    table.adopt(replacement);
                    yield List.of(row);
                }
                case "CLEAR" -> {
                    int size = table.size;
                    table.adopt(new HashTable(table.mode, table.cap));
                    yield List.of("CLEAR " + size);
                }
                case "DUMP" -> table.dump();
                case "MAP" -> table.map();
                case "STATS" -> table.statistics();
                case "KEYS" -> {
                    var keys = table.items().stream().map(Item::key).sorted().toList();
                    yield List.of("KEYS " + keys.size() + (keys.isEmpty() ? "" : " " + String.join(" ", keys)));
                }
                case "TOP" -> {
                    long limit = Long.parseLong(words[1]);
                    if (limit < 1 || limit > 100) throw new CommandError("BAD ARGUMENT");
                    var costs = table.costs();
                    costs.sort(Comparator.comparingInt(Cost::probes).reversed().thenComparing(Cost::key));
                    var selected = costs.subList(0, Math.min(costs.size(), (int) limit));
                    var lines = new ArrayList<String>();
                    lines.add("TOP " + selected.size());
                    for (Cost cost : selected) lines.add(cost.key + " cost=" + cost.probes + " at=" + table.position(cost.position));
                    yield lines;
                }
                case "SCAN" -> {
                    long cursor = Long.parseLong(words[1]), limit = Long.parseLong(words[2]);
                    if (limit < 1 || limit > 100) throw new CommandError("BAD ARGUMENT");
                    if (cursor >= table.slotCount()) throw new CommandError("BAD CURSOR");
                    yield List.of(table.scan((int) cursor, (int) limit));
                }
                case "CLUSTERS" -> table.clusters();
                case "DIST" -> table.distribution();
                case "COMPARE" -> compare(table, prime(capacity(Long.parseLong(words[1]))), maximum);
                default -> throw new IllegalStateException(command);
            };
        }
    }

    public static void main(String[] args) throws IOException {
        Locale.setDefault(Locale.ROOT);
        var input = new BufferedReader(new InputStreamReader(System.in));
        var output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String first = input.readLine();
        if (first == null) return;
        int count = Integer.parseInt(first);
        var simulator = new Simulator();
        for (int i = 0; i < count; i++) {
            try { for (String line : simulator.execute(input.readLine())) output.print(line + '\n'); }
            catch (CommandError error) { output.print("ERROR " + error.getMessage() + '\n'); }
        }
        output.flush();
    }
}
