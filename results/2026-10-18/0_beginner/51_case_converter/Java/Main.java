import java.util.Arrays;
import java.util.List;
import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        String[] ids = {
            "user_name", "maxRetryCount", "ShoppingCartItem", "background-color",
            "get_last_login_time", "isEmailAddressValid"};
        for (String id : ids) {
            List<String> words = Arrays.stream(id.split("[_-]|(?=[A-Z])"))
                    .filter(w -> !w.isEmpty())
                    .map(w -> w.toLowerCase(Locale.ROOT))
                    .toList();
            List<String> capitals = words.stream()
                    .map(w -> w.substring(0, 1).toUpperCase(Locale.ROOT) + w.substring(1))
                    .toList();
            String camel = words.get(0) + String.join("", capitals.subList(1, capitals.size()));
            System.out.println(id + ": snake=" + String.join("_", words) + ", camel=" + camel
                    + ", pascal=" + String.join("", capitals) + ", kebab=" + String.join("-", words));
        }
    }
}
