using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Program
{
    class Problem(string message) : Exception("ERROR " + message) { }

    class Station(string id, int zone, string name)
    {
        public readonly string Id = id, Name = name;
        public readonly int Zone = zone;
        public int Transfer;
        public bool Closed;
        public readonly SortedDictionary<string, int> Walks = new(StringComparer.Ordinal);
    }

    class MetroLine(string id, int first, int last, int headway, List<Station> stops, int[] cumulative)
    {
        public readonly string Id = id;
        public readonly int First = first, Last = last, Headway = headway;
        public readonly List<Station> Stops = [.. stops];
        public readonly int[] Cumulative = (int[])cumulative.Clone();
        public int Delay;
        public bool Suspended;
        public int Total => Cumulative[^1];
        public int Trips => (Last - First) / Headway + 1;
        public Station Stop(int direction, int index) => Stops[direction == 0 ? index : Stops.Count - 1 - index];
        public int Offset(int direction, int index) => direction == 0 ? Cumulative[index] : Total - Cumulative[Stops.Count - 1 - index];
        public int Position(int direction, Station station)
        {
            int index = Stops.IndexOf(station);
            return index < 0 ? -1 : direction == 0 ? index : Stops.Count - 1 - index;
        }
        public int Time(int direction, int index, int train) => First + Delay + train * Headway + Offset(direction, index);
        public int Next(int direction, int index, int ready)
        {
            int start = Time(direction, index, 0), train = ready <= start ? 0 : (ready - start + Headway - 1) / Headway;
            return train < Trips ? train : -1;
        }
    }

    record Segment(string Low, string High);

    record Leg(char Kind, MetroLine? Line, Station? Terminal, Station From, int Departure, Station To, int Arrival, int Stops);

    record Label(int Time, List<Leg> Journey);

    record Departure(int Time, MetroLine Line, int Direction);
    static readonly SortedDictionary<string, Station> Stations = new(StringComparer.Ordinal);
    static readonly SortedDictionary<string, MetroLine> Lines = new(StringComparer.Ordinal);
    static readonly HashSet<Segment> ClosedSegments = [];

    static int[]? prices;

    static int discount, window;

    static void Require(bool valid, string reason)
    {
        if (!valid) throw new Problem(reason);
    }

    static Station GetStation(string id)
    {
        Require(Stations.ContainsKey(id), "unknown station " + id);
        return Stations[id];
    }

    static MetroLine GetLine(string id)
    {
        Require(Lines.ContainsKey(id), "unknown line " + id);
        return Lines[id];
    }

    static int Time(string text) => int.Parse(text[..2]) * 60 + int.Parse(text[3..]);

    static string Clock(int time) => (time / 60).ToString("D2", CultureInfo.InvariantCulture) + ":" + (time % 60).ToString("D2", CultureInfo.InvariantCulture);

    static Segment Pair(Station left, Station right) => StringComparer.Ordinal.Compare(left.Id, right.Id) <= 0 ? new(left.Id, right.Id) : new(right.Id, left.Id);

    static bool Blocked(Station left, Station right) => ClosedSegments.Contains(Pair(left, right));

    static List<Leg> Append(List<Leg> journey, Leg leg) => [.. journey, leg];

    static void Relax(Dictionary<Station, Label> labels, Station destination, int arrival, List<Leg> journey, Leg leg)
    {
        if (!labels.TryGetValue(destination, out Label? before) || before.Time > arrival) labels[destination] = new(arrival, Append(journey, leg));
    }

    static Dictionary<Station, Label> Earliest(Station origin, int departure)
    {
        Dictionary<Station, Label> labels = new() { [origin] = new(departure, []) };
        HashSet<Station> settled = [];
        while (true)
        {
            Station? selected = null;
            foreach (Station station in Stations.Values) if (!settled.Contains(station) && labels.ContainsKey(station) && (selected is null || labels[station].Time < labels[selected].Time)) selected = station;
            if (selected is null) return labels;
            Station u = selected;
            settled.Add(u);
            Label label = labels[u];
            int ready = label.Time + (u == origin ? 0 : u.Transfer);
            foreach (MetroLine line in Lines.Values) if (!line.Suspended && line.Stops.Contains(u)) for (int direction = 0; direction < 2; direction++)
            {
                int i = line.Position(direction, u), last = line.Stops.Count - 1;
                if (i == last) continue;
                int train = line.Next(direction, i, ready);
                if (train < 0) continue;
                int start = line.Time(direction, i, train);
                for (int j = i + 1; j <= last; j++)
                {
                    Station v = line.Stop(direction, j);
                    if (Blocked(line.Stop(direction, j - 1), v)) break;
                    if (v.Closed) continue;
                    int arrival = line.Time(direction, j, train);
                    Relax(labels, v, arrival, label.Journey, new('R', line, line.Stop(direction, last), u, start, v, arrival, j - i));
                }
            }
            foreach (var walk in u.Walks)
            {
                Station v = Stations[walk.Key];
                int arrival = label.Time + walk.Value;
                if (!v.Closed && arrival <= 1440) Relax(labels, v, arrival, label.Journey, new('W', null, null, u, label.Time, v, arrival, 0));
            }
        }
    }

    static void WalkStep(Dictionary<Station, Label> labels, HashSet<Station> origins, HashSet<Station> marked)
    {
        var recorded = origins.ToDictionary(origin => origin, origin => labels[origin]);
        foreach (Station u in Stations.Values) if (origins.Contains(u)) foreach (var walk in u.Walks)
        {
            Label label = recorded[u];
            Station v = Stations[walk.Key];
            int arrival = label.Time + walk.Value;
            if (!v.Closed && arrival <= 1440 && (!labels.ContainsKey(v) || labels[v].Time > arrival))
            {
                labels[v] = new(arrival, Append(label.Journey, new('W', null, null, u, label.Time, v, arrival, 0)));
                marked.Add(v);
            }
        }
    }

    static List<Dictionary<Station, Label>> Rounds(Station origin, int departure)
    {
        List<Dictionary<Station, Label>> result = [];
        Dictionary<Station, Label> previous = new() { [origin] = new(departure, []) };
        HashSet<Station> marked = [origin];
        WalkStep(previous, [origin], marked);
        result.Add(previous);
        while (marked.Count > 0)
        {
            Dictionary<Station, Label> current = new(previous);
            HashSet<Station> updated = [], walks = [];
            foreach (MetroLine line in Lines.Values) if (!line.Suspended) for (int direction = 0; direction < 2; direction++)
            {
                int boarded = -1, boardIndex = -1, boardTime = 0, last = line.Stops.Count - 1;
                List<Leg>? boardJourney = null;
                for (int j = 0; j <= last; j++)
                {
                    Station u = line.Stop(direction, j);
                    if (j > 0 && Blocked(line.Stop(direction, j - 1), u)) boarded = -1;
                    if (u.Closed) continue;
                    if (boarded >= 0)
                    {
                        int arrival = line.Time(direction, j, boarded);
                        if (!current.ContainsKey(u) || current[u].Time > arrival)
                        {
                            current[u] = new(arrival, Append(boardJourney!, new('R', line, line.Stop(direction, last), line.Stop(direction, boardIndex), boardTime, u, arrival, j - boardIndex)));
                            walks.Add(u);
                            updated.Add(u);
                        }
                    }
                    if (j < last && marked.Contains(u))
                    {
                        Label label = previous[u];
                        int ready = label.Time + (u == origin ? 0 : u.Transfer), train = line.Next(direction, j, ready);
                        if (train >= 0 && (boarded < 0 || train < boarded))
                        {
                            boarded = train;
                            boardIndex = j;
                            boardTime = line.Time(direction, j, train);
                            boardJourney = label.Journey;
                        }
                    }
                }
            }
            WalkStep(current, walks, updated);
            result.Add(current);
            previous = current;
            marked = updated;
        }
        return result;
    }

    static int Rides(List<Leg> journey) => journey.Count(leg => leg.Kind == 'R');

    static void PrintJourney(string heading, int departure, Label label)
    {
        Console.WriteLine($"{heading} {Clock(departure)} -> {Clock(label.Time)} total {label.Time - departure} rides {Rides(label.Journey)} walks {label.Journey.Count(leg => leg.Kind == 'W')}");
        int previous = departure;
        foreach (Leg leg in label.Journey)
        {
            if (leg.Kind == 'R') Console.WriteLine($"RIDE {leg.Line!.Id} toward {leg.Terminal!.Id} {leg.From.Id} {Clock(leg.Departure)} -> {leg.To.Id} {Clock(leg.Arrival)} wait {leg.Departure - previous} stops {leg.Stops}");
            else if (leg.Kind == 'W') Console.WriteLine($"WALK {leg.From.Id} {Clock(leg.Departure)} -> {leg.To.Id} {Clock(leg.Arrival)}");
            else Console.WriteLine($"STAY {leg.From.Id} {Clock(leg.Departure)} -> {Clock(leg.Arrival)}");
            previous = leg.Arrival;
        }
    }

    static void SearchCheck(Station origin, Station destination)
    {
        Require(origin != destination, "origin and destination are the same");
        Require(!origin.Closed, "station " + origin.Id + " is closed");
        Require(!destination.Closed, "station " + destination.Id + " is closed");
    }

    static int Direction(MetroLine line, string terminal)
    {
        Require(line.Stops[0].Id == terminal || line.Stops[^1].Id == terminal, terminal + " is not a terminal of line " + line.Id);
        return line.Stops[^1].Id == terminal ? 0 : 1;
    }

    static int Half(int price) => (price + 19) / 20 * 10;

    static void Fare(string heading, Station origin, Station destination, int departure, string fareClass)
    {
        Label? label = Earliest(origin, departure).GetValueOrDefault(destination);
        if (label is null)
        {
            Console.WriteLine(heading + " unreachable");
            return;
        }
        List<string> tickets = [];
        int total = 0, lastRide = -1;
        bool child = fareClass == "CHILD";
        foreach (Leg leg in label.Journey) if (leg.Kind == 'R')
        {
            MetroLine line = leg.Line!;
            int a = line.Stops.IndexOf(leg.From), b = line.Stops.IndexOf(leg.To);
            HashSet<int> zones = [];
            for (int i = Math.Min(a, b); i <= Math.Max(a, b); i++) zones.Add(line.Stops[i].Zone);
            int price = prices![Math.Min(zones.Count, prices.Length) - 1];
            if (child) price = Half(price);
            int reduction = lastRide >= 0 && leg.Departure - lastRide <= window ? Math.Min(price, child ? Half(discount) : discount) : 0;
            int pay = price - reduction;
            total += pay;
            tickets.Add($"TICKET {line.Id} {leg.From.Id} {leg.To.Id} zones {zones.Count} price {price} discount {reduction} pay {pay}");
            lastRide = leg.Arrival;
        }
        Console.WriteLine($"{heading} rides {Rides(label.Journey)} total {total}");
        tickets.ForEach(Console.WriteLine);
    }

    static void Command(string[] w)
    {
        string command = w[0];
        switch (command)
        {
            case "STATION":
                Require(!Stations.ContainsKey(w[1]), "station " + w[1] + " already exists");
                Stations[w[1]] = new(w[1], int.Parse(w[2]), w[3]);
                Console.WriteLine($"STATION {w[1]} zone {w[2]} {w[3]}");
                return;
            case "LINE":
            {
                Require(!Lines.ContainsKey(w[1]), "line " + w[1] + " already exists");
                List<Station> stops = [];
                for (int i = 5; i < w.Length; i += 2) stops.Add(GetStation(w[i]));
                HashSet<Station> seen = [];
                foreach (Station stop in stops) Require(seen.Add(stop), "station " + stop.Id + " appears twice on line " + w[1]);
                int first = Time(w[2]), last = Time(w[3]);
                Require(first <= last, "line " + w[1] + " first departure is after last departure");
                int[] cumulative = new int[stops.Count];
                for (int i = 1; i < stops.Count; i++) cumulative[i] = cumulative[i - 1] + int.Parse(w[4 + 2 * i]);
                Require(last + cumulative[^1] <= 1440, "line " + w[1] + " runs past 24:00");
                MetroLine line = new(w[1], first, last, int.Parse(w[4]), stops, cumulative);
                Lines[w[1]] = line;
                Console.WriteLine($"LINE {line.Id} stops {stops.Count} time {line.Total} trips {line.Trips}");
                return;
            }
            case "TRANSFER":
            {
                Station station = GetStation(w[1]);
                station.Transfer = int.Parse(w[2]);
                Console.WriteLine($"TRANSFER {w[1]} {w[2]}");
                return;
            }
            case "WALK":
            {
                Station a = GetStation(w[1]), b = GetStation(w[2]);
                Require(a != b, "walk from " + a.Id + " to itself");
                int? before = a.Walks.TryGetValue(b.Id, out int old) ? old : null;
                int minutes = int.Parse(w[3]);
                a.Walks[b.Id] = minutes;
                b.Walks[a.Id] = minutes;
                Console.WriteLine($"WALK {a.Id} {b.Id} {minutes}" + (before is null ? "" : " was " + before));
                return;
            }
            case "TARIFF":
            {
                int[] added = w.Skip(3).Select(int.Parse).ToArray();
                for (int i = 1; i < added.Length; i++) Require(added[i] >= added[i - 1], "tariff prices must not decrease");
                prices = added;
                discount = int.Parse(w[1]);
                window = int.Parse(w[2]);
                Console.WriteLine($"TARIFF zones {prices.Length} discount {discount} window {window}");
                return;
            }
            case "CLOSE":
            case "OPEN":
            {
                Station a = GetStation(w[1]);
                bool close = command == "CLOSE";
                if (w.Length == 2)
                {
                    Require(close != a.Closed, "station " + a.Id + (close ? " is already closed" : " is not closed"));
                    a.Closed = close;
                    Console.WriteLine(command + " " + a.Id);
                }
                else
                {
                    Station b = GetStation(w[2]);
                    Segment key = Pair(a, b);
                    List<string> containing = [];
                    if (close)
                    {
                        foreach (MetroLine line in Lines.Values) for (int i = 1; i < line.Stops.Count; i++) if (Pair(line.Stops[i - 1], line.Stops[i]) == key)
                        {
                            containing.Add(line.Id);
                            break;
                        }
                        Require(containing.Count > 0, "no segment " + a.Id + "-" + b.Id);
                    }
                    Require(close != ClosedSegments.Contains(key), "segment " + a.Id + "-" + b.Id + (close ? " is already closed" : " is not closed"));
                    if (close) ClosedSegments.Add(key);
                    else ClosedSegments.Remove(key);
                    Console.WriteLine(command + " " + a.Id + "-" + b.Id + (close ? " lines " + string.Join(" ", containing) : ""));
                }
                return;
            }
            case "DELAY":
            {
                MetroLine line = GetLine(w[1]);
                int delay = int.Parse(w[2]);
                Require(line.Last + delay + line.Total <= 1440, "line " + line.Id + " runs past 24:00");
                line.Delay = delay;
                Console.WriteLine($"DELAY {line.Id} {delay}");
                return;
            }
            case "SUSPEND":
            case "RESUME":
            {
                MetroLine line = GetLine(w[1]);
                bool suspend = command == "SUSPEND";
                Require(line.Suspended != suspend, "line " + line.Id + (suspend ? " is already suspended" : " is not suspended"));
                line.Suspended = suspend;
                Console.WriteLine(command + " " + line.Id);
                return;
            }
            case "VIA":
            {
                Station origin = GetStation(w[1]), via = GetStation(w[2]), destination = GetStation(w[3]);
                Require(origin != destination, "origin and destination are the same");
                Require(via != origin && via != destination, "via station " + via.Id + " must differ from origin and destination");
                foreach (Station station in new[] {origin, via, destination}) Require(!station.Closed, "station " + station.Id + " is closed");
                int departure = Time(w[4]);
                Label? first = Earliest(origin, departure).GetValueOrDefault(via), result = null;
                if (first is not null)
                {
                    int ready = first.Time + via.Transfer;
                    Label? second = Earliest(via, ready).GetValueOrDefault(destination);
                    if (second is not null)
                    {
                        List<Leg> journey = Append(first.Journey, new('S', null, null, via, first.Time, via, ready, 0));
                        journey.AddRange(second.Journey);
                        result = new(second.Time, journey);
                    }
                }
                string heading = $"VIA {origin.Id} {via.Id} {destination.Id}";
                if (result is null) Console.WriteLine($"{heading} {Clock(departure)} unreachable");
                else PrintJourney(heading, departure, result);
                return;
            }
            case "REACH":
            {
                Station origin = GetStation(w[1]);
                Require(!origin.Closed, "station " + origin.Id + " is closed");
                int departure = Time(w[2]), limit = departure + int.Parse(w[3]);
                var labels = Earliest(origin, departure);
                var reached = Stations.Values.Where(station => labels.ContainsKey(station) && labels[station].Time <= limit).OrderBy(station => labels[station].Time).ThenBy(station => station.Id, StringComparer.Ordinal).ToList();
                Console.WriteLine($"REACH {origin.Id} {w[2]} {w[3]} count {reached.Count}");
                foreach (Station station in reached) Console.WriteLine($"{station.Id} {station.Name} {Clock(labels[station].Time)} {labels[station].Time - departure} rides {Rides(labels[station].Journey)}");
                return;
            }
            case "TIMETABLE":
            {
                Station station = GetStation(w[1]);
                MetroLine line = GetLine(w[2]);
                Require(line.Stops.Contains(station), "station " + station.Id + " is not on line " + line.Id);
                int direction = Direction(line, w[3]);
                Require(station.Id != w[3], "no departures from " + station.Id + " toward " + w[3]);
                Require(!line.Suspended, "line " + line.Id + " is suspended");
                Require(!station.Closed, "station " + station.Id + " is closed");
                int position = line.Position(direction, station), start = line.Next(direction, position, Time(w[4])), count = int.Parse(w[5]);
                List<string> times = [];
                if (start >= 0) for (int q = start; q < line.Trips && times.Count < count; q++) times.Add(Clock(line.Time(direction, position, q)));
                Console.WriteLine($"TIMETABLE {station.Id} {line.Id} toward {w[3]} {w[4]} next {times.Count}" + (times.Count == 0 ? "" : " " + string.Join(" ", times)));
                return;
            }
            case "DEPARTURES":
            case "ARRIVALS":
            {
                Station station = GetStation(w[1]);
                Require(!station.Closed, "station " + station.Id + " is closed");
                bool arrivals = command == "ARRIVALS";
                List<Departure> departures = [];
                foreach (MetroLine line in Lines.Values) if (!line.Suspended && line.Stops.Contains(station)) for (int direction = 0; direction < 2; direction++)
                {
                    int position = line.Position(direction, station);
                    if (arrivals ? position == 0 : position == line.Stops.Count - 1) continue;
                    int start = line.Next(direction, position, Time(w[2]));
                    if (start >= 0) for (int q = start; q < line.Trips; q++) departures.Add(new(line.Time(direction, position, q), line, direction));
                }
                var selected = departures.OrderBy(entry => entry.Time).ThenBy(entry => entry.Line.Id, StringComparer.Ordinal).ThenBy(entry => entry.Direction).Take(int.Parse(w[3])).ToList();
                Console.WriteLine($"{command} {station.Id} {w[2]} count {selected.Count}");
                foreach (var entry in selected) Console.WriteLine(Clock(entry.Time) + " " + entry.Line.Id + (arrivals ? " from " + entry.Line.Stop(entry.Direction, 0).Id : " toward " + entry.Line.Stop(entry.Direction, entry.Line.Stops.Count - 1).Id));
                return;
            }
            case "TRIP":
            {
                MetroLine line = GetLine(w[1]);
                int direction = Direction(line, w[2]);
                Require(!line.Suspended, "line " + line.Id + " is suspended");
                int train = line.Next(direction, 0, Time(w[3]));
                string heading = $"TRIP {line.Id} toward {w[2]} {w[3]}";
                if (train < 0) Console.WriteLine(heading + " none");
                else
                {
                    Console.WriteLine($"{heading} trip {train + 1} departs {Clock(line.Time(direction, 0, train))}");
                    for (int j = 0; j < line.Stops.Count; j++)
                    {
                        Station station = line.Stop(direction, j);
                        Console.WriteLine(Clock(line.Time(direction, j, train)) + " " + station.Id + (station.Closed ? " closed" : "") + (j > 0 && Blocked(line.Stop(direction, j - 1), station) ? " blocked" : ""));
                    }
                }
                return;
            }
            case "SHOWLINE":
            {
                MetroLine line = GetLine(w[1]);
                Console.WriteLine($"SHOWLINE {line.Id} {(line.Suspended ? "suspended" : "running")} first {Clock(line.First)} last {Clock(line.Last)} headway {line.Headway} delay {line.Delay} trips {line.Trips}");
                for (int j = 0; j < line.Stops.Count; j++)
                {
                    Station station = line.Stops[j];
                    Console.WriteLine($"{line.Cumulative[j]} {station.Id} zone {station.Zone}" + (station.Closed ? " closed" : "") + (j > 0 && Blocked(line.Stops[j - 1], station) ? " blocked" : ""));
                }
                return;
            }
            case "INFO":
            {
                Station station = GetStation(w[1]);
                Console.WriteLine($"INFO {station.Id} {station.Name} zone {station.Zone} transfer {station.Transfer} {(station.Closed ? "closed" : "open")}");
                var containing = Lines.Values.Where(line => line.Stops.Contains(station)).Select(line => line.Id).ToList();
                Console.WriteLine("LINES " + (containing.Count == 0 ? "none" : string.Join(" ", containing)));
                Console.WriteLine("WALKS " + (station.Walks.Count == 0 ? "none" : string.Join(" ", station.Walks.Select(entry => entry.Key + " " + entry.Value))));
                return;
            }
            case "STATUS": Console.WriteLine($"STATUS stations {Stations.Count} lines {Lines.Count} walks {Stations.Values.Sum(station => station.Walks.Count) / 2}");
            foreach (Station station in Stations.Values) if (station.Closed) Console.WriteLine("CLOSED " + station.Id);
            foreach (var segment in ClosedSegments.OrderBy(entry => entry.Low, StringComparer.Ordinal).ThenBy(entry => entry.High, StringComparer.Ordinal)) Console.WriteLine("CLOSED " + segment.Low + "-" + segment.High);
            foreach (MetroLine line in Lines.Values) if (line.Suspended) Console.WriteLine("SUSPENDED " + line.Id);
            foreach (MetroLine line in Lines.Values) if (line.Delay != 0) Console.WriteLine($"DELAYED {line.Id} {line.Delay}");
            return;
        }
        Station originStation = GetStation(w[1]), destinationStation = GetStation(w[2]);
        SearchCheck(originStation, destinationStation);
        string title = $"{command} {originStation.Id} {destinationStation.Id}";
        if (command == "FARE")
        {
            Require(w[4] is "ADULT" or "CHILD", "unknown fare class " + w[4]);
            Require(prices is not null, "no tariff");
            Fare(title + " " + w[3] + " " + w[4], originStation, destinationStation, Time(w[3]), w[4]);
            return;
        }
        if (command is "LASTTRAIN" or "ARRIVEBY")
        {
            int deadline = command == "LASTTRAIN" ? 1440 : Time(w[3]);
            if (command == "ARRIVEBY") title += " by " + w[3];
            for (int t = deadline - 1; t >= 0; t--)
            {
                Label? label = Earliest(originStation, t).GetValueOrDefault(destinationStation);
                if (label is not null && label.Time <= deadline)
                {
                    PrintJourney(title, t, label);
                    return;
                }
            }
            Console.WriteLine(title + " none");
            return;
        }
        int startTime = Time(w[3]);
        if (command == "PROFILE")
        {
            int last = Time(w[4]);
            Require(startTime <= last, "empty interval " + w[3] + " " + w[4]);
            SortedDictionary<int, int> arrivals = [];
            for (int t = startTime; t <= last; t++)
            {
                Label? label = Earliest(originStation, t).GetValueOrDefault(destinationStation);
                if (label is not null) arrivals[t] = label.Time;
            }
            var selected = arrivals.Keys.Where(t => t == last || !arrivals.ContainsKey(t + 1) || arrivals[t] < arrivals[t + 1]).ToList();
            Console.WriteLine($"{title} {w[3]} {w[4]} count {selected.Count}");
            foreach (int t in selected) Console.WriteLine($"{Clock(t)} -> {Clock(arrivals[t])} total {arrivals[t] - t}");
            return;
        }
        if (command is "FEWEST" or "PARETO")
        {
            var rounds = Rounds(originStation, startTime);
            List<int> options = [];
            for (int k = 0; k < rounds.Count; k++)
            {
                Label? label = rounds[k].GetValueOrDefault(destinationStation), previous = k == 0 ? null : rounds[k - 1].GetValueOrDefault(destinationStation);
                if (label is not null && (previous is null || previous.Time > label.Time)) options.Add(k);
            }
            if (command == "FEWEST")
            {
                if (options.Count == 0) Console.WriteLine($"{title} {w[3]} unreachable");
                else
                {
                    int k = options[0];
                    PrintJourney(title + " trips " + k, startTime, rounds[k][destinationStation]);
                }
            }
            else
            {
                Console.WriteLine($"{title} {w[3]} options {options.Count}");
                foreach (int k in options) PrintJourney("OPTION trips " + k, startTime, rounds[k][destinationStation]);
            }
            return;
        }
        Label? resultLabel = Earliest(originStation, startTime).GetValueOrDefault(destinationStation);
        if (resultLabel is null) Console.WriteLine($"{title} {w[3]} unreachable");
        else PrintJourney(title, startTime, resultLabel);
    }

    static void Main()
    {
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++) try
        {
            Command(Console.ReadLine()!.Split(' '));
        }
        catch (Problem error)
        {
            Console.WriteLine(error.Message);
        }
    }
}
