import java.util.regex.Pattern;

public class Main {
    public static void main(String[] args) {
        String[] values = {"AAABBBCCCD", "W".repeat(12) + "B" + "W".repeat(12) + "BBB", "ALGORITHM", "MISSISSIPPI", "X".repeat(10) + "Y".repeat(21) + "Z"};
        var runs = Pattern.compile("(.)\\1*");
        var counts = Pattern.compile("(\\d+)([A-Z])");
        for (String text : values) {
            String encoded = runs.matcher(text).replaceAll(m -> m.group().length() + m.group().substring(0, 1));
            String decoded = counts.matcher(encoded).replaceAll(m -> m.group(2).repeat(Integer.parseInt(m.group(1))));
            System.out.println(text + " -> " + encoded + " -> " + decoded);
        }
    }
}
