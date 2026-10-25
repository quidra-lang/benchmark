import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

record Center(String id, long minutes, long efficiency, long available, String description) {}
record Operation(String item, int number, String center, long setup, long run) { long minutes(long units) { return setup + units * run; } }
final class Capacity {
    static Map<String, Center> readCenters(List<String> errors) throws IOException {
        Map<String, Center> centers = new TreeMap<>();
        for (Main.Row row : Main.rows("workcenters.csv")) {
            String[] f = row.fields(); long minutes = Long.parseLong(f[1]), efficiency = Long.parseLong(f[2]); String error = "";
            if (centers.containsKey(f[0])) error = "duplicate center " + f[0]; else if (efficiency < 50 || efficiency > 150) error = "bad efficiency " + efficiency;
            if (!error.isEmpty()) Main.error(errors, "workcenters.csv", row.line(), error); else centers.put(f[0], new Center(f[0], minutes, efficiency, minutes * efficiency / 100, f[3]));
        }
        return centers;
    }
    static Map<String, List<Operation>> readRoutings(Map<String, Item> items, Map<String, Center> centers, Bom bom, List<String> errors) throws IOException {
        Map<String, List<Operation>> routes = new TreeMap<>();
        for (Main.Row row : Main.rows("routings.csv")) {
            String[] f = row.fields(); int number = Integer.parseInt(f[1]); long run = Long.parseLong(f[4]); String error = "";
            if (!items.containsKey(f[0])) error = "unknown item " + f[0];
            else if (!centers.containsKey(f[2])) error = "unknown center " + f[2];
            else if (!bom.manufactured(f[0])) error = "purchased item " + f[0];
            else if (run < 1) error = "bad run time " + run;
            else if (routes.getOrDefault(f[0], List.of()).stream().anyMatch(o -> o.number() == number)) error = "duplicate " + f[0] + " operation " + number;
            if (!error.isEmpty()) Main.error(errors, "routings.csv", row.line(), error);
            else routes.computeIfAbsent(f[0], key -> new ArrayList<>()).add(new Operation(f[0], number, f[2], Long.parseLong(f[3]), run));
        }
        for (List<Operation> operations : routes.values()) operations.sort(Comparator.comparingInt(Operation::number)); return routes;
    }
    static int operationWeek(int receipt, int lead, int index, int count) { return Math.max(receipt - lead + index * lead / count, 1); }
    static long[] level(long[] loads, long available) {
        long[] leveled = new long[loads.length]; long carry = 0;
        for (int week = loads.length - 1; week > 1; week--) { long total = loads[week] + carry; leveled[week] = Math.min(total, available); carry = total - leveled[week]; } leveled[1] = loads[1] + carry; return leveled;
    }
}
