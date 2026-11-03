using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class FlightPlans {
    public record AircraftType(int climb, int descent, int minimum) {}
    public record Sector(string name, int x1, int y1, int x2, int y2, int lower, int upper,
                         int capacity, int index) {}
    public record Waypoint(int x, int y, int level) {}
    public sealed class Plan {
        public string callsign, type;
        public int departure, level, speedInitial, speed, offset;
        public long delay;
        public List<Waypoint> waypoints;
        public List<string> history = new();
        public Plan(string callsign, string type, int departure, int level, int speed,
                    List<Waypoint> waypoints) {
            this.callsign = callsign;
            this.type = type;
            this.departure = departure;
            this.level = level;
            this.speedInitial = speed;
            this.speed = speed;
            this.waypoints = new List<Waypoint>(waypoints);
        }
        public Plan Copy() {
            Plan copy = new Plan(callsign, type, departure, level, speedInitial, waypoints);
            copy.speed = speed;
            copy.delay = delay;
            copy.offset = offset;
            copy.history = new(history);
            return copy;
        }
        public List<int> Levels() {
            List<int> levels = new();
            levels.Add(level + offset);
            for (int i = 1; i < waypoints.Count; i++)
                if (waypoints[i].level >= 0)
                    levels.Add(waypoints[i].level + offset);
            return levels;
        }
    }
    public record Settings(int dh, int dv, int lookahead, int maxDelay, int levelMin, int levelMax,
                           int sampleStart, int sampleEnd, int[] radar, int[] snapshots, int leader,
                           int alert) {}
    public record Input(SortedDictionary<string, Plan> plans,
                        Dictionary<string, AircraftType> types, List<Sector> sectors,
                        Settings settings) {}
    public static Input Read() {
        Dictionary<string, AircraftType> types = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "aircraft.txt")).ToList()) {
            string[] w = line.Split(" ");
            types[w[0]] = new AircraftType(int.Parse(w[1]), int.Parse(w[2]), int.Parse(w[3]));
        }
        List<Sector> sectors = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "sectors.txt")).ToList()) {
            string[] w = line.Split(" ");
            sectors.Add(new Sector(w[0], int.Parse(w[1]), int.Parse(w[2]), int.Parse(w[3]),
                                   int.Parse(w[4]), int.Parse(w[5]), int.Parse(w[6]),
                                   int.Parse(w[7]), sectors.Count));
        }
        Dictionary<string, int[]> parameters = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "params.txt")).ToList()) {
            string[] w = line.Split(" ");
            int[] values = new int[w.Length - 1];
            for (int i = 1; i < w.Length; i++)
                values[i - 1] = int.Parse(w[i]);
            parameters[w[0]] = values;
        }
        Settings settings = new Settings(
            parameters["separation"][0], parameters["separation"][1], parameters["lookahead"][0],
            parameters["max_delay"][0], parameters["levels"][0], parameters["levels"][1],
            parameters["sampling"][0], parameters["sampling"][1], parameters["radar"],
            parameters["snapshots"], parameters["leader"][0], parameters["alert"][0]);
        SortedDictionary<string, Plan> plans = new(StringComparer.Ordinal);
        List<string> lines = File.ReadAllLines(Path.Combine("input", "flights.csv")).ToList();
        foreach (string line in lines.GetRange(1, lines.Count - 1)) {
            string[] w = line.Split(',');
            List<Waypoint> waypoints = new();
            foreach (string raw in w[5].Split(" ")) {
                string[] v = raw.Split(":");
                waypoints.Add(new Waypoint(int.Parse(v[0]), int.Parse(v[1]),
                                           v.Length == 3 ? int.Parse(v[2]) : -1));
            }
            Plan plan =
                new Plan(w[0], w[1], int.Parse(w[2]), int.Parse(w[3]), int.Parse(w[4]), waypoints);
            plans[w[0]] = plan;
        }
        return new Input(plans, types, sectors, settings);
    }
}
