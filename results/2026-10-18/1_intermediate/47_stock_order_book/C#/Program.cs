#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
sealed class Order
{
    public string Id, Trader, Kind, Side, Condition = "", Status = "OPEN";
    public int? Price, Trigger, Peak;
    public int Quantity, Remaining, Visible, Filled, Value, Priority, Number;
    public List<string> History = new() {
        "ACCEPT"
    };
    public Order(string id, string trader, string kind, string side, int quantity)
    {
        Id = id;
        Trader = trader;
        Kind = kind;
        Side = side;
        Quantity = Remaining = quantity;
    }
    public bool Active => Status is "OPEN" or "PARTIAL" or "PENDING";
    public bool Resting => Status is "OPEN" or "PARTIAL";
    public bool Matches(int p) => Price == null || (Side == "BUY" ? p <= Price : p >= Price);
    public bool Triggered(int p) => Side == "BUY" ? p >= Trigger : p <= Trigger;
    public string Line => $"ORDER {Id} {Status} {Filled}/{Quantity}";
    public string Details => $"{Id} {Trader} {Kind} {Side} {Price?.ToString() ?? "-"} {Status} {Filled}/{Quantity} avg {(Filled == 0 ? "-" : Engine.Decimal(Value * 100 / Filled))}" + (Trigger is int r ? $" trigger {r}" : "");
    public void Fill(int n, int p, int q) {
        Remaining -= q;
        Filled += q;
        Value += p * q;
        History.Add($"FILL {n} {p} {q}");
    }
}
sealed class Trader
{
    public string Name;
    public int Bought, Sold, Cash, Fees;
    public int? Limit;
    public Trader(string name) {
        Name = name;
    }
    public int Net => Bought - Sold;
    public int Volume => Bought + Sold;
    public int Pnl(int p) => Cash + Net * p;
    public string Position(int p) => $"POSITION {Name} bought {Bought} sold {Sold} net {Net} cash {Cash} fees {Fees} pnl {Pnl(p)}";
}
sealed record Trade(int Number, int Price, int Quantity, Order Buy, Order Sell, string Taker, int BuyFee, int SellFee)
{
    public string Line => $"TRADE {Number} {Price} {Quantity} {Buy.Id} {Buy.Trader} {Sell.Id} {Sell.Trader}";
}
sealed class CommandError : Exception {
    public CommandError(string message) : base(message) {
    }
}
sealed class Engine
{
    readonly Dictionary<string, Order> orders = new(StringComparer.Ordinal);
    readonly Dictionary<string, Trader> traders = new(StringComparer.Ordinal);
    readonly List<Trade> trades = new();
    readonly HashSet<Order> book = new();
    readonly List<Order> pending = new();
    readonly List<string> output = new();
    int maker, taker, band, tick = 1, lot = 1, priority;
    bool halted;
    int Mark => trades.Count == 0 ? 0 : trades[^1].Price;
    public static string Decimal(int x) => $"{x / 100}.{x % 100:D2}";
    static void Require(bool good, string reason) {
        if (!good) throw new CommandError(reason);
    }
    Trader Register(string name) {
        if (!traders.ContainsKey(name)) traders[name] = new(name);
        return traders[name];
    }
    Trader RequireTrader(string name) {
        Require(traders.ContainsKey(name), "unknown trader");
        return traders[name];
    }
    Order RequireOrder(string id) {
        Require(orders.ContainsKey(id), "unknown order");
        return orders[id];
    }
    List<Order> Active(string name) => orders.Values.Where(o => o.Trader == name && o.Active).OrderBy(o => o.Number).ToList();
    int Exposure(string name, string side, Order? exclude = null) => (side == "BUY" ? traders[name].Net : -traders[name].Net) + Active(name).Where(o => o.Side == side && o != exclude).Sum(o => o.Remaining);
    void Risk(string name, string side, int q, Order? exclude = null) {
        if (traders.TryGetValue(name, out Trader? t) && t.Limit is int m) Require(Exposure(name, side, exclude) + q <= m, "risk limit");
    }
    void Band(int p) => Require(band == 0 || trades.Count == 0 || Math.Abs(p - Mark) <= band, "outside band");
    List<Order> Sorted(string side) => book.Where(o => o.Side == side).OrderBy(o => side == "BUY" ? -o.Price!.Value : o.Price!.Value).ThenBy(o => o.Priority).ToList();
    Order? Best(string side) => Sorted(side).FirstOrDefault();
    List<(int Price, int Quantity, int Count)> Levels(string side) => Sorted(side).GroupBy(o => o.Price!.Value).Select(g => (g.Key, g.Sum(o => o.Visible), g.Count())).ToList();
    static string Opposite(string side) => side == "BUY" ? "SELL" : "BUY";
    void Match(Order x)
    {
        while (x.Remaining > 0)
        {
            Order? y = Best(Opposite(x.Side));
            if (y == null || !x.Matches(y.Price!.Value)) break;
            if (x.Trader == y.Trader)
            {
                output.Add($"STP {y.Id} {y.Remaining}");
                y.History.Add($"STP {y.Remaining}");
                book.Remove(y);
                y.Remaining = 0;
                y.Status = "CANCELLED";
                continue;
            }
            int q = Math.Min(x.Remaining, y.Visible), p = y.Price.Value;
            Order buy = x.Side == "BUY" ? x : y, sell = x.Side == "SELL" ? x : y;
            int bf = q * (buy == x ? taker : maker), sf = q * (sell == x ? taker : maker);
            var trade = new Trade(trades.Count + 1, p, q, buy, sell, x.Id, bf, sf);
            trades.Add(trade);
            x.Fill(trade.Number, p, q);
            y.Fill(trade.Number, p, q);
            y.Visible -= q;
            Trader b = traders[buy.Trader], s = traders[sell.Trader];
            b.Bought += q;
            b.Cash -= p * q + bf;
            b.Fees += bf;
            s.Sold += q;
            s.Cash += p * q - sf;
            s.Fees += sf;
            output.Add(trade.Line);
            if (y.Remaining == 0) {
                book.Remove(y);
                y.Status = "FILLED";
            } else
            {
                y.Status = "PARTIAL";
                if (y.Visible == 0)
                {
                    y.Priority = ++priority;
                    y.Visible = Math.Min(y.Peak!.Value, y.Remaining);
                    string refresh = $"REFRESH {y.Visible} {y.Remaining - y.Visible}";
                    y.History.Add(refresh);
                    output.Add($"REFRESH {y.Id} {y.Visible} {y.Remaining - y.Visible}");
                }
            }
        }
    }
    void Post(Order o, bool forceRest = false)
    {
        if (o.Remaining == 0) o.Status = "FILLED";
        else if (forceRest || o.Kind is "ICEBERG" or "STOPLIMIT" || o.Kind == "LIMIT" && o.Condition != "IOC")
        {
            o.Priority = ++priority;
            o.Visible = Math.Min(o.Peak ?? o.Remaining, o.Remaining);
            o.Status = o.Filled == 0 ? "OPEN" : "PARTIAL";
            book.Add(o);
            o.History.Add($"REST {o.Price} {o.Visible}");
        } else {
            o.History.Add($"EXPIRE {o.Remaining}");
            o.Remaining = 0;
            o.Status = "CANCELLED";
        }
        output.Add(o.Line);
    }
    void Trigger()
    {
        while (trades.Count > 0)
        {
            List<Order> selected = pending.Where(o => o.Triggered(Mark)).OrderBy(o => o.Number).ToList();
            if (selected.Count == 0) break;
            foreach (Order o in selected) pending.Remove(o);
            foreach (Order o in selected) {
                output.Add($"TRIGGER {o.Id}");
                o.History.Add("TRIGGER");
                Match(o);
                Post(o);
            }
        }
    }
    void Cancel(Order o) {
        book.Remove(o);
        pending.Remove(o);
        o.History.Add($"CANCEL {o.Remaining}");
        o.Remaining = 0;
        o.Status = "CANCELLED";
        output.Add(o.Line);
    }
    string Bars(IEnumerable<Trade> source)
    {
        List<Trade> ts = source.ToList();
        return $"open {ts[0].Price} high {ts.Max(t => t.Price)} low {ts.Min(t => t.Price)} close {ts[^1].Price} volume {ts.Sum(t => t.Quantity)}";
    }
    void Command(string[] w)
    {
        string c = w[0];
        int Num(int i) => int.Parse(w[i]);
        if (c is "LIMIT" or "MARKET" or "STOP" or "STOPLIMIT" or "ICEBERG")
        {
            int qi = c == "MARKET" ? 4 : c == "STOPLIMIT" ? 6 : 5;
            var o = new Order(w[1], w[2], c, w[3], Num(qi));
            if (c is "LIMIT" or "ICEBERG") o.Price = Num(4);
            if (c is "STOP" or "STOPLIMIT") o.Trigger = Num(4);
            if (c == "STOPLIMIT") o.Price = Num(5);
            if (c == "ICEBERG") o.Peak = Num(6);
            if (c == "LIMIT" && w.Length == 7) o.Condition = w[6];
            int[] prices = new[] {
                o.Price, o.Trigger
            }
            .Where(p => p != null).Select(p => p!.Value).ToArray();
            Require(!halted, "halted");
            Require(!orders.ContainsKey(o.Id), "duplicate id");
            Require(prices.All(p => p != 0), "invalid price");
            Require(o.Quantity != 0, "invalid quantity");
            Require(prices.All(p => p % tick == 0), "invalid tick");
            Require(o.Quantity % lot == 0, "invalid lot");
            if (o.Peak is int k) Require(k > 0 && k <= o.Quantity && k % lot == 0, "invalid peak");
            if (o.Trigger != null) Require(trades.Count == 0 || !o.Triggered(Mark), "invalid trigger");
            if (o.Price is int p) Band(p);
            Risk(o.Trader, o.Side, o.Quantity);
            Order? best = Best(Opposite(o.Side));
            if (o.Condition == "POSTONLY") Require(best == null || !o.Matches(best.Price!.Value), "would cross");
            if (o.Condition == "FOK") Require(Sorted(Opposite(o.Side)).Where(a => a.Trader != o.Trader && o.Matches(a.Price!.Value)).Sum(a => a.Remaining) >= o.Quantity, "unfillable");
            Register(o.Trader);
            o.Number = orders.Count + 1;
            orders.Add(o.Id, o);
            if (o.Trigger != null) {
                o.Status = "PENDING";
                pending.Add(o);
                output.Add(o.Line);
            } else {
                if (o.Condition != "POSTONLY") Match(o);
                Post(o);
                Trigger();
            }
            return;
        }
        switch (c)
        {
            case "CANCEL": {
                Order o = RequireOrder(w[1]);
                Require(o.Active, "not open");
                Cancel(o);
                break;
            }
            case "REPLACE":
            {
                Require(!halted, "halted");
                Order o = RequireOrder(w[1]);
                Require(o.Resting, "not open");
                int p = Num(2), q = Num(3);
                bool moved = p != o.Price;
                Require(p > 0, "invalid price");
                Require(q > 0, "invalid quantity");
                Require(!moved || p % tick == 0, "invalid tick");
                Require(q % lot == 0, "invalid lot");
                Require(moved || q != o.Remaining, "no change");
                if (moved) Band(p);
                if (q > o.Remaining) Risk(o.Trader, o.Side, q, o);
                o.Quantity = o.Filled + q;
                if (!moved && q < o.Remaining)
                {
                    o.Remaining = q;
                    o.Visible = Math.Min(o.Visible, q);
                    o.History.Add($"REPLACE {p} {q} kept");
                    output.Add($"REPLACE {o.Id} kept");
                    output.Add(o.Line);
                } else
                {
                    book.Remove(o);
                    o.Price = p;
                    o.Remaining = q;
                    o.History.Add($"REPLACE {p} {q} lost");
                    output.Add($"REPLACE {o.Id} lost");
                    Match(o);
                    Post(o, true);
                    Trigger();
                }
                break;
            }
            case "CANCELALL": {
                RequireTrader(w[1]);
                List<Order> active = Active(w[1]);
                output.Add($"CANCELALL {w[1]} {active.Count}");
                foreach (Order o in active) Cancel(o);
                break;
            }
            case "HALT": Require(!halted, "already halted");
            halted = true;
            output.Add(c);
            break;
            case "RESUME": Require(halted, "not halted");
            halted = false;
            output.Add(c);
            break;
            case "RISK": Register(w[1]).Limit = Num(2);
            output.Add($"RISK {w[1]} {w[2]} exposure buy {Exposure(w[1], "BUY")} sell {Exposure(w[1], "SELL")}");
            break;
            case "FEE": Require(Num(1) + Num(2) >= 0, "invalid fee");
            maker = Num(1);
            taker = Num(2);
            output.Add($"FEE maker {maker} taker {taker}");
            break;
            case "BAND": band = Num(1);
            output.Add($"BAND {band}");
            break;
            case "TICK": case "LOT": Require(Num(1) > 0, "invalid size");
            if (c == "TICK") tick = Num(1);
            else lot = Num(1);
            output.Add($"{c} {w[1]}");
            break;
            case "BOOK":
            {
                int n = Num(1);
                Require(n > 0, "invalid depth");
                var bids = Levels("BUY");
                var asks = Levels("SELL");
                output.Add($"BOOK bids {bids.Count} asks {asks.Count}");
                foreach (var l in asks.Take(n).Reverse()) output.Add($"ASK {l.Price} {l.Quantity} {l.Count}");
                foreach (var l in bids.Take(n)) output.Add($"BID {l.Price} {l.Quantity} {l.Count}");
                break;
            }
            case "ORDERS": {
                RequireTrader(w[1]);
                var active = Active(w[1]);
                output.Add($"ORDERS {w[1]} {active.Count}");
                output.AddRange(active.Select(o => o.Details));
                break;
            }
            case "STATUS": output.Add("STATUS " + RequireOrder(w[1]).Details);
            break;
            case "HISTORY": {
                Order o = RequireOrder(w[1]);
                output.Add($"HISTORY {o.Id} {o.History.Count}");
                output.AddRange(o.History);
                break;
            }
            case "POSITION": output.Add(RequireTrader(w[1]).Position(Mark));
            break;
            case "FILLS":
            {
                string name = w[1];
                RequireTrader(name);
                var ts = trades.Where(t => t.Buy.Trader == name || t.Sell.Trader == name).ToList();
                output.Add($"FILLS {name} {ts.Count}");
                int net = 0;
                foreach (Trade t in ts) {
                    bool buy = t.Buy.Trader == name;
                    string id = buy ? t.Buy.Id : t.Sell.Id;
                    net += buy ? t.Quantity : -t.Quantity;
                    output.Add($"{t.Number} {(buy ? "BUY" : "SELL")} {t.Price} {t.Quantity} {id} {(t.Taker == id ? "TAKER" : "MAKER")} fee {(buy ? t.BuyFee : t.SellFee)} net {net}");
                }
                break;
            }
            case "LAST": output.Add(trades.Count == 0 ? "LAST none" : $"LAST {Mark} {trades[^1].Quantity}");
            break;
            case "VWAP": output.Add(trades.Count == 0 ? "VWAP none" : $"VWAP {Decimal(trades.Sum(t => t.Price * t.Quantity) * 100 / trades.Sum(t => t.Quantity))} volume {trades.Sum(t => t.Quantity)} trades {trades.Count}");
            break;
            case "SPREAD":
            {
                Order? b = Best("BUY"), a = Best("SELL");
                string line = $"SPREAD bid {b?.Price?.ToString() ?? "none"} ask {a?.Price?.ToString() ?? "none"}";
                if (a != null && b != null) {
                    int sum = a.Price!.Value + b.Price!.Value;
                    line += $" spread {a.Price - b.Price} mid {sum / 2}.{(sum % 2 == 0 ? 0 : 5)}";
                }
                output.Add(line);
                break;
            }
            case "IMPACT":
            {
                int q = Num(2);
                Require(q > 0, "invalid quantity");
                var levels = Levels(Opposite(w[1]));
                int rem = q, cost = 0, worst = 0, used = 0;
                foreach (var l in levels) {
                    if (rem == 0) break;
                    int u = Math.Min(rem, l.Quantity);
                    rem -= u;
                    cost += u * l.Price;
                    worst = l.Price;
                    used++;
                }
                output.Add(rem > 0 ? $"IMPACT {w[1]} {q} insufficient {levels.Sum(l => l.Quantity)}" : $"IMPACT {w[1]} {q} avg {Decimal(cost * 100 / q)} worst {worst} levels {used}");
                break;
            }
            case "TRADES": {
                int k = Num(1);
                Require(k > 0, "invalid count");
                output.Add($"TRADES {Math.Min(k, trades.Count)} of {trades.Count}");
                output.AddRange(trades.Skip(Math.Max(0, trades.Count - k)).Select(t => t.Line));
                break;
            }
            case "BARS": {
                int k = Num(1);
                Require(k > 0, "invalid count");
                output.Add($"BARS {(trades.Count + k - 1) / k}");
                for (int i = 0;
                i < trades.Count;
                i += k) output.Add($"{i / k + 1} {Bars(trades.Skip(i).Take(k))}");
                break;
            }
            case "RANK": {
                var ranked = traders.Values.OrderByDescending(t => t.Pnl(Mark)).ThenByDescending(t => t.Volume).ThenBy(t => t.Name, StringComparer.Ordinal).ToList();
                output.Add($"RANK {ranked.Count}");
                for (int i = 0;
                i < ranked.Count;
                i++) output.Add($"{i + 1} {ranked[i].Name} pnl {ranked[i].Pnl(Mark)} volume {ranked[i].Volume}");
                break;
            }
            case "FLOW": {
                int b = trades.Where(t => t.Taker == t.Buy.Id).Sum(t => t.Quantity), s = trades.Where(t => t.Taker == t.Sell.Id).Sum(t => t.Quantity);
                output.Add($"FLOW buy {b} sell {s} net {b - s}");
                break;
            }
            case "SUMMARY": output.Add(trades.Count == 0 ? "SUMMARY trades 0" : $"SUMMARY trades {trades.Count} volume {trades.Sum(t => t.Quantity)} open {trades[0].Price} high {trades.Max(t => t.Price)} low {trades.Min(t => t.Price)} close {Mark} fees {trades.Sum(t => t.BuyFee + t.SellFee)}");
            foreach (Trader t in traders.Values.OrderBy(t => t.Name, StringComparer.Ordinal)) output.Add(t.Position(Mark));
            break;
        }
    }
    public void Execute(string line)
    {
        string[] w = line.Split(' ');
        try {
            Command(w);
        } catch (CommandError e) {
            output.Add((w[0] is "LIMIT" or "MARKET" or "STOP" or "STOPLIMIT" or "ICEBERG" or "CANCEL" or "REPLACE" ? $"REJECT {w[1]} " : "ERROR ") + e.Message);
        }
    }
    public void Write() {
        Console.Write(string.Join("\n", output));
        Console.Write('\n');
    }
}
static class Program {
    static void Main() {
        int n = int.Parse(Console.ReadLine()!);
        var engine = new Engine();
        for (int i = 0;
        i < n;
        i++) engine.Execute(Console.ReadLine()!);
        engine.Write();
    }
}
