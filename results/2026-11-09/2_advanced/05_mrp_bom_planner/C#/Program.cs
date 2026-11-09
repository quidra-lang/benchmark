using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

readonly record struct Row(int Line, string[] Fields);
static class Io
{
    public static string[] Lines(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII);
    public static IEnumerable<Row> Rows(string name) => Lines(name).Skip(1).Select((line, index) => new Row(index + 2, line.Split(',')));
    public static void Error(List<string> errors, string file, int line, string message) => errors.Add($"{file} line {line}: {message}");
}
sealed record ScheduleRow(string Item, int Week, long Quantity, int Line);
sealed record Inquiry(string Id, string Item, long Quantity, int Week, int Line);
enum DemandKind { Mps, Order, Dependent, Safety }
sealed record Demand(string Item, DemandKind Kind, int Week, long Quantity, string OrderId = "", int Line = 0, string Parent = "", int ParentNumber = 0)
{
    public int RootRank => Kind == DemandKind.Mps ? 0 : Kind == DemandKind.Order ? 1 : 2;
    public (string, int, int, string) RootKey => (Item, RootRank, Week, OrderId);
    public string Text => Kind switch
    {
        DemandKind.Safety => "SAFETY " + Item,
        DemandKind.Mps => $"MPS {Item} week {Week}",
        DemandKind.Order => $"ORDER {OrderId} {Item} week {Week}",
        _ => $"{Parent} order {ParentNumber} week {Week}"
    };
}
sealed record PlannedOrder(string Item, int Number, int Receipt, long Quantity, int Lead)
{
    public int Original => Receipt - Lead;
    public int Release => Math.Max(1, Original);
}
enum SupplyKind { Stock, Receipt, Order }
sealed record Allocation(Demand Demand, long Share);
sealed class Supply(SupplyKind kind, int week, long quantity, int line = 0, PlannedOrder? order = null)
{
    public readonly SupplyKind Kind = kind;
    public readonly int Week = week, Line = line;
    public readonly long Quantity = quantity;
    public readonly PlannedOrder? Order = order;
    public long Remaining = quantity;
    public List<Allocation> Allocations = [];
    public List<Demand> Roots = [];
    public string Header => Kind switch
    {
        SupplyKind.Stock => "STOCK quantity " + Quantity,
        SupplyKind.Receipt => $"RECEIPT line {Line} week {Week} quantity {Quantity}",
        _ => $"ORDER {Order!.Number} receipt {Order.Receipt} release {Order.Release} quantity {Order.Quantity}"
    };
    public bool Serves(string id) => Roots.Any(root => root.Kind == DemandKind.Order && root.OrderId == id);
}
sealed class ItemPlan
{
    public readonly Item Item;
    public readonly long[] Receipts, Gross, OnHand, Net, PlannedReceipts, PlannedReleases;
    public List<Demand> Demands = [];
    public List<PlannedOrder> Orders = [];
    public List<Supply> Supplies = [], OrderSupplies = [];
    public ItemPlan(Item item, int horizon, long[] scheduled)
    {
        Item = item; Receipts = (long[])scheduled.Clone(); Gross = new long[horizon + 1]; OnHand = new long[horizon + 1]; Net = new long[horizon + 1]; PlannedReceipts = new long[horizon + 1]; PlannedReleases = new long[horizon + 1]; OnHand[0] = item.OnHand;
    }
    public long PastDue => Orders.Where(o => o.Original < 1).Sum(o => o.Quantity);
}
sealed class Plan
{
    public SortedDictionary<string, ItemPlan> Items = new(StringComparer.Ordinal);
    public SortedDictionary<string, long[]> Loads = new(StringComparer.Ordinal), Overloads = new(StringComparer.Ordinal);
}
sealed class Promise(Inquiry inquiry)
{
    public readonly Inquiry Inquiry = inquiry;
    public int Week, MaterialWeek;
    public string Reason = "";
}
sealed class Data
{
    public List<string> Errors = [], PegItems = [], PlanningOrder = [];
    public int Horizon;
    public long TreeQuantity;
    public SortedDictionary<string, Item> Items;
    public Bom Bom;
    public SortedDictionary<string, Center> Centers;
    public SortedDictionary<string, List<Operation>> Routings;
    public List<Demand> Mps = [];
    public List<Inquiry> Inquiries = [];
    public Dictionary<string, int> Codes = new(StringComparer.Ordinal), Cumulative = new(StringComparer.Ordinal);
    public SortedDictionary<string, List<ScheduleRow>> Receipts = new(StringComparer.Ordinal);
    public SortedDictionary<string, long[]> Scheduled = new(StringComparer.Ordinal);
    public long[] Weeks;
    string ScheduleError(string item, int week, long quantity)
    {
        if (!Items.ContainsKey(item)) return "unknown item " + item;
        if (week < 1 || week > Horizon) return $"week {week} outside horizon";
        return quantity < 1 ? "bad quantity " + quantity : "";
    }
    List<ScheduleRow> ReadSchedule(string name, bool unique)
    {
        List<ScheduleRow> accepted = []; HashSet<(string, int)> seen = [];
        foreach (Row row in Io.Rows(name))
        {
            string[] f = row.Fields; ScheduleRow value = new(f[0], int.Parse(f[1]), long.Parse(f[2]), row.Line); string error = ScheduleError(value.Item, value.Week, value.Quantity);
            if (error.Length == 0 && unique && seen.Contains((value.Item, value.Week))) error = $"duplicate {value.Item} week {value.Week}";
            if (error.Length > 0) Io.Error(Errors, name, row.Line, error); else { accepted.Add(value); seen.Add((value.Item, value.Week)); }
        }
        return accepted;
    }
    List<Inquiry> ReadInquiries()
    {
        List<Inquiry> accepted = []; HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (Row row in Io.Rows("orders.csv"))
        {
            string[] f = row.Fields; Inquiry value = new(f[0], f[1], long.Parse(f[2]), int.Parse(f[3]), row.Line);
            string error = seen.Contains(value.Id) ? "duplicate order " + value.Id : ScheduleError(value.Item, value.Week, value.Quantity);
            if (error.Length > 0) Io.Error(Errors, "orders.csv", row.Line, error); else { accepted.Add(value); seen.Add(value.Id); }
        }
        return accepted;
    }
    public Data()
    {
        foreach (string line in Io.Lines("params.txt")) { string[] f = line.Split(' '); if (f[0] == "horizon") Horizon = int.Parse(f[1]); else if (f[0] == "peg") PegItems = f.Skip(1).ToList(); else TreeQuantity = long.Parse(f[1]); }
        Items = global::Items.Read(Errors); Bom = global::Bom.Read(Items, Errors); Centers = Capacity.ReadCenters(Errors); Routings = Capacity.ReadRoutings(Items, Centers, Bom, Errors);
        List<ScheduleRow> mps = ReadSchedule("mps.csv", true), receipts = ReadSchedule("receipts.csv", false); Inquiries = ReadInquiries();
        Mps = mps.Select(row => new Demand(row.Item, DemandKind.Mps, row.Week, row.Quantity)).ToList();
        foreach (string id in Items.Keys) { Bom.LowLevel(id, Codes); Bom.Cumulative(id, Items, Cumulative); Receipts[id] = []; Scheduled[id] = new long[Horizon + 1]; }
        PlanningOrder = Items.Keys.OrderBy(id => Codes[id]).ThenBy(id => id, StringComparer.Ordinal).ToList();
        foreach (ScheduleRow row in receipts.OrderBy(r => r.Week).ThenBy(r => r.Line)) { Receipts[row.Item].Add(row); Scheduled[row.Item][row.Week] += row.Quantity; }
        Weeks = Enumerable.Range(1, Horizon).Select(w => (long)w).ToArray();
    }
}
sealed class Planner(Data planningData)
{
    readonly Data data = planningData;
    public Plan Run(List<Demand> orders)
    {
        Plan plan = new();
        foreach (string id in data.PlanningOrder) plan.Items[id] = new(data.Items[id], data.Horizon, data.Scheduled[id]);
        foreach (Demand demand in data.Mps.Concat(orders)) plan.Items[demand.Item].Demands.Add(demand);
        foreach (string id in data.PlanningOrder)
        {
            ItemPlan p = plan.Items[id]; Item item = p.Item; foreach (Demand demand in p.Demands) p.Gross[demand.Week] += demand.Quantity;
            long projected = item.OnHand;
            for (int week = 1; week <= data.Horizon; week++)
            {
                long available = projected + p.Receipts[week] - p.Gross[week]; projected = available;
                if (available < item.Safety)
                {
                    long quantity = LotSizing.Size(item, week, available, p.Receipts, p.Gross, data.Horizon); PlannedOrder order = new(id, p.Orders.Count + 1, week, quantity, item.Lead);
                    p.Orders.Add(order); p.Net[week] = item.Safety - available; p.PlannedReceipts[week] = quantity; p.PlannedReleases[order.Release] += quantity; projected += quantity;
                }
                p.OnHand[week] = projected;
            }
            foreach (PlannedOrder order in p.Orders) foreach (Edge edge in data.Bom.Children[id]) plan.Items[edge.Child].Demands.Add(new(edge.Child, DemandKind.Dependent, order.Release, edge.Need(order.Quantity), Parent: id, ParentNumber: order.Number));
        }
        foreach (string id in data.Centers.Keys) plan.Loads[id] = new long[data.Horizon + 1];
        foreach (var route in data.Routings) foreach (PlannedOrder order in plan.Items[route.Key].Orders) for (int index = 0; index < route.Value.Count; index++)
        {
            Operation operation = route.Value[index]; int week = Capacity.OperationWeek(order.Receipt, data.Items[route.Key].Lead, index, route.Value.Count); plan.Loads[operation.Center][week] += operation.Minutes(order.Quantity);
        }
        foreach (Center center in data.Centers.Values) { long[] over = new long[data.Horizon + 1]; for (int week = 1; week <= data.Horizon; week++) over[week] = Math.Max(0, plan.Loads[center.Id][week] - center.Available); plan.Overloads[center.Id] = over; }
        return plan;
    }
    public (List<Promise> Promises, Plan Final) PromiseInquiries(Plan baseline)
    {
        Plan current = baseline; List<Demand> promised = []; List<Promise> promises = [];
        foreach (Inquiry inquiry in data.Inquiries)
        {
            Promise promise = new(inquiry);
            for (int week = inquiry.Week; week <= data.Horizon; week++)
            {
                Demand demand = new(inquiry.Item, DemandKind.Order, week, inquiry.Quantity, inquiry.Id, inquiry.Line); List<Demand> trialDemands = new(promised) { demand }; Plan trial = Run(trialDemands); string reason = "";
                foreach (string id in data.PlanningOrder) if (trial.Items[id].PastDue > current.Items[id].PastDue) { reason = id; break; }
                if (reason.Length == 0)
                {
                    if (promise.MaterialWeek == 0) promise.MaterialWeek = week;
                    foreach (string id in data.Centers.Keys) { for (int w = 1; w <= data.Horizon; w++) if (trial.Overloads[id][w] > current.Overloads[id][w]) { reason = $"{id} week {w}"; break; } if (reason.Length > 0) break; }
                }
                if (reason.Length == 0) { promise.Week = week; promised.Add(demand); current = trial; break; }
                if (week == inquiry.Week) promise.Reason = reason;
            }
            promises.Add(promise);
        }
        return (promises, current);
    }
    static Supply ParentSupply(Plan plan, Demand demand) => plan.Items[demand.Parent].OrderSupplies[demand.ParentNumber - 1];
    public void Peg(Plan plan)
    {
        foreach (string id in data.PlanningOrder)
        {
            ItemPlan p = plan.Items[id]; Item item = p.Item;
            if (item.OnHand > 0) p.Supplies.Add(new(SupplyKind.Stock, 0, item.OnHand));
            foreach (ScheduleRow receipt in data.Receipts[id]) p.Supplies.Add(new(SupplyKind.Receipt, receipt.Week, receipt.Quantity, receipt.Line));
            foreach (PlannedOrder order in p.Orders) p.Supplies.Add(new(SupplyKind.Order, order.Receipt, order.Quantity, order: order));
            p.Supplies = p.Supplies.OrderBy(s => s.Week).ThenBy(s => s.Kind).ThenBy(s => s.Line).ToList();
            List<Demand> demands = p.Demands.OrderBy(d => d.Week).ThenBy(d => d.Kind).ThenBy(d => d.Line).ThenBy(d => d.Parent, StringComparer.Ordinal).ThenBy(d => d.ParentNumber).ToList();
            if (item.Safety > 0) demands.Insert(0, new(id, DemandKind.Safety, 0, item.Safety));
            int index = 0;
            foreach (Demand demand in demands)
            {
                long remaining = demand.Quantity;
                while (remaining > 0) { while (p.Supplies[index].Remaining == 0) index++; Supply supply = p.Supplies[index]; long share = Math.Min(remaining, supply.Remaining); supply.Allocations.Add(new(demand, share)); remaining -= share; supply.Remaining -= share; }
            }
            p.OrderSupplies = p.Supplies.Where(s => s.Kind == SupplyKind.Order).ToList();
            foreach (Supply supply in p.OrderSupplies)
            {
                Dictionary<(string, int, int, string), Demand> roots = new();
                foreach (Allocation allocation in supply.Allocations)
                {
                    Demand demand = allocation.Demand;
                    if (demand.Kind == DemandKind.Dependent) foreach (Demand root in ParentSupply(plan, demand).Roots) roots[root.RootKey] = root;
                    else roots[demand.RootKey] = demand;
                }
                supply.Roots = roots.Values.OrderBy(d => d.Item, StringComparer.Ordinal).ThenBy(d => d.RootRank).ThenBy(d => d.Week).ThenBy(d => d.OrderId, StringComparer.Ordinal).ToList();
            }
        }
    }
    static string Depth(int depth) => new string('.', depth) + depth;
    public List<string> Grid(Plan plan)
    {
        List<string> lines = [];
        foreach (string id in data.PlanningOrder)
        {
            ItemPlan p = plan.Items[id]; Item item = p.Item;
            lines.Add($"ITEM {id} LLC {data.Codes[id]} LT {item.Lead} LOT {item.LotLabel} SS {item.Safety} OH {item.OnHand} {item.Description}");
            lines.Add(Report.Table("WEEK", data.Weeks, 6));
            (string Label, long[] Values)[] rows = [("GROSS", p.Gross), ("RECEIPTS", p.Receipts), ("ON_HAND", p.OnHand), ("NET", p.Net), ("PLAN_RCPT", p.PlannedReceipts), ("PLAN_REL", p.PlannedReleases)];
            foreach (var row in rows) lines.Add(Report.Table(row.Label, row.Values.Skip(1), 6));
            lines.Add($"TOTAL gross {p.Gross.Sum()} receipts {p.Receipts.Sum()} planned {p.PlannedReceipts.Sum()} orders {p.Orders.Count} ending {p.OnHand[data.Horizon]}");
        }
        return lines;
    }
    void WhereUsed(string item, int depth, long extension, List<string> lines)
    {
        foreach (Edge edge in data.Bom.Parents[item]) { long next = extension * edge.Quantity; lines.Add($"{Depth(depth)} {edge.Parent} qty {edge.Quantity} ext {next}"); WhereUsed(edge.Parent, depth + 1, next, lines); }
    }
    static void AllocationLines(Plan plan, Supply supply, int depth, List<string> lines)
    {
        foreach (Allocation allocation in supply.Allocations)
        {
            lines.Add(new string(' ', 2 * depth) + $"ALLOC {allocation.Share} {allocation.Demand.Text}");
            if (supply.Kind == SupplyKind.Order && allocation.Demand.Kind == DemandKind.Dependent) AllocationLines(plan, ParentSupply(plan, allocation.Demand), depth + 1, lines);
        }
    }
    public List<string> Pegging(Plan plan)
    {
        List<string> lines = [];
        foreach (string id in data.PegItems)
        {
            ItemPlan p = plan.Items[id]; lines.Add($"PEG {id} orders {p.Orders.Count}"); WhereUsed(id, 1, 1, lines);
            foreach (SupplyKind kind in new[] { SupplyKind.Stock, SupplyKind.Receipt, SupplyKind.Order }) foreach (Supply supply in p.Supplies.Where(s => s.Kind == kind))
            {
                lines.Add(supply.Header); AllocationLines(plan, supply, 1, lines); if (supply.Remaining > 0) lines.Add("  EXCESS " + supply.Remaining); lines.AddRange(supply.Roots.Select(root => "  ROOT " + root.Text));
            }
        }
        return lines;
    }
    void Explode(string item, long gross, long extension, int depth, List<string> lines, SortedDictionary<string, long> totals)
    {
        foreach (Edge edge in data.Bom.Children[item])
        {
            Item child = data.Items[edge.Child]; long nextExtension = extension * edge.Quantity, nextGross = edge.Need(gross); totals[edge.Child] = totals.GetValueOrDefault(edge.Child) + nextGross;
            lines.Add($"{Depth(depth)} {edge.Child} qty {edge.Quantity} scrap {edge.Scrap} ext {nextExtension} gross {nextGross} lt {child.Lead} cum {data.Cumulative[edge.Child]} {child.Description}");
            Explode(edge.Child, nextGross, nextExtension, depth + 1, lines, totals);
        }
    }
    public List<string> Trees()
    {
        List<string> lines = [];
        foreach (Item item in data.Items.Values.Where(i => data.Bom.TopLevel(i.Id)))
        {
            string id = item.Id; lines.Add($"TREE {id} quantity {data.TreeQuantity}"); lines.Add($"0 {id} ext 1 gross {data.TreeQuantity} lt {item.Lead} cum {data.Cumulative[id]} {item.Description}");
            SortedDictionary<string, long> totals = new(StringComparer.Ordinal); Explode(id, data.TreeQuantity, 1, 1, lines, totals); lines.AddRange(totals.Select(p => $"SUM {p.Key} {p.Value}"));
            List<string> path = [id]; string current = id;
            while (data.Bom.Manufactured(current)) { var children = data.Bom.Children[current]; Edge best = children[0]; foreach (Edge edge in children) if (data.Cumulative[edge.Child] > data.Cumulative[best.Child]) best = edge; current = best.Child; path.Add(current); }
            lines.Add($"CRITICAL {string.Join(" -> ", path)} cum {data.Cumulative[id]}");
        }
        return lines;
    }
    public List<string> Costs(Plan plan, Dictionary<string, StandardCost> costs)
    {
        Dictionary<string, long> usages = data.Items.Keys.ToDictionary(id => id, id => plan.Items[id].Gross.Sum(), StringComparer.Ordinal);
        Dictionary<string, long> values = usages.ToDictionary(p => p.Key, p => p.Value * costs[p.Key].Total, StringComparer.Ordinal); var classes = Costing.Classes(values);
        List<string> lines = ["item,material,labor,total,usage,value,class"];
        foreach (string id in data.Items.Keys) { StandardCost cost = costs[id]; lines.Add($"{id},{Report.Money(cost.Material)},{Report.Money(cost.Labor)},{Report.Money(cost.Total)},{usages[id]},{Report.Money(values[id])},{classes[id]}"); }
        return lines;
    }
    public List<string> Exceptions(Plan plan)
    {
        List<string> messages = [];
        foreach (string id in data.PlanningOrder)
        {
            ItemPlan p = plan.Items[id]; Item item = p.Item;
            if (item.OnHand < item.Safety) messages.Add($"BELOW_SAFETY {id} on hand {item.OnHand} safety {item.Safety}");
            foreach (PlannedOrder order in p.Orders)
            {
                string head = $"{id} order {order.Number} receipt {order.Receipt}";
                if (order.Original < 1) messages.Add($"PAST_DUE {head} release {order.Original} late {1 - order.Original} quantity {order.Quantity}");
                else if (order.Original == 1) messages.Add($"RELEASE {head} quantity {order.Quantity}");
            }
            long[] balances = new long[data.Horizon + 1]; long balance = item.OnHand, covered = 0;
            for (int week = 1; week <= data.Horizon; week++) { balance -= p.Gross[week]; balances[week] = balance; }
            foreach (ScheduleRow receipt in data.Receipts[id])
            {
                int need = 0; for (int week = 1; week <= data.Horizon; week++) if (balances[week] + covered < item.Safety) { need = week; break; }
                string head = $"{id} receipt line {receipt.Line} week {receipt.Week} quantity {receipt.Quantity}";
                if (need == 0) messages.Add("CANCEL " + head); else if (need < receipt.Week) messages.Add($"EXPEDITE {head} to {need}"); else if (need > receipt.Week) messages.Add($"DEFER {head} to {need}"); covered += receipt.Quantity;
            }
            if (data.Bom.Manufactured(id) && !data.Routings.ContainsKey(id)) messages.Add("NO_ROUTING " + id);
            if (p.Gross.Sum() == 0 && item.OnHand > 0) messages.Add($"NO_DEMAND {id} on hand {item.OnHand}");
        }
        foreach (Center center in data.Centers.Values) for (int week = 1; week <= data.Horizon; week++) if (plan.Overloads[center.Id][week] > 0) messages.Add($"OVERLOAD {center.Id} week {week} load {plan.Loads[center.Id][week]} available {center.Available}");
        List<string> lines = data.Errors.Select(error => "ERROR " + error).ToList(); lines.AddRange(messages);
        string[] kinds = ["BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD"];
        lines.Add("SUMMARY errors " + data.Errors.Count + " " + string.Join(" ", kinds.Select(kind => kind.ToLowerInvariant() + " " + messages.Count(message => message.StartsWith(kind + " ", StringComparison.Ordinal))))); return lines;
    }
    public List<string> Capacities(Plan plan)
    {
        List<string> lines = []; Dictionary<string, long> totals = new(StringComparer.Ordinal);
        foreach (Center center in data.Centers.Values)
        {
            long[] loads = plan.Loads[center.Id], over = plan.Overloads[center.Id], leveled = Capacity.Level(loads, center.Available); long total = loads.Sum(), available = center.Available * data.Horizon; totals[center.Id] = total;
            int peak = total == 0 ? 0 : Array.IndexOf(loads, loads.Skip(1).Max()); int overloaded = over.Count(value => value > 0); long backlog = Math.Max(0, leveled[1] - center.Available);
            lines.Add($"CENTER {center.Id} minutes {center.Minutes} efficiency {center.Efficiency} available {center.Available} {center.Description}");
            lines.Add(Report.Table("WEEK", data.Weeks, 7)); lines.Add(Report.Table("LOAD", loads.Skip(1), 7)); lines.Add(Report.Table("UTIL", loads.Skip(1).Select(value => Report.Percent(value, center.Available)), 7)); lines.Add(Report.Table("OVER", over.Skip(1), 7)); lines.Add(Report.Table("LEVELED", leveled.Skip(1), 7));
            lines.Add($"TOTAL load {total} available {available} utilization {Report.Percent(total, available)} overloaded {overloaded} peak {peak} backlog {backlog}");
        }
        List<string> order = data.Centers.Keys.ToList();
        order.Sort((a, b) => { long left = totals[a] * data.Centers[b].Available, right = totals[b] * data.Centers[a].Available; return left != right ? right.CompareTo(left) : StringComparer.Ordinal.Compare(a, b); });
        for (int i = 0; i < order.Count; i++) { string id = order[i]; lines.Add($"RANK {i + 1} {id} load {totals[id]} utilization {Report.Percent(totals[id], data.Centers[id].Available * data.Horizon)}"); }
        return lines;
    }
    public List<string> Promises(List<Promise> promises, Plan baseline, Plan finalPlan)
    {
        List<string> lines = []; int onTime = 0, late = 0, rejected = 0;
        foreach (Promise promise in promises)
        {
            Inquiry inquiry = promise.Inquiry; string head = $"ORDER {inquiry.Id} {inquiry.Item} quantity {inquiry.Quantity} requested {inquiry.Week}", material = promise.MaterialWeek == 0 ? "none" : promise.MaterialWeek.ToString();
            if (promise.Week == 0) { rejected++; lines.Add($"{head} rejected material {material} reason {promise.Reason}"); continue; }
            if (promise.Week == inquiry.Week) { onTime++; lines.Add($"{head} promised {promise.Week}"); }
            else { late++; lines.Add($"{head} promised {promise.Week} late {promise.Week - inquiry.Week} material {material} reason {promise.Reason}"); }
            foreach (string id in data.PlanningOrder) foreach (Supply supply in finalPlan.Items[id].OrderSupplies.Where(s => s.Serves(inquiry.Id))) { PlannedOrder order = supply.Order!; lines.Add($"  SUPPLY {id} order {order.Number} receipt {order.Receipt} release {order.Release} quantity {order.Quantity}"); }
        }
        foreach (string id in data.PlanningOrder)
        {
            ItemPlan before = baseline.Items[id], after = finalPlan.Items[id]; int first = 0;
            for (int week = 1; week <= data.Horizon; week++) if (before.PlannedReceipts[week] != after.PlannedReceipts[week]) { first = week; break; }
            if (first != 0) lines.Add($"CHANGE {id} from {first} planned {before.PlannedReceipts.Sum()} -> {after.PlannedReceipts.Sum()} orders {before.Orders.Count} -> {after.Orders.Count}");
        }
        lines.Add($"SUMMARY orders {promises.Count} on_time {onTime} late {late} rejected {rejected}"); return lines;
    }
    public List<string> Releases(Plan plan)
    {
        var orders = data.PlanningOrder.SelectMany(id => plan.Items[id].Orders).Where(o => o.Release == 1).OrderBy(o => o.Original).ThenBy(o => o.Item, StringComparer.Ordinal).ThenBy(o => o.Number).ToList();
        Dictionary<string, long> available = data.Items.ToDictionary(p => p.Key, p => p.Value.OnHand + data.Scheduled[p.Key][1], StringComparer.Ordinal); List<string> lines = []; int made = 0, readyCount = 0, bought = 0; long purchased = 0;
        foreach (PlannedOrder order in orders)
        {
            Item item = data.Items[order.Item]; string head = $"{order.Item} order {order.Number} receipt {order.Receipt} quantity {order.Quantity}" + (order.Original < 1 ? " late " + (1 - order.Original) : "");
            if (!data.Bom.Manufactured(order.Item)) { long value = order.Quantity * item.Material; bought++; purchased += value; lines.Add($"BUY {head} value {Report.Money(value)}"); continue; }
            made++; bool ready = true; List<string> details = [];
            foreach (Edge edge in data.Bom.Children[order.Item]) { long need = edge.Need(order.Quantity), have = available[edge.Child]; if (need > have) ready = false; details.Add($"  PICK {edge.Child} need {need} available {have} short {Math.Max(0, need - have)}"); }
            if (ready) { readyCount++; foreach (Edge edge in data.Bom.Children[order.Item]) available[edge.Child] -= edge.Need(order.Quantity); }
            if (data.Routings.TryGetValue(order.Item, out var operations)) for (int i = 0; i < operations.Count; i++) { Operation operation = operations[i]; int week = Capacity.OperationWeek(order.Receipt, item.Lead, i, operations.Count); details.Add($"  OPERATION {operation.Number} {operation.Center} week {week} minutes {operation.Minutes(order.Quantity)}"); }
            lines.Add($"MAKE {head} {(ready ? "READY" : "SHORT")}"); lines.AddRange(details);
        }
        lines.Add($"SUMMARY make {made} ready {readyCount} short {made - readyCount} buy {bought} value {Report.Money(purchased)}"); return lines;
    }
    public List<string> ValuePlan(Plan plan, Dictionary<string, StandardCost> costs)
    {
        List<string> lines = ["week,inventory,purchases,labor"];
        for (int week = 1; week <= data.Horizon; week++)
        {
            long inventory = 0, purchases = 0, labor = 0;
            foreach (string id in data.PlanningOrder) { ItemPlan p = plan.Items[id]; inventory += p.OnHand[week] * costs[id].Total; if (data.Bom.Manufactured(id)) labor += p.PlannedReleases[week] * p.Item.Labor; else purchases += p.PlannedReleases[week] * p.Item.Material; }
            lines.Add($"{week},{Report.Money(inventory)},{Report.Money(purchases)},{Report.Money(labor)}");
        }
        return lines;
    }
}
static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Data data = new(); Planner planner = new(data); Plan baseline = planner.Run([]); var (promises, finalPlan) = planner.PromiseInquiries(baseline); planner.Peg(finalPlan); var costs = Costing.Rollup(data.Items, data.Bom, data.PlanningOrder);
        Report.Write("mrp_grid.txt", planner.Grid(finalPlan)); Report.Write("pegging.txt", planner.Pegging(finalPlan)); Report.Write("bom_tree.txt", planner.Trees()); Report.Write("cost_rollup.csv", planner.Costs(finalPlan, costs)); Report.Write("exceptions.txt", planner.Exceptions(finalPlan)); Report.Write("capacity.txt", planner.Capacities(finalPlan)); Report.Write("promises.txt", planner.Promises(promises, baseline, finalPlan)); Report.Write("releases.txt", planner.Releases(finalPlan)); Report.Write("value_plan.csv", planner.ValuePlan(finalPlan, costs));
    }
}
