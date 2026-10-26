using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed record NamingCondition(int feature, string comparison, double threshold)
{
    public bool holds(double[] center) => comparison == ">" ? center[feature] > threshold : center[feature] < threshold;
}
sealed record NamingRule(string name, List<NamingCondition> conditions)
{
    public bool holds(double[] center) => conditions.All(condition => condition.holds(center));
}
static class Profiles
{
    public static List<NamingRule> read(string path)
    {
        var rules = new List<NamingRule>();
        foreach (string line in Transactions.lines(path))
        {
            string[] words = line.Split(' ');
            var conditions = new List<NamingCondition>();
            for (int i = 1; i < words.Length; i += 3)
                conditions.Add(new NamingCondition(Features.NAMES.IndexOf(words[i]), words[i + 1], double.Parse(words[i + 2], CultureInfo.InvariantCulture)));
            rules.Add(new NamingRule(words[0], conditions));
        }
        return rules;
    }
    public static int ruleNumber(List<NamingRule> rules, double[] center)
    {
        for (int i = 0; i < rules.Count; i++) if (rules[i].holds(center)) return i + 1;
        throw new InvalidOperationException();
    }
    public static double[] originalScale(double[] center, double[] means, double[] sds)
    {
        double[] values = new double[center.Length];
        for (int f = 0; f < center.Length; f++)
        {
            double value = means[f] + sds[f] * center[f];
            values[f] = Features.SQRT[f] ? value * value : value;
        }
        return values;
    }
}
