using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Problem(string message) : Exception("error: " + message) { }

record Stop(int X, int Y, int Demand, int Service, int Open, int Close);

record Saving(int A, int B, int Value);

record Run(int Returned, int Waiting, int Service, int Violations, int Lateness, List<string> Lines);

class Program
{
    readonly SortedDictionary<int, Stop> stops = [];
    bool depot;
    int depotX, depotY, departure = 480, capacity;
    List<int>? tour;
    List<List<int>>? routes;

    static void Fail(string message) => throw new Problem(message);

    static int Time(string text) => int.Parse(text[..2]) * 60 + int.Parse(text[3..]);

    static string Clock(int value) => $"{value / 60:00}:{value % 60:00}";

    static string Location(int id) => id == 0 ? "D" : id.ToString();

    static string Sequence(List<int> route) => "D-" + string.Join("-", route) + "-D";

    static int At(List<int> route, int position) => position < 0 || position >= route.Count ? 0 : route[position];

    int Distance(int a, int b)
    {
        int ax = a == 0 ? depotX : stops[a].X, ay = a == 0 ? depotY : stops[a].Y;
        int bx = b == 0 ? depotX : stops[b].X, by = b == 0 ? depotY : stops[b].Y;
        return Math.Abs(ax - bx) + Math.Abs(ay - by);
    }

    int Length(List<int> route)
    {
        int total = 0, previous = 0;
        foreach (int id in route)
        {
            total += Distance(previous, id);
            previous = id;
        }
        return total + Distance(previous, 0);
    }
    int Load(List<int> route) => route.Sum(id => stops[id].Demand);
    int PlanLength() => routes!.Sum(Length);

    void Normalize()
    {
        routes!.RemoveAll(r => r.Count == 0);
        foreach (List<int> r in routes) if (r[0] > r[^1]) r.Reverse();
        routes.Sort((a, b) => a.Min().CompareTo(b.Min()));
    }

    void NetworkCheck()
    {
        if (!depot) Fail("no depot");
        if (stops.Count == 0) Fail("no stops");
    }

    void TourCheck()
    {
        if (tour == null) Fail("no tour");
    }

    void PlanCheck()
    {
        if (routes == null) Fail("no plan");
    }

    void CapacityCheck(int q)
    {
        foreach ((int id, Stop p) in stops) if (p.Demand > q) Fail($"stop {id} demand {p.Demand} exceeds capacity {q}");
    }
    List<string> RouteLines() => routes!.Select((r, i) => $"route {i + 1}: {Sequence(r)} load {Load(r)} length {Length(r)}").ToList();

    Run Simulate(List<int> route)
    {
        int t = departure, previous = 0, waiting = 0, service = 0, violations = 0, lateness = 0;
        List<string> lines = [];
        foreach (int id in route)
        {
            Stop p = stops[id];
            int arrival = t + Distance(previous, id), wait = p.Open < 0 ? 0 : Math.Max(0, p.Open - arrival);
            int begin = arrival + wait, late = p.Close < 0 ? 0 : Math.Max(0, arrival - p.Close);
            t = begin + p.Service;
            waiting += wait;
            service += p.Service;
            lateness += late;
            if (late > 0) violations++;
            lines.Add($"{id} arrive {Clock(arrival)} wait {wait} begin {Clock(begin)} leave {Clock(t)} " + (late > 0 ? $"late {late}" : "ok"));
            previous = id;
        }
        t += Distance(previous, 0);
        lines.Add($"return {Clock(t)}, travel {Length(route)}, wait {waiting}, service {service}, violations {violations}, lateness {lateness}");
        return new(t, waiting, service, violations, lateness, lines);
    }

    int TwoOpt(List<int> route, List<string>? output)
    {
        int moves = 0;
        while (true)
        {
            bool moved = false;
            for (int i = 0; i + 1 < route.Count; i++) for (int j = i + 1; j < route.Count; j++)
            {
                int a = route[i], b = route[j];
                int gain = Distance(At(route, i - 1), a) + Distance(b, At(route, j + 1)) - Distance(At(route, i - 1), b) - Distance(a, At(route, j + 1));
                if (gain > 0)
                {
                    output?.Add($"reverse {a}..{b} gain {gain}");
                    route.Reverse(i, j - i + 1);
                    moves++;
                    moved = true;
                    goto ScanDone;
                }
            }
            ScanDone: if (!moved) return moves;
        }
    }

    List<int> Exact()
    {
        List<int> ids = [.. stops.Keys];
        int n = ids.Count, full = (1 << n) - 1;
        int[,] memo = new int[1 << n, n + 1];
        for (int mask = 0; mask <= full; mask++) for (int last = 0; last <= n; last++) memo[mask, last] = -1;
        int Best(int mask, int last)
        {
            if (mask == full) return Distance(last == n ? 0 : ids[last], 0);
            if (memo[mask, last] >= 0) return memo[mask, last];
            int value = int.MaxValue, previous = last == n ? 0 : ids[last];
            for (int i = 0; i < n; i++) if ((mask & (1 << i)) == 0) value = Math.Min(value, Distance(previous, ids[i]) + Best(mask | (1 << i), i));
            return memo[mask, last] = value;
        }
        List<int> result = [];
        int used = 0, current = n;
        while (used != full) for (int i = 0; i < n; i++) if ((used & (1 << i)) == 0 && Distance(current == n ? 0 : ids[current], ids[i]) + Best(used | (1 << i), i) == Best(used, current))
        {
            result.Add(ids[i]);
            used |= 1 << i;
            current = i;
            break;
        }
        return result;
    }

    int AngleCompare(int a, int b)
    {
        int ax = stops[a].X - depotX, ay = stops[a].Y - depotY, bx = stops[b].X - depotX, by = stops[b].Y - depotY;
        bool az = ax == 0 && ay == 0, bz = bx == 0 && by == 0;
        if (az || bz) return az == bz ? a.CompareTo(b) : az ? -1 : 1;
        int ah = ay > 0 || ay == 0 && ax > 0 ? 0 : 1, bh = by > 0 || by == 0 && bx > 0 ? 0 : 1;
        if (ah != bh) return ah.CompareTo(bh);
        int cross = ax * by - ay * bx;
        if (cross != 0) return cross > 0 ? -1 : 1;
        int order = Distance(0, a).CompareTo(Distance(0, b));
        return order == 0 ? a.CompareTo(b) : order;
    }

    List<string> Bound()
    {
        List<int> entered = [0];
        SortedSet<int> remaining = new(stops.Keys);
        List<string> edges = [];
        int mst = 0;
        while (remaining.Count != 0)
        {
            int best = int.MaxValue, selected = 0, parent = 0;
            foreach (int c in remaining) foreach (int p in entered) if (Distance(p, c) < best)
            {
                best = Distance(p, c);
                selected = c;
                parent = p;
            }
            entered.Add(selected);
            remaining.Remove(selected);
            mst += best;
            edges.Add($"{Location(parent)}-{selected}");
        }
        int oneTree;
        if (stops.Count == 1) oneTree = 2 * Distance(0, stops.Keys.First());
        else
        {
            int tree = 0;
            HashSet<int> included = [stops.Keys.First()];
            while (included.Count < stops.Count)
            {
                int best = int.MaxValue, chosen = 0;
                foreach (int c in stops.Keys) if (!included.Contains(c)) foreach (int p in included) if (Distance(p, c) < best)
                {
                    best = Distance(p, c);
                    chosen = c;
                }
                included.Add(chosen);
                tree += best;
            }
            int[] distances = stops.Keys.Select(p => Distance(0, p)).Order().ToArray();
            oneTree = tree + distances[0] + distances[1];
        }
        int lower = Math.Max(mst, oneTree);
        List<string> output = [$"mst: {string.Join(" ", edges)} (length {mst})", $"bound: mst {mst}, one-tree {oneTree}, best {lower}"];
        if (tour == null) output.Add("gap: no tour");
        else
        {
            int value = Length(tour);
            long rounded = lower == 0 ? 0 : (2000L * (value - lower) + lower) / (2L * lower);
            output.Add($"gap: tour {value}, {rounded / 10}.{rounded % 10}%");
        }
        return output;
    }

    List<string> ImprovePlan(string command)
    {
        List<string> output = [];
        int initial = PlanLength(), oldCount = routes!.Count, moves = 0;
        while (true)
        {
            bool moved = false;
            for (int r = 0; r < routes.Count; r++)
            {
                List<int> a = routes[r];
                if (command == "RELOCATE")
                {
                    for (int p = 0; p < a.Count; p++) for (int t = 0; t < routes.Count; t++) if (t != r)
                    {
                        List<int> b = routes[t];
                        int c = a[p];
                        if (Load(b) + stops[c].Demand > capacity) continue;
                        for (int j = 0; j <= b.Count; j++)
                        {
                            int u = At(b, j - 1), v = At(b, j);
                            int gain = Distance(At(a, p - 1), c) + Distance(c, At(a, p + 1)) - Distance(At(a, p - 1), At(a, p + 1)) - Distance(u, c) - Distance(c, v) + Distance(u, v);
                            if (gain > 0)
                            {
                                output.Add($"relocate {c} from route {r + 1} to route {t + 1} after {Location(u)} gain {gain}");
                                a.RemoveAt(p);
                                b.Insert(j, c);
                                moved = true;
                                goto ScanDone;
                            }
                        }
                    }
                }
                else for (int t = r + 1; t < routes.Count; t++)
                {
                    List<int> b = routes[t];
                    if (command == "EXCHANGE")
                    {
                        for (int p = 0; p < a.Count; p++) for (int j = 0; j < b.Count; j++)
                        {
                            int c = a[p], e = b[j];
                            if (Load(a) - stops[c].Demand + stops[e].Demand > capacity || Load(b) - stops[e].Demand + stops[c].Demand > capacity) continue;
                            List<int> x = [.. a], y = [.. b];
                            x[p] = e;
                            y[j] = c;
                            int gain = Length(a) + Length(b) - Length(x) - Length(y);
                            if (gain > 0)
                            {
                                output.Add($"exchange {c} (route {r + 1}) with {e} (route {t + 1}) gain {gain}");
                                routes[r] = x;
                                routes[t] = y;
                                moved = true;
                                goto ScanDone;
                            }
                        }
                    }
                    else
                    {
                        for (int i = 0; i <= a.Count; i++) for (int j = 0; j <= b.Count; j++)
                        {
                            List<int> x = a.Take(i).Concat(b.Skip(j)).ToList(), y = b.Take(j).Concat(a.Skip(i)).ToList();
                            if (Load(x) > capacity || Load(y) > capacity) continue;
                            int gain = Distance(At(a, i - 1), At(a, i)) + Distance(At(b, j - 1), At(b, j)) - Distance(At(a, i - 1), At(b, j)) - Distance(At(b, j - 1), At(a, i));
                            if (gain > 0)
                            {
                                output.Add($"cross route {r + 1} after {Location(At(a, i - 1))} with route {t + 1} after {Location(At(b, j - 1))} gain {gain}");
                                routes[r] = x;
                                routes[t] = y;
                                moved = true;
                                goto ScanDone;
                            }
                        }
                    }
                }
            }
            ScanDone: if (!moved) break;
            moves++;
            Normalize();
        }
        output.Add(command.ToLowerInvariant() + $": moves {moves}" + (command == "EXCHANGE" ? "" : $", routes {oldCount} -> {routes.Count}") + $", length {initial} -> {PlanLength()}");
        return output;
    }

    List<string> Command(string line)
    {
        string[] w = line.Split(' ');
        string c = w[0];
        List<string> output = [];
        switch (c)
        {
            case "DEPOT":
                depot = true;
                depotX = int.Parse(w[1]);
                depotY = int.Parse(w[2]);
                output.Add($"depot at ({depotX},{depotY})");
                break;
            case "START":
                departure = Time(w[1]);
                output.Add("start " + Clock(departure));
                break;
            case "STOP":
            {
                int id = int.Parse(w[1]);
                if (stops.ContainsKey(id)) Fail($"stop {id} already exists");
                int open = w.Length == 8 ? Time(w[6]) : -1, close = w.Length == 8 ? Time(w[7]) : -1;
                if (open > close) Fail("invalid window");
                stops[id] = new(int.Parse(w[2]), int.Parse(w[3]), int.Parse(w[4]), int.Parse(w[5]), open, close);
                tour = null;
                routes = null;
                output.Add($"stop {id} added");
                break;
            }
            case "REMOVE":
            {
                int id = int.Parse(w[1]);
                if (!stops.ContainsKey(id)) Fail("unknown stop " + id);
                stops.Remove(id);
                if (stops.Count == 0)
                {
                    tour = null;
                    routes = null;
                }
                else
                {
                    tour?.Remove(id);
                    if (routes != null)
                    {
                        foreach (List<int> r in routes) r.Remove(id);
                        Normalize();
                    }
                }
                output.Add($"stop {id} removed");
                break;
            }
            case "LIST":
                output.Add(depot ? $"depot ({depotX},{depotY})" : "depot none");
                output.Add("start " + Clock(departure));
                output.Add("stops " + stops.Count);
                foreach ((int id, Stop p) in stops) output.Add($"{id} at ({p.X},{p.Y}) demand {p.Demand} service {p.Service} window " + (p.Open < 0 ? "none" : Clock(p.Open) + "-" + Clock(p.Close)));
                break;
            case "MATRIX":
            {
                if (!depot) Fail("no depot");
                List<int> ids = [0, .. stops.Keys];
                int width = 1;
                foreach (int a in ids) foreach (int b in ids) width = Math.Max(width, Math.Max(Location(a).Length, Distance(a, b).ToString().Length));
                output.Add(new string(' ', width) + string.Concat(ids.Select(id => " " + Location(id).PadLeft(width))));
                foreach (int a in ids) output.Add(Location(a).PadLeft(width) + string.Concat(ids.Select(b => " " + Distance(a, b).ToString().PadLeft(width))));
                break;
            }
            case "ORDER":
            {
                NetworkCheck();
                List<int> order = w.Skip(1).Select(int.Parse).ToList();
                foreach (int id in order) if (!stops.ContainsKey(id)) Fail("unknown stop " + id);
                HashSet<int> seen = [];
                foreach (int id in order) if (!seen.Add(id)) Fail("duplicate stop " + id);
                if (order.Count != stops.Count) Fail($"order has {order.Count} stops, expected {stops.Count}");
                tour = [.. order];
                output.Add($"order: {Sequence(tour)} length {Length(tour)}");
                break;
            }
            case "NEAREST":
            case "INSERTION":
            case "EXACT":
            {
                NetworkCheck();
                if (c == "EXACT")
                {
                    if (stops.Count > 10) Fail($"too many stops for exact ({stops.Count})");
                    tour = Exact();
                }
                else
                {
                    tour = [];
                    while (tour.Count < stops.Count)
                    {
                        int best = int.MaxValue, chosen = 0, position = 0;
                        foreach (int id in stops.Keys) if (!tour.Contains(id))
                        {
                            if (c == "NEAREST")
                            {
                                int value = Distance(tour.Count == 0 ? 0 : tour[^1], id);
                                if (value < best)
                                {
                                    best = value;
                                    chosen = id;
                                    position = tour.Count;
                                }
                            }
                            else for (int j = 0; j <= tour.Count; j++)
                            {
                                int value = Distance(At(tour, j - 1), id) + Distance(id, At(tour, j)) - Distance(At(tour, j - 1), At(tour, j));
                                if (value < best)
                                {
                                    best = value;
                                    chosen = id;
                                    position = j;
                                }
                            }
                        }
                        tour.Insert(position, chosen);
                    }
                }
                output.Add(c.ToLowerInvariant() + $": {Sequence(tour)} length {Length(tour)}");
                break;
            }
            case "TOUR":
                TourCheck();
                output.Add($"tour: {Sequence(tour!)} length {Length(tour!)}");
                break;
            case "TWOOPT":
            case "OROPT":
            case "SWAP":
            {
                TourCheck();
                int initial = Length(tour!), moves = 0;
                if (c == "TWOOPT") moves = TwoOpt(tour!, output);
                else while (true)
                {
                    bool moved = false;
                    if (c == "OROPT")
                    {
                        for (int size = 1; size <= 3; size++) for (int i = 0; i + size <= tour!.Count; i++)
                        {
                            List<int> segment = tour.GetRange(i, size), rest = [.. tour];
                            rest.RemoveRange(i, size);
                            for (int j = 0; j <= rest.Count; j++) if (j != i)
                            {
                                List<int> next = [.. rest];
                                next.InsertRange(j, segment);
                                int gain = Length(tour) - Length(next);
                                if (gain > 0)
                                {
                                    output.Add($"move {string.Join("-", segment)} after {Location(At(rest, j - 1))} gain {gain}");
                                    tour = next;
                                    moves++;
                                    moved = true;
                                    goto ScanDone;
                                }
                            }
                        }
                    }
                    else
                    {
                        for (int i = 0; i + 1 < tour!.Count; i++) for (int j = i + 1; j < tour.Count; j++)
                        {
                            List<int> next = [.. tour];
                            (next[i], next[j]) = (next[j], next[i]);
                            int gain = Length(tour) - Length(next);
                            if (gain > 0)
                            {
                                output.Add($"swap {tour[i]} and {tour[j]} gain {gain}");
                                tour = next;
                                moves++;
                                moved = true;
                                goto ScanDone;
                            }
                        }
                    }
                    ScanDone: if (!moved) break;
                }
                string title = c == "TWOOPT" ? "twoopt" : c == "OROPT" ? "oropt" : "swap";
                output.Add($"{title}: moves {moves}, length {initial} -> {Length(tour!)}");
                break;
            }
            case "TIMECHECK":
            {
                List<int> route;
                if (w.Length == 1)
                {
                    TourCheck();
                    route = tour!;
                    output.Add("timecheck tour depart " + Clock(departure));
                }
                else
                {
                    PlanCheck();
                    int r = int.Parse(w[1]);
                    if (r > routes!.Count) Fail("no route " + r);
                    route = routes[r - 1];
                    output.Add($"timecheck route {r} depart {Clock(departure)}");
                }
                output.AddRange(Simulate(route).Lines);
                break;
            }
            case "BOUND":
                NetworkCheck();
                output = Bound();
                break;
            case "VRP":
            case "SPLIT":
            case "SWEEP":
            {
                if (c == "SPLIT") TourCheck();
                else NetworkCheck();
                int q = int.Parse(w[1]);
                CapacityCheck(q);
                if (c == "VRP" && w.Length == 3) foreach (int id in stops.Keys) if (2 * Distance(0, id) > int.Parse(w[2])) Fail($"stop {id} too far for limit {w[2]}");
                List<List<int>> next = [];
                int merges = 0;
                if (c == "VRP")
                {
                    foreach (int id in stops.Keys) next.Add([id]);
                    List<Saving> savings = [];
                    foreach (int a in stops.Keys) foreach (int b in stops.Keys.Where(b => b > a))
                    {
                        int saving = Distance(0, a) + Distance(0, b) - Distance(a, b);
                        if (saving > 0) savings.Add(new(a, b, saving));
                    }
                    foreach (Saving saving in savings.OrderByDescending(s => s.Value).ThenBy(s => s.A).ThenBy(s => s.B))
                    {
                        List<int> a = next.First(r => r.Contains(saving.A)), b = next.First(r => r.Contains(saving.B));
                        if (a == b || a[0] != saving.A && a[^1] != saving.A || b[0] != saving.B && b[^1] != saving.B || Load(a) + Load(b) > q) continue;
                        List<int> x = [.. a], y = [.. b];
                        if (x[0] == saving.A) x.Reverse();
                        if (y[^1] == saving.B) y.Reverse();
                        x.AddRange(y);
                        if (w.Length == 3 && Length(x) > int.Parse(w[2])) continue;
                        next.Remove(a);
                        next.Remove(b);
                        next.Add(x);
                        merges++;
                    }
                }
                else if (c == "SPLIT")
                {
                    int n = tour!.Count;
                    int[] values = Enumerable.Repeat(int.MaxValue, n + 1).ToArray(), previous = new int[n + 1];
                    values[0] = 0;
                    for (int j = 1; j <= n; j++) for (int i = 0; i < j; i++)
                    {
                        List<int> part = tour.GetRange(i, j - i);
                        if (Load(part) <= q && values[i] + Length(part) < values[j])
                        {
                            values[j] = values[i] + Length(part);
                            previous[j] = i;
                        }
                    }
                    for (int j = n; j > 0; j = previous[j]) next.Add(tour.GetRange(previous[j], j - previous[j]));
                }
                else
                {
                    List<int> ids = [.. stops.Keys];
                    ids.Sort(AngleCompare);
                    List<int> route = [];
                    next.Add(route);
                    foreach (int id in ids)
                    {
                        if (Load(route) + stops[id].Demand > q)
                        {
                            route = [];
                            next.Add(route);
                        }
                        route.Add(id);
                    }
                }
                routes = next;
                capacity = q;
                Normalize();
                output.Add(c.ToLowerInvariant() + $": capacity {q}" + (c == "VRP" ? $", merges {merges}" : "") + $", routes {routes.Count}, length {PlanLength()}");
                output.AddRange(RouteLines());
                break;
            }
            case "ROUTES":
                PlanCheck();
                output.Add($"plan: capacity {capacity}, routes {routes!.Count}, length {PlanLength()}");
                output.AddRange(RouteLines());
                break;
            case "RELOCATE":
            case "EXCHANGE":
            case "CROSS":
                PlanCheck();
                output = ImprovePlan(c);
                break;
            case "ROUTEOPT":
            {
                PlanCheck();
                int initial = PlanLength();
                for (int i = 0; i < routes!.Count; i++)
                {
                    List<int> route = routes[i];
                    int before = Length(route), moves = TwoOpt(route, null);
                    output.Add($"route {i + 1}: moves {moves}, length {before} -> {Length(route)}");
                }
                Normalize();
                output.Add($"routeopt: length {initial} -> {PlanLength()}");
                break;
            }
            case "REPORT":
            {
                int demand = stops.Values.Sum(p => p.Demand), service = stops.Values.Sum(p => p.Service);
                output.Add($"report: stops {stops.Count}, demand {demand}, service {service}, windows {stops.Values.Count(p => p.Open >= 0)}");
                if (tour == null) output.Add("tour: none");
                else
                {
                    Run run = Simulate(tour);
                    output.Add($"tour: length {Length(tour)}, return {Clock(run.Returned)}, violations {run.Violations}, lateness {run.Lateness}");
                }
                if (routes == null) output.Add("plan: none");
                else
                {
                    int returned = 0, violations = 0, lateness = 0;
                    foreach (List<int> route in routes)
                    {
                        Run run = Simulate(route);
                        returned = Math.Max(returned, run.Returned);
                        violations += run.Violations;
                        lateness += run.Lateness;
                    }
                    long denominator = (long)routes.Count * capacity, utilization = (2000L * demand + denominator) / (2 * denominator);
                    output.Add($"plan: capacity {capacity}, routes {routes.Count}, length {PlanLength()}, utilization {utilization / 10}.{utilization % 10}%, return {Clock(returned)}, violations {violations}, lateness {lateness}");
                }
                break;
            }
        }
        return output;
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program optimizer = new();
        int n = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < n; i++)
        {
            try
            {
                foreach (string line in optimizer.Command(Console.ReadLine()!)) Console.WriteLine(line);
            }
            catch (Problem e)
            {
                Console.WriteLine(e.Message);
            }
        }
    }
}
