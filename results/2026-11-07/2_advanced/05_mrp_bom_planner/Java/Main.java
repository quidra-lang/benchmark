import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

public class Main {
    record Row(int line, String[] fields) {}
    static List<String> read(String name) throws IOException { return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII); }
    static List<Row> rows(String name) throws IOException { List<String> lines = read(name); List<Row> rows = new ArrayList<>(); for (int i = 1; i < lines.size(); i++) rows.add(new Row(i + 1, lines.get(i).split(",", -1))); return rows; }
    static void error(List<String> errors, String file, int line, String message) { errors.add(file + " line " + line + ": " + message); }
    private static long sum(long[] values) { long result = 0; for (long value : values) result += value; return result; }
    private static long[] weeks(long[] values) { return Arrays.copyOfRange(values, 1, values.length); }
    private static String join(String separator, Object... values) { StringBuilder text = new StringBuilder(); for (int i = 0; i < values.length; i++) { if (i > 0) text.append(separator); text.append(values[i]); } return text.toString(); }
    private static String line(Object... values) { return join(" ", values); }
    private record ScheduleRow(String item, int week, long quantity, int line) {}
    private record Inquiry(String id, String item, long quantity, int week, int line) {}
    private enum DemandKind { MPS, ORDER, DEPENDENT, SAFETY }
    private record RootKey(String item, int kind, int week, String orderId) implements Comparable<RootKey> {
        public int compareTo(RootKey other) { int result = item.compareTo(other.item); if (result == 0) result = Integer.compare(kind, other.kind); if (result == 0) result = Integer.compare(week, other.week); return result == 0 ? orderId.compareTo(other.orderId) : result; }
    }
    private record Demand(String item, DemandKind kind, int week, long quantity, String orderId, int line, String parent, int parentNumber) {
        Demand(String item, DemandKind kind, int week, long quantity) { this(item, kind, week, quantity, "", 0, "", 0); }
        RootKey rootKey() { return new RootKey(item, kind == DemandKind.MPS ? 0 : kind == DemandKind.ORDER ? 1 : 2, week, orderId); }
        String text() {
            return switch (kind) {
                case SAFETY -> "SAFETY " + item;
                case MPS -> Main.line("MPS", item, "week", week);
                case ORDER -> Main.line("ORDER", orderId, item, "week", week);
                case DEPENDENT -> Main.line(parent, "order", parentNumber, "week", week);
            };
        }
    }
    private record PlannedOrder(String item, int number, int receipt, long quantity, int lead) {
        int original() { return receipt - lead; }
        int release() { return Math.max(1, original()); }
    }
    private enum SupplyKind { STOCK, RECEIPT, ORDER }
    private record Allocation(Demand demand, long share) {}
    private static class Supply {
        final SupplyKind kind;
        final int week, line;
        final long quantity;
        final PlannedOrder order;
        long remaining;
        final List<Allocation> allocations = new ArrayList<>();
        final List<Demand> roots = new ArrayList<>();
        Supply(SupplyKind kind, int week, long quantity, int line, PlannedOrder order) { this.kind = kind; this.week = week; this.quantity = quantity; this.line = line; this.order = order; remaining = quantity; }
        String header() {
            return switch (kind) {
                case STOCK -> Main.line("STOCK", "quantity", quantity);
                case RECEIPT -> Main.line("RECEIPT", "line", line, "week", week, "quantity", quantity);
                case ORDER -> Main.line("ORDER", order.number(), "receipt", order.receipt(), "release", order.release(), "quantity", order.quantity());
            };
        }
        boolean serves(String id) { return roots.stream().anyMatch(root -> root.kind() == DemandKind.ORDER && root.orderId().equals(id)); }
    }
    private static class ItemPlan {
        final Item item;
        final long[] receipts, gross, onHand, net, plannedReceipts, plannedReleases;
        final List<Demand> demands = new ArrayList<>();
        final List<PlannedOrder> orders = new ArrayList<>();
        final List<Supply> supplies = new ArrayList<>(), orderSupplies = new ArrayList<>();
        ItemPlan(Item item, int horizon, long[] scheduled) {
            this.item = item; receipts = scheduled.clone(); gross = new long[horizon + 1]; onHand = new long[horizon + 1]; net = new long[horizon + 1]; plannedReceipts = new long[horizon + 1]; plannedReleases = new long[horizon + 1]; onHand[0] = item.onHand();
        }
        long pastDue() { long quantity = 0; for (PlannedOrder order : orders) if (order.original() < 1) quantity += order.quantity(); return quantity; }
    }
    private static class Plan {
        final Map<String, ItemPlan> items = new TreeMap<>();
        final Map<String, long[]> loads = new TreeMap<>(), overloads = new TreeMap<>();
    }
    private static class Promise {
        final Inquiry inquiry;
        int week, materialWeek;
        String reason = "";
        Promise(Inquiry inquiry) { this.inquiry = inquiry; }
    }
    private record Promised(List<Promise> promises, Plan plan) {}
    private static class Data {
        final List<String> errors = new ArrayList<>(), pegItems = new ArrayList<>(), planningOrder = new ArrayList<>();
        int horizon;
        long treeQuantity;
        final Map<String, Item> items;
        final Bom bom;
        final Map<String, Center> centers;
        final Map<String, List<Operation>> routings;
        final List<Demand> mps = new ArrayList<>();
        final List<Inquiry> inquiries;
        final Map<String, Integer> codes = new HashMap<>(), cumulative = new HashMap<>();
        final Map<String, List<ScheduleRow>> receipts = new TreeMap<>();
        final Map<String, long[]> scheduled = new TreeMap<>();
        final long[] weeks;
        private String scheduleError(String item, int week, long quantity) {
            if (!items.containsKey(item)) return "unknown item " + item;
            if (week < 1 || week > horizon) return "week " + week + " outside horizon";
            return quantity < 1 ? "bad quantity " + quantity : "";
        }
        private List<ScheduleRow> readSchedule(String name, boolean unique) throws IOException {
            List<ScheduleRow> accepted = new ArrayList<>(); Set<String> seen = new HashSet<>();
            for (Row row : rows(name)) {
                String[] f = row.fields(); ScheduleRow value = new ScheduleRow(f[0], Integer.parseInt(f[1]), Long.parseLong(f[2]), row.line()); String key = value.item() + ":" + value.week(), message = scheduleError(value.item(), value.week(), value.quantity());
                if (message.isEmpty() && unique && seen.contains(key)) message = "duplicate " + value.item() + " week " + value.week();
                if (!message.isEmpty()) error(errors, name, row.line(), message); else { accepted.add(value); seen.add(key); }
            }
            return accepted;
        }
        private List<Inquiry> readInquiries() throws IOException {
            List<Inquiry> accepted = new ArrayList<>(); Set<String> seen = new HashSet<>();
            for (Row row : rows("orders.csv")) {
                String[] f = row.fields(); Inquiry value = new Inquiry(f[0], f[1], Long.parseLong(f[2]), Integer.parseInt(f[3]), row.line());
                String message = seen.contains(value.id()) ? "duplicate order " + value.id() : scheduleError(value.item(), value.week(), value.quantity());
                if (!message.isEmpty()) error(errors, "orders.csv", row.line(), message); else { accepted.add(value); seen.add(value.id()); }
            }
            return accepted;
        }
        Data() throws IOException {
            for (String value : read("params.txt")) { String[] f = value.split(" "); if (f[0].equals("horizon")) horizon = Integer.parseInt(f[1]); else if (f[0].equals("peg")) pegItems.addAll(Arrays.asList(f).subList(1, f.length)); else treeQuantity = Long.parseLong(f[1]); }
            items = Items.read(errors); bom = Bom.read(items, errors); centers = Capacity.readCenters(errors); routings = Capacity.readRoutings(items, centers, bom, errors);
            List<ScheduleRow> schedule = readSchedule("mps.csv", true), received = readSchedule("receipts.csv", false); inquiries = readInquiries();
            for (ScheduleRow row : schedule) mps.add(new Demand(row.item(), DemandKind.MPS, row.week(), row.quantity()));
            for (String id : items.keySet()) { bom.lowLevel(id, codes); bom.cumulative(id, items, cumulative); planningOrder.add(id); receipts.put(id, new ArrayList<>()); scheduled.put(id, new long[horizon + 1]); }
            planningOrder.sort(Comparator.comparingInt((String id) -> codes.get(id)).thenComparing(Comparator.naturalOrder())); received.sort(Comparator.comparingInt(ScheduleRow::week).thenComparingInt(ScheduleRow::line));
            for (ScheduleRow row : received) { receipts.get(row.item()).add(row); scheduled.get(row.item())[row.week()] += row.quantity(); }
            weeks = new long[horizon]; for (int i = 0; i < horizon; i++) weeks[i] = i + 1;
        }
    }
    private static class Planner {
        final Data data;
        Planner(Data data) { this.data = data; }
        Plan run(List<Demand> orderDemands) {
            Plan plan = new Plan(); for (String id : data.planningOrder) plan.items.put(id, new ItemPlan(data.items.get(id), data.horizon, data.scheduled.get(id)));
            for (Demand demand : data.mps) plan.items.get(demand.item()).demands.add(demand); for (Demand demand : orderDemands) plan.items.get(demand.item()).demands.add(demand);
            for (String id : data.planningOrder) {
                ItemPlan p = plan.items.get(id); Item item = p.item; for (Demand demand : p.demands) p.gross[demand.week()] += demand.quantity(); long projected = item.onHand();
                for (int week = 1; week <= data.horizon; week++) {
                    long available = projected + p.receipts[week] - p.gross[week]; projected = available;
                    if (available < item.safety()) {
                        long quantity = LotSizing.size(item, week, available, p.receipts, p.gross, data.horizon); PlannedOrder order = new PlannedOrder(id, p.orders.size() + 1, week, quantity, item.lead());
                        p.orders.add(order); p.net[week] = item.safety() - available; p.plannedReceipts[week] = quantity; p.plannedReleases[order.release()] += quantity; projected += quantity;
                    }
                    p.onHand[week] = projected;
                }
                for (PlannedOrder order : p.orders) for (Edge edge : data.bom.children.get(id)) plan.items.get(edge.child()).demands.add(new Demand(edge.child(), DemandKind.DEPENDENT, order.release(), edge.need(order.quantity()), "", 0, id, order.number()));
            }
            for (String id : data.centers.keySet()) plan.loads.put(id, new long[data.horizon + 1]);
            for (Map.Entry<String, List<Operation>> route : data.routings.entrySet()) for (PlannedOrder order : plan.items.get(route.getKey()).orders) for (int i = 0; i < route.getValue().size(); i++) {
                Operation operation = route.getValue().get(i); int week = Capacity.operationWeek(order.receipt(), data.items.get(route.getKey()).lead(), i, route.getValue().size()); plan.loads.get(operation.center())[week] += operation.minutes(order.quantity());
            }
            for (Center center : data.centers.values()) { long[] over = new long[data.horizon + 1]; for (int week = 1; week <= data.horizon; week++) over[week] = Math.max(0, plan.loads.get(center.id())[week] - center.available()); plan.overloads.put(center.id(), over); }
            return plan;
        }
        Promised promiseInquiries(Plan baseline) {
            Plan current = baseline; List<Demand> promised = new ArrayList<>(); List<Promise> promises = new ArrayList<>();
            for (Inquiry inquiry : data.inquiries) {
                Promise promise = new Promise(inquiry);
                for (int week = inquiry.week(); week <= data.horizon; week++) {
                    Demand demand = new Demand(inquiry.item(), DemandKind.ORDER, week, inquiry.quantity(), inquiry.id(), inquiry.line(), "", 0); List<Demand> candidate = new ArrayList<>(promised); candidate.add(demand); Plan trial = run(candidate); String reason = "";
                    for (String id : data.planningOrder) if (trial.items.get(id).pastDue() > current.items.get(id).pastDue()) { reason = id; break; }
                    if (reason.isEmpty()) {
                        if (promise.materialWeek == 0) promise.materialWeek = week;
                        for (String id : data.centers.keySet()) { for (int w = 1; w <= data.horizon; w++) if (trial.overloads.get(id)[w] > current.overloads.get(id)[w]) { reason = id + " week " + w; break; } if (!reason.isEmpty()) break; }
                    }
                    if (reason.isEmpty()) { promise.week = week; promised.add(demand); current = trial; break; } if (week == inquiry.week()) promise.reason = reason;
                }
                promises.add(promise);
            }
            return new Promised(promises, current);
        }
        private static Supply parentSupply(Plan plan, Demand demand) { return plan.items.get(demand.parent()).orderSupplies.get(demand.parentNumber() - 1); }
        void peg(Plan plan) {
            for (String id : data.planningOrder) {
                ItemPlan p = plan.items.get(id); Item item = p.item;
                if (item.onHand() > 0) p.supplies.add(new Supply(SupplyKind.STOCK, 0, item.onHand(), 0, null));
                for (ScheduleRow receipt : data.receipts.get(id)) p.supplies.add(new Supply(SupplyKind.RECEIPT, receipt.week(), receipt.quantity(), receipt.line(), null));
                for (PlannedOrder order : p.orders) p.supplies.add(new Supply(SupplyKind.ORDER, order.receipt(), order.quantity(), 0, order));
                p.supplies.sort(Comparator.comparingInt((Supply s) -> s.week).thenComparing(s -> s.kind).thenComparingInt(s -> s.line));
                List<Demand> demands = new ArrayList<>(p.demands); demands.sort(Comparator.comparingInt(Demand::week).thenComparing(Demand::kind).thenComparingInt(Demand::line).thenComparing(Demand::parent).thenComparingInt(Demand::parentNumber));
                if (item.safety() > 0) demands.addFirst(new Demand(id, DemandKind.SAFETY, 0, item.safety())); int index = 0;
                for (Demand demand : demands) {
                    long remaining = demand.quantity();
                    while (remaining > 0) { while (p.supplies.get(index).remaining == 0) index++; Supply supply = p.supplies.get(index); long share = Math.min(remaining, supply.remaining); supply.allocations.add(new Allocation(demand, share)); remaining -= share; supply.remaining -= share; }
                }
                for (Supply supply : p.supplies) if (supply.kind == SupplyKind.ORDER) p.orderSupplies.add(supply);
                for (Supply supply : p.orderSupplies) {
                    Map<RootKey, Demand> roots = new TreeMap<>();
                    for (Allocation allocation : supply.allocations) { Demand demand = allocation.demand(); if (demand.kind() == DemandKind.DEPENDENT) for (Demand root : parentSupply(plan, demand).roots) roots.put(root.rootKey(), root); else roots.put(demand.rootKey(), demand); }
                    supply.roots.addAll(roots.values());
                }
            }
        }
        private static String depth(int depth) { return ".".repeat(depth) + depth; }
        List<String> grid(Plan plan) {
            List<String> lines = new ArrayList<>();
            for (String id : data.planningOrder) {
                ItemPlan p = plan.items.get(id); Item item = p.item;
                lines.add(line("ITEM", id, "LLC", data.codes.get(id), "LT", item.lead(), "LOT", item.lotLabel(), "SS", item.safety(), "OH", item.onHand(), item.description())); lines.add(Report.table("WEEK", data.weeks, 6));
                List<String> labels = List.of("GROSS", "RECEIPTS", "ON_HAND", "NET", "PLAN_RCPT", "PLAN_REL"); List<long[]> values = List.of(p.gross, p.receipts, p.onHand, p.net, p.plannedReceipts, p.plannedReleases);
                for (int i = 0; i < labels.size(); i++) lines.add(Report.table(labels.get(i), weeks(values.get(i)), 6));
                lines.add(line("TOTAL", "gross", sum(p.gross), "receipts", sum(p.receipts), "planned", sum(p.plannedReceipts), "orders", p.orders.size(), "ending", p.onHand[data.horizon]));
            }
            return lines;
        }
        private void whereUsed(String item, int depth, long extension, List<String> lines) {
            for (Edge edge : data.bom.parents.get(item)) { long next = extension * edge.quantity(); lines.add(line(depth(depth), edge.parent(), "qty", edge.quantity(), "ext", next)); whereUsed(edge.parent(), depth + 1, next, lines); }
        }
        private static void allocationLines(Plan plan, Supply supply, int depth, List<String> lines) {
            for (Allocation allocation : supply.allocations) {
                lines.add(" ".repeat(2 * depth) + line("ALLOC", allocation.share(), allocation.demand().text()));
                if (supply.kind == SupplyKind.ORDER && allocation.demand().kind() == DemandKind.DEPENDENT) allocationLines(plan, parentSupply(plan, allocation.demand()), depth + 1, lines);
            }
        }
        List<String> pegging(Plan plan) {
            List<String> lines = new ArrayList<>();
            for (String id : data.pegItems) {
                ItemPlan p = plan.items.get(id); lines.add(line("PEG", id, "orders", p.orders.size())); whereUsed(id, 1, 1, lines);
                for (SupplyKind kind : SupplyKind.values()) for (Supply supply : p.supplies) if (supply.kind == kind) {
                    lines.add(supply.header()); allocationLines(plan, supply, 1, lines); if (supply.remaining > 0) lines.add("  EXCESS " + supply.remaining); for (Demand root : supply.roots) lines.add("  ROOT " + root.text());
                }
            }
            return lines;
        }
        private void explode(String item, long gross, long extension, int depth, List<String> lines, Map<String, Long> totals) {
            for (Edge edge : data.bom.children.get(item)) {
                Item child = data.items.get(edge.child()); long nextExtension = extension * edge.quantity(), nextGross = edge.need(gross); totals.merge(edge.child(), nextGross, Long::sum);
                lines.add(line(depth(depth), edge.child(), "qty", edge.quantity(), "scrap", edge.scrap(), "ext", nextExtension, "gross", nextGross, "lt", child.lead(), "cum", data.cumulative.get(edge.child()), child.description()));
                explode(edge.child(), nextGross, nextExtension, depth + 1, lines, totals);
            }
        }
        List<String> trees() {
            List<String> lines = new ArrayList<>();
            for (Item item : data.items.values()) if (data.bom.topLevel(item.id())) {
                String id = item.id(); lines.add(line("TREE", id, "quantity", data.treeQuantity)); lines.add(line("0", id, "ext", 1, "gross", data.treeQuantity, "lt", item.lead(), "cum", data.cumulative.get(id), item.description()));
                Map<String, Long> totals = new TreeMap<>(); explode(id, data.treeQuantity, 1, 1, lines, totals); for (Map.Entry<String, Long> value : totals.entrySet()) lines.add(line("SUM", value.getKey(), value.getValue()));
                List<String> path = new ArrayList<>(List.of(id)); String current = id;
                while (data.bom.manufactured(current)) { List<Edge> children = data.bom.children.get(current); Edge best = children.getFirst(); for (Edge edge : children) if (data.cumulative.get(edge.child()) > data.cumulative.get(best.child())) best = edge; current = best.child(); path.add(current); }
                lines.add(line("CRITICAL", String.join(" -> ", path), "cum", data.cumulative.get(id)));
            }
            return lines;
        }
        List<String> costs(Plan plan, Map<String, StandardCost> costs) {
            Map<String, Long> usages = new HashMap<>(), values = new HashMap<>();
            for (String id : data.items.keySet()) { long usage = sum(plan.items.get(id).gross); usages.put(id, usage); values.put(id, usage * costs.get(id).total()); }
            Map<String, String> classes = Costing.classes(values); List<String> lines = new ArrayList<>(List.of("item,material,labor,total,usage,value,class"));
            for (String id : data.items.keySet()) { StandardCost cost = costs.get(id); lines.add(join(",", id, Report.money(cost.material()), Report.money(cost.labor()), Report.money(cost.total()), usages.get(id), Report.money(values.get(id)), classes.get(id))); } return lines;
        }
        List<String> exceptions(Plan plan) {
            List<String> messages = new ArrayList<>();
            for (String id : data.planningOrder) {
                ItemPlan p = plan.items.get(id); Item item = p.item;
                if (item.onHand() < item.safety()) messages.add(line("BELOW_SAFETY", id, "on hand", item.onHand(), "safety", item.safety()));
                for (PlannedOrder order : p.orders) {
                    String head = line(id, "order", order.number(), "receipt", order.receipt());
                    if (order.original() < 1) messages.add(line("PAST_DUE", head, "release", order.original(), "late", 1 - order.original(), "quantity", order.quantity()));
                    else if (order.original() == 1) messages.add(line("RELEASE", head, "quantity", order.quantity()));
                }
                long[] balances = new long[data.horizon + 1]; long balance = item.onHand(), covered = 0;
                for (int week = 1; week <= data.horizon; week++) { balance -= p.gross[week]; balances[week] = balance; }
                for (ScheduleRow receipt : data.receipts.get(id)) {
                    int need = 0; for (int week = 1; week <= data.horizon; week++) if (balances[week] + covered < item.safety()) { need = week; break; }
                    String head = line(id, "receipt line", receipt.line(), "week", receipt.week(), "quantity", receipt.quantity());
                    if (need == 0) messages.add("CANCEL " + head); else if (need < receipt.week()) messages.add(line("EXPEDITE", head, "to", need)); else if (need > receipt.week()) messages.add(line("DEFER", head, "to", need)); covered += receipt.quantity();
                }
                if (data.bom.manufactured(id) && !data.routings.containsKey(id)) messages.add("NO_ROUTING " + id);
                if (sum(p.gross) == 0 && item.onHand() > 0) messages.add(line("NO_DEMAND", id, "on hand", item.onHand()));
            }
            for (Center center : data.centers.values()) for (int week = 1; week <= data.horizon; week++) if (plan.overloads.get(center.id())[week] > 0) messages.add(line("OVERLOAD", center.id(), "week", week, "load", plan.loads.get(center.id())[week], "available", center.available()));
            List<String> lines = new ArrayList<>(); for (String error : data.errors) lines.add("ERROR " + error); lines.addAll(messages);
            StringBuilder summary = new StringBuilder("SUMMARY errors " + data.errors.size());
            for (String kind : List.of("BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD")) {
                long count = messages.stream().filter(message -> message.startsWith(kind + " ")).count(); summary.append(' ').append(kind.toLowerCase(java.util.Locale.ROOT)).append(' ').append(count);
            }
            lines.add(summary.toString()); return lines;
        }
        List<String> capacities(Plan plan) {
            List<String> lines = new ArrayList<>(); Map<String, Long> totals = new HashMap<>();
            for (Center center : data.centers.values()) {
                long[] loads = plan.loads.get(center.id()), over = plan.overloads.get(center.id()), leveled = Capacity.level(loads, center.available()), utilization = new long[data.horizon];
                long total = sum(loads), available = center.available() * data.horizon, largest = 0; totals.put(center.id(), total); int peak = 0, overloaded = 0;
                for (int week = 1; week <= data.horizon; week++) { utilization[week - 1] = Report.percent(loads[week], center.available()); if (loads[week] > largest) { largest = loads[week]; peak = week; } if (over[week] > 0) overloaded++; }
                lines.add(line("CENTER", center.id(), "minutes", center.minutes(), "efficiency", center.efficiency(), "available", center.available(), center.description()));
                lines.add(Report.table("WEEK", data.weeks, 7)); lines.add(Report.table("LOAD", weeks(loads), 7)); lines.add(Report.table("UTIL", utilization, 7)); lines.add(Report.table("OVER", weeks(over), 7)); lines.add(Report.table("LEVELED", weeks(leveled), 7));
                lines.add(line("TOTAL", "load", total, "available", available, "utilization", Report.percent(total, available), "overloaded", overloaded, "peak", peak, "backlog", Math.max(0, leveled[1] - center.available())));
            }
            List<String> order = new ArrayList<>(data.centers.keySet());
            order.sort((a, b) -> { long left = totals.get(a) * data.centers.get(b).available(), right = totals.get(b) * data.centers.get(a).available(); return left == right ? a.compareTo(b) : Long.compare(right, left); });
            for (int i = 0; i < order.size(); i++) { String id = order.get(i); lines.add(line("RANK", i + 1, id, "load", totals.get(id), "utilization", Report.percent(totals.get(id), data.centers.get(id).available() * data.horizon))); } return lines;
        }
        List<String> promises(List<Promise> promises, Plan baseline, Plan finalPlan) {
            List<String> lines = new ArrayList<>(); int onTime = 0, late = 0, rejected = 0;
            for (Promise promise : promises) {
                Inquiry inquiry = promise.inquiry; String head = line("ORDER", inquiry.id(), inquiry.item(), "quantity", inquiry.quantity(), "requested", inquiry.week()), material = promise.materialWeek == 0 ? "none" : Integer.toString(promise.materialWeek);
                if (promise.week == 0) { rejected++; lines.add(line(head, "rejected", "material", material, "reason", promise.reason)); continue; }
                if (promise.week == inquiry.week()) { onTime++; lines.add(line(head, "promised", promise.week)); }
                else { late++; lines.add(line(head, "promised", promise.week, "late", promise.week - inquiry.week(), "material", material, "reason", promise.reason)); }
                for (String id : data.planningOrder) for (Supply supply : finalPlan.items.get(id).orderSupplies) if (supply.serves(inquiry.id())) { PlannedOrder order = supply.order; lines.add("  " + line("SUPPLY", id, "order", order.number(), "receipt", order.receipt(), "release", order.release(), "quantity", order.quantity())); }
            }
            for (String id : data.planningOrder) {
                ItemPlan before = baseline.items.get(id), after = finalPlan.items.get(id); int first = 0;
                for (int week = 1; week <= data.horizon; week++) if (before.plannedReceipts[week] != after.plannedReceipts[week]) { first = week; break; }
                if (first > 0) lines.add(line("CHANGE", id, "from", first, "planned", sum(before.plannedReceipts), "->", sum(after.plannedReceipts), "orders", before.orders.size(), "->", after.orders.size()));
            }
            lines.add(line("SUMMARY", "orders", promises.size(), "on_time", onTime, "late", late, "rejected", rejected)); return lines;
        }
        List<String> releases(Plan plan) {
            List<PlannedOrder> orders = new ArrayList<>(); Map<String, Long> available = new HashMap<>();
            for (String id : data.planningOrder) { for (PlannedOrder order : plan.items.get(id).orders) if (order.release() == 1) orders.add(order); available.put(id, data.items.get(id).onHand() + data.scheduled.get(id)[1]); }
            orders.sort(Comparator.comparingInt(PlannedOrder::original).thenComparing(PlannedOrder::item).thenComparingInt(PlannedOrder::number));
            List<String> lines = new ArrayList<>(); int made = 0, readyCount = 0, bought = 0; long purchases = 0;
            for (PlannedOrder order : orders) {
                Item item = data.items.get(order.item()); String head = line(order.item(), "order", order.number(), "receipt", order.receipt(), "quantity", order.quantity()); if (order.original() < 1) head += " late " + (1 - order.original());
                if (!data.bom.manufactured(order.item())) { long value = order.quantity() * item.material(); bought++; purchases += value; lines.add(line("BUY", head, "value", Report.money(value))); continue; }
                made++; boolean ready = true; List<String> details = new ArrayList<>();
                for (Edge edge : data.bom.children.get(order.item())) { long need = edge.need(order.quantity()), have = available.get(edge.child()); if (need > have) ready = false; details.add("  " + line("PICK", edge.child(), "need", need, "available", have, "short", Math.max(0, need - have))); }
                if (ready) { readyCount++; for (Edge edge : data.bom.children.get(order.item())) available.put(edge.child(), available.get(edge.child()) - edge.need(order.quantity())); }
                List<Operation> operations = data.routings.getOrDefault(order.item(), List.of());
                for (int i = 0; i < operations.size(); i++) { Operation operation = operations.get(i); int week = Capacity.operationWeek(order.receipt(), item.lead(), i, operations.size()); details.add("  " + line("OPERATION", operation.number(), operation.center(), "week", week, "minutes", operation.minutes(order.quantity()))); }
                lines.add(line("MAKE", head, ready ? "READY" : "SHORT")); lines.addAll(details);
            }
            lines.add(line("SUMMARY", "make", made, "ready", readyCount, "short", made - readyCount, "buy", bought, "value", Report.money(purchases))); return lines;
        }
        List<String> valuePlan(Plan plan, Map<String, StandardCost> costs) {
            List<String> lines = new ArrayList<>(List.of("week,inventory,purchases,labor"));
            for (int week = 1; week <= data.horizon; week++) {
                long inventory = 0, purchases = 0, labor = 0;
                for (String id : data.planningOrder) { ItemPlan p = plan.items.get(id); inventory += p.onHand[week] * costs.get(id).total(); if (data.bom.manufactured(id)) labor += p.plannedReleases[week] * p.item.labor(); else purchases += p.plannedReleases[week] * p.item.material(); }
                lines.add(join(",", week, Report.money(inventory), Report.money(purchases), Report.money(labor)));
            }
            return lines;
        }
    }
    public static void main(String[] args) throws IOException {
        Data data = new Data(); Planner planner = new Planner(data); Plan baseline = planner.run(List.of()); Promised promised = planner.promiseInquiries(baseline); Plan finalPlan = promised.plan(); planner.peg(finalPlan); Map<String, StandardCost> costs = Costing.rollup(data.items, data.bom, data.planningOrder);
        Report.write("mrp_grid.txt", planner.grid(finalPlan)); Report.write("pegging.txt", planner.pegging(finalPlan)); Report.write("bom_tree.txt", planner.trees()); Report.write("cost_rollup.csv", planner.costs(finalPlan, costs)); Report.write("exceptions.txt", planner.exceptions(finalPlan)); Report.write("capacity.txt", planner.capacities(finalPlan)); Report.write("promises.txt", planner.promises(promised.promises(), baseline, finalPlan)); Report.write("releases.txt", planner.releases(finalPlan)); Report.write("value_plan.csv", planner.valuePlan(finalPlan, costs));
    }
}
