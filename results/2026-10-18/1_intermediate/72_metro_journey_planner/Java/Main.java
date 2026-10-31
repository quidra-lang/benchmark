import java.io.*;
import java.util.*;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super("ERROR " + message);
        }
    }

    static class Station {
        final String id, name;
        final int zone;
        int transfer;
        boolean closed;
        final TreeMap<String, Integer> walks = new TreeMap<>();
        Station(String id, int zone, String name) {
            this.id = id;
            this.zone = zone;
            this.name = name;
        }
    }

    static class Line {
        final String id;
        final int first, last, headway;
        final List<Station> stops;
        final int[] cumulative;
        int delay;
        boolean suspended;
        Line(String id, int first, int last, int headway, List<Station> stops, int[] cumulative) {
            this.id = id;
            this.first = first;
            this.last = last;
            this.headway = headway;
            this.stops = List.copyOf(stops);
            this.cumulative = cumulative.clone();
        }
        int total() {
            return cumulative[cumulative.length - 1];
        }
        int trips() {
            return (last - first) / headway + 1;
        }
        Station stop(int direction, int index) {
            return stops.get(direction == 0 ? index : stops.size() - 1 - index);
        }
        int offset(int direction, int index) {
            return direction == 0 ? cumulative[index] : total() - cumulative[stops.size() - 1 - index];
        }
        int position(int direction, Station station) {
            int index = stops.indexOf(station);
            return index < 0 ? -1 : direction == 0 ? index : stops.size() - 1 - index;
        }
        int time(int direction, int index, int train) {
            return first + delay + train * headway + offset(direction, index);
        }
        int next(int direction, int index, int ready) {
            int start = time(direction, index, 0);
            int train = ready <= start ? 0 : (ready - start + headway - 1) / headway;
            return train < trips() ? train : -1;
        }
    }

    record Segment(String low, String high) {}

    record Leg(char kind, Line line, Station terminal, Station from, int departure, Station to, int arrival, int stops) {}

    record Label(int time, List<Leg> journey) {}

    record Departure(int time, Line line, int direction) {}

    static final TreeMap<String, Station> stations = new TreeMap<>();
    static final TreeMap<String, Line> lines = new TreeMap<>();
    static final Set<Segment> closedSegments = new HashSet<>();

    static int[] prices;

    static int discount, window;

    static void require(boolean valid, String reason) {
        if (!valid) throw new Problem(reason);
    }

    static Station station(String id) {
        Station result = stations.get(id);
        require(result != null, "unknown station " + id);
        return result;
    }

    static Line line(String id) {
        Line result = lines.get(id);
        require(result != null, "unknown line " + id);
        return result;
    }

    static int time(String text) {
        return Integer.parseInt(text.substring(0, 2)) * 60 + Integer.parseInt(text.substring(3));
    }

    static String clock(int time) {
        return String.format(Locale.ROOT, "%02d:%02d", time / 60, time % 60);
    }

    static Segment segment(Station a, Station b) {
        return a.id.compareTo(b.id) <= 0 ? new Segment(a.id, b.id) : new Segment(b.id, a.id);
    }

    static boolean blocked(Station a, Station b) {
        return closedSegments.contains(segment(a, b));
    }

    static List<Leg> append(List<Leg> journey, Leg leg) {
        List<Leg> result = new ArrayList<>(journey);
        result.add(leg);
        return result;
    }

    static void relax(Map<Station, Label> labels, Station destination, int arrival, List<Leg> journey, Leg leg) {
        if (!labels.containsKey(destination) || labels.get(destination).time() > arrival) labels.put(destination, new Label(arrival, append(journey, leg)));
    }

    static Map<Station, Label> earliest(Station origin, int departure) {
        Map<Station, Label> labels = new HashMap<>();
        Set<Station> settled = new HashSet<>();
        labels.put(origin, new Label(departure, List.of()));
        while (true) {
            Station selected = null;
            for (Station station : stations.values()) if (!settled.contains(station) && labels.containsKey(station) && (selected == null || labels.get(station).time() < labels.get(selected).time())) selected = station;
            if (selected == null) return labels;
            Station u = selected;
            settled.add(u);
            Label label = labels.get(u);
            int ready = label.time() + (u == origin ? 0 : u.transfer);
            for (Line line : lines.values()) if (!line.suspended && line.stops.contains(u)) for (int direction = 0; direction < 2; direction++) {
                int i = line.position(direction, u), last = line.stops.size() - 1;
                if (i == last) continue;
                int train = line.next(direction, i, ready);
                if (train < 0) continue;
                int start = line.time(direction, i, train);
                for (int j = i + 1; j <= last; j++) {
                    Station v = line.stop(direction, j);
                    if (blocked(line.stop(direction, j - 1), v)) break;
                    if (v.closed) continue;
                    int arrival = line.time(direction, j, train);
                    relax(labels, v, arrival, label.journey(), new Leg('R', line, line.stop(direction, last), u, start, v, arrival, j - i));
                }
            }
            for (var walk : u.walks.entrySet()) {
                Station v = stations.get(walk.getKey());
                int arrival = label.time() + walk.getValue();
                if (!v.closed && arrival <= 1440) relax(labels, v, arrival, label.journey(), new Leg('W', null, null, u, label.time(), v, arrival, 0));
            }
        }
    }

    static void walkStep(Map<Station, Label> labels, Set<Station> origins, Set<Station> marked) {
        Map<Station, Label> recorded = new HashMap<>();
        for (Station origin : origins) recorded.put(origin, labels.get(origin));
        for (Station u : stations.values()) if (origins.contains(u)) for (var walk : u.walks.entrySet()) {
            Label label = recorded.get(u);
            Station v = stations.get(walk.getKey());
            int arrival = label.time() + walk.getValue();
            if (!v.closed && arrival <= 1440 && (!labels.containsKey(v) || labels.get(v).time() > arrival)) {
                labels.put(v, new Label(arrival, append(label.journey(), new Leg('W', null, null, u, label.time(), v, arrival, 0))));
                marked.add(v);
            }
        }
    }

    static List<Map<Station, Label>> rounds(Station origin, int departure) {
        List<Map<Station, Label>> result = new ArrayList<>();
        Map<Station, Label> previous = new HashMap<>();
        previous.put(origin, new Label(departure, List.of()));
        Set<Station> marked = new HashSet<>();
        marked.add(origin);
        walkStep(previous, Set.of(origin), marked);
        result.add(previous);
        while (!marked.isEmpty()) {
            Map<Station, Label> current = new HashMap<>(previous);
            Set<Station> updated = new HashSet<>(), walks = new HashSet<>();
            for (Line line : lines.values()) if (!line.suspended) for (int direction = 0; direction < 2; direction++) {
                int boarded = -1, boardIndex = -1, boardTime = 0, last = line.stops.size() - 1;
                List<Leg> boardJourney = null;
                for (int j = 0; j <= last; j++) {
                    Station u = line.stop(direction, j);
                    if (j > 0 && blocked(line.stop(direction, j - 1), u)) boarded = -1;
                    if (u.closed) continue;
                    if (boarded >= 0) {
                        int arrival = line.time(direction, j, boarded);
                        if (!current.containsKey(u) || current.get(u).time() > arrival) {
                            current.put(u, new Label(arrival, append(boardJourney, new Leg('R', line, line.stop(direction, last), line.stop(direction, boardIndex), boardTime, u, arrival, j - boardIndex))));
                            walks.add(u);
                            updated.add(u);
                        }
                    }
                    if (j < last && marked.contains(u)) {
                        Label label = previous.get(u);
                        int ready = label.time() + (u == origin ? 0 : u.transfer), train = line.next(direction, j, ready);
                        if (train >= 0 && (boarded < 0 || train < boarded)) {
                            boarded = train;
                            boardIndex = j;
                            boardTime = line.time(direction, j, train);
                            boardJourney = label.journey();
                        }
                    }
                }
            }
            walkStep(current, walks, updated);
            result.add(current);
            previous = current;
            marked = updated;
        }
        return result;
    }

    static int rides(List<Leg> journey) {
        return (int)journey.stream().filter(leg -> leg.kind() == 'R').count();
    }

    static void printJourney(String heading, int departure, Label label) {
        long walks = label.journey().stream().filter(leg -> leg.kind() == 'W').count();
        System.out.println(heading + " " + clock(departure) + " -> " + clock(label.time()) + " total " + (label.time() - departure) + " rides " + rides(label.journey()) + " walks " + walks);
        int previous = departure;
        for (Leg leg : label.journey()) {
            if (leg.kind() == 'R') System.out.println("RIDE " + leg.line().id + " toward " + leg.terminal().id + " " + leg.from().id + " " + clock(leg.departure()) + " -> " + leg.to().id + " " + clock(leg.arrival()) + " wait " + (leg.departure() - previous) + " stops " + leg.stops());
            else if (leg.kind() == 'W') System.out.println("WALK " + leg.from().id + " " + clock(leg.departure()) + " -> " + leg.to().id + " " + clock(leg.arrival()));
            else System.out.println("STAY " + leg.from().id + " " + clock(leg.departure()) + " -> " + clock(leg.arrival()));
            previous = leg.arrival();
        }
    }

    static void searchCheck(Station origin, Station destination) {
        require(origin != destination, "origin and destination are the same");
        require(!origin.closed, "station " + origin.id + " is closed");
        require(!destination.closed, "station " + destination.id + " is closed");
    }

    static int direction(Line line, String terminal) {
        require(line.stops.getFirst().id.equals(terminal) || line.stops.getLast().id.equals(terminal), terminal + " is not a terminal of line " + line.id);
        return line.stops.getLast().id.equals(terminal) ? 0 : 1;
    }

    static int half(int price) {
        return (price + 19) / 20 * 10;
    }

    static void fare(String heading, Station origin, Station destination, int departure, String fareClass) {
        Label label = earliest(origin, departure).get(destination);
        if (label == null) {
            System.out.println(heading + " unreachable");
            return;
        }
        List<String> tickets = new ArrayList<>();
        int total = 0, lastRide = -1;
        boolean child = fareClass.equals("CHILD");
        for (Leg leg : label.journey()) if (leg.kind() == 'R') {
            Line line = leg.line();
            int a = line.stops.indexOf(leg.from()), b = line.stops.indexOf(leg.to());
            Set<Integer> zones = new HashSet<>();
            for (int i = Math.min(a, b); i <= Math.max(a, b); i++) zones.add(line.stops.get(i).zone);
            int price = prices[Math.min(zones.size(), prices.length) - 1];
            if (child) price = half(price);
            int reduction = lastRide >= 0 && leg.departure() - lastRide <= window ? Math.min(price, child ? half(discount) : discount) : 0;
            int pay = price - reduction;
            total += pay;
            tickets.add("TICKET " + line.id + " " + leg.from().id + " " + leg.to().id + " zones " + zones.size() + " price " + price + " discount " + reduction + " pay " + pay);
            lastRide = leg.arrival();
        }
        System.out.println(heading + " rides " + rides(label.journey()) + " total " + total);
        tickets.forEach(System.out::println);
    }

    static void command(String[] w) {
        String command = w[0];
        switch (command) {
            case "STATION":
                require(!stations.containsKey(w[1]), "station " + w[1] + " already exists");
                stations.put(w[1], new Station(w[1], Integer.parseInt(w[2]), w[3]));
                System.out.println("STATION " + w[1] + " zone " + w[2] + " " + w[3]);
                return;
            case "LINE":
                {
                    require(!lines.containsKey(w[1]), "line " + w[1] + " already exists");
                    List<Station> stops = new ArrayList<>();
                    for (int i = 5; i < w.length; i += 2) stops.add(station(w[i]));
                    Set<Station> seen = new HashSet<>();
                    for (Station stop : stops) require(seen.add(stop), "station " + stop.id + " appears twice on line " + w[1]);
                    int first = time(w[2]), last = time(w[3]);
                    require(first <= last, "line " + w[1] + " first departure is after last departure");
                    int[] cumulative = new int[stops.size()];
                    for (int i = 1; i < stops.size(); i++) cumulative[i] = cumulative[i - 1] + Integer.parseInt(w[4 + 2 * i]);
                    require(last + cumulative[cumulative.length - 1] <= 1440, "line " + w[1] + " runs past 24:00");
                    Line line = new Line(w[1], first, last, Integer.parseInt(w[4]), stops, cumulative);
                    lines.put(w[1], line);
                    System.out.println("LINE " + line.id + " stops " + stops.size() + " time " + line.total() + " trips " + line.trips());
                    return;
                }
            case "TRANSFER":
                {
                    Station station = station(w[1]);
                    station.transfer = Integer.parseInt(w[2]);
                    System.out.println("TRANSFER " + w[1] + " " + w[2]);
                    return;
                }
            case "WALK":
                {
                    Station a = station(w[1]), b = station(w[2]);
                    require(a != b, "walk from " + a.id + " to itself");
                    Integer before = a.walks.get(b.id);
                    int minutes = Integer.parseInt(w[3]);
                    a.walks.put(b.id, minutes);
                    b.walks.put(a.id, minutes);
                    System.out.println("WALK " + a.id + " " + b.id + " " + minutes + (before == null ? "" : " was " + before));
                    return;
                }
            case "TARIFF":
                {
                    int[] added = Arrays.stream(w).skip(3).mapToInt(Integer::parseInt).toArray();
                    for (int i = 1; i < added.length; i++) require(added[i] >= added[i - 1], "tariff prices must not decrease");
                    prices = added;
                    discount = Integer.parseInt(w[1]);
                    window = Integer.parseInt(w[2]);
                    System.out.println("TARIFF zones " + prices.length + " discount " + discount + " window " + window);
                    return;
                }
            case "CLOSE":
            case "OPEN":
                {
                    Station a = station(w[1]);
                    boolean close = command.equals("CLOSE");
                    if (w.length == 2) {
                        require(close != a.closed, "station " + a.id + (close ? " is already closed" : " is not closed"));
                        a.closed = close;
                        System.out.println(command + " " + a.id);
                    } else {
                        Station b = station(w[2]);
                        Segment key = segment(a, b);
                        List<String> containing = new ArrayList<>();
                        if (close) {
                            for (Line line : lines.values()) for (int i = 1; i < line.stops.size(); i++) if (segment(line.stops.get(i - 1), line.stops.get(i)).equals(key)) {
                                containing.add(line.id);
                                break;
                            }
                            require(!containing.isEmpty(), "no segment " + a.id + "-" + b.id);
                        }
                        require(close != closedSegments.contains(key), "segment " + a.id + "-" + b.id + (close ? " is already closed" : " is not closed"));
                        if (close) closedSegments.add(key);
                        else closedSegments.remove(key);
                        System.out.println(command + " " + a.id + "-" + b.id + (close ? " lines " + String.join(" ", containing) : ""));
                    }
                    return;
                }
            case "DELAY":
                {
                    Line line = line(w[1]);
                    int delay = Integer.parseInt(w[2]);
                    require(line.last + delay + line.total() <= 1440, "line " + line.id + " runs past 24:00");
                    line.delay = delay;
                    System.out.println("DELAY " + line.id + " " + delay);
                    return;
                }
            case "SUSPEND":
            case "RESUME":
                {
                    Line line = line(w[1]);
                    boolean suspend = command.equals("SUSPEND");
                    require(line.suspended != suspend, "line " + line.id + (suspend ? " is already suspended" : " is not suspended"));
                    line.suspended = suspend;
                    System.out.println(command + " " + line.id);
                    return;
                }
            case "VIA":
                {
                    Station origin = station(w[1]), via = station(w[2]), destination = station(w[3]);
                    require(origin != destination, "origin and destination are the same");
                    require(via != origin && via != destination, "via station " + via.id + " must differ from origin and destination");
                    for (Station station : List.of(origin, via, destination)) require(!station.closed, "station " + station.id + " is closed");
                    int departure = time(w[4]);
                    Label first = earliest(origin, departure).get(via), result = null;
                    if (first != null) {
                        int ready = first.time() + via.transfer;
                        Label second = earliest(via, ready).get(destination);
                        if (second != null) {
                            List<Leg> journey = append(first.journey(), new Leg('S', null, null, via, first.time(), via, ready, 0));
                            journey.addAll(second.journey());
                            result = new Label(second.time(), journey);
                        }
                    }
                    String heading = "VIA " + origin.id + " " + via.id + " " + destination.id;
                    if (result == null) System.out.println(heading + " " + clock(departure) + " unreachable");
                    else printJourney(heading, departure, result);
                    return;
                }
            case "REACH":
                {
                    Station origin = station(w[1]);
                    require(!origin.closed, "station " + origin.id + " is closed");
                    int departure = time(w[2]), limit = departure + Integer.parseInt(w[3]);
                    var labels = earliest(origin, departure);
                    List<Station> reached = stations.values().stream().filter(station -> labels.containsKey(station) && labels.get(station).time() <= limit).sorted(Comparator.comparingInt((Station s) -> labels.get(s).time()).thenComparing(s -> s.id)).toList();
                    System.out.println("REACH " + origin.id + " " + w[2] + " " + w[3] + " count " + reached.size());
                    for (Station s : reached) System.out.println(s.id + " " + s.name + " " + clock(labels.get(s).time()) + " " + (labels.get(s).time() - departure) + " rides " + rides(labels.get(s).journey()));
                    return;
                }
            case "TIMETABLE":
                {
                    Station station = station(w[1]);
                    Line line = line(w[2]);
                    require(line.stops.contains(station), "station " + station.id + " is not on line " + line.id);
                    int direction = direction(line, w[3]);
                    require(!station.id.equals(w[3]), "no departures from " + station.id + " toward " + w[3]);
                    require(!line.suspended, "line " + line.id + " is suspended");
                    require(!station.closed, "station " + station.id + " is closed");
                    int position = line.position(direction, station), start = line.next(direction, position, time(w[4])), count = Integer.parseInt(w[5]);
                    List<String> times = new ArrayList<>();
                    if (start >= 0) for (int q = start; q < line.trips() && times.size() < count; q++) times.add(clock(line.time(direction, position, q)));
                    System.out.println("TIMETABLE " + station.id + " " + line.id + " toward " + w[3] + " " + w[4] + " next " + times.size() + (times.isEmpty() ? "" : " " + String.join(" ", times)));
                    return;
                }
            case "DEPARTURES":
            case "ARRIVALS":
                {
                    Station station = station(w[1]);
                    require(!station.closed, "station " + station.id + " is closed");
                    boolean arrivals = command.equals("ARRIVALS");
                    List<Departure> departures = new ArrayList<>();
                    for (Line line : lines.values()) if (!line.suspended && line.stops.contains(station)) for (int direction = 0; direction < 2; direction++) {
                        int position = line.position(direction, station);
                        if (arrivals ? position == 0 : position == line.stops.size() - 1) continue;
                        int start = line.next(direction, position, time(w[2]));
                        if (start >= 0) for (int q = start; q < line.trips(); q++) departures.add(new Departure(line.time(direction, position, q), line, direction));
                    }
                    departures.sort(Comparator.comparingInt(Departure::time).thenComparing(d -> d.line().id).thenComparingInt(Departure::direction));
                    int count = Math.min(Integer.parseInt(w[3]), departures.size());
                    System.out.println(command + " " + station.id + " " + w[2] + " count " + count);
                    for (Departure d : departures.subList(0, count)) System.out.println(clock(d.time()) + " " + d.line().id + (arrivals ? " from " + d.line().stop(d.direction(), 0).id : " toward " + d.line().stop(d.direction(), d.line().stops.size() - 1).id));
                    return;
                }
            case "TRIP":
                {
                    Line line = line(w[1]);
                    int direction = direction(line, w[2]);
                    require(!line.suspended, "line " + line.id + " is suspended");
                    int train = line.next(direction, 0, time(w[3]));
                    String heading = "TRIP " + line.id + " toward " + w[2] + " " + w[3];
                    if (train < 0) System.out.println(heading + " none");
                    else {
                        System.out.println(heading + " trip " + (train + 1) + " departs " + clock(line.time(direction, 0, train)));
                        for (int j = 0; j < line.stops.size(); j++) {
                            Station s = line.stop(direction, j);
                            System.out.println(clock(line.time(direction, j, train)) + " " + s.id + (s.closed ? " closed" : "") + (j > 0 && blocked(line.stop(direction, j - 1), s) ? " blocked" : ""));
                        }
                    }
                    return;
                }
            case "SHOWLINE":
                {
                    Line line = line(w[1]);
                    System.out.println("SHOWLINE " + line.id + " " + (line.suspended ? "suspended" : "running") + " first " + clock(line.first) + " last " + clock(line.last) + " headway " + line.headway + " delay " + line.delay + " trips " + line.trips());
                    for (int j = 0; j < line.stops.size(); j++) {
                        Station s = line.stops.get(j);
                        System.out.println(line.cumulative[j] + " " + s.id + " zone " + s.zone + (s.closed ? " closed" : "") + (j > 0 && blocked(line.stops.get(j - 1), s) ? " blocked" : ""));
                    }
                    return;
                }
            case "INFO":
                {
                    Station station = station(w[1]);
                    System.out.println("INFO " + station.id + " " + station.name + " zone " + station.zone + " transfer " + station.transfer + " " + (station.closed ? "closed" : "open"));
                    List<String> containing = lines.values().stream().filter(line -> line.stops.contains(station)).map(line -> line.id).toList();
                    System.out.println("LINES " + (containing.isEmpty() ? "none" : String.join(" ", containing)));
                    List<String> walks = station.walks.entrySet().stream().map(e -> e.getKey() + " " + e.getValue()).toList();
                    System.out.println("WALKS " + (walks.isEmpty() ? "none" : String.join(" ", walks)));
                    return;
                }
                case "STATUS": System.out.println("STATUS stations " + stations.size() + " lines " + lines.size() + " walks " + stations.values().stream().mapToInt(s -> s.walks.size()).sum() / 2);
                for (Station s : stations.values()) if (s.closed) System.out.println("CLOSED " + s.id);
                closedSegments.stream().sorted(Comparator.comparing(Segment::low).thenComparing(Segment::high)).forEach(s -> System.out.println("CLOSED " + s.low() + "-" + s.high()));
                for (Line line : lines.values()) if (line.suspended) System.out.println("SUSPENDED " + line.id);
                for (Line line : lines.values()) if (line.delay != 0) System.out.println("DELAYED " + line.id + " " + line.delay);
                return;
        }
        Station origin = station(w[1]), destination = station(w[2]);
        searchCheck(origin, destination);
        String heading = command + " " + origin.id + " " + destination.id;
        if (command.equals("FARE")) {
            require(w[4].equals("ADULT") || w[4].equals("CHILD"), "unknown fare class " + w[4]);
            require(prices != null, "no tariff");
            fare(heading + " " + w[3] + " " + w[4], origin, destination, time(w[3]), w[4]);
            return;
        }
        if (command.equals("LASTTRAIN") || command.equals("ARRIVEBY")) {
            int deadline = command.equals("LASTTRAIN") ? 1440 : time(w[3]);
            if (command.equals("ARRIVEBY")) heading += " by " + w[3];
            for (int t = deadline - 1; t >= 0; t--) {
                Label label = earliest(origin, t).get(destination);
                if (label != null && label.time() <= deadline) {
                    printJourney(heading, t, label);
                    return;
                }
            }
            System.out.println(heading + " none");
            return;
        }
        int departure = time(w[3]);
        if (command.equals("PROFILE")) {
            int last = time(w[4]);
            require(departure <= last, "empty interval " + w[3] + " " + w[4]);
            Map<Integer, Integer> arrivals = new TreeMap<>();
            for (int t = departure; t <= last; t++) {
                Label label = earliest(origin, t).get(destination);
                if (label != null) arrivals.put(t, label.time());
            }
            List<Integer> selected = new ArrayList<>();
            for (int t : arrivals.keySet()) if (t == last || !arrivals.containsKey(t + 1) || arrivals.get(t) < arrivals.get(t + 1)) selected.add(t);
            System.out.println(heading + " " + w[3] + " " + w[4] + " count " + selected.size());
            for (int t : selected) System.out.println(clock(t) + " -> " + clock(arrivals.get(t)) + " total " + (arrivals.get(t) - t));
            return;
        }
        if (command.equals("FEWEST") || command.equals("PARETO")) {
            var rounds = rounds(origin, departure);
            List<Integer> options = new ArrayList<>();
            for (int k = 0; k < rounds.size(); k++) {
                Label label = rounds.get(k).get(destination), previous = k == 0 ? null : rounds.get(k - 1).get(destination);
                if (label != null && (previous == null || previous.time() > label.time())) options.add(k);
            }
            if (command.equals("FEWEST")) {
                if (options.isEmpty()) System.out.println(heading + " " + w[3] + " unreachable");
                else {
                    int k = options.getFirst();
                    printJourney(heading + " trips " + k, departure, rounds.get(k).get(destination));
                }
            } else {
                System.out.println(heading + " " + w[3] + " options " + options.size());
                for (int k : options) printJourney("OPTION trips " + k, departure, rounds.get(k).get(destination));
            }
            return;
        }
        Label label = earliest(origin, departure).get(destination);
        if (label == null) System.out.println(heading + " " + w[3] + " unreachable");
        else printJourney(heading, departure, label);
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) try {
            command(input.readLine().split(" "));
        } catch (Problem error) {
            System.out.println(error.getMessage());
        }
    }
}
