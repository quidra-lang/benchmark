import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.MatchResult;
import java.util.regex.Pattern;

public class Main {
    static class Parser {
        final List<String> tokens;
        final Map<String, Integer> variables;
        int position;

        Parser(List<String> tokens, int position, Map<String, Integer> variables) {
            this.tokens = tokens;
            this.position = position;
            this.variables = variables;
        }

        boolean take(String token) {
            if (position >= tokens.size() || !tokens.get(position).equals(token)) {
                return false;
            }
            position++;
            return true;
        }

        int expression() {
            int result = term();
            while (position < tokens.size()
                    && (tokens.get(position).equals("+") || tokens.get(position).equals("-"))) {
                String operation = tokens.get(position++);
                int right = term();
                result = operation.equals("+") ? result + right : result - right;
            }
            return result;
        }

        int term() {
            int result = unary();
            while (position < tokens.size()
                    && (tokens.get(position).equals("*") || tokens.get(position).equals("/"))) {
                String operation = tokens.get(position++);
                int right = unary();
                if (operation.equals("/") && right == 0) {
                    throw new IllegalStateException("division by zero");
                }
                result = operation.equals("*") ? result * right : result / right;
            }
            return result;
        }

        int unary() {
            if (take("-")) {
                return -unary();
            }
            if (take("(")) {
                int result = expression();
                take(")");
                return result;
            }
            String token = tokens.get(position++);
            if (token.charAt(0) >= '0' && token.charAt(0) <= '9') {
                return Integer.parseInt(token);
            }
            Integer value = variables.get(token);
            if (value == null) {
                throw new IllegalStateException("undefined variable " + token);
            }
            return value;
        }
    }

    public static void main(String[] args) {
        String[] lines = {"width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
            "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth",
            "width = (width+3)*-(2-4)", "width * shift - height"};
        Map<String, Integer> variables = new HashMap<>();
        var tokenPattern = Pattern.compile("[0-9]+|[a-z]+|[^ ]");
        for (String line : lines) {
            List<String> tokens = tokenPattern.matcher(line).results().map(MatchResult::group).toList();
            boolean assignment = tokens.size() > 1 && tokens.get(1).equals("=");
            String name = assignment ? tokens.get(0) : null;
            try {
                int result = new Parser(tokens, assignment ? 2 : 0, variables).expression();
                if (assignment) {
                    variables.put(name, result);
                    System.out.println(name + " = " + result);
                } else {
                    System.out.println(result);
                }
            } catch (IllegalStateException error) {
                System.out.println("error: " + error.getMessage());
            }
        }
    }
}
