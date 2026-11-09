import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Molecule {
    record Element(String symbol, int number, int weight, List<Integer> valences) {}
    record Edge(int first, int second) implements Comparable<Edge> {
        Edge {
            if (first > second) {
                int temporary = first;
                first = second;
                second = temporary;
            }
        }
        public int compareTo(Edge other) {
            int c = Integer.compare(first, other.first);
            return c != 0 ? c : Integer.compare(second, other.second);
        }
    }
    static final Set<String> ORGANIC = Set.of("B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I"),
                             AROMATIC = Set.of("B", "C", "N", "O", "P", "S");
    static int bondType(char symbol) {
        return switch (symbol) {
            case '-', '/', '\\' -> 1;
            case '=' -> 2;
            case '#' -> 3;
            case ':' -> 4;
            default -> 5;
        };
    }
    static final class AnalysisError extends RuntimeException {
        String reason;
        int column;
        AnalysisError(String reason, int column) {
            super(reason);
            this.reason = reason;
            this.column = column;
        }
    }
    static final class Atom {
        Element element;
        boolean aromatic, bracket;
        int mass, charge, hydrogens, column;
        Search.AtomMatch matcher;
        Atom(Element element, boolean aromatic, int mass, int charge, int hydrogens,
             boolean bracket, int column) {
            this.element = element;
            this.aromatic = aromatic;
            this.mass = mass;
            this.charge = charge;
            this.hydrogens = hydrogens;
            this.bracket = bracket;
            this.column = column;
        }
    }
    static final class Bond {
        Edge ends;
        Character symbol;
        Integer expected;
        int kind, multiplicity;
        boolean ring;
        Bond(int first, int second, Character symbol) {
            ends = new Edge(first, second);
            this.symbol = symbol;
        }
    }
    Map<String, Element> elements;
    List<Atom> atoms = new ArrayList<>();
    List<Map<Integer, Bond>> neighbors = new ArrayList<>();
    Map<Edge, Bond> bonds = new TreeMap<>();
    List<List<Integer>> rings = new ArrayList<>();
    Set<Integer> ringAtoms = new TreeSet<>();
    String name;
    int order;
    Molecule(Map<String, Element> elements) { this.elements = elements; }
    int addAtom(Atom atom) {
        int number = atoms.size();
        atoms.add(atom);
        neighbors.add(new TreeMap<>());
        return number;
    }
    Bond addBond(int first, int second, Character symbol) {
        Bond bond = new Bond(first, second, symbol);
        bonds.put(bond.ends, bond);
        neighbors.get(first).put(second, bond);
        neighbors.get(second).put(first, bond);
        return bond;
    }
    int degree(int number) { return neighbors.get(number).size(); }
    int baseTotal(int number) {
        int total = 0;
        for (Bond bond : neighbors.get(number).values())
            total += bond.kind == 4 ? 1 : bond.kind;
        return total;
    }
    int bondTotal(int number) {
        int total = 0;
        for (Bond bond : neighbors.get(number).values())
            total += bond.multiplicity;
        return total;
    }
    boolean needsPi(int number, int hydrogens) {
        Atom atom = atoms.get(number);
        return atom.aromatic &&
            atom.element.valences().getFirst() + atom.charge >= baseTotal(number) + hydrogens + 1;
    }
    static Integer organicHydrogens(Atom atom, int total) {
        for (int valence : atom.element.valences())
            if (valence >= total)
                return valence - total;
        return null;
    }
    static Map<String, Element> readElements() throws Exception {
        Map<String, Element> elements = new HashMap<>();
        for (String line :
             Files.readAllLines(Path.of("input/elements.txt"), StandardCharsets.US_ASCII)) {
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            String[] f = line.split(" ");
            List<Integer> valences = new ArrayList<>();
            for (String value : f[3].split(","))
                valences.add(Integer.parseInt(value));
            elements.put(f[0], new Element(f[0], Integer.parseInt(f[1]), Integer.parseInt(f[2]),
                                           List.copyOf(valences)));
        }
        return elements;
    }
}
