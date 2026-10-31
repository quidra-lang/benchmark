global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
using System.Globalization;
using System.Text;
using static Stats;

sealed class Source(string node, List<(long Rate, long End)> rates, Segment segment)
{
    public string Node = node;
    public Segment Segment = segment;
    public Queue<Vehicle> Queue = new();
    public int Start, Maximum;
    public long Rate(int step) { foreach (var period in rates) if (step <= period.End) return period.Rate; return 0; }
}
sealed record Detector(string Name, Segment Segment, int Cell, int Width);
sealed class Diagram(Segment segment, int lane, int start, int end)
{
    public Segment Segment = segment;
    public int Lane = lane, Start = start, End = end;
    public List<string> Lines = [];
}
sealed record Ring(int Number, int Length, int Vmax, int Warmup, int Measure, long Seed, List<int> Counts);
sealed class Interval(int detectors)
{
    public long Arrivals, Insertions, Exits, VehicleSteps, SpeedSum;
    public long[] Passing = new long[detectors], Occupancy = new long[detectors], OccupancySpeed = new long[detectors];
}
sealed class Move(Vehicle vehicle)
{
    public Vehicle Vehicle = vehicle;
    public Segment Segment = vehicle.Segment!;
    public int Cell = vehicle.Cell, Speed;
}
sealed record Route(List<string> Segments, Share Share);
sealed class Simulation
{
    readonly List<Segment> segments = [];
    readonly Dictionary<string, Segment> segmentById = [];
    readonly List<Junction> junctions = [];
    readonly List<Incident> incidents = [];
    readonly List<BusStop> stops = [];
    readonly List<VehicleClass> classes = [];
    readonly List<Source> sources = [];
    readonly List<string> sinks = [];
    readonly List<Detector> detectors = [];
    readonly List<Diagram> diagrams = [];
    readonly List<long> trackNumbers = [];
    readonly List<Ring> rings = [];
    readonly List<Vehicle> vehicles = [];
    readonly List<Interval> intervals = [];
    readonly List<string> events = [];
    readonly Dictionary<long, List<string>> tracks = [];
    readonly Minstd rng = new(1);
    long seed = 1, binWidth = 1;
    int steps, dawdle, stopped, intervalLength = 1;
    static string Time(int step) => step.ToString("D4");
    static string Optional(int value) => value == 0 ? "-" : value.ToString();
    public Simulation()
    {
        foreach (string name in new[] { "network.txt","demand.txt","params.txt" }) foreach (string line in File.ReadLines(Path.Combine("input",name))) Load(line.Split(' '));
    }
    void Load(string[] p)
    {
        long N(int i) => long.Parse(p[i]); int I(int i) => (int)N(i);
        switch (p[0])
        {
            case "SEGMENT": { Segment s = new(p[1],p[2],p[3],I(4),I(5),I(6)); segments.Add(s); segmentById.Add(s.Id,s); break; }
            case "JUNCTION": { Junction j = new(p[1],I(2),p.Skip(3)); foreach (Segment s in segments.Where(s => s.End == p[1])) { s.Junction = j; j.Incoming.Add(s); } junctions.Add(j); break; }
            case "INCIDENT": incidents.Add(new(segmentById[p[1]],I(2),I(3),N(4),N(5))); break;
            case "STOP": { BusStop stop = new(segmentById[p[1]],I(2),I(3)); stop.Segment.Stop = stop; stops.Add(stop); break; }
            case "CLASS": classes.Add(new(p[1],I(2),N(3),p[4] == "Y",p[5] == "Y")); break;
            case "SOURCE": sources.Add(new(p[1],p.Skip(2).Select(x => { string[] pair = x.Split(':'); return (long.Parse(pair[0]),long.Parse(pair[1])); }).ToList(),segments.First(s => s.Start == p[1]))); break;
            case "SINK": sinks.Add(p[1]); break;
            case "TURN": segmentById[p[1]].Turns.Add(new(segmentById[p[2]],N(3))); break;
            case "seed": seed = N(1); break;
            case "steps": steps = I(1); break;
            case "dawdle": dawdle = I(1); stopped = I(2); break;
            case "interval": intervalLength = I(1); break;
            case "bin": binWidth = N(1); break;
            case "detector": detectors.Add(new(p[1],segmentById[p[2]],I(3),I(4))); break;
            case "diagram": diagrams.Add(new(segmentById[p[1]],I(2),I(3),I(4))); break;
            case "track": foreach (long number in p.Skip(1).Select(long.Parse)) { trackNumbers.Add(number); tracks.Add(number,[]); } break;
            case "ring": rings.Add(new(rings.Count + 1,I(1),I(2),I(3),I(4),N(5),p.Skip(6).Select(int.Parse).ToList())); break;
        }
    }
    void Record(int step, string text) => events.Add(Time(step) + " " + text);
    IEnumerable<Vehicle> VehiclesOn(Segment segment) => Enumerable.Range(1,segment.Lanes).SelectMany(segment.Numbers).Select(n => vehicles[n - 1]);
    void Enter(Vehicle vehicle, Segment segment)
    {
        vehicle.Route.Add(segment.Id); segment.Entered++;
        vehicle.Turn = segment.Junction is null ? null : segment.Turns[Minstd.Select(segment.Turns.Select(t => t.Weight),rng.Draw())];
    }
    void Arrive(int step)
    {
        foreach (Source source in sources) if (rng.Draw() % 1000 < source.Rate(step))
        {
            VehicleClass kind = classes[Minstd.Select(classes.Select(c => c.Weight),rng.Draw())]; Vehicle vehicle = new(vehicles.Count + 1,kind,source.Node,step);
            vehicles.Add(vehicle); source.Queue.Enqueue(vehicle); intervals[^1].Arrivals++;
        }
    }
    void Insert(int step)
    {
        foreach (Source source in sources)
        {
            Segment segment = source.Segment;
            while (source.Queue.Count != 0)
            {
                int best = 0, first = -1;
                for (int lane = 1; lane <= segment.Lanes; lane++) if (segment.Empty(lane,0) && segment.First(lane) > first) { best = lane; first = segment.First(lane); }
                if (best == 0) break; Vehicle vehicle = source.Queue.Dequeue(); vehicle.Place(segment,best,0); vehicle.Inserted = step; Enter(vehicle,segment); intervals[^1].Insertions++;
            }
            if (source.Queue.Count != 0 && source.Start == 0) { source.Start = step; source.Maximum = 0; }
            if (source.Start != 0)
            {
                source.Maximum = Math.Max(source.Maximum,source.Queue.Count);
                if (source.Queue.Count == 0) { Record(step,$"QUEUE {source.Node} from {source.Start} max {source.Maximum}"); source.Start = 0; }
            }
        }
    }
    (int Lane, int Kind) DesiredLane(Vehicle vehicle)
    {
        Segment s = vehicle.Segment!; int lane = vehicle.Lane, cell = vehicle.Cell, top = vehicle.MaxSpeed, here = s.Free(lane,cell,top + 1), want = Math.Min(vehicle.Speed + 1,top), ahead = cell + here + 1;
        if (here < top + 1 && ahead < s.Length && s.Cells[lane - 1][ahead] == -1)
            foreach (int target in new[] { lane + 1,lane - 1 }) if (target >= 1 && target <= s.Lanes && s.Free(target,cell,top + 1) > here && s.Safe(target,cell)) return (target,2);
        if (vehicle.HeadingForStop) return lane >= 2 && s.Safe(lane - 1,cell) ? (lane - 1,1) : (lane,-1);
        if (vehicle.Kind.Overtakes && lane < s.Lanes && here < want && s.Free(lane + 1,cell,top + 1) > here && s.Safe(lane + 1,cell)) return (lane + 1,0);
        if (lane >= 2 && s.Free(lane - 1,cell,top + 1) > want && s.Safe(lane - 1,cell)) return (lane - 1,1); return (lane,-1);
    }
    void ChangeLanes()
    {
        List<(Vehicle Vehicle, int Lane, int Kind)> changes = [];
        foreach (Segment segment in segments.Where(s => s.Lanes >= 2))
        {
            HashSet<(int, int)> reserved = [];
            for (int lane = 1; lane <= segment.Lanes; lane++) foreach (int number in segment.Numbers(lane))
            {
                Vehicle vehicle = vehicles[number - 1]; if (vehicle.Dwell != 0) continue; var desired = DesiredLane(vehicle);
                if (desired.Lane != lane && reserved.Add((desired.Lane,vehicle.Cell))) changes.Add((vehicle,desired.Lane,desired.Kind));
            }
        }
        foreach (var change in changes) { Segment segment = change.Vehicle.Segment!; change.Vehicle.Place(segment,change.Lane,change.Vehicle.Cell); change.Vehicle.LaneChanges++; segment.Changes[change.Kind]++; }
    }
    int DetermineSpeed(Vehicle vehicle, int step)
    {
        Segment s = vehicle.Segment!; int accelerated = Math.Min(vehicle.Speed + 1,vehicle.MaxSpeed), gap = s.Free(vehicle.Lane,vehicle.Cell,accelerated);
        if (gap < accelerated && vehicle.Cell + gap == s.Length - 1)
        {
            if (s.Junction is null) gap = accelerated;
            else if (s.Junction.Green(s.Id,step)) { Segment target = vehicle.Turn!.Target; gap += target.Free(Math.Min(vehicle.Lane,target.Lanes),-1,accelerated - gap); }
        }
        if (vehicle.HeadingForStop) gap = Math.Min(gap,s.Stop!.Cell - vehicle.Cell);
        int speed = Vehicle.Slowdown(Math.Min(accelerated,gap),vehicle.Speed,rng.Draw(),dawdle,stopped);
        if (vehicle.Dwell != 0) { speed = 0; vehicle.Dwell--; } return speed;
    }
    List<Move> ProcessingOrder()
    {
        List<Move> result = [];
        foreach (Segment segment in segments) for (int lane = 1; lane <= segment.Lanes; lane++) foreach (int number in segment.Numbers(lane).Reverse()) result.Add(new(vehicles[number - 1])); return result;
    }
    List<Move> MoveVehicles(List<Move> moves, int step)
    {
        List<Move> passing = [];
        foreach (Move move in moves)
        {
            Vehicle vehicle = move.Vehicle; Segment segment = move.Segment;
            if (move.Cell + move.Speed < segment.Length) vehicle.Place(segment,vehicle.Lane,move.Cell + move.Speed);
            else if (segment.Junction is null) { vehicle.Leave(); vehicle.Exited = step; vehicle.Sink = segment.End; intervals[^1].Exits++; }
            else passing.Add(move);
        }
        return passing;
    }
    void PassJunctions(List<Move> passing)
    {
        foreach (Move move in passing)
        {
            Vehicle vehicle = move.Vehicle; Segment segment = move.Segment, target = vehicle.Turn!.Target;
            int lane = Math.Min(vehicle.Lane,target.Lanes), overshoot = move.Cell + move.Speed - segment.Length, cell = Math.Min(overshoot,target.First(lane) - 1);
            if (cell < overshoot) segment.Blocked++;
            if (cell >= 0) { vehicle.Place(target,lane,cell); move.Speed = segment.Length - move.Cell + cell; segment.Passed++; vehicle.Turn.Vehicles++; Enter(vehicle,target); }
            else { vehicle.Place(segment,vehicle.Lane,segment.Length - 1); move.Speed = segment.Length - 1 - move.Cell; }
        }
    }
    void AggregateVehicle(Move move, int step)
    {
        Vehicle vehicle = move.Vehicle; Interval interval = intervals[^1]; vehicle.Steps++; vehicle.Distance += move.Speed;
        if (move.Speed == 0) { vehicle.StoppedSteps++; if (vehicle.Speed > 0) vehicle.StopCount++; } vehicle.Speed = move.Speed; interval.VehicleSteps++; interval.SpeedSum += move.Speed;
        if (vehicle.HeadingForStop && vehicle.Lane == 1 && vehicle.Cell == vehicle.Segment!.Stop!.Cell)
        {
            BusStop stop = vehicle.Segment.Stop; vehicle.CompletedStops.Add(vehicle.Segment.Id); vehicle.Dwell = stop.Dwell; stop.Buses++; Record(step,$"BUS_STOP {vehicle.Number} {vehicle.Segment.Id} cell {stop.Cell}");
        }
        if (tracks.TryGetValue(vehicle.Number,out var track)) track.Add(Time(step) + " " + (vehicle.Segment is null ? $"EXIT {vehicle.Speed}" : $"{vehicle.Segment.Id} {vehicle.Lane} {vehicle.Cell} {vehicle.Speed}"));
        for (int i = 0; i < detectors.Count; i++) if (move.Segment == detectors[i].Segment && move.Cell < detectors[i].Cell && (vehicle.Segment != detectors[i].Segment || vehicle.Cell >= detectors[i].Cell)) interval.Passing[i]++;
    }
    void AggregateState(int step)
    {
        Interval interval = intervals[^1];
        for (int i = 0; i < detectors.Count; i++) foreach (Vehicle vehicle in VehiclesOn(detectors[i].Segment)) if (vehicle.Cell >= detectors[i].Cell && vehicle.Cell < detectors[i].Cell + detectors[i].Width) { interval.Occupancy[i]++; interval.OccupancySpeed[i] += vehicle.Speed; }
        foreach (Segment segment in segments)
        {
            List<Vehicle> present = VehiclesOn(segment).ToList(); segment.VehicleSum += present.Count; segment.SpeedSum += present.Sum(v => (long)v.Speed); segment.MaxVehicles = Math.Max(segment.MaxVehicles,present.Count);
            if (segment.Junction is null) continue; bool green = segment.Junction.Green(segment.Id,step); if (green) segment.GreenSteps++;
            int queued = present.Count(v => v.Speed == 0); segment.QueueSum += queued; segment.MaxQueue = Math.Max(segment.MaxQueue,queued);
            if (step < steps && queued > 0 && green && !segment.Junction.Green(segment.Id,step + 1)) segment.Failures++;
        }
        foreach (Diagram diagram in diagrams) if (diagram.Start <= step && step <= diagram.End)
        {
            Segment segment = diagram.Segment; string signal = segment.Junction is null ? "E" : segment.Junction.Green(segment.Id,step) ? "G" : "R"; diagram.Lines.Add($"{Time(step)} {segment.Text(diagram.Lane,vehicles)} {signal}");
        }
    }
    public void Run()
    {
        rng.State = seed;
        for (int step = 1; step <= steps; step++)
        {
            foreach (Incident incident in incidents) { string text = incident.Update(step); if (text.Length > 0) Record(step,$"{text} {incident.Segment.Id} lane {incident.Lane} cell {incident.Cell}"); }
            if ((step - 1) % intervalLength == 0) intervals.Add(new(detectors.Count)); Arrive(step); Insert(step); ChangeLanes(); List<Move> moves = ProcessingOrder();
            foreach (Move move in moves) move.Speed = DetermineSpeed(move.Vehicle,step); PassJunctions(MoveVehicles(moves,step)); foreach (Move move in moves) AggregateVehicle(move,step); AggregateState(step);
        }
        foreach (Source source in sources) if (source.Start != 0) Record(steps,$"QUEUE {source.Node} from {source.Start} max {source.Maximum} open");
    }
    List<Route> EnumerateRoutes(Segment segment)
    {
        if (segment.Junction is null) return [new([segment.Id],new(1))]; long total = segment.Turns.Sum(t => t.Weight); List<Route> result = [];
        foreach (Turn turn in segment.Turns) foreach (Route route in EnumerateRoutes(turn.Target)) result.Add(new([segment.Id,..route.Segments],route.Share.Times(turn.Weight,total))); return result;
    }
    List<string> TravelBlock(string heading, List<Vehicle> group)
    {
        List<long> times = group.Select(v => (long)v.TravelTime).Order().ToList(); if (times.Count == 0) return [$"{heading} exited 0"];
        List<string> result = [$"{heading} exited {times.Count} min {times[0]} p50 {Percentile(times,50)} p90 {Percentile(times,90)} max {times[^1]} mean {Dec(times.Sum(),times.Count,2)}"]; result.AddRange(Histogram(times,binWidth)); return result;
    }
    static string Outcome(List<Vehicle> group, int total) => $"vehicles {group.Count} share {Frac(group.Count,total)} mean {Dec(group.Sum(v => (long)v.TravelTime),group.Count,2)}";
    List<string> TravelLines()
    {
        List<Vehicle> exited = vehicles.Where(v => v.Exited != 0).ToList(); List<string> result = [];
        foreach (VehicleClass kind in classes) result.AddRange(TravelBlock("CLASS " + kind.Name,exited.Where(v => ReferenceEquals(v.Kind,kind)).ToList())); result.AddRange(TravelBlock("ALL",exited));
        foreach (Source source in sources)
        {
            List<Vehicle> group = exited.Where(v => v.Source == source.Node).ToList(); result.Add($"SOURCE {source.Node} exited {group.Count}"); List<Route> routes = EnumerateRoutes(source.Segment);
            foreach (Route route in routes) result.Add($"  ROUTE {string.Join(',',route.Segments)} expected {route.Share} {Outcome(group.Where(v => v.Route.SequenceEqual(route.Segments)).ToList(),group.Count)}");
            foreach (string sink in sinks)
            {
                List<Share> shares = routes.Where(r => segmentById[r.Segments[^1]].End == sink).Select(r => r.Share).ToList(); if (shares.Count == 0) continue;
                Share expected = new(0); foreach (Share share in shares) expected = expected.Plus(share); result.Add($"  SINK {sink} expected {expected} {Outcome(group.Where(v => v.Sink == sink).ToList(),group.Count)}");
            }
        }
        return result;
    }
    static List<string> ClassBlock(string heading, List<Vehicle> group)
    {
        int inserted = group.Count(v => v.Inserted != 0); List<Vehicle> exited = group.Where(v => v.Exited != 0).ToList(); int count = exited.Count;
        long vehicleSteps = group.Sum(v => v.Steps), distance = group.Sum(v => v.Distance);
        return [heading,$"  generated {group.Count} inserted {inserted} exited {count} in_network {inserted - count} queued {group.Count - inserted}",$"  vehicle_steps {vehicleSteps} distance {distance} mean_speed {Frac(distance,vehicleSteps)} = {Dec(distance,vehicleSteps,3)}",$"  travel {Dec(exited.Sum(v => (long)v.TravelTime),count,2)} entry_delay {Dec(exited.Sum(v => (long)v.Inserted - v.Arrival),count,2)} stopped {Dec(exited.Sum(v => v.StoppedSteps),count,2)} stops {Dec(exited.Sum(v => v.StopCount),count,2)} lane_changes {Dec(exited.Sum(v => v.LaneChanges),count,2)}"];
    }
    List<string> ClassLines()
    {
        List<string> result = []; foreach (VehicleClass kind in classes) result.AddRange(ClassBlock($"CLASS {kind.Name} vmax {kind.Vmax} weight {kind.Weight} overtake {(kind.Overtakes ? "Y" : "N")} stops {(kind.Stops ? "Y" : "N")}",vehicles.Where(v => ReferenceEquals(v.Kind,kind)).ToList())); result.AddRange(ClassBlock("ALL",vehicles)); return result;
    }
    List<string> NetworkLines()
    {
        List<string> result = [];
        foreach (Segment s in segments) result.Add($"SEGMENT {s.Id} {s.Start} {s.End} length {s.Length} lanes {s.Lanes} limit {s.Limit} entered {s.Entered} mean_vehicles {Dec(s.VehicleSum,steps,3)} density {Dec(s.VehicleSum,(long)steps * s.Length * s.Lanes,4)} mean_speed {Dec(s.SpeedSum,s.VehicleSum,2)} max_vehicles {s.MaxVehicles} changes {string.Join('/',s.Changes)}");
        foreach (Junction junction in junctions)
        {
            result.AddRange(junction.PlanLines());
            foreach (Segment s in junction.Incoming)
            {
                result.Add($"  IN {s.Id} green {s.GreenSteps} passed {s.Passed} blocked {s.Blocked} max_queue {s.MaxQueue} mean_queue {Dec(s.QueueSum,steps,3)} failures {s.Failures}");
                foreach (Turn turn in s.Turns) result.Add($"    TURN {turn.Target.Id} weight {turn.Weight} vehicles {turn.Vehicles}");
            }
        }
        foreach (BusStop stop in stops) result.Add($"STOP {stop.Segment.Id} cell {stop.Cell} dwell {stop.Dwell} buses {stop.Buses}");
        foreach (Incident incident in incidents) result.Add($"INCIDENT {incident.Segment.Id} lane {incident.Lane} cell {incident.Cell} planned {incident.Start}-{incident.End} active {(incident.ActiveStart == 0 ? "none" : $"{incident.ActiveStart}-{incident.ActiveEnd}")}"); return result;
    }
    List<string> DetectorLines()
    {
        List<string> result = ["detector,interval,flow,density,speed"];
        for (int i = 0; i < detectors.Count; i++) for (int k = 0; k < intervals.Count; k++) { Interval a = intervals[k]; Detector d = detectors[i]; result.Add($"{d.Name},{k + 1},{a.Passing[i]},{Dec(a.Occupancy[i],(long)intervalLength * d.Width * d.Segment.Lanes,4)},{Dec(a.OccupancySpeed[i],a.Occupancy[i],2)}"); } return result;
    }
    List<string> TimelineLines()
    {
        List<string> result = ["interval,arrived,inserted,exited,in_network,queued,mean_speed"]; long arrived = 0, inserted = 0, exited = 0;
        for (int k = 0; k < intervals.Count; k++) { Interval a = intervals[k]; arrived += a.Arrivals; inserted += a.Insertions; exited += a.Exits; result.Add($"{k + 1},{a.Arrivals},{a.Insertions},{a.Exits},{inserted - exited},{arrived - inserted},{Dec(a.SpeedSum,a.VehicleSteps,2)}"); } return result;
    }
    List<string> TrackLines()
    {
        List<string> result = [];
        foreach (long number in trackNumbers)
        {
            if (number > vehicles.Count) { result.Add($"VEHICLE {number} none"); continue; } Vehicle vehicle = vehicles[(int)number - 1];
            result.Add($"VEHICLE {number} class {vehicle.Kind.Name} source {vehicle.Source} arrival {vehicle.Arrival} inserted {Optional(vehicle.Inserted)} exited {Optional(vehicle.Exited)} sink {(vehicle.Sink.Length == 0 ? "-" : vehicle.Sink)}"); result.Add("ROUTE " + (vehicle.Route.Count == 0 ? "-" : string.Join(' ',vehicle.Route))); result.AddRange(tracks[number]);
        }
        return result;
    }
    static long RunRing(Ring ring, int count, int dawdle, int stopped)
    {
        Minstd rng = new(ring.Seed); int[] positions = Enumerable.Range(0,count).Select(i => i * ring.Length / count).ToArray(), speeds = new int[count]; long total = 0;
        for (int step = 1; step <= ring.Warmup + ring.Measure; step++)
        {
            int[] order = Enumerable.Range(0,count).OrderByDescending(i => positions[i]).ToArray(), updated = new int[count];
            for (int rank = 0; rank < count; rank++) { int i = order[rank], ahead = order[rank == 0 ? count - 1 : rank - 1], gap = (positions[ahead] - positions[i] - 1 + ring.Length) % ring.Length; updated[i] = Vehicle.Slowdown(Math.Min(Math.Min(speeds[i] + 1,ring.Vmax),gap),speeds[i],rng.Draw(),dawdle,stopped); }
            for (int i = 0; i < count; i++) positions[i] = (positions[i] + updated[i]) % ring.Length; speeds = updated; if (step > ring.Warmup) total += speeds.Sum(x => (long)x);
        }
        return total;
    }
    List<string> FundamentalLines()
    {
        List<string> result = ["ring,vehicles,density,flow,speed"]; foreach (Ring ring in rings) foreach (int count in ring.Counts) { long total = RunRing(ring,count,dawdle,stopped); result.Add($"{ring.Number},{count},{Dec(count,ring.Length,4)},{Dec(total,(long)ring.Length * ring.Measure,4)},{Dec(total,(long)count * ring.Measure,3)}"); } return result;
    }
    public void Write()
    {
        List<string> spacetime = []; foreach (Diagram diagram in diagrams) { spacetime.Add($"DIAGRAM {diagram.Segment.Id} lane {diagram.Lane} steps {diagram.Start}-{diagram.End}"); spacetime.AddRange(diagram.Lines); }
        (string Name, List<string> Lines)[] outputs = [("spacetime.txt",spacetime),("detectors.csv",DetectorLines()),("travel_times.txt",TravelLines()),("class_stats.txt",ClassLines()),("network_stats.txt",NetworkLines()),("timeline.csv",TimelineLines()),("tracks.txt",TrackLines()),("fundamental.csv",FundamentalLines()),("events.txt",events)];
        Directory.CreateDirectory("output"); foreach (var output in outputs) File.WriteAllText(Path.Combine("output",output.Name),string.Concat(output.Lines.Select(x => x + "\n")),new UTF8Encoding(false));
    }
}
static class Program
{
    static void Main() { CultureInfo.CurrentCulture = CultureInfo.InvariantCulture; Simulation simulation = new(); simulation.Run(); simulation.Write(); }
}
