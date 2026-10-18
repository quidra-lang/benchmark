import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        String paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose " +
            "through careful names, small functions and honest tests. When a team agrees on shared rules for " +
            "internationalization, documentation and code review, every newcomer can read the code quickly, change it " +
            "safely and ship new improvements with confidence instead of fear, week after week.";
        List<List<String>> lines = new ArrayList<>();
        List<String> current = new ArrayList<>();
        int letters = 0;
        for (String word : paragraph.split(" ")) {
            if (!current.isEmpty() && letters + current.size() + word.length() > 30) {
                lines.add(current);
                current = new ArrayList<>();
                letters = 0;
            }
            current.add(word);
            letters += word.length();
        }
        if (!current.isEmpty()) lines.add(current);
        for (int i = 0; i < lines.size(); i++) {
            List<String> words = lines.get(i);
            String text;
            if (i == lines.size() - 1 || words.size() == 1) {
                text = String.join(" ",words);
                text += " ".repeat(30 - text.length());
            } else {
                int spaces = 30 - words.stream().mapToInt(String::length).sum();
                int gaps = words.size() - 1;
                StringBuilder line = new StringBuilder(words.get(0));
                for (int j = 1; j < words.size(); j++) {
                    line.append(" ".repeat(spaces / gaps + (j - 1 < spaces % gaps ? 1 : 0)));
                    line.append(words.get(j));
                }
                text = line.toString();
            }
            System.out.println("|" + text + "|");
        }
    }
}
