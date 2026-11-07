using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

static class Program
{
    static readonly string[] Weekdays = { "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" };
    static readonly string[] FlowNames = { "PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
        "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY" };
    static readonly Dictionary<string, int> ReportArities = new(StringComparer.Ordinal)
    {
        ["HOURLY"] = 1, ["DAILY"] = 0, ["BILL"] = 0, ["SAVINGS"] = 0,
        ["BYPERIOD"] = 0, ["DAYTYPE"] = 0, ["PEAKS"] = 1, ["PROFILE"] = 0,
        ["FLOWS"] = 0, ["SELFSUFF"] = 0, ["CYCLES"] = 0, ["USAGE"] = 0,
        ["HISTOGRAM"] = 0, ["CHART"] = 1
    };

    sealed class CommandError(string message) : Exception(message) { }

    static long Integer(string text) => long.Parse(text, CultureInfo.InvariantCulture);
    static long CeilDiv(long value, long divisor) => (value + divisor - 1) / divisor;
    static long Min3(long a, long b, long c) => Math.Min(a, Math.Min(b, c));
    static string Field(object value, int width) =>
        Convert.ToString(value, CultureInfo.InvariantCulture)!.PadLeft(width);
    static string Bar(long width) => "|" + new string('#', (int)width) + new string('.', 20 - (int)width) + "|";

    static string Money(long value)
    {
        long magnitude = Math.Abs(value);
        return $"{(value < 0 ? "-" : "")}{magnitude / 100}.{magnitude % 100:00}";
    }

    static string Percentage(long numerator, long denominator) =>
        Money(denominator == 0 ? 0 : 10000 * numerator / denominator);

    static long Gcd(long a, long b)
    {
        while (b != 0) (a, b) = (b, a % b);
        return a;
    }

    enum Item { Capacity, Initial, Charge, Discharge, Ceff, Deff, Reserve, Cost, Export, Feedin, Fixed, Demand, Pvscale }
    enum StrategyKind { Self, Tou, PeakShave, Backup, ExportPeak }

    static T Named<T>(string name, string error) where T : struct, Enum
    {
        foreach (T value in Enum.GetValues<T>())
            if (value.ToString().ToUpperInvariant() == name) return value;
        throw new CommandError($"{error} {name}");
    }

    static (long Minimum, long Maximum) Bounds(Item item) => (
        item is Item.Capacity or Item.Charge or Item.Discharge or Item.Ceff or Item.Deff ? 1 : 0,
        item switch
        {
            Item.Initial or Item.Ceff or Item.Deff or Item.Reserve => 100,
            Item.Charge or Item.Discharge => 20000,
            Item.Feedin => 10000,
            Item.Pvscale => 300,
            _ => 100000
        });

    sealed record Settings(long Capacity, long Initial, long Charge, long Discharge,
        long Ceff, long Deff, long Reserve, long Cost, long Export, long Feedin,
        long Fixed, long Demand, long Pvscale = 100)
    {
        public long this[Item item] => item switch
        {
            Item.Capacity => Capacity, Item.Initial => Initial, Item.Charge => Charge,
            Item.Discharge => Discharge, Item.Ceff => Ceff, Item.Deff => Deff,
            Item.Reserve => Reserve, Item.Cost => Cost, Item.Export => Export,
            Item.Feedin => Feedin, Item.Fixed => Fixed, Item.Demand => Demand,
            Item.Pvscale => Pvscale, _ => throw new ArgumentOutOfRangeException(nameof(item))
        };

        public Settings With(Item item, long value) => item switch
        {
            Item.Capacity => this with { Capacity = value },
            Item.Initial => this with { Initial = value },
            Item.Charge => this with { Charge = value },
            Item.Discharge => this with { Discharge = value },
            Item.Ceff => this with { Ceff = value },
            Item.Deff => this with { Deff = value },
            Item.Reserve => this with { Reserve = value },
            Item.Cost => this with { Cost = value },
            Item.Export => this with { Export = value },
            Item.Feedin => this with { Feedin = value },
            Item.Fixed => this with { Fixed = value },
            Item.Demand => this with { Demand = value },
            Item.Pvscale => this with { Pvscale = value },
            _ => throw new ArgumentOutOfRangeException(nameof(item))
        };
    }

    sealed record Strategy(StrategyKind Kind, long Parameter = 0)
    {
        public bool HasParameter => Kind is StrategyKind.Tou or StrategyKind.PeakShave or StrategyKind.Backup;
        public string Notation => Kind.ToString().ToUpperInvariant() + (HasParameter ? $" {Parameter}" : "");
    }

    static List<Strategy> Strategies(string[] words)
    {
        var strategies = new List<Strategy>();
        for (int i = 0; i < words.Length; i++)
        {
            string name = words[i];
            var kind = Named<StrategyKind>(name, "unknown strategy");
            var strategy = new Strategy(kind);
            if (strategy.HasParameter)
            {
                if (++i == words.Length) throw new CommandError($"missing parameter for {name}");
                long parameter = Integer(words[i]);
                long low = kind == StrategyKind.Tou ? 1 : 0;
                long high = kind == StrategyKind.PeakShave ? 100000 : 100;
                if (parameter < low || parameter > high)
                    throw new CommandError($"invalid parameter for {name}");
                strategy = new Strategy(kind, parameter);
            }
            strategies.Add(strategy);
        }
        return strategies;
    }

    static Strategy OneStrategy(string[] words)
    {
        var parsed = Strategies(words);
        if (parsed.Count != 1) throw new CommandError("wrong number of arguments");
        return parsed[0];
    }

    readonly record struct HourInput(long Load, long Pv, int Period);
    sealed record Outage(int First, int Last);

    static (int Low, int High) Extremes(IReadOnlyList<long> prices)
    {
        int low = 0, high = 0;
        for (int p = 1; p < prices.Count; p++)
        {
            if (prices[p] < prices[low]) low = p;
            if (prices[p] > prices[high]) high = p;
        }
        return (low, high);
    }

    sealed class Data(string[] periods, HourInput[] hours, HashSet<int> holidays)
    {
        public string[] Periods { get; } = periods;
        public HourInput[] Hours { get; } = hours;
        public int Days => Hours.Length / 24;
        public bool Weekend(int day) => day % 7 >= 5 || holidays.Contains(day);
        public string DayName(int day) => holidays.Contains(day) ? "HOL" : Weekdays[day % 7];
    }

    sealed class Metrics
    {
        public long Load, Pv, Charge, Discharge, Drawn, Soc, Imported, Exported;
        public long Curtailed, Shortfall, Loss, ImportCost, ExportIncome;
        public long Net => ImportCost - ExportIncome;

        public void Add(Metrics other)
        {
            Load += other.Load;
            Pv += other.Pv;
            Charge += other.Charge;
            Discharge += other.Discharge;
            Drawn += other.Drawn;
            Soc += other.Soc;
            Imported += other.Imported;
            Exported += other.Exported;
            Curtailed += other.Curtailed;
            Shortfall += other.Shortfall;
            Loss += other.Loss;
            ImportCost += other.ImportCost;
            ExportIncome += other.ExportIncome;
        }
    }

    sealed record HourRecord(int Period, Metrics Values, long[] Flows);

    sealed class Result
    {
        public Settings Settings { get; }
        public long[] Prices { get; }
        public Strategy Strategy { get; }
        public HourRecord[] Records { get; }
        public long Starting { get; }
        public long Reserve { get; }
        public Metrics Total { get; } = new();
        public Metrics[] Periods { get; }
        public int[] PeriodHours { get; }
        public long[] Flows { get; } = new long[8];
        public long Peak { get; }
        public long DemandCharge { get; }
        public long Bill { get; }
        public long EndSoc => Records[^1].Values.Soc;
        public string Sufficiency => Percentage(Math.Max(0, Total.Load - Total.Imported), Total.Load);

        public Result(Settings settings, IReadOnlyList<long> prices, Strategy strategy,
            HourRecord[] records, long starting, long reserve)
        {
            Settings = settings;
            Prices = prices.ToArray();
            Strategy = strategy;
            Records = records;
            Starting = starting;
            Reserve = reserve;
            Periods = Enumerable.Range(0, prices.Count).Select(_ => new Metrics()).ToArray();
            PeriodHours = new int[prices.Count];
            foreach (var record in records)
            {
                Total.Add(record.Values);
                Periods[record.Period].Add(record.Values);
                PeriodHours[record.Period]++;
                Peak = Math.Max(Peak, record.Values.Imported);
                for (int i = 0; i < Flows.Length; i++) Flows[i] += record.Flows[i];
            }
            DemandCharge = Peak * settings.Demand / 1000;
            Bill = Total.Net + settings.Fixed + DemandCharge;
        }

        public Metrics Sum(IEnumerable<int> indices)
        {
            var total = new Metrics();
            foreach (int index in indices) total.Add(Records[index].Values);
            return total;
        }

        public Metrics Day(int day) => Sum(Enumerable.Range(day * 24, 24));
    }

    static Result Simulate(Data data, Settings settings, IReadOnlyList<long> prices,
        Strategy strategy, Outage? outage = null)
    {
        long capacity = settings.Capacity;
        long reservePercent = strategy.Kind == StrategyKind.Backup
            ? Math.Max(settings.Reserve, strategy.Parameter) : settings.Reserve;
        long reserve = capacity * reservePercent / 100;
        long starting = capacity * settings.Initial / 100;
        var periods = Extremes(prices);
        bool arbitrage = strategy.Kind == StrategyKind.ExportPeak && settings.Feedin > prices[periods.Low];
        long soc = starting;
        var records = new HourRecord[data.Hours.Length];
        for (int i = 0; i < records.Length; i++)
        {
            var input = data.Hours[i];
            int p = input.Period;
            long pv = input.Pv * settings.Pvscale / 100;
            long direct = Math.Min(input.Load, pv);
            long surplus = pv - direct, deficit = input.Load - direct;
            long x1 = Min3(surplus, settings.Charge, CeilDiv(100 * (capacity - soc), settings.Ceff));
            long stored1 = x1 * settings.Ceff / 100;
            soc += stored1;
            surplus -= x1;
            bool off = outage != null && i >= outage.First && i <= outage.Last;
            long target = off ? deficit : strategy.Kind switch
            {
                StrategyKind.Self or StrategyKind.Backup => deficit,
                StrategyKind.Tou => p == periods.High ? deficit : 0,
                StrategyKind.PeakShave => Math.Max(0, deficit - strategy.Parameter),
                StrategyKind.ExportPeak => arbitrage && p == periods.Low && p != periods.High ? 0 : deficit,
                _ => throw new InvalidOperationException()
            };
            long lower = off ? 0 : reserve;
            long y1 = Min3(CeilDiv(100 * target, settings.Deff), settings.Discharge, Math.Max(0, soc - lower));
            long d1 = y1 * settings.Deff / 100;
            soc -= y1;
            deficit -= d1;
            long gridLoad = off ? 0 : deficit;
            long e1 = off ? 0 : Math.Min(surplus, settings.Export);
            long x2 = 0, y2 = 0, d2 = 0;
            if (!off)
            {
                long headroom = settings.Charge - x1;
                long? targetSoc = null;
                switch (strategy.Kind)
                {
                    case StrategyKind.Tou:
                        if (p == periods.Low && p != periods.High) targetSoc = capacity * strategy.Parameter / 100;
                        break;
                    case StrategyKind.PeakShave:
                        if (p == periods.Low)
                        {
                            targetSoc = capacity;
                            headroom = Math.Min(headroom, Math.Max(0, strategy.Parameter - gridLoad));
                        }
                        break;
                    case StrategyKind.Backup:
                        if (p == periods.Low) targetSoc = reserve;
                        break;
                    case StrategyKind.ExportPeak:
                        if (arbitrage && p == periods.Low && p != periods.High) targetSoc = capacity;
                        break;
                }
                if (targetSoc is long goal)
                {
                    x2 = Math.Min(headroom, CeilDiv(100 * Math.Max(0, goal - soc), settings.Ceff));
                    soc += x2 * settings.Ceff / 100;
                }
                if (strategy.Kind == StrategyKind.ExportPeak && arbitrage && p == periods.High && x1 == 0)
                {
                    y2 = Min3(CeilDiv(100 * (settings.Export - e1), settings.Deff),
                        settings.Discharge - y1, Math.Max(0, soc - reserve));
                    d2 = y2 * settings.Deff / 100;
                    soc -= y2;
                }
            }
            long imported = gridLoad + x2, exported = e1 + d2, curtailed = surplus - e1;
            var values = new Metrics
            {
                Load = input.Load, Pv = pv, Charge = x1 + x2, Discharge = d1 + d2,
                Drawn = y1 + y2, Soc = soc, Imported = imported, Exported = exported,
                Curtailed = curtailed, Shortfall = off ? deficit : 0,
                Loss = x1 - stored1 + x2 - x2 * settings.Ceff / 100 + y1 - d1 + y2 - d2,
                ImportCost = imported * prices[p] / 100000,
                ExportIncome = exported * settings.Feedin / 100000
            };
            records[i] = new HourRecord(p, values,
                new[] { direct, x1, e1, curtailed, d1, d2, gridLoad, x2 });
        }
        return new Result(settings, prices, strategy, records, starting, reserve);
    }

    static Result Baseline(Data data, Settings settings, IReadOnlyList<long> prices) =>
        Simulate(data, settings with { Capacity = 0 }, prices, new Strategy(StrategyKind.Self));

    sealed class Dispatch
    {
        readonly Data data;
        readonly Settings initialSettings;
        readonly long[] initialPrices;
        Settings settings;
        long[] prices;
        Result? current;
        public StringBuilder Output { get; } = new();
        Result Current => current ?? throw new CommandError("no run");

        public Dispatch(Data data, Settings settings, long[] prices)
        {
            this.data = data;
            this.settings = initialSettings = settings;
            this.prices = prices.ToArray();
            initialPrices = prices.ToArray();
        }

        void Emit(string line) => Output.Append(line).Append('\n');
        static void Arity(string[] args, int count)
        {
            if (args.Length != count) throw new CommandError("wrong number of arguments");
        }

        int DayArgument(string text)
        {
            long day = Integer(text);
            if (day < 1 || day > data.Days) throw new CommandError("invalid day");
            return (int)day - 1;
        }

        static void ValidateRange(long low, long high, long step, Item item)
        {
            var bounds = Bounds(item);
            if (low < bounds.Minimum || high > bounds.Maximum || high < low ||
                step < 1 || (high - low) / step + 1 > 20) throw new CommandError("invalid range");
        }

        void Table(params object[] values) =>
            Emit(Field(values[0], 4) + string.Concat(values.Skip(1).Select(value => Field(value, 7))));

        void Config()
        {
            var s = settings;
            var bounds = Extremes(prices);
            Emit($"BATTERY capacity {s.Capacity} initial {s.Initial} charge {s.Charge} discharge {s.Discharge} " +
                $"ceff {s.Ceff} deff {s.Deff} reserve {s.Reserve} cost {s.Cost}");
            Emit($"GRID export {s.Export} feedin {s.Feedin} fixed {s.Fixed} demand {s.Demand}");
            Emit($"SOLAR pvscale {s.Pvscale}");
            string tariff = string.Join(" ", prices.Select((price, p) => $"{data.Periods[p]} {price}"));
            Emit($"TARIFF {tariff} cheapest {data.Periods[bounds.Low]} peak {data.Periods[bounds.High]}");
        }

        void Compare(string[] args)
        {
            var parsed = Strategies(args);
            if (parsed.Count == 0) throw new CommandError("wrong number of arguments");
            var baseline = Baseline(data, settings, prices);
            var rows = parsed.Select(strategy => Simulate(data, settings, prices, strategy))
                .OrderBy(result => result.Bill).ToArray();
            Emit($"COMPARE baseline {Money(baseline.Bill)}");
            for (int i = 0; i < rows.Length; i++)
            {
                var r = rows[i];
                Emit($"{i + 1}. {r.Strategy.Notation} bill {Money(r.Bill)} " +
                    $"saving {Money(baseline.Bill - r.Bill)} sufficiency {r.Sufficiency}%");
            }
        }

        void Size(string[] args)
        {
            Arity(args, 3);
            long low = Integer(args[0]), high = Integer(args[1]), step = Integer(args[2]);
            ValidateRange(low, high, step, Item.Capacity);
            var baseline = Baseline(data, settings, prices);
            (long Capacity, long Cost, long Saving)? best = null;
            for (long capacity = low; capacity <= high; capacity += step)
            {
                var trial = Simulate(data, settings with { Capacity = capacity }, prices, new Strategy(StrategyKind.Self));
                long saving = baseline.Bill - trial.Bill;
                long cost = capacity * settings.Cost / 1000;
                string payback = "never";
                if (saving > 0)
                {
                    long value = 10 * cost / saving;
                    payback = $"{value / 10}.{value % 10}";
                    if (best is null || cost * best.Value.Saving < best.Value.Cost * saving)
                        best = (capacity, cost, saving);
                }
                Emit($"SIZE {capacity} bill {Money(trial.Bill)} saving {Money(saving)} cost {Money(cost)} payback {payback}");
            }
            Emit($"BEST {(best is { } chosen ? chosen.Capacity.ToString(CultureInfo.InvariantCulture) : "none")}");
        }

        void Sweep(string[] args)
        {
            if (args.Length < 5) throw new CommandError("wrong number of arguments");
            var item = Named<Item>(args[0], "unknown parameter");
            long low = Integer(args[1]), high = Integer(args[2]), step = Integer(args[3]);
            ValidateRange(low, high, step, item);
            var strategy = OneStrategy(args[4..]);
            (long SettingValue, long Bill)? best = null;
            for (long value = low; value <= high; value += step)
            {
                var changed = settings.With(item, value);
                var trial = Simulate(data, changed, prices, strategy);
                var baseline = Baseline(data, changed, prices);
                Emit($"SWEEP {args[0]} {value} bill {Money(trial.Bill)} " +
                    $"saving {Money(baseline.Bill - trial.Bill)} sufficiency {trial.Sufficiency}%");
                if (best is null || trial.Bill < best.Value.Bill) best = (value, trial.Bill);
            }
            Emit($"BEST {best!.Value.SettingValue}");
        }

        void EvaluateOutage(string[] args)
        {
            Arity(args, 3);
            int day = DayArgument(args[0]);
            long start = Integer(args[1]), end = Integer(args[2]);
            if (start < 0 || end > 23 || start > end) throw new CommandError("invalid hours");
            var saved = Current;
            int first = day * 24 + (int)start, last = day * 24 + (int)end;
            var trial = Simulate(data, saved.Settings, saved.Prices, saved.Strategy, new Outage(first, last));
            long before = first == 0 ? trial.Starting : trial.Records[first - 1].Values.Soc;
            Emit($"OUTAGE day {day + 1} hours {start}-{end} strategy {saved.Strategy.Notation} soc {before}");
            Emit("hour   load     pv  disch    soc  short   curt");
            var total = new Metrics();
            for (int i = first; i <= last; i++)
            {
                var v = trial.Records[i].Values;
                total.Add(v);
                Table(i % 24, v.Load, v.Pv, v.Discharge, v.Soc, v.Shortfall, v.Curtailed);
            }
            string served = total.Load == 0 ? "100.00" : Percentage(total.Load - total.Shortfall, total.Load);
            Emit($"TOTAL load {total.Load} unserved {total.Shortfall} served {served}% bill {Money(trial.Bill)}");
        }

        void Difference(string[] args)
        {
            if (args.Length < 2) throw new CommandError("wrong number of arguments");
            int day = DayArgument(args[0]);
            var strategy = OneStrategy(args[1..]);
            var saved = Current;
            var trial = Simulate(data, saved.Settings, saved.Prices, strategy);
            Emit($"DIFF day {day + 1} {data.DayName(day)} {saved.Strategy.Notation} vs {strategy.Notation}");
            Emit("hour   imp1   imp2   exp1   exp2   soc1   soc2");
            for (int hour = 0; hour < 24; hour++)
            {
                var a = saved.Records[day * 24 + hour].Values;
                var b = trial.Records[day * 24 + hour].Values;
                Table(hour, a.Imported, b.Imported, a.Exported, b.Exported, a.Soc, b.Soc);
            }
            long cost1 = saved.Day(day).Net, cost2 = trial.Day(day).Net;
            Emit($"TOTAL cost1 {Money(cost1)} cost2 {Money(cost2)} difference {Money(cost2 - cost1)}");
        }

        void Hourly(Result r, int day)
        {
            Emit($"HOURLY day {day + 1} {data.DayName(day)} strategy {r.Strategy.Notation}");
            Emit("hour   load     pv charge  disch    soc import export   curt");
            for (int hour = 0; hour < 24; hour++)
            {
                var v = r.Records[day * 24 + hour].Values;
                Table(hour, v.Load, v.Pv, v.Charge, v.Discharge, v.Soc, v.Imported, v.Exported, v.Curtailed);
            }
            var total = r.Day(day);
            Table("sum", total.Load, total.Pv, total.Charge, total.Discharge, "", total.Imported, total.Exported, total.Curtailed);
        }

        void Daily(Result r)
        {
            Emit($"DAILY strategy {r.Strategy.Notation}");
            Emit("day name    load      pv  import  export    curt     soc      cost");
            for (int day = 0; day < data.Days; day++)
            {
                var v = r.Day(day);
                long soc = r.Records[day * 24 + 23].Values.Soc;
                Emit($"{day + 1,3}{data.DayName(day),5}{v.Load,8}{v.Pv,8}{v.Imported,8}{v.Exported,8}{v.Curtailed,8}{soc,8}{Money(v.Net),10}");
            }
            var total = r.Total;
            Emit($"TOTAL load {total.Load} pv {total.Pv} import {total.Imported} export {total.Exported} " +
                $"curtailed {total.Curtailed} cost {Money(total.Net)}");
        }

        void Bill(Result r)
        {
            Emit($"BILL strategy {r.Strategy.Notation} days {data.Days}");
            for (int p = 0; p < data.Periods.Length; p++)
                Emit($"IMPORT {data.Periods[p]} {r.Periods[p].Imported} Wh {Money(r.Periods[p].ImportCost)}");
            Emit($"EXPORT {r.Total.Exported} Wh {Money(-r.Total.ExportIncome)}");
            Emit($"FIXED {Money(r.Settings.Fixed)}");
            Emit($"DEMAND {r.Peak} Wh {Money(r.DemandCharge)}");
            Emit($"TOTAL {Money(r.Bill)}");
        }

        void Savings(Result r)
        {
            var baseline = Baseline(data, r.Settings, r.Prices);
            Emit($"SAVINGS strategy {r.Strategy.Notation}");
            void Row(string name, long before, long after) =>
                Emit($"{name} {Money(before)} -> {Money(after)} saving {Money(before - after)}");
            for (int p = 0; p < data.Periods.Length; p++)
                Row(data.Periods[p], baseline.Periods[p].ImportCost, r.Periods[p].ImportCost);
            Row("EXPORT", -baseline.Total.ExportIncome, -r.Total.ExportIncome);
            Row("DEMAND", baseline.DemandCharge, r.DemandCharge);
            Row("TOTAL", baseline.Bill, r.Bill);
        }

        void DayType(Result r)
        {
            Emit($"DAYTYPE strategy {r.Strategy.Notation}");
            foreach (bool weekend in new[] { false, true })
            {
                int count = 0;
                var total = new Metrics();
                for (int day = 0; day < data.Days; day++)
                {
                    if (data.Weekend(day) != weekend) continue;
                    count++;
                    total.Add(r.Day(day));
                }
                Emit($"{(weekend ? "WEEKEND" : "WEEKDAY")} days {count} load {total.Load / count} " +
                    $"pv {total.Pv / count} import {total.Imported / count} export {total.Exported / count} cost {Money(total.Net / count)}");
            }
        }

        void Peaks(Result r, int count)
        {
            Emit($"PEAKS strategy {r.Strategy.Notation}");
            int[] indices = Enumerable.Range(0, r.Records.Length)
                .Where(i => r.Records[i].Values.Imported > 0)
                .OrderByDescending(i => r.Records[i].Values.Imported).Take(count).ToArray();
            if (indices.Length == 0) Emit("none");
            for (int rank = 0; rank < indices.Length; rank++)
            {
                int i = indices[rank];
                var record = r.Records[i];
                var v = record.Values;
                Emit($"{rank + 1}. day {i / 24 + 1} hour {i % 24} {data.Periods[record.Period]} " +
                    $"import {v.Imported} load {v.Load} soc {v.Soc}");
            }
        }

        void Usage(Result r)
        {
            int charging = 0, discharging = 0, idle = 0, full = 0, low = 0;
            int streak = 0, longest = 0, first = 0;
            for (int i = 0; i < r.Records.Length; i++)
            {
                var v = r.Records[i].Values;
                if (v.Charge > 0) charging++;
                if (v.Drawn > 0) discharging++;
                if (v.Charge == 0 && v.Drawn == 0) idle++;
                if (v.Soc == r.Settings.Capacity) full++;
                if (v.Soc <= r.Reserve)
                {
                    low++;
                    streak++;
                    if (streak > longest) { longest = streak; first = i - streak + 1; }
                }
                else streak = 0;
            }
            Emit($"USAGE charging {charging} discharging {discharging} idle {idle} full {full} low {low} longest {longest}" +
                (longest > 0 ? $" from day {first / 24 + 1} hour {first % 24}" : ""));
        }

        void Report(string command, Result r, int argument)
        {
            switch (command)
            {
                case "HOURLY": Hourly(r, argument); break;
                case "DAILY": Daily(r); break;
                case "BILL": Bill(r); break;
                case "SAVINGS": Savings(r); break;
                case "DAYTYPE": DayType(r); break;
                case "PEAKS": Peaks(r, argument); break;
                case "USAGE": Usage(r); break;
                case "BYPERIOD":
                    Emit($"BYPERIOD strategy {r.Strategy.Notation}");
                    for (int p = 0; p < data.Periods.Length; p++)
                    {
                        var v = r.Periods[p];
                        Emit($"{data.Periods[p]} hours {r.PeriodHours[p]} load {v.Load} pv {v.Pv} " +
                            $"charge {v.Charge} discharge {v.Discharge} import {v.Imported} export {v.Exported}");
                    }
                    break;
                case "PROFILE":
                    Emit($"PROFILE strategy {r.Strategy.Notation} days {data.Days}");
                    Emit("hour   load     pv import export    soc");
                    for (int hour = 0; hour < 24; hour++)
                    {
                        var v = r.Sum(Enumerable.Range(0, data.Days).Select(day => day * 24 + hour));
                        Table(hour, v.Load / data.Days, v.Pv / data.Days, v.Imported / data.Days, v.Exported / data.Days, v.Soc / data.Days);
                    }
                    break;
                case "FLOWS":
                    Emit($"FLOWS strategy {r.Strategy.Notation}");
                    for (int i = 0; i < FlowNames.Length; i++) Emit($"{FlowNames[i]} {r.Flows[i]}");
                    Emit($"LOSSES {r.Total.Loss}");
                    Emit($"STORED {r.EndSoc - r.Starting}");
                    break;
                case "SELFSUFF":
                    Emit($"SELFSUFF sufficiency {r.Sufficiency}% consumption {Percentage(r.Flows[0] + r.Flows[1], r.Total.Pv)}%");
                    break;
                case "CYCLES":
                {
                    long drawn = r.Total.Drawn, capacity = r.Settings.Capacity;
                    long divisor = Gcd(drawn, capacity), value = 1000 * drawn / capacity;
                    Emit($"CYCLES {drawn / divisor}/{capacity / divisor} {value / 1000}.{value % 1000:000} drawn {drawn} losses {r.Total.Loss}");
                    break;
                }
                case "HISTOGRAM":
                {
                    Emit($"HISTOGRAM strategy {r.Strategy.Notation}");
                    var counts = new int[10];
                    foreach (var record in r.Records)
                        counts[(int)Math.Min(9, 10 * record.Values.Soc / r.Settings.Capacity)]++;
                    for (int i = 0; i < counts.Length; i++)
                        Emit($"{i * 10,3}% {Bar(20L * counts[i] / r.Records.Length)} {counts[i]}");
                    break;
                }
                case "CHART":
                    Emit($"CHART day {argument + 1} {data.DayName(argument)} strategy {r.Strategy.Notation}");
                    for (int hour = 0; hour < 24; hour++)
                    {
                        long soc = r.Records[argument * 24 + hour].Values.Soc, capacity = r.Settings.Capacity;
                        Emit($"{hour,2} {Bar(20 * soc / capacity)} {Percentage(soc, capacity)}%");
                    }
                    break;
            }
        }

        public bool Execute(string line)
        {
            string[] words = line.Split(' '), args = words[1..];
            string command = words[0];
            try
            {
                if (ReportArities.TryGetValue(command, out int count))
                {
                    Arity(args, count);
                    int argument = 0;
                    if (command is "HOURLY" or "CHART") argument = DayArgument(args[0]);
                    if (command == "PEAKS")
                    {
                        long value = Integer(args[0]);
                        if (value < 1) throw new CommandError("invalid count");
                        argument = (int)value;
                    }
                    Report(command, Current, argument);
                    return false;
                }
                switch (command)
                {
                    case "END": Arity(args, 0); return true;
                    case "RUN":
                    {
                        var strategy = OneStrategy(args);
                        var trial = Simulate(data, settings, prices, strategy);
                        current = trial;
                        Emit($"RUN {strategy.Notation} bill {Money(trial.Bill)} import {trial.Total.Imported} " +
                            $"export {trial.Total.Exported} soc {trial.EndSoc}");
                        break;
                    }
                    case "SET":
                    {
                        Arity(args, 2);
                        var item = Named<Item>(args[0], "unknown parameter");
                        long value = Integer(args[1]);
                        var bounds = Bounds(item);
                        if (value < bounds.Minimum || value > bounds.Maximum) throw new CommandError($"invalid value for {args[0]}");
                        long previous = settings[item];
                        settings = settings.With(item, value);
                        Emit($"SET {args[0]} {previous} -> {value}");
                        break;
                    }
                    case "PRICE":
                    {
                        Arity(args, 2);
                        int p = Array.IndexOf(data.Periods, args[0]);
                        if (p < 0) throw new CommandError($"unknown period {args[0]}");
                        long value = Integer(args[1]);
                        if (value < 0 || value > 10000) throw new CommandError($"invalid value for {args[0]}");
                        long previous = prices[p];
                        prices[p] = value;
                        var bounds = Extremes(prices);
                        Emit($"PRICE {args[0]} {previous} -> {value} cheapest {data.Periods[bounds.Low]} peak {data.Periods[bounds.High]}");
                        break;
                    }
                    case "RESET":
                        Arity(args, 0);
                        settings = initialSettings;
                        prices = initialPrices.ToArray();
                        Emit("RESET");
                        break;
                    case "CONFIG": Arity(args, 0); Config(); break;
                    case "NOBATTERY":
                    {
                        Arity(args, 0);
                        var baseline = Baseline(data, settings, prices);
                        Emit($"NOBATTERY bill {Money(baseline.Bill)} import {baseline.Total.Imported} " +
                            $"export {baseline.Total.Exported} curtailed {baseline.Total.Curtailed} peak {baseline.Peak}");
                        break;
                    }
                    case "COMPARE": Compare(args); break;
                    case "SIZE": Size(args); break;
                    case "SWEEP": Sweep(args); break;
                    case "OUTAGE": EvaluateOutage(args); break;
                    case "DIFF": Difference(args); break;
                    default: throw new CommandError($"unknown command {command}");
                }
            }
            catch (CommandError error) { Emit($"ERROR {error.Message}"); }
            return false;
        }
    }

    static Dispatch ReadInput()
    {
        static string[] Words() => Console.ReadLine()!.Split(' ');
        long[] battery = Words().Skip(1).Select(Integer).ToArray();
        long[] grid = Words().Skip(1).Select(Integer).ToArray();
        var settings = new Settings(battery[0], battery[1], battery[2], battery[3],
            battery[4], battery[5], battery[6], battery[7], grid[0], grid[1], grid[2], grid[3]);
        int periodCount = (int)Integer(Words()[1]);
        var names = new string[periodCount];
        var prices = new long[periodCount];
        for (int i = 0; i < periodCount; i++)
        {
            var line = Words();
            names[i] = line[0];
            prices[i] = Integer(line[1]);
        }
        var divisions = new int[2][];
        for (int type = 0; type < 2; type++)
        {
            var line = Words();
            divisions[type] = new int[24];
            for (int i = 1; i < line.Length; i += 2)
            {
                int start = (int)Integer(line[i]);
                int end = i + 2 < line.Length ? (int)Integer(line[i + 2]) : 24;
                int period = Array.IndexOf(names, line[i + 1]);
                Array.Fill(divisions[type], period, start, end - start);
            }
        }
        int profileCount = (int)Integer(Words()[1]);
        var profiles = new Dictionary<(string Kind, string Name), long[]>();
        for (int i = 0; i < profileCount; i++)
        {
            var line = Words();
            profiles[(line[0], line[1])] = line.Skip(2).Select(Integer).ToArray();
        }
        int days = (int)Integer(Words()[1]);
        var hours = new HourInput[days * 24];
        for (int day = 0; day < days; day++)
        {
            var line = Words();
            var load = profiles[("LOAD", line[0])];
            var pv = profiles[("PV", line[2])];
            long loadPercent = Integer(line[1]), pvPercent = Integer(line[3]);
            for (int hour = 0; hour < 24; hour++)
                hours[day * 24 + hour] = new HourInput(load[hour] * loadPercent / 100, pv[hour] * pvPercent / 100, 0);
        }
        var holidays = Words().Skip(2).Select(word => (int)Integer(word) - 1).ToHashSet();
        var data = new Data(names, hours, holidays);
        for (int i = 0; i < hours.Length; i++)
            hours[i] = hours[i] with { Period = divisions[data.Weekend(i / 24) ? 1 : 0][i % 24] };
        int overrides = (int)Integer(Words()[1]);
        for (int i = 0; i < overrides; i++)
        {
            var line = Words().Select(Integer).ToArray();
            int index = ((int)line[0] - 1) * 24 + (int)line[1];
            hours[index] = hours[index] with { Load = line[2], Pv = line[3] };
        }
        return new Dispatch(data, settings, prices);
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var dispatch = ReadInput();
        while (Console.ReadLine() is { } line)
            if (dispatch.Execute(line)) break;
        Console.Write(dispatch.Output.ToString());
    }
}
