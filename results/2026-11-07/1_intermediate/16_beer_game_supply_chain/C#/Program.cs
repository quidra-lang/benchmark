using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

sealed class CommandError : Exception
{
    public CommandError(string reason) : base(reason) { }
}

sealed class Policy
{
    static readonly Dictionary<string, int> ParameterCounts = new()
    {
        ["FIXED"] = 1, ["PASS"] = 0, ["BASESTOCK"] = 1,
        ["MINMAX"] = 2, ["MOVAVG"] = 2, ["SMOOTH"] = 2, ["STERMAN"] = 4
    };

    public string Name { get; }
    public long[] Values { get; }
    public string Notation { get; }

    public Policy(string name, long[] values, string notation)
    {
        Name = name;
        Values = values;
        Notation = notation;
    }

    public static Policy Parse(IReadOnlyList<string> tokens)
    {
        string name = tokens.Count > 0 ? tokens[0] : "";
        if (!ParameterCounts.TryGetValue(name, out int expected))
            throw new CommandError("unknown policy " + name);
        if (tokens.Count != expected + 1)
            throw new CommandError($"{name} needs {expected} parameters");

        var values = new long[expected];
        for (int i = 0; i < expected; ++i)
        {
            string text = tokens[i + 1];
            values[i] = long.Parse(name == "STERMAN" && i < 3
                ? text.Replace(".", "") : text, CultureInfo.InvariantCulture);
        }

        bool valid = name switch
        {
            "FIXED" => values[0] >= 0 && values[0] <= 1000,
            "PASS" => true,
            "BASESTOCK" => values[0] >= 0 && values[0] <= 10000,
            "MINMAX" => values[0] >= 0 && values[0] < values[1] && values[1] <= 10000,
            "MOVAVG" => values[0] >= 1 && values[0] <= 52 &&
                         values[1] >= 0 && values[1] <= 10000,
            "SMOOTH" => values[0] >= 1 && values[0] <= 10 &&
                         values[1] >= 0 && values[1] <= 10000,
            _ => values.Take(3).All(value => value >= 0 && value <= 100) &&
                 values[3] >= 0 && values[3] <= 10000
        };
        if (!valid) throw new CommandError("invalid parameter for " + name);
        return new Policy(name, values, string.Join(" ", tokens));
    }

    public static Policy BaseStock(int target) =>
        new("BASESTOCK", new long[] { target }, $"BASESTOCK {target}");
}

sealed class Initial
{
    public long Inventory { get; }
    public long Quantity { get; }
    public int ShippingDelay { get; }
    public int OrderDelay { get; }
    public long HoldingRate { get; }
    public long BacklogRate { get; }
    public Policy Policy { get; }

    public Initial(string[] tokens)
    {
        Inventory = long.Parse(tokens[1], CultureInfo.InvariantCulture);
        Quantity = long.Parse(tokens[2], CultureInfo.InvariantCulture);
        ShippingDelay = int.Parse(tokens[3], CultureInfo.InvariantCulture);
        OrderDelay = int.Parse(tokens[4], CultureInfo.InvariantCulture);
        HoldingRate = long.Parse(tokens[5], CultureInfo.InvariantCulture);
        BacklogRate = long.Parse(tokens[6], CultureInfo.InvariantCulture);
        Policy = Policy.Parse(tokens.Skip(7).ToArray());
    }
}

sealed class WeekRecord
{
    public long Received, Incoming, Shipped, Before, Ontime;
    public long Inventory, Backlog, Order, Holding, BacklogCost, Cost;

    public WeekRecord Copy() => (WeekRecord)MemberwiseClone();
}

readonly record struct PlantRecord(long Incoming, long Produced, long Backlog);

sealed class Stage
{
    public long Inventory, Backlog, Expected, HoldingRate, BacklogRate;
    public int Lot;
    public long? Capacity;
    public Policy Policy;
    public List<long> Shipping;
    public List<long> Orders;
    public List<WeekRecord> Records;

    public Stage(Initial initial)
    {
        Inventory = initial.Inventory;
        Backlog = 0;
        Expected = 100 * initial.Quantity;
        HoldingRate = initial.HoldingRate;
        BacklogRate = initial.BacklogRate;
        Lot = 1;
        Capacity = null;
        Policy = initial.Policy;
        Shipping = Enumerable.Repeat(initial.Quantity, initial.ShippingDelay).ToList();
        Orders = Enumerable.Repeat(initial.Quantity, initial.OrderDelay).ToList();
        Records = new List<WeekRecord>();
    }

    public Stage Copy() => new(this);

    Stage(Stage other)
    {
        Inventory = other.Inventory;
        Backlog = other.Backlog;
        Expected = other.Expected;
        HoldingRate = other.HoldingRate;
        BacklogRate = other.BacklogRate;
        Lot = other.Lot;
        Capacity = other.Capacity;
        Policy = other.Policy;
        Shipping = new List<long>(other.Shipping);
        Orders = new List<long>(other.Orders);
        Records = other.Records.Select(record => record.Copy()).ToList();
    }
}

sealed class Simulation
{
    public List<Initial> Initials { get; }
    public List<long> Demands;
    public Stage[] Stages;
    public int Week;
    public long PlantBacklog;
    public long? PlantCapacity;
    public List<PlantRecord> PlantRecords;
    public string Visibility;

    public Simulation(List<Initial> initials, IEnumerable<long> demands)
    {
        Initials = initials;
        Demands = demands.ToList();
        Stages = initials.Select(initial => new Stage(initial)).ToArray();
        Week = 0;
        PlantBacklog = 0;
        PlantCapacity = null;
        PlantRecords = new List<PlantRecord>();
        Visibility = "OFF";
    }

    public Simulation Copy()
    {
        var copy = new Simulation(Initials, Demands)
        {
            Stages = Stages.Select(stage => stage.Copy()).ToArray(),
            Week = Week,
            PlantBacklog = PlantBacklog,
            PlantCapacity = PlantCapacity,
            PlantRecords = new List<PlantRecord>(PlantRecords),
            Visibility = Visibility
        };
        return copy;
    }

    public long Signal(int index, int week, long[]? current = null)
    {
        if (Visibility == "ON") return Demands[week - 1];
        if (current != null && week == Week + 1) return current[index];
        return Stages[index].Records[week - 1].Incoming;
    }

    public void SetPolicy(int index, Policy policy)
    {
        Stage stage = Stages[index];
        stage.Policy = policy;
        if (policy.Name == "STERMAN")
        {
            long signal = Week > 0
                ? Signal(index, Week)
                : Initials[index].Quantity;
            stage.Expected = 100 * signal;
        }
    }

    public (long[] Supply, long[] Position) Positions()
    {
        var supply = new long[4];
        var position = new long[4];
        for (int i = 0; i < 4; ++i)
        {
            Stage stage = Stages[i];
            long upstreamBacklog = i < 3 ? Stages[i + 1].Backlog : PlantBacklog;
            long line = stage.Orders.Sum() + upstreamBacklog + stage.Shipping.Sum();
            supply[i] = line;
            position[i] = stage.Inventory + line - stage.Backlog;
        }
        return (supply, position);
    }

    static long FloorDiv(long numerator, long denominator)
    {
        long quotient = numerator / denominator;
        return numerator % denominator < 0 ? quotient - 1 : quotient;
    }

    long PolicyOrder(int index, long[] incoming, long line, long position)
    {
        Stage stage = Stages[index];
        string name = stage.Policy.Name;
        long[] args = stage.Policy.Values;
        int week = Week + 1;
        long signal = Signal(index, week, incoming);

        switch (name)
        {
            case "FIXED":
                return args[0];
            case "PASS":
                return incoming[index];
            case "BASESTOCK":
                return Math.Max(0, args[0] - position);
            case "MINMAX":
                return position <= args[0] ? args[1] - position : 0;
            case "MOVAVG":
            {
                int count = (int)Math.Min(args[0], week);
                long signals = 0;
                for (int u = week - count + 1; u <= week; ++u)
                    signals += Signal(index, u, incoming);
                long forecast = signals / count;
                Initial initial = Initials[index];
                int delay = initial.ShippingDelay + initial.OrderDelay;
                return Math.Max(0, args[1] + forecast * delay - position);
            }
            case "SMOOTH":
                return Math.Max(0, signal + FloorDiv(args[1] - position, args[0]));
            default:
            {
                long theta = args[0];
                long alpha = args[1];
                long beta = args[2];
                long target = args[3];
                stage.Expected = FloorDiv(
                    100 * theta * signal + (100 - theta) * stage.Expected, 100);
                long net = stage.Inventory - stage.Backlog;
                return Math.Max(0, FloorDiv(
                    100 * stage.Expected + alpha * (100 * (target - net) - beta * line),
                    10000));
            }
        }
    }

    public WeekRecord[] Step()
    {
        var received = new long[4];
        var incoming = new long[4];
        for (int i = 0; i < 4; ++i)
        {
            Stage stage = Stages[i];
            received[i] = stage.Shipping[0];
            stage.Shipping.RemoveAt(0);
            stage.Inventory += received[i];
        }

        incoming[0] = Demands[Week];
        for (int i = 1; i < 4; ++i)
        {
            incoming[i] = Stages[i - 1].Orders[0];
            Stages[i - 1].Orders.RemoveAt(0);
        }
        long plantIncoming = Stages[3].Orders[0];
        Stages[3].Orders.RemoveAt(0);

        var records = new WeekRecord[4];
        for (int i = 0; i < 4; ++i)
        {
            Stage stage = Stages[i];
            long before = stage.Backlog;
            long requested = before + incoming[i];
            long shipped = Math.Min(stage.Inventory, requested);
            if (stage.Capacity.HasValue)
                shipped = Math.Min(shipped, stage.Capacity.Value);
            stage.Inventory -= shipped;
            stage.Backlog = requested - shipped;
            if (i > 0) Stages[i - 1].Shipping.Add(shipped);
            records[i] = new WeekRecord
            {
                Received = received[i],
                Incoming = incoming[i],
                Shipped = shipped,
                Before = before,
                Ontime = Math.Min(Math.Max(0, shipped - before), incoming[i]),
                Inventory = stage.Inventory,
                Backlog = stage.Backlog
            };
        }

        long requestedPlant = PlantBacklog + plantIncoming;
        long produced = PlantCapacity.HasValue
            ? Math.Min(requestedPlant, PlantCapacity.Value)
            : requestedPlant;
        PlantBacklog = requestedPlant - produced;
        Stages[3].Shipping.Add(produced);

        var (supply, positions) = Positions();
        var orders = new long[4];
        for (int i = 0; i < 4; ++i)
            orders[i] = PolicyOrder(i, incoming, supply[i], positions[i]);

        for (int i = 0; i < 4; ++i)
        {
            Stage stage = Stages[i];
            long lot = stage.Lot;
            WeekRecord record = records[i];
            record.Order = ((orders[i] + lot - 1) / lot) * lot;
            stage.Orders.Add(record.Order);
            record.Holding = stage.HoldingRate * stage.Inventory;
            record.BacklogCost = stage.BacklogRate * stage.Backlog;
            record.Cost = record.Holding + record.BacklogCost;
            stage.Records.Add(record);
        }
        PlantRecords.Add(new PlantRecord(plantIncoming, produced, PlantBacklog));
        ++Week;
        return records;
    }

    public long[] TotalCosts()
    {
        var result = new long[4];
        for (int i = 0; i < 4; ++i)
            result[i] = Stages[i].Records.Sum(record => record.Cost);
        return result;
    }
}

sealed class Game
{
    static readonly string[] Names = { "RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY" };

    readonly List<Initial> initials;
    readonly Dictionary<string, Simulation> snapshots = new();
    readonly List<string> output = new();
    List<long> baseDemands = new();
    Simulation simulation;

    public Game(List<Initial> initials)
    {
        this.initials = initials;
        simulation = new Simulation(initials, baseDemands);
    }

    static long Num(string text) => long.Parse(text, CultureInfo.InvariantCulture);
    static int Whole(string text) => int.Parse(text, CultureInfo.InvariantCulture);

    static string Money(long cents) =>
        $"{cents / 100}.{(cents % 100).ToString("D2", CultureInfo.InvariantCulture)}";

    static string Decimal(long numerator, long denominator, int places)
    {
        long scale = 1;
        for (int i = 0; i < places; ++i) scale *= 10;
        long scaled = numerator * scale / denominator;
        return (scaled / scale) + "." +
            (scaled % scale).ToString("D" + places, CultureInfo.InvariantCulture);
    }

    static long Variation(IEnumerable<long> source)
    {
        long[] values = source.ToArray();
        long total = values.Sum();
        long squares = values.Sum(value => value * value);
        return values.Length * squares - total * total;
    }

    void Emit(params object[] parts) =>
        output.Add(string.Join(" ", parts.Select(part => part.ToString())));

    int StageIndex(string name)
    {
        int index = Array.IndexOf(Names, name);
        if (index < 0) throw new CommandError("unknown stage " + name);
        return index;
    }

    List<int> Target(string name) =>
        name == "ALL" ? new List<int> { 0, 1, 2, 3 } : new List<int> { StageIndex(name) };

    void RequireWeeks()
    {
        if (simulation.Week == 0) throw new CommandError("no weeks simulated");
    }

    static (int First, int Last) Range(IReadOnlyList<string> args, int limit)
    {
        if (args.Count == 0) return (1, limit);
        int first = Whole(args[0]), last = Whole(args[1]);
        if (first < 1 || first > last || last > limit)
            throw new CommandError($"bad range {args[0]} {args[1]}");
        return (first, last);
    }

    static void CheckMode(string mode)
    {
        if (mode is not ("ORDERS" or "INV" or "BACK" or "NET"))
            throw new CommandError("unknown mode " + mode);
    }

    List<long> Values(int index, string mode)
    {
        return simulation.Stages[index].Records.Select(record => mode switch
        {
            "ORDERS" => record.Order,
            "INV" => record.Inventory,
            "BACK" => record.Backlog,
            _ => record.Inventory - record.Backlog
        }).ToList();
    }

    void Initialize(List<long>? demands = null)
    {
        if (demands != null) baseDemands = new List<long>(demands);
        simulation = new Simulation(initials, baseDemands);
    }

    Simulation Trial(IReadOnlyList<Policy> policies)
    {
        Simulation current = simulation;
        var trial = new Simulation(initials, current.Demands)
        {
            Visibility = current.Visibility,
            PlantCapacity = current.PlantCapacity
        };
        for (int i = 0; i < 4; ++i)
        {
            Stage stage = trial.Stages[i];
            Stage previous = current.Stages[i];
            stage.Lot = previous.Lot;
            stage.Capacity = previous.Capacity;
            stage.HoldingRate = previous.HoldingRate;
            stage.BacklogRate = previous.BacklogRate;
            trial.SetPolicy(i, policies[i]);
        }
        while (trial.Week < trial.Demands.Count) trial.Step();
        return trial;
    }

    void Demand(List<long> demands)
    {
        Initialize(demands);
        Emit("DEMAND", "weeks", demands.Count, "total", demands.Sum(),
             "min", demands.Min(), "max", demands.Max());
    }

    void Generate(IReadOnlyList<string> args)
    {
        int weeks = Whole(args[0]);
        long baseLevel = Num(args[1]), spread = Num(args[2]);
        long seed = Num(args[3]);
        for (int i = 4; i < args.Count; i += 3)
        {
            int week = Whole(args[i + 1]);
            if (week < 1 || week > weeks)
                throw new CommandError($"week {args[i + 1]} outside horizon");
        }

        var levels = new List<long>();
        for (int week = 1; week <= weeks; ++week)
        {
            long level = baseLevel;
            for (int i = 4; i < args.Count; i += 3)
            {
                string kind = args[i];
                int first = Whole(args[i + 1]);
                long amount = Num(args[i + 2]);
                if (kind == "STEP" && week >= first) level += amount;
                else if (kind == "PULSE" && week == first) level += amount;
                else if (kind == "RAMP" && week >= first)
                    level += amount * (week - first + 1);
            }
            if (level < 0)
                throw new CommandError($"negative level at week {week}");
            levels.Add(level);
        }

        var demands = new List<long>();
        foreach (long level in levels)
        {
            seed = 48271 * seed % 2147483647L;
            demands.Add(level + seed % spread);
        }
        Demand(demands);
    }

    void Status()
    {
        Simulation s = simulation;
        Emit("STATUS", "week", s.Week, "of", s.Demands.Count);
        var (supply, positions) = s.Positions();
        for (int i = 0; i < 4; ++i)
        {
            Stage stage = s.Stages[i];
            string text = Names[i] + " inv " + stage.Inventory + " back " + stage.Backlog +
                " transit " + string.Join(",", stage.Shipping) +
                " pending " + string.Join(",", stage.Orders) +
                " supply " + supply[i] + " position " + positions[i] +
                " policy " + stage.Policy.Notation;
            if (stage.Policy.Name == "STERMAN")
                text += " expect " + Money(stage.Expected);
            Emit(text);
        }
        Emit("PLANT", "back", s.PlantBacklog);
    }

    void ShowWeek(int week)
    {
        Simulation s = simulation;
        Emit("WEEK", week, "demand", s.Demands[week - 1]);
        for (int i = 0; i < 4; ++i)
        {
            WeekRecord record = s.Stages[i].Records[week - 1];
            Emit(Names[i], "recv", record.Received, "in", record.Incoming,
                 "ship", record.Shipped, "inv", record.Inventory,
                 "back", record.Backlog, "order", record.Order, "cost", Money(record.Cost));
        }
        PlantRecord plant = s.PlantRecords[week - 1];
        Emit("PLANT", "in", plant.Incoming, "made", plant.Produced, "back", plant.Backlog);
    }

    static string Aligned(object[] values, int[] widths) =>
        string.Join(" ", values.Select((value, i) =>
            value.ToString()!.PadLeft(widths[i])));

    void Table(int index, int first, int last)
    {
        Emit("TABLE", Names[index], $"{first}-{last}");
        int[] widths = { 4, 6, 6, 6, 6, 6, 6, 9 };
        Emit(Aligned(new object[] { "week", "in", "ship", "recv", "inv", "back",
                                    "order", "cost" }, widths));
        for (int week = first; week <= last; ++week)
        {
            WeekRecord r = simulation.Stages[index].Records[week - 1];
            Emit(Aligned(new object[] { week, r.Incoming, r.Shipped, r.Received,
                                        r.Inventory, r.Backlog, r.Order, Money(r.Cost) },
                         widths));
        }
    }

    void Costs()
    {
        Emit("COSTS", "week", simulation.Week);
        long totalHolding = 0, totalBacklog = 0;
        for (int i = 0; i < 4; ++i)
        {
            long holding = simulation.Stages[i].Records.Sum(r => r.Holding);
            long backlog = simulation.Stages[i].Records.Sum(r => r.BacklogCost);
            totalHolding += holding;
            totalBacklog += backlog;
            Emit(Names[i], "holding", Money(holding), "backlog", Money(backlog),
                 "total", Money(holding + backlog));
        }
        Emit("TOTAL", "holding", Money(totalHolding),
             "backlog", Money(totalBacklog),
             "total", Money(totalHolding + totalBacklog));
    }

    static (long Ordered, long Ontime, string Fill) FillText(List<WeekRecord> records)
    {
        long ordered = records.Sum(r => r.Incoming);
        long ontime = records.Sum(r => r.Ontime);
        string fill = ordered == 0 ? "n/a" : Decimal(ontime * 100, ordered, 2) + "%";
        return (ordered, ontime, fill);
    }

    void Bullwhip()
    {
        Simulation s = simulation;
        int n = s.Week;
        var demands = s.Demands.Take(n).ToList();
        long demandVariation = Variation(demands);
        Emit("BULLWHIP", "weeks", $"1-{n}", "demand", "mean",
             Decimal(demands.Sum(), n, 4), "var",
             Decimal(demandVariation, (long)n * n, 4));
        long previous = demandVariation;
        for (int i = 0; i < 4; ++i)
        {
            var orders = s.Stages[i].Records.Select(record => record.Order).ToList();
            long variation = Variation(orders);
            Emit(Names[i], "mean", Decimal(orders.Sum(), n, 4),
                 "var", Decimal(variation, (long)n * n, 4),
                 "ratio", demandVariation == 0 ? "n/a" : Decimal(variation, demandVariation, 4),
                 "step", previous == 0 ? "n/a" : Decimal(variation, previous, 4));
            previous = variation;
        }
    }

    void Peaks()
    {
        Simulation s = simulation;
        Emit("PEAKS", "weeks", $"1-{s.Week}");
        for (int index = 0; index < 4; ++index)
        {
            var records = s.Stages[index].Records;
            long maxInv = 0, maxBack = 0;
            int invWeek = 0, backWeek = 0;
            int longest = 0, run = 0, start = 0, bestStart = 0, bestEnd = 0;
            for (int i = 0; i < records.Count; ++i)
            {
                WeekRecord r = records[i];
                int week = i + 1;
                if (r.Inventory > maxInv) { maxInv = r.Inventory; invWeek = week; }
                if (r.Backlog > maxBack) { maxBack = r.Backlog; backWeek = week; }
                if (r.Backlog > 0)
                {
                    if (run == 0) start = week;
                    ++run;
                    if (run > longest)
                    {
                        longest = run;
                        bestStart = start;
                        bestEnd = week;
                    }
                }
                else run = 0;
            }
            string stockout = longest == 0 ? "0" :
                $"{longest} weeks {bestStart}-{bestEnd}";
            Emit(Names[index], "max_inv", maxInv, "week", invWeek == 0 ? "-" : invWeek,
                 "max_back", maxBack, "week", backWeek == 0 ? "-" : backWeek,
                 "longest_stockout", stockout);
        }
    }

    void Leadtime(int index)
    {
        Stage stage = simulation.Stages[index];
        Initial initial = initials[index];
        int nominal = initial.ShippingDelay + initial.OrderDelay;
        var arrivals = new long[stage.Records.Count];
        long received = -nominal * initial.Quantity;
        for (int i = 0; i < arrivals.Length; ++i)
        {
            received += stage.Records[i].Received;
            arrivals[i] = received;
        }
        long ordered = 0;
        int count = 0;
        var leads = new List<int>();
        for (int t = 0; t < stage.Records.Count; ++t)
        {
            long amount = stage.Records[t].Order;
            ordered += amount;
            if (amount == 0) continue;
            ++count;
            for (int u = t + 1; u < stage.Records.Count; ++u)
            {
                if (arrivals[u] >= ordered)
                {
                    leads.Add(u - t);
                    break;
                }
            }
        }
        Emit("LEADTIME", Names[index], "nominal", nominal, "orders", count,
             "completed", leads.Count, "open", count - leads.Count,
             "min", leads.Count > 0 ? leads.Min() : "-",
             "avg", leads.Count > 0 ? Decimal(leads.Sum(), leads.Count, 2) : "-",
             "max", leads.Count > 0 ? leads.Max() : "-");
    }

    void Plot(int index, string kind, int first, int last)
    {
        List<long> values = Values(index, kind).Skip(first - 1).Take(last - first + 1).ToList();
        long maximum = values.Max();
        if (kind == "NET")
        {
            long minimum = values.Min();
            long scale = values.Max(value => Math.Abs(value));
            Emit("PLOT", Names[index], "NET", $"{first}-{last}",
                 "min", minimum, "max", maximum);
            for (int i = 0; i < values.Count; ++i)
            {
                long value = values[i];
                int length = scale == 0 ? 0 : (int)(Math.Abs(value) * 25 / scale);
                string left = value < 0
                    ? new string(' ', 25 - length) + new string('-', length)
                    : new string(' ', 25);
                string right = value > 0 ? new string('+', length) : "";
                Emit($"{(i + first).ToString().PadLeft(3)} {left}|{right} {value}");
            }
        }
        else
        {
            Emit("PLOT", Names[index], kind, $"{first}-{last}", "max", maximum);
            for (int i = 0; i < values.Count; ++i)
            {
                long value = values[i];
                int length = maximum == 0 ? 0 : (int)(value * 50 / maximum);
                Emit($"{(i + first).ToString().PadLeft(3)} |{new string('#', length)} {value}");
            }
        }
    }

    void Histogram(int index, string kind, int width)
    {
        var counts = new SortedDictionary<long, int>();
        foreach (long value in Values(index, kind))
        {
            long bucket = Math.DivRem(value, width, out long remainder);
            if (remainder < 0) --bucket;
            counts[bucket] = counts.GetValueOrDefault(bucket, 0) + 1;
        }
        Emit("HISTOGRAM", Names[index], kind, "width", width,
             "weeks", $"1-{simulation.Week}");
        for (long bucket = counts.Keys.First(); bucket <= counts.Keys.Last(); ++bucket)
        {
            int count = counts.GetValueOrDefault(bucket, 0);
            string line = $"{bucket * width}..{bucket * width + width - 1} {count}";
            if (count > 0) line += " " + new string('*', count);
            Emit(line);
        }
    }

    void Compare(IReadOnlyList<string> tokens)
    {
        var policies = new List<Policy>();
        int start = 0;
        for (int end = 0; end <= tokens.Count; ++end)
        {
            if (end == tokens.Count || tokens[end] == "/")
            {
                policies.Add(Policy.Parse(tokens.Skip(start).Take(end - start).ToArray()));
                start = end + 1;
            }
        }

        var results = new List<(long Cost, int Original, string Label, string Fill, string Ratio)>();
        for (int i = 0; i < policies.Count; ++i)
        {
            Policy policy = policies[i];
            Simulation trial = Trial(new[] { policy, policy, policy, policy });
            long cost = trial.TotalCosts().Sum();
            string fill = FillText(trial.Stages[0].Records).Fill;
            long demandVariation = Variation(trial.Demands);
            long factoryVariation = Variation(trial.Stages[3].Records.Select(r => r.Order));
            string ratio = demandVariation == 0
                ? "n/a" : Decimal(factoryVariation, demandVariation, 4);
            results.Add((cost, i, policy.Notation, fill, ratio));
        }

        Emit("COMPARE", policies.Count, "weeks", simulation.Demands.Count);
        int rank = 0;
        foreach (var row in results.OrderBy(r => r.Cost).ThenBy(r => r.Original))
            Emit(++rank, row.Label, "total", Money(row.Cost),
                 "fill", row.Fill, "bullwhip", row.Ratio);
    }

    void Optimize(IReadOnlyList<string> args)
    {
        List<int> indices = Target(args[0]);
        int low = Whole(args[1]), high = Whole(args[2]);
        if (low > high) throw new CommandError($"bad range {args[1]} {args[2]}");
        if (high - low > 200) throw new CommandError("range too large");

        long bestCost = long.MaxValue, bestTotal = 0;
        int bestStock = low;
        for (int stock = low; stock <= high; ++stock)
        {
            Policy[] policies = simulation.Stages.Select(stage => stage.Policy).ToArray();
            foreach (int index in indices) policies[index] = Policy.BaseStock(stock);
            Simulation trial = Trial(policies);
            long[] costs = trial.TotalCosts();
            long objective = indices.Sum(index => costs[index]);
            if (objective < bestCost)
            {
                bestCost = objective;
                bestTotal = costs.Sum();
                bestStock = stock;
            }
        }
        Emit("OPTIMIZE", args[0], "BASESTOCK", bestStock,
             "cost", Money(bestCost), "total", Money(bestTotal));
    }

    void Command(string command, IReadOnlyList<string> a)
    {
        Simulation s = simulation;
        switch (command)
        {
            case "DEMAND":
                Demand(a.Select(Num).ToList());
                break;
            case "GENERATE":
                Generate(a);
                break;
            case "RUN":
            {
                if (s.Week == s.Demands.Count)
                    throw new CommandError($"horizon reached at week {s.Demands.Count}");
                int first = s.Week + 1;
                int count = Math.Min(Whole(a[0]), s.Demands.Count - s.Week);
                long cost = 0;
                for (int step = 0; step < count; ++step)
                {
                    WeekRecord[] records = s.Step();
                    for (int i = 0; i < 4; ++i)
                    {
                        WeekRecord record = records[i];
                        cost += record.Cost;
                        if (record.Before == 0 && record.Backlog > 0)
                            Emit("STOCKOUT", Names[i], "week", s.Week,
                                 "backlog", record.Backlog);
                        else if (record.Before > 0 && record.Backlog == 0)
                            Emit("RECOVER", Names[i], "week", s.Week);
                    }
                }
                Emit("RUN", $"{first}-{s.Week}", "demand",
                     s.Demands.Skip(first - 1).Take(s.Week - first + 1).Sum(),
                     "cost", Money(cost));
                if (s.Week == s.Demands.Count) Emit("HORIZON", s.Week);
                break;
            }
            case "RESET":
                Initialize();
                Emit("RESET", "week", 0);
                break;
            case "SAVE":
                snapshots[a[0]] = s.Copy();
                Emit("SAVE", a[0], "week", s.Week);
                break;
            case "LOAD":
            {
                if (!snapshots.TryGetValue(a[0], out Simulation? saved))
                    throw new CommandError("no snapshot " + a[0]);
                simulation = saved.Copy();
                Emit("LOAD", a[0], "week", simulation.Week);
                break;
            }
            case "SET":
            {
                List<int> targets = Target(a[0]);
                Policy policy = Policy.Parse(a.Skip(1).ToArray());
                foreach (int index in targets) s.SetPolicy(index, policy);
                Emit("SET", a[0], policy.Notation);
                break;
            }
            case "BATCH":
            {
                int index = StageIndex(a[0]);
                int lot = Whole(a[1]);
                if (lot < 1 || lot > 100)
                    throw new CommandError("invalid batch size " + a[1]);
                s.Stages[index].Lot = lot;
                Emit("BATCH", a[0], lot);
                break;
            }
            case "CAPACITY":
            {
                int index = a[0] == "PLANT" ? -1 : StageIndex(a[0]);
                long? capacity = a[1] == "OFF" ? null : Num(a[1]);
                if (capacity > 10000)
                    throw new CommandError("invalid capacity " + a[1]);
                if (index < 0) s.PlantCapacity = capacity;
                else s.Stages[index].Capacity = capacity;
                Emit("CAPACITY", a[0], a[1]);
                break;
            }
            case "COST":
            {
                int index = StageIndex(a[0]);
                long holding = Num(a[1]), backlog = Num(a[2]);
                if (holding > 1000 || backlog > 1000)
                    throw new CommandError("invalid cost");
                s.Stages[index].HoldingRate = holding;
                s.Stages[index].BacklogRate = backlog;
                Emit("COST", a[0], "holding", holding, "backlog", backlog);
                break;
            }
            case "VISIBILITY":
                if (a[0] is not ("ON" or "OFF"))
                    throw new CommandError("unknown visibility " + a[0]);
                s.Visibility = a[0];
                Emit("VISIBILITY", a[0]);
                break;
            case "SHOCK":
            {
                int week = Whole(a[0]);
                long demand = Num(a[1]);
                if (week < 1 || week > s.Demands.Count)
                    throw new CommandError($"week {a[0]} outside horizon");
                if (week <= s.Week)
                    throw new CommandError($"week {a[0]} already simulated");
                long previous = s.Demands[week - 1];
                s.Demands[week - 1] = demand;
                Emit("SHOCK", "week", week, previous, "->", demand);
                break;
            }
            case "STATUS":
                Status();
                break;
            case "SETTINGS":
                Emit("SETTINGS");
                for (int i = 0; i < 4; ++i)
                {
                    Stage stage = s.Stages[i];
                    Initial initial = initials[i];
                    Emit(Names[i], "holding", stage.HoldingRate, "backlog", stage.BacklogRate,
                         "batch", stage.Lot, "capacity", stage.Capacity?.ToString() ?? "OFF",
                         "delays", initial.ShippingDelay, initial.OrderDelay);
                }
                Emit("PLANT", "capacity", s.PlantCapacity?.ToString() ?? "OFF");
                Emit("VISIBILITY", s.Visibility);
                break;
            case "WEEK":
            {
                RequireWeeks();
                int week = Whole(a[0]);
                if (week < 1 || week > s.Week)
                    throw new CommandError("bad week " + a[0]);
                ShowWeek(week);
                break;
            }
            case "TABLE":
            {
                int index = StageIndex(a[0]);
                RequireWeeks();
                var (first, last) = Range(a.Skip(1).ToArray(), s.Week);
                Table(index, first, last);
                break;
            }
            case "CHAIN":
            {
                RequireWeeks();
                var (first, last) = Range(a, s.Week);
                Emit("CHAIN", $"{first}-{last}");
                Emit("week".PadLeft(4) + " " + "demand".PadLeft(6) + " " +
                     string.Join(" ", Names.Select(name => name.PadLeft(11))));
                for (int week = first; week <= last; ++week)
                {
                    string row = week.ToString().PadLeft(4) + " " +
                                 s.Demands[week - 1].ToString().PadLeft(6) + " " +
                                 string.Join(" ", s.Stages.Select(stage =>
                                     stage.Records[week - 1].Order.ToString().PadLeft(11)));
                    Emit(row);
                }
                break;
            }
            case "DEMANDS":
            {
                var (first, last) = Range(a, s.Demands.Count);
                List<long> values = s.Demands.Skip(first - 1).Take(last - first + 1).ToList();
                Emit("DEMANDS", $"{first}-{last}", "total", values.Sum(),
                     "min", values.Min(), "max", values.Max());
                Emit(string.Join(" ", values));
                break;
            }
            case "COSTS":
                Costs();
                break;
            case "SUMMARY":
                RequireWeeks();
                Emit("SUMMARY", "weeks", $"1-{s.Week}");
                for (int i = 0; i < 4; ++i)
                {
                    List<WeekRecord> records = s.Stages[i].Records;
                    long[] orders = records.Select(r => r.Order).ToArray();
                    Emit(Names[i], "avg_inv", Decimal(records.Sum(r => r.Inventory), s.Week, 2),
                         "avg_back", Decimal(records.Sum(r => r.Backlog), s.Week, 2),
                         "orders", orders.Sum(), "min", orders.Min(), "max", orders.Max(),
                         "zero_weeks", orders.Count(value => value == 0));
                }
                break;
            case "BALANCE":
            {
                Emit("BALANCE", "week", s.Week);
                for (int i = 0; i < 4; ++i)
                {
                    Stage stage = s.Stages[i];
                    Emit(Names[i], "start", initials[i].Inventory,
                         "received", stage.Records.Sum(r => r.Received),
                         "shipped", stage.Records.Sum(r => r.Shipped),
                         "end", stage.Inventory, "owed", stage.Backlog);
                }
                long initialGoods = initials.Sum(i => i.Inventory + i.Quantity * i.ShippingDelay);
                Emit("SYSTEM", "initial", initialGoods,
                     "produced", s.PlantRecords.Sum(r => r.Produced),
                     "delivered", s.Stages[0].Records.Sum(r => r.Shipped),
                     "stock", s.Stages.Sum(stage => stage.Inventory),
                     "transit", s.Stages.Sum(stage => stage.Shipping.Sum()));
                break;
            }
            case "FILLRATE":
                RequireWeeks();
                Emit("FILLRATE", "weeks", $"1-{s.Week}");
                for (int i = 0; i < 4; ++i)
                {
                    List<WeekRecord> records = s.Stages[i].Records;
                    var (ordered, ontime, fill) = FillText(records);
                    int stockouts = records.Count(record => record.Backlog > 0);
                    Emit(Names[i], "fill", fill, "ontime", ontime, "ordered", ordered,
                         "stockout_weeks", stockouts, "service",
                         Decimal((s.Week - stockouts) * 100, s.Week, 2) + "%");
                }
                break;
            case "BULLWHIP":
                RequireWeeks();
                Bullwhip();
                break;
            case "PEAKS":
                RequireWeeks();
                Peaks();
                break;
            case "LEADTIME":
            {
                int index = StageIndex(a[0]);
                RequireWeeks();
                Leadtime(index);
                break;
            }
            case "PLOT":
            case "HISTOGRAM":
            {
                int index = StageIndex(a[0]);
                CheckMode(a[1]);
                if (command == "HISTOGRAM")
                {
                    int width = Whole(a[2]);
                    if (width < 1 || width > 100)
                        throw new CommandError("invalid width " + a[2]);
                }
                RequireWeeks();
                if (command == "PLOT")
                {
                    var (first, last) = Range(a.Skip(2).ToArray(), s.Week);
                    Plot(index, a[1], first, last);
                }
                else Histogram(index, a[1], Whole(a[2]));
                break;
            }
            case "COMPARE":
                Compare(a);
                break;
            case "OPTIMIZE":
                Optimize(a);
                break;
            default:
                throw new CommandError("unknown command " + command);
        }
    }

    public void Execute(string line)
    {
        string[] fields = line.Split(' ');
        string command = fields[0];
        try
        {
            Command(command, fields.Skip(1).ToArray());
        }
        catch (CommandError error)
        {
            Emit("ERROR", error.Message);
        }
    }

    public void Print()
    {
        if (output.Count > 0)
            Console.WriteLine(string.Join("\n", output));
    }
}

static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var initials = new List<Initial>();
        for (int i = 0; i < 4; ++i)
            initials.Add(new Initial(Console.ReadLine()!.Split(' ')));
        var game = new Game(initials);
        string? line;
        while ((line = Console.ReadLine()) != null && line != "END")
            game.Execute(line);
        game.Print();
    }
}
