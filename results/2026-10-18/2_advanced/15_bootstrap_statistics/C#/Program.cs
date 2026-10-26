#nullable enable
using System;
using System.Linq;
using System.Collections.Generic;
using static Report;

sealed class Summary
{
    public double Estimate { get; }
    public double Average { get; }
    public double Se { get; }
    public double Bias { get; }
    public double Low { get; }
    public double High { get; }
    public double BasicLow { get; }
    public double BasicHigh { get; }
    public double[] Values { get; }
    public double[] Ordered { get; }
    public Summary(double estimate, double[] values, int lowRank, int highRank)
    {
        Estimate = estimate; Values = values;
        Ordered = values.OrderBy(value => value).ToArray();
        double[] spread = Resampling.MeanAndSe(values);
        Average = spread[0]; Se = spread[1]; Bias = Average - estimate;
        Low = Ordered[lowRank - 1]; High = Ordered[highRank - 1];
        BasicLow = 2 * estimate - High; BasicHigh = 2 * estimate - Low;
    }
    public string Csv(string name, string statistic) => string.Join(",", new[] { name, statistic }.Concat(
        new[] { Estimate, Se, Bias, Low, High, BasicLow, BasicHigh }.Select(Real)));
    public string Interval() => $"se {Real(Se)} bias {Real(Bias)} percentile {Real(Low)} {Real(High)} basic {Real(BasicLow)} {Real(BasicHigh)}";
}
sealed class GroupBootstrap
{
    public Group Group { get; }
    public int[][] Indices { get; }
    public long[][] Samples { get; }
    public Summary[] Summaries { get; } = new Summary[4];
    public GroupBootstrap(Group group, int[][] indices, int low, int high)
    {
        Group = group; Indices = indices;
        Samples = indices.Select(replicate => Resampling.Sample(group.Values, replicate)).ToArray();
        for (int statistic = 0; statistic < 4; statistic++)
        {
            double[] values = Samples.Select(sample => Resampling.GroupStatistic(statistic, sample)).ToArray();
            Summaries[statistic] = new Summary(Resampling.GroupStatistic(statistic, group.Values), values, low, high);
        }
    }
}
sealed class PairBootstrap
{
    public GroupBootstrap First { get; }
    public GroupBootstrap Second { get; }
    public string Name { get; }
    public Summary[] Summaries { get; } = new Summary[4];
    public PairBootstrap(GroupBootstrap first, GroupBootstrap second, int low, int high)
    {
        First = first; Second = second; Name = first.Group.Name + "-" + second.Group.Name;
        for (int statistic = 0; statistic < 4; statistic++)
        {
            double[] values = Enumerable.Range(0, first.Samples.Length)
                .Select(i => Resampling.PairStatistic(statistic, first.Samples[i], second.Samples[i])).ToArray();
            Summaries[statistic] = new Summary(Resampling.PairStatistic(statistic, first.Group.Values, second.Group.Values), values, low, high);
        }
    }
}
sealed class Jackknife
{
    public double[] Values { get; }
    public double Average { get; }
    public double Variance { get; }
    public double Bias { get; }
    public double Se { get; }
    public Jackknife(double estimate, double[] values)
    {
        Values = values;
        double[] spread = Study.JackknifeSpread(values);
        Average = spread[0]; Variance = spread[1]; Bias = (values.Length - 1) * (Average - estimate); Se = Math.Sqrt(Variance);
    }
}
sealed class Tally
{
    public long Observed { get; }
    public int Extreme { get; private set; }
    public int Greater { get; private set; }
    public Tally(long observed) { Observed = observed; }
    public void Count(long value)
    {
        if (Math.Abs(value) >= Math.Abs(Observed)) Extreme++;
        if (value >= Observed) Greater++;
    }
    public string Text(int offset, int denominator) => $"extreme {Extreme} greater {Greater} p_two {PValue(Extreme + offset, denominator)} p_greater {PValue(Greater + offset, denominator)}";
}
sealed class DisplayRange
{
    private readonly long low, delta;
    public DisplayRange(long[] values) { low = values.Min(); delta = 100 * (values.Max() - low); }
    public int Position(long value) => (int)((120 * (value - 100 * low) + delta) / (2 * delta));
}
sealed record TestResult(List<string> Lines, int[] Extremes);
readonly record struct Delta(long Numerator, long Denominator) : IComparable<Delta>
{
    public int CompareTo(Delta other) => (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);
}

sealed class Study
{
    private static readonly string[] GroupStatistics = { "mean", "median", "trimmed_mean", "sd" };
    private static readonly string[] PairStatistics = { "mean_diff", "median_ratio", "hodges_lehmann", "cohen_d" };
    private static readonly string[] TestStatistics = { "mean", "median", "ranksum", "absdev" };
    private readonly Dataset data;
    private readonly Settings settings;
    private readonly Minstd generator;
    private readonly int lowRank, highRank;
    private readonly double zLow;
    public Study(Dataset data)
    {
        this.data = data; settings = data.Settings; generator = new Minstd(settings.Seed);
        lowRank = (settings.Bootstrap + 1) * (100 - settings.Confidence) / 200;
        highRank = settings.Bootstrap + 1 - lowRank;
        zLow = Resampling.PhiInverse((100 - settings.Confidence) / 200.0);
    }
    private static long[] Concat(long[] first, long[] second) => first.Concat(second).ToArray();
    public static double[] JackknifeSpread(double[] values)
    {
        double average = Resampling.SequentialSum(values) / values.Length, squares = 0;
        foreach (double value in values) { double difference = value - average; squares += difference * difference; }
        return new[] { average, (values.Length - 1) * squares / values.Length };
    }
    private List<int> Outliers(long[] values)
    {
        long first = Resampling.QuantileNumerator(values, 25), third = Resampling.QuantileNumerator(values, 75);
        return Enumerable.Range(0, values.Length).Where(i => 200 * values[i] < 5 * first - 3 * third || 200 * values[i] > 5 * third - 3 * first).ToList();
    }
    private List<string> SeriesLines(string kind, string name, long[] values, DisplayRange display, bool stems)
    {
        long[] ordered = Resampling.Sorted(values);
        int count = values.Length;
        double mean = Resampling.Mean(values), sd = Resampling.Sd(values);
        double[] moments = Resampling.CentralMoments(values);
        long[] clipped = Resampling.Winsorized(values);
        long first = Resampling.QuantileNumerator(values, 25), third = Resampling.QuantileNumerator(values, 75);
        List<int> outliers = Outliers(values);
        long[] inside = values.Where((_, index) => !outliers.Contains(index)).ToArray();
        long low = inside.Min(), high = inside.Max();
        char[] band = Enumerable.Repeat('.', 61).ToArray();
        for (int i = display.Position(100 * low); i <= display.Position(100 * high); i++) band[i] = '-';
        for (int i = display.Position(first); i <= display.Position(third); i++) band[i] = '=';
        band[display.Position(Resampling.QuantileNumerator(values, 50))] = '|';
        foreach (int index in outliers) band[display.Position(100 * values[index])] = 'o';
        var lines = new List<string>
        {
            $"{kind} {name}", $"n {count}", $"mean {Real(mean)}", $"median {Real(Resampling.Median(values))}",
            $"trimmed_mean {Real(Resampling.TrimmedMean(values))} trim {count / 10}",
            $"winsorized_mean {Real(Resampling.Mean(clipped))} winsorized_sd {Real(Resampling.Sd(clipped))}",
            $"sd {Real(sd)}", $"se_mean {Real(sd / Math.Sqrt(count))}", $"cv {Real(sd / mean)}",
            $"skewness {Real(moments[1] / (moments[0] * Math.Sqrt(moments[0])))}", $"kurtosis {Real(moments[2] / (moments[0] * moments[0]) - 3)}",
            $"mad {Real(Resampling.Mad(values))}", $"min {Real(ordered[0] / 100.0)}", $"q1 {Real(first / 10000.0)}",
            $"q3 {Real(third / 10000.0)}", $"iqr {Real((third - first) / 10000.0)}", $"max {Real(ordered[^1] / 100.0)}"
        };
        lines.Add("percentiles " + string.Join(" ", new[] { 5, 10, 90, 95 }.Select(percent =>
            $"p{percent:D2} {Real(Resampling.QuantileNumerator(values, percent) / 10000.0)}")));
        lines.Add($"whiskers {Real(low / 100.0)} {Real(high / 100.0)}");
        lines.Add("outliers " + NumberList(outliers.Select(index => index + 1).ToList()));
        lines.Add("box " + new string(band));
        if (stems)
            for (long stem = ordered[0] / 100; stem <= ordered[^1] / 100; stem++)
            {
                string leaves = string.Concat(ordered.Where(value => value / 100 == stem).Select(value => (value % 100 / 10).ToString()));
                lines.Add($"stem {stem}" + (leaves.Length == 0 ? "" : " " + leaves));
            }
        return lines;
    }
    private List<string> DescriptiveLines()
    {
        long[] everything = data.Groups.SelectMany(group => group.Values).ToArray();
        var lines = new List<string> { $"groups {data.Groups.Count} observations {everything.Length}" };
        var display = new DisplayRange(everything);
        foreach (Group group in data.Groups) lines.AddRange(SeriesLines("group", group.Name, group.Values, display, true));
        PairedSample paired = data.Paired;
        lines.Add($"paired subjects {paired.Differences.Length}");
        display = new DisplayRange(Concat(paired.Before, paired.After));
        lines.AddRange(SeriesLines("series", "before", paired.Before, display, false));
        lines.AddRange(SeriesLines("series", "after", paired.After, display, false));
        lines.AddRange(SeriesLines("series", "diff", paired.Differences, new DisplayRange(paired.Differences), false));
        return lines;
    }
    private Summary[] PairedBootstrap()
    {
        PairedSample paired = data.Paired;
        var means = new double[settings.Bootstrap];
        var correlations = new double[settings.Bootstrap];
        int[][] indices = Resampling.OrdinaryIndices(generator, paired.Before.Length, settings.Bootstrap);
        for (int i = 0; i < indices.Length; i++)
        {
            means[i] = Resampling.Mean(Resampling.Sample(paired.Differences, indices[i]));
            correlations[i] = Resampling.Correlation(Resampling.Sample(paired.Before, indices[i]), Resampling.Sample(paired.After, indices[i]));
        }
        return new[] { new Summary(Resampling.Mean(paired.Differences), means, lowRank, highRank),
            new Summary(Resampling.Correlation(paired.Before, paired.After), correlations, lowRank, highRank) };
    }
    private List<string> BootstrapLines(List<GroupBootstrap> ordinary, List<GroupBootstrap> balanced, List<PairBootstrap> pairs)
    {
        var lines = new List<string> { "group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi" };
        for (int i = 0; i < ordinary.Count; i++)
        {
            for (int statistic = 0; statistic < 4; statistic++) lines.Add(ordinary[i].Summaries[statistic].Csv(ordinary[i].Group.Name, GroupStatistics[statistic]));
            for (int statistic = 0; statistic < 4; statistic++) lines.Add(balanced[i].Summaries[statistic].Csv(ordinary[i].Group.Name, "balanced_" + GroupStatistics[statistic]));
        }
        foreach (PairBootstrap pair in pairs)
            for (int statistic = 0; statistic < 4; statistic++) lines.Add(pair.Summaries[statistic].Csv(pair.Name, PairStatistics[statistic]));
        return lines;
    }
    private List<string> HistogramLines(string name, string statistic, Summary summary)
    {
        int bins = settings.Bins;
        double low = summary.Ordered[0], high = summary.Ordered[^1];
        var counts = new int[bins];
        foreach (double value in summary.Values) counts[BinNumber(value, low, high, bins) - 1]++;
        int top = counts.Max();
        List<string>[] marks = Enumerable.Range(0, bins).Select(_ => new List<string>()).ToArray();
        marks[BinNumber(summary.Low, low, high, bins) - 1].Add("L");
        string estimateBin = "none";
        if (summary.Estimate >= low && summary.Estimate <= high)
        {
            int bin = BinNumber(summary.Estimate, low, high, bins);
            estimateBin = bin.ToString(); marks[bin - 1].Add("E");
        }
        marks[BinNumber(summary.High, low, high, bins) - 1].Add("H");
        var convergence = new List<string>();
        for (int quarter = 1; quarter <= 4; quarter++)
        {
            int size = quarter * settings.Bootstrap / 4;
            convergence.Add($"{size}:{Real(Resampling.MeanAndSe(summary.Values[..size])[1])}");
        }
        var lines = new List<string>
        {
            $"histogram {name} {statistic} min {Real(low)} max {Real(high)} width {Real((high - low) / bins)} top {top} estimate_bin {estimateBin}",
            "convergence " + string.Join(" ", convergence)
        };
        for (int i = 0; i < bins; i++)
        {
            string line = $"bin {i + 1} {Real(low + (high - low) * i / bins)} {counts[i]}";
            if (counts[i] > 0) line += " " + Bar(counts[i], top);
            if (marks[i].Count > 0) line += " " + string.Join(" ", marks[i]);
            lines.Add(line);
        }
        return lines;
    }
    private double BcaAlpha(double z0, double acceleration, double z) => Resampling.Phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)));
    private string BcaLine(string statistic, Summary summary, Jackknife jackknife)
    {
        int below = summary.Values.Count(value => value < summary.Estimate);
        double z0 = Resampling.PhiInverse((double)below / settings.Bootstrap), squares = 0, cubes = 0;
        foreach (double value in jackknife.Values)
        {
            double difference = jackknife.Average - value;
            squares += difference * difference; cubes += difference * difference * difference;
        }
        double acceleration = cubes / (6 * squares * Math.Sqrt(squares));
        int lower = (int)Math.Floor((settings.Bootstrap + 1) * BcaAlpha(z0, acceleration, zLow));
        int upper = settings.Bootstrap + 1 - (int)Math.Floor((settings.Bootstrap + 1) * (1 - BcaAlpha(z0, acceleration, -zLow)));
        lower = Math.Clamp(lower, 1, settings.Bootstrap); upper = Math.Clamp(upper, 1, settings.Bootstrap);
        return $"bca {statistic} below {below} z0 {Real(z0)} acceleration {Real(acceleration)} ranks {lower} {upper} interval {Real(summary.Ordered[lower - 1])} {Real(summary.Ordered[upper - 1])}";
    }
    private List<string> GroupJackknife(GroupBootstrap bootstrap)
    {
        long[] values = bootstrap.Group.Values;
        int count = values.Length;
        var jackknives = new Jackknife[4];
        var lines = new List<string> { $"group {bootstrap.Group.Name} n {count}" };
        for (int statistic = 0; statistic < 4; statistic++)
        {
            double[] removed = Enumerable.Range(0, count).Select(i => Resampling.GroupStatistic(statistic, Resampling.Without(values, i))).ToArray();
            var jackknife = new Jackknife(bootstrap.Summaries[statistic].Estimate, removed);
            jackknives[statistic] = jackknife;
            lines.Add($"jackknife {GroupStatistics[statistic]} estimate {Real(bootstrap.Summaries[statistic].Estimate)} average {Real(jackknife.Average)} bias {Real(jackknife.Bias)} se {Real(jackknife.Se)}");
        }
        for (int statistic = 0; statistic < 4; statistic++) lines.Add(BcaLine(GroupStatistics[statistic], bootstrap.Summaries[statistic], jackknives[statistic]));
        List<int>[] omitted = Enumerable.Range(0, count).Select(_ => new List<int>()).ToArray();
        for (int replicate = 0; replicate < bootstrap.Indices.Length; replicate++)
        {
            var chosen = new bool[count];
            foreach (int index in bootstrap.Indices[replicate]) chosen[index] = true;
            for (int i = 0; i < count; i++) if (!chosen[i]) omitted[i].Add(replicate);
        }
        double[][] errors = Enumerable.Range(0, 4).Select(_ => new double[count]).ToArray();
        for (int statistic = 0; statistic < 4; statistic++)
        {
            Summary summary = bootstrap.Summaries[statistic];
            for (int i = 0; i < count; i++) errors[statistic][i] = Resampling.MeanAndSe(omitted[i].Select(index => summary.Values[index]).ToArray())[1];
            double[] spread = JackknifeSpread(errors[statistic]);
            lines.Add($"after_bootstrap {GroupStatistics[statistic]} se {Real(summary.Se)} average {Real(spread[0])} se_of_se {Real(Math.Sqrt(spread[1]))}");
        }
        lines.Add($"without min {omitted.Min(list => list.Count)} max {omitted.Max(list => list.Count)}");
        long total = Resampling.Sum(values);
        List<int> ranking = Enumerable.Range(0, count).OrderByDescending(index => Math.Abs(count * values[index] - total)).ThenBy(index => index).Take(5).ToList();
        for (int rank = 0; rank < ranking.Count; rank++)
        {
            int index = ranking[rank], size = omitted[index].Count;
            double influence = (count - 1) * (jackknives[0].Average - jackknives[0].Values[index]);
            Summary summary = bootstrap.Summaries[0];
            double[] shifted = omitted[index].Select(replicate => summary.Values[replicate] - summary.Estimate).OrderBy(value => value).ToArray();
            lines.Add($"influence {rank + 1} obs {index + 1} value {Real(values[index] / 100.0)} l {Real(influence)} without {size} se {Real(errors[0][index])} q05 {Real(shifted[(5 * size + 99) / 100 - 1])} q50 {Real(shifted[(50 * size + 99) / 100 - 1])} q95 {Real(shifted[(95 * size + 99) / 100 - 1])}");
        }
        return lines;
    }
    private List<string> PairJackknife(PairBootstrap pair)
    {
        long[] x = pair.First.Group.Values, y = pair.Second.Group.Values;
        var lines = new List<string>();
        for (int statistic = 0; statistic < 4; statistic++)
        {
            double[] first = Enumerable.Range(0, x.Length).Select(i => Resampling.PairStatistic(statistic, Resampling.Without(x, i), y)).ToArray();
            double[] second = Enumerable.Range(0, y.Length).Select(i => Resampling.PairStatistic(statistic, x, Resampling.Without(y, i))).ToArray();
            var a = new Jackknife(pair.Summaries[statistic].Estimate, first);
            var b = new Jackknife(pair.Summaries[statistic].Estimate, second);
            double bias = 0; bias += a.Bias; bias += b.Bias;
            double variance = 0; variance += a.Variance; variance += b.Variance;
            lines.Add($"pair {pair.Name} {PairStatistics[statistic]} estimate {Real(pair.Summaries[statistic].Estimate)} bias {Real(bias)} se {Real(Math.Sqrt(variance))}");
        }
        return lines;
    }
    private static long DeviationTotal(long[] values, long center)
    {
        long total = 0;
        foreach (long value in values) total += Math.Abs(2 * value - center);
        return total;
    }
    private long[] SplitStatistics(long[] values, long[] ranks, int[] order, int size)
    {
        long[] x = Resampling.Sample(values, order[..size]), y = Resampling.Sample(values, order[size..]);
        long firstCenter = Resampling.DoubledMedian(x), secondCenter = Resampling.DoubledMedian(y), rankTotal = 0;
        for (int i = 0; i < size; i++) rankTotal += ranks[order[i]];
        return new[] { Tests.Contrast(Resampling.Sum(x), x.Length, Resampling.Sum(y), y.Length), firstCenter - secondCenter,
            rankTotal - (long)size * (order.Length + 1), Tests.Contrast(DeviationTotal(x, firstCenter), x.Length, DeviationTotal(y, secondCenter), y.Length) };
    }
    private TestResult PermutationLines(long[] x, long[] y)
    {
        long[] combined = Concat(x, y), ranks = Tests.DoubledRanks(combined);
        int[] positions = Enumerable.Range(0, combined.Length).ToArray();
        long[] observed = SplitStatistics(combined, ranks, positions, x.Length);
        Tally[] tallies = observed.Select(value => new Tally(value)).ToArray();
        for (int repeat = 0; repeat < settings.Permutations; repeat++)
        {
            int[] order = (int[])positions.Clone(); generator.Shuffle(order);
            long[] trial = SplitStatistics(combined, ranks, order, x.Length);
            for (int i = 0; i < 4; i++) tallies[i].Count(trial[i]);
        }
        long rankTotal = Resampling.Sum(ranks[..x.Length]);
        int denominator = settings.Permutations + 1;
        return new TestResult(new List<string>
        {
            $"permutation n {x.Length} {y.Length} perms {settings.Permutations}",
            $"mean diff {Real(Resampling.MeanDifference(x, y))} {tallies[0].Text(1, denominator)}",
            $"median diff {Real(observed[1] / 200.0)} {tallies[1].Text(1, denominator)}",
            $"ranksum w {Real(rankTotal / 2.0)} u {Real((rankTotal - (long)x.Length * (x.Length + 1)) / 2.0)} {tallies[2].Text(1, denominator)}",
            $"absdev diff {Real((double)observed[3] / (200L * x.Length * y.Length))} {tallies[3].Text(1, denominator)}"
        }, tallies.Select(tally => tally.Extreme).ToArray());
    }
    private string PowerLine(long[] x, long[] y)
    {
        int rejections = 0;
        for (int simulation = 0; simulation < settings.PowerSims; simulation++)
        {
            long[] first = Resampling.Sample(x, Resampling.ResampleIndices(generator, x.Length));
            long[] second = Resampling.Sample(y, Resampling.ResampleIndices(generator, y.Length));
            long[] combined = Concat(first, second);
            long total = Resampling.Sum(combined), observed = Math.Abs(Tests.Contrast(Resampling.Sum(first), x.Length, Resampling.Sum(second), y.Length));
            int count = 0;
            for (int repeat = 0; repeat < settings.PowerPerms; repeat++)
            {
                long[] shuffled = (long[])combined.Clone(); generator.Shuffle(shuffled);
                long head = Resampling.Sum(shuffled[..x.Length]);
                if (Math.Abs(Tests.Contrast(head, x.Length, total - head, y.Length)) >= observed) count++;
            }
            if (100 * (count + 1) <= (100 - settings.Confidence) * (settings.PowerPerms + 1)) rejections++;
        }
        double power = (double)rejections / settings.PowerSims;
        return $"power sims {settings.PowerSims} perms {settings.PowerPerms} rejections {rejections} power {Real(power)} se {Real(Math.Sqrt(power * (1 - power) / settings.PowerSims))}";
    }
    private List<string> ExactLines(long[] x, long[] y)
    {
        int size = settings.Pilot;
        long[] first = x[..size], second = y[..size], combined = Concat(first, second), ranks = Tests.DoubledRanks(combined);
        long total = Resampling.Sum(combined);
        List<int[]> choices = Tests.PositionChoices(2 * size, size);
        var meanValues = new long[choices.Count];
        var rankValues = new long[choices.Count];
        for (int i = 0; i < choices.Count; i++)
        {
            long chosen = 0, rankSum = 0;
            foreach (int position in choices[i]) { chosen += combined[position]; rankSum += ranks[position]; }
            meanValues[i] = Tests.Contrast(chosen, size, total - chosen, size);
            rankValues[i] = rankSum - (long)size * (2 * size + 1);
        }
        var mean = new Tally(meanValues[0]);
        var rank = new Tally(rankValues[0]);
        for (int i = 0; i < choices.Count; i++) { mean.Count(meanValues[i]); rank.Count(rankValues[i]); }
        long rankTotal = Resampling.Sum(ranks[..size]);
        int cumulative = 0, attained = 0;
        long? critical = null;
        foreach (var entry in Tests.ValueCounts(meanValues.Select(Math.Abs).ToArray()).Reverse())
        {
            cumulative += entry.Value;
            if (100 * cumulative > (100 - settings.Confidence) * choices.Count) break;
            critical = entry.Key; attained = cumulative;
        }
        string criticalLine = critical is null ? "critical diff none attained none"
            : $"critical diff {Real((double)critical.Value / (100L * size * size))} attained {PValue(attained, choices.Count)}";
        return new List<string>
        {
            $"exact size {size} splits {choices.Count}", $"mean diff {Real(Resampling.MeanDifference(first, second))} {mean.Text(0, choices.Count)}",
            $"ranksum w {Real(rankTotal / 2.0)} u {Real((rankTotal - (long)size * (size + 1)) / 2.0)} {rank.Text(0, choices.Count)}", criticalLine
        };
    }
    private List<string> StudentizedLines(PairBootstrap pair)
    {
        long[] x = pair.First.Group.Values, y = pair.Second.Group.Values;
        int k = x.Length, m = y.Length;
        double estimate = Resampling.MeanDifference(x, y), firstSd = Resampling.Sd(x), secondSd = Resampling.Sd(y);
        double firstVariance = firstSd * firstSd / k, secondVariance = secondSd * secondSd / m;
        double se0 = Math.Sqrt(firstVariance + secondVariance), t = estimate / se0;
        var statistics = new double[settings.Bootstrap];
        int extreme = 0;
        for (int i = 0; i < statistics.Length; i++)
        {
            double first = pair.First.Summaries[3].Values[i], second = pair.Second.Summaries[3].Values[i];
            statistics[i] = (pair.Summaries[0].Values[i] - estimate) / Math.Sqrt(first * first / k + second * second / m);
            if (Math.Abs(statistics[i]) >= Math.Abs(t)) extreme++;
        }
        Array.Sort(statistics);
        double lower = estimate - statistics[highRank - 1] * se0, upper = estimate - statistics[lowRank - 1] * se0;
        double degrees = (firstVariance + secondVariance) * (firstVariance + secondVariance)
            / (firstVariance * firstVariance / (k - 1) + secondVariance * secondVariance / (m - 1));
        long greater = 0, equal = 0;
        foreach (long a in x) foreach (long b in y) { if (a > b) greater++; if (a == b) equal++; }
        double d = Resampling.CohenD(x, y), hedges = d * (1 - 3.0 / (4 * (k + m - 2) - 1));
        double cles = (double)(2 * greater + equal) / (2L * k * m);
        return new List<string>
        {
            $"bootstrap_t t {Real(t)} df {Real(degrees)} extreme {extreme} p {PValue(extreme + 1, settings.Bootstrap + 1)} interval {Real(lower)} {Real(upper)}",
            $"effect pooled_sd {Real(Resampling.PooledSd(x, y))} cohen_d {Real(d)} hedges_g {Real(hedges)} cles {Real(cles)}"
        };
    }
    private List<string> HolmLines(List<int[]> extremes)
    {
        var lines = new List<string>();
        int count = data.Pairs.Count, denominator = settings.Permutations + 1;
        for (int statistic = 0; statistic < 4; statistic++)
        {
            List<int> order = Enumerable.Range(0, count).OrderBy(index => extremes[index][statistic]).ThenBy(index => index).ToList();
            int adjusted = 0;
            for (int i = 0; i < order.Count; i++)
            {
                int index = order[i], extreme = extremes[index][statistic];
                adjusted = Math.Max(adjusted, Math.Min(denominator, (count - i) * (extreme + 1)));
                Comparison pair = data.Pairs[index];
                string verdict = 100 * adjusted <= (100 - settings.Confidence) * denominator ? "reject" : "retain";
                lines.Add($"holm {TestStatistics[statistic]} rank {i + 1} {pair.First.Name} {pair.Second.Name} p {PValue(extreme + 1, denominator)} adjusted {PValue(adjusted, denominator)} {verdict}");
            }
        }
        return lines;
    }
    private static double Tanh(double value) { double growth = Math.Exp(2 * value); return (growth - 1) / (growth + 1); }
    private List<string> PairedLines(Summary[] summaries)
    {
        PairedSample paired = data.Paired;
        long[] differences = paired.Differences;
        int count = differences.Length, positive = differences.Count(value => value > 0), negative = differences.Count(value => value < 0);
        double average = Resampling.Mean(differences), sd = Resampling.Sd(differences), correlation = Resampling.Correlation(paired.Before, paired.After);
        double z = 0.5 * Math.Log((1 + correlation) / (1 - correlation)), halfWidth = -zLow / Math.Sqrt(count - 3);
        return new List<string>
        {
            $"paired subjects {count} positive {positive} negative {negative} zero {count - positive - negative}",
            $"paired before {Real(Resampling.Mean(paired.Before))} after {Real(Resampling.Mean(paired.After))} diff {Real(average)} sd_diff {Real(sd)} t {Real(average / (sd / Math.Sqrt(count)))} dz {Real(average / sd)}",
            $"paired_bootstrap {summaries[0].Interval()}",
            $"correlation r {Real(correlation)} {summaries[1].Interval()} fisher {Real(Tanh(z - halfWidth))} {Real(Tanh(z + halfWidth))}"
        };
    }
    private List<string> SignFlipLines()
    {
        long[] differences = data.Paired.Differences;
        long[] magnitudes = differences.Where(value => value != 0).Select(Math.Abs).ToArray(), ranks = Tests.DoubledRanks(magnitudes);
        var rankOf = new Dictionary<long, long>();
        for (int i = 0; i < ranks.Length; i++) rankOf[magnitudes[i]] = ranks[i];
        long[] signed = differences.Select(value => value == 0 ? 0 : (value > 0 ? 1 : -1) * rankOf[Math.Abs(value)]).ToArray();
        var mean = new Tally(Resampling.Sum(differences));
        var rank = new Tally(Resampling.Sum(signed));
        for (int repeat = 0; repeat < settings.Permutations; repeat++)
        {
            long sum = 0, rankSum = 0;
            for (int i = 0; i < differences.Length; i++)
            {
                int sign = generator.Draw() % 2 == 1 ? -1 : 1;
                sum += sign * differences[i]; rankSum += sign * signed[i];
            }
            mean.Count(sum); rank.Count(rankSum);
        }
        long positive = signed.Where(value => value > 0).Sum();
        return new List<string> { $"signflip flips {settings.Permutations}",
            $"mean diff {Real(Resampling.Mean(differences))} {mean.Text(1, settings.Permutations + 1)}",
            $"signedrank w_plus {Real(positive / 2.0)} {rank.Text(1, settings.Permutations + 1)}" };
    }
    private static List<Delta> Deltas(List<long[]> samples, List<(int, int)> pairs) => pairs.Select(pair =>
    {
        long[] x = samples[pair.Item1], y = samples[pair.Item2];
        return new Delta(Math.Abs(Tests.Contrast(Resampling.Sum(x), x.Length, Resampling.Sum(y), y.Length)), (long)x.Length * y.Length);
    }).ToList();
    private string WelchLine(List<long[]> samples)
    {
        double[] means = samples.Select(Resampling.Mean).ToArray(), weights = new double[samples.Count];
        for (int i = 0; i < weights.Length; i++) { double sd = Resampling.Sd(samples[i]); weights[i] = samples[i].Length / (sd * sd); }
        double total = Resampling.SequentialSum(weights), center = 0;
        for (int i = 0; i < weights.Length; i++) center += weights[i] * means[i];
        center /= total;
        double spread = 0;
        for (int i = 0; i < weights.Length; i++) { double difference = means[i] - center; spread += weights[i] * (difference * difference); }
        spread /= samples.Count - 1;
        double lambda = 0;
        for (int i = 0; i < weights.Length; i++) { double share = 1 - weights[i] / total; lambda += share * share / (samples[i].Length - 1); }
        int groups = samples.Count;
        double f = spread / (1 + 2 * (groups - 2) * lambda / (groups * groups - 1)), degrees = (groups * groups - 1) / (3 * lambda);
        return $"welch f {Real(f)} df {groups - 1} {Real(degrees)}";
    }
    private List<string> AnovaLines(List<GroupBootstrap> ordinary)
    {
        List<long[]> samples = data.Groups.Select(group => group.Values).ToList();
        int[] sizes = samples.Select(sample => sample.Length).ToArray();
        int groups = samples.Count, total = sizes.Sum();
        double[] squares = Tests.SumsOfSquares(samples);
        double between = squares[0], within = squares[1], f = Tests.FStatistic(between, within, groups, total), eta = between / (between + within);
        double msw = within / (total - groups), omega = (between - (groups - 1) * msw) / (between + within + msw);
        var etaValues = new double[settings.Bootstrap];
        for (int i = 0; i < etaValues.Length; i++)
        {
            double[] spread = Tests.SumsOfSquares(ordinary.Select(bootstrap => bootstrap.Samples[i]).ToList());
            etaValues[i] = spread[0] / (spread[0] + spread[1]);
        }
        var etaSummary = new Summary(eta, etaValues, lowRank, highRank);
        long[] combined = samples.SelectMany(sample => sample).ToArray(), ranks = Tests.DoubledRanks(combined);
        long[] rankSums = Tests.SplitList(ranks, sizes).Select(Resampling.Sum).ToArray();
        long tieTotal = 0;
        int tieGroups = 0;
        foreach (int count in Tests.ValueCounts(combined).Values)
            if (count >= 2) { tieGroups++; tieTotal += (long)count * count * count - count; }
        double correction = 1 - (double)tieTotal / ((long)total * total * total - total), h = Tests.HStatistic(rankSums, sizes, correction);
        var lines = new List<string>
        {
            $"anova groups {groups} observations {total} ssb {Real(between)} ssw {Real(within)} df {groups - 1} {total - groups} f {Real(f)} eta_squared {Real(eta)} omega_squared {Real(omega)}",
            "eta_bootstrap " + etaSummary.Interval(), WelchLine(samples), $"kruskal h {Real(h)} tie_groups {tieGroups}"
        };
        var pairs = new List<(int, int)>();
        for (int i = 0; i < groups; i++) for (int j = i + 1; j < groups; j++) pairs.Add((i, j));
        List<Delta> observed = Deltas(samples, pairs);
        int fExtreme = 0, hExtreme = 0;
        var extremes = new int[pairs.Count];
        var maxima = new int[pairs.Count];
        int[] positions = Enumerable.Range(0, total).ToArray();
        for (int repeat = 0; repeat < settings.Permutations; repeat++)
        {
            int[] order = (int[])positions.Clone(); generator.Shuffle(order);
            List<int[]> parts = Tests.SplitList(order, sizes);
            List<long[]> trial = parts.Select(part => Resampling.Sample(combined, part)).ToList();
            var trialRanks = new long[groups];
            for (int i = 0; i < groups; i++) foreach (int index in parts[i]) trialRanks[i] += ranks[index];
            double[] spread = Tests.SumsOfSquares(trial);
            if (Tests.FStatistic(spread[0], spread[1], groups, total) >= f - 0.000000001 * f) fExtreme++;
            if (Tests.HStatistic(trialRanks, sizes, correction) >= h - 0.000000001 * h) hExtreme++;
            List<Delta> values = Deltas(trial, pairs);
            Delta largest = values.Max();
            for (int i = 0; i < pairs.Count; i++)
            {
                if (values[i].CompareTo(observed[i]) >= 0) extremes[i]++;
                if (largest.CompareTo(observed[i]) >= 0) maxima[i]++;
            }
        }
        int denominator = settings.Permutations + 1;
        lines.Add($"anova_permutation perms {settings.Permutations} f_extreme {fExtreme} f_p {PValue(fExtreme + 1, denominator)} h_extreme {hExtreme} h_p {PValue(hExtreme + 1, denominator)}");
        for (int i = 0; i < pairs.Count; i++)
        {
            Group first = data.Groups[pairs[i].Item1], second = data.Groups[pairs[i].Item2];
            lines.Add($"pairwise {first.Name} {second.Name} diff {Real(Resampling.MeanDifference(first.Values, second.Values))} extreme {extremes[i]} p {PValue(extremes[i] + 1, denominator)} maxt {maxima[i]} adjusted {PValue(maxima[i] + 1, denominator)}");
        }
        return lines;
    }
    public Dictionary<string, List<string>> Run()
    {
        var ordinary = new List<GroupBootstrap>();
        var balanced = new List<GroupBootstrap>();
        foreach (Group group in data.Groups) ordinary.Add(new GroupBootstrap(group, Resampling.OrdinaryIndices(generator, group.Values.Length, settings.Bootstrap), lowRank, highRank));
        foreach (Group group in data.Groups) balanced.Add(new GroupBootstrap(group, Resampling.BalancedIndices(generator, group.Values.Length, settings.Bootstrap), lowRank, highRank));
        Summary[] paired = PairedBootstrap();
        List<PairBootstrap> pairs = data.Pairs.Select(comparison => new PairBootstrap(ordinary[comparison.First.Number - 1], ordinary[comparison.Second.Number - 1], lowRank, highRank)).ToList();
        var tests = new List<string>();
        var extremes = new List<int[]>();
        foreach (PairBootstrap pair in pairs)
        {
            long[] x = pair.First.Group.Values, y = pair.Second.Group.Values;
            tests.Add($"compare {pair.First.Group.Name} {pair.Second.Group.Name}");
            TestResult result = PermutationLines(x, y); tests.AddRange(result.Lines); extremes.Add(result.Extremes);
            tests.Add(PowerLine(x, y)); tests.AddRange(ExactLines(x, y)); tests.AddRange(StudentizedLines(pair));
        }
        tests.AddRange(HolmLines(extremes)); tests.AddRange(PairedLines(paired)); tests.AddRange(SignFlipLines()); tests.AddRange(AnovaLines(ordinary));
        var jackknife = new List<string>();
        var histograms = new List<string>();
        foreach (GroupBootstrap bootstrap in ordinary)
        {
            jackknife.AddRange(GroupJackknife(bootstrap));
            for (int statistic = 0; statistic < 4; statistic++) histograms.AddRange(HistogramLines(bootstrap.Group.Name, GroupStatistics[statistic], bootstrap.Summaries[statistic]));
        }
        foreach (PairBootstrap pair in pairs)
        {
            jackknife.AddRange(PairJackknife(pair));
            for (int statistic = 0; statistic < 4; statistic++) histograms.AddRange(HistogramLines(pair.Name, PairStatistics[statistic], pair.Summaries[statistic]));
        }
        return new Dictionary<string, List<string>>(StringComparer.Ordinal)
        {
            ["descriptives.txt"] = DescriptiveLines(), ["bootstrap.csv"] = BootstrapLines(ordinary, balanced, pairs),
            ["jackknife.txt"] = jackknife, ["tests.txt"] = tests, ["histograms.txt"] = histograms
        };
    }
}

static class Program
{
    public static void Main() => Report.WriteFiles(new Study(Dataset.Load("input")).Run());
}
