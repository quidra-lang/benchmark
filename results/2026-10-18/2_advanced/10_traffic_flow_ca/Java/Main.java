import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.StringJoiner;
import java.util.stream.IntStream;

record Period(long rate, long end) {}
final class Source {
    final String node;
    final List<Period> rates;
    final Segment segment;
    final ArrayDeque<Vehicle> queue = new ArrayDeque<>();
    int start, maximum;
    Source(String node, List<Period> rates, Segment segment) { this.node = node; this.rates = rates; this.segment = segment; }
    long rate(int step) { for (Period period : rates) if (step <= period.end()) return period.rate(); return 0; }
}
record Detector(String name, Segment segment, int cell, int width) {}
final class Diagram {
    final Segment segment;
    final int lane, start, end;
    final List<String> lines = new ArrayList<>();
    Diagram(Segment segment, int lane, int start, int end) { this.segment = segment; this.lane = lane; this.start = start; this.end = end; }
}
record Ring(int number, int length, int vmax, int warmup, int measure, long seed, List<Integer> counts) {}
final class Interval {
    long arrivals, insertions, exits, vehicleSteps, speedSum;
    final long[] passing, occupancy, occupancySpeed;
    Interval(int detectors) { passing = new long[detectors]; occupancy = new long[detectors]; occupancySpeed = new long[detectors]; }
}
final class Move {
    final Vehicle vehicle;
    final Segment segment;
    final int cell;
    int speed;
    Move(Vehicle vehicle) { this.vehicle = vehicle; segment = vehicle.segment; cell = vehicle.cell; }
}
record Route(List<String> segments, Share share) {}
record LaneChoice(int lane, int kind) {}
record LaneChange(Vehicle vehicle, int lane, int kind) {}
record Cell(int lane, int cell) {}
record Output(String name, List<String> lines) {}
final class Simulation {
    final List<Segment> segments = new ArrayList<>();
    final Map<String, Segment> segmentById = new HashMap<>();
    final List<Junction> junctions = new ArrayList<>();
    final List<Incident> incidents = new ArrayList<>();
    final List<BusStop> stops = new ArrayList<>();
    final List<VehicleClass> classes = new ArrayList<>();
    final List<Source> sources = new ArrayList<>();
    final List<String> sinks = new ArrayList<>();
    final List<Detector> detectors = new ArrayList<>();
    final List<Diagram> diagrams = new ArrayList<>();
    final List<Long> trackNumbers = new ArrayList<>();
    final List<Ring> rings = new ArrayList<>();
    final List<Vehicle> vehicles = new ArrayList<>();
    final List<Interval> intervals = new ArrayList<>();
    final List<String> events = new ArrayList<>();
    final Map<Long, List<String>> tracks = new HashMap<>();
    final Minstd rng = new Minstd(1);
    long seed = 1, binWidth = 1;
    int steps, dawdle, stopped, intervalLength = 1;
    static String line(Object... values) { StringJoiner joiner = new StringJoiner(" "); for (Object value : values) joiner.add(value.toString()); return joiner.toString(); }
    static String time(int step) { return String.format(Locale.ROOT,"%04d",step); }
    static String optional(int value) { return value == 0 ? "-" : Integer.toString(value); }
    Simulation() throws IOException {
        for (String name : List.of("network.txt","demand.txt","params.txt")) for (String line : Files.readAllLines(Path.of("input",name),StandardCharsets.US_ASCII)) load(line.split(" "));
    }
    void load(String[] p) {
        switch (p[0]) {
            case "SEGMENT" -> { Segment segment = new Segment(p[1],p[2],p[3],Integer.parseInt(p[4]),Integer.parseInt(p[5]),Integer.parseInt(p[6])); segments.add(segment); segmentById.put(segment.id,segment); }
            case "JUNCTION" -> { Junction junction = new Junction(p[1],Integer.parseInt(p[2]),Arrays.asList(p).subList(3,p.length)); for (Segment segment : segments) if (segment.end.equals(p[1])) { segment.junction = junction; junction.incoming.add(segment); } junctions.add(junction); }
            case "INCIDENT" -> incidents.add(new Incident(segmentById.get(p[1]),Integer.parseInt(p[2]),Integer.parseInt(p[3]),Long.parseLong(p[4]),Long.parseLong(p[5])));
            case "STOP" -> { BusStop stop = new BusStop(segmentById.get(p[1]),Integer.parseInt(p[2]),Integer.parseInt(p[3])); stop.segment.stop = stop; stops.add(stop); }
            case "CLASS" -> classes.add(new VehicleClass(p[1],Integer.parseInt(p[2]),Long.parseLong(p[3]),p[4].equals("Y"),p[5].equals("Y")));
            case "SOURCE" -> { List<Period> rates = new ArrayList<>(); for (int i = 2; i < p.length; i++) { String[] pair = p[i].split(":"); rates.add(new Period(Long.parseLong(pair[0]),Long.parseLong(pair[1]))); } sources.add(new Source(p[1],rates,segments.stream().filter(s -> s.start.equals(p[1])).findFirst().orElseThrow())); }
            case "SINK" -> sinks.add(p[1]);
            case "TURN" -> segmentById.get(p[1]).turns.add(new Turn(segmentById.get(p[2]),Long.parseLong(p[3])));
            case "seed" -> seed = Long.parseLong(p[1]);
            case "steps" -> steps = Integer.parseInt(p[1]);
            case "dawdle" -> { dawdle = Integer.parseInt(p[1]); stopped = Integer.parseInt(p[2]); }
            case "interval" -> intervalLength = Integer.parseInt(p[1]);
            case "bin" -> binWidth = Long.parseLong(p[1]);
            case "detector" -> detectors.add(new Detector(p[1],segmentById.get(p[2]),Integer.parseInt(p[3]),Integer.parseInt(p[4])));
            case "diagram" -> diagrams.add(new Diagram(segmentById.get(p[1]),Integer.parseInt(p[2]),Integer.parseInt(p[3]),Integer.parseInt(p[4])));
            case "track" -> { for (int i = 1; i < p.length; i++) { long number = Long.parseLong(p[i]); trackNumbers.add(number); tracks.put(number,new ArrayList<>()); } }
            case "ring" -> rings.add(new Ring(rings.size() + 1,Integer.parseInt(p[1]),Integer.parseInt(p[2]),Integer.parseInt(p[3]),Integer.parseInt(p[4]),Long.parseLong(p[5]),Arrays.stream(p).skip(6).map(Integer::parseInt).toList()));
            default -> throw new IllegalArgumentException(p[0]);
        }
    }
    void record(int step, String text) { events.add(time(step) + " " + text); }
    List<Vehicle> vehiclesOn(Segment segment) { return IntStream.rangeClosed(1,segment.lanes).boxed().flatMap(lane -> segment.numbers(lane).stream()).map(number -> vehicles.get(number - 1)).toList(); }
    void enter(Vehicle vehicle, Segment segment) {
        vehicle.route.add(segment.id); segment.entered++;
        vehicle.turn = segment.junction == null ? null : segment.turns.get(Minstd.select(segment.turns.stream().map(t -> t.weight).toList(),rng.draw()));
    }
    void arrive(int step) {
        for (Source source : sources) if (rng.draw() % 1000 < source.rate(step)) {
            VehicleClass kind = classes.get(Minstd.select(classes.stream().map(VehicleClass::weight).toList(),rng.draw())); Vehicle vehicle = new Vehicle(vehicles.size() + 1,kind,source.node,step);
            vehicles.add(vehicle); source.queue.addLast(vehicle); intervals.getLast().arrivals++;
        }
    }
    void insert(int step) {
        for (Source source : sources) {
            Segment segment = source.segment;
            while (!source.queue.isEmpty()) {
                int best = 0, first = -1;
                for (int lane = 1; lane <= segment.lanes; lane++) if (segment.empty(lane,0) && segment.first(lane) > first) { best = lane; first = segment.first(lane); }
                if (best == 0) break; Vehicle vehicle = source.queue.removeFirst(); vehicle.place(segment,best,0); vehicle.inserted = step; enter(vehicle,segment); intervals.getLast().insertions++;
            }
            if (!source.queue.isEmpty() && source.start == 0) { source.start = step; source.maximum = 0; }
            if (source.start != 0) {
                source.maximum = Math.max(source.maximum,source.queue.size());
                if (source.queue.isEmpty()) { record(step,line("QUEUE",source.node,"from",source.start,"max",source.maximum)); source.start = 0; }
            }
        }
    }
    LaneChoice desiredLane(Vehicle vehicle) {
        Segment s = vehicle.segment; int lane = vehicle.lane, cell = vehicle.cell, top = vehicle.maxSpeed(), here = s.free(lane,cell,top + 1), want = Math.min(vehicle.speed + 1,top), ahead = cell + here + 1;
        if (here < top + 1 && ahead < s.length && s.cells[lane - 1][ahead] == -1)
            for (int target : new int[] { lane + 1,lane - 1 }) if (target >= 1 && target <= s.lanes && s.free(target,cell,top + 1) > here && s.safe(target,cell)) return new LaneChoice(target,2);
        if (vehicle.headingForStop()) return lane >= 2 && s.safe(lane - 1,cell) ? new LaneChoice(lane - 1,1) : new LaneChoice(lane,-1);
        if (vehicle.kind.overtakes() && lane < s.lanes && here < want && s.free(lane + 1,cell,top + 1) > here && s.safe(lane + 1,cell)) return new LaneChoice(lane + 1,0);
        if (lane >= 2 && s.free(lane - 1,cell,top + 1) > want && s.safe(lane - 1,cell)) return new LaneChoice(lane - 1,1); return new LaneChoice(lane,-1);
    }
    void changeLanes() {
        List<LaneChange> changes = new ArrayList<>();
        for (Segment segment : segments) if (segment.lanes >= 2) {
            Set<Cell> reserved = new HashSet<>();
            for (int lane = 1; lane <= segment.lanes; lane++) for (int number : segment.numbers(lane)) {
                Vehicle vehicle = vehicles.get(number - 1); if (vehicle.dwell != 0) continue; LaneChoice desired = desiredLane(vehicle);
                if (desired.lane() != lane && reserved.add(new Cell(desired.lane(),vehicle.cell))) changes.add(new LaneChange(vehicle,desired.lane(),desired.kind()));
            }
        }
        for (LaneChange change : changes) { Vehicle vehicle = change.vehicle(); Segment segment = vehicle.segment; vehicle.place(segment,change.lane(),vehicle.cell); vehicle.laneChanges++; segment.changes[change.kind()]++; }
    }
    int determineSpeed(Vehicle vehicle, int step) {
        Segment segment = vehicle.segment; int accelerated = Math.min(vehicle.speed + 1,vehicle.maxSpeed()), gap = segment.free(vehicle.lane,vehicle.cell,accelerated);
        if (gap < accelerated && vehicle.cell + gap == segment.length - 1) {
            if (segment.junction == null) gap = accelerated;
            else if (segment.junction.green(segment.id,step)) { Segment target = vehicle.turn.target; gap += target.free(Math.min(vehicle.lane,target.lanes),-1,accelerated - gap); }
        }
        if (vehicle.headingForStop()) gap = Math.min(gap,segment.stop.cell - vehicle.cell);
        int speed = Vehicle.slowdown(Math.min(accelerated,gap),vehicle.speed,rng.draw(),dawdle,stopped);
        if (vehicle.dwell != 0) { speed = 0; vehicle.dwell--; } return speed;
    }
    List<Move> processingOrder() {
        List<Move> result = new ArrayList<>(); for (Segment segment : segments) for (int lane = 1; lane <= segment.lanes; lane++) for (int number : segment.numbers(lane).reversed()) result.add(new Move(vehicles.get(number - 1))); return result;
    }
    List<Move> moveVehicles(List<Move> moves, int step) {
        List<Move> passing = new ArrayList<>();
        for (Move move : moves) {
            Vehicle vehicle = move.vehicle; Segment segment = move.segment;
            if (move.cell + move.speed < segment.length) vehicle.place(segment,vehicle.lane,move.cell + move.speed);
            else if (segment.junction == null) { vehicle.leave(); vehicle.exited = step; vehicle.sink = segment.end; intervals.getLast().exits++; }
            else passing.add(move);
        }
        return passing;
    }
    void passJunctions(List<Move> passing) {
        for (Move move : passing) {
            Vehicle vehicle = move.vehicle; Segment segment = move.segment, target = vehicle.turn.target;
            int lane = Math.min(vehicle.lane,target.lanes), overshoot = move.cell + move.speed - segment.length, cell = Math.min(overshoot,target.first(lane) - 1);
            if (cell < overshoot) segment.blocked++;
            if (cell >= 0) { vehicle.place(target,lane,cell); move.speed = segment.length - move.cell + cell; segment.passed++; vehicle.turn.vehicles++; enter(vehicle,target); }
            else { vehicle.place(segment,vehicle.lane,segment.length - 1); move.speed = segment.length - 1 - move.cell; }
        }
    }
    void aggregateVehicle(Move move, int step) {
        Vehicle vehicle = move.vehicle; Interval interval = intervals.getLast(); vehicle.steps++; vehicle.distance += move.speed;
        if (move.speed == 0) { vehicle.stoppedSteps++; if (vehicle.speed > 0) vehicle.stopCount++; } vehicle.speed = move.speed; interval.vehicleSteps++; interval.speedSum += move.speed;
        if (vehicle.headingForStop() && vehicle.lane == 1 && vehicle.cell == vehicle.segment.stop.cell) {
            BusStop stop = vehicle.segment.stop; vehicle.completedStops.add(vehicle.segment.id); vehicle.dwell = stop.dwell; stop.buses++; record(step,line("BUS_STOP",vehicle.number,vehicle.segment.id,"cell",stop.cell));
        }
        List<String> track = tracks.get((long)vehicle.number); if (track != null) track.add(time(step) + " " + (vehicle.segment == null ? line("EXIT",vehicle.speed) : line(vehicle.segment.id,vehicle.lane,vehicle.cell,vehicle.speed)));
        for (int i = 0; i < detectors.size(); i++) { Detector d = detectors.get(i); if (move.segment == d.segment() && move.cell < d.cell() && (vehicle.segment != d.segment() || vehicle.cell >= d.cell())) interval.passing[i]++; }
    }
    void aggregateState(int step) {
        Interval interval = intervals.getLast();
        for (int i = 0; i < detectors.size(); i++) { Detector d = detectors.get(i); for (Vehicle vehicle : vehiclesOn(d.segment())) if (vehicle.cell >= d.cell() && vehicle.cell < d.cell() + d.width()) { interval.occupancy[i]++; interval.occupancySpeed[i] += vehicle.speed; } }
        for (Segment segment : segments) {
            List<Vehicle> present = vehiclesOn(segment); segment.vehicleSum += present.size(); segment.speedSum += present.stream().mapToLong(v -> v.speed).sum(); segment.maxVehicles = Math.max(segment.maxVehicles,present.size());
            if (segment.junction == null) continue; boolean green = segment.junction.green(segment.id,step); if (green) segment.greenSteps++;
            long queued = present.stream().filter(v -> v.speed == 0).count(); segment.queueSum += queued; segment.maxQueue = Math.max(segment.maxQueue,queued);
            if (step < steps && queued > 0 && green && !segment.junction.green(segment.id,step + 1)) segment.failures++;
        }
        for (Diagram diagram : diagrams) if (diagram.start <= step && step <= diagram.end) {
            Segment segment = diagram.segment; String signal = segment.junction == null ? "E" : segment.junction.green(segment.id,step) ? "G" : "R"; diagram.lines.add(time(step) + " " + segment.text(diagram.lane,vehicles) + " " + signal);
        }
    }
    void run() {
        rng.state = seed;
        for (int step = 1; step <= steps; step++) {
            for (Incident incident : incidents) { String text = incident.update(step); if (!text.isEmpty()) record(step,line(text,incident.segment.id,"lane",incident.lane,"cell",incident.cell)); }
            if ((step - 1) % intervalLength == 0) intervals.add(new Interval(detectors.size())); arrive(step); insert(step); changeLanes(); List<Move> moves = processingOrder();
            for (Move move : moves) move.speed = determineSpeed(move.vehicle,step); passJunctions(moveVehicles(moves,step)); for (Move move : moves) aggregateVehicle(move,step); aggregateState(step);
        }
        for (Source source : sources) if (source.start != 0) record(steps,line("QUEUE",source.node,"from",source.start,"max",source.maximum,"open"));
    }
    List<Route> enumerateRoutes(Segment segment) {
        if (segment.junction == null) return List.of(new Route(List.of(segment.id),new Share(1))); long total = segment.turns.stream().mapToLong(t -> t.weight).sum(); List<Route> routes = new ArrayList<>();
        for (Turn turn : segment.turns) for (Route child : enumerateRoutes(turn.target)) { List<String> route = new ArrayList<>(); route.add(segment.id); route.addAll(child.segments()); routes.add(new Route(route,child.share().times(turn.weight,total))); } return routes;
    }
    List<String> travelBlock(String heading, List<Vehicle> group) {
        List<Long> times = group.stream().map(v -> (long)v.travelTime()).sorted().toList(); if (times.isEmpty()) return List.of(heading + " exited 0");
        List<String> result = new ArrayList<>(); result.add(line(heading,"exited",times.size(),"min",times.getFirst(),"p50",Stats.percentile(times,50),"p90",Stats.percentile(times,90),"max",times.getLast(),"mean",Stats.dec(times.stream().mapToLong(Long::longValue).sum(),times.size(),2))); result.addAll(Stats.histogram(times,binWidth)); return result;
    }
    static String outcome(List<Vehicle> group, int total) { return line("vehicles",group.size(),"share",Stats.frac(group.size(),total),"mean",Stats.dec(group.stream().mapToLong(Vehicle::travelTime).sum(),group.size(),2)); }
    List<String> travelLines() {
        List<Vehicle> exited = vehicles.stream().filter(v -> v.exited != 0).toList(); List<String> result = new ArrayList<>();
        for (VehicleClass kind : classes) result.addAll(travelBlock("CLASS " + kind.name(),exited.stream().filter(v -> v.kind == kind).toList())); result.addAll(travelBlock("ALL",exited));
        for (Source source : sources) {
            List<Vehicle> group = exited.stream().filter(v -> v.source.equals(source.node)).toList(); result.add(line("SOURCE",source.node,"exited",group.size())); List<Route> routes = enumerateRoutes(source.segment);
            for (Route route : routes) result.add("  ROUTE " + String.join(",",route.segments()) + " expected " + route.share() + " " + outcome(group.stream().filter(v -> v.route.equals(route.segments())).toList(),group.size()));
            for (String sink : sinks) {
                List<Share> shares = routes.stream().filter(r -> segmentById.get(r.segments().getLast()).end.equals(sink)).map(Route::share).toList(); if (shares.isEmpty()) continue;
                Share expected = new Share(0); for (Share share : shares) expected = expected.plus(share); result.add("  SINK " + sink + " expected " + expected + " " + outcome(group.stream().filter(v -> v.sink.equals(sink)).toList(),group.size()));
            }
        }
        return result;
    }
    static List<String> classBlock(String heading, List<Vehicle> group) {
        long inserted = group.stream().filter(v -> v.inserted != 0).count(); List<Vehicle> exited = group.stream().filter(v -> v.exited != 0).toList(); int count = exited.size();
        long vehicleSteps = group.stream().mapToLong(v -> v.steps).sum(), distance = group.stream().mapToLong(v -> v.distance).sum();
        return List.of(heading,"  " + line("generated",group.size(),"inserted",inserted,"exited",count,"in_network",inserted - count,"queued",group.size() - inserted),"  " + line("vehicle_steps",vehicleSteps,"distance",distance,"mean_speed",Stats.frac(distance,vehicleSteps),"=",Stats.dec(distance,vehicleSteps,3)),"  " + line("travel",Stats.dec(exited.stream().mapToLong(Vehicle::travelTime).sum(),count,2),"entry_delay",Stats.dec(exited.stream().mapToLong(v -> v.inserted - v.arrival).sum(),count,2),"stopped",Stats.dec(exited.stream().mapToLong(v -> v.stoppedSteps).sum(),count,2),"stops",Stats.dec(exited.stream().mapToLong(v -> v.stopCount).sum(),count,2),"lane_changes",Stats.dec(exited.stream().mapToLong(v -> v.laneChanges).sum(),count,2)));
    }
    List<String> classLines() {
        List<String> result = new ArrayList<>(); for (VehicleClass kind : classes) result.addAll(classBlock(line("CLASS",kind.name(),"vmax",kind.vmax(),"weight",kind.weight(),"overtake",kind.overtakes() ? "Y" : "N","stops",kind.stops() ? "Y" : "N"),vehicles.stream().filter(v -> v.kind == kind).toList())); result.addAll(classBlock("ALL",vehicles)); return result;
    }
    List<String> networkLines() {
        List<String> result = new ArrayList<>();
        for (Segment s : segments) result.add(line("SEGMENT",s.id,s.start,s.end,"length",s.length,"lanes",s.lanes,"limit",s.limit,"entered",s.entered,"mean_vehicles",Stats.dec(s.vehicleSum,steps,3),"density",Stats.dec(s.vehicleSum,(long)steps * s.length * s.lanes,4),"mean_speed",Stats.dec(s.speedSum,s.vehicleSum,2),"max_vehicles",s.maxVehicles,"changes",s.changes[0] + "/" + s.changes[1] + "/" + s.changes[2]));
        for (Junction junction : junctions) {
            result.addAll(junction.planLines());
            for (Segment s : junction.incoming) { result.add("  " + line("IN",s.id,"green",s.greenSteps,"passed",s.passed,"blocked",s.blocked,"max_queue",s.maxQueue,"mean_queue",Stats.dec(s.queueSum,steps,3),"failures",s.failures)); for (Turn turn : s.turns) result.add("    " + line("TURN",turn.target.id,"weight",turn.weight,"vehicles",turn.vehicles)); }
        }
        for (BusStop stop : stops) result.add(line("STOP",stop.segment.id,"cell",stop.cell,"dwell",stop.dwell,"buses",stop.buses));
        for (Incident incident : incidents) result.add(line("INCIDENT",incident.segment.id,"lane",incident.lane,"cell",incident.cell,"planned",incident.start + "-" + incident.end,"active",incident.activeStart == 0 ? "none" : incident.activeStart + "-" + incident.activeEnd)); return result;
    }
    List<String> detectorLines() {
        List<String> result = new ArrayList<>(List.of("detector,interval,flow,density,speed"));
        for (int i = 0; i < detectors.size(); i++) for (int k = 0; k < intervals.size(); k++) { Interval a = intervals.get(k); Detector d = detectors.get(i); result.add(d.name() + "," + (k + 1) + "," + a.passing[i] + "," + Stats.dec(a.occupancy[i],(long)intervalLength * d.width() * d.segment().lanes,4) + "," + Stats.dec(a.occupancySpeed[i],a.occupancy[i],2)); } return result;
    }
    List<String> timelineLines() {
        List<String> result = new ArrayList<>(List.of("interval,arrived,inserted,exited,in_network,queued,mean_speed")); long arrived = 0, inserted = 0, exited = 0;
        for (int k = 0; k < intervals.size(); k++) { Interval a = intervals.get(k); arrived += a.arrivals; inserted += a.insertions; exited += a.exits; result.add((k + 1) + "," + a.arrivals + "," + a.insertions + "," + a.exits + "," + (inserted - exited) + "," + (arrived - inserted) + "," + Stats.dec(a.speedSum,a.vehicleSteps,2)); } return result;
    }
    List<String> trackLines() {
        List<String> result = new ArrayList<>();
        for (long number : trackNumbers) {
            if (number > vehicles.size()) { result.add(line("VEHICLE",number,"none")); continue; } Vehicle vehicle = vehicles.get((int)number - 1);
            result.add(line("VEHICLE",number,"class",vehicle.kind.name(),"source",vehicle.source,"arrival",vehicle.arrival,"inserted",optional(vehicle.inserted),"exited",optional(vehicle.exited),"sink",vehicle.sink.isEmpty() ? "-" : vehicle.sink)); result.add("ROUTE " + (vehicle.route.isEmpty() ? "-" : String.join(" ",vehicle.route))); result.addAll(tracks.get(number));
        }
        return result;
    }
    static long runRing(Ring ring, int count, int dawdle, int stopped) {
        Minstd rng = new Minstd(ring.seed()); int[] positions = IntStream.range(0,count).map(i -> i * ring.length() / count).toArray(), speeds = new int[count]; long total = 0;
        for (int step = 1; step <= ring.warmup() + ring.measure(); step++) {
            List<Integer> order = IntStream.range(0,count).boxed().sorted(Comparator.comparingInt((Integer i) -> positions[i]).reversed()).toList(); int[] updated = new int[count];
            for (int rank = 0; rank < count; rank++) { int i = order.get(rank), ahead = order.get(rank == 0 ? count - 1 : rank - 1), gap = (positions[ahead] - positions[i] - 1 + ring.length()) % ring.length(); updated[i] = Vehicle.slowdown(Math.min(Math.min(speeds[i] + 1,ring.vmax()),gap),speeds[i],rng.draw(),dawdle,stopped); }
            for (int i = 0; i < count; i++) positions[i] = (positions[i] + updated[i]) % ring.length(); speeds = updated; if (step > ring.warmup()) total += Arrays.stream(speeds).asLongStream().sum();
        }
        return total;
    }
    List<String> fundamentalLines() {
        List<String> result = new ArrayList<>(List.of("ring,vehicles,density,flow,speed")); for (Ring ring : rings) for (int count : ring.counts()) { long total = runRing(ring,count,dawdle,stopped); result.add(ring.number() + "," + count + "," + Stats.dec(count,ring.length(),4) + "," + Stats.dec(total,(long)ring.length() * ring.measure(),4) + "," + Stats.dec(total,(long)count * ring.measure(),3)); } return result;
    }
    void write() throws IOException {
        List<String> spacetime = new ArrayList<>(); for (Diagram diagram : diagrams) { spacetime.add(line("DIAGRAM",diagram.segment.id,"lane",diagram.lane,"steps",diagram.start + "-" + diagram.end)); spacetime.addAll(diagram.lines); }
        List<Output> outputs = List.of(new Output("spacetime.txt",spacetime),new Output("detectors.csv",detectorLines()),new Output("travel_times.txt",travelLines()),new Output("class_stats.txt",classLines()),new Output("network_stats.txt",networkLines()),new Output("timeline.csv",timelineLines()),new Output("tracks.txt",trackLines()),new Output("fundamental.csv",fundamentalLines()),new Output("events.txt",events));
        Files.createDirectories(Path.of("output")); for (Output output : outputs) Files.writeString(Path.of("output",output.name()),String.join("\n",output.lines()) + (output.lines().isEmpty() ? "" : "\n"),StandardCharsets.US_ASCII);
    }
}
public class Main {
    public static void main(String[] args) throws IOException { Locale.setDefault(Locale.ROOT); Simulation simulation = new Simulation(); simulation.run(); simulation.write(); }
}
