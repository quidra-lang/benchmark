import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
final class CnfIo {
    record Formula(int variables, List<int[]> clauses) {}
    static final class Invalid extends RuntimeException {
        Invalid(String reason) {
            super(reason);
        }
    }
    static boolean number(String value) {
        return value.matches("0|[1-9][0-9]{0,5}");
    }
    static Formula read(String name) throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
        boolean header = false;
        int variables = 0, declared = 0;
        List<int[]> clauses = new ArrayList<>();
        List<Integer> clause = new ArrayList<>();
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            if (line.startsWith("c") || line.strip().isEmpty())
                continue;
            String[] tokens = line.strip().split(" +");
            if (tokens[0].equals("p")) {
                if (header)
                    throw new Invalid("duplicate header at line " + (i + 1));
                if (tokens.length != 4 || !tokens[1].equals("cnf") || !number(tokens[2]) ||
                    !number(tokens[3]))
                    throw new Invalid("bad header at line " + (i + 1));
                header = true;
                variables = Integer.parseInt(tokens[2]);
                declared = Integer.parseInt(tokens[3]);
            } else {
                if (!header)
                    throw new Invalid("missing header");
                for (String token : tokens) {
                    if (!token.matches("0|-?[1-9][0-9]{0,5}"))
                        throw new Invalid("bad token " + token + " at line " + (i + 1));
                    int literal = Integer.parseInt(token);
                    if (Math.abs(literal) > variables)
                        throw new Invalid("literal out of range " + token + " at line " + (i + 1));
                    if (literal == 0) {
                        clauses.add(clause.stream().mapToInt(Integer::intValue).toArray());
                        clause = new ArrayList<>();
                    } else
                        clause.add(literal);
                }
            }
        }
        if (!header)
            throw new Invalid("missing header");
        if (!clause.isEmpty())
            throw new Invalid("unterminated clause");
        if (clauses.size() != declared)
            throw new Invalid("clause count mismatch header=" + declared + " found=" + clauses.size());
        return new Formula(variables, clauses);
    }
    static List<String> modelLines(boolean[] model) {
        List<String> tokens = new ArrayList<>();
        for (int x = 1; x < model.length; x++)
            tokens.add(Integer.toString(model[x] ? x : -x));
        tokens.add("0");
        List<String> lines = new ArrayList<>();
        for (int i = 0; i < tokens.size(); i += 10)
            lines.add("v " + String.join(" ", tokens.subList(i, Math.min(i + 10, tokens.size()))));
        return lines;
    }
}
