using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
public static class ModelIo {
    public record Node(int identifier, int x, int y);
    public record Member(int identifier, int start, int end, int section, int material,
                         string group);
    public record Section(string name, double area, double inertia);
    public record Material(string name, double young, double yieldStress, double density,
                           double expansion);
    public record Support(int node, int[] fixity, double[] prescribed);
    public record Load(string kind, int index, double first, double second);
    public record LoadCase(string name, List<Load> lines);
    public record Term(string name, double factor);
    public record Combination(string name, List<Term> terms);
    public record Axle(int offset, double load);
    public record Drawing(string name, int magnification, int horizontal, int vertical);
    public sealed class Settings {
        public List<int> deck = new(), influence = new();
        public List<Axle> axles = new();
        public List<Drawing> drawings = new();
        public int vehicleStep, deflectionRatio, modeCount, iterations, mapHorizontal, mapVertical;
        public string rating, deflection, vibration, removal;
        public double deadFactor, vehicleFactor, compressionLimit, tensionLimit;
    }
    public record Model(List<Node> nodes, List<Member> members, List<Section> sections,
                        List<Material> materials, List<Support> supports, List<LoadCase> cases,
                        List<Combination> combinations, Settings settings);
    public static double Real(string value) => double.Parse(value, CultureInfo.InvariantCulture);
    public static List<string[]> Rows(string name) => File.ReadAllLines(Path.Combine("input",
                                                                                     name + ".csv"))
                                                          .Skip(1)
                                                          .Select(line => line.Split(','))
                                                          .ToList();
    public static Model Read() {
        List<Node> nodes = new();
        Dictionary<int, int> nodeIndex = new();
        foreach (string[] r in Rows("nodes")) {
            int id = int.Parse(r[0]);
            nodeIndex[id] = nodes.Count;
            nodes.Add(new(id, int.Parse(r[1]), int.Parse(r[2])));
        }
        List<Section> sections = new();
        Dictionary<string, int> sectionIndex = new();
        foreach (string[] r in Rows("sections")) {
            sectionIndex[r[0]] = sections.Count;
            sections.Add(new(r[0], Real(r[1]), Real(r[2])));
        }
        List<Material> materials = new();
        Dictionary<string, int> materialIndex = new();
        foreach (string[] r in Rows("materials")) {
            materialIndex[r[0]] = materials.Count;
            materials.Add(new(r[0], Real(r[1]), Real(r[2]), Real(r[3]), Real(r[4])));
        }
        List<Member> members = new();
        Dictionary<int, int> memberIndex = new();
        foreach (string[] r in Rows("members")) {
            int id = int.Parse(r[0]);
            memberIndex[id] = members.Count;
            members.Add(new(id, nodeIndex[int.Parse(r[1])], nodeIndex[int.Parse(r[2])],
                            sectionIndex[r[3]], materialIndex[r[4]], r[5]));
        }
        List<Support> supports = new();
        foreach (string[] r in Rows("supports"))
            supports.Add(new(nodeIndex[int.Parse(r[0])], new[] { int.Parse(r[1]), int.Parse(r[2]) },
                             new[] { Real(r[3]), Real(r[4]) }));
        List<LoadCase> cases = new();
        List<Combination> combinations = new();
        string name = "";
        List<Load> loads = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "loads.txt"))) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "LOADCASE":
                name = w[1];
                loads = new();
                break;
            case "END":
                cases.Add(new(name, loads));
                break;
            case "COMBINATION": {
                List<Term> terms = new();
                for (int i = 2; i < w.Length; i += 2)
                    terms.Add(new(w[i], Real(w[i + 1])));
                combinations.Add(new(w[1], terms));
                break;
            }
            case "FORCE":
                loads.Add(new(w[0], nodeIndex[int.Parse(w[1])], Real(w[2]), Real(w[3])));
                break;
            case "TEMPERATURE":
                loads.Add(new(w[0], memberIndex[int.Parse(w[1])], Real(w[2]), 0));
                break;
            default:
                loads.Add(new(w[0], -1, 0, 0));
                break;
            }
        }
        Settings s = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "params.txt"))) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "deck":
                for (int i = 1; i < w.Length; i++)
                    s.deck.Add(nodeIndex[int.Parse(w[i])]);
                break;
            case "influence":
                s.influence.Add(memberIndex[int.Parse(w[1])]);
                break;
            case "vehicle":
                s.vehicleStep = int.Parse(w[1]);
                for (int i = 2; i < w.Length; i += 2)
                    s.axles.Add(new(int.Parse(w[i]), Real(w[i + 1])));
                break;
            case "rating":
                s.rating = w[1];
                s.deadFactor = Real(w[2]);
                s.vehicleFactor = Real(w[3]);
                break;
            case "slenderness":
                s.compressionLimit = Real(w[1]);
                s.tensionLimit = Real(w[2]);
                break;
            case "deflection":
                s.deflection = w[1];
                s.deflectionRatio = int.Parse(w[2]);
                break;
            case "vibration":
                s.vibration = w[1];
                s.modeCount = int.Parse(w[2]);
                s.iterations = int.Parse(w[3]);
                break;
            case "removal":
                s.removal = w[1];
                break;
            case "drawing":
                s.drawings.Add(new(w[1], int.Parse(w[2]), int.Parse(w[3]), int.Parse(w[4])));
                break;
            case "utilization_map":
                s.mapHorizontal = int.Parse(w[1]);
                s.mapVertical = int.Parse(w[2]);
                break;
            }
        }
        return new(nodes, members, sections, materials, supports, cases, combinations, s);
    }
}
public static class CollectionHelpers {
    public static V GetOrAdd<K, V>(this IDictionary<K, V> map, K key, Func<K, V> factory) {
        if (!map.TryGetValue(key, out V value)) {
            value = factory(key);
            map[key] = value;
        }
        return value;
    }
}
