readonly record struct Fraction : IComparable<Fraction>
{
    public long Numerator { get; }
    public long Denominator { get; }
    public Fraction() : this(0, 1) {}
    public Fraction(long numerator, long denominator = 1)
    {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long a = Math.Abs(numerator), b = denominator;
        while (b != 0) (a, b) = (b, a % b);
        Numerator = numerator / a; Denominator = denominator / a;
    }
    public int CompareTo(Fraction other) => (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);
    public static Fraction operator +(Fraction a, Fraction b) => new(a.Numerator * b.Denominator + b.Numerator * a.Denominator, a.Denominator * b.Denominator);
    public static Fraction operator -(Fraction a, Fraction b) => new(a.Numerator * b.Denominator - b.Numerator * a.Denominator, a.Denominator * b.Denominator);
    public static Fraction operator *(Fraction a, Fraction b) => new(a.Numerator * b.Numerator, a.Denominator * b.Denominator);
    public static Fraction operator /(Fraction a, Fraction b) => new(a.Numerator * b.Denominator, a.Denominator * b.Numerator);
    public static bool operator <(Fraction a, Fraction b) => a.CompareTo(b) < 0;
    public static bool operator >(Fraction a, Fraction b) => a.CompareTo(b) > 0;
    public static bool operator <=(Fraction a, Fraction b) => a.CompareTo(b) <= 0;
    public static bool operator >=(Fraction a, Fraction b) => a.CompareTo(b) >= 0;
}
sealed class Rule(Itemset itemset, Itemset antecedent, Itemset consequent, long count, long total, long a, long b)
{
    public Itemset Itemset = itemset, Antecedent = antecedent, Consequent = consequent;
    public long Count = count;
    public Fraction Support = new(count, total), Confidence = new(count, a), Lift = Rules.LiftOf(total, count, a, b), Leverage = new(total * count - a * b, total * total), Improvement = new();
    public Fraction? Conviction = a == count ? null : new Fraction((total - b) * a, total * (a - count));
    public int Rank;
}
sealed class RuleSet
{
    public long Generated, Productive;
    public List<Rule> Rules = [];
}
static class Rules
{
    public static Fraction LiftOf(long total, long together, long a, long b) => new(total * together, a * b);
    public static bool Meets(Fraction confidence, Fraction lift, Fraction minimumConfidence, Fraction minimumLift) => confidence >= minimumConfidence && lift >= minimumLift;
    public static int Compare(Rule a, Rule b)
    {
        int result = b.Confidence.CompareTo(a.Confidence);
        if (result == 0) result = b.Lift.CompareTo(a.Lift);
        if (result == 0) result = b.Count.CompareTo(a.Count);
        if (result == 0) result = a.Antecedent.CompareTo(b.Antecedent);
        return result == 0 ? a.Consequent.CompareTo(b.Consequent) : result;
    }
}
