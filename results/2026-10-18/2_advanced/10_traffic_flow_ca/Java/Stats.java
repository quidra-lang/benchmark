import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

final class Stats {
    static long gcd(long a, long b) { while (b != 0) { long next = a % b; a = b; b = next; } return a; }
    static String dec(long a, long b, int places) {
        if (b == 0) return "-"; long scale = 1; for (int i = 0; i < places; i++) scale *= 10; long value = (2 * a * scale + b) / (2 * b); String digits = Long.toString(value % scale); return value / scale + "." + "0".repeat(places - digits.length()) + digits;
    }
    static String frac(long a, long b) { if (b == 0) return "-"; long d = gcd(a,b); return a / d + "/" + b / d; }
    static long percentile(List<Long> values, int q) { return values.get((q * values.size() + 99) / 100 - 1); }
    static List<String> histogram(List<Long> values, long width) {
        long first = values.getFirst() / width; long[] counts = new long[(int)(values.getLast() / width - first + 1)]; for (long value : values) counts[(int)(value / width - first)]++; long maximum = Arrays.stream(counts).max().orElseThrow(); List<String> lines = new ArrayList<>();
        for (int i = 0; i < counts.length; i++) { long low = (first + i) * width; int stars = (int)((80 * counts[i] + maximum) / (2 * maximum)); lines.add("  " + low + "-" + (low + width - 1) + " " + counts[i] + (stars == 0 ? "" : " " + "*".repeat(stars))); } return lines;
    }
}
record Share(long numerator, long denominator) {
    Share { long divisor = Stats.gcd(numerator,denominator); numerator /= divisor; denominator /= divisor; }
    Share(long value) { this(value,1); }
    Share times(long n, long d) { return new Share(numerator * n,denominator * d); }
    Share plus(Share other) { return new Share(numerator * other.denominator + other.numerator * denominator,denominator * other.denominator); }
    public String toString() { return Stats.frac(numerator,denominator); }
}
