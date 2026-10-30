import java.util.*;
final class Canonical {
    record RankBond(int rank, int kind) implements Comparable<RankBond> {
        public int compareTo(RankBond other) {
            int c = Integer.compare(rank, other.rank);
            return c != 0 ? c : Integer.compare(kind, other.kind);
        }
    }
    record Neighborhood(int rank, List<RankBond> neighbors) implements Comparable<Neighborhood> {
        public int compareTo(Neighborhood other) {
            int c = Integer.compare(rank, other.rank);
            if (c != 0)
                return c;
            for (int i = 0; i < Math.min(neighbors.size(), other.neighbors.size()); i++) {
                c = neighbors.get(i).compareTo(other.neighbors.get(i));
                if (c != 0)
                    return c;
            }
            return Integer.compare(neighbors.size(), other.neighbors.size());
        }
    }
    record Ranks(int[] values, int classes) {}
    record Result(String smiles, int classes) {}
    record Child(int atom, Molecule.Bond bond) {}
    static <T> int[] dense(List<T> values, Comparator<T> comparator) {
        Map<T, Integer> ranks = new TreeMap<>(comparator);
        for (T value : values)
            ranks.put(value, 0);
        int rank = 1;
        for (T key : ranks.keySet())
            ranks.put(key, rank++);
        int[] result = new int[values.size()];
        for (int i = 0; i < result.length; i++)
            result[i] = ranks.get(values.get(i));
        return result;
    }
    static int distinct(int[] values) {
        Set<Integer> unique = new HashSet<>();
        for (int value : values)
            unique.add(value);
        return unique.size();
    }
    static int[] refine(Molecule molecule, int[] input) {
        int[] ranks = input;
        while (true) {
            List<Neighborhood> values = new ArrayList<>();
            for (int atom = 0; atom < molecule.atoms.size(); atom++) {
                List<RankBond> neighbors = new ArrayList<>();
                for (var entry : molecule.neighbors.get(atom).entrySet())
                    neighbors.add(new RankBond(ranks[entry.getKey()], entry.getValue().kind));
                neighbors.sort(RankBond::compareTo);
                values.add(new Neighborhood(ranks[atom], neighbors));
            }
            int[] next = dense(values, Neighborhood::compareTo);
            if (distinct(next) == distinct(ranks))
                return next;
            ranks = next;
        }
    }
    static Ranks ranks(Molecule molecule) {
        List<List<Integer>> invariants = new ArrayList<>();
        for (int number = 0; number < molecule.atoms.size(); number++) {
            Molecule.Atom atom = molecule.atoms.get(number);
            invariants.add(List.of(molecule.degree(number), atom.element.number(), atom.mass,
                                   atom.charge, atom.hydrogens, atom.aromatic ? 1 : 0));
        }
        int[] ranks = refine(molecule, dense(invariants, RingsAromatic::compareSequence));
        int classes = distinct(ranks);
        while (distinct(ranks) != ranks.length) {
            Map<Integer, Integer> counts = new TreeMap<>();
            for (int rank : ranks)
                counts.merge(rank, 1, Integer::sum);
            int tied = 0;
            for (var entry : counts.entrySet())
                if (entry.getValue() > 1) {
                    tied = entry.getKey();
                    break;
                }
            int first = 0;
            while (ranks[first] != tied)
                first++;
            List<Integer> values = new ArrayList<>();
            for (int i = 0; i < ranks.length; i++)
                values.add(2 * ranks[i] - (i == first ? 1 : 0));
            ranks = refine(molecule, dense(values, Integer::compare));
        }
        return new Ranks(ranks, classes);
    }
    static String atomNotation(Molecule molecule, int number) {
        Molecule.Atom atom = molecule.atoms.get(number);
        String symbol = atom.element.symbol();
        boolean ordinary = Molecule.ORGANIC.contains(symbol) &&
                           (!atom.aromatic || Molecule.AROMATIC.contains(symbol)) &&
                           atom.mass == 0 && atom.charge == 0;
        if (atom.aromatic) {
            ordinary =
                ordinary && molecule.needsPi(number, atom.hydrogens) == molecule.needsPi(number, 0);
            symbol = symbol.toLowerCase(Locale.ROOT);
        }
        Integer hydrogens = Molecule.organicHydrogens(atom, molecule.bondTotal(number));
        if (ordinary && hydrogens != null && hydrogens == atom.hydrogens)
            return symbol;
        StringBuilder text = new StringBuilder("[");
        if (atom.mass != 0)
            text.append(atom.mass);
        text.append(symbol);
        if (atom.hydrogens > 0) {
            text.append('H');
            if (atom.hydrogens != 1)
                text.append(atom.hydrogens);
        }
        if (atom.charge != 0) {
            text.append(atom.charge > 0 ? '+' : '-');
            if (Math.abs(atom.charge) != 1)
                text.append(Math.abs(atom.charge));
        }
        return text.append(']').toString();
    }
    static String bondSymbol(Molecule molecule, Molecule.Bond bond) {
        boolean inRing = bond.ring && molecule.atoms.get(bond.ends.first()).aromatic &&
                         molecule.atoms.get(bond.ends.second()).aromatic;
        return switch (bond.kind) {
            case 1 -> inRing ? "-" : "";
            case 2 -> "=";
            case 3 -> "#";
            default -> inRing ? "" : ":";
        };
    }
    static final class Writer {
        Molecule molecule;
        int[] ranks, visits;
        int visited;
        List<List<Child>> children = new ArrayList<>();
        Set<Molecule.Edge> closures = new HashSet<>();
        Map<Molecule.Edge, Integer> assignments = new HashMap<>();
        Set<Integer> occupied = new HashSet<>();
        Writer(Molecule molecule, int[] ranks) {
            this.molecule = molecule;
            this.ranks = ranks;
            visits = new int[ranks.length];
            for (int rank : ranks)
                children.add(new ArrayList<>());
        }
        void visit(int atom, Molecule.Bond incoming) {
            visits[atom] = ++visited;
            List<Integer> neighbors = new ArrayList<>(molecule.neighbors.get(atom).keySet());
            neighbors.sort(Comparator.comparingInt(n -> ranks[n]));
            for (int neighbor : neighbors) {
                Molecule.Bond bond = molecule.neighbors.get(atom).get(neighbor);
                if (bond == incoming || closures.contains(bond.ends))
                    continue;
                if (visits[neighbor] == 0) {
                    children.get(atom).add(new Child(neighbor, bond));
                    visit(neighbor, bond);
                } else
                    closures.add(bond.ends);
            }
        }
        String write(int atom) {
            StringBuilder text = new StringBuilder(atomNotation(molecule, atom));
            List<Integer> neighbors = new ArrayList<>(molecule.neighbors.get(atom).keySet());
            neighbors.sort(Comparator.comparingInt(n -> visits[n]));
            for (int neighbor : neighbors) {
                Molecule.Bond bond = molecule.neighbors.get(atom).get(neighbor);
                if (!closures.contains(bond.ends))
                    continue;
                Integer assigned = assignments.remove(bond.ends);
                int number;
                String symbol;
                if (assigned != null) {
                    number = assigned;
                    occupied.remove(number);
                    symbol = "";
                } else {
                    number = 1;
                    while (occupied.contains(number))
                        number++;
                    assignments.put(bond.ends, number);
                    occupied.add(number);
                    symbol = bondSymbol(molecule, bond);
                }
                text.append(symbol).append(number < 10
                                               ? Integer.toString(number)
                                               : String.format(Locale.ROOT, "%%%02d", number));
            }
            List<Child> descendants = children.get(atom);
            for (int i = 0; i < descendants.size(); i++) {
                Child child = descendants.get(i);
                String continuation = bondSymbol(molecule, child.bond()) + write(child.atom());
                if (i + 1 < descendants.size())
                    text.append('(').append(continuation).append(')');
                else
                    text.append(continuation);
            }
            return text.toString();
        }
    }
    static Result canonicalize(Molecule molecule) {
        Ranks ranks = ranks(molecule);
        Writer writer = new Writer(molecule, ranks.values());
        int root = 0;
        while (ranks.values()[root] != 1)
            root++;
        writer.visit(root, null);
        return new Result(writer.write(root), ranks.classes());
    }
}
