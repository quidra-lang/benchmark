using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
public static class Program {
    public static ModelIo.Model model;
    public static ModelIo.Settings settings;
    public static List<ModelIo.Node> nodes;
    public static List<ModelIo.Member> members;
    public static List<int> order = new();
    public static List<HashSet<int>> neighbors = new();
    public static int[] numbers, free, restrained, ownerNode, ownerAxis, choices, governingCases,
        deckX;
    public static int[][] nodeDofs;
    public static int degrees;
    public static double[] prescribed, limits, governing;
    public static double[][] utilizations;
    public static double weight;
    public static List<Assembly.Geometry> geometry;
    public static List<Assembly.Properties> properties;
    public static Dictionary<string, List<int>> groups = new();
    public static List<string> groupOrder = new();
    public static Dictionary<string, ModelIo.Combination> combinationDefinitions = new();
    public static List<ResultOrder> resultOrder = new();
    public static List<SupportDirection> supportDirections = new();
    public static Dictionary<int, Postprocess.Result> units = new();
    public static StructuralSystem finalSystem;
    public static Dictionary<string, Postprocess.Result> results;
    public static List<Postprocess.Result> combinations;
    public record SupportDirection(int node, int axis, int degree) {}
    public record ResultOrder(string kind, string name) {}
    public record StructuralSystem(List<Assembly.Properties> properties, double[][] matrix,
                                   double[][] freeMatrix, double[][] lower, int unstable,
                                   int removed) {}
    public record Metrics(int bandwidth, int profile) {}
    public record Change(string group, int current, int chosen, double utilization) {}
    public record Range(double maximum, int highPosition, double minimum, int lowPosition) {}
    public record Rating(int member, string kind, double value) {}
    public record Point(int column, int row) {}
    public static string Real(double value, int digits) {
        string text = value.ToString("F" + digits, CultureInfo.InvariantCulture);
        return text.StartsWith("-") && double.Parse(text, CultureInfo.InvariantCulture) == 0
                   ? text.Substring(1)
                   : text;
    }
    public static string F(double value) { return Real(value, 4); }
    public static double Rounded(double value) {
        return double.Parse(F(value), CultureInfo.InvariantCulture);
    }
    public static string Yes(bool value) { return value ? "yes" : "no"; }
    public static double Total(double[] values) {
        double sum = 0;
        foreach (double value in values)
            sum += value;
        return sum;
    }
    public static int Extreme(double[] values, bool minimum) {
        int best = 0;
        for (int i = 1; i < values.Length; i++)
            if (minimum ? Rounded(values[i]) < Rounded(values[best])
                        : Rounded(values[i]) > Rounded(values[best]))
                best = i;
        return best;
    }
    public static int Extreme(double[] values) { return Extreme(values, false); }
    public static int BestMember(List<int> members, double[] values) {
        int best = members[0];
        foreach (int m in members)
            if (Rounded(values[m]) > Rounded(values[best]))
                best = m;
        return best;
    }
    public static int[] Integers(List<int> values) { return values.ToArray(); }
    public static void Prepare(ModelIo.Model input) {
        model = input;
        settings = model.settings;
        nodes = model.nodes;
        members = model.members;
        for (int i = 0; i < nodes.Count; i++)
            neighbors.Add(new());
        foreach (ModelIo.Member member in members) {
            neighbors[member.start].Add(member.end);
            neighbors[member.end].Add(member.start);
        }
        Comparison<int> degreeOrder = (a, b) => {
            int c = neighbors[a].Count.CompareTo(neighbors[b].Count);
            return c != 0 ? c : nodes[a].identifier.CompareTo(nodes[b].identifier);
        };
        List<int> all = new();
        for (int i = 0; i < nodes.Count; i++)
            all.Add(i);
        all.Sort(degreeOrder);
        int first = all[0];
        List<int> queue = new();
        queue.Add(first);
        bool[] visited = new bool[nodes.Count];
        visited[first] = true;
        for (int i = 0; i < queue.Count; i++) {
            List<int> following = new();
            foreach (int adjacent in neighbors[queue[i]])
                if (!visited[adjacent])
                    following.Add(adjacent);
            following.Sort(degreeOrder);
            foreach (int n in following) {
                queue.Add(n);
                visited[n] = true;
            }
        }
        queue.Reverse();
        order = queue;
        numbers = new int[nodes.Count];
        nodeDofs = Enumerable.Range(0, nodes.Count)
                       .Select(
                           _ => new int[2])
                       .ToArray();
        degrees = 2 * nodes.Count;
        ownerNode = new int[degrees];
        ownerAxis = new int[degrees];
        for (int i = 0; i < order.Count; i++) {
            int node = order[i];
            numbers[node] = i;
            for (int axis = 0; axis < 2; axis++) {
                int d = 2 * i + axis;
                nodeDofs[node][axis] = d;
                ownerNode[d] = node;
                ownerAxis[d] = axis;
            }
        }
        prescribed = new double[degrees];
        List<int> fixity = new();
        foreach (ModelIo.Support support in model.supports)
            for (int axis = 0; axis < 2; axis++)
                if (support.fixity[axis] == 1) {
                    int d = nodeDofs[support.node][axis];
                    prescribed[d] = support.prescribed[axis];
                    fixity.Add(d);
                    supportDirections.Add(new SupportDirection(support.node, axis, d));
                }
        fixity.Sort();
        restrained = Integers(fixity);
        List<int> unrestrained = new();
        for (int d = 0; d < degrees; d++)
            if (!fixity.Contains(d))
                unrestrained.Add(d);
        free = Integers(unrestrained);
        geometry = Assembly.GeometryList(nodes, members, nodeDofs);
        for (int m = 0; m < members.Count; m++) {
            string group = members[m].group;
            if (!groups.ContainsKey(group))
                groupOrder.Add(group);
            groups.GetOrAdd(group, key => new()).Add(m);
        }
        foreach (ModelIo.LoadCase loadCase in model.cases)
            resultOrder.Add(new ResultOrder("case", loadCase.name));
        foreach (ModelIo.Combination combination in model.combinations) {
            resultOrder.Add(new ResultOrder("combination", combination.name));
            combinationDefinitions[combination.name] = combination;
        }
        deckX = new int[settings.deck.Count];
        for (int i = 0; i < deckX.Length; i++)
            deckX[i] = nodes[settings.deck[i]].x;
    }
    public static Metrics NumberingMetrics(int[] numbering) {
        int bandwidth = 0, profile = 0;
        foreach (ModelIo.Member member in members)
            bandwidth =
                Math.Max(bandwidth, Math.Abs(numbering[member.start] - numbering[member.end]));
        for (int n = 0; n < nodes.Count; n++) {
            int minimum = numbering[n];
            foreach (int adjacent in neighbors[n])
                minimum = Math.Min(minimum, numbering[adjacent]);
            profile += numbering[n] - minimum;
        }
        return new Metrics(bandwidth, profile);
    }
    public static StructuralSystem BuildSystem(int[] choices, int removed) {
        List<Assembly.Properties> properties = Assembly.PropertyList(model, choices, geometry);
        double[][] matrix = Assembly.Assemble(geometry, properties, degrees, removed),
                   freeMatrix = Enumerable.Range(0, free.Length)
                                    .Select(
                                        _ => new double[free.Length])
                                    .ToArray();
        for (int i = 0; i < free.Length; i++)
            for (int j = 0; j < free.Length; j++)
                freeMatrix[i][j] = matrix[free[i]][free[j]];
        Solver.Factorization factor = Solver.Cholesky(freeMatrix, free);
        return new StructuralSystem(properties, matrix, freeMatrix, factor.lower, factor.unstable,
                                    removed);
    }
    public static double[] Displacement(StructuralSystem system, double[] force, bool settlement) {
        double[] displacement = new double[degrees];
        foreach (int d in restrained)
            displacement[d] = settlement ? prescribed[d] : 0;
        double[] right = new double[free.Length];
        for (int i = 0; i < free.Length; i++) {
            double value = force[free[i]];
            foreach (int d in restrained)
                value -= system.matrix[free[i]][d] * displacement[d];
            right[i] = value;
        }
        double[] solution = Solver.Solve(system.lower, right);
        for (int i = 0; i < free.Length; i++)
            displacement[free[i]] = solution[i];
        return displacement;
    }
    public static Postprocess.Result CaseResult(StructuralSystem system,
                                                ModelIo.LoadCase loadCase) {
        Assembly.Loading loading = Assembly.Loads(loadCase, geometry, system.properties, nodeDofs,
                                                  degrees, system.removed);
        double[] displacement = Displacement(system, loading.total, loading.settlement),
                 forces = Postprocess.Forces(geometry, system.properties, displacement,
                                             loading.temperature, system.removed),
                 reactions =
                     Postprocess.Reactions(system.matrix, displacement, loading.total, restrained);
        return new Postprocess.Result(loadCase.name, displacement, forces, reactions,
                                      loading.external);
    }
    public static Dictionary<string, Postprocess.Result> Analyze(StructuralSystem system,
                                                                 ModelIo.Combination only) {
        List<ModelIo.Combination> combinations =
            only == null ? model.combinations : new List<ModelIo.Combination> { only };
        HashSet<string> needed = new();
        foreach (ModelIo.Combination combination in combinations)
            foreach (ModelIo.Term term in combination.terms)
                needed.Add(term.name);
        Dictionary<string, Postprocess.Result> results = new();
        foreach (ModelIo.LoadCase loadCase in model.cases)
            if (only == null || needed.Contains(loadCase.name))
                results[loadCase.name] = CaseResult(system, loadCase);
        foreach (ModelIo.Combination combination in combinations)
            results[combination.name] = Postprocess.Superpose(combination, results);
        return results;
    }
    public static Postprocess.Result Unit(int node) {
        Postprocess.Result result = units.GetValueOrDefault(node);
        if (result == null) {
            double[] force = new double[degrees];
            force[nodeDofs[node][1]] = -1000;
            double[] displacement = Displacement(finalSystem, force, false),
                     forces = Postprocess.Forces(geometry, properties, displacement,
                                                 new double[members.Count], -1),
                     reactions =
                         Postprocess.Reactions(finalSystem.matrix, displacement, force, restrained);
            result = new Postprocess.Result("unit", displacement, forces, reactions, force);
            units[node] = result;
        }
        return result;
    }
    public static List<string> DesignSections() {
        choices = new int[members.Count];
        for (int m = 0; m < members.Count; m++)
            choices[m] = members[m].section;
        List<string> history = new();
        bool converged = false;
        int round = 0;
        for (round = 1; round <= 10; round++) {
            StructuralSystem system = BuildSystem(choices, -1);
            Dictionary<string, Postprocess.Result> results = Analyze(system, null);
            List<Postprocess.Result> combinations = new();
            foreach (ModelIo.Combination combination in model.combinations)
                combinations.Add(results[combination.name]);
            double[] limits = new double[members.Count];
            double[][] utilizations = Enumerable.Range(0, members.Count)
                                          .Select(
                                              _ => new double[combinations.Count])
                                          .ToArray();
            int largestMember = 0, largestCase = 0;
            double weight = 0;
            for (int m = 0; m < members.Count; m++) {
                Assembly.Properties p = system.properties[m];
                Assembly.Geometry g = geometry[m];
                limits[m] = Design.Limit(m, combinations, settings);
                weight += Assembly.Weight(p, g);
                for (int c = 0; c < combinations.Count; c++) {
                    utilizations[m][c] = Design.Utilization(combinations[c].forces[m], p, g);
                    if (Rounded(utilizations[m][c]) >
                        Rounded(utilizations[largestMember][largestCase])) {
                        largestMember = m;
                        largestCase = c;
                    }
                }
            }
            List<Change> changes = new();
            foreach (string groupName in groupOrder) {
                KeyValuePair<string, List<int>> group = new(groupName, groups[groupName]);
                List<int> groupMembers = group.Value;
                int chosen = Design.Select(groupMembers, model.sections, system.properties,
                                           geometry, combinations, limits),
                    current = choices[groupMembers[0]];
                if (chosen != current) {
                    double largest = utilizations[groupMembers[0]][0];
                    foreach (int m in groupMembers)
                        foreach (double utilization in utilizations[m])
                            if (Rounded(utilization) > Rounded(largest))
                                largest = utilization;
                    changes.Add(new Change(group.Key, current, chosen, largest));
                }
            }
            history.Add("round " + round + " weight " + F(weight / 1000) + " max_utilization " +
                        F(utilizations[largestMember][largestCase]) + " at " +
                        members[largestMember].identifier + " " + combinations[largestCase].name +
                        " changes " + changes.Count);
            foreach (Change change in changes)
                history.Add("change " + change.group + " " + model.sections[change.current].name +
                            " " + model.sections[change.chosen].name + " utilization " +
                            F(change.utilization));
            converged = changes.Count == 0;
            if (converged || round == 10) {
                finalSystem = system;
                Program.properties = system.properties;
                Program.results = results;
                Program.combinations = combinations;
                Program.limits = limits;
                Program.utilizations = utilizations;
                Program.weight = weight;
                break;
            }
            foreach (Change change in changes)
                foreach (int m in groups[change.group])
                    choices[m] = change.chosen;
        }
        governingCases = new int[members.Count];
        governing = new double[members.Count];
        for (int m = 0; m < members.Count; m++) {
            governingCases[m] = Extreme(utilizations[m]);
            governing[m] = utilizations[m][governingCases[m]];
        }
        history.Add("result " + (converged ? "converged" : "not_converged") + " rounds " + round);
        return history;
    }
    public static List<string> DesignReport(List<string> history) {
        List<string> lines = new(history);
        foreach (string groupName in groupOrder) {
            KeyValuePair<string, List<int>> group = new(groupName, groups[groupName]);
            List<int> groupMembers = group.Value;
            int member = BestMember(groupMembers, governing);
            string section = model.sections[choices[groupMembers[0]]].name;
            lines.Add("group " + group.Key + " section " + section + " members " +
                      groupMembers.Count + " utilization " + F(governing[member]) + " at " +
                      members[member].identifier);
        }
        for (int m = 0; m < members.Count; m++) {
            ModelIo.Member member = members[m];
            double slender = Design.Slenderness(properties[m], geometry[m]);
            lines.Add("member " + member.identifier + " group " + member.group + " section " +
                      model.sections[choices[m]].name + " utilization " + F(governing[m]) +
                      " governing " + combinations[governingCases[m]].name + " slenderness " +
                      F(slender) + " limit " + F(limits[m]) + " " +
                      (governing[m] <= 1 && slender <= limits[m] ? "ok" : "over"));
        }
        List<int> ranking = new();
        for (int m = 0; m < members.Count; m++)
            ranking.Add(m);
        ranking.Sort((a, b) => {
            int c = Rounded(governing[b]).CompareTo(Rounded(governing[a]));
            return c != 0 ? c : a.CompareTo(b);
        });
        for (int i = 0; i < Math.Min(5, ranking.Count); i++) {
            int m = ranking[i];
            lines.Add("rank " + (i + 1) + " member " + members[m].identifier + " utilization " +
                      F(governing[m]));
        }
        for (int m = 0; m < members.Count; m++) {
            double[] values = new double[combinations.Count];
            for (int c = 0; c < values.Length; c++)
                values[c] = combinations[c].forces[m] / 1000;
            int high = Extreme(values), low = Extreme(values, true);
            lines.Add("envelope " + members[m].identifier + " max " + F(values[high]) + " " +
                      combinations[high].name + " min " + F(values[low]) + " " +
                      combinations[low].name);
        }
        for (int s = 0; s < model.sections.Count; s++) {
            int count = 0;
            double length = 0;
            for (int m = 0; m < members.Count; m++)
                if (choices[m] == s) {
                    count++;
                    length += geometry[m].length;
                }
            if (count > 0)
                lines.Add("section " + model.sections[s].name + " members " + count + " length " +
                          F(length));
        }
        lines.Add("weight " + F(weight / 1000));
        return lines;
    }
    public static double[] Magnitudes(Postprocess.Result result) {
        double[] values = new double[nodes.Count];
        for (int n = 0; n < nodes.Count; n++) {
            double x = result.displacement[nodeDofs[n][0]], y = result.displacement[nodeDofs[n][1]];
            values[n] = Math.Sqrt(x * x + y * y);
        }
        return values;
    }
    public static string ResultSummary(string kind, Postprocess.Result result) {
        double[] magnitudes = Magnitudes(result);
        int node = Extreme(magnitudes);
        double energy = 0;
        for (int m = 0; m < members.Count; m++) {
            double force = result.forces[m];
            Assembly.Geometry g = geometry[m];
            Assembly.Properties p = properties[m];
            energy += force * force * g.length / (2 * p.young * p.area);
        }
        energy /= 1000;
        double[] reactions = new double[2], loads = new double[2];
        for (int axis = 0; axis < 2; axis++) {
            for (int n = 0; n < nodes.Count; n++)
                reactions[axis] += result.reactions[nodeDofs[n][axis]];
            reactions[axis] /= 1000;
            for (int n = 0; n < nodes.Count; n++)
                loads[axis] += result.external[nodeDofs[n][axis]];
            loads[axis] /= 1000;
        }
        double scale = 1;
        foreach (double value in result.external)
            scale = Math.Max(scale, Math.Abs(value));
        foreach (double value in result.reactions)
            scale = Math.Max(scale, Math.Abs(value));
        string equilibrium =
            Postprocess.Equilibrium(result, geometry) <= 0.000001 * scale ? "ok" : "failed";
        return kind + " " + result.name + " equilibrium " + equilibrium + " max_displacement " +
               F(magnitudes[node]) + " at " + nodes[node].identifier + " energy " + F(energy) +
               " reactions " + F(reactions[0]) + " " + F(reactions[1]) + " loads " + F(loads[0]) +
               " " + F(loads[1]);
    }
    public static List<string> AnalysisReport() {
        int[] original = new int[nodes.Count];
        for (int i = 0; i < original.Length; i++)
            original[i] = i;
        Metrics before = NumberingMetrics(original), after = NumberingMetrics(numbers);
        List<string> lines = new();
        lines.Add("model nodes " + nodes.Count + " members " + members.Count + " supports " +
                  model.supports.Count + " free_dofs " + free.Length + " restrained_dofs " +
                  restrained.Length + " indeterminacy " +
                  (members.Count + restrained.Length - 2 * nodes.Count));
        string renumbering = "renumbering";
        foreach (int node in order)
            renumbering += " " + nodes[node].identifier;
        lines.Add(renumbering);
        lines.Add("bandwidth before " + before.bandwidth + " after " + after.bandwidth);
        lines.Add("profile before " + before.profile + " after " + after.profile);
        for (int m = 0; m < members.Count; m++) {
            ModelIo.Member member = members[m];
            Assembly.Geometry g = geometry[m];
            lines.Add("member " + member.identifier + " nodes " + nodes[member.start].identifier +
                      " " + nodes[member.end].identifier + " length " + F(g.length) + " cos " +
                      Real(g.cosine, 6) + " sin " + Real(g.sine, 6));
        }
        foreach (ResultOrder entry in resultOrder)
            lines.Add(ResultSummary(entry.kind, results[entry.name]));
        foreach (SupportDirection support in supportDirections) {
            double[] values = new double[combinations.Count];
            bool uplift = false;
            for (int c = 0; c < values.Length; c++) {
                values[c] = combinations[c].reactions[support.degree] / 1000;
                if (values[c] < 0)
                    uplift = true;
            }
            int high = Extreme(values), low = Extreme(values, true);
            string line = "reaction_envelope " + nodes[support.node].identifier + " " +
                          "xy"[support.axis] + " max " + F(values[high]) + " " +
                          combinations[high].name + " min " + F(values[low]) + " " +
                          combinations[low].name;
            if (support.axis == 1)
                line += " uplift " + Yes(uplift);
            lines.Add(line);
        }
        List<double[]> displacements = new();
        foreach (Postprocess.Result result in combinations)
            displacements.Add(Magnitudes(result));
        for (int n = 0; n < nodes.Count; n++) {
            double[] values = new double[combinations.Count];
            for (int c = 0; c < values.Length; c++)
                values[c] = displacements[c][n];
            int high = Extreme(values);
            lines.Add("displacement_envelope " + nodes[n].identifier + " max " + F(values[high]) +
                      " " + combinations[high].name);
        }
        lines.AddRange(DeflectionReport());
        lines.AddRange(RemovalReport());
        return lines;
    }
    public static List<string> DeflectionReport() {
        Postprocess.Result result = results[settings.deflection];
        HashSet<int> fixity = new();
        foreach (SupportDirection support in supportDirections)
            if (support.axis == 1)
                fixity.Add(support.node);
        List<int> anchors = new();
        for (int i = 0; i < settings.deck.Count; i++)
            if (fixity.Contains(settings.deck[i]))
                anchors.Add(i);
        List<string> lines = new();
        for (int span = 0; span + 1 < anchors.Count; span++) {
            int first = anchors[span], last = anchors[span + 1], left = settings.deck[first],
                right = settings.deck[last], xa = deckX[first], xb = deckX[last];
            double va = result.displacement[nodeDofs[left][1]],
                   vb = result.displacement[nodeDofs[right][1]];
            double[] deflections = new double[last - first - 1];
            for (int i = first + 1; i < last; i++)
                deflections[i - first - 1] =
                    Math.Abs(result.displacement[nodeDofs[settings.deck[i]][1]] -
                             (va + (vb - va) * (deckX[i] - xa) / (xb - xa)));
            int chosen = Extreme(deflections), node = settings.deck[first + 1 + chosen];
            double maximum = deflections[chosen],
                   limit = (xb - xa) / (double)settings.deflectionRatio;
            lines.Add("deflection " + settings.deflection + " span " + nodes[left].identifier +
                      " " + nodes[right].identifier + " max " + F(maximum) + " at " +
                      nodes[node].identifier + " limit " + F(limit) + " " +
                      (maximum <= limit ? "ok" : "exceeded"));
            Postprocess.Result unit = Unit(node);
            double virtualWork = 0;
            for (int m = 0; m < members.Count; m++) {
                Assembly.Properties p = properties[m];
                virtualWork += result.forces[m] * (unit.forces[m] / 1000) * geometry[m].length /
                               (p.young * p.area);
            }
            double stiffness = -result.displacement[nodeDofs[node][1]];
            string verified =
                Math.Abs(virtualWork - stiffness) <= 0.000001 * Math.Max(1, Math.Abs(stiffness))
                    ? "ok"
                    : "failed";
            lines.Add("virtual_work " + settings.deflection + " node " + nodes[node].identifier +
                      " stiffness " + F(stiffness) + " virtual " + F(virtualWork) + " " + verified);
        }
        return lines;
    }
    public static List<string> RemovalReport() {
        ModelIo.Combination combination = combinationDefinitions[settings.removal];
        List<string> lines = new();
        for (int removed = 0; removed < members.Count; removed++) {
            StructuralSystem system = BuildSystem(choices, removed);
            if (system.unstable >= 0) {
                int degree = system.unstable;
                lines.Add("removal " + members[removed].identifier + " unstable at " +
                          nodes[ownerNode[degree]].identifier + " " + "xy"[ownerAxis[degree]]);
                continue;
            }
            Postprocess.Result result = Analyze(system, combination)[combination.name];
            List<int> remaining = new();
            List<double> values = new();
            for (int m = 0; m < members.Count; m++)
                if (m != removed) {
                    remaining.Add(m);
                    values.Add(
                        Design.Utilization(result.forces[m], system.properties[m], geometry[m]));
                }
            double[] utilizations = new double[values.Count];
            for (int i = 0; i < values.Count; i++)
                utilizations[i] = values[i];
            int largest = Extreme(utilizations);
            double[] magnitudes = Magnitudes(result);
            int node = Extreme(magnitudes);
            lines.Add("removal " + members[removed].identifier + " stable max_utilization " +
                      F(utilizations[largest]) + " at " + members[remaining[largest]].identifier +
                      " max_displacement " + F(magnitudes[node]) + " at " + nodes[node].identifier);
        }
        return lines;
    }
    public static double Ordinate(double[] ordinates, int position) {
        if (position < deckX[0] || position > deckX[deckX.Length - 1])
            return 0;
        if (position == deckX[deckX.Length - 1])
            return ordinates[ordinates.Length - 1];
        int index = 0;
        while (deckX[index + 1] <= position)
            index++;
        int first = deckX[index], last = deckX[index + 1];
        return ordinates[index] +
               (ordinates[index + 1] - ordinates[index]) * (position - first) / (last - first);
    }
    public static Range VehicleRange(double[] ordinates, List<int> positions) {
        double[] effects = new double[positions.Count];
        for (int i = 0; i < positions.Count; i++)
            foreach (ModelIo.Axle axle in settings.axles)
                effects[i] += axle.load * Ordinate(ordinates, positions[i] - axle.offset);
        int high = Extreme(effects), low = Extreme(effects, true);
        return new Range(effects[high], positions[high], effects[low], positions[low]);
    }
    public static List<string> InfluenceReport() {
        double[][] memberOrdinates = Enumerable.Range(0, members.Count)
                                         .Select(
                                             _ => new double[settings.deck.Count])
                                         .ToArray(),
                   reactionOrdinates = Enumerable.Range(0, degrees)
                                           .Select(
                                               _ => new double[settings.deck.Count])
                                           .ToArray();
        for (int k = 0; k < settings.deck.Count; k++) {
            Postprocess.Result unit = Unit(settings.deck[k]);
            for (int m = 0; m < members.Count; m++)
                memberOrdinates[m][k] = unit.forces[m] / 1000;
            foreach (SupportDirection support in supportDirections)
                reactionOrdinates[support.degree][k] = unit.reactions[support.degree] / 1000;
        }
        List<string> lines = new();
        foreach (int m in settings.influence) {
            double[] ordinates = memberOrdinates[m];
            lines.Add("influence " + members[m].identifier);
            for (int k = 0; k < ordinates.Length; k++)
                lines.Add("node " + nodes[settings.deck[k]].identifier + " " + F(ordinates[k]));
            int high = Extreme(ordinates), low = Extreme(ordinates, true);
            double positive = 0, negative = 0;
            foreach (double value in ordinates)
                if (value > 0)
                    positive += value;
                else if (value < 0)
                    negative += value;
            lines.Add("max " + F(ordinates[high]) + " at " + nodes[settings.deck[high]].identifier +
                      " min " + F(ordinates[low]) + " at " + nodes[settings.deck[low]].identifier +
                      " positive " + F(positive) + " negative " + F(negative));
            List<double> crossings = new();
            for (int k = 0; k + 1 < ordinates.Length; k++) {
                double a = ordinates[k], b = ordinates[k + 1];
                if ((a > 0 && b < 0) || (a < 0 && b > 0))
                    crossings.Add(deckX[k] + (deckX[k + 1] - deckX[k]) * a / (a - b));
            }
            string line = "crossings " + crossings.Count;
            foreach (double position in crossings)
                line += " " + Real(position, 1);
            lines.Add(line);
        }
        List<int> positions = new();
        for (int p = deckX[0]; p <= deckX[deckX.Length - 1] + settings.axles[^1].offset;
             p += settings.vehicleStep)
            positions.Add(p);
        lines.Add("vehicle axles " + settings.axles.Count + " positions " + positions.Count);
        List<Range> memberRanges = new();
        for (int m = 0; m < members.Count; m++) {
            Range range = VehicleRange(memberOrdinates[m], positions);
            memberRanges.Add(range);
            lines.Add("vehicle_member " + members[m].identifier + " max " + F(range.maximum) +
                      " at " + range.highPosition + " min " + F(range.minimum) + " at " +
                      range.lowPosition);
        }
        foreach (SupportDirection support in supportDirections) {
            Range range = VehicleRange(reactionOrdinates[support.degree], positions);
            lines.Add("vehicle_reaction " + nodes[support.node].identifier + " " +
                      "xy"[support.axis] + " max " + F(range.maximum) + " at " +
                      range.highPosition + " min " + F(range.minimum) + " at " + range.lowPosition);
        }
        Postprocess.Result dead = results[settings.rating];
        List<Rating> ratings = new();
        for (int m = 0; m < members.Count; m++) {
            Range range = memberRanges[m];
            Assembly.Properties p = properties[m];
            Assembly.Geometry g = geometry[m];
            double deadForce = dead.forces[m] / 1000,
                   tensionCapacity = p.area * p.yieldStress / 1000,
                   compressionCapacity =
                       Math.Min(p.area * p.yieldStress, Design.Buckling(p, g)) / 1000;
            string tension = "none", compression = "none";
            if (Rounded(range.maximum) > 0) {
                double rating = (tensionCapacity - settings.deadFactor * deadForce) /
                                (settings.vehicleFactor * range.maximum);
                tension = F(rating);
                ratings.Add(new Rating(m, "tension", rating));
            }
            if (Rounded(range.minimum) < 0) {
                double rating = (compressionCapacity + settings.deadFactor * deadForce) /
                                (settings.vehicleFactor * (-range.minimum));
                compression = F(rating);
                ratings.Add(new Rating(m, "compression", rating));
            }
            lines.Add("rating " + members[m].identifier + " tension " + tension + " compression " +
                      compression);
        }
        Rating minimum = ratings[0];
        foreach (Rating rating in ratings)
            if (Rounded(rating.value) < Rounded(minimum.value))
                minimum = rating;
        lines.Add("rating_min " + F(minimum.value) + " at " + members[minimum.member].identifier +
                  " " + minimum.kind);
        return lines;
    }
    public static List<string> VibrationReport() {
        Postprocess.Result result = results[settings.vibration];
        double[] masses = new double[nodes.Count], freeMasses = new double[free.Length];
        for (int n = 0; n < nodes.Count; n++)
            masses[n] = -result.external[nodeDofs[n][1]] / 9.81;
        for (int i = 0; i < free.Length; i++)
            freeMasses[i] = masses[ownerNode[free[i]]];
        int size = free.Length;
        List<double[]> modes = new();
        List<string> lines = new();
        lines.Add("vibration " + settings.vibration + " mass " + F(Total(masses)) + " iterations " +
                  settings.iterations);
        for (int mode = 1; mode <= settings.modeCount; mode++) {
            double[] vector = new double[size];
            Array.Fill(vector, 1);
            for (int iteration = 0; iteration < settings.iterations; iteration++) {
                foreach (double[] previous in modes) {
                    double beta = 0;
                    for (int i = 0; i < size; i++)
                        beta += previous[i] * freeMasses[i] * vector[i];
                    for (int i = 0; i < size; i++)
                        vector[i] = vector[i] - beta * previous[i];
                }
                double[] right = new double[size];
                for (int i = 0; i < size; i++)
                    right[i] = freeMasses[i] * vector[i];
                double[] solution = Solver.Solve(finalSystem.lower, right);
                double norm = 0;
                for (int i = 0; i < size; i++)
                    norm += freeMasses[i] * solution[i] * solution[i];
                norm = Math.Sqrt(norm);
                for (int i = 0; i < size; i++)
                    vector[i] = solution[i] / norm;
            }
            modes.Add(vector);
            double[] stiffnessProduct = new double[size];
            for (int i = 0; i < size; i++)
                for (int j = 0; j < size; j++)
                    stiffnessProduct[i] += finalSystem.freeMatrix[i][j] * vector[j];
            double numerator = 0, denominator = 0;
            for (int i = 0; i < size; i++)
                numerator += vector[i] * stiffnessProduct[i];
            for (int i = 0; i < size; i++)
                denominator += freeMasses[i] * vector[i] * vector[i];
            double eigenvalue = numerator / denominator,
                   frequency = Math.Sqrt(1000 * eigenvalue) / (2 * Design.PI);
            lines.Add("mode " + mode + " frequency " + F(frequency) + " period " +
                      F(1 / frequency));
            int peak = 0;
            for (int i = 1; i < size; i++)
                if (Math.Abs(vector[i]) > Math.Abs(vector[peak]))
                    peak = i;
            double[] normalized = new double[degrees];
            for (int i = 0; i < size; i++)
                normalized[free[i]] = vector[i] / vector[peak];
            for (int n = 0; n < nodes.Count; n++)
                lines.Add("node " + nodes[n].identifier + " " + F(normalized[nodeDofs[n][0]]) +
                          " " + F(normalized[nodeDofs[n][1]]));
        }
        return lines;
    }
    public sealed class Canvas {
        public int x0, x1, y0, y1, horizontal, vertical, width, height;
        public char[][] grid;
        public Canvas(int horizontal, int vertical) {
            this.horizontal = horizontal;
            this.vertical = vertical;
            x0 = x1 = nodes[0].x;
            y0 = y1 = nodes[0].y;
            foreach (ModelIo.Node node in nodes) {
                x0 = Math.Min(x0, node.x);
                x1 = Math.Max(x1, node.x);
                y0 = Math.Min(y0, node.y);
                y1 = Math.Max(y1, node.y);
            }
            width = (int)Math.Floor((x1 - x0) / (double)horizontal + 0.5) + 5;
            height = (int)Math.Floor((y1 - y0) / (double)vertical + 0.5) + 5;
            grid = Enumerable.Range(0, height)
                       .Select(
                           _ => new char[width])
                       .ToArray();
            foreach (char[] row in grid)
                Array.Fill(row, ' ');
        }
        public Point Position(double x, double y) {
            return new Point((int)Math.Floor((x - x0) / horizontal + 0.5) + 2,
                             (int)Math.Floor((y1 - y) / vertical + 0.5) + 2);
        }
        public void Put(Point point, char character) {
            if (point.column >= 0 && point.column < width && point.row >= 0 && point.row < height)
                grid[point.row][point.column] = character;
        }
        public void Line(Point first, Point last, char character) {
            int column = first.column, row = first.row, dc = Math.Abs(last.column - column),
                dr = -Math.Abs(last.row - row), sc = column < last.column ? 1 : -1,
                sr = row < last.row ? 1 : -1, error = dc + dr;
            while (true) {
                Put(new Point(column, row), character);
                if (column == last.column && row == last.row)
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
        public List<string> Framed() {
            string border = "+" + new string('-', width) + "+";
            List<string> lines = new();
            lines.Add(border);
            foreach (char[] row in grid)
                lines.Add("|" + new string(row) + "|");
            lines.Add(border);
            return lines;
        }
    }
    public static List<string> DrawingReport() {
        List<string> lines = new();
        foreach (ModelIo.Drawing drawing in settings.drawings) {
            Postprocess.Result result = results[drawing.name];
            Canvas canvas = new Canvas(drawing.horizontal, drawing.vertical);
            List<Point> original = new(), deformed = new();
            for (int n = 0; n < nodes.Count; n++) {
                ModelIo.Node node = nodes[n];
                original.Add(canvas.Position(node.x, node.y));
                deformed.Add(canvas.Position(
                    node.x + drawing.magnification * result.displacement[nodeDofs[n][0]],
                    node.y + drawing.magnification * result.displacement[nodeDofs[n][1]]));
            }
            foreach (ModelIo.Member member in members)
                canvas.Line(original[member.start], original[member.end], '.');
            foreach (Point point in original)
                canvas.Put(point, '+');
            foreach (ModelIo.Member member in members)
                canvas.Line(deformed[member.start], deformed[member.end], '*');
            foreach (Point point in deformed)
                canvas.Put(point, 'o');
            lines.Add("drawing " + drawing.name + " magnification " + drawing.magnification +
                      " columns " + canvas.width + " rows " + canvas.height);
            lines.AddRange(canvas.Framed());
        }
        Canvas utilizationCanvas = new Canvas(settings.mapHorizontal, settings.mapVertical);
        List<Point> positions = new();
        foreach (ModelIo.Node node in nodes)
            positions.Add(utilizationCanvas.Position(node.x, node.y));
        for (int m = 0; m < members.Count; m++) {
            ModelIo.Member member = members[m];
            char character =
                governing[m] >= 1 ? '#' : (char)('0' + (int)Math.Floor(10 * governing[m]));
            utilizationCanvas.Line(positions[member.start], positions[member.end], character);
        }
        foreach (Point point in positions)
            utilizationCanvas.Put(point, 'o');
        lines.Add("utilization_map columns " + utilizationCanvas.width + " rows " +
                  utilizationCanvas.height);
        lines.AddRange(utilizationCanvas.Framed());
        return lines;
    }
    public static void CsvReports() {
        List<string> displacementLines = new(), forceLines = new(), reactionLines = new();
        displacementLines.Add("case,node,dx,dy");
        forceLines.Add("case,member,force,stress,utilization");
        reactionLines.Add("case,node,rx,ry");
        foreach (ResultOrder entry in resultOrder) {
            string name = entry.name;
            Postprocess.Result result = results[name];
            for (int n = 0; n < nodes.Count; n++)
                displacementLines.Add(name + "," + nodes[n].identifier + "," +
                                      F(result.displacement[nodeDofs[n][0]]) + "," +
                                      F(result.displacement[nodeDofs[n][1]]));
            for (int m = 0; m < members.Count; m++) {
                double force = result.forces[m];
                Assembly.Properties p = properties[m];
                forceLines.Add(name + "," + members[m].identifier + "," + F(force / 1000) + "," +
                               F(force / p.area) + "," +
                               F(Design.Utilization(force, p, geometry[m])));
            }
            foreach (ModelIo.Support support in model.supports)
                reactionLines.Add(name + "," + nodes[support.node].identifier + "," +
                                  F(result.reactions[nodeDofs[support.node][0]] / 1000) + "," +
                                  F(result.reactions[nodeDofs[support.node][1]] / 1000));
        }
        Write("displacements.csv", displacementLines);
        Write("member_forces.csv", forceLines);
        Write("reactions.csv", reactionLines);
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
    public static void Main(string[] args) {
        Prepare(ModelIo.Read());
        List<string> history = DesignSections();
        CsvReports();
        Write("analysis.txt", AnalysisReport());
        Write("design.txt", DesignReport(history));
        Write("influence.txt", InfluenceReport());
        Write("drawing.txt", DrawingReport());
        Write("vibration.txt", VibrationReport());
    }
}
