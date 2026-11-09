import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    record Run(String algorithm, String heuristic) {
        String tag() { return algorithm + " " + heuristic; }
    }
    static final class Settings {
        int budget, weight, graphplan;
        List<Run> runs = new ArrayList<>();
        Run repair;
        Settings(String text) {
            for (String line : text.split("\n")) {
                if (line.isEmpty() || line.startsWith("#"))
                    continue;
                String[] f = line.split(" ");
                switch (f[0]) {
                case "budget":
                    budget = Integer.parseInt(f[1]);
                    break;
                case "weight":
                    weight = Integer.parseInt(f[1]);
                    break;
                case "graphplan":
                    graphplan = Integer.parseInt(f[1]);
                    break;
                case "run":
                    runs.add(new Run(f[1], f[2]));
                    break;
                case "repair":
                    repair = new Run(f[1], f[2]);
                    break;
                }
            }
        }
    }
    static final class Candidate {
        int number;
        String problem, label;
        List<Grounding.Step> steps = new ArrayList<>();
        Candidate(int number, String problem, String label) {
            this.number = number;
            this.problem = problem;
            this.label = label;
        }
    }
    record Validation(String status, List<String> messages, int correct) {
        String verdict() {
            return status + (status.equals("valid") ? " " : ": ") + messages.getFirst();
        }
    }
    record Transformed(List<GraphPlan.Action> actions, BitSet initial, int complements) {}
    record Summary(int solved, Integer best, String optimal) {}
    static final class Totals {
        int solved, best, expanded, generated;
    }
    static String read(String name) throws Exception {
        return Files.readString(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static List<Candidate> readCandidates(String text) {
        List<Candidate> candidates = new ArrayList<>();
        Candidate current = null;
        for (String line : text.split("\n")) {
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            if (line.startsWith("plan ")) {
                String[] f = line.split(" ");
                current = new Candidate(candidates.size() + 1, f[1], f[2]);
            } else if (line.equals("end")) {
                candidates.add(current);
                current = null;
            } else {
                String[] f = line.substring(1, line.length() - 1).split(" ");
                current.steps.add(new Grounding.Step(f[0], Arrays.asList(f).subList(1, f.length)));
            }
        }
        return candidates;
    }
    static String headed(String heading, List<String> items) {
        return heading + " " + (items.isEmpty() ? "-" : String.join(" ", items));
    }
    static String numberList(BitSet numbers) {
        List<String> values = new ArrayList<>();
        for (int number : Grounding.numbers(numbers))
            values.add(Integer.toString(number));
        return values.isEmpty() ? "-" : String.join(",", values);
    }
    static String valueText(int value) {
        return value == Heuristics.INF ? "inf" : Integer.toString(value);
    }
    static String heuristicText(int[] values) {
        List<String> items = new ArrayList<>();
        for (int i = 0; i < Heuristics.NAMES.size(); i++)
            items.add(Heuristics.NAMES.get(i) + "=" + valueText(values[i]));
        return String.join(" ", items);
    }
    static String argumentError(PddlParser.Domain domain, List<String> arguments,
                                List<String> expected, Map<String, String> table, String noun) {
        if (arguments.size() != expected.size())
            return "expected " + expected.size() + " arguments, got " + arguments.size();
        for (int i = 0; i < arguments.size(); i++) {
            String argument = arguments.get(i), type = table.get(argument);
            if (type == null)
                return "unknown " + noun + " " + argument;
            if (!Grounding.subtype(domain.parents, type, expected.get(i)))
                return "argument " + (i + 1) + " (" + argument + ") is not of type " +
                    expected.get(i);
        }
        return null;
    }
    static void validateDomain(PddlParser.Domain domain) {
        List<PddlParser.Schema> kept = new ArrayList<>();
        for (PddlParser.Schema action : domain.actions) {
            String error = null;
            Map<String, String> parameters = new HashMap<>();
            for (PddlParser.Typed parameter : action.parameters()) {
                parameters.put(parameter.name(), parameter.type());
                if (!domain.parents.containsKey(parameter.type()) && error == null)
                    error = "unknown type " + parameter.type();
            }
            if (error == null) {
                List<PddlParser.Literal> literals = new ArrayList<>(action.condition());
                literals.addAll(action.effects());
                for (PddlParser.Literal literal : literals) {
                    PddlParser.Atom atom = literal.atom();
                    if (!atom.predicate().equals("=") &&
                        !domain.predicates.containsKey(atom.predicate()))
                        error = "unknown predicate " + atom.predicate();
                    else
                        error = argumentError(domain, atom.terms(),
                                              atom.predicate().equals("=")
                                                  ? List.of("object", "object")
                                                  : domain.predicates.get(atom.predicate()),
                                              parameters, "variable");
                    if (error != null) {
                        error = atom + ": " + error;
                        break;
                    }
                }
            }
            if (error == null) {
                kept.add(action);
                domain.byName.put(action.name(), action);
            } else
                domain.diagnostics.add("error: action " + action.name() + ": " + error);
        }
        domain.actions = kept;
        Set<String> used = new HashSet<>();
        for (PddlParser.Schema action : kept) {
            for (PddlParser.Literal literal : action.condition())
                used.add(literal.atom().predicate());
            for (PddlParser.Literal literal : action.effects())
                used.add(literal.atom().predicate());
        }
        for (String predicate : domain.predicates.keySet())
            if (!used.contains(predicate))
                domain.diagnostics.add("warning: predicate " + predicate +
                                       " is not used by any action");
        Grounding.predicateClasses(domain);
    }
    static List<PddlParser.Atom> validateAtoms(PddlParser.Domain domain, PddlParser.Problem problem,
                                               List<PddlParser.Atom> atoms, String side) {
        List<PddlParser.Atom> kept = new ArrayList<>();
        Set<PddlParser.Atom> seen = new HashSet<>();
        for (PddlParser.Atom atom : atoms) {
            String error =
                domain.predicates.containsKey(atom.predicate())
                    ? argumentError(domain, atom.terms(), domain.predicates.get(atom.predicate()),
                                    problem.objects, "object")
                    : "unknown predicate " + atom.predicate();
            if (error == null && seen.contains(atom))
                error = "duplicate";
            if (error == null) {
                kept.add(atom);
                seen.add(atom);
            } else
                problem.diagnostics.add("warning: " + side + " " + atom + ": " + error);
        }
        return kept;
    }
    static void validateProblem(PddlParser.Domain domain, PddlParser.Problem problem) {
        problem.initial = validateAtoms(domain, problem, problem.initial, "init");
        problem.goals = validateAtoms(domain, problem, problem.goals, "goal");
    }
    static Validation validateSteps(PddlParser.Domain domain, PddlParser.Problem problem,
                                    List<Grounding.Step> steps) {
        Set<PddlParser.Atom> world = new HashSet<>(problem.initial);
        int cost = 0;
        for (int i = 0; i < steps.size(); i++) {
            Grounding.Step step = steps.get(i);
            String heading = "step " + (i + 1) + " " + step + ": ";
            PddlParser.Schema schema = domain.byName.get(step.name());
            if (schema == null)
                return new Validation("invalid", List.of(heading + "unknown action " + step.name()),
                                      i);
            List<String> expected = new ArrayList<>();
            for (PddlParser.Typed parameter : schema.parameters())
                expected.add(parameter.type());
            String error =
                argumentError(domain, step.arguments(), expected, problem.objects, "object");
            if (error != null)
                return new Validation("invalid", List.of(heading + error), i);
            Map<String, String> assignment = new HashMap<>();
            for (int p = 0; p < schema.parameters().size(); p++)
                assignment.put(schema.parameters().get(p).name(), step.arguments().get(p));
            for (PddlParser.Literal literal : schema.condition()) {
                PddlParser.Atom bound = Grounding.substitute(literal.atom(), assignment);
                boolean truth = bound.predicate().equals("=")
                                    ? bound.terms().getFirst().equals(bound.terms().get(1))
                                    : world.contains(bound);
                if (truth != literal.positive())
                    return new Validation(
                        "invalid",
                        List.of(heading + "precondition " +
                                (literal.positive() ? bound.toString() : "(not " + bound + ")") +
                                " is false"),
                        i);
            }
            Set<PddlParser.Atom> deletes = new HashSet<>(), adds = new HashSet<>();
            for (PddlParser.Literal literal : schema.effects())
                (literal.positive() ? adds : deletes)
                    .add(Grounding.substitute(literal.atom(), assignment));
            world.removeAll(deletes);
            world.addAll(adds);
            cost += schema.cost();
        }
        List<String> missing = new ArrayList<>();
        for (PddlParser.Atom atom : problem.goals)
            if (!world.contains(atom))
                missing.add("unsatisfied goal " + atom);
        return missing.isEmpty()
            ? new Validation("valid", List.of("length=" + steps.size() + " cost=" + cost),
                             steps.size())
            : new Validation("goal not reached", missing, steps.size());
    }
    static List<Grounding.Step> planSteps(Grounding.Problem problem, List<Integer> plan) {
        List<Grounding.Step> steps = new ArrayList<>();
        for (int number : plan) {
            Grounding.Action action = problem.actions.get(number);
            steps.add(new Grounding.Step(action.source().name(), action.arguments()));
        }
        return steps;
    }
    static int planCost(Grounding.Problem problem, List<Integer> plan) {
        int cost = 0;
        for (int number : plan)
            cost += problem.actions.get(number).cost();
        return cost;
    }
    static boolean interferes(Grounding.Action first, Grounding.Action second) {
        return first.delete().intersects(second.pre()) || first.delete().intersects(second.add()) ||
            second.delete().intersects(first.pre()) || second.delete().intersects(first.add()) ||
            first.add().intersects(second.neg()) || second.add().intersects(first.neg());
    }
    static List<List<Integer>> parallelize(Grounding.Problem problem, List<Integer> plan) {
        List<Integer> assigned = new ArrayList<>();
        List<List<Integer>> layers = new ArrayList<>();
        for (int position = 0; position < plan.size(); position++) {
            Grounding.Action action = problem.actions.get(plan.get(position));
            int layer = 1;
            for (int earlier = 0; earlier < position; earlier++) {
                Grounding.Action previous = problem.actions.get(plan.get(earlier));
                if (previous.add().intersects(action.pre()) ||
                    previous.delete().intersects(action.neg()) || interferes(previous, action))
                    layer = Math.max(layer, assigned.get(earlier) + 1);
            }
            assigned.add(layer);
            while (layers.size() < layer)
                layers.add(new ArrayList<>());
            layers.get(layer - 1).add(action.number());
        }
        return layers;
    }
    static String validateParallel(Grounding.Problem problem, List<List<Integer>> layers) {
        BitSet state = problem.initial;
        for (int k = 0; k < layers.size(); k++) {
            List<Integer> layer = layers.get(k);
            for (int number : layer)
                if (!Search.applicable(problem.actions.get(number), state))
                    return "invalid at layer " + (k + 1);
            for (int i = 0; i < layer.size(); i++)
                for (int j = i + 1; j < layer.size(); j++)
                    if (interferes(problem.actions.get(layer.get(i)),
                                   problem.actions.get(layer.get(j))))
                        return "invalid at layer " + (k + 1);
            BitSet deletes = new BitSet(), adds = new BitSet();
            for (int number : layer) {
                deletes.or(problem.actions.get(number).delete());
                adds.or(problem.actions.get(number).add());
            }
            BitSet next = (BitSet)state.clone();
            next.andNot(deletes);
            next.or(adds);
            state = next;
        }
        return Grounding.contains(state, problem.goal) ? "valid" : "goal not reached";
    }
    static List<Integer> improve(Grounding.Problem problem, List<Integer> plan) {
        List<Integer> sequence = new ArrayList<>(plan);
        int position = 0;
        while (position < sequence.size()) {
            BitSet state = problem.initial;
            for (int i = 0; i < position; i++)
                state = Search.apply(problem.actions.get(sequence.get(i)), state);
            List<Integer> applied = new ArrayList<>();
            for (int i = position + 1; i < sequence.size(); i++) {
                Grounding.Action action = problem.actions.get(sequence.get(i));
                if (Search.applicable(action, state)) {
                    state = Search.apply(action, state);
                    applied.add(action.number());
                }
            }
            if (Grounding.contains(state, problem.goal)) {
                List<Integer> next = new ArrayList<>(sequence.subList(0, position));
                next.addAll(applied);
                sequence = next;
            } else
                position++;
        }
        return sequence;
    }
    static BitSet reachedLandmarks(Grounding.Problem problem, List<Integer> plan,
                                   BitSet landmarks) {
        BitSet state = problem.initial, reached = new BitSet();
        for (int number : plan) {
            state = Search.apply(problem.actions.get(number), state);
            BitSet present = (BitSet)state.clone();
            present.and(landmarks);
            reached.or(present);
        }
        return reached;
    }
    static Transformed transformNegatives(Grounding.Problem problem) {
        BitSet negative = new BitSet();
        for (Grounding.Action action : problem.actions)
            negative.or(action.neg());
        Map<Integer, Integer> complements = new HashMap<>();
        for (int fact : Grounding.numbers(negative))
            complements.put(fact, problem.facts.size() + complements.size());
        List<GraphPlan.Action> actions = new ArrayList<>();
        for (Grounding.Action action : problem.actions) {
            BitSet pre = (BitSet)action.pre().clone(), add = (BitSet)action.add().clone(),
                   delete = (BitSet)action.delete().clone();
            for (int fact : Grounding.numbers(action.neg()))
                pre.set(complements.get(fact));
            for (int fact : Grounding.numbers(action.delete()))
                if (complements.containsKey(fact))
                    add.set(complements.get(fact));
            for (int fact : Grounding.numbers(action.add()))
                if (complements.containsKey(fact))
                    delete.set(complements.get(fact));
            actions.add(new GraphPlan.Action(action.number(), pre, add, delete));
        }
        BitSet initial = (BitSet)problem.initial.clone();
        for (int fact : Grounding.numbers(negative))
            if (!initial.get(fact))
                initial.set(complements.get(fact));
        return new Transformed(actions, initial, complements.size());
    }
    static final class Planner {
        PddlParser.Domain domain;
        List<PddlParser.Problem> sources;
        Settings settings;
        List<Candidate> candidates;
        List<String> tags = new ArrayList<>();
        List<Totals> totals = new ArrayList<>();
        List<String> groundingLines = new ArrayList<>(), planLines = new ArrayList<>(),
                     graphLines = new ArrayList<>(), validationLines = new ArrayList<>(),
                     comparisonLines = new ArrayList<>();
        Map<String, Grounding.Problem> problems = new LinkedHashMap<>();
        Map<String, Heuristics> evaluators = new HashMap<>();
        Map<String, Summary> summaries = new LinkedHashMap<>();
        int validatedPlans, validPlans, validCandidates;
        Planner() throws Exception {
            domain = PddlParser.readDomain(read("domain.txt"));
            sources = PddlParser.readProblems(read("problems.txt"));
            settings = new Settings(read("params.txt"));
            candidates = readCandidates(read("candidates.txt"));
            validateDomain(domain);
            for (Run run : settings.runs)
                tags.add(run.tag());
            tags.add("graphplan");
            for (String tag : tags)
                totals.add(new Totals());
            comparisonLines.add("problem,algorithm,heuristic,length,cost,expanded,generated");
        }
        List<String> actionTexts(Grounding.Problem problem, List<Integer> plan) {
            List<String> text = new ArrayList<>();
            for (int number : plan)
                text.add(problem.actions.get(number).text());
            return text;
        }
        void domainReport() {
            groundingLines.add("== domain " + domain.name + " ==");
            groundingLines.addAll(domain.diagnostics);
            for (String type : domain.typeOrder) {
                List<String> chain = new ArrayList<>();
                for (String current = type; current != null; current = domain.parents.get(current))
                    chain.add(current);
                groundingLines.add("type " + String.join(" < ", chain));
            }
            for (var entry : domain.predicates.entrySet())
                groundingLines.add("predicate " + entry.getKey() + "/" + entry.getValue().size() +
                                   " " +
                                   (domain.fluent.contains(entry.getKey()) ? "fluent" : "static"));
            for (PddlParser.Schema action : domain.actions) {
                int adds = 0, deletes = 0;
                for (PddlParser.Literal literal : action.effects())
                    if (literal.positive())
                        adds++;
                    else
                        deletes++;
                groundingLines.add("action " + action.name() + "/" + action.parameters().size() +
                                   " cost=" + action.cost() + " pre=" + action.condition().size() +
                                   " add=" + adds + " del=" + deletes);
            }
        }
        void groundingReport(Grounding.Problem problem) {
            groundingLines.add("");
            groundingLines.add("== problem " + problem.name + " ==");
            groundingLines.addAll(problem.source.diagnostics);
            groundingLines.add("objects: " + problem.source.objects.size());
            for (String type : domain.typeOrder)
                groundingLines.add(headed("  " + type + ":", problem.objectsByType.get(type)));
            groundingLines.add("static facts: " + problem.staticCount);
            for (PddlParser.Schema action : domain.actions) {
                int[] statistics = problem.statistics.get(action.name());
                groundingLines.add("schema " + action.name() + ": assignments=" + statistics[0] +
                                   " candidates=" + statistics[1] + " reachable=" + statistics[2]);
            }
            groundingLines.add("candidates: " + problem.candidateCount +
                               " reachable: " + problem.actions.size());
            groundingLines.add("facts: " + problem.facts.size() +
                               " init: " + problem.initial.cardinality() +
                               " goals: " + problem.goal.cardinality());
            for (PddlParser.Atom atom : problem.unreachable)
                groundingLines.add("unreachable goal: " + atom);
            Map<String, Integer> counts = new HashMap<>();
            for (PddlParser.Atom fact : problem.facts)
                counts.merge(fact.predicate(), 1, Integer::sum);
            List<String> factsByPredicate = new ArrayList<>();
            for (String predicate : domain.predicates.keySet())
                if (domain.fluent.contains(predicate))
                    factsByPredicate.add(predicate + "=" + counts.getOrDefault(predicate, 0));
            groundingLines.add(headed("facts by predicate:", factsByPredicate));
            groundingLines.add("facts:");
            for (int i = 0; i < problem.facts.size(); i++)
                groundingLines.add("  " + i + " " + problem.facts.get(i));
            groundingLines.add("actions:");
            for (Grounding.Action action : problem.actions)
                groundingLines.add(
                    "  " + action.number() + " " + action.text() + " cost=" + action.cost() +
                    " pre=" + numberList(action.pre()) + " neg=" + numberList(action.neg()) +
                    " add=" + numberList(action.add()) + " del=" + numberList(action.delete()));
        }
        BitSet initialReport(Grounding.Problem problem, Heuristics evaluator) {
            int[] values = evaluator.values(problem.initial);
            BitSet landmarks = evaluator.landmarks(problem.initial);
            if (landmarks == null)
                landmarks = new BitSet();
            List<Integer> relaxed = evaluator.relaxedPlan(problem.initial);
            if (relaxed == null)
                relaxed = List.of();
            planLines.add("initial h: " + heuristicText(values));
            planLines.add("landmarks: " + landmarks.cardinality());
            for (int number : Grounding.numbers(landmarks))
                planLines.add("  " + problem.facts.get(number));
            planLines.add("relaxed plan: length=" + relaxed.size() +
                          " cost=" + valueText(values[3]));
            for (int number : relaxed)
                planLines.add("  " + problem.actions.get(number).text());
            planLines.add(
                headed("helpful:", actionTexts(problem, evaluator.helpful(problem.initial))));
            return landmarks;
        }
        void planReport(Grounding.Problem problem, String tag, List<Integer> plan, BitSet landmarks,
                        Map<List<Integer>, String> earlier) {
            String first = earlier.computeIfAbsent(plan, p -> tag);
            planLines.add("plan: length=" + plan.size() + " cost=" + planCost(problem, plan) +
                          (first.equals(tag) ? "" : " (same as " + first + ")"));
            for (int i = 0; i < plan.size(); i++)
                planLines.add("  " + (i + 1) + " " + problem.actions.get(plan.get(i)).text());
            Map<String, Integer> counts = new HashMap<>();
            for (int number : plan)
                counts.merge(problem.actions.get(number).source().name(), 1, Integer::sum);
            List<String> schemas = new ArrayList<>();
            for (PddlParser.Schema schema : domain.actions)
                if (counts.containsKey(schema.name()))
                    schemas.add(schema.name() + "=" + counts.get(schema.name()));
            planLines.add(headed("schemas:", schemas));
            List<List<Integer>> layers = parallelize(problem, plan);
            planLines.add("parallel: layers=" + layers.size());
            for (int i = 0; i < layers.size(); i++)
                planLines.add(headed("  " + (i + 1) + ":", actionTexts(problem, layers.get(i))));
            List<Integer> improved = improve(problem, plan);
            int removed = plan.size() - improved.size();
            planLines.add("improved: length=" + improved.size() +
                          " cost=" + planCost(problem, improved) + " removed=" + removed);
            if (removed > 0)
                for (int i = 0; i < improved.size(); i++)
                    planLines.add("  " + (i + 1) + " " +
                                  problem.actions.get(improved.get(i)).text());
            BitSet reached = reachedLandmarks(problem, plan, landmarks);
            planLines.add("landmarks reached: " + reached.cardinality() + "/" +
                          landmarks.cardinality());
            BitSet missed = (BitSet)landmarks.clone();
            missed.andNot(reached);
            for (int number : Grounding.numbers(missed))
                planLines.add("  missed " + problem.facts.get(number));
            Validation checked = validateSteps(domain, problem.source, planSteps(problem, plan)),
                       checkedImproved =
                           validateSteps(domain, problem.source, planSteps(problem, improved));
            validationLines.add(tag + ": " + checked.verdict());
            validationLines.add("  parallel: " + validateParallel(problem, layers));
            validationLines.add("  improved: " + checkedImproved.verdict());
            validatedPlans++;
            if (checked.status().equals("valid"))
                validPlans++;
        }
        void searchResultReport(Grounding.Problem problem, String tag, Search.Result outcome,
                                BitSet landmarks, Map<List<Integer>, String> earlier) {
            planLines.add("-- " + tag + " --");
            if (!problem.unreachable.isEmpty()) {
                planLines.add("result: FAIL (unreachable goal)");
                return;
            }
            planLines.add(
                "result: " + (outcome.solved() ? "solved" : "FAIL (" + outcome.status() + ")") +
                " expanded=" + outcome.expanded() + " generated=" + outcome.generated());
            if (outcome.solved())
                planReport(problem, tag, outcome.plan(), landmarks, earlier);
        }
        void graphReport(Grounding.Problem problem, GraphPlan.Result outcome, int complements) {
            if (!problem.unreachable.isEmpty()) {
                graphLines.add("result: FAIL (unreachable goal)");
                return;
            }
            graphLines.add("complementary facts: " + complements);
            graphLines.addAll(outcome.lines());
            Search.Result search = outcome.search();
            String counts = " searched=" + search.expanded() + " memo_hits=" + outcome.memoHits() +
                            " tried=" + search.generated();
            if (search.solved()) {
                graphLines.add("result: solved levels=" + outcome.layers().size() +
                               " length=" + search.plan().size() +
                               " cost=" + planCost(problem, search.plan()) + counts);
                for (int i = 0; i < outcome.layers().size(); i++)
                    graphLines.add(headed("layer " + (i + 1) + ":",
                                          actionTexts(problem, outcome.layers().get(i))));
            } else
                graphLines.add("result: FAIL (" + search.status() + ")" + counts);
        }
        void profileReport(Grounding.Problem problem, Heuristics evaluator, String tag,
                           List<Integer> plan) {
            BitSet state = problem.initial;
            int remaining = planCost(problem, plan);
            int[] overestimates = new int[Heuristics.NAMES.size()];
            planLines.add("-- profile (" + tag + ") --");
            for (int position = 0; position <= plan.size(); position++) {
                int[] values = evaluator.values(state);
                planLines.add("  " + position + ": h*=" + remaining + " " + heuristicText(values));
                for (int i = 0; i < values.length; i++)
                    if (values[i] == Heuristics.INF || values[i] > remaining)
                        overestimates[i]++;
                if (position < plan.size()) {
                    Grounding.Action action = problem.actions.get(plan.get(position));
                    state = Search.apply(action, state);
                    remaining -= action.cost();
                }
            }
            List<String> counts = new ArrayList<>();
            for (int i = 0; i < overestimates.length; i++)
                counts.add(Heuristics.NAMES.get(i) + "=" + overestimates[i]);
            planLines.add("overestimates: " + String.join(" ", counts));
            planLines.add("-- causal links (" + tag + ") --");
            Map<Integer, Integer> suppliers = new HashMap<>();
            for (int i = 0; i < plan.size(); i++) {
                Grounding.Action action = problem.actions.get(plan.get(i));
                List<String> links = new ArrayList<>();
                for (int fact : Grounding.numbers(action.pre()))
                    links.add(problem.facts.get(fact) + "<-" + suppliers.getOrDefault(fact, 0));
                planLines.add(headed("  " + (i + 1) + " " + action.text() + ":", links));
                for (int fact : Grounding.numbers(action.add()))
                    suppliers.put(fact, i + 1);
            }
            List<String> links = new ArrayList<>();
            for (int fact : Grounding.numbers(problem.goal))
                links.add(problem.facts.get(fact) + "<-" + suppliers.getOrDefault(fact, 0));
            planLines.add(headed("  goal:", links));
        }
        void summarizeProblem(Grounding.Problem problem, List<Search.Result> outcomes,
                              Integer proof) {
            int solved = 0;
            Integer best = null;
            for (Search.Result outcome : outcomes)
                if (outcome.solved()) {
                    solved++;
                    int cost = planCost(problem, outcome.plan());
                    if (best == null || cost < best)
                        best = cost;
                }
            String optimal;
            if (proof != null)
                optimal = Integer.toString(planCost(problem, outcomes.get(proof).plan()));
            else {
                optimal = "unknown";
                for (Search.Result outcome : outcomes)
                    if (Set.of("unreachable goal", "dead end", "exhausted", "unreachable")
                            .contains(outcome.status()))
                        optimal = "none";
            }
            summaries.put(problem.name, new Summary(solved, best, optimal));
            List<Run> pairs = new ArrayList<>(settings.runs);
            pairs.add(new Run("graphplan", "none"));
            for (int i = 0; i < outcomes.size(); i++) {
                Search.Result outcome = outcomes.get(i);
                Run pair = pairs.get(i);
                Totals total = totals.get(i);
                total.expanded += outcome.expanded();
                total.generated += outcome.generated();
                String length = "-", cost = "-";
                if (outcome.solved()) {
                    int value = planCost(problem, outcome.plan());
                    length = Integer.toString(outcome.plan().size());
                    cost = Integer.toString(value);
                    total.solved++;
                    if (value == best)
                        total.best++;
                }
                comparisonLines.add(problem.name + "," + pair.algorithm() + "," + pair.heuristic() +
                                    "," + length + "," + cost + "," + outcome.expanded() + "," +
                                    outcome.generated());
            }
        }
        void solveProblem(PddlParser.Problem source) {
            validateProblem(domain, source);
            Grounding.Problem problem = Grounding.ground(domain, source);
            problems.put(problem.name, problem);
            groundingReport(problem);
            for (List<String> lines : List.of(planLines, graphLines, validationLines))
                lines.add("== problem " + problem.name + " ==");
            List<Search.Result> outcomes = new ArrayList<>();
            Map<List<Integer>, String> earlier = new HashMap<>();
            Integer proof = null;
            Heuristics evaluator = null;
            BitSet landmarks = new BitSet();
            boolean unreachable = !problem.unreachable.isEmpty();
            if (unreachable)
                planLines.add("initial h: unreachable goal");
            else {
                evaluator = new Heuristics(problem);
                evaluators.put(problem.name, evaluator);
                landmarks = initialReport(problem, evaluator);
            }
            for (int i = 0; i < settings.runs.size(); i++) {
                Run run = settings.runs.get(i);
                Search.Result outcome =
                    unreachable
                        ? Search.failure("unreachable goal", 0, 0)
                        : Search.run(problem, problem.initial, run.algorithm(), run.heuristic(),
                                     settings.budget, settings.weight, evaluator);
                outcomes.add(outcome);
                searchResultReport(problem, tags.get(i), outcome, landmarks, earlier);
                if (proof == null && outcome.solved() &&
                    (run.algorithm().equals("ucs") && run.heuristic().equals("none") ||
                     run.algorithm().equals("astar") && run.heuristic().equals("hmax")))
                    proof = i;
            }
            int complements = 0;
            GraphPlan.Result graph;
            if (unreachable)
                graph = new GraphPlan.Result(Search.failure("unreachable goal", 0, 0), List.of(),
                                             List.of(), 0);
            else {
                Transformed transformed = transformNegatives(problem);
                complements = transformed.complements();
                graph = new GraphPlan(transformed.actions(), transformed.initial(), problem.goal,
                                      settings.graphplan)
                            .run();
            }
            outcomes.add(graph.search());
            searchResultReport(problem, "graphplan", graph.search(), landmarks, earlier);
            graphReport(problem, graph, complements);
            if (proof != null)
                profileReport(problem, evaluator, tags.get(proof), outcomes.get(proof).plan());
            summarizeProblem(problem, outcomes, proof);
            for (List<String> lines : List.of(planLines, graphLines, validationLines))
                lines.add("");
        }
        void summaryReport() {
            planLines.add("== summary ==");
            for (var entry : summaries.entrySet()) {
                Summary summary = entry.getValue();
                planLines.add(
                    entry.getKey() + ": solved=" + summary.solved() + "/" + tags.size() +
                    " best=" + (summary.best() == null ? "-" : summary.best().toString()) +
                    " optimal=" + summary.optimal());
            }
            for (int i = 0; i < tags.size(); i++) {
                Totals total = totals.get(i);
                planLines.add(tags.get(i) + ": solved=" + total.solved + " best=" + total.best +
                              " expanded=" + total.expanded + " generated=" + total.generated);
            }
        }
        List<Integer> mappedSteps(Grounding.Problem problem, List<Grounding.Step> steps) {
            List<Integer> plan = new ArrayList<>();
            for (Grounding.Step step : steps)
                plan.add(problem.actionNumbers.get(step));
            return plan;
        }
        void repairCandidate(Grounding.Problem problem, Candidate candidate, Validation checked) {
            if (!problem.unreachable.isEmpty()) {
                validationLines.add("  repair: FAIL (unreachable goal)");
                return;
            }
            List<Integer> prefix =
                mappedSteps(problem, candidate.steps.subList(0, checked.correct()));
            BitSet state = problem.initial;
            for (int number : prefix)
                state = Search.apply(problem.actions.get(number), state);
            Search.Result outcome =
                Search.run(problem, state, settings.repair.algorithm(), settings.repair.heuristic(),
                           settings.budget, settings.weight, evaluators.get(problem.name));
            if (!outcome.solved()) {
                validationLines.add("  repair: FAIL (" + outcome.status() + ")");
                return;
            }
            List<Integer> repaired = new ArrayList<>(prefix);
            repaired.addAll(outcome.plan());
            Validation validation =
                validateSteps(domain, problem.source, planSteps(problem, repaired));
            validationLines.add("  repair: kept=" + prefix.size() +
                                " added=" + outcome.plan().size() + " " + validation.verdict());
            for (int i = 0; i < repaired.size(); i++)
                validationLines.add("    " + (i + 1) + " " +
                                    problem.actions.get(repaired.get(i)).text());
        }
        void candidateReport() {
            validationLines.add("== candidates ==");
            for (Candidate candidate : candidates) {
                Grounding.Problem problem = problems.get(candidate.problem);
                Validation checked = validateSteps(domain, problem.source, candidate.steps);
                String heading = "candidate " + candidate.number + " " + candidate.problem + " " +
                                 candidate.label + ": ";
                if (checked.status().equals("valid")) {
                    validCandidates++;
                    validationLines.add(heading + checked.verdict());
                    List<Integer> mapped = mappedSteps(problem, candidate.steps),
                                  improved = improve(problem, mapped);
                    Integer best = summaries.get(problem.name).best();
                    validationLines.add("  improved: length=" + improved.size() +
                                        " cost=" + planCost(problem, improved) +
                                        " removed=" + (mapped.size() - improved.size()) +
                                        " best known=" + (best == null ? "-" : best.toString()));
                } else {
                    validationLines.add(heading + checked.status());
                    for (String message : checked.messages())
                        validationLines.add("  " + message);
                    repairCandidate(problem, candidate, checked);
                }
            }
            validationLines.add("");
            validationLines.add("== summary ==");
            validationLines.add("plans: " + validatedPlans + " valid: " + validPlans);
            validationLines.add("candidates: " + candidates.size() + " valid: " + validCandidates);
        }
        void writeReports() throws Exception {
            Files.createDirectories(Path.of("output"));
            Map<String, List<String>> reports = new LinkedHashMap<>();
            reports.put("grounding.txt", groundingLines);
            reports.put("plans.txt", planLines);
            reports.put("graphplan.txt", graphLines);
            reports.put("validation.txt", validationLines);
            reports.put("comparison.csv", comparisonLines);
            for (var entry : reports.entrySet())
                Files.writeString(Path.of("output", entry.getKey()),
                                  String.join("\n", entry.getValue()) + "\n",
                                  StandardCharsets.US_ASCII);
        }
        void run() throws Exception {
            domainReport();
            for (PddlParser.Problem source : sources)
                solveProblem(source);
            summaryReport();
            candidateReport();
            writeReports();
        }
    }
    public static void main(String[] args) throws Exception { new Planner().run(); }
}
