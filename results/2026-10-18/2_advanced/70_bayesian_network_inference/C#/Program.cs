using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
public static class Program {
    public static NetworkIo.Network network;
    public static NetworkIo.Settings settings;
    public static List<int[]> samples;
    public static List<string> names;
    public static List<List<string>> states;
    public static List<List<int>> parents, children = new(), spouses = new(), blankets = new();
    public static List<HashSet<int>> ancestors = new(), descendants = new();
    public static List<int> variables = new(), topological = new();
    public static int[] sizes, depths, parameterCounts;
    public static List<int[][]> counts = new();
    public static List<double[][]> learned = new(), cpts = new();
    public static double[] likelihoods;
    public static List<Factors.Factor> factors = new();
    public static Sampling.Minstd random;
    public static Dictionary<string, double> familyScores = new();
    public record Evidence(int variable, int state) {}
    public record Parts(List<int> query, List<Evidence> evidence) {}
    public record Plans(Elimination.Plan minfill, Elimination.Plan given) {}
    public record SumResult(Factors.Factor distribution, double probability, double[][] marginals) {
    }
    public record Posterior(List<int> relevant, List<int> eliminate, List<Factors.Factor> initial,
                            Plans plans, SumResult result) {}
    public record Enumeration(long count, string result) {}
    public record Answer(List<string> lines, List<string> elimination) {}
    public record Mpe(double maximum, int[] assignment) {}
    public record SampleAnswer(List<string> lines, List<string> csv) {}
    public record Ball(int variable, int direction) {}
    public record Information(double cmi, double g2, long degrees) {}
    public static string Real(double value) {
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text.Equals("-0.0000") ? "0.0000" : text;
    }
    public static string Yes(bool value) { return value ? "yes" : "no"; }
    public static List<int> Sorted(IEnumerable<int> values) => new SortedSet<int>(values).ToList();
    public static List<int> Union(IEnumerable<int> a,
                                  IEnumerable<int> b) => a.Union(b).Order().ToList();
    public static List<int> Difference(IEnumerable<int> a,
                                       IEnumerable<int> b) => a.Except(b).Order().ToList();
    public static HashSet<int> Closure(IEnumerable<int> initial, List<List<int>> links) {
        HashSet<int> reached = new(initial);
        Stack<int> pending = new(initial);
        while (pending.Count != 0)
            foreach (int neighbor in links[pending.Pop()])
                if (reached.Add(neighbor))
                    pending.Push(neighbor);
        return reached;
    }
    public static string Sequence(IEnumerable<int> variables) {
        List<string> parts = new();
        foreach (int v in variables)
            parts.Add(names[v]);
        return parts.Count == 0 ? "-" : string.Join(" ", parts);
    }
    public static string AssignmentText(int[] assignment, List<int> variables) {
        List<string> parts = new();
        foreach (int v in variables)
            parts.Add(names[v] + "=" + states[v][assignment[v]]);
        return parts.Count == 0 ? "-" : string.Join(" ", parts);
    }
    public static int[] EvidenceArray(List<Evidence> evidence) {
        int[] values = new int[sizes.Length];
        Array.Fill(values, -1);
        foreach (Evidence e in evidence)
            values[e.variable] = e.state;
        return values;
    }
    public static List<int> EvidenceVariables(List<Evidence> evidence) {
        List<int> values = new();
        foreach (Evidence e in evidence)
            values.Add(e.variable);
        return Sorted(values);
    }
    public static List<Evidence> ParseEvidence(List<string> fields) {
        List<Evidence> result = new();
        foreach (string field in fields) {
            string[] w = field.Split("=");
            int v = names.IndexOf(w[0]);
            result.Add(new Evidence(v, states[v].IndexOf(w[1])));
        }
        return result;
    }
    public static Parts ParseParts(List<string> fields) {
        int separator = fields.IndexOf("|");
        if (separator < 0)
            separator = fields.Count;
        List<int> query = new();
        foreach (string name in fields.GetRange(0, separator - 0))
            query.Add(names.IndexOf(name));
        return new Parts(query, separator == fields.Count
                                    ? new()
                                    : ParseEvidence(fields.GetRange(
                                          separator + 1, fields.Count - (separator + 1))));
    }
    public static void Prepare(NetworkIo.Input input) {
        network = input.network;
        settings = input.settings;
        samples = input.samples;
        names = network.names;
        states = network.states;
        parents = network.parents;
        sizes = new int[names.Count];
        depths = new int[names.Count];
        likelihoods = new double[names.Count];
        parameterCounts = new int[names.Count];
        for (int v = 0; v < names.Count; v++) {
            variables.Add(v);
            sizes[v] = states[v].Count;
            List<int> list = new();
            for (int child = 0; child < names.Count; child++)
                if (parents[child].Contains(v))
                    list.Add(child);
            children.Add(list);
        }
        bool[] selected = new bool[sizes.Length];
        while (topological.Count < sizes.Length)
            foreach (int v in variables)
                if (!selected[v]) {
                    bool ready = true;
                    foreach (int p in parents[v])
                        if (!selected[p])
                            ready = false;
                    if (ready) {
                        selected[v] = true;
                        topological.Add(v);
                        break;
                    }
                }
        foreach (int v in topological)
            foreach (int p in parents[v])
                depths[v] = Math.Max(depths[v], depths[p] + 1);
        foreach (int v in variables) {
            ancestors.Add(Closure(parents[v], parents));
            descendants.Add(Closure(children[v], children));
            List<int> immediate = Union(parents[v], children[v]);
            SortedSet<int> coParents = new();
            foreach (int child in children[v])
                coParents.UnionWith(parents[child]);
            coParents.ExceptWith(immediate);
            coParents.Remove(v);
            spouses.Add(new(coParents));
            blankets.Add(Union(immediate, coParents));
            int[][] observed = Learning.Counts(v, parents[v], samples, sizes);
            counts.Add(observed);
            double[][] fitted = Learning.Learn(observed, settings.alpha);
            learned.Add(fitted);
            double[][] used = settings.sources[v].Equals("GIVEN") ? network.expert[v] : fitted;
            cpts.Add(used);
            likelihoods[v] = Learning.Likelihood(observed, used);
            parameterCounts[v] = Learning.Parameters(observed);
            factors.Add(Factors.Cpt(v, parents[v], used, sizes));
        }
        random = new Sampling.Minstd(settings.seed);
    }
    public static Plans BuildPlans(List<Factors.Factor> initial, List<int> eliminate) {
        return new Plans(Elimination.MakePlan(initial, eliminate, "MINFILL", settings.order, sizes),
                         Elimination.MakePlan(initial, eliminate, "GIVEN", settings.order, sizes));
    }
    public static Elimination.Plan Used(Plans plans) {
        return settings.method.Equals("MINFILL") ? plans.minfill : plans.given;
    }
    public static SumResult ComputeSumResult(List<Factors.Factor> initial, Elimination.Plan plan,
                                             List<int> query) {
        Factors.Factor factor = Elimination.Execute(initial, plan, sizes, false).factor;
        double probability = Learning.Total(factor.values);
        double[] values = new double[factor.values.Length];
        for (int i = 0; i < values.Length; i++)
            values[i] = factor.values[i] / probability;
        Factors.Factor distribution = new Factors.Factor(factor.variables, values, sizes);
        double[][] marginals = new double [sizes.Length][];
        foreach (int v in query)
            marginals[v] = new double[sizes[v]];
        for (int i = 0; i < values.Length; i++) {
            int[] assignment = Factors.Assignment(i, factor.variables, sizes);
            foreach (int v in query)
                marginals[v][assignment[v]] += values[i];
        }
        return new SumResult(distribution, probability, marginals);
    }
    public static Posterior ComputePosterior(List<int> query, List<Evidence> evidence) {
        List<int> relevant = Sorted(Closure(Union(query, EvidenceVariables(evidence)), parents)),
                  eliminate = Difference(Difference(relevant, query), EvidenceVariables(evidence));
        List<Factors.Factor> initial = new();
        int[] observed = EvidenceArray(evidence);
        foreach (int v in relevant)
            initial.Add(factors[v].Reduced(observed));
        Plans plans = BuildPlans(initial, eliminate);
        return new Posterior(relevant, eliminate, initial, plans,
                             ComputeSumResult(initial, Used(plans), query));
    }
    public static double Joint(int[] assignment, List<int> variables) {
        double probability = 1;
        foreach (int v in variables)
            probability *=
                cpts[v][Learning.ParentRow(parents[v], assignment, sizes)][assignment[v]];
        return probability;
    }
    public static void AddEvidence(int[] assignment, List<Evidence> evidence) {
        foreach (Evidence e in evidence)
            assignment[e.variable] = e.state;
    }
    public static Enumeration QueryEnumeration(Posterior result, List<int> query,
                                               List<Evidence> evidence) {
        List<int> free = Difference(result.relevant, EvidenceVariables(evidence));
        int count = Factors.Entries(free, sizes);
        if (count > settings.limit)
            return new Enumeration(count, "skipped");
        List<int> ordered = Sorted(query);
        double[] values = new double[Factors.Entries(ordered, sizes)];
        for (int i = 0; i < count; i++) {
            int[] assignment = Factors.Assignment(i, free, sizes);
            AddEvidence(assignment, evidence);
            values[Learning.ParentRow(ordered, assignment, sizes)] +=
                Joint(assignment, result.relevant);
        }
        double probability = Learning.Total(values);
        bool agreed = Math.Abs(Math.Log(probability) - Math.Log(result.result.probability)) <= 1e-9;
        for (int i = 0; i < values.Length; i++)
            agreed &=
                Math.Abs(values[i] / probability - result.result.distribution.values[i]) <= 1e-9;
        return new Enumeration(count, agreed ? "agree" : "disagree");
    }
    public static List<string> EliminationLines(List<int> relevant, List<int> eliminate,
                                                Plans plans, bool agreement,
                                                Enumeration enumeration) {
        List<string> lines = new();
        lines.Add("relevant " + Sequence(relevant));
        lines.Add("pruned " + Sequence(Difference(variables, relevant)));
        lines.Add("eliminate " + Sequence(eliminate));
        for (int i = 0; i < 2; i++) {
            Elimination.Plan plan = i == 0 ? plans.minfill : plans.given;
            lines.Add("order " + (i == 0 ? "minfill" : "given"));
            foreach (Elimination.Step step in plan.steps)
                lines.Add("step " + names[step.variable] + " fill " + step.fill + " scope " +
                          Sequence(step.scope) + " entries " + step.size);
            lines.Add("cost max " + plan.maximum + " total " + plan.total);
        }
        lines.Add("used " + settings.method.ToLowerInvariant());
        lines.Add("orders_agree " + Yes(agreement));
        lines.Add("enumeration " + enumeration.count + " " + enumeration.result);
        return lines;
    }
    public static List<string> MarginalLines(string prefix, List<int> query, double[][] marginals) {
        List<string> lines = new();
        foreach (int v in query) {
            string line = prefix + " " + names[v];
            for (int s = 0; s < sizes[v]; s++)
                line += " " + states[v][s] + " " + Real(marginals[v][s]);
            lines.Add(line);
        }
        return lines;
    }
    public static Answer AnswerQuery(List<int> query, List<Evidence> evidence) {
        Posterior result = ComputePosterior(query, evidence);
        List<string> lines = new();
        lines.Add("log_evidence " + Real(Math.Log(result.result.probability)));
        if (evidence.Count != 0) {
            double conflict = 0;
            foreach (Evidence e in evidence)
                conflict +=
                    Math.Log(ComputePosterior(new(), new List<Evidence> { e }).result.probability);
            conflict -= Math.Log(result.result.probability);
            lines.Add("conflict " + Real(conflict));
        }
        Factors.Factor distribution = result.result.distribution;
        if (query.Count >= 2)
            for (int i = 0; i < distribution.values.Length; i++)
                lines.Add("joint " +
                          AssignmentText(Factors.Assignment(i, distribution.variables, sizes),
                                         distribution.variables) +
                          " " + Real(distribution.values[i]));
        lines.AddRange(MarginalLines("marginal", query, result.result.marginals));
        foreach (Evidence e in evidence) {
            List<Evidence> reduced = new();
            foreach (Evidence other in evidence)
                if (other.variable != e.variable)
                    reduced.Add(other);
            double[][] without = ComputePosterior(query, reduced).result.marginals;
            double shift = 0;
            foreach (int v in query)
                for (int s = 0; s < sizes[v]; s++)
                    shift =
                        Math.Max(shift, Math.Abs(result.result.marginals[v][s] - without[v][s]));
            lines.Add("drop " + names[e.variable] + "=" + states[e.variable][e.state] + " shift " +
                      Real(shift));
        }
        SumResult a = ComputeSumResult(result.initial, result.plans.minfill, query),
                  b = ComputeSumResult(result.initial, result.plans.given, query);
        bool agree = Math.Abs(Math.Log(a.probability) - Math.Log(b.probability)) <= 1e-9;
        for (int i = 0; i < a.distribution.values.Length; i++)
            agree &= Math.Abs(a.distribution.values[i] - b.distribution.values[i]) <= 1e-9;
        return new Answer(lines,
                          EliminationLines(result.relevant, result.eliminate, result.plans, agree,
                                           QueryEnumeration(result, query, evidence)));
    }
    public static Mpe MaxResult(List<Factors.Factor> initial, Elimination.Plan plan,
                                List<Evidence> evidence) {
        Elimination.Outcome outcome = Elimination.Execute(initial, plan, sizes, true);
        int[] assignment = Elimination.Traceback(outcome.products, sizes);
        AddEvidence(assignment, evidence);
        return new Mpe(outcome.factor.values[0], assignment);
    }
    public static Enumeration MpeEnumeration(List<int> eliminate, List<Evidence> evidence,
                                             Mpe mpe) {
        int count = Factors.Entries(eliminate, sizes);
        if (count > settings.limit)
            return new Enumeration(count, "skipped");
        double best = -1;
        int[] assignment = null;
        for (int i = 0; i < count; i++) {
            int[] candidate = Factors.Assignment(i, eliminate, sizes);
            AddEvidence(candidate, evidence);
            double probability = Joint(candidate, variables);
            if (probability > best) {
                best = probability;
                assignment = candidate;
            }
        }
        bool agree = assignment.SequenceEqual(mpe.assignment) &&
                     Math.Abs(Math.Log(best) - Math.Log(mpe.maximum)) <= 1e-9;
        return new Enumeration(count, agree ? "agree" : "disagree");
    }
    public static Answer AnswerMpe(List<Evidence> evidence) {
        int[] observed = EvidenceArray(evidence);
        List<Factors.Factor> initial = new();
        foreach (Factors.Factor factor in factors)
            initial.Add(factor.Reduced(observed));
        List<int> eliminate = Difference(variables, EvidenceVariables(evidence));
        Plans plans = BuildPlans(initial, eliminate);
        Mpe a = MaxResult(initial, plans.minfill, evidence),
            b = MaxResult(initial, plans.given, evidence),
            result = settings.method.Equals("MINFILL") ? a : b;
        double probability =
            evidence.Count == 0 ? 1 : ComputePosterior(new(), evidence).result.probability;
        List<string> lines = new();
        lines.Add("assignment " + AssignmentText(result.assignment, variables));
        lines.Add("log_joint " + Real(Math.Log(result.maximum)));
        lines.Add("log_evidence " + Real(Math.Log(probability)));
        lines.Add("posterior " + Real(result.maximum / probability));
        foreach (int v in eliminate) {
            List<int> remaining = new(eliminate);
            remaining.Remove(v);
            Elimination.Plan plan =
                Elimination.MakePlan(initial, remaining, settings.method, settings.order, sizes);
            Factors.Factor factor = Elimination.Execute(initial, plan, sizes, true).factor;
            int alternative = -1;
            for (int s = 0; s < sizes[v]; s++)
                if (s != result.assignment[v] &&
                    (alternative < 0 || factor.values[s] > factor.values[alternative]))
                    alternative = s;
            double margin = Math.Log(result.maximum) - Math.Log(factor.values[alternative]);
            lines.Add("margin " + names[v] + " " + states[v][alternative] + " " + Real(margin));
        }
        bool agree = a.assignment.SequenceEqual(b.assignment) &&
                     Math.Abs(Math.Log(a.maximum) - Math.Log(b.maximum)) <= 1e-9;
        return new Answer(lines, EliminationLines(variables, eliminate, plans, agree,
                                                  MpeEnumeration(eliminate, evidence, result)));
    }
    public static SampleAnswer AnswerSample(int number, List<int> query, List<Evidence> evidence,
                                            List<int> checkpoints) {
        double[][] exact = ComputePosterior(query, evidence).result.marginals,
                   weights = new double [sizes.Length][];
        foreach (int v in query)
            weights[v] = new double[sizes[v]];
        List<string> lines = MarginalLines("exact", query, exact), csv = new();
        double weight = 0, squaredWeight = 0;
        int[] observed = EvidenceArray(evidence);
        HashSet<int> selected = new(checkpoints);
        for (int i = 1; i <= checkpoints[^1]; i++) {
            Sampling.Weighted sample =
                Sampling.Generate(topological, parents, cpts, sizes, observed, random);
            double current = sample.weight;
            weight += current;
            squaredWeight += current * current;
            foreach (int v in query)
                weights[v][sample.sample[v]] += current;
            if (!selected.Contains(i))
                continue;
            double maximumError = 0;
            foreach (int v in query)
                for (int s = 0; s < sizes[v]; s++) {
                    double estimate = weights[v][s] / weight, probability = exact[v][s],
                           error = Math.Abs(estimate - probability);
                    maximumError = Math.Max(maximumError, error);
                    csv.Add(number + "," + i + "," + names[v] + "," + states[v][s] + "," +
                            Real(estimate) + "," + Real(probability) + "," + Real(error));
                }
            double effective = weight * weight / squaredWeight;
            lines.Add("after " + i + " weight " + Real(weight) + " ess " + Real(effective) +
                      " max_error " + Real(maximumError));
        }
        return new SampleAnswer(lines, csv);
    }
    public static List<string> AnswerPredict(int variable) {
        int size = sizes[variable];
        int[][] confusion = Enumerable.Range(0, size)
                                .Select(
                                    _ => new int[size])
                                .ToArray();
        double likelihood = 0;
        foreach (int[] sample in samples) {
            int[] assignment = sample.ToArray();
            double[] values = new double[size];
            for (int s = 0; s < size; s++) {
                assignment[variable] = s;
                double probability =
                    cpts[variable][Learning.ParentRow(parents[variable], assignment, sizes)][s];
                foreach (int child in children[variable])
                    probability *= cpts[child][Learning.ParentRow(parents[child], assignment,
                                                                  sizes)][assignment[child]];
                values[s] = probability;
            }
            double total = Learning.Total(values);
            int predicted = 0;
            for (int s = 0; s < size; s++) {
                values[s] /= total;
                if (values[s] > values[predicted])
                    predicted = s;
            }
            int actual = sample[variable];
            confusion[actual][predicted]++;
            likelihood += Math.Log(values[actual]);
        }
        int correct = 0;
        for (int s = 0; s < size; s++)
            correct += confusion[s][s];
        int count = samples.Count;
        List<string> lines = new();
        lines.Add("blanket " + Sequence(blankets[variable]));
        lines.Add("accuracy " + correct + "/" + count + " " + Real(correct / (double)count));
        lines.Add("log_loss " + Real(-likelihood / count));
        lines.Add("predicted " + string.Join(" ", states[variable]));
        for (int s = 0; s < size; s++) {
            string line = "actual " + states[variable][s];
            foreach (int value in confusion[s])
                line += " " + value;
            lines.Add(line);
        }
        return lines;
    }
    public static void AddBall(Queue<Ball> queue, bool[][] visited, int variable, int direction) {
        if (!visited[variable][direction]) {
            visited[variable][direction] = true;
            queue.Enqueue(new Ball(variable, direction));
        }
    }
    public static List<int> Reachable(IEnumerable<int> x, IEnumerable<int> z) {
        HashSet<int> observed = new(z), initial = new(x), ancestors = Closure(z, parents);
        bool[][] visited = Enumerable.Range(0, sizes.Length)
                               .Select(
                                   _ => new bool[2])
                               .ToArray();
        Queue<Ball> pending = new();
        foreach (int v in Sorted(x))
            AddBall(pending, visited, v, 0);
        while (pending.Count != 0) {
            Ball ball = pending.Dequeue();
            int v = ball.variable;
            if (ball.direction == 0 && !observed.Contains(v)) {
                foreach (int p in parents[v])
                    AddBall(pending, visited, p, 0);
                foreach (int child in children[v])
                    AddBall(pending, visited, child, 1);
            } else if (ball.direction == 1) {
                if (!observed.Contains(v))
                    foreach (int child in children[v])
                        AddBall(pending, visited, child, 1);
                if (ancestors.Contains(v))
                    foreach (int p in parents[v])
                        AddBall(pending, visited, p, 0);
            }
        }
        List<int> result = new();
        foreach (int v in variables)
            if ((visited[v][0] || visited[v][1]) && !observed.Contains(v) && !initial.Contains(v))
                result.Add(v);
        return result;
    }
    public static SortedDictionary<int, int> Frequencies(List<int> scope) {
        SortedDictionary<int, int> counts = new();
        foreach (int[] sample in samples)
            counts.AddCount(Learning.ParentRow(scope, sample, sizes), 1);
        return counts;
    }
    public static Information ComputeInformation(List<int> x, List<int> y, List<int> z) {
        List<int> scope = Union(Union(x, y), z), xz = Union(x, z), yz = Union(y, z),
                  orderedZ = Sorted(z);
        SortedDictionary<int, int> observed = Frequencies(scope), countsXz = Frequencies(xz),
                                   countsYz = Frequencies(yz), countsZ = Frequencies(orderedZ);
        double information = 0;
        foreach (var entry in observed) {
            int[] assignment = Factors.Assignment(entry.Key, scope, sizes);
            int count = entry.Value, nxz = countsXz[Learning.ParentRow(xz, assignment, sizes)],
                nyz = countsYz[Learning.ParentRow(yz, assignment, sizes)],
                nz = countsZ[Learning.ParentRow(orderedZ, assignment, sizes)];
            double argument = (count * (double)nz) / (nxz * (double)nyz);
            information += (count / (double)samples.Count) * Math.Log(argument);
        }
        long degrees = (long)(Factors.Entries(x, sizes) - 1) * (Factors.Entries(y, sizes) - 1) *
                       Factors.Entries(z, sizes);
        return new Information(information, 2 * samples.Count * information, degrees);
    }
    public static List<string> AnswerDsep(List<List<int>> groups) {
        List<int> x = groups[0], y = groups[1], z = groups.Count == 3 ? groups[2] : new(),
                  reachable = Reachable(x, z);
        Information information = ComputeInformation(x, y, z);
        return new(new List<string> { "result " + (!reachable.Intersect(y).Any() ? "separated"
                                                                                 : "connected"),
                                      "reachable " + Sequence(reachable),
                                      "data cmi " + Real(information.cmi) + " g2 " +
                                          Real(information.g2) + " df " + information.degrees });
    }
    public static List<string> AnswerBlanket(int variable) {
        List<int> blanket = blankets[variable],
                  rest = Difference(Difference(variables, blanket), new List<int> { variable });
        bool separated = !Reachable(new List<int> { variable }, blanket).Intersect(rest).Any();
        return new(new List<string> { "parents " + Sequence(parents[variable]),
                                      "children " + Sequence(children[variable]),
                                      "spouses " + Sequence(spouses[variable]),
                                      "blanket " + Sequence(blanket), "rest " + Sequence(rest),
                                      "rest_separated " + Yes(separated) });
    }
    public static List<int> FindPath(int start, int finish, int ignoreFrom, int ignoreTo) {
        int[] previous = new int[sizes.Length];
        Array.Fill(previous, -2);
        previous[start] = -1;
        Queue<int> pending = new();
        pending.Enqueue(start);
        while (pending.Count != 0) {
            int v = pending.Dequeue();
            foreach (int child in children[v]) {
                if ((v == ignoreFrom && child == ignoreTo) || previous[child] != -2)
                    continue;
                previous[child] = v;
                if (child == finish) {
                    List<int> result = new();
                    for (int node = child; node >= 0; node = previous[node])
                        result.Add(node);
                    result.Reverse();
                    return result;
                }
                pending.Enqueue(child);
            }
        }
        return null;
    }
    public static double FamilyScore(int variable, IEnumerable<int> parents) {
        List<int> ordered = Sorted(parents);
        string key = variable + ":" + string.Join(",", ordered);
        if (!familyScores.TryGetValue(key, out double value)) {
            value = Learning.FamilyScore(variable, ordered, samples, sizes, settings.alpha);
            familyScores[key] = value;
        }
        return value;
    }
    public static List<string> AnswerEdge(string operation, int x, int y) {
        bool exists = parents[y].Contains(x);
        if (operation.Equals("ADD") && exists)
            return new(new List<string> { "result exists" });
        if (!operation.Equals("ADD") && !exists)
            return new(new List<string> { "result missing" });
        List<int> path = null, cycle = null;
        if (operation.Equals("ADD")) {
            path = FindPath(y, x, -1, -1);
            if (path != null) {
                cycle = new();
                cycle.Add(x);
                cycle.AddRange(path);
            }
        } else if (operation.Equals("REVERSE")) {
            path = FindPath(x, y, x, y);
            if (path != null) {
                cycle = new();
                cycle.Add(y);
                cycle.AddRange(path);
            }
        }
        if (cycle != null) {
            List<string> names = new();
            foreach (int v in cycle)
                names.Add(Program.names[v]);
            return new(new List<string> { "result cycle " + string.Join(" -> ", names) });
        }
        double beforeY = FamilyScore(y, parents[y]);
        List<int> newParents = operation.Equals("ADD")
                                   ? Union(parents[y], new List<int> { x })
                                   : Difference(parents[y], new List<int> { x });
        double afterY = FamilyScore(y, newParents), change = afterY - beforeY;
        List<string> lines = new();
        lines.Add("result ok");
        lines.Add("family " + names[y] + " before " + Real(beforeY) + " after " + Real(afterY));
        if (operation.Equals("REVERSE")) {
            double beforeX = FamilyScore(x, parents[x]),
                   afterX = FamilyScore(x, Union(parents[x], new List<int> { y }));
            change = (afterY - beforeY) + (afterX - beforeX);
            lines.Add("family " + names[x] + " before " + Real(beforeX) + " after " + Real(afterX));
        }
        lines.Add("delta " + Real(change) + " " + (change > 0 ? "improves" : "worsens"));
        return lines;
    }
    public static List<List<string>> CptBlocks() {
        List<List<string>> blocks = new();
        int count = samples.Count;
        foreach (int v in variables) {
            string source = settings.sources[v];
            List<int> parents = Program.parents[v];
            double[][] cpt = cpts[v];
            int[][] observed = counts[v];
            List<string> lines = new();
            lines.Add("variable " + names[v] + " source " + source);
            lines.Add("states " + string.Join(" ", states[v]));
            lines.Add("parents " + Sequence(parents));
            for (int row = 0; row < observed.Length; row++) {
                string rowLine = "row " +
                                 AssignmentText(Factors.Assignment(row, parents, sizes), parents) +
                                 " counts";
                foreach (int value in observed[row])
                    rowLine += " " + value;
                rowLine += " probs";
                foreach (double value in cpt[row])
                    rowLine += " " + Real(value);
                lines.Add(rowLine);
            }
            double likelihood = likelihoods[v],
                   bic = likelihood - parameterCounts[v] * Math.Log(count) / 2;
            lines.Add("loglik " + Real(likelihood) + " parameters " + parameterCounts[v] + " bic " +
                      Real(bic));
            double[] marginal = ComputePosterior(new List<int> { v }, new()).result.marginals[v];
            string line = "marginal model";
            foreach (double probability in marginal)
                line += " " + Real(probability);
            line += " data";
            for (int s = 0; s < sizes[v]; s++) {
                int frequency = 0;
                foreach (int[] row in observed)
                    frequency += row[s];
                line += " " + Real(frequency / (double)count);
            }
            lines.Add(line);
            if (source.Equals("LEARNED")) {
                string difference = "-";
                if (network.expert.ContainsKey(v)) {
                    double maximum = 0;
                    for (int r = 0; r < observed.Length; r++)
                        for (int s = 0; s < sizes[v]; s++)
                            maximum = Math.Max(
                                maximum, Math.Abs(learned[v][r][s] - network.expert[v][r][s]));
                    difference = Real(maximum);
                }
                lines.Add("given_difference " + difference);
            }
            blocks.Add(lines);
        }
        double networkLikelihood = Learning.Total(likelihoods);
        int parameters = 0;
        foreach (int n in parameterCounts)
            parameters += n;
        double networkBic = networkLikelihood - parameters * Math.Log(count) / 2;
        blocks.Add(new List<string> { "network samples " + count + " pseudocount " +
                                      Real(settings.alpha) + " loglik " + Real(networkLikelihood) +
                                      " parameters " + parameters + " bic " + Real(networkBic) });
        return blocks;
    }
    public static List<string> StructureSummary() {
        Plans plans = BuildPlans(factors, variables);
        int widthMinfill = 0, widthGiven = 0;
        foreach (Elimination.Step step in plans.minfill.steps)
            widthMinfill = Math.Max(widthMinfill, step.scope.Count - 1);
        foreach (Elimination.Step step in plans.given.steps)
            widthGiven = Math.Max(widthGiven, step.scope.Count - 1);
        bool[][] graph = Elimination.Interaction(factors, sizes.Length);
        int moral = 0, edges = 0;
        List<int> roots = new(), leaves = new();
        foreach (int v in variables) {
            edges += parents[v].Count;
            if (parents[v].Count == 0)
                roots.Add(v);
            if (children[v].Count == 0)
                leaves.Add(v);
            for (int u = v + 1; u < sizes.Length; u++)
                if (graph[v][u])
                    moral++;
        }
        List<string> lines = new();
        lines.Add("variables " + sizes.Length + " edges " + edges);
        lines.Add("topological_order " + Sequence(topological));
        lines.Add("roots " + Sequence(roots));
        lines.Add("leaves " + Sequence(leaves));
        lines.Add("moral_edges " + moral + " width minfill " + widthMinfill + " given " +
                  widthGiven);
        foreach (int v in variables)
            lines.Add("variable " + names[v] + " states " + sizes[v] + " parents " +
                      parents[v].Count + " children " + children[v].Count + " depth " + depths[v] +
                      " ancestors " + ancestors[v].Count + " descendants " + descendants[v].Count +
                      " blanket " + blankets[v].Count);
        return lines;
    }
    public static List<string> Heading(string heading, List<string> lines) {
        List<string> result = new();
        result.Add(heading);
        result.AddRange(lines);
        return result;
    }
    public static void WriteBlocks(string name, List<List<string>> blocks) {
        List<string> parts = new();
        foreach (List<string> block in blocks)
            parts.Add(string.Join("\n", block));
        string text = string.Join("\n\n", parts);
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), text + (text.Length == 0 ? "" : "\n"));
    }
    public static void ProcessQueries(List<string> queries, List<List<string>> cptReport) {
        List<List<string>> answers = new(), elimination = new(),
                           structure = new() { StructureSummary() };
        List<string> csv = new() { "query,samples,variable,state,estimate,exact,abs_error" };
        for (int number = 1; number <= queries.Count; number++) {
            string line = queries[number - 1];
            List<string> fields = line.Split(' ').ToList();
            string kind = fields[0], heading = "query " + number + " " + line;
            fields.RemoveAt(0);
            switch (kind) {
            case "QUERY": {
                Parts parts = ParseParts(fields);
                Answer answer = AnswerQuery(parts.query, parts.evidence);
                answers.Add(Heading(heading, answer.lines));
                elimination.Add(Heading(heading, answer.elimination));
                break;
            }
            case "MPE": {
                Answer answer = AnswerMpe(ParseEvidence(fields));
                answers.Add(Heading(heading, answer.lines));
                elimination.Add(Heading(heading, answer.elimination));
                break;
            }
            case "SAMPLE": {
                int separator = fields.IndexOf("COUNTS");
                Parts parts = ParseParts(fields.Take(separator).ToList());
                List<int> counts = fields.Skip(separator + 1).Select(int.Parse).ToList();
                SampleAnswer answer = AnswerSample(number, parts.query, parts.evidence, counts);
                answers.Add(Heading(heading, answer.lines));
                csv.AddRange(answer.csv);
                break;
            }
            case "PREDICT":
                answers.Add(Heading(heading, AnswerPredict(names.IndexOf(fields[0]))));
                break;
            case "DSEP": {
                List<List<int>> groups = new() { new() };
                foreach (string field in fields)
                    if (field == "|")
                        groups.Add(new());
                    else
                        groups[^1].Add(names.IndexOf(field));
                structure.Add(Heading(heading, AnswerDsep(groups)));
                break;
            }
            case "BLANKET":
                structure.Add(Heading(heading, AnswerBlanket(names.IndexOf(fields[0]))));
                break;
            case "EDGE":
                structure.Add(Heading(heading, AnswerEdge(fields[0], names.IndexOf(fields[1]),
                                                          names.IndexOf(fields[2]))));
                break;
            }
        }
        WriteBlocks("cpts.txt", cptReport);
        WriteBlocks("structure.txt", structure);
        WriteBlocks("answers.txt", answers);
        WriteBlocks("elimination.txt", elimination);
        WriteBlocks("sampling.csv", new() { csv });
    }
    public static void Main(string[] args) {
        NetworkIo.Input input = NetworkIo.Read();
        Prepare(input);
        List<List<string>> cpts = CptBlocks();
        ProcessQueries(input.queries, cpts);
    }
}
