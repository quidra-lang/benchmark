sealed record Validation(string Status, List<string> Messages, int Correct)
{
    public string Verdict => Status == "valid" ? "valid " + Messages[0] : Status + ": " + Messages[0];
}
sealed record Transformed(List<GroundAction> Actions, State Initial, int Complements);
sealed class Params
{
    public int Budget {
        get;
        set;
    }
    public int Weight {
        get;
        set;
    }
    public int Limit {
        get;
        set;
    }
    public List<(string Algorithm, string Heuristic)> Runs {
        get;
    } = new();
    public (string Algorithm, string Heuristic) Repair {
        get;
        set;
    }
    public static Params Read()
    {
        Params p = new();
        foreach (string line in File.ReadLines("input/params.txt").Where(l => l.Length > 0 && !l.StartsWith('#')))
        {
            string[] a = line.Split(' ');
            switch (a[0])
            {
                case "budget": p.Budget = int.Parse(a[1]);
                break;
                case "weight": p.Weight = int.Parse(a[1]);
                break;
                case "graphplan": p.Limit = int.Parse(a[1]);
                break;
                case "run": p.Runs.Add((a[1], a[2]));
                break;
                default: p.Repair = (a[1], a[2]);
                break;
            }
        }
        return p;
    }
}
sealed record Candidate(string Problem, string Label, List<Atom> Steps);
sealed record PlanBlock(List<string> Lines, List<string> Validation, bool Valid);
static class Program
{
    static string? Arguments(Domain domain, List<string> args, List<string> expected, Dictionary<string, string> table, string noun)
    {
        if (args.Count != expected.Count) return $"expected {expected.Count} arguments, got {args.Count}";
        for (int i = 0; i < args.Count; i++)
        {
            string name = args[i];
            if (!table.TryGetValue(name, out string? actual)) return $"unknown {noun} {name}";
            if (!Grounder.Subtype(domain, actual, expected[i])) return $"argument {i + 1} ({name}) is not of type {expected[i]}";
        }
        return null;
    }
    static string? AtomError(Domain domain, Atom atom, Dictionary<string, string> table, string noun, bool equality)
    {
        List<string> types;
        if (equality && atom.Predicate == "=") types = new() {
            "object", "object"
        };
        else
        {
            Predicate? predicate = domain.Predicates.FirstOrDefault(p => p.Name == atom.Predicate);
            if (predicate is null) return $"unknown predicate {atom.Predicate}";
            types = predicate.Types;
        }
        return Arguments(domain, atom.Terms, types, table, noun);
    }
    static void ValidateDomain(Domain domain)
    {
        List<Schema> actions = new();
        foreach (Schema action in domain.Actions)
        {
            Dictionary<string, string> table = action.Parameters.ToDictionary(p => p.Name, p => p.Type, StringComparer.Ordinal);
            Typed? invalid = action.Parameters.FirstOrDefault(p => !domain.TypeOrder.Contains(p.Type));
            string? error = invalid is null ? null : "unknown type " + invalid.Type;
            if (error is null) foreach (Literal literal in action.Pre.Concat(action.Effects))
            {
                string? reason = AtomError(domain, literal.Atom, table, "variable", true);
                if (reason is not null) {
                    error = literal.Atom.Text + ": " + reason;
                    break;
                }
            }
            if (error is not null) domain.Diagnostics.Add($"error: action {action.Name}: {error}");
            else actions.Add(action);
        }
        domain.Actions = actions;
        foreach (Predicate predicate in domain.Predicates) if (!domain.Actions.Any(a => a.Pre.Concat(a.Effects).Any(l => l.Atom.Predicate == predicate.Name))) domain.Diagnostics.Add($"warning: predicate {predicate.Name} is not used by any action");
    }
    static void ValidateProblem(Domain domain, Problem problem)
    {
        Dictionary<string, string> table = problem.Objects.ToDictionary(o => o.Name, o => o.Type, StringComparer.Ordinal);
        for (int side = 0; side < 2; side++)
        {
            List<Atom> original = side == 0 ? problem.Initial : problem.Goals;
            HashSet<Atom> seen = new();
            List<Atom> kept = new();
            foreach (Atom atom in original)
            {
                string? error = AtomError(domain, atom, table, "object", false) ?? (seen.Contains(atom) ? "duplicate" : null);
                if (error is not null) problem.Diagnostics.Add($"warning: {(side == 0 ? "init" : "goal")} {atom.Text}: {error}");
                else {
                    seen.Add(atom);
                    kept.Add(atom);
                }
            }
            if (side == 0) problem.Initial = kept;
            else problem.Goals = kept;
        }
    }
    static string Listed(string heading, IEnumerable<string> input)
    {
        List<string> values = input.ToList();
        return heading + " " + (values.Count == 0 ? "-" : string.Join(" ", values));
    }
    static string Numbers(State values) => values.Count == 0 ? "-" : string.Join(",", values.Order());
    static string HText(long value) => value >= Heuristics.Infinity ? "inf" : value.ToString(CultureInfo.InvariantCulture);
    static string HValues(IEnumerable<long> values) => string.Join(" ", new[] {
        "goalcount", "hmax", "hadd", "ff", "lmcount"
    }.Zip(values, (name, value) => name + "=" + HText(value)));
    static long Cost(Grounding g, List<int> plan) => plan.Sum(i => (long)g.Actions[i].Cost);
    static List<string> DomainReport(Domain domain)
    {
        List<string> lines = new() {
            $"== domain {domain.Name} =="
        };
        lines.AddRange(domain.Diagnostics);
        foreach (string type in domain.TypeOrder)
        {
            List<string> chain = new() {
                type
            };
            string current = type;
            while (domain.Parents.TryGetValue(current, out string? parent)) {
                chain.Add(parent);
                current = parent;
            }
            lines.Add("type " + string.Join(" < ", chain));
        }
        HashSet<string> fluent = Grounder.Fluents(domain);
        foreach (Predicate p in domain.Predicates) lines.Add($"predicate {p.Name}/{p.Types.Count} {(fluent.Contains(p.Name) ? "fluent" : "static")}");
        foreach (Schema a in domain.Actions) lines.Add($"action {a.Name}/{a.Parameters.Count} cost={a.Cost} pre={a.Pre.Count} add={a.Effects.Count(l => !l.Negative)} del={a.Effects.Count(l => l.Negative)}");
        return lines;
    }
    static List<string> GroundingReport(Domain domain, Problem problem, Grounding g)
    {
        List<string> lines = new() {
            "", $"== problem {problem.Name} =="
        };
        lines.AddRange(problem.Diagnostics);
        lines.Add($"objects: {problem.Objects.Count}");
        foreach (string type in domain.TypeOrder) lines.Add(Listed($"  {type}:", problem.Objects.Where(o => Grounder.Subtype(domain, o.Type, type)).Select(o => o.Name)));
        lines.Add($"static facts: {g.StaticCount}");
        for (int i = 0; i < domain.Actions.Count; i++) lines.Add($"schema {domain.Actions[i].Name}: assignments={g.Stats[i][0]} candidates={g.Stats[i][1]} reachable={g.Stats[i][2]}");
        lines.Add($"candidates: {g.Stats.Sum(s => s[1])} reachable: {g.Actions.Count}");
        lines.Add($"facts: {g.Facts.Count} init: {g.Initial.Count} goals: {g.Goals.Count}");
        foreach (Atom atom in g.Unreachable) lines.Add("unreachable goal: " + atom.Text);
        lines.Add(Listed("facts by predicate:", domain.Predicates.Where(p => g.Fluent.Contains(p.Name)).Select(p => $"{p.Name}={g.Facts.Count(a => a.Predicate == p.Name)}")));
        lines.Add("facts:");
        for (int i = 0; i < g.Facts.Count; i++) lines.Add($"  {i} {g.Facts[i].Text}");
        lines.Add("actions:");
        for (int i = 0; i < g.Actions.Count; i++)
        {
            GroundAction a = g.Actions[i];
            lines.Add($"  {i} {a.Text} cost={a.Cost} pre={Numbers(a.Pre)} neg={Numbers(a.Neg)} add={Numbers(a.Add)} del={Numbers(a.Del)}");
        }
        return lines;
    }
    static Validation ValidateSteps(Domain domain, Problem problem, List<Atom> steps)
    {
        HashSet<Atom> world = problem.Initial.ToHashSet();
        long cost = 0;
        Dictionary<string, string> table = problem.Objects.ToDictionary(o => o.Name, o => o.Type, StringComparer.Ordinal);
        for (int k = 0; k < steps.Count; k++)
        {
            Atom step = steps[k];
            Schema? action = domain.Actions.FirstOrDefault(a => a.Name == step.Predicate);
            if (action is null) return new Validation("invalid", new() {
                $"step {k + 1} {step.Text}: unknown action {step.Predicate}"
            }, k);
            string? error = Arguments(domain, step.Terms, action.Parameters.Select(p => p.Type).ToList(), table, "object");
            if (error is not null) return new Validation("invalid", new() {
                $"step {k + 1} {step.Text}: {error}"
            }, k);
            Dictionary<string, string> values = action.Parameters.Select((p, i) => (p.Name, Value: step.Terms[i])).ToDictionary(p => p.Name, p => p.Value, StringComparer.Ordinal);
            foreach (Literal original in action.Pre)
            {
                Literal literal = original.Replace(values);
                Atom atom = literal.Atom;
                bool truth = atom.Predicate == "=" ? atom.Terms[0] == atom.Terms[1] : world.Contains(atom);
                if (truth == literal.Negative) return new Validation("invalid", new() {
                    $"step {k + 1} {step.Text}: precondition {literal.Text} is false"
                }, k);
            }
            foreach (Literal l in action.Effects.Where(l => l.Negative)) world.Remove(l.Atom.Replace(values));
            foreach (Literal l in action.Effects.Where(l => !l.Negative)) world.Add(l.Atom.Replace(values));
            cost += action.Cost;
        }
        List<string> missing = problem.Goals.Where(a => !world.Contains(a)).Select(a => "unsatisfied goal " + a.Text).ToList();
        return missing.Count == 0 ? new Validation("valid", new() {
            $"length={steps.Count} cost={cost}"
        }, steps.Count) : new Validation("goal not reached", missing, steps.Count);
    }
    static List<Atom> Steps(Grounding g, List<int> plan) => plan.Select(i => new Atom(g.Actions[i].Name, g.Actions[i].Args)).ToList();
    static List<int> MapSteps(Grounding g, List<Atom> steps) => steps.Select(step => g.Actions.FindIndex(a => a.Name == step.Predicate && a.Args.SequenceEqual(step.Terms))).ToList();
    static bool Interfere(GroundAction a, GroundAction b) => a.Del.Overlaps(b.Pre) || a.Del.Overlaps(b.Add) || b.Del.Overlaps(a.Pre) || b.Del.Overlaps(a.Add) || a.Add.Overlaps(b.Neg) || b.Add.Overlaps(a.Neg);
    static List<List<int>> Parallel(Grounding g, List<int> plan)
    {
        List<int> levels = new();
        for (int j = 0; j < plan.Count; j++)
        {
            int level = 0;
            for (int i = 0; i < j; i++)
            {
                GroundAction a = g.Actions[plan[i]], b = g.Actions[plan[j]];
                if (a.Add.Overlaps(b.Pre) || a.Del.Overlaps(b.Neg) || Interfere(a, b)) level = Math.Max(level, levels[i]);
            }
            levels.Add(level + 1);
        }
        List<List<int>> layers = Enumerable.Range(0, levels.DefaultIfEmpty(0).Max()).Select(_ => new List<int>()).ToList();
        for (int i = 0; i < plan.Count; i++) layers[levels[i] - 1].Add(plan[i]);
        return layers;
    }
    static string ParallelVerdict(Grounding g, List<List<int>> layers)
    {
        State state = new(g.Initial);
        for (int k = 0; k < layers.Count; k++)
        {
            List<int> layer = layers[k];
            bool bad = Enumerable.Range(0, layer.Count).Any(i => layer.Skip(i + 1).Any(a => Interfere(g.Actions[layer[i]], g.Actions[a])));
            if (bad || layer.Any(i => !Search.Applicable(g.Actions[i], state))) return $"invalid at layer {k + 1}";
            state.ExceptWith(layer.SelectMany(i => g.Actions[i].Del));
            state.UnionWith(layer.SelectMany(i => g.Actions[i].Add));
        }
        return g.Goals.IsSubsetOf(state) ? "valid" : "goal not reached";
    }
    static List<int> Improve(Grounding g, List<int> input)
    {
        List<int> plan = input;
        int i = 0;
        while (i < plan.Count)
        {
            State state = g.Initial;
            foreach (int action in plan.Take(i)) state = Search.Apply(g.Actions[action], state);
            List<int> next = plan.Take(i).ToList();
            foreach (int action in plan.Skip(i + 1)) if (Search.Applicable(g.Actions[action], state)) {
                state = Search.Apply(g.Actions[action], state);
                next.Add(action);
            }
            if (g.Goals.IsSubsetOf(state)) plan = next;
            else i++;
        }
        return plan;
    }
    static Transformed Transform(Grounding g)
    {
        int[] negatives = g.Actions.SelectMany(a => a.Neg).Distinct().Order().ToArray();
        Dictionary<int, int> complements = negatives.Select((p, i) => (Fact: p, Complement: g.Facts.Count + i)).ToDictionary(p => p.Fact, p => p.Complement);
        State initial = g.Initial.Concat(negatives.Where(p => !g.Initial.Contains(p)).Select(p => complements[p])).ToHashSet();
        List<GroundAction> actions = g.Actions.Select(a => a with
        {
            Pre = a.Pre.Concat(a.Neg.Select(p => complements[p])).ToHashSet(),
            Add = a.Add.Concat(a.Del.Where(complements.ContainsKey).Select(p => complements[p])).ToHashSet(),
            Del = a.Del.Concat(a.Add.Where(complements.ContainsKey).Select(p => complements[p])).ToHashSet()
        }).ToList();
        return new Transformed(actions, initial, negatives.Length);
    }
    static List<Candidate> ReadCandidates()
    {
        List<Candidate> result = new();
        foreach (string line in File.ReadLines("input/candidates.txt").Where(l => l.Length > 0 && !l.StartsWith('#')))
        {
            if (line.StartsWith("plan ", StringComparison.Ordinal)) {
                string[] a = line.Split(' ');
                result.Add(new Candidate(a[1], a[2], new()));
            }
            else if (line != "end") {
                string[] a = line[1..^1].Split(' ');
                result[^1].Steps.Add(new Atom(a[0], a.Skip(1)));
            }
        }
        return result;
    }
    static PlanBlock AnalyzePlan(Domain domain, Problem problem, Grounding g, List<int> plan, string tag, State landmarks, List<(List<int> Plan, string Tag)> seen)
    {
        int first = seen.FindIndex(p => p.Plan.SequenceEqual(plan));
        string same = first < 0 ? "" : $" (same as {seen[first].Tag})";
        if (first < 0) seen.Add((plan, tag));
        List<string> lines = new() {
            $"plan: length={plan.Count} cost={Cost(g, plan)}{same}"
        };
        for (int k = 0; k < plan.Count; k++) lines.Add($"  {k + 1} {g.Actions[plan[k]].Text}");
        lines.Add(Listed("schemas:", domain.Actions.Select((a, i) => (Schema: a, Count: plan.Count(p => g.Actions[p].Source == i))).Where(p => p.Count > 0).Select(p => $"{p.Schema.Name}={p.Count}")));
        List<List<int>> layers = Parallel(g, plan);
        lines.Add($"parallel: layers={layers.Count}");
        for (int k = 0; k < layers.Count; k++) lines.Add(Listed($"  {k + 1}:", layers[k].Select(a => g.Actions[a].Text)));
        List<int> improved = Improve(g, plan);
        lines.Add($"improved: length={improved.Count} cost={Cost(g, improved)} removed={plan.Count - improved.Count}");
        if (improved.Count < plan.Count) for (int k = 0; k < improved.Count; k++) lines.Add($"  {k + 1} {g.Actions[improved[k]].Text}");
        State state = g.Initial, reached = new();
        foreach (int action in plan) {
            state = Search.Apply(g.Actions[action], state);
            reached.UnionWith(state.Intersect(landmarks));
        }
        lines.Add($"landmarks reached: {reached.Count}/{landmarks.Count}");
        foreach (int fact in landmarks.Except(reached).Order()) lines.Add("  missed " + g.Facts[fact].Text);
        Validation original = ValidateSteps(domain, problem, Steps(g, plan)), check = ValidateSteps(domain, problem, Steps(g, improved));
        return new PlanBlock(lines, new() {
            $"{tag}: {original.Verdict}", "  parallel: " + ParallelVerdict(g, layers), "  improved: " + check.Verdict
        }, original.Status == "valid");
    }
    static List<string> Profile(Grounding g, List<int> plan, string tag)
    {
        List<string> lines = new() {
            $"-- profile ({tag}) --"
        };
        State state = g.Initial;
        long remaining = Cost(g, plan);
        long[] over = new long[5];
        for (int k = 0; k <= plan.Count; k++)
        {
            List<long> values = Heuristics.Values(g, state);
            for (int i = 0; i < 5; i++) if (values[i] > remaining) over[i]++;
            lines.Add($"  {k}: h*={remaining} {HValues(values)}");
            if (k < plan.Count) {
                state = Search.Apply(g.Actions[plan[k]], state);
                remaining -= g.Actions[plan[k]].Cost;
            }
        }
        lines.Add("overestimates: " + HValues(over));
        lines.Add($"-- causal links ({tag}) --");
        int[] suppliers = new int[g.Facts.Count];
        for (int k = 0; k < plan.Count; k++)
        {
            GroundAction action = g.Actions[plan[k]];
            lines.Add(Listed($"  {k + 1} {action.Text}:", action.Pre.Order().Select(p => $"{g.Facts[p].Text}<-{suppliers[p]}")));
            foreach (int fact in action.Add) suppliers[fact] = k + 1;
        }
        lines.Add(Listed("  goal:", g.Goals.Order().Select(p => $"{g.Facts[p].Text}<-{suppliers[p]}")));
        return lines;
    }
    static string ResultLine(SearchResult result, bool unreachable) => unreachable ? "result: FAIL (unreachable goal)" : result.Status == "solved" ? $"result: solved expanded={result.Expanded} generated={result.Generated}" : $"result: FAIL ({result.Status}) expanded={result.Expanded} generated={result.Generated}";
    static void Write(string name, List<string> lines)
    {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", new System.Text.UTF8Encoding(false));
    }
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        Domain domain = PddlParser.ReadDomain();
        ValidateDomain(domain);
        List<Problem> problems = PddlParser.ReadProblems();
        foreach (Problem problem in problems) ValidateProblem(domain, problem);
        Params parameters = Params.Read();
        List<Grounding> grounds = problems.Select(p => Grounder.Ground(domain, p)).ToList();
        List<string> tags = parameters.Runs.Select(p => p.Algorithm + " " + p.Heuristic).Append("graphplan").ToList();
        List<string> groundingLines = DomainReport(domain), plans = new(), graphLines = new(), validation = new(), comparison = new() {
            "problem,algorithm,heuristic,length,cost,expanded,generated"
        }, problemSummary = new();
        int[][] tagStats = tags.Select(_ => new int[4]).ToArray();
        List<long?> bests = new();
        int analyzed = 0, validPlans = 0;
        for (int index = 0; index < problems.Count; index++)
        {
            Problem problem = problems[index];
            Grounding g = grounds[index];
            bool unreachable = g.Unreachable.Count > 0;
            groundingLines.AddRange(GroundingReport(domain, problem, g));
            string heading = $"== problem {problem.Name} ==";
            plans.Add(heading);
            validation.Add(heading);
            graphLines.Add(heading);
            State landmarks = new();
            if (unreachable) plans.Add("initial h: unreachable goal");
            else
            {
                plans.Add("initial h: " + HValues(Heuristics.Values(g, g.Initial)));
                landmarks = Heuristics.Landmarks(g, g.Initial) ?? new();
                plans.Add($"landmarks: {landmarks.Count}");
                foreach (int fact in landmarks.Order()) plans.Add("  " + g.Facts[fact].Text);
                Relaxed relaxed = Heuristics.Relax(g, g.Initial);
                plans.Add($"relaxed plan: length={relaxed.Plan.Count} cost={HText(relaxed.Value)}");
                foreach (int action in relaxed.Plan) plans.Add("  " + g.Actions[action].Text);
                plans.Add(Listed("helpful:", relaxed.Helpful.Select(a => g.Actions[a].Text)));
            }
            List<SearchResult> results = parameters.Runs.Select(p => unreachable ? new SearchResult("unreachable goal") : Search.Run(g, g.Initial, p.Algorithm, p.Heuristic, parameters.Budget, parameters.Weight)).ToList();
            if (unreachable) {
                graphLines.Add("result: FAIL (unreachable goal)");
                results.Add(new SearchResult("unreachable goal"));
            }
            else
            {
                Transformed transformed = Transform(g);
                GraphResult graph = GraphPlan.Run(transformed.Actions, transformed.Initial, g.Goals, parameters.Limit);
                graphLines.Add($"complementary facts: {transformed.Complements}");
                graphLines.AddRange(graph.Records);
                if (graph.Search.Status == "solved")
                {
                    graphLines.Add($"result: solved levels={graph.Layers.Count} length={graph.Search.Plan.Count} cost={Cost(g, graph.Search.Plan)} searched={graph.Search.Expanded} memo_hits={graph.Hits} tried={graph.Search.Generated}");
                    for (int k = 0; k < graph.Layers.Count; k++) graphLines.Add(Listed($"layer {k + 1}:", graph.Layers[k].Select(a => g.Actions[a].Text)));
                }
                else graphLines.Add($"result: FAIL ({graph.Search.Status}) searched={graph.Search.Expanded} memo_hits={graph.Hits} tried={graph.Search.Generated}");
                results.Add(graph.Search);
            }
            graphLines.Add("");
            long? best = results.Where(r => r.Status == "solved").Select(r => (long?)Cost(g, r.Plan)).Min();
            bests.Add(best);
            int proof = parameters.Runs.FindIndex(p => (p == ("ucs", "none") || p == ("astar", "hmax")) && results[parameters.Runs.IndexOf(p)].Status == "solved");
            string optimal = proof >= 0 ? Cost(g, results[proof].Plan).ToString(CultureInfo.InvariantCulture) : results.Any(r => r.Status is "unreachable goal" or "dead end" or "exhausted" or "unreachable") ? "none" : "unknown";
            problemSummary.Add($"{problem.Name}: solved={results.Count(r => r.Status == "solved")}/{results.Count} best={(best?.ToString(CultureInfo.InvariantCulture) ?? "-")} optimal={optimal}");
            List<(List<int> Plan, string Tag)> seen = new();
            for (int i = 0; i < results.Count; i++)
            {
                SearchResult result = results[i];
                plans.Add($"-- {tags[i]} --");
                plans.Add(ResultLine(result, unreachable));
                tagStats[i][2] += result.Expanded;
                tagStats[i][3] += result.Generated;
                var pair = i < parameters.Runs.Count ? parameters.Runs[i] : (Algorithm: "graphplan", Heuristic: "none");
                string length = "-", costText = "-";
                if (result.Status == "solved")
                {
                    tagStats[i][0]++;
                    if (Cost(g, result.Plan) == best) tagStats[i][1]++;
                    PlanBlock block = AnalyzePlan(domain, problem, g, result.Plan, tags[i], landmarks, seen);
                    plans.AddRange(block.Lines);
                    validation.AddRange(block.Validation);
                    analyzed++;
                    if (block.Valid) validPlans++;
                    length = result.Plan.Count.ToString(CultureInfo.InvariantCulture);
                    costText = Cost(g, result.Plan).ToString(CultureInfo.InvariantCulture);
                }
                comparison.Add($"{problem.Name},{pair.Algorithm},{pair.Heuristic},{length},{costText},{result.Expanded},{result.Generated}");
            }
            if (proof >= 0) plans.AddRange(Profile(g, results[proof].Plan, tags[proof]));
            plans.Add("");
            validation.Add("");
        }
        plans.Add("== summary ==");
        plans.AddRange(problemSummary);
        for (int i = 0; i < tags.Count; i++) plans.Add($"{tags[i]}: solved={tagStats[i][0]} best={tagStats[i][1]} expanded={tagStats[i][2]} generated={tagStats[i][3]}");
        validation.Add("== candidates ==");
        List<Candidate> candidates = ReadCandidates();
        int validCandidates = 0;
        for (int k = 0; k < candidates.Count; k++)
        {
            Candidate candidate = candidates[k];
            int index = problems.FindIndex(p => p.Name == candidate.Problem);
            Problem problem = problems[index];
            Grounding g = grounds[index];
            Validation check = ValidateSteps(domain, problem, candidate.Steps);
            if (check.Status == "valid")
            {
                validCandidates++;
                validation.Add($"candidate {k + 1} {problem.Name} {candidate.Label}: {check.Verdict}");
                List<int> mapped = MapSteps(g, candidate.Steps), improved = Improve(g, mapped);
                validation.Add($"  improved: length={improved.Count} cost={Cost(g, improved)} removed={mapped.Count - improved.Count} best known={(bests[index]?.ToString(CultureInfo.InvariantCulture) ?? "-")}");
            }
            else
            {
                validation.Add($"candidate {k + 1} {problem.Name} {candidate.Label}: {check.Status}");
                validation.AddRange(check.Messages.Select(m => "  " + m));
                if (g.Unreachable.Count > 0) {
                    validation.Add("  repair: FAIL (unreachable goal)");
                    continue;
                }
                List<int> mapped = MapSteps(g, candidate.Steps.Take(check.Correct).ToList());
                State state = g.Initial;
                foreach (int action in mapped) state = Search.Apply(g.Actions[action], state);
                SearchResult repair = Search.Run(g, state, parameters.Repair.Algorithm, parameters.Repair.Heuristic, parameters.Budget, parameters.Weight);
                if (repair.Status != "solved") validation.Add($"  repair: FAIL ({repair.Status})");
                else
                {
                    List<int> repairedPlan = mapped.Concat(repair.Plan).ToList();
                    Validation repaired = ValidateSteps(domain, problem, Steps(g, repairedPlan));
                    validation.Add($"  repair: kept={check.Correct} added={repair.Plan.Count} {repaired.Verdict}");
                    for (int j = 0; j < repairedPlan.Count; j++) validation.Add($"    {j + 1} {g.Actions[repairedPlan[j]].Text}");
                }
            }
        }
        validation.AddRange(new[] {
            "", "== summary ==", $"plans: {analyzed} valid: {validPlans}", $"candidates: {candidates.Count} valid: {validCandidates}"
        });
        Write("grounding.txt", groundingLines);
        Write("plans.txt", plans);
        Write("graphplan.txt", graphLines);
        Write("validation.txt", validation);
        Write("comparison.csv", comparison);
    }
}
