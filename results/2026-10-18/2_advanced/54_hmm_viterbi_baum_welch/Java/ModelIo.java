import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.math.*;
import java.io.IOException;

final class ModelIo {
    static final class Model {
        String name;
        char[] states, symbols;
        char missing;
        double[] pi;
        double[][] a, b;
        Model(String name, char[] states, char[] symbols, char missing, double[] pi, double[][] a,
              double[][] b) {
            this.name = name;
            this.states = states;
            this.symbols = symbols;
            this.missing = missing;
            this.pi = normalize(pi);
            this.a = new double[a.length][];
            this.b = new double[b.length][];
            for (int i = 0; i < a.length; i++)
                this.a[i] = normalize(a[i]);
            for (int i = 0; i < b.length; i++)
                this.b[i] = normalize(b[i]);
        }
    }
    record Data(Model model, List<String> sequences, List<String> labeled, Map<String, String[]> params) {}
    static double[] normalize(double[] values) {
        double sum = 0;
        for (double value : values)
            sum += value;
        double[] result = new double[values.length];
        for (int i = 0; i < values.length; i++)
            result[i] = values[i] / sum;
        return result;
    }
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static double[] numbers(String[] words, int start) {
        double[] result = new double[words.length - start];
        for (int i = start; i < words.length; i++)
            result[i - start] = Double.parseDouble(words[i]);
        return result;
    }
    static char[] letters(String line) {
        String[] w = line.split(" ");
        char[] result = new char[w.length - 1];
        for (int i = 1; i < w.length; i++)
            result[i - 1] = w[i].charAt(0);
        return result;
    }
    static Data read() throws IOException {
        List<String> input = lines("model.txt");
        char[] states = letters(input.get(0)), symbols = letters(input.get(1));
        char missing = input.get(2).split(" ")[1].charAt(0);
        int k = states.length;
        double[] pi = numbers(input.get(3).split(" "), 1);
        double[][] a = new double[k][], b = new double[k][];
        for (int i = 0; i < k; i++) {
            a[i] = numbers(input.get(4 + i).split(" "), 2);
            b[i] = numbers(input.get(4 + k + i).split(" "), 2);
        }
        Map<String, String[]> params = new HashMap<>();
        for (String line : lines("params.txt")) {
            String[] words = line.split(" ");
            params.put(words[0], Arrays.copyOfRange(words, 1, words.length));
        }
        return new Data(new Model("INITIAL", states, symbols, missing, pi, a, b), lines("sequences.txt"),
                        lines("labeled.txt"), params);
    }
    static String real(double value, int digits) {
        if (Double.isNaN(value))
            return "-";
        BigDecimal result = BigDecimal.valueOf(value).setScale(digits, RoundingMode.HALF_UP);
        if (result.signum() == 0)
            result = BigDecimal.ZERO.setScale(digits);
        return result.toPlainString();
    }
    static String f(double value) {
        return real(value, 4);
    }
    static String values(double[] values) {
        String text = "";
        for (double value : values)
            text += " " + f(value);
        return text;
    }
    static String names(char[] names) {
        String text = "";
        for (char name : names)
            text += " " + name;
        return text;
    }
    static List<String> format(Model model) {
        List<String> out = new ArrayList<>(List.of("MODEL " + model.name, "STATES" + names(model.states),
                                                   "SYMBOLS" + names(model.symbols),
                                                   "MISSING " + model.missing, "INITIAL" + values(model.pi)));
        for (int i = 0; i < model.states.length; i++)
            out.add("TRANSITION " + model.states[i] + values(model.a[i]));
        for (int i = 0; i < model.states.length; i++)
            out.add("EMISSION " + model.states[i] + values(model.b[i]));
        return out;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
