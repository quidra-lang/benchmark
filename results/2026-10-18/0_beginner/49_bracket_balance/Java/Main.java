import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        for (String text : new String[]{"(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}", "f(a[i] + g(b)}", "(1 + 2)) * 3", "if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}"}) {
            Deque<Character> stack = new ArrayDeque<>(); int error = -1;
            for (int i = 0; i < text.length(); i++) {
                char ch = text.charAt(i); int close = ")]}".indexOf(ch);
                if ("([{".indexOf(ch) >= 0) stack.push(ch);
                else if (close >= 0) { if (stack.isEmpty() || stack.peek() != "([{".charAt(close)) { error = i; break; } stack.pop(); }
            }
            if (error < 0 && !stack.isEmpty()) error = text.length();
            System.out.println(text + " -> " + (error < 0 ? "balanced" : "error at index " + error));
        }
    }
}
