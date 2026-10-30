import java.nio.file.*;
import java.util.*;
final class FlightPlans {
    record AircraftType(int climb, int descent, int minimum) {}
    record Sector(String name, int x1, int y1, int x2, int y2, int lower, int upper, int capacity,
                  int index) {}
    record Waypoint(int x, int y, int level) {}
    static final class Plan {
        String callsign, type;
        int departure, level, speedInitial, speed, offset;
        long delay;
        List<Waypoint> waypoints;
        List<String> history = new ArrayList<>();
        Plan(String callsign, String type, int departure, int level, int speed,
             List<Waypoint> waypoints) {
            this.callsign = callsign;
            this.type = type;
            this.departure = departure;
            this.level = level;
            this.speedInitial = speed;
            this.speed = speed;
            this.waypoints = List.copyOf(waypoints);
        }
        Plan copy() {
            Plan copy = new Plan(callsign, type, departure, level, speedInitial, waypoints);
            copy.speed = speed;
            copy.delay = delay;
            copy.offset = offset;
            copy.history = new ArrayList<>(history);
            return copy;
        }
        List<Integer> levels() {
            List<Integer> levels = new ArrayList<>();
            levels.add(level + offset);
            for (int i = 1; i < waypoints.size(); i++)
                if (waypoints.get(i).level() >= 0)
                    levels.add(waypoints.get(i).level() + offset);
            return levels;
        }
    }
    record Settings(int dh, int dv, int lookahead, int maxDelay, int levelMin, int levelMax,
                    int sampleStart, int sampleEnd, int[] radar, int[] snapshots, int leader,
                    int alert) {}
    record Input(TreeMap<String, Plan> plans, Map<String, AircraftType> types, List<Sector> sectors,
                 Settings settings) {}
    static Input read() throws Exception {
        Map<String, AircraftType> types = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input", "aircraft.txt"))) {
            String[] w = line.split(" ");
            types.put(w[0], new AircraftType(Integer.parseInt(w[1]), Integer.parseInt(w[2]),
                                             Integer.parseInt(w[3])));
        }
        List<Sector> sectors = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input", "sectors.txt"))) {
            String[] w = line.split(" ");
            sectors.add(new Sector(w[0], Integer.parseInt(w[1]), Integer.parseInt(w[2]),
                                   Integer.parseInt(w[3]), Integer.parseInt(w[4]),
                                   Integer.parseInt(w[5]), Integer.parseInt(w[6]),
                                   Integer.parseInt(w[7]), sectors.size()));
        }
        Map<String, int[]> parameters = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input", "params.txt"))) {
            String[] w = line.split(" ");
            int[] values = new int[w.length - 1];
            for (int i = 1; i < w.length; i++)
                values[i - 1] = Integer.parseInt(w[i]);
            parameters.put(w[0], values);
        }
        Settings settings = new Settings(
            parameters.get("separation")[0], parameters.get("separation")[1],
            parameters.get("lookahead")[0], parameters.get("max_delay")[0],
            parameters.get("levels")[0], parameters.get("levels")[1], parameters.get("sampling")[0],
            parameters.get("sampling")[1], parameters.get("radar"), parameters.get("snapshots"),
            parameters.get("leader")[0], parameters.get("alert")[0]);
        TreeMap<String, Plan> plans = new TreeMap<>();
        List<String> lines = Files.readAllLines(Path.of("input", "flights.csv"));
        for (String line : lines.subList(1, lines.size())) {
            String[] w = line.split(",");
            List<Waypoint> waypoints = new ArrayList<>();
            for (String raw : w[5].split(" ")) {
                String[] v = raw.split(":");
                waypoints.add(new Waypoint(Integer.parseInt(v[0]), Integer.parseInt(v[1]),
                                           v.length == 3 ? Integer.parseInt(v[2]) : -1));
            }
            Plan plan = new Plan(w[0], w[1], Integer.parseInt(w[2]), Integer.parseInt(w[3]),
                                 Integer.parseInt(w[4]), waypoints);
            plans.put(w[0], plan);
        }
        return new Input(plans, types, sectors, settings);
    }
}
