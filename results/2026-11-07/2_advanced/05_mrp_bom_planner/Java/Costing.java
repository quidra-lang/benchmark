import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

record StandardCost(long material, long labor) { long total() { return material + labor; } }
final class Costing {
    static Map<String, StandardCost> rollup(Map<String, Item> items, Bom bom, List<String> planningOrder) {
        Map<String, StandardCost> costs = new HashMap<>();
        for (String id : planningOrder.reversed()) {
            Item item = items.get(id); long material = item.material(), labor = item.labor();
            for (Edge edge : bom.children.get(id)) { StandardCost child = costs.get(edge.child()); material += (edge.quantity() * (100 + edge.scrap()) * child.material() + 50) / 100; labor += (edge.quantity() * (100 + edge.scrap()) * child.labor() + 50) / 100; }
            costs.put(id, new StandardCost(material, labor));
        }
        return costs;
    }
    static Map<String, String> classes(Map<String, Long> values) {
        long total = 0, before = 0; for (long value : values.values()) total += value;
        List<String> order = new ArrayList<>(values.keySet()); order.sort(Comparator.comparingLong((String id) -> values.get(id)).reversed().thenComparing(Comparator.naturalOrder())); Map<String, String> classes = new HashMap<>();
        for (String id : order) { long value = values.get(id); classes.put(id, value == 0 ? "C" : 100 * before < 80 * total ? "A" : 100 * before < 95 * total ? "B" : "C"); before += value; } return classes;
    }
}
