import java.util.*;
final class RingsAromatic {
    record Candidate(List<Integer> sequence, BitSet bonds) {}
    static Set<Molecule.Edge> ringEdges(List<Integer> sequence) {
        Set<Molecule.Edge> edges = new TreeSet<>();
        for (int i = 0; i < sequence.size(); i++)
            edges.add(new Molecule.Edge(sequence.get((i + sequence.size() - 1) % sequence.size()),
                                        sequence.get(i)));
        return edges;
    }
    static int compareSequence(List<Integer> a, List<Integer> b) {
        for (int i = 0; i < Math.min(a.size(), b.size()); i++) {
            int c = Integer.compare(a.get(i), b.get(i));
            if (c != 0)
                return c;
        }
        return Integer.compare(a.size(), b.size());
    }
    static List<Integer> ringSequence(List<Integer> sequence) {
        int first = sequence.indexOf(Collections.min(sequence));
        List<Integer> forward = new ArrayList<>();
        for (int i = 0; i < sequence.size(); i++)
            forward.add(sequence.get((first + i) % sequence.size()));
        List<Integer> backward = new ArrayList<>();
        backward.add(forward.getFirst());
        for (int i = forward.size() - 1; i > 0; i--)
            backward.add(forward.get(i));
        return compareSequence(forward, backward) <= 0 ? forward : backward;
    }
    static void findRings(Molecule molecule) {
        List<Molecule.Edge> bonds = new ArrayList<>(molecule.bonds.keySet());
        Map<Molecule.Edge, Integer> indices = new HashMap<>();
        for (int i = 0; i < bonds.size(); i++)
            indices.put(bonds.get(i), i);
        List<Candidate> candidates = new ArrayList<>();
        Set<BitSet> seen = new HashSet<>();
        int count = molecule.atoms.size();
        for (int root = 0; root < count; root++) {
            int[] parents = new int[count];
            Arrays.fill(parents, -2);
            parents[root] = -1;
            Deque<Integer> queue = new ArrayDeque<>();
            queue.add(root);
            while (!queue.isEmpty()) {
                int atom = queue.remove();
                for (int neighbor : molecule.neighbors.get(atom).keySet())
                    if (parents[neighbor] == -2) {
                        parents[neighbor] = atom;
                        queue.add(neighbor);
                    }
            }
            List<List<Integer>> paths = new ArrayList<>();
            for (int atom = 0; atom < count; atom++) {
                List<Integer> path = new ArrayList<>();
                for (int current = atom; current != -1; current = parents[current])
                    path.add(current);
                paths.add(path);
            }
            for (Molecule.Edge edge : bonds) {
                int first = edge.first(), second = edge.second();
                if (parents[first] == second || parents[second] == first)
                    continue;
                Set<Integer> shared = new HashSet<>(paths.get(first));
                shared.retainAll(paths.get(second));
                if (shared.size() != 1 || !shared.contains(root))
                    continue;
                List<Integer> sequence = new ArrayList<>(paths.get(first));
                Collections.reverse(sequence);
                sequence.addAll(paths.get(second).subList(0, paths.get(second).size() - 1));
                BitSet bits = new BitSet();
                for (Molecule.Edge ringEdge : ringEdges(sequence))
                    bits.set(indices.get(ringEdge));
                if (seen.add(bits))
                    candidates.add(new Candidate(sequence, bits));
            }
        }
        candidates.sort(Comparator.comparingInt(candidate -> candidate.sequence().size()));
        Map<Integer, BitSet> basis = new HashMap<>();
        for (Candidate candidate : candidates) {
            BitSet reduced = (BitSet)candidate.bonds().clone();
            while (!reduced.isEmpty()) {
                int pivot = reduced.length() - 1;
                BitSet vector = basis.get(pivot);
                if (vector == null) {
                    basis.put(pivot, reduced);
                    molecule.rings.add(ringSequence(candidate.sequence()));
                    break;
                }
                reduced.xor(vector);
            }
        }
        molecule.rings.sort(Comparator.comparingInt((List<Integer> ring) -> ring.size())
                                .thenComparing(RingsAromatic::compareSequence));
        for (List<Integer> ring : molecule.rings) {
            molecule.ringAtoms.addAll(ring);
            for (Molecule.Edge edge : ringEdges(ring))
                molecule.bonds.get(edge).ring = true;
        }
    }
    static List<Set<Integer>> aromaticSystems(Molecule molecule, Set<Integer> needing) {
        Set<Integer> remaining = new TreeSet<>(needing);
        List<Set<Integer>> systems = new ArrayList<>();
        while (!remaining.isEmpty()) {
            int start = Collections.min(remaining);
            remaining.remove(start);
            Set<Integer> system = new TreeSet<>();
            system.add(start);
            Deque<Integer> queue = new ArrayDeque<>();
            queue.add(start);
            while (!queue.isEmpty()) {
                int atom = queue.remove();
                for (var entry : molecule.neighbors.get(atom).entrySet())
                    if (entry.getValue().kind == 4 && remaining.remove(entry.getKey())) {
                        system.add(entry.getKey());
                        queue.add(entry.getKey());
                    }
            }
            systems.add(system);
        }
        return systems;
    }
    static boolean match(Molecule molecule, Set<Integer> unpaired, Set<Molecule.Edge> pairs) {
        if (unpaired.isEmpty())
            return true;
        int first = Collections.min(unpaired);
        unpaired.remove(first);
        for (var entry : molecule.neighbors.get(first).entrySet()) {
            int second = entry.getKey();
            Molecule.Bond bond = entry.getValue();
            if (!unpaired.contains(second) || bond.kind != 4)
                continue;
            unpaired.remove(second);
            pairs.add(bond.ends);
            if (match(molecule, unpaired, pairs))
                return true;
            pairs.remove(bond.ends);
            unpaired.add(second);
        }
        unpaired.add(first);
        return false;
    }
    static void kekulize(Molecule molecule, Set<Integer> needing) {
        Set<Molecule.Edge> selected = new HashSet<>();
        for (Set<Integer> system : aromaticSystems(molecule, needing)) {
            Set<Molecule.Edge> pairs = new HashSet<>();
            if (!match(molecule, new TreeSet<>(system), pairs))
                throw new Molecule.AnalysisError(
                    "kekulization failed", molecule.atoms.get(Collections.min(system)).column);
            selected.addAll(pairs);
        }
        for (Molecule.Bond bond : molecule.bonds.values())
            bond.multiplicity = bond.kind == 4 ? (selected.contains(bond.ends) ? 2 : 1) : bond.kind;
    }
}
