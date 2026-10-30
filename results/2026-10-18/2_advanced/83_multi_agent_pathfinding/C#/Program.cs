using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static readonly List<string> CLASSES =
        new List<string> { "cardinal", "semi_cardinal", "non_cardinal" };
    public record Definition(string solver, string function) {
        public string Name() { return solver + "-" + function; }
    }
    public record Delay(int agent, int start, int duration) {}
    public sealed class Settings {
        public int horizon, hlBudget, llBudget, window, step, frames;
        public string animate;
        public List<List<int>> orders = new();
        public List<Definition> runs = new();
        public List<Delay> delays = new();
        public Settings(int count) {
            List<int> numberOrder = new();
            for (int i = 0; i < count; i++)
                numberOrder.Add(i);
            orders.Add(numberOrder);
            foreach (string line in File
                         .ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)
                         .ToList()) {
                string[] f = line.Split(" ");
                switch (f[0]) {
                case "HORIZON":
                    horizon = int.Parse(f[1]);
                    break;
                case "HL_BUDGET":
                    hlBudget = int.Parse(f[1]);
                    break;
                case "LL_BUDGET":
                    llBudget = int.Parse(f[1]);
                    break;
                case "WINDOW":
                    window = int.Parse(f[1]);
                    step = int.Parse(f[2]);
                    break;
                case "ORDER": {
                    List<int> order = new();
                    for (int i = 1; i < f.Length; i++)
                        order.Add(int.Parse(f[i]));
                    orders.Add(order);
                    break;
                }
                case "RUN":
                    runs.Add(new Definition(f[1], f[2]));
                    break;
                case "ANIMATE":
                    animate = f[1];
                    frames = int.Parse(f[2]);
                    break;
                case "DELAY":
                    delays.Add(new Delay(int.Parse(f[1]), int.Parse(f[2]), int.Parse(f[3])));
                    break;
                }
            }
        }
    }
    public record AgentInfo(int shortest, int states, int width) {}
    public record Split(Cbs.Conflict conflict, string category) {}
    public record PathStats(int cost, int extra, int waits, int turns, int arrive, int leave,
                            string actions) {}
    public sealed class Metrics {
        public int soc, makespan, cost, sumExtra, maxExtra, waits, turns;
        public string ratio;
        public List<PathStats> agents = new();
        public List<int> arrivals = new();
        public Dictionary<GridMap.Cell, int> traffic = new(), cellWaits = new();
        public List<GridMap.Cell> hotspots;
    }
    public record Validation(int start, int goal, int moves, int vertex, int edge, int follows,
                             List<Cbs.Conflict> conflicts) {
        public string Verdict() {
            return start + goal + moves + vertex + edge == 0 ? "VALID" : "INVALID";
        }
    }
    public record Step(int time, GridMap.Cell cell) {}
    public record Prerequisite(int agent, int step) {}
    public record Execution(int? deadlock, int blocked, List<int> finish, int soc, int makespan) {}
    public sealed class Run {
        public Definition definition;
        public string status = "FAIL", reason, end;
        public List<List<GridMap.Cell>> paths;
        public int highLevel;
        public int? generated;
        public LowLevel.Budget budget;
        public List<string> specific = new(), trace = new();
        public Metrics metrics;
        public Validation validation;
        public Execution execution;
        public Run(Definition definition, int limit) {
            this.definition = definition;
            budget = new LowLevel.Budget(limit);
        }
        public string Name() { return definition.Name(); }
    }
    public sealed class Planner {
        public GridMap grid;
        public List<GridMap.Agent> agents;
        public Settings settings;
        public List<Dictionary<GridMap.Cell, int>> distances = new();
        public List<List<GridMap.Cell>> independent = new();
        public List<AgentInfo> info = new();
        public List<Cbs.Conflict> independentConflicts;
        public Dictionary<Cbs.Conflict, string> independentClasses = new();
        public List<Run> results = new();
        public int socLower, makespanLower, components;
        public int[] degrees = new int[4];
        public List<string> groups = new();
        public Planner() {
            grid = new GridMap();
            agents = GridMap.Agents();
            settings = new Settings(agents.Count);
            LowLevel.Budget budget = new LowLevel.Budget(null);
            foreach (GridMap.Agent agent in agents) {
                Dictionary<GridMap.Cell, int> distance = grid.Distances(agent.goal);
                distances.Add(distance);
                independent.Add(LowLevel
                                    .FindPath(grid, agent, distance, agent.start, 0,
                                              new LowLevel.Prohibitions(), settings.horizon, budget,
                                              false)
                                    .path);
            }
            Overview();
        }
        public List<HashSet<GridMap.Cell>> Mdd(int id, int length,
                                               LowLevel.Prohibitions restrictions) {
            List<HashSet<GridMap.Cell>> layers = new();
            layers.Add(new HashSet<GridMap.Cell> { agents[id].start });
            for (int time = 1; time <= length; time++) {
                HashSet<GridMap.Cell> next = new();
                foreach (GridMap.Cell source in layers[^1])
                    foreach (GridMap.Cell destination in grid.Destinations(source))
                        if (time + distances[id].GetValueOrDefault(destination, length + 1) <=
                                length &&
                            restrictions.ActionAllowed(source, destination, time))
                            next.Add(destination);
                layers.Add(next);
            }
            List<HashSet<GridMap.Cell>> valid = new();
            for (int time = 0; time <= length; time++)
                valid.Add(new());
            valid[^1].Add(agents[id].goal);
            for (int time = length - 1; time >= 0; time--)
                foreach (GridMap.Cell source in layers[time])
                    foreach (GridMap.Cell destination in grid.Destinations(source))
                        if (valid[time + 1].Contains(destination) &&
                            restrictions.ActionAllowed(source, destination, time + 1)) {
                            valid[time].Add(source);
                            break;
                        }
            return valid;
        }
        public string ConflictClass(Cbs.Conflict conflict, List<List<GridMap.Cell>> paths,
                                    List<LowLevel.Prohibitions> restrictions,
                                    Dictionary<int, List<HashSet<GridMap.Cell>>> cache) {
            int forcedCount = 0;
            foreach (int id in new int[] { conflict.a, conflict.b }) {
                int length = paths[id].Count - 1;
                List<HashSet<GridMap.Cell>> layers =
                    cache.GetOrAdd(id, () => Mdd(id, length, restrictions[id]));
                int time = conflict.time;
                bool forced = time > length ||
                              layers[time].Count == 1 &&
                                  (conflict.kind.Equals("vertex") || layers[time - 1].Count == 1);
                if (forced)
                    forcedCount++;
            }
            return CLASSES[2 - forcedCount];
        }
        public List<LowLevel.Prohibitions> EmptyRestrictions() {
            List<LowLevel.Prohibitions> restrictions = new();
            for (int i = 0; i < agents.Count; i++)
                restrictions.Add(new LowLevel.Prohibitions());
            return restrictions;
        }
        public void Overview() {
            foreach (GridMap.Cell cell in grid.free)
                degrees[Math.Min(3, grid.Neighbors(cell).Count)]++;
            HashSet<GridMap.Cell> remaining = new(grid.free);
            while (remaining.Count != 0) {
                components++;
                Queue<GridMap.Cell> queue = new();
                GridMap.Cell seed = remaining.First();
                remaining.Remove(seed);
                queue.Enqueue(seed);
                while (queue.Count != 0)
                    foreach (GridMap.Cell next in grid.Neighbors(queue.Dequeue()))
                        if (remaining.Remove(next))
                            queue.Enqueue(next);
            }
            for (int id = 0; id < agents.Count; id++) {
                int shortest = distances[id][agents[id].start];
                List<HashSet<GridMap.Cell>> layers = Mdd(id, shortest, new LowLevel.Prohibitions());
                int states = layers.Sum(layer => layer.Count),
                    width = layers.Max(layer => layer.Count);
                info.Add(new AgentInfo(shortest, states, width));
                socLower += shortest;
                makespanLower = Math.Max(makespanLower, shortest);
            }
            independentConflicts = Cbs.Conflicts(independent);
            List<LowLevel.Prohibitions> restrictions = EmptyRestrictions();
            Dictionary<int, List<HashSet<GridMap.Cell>>> cache = new();
            List<HashSet<int>> adjacent = new();
            for (int i = 0; i < agents.Count; i++)
                adjacent.Add(new());
            foreach (Cbs.Conflict conflict in independentConflicts) {
                independentClasses[conflict] =
                    ConflictClass(conflict, independent, restrictions, cache);
                adjacent[conflict.a].Add(conflict.b);
                adjacent[conflict.b].Add(conflict.a);
            }
            HashSet<int> seen = new();
            for (int start = 0; start < agents.Count; start++) {
                if (seen.Contains(start) || adjacent[start].Count == 0)
                    continue;
                SortedSet<int> component = new();
                Queue<int> queue = new();
                queue.Enqueue(start);
                seen.Add(start);
                while (queue.Count != 0) {
                    int current = queue.Dequeue();
                    component.Add(current);
                    foreach (int next in adjacent[current])
                        if (seen.Add(next))
                            queue.Enqueue(next);
                }
                StringBuilder names = new StringBuilder();
                foreach (int id in component)
                    names.Append(Report.Name(id));
                groups.Add(names.ToString());
            }
        }
        public void SolvePp(Run run) {
            int answer = 0;
            for (int index = 0; index < settings.orders.Count; index++) {
                int orderNumber = index + 1;
                List<int> order = settings.orders[index];
                run.highLevel++;
                int before = run.budget.expansions;
                Prioritized.Result result = Prioritized.TryOrder(
                    grid, agents, distances, settings.horizon, order, run.budget);
                foreach (Prioritized.Attempt attempt in result.attempts) {
                    LowLevel.Search search = attempt.search;
                    string prefix = "order " + orderNumber + " agent " + Report.Name(attempt.agent);
                    run.trace.Add(
                        prefix +
                        (search.path == null ? " failed" : " cost " + (search.path.Count - 1)) +
                        " expansions " + search.expansions);
                }
                if (result.aborted) {
                    run.reason = "ll_budget";
                    break;
                }
                StringBuilder names = new StringBuilder();
                foreach (int id in order)
                    names.Append(Report.Name(id));
                int planned = result.attempts.Count - (result.failed == null ? 0 : 1);
                string summary = "order " + orderNumber + " " + names + " planned " + planned +
                                 " expansions " + (run.budget.expansions - before);
                if (result.failed == null) {
                    run.specific.Add(summary + " ok");
                    run.paths = result.paths;
                    run.status = "OK";
                    answer = orderNumber;
                    break;
                }
                run.specific.Add(summary + " failed " + Report.Name(result.failed.Value));
            }
            if (run.status.Equals("OK"))
                run.end = "end OK order " + answer;
            else {
                if (run.reason == null)
                    run.reason = "orders";
                run.end = "end FAIL " + run.reason;
            }
        }
        public List<LowLevel.Prohibitions>
        ApplyConstraint(List<LowLevel.Prohibitions> baseRestrictions, Cbs.Constraint addition) {
            List<LowLevel.Prohibitions> copied = new(baseRestrictions);
            LowLevel.Prohibitions changed = baseRestrictions[addition.agent].Copy();
            if (addition.kind.Equals("vertex"))
                changed.states.Add(new LowLevel.State(addition.v, addition.time));
            else
                changed.moves.Add(new LowLevel.Move(addition.u, addition.v, addition.time));
            copied[addition.agent] = changed;
            return copied;
        }
        public Split ChooseSplit(Cbs.Node node, Run run) {
            if (run.definition.solver.Equals("CBS"))
                return new Split(node.conflicts[0], null);
            Dictionary<int, List<HashSet<GridMap.Cell>>> cache = new();
            Cbs.Conflict best = null;
            string category = null;
            int earliest = 3;
            foreach (Cbs.Conflict conflict in node.conflicts) {
                string candidate = ConflictClass(conflict, node.paths, node.constraints, cache);
                int rank = CLASSES.IndexOf(candidate);
                if (rank < earliest) {
                    earliest = rank;
                    best = conflict;
                    category = candidate;
                }
            }
            return new Split(best, category);
        }
        public void SolveCbs(Run run) {
            List<LowLevel.Prohibitions> empty = EmptyRestrictions();
            List<List<GridMap.Cell>> paths = new();
            try {
                for (int id = 0; id < agents.Count; id++)
                    paths.Add(LowLevel
                                  .FindPath(grid, agents[id], distances[id], agents[id].start, 0,
                                            empty[id], settings.horizon, run.budget, false)
                                  .path);
            } catch (LowLevel.BudgetExceeded exception) {
                run.reason = "ll_budget";
                run.generated = 0;
                run.specific.Add("search expanded 0 generated 0 pruned 0 open 0");
                if (run.definition.solver.Equals("ICBS"))
                    run.specific.Add("classes cardinal 0 semi_cardinal 0 non_cardinal 0");
                run.end = "end FAIL ll_budget";
                return;
            }
            Cbs.Node root = new Cbs.Node(paths, empty, 0, 0, null, run.definition.function);
            PriorityQueue<Cbs.Node, Cbs.Node> open = new(Cbs.Order);
            open.Enqueue(root, root);
            int generated = 1, expanded = 0, pruned = 0;
            int[] classifications = new int[3];
            string reason = "exhausted";
            Cbs.Node answer = null;
            while (open.Count != 0) {
                Cbs.Node node = open.Dequeue();
                if (node.conflicts.Count == 0) {
                    answer = node;
                    reason = null;
                    break;
                }
                if (expanded == settings.hlBudget) {
                    reason = "hl_budget";
                    break;
                }
                expanded++;
                Split split = ChooseSplit(node, run);
                Cbs.Conflict conflict = split.conflict;
                if (split.category != null)
                    classifications[CLASSES.IndexOf(split.category)]++;
                List<string> created = new();
                bool aborted = false;
                foreach (Cbs.Constraint branch in Cbs.Split(conflict)) {
                    int id = branch.agent;
                    List<LowLevel.Prohibitions> restrictions =
                        ApplyConstraint(node.constraints, branch);
                    LowLevel.Search search;
                    try {
                        search = LowLevel.FindPath(grid, agents[id], distances[id],
                                                   agents[id].start, 0, restrictions[id],
                                                   settings.horizon, run.budget, false);
                    } catch (LowLevel.BudgetExceeded exception) {
                        aborted = true;
                        break;
                    }
                    if (search.path == null) {
                        pruned++;
                        created.Add("-");
                        continue;
                    }
                    List<List<GridMap.Cell>> newPaths = new(node.paths);
                    newPaths[id] = search.path;
                    Cbs.Node child = new Cbs.Node(newPaths, restrictions, generated, node.depth + 1,
                                                  node.number, run.definition.function);
                    open.Enqueue(child, child);
                    created.Add(Convert.ToString(generated++));
                }
                if (aborted) {
                    reason = "ll_budget";
                    break;
                }
                string text = "expand " + expanded + " node " + node.number + " parent " +
                              (node.parent == null ? "-" : node.parent.ToString()) + " depth " +
                              node.depth + " cost " + node.cost + " conflicts " +
                              node.conflicts.Count + " split " + Report.Conflict(conflict);
                if (split.category != null)
                    text += " class " + split.category;
                run.trace.Add(text + " children " + created[0] + " " + created[1]);
            }
            run.highLevel = expanded;
            run.generated = generated;
            run.specific.Add("search expanded " + expanded + " generated " + generated +
                             " pruned " + pruned + " open " + open.Count);
            if (run.definition.solver.Equals("ICBS"))
                run.specific.Add("classes cardinal " + classifications[0] + " semi_cardinal " +
                                 classifications[1] + " non_cardinal " + classifications[2]);
            if (answer == null) {
                run.reason = reason;
                run.end = "end FAIL " + reason;
                return;
            }
            run.status = "OK";
            run.paths = answer.paths;
            run.specific.Add("solution node " + answer.number + " depth " + answer.depth);
            foreach (Cbs.Constraint c in Cbs.OrderedConstraints(answer))
                run.specific.Add("constraint " + Report.Name(c.agent) + " " + c.kind + " " + c.u +
                                 (c.kind.Equals("vertex") ? "" : " " + c.v) + " t " + c.time);
            run.end = "end OK node " + answer.number + " cost " + answer.cost;
        }
        public void SolveWhca(Run run) {
            List<GridMap.Cell> current = new();
            List<List<GridMap.Cell>> executed = new();
            foreach (GridMap.Agent agent in agents) {
                current.Add(agent.start);
                executed.Add(new List<GridMap.Cell> { agent.start });
            }
            int time = 0, rounds = 0;
            string reason = null;
            while (true) {
                bool complete = true;
                for (int id = 0; id < agents.Count; id++)
                    if (!current[id].Equals(agents[id].goal))
                        complete = false;
                if (complete)
                    break;
                if (time >= settings.horizon) {
                    reason = "timeout";
                    break;
                }
                rounds++;
                LowLevel.Prohibitions restrictions = new LowLevel.Prohibitions();
                List<int> order = new();
                foreach (bool atGoal in new bool[] { false, true })
                    for (int id = 0; id < agents.Count; id++)
                        if (current[id].Equals(agents[id].goal) == atGoal)
                            order.Add(id);
                Dictionary<int, List<GridMap.Cell>> plans = new();
                bool failed = false;
                foreach (int id in order) {
                    LowLevel.Search search;
                    try {
                        search = LowLevel.FindPath(grid, agents[id], distances[id], current[id],
                                                   time, restrictions, time + settings.window,
                                                   run.budget, true);
                    } catch (LowLevel.BudgetExceeded exception) {
                        reason = "ll_budget";
                        failed = true;
                        break;
                    }
                    string prefix =
                        "round " + rounds + " time " + time + " agent " + Report.Name(id);
                    if (search.path == null) {
                        run.trace.Add(prefix + " blocked expansions " + search.expansions);
                        reason = "blocked";
                        failed = true;
                        break;
                    }
                    List<GridMap.Cell> extended = new(search.path);
                    while (extended.Count < settings.window + 1)
                        extended.Add(extended[^1]);
                    plans[id] = extended;
                    run.trace.Add(prefix + " moves " + Report.Actions(extended) + " expansions " +
                                  search.expansions);
                    LowLevel.Reserve(restrictions, extended, time, false);
                }
                if (failed)
                    break;
                for (int id = 0; id < agents.Count; id++) {
                    executed[id].AddRange(plans[id].GetRange(1, settings.step + 1 - 1));
                    current[id] = plans[id][settings.step];
                }
                time += settings.step;
            }
            run.highLevel = rounds;
            run.specific.Add("window " + settings.window + " step " + settings.step + " rounds " +
                             rounds);
            if (reason != null) {
                run.reason = reason;
                run.end = "end FAIL " + reason;
            } else {
                run.status = "OK";
                for (int id = 0; id < agents.Count; id++) {
                    List<GridMap.Cell> path = executed[id];
                    GridMap.Cell goal = agents[id].goal;
                    while (path.Count > 1 && path[^1].Equals(goal) &&
                           path[path.Count - 2].Equals(goal))
                        path.RemoveAt(path.Count - 1);
                }
                run.paths = executed;
                run.end = "end OK rounds " + rounds;
            }
        }
        public Validation Validate(List<List<GridMap.Cell>> paths) {
            int start = 0, goal = 0, moves = 0;
            for (int id = 0; id < agents.Count; id++) {
                List<GridMap.Cell> path = paths[id];
                if (!path[0].Equals(agents[id].start))
                    start++;
                if (!path[^1].Equals(agents[id].goal))
                    goal++;
                for (int t = 1; t < path.Count; t++)
                    if (!grid.Destinations(path[t - 1]).Contains(path[t]))
                        moves++;
            }
            List<Cbs.Conflict> collisions = Cbs.Conflicts(paths);
            int vertex = collisions.Count(c => c.kind == "vertex"),
                edge = collisions.Count - vertex, follows = 0;
            int horizon = Cbs.Cost(paths, "MAKESPAN");
            for (int time = 1; time <= horizon; time++)
                for (int a = 0; a < paths.Count; a++) {
                    GridMap.Cell pastA = Cbs.Position(paths[a], time - 1),
                                 nextA = Cbs.Position(paths[a], time);
                    if (nextA.Equals(pastA))
                        continue;
                    for (int b = 0; b < paths.Count; b++)
                        if (a != b && nextA.Equals(Cbs.Position(paths[b], time - 1)) &&
                            !Cbs.Position(paths[b], time).Equals(pastA))
                            follows++;
                }
            return new Validation(start, goal, moves, vertex, edge, follows, collisions);
        }
        public PathStats PathStats(List<GridMap.Cell> path, int id) {
            int waits = 0, turns = 0, arrive = -1, leave = 0;
            char previous = '\0';
            string actions = Report.Actions(path);
            GridMap.Cell goal = agents[id].goal;
            for (int t = 0; t < path.Count; t++)
                if (path[t].Equals(goal)) {
                    arrive = t;
                    break;
                }
            for (int t = 1; t < path.Count; t++) {
                char action = actions[t - 1];
                if (action == '.')
                    waits++;
                else {
                    if (previous != '\0' && previous != action)
                        turns++;
                    previous = action;
                }
                if (path[t - 1].Equals(goal) && !path[t].Equals(goal))
                    leave++;
            }
            int cost = path.Count - 1;
            return new PathStats(cost, cost - info[id].shortest, waits, turns, arrive, leave,
                                 actions);
        }
        public Metrics Metrics(List<List<GridMap.Cell>> paths, string function) {
            Metrics result = new Metrics();
            result.soc = Cbs.Cost(paths, "SOC");
            result.makespan = Cbs.Cost(paths, "MAKESPAN");
            result.cost = function.Equals("SOC") ? result.soc : result.makespan;
            result.ratio =
                Report.Fraction(result.cost, function.Equals("SOC") ? socLower : makespanLower);
            for (int id = 0; id < agents.Count; id++) {
                List<GridMap.Cell> path = paths[id];
                PathStats stats = PathStats(path, id);
                result.agents.Add(stats);
                result.sumExtra += stats.extra;
                result.maxExtra = Math.Max(result.maxExtra, stats.extra);
                result.waits += stats.waits;
                result.turns += stats.turns;
                foreach (GridMap.Cell cell in new HashSet<GridMap.Cell>(path))
                    result.traffic.AddCount(cell, 1);
                for (int t = 1; t < path.Count; t++)
                    if (path[t].Equals(path[t - 1]))
                        result.cellWaits.AddCount(path[t], 1);
            }
            for (int time = 0; time <= result.makespan; time++) {
                int arrived = 0;
                foreach (List<GridMap.Cell> path in paths)
                    if (path.Count - 1 <= time)
                        arrived++;
                result.arrivals.Add(arrived);
            }
            result.hotspots = new(result.traffic.Keys);
            result.hotspots.Sort((a, b) => {
                int c = result.traffic[b].CompareTo(result.traffic[a]);
                if (c == 0)
                    c = a.y.CompareTo(b.y);
                return c != 0 ? c : a.x.CompareTo(b.x);
            });
            if (result.hotspots.Count > 5)
                result.hotspots = new(result.hotspots.GetRange(0, 5 - 0));
            return result;
        }
        public Execution DelayedExecution(List<List<GridMap.Cell>> paths) {
            List<List<Step>> steps = new();
            foreach (List<GridMap.Cell> path in paths) {
                List<Step> entries = new();
                entries.Add(new Step(0, path[0]));
                for (int scheduledTime = 1; scheduledTime < path.Count; scheduledTime++)
                    if (!path[scheduledTime].Equals(path[scheduledTime - 1]))
                        entries.Add(new Step(scheduledTime, path[scheduledTime]));
                steps.Add(entries);
            }
            List<List<List<Prerequisite>>> prerequisites = new();
            for (int i = 0; i < paths.Count; i++) {
                List<List<Prerequisite>> requests = new();
                foreach (Step target in steps[i]) {
                    List<Prerequisite> required = new();
                    for (int j = 0; j < paths.Count; j++)
                        if (j != i)
                            for (int k = 0; k < steps[j].Count; k++) {
                                Step other = steps[j][k];
                                if (other.cell.Equals(target.cell) && other.time < target.time)
                                    required.Add(new Prerequisite(j, k));
                            }
                    requests.Add(required);
                }
                prerequisites.Add(requests);
            }
            int[] progress = new int[paths.Count], finish = new int[paths.Count];
            int holds = 0, time = 0;
            while (true) {
                bool complete = true;
                for (int i = 0; i < paths.Count; i++)
                    if (progress[i] < steps[i].Count - 1)
                        complete = false;
                if (complete)
                    break;
                List<int> advancing = new();
                int stopped = 0;
                for (int i = 0; i < paths.Count; i++) {
                    if (progress[i] == steps[i].Count - 1)
                        continue;
                    bool delayed = false;
                    foreach (Delay delay in settings.delays)
                        if (delay.agent == i && delay.start <= time &&
                            time < delay.start + delay.duration)
                            delayed = true;
                    if (delayed) {
                        stopped++;
                        continue;
                    }
                    bool allowed = true;
                    foreach (Prerequisite required in prerequisites[i][progress[i] + 1])
                        if (progress[required.agent] <= required.step)
                            allowed = false;
                    if (allowed)
                        advancing.Add(i);
                    else
                        holds++;
                }
                if (advancing.Count == 0 && stopped == 0)
                    return new Execution(time, holds, new List<int>(), 0, 0);
                foreach (int i in advancing) {
                    progress[i]++;
                    if (progress[i] == steps[i].Count - 1)
                        finish[i] = time + 1;
                }
                time++;
            }
            List<int> times = new();
            int soc = 0, makespan = 0;
            foreach (int value in finish) {
                times.Add(value);
                soc += value;
                makespan = Math.Max(makespan, value);
            }
            return new Execution(null, holds, times, soc, makespan);
        }
        public void Solve() {
            foreach (Definition definition in settings.runs) {
                Run run = new Run(definition, settings.llBudget);
                switch (definition.solver) {
                case "PP":
                    SolvePp(run);
                    break;
                case "CBS":
                case "ICBS":
                    SolveCbs(run);
                    break;
                default:
                    SolveWhca(run);
                    break;
                }
                if (run.status.Equals("OK")) {
                    run.metrics = Metrics(run.paths, definition.function);
                    run.validation = Validate(run.paths);
                    run.execution = DelayedExecution(run.paths);
                }
                results.Add(run);
            }
        }
        public List<string> InstanceLines() {
            List<string> lines = new();
            lines.Add("instance width " + grid.width + " height " + grid.height + " free " +
                      grid.free.Count + " agents " + agents.Count);
            lines.Add("map isolated " + degrees[0] + " dead_ends " + degrees[1] + " corridors " +
                      degrees[2] + " junctions " + degrees[3] + " components " + components);
            for (int id = 0; id < agents.Count; id++) {
                GridMap.Agent agent = agents[id];
                AgentInfo record = info[id];
                lines.Add("agent " + agent.Name() + " start " + agent.start + " goal " +
                          agent.goal + " distance " + record.shortest + " mdd " + record.states +
                          " width " + record.width);
            }
            lines.Add("lower_bound soc " + socLower + " makespan " + makespanLower);
            int vertex = 0;
            int[] classes = new int[3];
            foreach (Cbs.Conflict conflict in independentConflicts) {
                if (conflict.kind.Equals("vertex"))
                    vertex++;
                classes[CLASSES.IndexOf(independentClasses[conflict])]++;
            }
            lines.Add("independent conflicts " + independentConflicts.Count + " vertex " + vertex +
                      " edge " + (independentConflicts.Count - vertex) + " cardinal " + classes[0] +
                      " semi_cardinal " + classes[1] + " non_cardinal " + classes[2]);
            lines.Add("groups " + (groups.Count == 0 ? "-" : string.Join(" ", groups)));
            return lines;
        }
        public List<string> SuccessfulLines(Run run) {
            Metrics m = run.metrics;
            Execution execution = run.execution;
            List<string> lines = new();
            lines.Add("run " + run.Name() + " solver " + run.definition.solver + " cost_function " +
                      run.definition.function + " result OK cost " + m.cost + " soc " + m.soc +
                      " makespan " + m.makespan + " ratio " + m.ratio);
            lines.AddRange(run.specific);
            for (int id = 0; id < agents.Count; id++) {
                PathStats p = m.agents[id];
                lines.Add("agent " + Report.Name(id) + " cost " + p.cost + " extra " + p.extra +
                          " waits " + p.waits + " turns " + p.turns + " arrive " + p.arrive +
                          " leave " + p.leave + " moves " + p.actions);
            }
            lines.Add("arrivals " + JoinNumbers(m.arrivals));
            List<string> hot = new();
            foreach (GridMap.Cell cell in m.hotspots)
                hot.Add(cell + ":" + m.traffic[cell]);
            lines.Add("hotspots " + string.Join(" ", hot));
            if (execution.deadlock != null)
                lines.Add("execution deadlock time " + execution.deadlock);
            else
                lines.Add("execution soc " + execution.soc + " makespan " + execution.makespan +
                          " blocked " + execution.blocked + " finish " +
                          JoinNumbers(execution.finish));
            return lines;
        }
        public string JoinNumbers(List<int> numbers) { return string.Join(" ", numbers); }
        public List<string> SolutionLines() {
            List<string> lines = InstanceLines();
            List<Run> succeeded = new();
            foreach (Run run in results) {
                lines.Add("");
                if (run.status.Equals("OK")) {
                    lines.AddRange(SuccessfulLines(run));
                    succeeded.Add(run);
                } else {
                    lines.Add("run " + run.Name() + " solver " + run.definition.solver +
                              " cost_function " + run.definition.function + " result FAIL reason " +
                              run.reason);
                    lines.AddRange(run.specific);
                }
            }
            lines.Add("");
            lines.Add("summary ok " + succeeded.Count + " failed " +
                      (results.Count - succeeded.Count));
            if (succeeded.Count != 0) {
                int bestSoc = succeeded.Min(run => run.metrics.soc),
                    bestSpan = succeeded.Min(run => run.metrics.makespan);
                List<string> socNames = new(), spanNames = new();
                foreach (Run run in succeeded) {
                    if (run.metrics.soc == bestSoc)
                        socNames.Add(run.Name());
                    if (run.metrics.makespan == bestSpan)
                        spanNames.Add(run.Name());
                }
                lines.Add("best_soc " + bestSoc + " " + string.Join(" ", socNames));
                lines.Add("best_makespan " + bestSpan + " " + string.Join(" ", spanNames));
                succeeded.Sort((a, b) => {
                    int c = a.metrics.soc.CompareTo(b.metrics.soc);
                    if (c == 0)
                        c = a.metrics.makespan.CompareTo(b.metrics.makespan);
                    return c != 0 ? c : results.IndexOf(a).CompareTo(results.IndexOf(b));
                });
                lines.Add("ranking " + string.Join(" ", succeeded.Select(run => run.Name())));
            }
            return lines;
        }
        public List<string> StatsLines() {
            List<string> lines = new();
            lines.Add(
                "run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions");
            foreach (Run run in results) {
                List<string> fields = new(
                    new List<string> { run.Name(), run.definition.solver, run.definition.function,
                                       run.status, run.reason == null ? "-" : run.reason });
                if (run.status.Equals("OK")) {
                    Metrics m = run.metrics;
                    foreach (int value in new int[] { m.cost, m.soc, m.makespan, m.sumExtra,
                                                      m.maxExtra, m.waits, m.turns })
                        fields.Add(Convert.ToString(value));
                    fields.Add(run.execution.deadlock == null ? Convert.ToString(run.execution.soc)
                                                              : "-");
                    fields.Add(run.execution.deadlock == null
                                   ? Convert.ToString(run.execution.makespan)
                                   : "-");
                } else
                    fields.AddRange(Enumerable.Repeat("-", 9));
                fields.Add(Convert.ToString(run.highLevel));
                fields.Add(run.generated == null ? "-" : run.generated.ToString());
                fields.Add(Convert.ToString(run.budget.searches));
                fields.Add(Convert.ToString(run.budget.expansions));
                lines.Add(Report.Csv(fields));
            }
            return lines;
        }
        public void ValidationBlock(List<string> lines, string name, Validation v) {
            lines.Add("plan " + name + " verdict " + v.Verdict() + " start " + v.start + " goal " +
                      v.goal + " moves " + v.moves + " vertex " + v.vertex + " edge " + v.edge +
                      " follows " + v.follows);
            foreach (Cbs.Conflict conflict in v.conflicts)
                lines.Add("  " + Report.Conflict(conflict) +
                          (name.Equals("INDEPENDENT") ? " " + independentClasses[conflict] : ""));
        }
        public List<string> ValidationLines() {
            List<string> lines = new();
            ValidationBlock(lines, "INDEPENDENT", Validate(independent));
            foreach (Run run in results)
                if (run.validation == null)
                    lines.Add("plan " + run.Name() + " verdict NONE");
                else
                    ValidationBlock(lines, run.Name(), run.validation);
            return lines;
        }
        public List<string> TraceLines() {
            List<string> lines = new();
            foreach (Run run in results) {
                if (lines.Count != 0)
                    lines.Add("");
                lines.Add("run " + run.Name());
                lines.AddRange(run.trace);
                lines.Add(run.end);
            }
            return lines;
        }
        public List<string> Picture(Dictionary<GridMap.Cell, char> placements) {
            List<string> lines = new();
            for (int y = 0; y < grid.height; y++) {
                StringBuilder row = new StringBuilder();
                for (int x = 0; x < grid.width; x++)
                    row.Append(
                        placements.GetValueOrDefault(new GridMap.Cell(x, y), grid.rows[y][x]));
                lines.Add(row.ToString());
            }
            return lines;
        }
        public List<string> CountPicture(Dictionary<GridMap.Cell, int> counts) {
            Dictionary<GridMap.Cell, char> glyphs = new();
            foreach (var entry in counts)
                if (entry.Value > 0)
                    glyphs[entry.Key] = entry.Value <= 9 ? (char)('0' + entry.Value) : '+';
            return Picture(glyphs);
        }
        public List<string> AnimationLines() {
            Run selected = results.First(run => run.Name() == settings.animate);
            if (!selected.status.Equals("OK"))
                return new List<string> { "run " + selected.Name() + " FAIL" };
            List<string> lines = new();
            lines.Add("run " + selected.Name() + " frames " + settings.frames);
            for (int time = 0; time < settings.frames; time++) {
                int done = 0, moving = 0, waiting = 0;
                Dictionary<GridMap.Cell, char> glyphs = new();
                foreach (GridMap.Agent agent in agents)
                    glyphs[agent.goal] = char.ToLowerInvariant(agent.Name());
                for (int id = 0; id < agents.Count; id++) {
                    List<GridMap.Cell> path = selected.paths[id];
                    GridMap.Cell cell = Cbs.Position(path, time);
                    glyphs[cell] = Report.Name(id);
                    if (time >= path.Count - 1)
                        done++;
                    else if (time >= 1 && !cell.Equals(Cbs.Position(path, time - 1)))
                        moving++;
                    else
                        waiting++;
                }
                lines.Add("");
                lines.Add("frame " + time + " done " + done + " moving " + moving + " waiting " +
                          waiting);
                lines.AddRange(Picture(glyphs));
            }
            lines.Add("");
            lines.Add("traffic");
            lines.AddRange(CountPicture(selected.metrics.traffic));
            lines.Add("");
            lines.Add("waits");
            lines.AddRange(CountPicture(selected.metrics.cellWaits));
            return lines;
        }
        public void Write() {
            Report.Write("solutions.txt", SolutionLines());
            Report.Write("stats.csv", StatsLines());
            Report.Write("validation.txt", ValidationLines());
            Report.Write("trace.txt", TraceLines());
            Report.Write("frames.txt", AnimationLines());
        }
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Planner planner = new Planner();
        planner.Solve();
        planner.Write();
    }
}
public static class MapHelpers {
    public static V GetOrAdd<K, V>(this IDictionary<K, V> values, K key, Func<V> factory) {
        if (!values.TryGetValue(key, out V value)) {
            value = factory();
            values[key] = value;
        }
        return value;
    }
    public static void AddCount<K>(this IDictionary<K, int> values, K key, int amount) {
        values.TryGetValue(key, out int value);
        values[key] = value + amount;
    }
}
