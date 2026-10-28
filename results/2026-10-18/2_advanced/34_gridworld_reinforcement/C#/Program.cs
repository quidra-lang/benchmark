using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static readonly string[] METHODS = { "mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q" };
    public static readonly string[] POLICIES = { "value_iteration", "policy_iteration", "mc",    "sarsa",
                                                 "q_learning",      "expected_sarsa",   "dyna_q" };
    public sealed class Settings {
        public readonly Dictionary<string, long[]> entries = new();
        public Settings() {
            foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)) {
                string[] parts = line.Split(" ");
                long[] values = new long[parts.Length - 1];
                for (int i = 1; i < parts.Length; i++)
                    values[i - 1] = long.Parse(parts[i]);
                entries[parts[0]] = values;
            }
        }
        public int Option(string key) {
            return (int)entries[key][0];
        }
        public long[] Values(string key) {
            return entries[key];
        }
        public int Schedule(string key, int episode) {
            long[] values = Values(key);
            int result = (int)values[1];
            for (int i = 0; i < values.Length; i += 2)
                if (values[i] <= episode)
                    result = (int)values[i + 1];
            return result;
        }
    }
    public sealed record Episode(long total, int steps, int ending);
    public record Block(long total, long steps, int goals, int pits, int timeouts, int agree, long error,
                        int coverage) {
    }
    public record Route(List<int> cells, string ending) {
        public int StepCount() {
            return cells.Count - 1;
        }
        public int Last() {
            return cells[^1];
        }
    }
    public sealed class Learning {
        public readonly string name;
        public readonly long[][] q, visits;
        public readonly List<Episode> episodes = new();
        public readonly List<Block> blocks = new();
        public List<int> last = new();
        public int[] policy;
        public Learning(string name, int size) {
            this.name = name;
            q = Enumerable.Range(0, size)
                    .Select(
                        _ => new long[4])
                    .ToArray();
            visits = Enumerable.Range(0, size)
                         .Select(
                             _ => new long[4])
                         .ToArray();
        }
    }
    public static long Sum(long[] values) {
        long total = 0;
        foreach (long value in values)
            total += value;
        return total;
    }
    public static int Agree(Environment world, int[] first, int[] second) {
        int total = 0;
        foreach (int x in world.states)
            if (first[x] == second[x])
                total++;
        return total;
    }
    public static int[] Greedy(Environment world, long[][] q) {
        int[] policy = new int[world.size];
        foreach (int x in world.states)
            policy[x] = DynamicProgramming.First(q[x]);
        return policy;
    }
    public static int Ending(Environment world, int x) {
        return world.cells[x] == 'G' ? 0 : world.cells[x] == 'P' ? 1 : 2;
    }
    public static string EndingName(int kind) {
        return new string[] { "goal", "pit", "timeout" }[kind];
    }
    public static Learning Learn(string name, Environment.Model model, Settings settings, long[] optimal,
                                 int[] optimalPolicy) {
        Environment world = model.world;
        int gamma = settings.Option("GAMMA"), limit = settings.Option("STEP_LIMIT"),
            blockSize = settings.Option("BLOCK_SIZE"), count = settings.Option("EPISODES");
        Learning learning = new Learning(name, world.size);
        long[][] sums = Enumerable.Range(0, world.size)
                            .Select(
                                _ => new long[4])
                            .ToArray(),
                 counts = Enumerable.Range(0, world.size)
                              .Select(
                                  _ => new long[4])
                              .ToArray();
        Environment.Rng rng = new Environment.Rng(settings.Option("SEED"));
        TdLearning.Dyna dyna = new TdLearning.Dyna(world.size);
        for (int episode = 1; episode <= count; episode++) {
            int alpha = settings.Schedule("ALPHA", episode), epsilon = settings.Schedule("EPSILON", episode),
                x = world.start,
                action = name.Equals("sarsa") ? TdLearning.Choose(learning.q, x, epsilon, rng) : 0;
            long total = 0;
            List<MonteCarlo.Step> records = new();
            List<int> cells = new([x]);
            int steps = 0;
            while (steps < limit) {
                if (!name.Equals("sarsa"))
                    action = TdLearning.Choose(learning.q, x, epsilon, rng);
                int y = model.Step(x, action, rng);
                learning.visits[x][action]++;
                long reward = world.rewards[y];
                total += reward;
                steps++;
                cells.Add(y);
                if (name.Equals("mc"))
                    records.Add(new MonteCarlo.Step(x, action, reward));
                else {
                    int nextAction = name.Equals("sarsa") && !world.Terminal(y)
                                         ? TdLearning.Choose(learning.q, y, epsilon, rng)
                                         : 0;
                    long nextValue = world.Terminal(y)      ? 0
                                     : name.Equals("sarsa") ? learning.q[y][nextAction]
                                                            : TdLearning.Next(learning.q[y], epsilon,
                                                                              name.Equals("expected_sarsa"));
                    TdLearning.Update(learning.q, world, x, action, y, nextValue, gamma, alpha);
                    if (name.Equals("dyna_q")) {
                        dyna.Observe(x, action, y);
                        dyna.Plan(learning.q, world, settings.Option("PLANNING_STEPS"), gamma, alpha, rng);
                    }
                    action = nextAction;
                }
                x = y;
                if (world.Terminal(x))
                    break;
            }
            if (name.Equals("mc"))
                MonteCarlo.Update(learning.q, sums, counts, records, gamma);
            learning.episodes.Add(new Episode(total, steps, Ending(world, x)));
            if (episode == count)
                learning.last = cells;
            if (episode % blockSize == 0) {
                long blockTotal = 0, blockSteps = 0, error = 0;
                int[] endings = new int[3];
                int agreement = 0, coverage = 0;
                for (int i = episode - blockSize; i < episode; i++) {
                    Episode record = learning.episodes[i];
                    blockTotal += record.total;
                    blockSteps += record.steps;
                    endings[record.ending]++;
                }
                foreach (int state in world.states) {
                    int best = DynamicProgramming.First(learning.q[state]);
                    if (best == optimalPolicy[state])
                        agreement++;
                    error += Math.Abs(learning.q[state][best] - optimal[state]);
                    if (Sum(learning.visits[state]) > 0)
                        coverage++;
                }
                learning.blocks.Add(new Block(blockTotal, blockSteps, endings[0], endings[1], endings[2],
                                              agreement, DynamicProgramming.Floor(error, world.states.Length),
                                              coverage));
            }
        }
        learning.policy = Greedy(world, learning.q);
        return learning;
    }
    public static Route NominalPath(Environment world, int[] policy, int start, int limit) {
        List<int> cells = new([start]);
        HashSet<int> seen = new();
        seen.Add(start);
        int x = start;
        while (true) {
            int y = world.moves[x][policy[x]];
            bool repeated = seen.Contains(y);
            cells.Add(y);
            if (world.Terminal(y))
                return new Route(cells, EndingName(Ending(world, y)));
            if (repeated)
                return new Route(cells, "loop");
            if (cells.Count - 1 >= limit)
                return new Route(cells, "limit");
            seen.Add(y);
            x = y;
        }
    }
    public static string Cells(Environment world, List<int> cells) {
        List<string> result = new();
        foreach (int x in cells)
            result.Add(Report.Cell(world, x));
        return string.Join(" ", result);
    }
    public static int[] Distances(Environment.Model model) {
        Environment world = model.world;
        int[] distances = new int[world.size];
        Array.Fill(distances, -1);
        distances[world.start] = 0;
        Queue<int> queue = new();
        queue.Enqueue(world.start);
        while (queue.Count != 0) {
            int x = queue.Dequeue();
            if (world.Terminal(x))
                continue;
            for (int a = 0; a < 4; a++)
                foreach (Environment.Outcome transition in model.transitions[x][a]) {
                    int y = transition.cell;
                    if (distances[y] < 0) {
                        distances[y] = distances[x] + 1;
                        queue.Enqueue(y);
                    }
                }
        }
        return distances;
    }
    public static long[] Absorption(Environment.Model model, int[] policy, int limit) {
        Environment world = model.world;
        long[] goals = new long[world.size], pits = new long[world.size], steps = new long[world.size];
        for (int k = 0; k < limit; k++) {
            long[] nextGoals = new long[world.size], nextPits = new long[world.size],
                   nextSteps = new long[world.size];
            foreach (int x in world.states) {
                long g = 0, p = 0, e = 0;
                foreach (Environment.Outcome t in model.transitions[x][policy[x]]) {
                    int y = t.cell;
                    g += t.weight * (world.cells[y] == 'G' ? 100000000 : world.Terminal(y) ? 0 : goals[y]);
                    p += t.weight * (world.cells[y] == 'P' ? 100000000 : world.Terminal(y) ? 0 : pits[y]);
                    e += t.weight * (world.Terminal(y) ? 0 : steps[y]);
                }
                nextGoals[x] = g / model.q;
                nextPits[x] = p / model.q;
                nextSteps[x] = 100000000 + e / model.q;
            }
            goals = nextGoals;
            pits = nextPits;
            steps = nextSteps;
        }
        return new long[] { goals[world.start] / 10000, pits[world.start] / 10000,
                            (100000000 - goals[world.start] - pits[world.start]) / 10000,
                            steps[world.start] / 10000 };
    }
    public static DynamicProgramming.Evaluation Behaviour(Environment.Model model, int[] policy,
                                                          Settings settings) {
        Environment world = model.world;
        long[] values = new long[world.size];
        int sweeps = 0, epsilon = settings.Schedule("EPSILON", settings.Option("EPISODES"));
        while (true) {
            long delta = 0;
            foreach (int x in world.states) {
                long weighted = 0;
                for (int a = 0; a < 4; a++)
                    weighted += (epsilon + (a == policy[x] ? 4L * (1000 - epsilon) : 0)) *
                                DynamicProgramming.Bellman(model, values, x, a, settings.Option("GAMMA"));
                long v = DynamicProgramming.Floor(weighted, 4000);
                delta = Math.Max(delta, Math.Abs(v - values[x]));
                values[x] = v;
            }
            sweeps++;
            if (delta <= settings.Values("THETA")[0])
                return new DynamicProgramming.Evaluation(values, sweeps);
        }
    }
    public sealed class Rollouts {
        public long total, discounted, steps;
        public readonly int[] endings = new int[3], terminals;
        public readonly List<long> returns = new();
        public Rollouts(int count) {
            terminals = new int[count];
        }
    }
    public static Rollouts RunRollouts(Environment.Model model, int[] policy, Settings settings) {
        Environment world = model.world;
        Environment.Rng rng = new Environment.Rng(settings.Option("ROLLOUT_SEED"));
        Rollouts result = new Rollouts(world.terminals.Length);
        for (int i = 0; i < settings.Option("ROLLOUTS"); i++) {
            int x = world.start, steps = 0;
            List<long> rewards = new();
            long total = 0;
            while (steps < settings.Option("STEP_LIMIT")) {
                x = model.Step(x, policy[x], rng);
                rewards.Add(world.rewards[x]);
                total += world.rewards[x];
                steps++;
                if (world.Terminal(x))
                    break;
            }
            result.total += total;
            result.discounted += MonteCarlo.Discounted(rewards, settings.Option("GAMMA"));
            result.steps += steps;
            result.endings[Ending(world, x)]++;
            result.returns.Add(total);
            for (int j = 0; j < world.terminals.Length; j++)
                if (x == world.terminals[j])
                    result.terminals[j]++;
        }
        Collections.Sort(result.returns);
        return result;
    }
    public static void Part(List<string> output, List<string> lines) {
        if (output.Count != 0)
            output.Add("");
        output.AddRange(lines);
    }
    public static int MaxIndex(Environment world, long[] values) {
        int best = world.states[0];
        foreach (int x in world.states)
            if (values[x] > values[best])
                best = x;
        return best;
    }
    public static List<string> ValueLines(Environment.Model model, Settings settings,
                                          DynamicProgramming.Iteration vi,
                                          DynamicProgramming.Iteration inPlace,
                                          DynamicProgramming.PolicyIteration pi, long[][] q,
                                          int[] optimalPolicy, int[] distance) {
        Environment world = model.world;
        List<string> output = new(), section = new();
        int walls = 0, floor = 0, ice = 0, goals = 0, pits = 0, reachable = 0;
        foreach (char c in world.cells) {
            if (c == '#')
                walls++;
            else if (c == '.' || c == 'S')
                floor++;
            else if (c == '~')
                ice++;
            else if (c == 'G')
                goals++;
            else if (c == 'P')
                pits++;
        }
        foreach (int x in world.states)
            if (distance[x] >= 0)
                reachable++;
        section.Add("world rows " + world.height + " cols " + world.width + " states " + world.states.Length +
                    " walls " + walls + " floor " + floor + " ice " + ice + " goals " + goals + " pits " +
                    pits);
        section.Add("start " + Report.Cell(world, world.start) + " reachable " + reachable);
        foreach (int x in world.terminals)
            section.Add("terminal " + Report.Cell(world, x) + " " + EndingName(Ending(world, x)) +
                        " reward " + world.rewards[x] + " distance " +
                        (distance[x] < 0 ? "-" : distance[x].ToString(CultureInfo.InvariantCulture)));
        Part(output, section);
        section = new();
        section.Add("value_iteration gamma " + settings.Option("GAMMA") + " theta " +
                    Report.Fixed(settings.Values("THETA")[0]) + " iterations " + vi.changes.Count);
        for (int k = 0; k < vi.changes.Count; k++)
            section.Add("iteration " + (k + 1) + " max_change " + Report.Fixed(vi.changes[k]));
        Part(output, section);
        section = new(["optimal_values"]);
        section.AddRange(Report.Grid(world, true, x => Report.Fixed(vi.values[x])));
        Part(output, section);
        int[] optimalCounts = new int[world.size];
        List<string> ties = new();
        foreach (int x in world.states) {
            StringBuilder actions = new StringBuilder();
            for (int a = 0; a < 4; a++)
                if (q[x][a] == q[x][optimalPolicy[x]]) {
                    optimalCounts[x]++;
                    actions.Append("NESW"[a]);
                }
            if (optimalCounts[x] > 1)
                ties.Add("tie " + Report.Cell(world, x) + " " + actions);
        }
        section = new(["optimal_action_counts"]);
        section.AddRange(Report.Grid(world, false, x => Convert.ToString(optimalCounts[x])));
        Part(output, section);
        section = new(["ties " + ties.Count]);
        section.AddRange(ties);
        int pairs = 0, equal = 0, mirrored = 0;
        int[] mirror = { 0, 3, 2, 1 };
        HashSet<int> nonterminal = new();
        foreach (int x in world.states)
            nonterminal.Add(x);
        foreach (int x in world.states) {
            int row = x / world.width, column = x % world.width,
                other = row * world.width + world.width - 1 - column;
            if (column < world.width - 1 - column && nonterminal.Contains(other)) {
                pairs++;
                if (vi.values[x] == vi.values[other])
                    equal++;
                if (optimalPolicy[other] == mirror[optimalPolicy[x]])
                    mirrored++;
            }
        }
        section.Add("symmetry pairs " + pairs + " equal_values " + equal + " mirrored_actions " + mirrored);
        Part(output, section);
        section = new(["policy_iteration rounds " + pi.rounds.Count]);
        long evaluationSweeps = 0;
        for (int i = 0; i < pi.rounds.Count; i++) {
            DynamicProgramming.Round round = pi.rounds[i];
            evaluationSweeps += round.sweeps;
            section.Add("round " + (i + 1) + " sweeps " + round.sweeps + " changed " + round.changes +
                        " value_start " + Report.Fixed(round.value));
        }
        Part(output, section);
        section = new(["policy_iteration_values"]);
        section.AddRange(Report.Grid(world, true, x => Report.Fixed(pi.values[x])));
        Part(output, section);
        long[] differences = new long[world.size];
        foreach (int x in world.states)
            differences[x] = Math.Abs(pi.values[x] - vi.values[x]);
        int at = MaxIndex(world, differences);
        long n = world.states.Length;
        Part(output, [
            "comparison policy_differences " +
                (world.states.Length - Agree(world, pi.policy, optimalPolicy)) + " max_value_difference " +
                Report.Fixed(differences[at]) + " at " + Report.Cell(world, at),
            "backups value_iteration " + vi.changes.Count * n * 4 + " in_place_iterations " +
                inPlace.changes.Count + " in_place " + inPlace.changes.Count * n * 4 + " policy_iteration " +
                (evaluationSweeps * n + pi.rounds.Count * n * 4)
        ]);
        section = new(["gamma_sweep"]);
        foreach (long gamma in settings.Values("GAMMA_SWEEP"))
            section.Add(Sensitivity("gamma " + gamma, model, settings, (int)gamma, optimalPolicy));
        Part(output, section);
        section = new(["slip_sweep"]);
        long[] slips = settings.Values("SLIP_SWEEP");
        for (int i = 0; i < slips.Length; i += 2) {
            Environment.Model changed =
                new Environment.Model(world, model.q, (int)slips[i], (int)slips[i + 1]);
            section.Add(Sensitivity("slip " + slips[i] + " " + slips[i + 1], changed, settings,
                                    settings.Option("GAMMA"), optimalPolicy));
        }
        Part(output, section);
        return output;
    }
    public static string Sensitivity(string prefix, Environment.Model model, Settings settings, int gamma,
                                     int[] optimalPolicy) {
        DynamicProgramming.Iteration iteration =
            DynamicProgramming.Iterate(model, gamma, settings.Values("THETA")[0], false);
        int[] policy = DynamicProgramming.Policy(model, iteration.values, gamma);
        Route route = NominalPath(model.world, policy, model.world.start, settings.Option("STEP_LIMIT"));
        return prefix + " iterations " + iteration.changes.Count + " value_start " +
               Report.Fixed(iteration.values[model.world.start]) + " path " + route.ending + " steps " +
               route.StepCount() + " last " + Report.Cell(model.world, route.Last()) + " differences " +
               (model.world.states.Length - Agree(model.world, policy, optimalPolicy));
    }
    public static List<string> PolicyLines(Environment.Model model, Settings settings, List<int[]> policies,
                                           List<Learning> learning) {
        Environment world = model.world;
        List<string> output = new();
        int limit = settings.Option("STEP_LIMIT");
        for (int i = 0; i < policies.Count; i++) {
            int[] policy = policies[i];
            List<string> section = new([POLICIES[i]]);
            section.AddRange(Report.Grid(world, false, x => Convert.ToString("^>v<"[policy[x]])));
            Route route = NominalPath(world, policy, world.start, limit);
            section.Add("path " + route.ending + " steps " + route.StepCount() + " " +
                        Cells(world, route.cells));
            int[] counts = new int[4];
            int risk = 0;
            foreach (int x in world.states) {
                counts[policy[x]]++;
                bool risky = false;
                foreach (Environment.Outcome t in model.transitions[x][policy[x]])
                    if (world.cells[t.cell] == 'P')
                        risky = true;
                if (risky)
                    risk++;
            }
            section.Add("actions N " + counts[0] + " E " + counts[1] + " S " + counts[2] + " W " + counts[3] +
                        " risk " + risk);
            section.Add("basins");
            section.AddRange(Report.Grid(world, false, x => {
                Route basin = NominalPath(world, policy, x, limit);
                if (!world.Terminal(basin.Last()))
                    return "*";
                int terminal = 0;
                while (world.terminals[terminal] != basin.Last())
                    terminal++;
                return Convert.ToString((char)('a' + terminal));
            }));
            if (i >= 2) {
                Learning result = learning[i - 2];
                section.Add("visits");
                section.AddRange(Report.Grid(world, false, x => {
                    long count = Sum(result.visits[x]);
                    return count == 0 ? "0"
                                      : Convert.ToString(count.ToString(CultureInfo.InvariantCulture).Length);
                }));
            }
            Part(output, section);
        }
        return output;
    }
    public static List<string> LearningLines(Settings settings, List<Learning> learning) {
        List<string> output =
            new(["method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"]);
        int count = settings.Option("BLOCK_SIZE");
        foreach (Learning result in learning)
            for (int i = 0; i < result.blocks.Count; i++) {
                Block b = result.blocks[i];
                output.Add(result.name + "," + (i + 1) + "," + Report.Average(b.total, count) + "," +
                           Report.Average(b.steps, count) + "," + b.goals + "," + b.pits + "," + b.timeouts +
                           "," + b.agree + "," + Report.Fixed(b.error) + "," + b.coverage);
            }
        return output;
    }
    public static List<string> EvaluationLines(Environment.Model model, Settings settings,
                                               DynamicProgramming.Iteration vi, long[][] optimalQ,
                                               int[] optimalPolicy, List<int[]> policies,
                                               List<Learning> learning) {
        Environment world = model.world;
        List<string> output = new();
        Part(output,
             ["summary states " + world.states.Length + " start " + Report.Cell(world, world.start) +
              " rollouts " + settings.Option("ROLLOUTS") + " step_limit " + settings.Option("STEP_LIMIT")]);
        List<string>
            policyValues = new(["policies", "policy agree optimal_actions value_start sweeps max_gap at"]),
            improvements = new(["improvement", "policy changed value_start agree"]),
            absorptions = new(["absorption", "policy p_goal p_pit p_timeout expected_steps"]),
            behaviours = new(["behaviour", "method epsilon value_start sweeps"]),
            qErrors = new(["q_errors", "method mean_abs max_abs at unvisited tied"]),
            actionErrors = new(["q_action_errors", "method N E S W"]),
            rolloutLines = new([
                "rollouts", "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"
            ]),
            terminalLines = new(["terminals"]),
            agreementLines = new(["agreement", "policy " + string.Join(" ", POLICIES)]),
            training =
                new(["training", "method steps goals pits timeouts best_block best_mean last_mean reach"]),
            visited = new(["visited"]), lastEpisodes = new(["last_episodes"]), phases = new(["phases"]);
        string terminalHeader = "policy";
        foreach (int x in world.terminals)
            terminalHeader += " " + Report.Cell(world, x);
        terminalLines.Add(terminalHeader);
        List<Rollouts> rolloutResults = new();
        int m = settings.Option("ROLLOUTS"), limit = settings.Option("STEP_LIMIT"),
            gamma = settings.Option("GAMMA");
        long theta = settings.Values("THETA")[0];
        for (int i = 0; i < policies.Count; i++) {
            int[] policy = policies[i];
            string name = POLICIES[i];
            DynamicProgramming.Evaluation evaluation =
                DynamicProgramming.Evaluate(model, policy, gamma, theta, new long[world.size]);
            long[] gaps = new long[world.size];
            int optimalActions = 0;
            foreach (int x in world.states) {
                gaps[x] = vi.values[x] - evaluation.values[x];
                if (optimalQ[x][policy[x]] == optimalQ[x][optimalPolicy[x]])
                    optimalActions++;
            }
            int at = MaxIndex(world, gaps);
            policyValues.Add(name + " " + Agree(world, policy, optimalPolicy) + " " + optimalActions + " " +
                             Report.Fixed(evaluation.values[world.start]) + " " + evaluation.sweeps + " " +
                             Report.Fixed(gaps[at]) + " " + Report.Cell(world, at));
            int[] improved = DynamicProgramming.Policy(model, evaluation.values, gamma);
            DynamicProgramming.Evaluation improvedValue =
                DynamicProgramming.Evaluate(model, improved, gamma, theta, new long[world.size]);
            improvements.Add(name + " " + (world.states.Length - Agree(world, policy, improved)) + " " +
                             Report.Fixed(improvedValue.values[world.start]) + " " +
                             Agree(world, improved, optimalPolicy));
            string absorptionLine = name;
            foreach (long value in Absorption(model, policy, limit))
                absorptionLine += " " + Report.Fixed(value);
            absorptions.Add(absorptionLine);
            if (i >= 2) {
                Learning result = learning[i - 2];
                DynamicProgramming.Evaluation behaviour = Behaviour(model, policy, settings);
                behaviours.Add(name + " " + settings.Schedule("EPSILON", settings.Option("EPISODES")) + " " +
                               Report.Fixed(behaviour.values[world.start]) + " " + behaviour.sweeps);
                long[] errors = new long[world.size];
                long total = 0;
                int unvisited = 0, tied = 0;
                foreach (int x in world.states) {
                    long maximum = result.q[x][policy[x]];
                    errors[x] = Math.Abs(maximum - vi.values[x]);
                    total += errors[x];
                    if (Sum(result.visits[x]) == 0)
                        unvisited++;
                    int ties = 0;
                    foreach (long value in result.q[x])
                        if (value == maximum)
                            ties++;
                    if (ties > 1)
                        tied++;
                }
                at = MaxIndex(world, errors);
                qErrors.Add(name + " " + Report.Fixed(DynamicProgramming.Floor(total, world.states.Length)) +
                            " " + Report.Fixed(errors[at]) + " " + Report.Cell(world, at) + " " + unvisited +
                            " " + tied);
                string actionLine = name;
                for (int a = 0; a < 4; a++) {
                    long error = 0;
                    int count = 0;
                    foreach (int x in world.states)
                        if (result.visits[x][a] > 0) {
                            count++;
                            error += Math.Abs(result.q[x][a] - optimalQ[x][a]);
                        }
                    actionLine +=
                        " " + (count == 0 ? "-" : Report.Fixed(DynamicProgramming.Floor(error, count)));
                }
                actionErrors.Add(actionLine);
            }
            Rollouts rollouts = RunRollouts(model, policy, settings);
            rolloutResults.Add(rollouts);
            rolloutLines.Add(name + " " + Report.Average(rollouts.total, m) + " " +
                             Report.Fixed(DynamicProgramming.Floor(rollouts.discounted, m)) + " " +
                             Report.Average(rollouts.steps, m) + " " + rollouts.endings[0] + " " +
                             rollouts.endings[1] + " " + rollouts.endings[2] + " " + rollouts.returns[0] +
                             " " + rollouts.returns[(m - 1) / 2] + " " + rollouts.returns[^1]);
            string terminalLine = name;
            foreach (int count in rollouts.terminals)
                terminalLine += " " + count;
            terminalLines.Add(terminalLine);
            string agreementLine = name;
            foreach (int[] other in policies)
                agreementLine += " " + Agree(world, policy, other);
            agreementLines.Add(agreementLine);
        }
        int blockSize = settings.Option("BLOCK_SIZE"), episodeCount = settings.Option("EPISODES");
        SortedSet<int> phaseStarts = new SortedSet<int>();
        foreach (string schedule in["ALPHA", "EPSILON"]) {
            long[] values = settings.Values(schedule);
            for (int i = 0; i < values.Length; i += 2)
                phaseStarts.Add((int)values[i]);
        }
        List<int> starts = new(phaseStarts);
        foreach (Learning result in learning) {
            long steps = 0;
            int[] endings = new int[3];
            foreach (Episode episode in result.episodes) {
                steps += episode.steps;
                endings[episode.ending]++;
            }
            int best = 0;
            string reach = "-";
            for (int j = 0; j < result.blocks.Count; j++) {
                if (result.blocks[j].total > result.blocks[best].total)
                    best = j;
                if (reach.Equals("-") &&
                    10L * m * result.blocks[j].total >= 9L * blockSize * rolloutResults[0].total)
                    reach = Convert.ToString(j + 1);
            }
            training.Add(result.name + " " + steps + " " + endings[0] + " " + endings[1] + " " + endings[2] +
                         " " + (best + 1) + " " + Report.Average(result.blocks[best].total, blockSize) + " " +
                         Report.Average(result.blocks[^1].total, blockSize) + " " + reach);
            List<int> ordered = new();
            foreach (int x in world.states)
                ordered.Add(x);
            ordered.Sort((a, b) => Sum(result.visits[a]) != Sum(result.visits[b])
                                       ? Sum(result.visits[b]).CompareTo(Sum(result.visits[a]))
                                       : a.CompareTo(b));
            string visitLine = result.name;
            for (int i = 0; i < 3; i++) {
                int x = ordered[i];
                visitLine += " " + Report.Cell(world, x) + ":" + Sum(result.visits[x]);
            }
            visited.Add(visitLine);
            Episode last = result.episodes[^1];
            lastEpisodes.Add(result.name + " return " + last.total + " steps " + last.steps + " end " +
                             EndingName(last.ending) + " " + Cells(world, result.last));
            for (int i = 0; i < starts.Count; i++) {
                int start = starts[i], end = i + 1 < starts.Count ? starts[i + 1] - 1 : episodeCount;
                long total = 0, phaseSteps = 0;
                int goals = 0;
                for (int e = start; e <= end; e++) {
                    Episode episode = result.episodes[e - 1];
                    total += episode.total;
                    phaseSteps += episode.steps;
                    if (episode.ending == 0)
                        goals++;
                }
                phases.Add(result.name + " " + start + "-" + end + " alpha " +
                           settings.Schedule("ALPHA", start) + " epsilon " +
                           settings.Schedule("EPSILON", start) + " mean_return " +
                           Report.Average(total, end - start + 1) + " mean_steps " +
                           Report.Average(phaseSteps, end - start + 1) + " goals " + goals);
            }
        }
        foreach (List<string> section in new List<string>[] { policyValues, improvements, absorptions,
                                                              behaviours, qErrors, actionErrors, rolloutLines,
                                                              terminalLines, agreementLines, training,
                                                              visited, lastEpisodes, phases })
            Part(output, section);
        return output;
    }
    public static void Main(string[] args) {
        Settings settings = new Settings();
        Environment world = new Environment(settings.Option("STEP_REWARD"));
        long[] slip = settings.Values("SLIP");
        Environment.Model model = new Environment.Model(world, (int)slip[0], (int)slip[1], (int)slip[2]);
        int gamma = settings.Option("GAMMA");
        long theta = settings.Values("THETA")[0];
        DynamicProgramming.Iteration vi = DynamicProgramming.Iterate(model, gamma, theta, false),
                                     inPlace = DynamicProgramming.Iterate(model, gamma, theta, true);
        DynamicProgramming.PolicyIteration pi = DynamicProgramming.RunPolicyIteration(model, gamma, theta);
        long[][] optimalQ = Enumerable.Range(0, world.size)
                                .Select(
                                    _ => new long[4])
                                .ToArray();
        foreach (int x in world.states)
            optimalQ[x] = DynamicProgramming.Actions(model, vi.values, x, gamma);
        int[] optimalPolicy = Greedy(world, optimalQ);
        List<Learning> learning = new();
        List<int[]> policies = new();
        policies.Add(optimalPolicy);
        policies.Add(pi.policy);
        foreach (string method in METHODS) {
            Learning result = Learn(method, model, settings, vi.values, optimalPolicy);
            learning.Add(result);
            policies.Add(result.policy);
        }
        List<string> qLines = new(["method,row,col,action,value,visits"]);
        Report.QRows(qLines, "value_iteration", world, optimalQ, null);
        foreach (Learning result in learning)
            Report.QRows(qLines, result.name, world, result.q, result.visits);
        Directory.CreateDirectory(Path.Combine("output"));
        Report.Write("values.txt",
                     ValueLines(model, settings, vi, inPlace, pi, optimalQ, optimalPolicy, Distances(model)));
        Report.Write("policies.txt", PolicyLines(model, settings, policies, learning));
        Report.Write("q_tables.csv", qLines);
        Report.Write("learning_curves.csv", LearningLines(settings, learning));
        Report.Write("evaluation.txt",
                     EvaluationLines(model, settings, vi, optimalQ, optimalPolicy, policies, learning));
    }
}
