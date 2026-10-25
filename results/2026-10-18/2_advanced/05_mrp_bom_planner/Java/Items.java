import java.io.IOException;
import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

record Item(String id, int lead, String rule, long first, long second, long safety, long onHand, long material, long labor, String description) {
    String lotLabel() { return rule.equals("LFL") ? rule : rule.equals("MIN") ? "MIN " + first + "/" + second : rule + " " + first; }
}
final class Items {
    static Map<String, Item> read(java.util.List<String> errors) throws IOException {
        Map<String, Item> items = new TreeMap<>(); Set<String> rules = Set.of("LFL", "FOQ", "POQ", "MIN");
        for (Main.Row row : Main.rows("items.csv")) {
            String[] f = row.fields(); long[] lot = Arrays.stream(f[3].split("/")).mapToLong(Long::parseLong).toArray(); String error = "";
            boolean fits = f[2].equals("LFL") ? lot.length == 1 && lot[0] == 0 : f[2].equals("MIN") ? lot.length == 2 && lot[0] >= 1 && lot[1] >= 1 : lot.length == 1 && lot[0] >= 1;
            if (items.containsKey(f[0])) error = "duplicate item " + f[0];
            else if (!rules.contains(f[2])) error = "unknown lot rule " + f[2];
            else if (!fits) error = "bad lot parameter " + f[3] + " for " + f[2];
            if (!error.isEmpty()) Main.error(errors, "items.csv", row.line(), error);
            else items.put(f[0], new Item(f[0], Integer.parseInt(f[1]), f[2], lot[0], lot.length == 2 ? lot[1] : 0, Long.parseLong(f[4]), Long.parseLong(f[5]), Long.parseLong(f[6]), Long.parseLong(f[7]), f[8]));
        }
        return items;
    }
}
