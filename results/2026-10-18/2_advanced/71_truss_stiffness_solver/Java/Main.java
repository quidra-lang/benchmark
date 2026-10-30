import java.nio.file.*;
import java.util.*;
public class Main {
    static ModelIo.Model model;
    static ModelIo.Settings settings;
    static List<ModelIo.Node> nodes;
    static List<ModelIo.Member> members;
    static List<Integer> order = new ArrayList<>();
    static List<Set<Integer>> neighbors = new ArrayList<>();
    static int[] numbers, free, restrained, ownerNode, ownerAxis, choices, governingCases, deckX;
    static int[][] nodeDofs;
    static int degrees;
    static double[] prescribed, limits, governing;
    static double[][] utilizations;
    static double weight;
    static List<Assembly.Geometry> geometry;
    static List<Assembly.Properties> properties;
    static LinkedHashMap<String, List<Integer>> groups = new LinkedHashMap<>();
    static Map<String, ModelIo.Combination> combinationDefinitions = new HashMap<>();
    static List<ResultOrder> resultOrder = new ArrayList<>();
    static List<SupportDirection> supportDirections = new ArrayList<>();
    static Map<Integer, Postprocess.Result> units = new HashMap<>();
    static StructuralSystem finalSystem;
    static Map<String, Postprocess.Result> results;
    static List<Postprocess.Result> combinations;
    record SupportDirection(int node, int axis, int degree) {}
    record ResultOrder(String kind, String name) {}
    record StructuralSystem(List<Assembly.Properties> properties, double[][] matrix,
                            double[][] freeMatrix, double[][] lower, int unstable, int removed) {}
    record Metrics(int bandwidth, int profile) {}
    record Change(String group, int current, int chosen, double utilization) {}
    record Range(double maximum, int highPosition, double minimum, int lowPosition) {}
    record Rating(int member, String kind, double value) {}
    record Point(int column, int row) {}
    static String real(double value, int digits) {
        String text = String.format(Locale.ROOT, "%." + digits + "f", value);
        return text.startsWith("-") && Double.parseDouble(text) == 0 ? text.substring(1) : text;
    }
    static String f(double value) { return real(value, 4); }
    static double rounded(double value) { return Double.parseDouble(f(value)); }
    static String yes(boolean value) { return value ? "yes" : "no"; }
    static double total(double[] values) {
        double sum = 0;
        for (double value : values)
            sum += value;
        return sum;
    }
    static int extreme(double[] values, boolean minimum) {
        int best = 0;
        for (int i = 1; i < values.length; i++)
            if (minimum ? rounded(values[i]) < rounded(values[best])
                        : rounded(values[i]) > rounded(values[best]))
                best = i;
        return best;
    }
    static int extreme(double[] values) { return extreme(values, false); }
    static int bestMember(List<Integer> members, double[] values) {
        int best = members.getFirst();
        for (int m : members)
            if (rounded(values[m]) > rounded(values[best]))
                best = m;
        return best;
    }
    static int[] integers(List<Integer> values) {
        return values.stream().mapToInt(Integer::intValue).toArray();
    }
    static void prepare(ModelIo.Model input) {
        model = input;
        settings = model.settings();
        nodes = model.nodes();
        members = model.members();
        for (int i = 0; i < nodes.size(); i++)
            neighbors.add(new HashSet<>());
        for (ModelIo.Member member : members) {
            neighbors.get(member.start()).add(member.end());
            neighbors.get(member.end()).add(member.start());
        }
        Comparator<Integer> degreeOrder =
            Comparator.comparingInt((Integer n) -> neighbors.get(n).size())
                .thenComparingInt(n -> nodes.get(n).identifier());
        List<Integer> all = new ArrayList<>();
        for (int i = 0; i < nodes.size(); i++)
            all.add(i);
        int first = Collections.min(all, degreeOrder);
        List<Integer> queue = new ArrayList<>();
        queue.add(first);
        boolean[] visited = new boolean[nodes.size()];
        visited[first] = true;
        for (int i = 0; i < queue.size(); i++) {
            List<Integer> following = new ArrayList<>();
            for (int adjacent : neighbors.get(queue.get(i)))
                if (!visited[adjacent])
                    following.add(adjacent);
            following.sort(degreeOrder);
            for (int n : following) {
                queue.add(n);
                visited[n] = true;
            }
        }
        Collections.reverse(queue);
        order = queue;
        numbers = new int[nodes.size()];
        nodeDofs = new int[nodes.size()][2];
        degrees = 2 * nodes.size();
        ownerNode = new int[degrees];
        ownerAxis = new int[degrees];
        for (int i = 0; i < order.size(); i++) {
            int node = order.get(i);
            numbers[node] = i;
            for (int axis = 0; axis < 2; axis++) {
                int d = 2 * i + axis;
                nodeDofs[node][axis] = d;
                ownerNode[d] = node;
                ownerAxis[d] = axis;
            }
        }
        prescribed = new double[degrees];
        List<Integer> fixed = new ArrayList<>();
        for (ModelIo.Support support : model.supports())
            for (int axis = 0; axis < 2; axis++)
                if (support.fixed()[axis] == 1) {
                    int d = nodeDofs[support.node()][axis];
                    prescribed[d] = support.prescribed()[axis];
                    fixed.add(d);
                    supportDirections.add(new SupportDirection(support.node(), axis, d));
                }
        Collections.sort(fixed);
        restrained = integers(fixed);
        List<Integer> unrestrained = new ArrayList<>();
        for (int d = 0; d < degrees; d++)
            if (!fixed.contains(d))
                unrestrained.add(d);
        free = integers(unrestrained);
        geometry = Assembly.geometry(nodes, members, nodeDofs);
        for (int m = 0; m < members.size(); m++)
            groups.computeIfAbsent(members.get(m).group(), key -> new ArrayList<>()).add(m);
        for (ModelIo.LoadCase loadCase : model.cases())
            resultOrder.add(new ResultOrder("case", loadCase.name()));
        for (ModelIo.Combination combination : model.combinations()) {
            resultOrder.add(new ResultOrder("combination", combination.name()));
            combinationDefinitions.put(combination.name(), combination);
        }
        deckX = new int[settings.deck.size()];
        for (int i = 0; i < deckX.length; i++)
            deckX[i] = nodes.get(settings.deck.get(i)).x();
    }
    static Metrics metrics(int[] numbering) {
        int bandwidth = 0, profile = 0;
        for (ModelIo.Member member : members)
            bandwidth =
                Math.max(bandwidth, Math.abs(numbering[member.start()] - numbering[member.end()]));
        for (int n = 0; n < nodes.size(); n++) {
            int minimum = numbering[n];
            for (int adjacent : neighbors.get(n))
                minimum = Math.min(minimum, numbering[adjacent]);
            profile += numbering[n] - minimum;
        }
        return new Metrics(bandwidth, profile);
    }
    static StructuralSystem system(int[] choices, int removed) {
        List<Assembly.Properties> properties = Assembly.properties(model, choices, geometry);
        double[][] matrix = Assembly.assemble(geometry, properties, degrees, removed),
                   freeMatrix = new double[free.length][free.length];
        for (int i = 0; i < free.length; i++)
            for (int j = 0; j < free.length; j++)
                freeMatrix[i][j] = matrix[free[i]][free[j]];
        Solver.Factorization factor = Solver.cholesky(freeMatrix, free);
        return new StructuralSystem(properties, matrix, freeMatrix, factor.lower(),
                                    factor.unstable(), removed);
    }
    static double[] displacement(StructuralSystem system, double[] force, boolean settlement) {
        double[] displacement = new double[degrees];
        for (int d : restrained)
            displacement[d] = settlement ? prescribed[d] : 0;
        double[] right = new double[free.length];
        for (int i = 0; i < free.length; i++) {
            double value = force[free[i]];
            for (int d : restrained)
                value -= system.matrix()[free[i]][d] * displacement[d];
            right[i] = value;
        }
        double[] solution = Solver.solve(system.lower(), right);
        for (int i = 0; i < free.length; i++)
            displacement[free[i]] = solution[i];
        return displacement;
    }
    static Postprocess.Result caseResult(StructuralSystem system, ModelIo.LoadCase loadCase) {
        Assembly.Loading loading = Assembly.loads(loadCase, geometry, system.properties(), nodeDofs,
                                                  degrees, system.removed());
        double[] displacement = displacement(system, loading.total(), loading.settlement()),
                 forces = Postprocess.forces(geometry, system.properties(), displacement,
                                             loading.temperature(), system.removed()),
                 reactions = Postprocess.reactions(system.matrix(), displacement, loading.total(),
                                                   restrained);
        return new Postprocess.Result(loadCase.name(), displacement, forces, reactions,
                                      loading.external());
    }
    static Map<String, Postprocess.Result> analyze(StructuralSystem system,
                                                   ModelIo.Combination only) {
        List<ModelIo.Combination> combinations =
            only == null ? model.combinations() : List.of(only);
        Set<String> needed = new HashSet<>();
        for (ModelIo.Combination combination : combinations)
            for (ModelIo.Term term : combination.terms())
                needed.add(term.name());
        Map<String, Postprocess.Result> results = new LinkedHashMap<>();
        for (ModelIo.LoadCase loadCase : model.cases())
            if (only == null || needed.contains(loadCase.name()))
                results.put(loadCase.name(), caseResult(system, loadCase));
        for (ModelIo.Combination combination : combinations)
            results.put(combination.name(), Postprocess.superpose(combination, results));
        return results;
    }
    static Postprocess.Result unit(int node) {
        Postprocess.Result result = units.get(node);
        if (result == null) {
            double[] force = new double[degrees];
            force[nodeDofs[node][1]] = -1000;
            double[] displacement = displacement(finalSystem, force, false),
                     forces = Postprocess.forces(geometry, properties, displacement,
                                                 new double[members.size()], -1),
                     reactions = Postprocess.reactions(finalSystem.matrix(), displacement, force,
                                                       restrained);
            result = new Postprocess.Result("unit", displacement, forces, reactions, force);
            units.put(node, result);
        }
        return result;
    }
    static List<String> designSections() {
        choices = new int[members.size()];
        for (int m = 0; m < members.size(); m++)
            choices[m] = members.get(m).section();
        List<String> history = new ArrayList<>();
        boolean converged = false;
        int round = 0;
        for (round = 1; round <= 10; round++) {
            StructuralSystem system = system(choices, -1);
            Map<String, Postprocess.Result> results = analyze(system, null);
            List<Postprocess.Result> combinations = new ArrayList<>();
            for (ModelIo.Combination combination : model.combinations())
                combinations.add(results.get(combination.name()));
            double[] limits = new double[members.size()];
            double[][] utilizations = new double[members.size()][combinations.size()];
            int largestMember = 0, largestCase = 0;
            double weight = 0;
            for (int m = 0; m < members.size(); m++) {
                Assembly.Properties p = system.properties().get(m);
                Assembly.Geometry g = geometry.get(m);
                limits[m] = Design.limit(m, combinations, settings);
                weight += Assembly.weight(p, g);
                for (int c = 0; c < combinations.size(); c++) {
                    utilizations[m][c] = Design.utilization(combinations.get(c).forces()[m], p, g);
                    if (rounded(utilizations[m][c]) >
                        rounded(utilizations[largestMember][largestCase])) {
                        largestMember = m;
                        largestCase = c;
                    }
                }
            }
            List<Change> changes = new ArrayList<>();
            for (var group : groups.entrySet()) {
                List<Integer> groupMembers = group.getValue();
                int chosen = Design.select(groupMembers, model.sections(), system.properties(),
                                           geometry, combinations, limits),
                    current = choices[groupMembers.getFirst()];
                if (chosen != current) {
                    double largest = utilizations[groupMembers.getFirst()][0];
                    for (int m : groupMembers)
                        for (double utilization : utilizations[m])
                            if (rounded(utilization) > rounded(largest))
                                largest = utilization;
                    changes.add(new Change(group.getKey(), current, chosen, largest));
                }
            }
            history.add("round " + round + " weight " + f(weight / 1000) + " max_utilization " +
                        f(utilizations[largestMember][largestCase]) + " at " +
                        members.get(largestMember).identifier() + " " +
                        combinations.get(largestCase).name() + " changes " + changes.size());
            for (Change change : changes)
                history.add("change " + change.group() + " " +
                            model.sections().get(change.current()).name() + " " +
                            model.sections().get(change.chosen()).name() + " utilization " +
                            f(change.utilization()));
            converged = changes.isEmpty();
            if (converged || round == 10) {
                finalSystem = system;
                Main.properties = system.properties();
                Main.results = results;
                Main.combinations = combinations;
                Main.limits = limits;
                Main.utilizations = utilizations;
                Main.weight = weight;
                break;
            }
            for (Change change : changes)
                for (int m : groups.get(change.group()))
                    choices[m] = change.chosen();
        }
        governingCases = new int[members.size()];
        governing = new double[members.size()];
        for (int m = 0; m < members.size(); m++) {
            governingCases[m] = extreme(utilizations[m]);
            governing[m] = utilizations[m][governingCases[m]];
        }
        history.add("result " + (converged ? "converged" : "not_converged") + " rounds " + round);
        return history;
    }
    static List<String> designReport(List<String> history) {
        List<String> lines = new ArrayList<>(history);
        for (var group : groups.entrySet()) {
            List<Integer> groupMembers = group.getValue();
            int member = bestMember(groupMembers, governing);
            String section = model.sections().get(choices[groupMembers.getFirst()]).name();
            lines.add("group " + group.getKey() + " section " + section + " members " +
                      groupMembers.size() + " utilization " + f(governing[member]) + " at " +
                      members.get(member).identifier());
        }
        for (int m = 0; m < members.size(); m++) {
            ModelIo.Member member = members.get(m);
            double slender = Design.slenderness(properties.get(m), geometry.get(m));
            lines.add("member " + member.identifier() + " group " + member.group() + " section " +
                      model.sections().get(choices[m]).name() + " utilization " + f(governing[m]) +
                      " governing " + combinations.get(governingCases[m]).name() + " slenderness " +
                      f(slender) + " limit " + f(limits[m]) + " " +
                      (governing[m] <= 1 && slender <= limits[m] ? "ok" : "over"));
        }
        List<Integer> ranking = new ArrayList<>();
        for (int m = 0; m < members.size(); m++)
            ranking.add(m);
        ranking.sort(Comparator.comparingDouble((Integer m) -> - rounded(governing[m]))
                         .thenComparingInt(m -> m));
        for (int i = 0; i < Math.min(5, ranking.size()); i++) {
            int m = ranking.get(i);
            lines.add("rank " + (i + 1) + " member " + members.get(m).identifier() +
                      " utilization " + f(governing[m]));
        }
        for (int m = 0; m < members.size(); m++) {
            double[] values = new double[combinations.size()];
            for (int c = 0; c < values.length; c++)
                values[c] = combinations.get(c).forces()[m] / 1000;
            int high = extreme(values), low = extreme(values, true);
            lines.add("envelope " + members.get(m).identifier() + " max " + f(values[high]) + " " +
                      combinations.get(high).name() + " min " + f(values[low]) + " " +
                      combinations.get(low).name());
        }
        for (int s = 0; s < model.sections().size(); s++) {
            int count = 0;
            double length = 0;
            for (int m = 0; m < members.size(); m++)
                if (choices[m] == s) {
                    count++;
                    length += geometry.get(m).length();
                }
            if (count > 0)
                lines.add("section " + model.sections().get(s).name() + " members " + count +
                          " length " + f(length));
        }
        lines.add("weight " + f(weight / 1000));
        return lines;
    }
    static double[] magnitudes(Postprocess.Result result) {
        double[] values = new double[nodes.size()];
        for (int n = 0; n < nodes.size(); n++) {
            double x = result.displacement()[nodeDofs[n][0]],
                   y = result.displacement()[nodeDofs[n][1]];
            values[n] = Math.sqrt(x * x + y * y);
        }
        return values;
    }
    static String resultSummary(String kind, Postprocess.Result result) {
        double[] magnitudes = magnitudes(result);
        int node = extreme(magnitudes);
        double energy = 0;
        for (int m = 0; m < members.size(); m++) {
            double force = result.forces()[m];
            Assembly.Geometry g = geometry.get(m);
            Assembly.Properties p = properties.get(m);
            energy += force * force * g.length() / (2 * p.young() * p.area());
        }
        energy /= 1000;
        double[] reactions = new double[2], loads = new double[2];
        for (int axis = 0; axis < 2; axis++) {
            for (int n = 0; n < nodes.size(); n++)
                reactions[axis] += result.reactions()[nodeDofs[n][axis]];
            reactions[axis] /= 1000;
            for (int n = 0; n < nodes.size(); n++)
                loads[axis] += result.external()[nodeDofs[n][axis]];
            loads[axis] /= 1000;
        }
        double scale = 1;
        for (double value : result.external())
            scale = Math.max(scale, Math.abs(value));
        for (double value : result.reactions())
            scale = Math.max(scale, Math.abs(value));
        String equilibrium =
            Postprocess.equilibrium(result, geometry) <= 0.000001 * scale ? "ok" : "failed";
        return kind + " " + result.name() + " equilibrium " + equilibrium + " max_displacement " +
            f(magnitudes[node]) + " at " + nodes.get(node).identifier() + " energy " + f(energy) +
            " reactions " + f(reactions[0]) + " " + f(reactions[1]) + " loads " + f(loads[0]) +
            " " + f(loads[1]);
    }
    static List<String> analysisReport() {
        int[] original = new int[nodes.size()];
        for (int i = 0; i < original.length; i++)
            original[i] = i;
        Metrics before = metrics(original), after = metrics(numbers);
        List<String> lines = new ArrayList<>();
        lines.add("model nodes " + nodes.size() + " members " + members.size() + " supports " +
                  model.supports().size() + " free_dofs " + free.length + " restrained_dofs " +
                  restrained.length + " indeterminacy " +
                  (members.size() + restrained.length - 2 * nodes.size()));
        String renumbering = "renumbering";
        for (int node : order)
            renumbering += " " + nodes.get(node).identifier();
        lines.add(renumbering);
        lines.add("bandwidth before " + before.bandwidth() + " after " + after.bandwidth());
        lines.add("profile before " + before.profile() + " after " + after.profile());
        for (int m = 0; m < members.size(); m++) {
            ModelIo.Member member = members.get(m);
            Assembly.Geometry g = geometry.get(m);
            lines.add("member " + member.identifier() + " nodes " +
                      nodes.get(member.start()).identifier() + " " +
                      nodes.get(member.end()).identifier() + " length " + f(g.length()) + " cos " +
                      real(g.cosine(), 6) + " sin " + real(g.sine(), 6));
        }
        for (ResultOrder entry : resultOrder)
            lines.add(resultSummary(entry.kind(), results.get(entry.name())));
        for (SupportDirection support : supportDirections) {
            double[] values = new double[combinations.size()];
            boolean uplift = false;
            for (int c = 0; c < values.length; c++) {
                values[c] = combinations.get(c).reactions()[support.degree()] / 1000;
                if (values[c] < 0)
                    uplift = true;
            }
            int high = extreme(values), low = extreme(values, true);
            String line = "reaction_envelope " + nodes.get(support.node()).identifier() + " "
                          + "xy".charAt(support.axis()) + " max " + f(values[high]) + " " +
                          combinations.get(high).name() + " min " + f(values[low]) + " " +
                          combinations.get(low).name();
            if (support.axis() == 1)
                line += " uplift " + yes(uplift);
            lines.add(line);
        }
        List<double[]> displacements = new ArrayList<>();
        for (Postprocess.Result result : combinations)
            displacements.add(magnitudes(result));
        for (int n = 0; n < nodes.size(); n++) {
            double[] values = new double[combinations.size()];
            for (int c = 0; c < values.length; c++)
                values[c] = displacements.get(c)[n];
            int high = extreme(values);
            lines.add("displacement_envelope " + nodes.get(n).identifier() + " max " +
                      f(values[high]) + " " + combinations.get(high).name());
        }
        lines.addAll(deflectionReport());
        lines.addAll(removalReport());
        return lines;
    }
    static List<String> deflectionReport() {
        Postprocess.Result result = results.get(settings.deflection);
        Set<Integer> fixed = new HashSet<>();
        for (SupportDirection support : supportDirections)
            if (support.axis() == 1)
                fixed.add(support.node());
        List<Integer> anchors = new ArrayList<>();
        for (int i = 0; i < settings.deck.size(); i++)
            if (fixed.contains(settings.deck.get(i)))
                anchors.add(i);
        List<String> lines = new ArrayList<>();
        for (int span = 0; span + 1 < anchors.size(); span++) {
            int first = anchors.get(span), last = anchors.get(span + 1),
                left = settings.deck.get(first), right = settings.deck.get(last), xa = deckX[first],
                xb = deckX[last];
            double va = result.displacement()[nodeDofs[left][1]],
                   vb = result.displacement()[nodeDofs[right][1]];
            double[] deflections = new double[last - first - 1];
            for (int i = first + 1; i < last; i++)
                deflections[i - first - 1] =
                    Math.abs(result.displacement()[nodeDofs[settings.deck.get(i)][1]] -
                             (va + (vb - va) * (deckX[i] - xa) / (xb - xa)));
            int chosen = extreme(deflections), node = settings.deck.get(first + 1 + chosen);
            double maximum = deflections[chosen], limit =
                                                      (xb - xa) / (double)settings.deflectionRatio;
            lines.add("deflection " + settings.deflection + " span " +
                      nodes.get(left).identifier() + " " + nodes.get(right).identifier() + " max " +
                      f(maximum) + " at " + nodes.get(node).identifier() + " limit " + f(limit) +
                      " " + (maximum <= limit ? "ok" : "exceeded"));
            Postprocess.Result unit = unit(node);
            double virtual = 0;
            for (int m = 0; m < members.size(); m++) {
                Assembly.Properties p = properties.get(m);
                virtual += result.forces()[m] * (unit.forces()[m] / 1000) *
                           geometry.get(m).length() / (p.young() * p.area());
            }
            double stiffness = -result.displacement()[nodeDofs[node][1]];
            String verified =
                Math.abs(virtual - stiffness) <= 0.000001 * Math.max(1, Math.abs(stiffness))
                    ? "ok"
                    : "failed";
            lines.add("virtual_work " + settings.deflection + " node " +
                      nodes.get(node).identifier() + " stiffness " + f(stiffness) + " virtual " +
                      f(virtual) + " " + verified);
        }
        return lines;
    }
    static List<String> removalReport() {
        ModelIo.Combination combination = combinationDefinitions.get(settings.removal);
        List<String> lines = new ArrayList<>();
        for (int removed = 0; removed < members.size(); removed++) {
            StructuralSystem system = system(choices, removed);
            if (system.unstable() >= 0) {
                int degree = system.unstable();
                lines.add("removal " + members.get(removed).identifier() + " unstable at " +
                          nodes.get(ownerNode[degree]).identifier() + " "
                          + "xy".charAt(ownerAxis[degree]));
                continue;
            }
            Postprocess.Result result = analyze(system, combination).get(combination.name());
            List<Integer> remaining = new ArrayList<>();
            List<Double> values = new ArrayList<>();
            for (int m = 0; m < members.size(); m++)
                if (m != removed) {
                    remaining.add(m);
                    values.add(Design.utilization(result.forces()[m], system.properties().get(m),
                                                  geometry.get(m)));
                }
            double[] utilizations = new double[values.size()];
            for (int i = 0; i < values.size(); i++)
                utilizations[i] = values.get(i);
            int largest = extreme(utilizations);
            double[] magnitudes = magnitudes(result);
            int node = extreme(magnitudes);
            lines.add("removal " + members.get(removed).identifier() + " stable max_utilization " +
                      f(utilizations[largest]) + " at " +
                      members.get(remaining.get(largest)).identifier() + " max_displacement " +
                      f(magnitudes[node]) + " at " + nodes.get(node).identifier());
        }
        return lines;
    }
    static double ordinate(double[] ordinates, int position) {
        if (position < deckX[0] || position > deckX[deckX.length - 1])
            return 0;
        if (position == deckX[deckX.length - 1])
            return ordinates[ordinates.length - 1];
        int index = 0;
        while (deckX[index + 1] <= position)
            index++;
        int first = deckX[index], last = deckX[index + 1];
        return ordinates[index] +
            (ordinates[index + 1] - ordinates[index]) * (position - first) / (last - first);
    }
    static Range vehicleRange(double[] ordinates, List<Integer> positions) {
        double[] effects = new double[positions.size()];
        for (int i = 0; i < positions.size(); i++)
            for (ModelIo.Axle axle : settings.axles)
                effects[i] += axle.load() * ordinate(ordinates, positions.get(i) - axle.offset());
        int high = extreme(effects), low = extreme(effects, true);
        return new Range(effects[high], positions.get(high), effects[low], positions.get(low));
    }
    static List<String> influenceReport() {
        double[][] memberOrdinates = new double[members.size()][settings.deck.size()],
                   reactionOrdinates = new double[degrees][settings.deck.size()];
        for (int k = 0; k < settings.deck.size(); k++) {
            Postprocess.Result unit = unit(settings.deck.get(k));
            for (int m = 0; m < members.size(); m++)
                memberOrdinates[m][k] = unit.forces()[m] / 1000;
            for (SupportDirection support : supportDirections)
                reactionOrdinates[support.degree()][k] = unit.reactions()[support.degree()] / 1000;
        }
        List<String> lines = new ArrayList<>();
        for (int m : settings.influence) {
            double[] ordinates = memberOrdinates[m];
            lines.add("influence " + members.get(m).identifier());
            for (int k = 0; k < ordinates.length; k++)
                lines.add("node " + nodes.get(settings.deck.get(k)).identifier() + " " +
                          f(ordinates[k]));
            int high = extreme(ordinates), low = extreme(ordinates, true);
            double positive = 0, negative = 0;
            for (double value : ordinates)
                if (value > 0)
                    positive += value;
                else if (value < 0)
                    negative += value;
            lines.add("max " + f(ordinates[high]) + " at " +
                      nodes.get(settings.deck.get(high)).identifier() + " min " +
                      f(ordinates[low]) + " at " + nodes.get(settings.deck.get(low)).identifier() +
                      " positive " + f(positive) + " negative " + f(negative));
            List<Double> crossings = new ArrayList<>();
            for (int k = 0; k + 1 < ordinates.length; k++) {
                double a = ordinates[k], b = ordinates[k + 1];
                if ((a > 0 && b < 0) || (a < 0 && b > 0))
                    crossings.add(deckX[k] + (deckX[k + 1] - deckX[k]) * a / (a - b));
            }
            String line = "crossings " + crossings.size();
            for (double position : crossings)
                line += " " + real(position, 1);
            lines.add(line);
        }
        List<Integer> positions = new ArrayList<>();
        for (int p = deckX[0]; p <= deckX[deckX.length - 1] + settings.axles.getLast().offset();
             p += settings.vehicleStep)
            positions.add(p);
        lines.add("vehicle axles " + settings.axles.size() + " positions " + positions.size());
        List<Range> memberRanges = new ArrayList<>();
        for (int m = 0; m < members.size(); m++) {
            Range range = vehicleRange(memberOrdinates[m], positions);
            memberRanges.add(range);
            lines.add("vehicle_member " + members.get(m).identifier() + " max " +
                      f(range.maximum()) + " at " + range.highPosition() + " min " +
                      f(range.minimum()) + " at " + range.lowPosition());
        }
        for (SupportDirection support : supportDirections) {
            Range range = vehicleRange(reactionOrdinates[support.degree()], positions);
            lines.add("vehicle_reaction " + nodes.get(support.node()).identifier() + " "
                      + "xy".charAt(support.axis()) + " max " + f(range.maximum()) + " at " +
                      range.highPosition() + " min " + f(range.minimum()) + " at " +
                      range.lowPosition());
        }
        Postprocess.Result dead = results.get(settings.rating);
        List<Rating> ratings = new ArrayList<>();
        for (int m = 0; m < members.size(); m++) {
            Range range = memberRanges.get(m);
            Assembly.Properties p = properties.get(m);
            Assembly.Geometry g = geometry.get(m);
            double deadForce = dead.forces()[m] / 1000,
                   tensionCapacity = p.area() * p.yieldStress() / 1000,
                   compressionCapacity =
                       Math.min(p.area() * p.yieldStress(), Design.buckling(p, g)) / 1000;
            String tension = "none", compression = "none";
            if (rounded(range.maximum()) > 0) {
                double rating = (tensionCapacity - settings.deadFactor * deadForce) /
                                (settings.vehicleFactor * range.maximum());
                tension = f(rating);
                ratings.add(new Rating(m, "tension", rating));
            }
            if (rounded(range.minimum()) < 0) {
                double rating = (compressionCapacity + settings.deadFactor * deadForce) /
                                (settings.vehicleFactor * (-range.minimum()));
                compression = f(rating);
                ratings.add(new Rating(m, "compression", rating));
            }
            lines.add("rating " + members.get(m).identifier() + " tension " + tension +
                      " compression " + compression);
        }
        Rating minimum = ratings.getFirst();
        for (Rating rating : ratings)
            if (rounded(rating.value()) < rounded(minimum.value()))
                minimum = rating;
        lines.add("rating_min " + f(minimum.value()) + " at " +
                  members.get(minimum.member()).identifier() + " " + minimum.kind());
        return lines;
    }
    static List<String> vibrationReport() {
        Postprocess.Result result = results.get(settings.vibration);
        double[] masses = new double[nodes.size()], freeMasses = new double[free.length];
        for (int n = 0; n < nodes.size(); n++)
            masses[n] = -result.external()[nodeDofs[n][1]] / 9.81;
        for (int i = 0; i < free.length; i++)
            freeMasses[i] = masses[ownerNode[free[i]]];
        int size = free.length;
        List<double[]> modes = new ArrayList<>();
        List<String> lines = new ArrayList<>();
        lines.add("vibration " + settings.vibration + " mass " + f(total(masses)) + " iterations " +
                  settings.iterations);
        for (int mode = 1; mode <= settings.modeCount; mode++) {
            double[] vector = new double[size];
            Arrays.fill(vector, 1);
            for (int iteration = 0; iteration < settings.iterations; iteration++) {
                for (double[] previous : modes) {
                    double beta = 0;
                    for (int i = 0; i < size; i++)
                        beta += previous[i] * freeMasses[i] * vector[i];
                    for (int i = 0; i < size; i++)
                        vector[i] = vector[i] - beta * previous[i];
                }
                double[] right = new double[size];
                for (int i = 0; i < size; i++)
                    right[i] = freeMasses[i] * vector[i];
                double[] solution = Solver.solve(finalSystem.lower(), right);
                double norm = 0;
                for (int i = 0; i < size; i++)
                    norm += freeMasses[i] * solution[i] * solution[i];
                norm = Math.sqrt(norm);
                for (int i = 0; i < size; i++)
                    vector[i] = solution[i] / norm;
            }
            modes.add(vector);
            double[] stiffnessProduct = new double[size];
            for (int i = 0; i < size; i++)
                for (int j = 0; j < size; j++)
                    stiffnessProduct[i] += finalSystem.freeMatrix()[i][j] * vector[j];
            double numerator = 0, denominator = 0;
            for (int i = 0; i < size; i++)
                numerator += vector[i] * stiffnessProduct[i];
            for (int i = 0; i < size; i++)
                denominator += freeMasses[i] * vector[i] * vector[i];
            double eigenvalue = numerator / denominator,
                   frequency = Math.sqrt(1000 * eigenvalue) / (2 * Design.PI);
            lines.add("mode " + mode + " frequency " + f(frequency) + " period " +
                      f(1 / frequency));
            int peak = 0;
            for (int i = 1; i < size; i++)
                if (Math.abs(vector[i]) > Math.abs(vector[peak]))
                    peak = i;
            double[] normalized = new double[degrees];
            for (int i = 0; i < size; i++)
                normalized[free[i]] = vector[i] / vector[peak];
            for (int n = 0; n < nodes.size(); n++)
                lines.add("node " + nodes.get(n).identifier() + " " +
                          f(normalized[nodeDofs[n][0]]) + " " + f(normalized[nodeDofs[n][1]]));
        }
        return lines;
    }
    static final class Canvas {
        int x0, x1, y0, y1, horizontal, vertical, width, height;
        char[][] grid;
        Canvas(int horizontal, int vertical) {
            this.horizontal = horizontal;
            this.vertical = vertical;
            x0 = x1 = nodes.getFirst().x();
            y0 = y1 = nodes.getFirst().y();
            for (ModelIo.Node node : nodes) {
                x0 = Math.min(x0, node.x());
                x1 = Math.max(x1, node.x());
                y0 = Math.min(y0, node.y());
                y1 = Math.max(y1, node.y());
            }
            width = (int)Math.floor((x1 - x0) / (double)horizontal + 0.5) + 5;
            height = (int)Math.floor((y1 - y0) / (double)vertical + 0.5) + 5;
            grid = new char[height][width];
            for (char[] row : grid)
                Arrays.fill(row, ' ');
        }
        Point position(double x, double y) {
            return new Point((int)Math.floor((x - x0) / horizontal + 0.5) + 2,
                             (int)Math.floor((y1 - y) / vertical + 0.5) + 2);
        }
        void put(Point point, char character) {
            if (point.column() >= 0 && point.column() < width && point.row() >= 0 &&
                point.row() < height)
                grid[point.row()][point.column()] = character;
        }
        void line(Point first, Point last, char character) {
            int column = first.column(), row = first.row(), dc = Math.abs(last.column() - column),
                dr = -Math.abs(last.row() - row), sc = column < last.column() ? 1 : -1,
                sr = row < last.row() ? 1 : -1, error = dc + dr;
            while (true) {
                put(new Point(column, row), character);
                if (column == last.column() && row == last.row())
                    break;
                int twice = 2 * error;
                if (twice >= dr) {
                    error += dr;
                    column += sc;
                }
                if (twice <= dc) {
                    error += dc;
                    row += sr;
                }
            }
        }
        List<String> framed() {
            String border = "+"
                            + "-".repeat(width) + "+";
            List<String> lines = new ArrayList<>();
            lines.add(border);
            for (char[] row : grid)
                lines.add("|" + new String(row) + "|");
            lines.add(border);
            return lines;
        }
    }
    static List<String> drawingReport() {
        List<String> lines = new ArrayList<>();
        for (ModelIo.Drawing drawing : settings.drawings) {
            Postprocess.Result result = results.get(drawing.name());
            Canvas canvas = new Canvas(drawing.horizontal(), drawing.vertical());
            List<Point> original = new ArrayList<>(), deformed = new ArrayList<>();
            for (int n = 0; n < nodes.size(); n++) {
                ModelIo.Node node = nodes.get(n);
                original.add(canvas.position(node.x(), node.y()));
                deformed.add(canvas.position(
                    node.x() + drawing.magnification() * result.displacement()[nodeDofs[n][0]],
                    node.y() + drawing.magnification() * result.displacement()[nodeDofs[n][1]]));
            }
            for (ModelIo.Member member : members)
                canvas.line(original.get(member.start()), original.get(member.end()), '.');
            for (Point point : original)
                canvas.put(point, '+');
            for (ModelIo.Member member : members)
                canvas.line(deformed.get(member.start()), deformed.get(member.end()), '*');
            for (Point point : deformed)
                canvas.put(point, 'o');
            lines.add("drawing " + drawing.name() + " magnification " + drawing.magnification() +
                      " columns " + canvas.width + " rows " + canvas.height);
            lines.addAll(canvas.framed());
        }
        Canvas canvas = new Canvas(settings.mapHorizontal, settings.mapVertical);
        List<Point> positions = new ArrayList<>();
        for (ModelIo.Node node : nodes)
            positions.add(canvas.position(node.x(), node.y()));
        for (int m = 0; m < members.size(); m++) {
            ModelIo.Member member = members.get(m);
            char character =
                governing[m] >= 1 ? '#' : (char)('0' + (int)Math.floor(10 * governing[m]));
            canvas.line(positions.get(member.start()), positions.get(member.end()), character);
        }
        for (Point point : positions)
            canvas.put(point, 'o');
        lines.add("utilization_map columns " + canvas.width + " rows " + canvas.height);
        lines.addAll(canvas.framed());
        return lines;
    }
    static void csvReports() throws Exception {
        List<String> displacementLines = new ArrayList<>(), forceLines = new ArrayList<>(),
                     reactionLines = new ArrayList<>();
        displacementLines.add("case,node,dx,dy");
        forceLines.add("case,member,force,stress,utilization");
        reactionLines.add("case,node,rx,ry");
        for (ResultOrder entry : resultOrder) {
            String name = entry.name();
            Postprocess.Result result = results.get(name);
            for (int n = 0; n < nodes.size(); n++)
                displacementLines.add(name + "," + nodes.get(n).identifier() + "," +
                                      f(result.displacement()[nodeDofs[n][0]]) + "," +
                                      f(result.displacement()[nodeDofs[n][1]]));
            for (int m = 0; m < members.size(); m++) {
                double force = result.forces()[m];
                Assembly.Properties p = properties.get(m);
                forceLines.add(name + "," + members.get(m).identifier() + "," + f(force / 1000) +
                               "," + f(force / p.area()) + "," +
                               f(Design.utilization(force, p, geometry.get(m))));
            }
            for (ModelIo.Support support : model.supports())
                reactionLines.add(name + "," + nodes.get(support.node()).identifier() + "," +
                                  f(result.reactions()[nodeDofs[support.node()][0]] / 1000) + "," +
                                  f(result.reactions()[nodeDofs[support.node()][1]] / 1000));
        }
        write("displacements.csv", displacementLines);
        write("member_forces.csv", forceLines);
        write("reactions.csv", reactionLines);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
    public static void main(String[] args) throws Exception {
        prepare(ModelIo.read());
        List<String> history = designSections();
        csvReports();
        write("analysis.txt", analysisReport());
        write("design.txt", designReport(history));
        write("influence.txt", influenceReport());
        write("drawing.txt", drawingReport());
        write("vibration.txt", vibrationReport());
    }
}
