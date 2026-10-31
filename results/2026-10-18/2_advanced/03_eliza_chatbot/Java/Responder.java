import java.util.ArrayList;
import java.util.List;
import java.util.Map;

final class Responder {
    static List<String> reflect(List<String> words, Map<String, List<String>> substitutions) {
        List<String> result = new ArrayList<>();
        for (String word : words) result.addAll(substitutions.getOrDefault(word, List.of(word)));
        return result;
    }
    static String build(String text, List<List<String>> bindings, Map<String, List<String>> post) {
        StringBuilder reply = new StringBuilder();
        for (int index = 0; index < text.length();) {
            if (index + 3 <= text.length() && ScriptLoader.reference(text.substring(index, index + 3))) {
                int n = text.charAt(index + 1) - '0';
                if (n >= 1 && n <= bindings.size()) reply.append(String.join(" ", reflect(bindings.get(n - 1), post)));
                index += 3;
            } else reply.append(text.charAt(index++));
        }
        String result = String.join(" ", Helpers.words(reply.toString()));
        return !result.isEmpty() && result.charAt(0) >= 'a' && result.charAt(0) <= 'z' ? Character.toUpperCase(result.charAt(0)) + result.substring(1) : result;
    }
    static List<String> restate(List<String> arguments, List<List<String>> bindings) {
        List<String> result = new ArrayList<>();
        for (String argument : arguments) {
            if (!ScriptLoader.reference(argument)) result.add(argument);
            else { int n = argument.charAt(1) - '0'; if (n >= 1 && n <= bindings.size()) result.addAll(bindings.get(n - 1)); }
        }
        return result;
    }
    static List<String> wrap(String text) {
        List<String> result = new ArrayList<>();
        for (String word : Helpers.words(text)) {
            if (result.isEmpty()) result.add("ELIZA: " + word);
            else if (result.getLast().length() + 1 + word.length() <= 72) result.set(result.size() - 1, result.getLast() + " " + word);
            else result.add("       " + word);
        }
        return result;
    }
}
