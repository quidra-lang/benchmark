import java.nio.file.*;
import java.util.*;
final class Report {
    record Fraction(long numerator, long denominator) implements Comparable<Fraction> {
        Fraction {
            if (denominator < 0) {
                numerator = -numerator;
                denominator = -denominator;
            }
            long divisor = gcd(Math.abs(numerator), denominator);
            numerator /= divisor;
            denominator /= divisor;
        }
        Fraction subtract(Fraction other) {
            return new Fraction(numerator * other.denominator - other.numerator * denominator,
                                denominator * other.denominator);
        }
        public int compareTo(Fraction other) {
            return Long.compare(numerator * other.denominator, other.numerator * denominator);
        }
    }
    static long gcd(long a, long b) {
        while (b != 0) {
            long t = a % b;
            a = b;
            b = t;
        }
        return a;
    }
    static Fraction parse(String value) {
        String[] w = value.split("/");
        return new Fraction(Long.parseLong(w[0]), w.length == 1 ? 1 : Long.parseLong(w[1]));
    }
    static String fraction(Fraction f) {
        long numerator = Math.abs(f.numerator()), denominator = f.denominator(),
             scaled = 10000 * numerator / denominator;
        String sign = f.numerator() < 0 ? "-" : "", decimalSign = scaled == 0 ? "" : sign;
        return sign + numerator + "/" + denominator + "=" + decimalSign + scaled / 10000 + "." +
            String.format(Locale.ROOT, "%04d", scaled % 10000);
    }
    static String fraction(long numerator, long denominator) {
        return fraction(new Fraction(numerator, denominator));
    }
    static String percentage(long count, long total) {
        long scaled = 10000 * count / total;
        return scaled / 100 + "." + String.format(Locale.ROOT, "%02d", scaled % 100) + "%";
    }
    static String names(Collection<String> values) {
        return values.isEmpty() ? "-" : String.join(",", values);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
}
