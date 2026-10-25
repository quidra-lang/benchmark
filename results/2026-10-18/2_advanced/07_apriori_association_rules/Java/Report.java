import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class Report {
    static String fractionText(Fraction value) {
        long numerator = Math.abs(value.numerator()), scaled = 10000 * numerator / value.denominator();
        String sign = value.numerator() < 0 ? "-" : "", decimalSign = value.numerator() < 0 && scaled > 0 ? "-" : "";
        return sign + numerator + "/" + value.denominator() + "=" + decimalSign + scaled / 10000 + "." + String.format(Locale.ROOT, "%04d", scaled % 10000);
    }
    static String percent(long part, long whole) { long scaled = 10000 * part / whole; return scaled / 100 + "." + String.format(Locale.ROOT, "%02d", scaled % 100) + "%"; }
    static String money(long cents) { return cents / 100 + "." + String.format(Locale.ROOT, "%02d", cents % 100); }
    static String itemsetText(Itemset itemset) { return String.join("+", itemset.items()); }
    static String arrow(Rule rule) { return itemsetText(rule.antecedent) + " -> " + itemsetText(rule.consequent); }
    static List<String> rulesCsv(List<Rule> rules) {
        List<String> lines = new ArrayList<>(List.of("rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement"));
        for (Rule r : rules) lines.add(String.join(",", Integer.toString(r.rank), itemsetText(r.antecedent), itemsetText(r.consequent), Long.toString(r.count), fractionText(r.support), fractionText(r.confidence), fractionText(r.lift), fractionText(r.leverage), r.conviction == null ? "INF" : fractionText(r.conviction), fractionText(r.improvement)));
        return lines;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.createDirectories(Path.of("output")); Files.writeString(Path.of("output", name), String.join("\n", lines) + (lines.isEmpty() ? "" : "\n"), StandardCharsets.US_ASCII);
    }
}
