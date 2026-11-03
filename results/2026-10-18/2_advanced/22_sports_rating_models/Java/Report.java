import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;

final class Fraction implements Comparable<Fraction> {
    final long numerator, denominator;
    Fraction(long numerator) { this(numerator, 1); }
    Fraction(long numerator, long denominator) {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long first = Math.abs(numerator), second = denominator;
        while (second != 0) { long remainder = first % second; first = second; second = remainder; }
        this.numerator = numerator / first; this.denominator = denominator / first;
    }
    Fraction add(Fraction other) { return new Fraction(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator); }
    Fraction subtract(Fraction other) { return new Fraction(numerator * other.denominator - other.numerator * denominator, denominator * other.denominator); }
    Fraction multiply(long value) { return new Fraction(numerator * value, denominator); }
    Fraction divide(long value) { return new Fraction(numerator, denominator * value); }
    double real() { return (double) numerator / denominator; }
    public int compareTo(Fraction other) { return Long.compare(numerator * other.denominator, other.numerator * denominator); }
    public String toString() { return numerator + "/" + denominator; }
}
final class Report {
    static long scale(int places) { long scale = 1; for (int i = 0; i < places; i++) scale *= 10; return scale; }
    static Fraction comparison(double value, int places) { long scale = scale(places); return new Fraction(Math.round(value * scale), scale); }
    static String fixed(double value) { return fixed(value, 4); }
    static String fixed(double value, int places) {
        String text = String.format(Locale.ROOT, "%." + places + "f", value);
        return text.startsWith("-") && Double.parseDouble(text) == 0 ? text.substring(1) : text;
    }
    static String fixed(Fraction value) {
        long magnitude = Math.abs(value.numerator);
        long whole = magnitude / value.denominator, remainder = magnitude % value.denominator;
        long decimals = 0;
        for (int digit = 0; digit < 4; digit++) {
            remainder *= 10;
            decimals = decimals * 10 + remainder / value.denominator;
            remainder %= value.denominator;
        }
        if (2 * remainder >= value.denominator) decimals++;
        if (decimals == 10000) { whole++; decimals = 0; }
        String sign = value.numerator < 0 && (whole != 0 || decimals != 0) ? "-" : "";
        return sign + whole + "." + String.format(Locale.ROOT, "%04d", decimals);
    }
    static String fractionWithReal(Fraction value) { return value + " " + fixed(value); }
    static void write(String name, List<String> lines) throws Exception { Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n", StandardCharsets.US_ASCII); }
}
