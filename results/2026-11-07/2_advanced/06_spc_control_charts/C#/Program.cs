global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
using System.Globalization;
using System.Text;

record EstimationPass(int Points, Limits[] Limits, List<int> Outliers);
sealed class Estimate
{
    public List<EstimationPass> Passes = [];
    public Limits[] Limits = [];
    public List<int> Retained = [], Removed = [];
    public bool Converged;
}
record Pattern(int Chart, int Points, List<Signal> Signals);
record Proposal(int Family, int Points, Limits[] Limits);
record CusumPoint(int Number, double Upper, double Lower);
record BandPoint(int Number, double Value, double Width);
sealed class Event(int number, int start)
{
    public int Number = number, Start = start, End = start, Onset = start, OutOfSpec, Kind;
    public List<Signal> Signals = [];
    public int[] Counts = new int[5], Detection = new int[9];
    public double Shift, Spread;
    public int Length => End - Start + 1;
    public bool Contains(int number) => Start <= number && number <= End;
}
record AttributePass(int Lots, Center Center, List<int> Outliers);
sealed class AttributeResult(int chart)
{
    public int Chart = chart, Retained;
    public bool Converged;
    public List<AttributePass> Passes = [];
    public List<int> Removed = [];
    public List<LotPoint> Points = [];
    public List<Signal> Signals = [];
}

sealed class Analysis
{
    static readonly string[] ChartNames = ["XBAR_R", "R", "XBAR_S", "S", "I", "MR", "CUSUM", "EWMA", "MA"];
    static readonly string[] FamilyNames = ["XBAR_R", "XBAR_S", "I_MR"];
    static readonly string[] AttributeNames = ["p", "np", "c", "u"];
    static readonly string[][] Labels = [["XBAR", "R"], ["XBAR", "S"], ["I", "MR"]];
    readonly Input data;
    readonly Settings s;
    readonly Constants constants;
    readonly List<Subgroup> groups;
    readonly Estimate[] estimates = [new(), new(), new()];
    readonly List<Pattern> patterns = [];
    readonly List<Proposal> proposals = [];
    readonly List<Signal> signals = [];
    readonly List<Event> events = [];
    readonly List<CusumPoint> cusum = [];
    readonly List<BandPoint> ewma = [], average = [];
    readonly List<AttributeResult> attributes = [];
    double mu, sigma, reference, interval, sbar, ewmaWidth, maWidth;
    public Analysis(Input input)
    {
        data = input; s = input.Settings; constants = Dataset.ControlConstants(s.Size);
        groups = VariableCharts.Statistics(data.Values, s.Size);
    }
    static string Row(params object[] values) => string.Join(" ", values);
    static string Real(double value)
    {
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text == "-0.0000" ? "0.0000" : text;
    }
    static List<int> Range(int first, int last) => Enumerable.Range(first, last - first + 1).ToList();
    static string NumberList(List<int> values) => values.Count == 0 ? "none" : string.Join(" ", values);
    static string LimitText(string label, Limits limits) => Row(label, "lcl", Real(limits.Lcl), "cl", Real(limits.Cl), "ucl", Real(limits.Ucl));
    static string PairText(int family, Limits[] limits) => Row(LimitText(Labels[family][0], limits[0]), LimitText(Labels[family][1], limits[1]));
    static string RuleName(int rule) => rule < 9 ? rule.ToString() : rule == 9 ? "UPPER" : "LOWER";
    static string Status(bool converged) => converged ? "converged" : "stopped";
    Limits[] FamilyLimits(int family, List<int> points) => VariableCharts.Compute(family, points, data.Values, groups, s.Size, constants);
    Series[] FamilySeries(int family, List<int> points)
    {
        Series[] result = [new([], []), new([], [])];
        for (int j = 0; j < points.Count; j++)
        {
            int point = points[j]; result[0].Numbers.Add(point);
            if (family == 2)
            {
                result[0].Values.Add(data.Values[point - 1]);
                if (j > 0)
                {
                    result[1].Numbers.Add(point);
                    result[1].Values.Add(Math.Abs(data.Values[point - 1] - data.Values[points[j - 1] - 1]));
                }
            }
            else
            {
                Subgroup group = groups[point - 1];
                result[0].Values.Add(group.Mean); result[1].Numbers.Add(point);
                result[1].Values.Add(family == 0 ? group.Range : group.Sd);
            }
        }
        return result;
    }
    int SignalSubgroup(Signal signal) => signal.Chart is 4 or 5 ? (signal.End - 1) / s.Size + 1 : signal.End;
    bool HasSignal(int chart, int end, int rule = 0) => signals.Any(signal => signal.Chart == chart && signal.End == end && (rule == 0 || signal.Rule == rule));
    Event? EventOf(int number) => events.FirstOrDefault(e => e.Contains(number));
    void AddBand(int chart, BandPoint point, int start)
    {
        if (point.Value > mu + point.Width) signals.Add(new(chart, 9, start, point.Number, point.Value, "UP"));
        else if (point.Value < mu - point.Width) signals.Add(new(chart, 10, start, point.Number, point.Value, "DOWN"));
    }
    void EstimateFamilies()
    {
        for (int family = 0; family < 3; family++)
        {
            List<int> initial = Range(1, s.Phase1 * (family == 2 ? s.Size : 1)), points = [..initial];
            Estimate estimate = estimates[family];
            for (int pass = 1; pass <= s.Passes; pass++)
            {
                Limits[] limits = FamilyLimits(family, points);
                Series[] sequences = FamilySeries(family, points);
                SortedSet<int> found = [];
                for (int chart = 0; chart < 2; chart++) for (int j = 0; j < sequences[chart].Values.Count; j++)
                    if (limits[chart].Outside(sequences[chart].Values[j])) found.Add(sequences[chart].Numbers[j]);
                estimate.Passes.Add(new(points.Count, limits, found.ToList())); estimate.Limits = limits;
                if (found.Count == 0) { estimate.Converged = true; break; }
                if (pass == s.Passes) break;
                points.RemoveAll(found.Contains);
            }
            estimate.Retained = points; estimate.Removed = initial.Except(points).ToList();
        }
        for (int family = 0; family < 3; family++)
        {
            Series[] sequences = FamilySeries(family, estimates[family].Retained);
            for (int index = 0; index < 2; index++)
            {
                int chart = family * 2 + index;
                patterns.Add(new(chart, sequences[index].Values.Count, RunRules.Check(chart, sequences[index], estimates[family].Limits[index], s.Rules[chart])));
            }
        }
    }
    void Monitor()
    {
        mu = estimates[0].Limits[0].Cl; sigma = estimates[0].Limits[1].Cl / constants.D2 / Math.Sqrt(s.Size);
        reference = s.CusumK * sigma; interval = s.CusumH * sigma; sbar = estimates[1].Limits[1].Cl;
        for (int chart = 0; chart < 6; chart++)
        {
            Series sequence = new([], []);
            if (chart >= 4)
                for (int t = s.Phase1 * s.Size + 1; t <= data.Values.Length; t++)
                {
                    sequence.Numbers.Add(t);
                    sequence.Values.Add(chart == 4 ? data.Values[t - 1] : Math.Abs(data.Values[t - 1] - data.Values[t - 2]));
                }
            else
                for (int i = s.Phase1; i < groups.Count; i++)
                {
                    sequence.Numbers.Add(i + 1);
                    sequence.Values.Add(chart is 0 or 2 ? groups[i].Mean : chart == 1 ? groups[i].Range : groups[i].Sd);
                }
            signals.AddRange(RunRules.Check(chart, sequence, estimates[chart / 2].Limits[chart % 2], s.Rules[chart]));
        }
        double upper = 0, lower = 0, smooth = mu, factor = 1;
        int upperRun = 0, lowerRun = 0;
        double decay = (1 - s.Weight) * (1 - s.Weight), ratio = s.Weight / (2 - s.Weight);
        ewmaWidth = s.EwmaL * sigma * Math.Sqrt(ratio); maWidth = 3 * sigma / Math.Sqrt(s.Span);
        for (int i = s.Phase1 + 1; i <= groups.Count; i++)
        {
            Subgroup group = groups[i - 1];
            upper = Math.Max(0, upper + (group.Mean - mu - reference)); lower = Math.Max(0, lower + (mu - group.Mean - reference));
            upperRun = upper > 0 ? upperRun + 1 : 0; lowerRun = lower > 0 ? lowerRun + 1 : 0;
            cusum.Add(new(i, upper, lower));
            if (upper > interval) { signals.Add(new(6, 9, i - upperRun + 1, i, upper, "UP")); upper = 0; upperRun = 0; }
            if (lower > interval) { signals.Add(new(6, 10, i - lowerRun + 1, i, lower, "DOWN")); lower = 0; lowerRun = 0; }
            smooth = s.Weight * group.Mean + (1 - s.Weight) * smooth; factor = factor * decay;
            BandPoint e = new(i, smooth, s.EwmaL * sigma * Math.Sqrt(ratio * (1 - factor)));
            ewma.Add(e); AddBand(7, e, i);
            int first = Math.Max(s.Phase1 + 1, i - s.Span + 1), count = i - first + 1;
            long total = 0;
            for (int j = first; j <= i; j++) total += groups[j - 1].Total;
            BandPoint a = new(i, (double)total / (s.Size * count), 3 * sigma / Math.Sqrt(count));
            average.Add(a); AddBand(8, a, first);
        }
        signals.Sort((a, b) => (a.Chart, a.End, a.Rule).CompareTo((b.Chart, b.End, b.Rule)));
    }
    void BuildEvents()
    {
        foreach (int point in signals.Select(SignalSubgroup).Distinct().Order())
        {
            if (events.Count > 0 && point - events[^1].End - 1 <= s.Gap) events[^1].End = point;
            else events.Add(new(events.Count + 1, point));
        }
        foreach (Event e in events)
        {
            bool cusumFound = false;
            foreach (Signal signal in signals.Where(signal => e.Contains(SignalSubgroup(signal))))
            {
                e.Signals.Add(signal);
                bool location = signal.Chart is 0 or 2 or 4 or >= 6;
                int kind = signal.Direction == "NONE" ? 4 : (location ? 0 : 2) + (signal.Direction == "DOWN" ? 1 : 0);
                e.Counts[kind]++;
                int point = SignalSubgroup(signal);
                if (e.Detection[signal.Chart] == 0 || point < e.Detection[signal.Chart]) e.Detection[signal.Chart] = point;
                if (signal.Chart == 6) { e.Onset = cusumFound ? Math.Min(e.Onset, signal.Start) : signal.Start; cusumFound = true; }
            }
            e.Kind = Array.IndexOf(e.Counts, e.Counts.Max());
            long total = 0; double deviations = 0;
            for (int i = e.Start; i <= e.End; i++)
            {
                total += groups[i - 1].Total; deviations += groups[i - 1].Sd;
                e.OutOfSpec += groups[i - 1].Values.Count(value => value < s.Lsl || value > s.Usl);
            }
            double mean = (double)total / (s.Size * e.Length);
            e.Shift = (mean - mu) / sigma; e.Spread = (deviations / e.Length) / sbar;
        }
        for (int family = 0; family < 3; family++)
        {
            List<int> retained = [..estimates[family].Retained];
            for (int i = s.Phase1 + 1; i <= groups.Count; i++) if (EventOf(i) == null)
            {
                if (family == 2) retained.AddRange(Range((i - 1) * s.Size + 1, i * s.Size));
                else retained.Add(i);
            }
            proposals.Add(new(family, retained.Count, FamilyLimits(family, retained)));
        }
    }
    void EstimateAttributes()
    {
        for (int chart = 0; chart < 4; chart++)
        {
            AttributeResult result = new(chart);
            List<int> points = Range(1, data.Lots.Count);
            Center center = new(chart, 0, 0);
            for (int pass = 1; pass <= s.Passes; pass++)
            {
                center = AttributeCharts.CenterLine(chart, data.Lots, points);
                List<int> outliers = points.Where(number => AttributeCharts.Point(data.Lots[number - 1], center).Status != "ok").ToList();
                result.Passes.Add(new(points.Count, center, outliers));
                if (outliers.Count == 0) { result.Converged = true; break; }
                if (pass == s.Passes) break;
                points.RemoveAll(outliers.Contains);
            }
            result.Retained = points.Count;
            Series standardized = new([], []);
            foreach (Lot lot in data.Lots)
            {
                if (!points.Contains(lot.Number)) result.Removed.Add(lot.Number);
                LotPoint point = AttributeCharts.Point(lot, center); result.Points.Add(point);
                standardized.Numbers.Add(lot.Number); standardized.Values.Add(point.Z);
            }
            result.Signals = RunRules.Check(chart, standardized, new(-3, 0, 3), s.Rules[6]);
            attributes.Add(result);
        }
    }
    List<string> LimitsLines()
    {
        List<string> lines = [Row("characteristic", s.Characteristic), Row("subgroup_size", s.Size), Row("subgroups", groups.Count), Row("samples", data.Values.Length), Row("phase1_subgroups", s.Phase1)];
        for (int family = 0; family < 3; family++)
        {
            Estimate e = estimates[family]; lines.Add(Row("family", FamilyNames[family]));
            for (int j = 0; j < e.Passes.Count; j++)
            {
                EstimationPass p = e.Passes[j]; lines.Add(Row("pass", j + 1, "points", p.Points, PairText(family, p.Limits), "out", NumberList(p.Outliers)));
            }
            lines.Add(Row("result", Status(e.Converged), "passes", e.Passes.Count, "retained", e.Retained.Count, "removed", NumberList(e.Removed)));
        }
        foreach (Pattern p in patterns)
        {
            foreach (Signal signal in p.Signals) lines.Add(Row("phase1_signal", ChartNames[p.Chart], signal.Rule, signal.Start, signal.End, Real(signal.Value)));
            lines.Add(Row("phase1_check", ChartNames[p.Chart], "points", p.Points, "signals", p.Signals.Count));
        }
        foreach (Proposal p in proposals) lines.Add(Row("proposed", FamilyNames[p.Family], "points", p.Points, PairText(p.Family, p.Limits)));
        string target = Row("target", Real(mu), "sigma", Real(sigma));
        lines.Add(Row("cusum", target, "k", Real(reference), "h", Real(interval)));
        lines.Add(Row("ewma", target, "lcl", Real(mu - ewmaWidth), "ucl", Real(mu + ewmaWidth)));
        lines.Add(Row("ma", target, "span", s.Span, "lcl", Real(mu - maWidth), "ucl", Real(mu + maWidth)));
        for (int chart = 0; chart < 9; chart++)
        {
            List<Signal> found = signals.Where(signal => signal.Chart == chart).ToList();
            List<int> ends = found.Select(signal => signal.End).Distinct().Order().ToList();
            List<int> rules = chart < 6 ? s.Rules[chart] : [9, 10];
            string counts = string.Join(" ", rules.Select(rule => $"{RuleName(rule)}:{found.Count(signal => signal.Rule == rule)}"));
            int points = (groups.Count - s.Phase1) * (chart is 4 or 5 ? s.Size : 1);
            lines.Add(Row("phase2", ChartNames[chart], "points", points, "signals", found.Count, "signalled", ends.Count, "first", ends.Count == 0 ? "none" : ends[0].ToString(), "by_rule", counts));
        }
        return lines;
    }
    List<string> SignalLines() => ["chart,rule,start,end,value,direction", ..signals.Select(signal => string.Join(",", ChartNames[signal.Chart], RuleName(signal.Rule), signal.Start, signal.End, Real(signal.Value), signal.Direction))];
    List<string> EventLines()
    {
        string[] types = ["SHIFT_UP", "SHIFT_DOWN", "SPREAD_UP", "SPREAD_DOWN", "PATTERN"];
        List<string> lines = [Row("events", events.Count)];
        foreach (Event e in events)
        {
            string charts = string.Join(",", ChartNames.Where((_, chart) => e.Detection[chart] > 0));
            string detection = string.Join(" ", ChartNames.Select((name, chart) => name + ":" + (e.Detection[chart] == 0 ? "-" : e.Detection[chart].ToString())));
            lines.Add(Row("event", e.Number, "start", e.Start, "end", e.End, "length", e.Length, "signals", e.Signals.Count, "charts", charts, "location_up", e.Counts[0], "location_down", e.Counts[1], "spread_up", e.Counts[2], "spread_down", e.Counts[3], "pattern", e.Counts[4], "onset", e.Onset, "shift", Real(e.Shift), "spread", Real(e.Spread), "out_of_spec", e.OutOfSpec, "type", types[e.Kind]));
            lines.Add(Row("detection", e.Number, detection));
        }
        return lines;
    }
    List<string> SubgroupLines()
    {
        List<string> lines = ["subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"];
        Zones zones = new(estimates[0].Limits[0]);
        foreach (Subgroup g in groups)
        {
            bool phase2 = g.Number > s.Phase1;
            string phase = phase2 ? "phase2" : estimates[0].Removed.Contains(g.Number) ? "excluded" : "phase1";
            List<string> fields = [g.Number.ToString(), phase, Real(g.Mean), zones.Name(g.Mean), g.Range.ToString(), Real(g.Sd)];
            if (phase2)
            {
                int index = g.Number - s.Phase1 - 1;
                fields.AddRange([Real(cusum[index].Upper), Real(cusum[index].Lower), Real(ewma[index].Value), Real(average[index].Value)]);
            }
            else fields.AddRange(["-", "-", "-", "-"]);
            Event? e = EventOf(g.Number);
            fields.Add(signals.Count(signal => SignalSubgroup(signal) == g.Number).ToString()); fields.Add(e?.Number.ToString() ?? "-");
            lines.Add(string.Join(",", fields));
        }
        return lines;
    }
    List<string> AttributeLines()
    {
        List<string> lines = [];
        foreach (AttributeResult r in attributes)
        {
            lines.Add(Row("chart", AttributeNames[r.Chart]));
            for (int j = 0; j < r.Passes.Count; j++)
            {
                AttributePass p = r.Passes[j]; lines.Add(Row("pass", j + 1, "lots", p.Lots, "center", Real(p.Center.Value), "out", NumberList(p.Outliers)));
            }
            lines.Add(Row("result", Status(r.Converged), "passes", r.Passes.Count, "retained", r.Retained, "removed", NumberList(r.Removed)));
            for (int j = 0; j < data.Lots.Count; j++)
            {
                Lot lot = data.Lots[j]; LotPoint p = r.Points[j];
                string value = r.Chart == 1 ? lot.Defectives.ToString() : r.Chart == 2 ? lot.Defects.ToString() : Real(p.Value);
                lines.Add(Row("lot", lot.Number, "size", lot.Inspected, "value", value, "lcl", Real(p.Lcl), "ucl", Real(p.Ucl), "z", Real(p.Z), "status", p.Status));
            }
            foreach (Signal signal in r.Signals) lines.Add(Row("signal", signal.Rule, signal.Start, signal.End, Real(signal.Value)));
            lines.Add(Row("signals", r.Signals.Count));
        }
        return lines;
    }
    List<Subgroup> Selected(List<int> points) => points.Select(point => groups[point - 1]).ToList();
    List<string> CapabilityLines()
    {
        List<string> lines = [];
        for (int phase = 0; phase < 2; phase++)
        {
            List<Subgroup> chosen = Selected(phase == 0 ? estimates[0].Retained : Range(s.Phase1 + 1, groups.Count));
            Capability r = new(chosen, s, constants);
            lines.Add(Row("group", phase == 0 ? "phase1" : "phase2", "subgroups", chosen.Count, "values", r.Count));
            (string Name, double Value)[] measures = [("mean", r.Mean), ("sigma_within", r.Within), ("sigma_sbar", r.Sbar), ("sigma_overall", r.Overall), ("cp", r.Cp), ("cpu", r.Cpu), ("cpl", r.Cpl), ("cpk", r.Cpk), ("pp", r.Pp), ("ppu", r.Ppu), ("ppl", r.Ppl), ("ppk", r.Ppk), ("cpm", r.Cpm)];
            foreach (var measure in measures) lines.Add(Row(measure.Name, Real(measure.Value)));
            lines.Add(Row("cpk_ci", Real(r.CpkInterval.Lower), Real(r.CpkInterval.Upper))); lines.Add(Row("ppk_ci", Real(r.PpkInterval.Lower), Real(r.PpkInterval.Upper)));
            lines.AddRange([Row("below_lsl", r.Below), Row("above_usl", r.Above), Row("ppm", Real(r.Ppm))]);
            foreach (Subgroup g in chosen) for (int j = 0; j < s.Size; j++)
            {
                long value = g.Values[j];
                if (value < s.Lsl || value > s.Usl) lines.Add(Row("out_of_spec sample", (g.Number - 1) * s.Size + j + 1, "subgroup", g.Number, "value", value, "side", value < s.Lsl ? "low" : "high"));
            }
            lines.Add(Row("verdict", r.Verdict));
            foreach (HistogramBin bin in r.Bins)
            {
                string text = Row("bin", bin.Lower, bin.Upper, bin.Frequency);
                if (bin.Length > 0) text += " " + new string('#', bin.Length);
                foreach (string mark in bin.Marks) text += " " + mark;
                lines.Add(text);
            }
        }
        for (int first = s.Phase1 + 1; first + s.Window - 1 <= groups.Count; first += s.Step)
        {
            int last = first + s.Window - 1; Capability r = new(Selected(Range(first, last)), s, constants);
            lines.Add(Row("rolling", first, last, "mean", Real(r.Mean), "sigma_within", Real(r.Within), "sigma_overall", Real(r.Overall), "cpk", Real(r.Cpk), "ppk", Real(r.Ppk), "verdict", r.Verdict));
        }
        return lines;
    }
    static string PictureNumber(int number) => number.ToString().PadLeft(3);
    List<string> ChartLines()
    {
        List<string> lines = [];
        for (int picture = 0; picture < 3; picture++)
        {
            int chart = picture == 0 ? 0 : picture == 1 ? 1 : 3, family = chart / 2;
            Limits limits = estimates[family].Limits[chart % 2];
            lines.Add(LimitText("chart " + (picture == 0 ? "XBAR" : picture == 1 ? "R" : "S"), limits));
            foreach (Subgroup g in groups)
            {
                double value = picture == 0 ? g.Mean : picture == 1 ? g.Range : g.Sd;
                string mark = g.Number > s.Phase1 ? "2" : estimates[family].Removed.Contains(g.Number) ? "x" : "1";
                lines.Add(Row(PictureNumber(g.Number), mark, Plot.LimitsBand(limits, value, g.Number > s.Phase1 && HasSignal(chart, g.Number)), Real(value)));
            }
        }
        lines.Add(Row("chart CUSUM h", Real(interval)));
        foreach (CusumPoint p in cusum) lines.Add(Row(PictureNumber(p.Number), Plot.CusumBand(p.Upper, p.Lower, interval, HasSignal(6, p.Number, 9), HasSignal(6, p.Number, 10)), Real(p.Upper), Real(p.Lower)));
        for (int chart = 7; chart <= 8; chart++)
        {
            double scale = chart == 7 ? ewmaWidth : maWidth;
            List<BandPoint> points = chart == 7 ? ewma : average;
            lines.Add(LimitText("chart " + ChartNames[chart], new(mu - scale, mu, mu + scale)));
            foreach (BandPoint p in points) lines.Add(Row(PictureNumber(p.Number), Plot.WidthBand(scale, p.Width, p.Value, mu, HasSignal(chart, p.Number)), Real(p.Value), Real(mu - p.Width), Real(mu + p.Width)));
        }
        string[] pictures = ["P_STD", "NP_STD", "C_STD", "U_STD"];
        foreach (AttributeResult r in attributes)
        {
            lines.Add(LimitText("chart " + pictures[r.Chart], new(-3, 0, 3)));
            for (int j = 0; j < data.Lots.Count; j++) lines.Add(Row(PictureNumber(data.Lots[j].Number), Plot.StandardBand(r.Points[j].Z, r.Points[j].Status == "ok"), Real(r.Points[j].Z)));
        }
        return lines;
    }
    public void Run()
    {
        EstimateFamilies(); Monitor(); BuildEvents(); EstimateAttributes();
        Directory.CreateDirectory("output");
        (string Name, List<string> Lines)[] outputs = [("limits.txt", LimitsLines()), ("signals.csv", SignalLines()), ("events.txt", EventLines()), ("subgroups.csv", SubgroupLines()), ("attribute_charts.txt", AttributeLines()), ("capability.txt", CapabilityLines()), ("charts.txt", ChartLines())];
        foreach (var output in outputs) File.WriteAllText(Path.Combine("output", output.Name), string.Join("\n", output.Lines) + "\n", Encoding.ASCII);
    }
}
static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        new Analysis(Dataset.Read()).Run();
    }
}
