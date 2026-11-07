import java.math.BigInteger;
final class Rational {
    record Fraction(BigInteger numerator, BigInteger denominator) implements Comparable<Fraction> {
        Fraction {
            if (denominator.signum() < 0) {
                numerator = numerator.negate();
                denominator = denominator.negate();
            }
            BigInteger gcd = numerator.gcd(denominator);
            numerator = numerator.divide(gcd);
            denominator = denominator.divide(gcd);
        }
        Fraction(long value) { this(BigInteger.valueOf(value), BigInteger.ONE); }
        Fraction(long numerator, long denominator) {
            this(BigInteger.valueOf(numerator), BigInteger.valueOf(denominator));
        }
        Fraction add(Fraction other) {
            return new Fraction(
                numerator.multiply(other.denominator).add(other.numerator.multiply(denominator)),
                denominator.multiply(other.denominator));
        }
        Fraction subtract(Fraction other) {
            return new Fraction(numerator.multiply(other.denominator)
                                    .subtract(other.numerator.multiply(denominator)),
                                denominator.multiply(other.denominator));
        }
        Fraction multiply(Fraction other) {
            return new Fraction(numerator.multiply(other.numerator),
                                denominator.multiply(other.denominator));
        }
        Fraction divide(Fraction other) {
            return new Fraction(numerator.multiply(other.denominator),
                                denominator.multiply(other.numerator));
        }
        int sign() { return numerator.signum(); }
        double real() { return numerator.doubleValue() / denominator.doubleValue(); }
        public int compareTo(Fraction other) {
            return numerator.multiply(other.denominator)
                .compareTo(other.numerator.multiply(denominator));
        }
        public String toString() {
            return denominator.equals(BigInteger.ONE) ? numerator.toString()
                                                      : numerator + "/" + denominator;
        }
        Fraction rounded() {
            BigInteger n = numerator.shiftLeft(1).add(denominator), d = denominator.shiftLeft(1);
            BigInteger[] q = n.divideAndRemainder(d);
            if (n.signum() < 0 && q[1].signum() != 0)
                q[0] = q[0].subtract(BigInteger.ONE);
            return new Fraction(q[0], BigInteger.ONE);
        }
    }
    static final Fraction ZERO = new Fraction(0), ONE = new Fraction(1);
    record Point(Fraction x, Fraction y) implements Comparable<Point> {
        Point(long x, long y) { this(new Fraction(x), new Fraction(y)); }
        public int compareTo(Point other) {
            int c = y.compareTo(other.y);
            return c != 0 ? c : x.compareTo(other.x);
        }
        public String toString() { return "(" + x + "," + y + ")"; }
    }
    static Fraction cross(Point origin, Point first, Point second) {
        return first.x()
            .subtract(origin.x())
            .multiply(second.y().subtract(origin.y()))
            .subtract(first.y().subtract(origin.y()).multiply(second.x().subtract(origin.x())));
    }
    static Point along(Point start, Point end, Fraction position) {
        return new Point(start.x().add(position.multiply(end.x().subtract(start.x()))),
                         start.y().add(position.multiply(end.y().subtract(start.y()))));
    }
    static Fraction min(Fraction a, Fraction b) { return a.compareTo(b) <= 0 ? a : b; }
    static Fraction max(Fraction a, Fraction b) { return a.compareTo(b) >= 0 ? a : b; }
    static String segment(Point first, Point second) { return first + "-" + second; }
}
