using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using static Utils;
using static Conventions;

static class Conventions
{
    public static readonly string[] Types = ["FIXED", "ZERO", "AMORT", "FRN"];
    public static readonly string[] Buckets = ["0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+"];
    public static readonly HashSet<int> Frequencies = [1, 2, 4, 12];
    public static readonly HashSet<string> DayCounts = ["30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT"];
    public static readonly HashSet<string> BusinessRules = ["FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED"];
}
readonly record struct Row(int Line, string[] Fields);
static class Utils
{
    public static string[] Read(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII);
    public static IEnumerable<Row> Rows(string name) => Read(name).Skip(1).Select((line, index) => new Row(index + 2, line.Split(',')));
    public static long Round(long numerator, long denominator) => (2 * numerator + denominator) / (2 * denominator);
    public static long Thousandths(string text) { string[] parts = text.Split('.'); return long.Parse(parts[0]) * 1000 + long.Parse(parts[1]); }
    public static string Decimal(double value, int places)
    {
        long scale = 1; for (int i = 0; i < places; i++) scale *= 10;
        long n = (long)((value < 0 ? -value : value) * scale + 0.5);
        return (value < 0 && n != 0 ? "-" : "") + n / scale + "." + (n % scale).ToString(CultureInfo.InvariantCulture).PadLeft(places, '0');
    }
    public static string Hundredths(long value) => value < 0 ? "-" + Hundredths(-value) : value / 100 + "." + (value % 100).ToString(CultureInfo.InvariantCulture).PadLeft(2, '0');
    public static string Percent(double value) => Decimal(value * 100, 4);
    public static string Amount(double value) => Decimal(value / 100, 2);
    public static void Save(string name, IEnumerable<string> lines) => File.WriteAllText(Path.Combine("output", name), string.Concat(lines.Select(line => line + "\n")), Encoding.ASCII);
}
sealed class InputError(string message) : Exception(message) {}
sealed class ErrorLog
{
    public List<string> Lines = [];
    public void Add(string file, int line, string key, string message) => Lines.Add($"{file}:{line}: {key}: {message}");
}
sealed record Scenario(string Name, double[] Deltas);
sealed record RawScenario(int Line, string Name, List<int> Shifts);
sealed class Parameters
{
    public int Valuation, SettlementDays;
    public List<RawScenario> Scenarios = [];
    public List<string[]> Limits = [];
    public Parameters(string[] lines)
    {
        for (int i = 0; i < lines.Length; i++)
        {
            string[] fields = lines[i].Split(' ');
            switch (fields[0])
            {
                case "valuation_date": Valuation = Dates.Parse(fields[1]); break;
                case "settlement_days": SettlementDays = int.Parse(fields[1]); break;
                case "scenario": Scenarios.Add(new(i + 1, fields[1], fields.Skip(2).Select(int.Parse).ToList())); break;
                case "limit": Limits.Add(fields.Skip(1).ToArray()); break;
            }
        }
    }
}
sealed class Fixings
{
    readonly int[] dates, rates;
    public Fixings(IEnumerable<Row> rows) { Row[] values = rows.ToArray(); dates = values.Select(r => Dates.Parse(r.Fields[0])).ToArray(); rates = values.Select(r => int.Parse(r.Fields[1])).ToArray(); }
    public int? Latest(int day)
    {
        int low = 0, high = dates.Length;
        while (low < high) { int middle = (low + high) / 2; if (dates[middle] <= day) low = middle + 1; else high = middle; }
        return low == 0 ? null : rates[low - 1];
    }
}
sealed class Options
{
    public bool Eom, LongStub;
    public int Lag = -1, Cap = -1, Floor = -1;
    public List<(string Date, long Value)> Sinks = [], Calls = [];
}
readonly record struct Period(int Number, int Start, int End, int Payment, Fraction Fraction, int Rate, long Opening, long Coupon, long Principal)
{
    public long Cash => Coupon + Principal;
}
sealed class Bond(string code, string type, int issue, int maturity, int coupon, int frequency, string daycount, string bdc, long face)
{
    public readonly string Code = code, Type = type, Daycount = daycount, Bdc = bdc;
    public readonly int Issue = issue, Maturity = maturity, Coupon = coupon, Frequency = frequency;
    public readonly long Face = face;
    public Options Options = new();
    public List<int> Schedule = [];
    public Dictionary<int, long> Sinks = new();
    public List<(int Day, long Value)> Calls = [];
    public List<Period> Periods = [];
}
static class Input
{
    public static List<Pillar> Pillars(int settlement, ErrorLog errors)
    {
        HashSet<string> seen = new(StringComparer.Ordinal); List<Pillar> pillars = [];
        foreach (Row row in Rows("curve_quotes.csv"))
        {
            string[] f = row.Fields; string error = "";
            if (!seen.Add(f[0])) error = "duplicate pillar";
            else if (!Dates.Valid(f[0])) error = "invalid date";
            else if (Dates.Parse(f[0]) <= settlement) error = "pillar not after settlement";
            else if (!Frequencies.Contains(int.Parse(f[2]))) error = "invalid frequency";
            if (error.Length > 0) errors.Add("curve_quotes.csv", row.Line, f[0], error);
            else pillars.Add(new(Dates.Parse(f[0]), int.Parse(f[1]), int.Parse(f[2])));
        }
        return pillars.OrderBy(p => p.Maturity).ToList();
    }
    public static List<Scenario> Scenarios(List<RawScenario> raw, int pillars, ErrorLog errors)
    {
        HashSet<string> seen = new(StringComparer.Ordinal); List<Scenario> scenarios = [];
        foreach (RawScenario source in raw)
        {
            string error = !seen.Add(source.Name) ? "duplicate scenario" : source.Shifts.Count != pillars ? "wrong number of shifts" : "";
            if (error.Length > 0) errors.Add("params.txt", source.Line, source.Name, error);
            else scenarios.Add(new(source.Name, source.Shifts.Select(s => s * 0.0001).ToArray()));
        }
        return scenarios;
    }
    static Options ParseOptions(string type, string text)
    {
        Options options = new(); HashSet<string> seen = new(StringComparer.Ordinal);
        if (text != "-") foreach (string item in text.Split(';'))
        {
            int equal = item.IndexOf('='); string key = equal < 0 ? item : item[..equal], value = equal < 0 ? "" : item[(equal + 1)..];
            bool allowed = key is "EOM" or "LONG" || type == "FIXED" && key == "CALL" || type == "AMORT" && key == "SINK" || type == "FRN" && key is "LAG" or "CAP" or "FLOOR";
            if (!allowed || !seen.Add(key) && key is not "SINK" and not "CALL") throw new InputError("invalid option");
            switch (key)
            {
                case "EOM": options.Eom = true; break;
                case "LONG": options.LongStub = true; break;
                case "LAG": options.Lag = int.Parse(value); break;
                case "CAP": options.Cap = int.Parse(value); break;
                case "FLOOR": options.Floor = int.Parse(value); break;
                default:
                    string[] fields = value.Split(':'); (key == "SINK" ? options.Sinks : options.Calls).Add((fields[0], key == "SINK" ? long.Parse(fields[1]) : Thousandths(fields[1]))); break;
            }
        }
        if (type == "FRN" && (options.Lag < 1 || options.Lag > 5 || options.Cap > 1200 || options.Floor > (options.Cap < 0 ? 1200 : options.Cap))) throw new InputError("invalid option");
        return options;
    }
    static List<(int Day, long Value)> ScheduleItems(List<(string Date, long Value)> items, List<int> schedule, string reason)
    {
        HashSet<int> inside = schedule.Skip(1).SkipLast(1).ToHashSet(); List<(int Day, long Value)> result = [];
        foreach (var item in items)
        {
            if (!Dates.Valid(item.Date)) throw new InputError(reason);
            int day = Dates.Parse(item.Date); if (!inside.Contains(day) || result.Count > 0 && day <= result[^1].Day) throw new InputError(reason); result.Add((day, item.Value));
        }
        return result;
    }
    static Bond ParseBond(string[] f, Calendar calendar, Fixings fixings)
    {
        if (!Types.Contains(f[1])) throw new InputError("unknown type");
        if (!Dates.Valid(f[2]) || !Dates.Valid(f[3])) throw new InputError("invalid date");
        int issue = Dates.Parse(f[2]), maturity = Dates.Parse(f[3]), coupon = int.Parse(f[4]), frequency = int.Parse(f[5]); long face = long.Parse(f[8]);
        if (maturity <= issue) throw new InputError("maturity not after issue");
        if (!Frequencies.Contains(frequency)) throw new InputError("invalid frequency");
        if (!DayCounts.Contains(f[6])) throw new InputError("unknown day count");
        if (!BusinessRules.Contains(f[7])) throw new InputError("unknown business day rule");
        if (face % 100000 != 0 || face > 10000000) throw new InputError("invalid face");
        if (coupon > 1200 || f[1] == "ZERO" && coupon != 0) throw new InputError("invalid coupon");
        Bond bond = new(f[0], f[1], issue, maturity, coupon, frequency, f[6], f[7], face) { Options = ParseOptions(f[1], f[9]) };
        bond.Schedule = Schedule.Build(issue, maturity, frequency, bond.Options.Eom, bond.Options.LongStub);
        var sinks = ScheduleItems(bond.Options.Sinks, bond.Schedule, "invalid sinking fund"); long total = 0;
        foreach (var sink in sinks) { if (sink.Value == 0) throw new InputError("invalid sinking fund"); bond.Sinks[sink.Day] = sink.Value; total += sink.Value; }
        if (bond.Type == "AMORT" && (total == 0 || total >= face)) throw new InputError("invalid sinking fund");
        bond.Calls = ScheduleItems(bond.Options.Calls, bond.Schedule, "invalid call schedule");
        if (bond.Calls.Any(c => c.Value < 100000 || c.Value > 110000)) throw new InputError("invalid call schedule");
        long opening = face;
        for (int i = 1; i < bond.Schedule.Count; i++)
        {
            int start = bond.Schedule[i - 1], end = bond.Schedule[i], rate = bond.Type == "ZERO" ? 0 : coupon;
            if (bond.Type == "FRN")
            {
                int fixing = calendar.Move(calendar.Adjust(start, bond.Bdc), -bond.Options.Lag);
                rate += fixings.Latest(fixing) ?? throw new InputError("missing fixing");
                if (bond.Options.Floor >= 0) rate = Math.Max(rate, bond.Options.Floor); if (bond.Options.Cap >= 0) rate = Math.Min(rate, bond.Options.Cap);
            }
            Fraction fraction = Daycount.Between(bond.Daycount, start, end); long principal = i + 1 == bond.Schedule.Count ? opening : bond.Sinks.GetValueOrDefault(end);
            long interest = Round(opening * rate * fraction.Numerator, 10000 * fraction.Denominator);
            bond.Periods.Add(new(i, start, end, calendar.Adjust(end, bond.Bdc), fraction, rate, opening, interest, principal)); opening -= principal;
        }
        return bond;
    }
    public static SortedDictionary<string, Bond> Bonds(Calendar calendar, Fixings fixings, ErrorLog errors)
    {
        SortedDictionary<string, Bond> bonds = new(StringComparer.Ordinal); HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (Row row in Rows("bonds.csv")) try { if (!seen.Add(row.Fields[0])) throw new InputError("duplicate id"); Bond bond = ParseBond(row.Fields, calendar, fixings); bonds[bond.Code] = bond; }
        catch (InputError e) { errors.Add("bonds.csv", row.Line, row.Fields[0], e.Message); }
        return bonds;
    }
    public static SortedDictionary<string, Valuation> Prices(SortedDictionary<string, Bond> bonds, int settlement, ErrorLog errors)
    {
        SortedDictionary<string, Valuation> prices = new(StringComparer.Ordinal); HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (Row row in Rows("prices.csv"))
        {
            string code = row.Fields[0]; bool duplicate = !seen.Add(code);
            try
            {
                if (!bonds.TryGetValue(code, out Bond? bond)) throw new InputError("unknown bond"); if (duplicate) throw new InputError("duplicate price");
                if (bond.Issue > settlement || settlement >= bond.Maturity) throw new InputError("not outstanding");
                Valuation valuation = new(bond, Thousandths(row.Fields[1]), settlement);
                if (!(valuation.Pricer.Dirty(0) > valuation.Target && valuation.Target > valuation.Pricer.Dirty(1))) throw new InputError("yield out of range"); prices[code] = valuation;
            }
            catch (InputError e) { errors.Add("prices.csv", row.Line, code, e.Message); }
        }
        return prices;
    }
    public static SortedDictionary<string, SortedDictionary<string, Position>> Holdings(SortedDictionary<string, Bond> bonds, SortedDictionary<string, Valuation> prices, ErrorLog errors)
    {
        SortedDictionary<string, SortedDictionary<string, Position>> groups = new(StringComparer.Ordinal);
        foreach (Row row in Rows("holdings.csv"))
        {
            string[] f = row.Fields;
            try
            {
                if (!bonds.ContainsKey(f[1])) throw new InputError("unknown bond"); if (!prices.TryGetValue(f[1], out Valuation? valuation)) throw new InputError("no price");
                long face = long.Parse(f[2]); if (face % valuation.Bond.Face != 0) throw new InputError("invalid face"); long units = face / valuation.Bond.Face;
                if (!groups.TryGetValue(f[0], out var members)) groups[f[0]] = members = new(StringComparer.Ordinal);
                if (!members.TryGetValue(f[1], out Position? position)) members[f[1]] = position = new(valuation);
                position.Units += units; position.Book += Round(units * valuation.Outstanding * Thousandths(f[3]), 100000);
            }
            catch (InputError e) { errors.Add("holdings.csv", row.Line, f[1], e.Message); }
        }
        return groups;
    }
}
sealed class Valuation
{
    public readonly Bond Bond;
    public readonly long Clean, Outstanding, AccruedAmount, CleanAmount, UnitValue;
    public readonly List<Period> Remaining, Cashflows = [];
    public readonly List<Flow> Flows = [];
    public readonly YieldPricer Pricer;
    public readonly double Accrued, Target, FractionWeight;
    public double Ytm, Ytw, Wal, CurveClean, Spread;
    public Risk Risk;
    public int Workout, NextPayment;
    public Valuation(Bond bond, long clean, int settlement)
    {
        Bond = bond; Clean = clean; Workout = bond.Maturity; int index = 0; while (bond.Periods[index].End <= settlement) index++;
        Remaining = bond.Periods.Skip(index).ToList(); Period current = Remaining[0]; Outstanding = current.Opening;
        Fraction elapsed = Daycount.Between(bond.Daycount, current.Start, settlement); Accrued = current.Rate * (double)elapsed.Numerator / (100 * elapsed.Denominator);
        AccruedAmount = Round(Outstanding * current.Rate * elapsed.Numerator, 10000 * elapsed.Denominator); CleanAmount = Round(Outstanding * clean, 100000); UnitValue = CleanAmount + AccruedAmount;
        Target = clean / 1000.0 + Accrued; Fraction rest = Daycount.Between(bond.Daycount, settlement, current.End); FractionWeight = bond.Frequency * rest.Value;
        foreach (Period period in Remaining) if (period.Cash >= 1) { Cashflows.Add(period); Flows.Add(new(period.Payment - settlement, period.Cash)); }
        Pricer = new(Remaining.Select(p => (double)p.Cash).ToList(), FractionWeight, bond.Frequency, Outstanding); NextPayment = Cashflows[0].Payment;
    }
    public void Analyze(ZeroCurve curve, int settlement)
    {
        Ytm = Pricer.Solve(Target); Ytw = Ytm; Risk = Pricer.Measure(Ytm);
        foreach (var call in Bond.Calls) if (call.Day > settlement)
        {
            List<double> flows = [];
            foreach (Period period in Remaining) { flows.Add(period.Coupon); if (period.End == call.Day) { flows[^1] += Round(period.Opening * call.Value, 100000); break; } }
            double callYield = new YieldPricer(flows, FractionWeight, Bond.Frequency, Outstanding).Solve(Target); if (callYield < Ytw) { Ytw = callYield; Workout = call.Day; }
        }
        long principalDays = 0; foreach (Period period in Cashflows) principalDays += period.Principal * (period.Payment - settlement);
        Wal = (double)principalDays / (365 * Outstanding); CurveClean = curve.PresentValue(Flows) * 100 / Outstanding - Accrued; Spread = curve.Spread(Flows, UnitValue);
    }
}
sealed class Position(Valuation valuation)
{
    public Valuation Valuation { get; } = valuation;
    public Bond Bond => Valuation.Bond;
    public long Units, Book;
    public long Value => Units * Valuation.UnitValue;
    public long Face => Units * Bond.Face;
    public long Outstanding => Units * Valuation.Outstanding;
    public long Gain => Units * Valuation.CleanAmount - Book;
    public double Dv01 => Valuation.Risk.Dv01 * Units * Valuation.Outstanding / 10000;
    public double PresentValue(ZeroCurve curve) => Units * curve.PresentValue(Valuation.Flows, Valuation.Spread);
}
sealed class GroupTotals
{
    public int Count;
    public long Value;
    public double Duration, Dv01;
    public void Add(Position position) { Count++; Value += position.Value; Duration += (double)position.Value * position.Valuation.Risk.Modified; Dv01 += position.Dv01; }
}
sealed class ScenarioResult(string name)
{
    public string Name = name;
    public List<double> Values = [], Pnls = [];
    public double Total, Pnl;
}
sealed class Portfolio(string portfolioName, List<Position> members)
{
    readonly string name = portfolioName;
    readonly List<Position> positions = members;
    long totalValue, face, outstanding, book, gain, income;
    double ytm, modified, convexity, spread, dv01, cashYield, baseValue, effective;
    readonly List<double> baseValues = [], keyRates = [];
    readonly GroupTotals[] typeTotals = Enumerable.Range(0, 4).Select(_ => new GroupTotals()).ToArray();
    readonly GroupTotals[] buckets = Enumerable.Range(0, 5).Select(_ => new GroupTotals()).ToArray();
    readonly SortedDictionary<int, (long Coupon, long Principal)> ladder = new();
    readonly List<ScenarioResult> scenarios = [];
    double Weight(long value) => (double)value * 100 / totalValue;
    double PresentValue(ZeroCurve curve) { double value = 0; foreach (Position p in positions) value += p.PresentValue(curve); return value; }
    double RateDuration(ZeroCurve curve, int pillar)
    {
        double[] down = new double[curve.Rates.Length], up = new double[curve.Rates.Length];
        for (int i = 0; i < down.Length; i++) if (pillar < 0 || i == pillar) { down[i] = -0.0001; up[i] = 0.0001; }
        return (PresentValue(curve.Shifted(down)) - PresentValue(curve.Shifted(up))) / (2 * 0.0001 * baseValue);
    }
    public void Analyze(ZeroCurve curve, List<Scenario> shocks, int settlement)
    {
        List<Flow> allFlows = [];
        foreach (Position p in positions)
        {
            Valuation v = p.Valuation; long value = p.Value; totalValue += value; face += p.Face; outstanding += p.Outstanding; book += p.Book; gain += p.Gain;
            ytm += (double)value * v.Ytm; modified += (double)value * v.Risk.Modified; convexity += (double)value * v.Risk.Convexity; spread += (double)value * v.Spread; dv01 += p.Dv01;
            for (int i = 0; i < v.Flows.Count; i++)
            {
                Flow flow = v.Flows[i]; Period period = v.Cashflows[i]; allFlows.Add(new(flow.Days, p.Units * flow.Amount));
                if (flow.Days <= 365) income += p.Units * period.Coupon;
                int year = Dates.Civil(period.Payment).Year; var row = ladder.GetValueOrDefault(year); ladder[year] = (row.Coupon + p.Units * period.Coupon, row.Principal + p.Units * period.Principal);
            }
            typeTotals[Array.IndexOf(Types, p.Bond.Type)].Add(p);
            int days = p.Bond.Maturity - settlement, bucket = 0; int[] bounds = [365, 1095, 1825, 3650]; while (bucket < bounds.Length && days >= bounds[bucket]) bucket++; buckets[bucket].Add(p);
            double baseline = p.PresentValue(curve); baseValues.Add(baseline); baseValue += baseline;
        }
        ytm /= totalValue; modified /= totalValue; convexity /= totalValue; spread /= totalValue;
        cashYield = Bisection.Solve(rate => new ZeroCurve([0], [rate]).PresentValue(allFlows), 0, 1, totalValue);
        effective = RateDuration(curve, -1); for (int i = 0; i < curve.Rates.Length; i++) keyRates.Add(RateDuration(curve, i));
        foreach (Scenario shock in new[] { new Scenario("BASE", new double[curve.Rates.Length]) }.Concat(shocks))
        {
            ZeroCurve shifted = curve.Shifted(shock.Deltas); ScenarioResult result = new(shock.Name);
            for (int i = 0; i < positions.Count; i++) { double value = positions[i].PresentValue(shifted); result.Values.Add(value); result.Pnls.Add(value - baseValues[i]); result.Total += value; }
            result.Pnl = result.Total - baseValue; scenarios.Add(result);
        }
    }
    string GroupLine(string kind, string label, GroupTotals group) => $"{kind} {label} positions {group.Count} value {Hundredths(group.Value)} weight {Decimal(Weight(group.Value), 4)} duration {Decimal(group.Duration / totalValue, 4)} dv01 {Decimal(group.Dv01, 2)}";
    public List<string> Report()
    {
        List<string> lines = ["portfolio " + name];
        foreach (Position p in positions)
        {
            Valuation v = p.Valuation;
            lines.Add($"position {p.Bond.Code} face {Hundredths(p.Face)} outstanding {Hundredths(p.Outstanding)} clean {Decimal(v.Clean / 1000.0, 6)} value {Hundredths(p.Value)} weight {Decimal(Weight(p.Value), 4)} book {Hundredths(p.Book)} gain {Hundredths(p.Gain)} ytm {Percent(v.Ytm)} modified {Decimal(v.Risk.Modified, 4)} dv01 {Decimal(p.Dv01, 2)}");
        }
        lines.Add($"total positions {positions.Count} face {Hundredths(face)} outstanding {Hundredths(outstanding)} value {Hundredths(totalValue)} book {Hundredths(book)} gain {Hundredths(gain)} income {Hundredths(income)}");
        lines.Add($"risk ytm {Percent(ytm)} yield {Percent(cashYield)} modified {Decimal(modified, 4)} convexity {Decimal(convexity, 4)} zspread {Percent(spread)} dv01 {Decimal(dv01, 2)}");
        lines.Add($"curve effective {Decimal(effective, 4)} krd {string.Join(" ", keyRates.Select(d => Decimal(d, 4)))}");
        for (int i = 0; i < Types.Length; i++) lines.Add(GroupLine("type", Types[i], typeTotals[i]));
        for (int i = 0; i < Buckets.Length; i++) lines.Add(GroupLine("bucket", Buckets[i], buckets[i]));
        long coupons = 0, principal = 0;
        foreach (var row in ladder) { lines.Add($"ladder {row.Key} coupon {Hundredths(row.Value.Coupon)} principal {Hundredths(row.Value.Principal)} total {Hundredths(row.Value.Coupon + row.Value.Principal)}"); coupons += row.Value.Coupon; principal += row.Value.Principal; }
        lines.Add($"ladder total coupon {Hundredths(coupons)} principal {Hundredths(principal)} total {Hundredths(coupons + principal)}");
        if (scenarios.Count > 1)
        {
            ScenarioResult worst = scenarios[1]; foreach (ScenarioResult result in scenarios.Skip(2)) if (result.Pnl < worst.Pnl) worst = result;
            var order = Enumerable.Range(0, positions.Count).OrderBy(i => worst.Pnls[i]).ThenBy(i => positions[i].Bond.Code, StringComparer.Ordinal).Take(3);
            lines.Add($"stress worst {worst.Name} pnl {Amount(worst.Pnl)} losers " + string.Join(" ", order.Select(i => positions[i].Bond.Code + " " + Amount(worst.Pnls[i]))));
        }
        return lines;
    }
    public List<string> ScenarioLines()
    {
        List<string> lines = [];
        foreach (ScenarioResult result in scenarios) { for (int i = 0; i < positions.Count; i++) lines.Add($"{name},{result.Name},{positions[i].Bond.Code},{Amount(result.Values[i])},{Amount(result.Pnls[i])}"); lines.Add($"{name},{result.Name},*,{Amount(result.Total)},{Amount(result.Pnl)}"); }
        return lines;
    }
    public List<string> Compliance(List<string[]> limits, int settlement)
    {
        List<string> lines = []; int breaches = 0;
        foreach (string[] limit in limits)
        {
            bool breach; string detail;
            switch (limit[0])
            {
                case "position_weight":
                    Position largest = positions[0]; foreach (Position p in positions) if (p.Value > largest.Value) largest = p;
                    long bound = long.Parse(limit[1]); detail = $"{largest.Bond.Code} {Decimal(Weight(largest.Value), 4)} limit {Hundredths(bound)}"; breach = largest.Value * 10000 > bound * totalValue; break;
                case "type_weight":
                    long maximum = long.Parse(limit[2]), value = typeTotals[Array.IndexOf(Types, limit[1])].Value;
                    detail = $"{limit[1]} {Decimal(Weight(value), 4)} limit {Hundredths(maximum)}"; breach = value * 10000 > maximum * totalValue; break;
                case "max_maturity":
                    int years = int.Parse(limit[1]), count = positions.Count(p => p.Bond.Maturity - settlement > 365 * years); detail = $"{years}Y positions {count}"; breach = count > 0; break;
                case "min_yield":
                    long minimum = long.Parse(limit[1]); detail = $"{Percent(ytm)} limit {Hundredths(minimum)}"; breach = ytm * 10000 < minimum; break;
                case "duration":
                    long low = long.Parse(limit[1]), high = long.Parse(limit[2]); detail = $"{Decimal(modified, 4)} range {Hundredths(low)} {Hundredths(high)}"; breach = modified < low / 100.0 || modified > high / 100.0; break;
                default:
                    long cents = long.Parse(limit[1]); detail = $"{Decimal(dv01, 2)} limit {Hundredths(cents)}"; breach = dv01 * 100 > cents; break;
            }
            lines.Add($"{name} {limit[0]} {detail} {(breach ? "BREACH" : "PASS")}"); if (breach) breaches++;
        }
        lines.Add($"{name} breaches {breaches}"); return lines;
    }
}
static class Program
{
    static List<string> CashflowLines(SortedDictionary<string, Bond> bonds)
    {
        List<string> lines = ["bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"];
        foreach (Bond bond in bonds.Values) foreach (Period p in bond.Periods) if (p.Cash >= 1) lines.Add($"{bond.Code},{p.Number},{Dates.Format(p.Start)},{Dates.Format(p.End)},{Dates.Format(p.Payment)},{Decimal(p.Fraction.Value, 6)},{p.Rate},{p.Opening},{p.Coupon},{p.Principal}");
        return lines;
    }
    static List<string> AnalyticsLines(SortedDictionary<string, Valuation> prices)
    {
        List<string> lines = ["bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread"];
        foreach (Valuation v in prices.Values) lines.Add(string.Join(",", v.Bond.Code, Decimal(v.Clean / 1000.0, 6), Decimal(v.Accrued, 6), Decimal(v.Target, 6), Percent(v.Ytm), Percent(v.Ytw), Dates.Format(v.Workout), Dates.Format(v.NextPayment), Decimal(v.Wal, 4), Decimal(v.Risk.Macaulay, 4), Decimal(v.Risk.Modified, 4), Decimal(v.Risk.Convexity, 4), Decimal(v.Risk.Dv01, 6), Decimal(v.CurveClean, 6), Percent(v.Spread)));
        return lines;
    }
    static List<string> CurveLines(int valuation, int settlement, List<Pillar> pillars, ZeroCurve curve)
    {
        List<string> lines = [$"valuation {Dates.Format(valuation)} settlement {Dates.Format(settlement)}"]; int previous = 0;
        for (int i = 0; i < pillars.Count; i++)
        {
            Pillar pillar = pillars[i]; int day = curve.Days[i]; lines.Add($"pillar {Dates.Format(pillar.Maturity)} days {day} frequency {pillar.Frequency} par {Hundredths(pillar.Coupon)} zero {Percent(curve.Rates[i])} df {Decimal(curve.Discount(day), 6)} forward {Percent(curve.Forward(previous, day))}"); previous = day;
        }
        for (int year = 1; year <= curve.Days[^1] / 365; year++) { int day = year * 365; lines.Add($"grid {year}Y days {day} zero {Percent(curve.Zero(day))} df {Decimal(curve.Discount(day), 6)} forward {Percent(curve.Forward(day - 365, day))}"); }
        return lines;
    }
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Parameters parameters = new(Read("params.txt")); Calendar calendar = new() { Holidays = Read("calendar.txt").Select(Dates.Parse).ToHashSet() }; Fixings fixings = new(Rows("fixings.csv"));
        int settlement = calendar.Move(parameters.Valuation, parameters.SettlementDays); ErrorLog errors = new();
        List<Pillar> pillars = Input.Pillars(settlement, errors); List<Scenario> scenarios = Input.Scenarios(parameters.Scenarios, pillars.Count, errors);
        var bonds = Input.Bonds(calendar, fixings, errors); var prices = Input.Prices(bonds, settlement, errors); var groups = Input.Holdings(bonds, prices, errors);
        ZeroCurve curve = ZeroCurve.Bootstrap(settlement, pillars); foreach (Valuation valuation in prices.Values) valuation.Analyze(curve, settlement);
        List<string> report = [], scenarioLines = ["portfolio,scenario,bond,value,pnl"], compliance = [];
        foreach (var group in groups) { Portfolio portfolio = new(group.Key, group.Value.Values.ToList()); portfolio.Analyze(curve, scenarios, settlement); report.AddRange(portfolio.Report()); scenarioLines.AddRange(portfolio.ScenarioLines()); compliance.AddRange(portfolio.Compliance(parameters.Limits, settlement)); }
        Directory.CreateDirectory("output"); Save("errors.txt", errors.Lines); Save("cashflows.csv", CashflowLines(bonds)); Save("analytics.csv", AnalyticsLines(prices)); Save("curve.txt", CurveLines(parameters.Valuation, settlement, pillars, curve)); Save("portfolio.txt", report); Save("scenarios.csv", scenarioLines); Save("compliance.txt", compliance);
    }
}
