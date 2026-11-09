import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static final List<String> CLASSES = List.of("cardinal", "semi_cardinal", "non_cardinal");
    record Definition(String solver, String function) {
        String name() { return solver + "-" + function; }
    }
    record Delay(int agent, int start, int duration) {}
    static final class Settings {
        int horizon, hlBudget, llBudget, window, step, frames;
        String animate;
        List<List<Integer>> orders = new ArrayList<>();
        List<Definition> runs = new ArrayList<>();
        List<Delay> delays = new ArrayList<>();
        Settings(int count) throws Exception {
            List<Integer> numberOrder = new ArrayList<>();
            for (int i = 0; i < count; i++)
                numberOrder.add(i);
            orders.add(numberOrder);
            for (String line :
                 Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
                String[] f = line.split(" ");
                switch (f[0]) {
                case "HORIZON":
                    horizon = Integer.parseInt(f[1]);
                    break;
                case "HL_BUDGET":
                    hlBudget = Integer.parseInt(f[1]);
                    break;
                case "LL_BUDGET":
                    llBudget = Integer.parseInt(f[1]);
                    break;
                case "WINDOW":
                    window = Integer.parseInt(f[1]);
                    step = Integer.parseInt(f[2]);
                    break;
                case "ORDER": {
                    List<Integer> order = new ArrayList<>();
                    for (int i = 1; i < f.length; i++)
                        order.add(Integer.parseInt(f[i]));
                    orders.add(order);
                    break;
                }
                case "RUN":
                    runs.add(new Definition(f[1], f[2]));
                    break;
                case "ANIMATE":
                    animate = f[1];
                    frames = Integer.parseInt(f[2]);
                    break;
                case "DELAY":
                    delays.add(new Delay(Integer.parseInt(f[1]), Integer.parseInt(f[2]),
                                         Integer.parseInt(f[3])));
                    break;
                }
            }
        }
    }
    record AgentInfo(int shortest, int states, int width) {}
    record Split(Cbs.Conflict conflict, String category) {}
    record PathStats(int cost, int extra, int waits, int turns, int arrive, int leave,
                     String actions) {}
    static final class Metrics {
        int soc, makespan, cost, sumExtra, maxExtra, waits, turns;
        String ratio;
        List<PathStats> agents = new ArrayList<>();
        List<Integer> arrivals = new ArrayList<>();
        Map<GridMap.Cell, Integer> traffic = new HashMap<>(), cellWaits = new HashMap<>();
        List<GridMap.Cell> hotspots;
    }
    record Validation(int start, int goal, int moves, int vertex, int edge, int follows,
                      List<Cbs.Conflict> conflicts) {
        String verdict() { return start + goal + moves + vertex + edge == 0 ? "VALID" : "INVALID"; }
    }
    record Step(int time, GridMap.Cell cell) {}
    record Prerequisite(int agent, int step) {}
    record Execution(Integer deadlock, int blocked, List<Integer> finish, int soc, int makespan) {}
    static final class Run {
        Definition definition;
        String status = "FAIL", reason, end;
        List<List<GridMap.Cell>> paths;
        int highLevel;
        Integer generated;
        LowLevel.Budget budget;
        List<String> specific = new ArrayList<>(), trace = new ArrayList<>();
        Metrics metrics;
        Validation validation;
        Execution execution;
        Run(Definition definition, int limit) {
            this.definition = definition;
            budget = new LowLevel.Budget(limit);
        }
        String name() { return definition.name(); }
    }
    static final class Planner {
        GridMap grid;
        List<GridMap.Agent> agents;
        Settings settings;
        List<Map<GridMap.Cell, Integer>> distances = new ArrayList<>();
        List<List<GridMap.Cell>> independent = new ArrayList<>();
        List<AgentInfo> info = new ArrayList<>();
        List<Cbs.Conflict> independentConflicts;
        Map<Cbs.Conflict, String> independentClasses = new HashMap<>();
        List<Run> results = new ArrayList<>();
        int socLower, makespanLower, components;
        int[] degrees = new int[4];
        List<String> groups = new ArrayList<>();
        Planner() throws Exception {
            grid = new GridMap();
            agents = GridMap.agents();
            settings = new Settings(agents.size());
            LowLevel.Budget budget = new LowLevel.Budget(null);
            for (GridMap.Agent agent : agents) {
                Map<GridMap.Cell, Integer> distance = grid.distances(agent.goal());
                distances.add(distance);
                independent.add(LowLevel
                                    .search(grid, agent, distance, agent.start(), 0,
                                            new LowLevel.Prohibitions(), settings.horizon, budget,
                                            false)
                                    .path());
            }
            overview();
        }
        List<Set<GridMap.Cell>> mdd(int id, int length, LowLevel.Prohibitions restrictions) {
            List<Set<GridMap.Cell>> layers = new ArrayList<>();
            layers.add(Set.of(agents.get(id).start()));
            for (int time = 1; time <= length; time++) {
                Set<GridMap.Cell> next = new HashSet<>();
                for (GridMap.Cell source : layers.getLast())
                    for (GridMap.Cell destination : grid.destinations(source))
                        if (time + distances.get(id).getOrDefault(destination, length + 1) <=
                                length &&
                            restrictions.actionAllowed(source, destination, time))
                            next.add(destination);
                layers.add(next);
            }
            List<Set<GridMap.Cell>> valid = new ArrayList<>();
            for (int time = 0; time <= length; time++)
                valid.add(new HashSet<>());
            valid.getLast().add(agents.get(id).goal());
            for (int time = length - 1; time >= 0; time--)
                for (GridMap.Cell source : layers.get(time))
                    for (GridMap.Cell destination : grid.destinations(source))
                        if (valid.get(time + 1).contains(destination) &&
                            restrictions.actionAllowed(source, destination, time + 1)) {
                            valid.get(time).add(source);
                            break;
                        }
            return valid;
        }
        String conflictClass(Cbs.Conflict conflict, List<List<GridMap.Cell>> paths,
                             List<LowLevel.Prohibitions> restrictions,
                             Map<Integer, List<Set<GridMap.Cell>>> cache) {
            int fixed = 0;
            for (int id : new int[] {conflict.a(), conflict.b()}) {
                int length = paths.get(id).size() - 1;
                List<Set<GridMap.Cell>> layers =
                    cache.computeIfAbsent(id, key -> mdd(id, length, restrictions.get(id)));
                int time = conflict.time();
                boolean forced = time > length || layers.get(time).size() == 1 &&
                                                      (conflict.kind().equals("vertex") ||
                                                       layers.get(time - 1).size() == 1);
                if (forced)
                    fixed++;
            }
            return CLASSES.get(2 - fixed);
        }
        List<LowLevel.Prohibitions> emptyRestrictions() {
            List<LowLevel.Prohibitions> restrictions = new ArrayList<>();
            for (int i = 0; i < agents.size(); i++)
                restrictions.add(new LowLevel.Prohibitions());
            return restrictions;
        }
        void overview() {
            for (GridMap.Cell cell : grid.free)
                degrees[Math.min(3, grid.neighbors(cell).size())]++;
            Set<GridMap.Cell> remaining = new HashSet<>(grid.free);
            while (!remaining.isEmpty()) {
                components++;
                Deque<GridMap.Cell> queue = new ArrayDeque<>();
                GridMap.Cell seed = remaining.iterator().next();
                remaining.remove(seed);
                queue.add(seed);
                while (!queue.isEmpty())
                    for (GridMap.Cell next : grid.neighbors(queue.remove()))
                        if (remaining.remove(next))
                            queue.add(next);
            }
            for (int id = 0; id < agents.size(); id++) {
                int shortest = distances.get(id).get(agents.get(id).start());
                List<Set<GridMap.Cell>> layers = mdd(id, shortest, new LowLevel.Prohibitions());
                int states = layers.stream().mapToInt(Set::size).sum(),
                    width = layers.stream().mapToInt(Set::size).max().orElse(0);
                info.add(new AgentInfo(shortest, states, width));
                socLower += shortest;
                makespanLower = Math.max(makespanLower, shortest);
            }
            independentConflicts = Cbs.conflicts(independent);
            List<LowLevel.Prohibitions> restrictions = emptyRestrictions();
            Map<Integer, List<Set<GridMap.Cell>>> cache = new HashMap<>();
            List<Set<Integer>> adjacent = new ArrayList<>();
            for (int i = 0; i < agents.size(); i++)
                adjacent.add(new TreeSet<>());
            for (Cbs.Conflict conflict : independentConflicts) {
                independentClasses.put(conflict,
                                       conflictClass(conflict, independent, restrictions, cache));
                adjacent.get(conflict.a()).add(conflict.b());
                adjacent.get(conflict.b()).add(conflict.a());
            }
            Set<Integer> seen = new HashSet<>();
            for (int start = 0; start < agents.size(); start++) {
                if (seen.contains(start) || adjacent.get(start).isEmpty())
                    continue;
                Set<Integer> component = new TreeSet<>();
                Deque<Integer> queue = new ArrayDeque<>();
                queue.add(start);
                seen.add(start);
                while (!queue.isEmpty()) {
                    int current = queue.remove();
                    component.add(current);
                    for (int next : adjacent.get(current))
                        if (seen.add(next))
                            queue.add(next);
                }
                StringBuilder names = new StringBuilder();
                for (int id : component)
                    names.append(Report.name(id));
                groups.add(names.toString());
            }
        }
        void solvePp(Run run) {
            int answer = 0;
            for (int index = 0; index < settings.orders.size(); index++) {
                int orderNumber = index + 1;
                List<Integer> order = settings.orders.get(index);
                run.highLevel++;
                int before = run.budget.expansions;
                Prioritized.Result result = Prioritized.tryOrder(
                    grid, agents, distances, settings.horizon, order, run.budget);
                for (Prioritized.Attempt attempt : result.attempts()) {
                    LowLevel.Search search = attempt.search();
                    String prefix =
                        "order " + orderNumber + " agent " + Report.name(attempt.agent());
                    run.trace.add(prefix +
                                  (search.path() == null ? " failed"
                                                         : " cost " + (search.path().size() - 1)) +
                                  " expansions " + search.expansions());
                }
                if (result.aborted()) {
                    run.reason = "ll_budget";
                    break;
                }
                StringBuilder names = new StringBuilder();
                for (int id : order)
                    names.append(Report.name(id));
                int planned = result.attempts().size() - (result.failed() == null ? 0 : 1);
                String summary = "order " + orderNumber + " " + names + " planned " + planned +
                                 " expansions " + (run.budget.expansions - before);
                if (result.failed() == null) {
                    run.specific.add(summary + " ok");
                    run.paths = result.paths();
                    run.status = "OK";
                    answer = orderNumber;
                    break;
                }
                run.specific.add(summary + " failed " + Report.name(result.failed()));
            }
            if (run.status.equals("OK"))
                run.end = "end OK order " + answer;
            else {
                if (run.reason == null)
                    run.reason = "orders";
                run.end = "end FAIL " + run.reason;
            }
        }
        List<LowLevel.Prohibitions> applyConstraint(List<LowLevel.Prohibitions> base,
                                                    Cbs.Constraint addition) {
            List<LowLevel.Prohibitions> copied = new ArrayList<>(base);
            LowLevel.Prohibitions changed = base.get(addition.agent()).copy();
            if (addition.kind().equals("vertex"))
                changed.states.add(new LowLevel.State(addition.v(), addition.time()));
            else
                changed.moves.add(new LowLevel.Move(addition.u(), addition.v(), addition.time()));
            copied.set(addition.agent(), changed);
            return copied;
        }
        Split chooseSplit(Cbs.Node node, Run run) {
            if (run.definition.solver().equals("CBS"))
                return new Split(node.conflicts.getFirst(), null);
            Map<Integer, List<Set<GridMap.Cell>>> cache = new HashMap<>();
            Cbs.Conflict best = null;
            String category = null;
            int earliest = 3;
            for (Cbs.Conflict conflict : node.conflicts) {
                String candidate = conflictClass(conflict, node.paths, node.constraints, cache);
                int rank = CLASSES.indexOf(candidate);
                if (rank < earliest) {
                    earliest = rank;
                    best = conflict;
                    category = candidate;
                }
            }
            return new Split(best, category);
        }
        void solveCbs(Run run) {
            List<LowLevel.Prohibitions> empty = emptyRestrictions();
            List<List<GridMap.Cell>> paths = new ArrayList<>();
            try {
                for (int id = 0; id < agents.size(); id++)
                    paths.add(LowLevel
                                  .search(grid, agents.get(id), distances.get(id),
                                          agents.get(id).start(), 0, empty.get(id),
                                          settings.horizon, run.budget, false)
                                  .path());
            } catch (LowLevel.BudgetExceeded exception) {
                run.reason = "ll_budget";
                run.generated = 0;
                run.specific.add("search expanded 0 generated 0 pruned 0 open 0");
                if (run.definition.solver().equals("ICBS"))
                    run.specific.add("classes cardinal 0 semi_cardinal 0 non_cardinal 0");
                run.end = "end FAIL ll_budget";
                return;
            }
            Cbs.Node root = new Cbs.Node(paths, empty, 0, 0, null, run.definition.function());
            PriorityQueue<Cbs.Node> open = new PriorityQueue<>(Cbs.ORDER);
            open.add(root);
            int generated = 1, expanded = 0, pruned = 0;
            int[] classifications = new int[3];
            String reason = "exhausted";
            Cbs.Node answer = null;
            while (!open.isEmpty()) {
                Cbs.Node node = open.remove();
                if (node.conflicts.isEmpty()) {
                    answer = node;
                    reason = null;
                    break;
                }
                if (expanded == settings.hlBudget) {
                    reason = "hl_budget";
                    break;
                }
                expanded++;
                Split split = chooseSplit(node, run);
                Cbs.Conflict conflict = split.conflict();
                if (split.category() != null)
                    classifications[CLASSES.indexOf(split.category())]++;
                List<String> created = new ArrayList<>();
                boolean aborted = false;
                for (Cbs.Constraint branch : Cbs.split(conflict)) {
                    int id = branch.agent();
                    List<LowLevel.Prohibitions> restrictions =
                        applyConstraint(node.constraints, branch);
                    LowLevel.Search search;
                    try {
                        search = LowLevel.search(grid, agents.get(id), distances.get(id),
                                                 agents.get(id).start(), 0, restrictions.get(id),
                                                 settings.horizon, run.budget, false);
                    } catch (LowLevel.BudgetExceeded exception) {
                        aborted = true;
                        break;
                    }
                    if (search.path() == null) {
                        pruned++;
                        created.add("-");
                        continue;
                    }
                    List<List<GridMap.Cell>> newPaths = new ArrayList<>(node.paths);
                    newPaths.set(id, search.path());
                    Cbs.Node child = new Cbs.Node(newPaths, restrictions, generated, node.depth + 1,
                                                  node.number, run.definition.function());
                    open.add(child);
                    created.add(Integer.toString(generated++));
                }
                if (aborted) {
                    reason = "ll_budget";
                    break;
                }
                String text = "expand " + expanded + " node " + node.number + " parent " +
                              (node.parent == null ? "-" : node.parent.toString()) + " depth " +
                              node.depth + " cost " + node.cost + " conflicts " +
                              node.conflicts.size() + " split " + Report.conflict(conflict);
                if (split.category() != null)
                    text += " class " + split.category();
                run.trace.add(text + " children " + created.get(0) + " " + created.get(1));
            }
            run.highLevel = expanded;
            run.generated = generated;
            run.specific.add("search expanded " + expanded + " generated " + generated +
                             " pruned " + pruned + " open " + open.size());
            if (run.definition.solver().equals("ICBS"))
                run.specific.add("classes cardinal " + classifications[0] + " semi_cardinal " +
                                 classifications[1] + " non_cardinal " + classifications[2]);
            if (answer == null) {
                run.reason = reason;
                run.end = "end FAIL " + reason;
                return;
            }
            run.status = "OK";
            run.paths = answer.paths;
            run.specific.add("solution node " + answer.number + " depth " + answer.depth);
            for (Cbs.Constraint c : Cbs.orderedConstraints(answer))
                run.specific.add("constraint " + Report.name(c.agent()) + " " + c.kind() + " " +
                                 c.u() + (c.kind().equals("vertex") ? "" : " " + c.v()) + " t " +
                                 c.time());
            run.end = "end OK node " + answer.number + " cost " + answer.cost;
        }
        void solveWhca(Run run) {
            List<GridMap.Cell> current = new ArrayList<>();
            List<List<GridMap.Cell>> executed = new ArrayList<>();
            for (GridMap.Agent agent : agents) {
                current.add(agent.start());
                executed.add(new ArrayList<>(List.of(agent.start())));
            }
            int time = 0, rounds = 0;
            String reason = null;
            while (true) {
                boolean complete = true;
                for (int id = 0; id < agents.size(); id++)
                    if (!current.get(id).equals(agents.get(id).goal()))
                        complete = false;
                if (complete)
                    break;
                if (time >= settings.horizon) {
                    reason = "timeout";
                    break;
                }
                rounds++;
                LowLevel.Prohibitions restrictions = new LowLevel.Prohibitions();
                List<Integer> order = new ArrayList<>();
                for (boolean atGoal : new boolean[] {false, true})
                    for (int id = 0; id < agents.size(); id++)
                        if (current.get(id).equals(agents.get(id).goal()) == atGoal)
                            order.add(id);
                Map<Integer, List<GridMap.Cell>> plans = new HashMap<>();
                boolean failed = false;
                for (int id : order) {
                    LowLevel.Search search;
                    try {
                        search = LowLevel.search(grid, agents.get(id), distances.get(id),
                                                 current.get(id), time, restrictions,
                                                 time + settings.window, run.budget, true);
                    } catch (LowLevel.BudgetExceeded exception) {
                        reason = "ll_budget";
                        failed = true;
                        break;
                    }
                    String prefix =
                        "round " + rounds + " time " + time + " agent " + Report.name(id);
                    if (search.path() == null) {
                        run.trace.add(prefix + " blocked expansions " + search.expansions());
                        reason = "blocked";
                        failed = true;
                        break;
                    }
                    List<GridMap.Cell> extended = new ArrayList<>(search.path());
                    while (extended.size() < settings.window + 1)
                        extended.add(extended.getLast());
                    plans.put(id, extended);
                    run.trace.add(prefix + " moves " + Report.actions(extended) + " expansions " +
                                  search.expansions());
                    LowLevel.reserve(restrictions, extended, time, false);
                }
                if (failed)
                    break;
                for (int id = 0; id < agents.size(); id++) {
                    executed.get(id).addAll(plans.get(id).subList(1, settings.step + 1));
                    current.set(id, plans.get(id).get(settings.step));
                }
                time += settings.step;
            }
            run.highLevel = rounds;
            run.specific.add("window " + settings.window + " step " + settings.step + " rounds " +
                             rounds);
            if (reason != null) {
                run.reason = reason;
                run.end = "end FAIL " + reason;
            } else {
                run.status = "OK";
                for (int id = 0; id < agents.size(); id++) {
                    List<GridMap.Cell> path = executed.get(id);
                    GridMap.Cell goal = agents.get(id).goal();
                    while (path.size() > 1 && path.getLast().equals(goal) &&
                           path.get(path.size() - 2).equals(goal))
                        path.removeLast();
                }
                run.paths = executed;
                run.end = "end OK rounds " + rounds;
            }
        }
        Validation validate(List<List<GridMap.Cell>> paths) {
            int start = 0, goal = 0, moves = 0;
            for (int id = 0; id < agents.size(); id++) {
                List<GridMap.Cell> path = paths.get(id);
                if (!path.getFirst().equals(agents.get(id).start()))
                    start++;
                if (!path.getLast().equals(agents.get(id).goal()))
                    goal++;
                for (int t = 1; t < path.size(); t++)
                    if (!grid.destinations(path.get(t - 1)).contains(path.get(t)))
                        moves++;
            }
            List<Cbs.Conflict> collisions = Cbs.conflicts(paths);
            int vertex = (int)collisions.stream().filter(c -> c.kind().equals("vertex")).count(),
                edge = collisions.size() - vertex, follows = 0;
            int horizon = Cbs.cost(paths, "MAKESPAN");
            for (int time = 1; time <= horizon; time++)
                for (int a = 0; a < paths.size(); a++) {
                    GridMap.Cell pastA = Cbs.position(paths.get(a), time - 1),
                                 nextA = Cbs.position(paths.get(a), time);
                    if (nextA.equals(pastA))
                        continue;
                    for (int b = 0; b < paths.size(); b++)
                        if (a != b && nextA.equals(Cbs.position(paths.get(b), time - 1)) &&
                            !Cbs.position(paths.get(b), time).equals(pastA))
                            follows++;
                }
            return new Validation(start, goal, moves, vertex, edge, follows, collisions);
        }
        PathStats pathStats(List<GridMap.Cell> path, int id) {
            int waits = 0, turns = 0, arrive = -1, leave = 0;
            char previous = 0;
            String actions = Report.actions(path);
            GridMap.Cell goal = agents.get(id).goal();
            for (int t = 0; t < path.size(); t++)
                if (path.get(t).equals(goal)) {
                    arrive = t;
                    break;
                }
            for (int t = 1; t < path.size(); t++) {
                char action = actions.charAt(t - 1);
                if (action == '.')
                    waits++;
                else {
                    if (previous != 0 && previous != action)
                        turns++;
                    previous = action;
                }
                if (path.get(t - 1).equals(goal) && !path.get(t).equals(goal))
                    leave++;
            }
            int cost = path.size() - 1;
            return new PathStats(cost, cost - info.get(id).shortest(), waits, turns, arrive, leave,
                                 actions);
        }
        Metrics metrics(List<List<GridMap.Cell>> paths, String function) {
            Metrics result = new Metrics();
            result.soc = Cbs.cost(paths, "SOC");
            result.makespan = Cbs.cost(paths, "MAKESPAN");
            result.cost = function.equals("SOC") ? result.soc : result.makespan;
            result.ratio =
                Report.fraction(result.cost, function.equals("SOC") ? socLower : makespanLower);
            for (int id = 0; id < agents.size(); id++) {
                List<GridMap.Cell> path = paths.get(id);
                PathStats stats = pathStats(path, id);
                result.agents.add(stats);
                result.sumExtra += stats.extra();
                result.maxExtra = Math.max(result.maxExtra, stats.extra());
                result.waits += stats.waits();
                result.turns += stats.turns();
                for (GridMap.Cell cell : new HashSet<>(path))
                    result.traffic.merge(cell, 1, Integer::sum);
                for (int t = 1; t < path.size(); t++)
                    if (path.get(t).equals(path.get(t - 1)))
                        result.cellWaits.merge(path.get(t), 1, Integer::sum);
            }
            for (int time = 0; time <= result.makespan; time++) {
                int arrived = 0;
                for (List<GridMap.Cell> path : paths)
                    if (path.size() - 1 <= time)
                        arrived++;
                result.arrivals.add(arrived);
            }
            result.hotspots = new ArrayList<>(result.traffic.keySet());
            result.hotspots.sort(
                Comparator.comparingInt((GridMap.Cell cell) -> - result.traffic.get(cell))
                    .thenComparingInt(GridMap.Cell::y)
                    .thenComparingInt(GridMap.Cell::x));
            if (result.hotspots.size() > 5)
                result.hotspots = new ArrayList<>(result.hotspots.subList(0, 5));
            return result;
        }
        Execution delayedExecution(List<List<GridMap.Cell>> paths) {
            List<List<Step>> steps = new ArrayList<>();
            for (List<GridMap.Cell> path : paths) {
                List<Step> entries = new ArrayList<>();
                entries.add(new Step(0, path.getFirst()));
                for (int time = 1; time < path.size(); time++)
                    if (!path.get(time).equals(path.get(time - 1)))
                        entries.add(new Step(time, path.get(time)));
                steps.add(entries);
            }
            List<List<List<Prerequisite>>> prerequisites = new ArrayList<>();
            for (int i = 0; i < paths.size(); i++) {
                List<List<Prerequisite>> requests = new ArrayList<>();
                for (Step target : steps.get(i)) {
                    List<Prerequisite> required = new ArrayList<>();
                    for (int j = 0; j < paths.size(); j++)
                        if (j != i)
                            for (int k = 0; k < steps.get(j).size(); k++) {
                                Step other = steps.get(j).get(k);
                                if (other.cell().equals(target.cell()) &&
                                    other.time() < target.time())
                                    required.add(new Prerequisite(j, k));
                            }
                    requests.add(required);
                }
                prerequisites.add(requests);
            }
            int[] progress = new int[paths.size()], finish = new int[paths.size()];
            int holds = 0, time = 0;
            while (true) {
                boolean complete = true;
                for (int i = 0; i < paths.size(); i++)
                    if (progress[i] < steps.get(i).size() - 1)
                        complete = false;
                if (complete)
                    break;
                List<Integer> advancing = new ArrayList<>();
                int stopped = 0;
                for (int i = 0; i < paths.size(); i++) {
                    if (progress[i] == steps.get(i).size() - 1)
                        continue;
                    boolean delayed = false;
                    for (Delay delay : settings.delays)
                        if (delay.agent() == i && delay.start() <= time &&
                            time < delay.start() + delay.duration())
                            delayed = true;
                    if (delayed) {
                        stopped++;
                        continue;
                    }
                    boolean allowed = true;
                    for (Prerequisite required : prerequisites.get(i).get(progress[i] + 1))
                        if (progress[required.agent()] <= required.step())
                            allowed = false;
                    if (allowed)
                        advancing.add(i);
                    else
                        holds++;
                }
                if (advancing.isEmpty() && stopped == 0)
                    return new Execution(time, holds, List.of(), 0, 0);
                for (int i : advancing) {
                    progress[i]++;
                    if (progress[i] == steps.get(i).size() - 1)
                        finish[i] = time + 1;
                }
                time++;
            }
            List<Integer> times = new ArrayList<>();
            int soc = 0, makespan = 0;
            for (int value : finish) {
                times.add(value);
                soc += value;
                makespan = Math.max(makespan, value);
            }
            return new Execution(null, holds, times, soc, makespan);
        }
        void solve() {
            for (Definition definition : settings.runs) {
                Run run = new Run(definition, settings.llBudget);
                switch (definition.solver()) {
                case "PP":
                    solvePp(run);
                    break;
                case "CBS":
                case "ICBS":
                    solveCbs(run);
                    break;
                default:
                    solveWhca(run);
                    break;
                }
                if (run.status.equals("OK")) {
                    run.metrics = metrics(run.paths, definition.function());
                    run.validation = validate(run.paths);
                    run.execution = delayedExecution(run.paths);
                }
                results.add(run);
            }
        }
        List<String> instanceLines() {
            List<String> lines = new ArrayList<>();
            lines.add("instance width " + grid.width + " height " + grid.height + " free " +
                      grid.free.size() + " agents " + agents.size());
            lines.add("map isolated " + degrees[0] + " dead_ends " + degrees[1] + " corridors " +
                      degrees[2] + " junctions " + degrees[3] + " components " + components);
            for (int id = 0; id < agents.size(); id++) {
                GridMap.Agent agent = agents.get(id);
                AgentInfo record = info.get(id);
                lines.add("agent " + agent.name() + " start " + agent.start() + " goal " +
                          agent.goal() + " distance " + record.shortest() + " mdd " +
                          record.states() + " width " + record.width());
            }
            lines.add("lower_bound soc " + socLower + " makespan " + makespanLower);
            int vertex = 0;
            int[] classes = new int[3];
            for (Cbs.Conflict conflict : independentConflicts) {
                if (conflict.kind().equals("vertex"))
                    vertex++;
                classes[CLASSES.indexOf(independentClasses.get(conflict))]++;
            }
            lines.add("independent conflicts " + independentConflicts.size() + " vertex " + vertex +
                      " edge " + (independentConflicts.size() - vertex) + " cardinal " +
                      classes[0] + " semi_cardinal " + classes[1] + " non_cardinal " + classes[2]);
            lines.add("groups " + (groups.isEmpty() ? "-" : String.join(" ", groups)));
            return lines;
        }
        List<String> successfulLines(Run run) {
            Metrics m = run.metrics;
            Execution execution = run.execution;
            List<String> lines = new ArrayList<>();
            lines.add("run " + run.name() + " solver " + run.definition.solver() +
                      " cost_function " + run.definition.function() + " result OK cost " + m.cost +
                      " soc " + m.soc + " makespan " + m.makespan + " ratio " + m.ratio);
            lines.addAll(run.specific);
            for (int id = 0; id < agents.size(); id++) {
                PathStats p = m.agents.get(id);
                lines.add("agent " + Report.name(id) + " cost " + p.cost() + " extra " + p.extra() +
                          " waits " + p.waits() + " turns " + p.turns() + " arrive " + p.arrive() +
                          " leave " + p.leave() + " moves " + p.actions());
            }
            lines.add("arrivals " + joinNumbers(m.arrivals));
            List<String> hot = new ArrayList<>();
            for (GridMap.Cell cell : m.hotspots)
                hot.add(cell + ":" + m.traffic.get(cell));
            lines.add("hotspots " + String.join(" ", hot));
            if (execution.deadlock() != null)
                lines.add("execution deadlock time " + execution.deadlock());
            else
                lines.add("execution soc " + execution.soc() + " makespan " + execution.makespan() +
                          " blocked " + execution.blocked() + " finish " +
                          joinNumbers(execution.finish()));
            return lines;
        }
        String joinNumbers(List<Integer> numbers) {
            return String.join(" ", numbers.stream().map(Object::toString).toList());
        }
        List<String> solutionLines() {
            List<String> lines = instanceLines();
            List<Run> succeeded = new ArrayList<>();
            for (Run run : results) {
                lines.add("");
                if (run.status.equals("OK")) {
                    lines.addAll(successfulLines(run));
                    succeeded.add(run);
                } else {
                    lines.add("run " + run.name() + " solver " + run.definition.solver() +
                              " cost_function " + run.definition.function() +
                              " result FAIL reason " + run.reason);
                    lines.addAll(run.specific);
                }
            }
            lines.add("");
            lines.add("summary ok " + succeeded.size() + " failed " +
                      (results.size() - succeeded.size()));
            if (!succeeded.isEmpty()) {
                int bestSoc =
                        succeeded.stream().mapToInt(run -> run.metrics.soc).min().orElseThrow(),
                    bestSpan = succeeded.stream()
                                   .mapToInt(run -> run.metrics.makespan)
                                   .min()
                                   .orElseThrow();
                List<String> socNames = new ArrayList<>(), spanNames = new ArrayList<>();
                for (Run run : succeeded) {
                    if (run.metrics.soc == bestSoc)
                        socNames.add(run.name());
                    if (run.metrics.makespan == bestSpan)
                        spanNames.add(run.name());
                }
                lines.add("best_soc " + bestSoc + " " + String.join(" ", socNames));
                lines.add("best_makespan " + bestSpan + " " + String.join(" ", spanNames));
                succeeded.sort(Comparator.comparingInt((Run run) -> run.metrics.soc)
                                   .thenComparingInt(run -> run.metrics.makespan));
                lines.add("ranking " +
                          String.join(" ", succeeded.stream().map(Run::name).toList()));
            }
            return lines;
        }
        List<String> statsLines() {
            List<String> lines = new ArrayList<>();
            lines.add(
                "run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions");
            for (Run run : results) {
                List<String> fields = new ArrayList<>(
                    List.of(run.name(), run.definition.solver(), run.definition.function(),
                            run.status, run.reason == null ? "-" : run.reason));
                if (run.status.equals("OK")) {
                    Metrics m = run.metrics;
                    for (int value : new int[] {m.cost, m.soc, m.makespan, m.sumExtra, m.maxExtra,
                                                m.waits, m.turns})
                        fields.add(Integer.toString(value));
                    fields.add(run.execution.deadlock() == null
                                   ? Integer.toString(run.execution.soc())
                                   : "-");
                    fields.add(run.execution.deadlock() == null
                                   ? Integer.toString(run.execution.makespan())
                                   : "-");
                } else
                    fields.addAll(Collections.nCopies(9, "-"));
                fields.add(Integer.toString(run.highLevel));
                fields.add(run.generated == null ? "-" : run.generated.toString());
                fields.add(Integer.toString(run.budget.searches));
                fields.add(Integer.toString(run.budget.expansions));
                lines.add(Report.csv(fields));
            }
            return lines;
        }
        void validationBlock(List<String> lines, String name, Validation v) {
            lines.add("plan " + name + " verdict " + v.verdict() + " start " + v.start() +
                      " goal " + v.goal() + " moves " + v.moves() + " vertex " + v.vertex() +
                      " edge " + v.edge() + " follows " + v.follows());
            for (Cbs.Conflict conflict : v.conflicts())
                lines.add(
                    "  " + Report.conflict(conflict) +
                    (name.equals("INDEPENDENT") ? " " + independentClasses.get(conflict) : ""));
        }
        List<String> validationLines() {
            List<String> lines = new ArrayList<>();
            validationBlock(lines, "INDEPENDENT", validate(independent));
            for (Run run : results)
                if (run.validation == null)
                    lines.add("plan " + run.name() + " verdict NONE");
                else
                    validationBlock(lines, run.name(), run.validation);
            return lines;
        }
        List<String> traceLines() {
            List<String> lines = new ArrayList<>();
            for (Run run : results) {
                if (!lines.isEmpty())
                    lines.add("");
                lines.add("run " + run.name());
                lines.addAll(run.trace);
                lines.add(run.end);
            }
            return lines;
        }
        List<String> picture(Map<GridMap.Cell, Character> placements) {
            List<String> lines = new ArrayList<>();
            for (int y = 0; y < grid.height; y++) {
                StringBuilder row = new StringBuilder();
                for (int x = 0; x < grid.width; x++)
                    row.append(placements.getOrDefault(new GridMap.Cell(x, y),
                                                       grid.rows.get(y).charAt(x)));
                lines.add(row.toString());
            }
            return lines;
        }
        List<String> countPicture(Map<GridMap.Cell, Integer> counts) {
            Map<GridMap.Cell, Character> glyphs = new HashMap<>();
            for (var entry : counts.entrySet())
                if (entry.getValue() > 0)
                    glyphs.put(entry.getKey(),
                               entry.getValue() <= 9 ? (char)('0' + entry.getValue()) : '+');
            return picture(glyphs);
        }
        List<String> animationLines() {
            Run selected = results.stream()
                               .filter(run -> run.name().equals(settings.animate))
                               .findFirst()
                               .orElseThrow();
            if (!selected.status.equals("OK"))
                return List.of("run " + selected.name() + " FAIL");
            List<String> lines = new ArrayList<>();
            lines.add("run " + selected.name() + " frames " + settings.frames);
            for (int time = 0; time < settings.frames; time++) {
                int done = 0, moving = 0, waiting = 0;
                Map<GridMap.Cell, Character> glyphs = new HashMap<>();
                for (GridMap.Agent agent : agents)
                    glyphs.put(agent.goal(), Character.toLowerCase(agent.name()));
                for (int id = 0; id < agents.size(); id++) {
                    List<GridMap.Cell> path = selected.paths.get(id);
                    GridMap.Cell cell = Cbs.position(path, time);
                    glyphs.put(cell, Report.name(id));
                    if (time >= path.size() - 1)
                        done++;
                    else if (time >= 1 && !cell.equals(Cbs.position(path, time - 1)))
                        moving++;
                    else
                        waiting++;
                }
                lines.add("");
                lines.add("frame " + time + " done " + done + " moving " + moving + " waiting " +
                          waiting);
                lines.addAll(picture(glyphs));
            }
            lines.add("");
            lines.add("traffic");
            lines.addAll(countPicture(selected.metrics.traffic));
            lines.add("");
            lines.add("waits");
            lines.addAll(countPicture(selected.metrics.cellWaits));
            return lines;
        }
        void write() throws Exception {
            Report.write("solutions.txt", solutionLines());
            Report.write("stats.csv", statsLines());
            Report.write("validation.txt", validationLines());
            Report.write("trace.txt", traceLines());
            Report.write("frames.txt", animationLines());
        }
    }
    public static void main(String[] args) throws Exception {
        Planner planner = new Planner();
        planner.solve();
        planner.write();
    }
}
