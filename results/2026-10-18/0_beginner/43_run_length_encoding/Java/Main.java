import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        String[] values = {"AAABBBCCCD", "W".repeat(12) + "B" + "W".repeat(12) + "BBB", "ALGORITHM", "MISSISSIPPI", "X".repeat(10) + "Y".repeat(21) + "Z"};
        for (String text : values) {
            StringBuilder encoded = new StringBuilder();
            for (int i = 0; i < text.length();) { int j = i + 1; while (j < text.length() && text.charAt(j) == text.charAt(i)) j++; encoded.append(j - i).append(text.charAt(i)); i = j; }
            StringBuilder decoded = new StringBuilder();
            for (int i = 0; i < encoded.length();) { int count = 0; while (encoded.charAt(i) >= '0' && encoded.charAt(i) <= '9') count = count * 10 + encoded.charAt(i++) - '0'; decoded.append(String.valueOf(encoded.charAt(i++)).repeat(count)); }
            System.out.println(text + " -> " + encoded + " -> " + decoded);
        }
    }
}
