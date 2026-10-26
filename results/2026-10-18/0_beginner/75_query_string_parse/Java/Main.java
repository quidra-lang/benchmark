import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    public static void main(String[] args) {
        String[] queries = {"name=Alice+Smith&age=30&city=New%20York",
            "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
            "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
            "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"};
        for (int index = 0; index < queries.length; index++) {
            Map<String, List<String>> values = new TreeMap<>();
            for (String item : queries[index].split("&")) {
                int equals = item.indexOf('=');
                String key = URLDecoder.decode(equals < 0 ? item : item.substring(0, equals), StandardCharsets.UTF_8);
                String value = URLDecoder.decode(equals < 0 ? "" : item.substring(equals + 1), StandardCharsets.UTF_8);
                values.computeIfAbsent(key, k -> new ArrayList<>()).add(value);
            }
            System.out.println("query " + (index + 1) + ":");
            for (var entry : values.entrySet()) {
                List<String> quoted = entry.getValue().stream().map(v -> "\"" + v + "\"").toList();
                System.out.println("  " + entry.getKey() + ": " + String.join(", ", quoted));
            }
        }
    }
}
