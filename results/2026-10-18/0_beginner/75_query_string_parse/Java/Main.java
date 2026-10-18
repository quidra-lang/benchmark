import java.util.*;
import java.math.*;

public class Main {
    static String decode(String text) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            char ch = text.charAt(i);
            if (ch == '+') result.append(' ');
            else if (ch == '%') {
                result.append((char)Integer.parseInt(text.substring(i + 1,i + 3),16));
                i += 2;
            } else result.append(ch);
        }
        return result.toString();
    }
    public static void main(String[] args) {
        String[] queries = {"name=Alice+Smith&age=30&city=New%20York",
            "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
            "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
            "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"};
        for (int index = 0; index < queries.length; index++) {
            Map<String,List<String>> values = new TreeMap<>();
            for (String item : queries[index].split("&")) {
                int equals = item.indexOf('=');
                String key = decode(equals < 0 ? item : item.substring(0,equals));
                String value = decode(equals < 0 ? "" : item.substring(equals + 1));
                values.computeIfAbsent(key,k -> new ArrayList<>()).add(value);
            }
            System.out.println("query " + (index + 1) + ":");
            for (var entry : values.entrySet()) {
                List<String> quoted = entry.getValue().stream().map(v -> "\"" + v + "\"").toList();
                System.out.println("  " + entry.getKey() + ": " + String.join(", ",quoted));
            }
        }
    }
}
