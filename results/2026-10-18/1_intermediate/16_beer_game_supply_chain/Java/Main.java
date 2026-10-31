import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    static final String[] NAMES = {"RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY"};
    static final Map<String, Integer> PARAMETER_COUNTS = Map.of(
        "FIXED", 1, "PASS", 0, "BASESTOCK", 1, "MINMAX", 2,
        "MOVAVG", 2, "SMOOTH", 2, "STERMAN", 4
    );

    static class CommandError extends RuntimeException {
        CommandError(String reason) { super(reason); }
    }

    static void fail(String reason) {
        throw new CommandError(reason);
    }

    static long num(String value) { return Long.parseLong(value); }
    static int whole(String value) { return Integer.parseInt(value); }

    static String money(long cents) {
        return (cents / 100) + "." + String.format(Locale.ROOT, "%02d", cents % 100);
    }

    static String decimal(long numerator, long denominator, int places) {
        long scale = 1;
        for (int i = 0; i < places; i++) scale *= 10;
        long scaled = numerator * scale / denominator;
        return (scaled / scale) + "." +
            String.format(Locale.ROOT, "%0" + places + "d", scaled % scale);
    }

    static long sum(List<Long> values) {
        long total = 0;
        for (long v : values) total += v;
        return total;
    }

    static long variation(List<Long> values) {
        long total = 0;
        long squares = 0;
        for (long value : values) {
            total += value;
            squares += value * value;
        }
        return values.size() * squares - total * total;
    }

    static String comma(List<Long> values) {
        StringBuilder result = new StringBuilder();
        for (long value : values) {
            if (result.length() != 0) result.append(',');
            result.append(value);
        }
        return result.toString();
    }

    static String pad(Object value, int width) {
        return String.format(Locale.ROOT, "%" + width + "s", value);
    }

    static final class Policy {
        final String name;
        final long[] values;
        final String notation;

        Policy(String name, long[] values, String notation) {
            this.name = name;
            this.values = values;
            this.notation = notation;
        }

        static Policy read(List<String> tokens) {
            String name = tokens.isEmpty() ? "" : tokens.get(0);
            Integer expected = PARAMETER_COUNTS.get(name);
            if (expected == null) fail("unknown policy " + name);
            if (tokens.size() - 1 != expected)
                fail(name + " needs " + expected + " parameters");
            long[] values = new long[expected];
            for (int i = 0; i < expected; i++) {
                String text = tokens.get(i + 1);
                values[i] = num(name.equals("STERMAN") && i < 3
                                ? text.replace(".", "") : text);
            }
            boolean valid;
            switch (name) {
                case "FIXED":
                    valid = values[0] >= 0 && values[0] <= 1000;
                    break;
                case "PASS":
                    valid = true;
                    break;
                case "BASESTOCK":
                    valid = values[0] >= 0 && values[0] <= 10000;
                    break;
                case "MINMAX":
                    valid = values[0] >= 0 && values[0] < values[1] &&
                            values[1] <= 10000;
                    break;
                case "MOVAVG":
                    valid = values[0] >= 1 && values[0] <= 52 &&
                            values[1] >= 0 && values[1] <= 10000;
                    break;
                case "SMOOTH":
                    valid = values[0] >= 1 && values[0] <= 10 &&
                            values[1] >= 0 && values[1] <= 10000;
                    break;
                default:
                    valid = values[3] >= 0 && values[3] <= 10000;
                    for (int i = 0; i < 3; i++)
                        valid &= values[i] >= 0 && values[i] <= 100;
            }
            if (!valid) fail("invalid parameter for " + name);
            return new Policy(name, values, String.join(" ", tokens));
        }

        static Policy baseStock(int target) {
            return new Policy("BASESTOCK", new long[]{target}, "BASESTOCK " + target);
        }
    }

    static final class Initial {
        long inventory, quantity, holding, backlog;
        int shipping, orders;
        Policy policy;

        Initial(String[] input) {
            inventory = num(input[1]);
            quantity = num(input[2]);
            shipping = whole(input[3]);
            orders = whole(input[4]);
            holding = num(input[5]);
            backlog = num(input[6]);
            policy = Policy.read(Arrays.asList(input).subList(7, input.length));
        }
    }

    static final class Record {
        long received, incoming, shipped, before, ontime;
        long inventory, backlog, order, holding, backlogCost, cost;

        Record copy() {
            Record r = new Record();
            r.received = received;
            r.incoming = incoming;
            r.shipped = shipped;
            r.before = before;
            r.ontime = ontime;
            r.inventory = inventory;
            r.backlog = backlog;
            r.order = order;
            r.holding = holding;
            r.backlogCost = backlogCost;
            r.cost = cost;
            return r;
        }
    }

    static final class PlantRecord {
        final long incoming, produced, backlog;

        PlantRecord(long incoming, long produced, long backlog) {
            this.incoming = incoming;
            this.produced = produced;
            this.backlog = backlog;
        }
    }

    static final class Stage {
        long inventory, backlog, expected, holding, backlogRate;
        int lot;
        Long capacity;
        Policy policy;
        List<Long> shipping, orders;
        List<Record> records;

        Stage(Initial initial) {
            inventory = initial.inventory;
            backlog = 0;
            shipping = new ArrayList<>();
            orders = new ArrayList<>();
            for (int i = 0; i < initial.shipping; i++)
                shipping.add(initial.quantity);
            for (int i = 0; i < initial.orders; i++)
                orders.add(initial.quantity);
            policy = initial.policy;
            expected = 100 * initial.quantity;
            holding = initial.holding;
            backlogRate = initial.backlog;
            lot = 1;
            capacity = null;
            records = new ArrayList<>();
        }

        Stage(Stage previous) {
            inventory = previous.inventory;
            backlog = previous.backlog;
            expected = previous.expected;
            holding = previous.holding;
            backlogRate = previous.backlogRate;
            lot = previous.lot;
            capacity = previous.capacity;
            policy = previous.policy;
            shipping = new ArrayList<>(previous.shipping);
            orders = new ArrayList<>(previous.orders);
            records = new ArrayList<>();
            for (Record record : previous.records) records.add(record.copy());
        }
    }

    static final class Simulation {
        final List<Initial> initials;
        List<Long> demands;
        Stage[] stages;
        int week;
        long plantBacklog;
        Long plantCapacity;
        List<PlantRecord> plantRecords;
        String visibility;

        Simulation(List<Initial> initials, List<Long> demands) {
            this.initials = initials;
            this.demands = new ArrayList<>(demands);
            stages = new Stage[4];
            for (int i = 0; i < 4; i++)
                stages[i] = new Stage(initials.get(i));
            week = 0;
            plantBacklog = 0;
            plantCapacity = null;
            plantRecords = new ArrayList<>();
            visibility = "OFF";
        }

        Simulation(Simulation other) {
            initials = other.initials;
            demands = new ArrayList<>(other.demands);
            stages = new Stage[4];
            for (int i = 0; i < 4; i++)
                stages[i] = new Stage(other.stages[i]);
            week = other.week;
            plantBacklog = other.plantBacklog;
            plantCapacity = other.plantCapacity;
            plantRecords = new ArrayList<>(other.plantRecords);
            visibility = other.visibility;
        }

        long signal(int index, int t, long[] current) {
            if (visibility.equals("ON")) return demands.get(t - 1);
            if (current != null && t == week + 1) return current[index];
            return stages[index].records.get(t - 1).incoming;
        }

        void setPolicy(int index, Policy policy) {
            Stage stage = stages[index];
            stage.policy = policy;
            if (policy.name.equals("STERMAN")) {
                stage.expected = 100 * (week > 0 ? signal(index, week, null)
                                                  : initials.get(index).quantity);
            }
        }

        long[][] positions() {
            long[][] result = new long[2][4];
            for (int i = 0; i < 4; i++) {
                Stage stage = stages[i];
                long upstreamBacklog = i < 3 ? stages[i + 1].backlog : plantBacklog;
                long line = sum(stage.orders) + upstreamBacklog + sum(stage.shipping);
                result[0][i] = line;
                result[1][i] = stage.inventory + line - stage.backlog;
            }
            return result;
        }

        long policyOrder(int index, long[] incoming, long line, long position) {
            Stage stage = stages[index];
            Policy policy = stage.policy;
            long[] a = policy.values;
            int t = week + 1;
            long demand = signal(index, t, incoming);
            switch (policy.name) {
                case "FIXED":
                    return a[0];
                case "PASS":
                    return incoming[index];
                case "BASESTOCK":
                    return Math.max(0L, a[0] - position);
                case "MINMAX":
                    return position <= a[0] ? a[1] - position : 0;
                case "MOVAVG": {
                    int count = (int) Math.min(a[0], t);
                    long forecastSum = 0;
                    for (int u = t - count + 1; u <= t; u++)
                        forecastSum += signal(index, u, incoming);
                    long forecast = forecastSum / count;
                    Initial initial = initials.get(index);
                    int delay = initial.shipping + initial.orders;
                    return Math.max(0L, a[1] + forecast * delay - position);
                }
                case "SMOOTH":
                    return Math.max(0L, demand + Math.floorDiv(a[1] - position, a[0]));
                default: {
                    long theta = a[0], alpha = a[1], beta = a[2], target = a[3];
                    stage.expected = Math.floorDiv(
                        100 * theta * demand + (100 - theta) * stage.expected, 100);
                    long net = stage.inventory - stage.backlog;
                    return Math.max(0L, Math.floorDiv(
                        100 * stage.expected + alpha * (100 * (target - net) - beta * line),
                        10000));
                }
            }
        }

        Record[] step() {
            long[] received = new long[4];
            long[] incoming = new long[4];
            for (int i = 0; i < 4; i++) {
                Stage stage = stages[i];
                received[i] = stage.shipping.remove(0);
                stage.inventory += received[i];
            }

            incoming[0] = demands.get(week);
            for (int i = 1; i < 4; i++)
                incoming[i] = stages[i - 1].orders.remove(0);
            long plantIncoming = stages[3].orders.remove(0);

            Record[] newRecords = new Record[4];
            for (int i = 0; i < 4; i++) {
                Stage stage = stages[i];
                Record record = new Record();
                record.received = received[i];
                record.incoming = incoming[i];
                record.before = stage.backlog;
                long requested = stage.backlog + incoming[i];
                long shipped = Math.min(stage.inventory, requested);
                if (stage.capacity != null)
                    shipped = Math.min(shipped, stage.capacity);
                stage.inventory -= shipped;
                stage.backlog = requested - shipped;
                if (i > 0) stages[i - 1].shipping.add(shipped);
                record.shipped = shipped;
                record.ontime = Math.min(Math.max(0L, shipped - record.before), incoming[i]);
                record.inventory = stage.inventory;
                record.backlog = stage.backlog;
                newRecords[i] = record;
            }

            long request = plantBacklog + plantIncoming;
            long produced = plantCapacity == null ? request : Math.min(request, plantCapacity);
            plantBacklog = request - produced;
            stages[3].shipping.add(produced);

            long[][] positions = positions();
            long[] policyOrders = new long[4];
            for (int i = 0; i < 4; i++)
                policyOrders[i] = policyOrder(i, incoming, positions[0][i], positions[1][i]);

            for (int i = 0; i < 4; i++) {
                Stage stage = stages[i];
                Record record = newRecords[i];
                long lot = stage.lot;
                record.order = ((policyOrders[i] + lot - 1) / lot) * lot;
                stage.orders.add(record.order);
                record.holding = stage.holding * stage.inventory;
                record.backlogCost = stage.backlogRate * stage.backlog;
                record.cost = record.holding + record.backlogCost;
                stage.records.add(record);
            }
            plantRecords.add(new PlantRecord(plantIncoming, produced, plantBacklog));
            week++;
            return newRecords;
        }

        long[] totalCosts() {
            long[] totals = new long[4];
            for (int i = 0; i < 4; i++)
                for (Record r : stages[i].records)
                    totals[i] += r.cost;
            return totals;
        }
    }

    static final class Game {
        final List<Initial> initials;
        final Map<String, Simulation> snapshots = new HashMap<>();
        final List<String> output = new ArrayList<>();
        List<Long> base = new ArrayList<>();
        Simulation sim;

        Game(List<Initial> initials) {
            this.initials = initials;
            sim = new Simulation(initials, base);
        }

        void emit(Object... parts) {
            StringBuilder result = new StringBuilder();
            for (Object part : parts) {
                if (result.length() != 0) result.append(' ');
                result.append(part);
            }
            output.add(result.toString());
        }

        int stageIndex(String name) {
            for (int i = 0; i < 4; i++)
                if (NAMES[i].equals(name)) return i;
            fail("unknown stage " + name);
            return -1;
        }

        List<Integer> target(String text) {
            if (text.equals("ALL")) return Arrays.asList(0, 1, 2, 3);
            return Collections.singletonList(stageIndex(text));
        }

        void requireWeeks() {
            if (sim.week == 0) fail("no weeks simulated");
        }

        int[] range(List<String> args, int limit) {
            if (args.isEmpty()) return new int[]{1, limit};
            int first = whole(args.get(0));
            int last = whole(args.get(1));
            if (first < 1 || last < first || last > limit)
                fail("bad range " + args.get(0) + " " + args.get(1));
            return new int[]{first, last};
        }

        void mode(String name) {
            if (!name.equals("ORDERS") && !name.equals("INV") &&
                !name.equals("BACK") && !name.equals("NET"))
                fail("unknown mode " + name);
        }

        List<Long> values(int stage, String kind) {
            List<Long> result = new ArrayList<>();
            for (Record r : sim.stages[stage].records) {
                switch (kind) {
                    case "ORDERS": result.add(r.order); break;
                    case "INV": result.add(r.inventory); break;
                    case "BACK": result.add(r.backlog); break;
                    default: result.add(r.inventory - r.backlog);
                }
            }
            return result;
        }

        void initialize(List<Long> demands) {
            if (demands != null) base = new ArrayList<>(demands);
            sim = new Simulation(initials, base);
        }

        Simulation trial(Policy[] policies) {
            Simulation result = new Simulation(initials, sim.demands);
            result.visibility = sim.visibility;
            result.plantCapacity = sim.plantCapacity;
            for (int i = 0; i < 4; i++) {
                Stage stage = result.stages[i];
                Stage current = sim.stages[i];
                stage.lot = current.lot;
                stage.capacity = current.capacity;
                stage.holding = current.holding;
                stage.backlogRate = current.backlogRate;
                result.setPolicy(i, policies[i]);
            }
            while (result.week < result.demands.size()) result.step();
            return result;
        }

        void demand(List<Long> series) {
            initialize(series);
            emit("DEMAND", "weeks", series.size(), "total", sum(series),
                 "min", Collections.min(series), "max", Collections.max(series));
        }

        void generate(List<String> arguments) {
            int weeks = whole(arguments.get(0));
            long level = num(arguments.get(1)), spread = num(arguments.get(2));
            long seed = num(arguments.get(3));
            List<String> changes = arguments.subList(4, arguments.size());
            for (int i = 0; i < changes.size(); i += 3) {
                int first = whole(changes.get(i + 1));
                if (first < 1 || first > weeks)
                    fail("week " + changes.get(i + 1) + " outside horizon");
            }
            List<Long> levels = new ArrayList<>();
            for (int t = 1; t <= weeks; t++) {
                long current = level;
                for (int i = 0; i < changes.size(); i += 3) {
                    String kind = changes.get(i);
                    int first = whole(changes.get(i + 1));
                    long amount = num(changes.get(i + 2));
                    if (kind.equals("STEP") && t >= first) current += amount;
                    else if (kind.equals("PULSE") && t == first) current += amount;
                    else if (kind.equals("RAMP") && t >= first)
                        current += amount * (t - first + 1);
                }
                if (current < 0) fail("negative level at week " + t);
                levels.add(current);
            }
            List<Long> series = new ArrayList<>();
            for (long current : levels) {
                seed = (48271L * seed) % 2147483647L;
                series.add(current + seed % spread);
            }
            demand(series);
        }

        void status() {
            emit("STATUS", "week", sim.week, "of", sim.demands.size());
            long[][] positions = sim.positions();
            for (int i = 0; i < 4; i++) {
                Stage s = sim.stages[i];
                String line = NAMES[i] + " inv " + s.inventory + " back " + s.backlog +
                    " transit " + comma(s.shipping) + " pending " + comma(s.orders) +
                    " supply " + positions[0][i] + " position " + positions[1][i] +
                    " policy " + s.policy.notation;
                if (s.policy.name.equals("STERMAN"))
                    line += " expect " + money(s.expected);
                emit(line);
            }
            emit("PLANT", "back", sim.plantBacklog);
        }

        void showWeek(int week) {
            emit("WEEK", week, "demand", sim.demands.get(week - 1));
            for (int i = 0; i < 4; i++) {
                Record r = sim.stages[i].records.get(week - 1);
                emit(NAMES[i], "recv", r.received, "in", r.incoming,
                     "ship", r.shipped, "inv", r.inventory, "back", r.backlog,
                     "order", r.order, "cost", money(r.cost));
            }
            PlantRecord p = sim.plantRecords.get(week - 1);
            emit("PLANT", "in", p.incoming, "made", p.produced, "back", p.backlog);
        }

        void table(int index, int first, int last) {
            emit("TABLE", NAMES[index], first + "-" + last);
            int[] widths = {4, 6, 6, 6, 6, 6, 6, 9};
            Object[] heading = {"week", "in", "ship", "recv", "inv", "back", "order", "cost"};
            emit(tableLine(heading, widths));
            for (int week = first; week <= last; week++) {
                Record r = sim.stages[index].records.get(week - 1);
                Object[] row = {week, r.incoming, r.shipped, r.received, r.inventory,
                                r.backlog, r.order, money(r.cost)};
                emit(tableLine(row, widths));
            }
        }

        String tableLine(Object[] row, int[] widths) {
            List<String> fields = new ArrayList<>();
            for (int i = 0; i < row.length; i++)
                fields.add(pad(row[i], widths[i]));
            return String.join(" ", fields);
        }

        void costs() {
            emit("COSTS", "week", sim.week);
            long totalHolding = 0, totalBacklog = 0;
            for (int i = 0; i < 4; i++) {
                long holding = 0, backlog = 0;
                for (Record record : sim.stages[i].records) {
                    holding += record.holding;
                    backlog += record.backlogCost;
                }
                totalHolding += holding;
                totalBacklog += backlog;
                emit(NAMES[i], "holding", money(holding), "backlog", money(backlog),
                     "total", money(holding + backlog));
            }
            emit("TOTAL", "holding", money(totalHolding), "backlog", money(totalBacklog),
                 "total", money(totalHolding + totalBacklog));
        }

        long[] fillCounts(List<Record> records) {
            long incoming = 0, ontime = 0;
            for (Record r : records) {
                incoming += r.incoming;
                ontime += r.ontime;
            }
            return new long[]{incoming, ontime};
        }

        String fillText(List<Record> records) {
            long[] counts = fillCounts(records);
            return counts[0] == 0 ? "n/a" : decimal(counts[1] * 100, counts[0], 2) + "%";
        }

        void bullwhip() {
            int n = sim.week;
            List<Long> demand = new ArrayList<>(sim.demands.subList(0, n));
            long demandVariation = variation(demand);
            emit("BULLWHIP", "weeks", "1-" + n, "demand", "mean",
                 decimal(sum(demand), n, 4), "var",
                 decimal(demandVariation, (long) n * n, 4));
            long previous = demandVariation;
            for (int i = 0; i < 4; i++) {
                List<Long> values = new ArrayList<>();
                for (Record r : sim.stages[i].records) values.add(r.order);
                long v = variation(values);
                emit(NAMES[i], "mean", decimal(sum(values), n, 4),
                     "var", decimal(v, (long) n * n, 4),
                     "ratio", demandVariation == 0 ? "n/a" : decimal(v, demandVariation, 4),
                     "step", previous == 0 ? "n/a" : decimal(v, previous, 4));
                previous = v;
            }
        }

        void peaks() {
            emit("PEAKS", "weeks", "1-" + sim.week);
            for (int i = 0; i < 4; i++) {
                List<Record> records = sim.stages[i].records;
                long maxInv = 0, maxBack = 0;
                int invWeek = 0, backWeek = 0;
                int longest = 0, run = 0, start = 0, bestStart = 0, bestEnd = 0;
                for (int j = 0; j < records.size(); j++) {
                    Record r = records.get(j);
                    int week = j + 1;
                    if (r.inventory > maxInv) {
                        maxInv = r.inventory;
                        invWeek = week;
                    }
                    if (r.backlog > maxBack) {
                        maxBack = r.backlog;
                        backWeek = week;
                    }
                    if (r.backlog > 0) {
                        if (run == 0) start = week;
                        run++;
                        if (run > longest) {
                            longest = run;
                            bestStart = start;
                            bestEnd = week;
                        }
                    } else {
                        run = 0;
                    }
                }
                String longestText = longest == 0 ? "0" :
                    longest + " weeks " + bestStart + "-" + bestEnd;
                emit(NAMES[i], "max_inv", maxInv, "week", invWeek == 0 ? "-" : invWeek,
                     "max_back", maxBack, "week", backWeek == 0 ? "-" : backWeek,
                     "longest_stockout", longestText);
            }
        }

        void leadtime(int index) {
            Stage stage = sim.stages[index];
            Initial initial = initials.get(index);
            int nominal = initial.shipping + initial.orders;
            long[] arrivals = new long[stage.records.size()];
            long received = -nominal * initial.quantity;
            for (int i = 0; i < arrivals.length; i++) {
                received += stage.records.get(i).received;
                arrivals[i] = received;
            }
            long ordered = 0;
            int count = 0;
            List<Integer> leads = new ArrayList<>();
            for (int t = 0; t < stage.records.size(); t++) {
                long amount = stage.records.get(t).order;
                ordered += amount;
                if (amount == 0) continue;
                count++;
                for (int u = t + 1; u < stage.records.size(); u++) {
                    if (arrivals[u] >= ordered) {
                        leads.add(u - t);
                        break;
                    }
                }
            }
            String min = "-", avg = "-", max = "-";
            if (!leads.isEmpty()) {
                min = String.valueOf(Collections.min(leads));
                max = String.valueOf(Collections.max(leads));
                long total = 0;
                for (int lead : leads) total += lead;
                avg = decimal(total, leads.size(), 2);
            }
            emit("LEADTIME", NAMES[index], "nominal", nominal, "orders", count,
                 "completed", leads.size(), "open", count - leads.size(),
                 "min", min, "avg", avg, "max", max);
        }

        void plot(int index, String kind, int first, int last) {
            List<Long> values = values(index, kind).subList(first - 1, last);
            long high = Collections.max(values);
            if (kind.equals("NET")) {
                long low = Collections.min(values), scale = 0;
                for (long v : values) scale = Math.max(scale, Math.abs(v));
                emit("PLOT", NAMES[index], kind, first + "-" + last,
                     "min", low, "max", high);
                for (int j = 0; j < values.size(); j++) {
                    long v = values.get(j);
                    int length = scale == 0 ? 0 : (int) (Math.abs(v) * 25 / scale);
                    String left = v < 0
                        ? " ".repeat(25 - length) + "-".repeat(length) : " ".repeat(25);
                    String right = v > 0 ? "+".repeat(length) : "";
                    emit(pad(first + j, 3) + " " + left + "|" + right + " " + v);
                }
            } else {
                emit("PLOT", NAMES[index], kind, first + "-" + last, "max", high);
                for (int j = 0; j < values.size(); j++) {
                    long v = values.get(j);
                    int length = high == 0 ? 0 : (int) (v * 50 / high);
                    emit(pad(first + j, 3) + " |" + "#".repeat(length) + " " + v);
                }
            }
        }

        void histogram(int index, String kind, int width) {
            List<Long> values = values(index, kind);
            TreeMap<Long, Integer> bins = new TreeMap<>();
            for (long v : values) {
                long bucket = Math.floorDiv(v, width);
                bins.merge(bucket, 1, Integer::sum);
            }
            emit("HISTOGRAM", NAMES[index], kind, "width", width,
                 "weeks", "1-" + sim.week);
            for (long b = bins.firstKey(); b <= bins.lastKey(); b++) {
                int count = bins.getOrDefault(b, 0);
                String line = (b * width) + ".." + (b * width + width - 1) + " " + count;
                if (count != 0) line += " " + "*".repeat(count);
                emit(line);
            }
        }

        void command(String command, List<String> a) {
            Simulation s = sim;
            switch (command) {
                case "DEMAND": {
                    List<Long> demands = new ArrayList<>();
                    for (String v : a) demands.add(num(v));
                    demand(demands);
                    break;
                }
                case "GENERATE":
                    generate(a);
                    break;
                case "RUN": {
                    if (s.week == s.demands.size())
                        fail("horizon reached at week " + s.demands.size());
                    int first = s.week + 1;
                    int steps = Math.min(whole(a.get(0)), s.demands.size() - s.week);
                    long cost = 0;
                    for (int k = 0; k < steps; k++) {
                        Record[] records = s.step();
                        for (int i = 0; i < 4; i++) {
                            Record r = records[i];
                            cost += r.cost;
                            if (r.before == 0 && r.backlog > 0)
                                emit("STOCKOUT", NAMES[i], "week", s.week,
                                     "backlog", r.backlog);
                            else if (r.before > 0 && r.backlog == 0)
                                emit("RECOVER", NAMES[i], "week", s.week);
                        }
                    }
                    long totalDemand = sum(s.demands.subList(first - 1, s.week));
                    emit("RUN", first + "-" + s.week, "demand", totalDemand, "cost", money(cost));
                    if (s.week == s.demands.size()) emit("HORIZON", s.week);
                    break;
                }
                case "RESET":
                    initialize(null);
                    emit("RESET", "week", 0);
                    break;
                case "SAVE":
                    snapshots.put(a.get(0), new Simulation(s));
                    emit("SAVE", a.get(0), "week", s.week);
                    break;
                case "LOAD": {
                    Simulation snapshot = snapshots.get(a.get(0));
                    if (snapshot == null) fail("no snapshot " + a.get(0));
                    sim = new Simulation(snapshot);
                    emit("LOAD", a.get(0), "week", sim.week);
                    break;
                }
                case "SET": {
                    List<Integer> indices = target(a.get(0));
                    Policy policy = Policy.read(a.subList(1, a.size()));
                    for (int index : indices) s.setPolicy(index, policy);
                    emit("SET", a.get(0), policy.notation);
                    break;
                }
                case "BATCH": {
                    int index = stageIndex(a.get(0));
                    int lot = whole(a.get(1));
                    if (lot < 1 || lot > 100)
                        fail("invalid batch size " + a.get(1));
                    s.stages[index].lot = lot;
                    emit("BATCH", a.get(0), lot);
                    break;
                }
                case "CAPACITY": {
                    int index = a.get(0).equals("PLANT") ? -1 : stageIndex(a.get(0));
                    Long capacity = a.get(1).equals("OFF") ? null : num(a.get(1));
                    if (capacity != null && capacity > 10000)
                        fail("invalid capacity " + a.get(1));
                    if (index < 0) s.plantCapacity = capacity;
                    else s.stages[index].capacity = capacity;
                    emit("CAPACITY", a.get(0), a.get(1));
                    break;
                }
                case "COST": {
                    int index = stageIndex(a.get(0));
                    long holding = num(a.get(1)), backlog = num(a.get(2));
                    if (holding > 1000 || backlog > 1000) fail("invalid cost");
                    s.stages[index].holding = holding;
                    s.stages[index].backlogRate = backlog;
                    emit("COST", a.get(0), "holding", holding, "backlog", backlog);
                    break;
                }
                case "VISIBILITY":
                    if (!a.get(0).equals("ON") && !a.get(0).equals("OFF"))
                        fail("unknown visibility " + a.get(0));
                    s.visibility = a.get(0);
                    emit("VISIBILITY", a.get(0));
                    break;
                case "SHOCK": {
                    int week = whole(a.get(0));
                    long demand = num(a.get(1));
                    if (week < 1 || week > s.demands.size())
                        fail("week " + a.get(0) + " outside horizon");
                    if (week <= s.week)
                        fail("week " + a.get(0) + " already simulated");
                    long old = s.demands.set(week - 1, demand);
                    emit("SHOCK", "week", week, old, "->", demand);
                    break;
                }
                case "STATUS":
                    status();
                    break;
                case "SETTINGS": {
                    emit("SETTINGS");
                    for (int i = 0; i < 4; i++) {
                        Stage stage = s.stages[i];
                        Initial initial = initials.get(i);
                        emit(NAMES[i], "holding", stage.holding, "backlog", stage.backlogRate,
                             "batch", stage.lot, "capacity",
                             stage.capacity == null ? "OFF" : stage.capacity,
                             "delays", initial.shipping, initial.orders);
                    }
                    emit("PLANT", "capacity",
                         s.plantCapacity == null ? "OFF" : s.plantCapacity);
                    emit("VISIBILITY", s.visibility);
                    break;
                }
                case "WEEK": {
                    requireWeeks();
                    int week = whole(a.get(0));
                    if (week < 1 || week > s.week)
                        fail("bad week " + a.get(0));
                    showWeek(week);
                    break;
                }
                case "TABLE": {
                    int index = stageIndex(a.get(0));
                    requireWeeks();
                    int[] range = range(a.subList(1, a.size()), s.week);
                    table(index, range[0], range[1]);
                    break;
                }
                case "CHAIN": {
                    requireWeeks();
                    int[] range = range(a, s.week);
                    emit("CHAIN", range[0] + "-" + range[1]);
                    String header = pad("week", 4) + " " + pad("demand", 6);
                    for (String name : NAMES) header += " " + pad(name, 11);
                    emit(header);
                    for (int week = range[0]; week <= range[1]; week++) {
                        String row = pad(week, 4) + " " + pad(s.demands.get(week - 1), 6);
                        for (Stage stage : s.stages)
                            row += " " + pad(stage.records.get(week - 1).order, 11);
                        emit(row);
                    }
                    break;
                }
                case "DEMANDS": {
                    int[] range = range(a, s.demands.size());
                    List<Long> values = s.demands.subList(range[0] - 1, range[1]);
                    emit("DEMANDS", range[0] + "-" + range[1], "total", sum(values),
                         "min", Collections.min(values), "max", Collections.max(values));
                    StringBuilder line = new StringBuilder();
                    for (long v : values) {
                        if (line.length() > 0) line.append(' ');
                        line.append(v);
                    }
                    emit(line.toString());
                    break;
                }
                case "COSTS":
                    costs();
                    break;
                case "SUMMARY": {
                    requireWeeks();
                    emit("SUMMARY", "weeks", "1-" + s.week);
                    for (int i = 0; i < 4; i++) {
                        long inv = 0, back = 0, orders = 0;
                        long least = Long.MAX_VALUE, most = 0;
                        int zeros = 0;
                        for (Record r : s.stages[i].records) {
                            inv += r.inventory;
                            back += r.backlog;
                            orders += r.order;
                            least = Math.min(least, r.order);
                            most = Math.max(most, r.order);
                            if (r.order == 0) zeros++;
                        }
                        emit(NAMES[i], "avg_inv", decimal(inv, s.week, 2),
                             "avg_back", decimal(back, s.week, 2),
                             "orders", orders, "min", least, "max", most,
                             "zero_weeks", zeros);
                    }
                    break;
                }
                case "BALANCE": {
                    emit("BALANCE", "week", s.week);
                    for (int i = 0; i < 4; i++) {
                        long received = 0, shipped = 0;
                        for (Record r : s.stages[i].records) {
                            received += r.received;
                            shipped += r.shipped;
                        }
                        emit(NAMES[i], "start", initials.get(i).inventory,
                             "received", received, "shipped", shipped,
                             "end", s.stages[i].inventory, "owed", s.stages[i].backlog);
                    }
                    long initialGoods = 0, produced = 0, delivered = 0, stock = 0, transit = 0;
                    for (Initial init : initials)
                        initialGoods += init.inventory + init.quantity * init.shipping;
                    for (PlantRecord r : s.plantRecords) produced += r.produced;
                    for (Record r : s.stages[0].records) delivered += r.shipped;
                    for (Stage stage : s.stages) {
                        stock += stage.inventory;
                        transit += sum(stage.shipping);
                    }
                    emit("SYSTEM", "initial", initialGoods, "produced", produced,
                         "delivered", delivered, "stock", stock, "transit", transit);
                    break;
                }
                case "FILLRATE": {
                    requireWeeks();
                    emit("FILLRATE", "weeks", "1-" + s.week);
                    for (int i = 0; i < 4; i++) {
                        List<Record> records = s.stages[i].records;
                        long[] counts = fillCounts(records);
                        int stockouts = 0;
                        for (Record r : records)
                            if (r.backlog > 0) stockouts++;
                        emit(NAMES[i], "fill", fillText(records),
                             "ontime", counts[1], "ordered", counts[0],
                             "stockout_weeks", stockouts,
                             "service", decimal((long) (s.week - stockouts) * 100, s.week, 2) + "%");
                    }
                    break;
                }
                case "BULLWHIP":
                    requireWeeks();
                    bullwhip();
                    break;
                case "PEAKS":
                    requireWeeks();
                    peaks();
                    break;
                case "LEADTIME": {
                    int index = stageIndex(a.get(0));
                    requireWeeks();
                    leadtime(index);
                    break;
                }
                case "PLOT":
                case "HISTOGRAM": {
                    int index = stageIndex(a.get(0));
                    mode(a.get(1));
                    if (command.equals("HISTOGRAM")) {
                        int width = whole(a.get(2));
                        if (width < 1 || width > 100)
                            fail("invalid width " + a.get(2));
                    }
                    requireWeeks();
                    if (command.equals("PLOT")) {
                        int[] interval = range(a.subList(2, a.size()), s.week);
                        plot(index, a.get(1), interval[0], interval[1]);
                    } else {
                        histogram(index, a.get(1), whole(a.get(2)));
                    }
                    break;
                }
                case "COMPARE": {
                    List<Policy> policies = new ArrayList<>();
                    int start = 0;
                    for (int end = 0; end <= a.size(); end++) {
                        if (end == a.size() || a.get(end).equals("/")) {
                            policies.add(Policy.read(a.subList(start, end)));
                            start = end + 1;
                        }
                    }
                    class Row {
                        long cost;
                        int original;
                        String label, fill, ratio;
                        Row(long cost, int original, String label, String fill, String ratio) {
                            this.cost = cost;
                            this.original = original;
                            this.label = label;
                            this.fill = fill;
                            this.ratio = ratio;
                        }
                    }
                    List<Row> rows = new ArrayList<>();
                    for (int index = 0; index < policies.size(); index++) {
                        Policy policy = policies.get(index);
                        Policy[] all = {policy, policy, policy, policy};
                        Simulation trial = trial(all);
                        long cost = 0;
                        for (long value : trial.totalCosts()) cost += value;
                        long dv = variation(trial.demands);
                        List<Long> factory = new ArrayList<>();
                        for (Record r : trial.stages[3].records) factory.add(r.order);
                        long fv = variation(factory);
                        String ratio = dv == 0 ? "n/a" : decimal(fv, dv, 4);
                        String fill = fillText(trial.stages[0].records);
                        rows.add(new Row(cost, index, policy.notation, fill, ratio));
                    }
                    rows.sort(Comparator.comparingLong((Row r) -> r.cost)
                                        .thenComparingInt(r -> r.original));
                    emit("COMPARE", policies.size(), "weeks", s.demands.size());
                    int rank = 0;
                    for (Row row : rows)
                        emit(++rank, row.label, "total", money(row.cost),
                             "fill", row.fill, "bullwhip", row.ratio);
                    break;
                }
                case "OPTIMIZE": {
                    List<Integer> indices = target(a.get(0));
                    int low = whole(a.get(1)), high = whole(a.get(2));
                    if (low > high) fail("bad range " + a.get(1) + " " + a.get(2));
                    if (high - low > 200) fail("range too large");
                    long bestCost = Long.MAX_VALUE, bestTotal = 0;
                    int bestValue = low;
                    for (int candidate = low; candidate <= high; candidate++) {
                        Policy[] policies = new Policy[4];
                        for (int i = 0; i < 4; i++) policies[i] = s.stages[i].policy;
                        for (int i : indices) policies[i] = Policy.baseStock(candidate);
                        Simulation trial = trial(policies);
                        long[] costs = trial.totalCosts();
                        long objective = 0, total = 0;
                        for (long cost : costs) total += cost;
                        for (int i : indices) objective += costs[i];
                        if (objective < bestCost) {
                            bestCost = objective;
                            bestTotal = total;
                            bestValue = candidate;
                        }
                    }
                    emit("OPTIMIZE", a.get(0), "BASESTOCK", bestValue,
                         "cost", money(bestCost), "total", money(bestTotal));
                    break;
                }
                default:
                    fail("unknown command " + command);
            }
        }

        void execute(String line) {
            String[] fields = line.split(" ");
            String command = fields[0];
            List<String> args = Arrays.asList(fields).subList(1, fields.length);
            try {
                command(command, args);
            } catch (CommandError error) {
                emit("ERROR", error.getMessage());
            }
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        List<Initial> initials = new ArrayList<>();
        for (int i = 0; i < 4; i++)
            initials.add(new Initial(input.readLine().split(" ")));
        Game game = new Game(initials);
        String line;
        while ((line = input.readLine()) != null && !line.equals("END"))
            game.execute(line);
        if (!game.output.isEmpty())
            System.out.println(String.join("\n", game.output));
    }
}
