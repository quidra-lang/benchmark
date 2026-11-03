import java.nio.file.*;
import java.util.*;
final class ModelIo {
    record Node(int identifier, int x, int y) {}
    record Member(int identifier, int start, int end, int section, int material, String group) {}
    record Section(String name, double area, double inertia) {}
    record
        Material(String name, double young, double yieldStress, double density, double expansion) {}
    record Support(int node, int[] fixed, double[] prescribed) {}
    record Load(String kind, int index, double first, double second) {}
    record LoadCase(String name, List<Load> lines) {}
    record Term(String name, double factor) {}
    record Combination(String name, List<Term> terms) {}
    record Axle(int offset, double load) {}
    record Drawing(String name, int magnification, int horizontal, int vertical) {}
    static final class Settings {
        List<Integer> deck = new ArrayList<>(), influence = new ArrayList<>();
        List<Axle> axles = new ArrayList<>();
        List<Drawing> drawings = new ArrayList<>();
        int vehicleStep, deflectionRatio, modeCount, iterations, mapHorizontal, mapVertical;
        String rating, deflection, vibration, removal;
        double deadFactor, vehicleFactor, compressionLimit, tensionLimit;
    }
    record Model(List<Node> nodes, List<Member> members, List<Section> sections,
                 List<Material> materials, List<Support> supports, List<LoadCase> cases,
                 List<Combination> combinations, Settings settings) {}
    static List<String[]> rows(String name) throws Exception {
        List<String[]> rows = new ArrayList<>();
        List<String> lines = Files.readAllLines(Path.of("input", name + ".csv"));
        for (int i = 1; i < lines.size(); i++)
            rows.add(lines.get(i).split(","));
        return rows;
    }
    static Model read() throws Exception {
        List<Node> nodes = new ArrayList<>();
        Map<Integer, Integer> nodeIndex = new HashMap<>();
        for (String[] r : rows("nodes")) {
            int id = Integer.parseInt(r[0]);
            nodeIndex.put(id, nodes.size());
            nodes.add(new Node(id, Integer.parseInt(r[1]), Integer.parseInt(r[2])));
        }
        List<Section> sections = new ArrayList<>();
        Map<String, Integer> sectionIndex = new HashMap<>();
        for (String[] r : rows("sections")) {
            sectionIndex.put(r[0], sections.size());
            sections.add(new Section(r[0], Double.parseDouble(r[1]), Double.parseDouble(r[2])));
        }
        List<Material> materials = new ArrayList<>();
        Map<String, Integer> materialIndex = new HashMap<>();
        for (String[] r : rows("materials")) {
            materialIndex.put(r[0], materials.size());
            materials.add(new Material(r[0], Double.parseDouble(r[1]), Double.parseDouble(r[2]),
                                       Double.parseDouble(r[3]), Double.parseDouble(r[4])));
        }
        List<Member> members = new ArrayList<>();
        Map<Integer, Integer> memberIndex = new HashMap<>();
        for (String[] r : rows("members")) {
            int id = Integer.parseInt(r[0]);
            memberIndex.put(id, members.size());
            members.add(new Member(id, nodeIndex.get(Integer.parseInt(r[1])),
                                   nodeIndex.get(Integer.parseInt(r[2])), sectionIndex.get(r[3]),
                                   materialIndex.get(r[4]), r[5]));
        }
        List<Support> supports = new ArrayList<>();
        for (String[] r : rows("supports"))
            supports.add(
                new Support(nodeIndex.get(Integer.parseInt(r[0])),
                            new int[] {Integer.parseInt(r[1]), Integer.parseInt(r[2])},
                            new double[] {Double.parseDouble(r[3]), Double.parseDouble(r[4])}));
        List<LoadCase> cases = new ArrayList<>();
        List<Combination> combinations = new ArrayList<>();
        String name = "";
        List<Load> loads = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input", "loads.txt"))) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "LOADCASE" -> {
                name = w[1];
                loads = new ArrayList<>();
            }
            case "END" -> cases.add(new LoadCase(name, loads));
            case "COMBINATION" -> {
                List<Term> terms = new ArrayList<>();
                for (int i = 2; i < w.length; i += 2)
                    terms.add(new Term(w[i], Double.parseDouble(w[i + 1])));
                combinations.add(new Combination(w[1], terms));
            }
            case "FORCE" ->
                loads.add(new Load(w[0], nodeIndex.get(Integer.parseInt(w[1])),
                                   Double.parseDouble(w[2]), Double.parseDouble(w[3])));
            case "TEMPERATURE" ->
                loads.add(new Load(w[0], memberIndex.get(Integer.parseInt(w[1])),
                                   Double.parseDouble(w[2]), 0));
            default -> loads.add(new Load(w[0], -1, 0, 0));
            }
        }
        Settings s = new Settings();
        for (String line : Files.readAllLines(Path.of("input", "params.txt"))) {
            String[] w = line.split(" ");
            switch (w[0]) {
            case "deck" -> {
                for (int i = 1; i < w.length; i++)
                    s.deck.add(nodeIndex.get(Integer.parseInt(w[i])));
            }
            case "influence" -> s.influence.add(memberIndex.get(Integer.parseInt(w[1])));
            case "vehicle" -> {
                s.vehicleStep = Integer.parseInt(w[1]);
                for (int i = 2; i < w.length; i += 2)
                    s.axles.add(new Axle(Integer.parseInt(w[i]), Double.parseDouble(w[i + 1])));
            }
            case "rating" -> {
                s.rating = w[1];
                s.deadFactor = Double.parseDouble(w[2]);
                s.vehicleFactor = Double.parseDouble(w[3]);
            }
            case "slenderness" -> {
                s.compressionLimit = Double.parseDouble(w[1]);
                s.tensionLimit = Double.parseDouble(w[2]);
            }
            case "deflection" -> {
                s.deflection = w[1];
                s.deflectionRatio = Integer.parseInt(w[2]);
            }
            case "vibration" -> {
                s.vibration = w[1];
                s.modeCount = Integer.parseInt(w[2]);
                s.iterations = Integer.parseInt(w[3]);
            }
            case "removal" -> s.removal = w[1];
            case "drawing" ->
                s.drawings.add(new Drawing(w[1], Integer.parseInt(w[2]), Integer.parseInt(w[3]),
                                           Integer.parseInt(w[4])));
            case "utilization_map" -> {
                s.mapHorizontal = Integer.parseInt(w[1]);
                s.mapVertical = Integer.parseInt(w[2]);
            }
            }
        }
        return new Model(nodes, members, sections, materials, supports, cases, combinations, s);
    }
}
