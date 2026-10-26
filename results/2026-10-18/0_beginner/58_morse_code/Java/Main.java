import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

public class Main {
    public static void main(String[] args) {
        String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        String[] codes = ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.".split(" ");
        Map<String, String> reverse = new HashMap<>();
        for (int i = 0; i < codes.length; i++) {
            reverse.put(codes[i], String.valueOf(alphabet.charAt(i)));
        }
        String message = "MEET ME AT PIER 9 AT 1745";
        String encoded = String.join(" / ", Arrays.stream(message.split(" "))
                .map(word -> String.join(" ", word.chars().mapToObj(ch -> codes[alphabet.indexOf(ch)]).toList()))
                .toList());
        String decoded = String.join(" ", Arrays.stream(encoded.split(" / "))
                .map(word -> String.join("", Arrays.stream(word.split(" ")).map(reverse::get).toList()))
                .toList());
        System.out.println(encoded);
        System.out.println(decoded);
    }
}
