import java.nio.file.*;
import java.util.*;
public class Main {
    static NetworkIo.Network network;
    static NetworkIo.Settings settings;
    static List<int[]> samples;
    static List<String> names;
    static List<List<String>> states;
    static List<List<Integer>> parents, children = new ArrayList<>(), spouses = new ArrayList<>(),
                                        blankets = new ArrayList<>();
    static List<Set<Integer>> ancestors = new ArrayList<>(), descendants = new ArrayList<>();
    static List<Integer> variables = new ArrayList<>(), topological = new ArrayList<>();
    static int[] sizes, depths, parameterCounts;
    static List<int[][]> counts = new ArrayList<>();
    static List<double[][]> learned = new ArrayList<>(), cpts = new ArrayList<>();
    static double[] likelihoods;
    static List<Factors.Factor> factors = new ArrayList<>();
    static Sampling.Minstd random;
    static Map<String, Double> familyScores = new HashMap<>();
    record Evidence(int variable, int state) {}
    record Parts(List<Integer> query, List<Evidence> evidence) {}
    record Plans(Elimination.Plan minfill, Elimination.Plan given) {}
    record SumResult(Factors.Factor distribution, double probability, double[][] marginals) {}
    record Posterior(List<Integer> relevant, List<Integer> eliminate, List<Factors.Factor> initial,
                     Plans plans, SumResult result) {}
    record Enumeration(long count, String result) {}
    record Answer(List<String> lines, List<String> elimination) {}
    record Mpe(double maximum, int[] assignment) {}
    record SampleAnswer(List<String> lines, List<String> csv) {}
    record Ball(int variable, int direction) {}
    record Information(double cmi, double g2, long degrees) {}
    static String real(double value) {
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }
    static String yes(boolean value) { return value ? "yes" : "no"; }
    static List<Integer> sorted(Collection<Integer> values) {
        return new ArrayList<>(new TreeSet<>(values));
    }
    static List<Integer> union(Collection<Integer> a, Collection<Integer> b) {
        TreeSet<Integer> result = new TreeSet<>(a);
        result.addAll(b);
        return new ArrayList<>(result);
    }
    static List<Integer> difference(Collection<Integer> a, Collection<Integer> b) {
        TreeSet<Integer> result = new TreeSet<>(a);
        result.removeAll(b);
        return new ArrayList<>(result);
    }
    static Set<Integer> closure(Collection<Integer> initial, List<List<Integer>> links) {
        Set<Integer> reached = new TreeSet<>(initial);
        ArrayDeque<Integer> pending = new ArrayDeque<>(initial);
        while (!pending.isEmpty())
            for (int neighbor : links.get(pending.pop()))
                if (reached.add(neighbor))
                    pending.push(neighbor);
        return reached;
    }
    static String sequence(Collection<Integer> variables) {
        List<String> parts = new ArrayList<>();
        for (int v : variables)
            parts.add(names.get(v));
        return parts.isEmpty() ? "-" : String.join(" ", parts);
    }
    static String assignmentText(int[] assignment, List<Integer> variables) {
        List<String> parts = new ArrayList<>();
        for (int v : variables)
            parts.add(names.get(v) + "=" + states.get(v).get(assignment[v]));
        return parts.isEmpty() ? "-" : String.join(" ", parts);
    }
    static int[] evidenceArray(List<Evidence> evidence) {
        int[] values = new int[sizes.length];
        Arrays.fill(values, -1);
        for (Evidence e : evidence)
            values[e.variable()] = e.state();
        return values;
    }
    static List<Integer> evidenceVariables(List<Evidence> evidence) {
        List<Integer> values = new ArrayList<>();
        for (Evidence e : evidence)
            values.add(e.variable());
        return sorted(values);
    }
    static List<Evidence> evidence(List<String> fields) {
        List<Evidence> result = new ArrayList<>();
        for (String field : fields) {
            String[] w = field.split("=");
            int v = names.indexOf(w[0]);
            result.add(new Evidence(v, states.get(v).indexOf(w[1])));
        }
        return result;
    }
    static Parts parts(List<String> fields) {
        int separator = fields.indexOf("|");
        if (separator < 0)
            separator = fields.size();
        List<Integer> query = new ArrayList<>();
        for (String name : fields.subList(0, separator))
            query.add(names.indexOf(name));
        return new Parts(query, separator == fields.size()
                                    ? List.of()
                                    : evidence(fields.subList(separator + 1, fields.size())));
    }
    static void prepare(NetworkIo.Input input) {
        network = input.network();
        settings = input.settings();
        samples = input.samples();
        names = network.names();
        states = network.states();
        parents = network.parents();
        sizes = new int[names.size()];
        depths = new int[names.size()];
        likelihoods = new double[names.size()];
        parameterCounts = new int[names.size()];
        for (int v = 0; v < names.size(); v++) {
            variables.add(v);
            sizes[v] = states.get(v).size();
            List<Integer> list = new ArrayList<>();
            for (int child = 0; child < names.size(); child++)
                if (parents.get(child).contains(v))
                    list.add(child);
            children.add(list);
        }
        boolean[] selected = new boolean[sizes.length];
        while (topological.size() < sizes.length)
            for (int v : variables)
                if (!selected[v]) {
                    boolean ready = true;
                    for (int p : parents.get(v))
                        if (!selected[p])
                            ready = false;
                    if (ready) {
                        selected[v] = true;
                        topological.add(v);
                        break;
                    }
                }
        for (int v : topological)
            for (int p : parents.get(v))
                depths[v] = Math.max(depths[v], depths[p] + 1);
        for (int v : variables) {
            ancestors.add(closure(parents.get(v), parents));
            descendants.add(closure(children.get(v), children));
            List<Integer> immediate = union(parents.get(v), children.get(v));
            TreeSet<Integer> coParents = new TreeSet<>();
            for (int child : children.get(v))
                coParents.addAll(parents.get(child));
            coParents.removeAll(immediate);
            coParents.remove(v);
            spouses.add(new ArrayList<>(coParents));
            blankets.add(union(immediate, coParents));
            int[][] observed = Learning.counts(v, parents.get(v), samples, sizes);
            counts.add(observed);
            double[][] fitted = Learning.learn(observed, settings.alpha());
            learned.add(fitted);
            double[][] used =
                settings.sources().get(v).equals("GIVEN") ? network.expert().get(v) : fitted;
            cpts.add(used);
            likelihoods[v] = Learning.likelihood(observed, used);
            parameterCounts[v] = Learning.parameters(observed);
            factors.add(Factors.cpt(v, parents.get(v), used, sizes));
        }
        random = new Sampling.Minstd(settings.seed());
    }
    static Plans plans(List<Factors.Factor> initial, List<Integer> eliminate) {
        return new Plans(Elimination.plan(initial, eliminate, "MINFILL", settings.order(), sizes),
                         Elimination.plan(initial, eliminate, "GIVEN", settings.order(), sizes));
    }
    static Elimination.Plan used(Plans plans) {
        return settings.method().equals("MINFILL") ? plans.minfill() : plans.given();
    }
    static SumResult sumResult(List<Factors.Factor> initial, Elimination.Plan plan,
                               List<Integer> query) {
        Factors.Factor factor = Elimination.execute(initial, plan, sizes, false).factor();
        double probability = Learning.total(factor.values);
        double[] values = new double[factor.values.length];
        for (int i = 0; i < values.length; i++)
            values[i] = factor.values[i] / probability;
        Factors.Factor distribution = new Factors.Factor(factor.variables, values, sizes);
        double[][] marginals = new double[sizes.length][];
        for (int v : query)
            marginals[v] = new double[sizes[v]];
        for (int i = 0; i < values.length; i++) {
            int[] assignment = Factors.assignment(i, factor.variables, sizes);
            for (int v : query)
                marginals[v][assignment[v]] += values[i];
        }
        return new SumResult(distribution, probability, marginals);
    }
    static Posterior posterior(List<Integer> query, List<Evidence> evidence) {
        List<Integer> relevant =
                          sorted(closure(union(query, evidenceVariables(evidence)), parents)),
                      eliminate =
                          difference(difference(relevant, query), evidenceVariables(evidence));
        List<Factors.Factor> initial = new ArrayList<>();
        int[] observed = evidenceArray(evidence);
        for (int v : relevant)
            initial.add(factors.get(v).reduced(observed));
        Plans plans = plans(initial, eliminate);
        return new Posterior(relevant, eliminate, initial, plans,
                             sumResult(initial, used(plans), query));
    }
    static double joint(int[] assignment, List<Integer> variables) {
        double probability = 1;
        for (int v : variables)
            probability *=
                cpts.get(v)[Learning.parentRow(parents.get(v), assignment, sizes)][assignment[v]];
        return probability;
    }
    static void addEvidence(int[] assignment, List<Evidence> evidence) {
        for (Evidence e : evidence)
            assignment[e.variable()] = e.state();
    }
    static Enumeration queryEnumeration(Posterior result, List<Integer> query,
                                        List<Evidence> evidence) {
        List<Integer> free = difference(result.relevant(), evidenceVariables(evidence));
        int count = Factors.entries(free, sizes);
        if (count > settings.limit())
            return new Enumeration(count, "skipped");
        List<Integer> ordered = sorted(query);
        double[] values = new double[Factors.entries(ordered, sizes)];
        for (int i = 0; i < count; i++) {
            int[] assignment = Factors.assignment(i, free, sizes);
            addEvidence(assignment, evidence);
            values[Learning.parentRow(ordered, assignment, sizes)] +=
                joint(assignment, result.relevant());
        }
        double probability = Learning.total(values);
        boolean agreed =
            Math.abs(Math.log(probability) - Math.log(result.result().probability())) <= 1e-9;
        for (int i = 0; i < values.length; i++)
            agreed &= Math.abs(values[i] / probability -
                               result.result().distribution().values[i]) <= 1e-9;
        return new Enumeration(count, agreed ? "agree" : "disagree");
    }
    static List<String> eliminationLines(List<Integer> relevant, List<Integer> eliminate,
                                         Plans plans, boolean agreement, Enumeration enumeration) {
        List<String> lines = new ArrayList<>();
        lines.add("relevant " + sequence(relevant));
        lines.add("pruned " + sequence(difference(variables, relevant)));
        lines.add("eliminate " + sequence(eliminate));
        for (int i = 0; i < 2; i++) {
            Elimination.Plan plan = i == 0 ? plans.minfill() : plans.given();
            lines.add("order " + (i == 0 ? "minfill" : "given"));
            for (Elimination.Step step : plan.steps())
                lines.add("step " + names.get(step.variable()) + " fill " + step.fill() +
                          " scope " + sequence(step.scope()) + " entries " + step.size());
            lines.add("cost max " + plan.maximum() + " total " + plan.total());
        }
        lines.add("used " + settings.method().toLowerCase(Locale.ROOT));
        lines.add("orders_agree " + yes(agreement));
        lines.add("enumeration " + enumeration.count() + " " + enumeration.result());
        return lines;
    }
    static List<String> marginalLines(String prefix, List<Integer> query, double[][] marginals) {
        List<String> lines = new ArrayList<>();
        for (int v : query) {
            String line = prefix + " " + names.get(v);
            for (int s = 0; s < sizes[v]; s++)
                line += " " + states.get(v).get(s) + " " + real(marginals[v][s]);
            lines.add(line);
        }
        return lines;
    }
    static Answer answerQuery(List<Integer> query, List<Evidence> evidence) {
        Posterior result = posterior(query, evidence);
        List<String> lines = new ArrayList<>();
        lines.add("log_evidence " + real(Math.log(result.result().probability())));
        if (!evidence.isEmpty()) {
            double conflict = 0;
            for (Evidence e : evidence)
                conflict += Math.log(posterior(List.of(), List.of(e)).result().probability());
            conflict -= Math.log(result.result().probability());
            lines.add("conflict " + real(conflict));
        }
        Factors.Factor distribution = result.result().distribution();
        if (query.size() >= 2)
            for (int i = 0; i < distribution.values.length; i++)
                lines.add("joint " +
                          assignmentText(Factors.assignment(i, distribution.variables, sizes),
                                         distribution.variables) +
                          " " + real(distribution.values[i]));
        lines.addAll(marginalLines("marginal", query, result.result().marginals()));
        for (Evidence e : evidence) {
            List<Evidence> reduced = new ArrayList<>();
            for (Evidence other : evidence)
                if (other.variable() != e.variable())
                    reduced.add(other);
            double[][] without = posterior(query, reduced).result().marginals();
            double shift = 0;
            for (int v : query)
                for (int s = 0; s < sizes[v]; s++)
                    shift = Math.max(shift,
                                     Math.abs(result.result().marginals()[v][s] - without[v][s]));
            lines.add("drop " + names.get(e.variable()) + "=" +
                      states.get(e.variable()).get(e.state()) + " shift " + real(shift));
        }
        SumResult a = sumResult(result.initial(), result.plans().minfill(), query),
                  b = sumResult(result.initial(), result.plans().given(), query);
        boolean agree = Math.abs(Math.log(a.probability()) - Math.log(b.probability())) <= 1e-9;
        for (int i = 0; i < a.distribution().values.length; i++)
            agree &= Math.abs(a.distribution().values[i] - b.distribution().values[i]) <= 1e-9;
        return new Answer(lines,
                          eliminationLines(result.relevant(), result.eliminate(), result.plans(),
                                           agree, queryEnumeration(result, query, evidence)));
    }
    static Mpe maxResult(List<Factors.Factor> initial, Elimination.Plan plan,
                         List<Evidence> evidence) {
        Elimination.Outcome outcome = Elimination.execute(initial, plan, sizes, true);
        int[] assignment = Elimination.traceback(outcome.products(), sizes);
        addEvidence(assignment, evidence);
        return new Mpe(outcome.factor().values[0], assignment);
    }
    static Enumeration mpeEnumeration(List<Integer> eliminate, List<Evidence> evidence, Mpe mpe) {
        int count = Factors.entries(eliminate, sizes);
        if (count > settings.limit())
            return new Enumeration(count, "skipped");
        double best = -1;
        int[] assignment = null;
        for (int i = 0; i < count; i++) {
            int[] candidate = Factors.assignment(i, eliminate, sizes);
            addEvidence(candidate, evidence);
            double probability = joint(candidate, variables);
            if (probability > best) {
                best = probability;
                assignment = candidate;
            }
        }
        boolean agree = Arrays.equals(assignment, mpe.assignment()) &&
                        Math.abs(Math.log(best) - Math.log(mpe.maximum())) <= 1e-9;
        return new Enumeration(count, agree ? "agree" : "disagree");
    }
    static Answer answerMpe(List<Evidence> evidence) {
        int[] observed = evidenceArray(evidence);
        List<Factors.Factor> initial = new ArrayList<>();
        for (Factors.Factor factor : factors)
            initial.add(factor.reduced(observed));
        List<Integer> eliminate = difference(variables, evidenceVariables(evidence));
        Plans plans = plans(initial, eliminate);
        Mpe a = maxResult(initial, plans.minfill(), evidence),
            b = maxResult(initial, plans.given(), evidence),
            result = settings.method().equals("MINFILL") ? a : b;
        double probability =
            evidence.isEmpty() ? 1 : posterior(List.of(), evidence).result().probability();
        List<String> lines = new ArrayList<>();
        lines.add("assignment " + assignmentText(result.assignment(), variables));
        lines.add("log_joint " + real(Math.log(result.maximum())));
        lines.add("log_evidence " + real(Math.log(probability)));
        lines.add("posterior " + real(result.maximum() / probability));
        for (int v : eliminate) {
            List<Integer> remaining = new ArrayList<>(eliminate);
            remaining.remove(Integer.valueOf(v));
            Elimination.Plan plan =
                Elimination.plan(initial, remaining, settings.method(), settings.order(), sizes);
            Factors.Factor factor = Elimination.execute(initial, plan, sizes, true).factor();
            int alternative = -1;
            for (int s = 0; s < sizes[v]; s++)
                if (s != result.assignment()[v] &&
                    (alternative < 0 || factor.values[s] > factor.values[alternative]))
                    alternative = s;
            double margin = Math.log(result.maximum()) - Math.log(factor.values[alternative]);
            lines.add("margin " + names.get(v) + " " + states.get(v).get(alternative) + " " +
                      real(margin));
        }
        boolean agree = Arrays.equals(a.assignment(), b.assignment()) &&
                        Math.abs(Math.log(a.maximum()) - Math.log(b.maximum())) <= 1e-9;
        return new Answer(lines, eliminationLines(variables, eliminate, plans, agree,
                                                  mpeEnumeration(eliminate, evidence, result)));
    }
    static SampleAnswer answerSample(int number, List<Integer> query, List<Evidence> evidence,
                                     List<Integer> checkpoints) {
        double[][] exact = posterior(query, evidence).result().marginals(),
                   weights = new double[sizes.length][];
        for (int v : query)
            weights[v] = new double[sizes[v]];
        List<String> lines = marginalLines("exact", query, exact), csv = new ArrayList<>();
        double weight = 0, squaredWeight = 0;
        int[] observed = evidenceArray(evidence);
        Set<Integer> selected = new HashSet<>(checkpoints);
        for (int i = 1; i <= checkpoints.getLast(); i++) {
            Sampling.Weighted sample =
                Sampling.weighted(topological, parents, cpts, sizes, observed, random);
            double current = sample.weight();
            weight += current;
            squaredWeight += current * current;
            for (int v : query)
                weights[v][sample.sample()[v]] += current;
            if (!selected.contains(i))
                continue;
            double maximumError = 0;
            for (int v : query)
                for (int s = 0; s < sizes[v]; s++) {
                    double estimate = weights[v][s] / weight, probability = exact[v][s],
                           error = Math.abs(estimate - probability);
                    maximumError = Math.max(maximumError, error);
                    csv.add(number + "," + i + "," + names.get(v) + "," + states.get(v).get(s) +
                            "," + real(estimate) + "," + real(probability) + "," + real(error));
                }
            double effective = weight * weight / squaredWeight;
            lines.add("after " + i + " weight " + real(weight) + " ess " + real(effective) +
                      " max_error " + real(maximumError));
        }
        return new SampleAnswer(lines, csv);
    }
    static List<String> answerPredict(int variable) {
        int size = sizes[variable];
        int[][] confusion = new int[size][size];
        double likelihood = 0;
        for (int[] sample : samples) {
            int[] assignment = sample.clone();
            double[] values = new double[size];
            for (int s = 0; s < size; s++) {
                assignment[variable] = s;
                double probability = cpts.get(
                    variable)[Learning.parentRow(parents.get(variable), assignment, sizes)][s];
                for (int child : children.get(variable))
                    probability *=
                        cpts.get(child)[Learning.parentRow(parents.get(child), assignment, sizes)]
                                       [assignment[child]];
                values[s] = probability;
            }
            double total = Learning.total(values);
            int predicted = 0;
            for (int s = 0; s < size; s++) {
                values[s] /= total;
                if (values[s] > values[predicted])
                    predicted = s;
            }
            int actual = sample[variable];
            confusion[actual][predicted]++;
            likelihood += Math.log(values[actual]);
        }
        int correct = 0;
        for (int s = 0; s < size; s++)
            correct += confusion[s][s];
        int count = samples.size();
        List<String> lines = new ArrayList<>();
        lines.add("blanket " + sequence(blankets.get(variable)));
        lines.add("accuracy " + correct + "/" + count + " " + real(correct / (double)count));
        lines.add("log_loss " + real(-likelihood / count));
        lines.add("predicted " + String.join(" ", states.get(variable)));
        for (int s = 0; s < size; s++) {
            String line = "actual " + states.get(variable).get(s);
            for (int value : confusion[s])
                line += " " + value;
            lines.add(line);
        }
        return lines;
    }
    static void addBall(ArrayDeque<Ball> queue, boolean[][] visited, int variable, int direction) {
        if (!visited[variable][direction]) {
            visited[variable][direction] = true;
            queue.add(new Ball(variable, direction));
        }
    }
    static List<Integer> reachable(Collection<Integer> x, Collection<Integer> z) {
        Set<Integer> observed = new HashSet<>(z), initial = new HashSet<>(x),
                     ancestors = closure(z, parents);
        boolean[][] visited = new boolean[sizes.length][2];
        ArrayDeque<Ball> pending = new ArrayDeque<>();
        for (int v : sorted(x))
            addBall(pending, visited, v, 0);
        while (!pending.isEmpty()) {
            Ball ball = pending.removeFirst();
            int v = ball.variable();
            if (ball.direction() == 0 && !observed.contains(v)) {
                for (int p : parents.get(v))
                    addBall(pending, visited, p, 0);
                for (int child : children.get(v))
                    addBall(pending, visited, child, 1);
            } else if (ball.direction() == 1) {
                if (!observed.contains(v))
                    for (int child : children.get(v))
                        addBall(pending, visited, child, 1);
                if (ancestors.contains(v))
                    for (int p : parents.get(v))
                        addBall(pending, visited, p, 0);
            }
        }
        List<Integer> result = new ArrayList<>();
        for (int v : variables)
            if ((visited[v][0] || visited[v][1]) && !observed.contains(v) && !initial.contains(v))
                result.add(v);
        return result;
    }
    static TreeMap<Integer, Integer> frequencies(List<Integer> scope) {
        TreeMap<Integer, Integer> counts = new TreeMap<>();
        for (int[] sample : samples)
            counts.merge(Learning.parentRow(scope, sample, sizes), 1, Integer::sum);
        return counts;
    }
    static Information information(List<Integer> x, List<Integer> y, List<Integer> z) {
        List<Integer> scope = union(union(x, y), z), xz = union(x, z), yz = union(y, z),
                      orderedZ = sorted(z);
        TreeMap<Integer, Integer> observed = frequencies(scope), countsXz = frequencies(xz),
                                  countsYz = frequencies(yz), countsZ = frequencies(orderedZ);
        double information = 0;
        for (var entry : observed.entrySet()) {
            int[] assignment = Factors.assignment(entry.getKey(), scope, sizes);
            int count = entry.getValue(),
                nxz = countsXz.get(Learning.parentRow(xz, assignment, sizes)),
                nyz = countsYz.get(Learning.parentRow(yz, assignment, sizes)),
                nz = countsZ.get(Learning.parentRow(orderedZ, assignment, sizes));
            double argument = (count * (double)nz) / (nxz * (double)nyz);
            information += (count / (double)samples.size()) * Math.log(argument);
        }
        long degrees = (long)(Factors.entries(x, sizes) - 1) * (Factors.entries(y, sizes) - 1) *
                       Factors.entries(z, sizes);
        return new Information(information, 2 * samples.size() * information, degrees);
    }
    static List<String> answerDsep(List<List<Integer>> groups) {
        List<Integer> x = groups.get(0), y = groups.get(1),
                      z = groups.size() == 3 ? groups.get(2) : List.of(),
                      reachable = reachable(x, z);
        Information information = information(x, y, z);
        return new ArrayList<>(
            List.of("result " + (Collections.disjoint(reachable, y) ? "separated" : "connected"),
                    "reachable " + sequence(reachable),
                    "data cmi " + real(information.cmi()) + " g2 " + real(information.g2()) +
                        " df " + information.degrees()));
    }
    static List<String> answerBlanket(int variable) {
        List<Integer> blanket = blankets.get(variable),
                      rest = difference(difference(variables, blanket), List.of(variable));
        boolean separated = Collections.disjoint(reachable(List.of(variable), blanket), rest);
        return new ArrayList<>(List.of("parents " + sequence(parents.get(variable)),
                                       "children " + sequence(children.get(variable)),
                                       "spouses " + sequence(spouses.get(variable)),
                                       "blanket " + sequence(blanket), "rest " + sequence(rest),
                                       "rest_separated " + yes(separated)));
    }
    static List<Integer> path(int start, int finish, int ignoreFrom, int ignoreTo) {
        int[] previous = new int[sizes.length];
        Arrays.fill(previous, -2);
        previous[start] = -1;
        ArrayDeque<Integer> pending = new ArrayDeque<>();
        pending.add(start);
        while (!pending.isEmpty()) {
            int v = pending.removeFirst();
            for (int child : children.get(v)) {
                if ((v == ignoreFrom && child == ignoreTo) || previous[child] != -2)
                    continue;
                previous[child] = v;
                if (child == finish) {
                    List<Integer> result = new ArrayList<>();
                    for (int node = child; node >= 0; node = previous[node])
                        result.add(node);
                    Collections.reverse(result);
                    return result;
                }
                pending.add(child);
            }
        }
        return null;
    }
    static double familyScore(int variable, Collection<Integer> parents) {
        List<Integer> ordered = sorted(parents);
        String key = variable + ":" + ordered;
        Double value = familyScores.get(key);
        if (value == null) {
            value = Learning.familyScore(variable, ordered, samples, sizes, settings.alpha());
            familyScores.put(key, value);
        }
        return value;
    }
    static List<String> answerEdge(String operation, int x, int y) {
        boolean exists = parents.get(y).contains(x);
        if (operation.equals("ADD") && exists)
            return new ArrayList<>(List.of("result exists"));
        if (!operation.equals("ADD") && !exists)
            return new ArrayList<>(List.of("result missing"));
        List<Integer> path = null, cycle = null;
        if (operation.equals("ADD")) {
            path = path(y, x, -1, -1);
            if (path != null) {
                cycle = new ArrayList<>();
                cycle.add(x);
                cycle.addAll(path);
            }
        } else if (operation.equals("REVERSE")) {
            path = path(x, y, x, y);
            if (path != null) {
                cycle = new ArrayList<>();
                cycle.add(y);
                cycle.addAll(path);
            }
        }
        if (cycle != null) {
            List<String> names = new ArrayList<>();
            for (int v : cycle)
                names.add(Main.names.get(v));
            return new ArrayList<>(List.of("result cycle " + String.join(" -> ", names)));
        }
        double beforeY = familyScore(y, parents.get(y));
        List<Integer> newParents = operation.equals("ADD") ? union(parents.get(y), List.of(x))
                                                           : difference(parents.get(y), List.of(x));
        double afterY = familyScore(y, newParents), change = afterY - beforeY;
        List<String> lines = new ArrayList<>();
        lines.add("result ok");
        lines.add("family " + names.get(y) + " before " + real(beforeY) + " after " + real(afterY));
        if (operation.equals("REVERSE")) {
            double beforeX = familyScore(x, parents.get(x)),
                   afterX = familyScore(x, union(parents.get(x), List.of(y)));
            change = (afterY - beforeY) + (afterX - beforeX);
            lines.add("family " + names.get(x) + " before " + real(beforeX) + " after " +
                      real(afterX));
        }
        lines.add("delta " + real(change) + " " + (change > 0 ? "improves" : "worsens"));
        return lines;
    }
    static List<List<String>> cptBlocks() {
        List<List<String>> blocks = new ArrayList<>();
        int count = samples.size();
        for (int v : variables) {
            String source = settings.sources().get(v);
            List<Integer> parents = Main.parents.get(v);
            double[][] cpt = cpts.get(v);
            int[][] observed = counts.get(v);
            List<String> lines = new ArrayList<>();
            lines.add("variable " + names.get(v) + " source " + source);
            lines.add("states " + String.join(" ", states.get(v)));
            lines.add("parents " + sequence(parents));
            for (int row = 0; row < observed.length; row++) {
                String line = "row " +
                              assignmentText(Factors.assignment(row, parents, sizes), parents) +
                              " counts";
                for (int value : observed[row])
                    line += " " + value;
                line += " probs";
                for (double value : cpt[row])
                    line += " " + real(value);
                lines.add(line);
            }
            double likelihood = likelihoods[v],
                   bic = likelihood - parameterCounts[v] * Math.log(count) / 2;
            lines.add("loglik " + real(likelihood) + " parameters " + parameterCounts[v] + " bic " +
                      real(bic));
            double[] marginal = posterior(List.of(v), List.of()).result().marginals()[v];
            String line = "marginal model";
            for (double probability : marginal)
                line += " " + real(probability);
            line += " data";
            for (int s = 0; s < sizes[v]; s++) {
                int frequency = 0;
                for (int[] row : observed)
                    frequency += row[s];
                line += " " + real(frequency / (double)count);
            }
            lines.add(line);
            if (source.equals("LEARNED")) {
                String difference = "-";
                if (network.expert().containsKey(v)) {
                    double maximum = 0;
                    for (int r = 0; r < observed.length; r++)
                        for (int s = 0; s < sizes[v]; s++)
                            maximum = Math.max(maximum, Math.abs(learned.get(v)[r][s] -
                                                                 network.expert().get(v)[r][s]));
                    difference = real(maximum);
                }
                lines.add("given_difference " + difference);
            }
            blocks.add(lines);
        }
        double likelihood = Learning.total(likelihoods);
        int parameters = 0;
        for (int n : parameterCounts)
            parameters += n;
        double bic = likelihood - parameters * Math.log(count) / 2;
        blocks.add(List.of("network samples " + count + " pseudocount " + real(settings.alpha()) +
                           " loglik " + real(likelihood) + " parameters " + parameters + " bic " +
                           real(bic)));
        return blocks;
    }
    static List<String> structureSummary() {
        Plans plans = plans(factors, variables);
        int widthMinfill = 0, widthGiven = 0;
        for (Elimination.Step step : plans.minfill().steps())
            widthMinfill = Math.max(widthMinfill, step.scope().size() - 1);
        for (Elimination.Step step : plans.given().steps())
            widthGiven = Math.max(widthGiven, step.scope().size() - 1);
        boolean[][] graph = Elimination.interaction(factors, sizes.length);
        int moral = 0, edges = 0;
        List<Integer> roots = new ArrayList<>(), leaves = new ArrayList<>();
        for (int v : variables) {
            edges += parents.get(v).size();
            if (parents.get(v).isEmpty())
                roots.add(v);
            if (children.get(v).isEmpty())
                leaves.add(v);
            for (int u = v + 1; u < sizes.length; u++)
                if (graph[v][u])
                    moral++;
        }
        List<String> lines = new ArrayList<>();
        lines.add("variables " + sizes.length + " edges " + edges);
        lines.add("topological_order " + sequence(topological));
        lines.add("roots " + sequence(roots));
        lines.add("leaves " + sequence(leaves));
        lines.add("moral_edges " + moral + " width minfill " + widthMinfill + " given " +
                  widthGiven);
        for (int v : variables)
            lines.add("variable " + names.get(v) + " states " + sizes[v] + " parents " +
                      parents.get(v).size() + " children " + children.get(v).size() + " depth " +
                      depths[v] + " ancestors " + ancestors.get(v).size() + " descendants " +
                      descendants.get(v).size() + " blanket " + blankets.get(v).size());
        return lines;
    }
    static List<String> heading(String heading, List<String> lines) {
        List<String> result = new ArrayList<>();
        result.add(heading);
        result.addAll(lines);
        return result;
    }
    static void writeBlocks(String name, List<List<String>> blocks) throws Exception {
        List<String> parts = new ArrayList<>();
        for (List<String> block : blocks)
            parts.add(String.join("\n", block));
        String text = String.join("\n\n", parts);
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), text + (text.isEmpty() ? "" : "\n"));
    }
    static void queries(List<String> queries, List<List<String>> cpts) throws Exception {
        List<List<String>> answers = new ArrayList<>(), elimination = new ArrayList<>(),
                           structure = new ArrayList<>();
        structure.add(structureSummary());
        List<String> csv = new ArrayList<>();
        csv.add("query,samples,variable,state,estimate,exact,abs_error");
        for (int number = 1; number <= queries.size(); number++) {
            String line = queries.get(number - 1);
            List<String> fields = new ArrayList<>(Arrays.asList(line.split(" ")));
            String kind = fields.removeFirst(), heading = "query " + number + " " + line;
            switch (kind) {
            case "QUERY" -> {
                Parts parts = parts(fields);
                Answer answer = answerQuery(parts.query(), parts.evidence());
                answers.add(heading(heading, answer.lines()));
                elimination.add(heading(heading, answer.elimination()));
            }
            case "MPE" -> {
                Answer answer = answerMpe(evidence(fields));
                answers.add(heading(heading, answer.lines()));
                elimination.add(heading(heading, answer.elimination()));
            }
            case "SAMPLE" -> {
                int separator = fields.indexOf("COUNTS");
                Parts parts = parts(fields.subList(0, separator));
                List<Integer> counts = new ArrayList<>();
                for (String value : fields.subList(separator + 1, fields.size()))
                    counts.add(Integer.parseInt(value));
                SampleAnswer answer = answerSample(number, parts.query(), parts.evidence(), counts);
                answers.add(heading(heading, answer.lines()));
                csv.addAll(answer.csv());
            }
            case "PREDICT" ->
                answers.add(heading(heading, answerPredict(names.indexOf(fields.getFirst()))));
            case "DSEP" -> {
                List<List<Integer>> groups = new ArrayList<>();
                groups.add(new ArrayList<>());
                for (String field : fields)
                    if (field.equals("|"))
                        groups.add(new ArrayList<>());
                    else
                        groups.getLast().add(names.indexOf(field));
                structure.add(heading(heading, answerDsep(groups)));
            }
            case "BLANKET" ->
                structure.add(heading(heading, answerBlanket(names.indexOf(fields.getFirst()))));
            case "EDGE" ->
                structure.add(
                    heading(heading, answerEdge(fields.get(0), names.indexOf(fields.get(1)),
                                                names.indexOf(fields.get(2)))));
            }
        }
        writeBlocks("cpts.txt", cpts);
        writeBlocks("structure.txt", structure);
        writeBlocks("answers.txt", answers);
        writeBlocks("elimination.txt", elimination);
        writeBlocks("sampling.csv", List.of(csv));
    }
    public static void main(String[] args) throws Exception {
        NetworkIo.Input input = NetworkIo.read();
        prepare(input);
        List<List<String>> cpts = cptBlocks();
        queries(input.queries(), cpts);
    }
}
