import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    public static void main(String[] args) {
        String[] lines = {
            "date,region,product,quantity,unit_price",
            "2026-04-01,north,notebook,10,200",
            "2026-04-01,east,marker,6,150",
            "2026-04-01,south,eraser,25,80",
            "2026-04-02,west,stapler,4,600",
            "2026-04-02,north,marker,8,150",
            "2026-04-02,east,notebook,9,200",
            "2026-04-03,south,stapler,3,600",
            "2026-04-03,west,eraser,15,80",
            "2026-04-03,north,eraser,20,80",
            "2026-04-04,east,stapler,5,600",
            "2026-04-04,south,notebook,6,200",
            "2026-04-04,west,marker,8,150"};
        Map<String,Integer> regions = new HashMap<>(), products = new TreeMap<>(), days = new TreeMap<>();
        for (int i = 1; i < lines.length; i++) {
            String[] fields = lines[i].split(",");
            int quantity = Integer.parseInt(fields[3]), amount = quantity * Integer.parseInt(fields[4]);
            regions.merge(fields[1],amount,Integer::sum);
            products.merge(fields[2],quantity,Integer::sum);
            days.merge(fields[0],amount,Integer::sum);
        }
        System.out.println("total: " + days.values().stream().mapToInt(Integer::intValue).sum());
        List<String> names = new ArrayList<>(regions.keySet());
        names.sort(Comparator.<String>comparingInt(regions::get).reversed().thenComparing(Comparator.naturalOrder()));
        for (String name : names) System.out.println(name + ": " + regions.get(name));
        for (var entry : products.entrySet()) System.out.println(entry.getKey() + ": " + entry.getValue());
        var best = days.entrySet().stream()
                .min(Comparator.<Map.Entry<String, Integer>>comparingInt(Map.Entry::getValue).reversed()
                        .thenComparing(Map.Entry::getKey)).orElseThrow();
        System.out.println("best day: " + best.getKey() + " (" + best.getValue() + ")");
    }
}
