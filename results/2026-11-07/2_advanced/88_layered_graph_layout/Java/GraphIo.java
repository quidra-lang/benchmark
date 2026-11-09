import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class GraphIo {
    static final List<String> SETTINGS =
        List.of("layering", "width", "promotion", "heuristic", "sweeps", "node_sep", "dummy_sep",
                "layer_gap", "direction", "sifting", "reduce", "restarts", "seed");
    record Pair(int first, int second) {}
    record InputLine(int number, String[] fields) {}
    record Error(String kind, int line) {}
    static final class Settings {
        String layering = "longest", heuristic = "barycenter", direction = "TB";
        int width = 4, sweeps = 12, nodeSep = 2, dummySep = 1, layerGap = 3, restarts;
        long seed = 1;
        boolean promotion, sifting, reduce;
        Settings() {}
        Settings(Settings source) {
            layering = source.layering;
            heuristic = source.heuristic;
            direction = source.direction;
            width = source.width;
            sweeps = source.sweeps;
            nodeSep = source.nodeSep;
            dummySep = source.dummySep;
            layerGap = source.layerGap;
            restarts = source.restarts;
            seed = source.seed;
            promotion = source.promotion;
            sifting = source.sifting;
            reduce = source.reduce;
        }
        boolean set(String name, String value) {
            if (Set.of("layering", "heuristic", "direction", "promotion", "sifting", "reduce")
                    .contains(name)) {
                boolean valid = switch (name) {
                    case "layering" -> Set.of("longest", "coffman").contains(value);
                    case "heuristic" -> Set.of("barycenter", "median").contains(value);
                    case "direction" -> Set.of("TB", "BT", "LR", "RL").contains(value);
                    default -> Set.of("on", "off").contains(value);
                };
                if (!valid)
                    return false;
                switch (name) {
                case "layering":
                    layering = value;
                    break;
                case "heuristic":
                    heuristic = value;
                    break;
                case "direction":
                    direction = value;
                    break;
                case "promotion":
                    promotion = value.equals("on");
                    break;
                case "sifting":
                    sifting = value.equals("on");
                    break;
                case "reduce":
                    reduce = value.equals("on");
                    break;
                }
                return true;
            }
            if (!SETTINGS.contains(name) || value.isEmpty() || value.length() > 10)
                return false;
            for (char c : value.toCharArray())
                if (c < '0' || c > '9')
                    return false;
            long number = Long.parseLong(value);
            long low = switch (name) {
                case "sweeps", "restarts" -> 0;
                case "layer_gap" -> 2;
                default -> 1;
            }, high = switch (name) {
                case "width" -> 40;
                case "sweeps" -> 50;
                case "seed" -> 2147483646L;
                default -> 9;
            };
            if (number < low || number > high)
                return false;
            switch (name) {
            case "width":
                width = (int)number;
                break;
            case "sweeps":
                sweeps = (int)number;
                break;
            case "node_sep":
                nodeSep = (int)number;
                break;
            case "dummy_sep":
                dummySep = (int)number;
                break;
            case "layer_gap":
                layerGap = (int)number;
                break;
            case "restarts":
                restarts = (int)number;
                break;
            case "seed":
                seed = number;
                break;
            }
            return true;
        }
        String value(String name) {
            return switch (name) {
                case "layering" -> layering;
                case "width" -> Integer.toString(width);
                case "promotion" -> promotion ? "on" : "off";
                case "heuristic" -> heuristic;
                case "sweeps" -> Integer.toString(sweeps);
                case "node_sep" -> Integer.toString(nodeSep);
                case "dummy_sep" -> Integer.toString(dummySep);
                case "layer_gap" -> Integer.toString(layerGap);
                case "direction" -> direction;
                case "sifting" -> sifting ? "on" : "off";
                case "reduce" -> reduce ? "on" : "off";
                case "restarts" -> Integer.toString(restarts);
                default -> Long.toString(seed);
            };
        }
    }
    static final class Graph {
        String name;
        Settings settings;
        Map<Integer, String> nodes = new TreeMap<>();
        List<Pair> edges = new ArrayList<>();
        Set<Pair> edgeSet = new HashSet<>();
        Pair path;
        int selfLoops, duplicates;
        Error error;
        Graph(String name, Settings defaults) {
            this.name = name;
            settings = new Settings(defaults);
        }
        String accept(String[] f) {
            if (f[0].equals("OPTION"))
                return settings.set(f[1], f[2]) ? null : "bad_option";
            int first = Integer.parseInt(f[1]);
            if (f[0].equals("NODE")) {
                if (nodes.containsKey(first))
                    return "duplicate_node";
                if (nodes.size() == 40)
                    return "too_many_nodes";
                nodes.put(first, f[2]);
                return null;
            }
            int second = Integer.parseInt(f[2]);
            if (!nodes.containsKey(first) || !nodes.containsKey(second))
                return "unknown_node";
            Pair pair = new Pair(first, second);
            if (f[0].equals("PATH"))
                path = pair;
            else if (first == second)
                selfLoops++;
            else if (!edgeSet.add(pair))
                duplicates++;
            else
                edges.add(pair);
            return null;
        }
    }
    static List<InputLine> lines(String name) throws Exception {
        List<InputLine> records = new ArrayList<>();
        List<String> lines = Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
        for (int i = 0; i < lines.size(); i++)
            if (!lines.get(i).isEmpty() && !lines.get(i).startsWith("#"))
                records.add(new InputLine(i + 1, lines.get(i).split(" ")));
        return records;
    }
    static Settings defaults() throws Exception {
        Settings settings = new Settings();
        for (InputLine line : lines("params.txt"))
            settings.set(line.fields()[0], line.fields()[1]);
        return settings;
    }
    static List<Graph> graphs(Settings defaults) throws Exception {
        List<Graph> graphs = new ArrayList<>();
        Graph graph = null;
        for (InputLine line : lines("graphs.txt")) {
            String[] f = line.fields();
            if (f[0].equals("GRAPH")) {
                graph = new Graph(f[1], defaults);
                graphs.add(graph);
            } else if (f[0].equals("END")) {
                if (graph.error == null && graph.nodes.isEmpty())
                    graph.error = new Error("no_nodes", line.number());
            } else if (graph.error == null) {
                String error = graph.accept(f);
                if (error != null)
                    graph.error = new Error(error, line.number());
            }
        }
        return graphs;
    }
}
