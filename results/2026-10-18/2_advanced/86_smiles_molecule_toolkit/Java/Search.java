import java.util.*;
final class Search {
    record Choice(String symbol, boolean aromatic) {}
    record AtomMatch(Set<Choice> choices, Boolean aromatic) {
        boolean matches(Molecule.Atom atom) {
            return choices != null
                ? choices.contains(new Choice(atom.element.symbol(), atom.aromatic))
                : aromatic == null || aromatic == atom.aromatic;
        }
    }
    static SmilesParser.AtomRead patternAtom(String text, int position) {
        char c = text.charAt(position);
        AtomMatch match;
        int end;
        if (c == '*' || c == 'A' || c == 'a') {
            match = new AtomMatch(null, c == '*' ? null : c == 'a');
            end = position + 1;
        } else if (c == '[') {
            end = text.indexOf(']', position + 1);
            if (end < 0)
                throw new Molecule.AnalysisError("unclosed bracket", position + 1);
            Set<Choice> choices = new HashSet<>();
            for (String item : text.substring(position + 1, end).split(",", -1)) {
                SmilesParser.Organic organic = SmilesParser.organic(item, 0);
                if (organic == null || organic.end() != item.length())
                    throw new Molecule.AnalysisError("bad bracket atom", position + 1);
                choices.add(new Choice(organic.symbol(), organic.aromatic()));
            }
            match = new AtomMatch(choices, null);
            end++;
        } else {
            SmilesParser.Organic organic = SmilesParser.organic(text, position);
            if (organic == null)
                throw new Molecule.AnalysisError("unexpected character", position + 1);
            match = new AtomMatch(Set.of(new Choice(organic.symbol(), organic.aromatic())), null);
            end = organic.end();
        }
        Molecule.Atom atom = new Molecule.Atom(null, false, 0, 0, 0, false, position + 1);
        atom.matcher = match;
        return new SmilesParser.AtomRead(atom, end);
    }
    static Molecule moleculePattern(Molecule molecule) {
        Molecule pattern = new Molecule(molecule.elements);
        for (Molecule.Atom original : molecule.atoms) {
            Molecule.Atom atom = new Molecule.Atom(null, false, 0, 0, 0, false, 0);
            atom.matcher = new AtomMatch(
                Set.of(new Choice(original.element.symbol(), original.aromatic)), null);
            pattern.addAtom(atom);
        }
        for (Molecule.Bond original : molecule.bonds.values()) {
            Molecule.Bond bond =
                pattern.addBond(original.ends.first(), original.ends.second(), null);
            bond.expected = original.kind;
        }
        return pattern;
    }
    static boolean bondMatches(Molecule.Bond pattern, Molecule.Bond molecule) {
        if (pattern.expected != null)
            return pattern.expected == molecule.kind;
        if (pattern.symbol == null)
            return molecule.kind == 1 || molecule.kind == 4;
        if (pattern.symbol == '~')
            return true;
        return Molecule.bondType(pattern.symbol) == molecule.kind;
    }
    record Embeddings(int count, int unique, List<Integer> mapping) {}
    static final class Matching {
        Molecule pattern, molecule;
        List<List<Integer>> candidates = new ArrayList<>();
        int[] mapping;
        BitSet used = new BitSet();
        Set<BitSet> unique = new HashSet<>();
        int count;
        List<Integer> first;
        Matching(Molecule pattern, Molecule molecule) {
            this.pattern = pattern;
            this.molecule = molecule;
            mapping = new int[pattern.atoms.size()];
            for (int i = 0; i < pattern.atoms.size(); i++) {
                List<Integer> atoms = new ArrayList<>();
                for (int number = 0; number < molecule.atoms.size(); number++)
                    if (pattern.atoms.get(i).matcher.matches(molecule.atoms.get(number)) &&
                        molecule.degree(number) >= pattern.degree(i))
                        atoms.add(number);
                candidates.add(atoms);
            }
        }
        void assign(int index) {
            if (index == mapping.length) {
                count++;
                unique.add((BitSet)used.clone());
                if (first == null) {
                    first = new ArrayList<>();
                    for (int number : mapping)
                        first.add(number);
                }
                return;
            }
            for (int atom : candidates.get(index)) {
                if (used.get(atom))
                    continue;
                boolean allowed = true;
                for (var entry : pattern.neighbors.get(index).entrySet())
                    if (entry.getKey() < index) {
                        Molecule.Bond target =
                            molecule.neighbors.get(atom).get(mapping[entry.getKey()]);
                        if (target == null || !bondMatches(entry.getValue(), target)) {
                            allowed = false;
                            break;
                        }
                    }
                if (!allowed)
                    continue;
                mapping[index] = atom;
                used.set(atom);
                assign(index + 1);
                used.clear(atom);
            }
        }
    }
    static Embeddings embeddings(Molecule pattern, Molecule molecule) {
        if (pattern.atoms.size() > molecule.atoms.size())
            return new Embeddings(0, 0, null);
        Matching matching = new Matching(pattern, molecule);
        matching.assign(0);
        return new Embeddings(matching.count, matching.unique.size(), matching.first);
    }
    record Fingerprint(BitSet bits, int paths) {}
    record Similarity(int common, int union) {}
    static final class Paths {
        Molecule molecule;
        int[] codes;
        BitSet used = new BitSet(), bits = new BitSet(1024);
        int count;
        Paths(Molecule molecule) {
            this.molecule = molecule;
            codes = new int[molecule.atoms.size()];
            for (int i = 0; i < codes.length; i++) {
                Molecule.Atom atom = molecule.atoms.get(i);
                codes[i] =
                    16 * atom.element.number() + (atom.aromatic ? 8 : 0) + molecule.degree(i);
            }
        }
        void extend(int atom, int depth, int value) {
            count++;
            bits.set(value % 1024);
            if (depth == 5)
                return;
            for (var entry : molecule.neighbors.get(atom).entrySet()) {
                int neighbor = entry.getKey();
                if (used.get(neighbor))
                    continue;
                int next = (value * 31 + entry.getValue().kind) % 1000003;
                next = (next * 31 + codes[neighbor]) % 1000003;
                used.set(neighbor);
                extend(neighbor, depth + 1, next);
                used.clear(neighbor);
            }
        }
    }
    static Fingerprint fingerprint(Molecule molecule) {
        Paths paths = new Paths(molecule);
        for (int atom = 0; atom < molecule.atoms.size(); atom++) {
            paths.used.set(atom);
            paths.extend(atom, 0, paths.codes[atom]);
            paths.used.clear(atom);
        }
        return new Fingerprint(paths.bits, paths.count);
    }
    static Similarity tanimoto(BitSet first, BitSet second) {
        BitSet common = (BitSet)first.clone();
        common.and(second);
        int count = common.cardinality();
        return new Similarity(count, first.cardinality() + second.cardinality() - count);
    }
}
