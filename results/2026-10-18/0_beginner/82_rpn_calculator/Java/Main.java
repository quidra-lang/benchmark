import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        String[] expressions = {"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",
            "15 7 1 1 + - / 3 * 2 1 1 + + -", "4 2 5 * + 1 3 2 * - 5 + /",
            "2 3 4 + 5", "46341 46339 * -2 /"};
        for (String expression : expressions) {
            Deque<Integer> stack = new ArrayDeque<>();
            String error = null;
            for (String token : expression.split(" ")) {
                if (token.length() == 1 && "+-*/".contains(token)) {
                    if (stack.size() < 2) {
                        error = "stack underflow";
                        break;
                    }
                    int b = stack.pop(), a = stack.pop();
                    if (token.equals("/") && b == 0) {
                        error = "division by zero";
                        break;
                    }
                    int value = switch (token) {
                        case "+" -> a + b;
                        case "-" -> a - b;
                        case "*" -> a * b;
                        default -> a / b;
                    };
                    stack.push(value);
                } else stack.push(Integer.parseInt(token));
            }
            if (error == null && stack.size() != 1) error = "leftover operands";
            System.out.println(expression + " => " + (error == null ? stack.peek() : "error: " + error));
        }
    }
}
