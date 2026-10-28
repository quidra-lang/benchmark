using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    static int[] GetCounters(Dictionary<string, int[]> counters, string name) {
        if (!counters.TryGetValue(name, out int[] counts)) {
            counts = new int[6];
            counters[name] = counts;
        }
        return counts;
    }
    public static int CompareInt(int first, int second) => first.CompareTo(second);

    public static readonly string[] COMMANDS = { "SOLVE",  "ENUM",  "CORE",     "QUEENS",
                                                 "PIGEON", "COLOR", "CHROMATIC" };
    public static readonly Dictionary<string, string[]> ARGUMENTS =
        new Dictionary<string, string[]> { ["SOLVE"] = new string[] { "file" },
                                           ["ENUM"] = new string[] { "file", "limit" },
                                           ["CORE"] = new string[] { "file" },
                                           ["QUEENS"] = new string[] { "small", "limit" },
                                           ["PIGEON"] = new string[] { "small", "small", "limit" },
                                           ["COLOR"] = new string[] { "graph", "color", "limit" },
                                           ["CHROMATIC"] = new string[] { "graph", "color" } };
    public sealed class Graph {
        public string name, invalid;
        public int vertices, maximumDegree, used;
        public readonly List<int[]> edges = new();
        public int[] degree, greedy;
        public Graph(string name, int vertices) {
            this.name = name;
            this.vertices = vertices;
        }
    }
    public sealed class Solution {
        public CnfIo.Formula formula;
        public Preprocess.Result preparation;
        public readonly List<bool[]> models = new();
        public readonly Dpll.Stats stats = new Dpll.Stats();
        public List<string> trace = new();
        public int rounds;
        public string stop = "limit";
        public string Status() {
            return models.Count == 0 ? "UNSAT" : "SAT";
        }
    }
    public sealed record Attempt(int colors, Solution solution);
    public sealed class Job {
        public int number, removed, rounds, colors, coreDecisions, coreConflicts;
        public string text, command, error;
        public string[] arguments;
        public Graph graph;
        public CnfIo.Formula formula;
        public Solution solution;
        public Dpll.Stats stats = new Dpll.Stats();
        public readonly List<Attempt> attempts = new();
        public List<int> core = new();
    }
    public static Dictionary<string, Graph> Graphs() {
        Dictionary<string, Graph> graphs = new();
        Graph current = null;
        List<string> lines = File.ReadAllLines(Path.Combine("input/graphs.txt"), Encoding.ASCII).ToList();
        for (int i = 0; i < lines.Count; i++) {
            string line = lines[i];
            if (current == null) {
                if (line.Length == 0 || line.StartsWith("#"))
                    continue;
                string[] parts = line.Split(" ");
                current = new Graph(parts[1], int.Parse(parts[2]));
                continue;
            }
            if (line.Equals("END")) {
                current.edges.Sort((a, b) => a[0] != b[0] ? CompareInt(a[0], b[0]) : CompareInt(a[1], b[1]));
                if (current.invalid == null)
                    Greedy(current);
                graphs[current.name] = current;
                current = null;
                continue;
            }
            if (current.invalid != null)
                continue;
            string[] parts = line.Split(' ');
            string error = null;
            if (parts.Length != 2 || !CnfIo.Number(parts[0]) || !CnfIo.Number(parts[1]))
                error = "bad edge line";
            else {
                int a = int.Parse(parts[0]), b = int.Parse(parts[1]);
                if (a < 1 || a > current.vertices || b < 1 || b > current.vertices)
                    error = "vertex out of range";
                else if (a == b)
                    error = "self loop";
                else {
                    int first = Math.Min(a, b), second = Math.Max(a, b);
                    bool duplicate = false;
                    foreach (int[] edge in current.edges)
                        if (edge[0] == first && edge[1] == second)
                            duplicate = true;
                    if (duplicate)
                        error = "duplicate edge";
                    else
                        current.edges.Add(new int[] { first, second });
                }
            }
            if (error != null)
                current.invalid = error + " at line " + (i + 1);
        }
        return graphs;
    }
    public static void Greedy(Graph graph) {
        graph.degree = new int[graph.vertices + 1];
        foreach (int[] edge in graph.edges) {
            graph.degree[edge[0]]++;
            graph.degree[edge[1]]++;
        }
        int[] order = new int[graph.vertices];
        for (int i = 0; i < order.Length; i++)
            order[i] = i + 1;
        Array.Sort(order, Comparer<int>.Create((a, b) => graph.degree[a] != graph.degree[b]
                                                             ? graph.degree[b].CompareTo(graph.degree[a])
                                                             : a.CompareTo(b)));
        int[] colors = new int[graph.vertices + 1];
        foreach (int vertex in order) {
            HashSet<int> used = new();
            foreach (int[] edge in graph.edges) {
                if (edge[0] == vertex)
                    used.Add(colors[edge[1]]);
                if (edge[1] == vertex)
                    used.Add(colors[edge[0]]);
            }
            int color = 1;
            while (used.Contains(color))
                color++;
            colors[vertex] = color;
            graph.used = Math.Max(graph.used, color);
            graph.maximumDegree = Math.Max(graph.maximumDegree, graph.degree[vertex]);
        }
        graph.greedy = colors[1..colors.Length];
    }
    public static List<Job> Jobs() {
        List<Job> jobs = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input/jobs.txt"), Encoding.ASCII).ToList()) {
            if (line.Length == 0 || line.StartsWith("#"))
                continue;
            string[] parts = line.Split(" ");
            Job job = new Job();
            job.number = jobs.Count + 1;
            job.text = line;
            job.command = parts[0];
            job.arguments = parts[1..parts.Length];
            jobs.Add(job);
        }
        return jobs;
    }
    public static string Validate(Job job, Dictionary<string, Graph> graphs) {
        string[] types = ARGUMENTS.GetValueOrDefault(job.command);
        if (types == null)
            return "unknown command " + job.command;
        if (job.arguments.Length != types.Length)
            return "wrong argument count";
        for (int i = 0; i < types.Length; i++) {
            string token = job.arguments[i], type = types[i];
            if (type.Equals("file")) {
                if (!token.Matches("[a-z0-9_]{1,20}\\.cnf"))
                    return "bad file name " + token;
            } else if (type.Equals("graph")) {
                Graph graph = graphs.GetValueOrDefault(token);
                if (graph == null)
                    return "unknown graph " + token;
                if (graph.invalid != null)
                    return "invalid graph " + token + ": " + graph.invalid;
                job.graph = graph;
            } else {
                if (!CnfIo.Number(token))
                    return "bad number " + token;
                int value = int.Parse(token), maximum = type.Equals("small")   ? 8
                                                        : type.Equals("color") ? 6
                                                                               : 200;
                if (value < 1 || value > maximum)
                    return "out of range " + token;
            }
        }
        return null;
    }
    public static Solution Solve(CnfIo.Formula formula, int limit) {
        Solution solution = new Solution();
        solution.formula = formula;
        solution.preparation = Preprocess.Run(formula, limit == 1);
        if (solution.preparation.empty != 0) {
            solution.stop = "preprocess";
            return solution;
        }
        List<int[]> search = new(solution.preparation.clauses);
        while (solution.models.Count < limit) {
            solution.rounds++;
            Dpll.Result result = Dpll.Run(formula.variables, search);
            if (solution.rounds == 1)
                solution.trace = result.trace;
            solution.stats.Add(result.stats);
            if (result.model == null) {
                solution.stop = "all";
                break;
            }
            bool[] model = result.model;
            for (int x = 1; x <= formula.variables; x++)
                if (solution.preparation.fixedAssignment[x] != 0)
                    model[x] = solution.preparation.fixedAssignment[x] > 0;
            solution.models.Add(model);
            int[] blocking = new int[solution.preparation.active.Count];
            for (int i = 0; i < blocking.Length; i++) {
                int x = solution.preparation.active[i];
                blocking[i] = model[x] ? -x : x;
            }
            search.Add(blocking);
        }
        return solution;
    }
    public static void Core(Job job) {
        int count = job.formula.clauses.Count;
        bool[] retained = new bool[count];
        Array.Fill(retained, true);
        for (int i = 0; i < count; i++) {
            List<int[]> clauses = new();
            for (int j = 0; j < count; j++)
                if (retained[j] && j != i)
                    clauses.Add(job.formula.clauses[j]);
            Solution test = Solve(new CnfIo.Formula(job.formula.variables, clauses), 1);
            job.coreDecisions += test.stats.decisions;
            job.coreConflicts += test.stats.conflicts;
            if (test.models.Count == 0)
                retained[i] = false;
        }
        for (int i = 0; i < count; i++)
            if (retained[i])
                job.core.Add(i + 1);
    }
    public static void Execute(Job job) {
        if (job.command.Equals("CHROMATIC")) {
            int maximum = int.Parse(job.arguments[1]);
            for (int k = 1; k <= maximum; k++) {
                Solution solution = Solve(Encoders.Coloring(job.graph.vertices, job.graph.edges, k), 1);
                job.attempts.Add(new Attempt(k, solution));
                job.stats.Add(solution.stats);
                job.removed += solution.preparation.Removed();
                job.rounds += solution.rounds;
                job.solution = solution;
                job.formula = solution.formula;
                job.colors = k;
                if (solution.models.Count != 0)
                    break;
            }
            return;
        }
        int limit = 1;
        if (job.command.Equals("SOLVE") || job.command.Equals("ENUM") || job.command.Equals("CORE")) {
            job.formula = CnfIo.Read(job.arguments[0]);
            if (job.command.Equals("ENUM"))
                limit = int.Parse(job.arguments[1]);
        } else if (job.command.Equals("QUEENS")) {
            job.formula = Encoders.Queens(int.Parse(job.arguments[0]));
            limit = int.Parse(job.arguments[1]);
        } else if (job.command.Equals("PIGEON")) {
            job.formula = Encoders.Pigeon(int.Parse(job.arguments[0]), int.Parse(job.arguments[1]));
            limit = int.Parse(job.arguments[2]);
        } else {
            job.colors = int.Parse(job.arguments[1]);
            job.formula = Encoders.Coloring(job.graph.vertices, job.graph.edges, job.colors);
            limit = int.Parse(job.arguments[2]);
        }
        job.solution = Solve(job.formula, limit);
        job.stats = job.solution.stats;
        job.removed = job.solution.preparation.Removed();
        job.rounds = job.solution.rounds;
        if (job.command.Equals("CORE") && job.solution.models.Count == 0)
            Core(job);
    }
    public static bool TrueLiteral(bool[] model, int literal) {
        return literal > 0 ? model[literal] : !model[-literal];
    }
    public static bool ClauseTrue(bool[] model, int[] clause) {
        foreach (int literal in clause)
            if (TrueLiteral(model, literal))
                return true;
        return false;
    }
    public static bool Satisfies(bool[] model, List<int[]> clauses) {
        foreach (int[] clause in clauses)
            if (!ClauseTrue(model, clause))
                return false;
        return true;
    }
    public static List<string> Analysis(Solution solution, bool extended) {
        List<string> lines = new();
        if (solution.models.Count == 0)
            return lines;
        List<int[]> clauses = solution.formula.clauses;
        bool[] first = solution.models[0];
        int failureModel = 0, failureClause = 0;
        for (int i = 0; i < solution.models.Count && failureModel == 0; i++)
            for (int j = 0; j < clauses.Count; j++)
                if (!ClauseTrue(solution.models[i], clauses[j])) {
                    failureModel = i + 1;
                    failureClause = j + 1;
                    break;
                }
        List<int> distribution = new();
        foreach (int[] clause in clauses) {
            int count = 0;
            foreach (int literal in clause)
                if (TrueLiteral(first, literal))
                    count++;
            distribution.Add(count);
        }
        lines.Add(failureModel == 0 ? "verify ok models=" + solution.models.Count + " clauses=" +
                                          clauses.Count + " true_literals=" + Report.Frequency(distribution)
                                    : "verify failed model=" + failureModel + " clause=" + failureClause);
        List<int> safe = new();
        for (int x = 1; x < first.Length; x++) {
            bool[] flipped = first.ToArray();
            flipped[x] = !flipped[x];
            if (Satisfies(flipped, clauses))
                safe.Add(x);
        }
        lines.Add("flips safe=" + safe.Count + " variables=" + Report.Numbers(safe));
        if (extended && solution.models.Count >= 2) {
            int pairs = 0, minimum = int.MaxValue, maximum = 0;
            for (int i = 0; i < solution.models.Count; i++)
                for (int j = i + 1; j < solution.models.Count; j++) {
                    int distance = 0;
                    for (int x = 1; x < first.Length; x++)
                        if (solution.models[i][x] != solution.models[j][x])
                            distance++;
                    pairs++;
                    minimum = Math.Min(minimum, distance);
                    maximum = Math.Max(maximum, distance);
                }
            lines.Add("diversity pairs=" + pairs + " min_distance=" + minimum + " max_distance=" + maximum);
        }
        if (extended && solution.stop.Equals("all")) {
            List<int> backbone = new();
            for (int x = 1; x < first.Length; x++) {
                bool same = true;
                foreach (bool[] model in solution.models)
                    if (model[x] != first[x])
                        same = false;
                if (same)
                    backbone.Add(first[x] ? x : -x);
            }
            lines.Add("backbone size=" + backbone.Count + " literals=" + Report.Numbers(backbone));
        }
        return lines;
    }
    public static List<int> Lengths(List<int[]> clauses) {
        List<int> lengths = new();
        foreach (int[] clause in clauses)
            lengths.Add(clause.Length);
        return lengths;
    }
    public static int Literals(List<int[]> clauses) {
        int total = 0;
        foreach (int[] clause in clauses)
            total += clause.Length;
        return total;
    }
    public static string Heading(Job job) {
        return "JOB " + job.number + " " + job.text;
    }
    public static string GraphLine(Graph graph) {
        return "graph vertices=" + graph.vertices + " edges=" + graph.edges.Count +
               " max_degree=" + graph.maximumDegree + " greedy=" + graph.used;
    }
    public static List<int> Sorted(List<int> values) {
        List<int> sorted = new(values);
        Collections.Sort(sorted);
        return sorted;
    }
    public static List<string> ResultLines(Job job) {
        List<string> lines = new([Heading(job)]);
        if (job.error != null) {
            lines.Add("error " + job.error);
            return lines;
        }
        Solution solution = job.solution;
        if (job.command.Equals("CHROMATIC")) {
            lines.Add(GraphLine(job.graph));
            foreach (Attempt attempt in job.attempts) {
                Solution result = attempt.solution;
                lines.Add("attempt k=" + attempt.colors + " clauses=" + result.formula.clauses.Count +
                          " removed=" + result.preparation.Removed() + " result=" + result.Status() +
                          " stop=" + result.stop + " " + Report.Search(result.stats));
            }
            lines.Add("result " + solution.Status() +
                      " chromatic=" + (solution.models.Count == 0 ? "-" : Convert.ToString(job.colors)) +
                      " attempts=" + job.attempts.Count);
            lines.Add("search " + Report.Search(job.stats));
            lines.AddRange(Analysis(solution, false));
            return lines;
        }
        if (job.command.Equals("COLOR"))
            lines.Add(GraphLine(job.graph));
        CnfIo.Formula formula = job.formula;
        Preprocess.Result p = solution.preparation;
        bool pure = job.command.Equals("SOLVE") || job.command.Equals("CORE") ||
                    job.command.Equals("ENUM") && int.Parse(job.arguments[1]) == 1 ||
                    (job.command.Equals("QUEENS") && int.Parse(job.arguments[1]) == 1) ||
                    ((job.command.Equals("PIGEON") || job.command.Equals("COLOR")) &&
                     int.Parse(job.arguments[2]) == 1);
        lines.Add("formula variables=" + formula.variables + " clauses=" + formula.clauses.Count +
                  " literals=" + Literals(formula.clauses) +
                  " lengths=" + Report.Frequency(Lengths(formula.clauses)));
        lines.Add("preprocess pure=" + (pure ? "on" : "off") + " tautologies=" + p.tautologies +
                  " duplicate_literals=" + p.duplicateLiterals + " unit_fixed=" + p.unitFixed +
                  " unit_removed=" + p.unit.Count + " subsumed=" + p.subsumed.Count +
                  " pure_fixed=" + p.pureFixed + " pure_removed=" + p.pure.Count + " removed=" + p.Removed());
        lines.Add("removed_clauses tautology=" + Report.Numbers(Sorted(p.tautology)) + " unit=" +
                  Report.Numbers(Sorted(p.unit)) + " subsumed=" + Report.Numbers(Sorted(p.subsumed)) +
                  " pure=" + Report.Numbers(Sorted(p.pure)));
        if (p.empty != 0)
            lines.Add("simplified empty_clause=" + p.empty);
        else {
            List<int> fixedAssignment = new();
            for (int x = 1; x < p.fixedAssignment.Length; x++)
                if (p.fixedAssignment[x] != 0)
                    fixedAssignment.Add(p.fixedAssignment[x] > 0 ? x : -x);
            lines.Add("simplified clauses=" + p.clauses.Count + " literals=" + Literals(p.clauses) +
                      " lengths=" + Report.Frequency(Lengths(p.clauses)) + " fixed=" + fixedAssignment.Count +
                      " active=" + p.active.Count);
            lines.Add("fixed literals=" + Report.Numbers(fixedAssignment));
        }
        lines.Add("result " + solution.Status() + " models=" + solution.models.Count +
                  " rounds=" + solution.rounds + " stop=" + solution.stop);
        lines.Add("search " + Report.Search(solution.stats));
        if (solution.rounds > 0)
            lines.Add("trace " +
                      (solution.trace.Count == 0
                           ? "-"
                           : string.Join(
                                 " ", solution.trace.GetRange(0, Math.Min(12, solution.trace.Count) - (0))) +
                                 (solution.trace.Count > 12 ? " +" + (solution.trace.Count - 12) : "")));
        lines.AddRange(Analysis(solution, true));
        if (job.command.Equals("CORE") && solution.models.Count == 0)
            lines.Add("core size=" + job.core.Count + " decisions=" + job.coreDecisions +
                      " conflicts=" + job.coreConflicts + " clauses=" + Report.Numbers(job.core));
        return lines;
    }
    public static int Compare(int[] first, int[] second) {
        for (int i = 0; i < first.Length; i++)
            if (first[i] != second[i])
                return CompareInt(first[i], second[i]);
        return 0;
    }
    public sealed record Symmetry(int[] canonical, int orbit);
    public static Symmetry QueenSymmetry(int[] positions) {
        int n = positions.Length;
        int[][] boards = Enumerable.Range(0, 8)
                             .Select(
                                 _ => new int[n])
                             .ToArray();
        for (int i = 0; i < n; i++) {
            int r = i + 1, c = positions[i];
            int[][] mapped = [
                [r, c], [c, n + 1 - r], [n + 1 - r, n + 1 - c], [n + 1 - c, r], [r, n + 1 - c],
                [n + 1 - r, c], [c, r], [n + 1 - c, n + 1 - r]
            ];
            for (int j = 0; j < 8; j++)
                boards[j][mapped[j][0] - 1] = mapped[j][1];
        }
        int[] canonical = boards[0];
        HashSet<string> distinct = new();
        foreach (int[] board in boards) {
            distinct.Add(Report.Numbers(board));
            if (Compare(board, canonical) < 0)
                canonical = board;
        }
        return new Symmetry(canonical, distinct.Count);
    }
    public static int[] ColorCanonical(int[] colors) {
        Dictionary<int, int> numbers = new();
        int[] result = new int[colors.Length];
        for (int i = 0; i < colors.Length; i++) {
            if (!numbers.ContainsKey(colors[i]))
                numbers[colors[i]] = numbers.Count + 1;
            result[i] = numbers[colors[i]];
        }
        return result;
    }
    public sealed class ClassInfo {
        public int[] canonical;
        public int orbit, found, first;
        public ClassInfo(int[] canonical, int orbit, int first) {
            this.canonical = canonical;
            this.orbit = orbit;
            this.first = first;
        }
    }
    public static List<string> BoardLines(Job job) {
        List<string> lines = new();
        Solution solution = job.solution;
        List<ClassInfo> classes = new();
        Dictionary<string, int> classNumbers = new();
        if (job.command.Equals("QUEENS")) {
            int n = int.Parse(job.arguments[0]);
            lines.Add("QUEENS job=" + job.number + " n=" + n);
            for (int i = 0; i < solution.models.Count; i++) {
                int[] positions = Encoders.Positions(solution.models[i], n, n);
                Symmetry symmetry = QueenSymmetry(positions);
                string key = Report.Numbers(symmetry.canonical);
                bool first = !classNumbers.ContainsKey(key);
                if (first) {
                    classNumbers[key] = classes.Count + 1;
                    classes.Add(new ClassInfo(symmetry.canonical, symmetry.orbit, i + 1));
                }
                int number = classNumbers[key];
                classes[number - 1].found++;
                lines.Add("solution " + (i + 1) + " columns=" + Report.Numbers(positions) +
                          " class=" + number);
                if (first)
                    lines.AddRange(Report.Board(positions));
            }
            for (int i = 0; i < classes.Count; i++) {
                ClassInfo c = classes[i];
                lines.Add("class " + (i + 1) + " orbit=" + c.orbit + " found=" + c.found +
                          " first=" + c.first + " canonical=" + Report.Numbers(c.canonical));
            }
            lines.Add("summary solutions=" + solution.models.Count + " stop=" + solution.stop +
                      " classes=" + classes.Count);
        } else if (job.command.Equals("PIGEON")) {
            int pigeons = int.Parse(job.arguments[0]), holes = int.Parse(job.arguments[1]);
            lines.Add("PIGEON job=" + job.number + " pigeons=" + pigeons + " holes=" + holes);
            for (int i = 0; i < solution.models.Count; i++) {
                int[] positions = Encoders.Positions(solution.models[i], pigeons, holes);
                List<int> empty = new();
                for (int h = 1; h <= holes; h++) {
                    bool used = false;
                    foreach (int position in positions)
                        if (position == h)
                            used = true;
                    if (!used)
                        empty.Add(h);
                }
                lines.Add("assignment " + (i + 1) + " holes=" + Report.Numbers(positions) +
                          " empty=" + Report.Numbers(empty));
            }
            int expected = pigeons <= holes ? 1 : 0;
            if (pigeons <= holes)
                for (int i = 0; i < pigeons; i++)
                    expected *= holes - i;
            lines.Add("summary assignments=" + solution.models.Count + " stop=" + solution.stop +
                      " expected=" + expected);
        } else {
            Graph graph = job.graph;
            int colors = job.colors;
            lines.Add(job.command + " job=" + job.number + " graph=" + graph.name +
                      " vertices=" + graph.vertices + " edges=" + graph.edges.Count + " colors=" + colors);
            lines.Add("greedy used=" + graph.used + " colors=" + Report.Numbers(graph.greedy));
            for (int i = 0; i < solution.models.Count; i++) {
                int[] positions = Encoders.Positions(solution.models[i], graph.vertices, colors),
                      canonical = ColorCanonical(positions), sizes = new int[colors];
                HashSet<int> used = new();
                foreach (int color in positions) {
                    used.Add(color);
                    sizes[color - 1]++;
                }
                string key = Report.Numbers(canonical);
                if (!classNumbers.ContainsKey(key)) {
                    classNumbers[key] = classes.Count + 1;
                    classes.Add(new ClassInfo(canonical, 0, i + 1));
                }
                int number = classNumbers[key];
                classes[number - 1].found++;
                lines.Add("coloring " + (i + 1) + " colors=" + Report.Numbers(positions) +
                          " used=" + used.Count + " sizes=" + Report.Numbers(sizes) + " class=" + number);
            }
            for (int i = 0; i < classes.Count; i++) {
                ClassInfo c = classes[i];
                lines.Add("class " + (i + 1) + " found=" + c.found + " first=" + c.first +
                          " canonical=" + Report.Numbers(c.canonical));
            }
            lines.Add("summary colorings=" + solution.models.Count + " stop=" + solution.stop +
                      " classes=" + classes.Count);
        }
        return lines;
    }
    public static string Statistics(Job job) {
        return job.number + "," + job.command + "," + job.solution.Status() + "," + job.formula.variables +
               "," + job.formula.clauses.Count + "," + job.removed + "," + job.stats.decisions + "," +
               job.stats.propagations + "," + job.stats.conflicts + "," + job.stats.maxDepth + "," +
               job.solution.models.Count + "," + job.rounds;
    }
    public static List<string> Summary(List<Job> jobs) {
        int sat = 0, unsat = 0, errors = 0;
        int[] totals = new int[6];
        Dictionary<string, int[]> commands = new();
        Job hardest = null, deepest = null, busiest = null;
        foreach (Job job in jobs) {
            if (job.error != null) {
                errors++;
                continue;
            }
            bool satisfied = job.solution.models.Count != 0;
            if (satisfied)
                sat++;
            else
                unsat++;
            totals[0] += job.solution.models.Count;
            totals[1] += job.rounds;
            totals[2] += job.stats.decisions;
            totals[3] += job.stats.propagations;
            totals[4] += job.stats.conflicts;
            totals[5] += job.removed;
            int[] count = GetCounters(commands, job.command);
            count[0]++;
            count[satisfied ? 1 : 2]++;
            count[3] += job.stats.decisions;
            count[4] += job.stats.propagations;
            count[5] += job.stats.conflicts;
            if (hardest == null || job.stats.conflicts > hardest.stats.conflicts)
                hardest = job;
            if (deepest == null || job.stats.maxDepth > deepest.stats.maxDepth)
                deepest = job;
            if (busiest == null || job.stats.propagations > busiest.stats.propagations)
                busiest = job;
        }
        List<string> lines = new([
            "SUMMARY jobs=" + jobs.Count + " sat=" + sat + " unsat=" + unsat + " error=" + errors,
            "totals models=" + totals[0] + " rounds=" + totals[1] + " decisions=" + totals[2] +
                " propagations=" + totals[3] + " conflicts=" + totals[4] + " removed_clauses=" + totals[5]
        ]);
        foreach (string command in COMMANDS)
            if (commands.ContainsKey(command)) {
                int[] count = commands[command];
                lines.Add("command " + command + " jobs=" + count[0] + " sat=" + count[1] +
                          " unsat=" + count[2] + " decisions=" + count[3] + " propagations=" + count[4] +
                          " conflicts=" + count[5]);
            }
        if (hardest != null) {
            lines.Add("hardest job=" + hardest.number + " conflicts=" + hardest.stats.conflicts);
            lines.Add("deepest job=" + deepest.number + " max_depth=" + deepest.stats.maxDepth);
            lines.Add("busiest job=" + busiest.number + " propagations=" + busiest.stats.propagations);
        }
        return lines;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Dictionary<string, Graph> graphs = Graphs();
        List<Job> jobs = Jobs();
        List<string>
            results = new(),
            models = new(), boards = new(),
            stats = new([
                "job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"
            ]);
        foreach (Job job in jobs) {
            job.error = Validate(job, graphs);
            if (job.error == null)
                try {
                    Execute(job);
                } catch (CnfIo.Invalid error) {
                    job.error = error.getMessage();
                }
            Report.Paragraph(results, ResultLines(job));
            if (job.error != null)
                continue;
            stats.Add(Statistics(job));
            if (job.solution.models.Count != 0) {
                List<string> paragraph = new([Heading(job)]);
                for (int i = 0; i < job.solution.models.Count; i++) {
                    paragraph.Add("model " + (i + 1));
                    paragraph.AddRange(CnfIo.ModelLines(job.solution.models[i]));
                }
                Report.Paragraph(models, paragraph);
            }
            if (new HashSet<string> { "QUEENS", "PIGEON", "COLOR", "CHROMATIC" }.Contains(job.command))
                Report.Paragraph(boards, BoardLines(job));
        }
        Report.Paragraph(results, Summary(jobs));
        Directory.CreateDirectory(Path.Combine("output"));
        Report.Write("results.txt", results);
        Report.Write("models.txt", models);
        Report.Write("boards.txt", boards);
        Report.Write("stats.csv", stats);
    }
}
