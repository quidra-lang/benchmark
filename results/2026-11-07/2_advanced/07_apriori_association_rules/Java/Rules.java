record Fraction(long numerator, long denominator) implements Comparable<Fraction> {
    Fraction {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long a = Math.abs(numerator), b = denominator;
        while (b != 0) { long next = a % b; a = b; b = next; }
        numerator /= a; denominator /= a;
    }
    Fraction(long numerator) { this(numerator, 1); }
    Fraction() { this(0, 1); }
    Fraction add(Fraction other) { return new Fraction(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator); }
    Fraction subtract(Fraction other) { return new Fraction(numerator * other.denominator - other.numerator * denominator, denominator * other.denominator); }
    Fraction multiply(Fraction other) { return new Fraction(numerator * other.numerator, denominator * other.denominator); }
    Fraction divide(Fraction other) { return new Fraction(numerator * other.denominator, denominator * other.numerator); }
    @Override public int compareTo(Fraction other) { return Long.compare(numerator * other.denominator, other.numerator * denominator); }
}
final class Rule {
    final Itemset itemset, antecedent, consequent;
    final long count;
    final Fraction support, confidence, lift, leverage, conviction;
    Fraction improvement = new Fraction();
    int rank;
    Rule(Itemset itemset, Itemset antecedent, Itemset consequent, long count, long total, long a, long b) {
        this.itemset = itemset; this.antecedent = antecedent; this.consequent = consequent; this.count = count;
        support = new Fraction(count, total); confidence = new Fraction(count, a); lift = Rules.liftOf(total, count, a, b);
        leverage = new Fraction(total * count - a * b, total * total);
        conviction = a == count ? null : new Fraction((total - b) * a, total * (a - count));
    }
}
final class RuleSet {
    long generated, productive;
    final java.util.List<Rule> rules = new java.util.ArrayList<>();
}
final class Rules {
    static Fraction liftOf(long total, long together, long a, long b) { return new Fraction(total * together, a * b); }
    static boolean meets(Fraction confidence, Fraction lift, Fraction minimumConfidence, Fraction minimumLift) { return confidence.compareTo(minimumConfidence) >= 0 && lift.compareTo(minimumLift) >= 0; }
    static int compare(Rule a, Rule b) {
        int comparison = b.confidence.compareTo(a.confidence);
        if (comparison == 0) comparison = b.lift.compareTo(a.lift);
        if (comparison == 0) comparison = Long.compare(b.count, a.count);
        if (comparison == 0) comparison = a.antecedent.compareTo(b.antecedent);
        return comparison == 0 ? a.consequent.compareTo(b.consequent) : comparison;
    }
}
