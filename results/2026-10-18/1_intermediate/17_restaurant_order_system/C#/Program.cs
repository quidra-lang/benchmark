using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError : Exception
{
    public CommandError(string message) : base(message) { }
}

sealed class Table
{
    public int Number { get; }
    public int Seats { get; }
    public Check? Check { get; set; }

    public Table(int number, int seats)
    {
        Number = number;
        Seats = seats;
    }
}

sealed class Server
{
    public string Name { get; }
    public int Parties { get; set; }
    public int Sales { get; set; }
    public int Tips { get; set; }

    public Server(string name) => Name = name;
}

sealed class MenuItem
{
    public string Name { get; }
    public string Station { get; set; }
    public int Prep { get; set; }
    public int Price { get; set; }
    public string Course { get; set; }
    public int? Stock { get; set; }

    public MenuItem(string name, string station, int prep, int price, string course)
    {
        Name = name;
        Station = station;
        Prep = prep;
        Price = price;
        Course = course;
    }
}

sealed class Check
{
    public string Party { get; }
    public int Size { get; }
    public Table Table { get; set; }
    public Server Server { get; }
    public int Seated { get; }
    public List<OrderLine> Lines { get; } = new();
    public int Paid { get; set; }
    public int Discount { get; set; }
    public bool Closed { get; set; }

    public Check(string party, int size, Table table, Server server, int seated)
    {
        Party = party;
        Size = size;
        Table = table;
        Server = server;
        Seated = seated;
    }

    public IEnumerable<OrderLine> Active() => Lines.Where(line => line.State != "VOID");
}

sealed class OrderLine
{
    public int Number { get; }
    public Check Check { get; }
    public int Seat { get; set; }
    public string Item { get; }
    public int Quantity { get; }
    public string Station { get; }
    public int Prep { get; }
    public int Price { get; }
    public string Course { get; }
    public string State { get; set; } = "ORDERED";
    public string? Reason { get; set; }
    public int Fire { get; set; }
    public int Ready { get; set; }
    public bool Started { get; set; }

    public OrderLine(int number, Check check, int seat, MenuItem item, int quantity, int price)
    {
        Number = number;
        Check = check;
        Seat = seat;
        Item = item.Name;
        Quantity = quantity;
        Station = item.Station;
        Prep = item.Prep;
        Price = price;
        Course = item.Course;
    }

    public int Amount => Reason is null ? Price * Quantity : 0;
}

sealed class Station
{
    public string Name { get; }
    public int Capacity { get; }
    public bool Up { get; set; } = true;
    public List<OrderLine> Queue { get; } = new();
    public List<OrderLine> Cooking { get; } = new();
    public List<int> Tickets { get; } = new();
    public int Remakes { get; set; }

    public Station(string name)
    {
        Name = name;
        Capacity = name == "BAR" ? 2 : 1;
    }
}

sealed class WaitingParty
{
    public string Party { get; }
    public int Size { get; }
    public int Joined { get; }

    public WaitingParty(string party, int size, int joined)
    {
        Party = party;
        Size = size;
        Joined = joined;
    }
}

readonly record struct Amounts(int Subtotal, int Discount, int Service, int Tax, int Total, int Due);

sealed class Restaurant
{
    private static readonly string[] StationNames = { "GRILL", "FRY", "COLD", "BAR" };
    private static readonly string[] CourseNames = { "DRINK", "STARTER", "MAIN", "DESSERT" };

    private readonly Dictionary<int, Table> tables = new();
    private readonly List<Server> servers = new();
    private readonly List<WaitingParty> waiting = new();
    private readonly Dictionary<string, MenuItem> menu = new(StringComparer.Ordinal);
    private readonly List<OrderLine> lines = new();
    private readonly Dictionary<string, Station> stations = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> sales = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> totals = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> payments = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> served = new(StringComparer.Ordinal);
    private readonly List<string> output = new();

    private int now;
    private int happyRate;
    private int happyEnd;
    private int covers;
    private int parties;
    private int turns;
    private int stay;
    private int tips;
    private int comps;
    private int compAmount;
    private int voids;

    public Restaurant()
    {
        foreach (string name in StationNames) stations.Add(name, new Station(name));
        foreach (string name in CourseNames) sales.Add(name, 0);
        foreach (string name in new[] { "subtotal", "discount", "service", "tax", "total" })
            totals.Add(name, 0);
        payments.Add("CASH", 0);
        payments.Add("CARD", 0);
    }

    private static int Number(string value) => int.Parse(value, CultureInfo.InvariantCulture);

    private static int Cents(string amount) => Number(amount.Replace(".", "", StringComparison.Ordinal));

    private static string Money(int amount) =>
        (amount / 100).ToString(CultureInfo.InvariantCulture) + "." +
        (amount % 100).ToString("00", CultureInfo.InvariantCulture);

    private static string Clock(int time)
    {
        int minutes = 660 + time;
        return (minutes / 60).ToString("00", CultureInfo.InvariantCulture) + ":" +
               (minutes % 60).ToString("00", CultureInfo.InvariantCulture);
    }

    private static int Rounded(int value, int rate) => (value * rate + 50) / 100;

    private void Emit(params object[] parts) =>
        output.Add(string.Join(" ", parts.Select(p => Convert.ToString(p, CultureInfo.InvariantCulture))));

    private static void Fail(string reason) => throw new CommandError(reason);

    private Table RequireTable(string text)
    {
        int number = Number(text);
        if (!tables.TryGetValue(number, out Table? table)) Fail("unknown table " + text);
        return table!;
    }

    private Check RequireCheck(string text)
    {
        Table table = RequireTable(text);
        if (table.Check is null) Fail("table " + text + " is free");
        return table.Check!;
    }

    private static void Unlocked(Check check)
    {
        if (check.Paid > 0) Fail("check for table " + check.Table.Number + " is locked");
    }

    private OrderLine RequireLine(string text)
    {
        int number = Number(text);
        if (number < 1 || number > lines.Count) Fail("unknown line " + text);
        return lines[number - 1];
    }

    private static void Modifiable(OrderLine line)
    {
        if (line.State == "VOID") Fail("#" + line.Number + " is void");
        if (line.Check.Closed) Fail("#" + line.Number + " is on a closed check");
        Unlocked(line.Check);
    }

    private static void Unserved(Check check)
    {
        int count = check.Active().Count(line => line.State != "SERVED");
        if (count != 0)
            Fail("table " + check.Table.Number + " has " + count + " unserved items");
    }

    private Station RequireStation(string name)
    {
        if (!stations.TryGetValue(name, out Station? station)) Fail("unknown station " + name);
        return station!;
    }

    private static void RequireCourse(string name)
    {
        if (!CourseNames.Contains(name, StringComparer.Ordinal)) Fail("unknown course " + name);
    }

    private MenuItem RequireItem(string name)
    {
        if (!menu.TryGetValue(name, out MenuItem? item)) Fail("unknown item " + name);
        return item!;
    }

    private int Load(Server server) =>
        tables.Values.Count(table => table.Check?.Server == server);

    private Table? SelectTable(int size) =>
        tables.Values.Where(table => table.Check is null && table.Seats >= size)
              .OrderBy(table => table.Seats).ThenBy(table => table.Number).FirstOrDefault();

    private Check Seat(string party, int size, Table table)
    {
        Server server = servers[0];
        foreach (Server candidate in servers)
        {
            if (Load(candidate) < Load(server)) server = candidate;
        }
        Check check = new(party, size, table, server, now);
        table.Check = check;
        server.Parties++;
        covers += size;
        parties++;
        return check;
    }

    private void ProcessWaiting()
    {
        List<WaitingParty> remaining = new();
        foreach (WaitingParty party in waiting)
        {
            Table? table = SelectTable(party.Size);
            if (table is null)
            {
                remaining.Add(party);
                continue;
            }
            Check check = Seat(party.Party, party.Size, table);
            Emit("SEATED", party.Party, party.Size, "table", table.Number, "server",
                 check.Server.Name, "waited", now - party.Joined);
        }
        waiting.Clear();
        waiting.AddRange(remaining);
    }

    private static Amounts Calculate(Check check)
    {
        int subtotal = check.Active().Sum(line => line.Amount);
        int discount = Rounded(subtotal, check.Discount);
        int after = subtotal - discount;
        int service = check.Size >= 6 ? Rounded(after, 18) : 0;
        int tax = Rounded(after, 8);
        int total = after + service + tax;
        return new Amounts(subtotal, discount, service, tax, total, total - check.Paid);
    }

    private void Close(Check check)
    {
        Amounts amounts = Calculate(check);
        turns++;
        stay += now - check.Seated;
        foreach (OrderLine line in check.Active()) sales[line.Course] += line.Amount;
        totals["subtotal"] += amounts.Subtotal;
        totals["discount"] += amounts.Discount;
        totals["service"] += amounts.Service;
        totals["tax"] += amounts.Tax;
        totals["total"] += amounts.Total;
        check.Server.Sales += amounts.Total;
        check.Closed = true;
        check.Table.Check = null;
        Emit("FREE", "table", check.Table.Number, check.Party, "stayed", now - check.Seated);
        ProcessWaiting();
    }

    private static void Start(Station station, int time)
    {
        while (station.Up && station.Queue.Count > 0 &&
               station.Cooking.Count < station.Capacity)
        {
            OrderLine line = station.Queue[0];
            station.Queue.RemoveAt(0);
            line.State = "COOKING";
            line.Ready = time + line.Prep;
            line.Started = true;
            station.Cooking.Add(line);
        }
    }

    private void Tick(int minutes)
    {
        int end = now + minutes;
        Emit("TICK", Clock(end));
        while (true)
        {
            List<OrderLine> cooking = StationNames.SelectMany(name => stations[name].Cooking).ToList();
            if (cooking.Count == 0) break;
            int time = cooking.Min(line => line.Ready);
            if (time > end) break;
            foreach (string name in StationNames)
            {
                Station station = stations[name];
                List<OrderLine> finished = station.Cooking
                    .Where(line => line.Ready == time).OrderBy(line => line.Number).ToList();
                station.Cooking.RemoveAll(line => line.Ready == time);
                foreach (OrderLine line in finished)
                {
                    line.State = "READY";
                    station.Tickets.Add(time - line.Fire);
                    Emit("READY", Clock(time), name, "#" + line.Number, line.Item,
                         "x" + line.Quantity, "table", line.Check.Table.Number, "seat", line.Seat);
                }
            }
            foreach (string name in StationNames) Start(stations[name], time);
        }
        now = end;
    }

    private static SortedDictionary<int, int> SeatSubtotals(Check check)
    {
        SortedDictionary<int, int> result = new();
        foreach (OrderLine line in check.Active())
        {
            result[line.Seat] = result.GetValueOrDefault(line.Seat) + line.Amount;
        }
        return result;
    }

    private static Dictionary<int, int> Allocate(IReadOnlyDictionary<int, int> values, int rate)
    {
        Dictionary<int, int> result = values.ToDictionary(
            entry => entry.Key, entry => entry.Value * rate / 100);
        int left = Rounded(values.Values.Sum(), rate) - result.Values.Sum();
        foreach (int seat in values.Keys
                     .OrderByDescending(seat => values[seat] * rate % 100)
                     .ThenBy(seat => seat).Take(left))
        {
            result[seat]++;
        }
        return result;
    }

    private void Bill(Check check)
    {
        Emit("BILL", "table", check.Table.Number, check.Party, "guests", check.Size);
        foreach ((int seat, int subtotal) in SeatSubtotals(check))
        {
            Emit("SEAT", seat, Money(subtotal));
            foreach (OrderLine line in check.Active().Where(line => line.Seat == seat))
            {
                if (line.Reason is null)
                    Emit("#" + line.Number, line.Item, "x" + line.Quantity, Money(line.Amount));
                else
                    Emit("#" + line.Number, line.Item, "x" + line.Quantity, Money(line.Amount),
                         "COMP", line.Reason);
            }
        }
        Amounts amount = Calculate(check);
        Emit("SUBTOTAL", Money(amount.Subtotal));
        if (check.Discount != 0) Emit("DISCOUNT", check.Discount + "%", Money(amount.Discount));
        if (check.Size >= 6) Emit("SERVICE", Money(amount.Service));
        Emit("TAX", Money(amount.Tax));
        Emit("TOTAL", Money(amount.Total));
        if (check.Paid > 0)
        {
            Emit("PAID", Money(check.Paid));
            Emit("DUE", Money(amount.Due));
        }
    }

    private void Report()
    {
        Emit("REPORT", Clock(now));
        Emit("COVERS", covers, "parties", parties);
        Emit("TURNS", turns, "avg_stay", turns > 0 ? (object) (stay / turns) : "-");
        List<object> saleParts = new() { "SALES" };
        foreach (string name in CourseNames)
        {
            saleParts.Add(name);
            saleParts.Add(Money(sales[name]));
        }
        Emit(saleParts.ToArray());
        List<object> totalParts = new() { "TOTALS" };
        foreach (string name in new[] { "subtotal", "discount", "service", "tax", "total" })
        {
            totalParts.Add(name);
            totalParts.Add(Money(totals[name]));
        }
        Emit(totalParts.ToArray());
        Emit("PAYMENTS", "cash", Money(payments["CASH"]), "card", Money(payments["CARD"]),
             "tips", Money(tips));
        Emit("COMPS", comps, Money(compAmount), "VOIDS", voids);
        int rank = 0;
        foreach (KeyValuePair<string, int> entry in served.Where(entry => entry.Value > 0)
                     .OrderByDescending(entry => entry.Value)
                     .ThenBy(entry => entry.Key, StringComparer.Ordinal).Take(3))
        {
            Emit("TOP", ++rank, entry.Key, entry.Value);
        }
        foreach (string name in StationNames)
        {
            Station station = stations[name];
            Emit(name, "tickets", station.Tickets.Count,
                 "avg", station.Tickets.Count > 0
                     ? (object) (station.Tickets.Sum() / station.Tickets.Count) : "-",
                 "max", station.Tickets.Count > 0
                     ? (object) station.Tickets.Max() : "-",
                 "remakes", station.Remakes);
        }
        foreach (Server server in servers)
        {
            Emit("SERVER", server.Name, "tables", Load(server), "parties", server.Parties,
                 "sales", Money(server.Sales), "tips", Money(server.Tips));
        }
    }

    private void Command(string command, string[] args)
    {
        switch (command)
        {
            case "TABLE":
            {
                int number = Number(args[0]);
                if (tables.ContainsKey(number)) Fail("table " + args[0] + " already exists");
                tables[number] = new Table(number, Number(args[1]));
                Emit("TABLE", number, "seats", Number(args[1]));
                ProcessWaiting();
                break;
            }
            case "STAFF":
                if (servers.Any(server => server.Name == args[0]))
                    Fail(args[0] + " is already on duty");
                servers.Add(new Server(args[0]));
                Emit("STAFF", args[0]);
                break;

            case "SEAT":
            {
                Table? seated = tables.Values.FirstOrDefault(table => table.Check?.Party == args[0]);
                if (seated is not null)
                    Fail(args[0] + " is already seated at table " + seated.Number);
                if (waiting.Any(party => party.Party == args[0]))
                    Fail(args[0] + " is already waiting");
                int size = Number(args[1]);
                if (!tables.Values.Any(table => table.Seats >= size))
                    Fail("no table for party of " + size);
                if (servers.Count == 0) Fail("no server on duty");
                Table? table = SelectTable(size);
                if (table is null)
                {
                    waiting.Add(new WaitingParty(args[0], size, now));
                    Emit("WAIT", args[0], size, "position", waiting.Count);
                }
                else
                {
                    Check check = Seat(args[0], size, table);
                    Emit("SEAT", args[0], size, "table", table.Number, "server", check.Server.Name);
                }
                break;
            }
            case "CANCEL":
            {
                int index = waiting.FindIndex(party => party.Party == args[0]);
                if (index < 0) Fail(args[0] + " is not waiting");
                WaitingParty party = waiting[index];
                waiting.RemoveAt(index);
                Emit("CANCEL", party.Party, party.Size, "waited", now - party.Joined);
                break;
            }
            case "MOVE":
            {
                Table source = RequireTable(args[0]);
                Table destination = RequireTable(args[1]);
                if (source.Check is null) Fail("table " + args[0] + " is free");
                if (destination.Check is not null) Fail("table " + args[1] + " is occupied");
                Check check = source.Check!;
                if (destination.Seats < check.Size)
                    Fail("table " + args[1] + " is too small for " + check.Party);
                source.Check = null;
                destination.Check = check;
                check.Table = destination;
                Emit("MOVE", check.Party, "table", source.Number, "->", destination.Number);
                ProcessWaiting();
                break;
            }
            case "MENU":
            {
                RequireStation(args[1]);
                RequireCourse(args[4]);
                menu.TryGetValue(args[0], out MenuItem? previous);
                MenuItem item = new(args[0], args[1], Number(args[2]), Cents(args[3]), args[4])
                {
                    Stock = previous?.Stock
                };
                menu[args[0]] = item;
                Emit("MENU", previous is null ? "ADD" : "UPDATE", item.Name,
                     item.Station, item.Prep, Money(item.Price), item.Course);
                break;
            }
            case "STOCK":
            {
                MenuItem item = RequireItem(args[0]);
                item.Stock = Number(args[1]);
                Emit("STOCK", item.Name, item.Stock.Value);
                break;
            }
            case "HAPPY":
                happyRate = Number(args[0]);
                happyEnd = now + Number(args[1]);
                Emit("HAPPY", happyRate + "%", "until", Clock(happyEnd));
                break;

            case "ITEMS":
            {
                List<MenuItem> items = menu.Values
                    .OrderBy(item => Array.IndexOf(CourseNames, item.Course))
                    .ThenBy(item => item.Name, StringComparer.Ordinal).ToList();
                Emit("ITEMS", items.Count);
                foreach (MenuItem item in items)
                {
                    Emit(item.Course, item.Name, item.Station, item.Prep,
                         Money(item.Price), item.Stock is null ? "-" : item.Stock.Value);
                }
                break;
            }
            case "ORDER":
            {
                Check check = RequireCheck(args[0]);
                Unlocked(check);
                int seat = Number(args[1]);
                if (seat > check.Size) Fail("seat " + seat + " out of range for table " + args[0]);
                MenuItem item = RequireItem(args[2]);
                int quantity = Number(args[3]);
                if (item.Stock is not null && item.Stock.Value < quantity)
                    Fail("only " + item.Stock.Value + " " + item.Name + " left");
                bool happy = item.Course == "DRINK" && now < happyEnd;
                int price = item.Price - (happy ? Rounded(item.Price, happyRate) : 0);
                OrderLine line = new(lines.Count + 1, check, seat, item, quantity, price);
                lines.Add(line);
                check.Lines.Add(line);
                List<object> parts = new()
                {
                    "ORDER", "#" + line.Number, "table", check.Table.Number, "seat", seat,
                    item.Name, "x" + quantity, Money(line.Amount)
                };
                if (happy) parts.Add("HAPPY");
                Emit(parts.ToArray());
                if (item.Stock is not null)
                {
                    item.Stock -= quantity;
                    if (item.Stock == 0) Emit("SOLDOUT", item.Name);
                }
                break;
            }
            case "FIRE":
            {
                Check check = RequireCheck(args[0]);
                RequireCourse(args[1]);
                List<OrderLine> firing = check.Lines
                    .Where(line => line.Course == args[1] && line.State == "ORDERED").ToList();
                if (firing.Count == 0)
                    Fail("nothing to fire for " + args[1] + " at table " + args[0]);
                string[] orderedCourses = { "STARTER", "MAIN", "DESSERT" };
                int position = Array.IndexOf(orderedCourses, args[1]);
                for (int i = 0; i < position; ++i)
                {
                    string earlier = orderedCourses[i];
                    if (check.Lines.Any(line => line.Course == earlier && line.State == "ORDERED"))
                        Fail("fire " + earlier + " first");
                }
                List<object> parts = new() { "FIRE", "table", check.Table.Number, args[1] };
                foreach (OrderLine line in firing)
                {
                    line.State = "QUEUED";
                    line.Fire = now;
                    stations[line.Station].Queue.Add(line);
                    parts.Add("#" + line.Number);
                }
                Emit(parts.ToArray());
                foreach (string name in StationNames) Start(stations[name], now);
                break;
            }
            case "TICK":
                Tick(Number(args[0]));
                break;

            case "SERVE":
            {
                Check check = RequireCheck(args[0]);
                List<OrderLine> ready = check.Lines.Where(line => line.State == "READY").ToList();
                if (ready.Count == 0) Fail("nothing ready for table " + args[0]);
                List<object> parts = new() { "SERVE", "table", check.Table.Number };
                foreach (OrderLine line in ready)
                {
                    line.State = "SERVED";
                    served[line.Item] = served.GetValueOrDefault(line.Item) + line.Quantity;
                    parts.Add("#" + line.Number);
                }
                Emit(parts.ToArray());
                break;
            }
            case "RUSH":
            {
                OrderLine line = RequireLine(args[0]);
                if (line.State != "QUEUED") Fail("#" + line.Number + " is not queued");
                Station station = stations[line.Station];
                station.Queue.Remove(line);
                station.Queue.Insert(0, line);
                Emit("RUSH", "#" + line.Number, line.Station);
                break;
            }
            case "REMAKE":
            {
                OrderLine line = RequireLine(args[0]);
                if (line.Check.Closed) Fail("#" + line.Number + " is on a closed check");
                if (line.State != "READY" && line.State != "SERVED")
                    Fail("#" + line.Number + " is not ready or served");
                line.State = "QUEUED";
                line.Fire = now;
                Station station = stations[line.Station];
                station.Queue.Insert(0, line);
                station.Remakes++;
                Emit("REMAKE", "#" + line.Number, line.Item, line.Station);
                Start(station, now);
                break;
            }
            case "VOID":
            {
                OrderLine line = RequireLine(args[0]);
                if (line.State == "VOID") Fail("#" + line.Number + " is already void");
                if (line.Started) Fail("#" + line.Number + " has already started");
                if (line.State == "QUEUED") stations[line.Station].Queue.Remove(line);
                line.State = "VOID";
                MenuItem item = menu[line.Item];
                if (item.Stock is not null) item.Stock += line.Quantity;
                voids++;
                Emit("VOID", "#" + line.Number, line.Item, "x" + line.Quantity);
                break;
            }
            case "STATION":
            {
                Station station = RequireStation(args[0]);
                if (args[1] == "DOWN" && !station.Up)
                    Fail("station " + station.Name + " is already down");
                if (args[1] == "UP" && station.Up)
                    Fail("station " + station.Name + " is not down");
                station.Up = args[1] == "UP";
                if (station.Up) Start(station, now);
                Emit("STATION", station.Name, args[1]);
                break;
            }
            case "COMP":
            case "TRANSFER":
            {
                OrderLine line = RequireLine(args[0]);
                Modifiable(line);
                if (command == "COMP")
                {
                    if (line.Reason is not null)
                        Fail("#" + line.Number + " is already comped");
                    int amount = line.Amount;
                    Emit("COMP", "#" + line.Number, line.Item, Money(amount), args[1]);
                    comps++;
                    compAmount += amount;
                    line.Reason = args[1];
                }
                else
                {
                    int seat = Number(args[1]);
                    if (seat > line.Check.Size)
                        Fail("seat " + seat + " out of range for table " + line.Check.Table.Number);
                    if (seat == line.Seat)
                        Fail("#" + line.Number + " is already on seat " + seat);
                    Emit("TRANSFER", "#" + line.Number, "seat", line.Seat, "->", seat);
                    line.Seat = seat;
                }
                break;
            }
            case "DISCOUNT":
            {
                Check check = RequireCheck(args[0]);
                Unlocked(check);
                check.Discount = Number(args[1]);
                Emit("DISCOUNT", "table", check.Table.Number, check.Discount + "%");
                break;
            }
            case "BILL":
                Bill(RequireCheck(args[0]));
                break;

            case "SPLIT":
            {
                Check check = RequireCheck(args[0]);
                Amounts amount = Calculate(check);
                if (amount.Due == 0)
                    Fail("nothing to split for table " + args[0]);
                if (args[1] == "EVEN")
                {
                    int count = Number(args[2]);
                    if (count > check.Size)
                        Fail("cannot split table " + args[0] + " " + count + " ways");
                    Emit("SPLIT", "table", check.Table.Number, "EVEN", count, "due", Money(amount.Due));
                    int quotient = amount.Due / count;
                    int remainder = amount.Due % count;
                    for (int i = 1; i <= count; ++i)
                        Emit("PAYER", i, Money(quotient + (i <= remainder ? 1 : 0)));
                }
                else
                {
                    if (check.Paid > 0) Fail("table " + args[0] + " has payments");
                    SortedDictionary<int, int> values = SeatSubtotals(check);
                    Dictionary<int, int> discounts = Allocate(values, check.Discount);
                    Dictionary<int, int> after = values.ToDictionary(
                        entry => entry.Key, entry => entry.Value - discounts[entry.Key]);
                    Dictionary<int, int> services = Allocate(after, check.Size >= 6 ? 18 : 0);
                    Dictionary<int, int> taxes = Allocate(after, 8);
                    Emit("SPLIT", "table", check.Table.Number, "BYSEAT", "total", Money(amount.Total));
                    foreach ((int seat, int subtotal) in values)
                    {
                        Emit("SEAT", seat, "subtotal", Money(subtotal),
                             "discount", Money(discounts[seat]), "service", Money(services[seat]),
                             "tax", Money(taxes[seat]),
                             "total", Money(after[seat] + services[seat] + taxes[seat]));
                    }
                }
                break;
            }
            case "PAY":
            {
                Check check = RequireCheck(args[0]);
                if (args[1] != "CASH" && args[1] != "CARD")
                    Fail("unknown method " + args[1]);
                Unserved(check);
                int due = Calculate(check).Due;
                if (due == 0) Fail("nothing to pay for table " + args[0]);
                int value = Cents(args[2]);
                int applied = Math.Min(value, due);
                check.Paid += applied;
                payments[args[1]] += applied;
                if (value < due)
                {
                    Emit("PAY", "table", check.Table.Number, args[1], Money(value),
                         "remaining", Money(due - value));
                }
                else
                {
                    Emit("PAY", "table", check.Table.Number, args[1], Money(value),
                         args[1] == "CASH" ? "change" : "tip", Money(value - due));
                    if (args[1] == "CARD")
                    {
                        tips += value - due;
                        check.Server.Tips += value - due;
                    }
                    Close(check);
                }
                break;
            }
            case "CLOSE":
            {
                Check check = RequireCheck(args[0]);
                Unserved(check);
                int due = Calculate(check).Due;
                if (due != 0) Fail("table " + args[0] + " still owes " + Money(due));
                Close(check);
                break;
            }
            case "STATUS":
            {
                Check check = RequireCheck(args[0]);
                Emit("STATUS", "table", check.Table.Number, check.Party, "guests",
                     check.Size, "since", Clock(check.Seated));
                foreach (OrderLine line in check.Lines)
                {
                    List<object> parts = new()
                    {
                        "#" + line.Number, "seat", line.Seat, line.Item,
                        "x" + line.Quantity, line.Course, line.State
                    };
                    if (line.State == "COOKING")
                    {
                        parts.Add("until");
                        parts.Add(Clock(line.Ready));
                    }
                    if (line.Reason is not null)
                    {
                        parts.Add("COMP");
                        parts.Add(line.Reason);
                    }
                    Emit(parts.ToArray());
                }
                break;
            }
            case "KITCHEN":
            {
                Emit("KITCHEN", Clock(now));
                foreach (string name in StationNames)
                {
                    Station station = stations[name];
                    string cooking = string.Join(" ", station.Cooking
                        .OrderBy(line => line.Ready).ThenBy(line => line.Number)
                        .Select(line => "#" + line.Number + "@" + Clock(line.Ready)));
                    string queue = string.Join(" ", station.Queue.Select(line => "#" + line.Number));
                    Emit(name, station.Up ? "up" : "down", "cooking",
                         cooking.Length > 0 ? cooking : "-", "queue",
                         queue.Length > 0 ? queue : "-");
                }
                break;
            }
            case "FLOOR":
            {
                List<Table> ordered = tables.Values.OrderBy(table => table.Number).ToList();
                int free = ordered.Count(table => table.Check is null);
                Emit("FLOOR", Clock(now), "free", free, "seated", ordered.Count - free,
                     "waiting", waiting.Count);
                foreach (Table table in ordered)
                {
                    Check? check = table.Check;
                    if (check is null)
                    {
                        Emit("table", table.Number, "seats", table.Seats, "free");
                        continue;
                    }
                    List<object> parts = new()
                    {
                        "table", table.Number, "seats", table.Seats, check.Party,
                        "guests", check.Size, "server", check.Server.Name,
                        "since", Clock(check.Seated), "items", check.Active().Count(),
                        "total", Money(Calculate(check).Total)
                    };
                    if (check.Paid > 0)
                    {
                        parts.Add("paid");
                        parts.Add(Money(check.Paid));
                    }
                    Emit(parts.ToArray());
                }
                for (int i = 0; i < waiting.Count; ++i)
                {
                    WaitingParty party = waiting[i];
                    Emit("WAITING", i + 1, party.Party, party.Size, "since", Clock(party.Joined));
                }
                break;
            }
            case "REPORT":
                Report();
                break;
        }
    }

    public void Execute(string text)
    {
        string[] tokens = text.Split(' ');
        try
        {
            Command(tokens[0], tokens[1..]);
        }
        catch (CommandError error)
        {
            Emit("ERROR", error.Message);
        }
    }

    public void Print()
    {
        foreach (string line in output) Console.WriteLine(line);
    }
}

static class Program
{
    private static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!, CultureInfo.InvariantCulture);
        Restaurant restaurant = new();
        for (int i = 0; i < count; ++i) restaurant.Execute(Console.ReadLine()!);
        restaurant.Print();
    }
}
