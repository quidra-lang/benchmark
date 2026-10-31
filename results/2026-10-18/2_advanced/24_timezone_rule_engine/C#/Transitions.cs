using System.Collections.Generic;
using System.Linq;

static class Transitions
{
    public sealed record Rule(int Number, string[] Fields, int FromYear, int ToYear, int Month, DayRules.DaySpec Day, long At, char Type, long Save, string Letter)
    {
        public string Name => Fields[1];
    }
    public sealed record Instance(Rule Rule, long Nominal);
    public sealed record Applied(long Time, Rule Rule);
    public sealed record Switch(long Time, long Save, string Letter);
    public sealed class LineRun
    {
        public List<Rule> PreStart { get; } = new();
        public List<Applied> Applied { get; } = new();
        public long End { get; set; } = DayRules.PositiveInfinity;
    }

    public static List<Instance> Instances(List<Rule> rules)
    {
        var result = new List<Instance>();
        foreach (Rule rule in rules) for (int year = rule.FromYear; year <= rule.ToYear; year++) result.Add(new Instance(rule, rule.Day.Value(year, rule.Month) * DayRules.Day + rule.At));
        return result.OrderBy(instance => instance.Nominal).ThenBy(instance => instance.Rule.Number).ToList();
    }

    public static long Adjustment(char type, long offset, long save) => type == 'u' ? 0 : type == 's' ? offset : offset + save;

    public static LineRun Run(List<Instance> instances, long offset, long start, TzParser.Until? until)
    {
        var result = new LineRun();
        long save = 0;
        foreach (Instance instance in instances)
        {
            Rule rule = instance.Rule;
            long time = instance.Nominal - Adjustment(rule.Type, offset, save);
            if (until != null && time >= until.Value - Adjustment(until.Type, offset, save)) break;
            if (time <= start) result.PreStart.Add(rule);
            else result.Applied.Add(new Applied(time, rule));
            save = rule.Save;
        }
        if (until != null) result.End = until.Value - Adjustment(until.Type, offset, save);
        return result;
    }

    public static string Abbreviation(string format, long save, string letter)
    {
        if (format.Contains('/')) { string[] parts = format.Split('/'); return save == 0 ? parts[0] : parts[1]; }
        return format.Replace("%s", letter, System.StringComparison.Ordinal);
    }
}
