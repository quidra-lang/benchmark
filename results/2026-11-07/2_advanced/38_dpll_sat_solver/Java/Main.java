import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
public final class Main {
    static final String[] COMMANDS = {"SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC"};
    static final Map<String, String[]> ARGUMENTS = Map.of(
        "SOLVE", new String[] {"file"}, "ENUM", new String[] {"file", "limit"}, "CORE", new String[] {"file"},
        "QUEENS", new String[] {"small", "limit"}, "PIGEON", new String[] {"small", "small", "limit"},
        "COLOR", new String[] {"graph", "color", "limit"}, "CHROMATIC", new String[] {"graph", "color"});
    static final class Graph {
        String name, invalid;
        int vertices, maximumDegree, used;
        final List<int[]> edges = new ArrayList<>();
        int[] degree, greedy;
        Graph(String name, int vertices) {
            this.name = name;
            this.vertices = vertices;
        }
    }
    static final class Solution {
        CnfIo.Formula formula;
        Preprocess.Result preparation;
        final List<boolean[]> models = new ArrayList<>();
        final Dpll.Stats stats = new Dpll.Stats();
        List<String> trace = new ArrayList<>();
        int rounds;
        String stop = "limit";
        String status() {
            return models.isEmpty() ? "UNSAT" : "SAT";
        }
    }
    record Attempt(int colors, Solution solution) {}
    static final class Job {
        int number, removed, rounds, colors, coreDecisions, coreConflicts;
        String text, command, error;
        String[] arguments;
        Graph graph;
        CnfIo.Formula formula;
        Solution solution;
        Dpll.Stats stats = new Dpll.Stats();
        final List<Attempt> attempts = new ArrayList<>();
        List<Integer> core = new ArrayList<>();
    }
    static Map<String, Graph> graphs() throws IOException {
        Map<String, Graph> graphs = new HashMap<>();
        Graph current = null;
        List<String> lines = Files.readAllLines(Path.of("input/graphs.txt"), StandardCharsets.US_ASCII);
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            if (current == null) {
                if (line.isEmpty() || line.startsWith("#"))
                    continue;
                String[] parts = line.split(" ");
                current = new Graph(parts[1], Integer.parseInt(parts[2]));
                continue;
            }
            if (line.equals("END")) {
                current.edges.sort(
                    (a, b) -> a[0] != b[0] ? Integer.compare(a[0], b[0]) : Integer.compare(a[1], b[1]));
                if (current.invalid == null)
                    greedy(current);
                graphs.put(current.name, current);
                current = null;
                continue;
            }
            if (current.invalid != null)
                continue;
            String[] parts = line.split(" ", -1);
            String error = null;
            if (parts.length != 2 || !CnfIo.number(parts[0]) || !CnfIo.number(parts[1]))
                error = "bad edge line";
            else {
                int a = Integer.parseInt(parts[0]), b = Integer.parseInt(parts[1]);
                if (a < 1 || a > current.vertices || b < 1 || b > current.vertices)
                    error = "vertex out of range";
                else if (a == b)
                    error = "self loop";
                else {
                    int first = Math.min(a, b), second = Math.max(a, b);
                    boolean duplicate = false;
                    for (int[] edge : current.edges)
                        if (edge[0] == first && edge[1] == second)
                            duplicate = true;
                    if (duplicate)
                        error = "duplicate edge";
                    else
                        current.edges.add(new int[] {first, second});
                }
            }
            if (error != null)
                current.invalid = error + " at line " + (i + 1);
        }
        return graphs;
    }
    static void greedy(Graph graph) {
        graph.degree = new int[graph.vertices + 1];
        for (int[] edge : graph.edges) {
            graph.degree[edge[0]]++;
            graph.degree[edge[1]]++;
        }
        Integer[] order = new Integer[graph.vertices];
        for (int i = 0; i < order.length; i++)
            order[i] = i + 1;
        Arrays.sort(
            order,
            Comparator.<Integer>comparingInt(x -> graph.degree[x]).reversed().thenComparingInt(x -> x));
        int[] colors = new int[graph.vertices + 1];
        for (int vertex : order) {
            Set<Integer> used = new HashSet<>();
            for (int[] edge : graph.edges) {
                if (edge[0] == vertex)
                    used.add(colors[edge[1]]);
                if (edge[1] == vertex)
                    used.add(colors[edge[0]]);
            }
            int color = 1;
            while (used.contains(color))
                color++;
            colors[vertex] = color;
            graph.used = Math.max(graph.used, color);
            graph.maximumDegree = Math.max(graph.maximumDegree, graph.degree[vertex]);
        }
        graph.greedy = Arrays.copyOfRange(colors, 1, colors.length);
    }
    static List<Job> jobs() throws IOException {
        List<Job> jobs = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input/jobs.txt"), StandardCharsets.US_ASCII)) {
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            String[] parts = line.split(" ");
            Job job = new Job();
            job.number = jobs.size() + 1;
            job.text = line;
            job.command = parts[0];
            job.arguments = Arrays.copyOfRange(parts, 1, parts.length);
            jobs.add(job);
        }
        return jobs;
    }
    static String validate(Job job, Map<String, Graph> graphs) {
        String[] types = ARGUMENTS.get(job.command);
        if (types == null)
            return "unknown command " + job.command;
        if (job.arguments.length != types.length)
            return "wrong argument count";
        for (int i = 0; i < types.length; i++) {
            String token = job.arguments[i], type = types[i];
            if (type.equals("file")) {
                if (!token.matches("[a-z0-9_]{1,20}\\.cnf"))
                    return "bad file name " + token;
            } else if (type.equals("graph")) {
                Graph graph = graphs.get(token);
                if (graph == null)
                    return "unknown graph " + token;
                if (graph.invalid != null)
                    return "invalid graph " + token + ": " + graph.invalid;
                job.graph = graph;
            } else {
                if (!CnfIo.number(token))
                    return "bad number " + token;
                int value = Integer.parseInt(token), maximum = type.equals("small")   ? 8
                                                               : type.equals("color") ? 6
                                                                                      : 200;
                if (value < 1 || value > maximum)
                    return "out of range " + token;
            }
        }
        return null;
    }
    static Solution solve(CnfIo.Formula formula, int limit) {
        Solution solution = new Solution();
        solution.formula = formula;
        solution.preparation = Preprocess.run(formula, limit == 1);
        if (solution.preparation.empty != 0) {
            solution.stop = "preprocess";
            return solution;
        }
        List<int[]> search = new ArrayList<>(solution.preparation.clauses);
        while (solution.models.size() < limit) {
            solution.rounds++;
            Dpll.Result result = Dpll.run(formula.variables(), search);
            if (solution.rounds == 1)
                solution.trace = result.trace();
            solution.stats.add(result.stats());
            if (result.model() == null) {
                solution.stop = "all";
                break;
            }
            boolean[] model = result.model();
            for (int x = 1; x <= formula.variables(); x++)
                if (solution.preparation.fixed[x] != 0)
                    model[x] = solution.preparation.fixed[x] > 0;
            solution.models.add(model);
            int[] blocking = new int[solution.preparation.active.size()];
            for (int i = 0; i < blocking.length; i++) {
                int x = solution.preparation.active.get(i);
                blocking[i] = model[x] ? -x : x;
            }
            search.add(blocking);
        }
        return solution;
    }
    static void core(Job job) {
        int count = job.formula.clauses().size();
        boolean[] retained = new boolean[count];
        Arrays.fill(retained, true);
        for (int i = 0; i < count; i++) {
            List<int[]> clauses = new ArrayList<>();
            for (int j = 0; j < count; j++)
                if (retained[j] && j != i)
                    clauses.add(job.formula.clauses().get(j));
            Solution test = solve(new CnfIo.Formula(job.formula.variables(), clauses), 1);
            job.coreDecisions += test.stats.decisions;
            job.coreConflicts += test.stats.conflicts;
            if (test.models.isEmpty())
                retained[i] = false;
        }
        for (int i = 0; i < count; i++)
            if (retained[i])
                job.core.add(i + 1);
    }
    static void execute(Job job) throws IOException {
        if (job.command.equals("CHROMATIC")) {
            int maximum = Integer.parseInt(job.arguments[1]);
            for (int k = 1; k <= maximum; k++) {
                Solution solution = solve(Encoders.coloring(job.graph.vertices, job.graph.edges, k), 1);
                job.attempts.add(new Attempt(k, solution));
                job.stats.add(solution.stats);
                job.removed += solution.preparation.removed();
                job.rounds += solution.rounds;
                job.solution = solution;
                job.formula = solution.formula;
                job.colors = k;
                if (!solution.models.isEmpty())
                    break;
            }
            return;
        }
        int limit = 1;
        if (job.command.equals("SOLVE") || job.command.equals("ENUM") || job.command.equals("CORE")) {
            job.formula = CnfIo.read(job.arguments[0]);
            if (job.command.equals("ENUM"))
                limit = Integer.parseInt(job.arguments[1]);
        } else if (job.command.equals("QUEENS")) {
            job.formula = Encoders.queens(Integer.parseInt(job.arguments[0]));
            limit = Integer.parseInt(job.arguments[1]);
        } else if (job.command.equals("PIGEON")) {
            job.formula =
                Encoders.pigeon(Integer.parseInt(job.arguments[0]), Integer.parseInt(job.arguments[1]));
            limit = Integer.parseInt(job.arguments[2]);
        } else {
            job.colors = Integer.parseInt(job.arguments[1]);
            job.formula = Encoders.coloring(job.graph.vertices, job.graph.edges, job.colors);
            limit = Integer.parseInt(job.arguments[2]);
        }
        job.solution = solve(job.formula, limit);
        job.stats = job.solution.stats;
        job.removed = job.solution.preparation.removed();
        job.rounds = job.solution.rounds;
        if (job.command.equals("CORE") && job.solution.models.isEmpty())
            core(job);
    }
    static boolean trueLiteral(boolean[] model, int literal) {
        return literal > 0 ? model[literal] : !model[-literal];
    }
    static boolean clauseTrue(boolean[] model, int[] clause) {
        for (int literal : clause)
            if (trueLiteral(model, literal))
                return true;
        return false;
    }
    static boolean satisfies(boolean[] model, List<int[]> clauses) {
        for (int[] clause : clauses)
            if (!clauseTrue(model, clause))
                return false;
        return true;
    }
    static List<String> analysis(Solution solution, boolean extended) {
        List<String> lines = new ArrayList<>();
        if (solution.models.isEmpty())
            return lines;
        List<int[]> clauses = solution.formula.clauses();
        boolean[] first = solution.models.getFirst();
        int failureModel = 0, failureClause = 0;
        for (int i = 0; i < solution.models.size() && failureModel == 0; i++)
            for (int j = 0; j < clauses.size(); j++)
                if (!clauseTrue(solution.models.get(i), clauses.get(j))) {
                    failureModel = i + 1;
                    failureClause = j + 1;
                    break;
                }
        List<Integer> distribution = new ArrayList<>();
        for (int[] clause : clauses) {
            int count = 0;
            for (int literal : clause)
                if (trueLiteral(first, literal))
                    count++;
            distribution.add(count);
        }
        lines.add(failureModel == 0 ? "verify ok models=" + solution.models.size() + " clauses=" +
                                          clauses.size() + " true_literals=" + Report.frequency(distribution)
                                    : "verify failed model=" + failureModel + " clause=" + failureClause);
        List<Integer> safe = new ArrayList<>();
        for (int x = 1; x < first.length; x++) {
            boolean[] flipped = first.clone();
            flipped[x] = !flipped[x];
            if (satisfies(flipped, clauses))
                safe.add(x);
        }
        lines.add("flips safe=" + safe.size() + " variables=" + Report.numbers(safe));
        if (extended && solution.models.size() >= 2) {
            int pairs = 0, minimum = Integer.MAX_VALUE, maximum = 0;
            for (int i = 0; i < solution.models.size(); i++)
                for (int j = i + 1; j < solution.models.size(); j++) {
                    int distance = 0;
                    for (int x = 1; x < first.length; x++)
                        if (solution.models.get(i)[x] != solution.models.get(j)[x])
                            distance++;
                    pairs++;
                    minimum = Math.min(minimum, distance);
                    maximum = Math.max(maximum, distance);
                }
            lines.add("diversity pairs=" + pairs + " min_distance=" + minimum + " max_distance=" + maximum);
        }
        if (extended && solution.stop.equals("all")) {
            List<Integer> backbone = new ArrayList<>();
            for (int x = 1; x < first.length; x++) {
                boolean same = true;
                for (boolean[] model : solution.models)
                    if (model[x] != first[x])
                        same = false;
                if (same)
                    backbone.add(first[x] ? x : -x);
            }
            lines.add("backbone size=" + backbone.size() + " literals=" + Report.numbers(backbone));
        }
        return lines;
    }
    static List<Integer> lengths(List<int[]> clauses) {
        List<Integer> lengths = new ArrayList<>();
        for (int[] clause : clauses)
            lengths.add(clause.length);
        return lengths;
    }
    static int literals(List<int[]> clauses) {
        int total = 0;
        for (int[] clause : clauses)
            total += clause.length;
        return total;
    }
    static String heading(Job job) {
        return "JOB " + job.number + " " + job.text;
    }
    static String graphLine(Graph graph) {
        return "graph vertices=" + graph.vertices + " edges=" + graph.edges.size() +
            " max_degree=" + graph.maximumDegree + " greedy=" + graph.used;
    }
    static List<Integer> sorted(List<Integer> values) {
        List<Integer> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        return sorted;
    }
    static List<String> resultLines(Job job) {
        List<String> lines = new ArrayList<>(List.of(heading(job)));
        if (job.error != null) {
            lines.add("error " + job.error);
            return lines;
        }
        Solution solution = job.solution;
        if (job.command.equals("CHROMATIC")) {
            lines.add(graphLine(job.graph));
            for (Attempt attempt : job.attempts) {
                Solution result = attempt.solution;
                lines.add("attempt k=" + attempt.colors + " clauses=" + result.formula.clauses().size() +
                          " removed=" + result.preparation.removed() + " result=" + result.status() +
                          " stop=" + result.stop + " " + Report.search(result.stats));
            }
            lines.add("result " + solution.status() +
                      " chromatic=" + (solution.models.isEmpty() ? "-" : Integer.toString(job.colors)) +
                      " attempts=" + job.attempts.size());
            lines.add("search " + Report.search(job.stats));
            lines.addAll(analysis(solution, false));
            return lines;
        }
        if (job.command.equals("COLOR"))
            lines.add(graphLine(job.graph));
        CnfIo.Formula formula = job.formula;
        Preprocess.Result p = solution.preparation;
        boolean pure = job.command.equals("SOLVE") || job.command.equals("CORE") ||
                       job.command.equals("ENUM") && Integer.parseInt(job.arguments[1]) == 1 ||
                       (job.command.equals("QUEENS") && Integer.parseInt(job.arguments[1]) == 1) ||
                       ((job.command.equals("PIGEON") || job.command.equals("COLOR")) &&
                        Integer.parseInt(job.arguments[2]) == 1);
        lines.add("formula variables=" + formula.variables() + " clauses=" + formula.clauses().size() +
                  " literals=" + literals(formula.clauses()) +
                  " lengths=" + Report.frequency(lengths(formula.clauses())));
        lines.add("preprocess pure=" + (pure ? "on" : "off") + " tautologies=" + p.tautologies +
                  " duplicate_literals=" + p.duplicateLiterals + " unit_fixed=" + p.unitFixed +
                  " unit_removed=" + p.unit.size() + " subsumed=" + p.subsumed.size() + " pure_fixed=" +
                  p.pureFixed + " pure_removed=" + p.pure.size() + " removed=" + p.removed());
        lines.add("removed_clauses tautology=" + Report.numbers(sorted(p.tautology)) + " unit=" +
                  Report.numbers(sorted(p.unit)) + " subsumed=" + Report.numbers(sorted(p.subsumed)) +
                  " pure=" + Report.numbers(sorted(p.pure)));
        if (p.empty != 0)
            lines.add("simplified empty_clause=" + p.empty);
        else {
            List<Integer> fixed = new ArrayList<>();
            for (int x = 1; x < p.fixed.length; x++)
                if (p.fixed[x] != 0)
                    fixed.add(p.fixed[x] > 0 ? x : -x);
            lines.add("simplified clauses=" + p.clauses.size() + " literals=" + literals(p.clauses) +
                      " lengths=" + Report.frequency(lengths(p.clauses)) + " fixed=" + fixed.size() +
                      " active=" + p.active.size());
            lines.add("fixed literals=" + Report.numbers(fixed));
        }
        lines.add("result " + solution.status() + " models=" + solution.models.size() +
                  " rounds=" + solution.rounds + " stop=" + solution.stop);
        lines.add("search " + Report.search(solution.stats));
        if (solution.rounds > 0)
            lines.add(
                "trace " +
                (solution.trace.isEmpty()
                     ? "-"
                     : String.join(" ", solution.trace.subList(0, Math.min(12, solution.trace.size()))) +
                           (solution.trace.size() > 12 ? " +" + (solution.trace.size() - 12) : "")));
        lines.addAll(analysis(solution, true));
        if (job.command.equals("CORE") && solution.models.isEmpty())
            lines.add("core size=" + job.core.size() + " decisions=" + job.coreDecisions +
                      " conflicts=" + job.coreConflicts + " clauses=" + Report.numbers(job.core));
        return lines;
    }
    static int compare(int[] first, int[] second) {
        for (int i = 0; i < first.length; i++)
            if (first[i] != second[i])
                return Integer.compare(first[i], second[i]);
        return 0;
    }
    record Symmetry(int[] canonical, int orbit) {}
    static Symmetry queenSymmetry(int[] positions) {
        int n = positions.length;
        int[][] boards = new int[8][n];
        for (int i = 0; i < n; i++) {
            int r = i + 1, c = positions[i];
            int[][] mapped = {{r, c},         {c, n + 1 - r},        {n + 1 - r, n + 1 - c},
                              {n + 1 - c, r}, {r, n + 1 - c},        {n + 1 - r, c},
                              {c, r},         {n + 1 - c, n + 1 - r}};
            for (int j = 0; j < 8; j++)
                boards[j][mapped[j][0] - 1] = mapped[j][1];
        }
        int[] canonical = boards[0];
        Set<String> distinct = new HashSet<>();
        for (int[] board : boards) {
            distinct.add(Report.numbers(board));
            if (compare(board, canonical) < 0)
                canonical = board;
        }
        return new Symmetry(canonical, distinct.size());
    }
    static int[] colorCanonical(int[] colors) {
        Map<Integer, Integer> numbers = new HashMap<>();
        int[] result = new int[colors.length];
        for (int i = 0; i < colors.length; i++) {
            if (!numbers.containsKey(colors[i]))
                numbers.put(colors[i], numbers.size() + 1);
            result[i] = numbers.get(colors[i]);
        }
        return result;
    }
    static final class ClassInfo {
        int[] canonical;
        int orbit, found, first;
        ClassInfo(int[] canonical, int orbit, int first) {
            this.canonical = canonical;
            this.orbit = orbit;
            this.first = first;
        }
    }
    static List<String> boardLines(Job job) {
        List<String> lines = new ArrayList<>();
        Solution solution = job.solution;
        List<ClassInfo> classes = new ArrayList<>();
        Map<String, Integer> classNumbers = new HashMap<>();
        if (job.command.equals("QUEENS")) {
            int n = Integer.parseInt(job.arguments[0]);
            lines.add("QUEENS job=" + job.number + " n=" + n);
            for (int i = 0; i < solution.models.size(); i++) {
                int[] positions = Encoders.positions(solution.models.get(i), n, n);
                Symmetry symmetry = queenSymmetry(positions);
                String key = Report.numbers(symmetry.canonical);
                boolean first = !classNumbers.containsKey(key);
                if (first) {
                    classNumbers.put(key, classes.size() + 1);
                    classes.add(new ClassInfo(symmetry.canonical, symmetry.orbit, i + 1));
                }
                int number = classNumbers.get(key);
                classes.get(number - 1).found++;
                lines.add("solution " + (i + 1) + " columns=" + Report.numbers(positions) +
                          " class=" + number);
                if (first)
                    lines.addAll(Report.board(positions));
            }
            for (int i = 0; i < classes.size(); i++) {
                ClassInfo c = classes.get(i);
                lines.add("class " + (i + 1) + " orbit=" + c.orbit + " found=" + c.found +
                          " first=" + c.first + " canonical=" + Report.numbers(c.canonical));
            }
            lines.add("summary solutions=" + solution.models.size() + " stop=" + solution.stop +
                      " classes=" + classes.size());
        } else if (job.command.equals("PIGEON")) {
            int pigeons = Integer.parseInt(job.arguments[0]), holes = Integer.parseInt(job.arguments[1]);
            lines.add("PIGEON job=" + job.number + " pigeons=" + pigeons + " holes=" + holes);
            for (int i = 0; i < solution.models.size(); i++) {
                int[] positions = Encoders.positions(solution.models.get(i), pigeons, holes);
                List<Integer> empty = new ArrayList<>();
                for (int h = 1; h <= holes; h++) {
                    boolean used = false;
                    for (int position : positions)
                        if (position == h)
                            used = true;
                    if (!used)
                        empty.add(h);
                }
                lines.add("assignment " + (i + 1) + " holes=" + Report.numbers(positions) +
                          " empty=" + Report.numbers(empty));
            }
            int expected = pigeons <= holes ? 1 : 0;
            if (pigeons <= holes)
                for (int i = 0; i < pigeons; i++)
                    expected *= holes - i;
            lines.add("summary assignments=" + solution.models.size() + " stop=" + solution.stop +
                      " expected=" + expected);
        } else {
            Graph graph = job.graph;
            int colors = job.colors;
            lines.add(job.command + " job=" + job.number + " graph=" + graph.name +
                      " vertices=" + graph.vertices + " edges=" + graph.edges.size() + " colors=" + colors);
            lines.add("greedy used=" + graph.used + " colors=" + Report.numbers(graph.greedy));
            for (int i = 0; i < solution.models.size(); i++) {
                int[] positions = Encoders.positions(solution.models.get(i), graph.vertices, colors),
                      canonical = colorCanonical(positions), sizes = new int[colors];
                Set<Integer> used = new HashSet<>();
                for (int color : positions) {
                    used.add(color);
                    sizes[color - 1]++;
                }
                String key = Report.numbers(canonical);
                if (!classNumbers.containsKey(key)) {
                    classNumbers.put(key, classes.size() + 1);
                    classes.add(new ClassInfo(canonical, 0, i + 1));
                }
                int number = classNumbers.get(key);
                classes.get(number - 1).found++;
                lines.add("coloring " + (i + 1) + " colors=" + Report.numbers(positions) +
                          " used=" + used.size() + " sizes=" + Report.numbers(sizes) + " class=" + number);
            }
            for (int i = 0; i < classes.size(); i++) {
                ClassInfo c = classes.get(i);
                lines.add("class " + (i + 1) + " found=" + c.found + " first=" + c.first +
                          " canonical=" + Report.numbers(c.canonical));
            }
            lines.add("summary colorings=" + solution.models.size() + " stop=" + solution.stop +
                      " classes=" + classes.size());
        }
        return lines;
    }
    static String statistics(Job job) {
        return job.number + "," + job.command + "," + job.solution.status() + "," + job.formula.variables() +
            "," + job.formula.clauses().size() + "," + job.removed + "," + job.stats.decisions + "," +
            job.stats.propagations + "," + job.stats.conflicts + "," + job.stats.maxDepth + "," +
            job.solution.models.size() + "," + job.rounds;
    }
    static List<String> summary(List<Job> jobs) {
        int sat = 0, unsat = 0, errors = 0;
        int[] totals = new int[6];
        Map<String, int[]> commands = new HashMap<>();
        Job hardest = null, deepest = null, busiest = null;
        for (Job job : jobs) {
            if (job.error != null) {
                errors++;
                continue;
            }
            boolean satisfied = !job.solution.models.isEmpty();
            if (satisfied)
                sat++;
            else
                unsat++;
            totals[0] += job.solution.models.size();
            totals[1] += job.rounds;
            totals[2] += job.stats.decisions;
            totals[3] += job.stats.propagations;
            totals[4] += job.stats.conflicts;
            totals[5] += job.removed;
            int[] count = commands.computeIfAbsent(job.command, key -> new int[6]);
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
        List<String> lines = new ArrayList<>(List.of(
            "SUMMARY jobs=" + jobs.size() + " sat=" + sat + " unsat=" + unsat + " error=" + errors,
            "totals models=" + totals[0] + " rounds=" + totals[1] + " decisions=" + totals[2] +
                " propagations=" + totals[3] + " conflicts=" + totals[4] + " removed_clauses=" + totals[5]));
        for (String command : COMMANDS)
            if (commands.containsKey(command)) {
                int[] count = commands.get(command);
                lines.add("command " + command + " jobs=" + count[0] + " sat=" + count[1] +
                          " unsat=" + count[2] + " decisions=" + count[3] + " propagations=" + count[4] +
                          " conflicts=" + count[5]);
            }
        if (hardest != null) {
            lines.add("hardest job=" + hardest.number + " conflicts=" + hardest.stats.conflicts);
            lines.add("deepest job=" + deepest.number + " max_depth=" + deepest.stats.maxDepth);
            lines.add("busiest job=" + busiest.number + " propagations=" + busiest.stats.propagations);
        }
        return lines;
    }
    public static void main(String[] args) throws IOException {
        Map<String, Graph> graphs = graphs();
        List<Job> jobs = jobs();
        List<String>
            results = new ArrayList<>(),
            models = new ArrayList<>(), boards = new ArrayList<>(),
            stats = new ArrayList<>(List.of(
                "job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"));
        for (Job job : jobs) {
            job.error = validate(job, graphs);
            if (job.error == null)
                try {
                    execute(job);
                } catch (CnfIo.Invalid error) {
                    job.error = error.getMessage();
                }
            Report.paragraph(results, resultLines(job));
            if (job.error != null)
                continue;
            stats.add(statistics(job));
            if (!job.solution.models.isEmpty()) {
                List<String> paragraph = new ArrayList<>(List.of(heading(job)));
                for (int i = 0; i < job.solution.models.size(); i++) {
                    paragraph.add("model " + (i + 1));
                    paragraph.addAll(CnfIo.modelLines(job.solution.models.get(i)));
                }
                Report.paragraph(models, paragraph);
            }
            if (Set.of("QUEENS", "PIGEON", "COLOR", "CHROMATIC").contains(job.command))
                Report.paragraph(boards, boardLines(job));
        }
        Report.paragraph(results, summary(jobs));
        Files.createDirectories(Path.of("output"));
        Report.write("results.txt", results);
        Report.write("models.txt", models);
        Report.write("boards.txt", boards);
        Report.write("stats.csv", stats);
    }
}
