static class Report
{
    public static string FractionText(Fraction value)
    {
        long numerator = Math.Abs(value.Numerator), scaled = 10000 * numerator / value.Denominator;
        string sign = value.Numerator < 0 ? "-" : "", decimalSign = value.Numerator < 0 && scaled > 0 ? "-" : "";
        return $"{sign}{numerator}/{value.Denominator}={decimalSign}{scaled / 10000}.{scaled % 10000:D4}";
    }
    public static string Percent(long part, long whole)
    {
        long scaled = 10000 * part / whole; return $"{scaled / 100}.{scaled % 100:D2}%";
    }
    public static string Money(long cents) => $"{cents / 100}.{cents % 100:D2}";
    public static string ItemsetText(Itemset itemset) => itemset.Key;
    public static string Arrow(Rule rule) => $"{ItemsetText(rule.Antecedent)} -> {ItemsetText(rule.Consequent)}";
    public static List<string> RulesCsv(List<Rule> rules)
    {
        List<string> lines = ["rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement"];
        foreach (Rule r in rules) lines.Add(string.Join(",", r.Rank, ItemsetText(r.Antecedent), ItemsetText(r.Consequent), r.Count, FractionText(r.Support), FractionText(r.Confidence), FractionText(r.Lift), FractionText(r.Leverage), r.Conviction is Fraction conviction ? FractionText(conviction) : "INF", FractionText(r.Improvement)));
        return lines;
    }
    public static void Write(string name, List<string> lines)
    {
        Directory.CreateDirectory("output"); File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + (lines.Count == 0 ? "" : "\n"), System.Text.Encoding.ASCII);
    }
}
