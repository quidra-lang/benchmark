import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

record SourceLine(int number, String text) {}
record Field(String name, String value) {}
record Token(String kind, String text, boolean spaced) {}
record DecodedWord(String text, boolean decoded, boolean error) {}
record Parameters(String type, String subtype, Map<String, String> values) {}
final class Header {
    final List<Field> fields = new ArrayList<>();
    final List<Integer> invalid = new ArrayList<>();
    String value(String name) { for (Field field : fields) if (field.name().equals(Headers.lower(name))) return field.value(); return null; }
    int count(String name) { int count = 0; for (Field field : fields) if (field.name().equals(Headers.lower(name))) count++; return count; }
}
final class Headers {
    static final String ADDRESS_SPECIALS = "<>:;@,.", ADDRESS_WORDS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~";
    static final String MIME_SPECIALS = "/;=", MIME_EXCLUDED = "()<>@,;:\\\"/[]?=";
    static String lower(String text) { return text.toLowerCase(Locale.ROOT); }
    static boolean whitespace(char letter) { return letter == ' ' || letter == '\t'; }
    static String rstrip(String text) { int end = text.length(); while (end > 0 && whitespace(text.charAt(end - 1))) end--; return text.substring(0, end); }
    static String strip(String text) { int start = 0; while (start < text.length() && whitespace(text.charAt(start))) start++; return rstrip(text.substring(start)); }
    static List<String> words(String text) {
        List<String> words = new ArrayList<>(); int position = 0;
        while (position < text.length()) {
            while (position < text.length() && whitespace(text.charAt(position))) position++;
            int start = position; while (position < text.length() && !whitespace(text.charAt(position))) position++;
            if (position > start) words.add(text.substring(start, position));
        }
        return words;
    }
    static String collapse(String text) { return String.join(" ", words(text)); }
    static Header parseFields(List<SourceLine> lines) {
        Header header = new Header(); List<String> names = new ArrayList<>(), values = new ArrayList<>(); boolean inField = false;
        for (SourceLine line : lines) {
            String text = line.text();
            if (whitespace(text.charAt(0))) {
                if (inField) values.set(values.size() - 1, values.getLast() + text); else header.invalid.add(line.number());
                continue;
            }
            int split = text.indexOf(':'); String name = split < 0 ? "" : text.substring(0, split);
            inField = !name.isEmpty() && name.chars().allMatch(letter -> letter >= 33 && letter <= 126);
            if (inField) { names.add(lower(name)); values.add(text.substring(split + 1)); } else header.invalid.add(line.number());
        }
        for (int i = 0; i < names.size(); i++) header.fields.add(new Field(names.get(i), strip(values.get(i))));
        return header;
    }
    static String removeComments(String text) {
        StringBuilder result = new StringBuilder(); int depth = 0;
        for (int i = 0; i < text.length(); i++) {
            char letter = text.charAt(i);
            if (depth == 0) { if (letter == '(') { depth = 1; result.append(' '); } else result.append(letter); }
            else if (letter == '\\') i++;
            else if (letter == '(') depth++;
            else if (letter == ')') depth--;
        }
        return depth == 0 ? result.toString() : null;
    }
    static List<Token> tokenize(String text, boolean mime) {
        List<Token> tokens = new ArrayList<>(); int position = 0; boolean spaced = false;
        String specials = mime ? MIME_SPECIALS : ADDRESS_SPECIALS;
        while (position < text.length()) {
            char letter = text.charAt(position);
            if (whitespace(letter)) { spaced = true; position++; continue; }
            if (letter == '(') {
                int depth = 1; position++;
                while (position < text.length() && depth > 0) { char next = text.charAt(position++); if (next == '\\') position++; else if (next == '(') depth++; else if (next == ')') depth--; }
                if (depth != 0) return null;
                spaced = true; continue;
            }
            if (letter == '"') {
                position++; StringBuilder value = new StringBuilder(); boolean closed = false;
                while (position < text.length()) {
                    char next = text.charAt(position++);
                    if (next == '"') { closed = true; break; }
                    if (next == '\\') { if (position == text.length()) return null; next = text.charAt(position++); }
                    value.append(next);
                }
                if (!closed) return null;
                tokens.add(new Token("quoted", value.toString(), spaced));
            } else if (specials.indexOf(letter) >= 0) { tokens.add(new Token("" + letter, "" + letter, spaced)); position++; }
            else if (wordCharacter(letter, mime)) {
                int start = position; while (position < text.length() && wordCharacter(text.charAt(position), mime)) position++;
                tokens.add(new Token("word", text.substring(start, position), spaced));
            } else return null;
            spaced = false;
        }
        return tokens;
    }
    static boolean wordCharacter(char letter, boolean mime) { return mime ? letter >= 33 && letter <= 126 && MIME_EXCLUDED.indexOf(letter) < 0 : ADDRESS_WORDS.indexOf(letter) >= 0; }
    static String decodeQ(String text) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            char letter = text.charAt(i);
            if (letter == '_') result.append(' ');
            else if (letter == '=') {
                if (i + 2 >= text.length()) return null;
                int first = Mime.hex(text.charAt(i + 1)), second = Mime.hex(text.charAt(i + 2));
                if (first < 0 || second < 0) return null;
                result.append((char) (first * 16 + second)); i += 2;
            } else result.append(letter);
        }
        return result.toString();
    }
    static DecodedWord decodeWord(String word) {
        if (word.length() < 4 || !word.startsWith("=?") || !word.endsWith("?=")) return new DecodedWord(word, false, false);
        String[] parts = word.substring(2, word.length() - 2).split("\\?", -1);
        if (parts.length != 3 || parts[0].isEmpty() || parts[1].isEmpty() || parts[2].isEmpty()) return new DecodedWord(word, false, false);
        String decoded = null;
        if (lower(parts[0]).equals("us-ascii")) {
            if (parts[1].equals("Q") || parts[1].equals("q")) decoded = decodeQ(parts[2]);
            else if (parts[1].equals("B") || parts[1].equals("b")) decoded = Mime.strictBase64(parts[2]);
        }
        if (decoded == null || !decoded.chars().allMatch(letter -> letter >= 32 && letter <= 126)) return new DecodedWord(word, false, true);
        return new DecodedWord(decoded, true, false);
    }
    static DecodedText unstructured(String value) {
        StringBuilder text = new StringBuilder(); boolean previous = false, error = false, first = true;
        for (String word : words(value)) {
            DecodedWord decoded = decodeWord(word);
            if (!first && !(previous && decoded.decoded())) text.append(' ');
            text.append(decoded.text()); previous = decoded.decoded(); error |= decoded.error(); first = false;
        }
        return new DecodedText(collapse(text.toString()), error);
    }
    static Parameters parameters(String value, boolean withSubtype) {
        List<Token> tokens = tokenize(value, true);
        if (tokens == null || tokens.isEmpty() || !tokens.getFirst().kind().equals("word")) return null;
        String type = lower(tokens.getFirst().text()), subtype = ""; int position = 1;
        if (withSubtype) {
            if (tokens.size() < 3 || !tokens.get(1).kind().equals("/") || !tokens.get(2).kind().equals("word")) return null;
            subtype = lower(tokens.get(2).text()); position = 3;
        }
        Map<String, String> values = new LinkedHashMap<>();
        while (position < tokens.size()) {
            if (position + 3 >= tokens.size() || !tokens.get(position).kind().equals(";") || !tokens.get(position + 1).kind().equals("word") || !tokens.get(position + 2).kind().equals("=") || !(tokens.get(position + 3).kind().equals("word") || tokens.get(position + 3).kind().equals("quoted"))) return null;
            values.putIfAbsent(lower(tokens.get(position + 1).text()), tokens.get(position + 3).text()); position += 4;
        }
        return new Parameters(type, subtype, values);
    }
}
