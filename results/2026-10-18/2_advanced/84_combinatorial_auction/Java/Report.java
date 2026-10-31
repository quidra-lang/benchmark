import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Report {
    record Rational(long numerator, long denominator) implements Comparable<Rational> {
        Rational {
            if (denominator < 0) {
                numerator = -numerator;
                denominator = -denominator;
            }
            long divisor = gcd(numerator, denominator);
            numerator /= divisor;
            denominator /= divisor;
        }
        Rational(long value) { this(value, 1); }
        static long gcd(long a, long b) {
            a = Math.abs(a);
            while (b != 0) {
                long r = a % b;
                a = b;
                b = r;
            }
            return a;
        }
        Rational add(Rational other) {
            return new Rational(numerator * other.denominator + other.numerator * denominator,
                                denominator * other.denominator);
        }
        Rational subtract(Rational other) {
            return new Rational(numerator * other.denominator - other.numerator * denominator,
                                denominator * other.denominator);
        }
        Rational multiply(long value) { return new Rational(numerator * value, denominator); }
        Rational divide(Rational other) {
            return new Rational(numerator * other.denominator, denominator * other.numerator);
        }
        public int compareTo(Rational other) {
            return Long.compare(numerator * other.denominator, other.numerator * denominator);
        }
        public String toString() {
            return denominator == 1 ? Long.toString(numerator) : numerator + "/" + denominator;
        }
    }
    static String bundle(int mask, List<BidsIo.Item> items) {
        List<String> names = new ArrayList<>();
        for (int i = 0; i < items.size(); i++)
            if ((mask & (1 << i)) != 0)
                names.add(items.get(i).name());
        return names.isEmpty() ? "-" : String.join("+", names);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name),
                          lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
