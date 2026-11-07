import java.util.*;
final class Grounding {
    record Action(int number, PddlParser.Schema source, List<String> arguments, int cost,
                  BitSet pre, BitSet neg, BitSet add, BitSet delete) {
        Action { arguments = List.copyOf(arguments); }
        String text() { return new PddlParser.Atom(source.name(), arguments).toString(); }
    }
    record Step(String name, List<String> arguments) {
        Step { arguments = List.copyOf(arguments); }
        public String toString() { return new PddlParser.Atom(name, arguments).toString(); }
    }
    static final class Problem {
        String name;
        PddlParser.Problem source;
        Map<String, List<String>> objectsByType = new LinkedHashMap<>();
        Map<String, int[]> statistics = new LinkedHashMap<>();
        int candidateCount, staticCount;
        List<PddlParser.Atom> facts = new ArrayList<>(), unreachable = new ArrayList<>();
        List<Action> actions = new ArrayList<>();
        BitSet initial = new BitSet(), goal = new BitSet();
        Map<Step, Integer> actionNumbers = new HashMap<>();
        Problem(PddlParser.Problem source) {
            this.source = source;
            name = source.name;
        }
    }
    record Candidate(PddlParser.Schema source, List<String> arguments, Set<PddlParser.Atom> pre,
                     Set<PddlParser.Atom> neg, Set<PddlParser.Atom> add,
                     Set<PddlParser.Atom> delete) {}
    static boolean subtype(Map<String, String> parents, String actual, String expected) {
        for (String type = actual; type != null; type = parents.get(type))
            if (type.equals(expected))
                return true;
        return false;
    }
    static void predicateClasses(PddlParser.Domain domain) {
        domain.fluent.clear();
        for (PddlParser.Schema schema : domain.actions)
            for (PddlParser.Literal literal : schema.effects())
                domain.fluent.add(literal.atom().predicate());
        domain.statics = new HashSet<>(domain.predicates.keySet());
        domain.statics.removeAll(domain.fluent);
    }
    static PddlParser.Atom substitute(PddlParser.Atom atom, Map<String, String> binding) {
        List<String> terms = new ArrayList<>();
        for (String term : atom.terms())
            terms.add(binding.get(term));
        return new PddlParser.Atom(atom.predicate(), terms);
    }
    static boolean contains(BitSet state, BitSet subset) {
        for (int fact = subset.nextSetBit(0); fact >= 0; fact = subset.nextSetBit(fact + 1))
            if (!state.get(fact))
                return false;
        return true;
    }
    static List<Integer> numbers(BitSet bits) {
        List<Integer> result = new ArrayList<>();
        for (int number = bits.nextSetBit(0); number >= 0; number = bits.nextSetBit(number + 1))
            result.add(number);
        return result;
    }
    static BitSet mapped(Set<PddlParser.Atom> atoms, Map<PddlParser.Atom, Integer> numbers) {
        BitSet result = new BitSet();
        for (PddlParser.Atom atom : atoms) {
            Integer number = numbers.get(atom);
            if (number != null)
                result.set(number);
        }
        return result;
    }
    static void enumerate(PddlParser.Domain domain, PddlParser.Problem problem,
                          PddlParser.Schema schema, List<List<String>> choices, int index,
                          List<String> arguments, List<Candidate> candidates, int[] statistics) {
        if (index < choices.size()) {
            for (String object : choices.get(index)) {
                List<String> next = new ArrayList<>(arguments);
                next.add(object);
                enumerate(domain, problem, schema, choices, index + 1, next, candidates,
                          statistics);
            }
            return;
        }
        Map<String, String> binding = new HashMap<>();
        for (int i = 0; i < arguments.size(); i++)
            binding.put(schema.parameters().get(i).name(), arguments.get(i));
        Set<PddlParser.Atom> positive = new HashSet<>(), negative = new HashSet<>();
        Set<PddlParser.Atom> initial = new HashSet<>(problem.initial);
        for (PddlParser.Literal literal : schema.condition()) {
            PddlParser.Atom atom = substitute(literal.atom(), binding);
            boolean truth;
            if (atom.predicate().equals("="))
                truth = atom.terms().getFirst().equals(atom.terms().get(1));
            else if (domain.statics.contains(atom.predicate()))
                truth = initial.contains(atom);
            else {
                (literal.positive() ? positive : negative).add(atom);
                continue;
            }
            if (truth != literal.positive())
                return;
        }
        Set<PddlParser.Atom> adds = new HashSet<>(), deletes = new HashSet<>();
        for (PddlParser.Literal literal : schema.effects())
            (literal.positive() ? adds : deletes).add(substitute(literal.atom(), binding));
        deletes.removeAll(adds);
        candidates.add(
            new Candidate(schema, List.copyOf(arguments), positive, negative, adds, deletes));
        statistics[1]++;
    }
    static Problem ground(PddlParser.Domain domain, PddlParser.Problem source) {
        Problem problem = new Problem(source);
        for (String type : domain.typeOrder) {
            List<String> objects = new ArrayList<>();
            for (var entry : source.objects.entrySet())
                if (subtype(domain.parents, entry.getValue(), type))
                    objects.add(entry.getKey());
            problem.objectsByType.put(type, objects);
        }
        List<Candidate> candidates = new ArrayList<>();
        for (PddlParser.Schema schema : domain.actions) {
            List<List<String>> choices = new ArrayList<>();
            int assignments = 1;
            for (PddlParser.Typed parameter : schema.parameters()) {
                List<String> objects = problem.objectsByType.get(parameter.type());
                choices.add(objects);
                assignments *= objects.size();
            }
            int[] stats = {assignments, 0, 0};
            problem.statistics.put(schema.name(), stats);
            enumerate(domain, source, schema, choices, 0, List.of(), candidates, stats);
        }
        problem.candidateCount = candidates.size();
        Set<PddlParser.Atom> reachable = new HashSet<>();
        for (PddlParser.Atom atom : source.initial)
            if (domain.fluent.contains(atom.predicate()))
                reachable.add(atom);
        boolean[] accepted = new boolean[candidates.size()];
        boolean changed = true;
        while (changed) {
            changed = false;
            for (int i = 0; i < candidates.size(); i++) {
                Candidate candidate = candidates.get(i);
                if (!accepted[i] && reachable.containsAll(candidate.pre())) {
                    accepted[i] = true;
                    reachable.addAll(candidate.add());
                    problem.statistics.get(candidate.source().name())[2]++;
                    changed = true;
                }
            }
        }
        Map<String, Integer> predicateOrder = new HashMap<>(), objectOrder = new HashMap<>();
        int index = 0;
        for (String predicate : domain.predicates.keySet())
            predicateOrder.put(predicate, index++);
        index = 0;
        for (String object : source.objects.keySet())
            objectOrder.put(object, index++);
        problem.facts = new ArrayList<>(reachable);
        problem.facts.sort((a, b) -> {
            int c = Integer.compare(predicateOrder.get(a.predicate()),
                                    predicateOrder.get(b.predicate()));
            if (c != 0)
                return c;
            for (int i = 0; i < a.terms().size(); i++) {
                c = Integer.compare(objectOrder.get(a.terms().get(i)),
                                    objectOrder.get(b.terms().get(i)));
                if (c != 0)
                    return c;
            }
            return 0;
        });
        Map<PddlParser.Atom, Integer> factNumbers = new HashMap<>();
        for (int i = 0; i < problem.facts.size(); i++)
            factNumbers.put(problem.facts.get(i), i);
        for (int i = 0; i < candidates.size(); i++)
            if (accepted[i]) {
                Candidate c = candidates.get(i);
                Action action =
                    new Action(problem.actions.size(), c.source(), c.arguments(), c.source().cost(),
                               mapped(c.pre(), factNumbers), mapped(c.neg(), factNumbers),
                               mapped(c.add(), factNumbers), mapped(c.delete(), factNumbers));
                problem.actions.add(action);
                problem.actionNumbers.put(new Step(action.source().name(), action.arguments()),
                                          action.number());
            }
        Set<PddlParser.Atom> initialAtoms = new HashSet<>(source.initial);
        for (PddlParser.Atom atom : source.initial)
            if (domain.fluent.contains(atom.predicate()))
                problem.initial.set(factNumbers.get(atom));
            else
                problem.staticCount++;
        for (PddlParser.Atom atom : source.goals) {
            Integer number = factNumbers.get(atom);
            if (number != null)
                problem.goal.set(number);
            else if (!domain.statics.contains(atom.predicate()) || !initialAtoms.contains(atom))
                problem.unreachable.add(atom);
        }
        return problem;
    }
}
