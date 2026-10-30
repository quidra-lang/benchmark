import java.util.*;
record Rational(long numerator, long denominator) implements Comparable<Rational> {
    static final Rational ZERO = new Rational(0), ONE = new Rational(1);
    Rational(long value) { this(value, 1); }
    Rational {
        if (denominator < 0) {
            numerator = -numerator;
            denominator = -denominator;
        }
        long a = Math.abs(numerator), b = denominator;
        while (b != 0) {
            long remainder = a % b;
            a = b;
            b = remainder;
        }
        numerator /= a;
        denominator /= a;
    }
    Rational add(Rational value) {
        return new Rational(numerator * value.denominator + value.numerator * denominator,
                            denominator * value.denominator);
    }
    Rational subtract(Rational value) { return add(value.negate()); }
    Rational multiply(Rational value) {
        return new Rational(numerator * value.numerator, denominator * value.denominator);
    }
    Rational multiply(long value) { return new Rational(numerator * value, denominator); }
    Rational divide(Rational value) {
        return new Rational(numerator * value.denominator, denominator * value.numerator);
    }
    Rational negate() { return new Rational(-numerator, denominator); }
    Rational abs() { return numerator < 0 ? negate() : this; }
    int sign() { return Long.compare(numerator, 0); }
    public int compareTo(Rational value) {
        return Long.compare(numerator * value.denominator, value.numerator * denominator);
    }
    long floor() { return Math.floorDiv(numerator, denominator); }
    long ceil() { return -Math.floorDiv(-numerator, denominator); }
    public String toString() {
        return denominator == 1 ? Long.toString(numerator) : numerator + "/" + denominator;
    }
    static Rational read(String word, boolean signed) {
        if (!word.matches(signed ? "-?[0-9]+(?:\\.[0-9]+|/[0-9]+)?"
                                 : "[0-9]+(?:\\.[0-9]+|/[0-9]+)?"))
            return null;
        try {
            int slash = word.indexOf('/'), dot = word.indexOf('.');
            if (slash >= 0) {
                long denominator = Long.parseLong(word.substring(slash + 1));
                return denominator == 0
                    ? null
                    : new Rational(Long.parseLong(word.substring(0, slash)), denominator);
            }
            if (dot >= 0) {
                long denominator = 1;
                for (int i = dot + 1; i < word.length(); i++)
                    denominator *= 10;
                return new Rational(
                    Long.parseLong(word.substring(0, dot) + word.substring(dot + 1)), denominator);
            }
            return new Rational(Long.parseLong(word));
        } catch (NumberFormatException error) {
            return null;
        }
    }
    String approximate() {
        long scaled = abs().multiply(1000000).add(new Rational(1, 2)).floor();
        return (sign() < 0 && scaled > 0 ? "-" : "") + (scaled / 1000000) + "." +
            String.format(Locale.ROOT, "%06d", scaled % 1000000);
    }
    static String endpoint(Rational value, boolean lower) {
        return value == null ? (lower ? "-inf" : "inf") : value.toString();
    }
}
