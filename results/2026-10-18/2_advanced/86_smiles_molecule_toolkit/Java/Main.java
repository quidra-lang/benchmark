import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static final List<String> QUERY_KINDS = List.of("MATCH", "CONTAINS", "MATRIX", "NEAREST",
                                                    "WITHIN", "COMPARE", "CLUSTER"),
                              SYSTEM_KINDS = List.of("isolated", "fused", "spiro", "bridged");
    record Line(int number, String text) {}
    record Fraction(int numerator, int denominator) implements Comparable<Fraction> {
        Fraction {
            int a = numerator, b = denominator;
            while (b != 0) {
                int r = a % b;
                a = b;
                b = r;
            }
            numerator /= a;
            denominator /= a;
        }
        public int compareTo(Fraction other) {
            return Integer.compare(numerator * other.denominator, other.numerator * denominator);
        }
        public String toString() { return numerator + "/" + denominator; }
    }
    record Properties(String formula, int weight, int heavy, int rotatable, int donors,
                      int acceptors, String lipinski, int charge) {}
    record RingSystem(List<Integer> rings, int atoms, String kind) {}
    static final class Prepared {
        Molecule molecule;
        Properties properties;
        String canonical, scaffold;
        int classes, paths;
        BitSet bits;
        List<RingSystem> systems;
        List<Boolean> aromaticRings;
        Prepared(Molecule molecule) {
            this.molecule = molecule;
            properties = molecularProperties(molecule);
            Canonical.Result result = Canonical.canonicalize(molecule);
            canonical = result.smiles();
            classes = result.classes();
            Molecule scaffoldMolecule = scaffoldMolecule(molecule);
            scaffold =
                scaffoldMolecule == null ? null : Canonical.canonicalize(scaffoldMolecule).smiles();
            systems = ringSystems(molecule);
            aromaticRings = new ArrayList<>();
            for (List<Integer> ring : molecule.rings) {
                boolean aromatic = true;
                for (int atom : ring)
                    if (!molecule.atoms.get(atom).aromatic)
                        aromatic = false;
                aromaticRings.add(aromatic);
            }
            Search.Fingerprint fingerprint = Search.fingerprint(molecule);
            bits = fingerprint.bits();
            paths = fingerprint.paths();
        }
        String name() { return molecule.name; }
    }
    static final class Query {
        String kind, id;
        List<String> arguments;
        Molecule pattern;
        Fraction threshold;
        int count;
        Query(String kind, String id, List<String> arguments) {
            this.kind = kind;
            this.id = id;
            this.arguments = arguments;
        }
    }
    record ReadMolecules(List<Prepared> molecules, List<String> errors) {}
    record ReadQueries(List<Query> queries, List<String> errors) {}
    record Hit(Prepared molecule, Search.Embeddings embeddings) {}
    record Neighbor(Prepared molecule, Search.Similarity value) {}
    static List<Line> dataLines(String file) throws Exception {
        List<Line> result = new ArrayList<>();
        List<String> lines = Files.readAllLines(Path.of("input", file), StandardCharsets.US_ASCII);
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            if (!line.isEmpty() && !line.startsWith("#"))
                result.add(new Line(i + 1, line));
        }
        return result;
    }
    static boolean validName(String value) {
        if (value.isEmpty() || value.length() > 32)
            return false;
        for (char c : value.toCharArray())
            if (!(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' ||
                  c == '_' || c == '-'))
                return false;
        return true;
    }
    static boolean validNumber(String value, int minimum, int maximum) {
        if (value.isEmpty() || value.length() > 2 || value.length() > 1 && value.charAt(0) == '0')
            return false;
        for (char c : value.toCharArray())
            if (c < '0' || c > '9')
                return false;
        int number = Integer.parseInt(value);
        return minimum <= number && number <= maximum;
    }
    static Fraction threshold(String value) {
        String[] parts = value.split("/", -1);
        if (parts.length != 2 || !validNumber(parts[0], 0, 99) || !validNumber(parts[1], 1, 99))
            return null;
        int p = Integer.parseInt(parts[0]), q = Integer.parseInt(parts[1]);
        return p <= q ? new Fraction(p, q) : null;
    }
    static String atomNumbers(Collection<Integer> atoms, String separator) {
        List<String> numbers = new ArrayList<>();
        for (int atom : atoms)
            numbers.add(Integer.toString(atom + 1));
        return String.join(separator, numbers);
    }
    static String memberNames(List<Prepared> molecules) {
        return String.join(",", molecules.stream().map(Prepared::name).toList());
    }
    static void cause(Map<String, Integer> causes, String reason) {
        causes.merge(reason, 1, Integer::sum);
    }
    static void analyze(Molecule molecule) {
        RingsAromatic.findRings(molecule);
        for (Molecule.Bond bond : molecule.bonds.values())
            bond.kind = bond.symbol != null ? Molecule.bondType(bond.symbol)
                        : molecule.atoms.get(bond.ends.first()).aromatic &&
                                molecule.atoms.get(bond.ends.second()).aromatic && bond.ring
                            ? 4
                            : 1;
        Set<Integer> needing = new TreeSet<>();
        for (int number = 0; number < molecule.atoms.size(); number++)
            if (molecule.needsPi(number, molecule.atoms.get(number).hydrogens))
                needing.add(number);
        RingsAromatic.kekulize(molecule, needing);
        for (int number = 0; number < molecule.atoms.size(); number++) {
            Molecule.Atom atom = molecule.atoms.get(number);
            int total = molecule.bondTotal(number);
            if (atom.bracket) {
                if (total + atom.hydrogens >
                    atom.element.valences().getLast() + Math.abs(atom.charge))
                    throw new Molecule.AnalysisError("bad valence", atom.column);
            } else {
                Integer hydrogens = Molecule.organicHydrogens(atom, total);
                if (hydrogens == null)
                    throw new Molecule.AnalysisError("bad valence", atom.column);
                atom.hydrogens = hydrogens;
            }
        }
    }
    static Properties molecularProperties(Molecule molecule) {
        Map<String, Integer> counts = new TreeMap<>();
        int hydrogens = 0, weight = 0, heavy = 0, charge = 0;
        for (Molecule.Atom atom : molecule.atoms) {
            counts.merge(atom.element.symbol(), 1, Integer::sum);
            hydrogens += atom.hydrogens;
            weight += atom.mass != 0 ? atom.mass * 1000 : atom.element.weight();
            if (!atom.element.symbol().equals("H"))
                heavy++;
            charge += atom.charge;
        }
        counts.merge("H", hydrogens, Integer::sum);
        List<String> symbols = new ArrayList<>();
        for (var entry : counts.entrySet())
            if (entry.getValue() > 0)
                symbols.add(entry.getKey());
        if (counts.getOrDefault("C", 0) > 0) {
            symbols.remove("C");
            List<String> first = new ArrayList<>();
            first.add("C");
            if (symbols.remove("H"))
                first.add("H");
            first.addAll(symbols);
            symbols = first;
        }
        StringBuilder formula = new StringBuilder();
        for (String symbol : symbols) {
            formula.append(symbol);
            if (counts.get(symbol) != 1)
                formula.append(counts.get(symbol));
        }
        weight += hydrogens * molecule.elements.get("H").weight();
        int[] heavyDegrees = new int[molecule.atoms.size()];
        for (int atom = 0; atom < heavyDegrees.length; atom++)
            for (int neighbor : molecule.neighbors.get(atom).keySet())
                if (!molecule.atoms.get(neighbor).element.symbol().equals("H"))
                    heavyDegrees[atom]++;
        Set<Integer> tripleEnds = new HashSet<>();
        for (Molecule.Bond bond : molecule.bonds.values())
            if (bond.multiplicity == 3) {
                tripleEnds.add(bond.ends.first());
                tripleEnds.add(bond.ends.second());
            }
        int rotatable = 0;
        for (Molecule.Bond bond : molecule.bonds.values())
            if (bond.multiplicity == 1 && !bond.ring && heavyDegrees[bond.ends.first()] >= 2 &&
                heavyDegrees[bond.ends.second()] >= 2 && !tripleEnds.contains(bond.ends.first()) &&
                !tripleEnds.contains(bond.ends.second()))
                rotatable++;
        int donors = 0, acceptors = 0;
        for (int number = 0; number < molecule.atoms.size(); number++) {
            Molecule.Atom atom = molecule.atoms.get(number);
            if (atom.element.symbol().equals("N") || atom.element.symbol().equals("O")) {
                acceptors++;
                int attached = atom.hydrogens;
                for (int neighbor : molecule.neighbors.get(number).keySet())
                    if (molecule.atoms.get(neighbor).element.symbol().equals("H"))
                        attached++;
                if (attached >= 1)
                    donors++;
            }
        }
        int violations =
            (weight > 500000 ? 1 : 0) + (donors > 5 ? 1 : 0) + (acceptors > 10 ? 1 : 0);
        return new Properties(formula.toString(), weight, heavy, rotatable, donors, acceptors,
                              violations <= 1 ? "pass" : "fail", charge);
    }
    static Molecule scaffoldMolecule(Molecule molecule) {
        if (molecule.rings.isEmpty())
            return null;
        Set<Integer> remaining = new TreeSet<>();
        for (int i = 0; i < molecule.atoms.size(); i++)
            remaining.add(i);
        while (true) {
            Integer leaf = null;
            for (int atom : remaining) {
                if (molecule.ringAtoms.contains(atom))
                    continue;
                int degree = 0;
                for (int neighbor : molecule.neighbors.get(atom).keySet())
                    if (remaining.contains(neighbor))
                        degree++;
                if (degree == 1) {
                    leaf = atom;
                    break;
                }
            }
            if (leaf == null)
                break;
            remaining.remove(leaf);
        }
        Set<Integer> kept = new TreeSet<>(remaining);
        for (int atom : remaining)
            for (var entry : molecule.neighbors.get(atom).entrySet())
                if (!remaining.contains(entry.getKey()) && entry.getValue().kind == 2)
                    kept.add(entry.getKey());
        Molecule scaffold = new Molecule(molecule.elements);
        Map<Integer, Integer> renumber = new HashMap<>();
        for (int number : kept) {
            Molecule.Atom original = molecule.atoms.get(number);
            int added = 0;
            for (var entry : molecule.neighbors.get(number).entrySet())
                if (!kept.contains(entry.getKey()))
                    added += entry.getValue().multiplicity;
            Molecule.Atom atom = new Molecule.Atom(
                original.element, original.aromatic, original.mass, original.charge,
                original.hydrogens + added, original.bracket, original.column);
            renumber.put(number, scaffold.addAtom(atom));
        }
        for (Molecule.Bond original : molecule.bonds.values()) {
            int first = original.ends.first(), second = original.ends.second();
            if (kept.contains(first) && kept.contains(second)) {
                Molecule.Bond bond =
                    scaffold.addBond(renumber.get(first), renumber.get(second), original.symbol);
                bond.kind = original.kind;
                bond.multiplicity = original.multiplicity;
                bond.ring = original.ring;
            }
        }
        for (List<Integer> ring : molecule.rings) {
            List<Integer> transformed = new ArrayList<>();
            for (int atom : ring)
                transformed.add(renumber.get(atom));
            scaffold.rings.add(transformed);
        }
        for (int atom : molecule.ringAtoms)
            scaffold.ringAtoms.add(renumber.get(atom));
        return scaffold;
    }
    static List<RingSystem> ringSystems(Molecule molecule) {
        List<Set<Integer>> atomSets = new ArrayList<>();
        List<Set<Integer>> connections = new ArrayList<>();
        for (List<Integer> ring : molecule.rings) {
            atomSets.add(new HashSet<>(ring));
            connections.add(new TreeSet<>());
        }
        Map<Molecule.Edge, String> relations = new HashMap<>();
        for (int first = 0; first < atomSets.size(); first++)
            for (int second = first + 1; second < atomSets.size(); second++) {
                Set<Integer> shared = new TreeSet<>(atomSets.get(first));
                shared.retainAll(atomSets.get(second));
                if (shared.isEmpty())
                    continue;
                connections.get(first).add(second);
                connections.get(second).add(first);
                String relation;
                if (shared.size() == 1)
                    relation = "spiro";
                else if (shared.size() == 2) {
                    List<Integer> pair = new ArrayList<>(shared);
                    relation = molecule.neighbors.get(pair.getFirst()).containsKey(pair.get(1))
                                   ? "fused"
                                   : "bridged";
                } else
                    relation = "bridged";
                relations.put(new Molecule.Edge(first, second), relation);
            }
        List<RingSystem> systems = new ArrayList<>();
        Set<Integer> unseen = new TreeSet<>();
        for (int i = 0; i < atomSets.size(); i++)
            unseen.add(i);
        while (!unseen.isEmpty()) {
            int start = Collections.min(unseen);
            unseen.remove(start);
            Set<Integer> component = new TreeSet<>();
            component.add(start);
            Deque<Integer> queue = new ArrayDeque<>();
            queue.add(start);
            while (!queue.isEmpty())
                for (int neighbor : connections.get(queue.remove()))
                    if (unseen.remove(neighbor)) {
                        component.add(neighbor);
                        queue.add(neighbor);
                    }
            Set<String> kinds = new HashSet<>();
            for (var entry : relations.entrySet())
                if (component.contains(entry.getKey().first()) &&
                    component.contains(entry.getKey().second()))
                    kinds.add(entry.getValue());
            String kind = component.size() == 1       ? "isolated"
                          : kinds.contains("bridged") ? "bridged"
                          : kinds.contains("fused")   ? "fused"
                                                      : "spiro";
            Set<Integer> atoms = new HashSet<>();
            for (int ring : component)
                atoms.addAll(atomSets.get(ring));
            systems.add(new RingSystem(new ArrayList<>(component), atoms.size(), kind));
        }
        return systems;
    }
    static ReadMolecules readMolecules(Map<String, Molecule.Element> elements,
                                       Map<String, Integer> causes) throws Exception {
        List<Prepared> molecules = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        Set<String> reserved = new HashSet<>();
        List<Line> lines = dataLines("molecules.smi");
        for (Line line : lines) {
            String[] tokens = line.text().split(" ", -1);
            if (tokens.length != 2 || tokens[0].isEmpty() || !validName(tokens[1])) {
                errors.add("line " + line.number() + ": bad line");
                cause(causes, "bad line");
                continue;
            }
            String name = tokens[1];
            if (!reserved.add(name)) {
                errors.add("line " + line.number() + " " + name + ": duplicate name");
                cause(causes, "duplicate name");
                continue;
            }
            Molecule molecule;
            try {
                molecule = SmilesParser.parse(tokens[0], elements, false);
                analyze(molecule);
            } catch (Molecule.AnalysisError error) {
                errors.add("line " + line.number() + " " + name + ": " + error.reason +
                           " at column " + error.column);
                cause(causes, error.reason);
                continue;
            }
            molecule.name = name;
            molecule.order = molecules.size();
            molecules.add(new Prepared(molecule));
        }
        List<String> paragraph = new ArrayList<>();
        paragraph.add("MOLECULES lines=" + lines.size() + " valid=" + molecules.size() +
                      " errors=" + errors.size());
        paragraph.addAll(errors);
        return new ReadMolecules(molecules, paragraph);
    }
    static String checkArguments(Query query, Map<String, Molecule.Element> elements,
                                 Map<String, Prepared> byName) {
        List<String> arguments = query.arguments;
        int minimum = query.kind.equals("MATRIX")                                  ? 2
                      : query.kind.equals("MATCH") || query.kind.equals("CLUSTER") ? 1
                                                                                   : 2,
            maximum = query.kind.equals("MATRIX") ? 12 : minimum;
        if (arguments.size() < minimum || arguments.size() > maximum)
            return "bad arguments";
        if (query.kind.equals("MATCH")) {
            try {
                query.pattern = SmilesParser.parse(arguments.getFirst(), elements, true);
            } catch (Molecule.AnalysisError error) {
                return "bad pattern " + error.reason + " at column " + error.column;
            }
        } else if (query.kind.equals("CLUSTER")) {
            query.threshold = threshold(arguments.getFirst());
            if (query.threshold == null)
                return "bad threshold";
        } else if (Set.of("CONTAINS", "MATRIX", "COMPARE").contains(query.kind)) {
            for (String name : arguments)
                if (!byName.containsKey(name))
                    return "unknown molecule " + name;
            if (new HashSet<>(arguments).size() != arguments.size())
                return "repeated molecule";
        } else {
            if (!byName.containsKey(arguments.getFirst()))
                return "unknown molecule " + arguments.getFirst();
            if (query.kind.equals("NEAREST")) {
                if (!validNumber(arguments.get(1), 1, 99))
                    return "bad count";
                query.count = Integer.parseInt(arguments.get(1));
            } else {
                query.threshold = threshold(arguments.get(1));
                if (query.threshold == null)
                    return "bad threshold";
            }
        }
        return null;
    }
    static ReadQueries readQueries(Map<String, Molecule.Element> elements,
                                   Map<String, Prepared> byName, Map<String, Integer> causes)
        throws Exception {
        List<Query> queries = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        Set<String> reserved = new HashSet<>();
        List<Line> lines = dataLines("queries.txt");
        for (Line line : lines) {
            String[] tokens = line.text().split(" ", -1);
            String kind = tokens[0], id = tokens.length >= 2 ? tokens[1] : null, reason;
            if (!QUERY_KINDS.contains(kind))
                reason = "unknown query";
            else if (id == null || !validName(id))
                reason = "bad id";
            else if (!reserved.add(id))
                reason = "duplicate id";
            else {
                Query query = new Query(
                    kind, id, List.copyOf(Arrays.asList(tokens).subList(2, tokens.length)));
                reason = checkArguments(query, elements, byName);
                if (reason == null) {
                    queries.add(query);
                    continue;
                }
            }
            String text;
            if (reason.equals("unknown query"))
                text = "line " + line.number() + ": unknown query";
            else if (reason.equals("bad id"))
                text = "line " + line.number() + " " + kind + ": bad id";
            else
                text = "line " + line.number() + " " + kind + " " + id + ": " + reason;
            errors.add(text);
            cause(causes, reason.startsWith("bad pattern ")        ? "bad pattern"
                          : reason.startsWith("unknown molecule ") ? "unknown molecule"
                                                                   : reason);
        }
        List<String> paragraph = new ArrayList<>();
        paragraph.add("QUERIES lines=" + lines.size() + " valid=" + queries.size() +
                      " errors=" + errors.size());
        paragraph.addAll(errors);
        return new ReadQueries(queries, paragraph);
    }
    static List<String> propertiesLines(List<Prepared> molecules) {
        List<String> lines = new ArrayList<>();
        lines.add("name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski");
        for (Prepared prepared : molecules) {
            Properties p = prepared.properties;
            int weight = p.weight();
            lines.add(prepared.name() + "," + p.formula() + "," + weight / 1000 + "." +
                      String.format(Locale.ROOT, "%03d", weight % 1000) + "," + p.heavy() + "," +
                      prepared.molecule.rings.size() + "," + p.rotatable() + "," + p.donors() +
                      "," + p.acceptors() + "," + p.lipinski());
        }
        return lines;
    }
    static List<List<String>> canonicalParagraphs(List<Prepared> molecules) {
        Map<String, List<Prepared>> byCanonical = new LinkedHashMap<>(),
                                    byFormula = new LinkedHashMap<>(),
                                    byScaffold = new LinkedHashMap<>();
        int acyclic = 0;
        for (Prepared molecule : molecules) {
            byCanonical.computeIfAbsent(molecule.canonical, k -> new ArrayList<>()).add(molecule);
            byFormula.computeIfAbsent(molecule.properties.formula(), k -> new ArrayList<>())
                .add(molecule);
            if (molecule.scaffold == null)
                acyclic++;
            else
                byScaffold.computeIfAbsent(molecule.scaffold, k -> new ArrayList<>()).add(molecule);
        }
        List<String> canonical = new ArrayList<>();
        canonical.add("CANONICAL molecules=" + molecules.size() + " unique=" + byCanonical.size());
        for (Prepared molecule : molecules) {
            int charge = molecule.properties.charge();
            canonical.add(molecule.name() + " " + molecule.canonical + " classes=" +
                          molecule.classes + " charge=" + (charge > 0 ? "+" : "") + charge);
        }
        List<Map.Entry<String, List<Prepared>>> duplicates = new ArrayList<>();
        int count = 0;
        for (var entry : byCanonical.entrySet())
            if (entry.getValue().size() >= 2) {
                duplicates.add(entry);
                count += entry.getValue().size();
            }
        List<String> duplicateLines = new ArrayList<>();
        duplicateLines.add("DUPLICATES groups=" + duplicates.size() + " molecules=" + count);
        for (int i = 0; i < duplicates.size(); i++) {
            var entry = duplicates.get(i);
            duplicateLines.add("group " + (i + 1) + " " + entry.getKey() +
                               " members=" + memberNames(entry.getValue()));
        }
        List<String> isomerRecords = new ArrayList<>();
        for (var entry : byFormula.entrySet()) {
            Set<String> forms = new HashSet<>();
            for (Prepared molecule : entry.getValue())
                forms.add(molecule.canonical);
            if (forms.size() >= 2)
                isomerRecords.add("isomer " + (isomerRecords.size() + 1) + " " + entry.getKey() +
                                  " forms=" + forms.size() +
                                  " members=" + memberNames(entry.getValue()));
        }
        List<String> isomers = new ArrayList<>();
        isomers.add("ISOMERS groups=" + isomerRecords.size());
        isomers.addAll(isomerRecords);
        List<String> scaffolds = new ArrayList<>();
        scaffolds.add("SCAFFOLDS distinct=" + byScaffold.size() + " acyclic=" + acyclic);
        List<Map.Entry<String, List<Prepared>>> ordered = new ArrayList<>(byScaffold.entrySet());
        ordered.sort(Comparator
                         .comparingInt(
                             (Map.Entry<String, List<Prepared>> entry) -> - entry.getValue().size())
                         .thenComparing(Map.Entry::getKey));
        for (int i = 0; i < ordered.size(); i++) {
            var entry = ordered.get(i);
            scaffolds.add("scaffold " + (i + 1) + " " + entry.getKey() + " count=" +
                          entry.getValue().size() + " members=" + memberNames(entry.getValue()));
        }
        return List.of(canonical, duplicateLines, isomers, scaffolds);
    }
    static List<List<String>> ringParagraphs(List<Prepared> molecules) {
        List<List<String>> paragraphs = new ArrayList<>();
        Map<Integer, Integer> sizes = new TreeMap<>();
        Map<String, Integer> kinds = new HashMap<>();
        int totalAromatic = 0, totalRings = 0;
        for (Prepared prepared : molecules) {
            Molecule molecule = prepared.molecule;
            if (molecule.rings.isEmpty())
                continue;
            int aromatic = 0, ringBonds = 0;
            for (boolean value : prepared.aromaticRings)
                if (value)
                    aromatic++;
            totalAromatic += aromatic;
            totalRings += molecule.rings.size();
            for (Molecule.Bond bond : molecule.bonds.values())
                if (bond.ring)
                    ringBonds++;
            List<String> paragraph = new ArrayList<>();
            paragraph.add("MOLECULE " + molecule.name + " atoms=" + molecule.atoms.size() +
                          " bonds=" + molecule.bonds.size() + " rings=" + molecule.rings.size() +
                          " aromatic=" + aromatic + " systems=" + prepared.systems.size() +
                          " ring_atoms=" + molecule.ringAtoms.size() + " ring_bonds=" + ringBonds);
            for (int i = 0; i < molecule.rings.size(); i++) {
                List<Integer> ring = molecule.rings.get(i);
                int hetero = 0;
                for (int atom : ring)
                    if (!molecule.atoms.get(atom).element.symbol().equals("C"))
                        hetero++;
                paragraph.add("ring " + (i + 1) + " size=" + ring.size() +
                              " aromatic=" + (prepared.aromaticRings.get(i) ? "yes" : "no") +
                              " hetero=" + hetero + " atoms=" + atomNumbers(ring, "-"));
                sizes.merge(ring.size(), 1, Integer::sum);
            }
            for (int i = 0; i < prepared.systems.size(); i++) {
                RingSystem system = prepared.systems.get(i);
                kinds.merge(system.kind(), 1, Integer::sum);
                paragraph.add("system " + (i + 1) + " kind=" + system.kind() + " rings=" +
                              atomNumbers(system.rings(), ",") + " atoms=" + system.atoms());
            }
            List<String> doubleBonds = new ArrayList<>();
            for (Molecule.Bond bond : molecule.bonds.values())
                if (bond.kind == 4 && bond.multiplicity == 2)
                    doubleBonds.add((bond.ends.first() + 1) + "=" + (bond.ends.second() + 1));
            paragraph.add("kekule " +
                          (doubleBonds.isEmpty() ? "-" : String.join(" ", doubleBonds)));
            paragraphs.add(paragraph);
        }
        List<String> summary = new ArrayList<>();
        summary.add("SUMMARY molecules=" + molecules.size() + " cyclic=" + paragraphs.size() +
                    " rings=" + totalRings + " aromatic=" + totalAromatic);
        List<String> sizeValues = new ArrayList<>();
        for (var entry : sizes.entrySet())
            sizeValues.add(entry.getKey() + "=" + entry.getValue());
        summary.add("sizes " + (sizeValues.isEmpty() ? "-" : String.join(" ", sizeValues)));
        List<String> systemValues = new ArrayList<>();
        for (String kind : SYSTEM_KINDS)
            systemValues.add(kind + "=" + kinds.getOrDefault(kind, 0));
        summary.add("systems " + String.join(" ", systemValues));
        paragraphs.add(summary);
        return paragraphs;
    }
    static List<List<String>> substructureParagraphs(List<Query> queries, List<Prepared> molecules,
                                                     Map<String, Prepared> byName) {
        List<List<String>> paragraphs = new ArrayList<>();
        int patterns = 0, hits = 0, contains = 0, found = 0;
        for (Query query : queries)
            if (query.kind.equals("MATCH")) {
                patterns++;
                List<Hit> matches = new ArrayList<>();
                int total = 0;
                for (Prepared molecule : molecules) {
                    Search.Embeddings embeddings =
                        Search.embeddings(query.pattern, molecule.molecule);
                    if (embeddings.count() > 0) {
                        matches.add(new Hit(molecule, embeddings));
                        total += embeddings.count();
                    }
                }
                hits += matches.size();
                List<String> paragraph = new ArrayList<>();
                paragraph.add("MATCH " + query.id + " " + query.arguments.getFirst() + " atoms=" +
                              query.pattern.atoms.size() + " bonds=" + query.pattern.bonds.size() +
                              " hits=" + matches.size() + " embeddings=" + total);
                Hit top = null;
                for (Hit hit : matches) {
                    Search.Embeddings e = hit.embeddings();
                    paragraph.add(hit.molecule().name() + " count=" + e.count() + " unique=" +
                                  e.unique() + " map=" + atomNumbers(e.mapping(), ","));
                    if (top == null || e.count() > top.embeddings().count())
                        top = hit;
                }
                if (top != null)
                    paragraph.add("top " + top.molecule().name() +
                                  " count=" + top.embeddings().count());
                paragraphs.add(paragraph);
            } else if (query.kind.equals("CONTAINS")) {
                contains++;
                Prepared first = byName.get(query.arguments.getFirst()),
                         second = byName.get(query.arguments.get(1));
                Search.Embeddings e =
                    Search.embeddings(Search.moleculePattern(first.molecule), second.molecule);
                String text =
                    "CONTAINS " + query.id + " " + first.name() + " " + second.name() + " result=";
                if (e.count() > 0) {
                    found++;
                    text += "yes count=" + e.count() + " unique=" + e.unique() +
                            " map=" + atomNumbers(e.mapping(), ",");
                } else
                    text += "no";
                paragraphs.add(List.of(text));
            }
        paragraphs.add(List.of("SUMMARY patterns=" + patterns + " hits=" + hits +
                               " contains=" + contains + " found=" + found));
        return paragraphs;
    }
    static Fraction ratio(Search.Similarity value) {
        return new Fraction(value.common(), value.union());
    }
    static final class Similarities {
        Map<Molecule.Edge, Search.Similarity> cache = new HashMap<>();
        Search.Similarity get(Prepared first, Prepared second) {
            Molecule.Edge key = new Molecule.Edge(first.molecule.order, second.molecule.order);
            return cache.computeIfAbsent(key, k -> Search.tanimoto(first.bits, second.bits));
        }
    }
    static List<String> matrixParagraph(Query query, Map<String, Prepared> byName,
                                        Similarities similarities) {
        List<Prepared> molecules = new ArrayList<>();
        for (String name : query.arguments)
            molecules.add(byName.get(name));
        List<String> paragraph = new ArrayList<>();
        paragraph.add("MATRIX " + query.id + " size=" + molecules.size());
        for (Prepared first : molecules) {
            StringBuilder row = new StringBuilder("row " + first.name());
            for (Prepared second : molecules)
                row.append(' ').append(ratio(similarities.get(first, second)));
            paragraph.add(row.toString());
        }
        Prepared bestFirst = molecules.getFirst(), bestSecond = molecules.get(1);
        Fraction best = ratio(similarities.get(bestFirst, bestSecond));
        for (int i = 0; i < molecules.size(); i++)
            for (int j = i + 1; j < molecules.size(); j++) {
                Fraction value = ratio(similarities.get(molecules.get(i), molecules.get(j)));
                if (value.compareTo(best) > 0) {
                    bestFirst = molecules.get(i);
                    bestSecond = molecules.get(j);
                    best = value;
                }
            }
        paragraph.add("best " + bestFirst.name() + " " + bestSecond.name() + " " + best);
        return paragraph;
    }
    static List<String> neighborsParagraph(Query query, List<Prepared> molecules,
                                           Map<String, Prepared> byName,
                                           Similarities similarities) {
        Prepared source = byName.get(query.arguments.getFirst());
        List<Neighbor> neighbors = new ArrayList<>();
        for (Prepared molecule : molecules)
            if (molecule != source)
                neighbors.add(new Neighbor(molecule, similarities.get(source, molecule)));
        neighbors.sort((a, b) -> {
            int c = ratio(b.value()).compareTo(ratio(a.value()));
            return c != 0
                ? c
                : Integer.compare(a.molecule().molecule.order, b.molecule().molecule.order);
        });
        List<Neighbor> result = new ArrayList<>();
        String heading;
        if (query.kind.equals("NEAREST")) {
            result.addAll(neighbors.subList(0, Math.min(query.count, neighbors.size())));
            heading = "NEAREST " + query.id + " " + source.name() + " count=" + result.size();
        } else {
            for (Neighbor neighbor : neighbors)
                if (ratio(neighbor.value()).compareTo(query.threshold) >= 0)
                    result.add(neighbor);
            heading = "WITHIN " + query.id + " " + source.name() + " threshold=" + query.threshold +
                      " count=" + result.size();
        }
        List<String> paragraph = new ArrayList<>();
        paragraph.add(heading);
        for (int i = 0; i < result.size(); i++) {
            Neighbor neighbor = result.get(i);
            paragraph.add((i + 1) + " " + neighbor.molecule().name() + " " +
                          ratio(neighbor.value()) + " common=" + neighbor.value().common());
        }
        return paragraph;
    }
    static List<String> compareParagraph(Query query, Map<String, Prepared> byName,
                                         Similarities similarities) {
        Prepared first = byName.get(query.arguments.getFirst()),
                 second = byName.get(query.arguments.get(1));
        Search.Similarity value = similarities.get(first, second);
        return List.of("COMPARE " + query.id + " " + first.name() + " " + second.name() +
                       " bits=" + first.bits.cardinality() + "," + second.bits.cardinality() +
                       " common=" + value.common() + " union=" + value.union() +
                       " tanimoto=" + ratio(value) +
                       " identical=" + (first.canonical.equals(second.canonical) ? "yes" : "no"));
    }
    static List<String> clusterParagraph(Query query, List<Prepared> molecules,
                                         Similarities similarities) {
        List<List<Integer>> neighbors = new ArrayList<>();
        for (Prepared first : molecules) {
            List<Integer> near = new ArrayList<>();
            for (Prepared second : molecules)
                if (first != second &&
                    ratio(similarities.get(first, second)).compareTo(query.threshold) >= 0)
                    near.add(second.molecule.order);
            neighbors.add(near);
        }
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < molecules.size(); i++)
            order.add(i);
        order.sort(Comparator.comparingInt((Integer i) -> - neighbors.get(i).size())
                       .thenComparingInt(Integer::intValue));
        Set<Integer> assigned = new HashSet<>();
        List<List<Integer>> clusters = new ArrayList<>();
        for (int center : order)
            if (!assigned.contains(center)) {
                List<Integer> members = new ArrayList<>();
                members.add(center);
                for (int neighbor : neighbors.get(center))
                    if (!assigned.contains(neighbor))
                        members.add(neighbor);
                clusters.add(members);
                assigned.addAll(members);
            }
        int singletons = 0;
        for (List<Integer> members : clusters)
            if (members.size() == 1)
                singletons++;
        List<String> paragraph = new ArrayList<>();
        paragraph.add("CLUSTER " + query.id + " threshold=" + query.threshold +
                      " clusters=" + clusters.size() + " singletons=" + singletons);
        int number = 0;
        for (List<Integer> members : clusters) {
            if (members.size() == 1)
                continue;
            number++;
            List<Prepared> selected = new ArrayList<>();
            for (int member : members)
                selected.add(molecules.get(member));
            paragraph.add("cluster " + number + " centroid=" + selected.getFirst().name() +
                          " size=" + selected.size() + " members=" + memberNames(selected));
        }
        return paragraph;
    }
    static List<List<String>> similarityParagraphs(List<Query> queries, List<Prepared> molecules,
                                                   Map<String, Prepared> byName) {
        List<String> fingerprints = new ArrayList<>();
        fingerprints.add("FINGERPRINTS molecules=" + molecules.size() + " size=1024 depth=5");
        for (Prepared molecule : molecules)
            fingerprints.add(molecule.name() + " bits=" + molecule.bits.cardinality() +
                             " paths=" + molecule.paths);
        List<List<String>> paragraphs = new ArrayList<>();
        paragraphs.add(fingerprints);
        Similarities similarities = new Similarities();
        for (Query query : queries) {
            List<String> paragraph = switch (query.kind) {
                case "MATRIX" -> matrixParagraph(query, byName, similarities);
                case "NEAREST", "WITHIN" ->
                    neighborsParagraph(query, molecules, byName, similarities);
                case "COMPARE" -> compareParagraph(query, byName, similarities);
                case "CLUSTER" -> clusterParagraph(query, molecules, similarities);
                default -> null;
            };
            if (paragraph != null)
                paragraphs.add(paragraph);
        }
        return paragraphs;
    }
    static List<String> causesParagraph(Map<String, Integer> causes) {
        List<Map.Entry<String, Integer>> ordered = new ArrayList<>(causes.entrySet());
        ordered.sort(
            Comparator.comparingInt((Map.Entry<String, Integer> entry) -> - entry.getValue())
                .thenComparing(Map.Entry::getKey));
        List<String> paragraph = new ArrayList<>();
        paragraph.add("CAUSES kinds=" + causes.size());
        for (var entry : ordered)
            paragraph.add(entry.getKey() + "=" + entry.getValue());
        return paragraph;
    }
    static String paragraphsText(List<List<String>> paragraphs) {
        List<String> blocks = new ArrayList<>();
        for (List<String> paragraph : paragraphs)
            blocks.add(String.join("\n", paragraph));
        return String.join("\n\n", blocks) + "\n";
    }
    public static void main(String[] args) throws Exception {
        Map<String, Molecule.Element> elements = Molecule.readElements();
        Map<String, Integer> causes = new HashMap<>();
        ReadMolecules read = readMolecules(elements, causes);
        List<Prepared> molecules = read.molecules();
        Map<String, Prepared> byName = new HashMap<>();
        for (Prepared molecule : molecules)
            byName.put(molecule.name(), molecule);
        ReadQueries queryRead = readQueries(elements, byName, causes);
        List<Query> queries = queryRead.queries();
        Map<String, String> outputs = new LinkedHashMap<>();
        outputs.put("properties.csv", String.join("\n", propertiesLines(molecules)) + "\n");
        outputs.put("canonical.txt", paragraphsText(canonicalParagraphs(molecules)));
        outputs.put("rings.txt", paragraphsText(ringParagraphs(molecules)));
        outputs.put("substructure.txt",
                    paragraphsText(substructureParagraphs(queries, molecules, byName)));
        outputs.put("similarity.txt",
                    paragraphsText(similarityParagraphs(queries, molecules, byName)));
        outputs.put("errors.txt", paragraphsText(List.of(read.errors(), queryRead.errors(),
                                                         causesParagraph(causes))));
        Files.createDirectories(Path.of("output"));
        for (var entry : outputs.entrySet())
            Files.writeString(Path.of("output", entry.getKey()), entry.getValue(),
                              StandardCharsets.US_ASCII);
    }
}
