import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
public final class Main {
    static final String[] METHODS = {"mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q"};
    static final String[] POLICIES = {"value_iteration", "policy_iteration", "mc",    "sarsa",
                                      "q_learning",      "expected_sarsa",   "dyna_q"};
    static final class Settings {
        final Map<String, long[]> entries = new HashMap<>();
        Settings() throws IOException {
            for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
                String[] parts = line.split(" ");
                long[] values = new long[parts.length - 1];
                for (int i = 1; i < parts.length; i++)
                    values[i - 1] = Long.parseLong(parts[i]);
                entries.put(parts[0], values);
            }
        }
        int get(String key) {
            return (int)entries.get(key)[0];
        }
        long[] values(String key) {
            return entries.get(key);
        }
        int schedule(String key, int episode) {
            long[] values = values(key);
            int result = (int)values[1];
            for (int i = 0; i < values.length; i += 2)
                if (values[i] <= episode)
                    result = (int)values[i + 1];
            return result;
        }
    }
    record Episode(long total, int steps, int ending) {}
    record Block(long total, long steps, int goals, int pits, int timeouts, int agree, long error,
                 int coverage) {}
    record Route(List<Integer> cells, String ending) {
        int steps() {
            return cells.size() - 1;
        }
        int last() {
            return cells.getLast();
        }
    }
    static final class Learning {
        final String name;
        final long[][] q, visits;
        final List<Episode> episodes = new ArrayList<>();
        final List<Block> blocks = new ArrayList<>();
        List<Integer> last = new ArrayList<>();
        int[] policy;
        Learning(String name, int size) {
            this.name = name;
            q = new long[size][4];
            visits = new long[size][4];
        }
    }
    static long sum(long[] values) {
        long total = 0;
        for (long value : values)
            total += value;
        return total;
    }
    static int agree(Environment world, int[] first, int[] second) {
        int total = 0;
        for (int x : world.states)
            if (first[x] == second[x])
                total++;
        return total;
    }
    static int[] greedy(Environment world, long[][] q) {
        int[] policy = new int[world.size];
        for (int x : world.states)
            policy[x] = DynamicProgramming.first(q[x]);
        return policy;
    }
    static int ending(Environment world, int x) {
        return world.cells[x] == 'G' ? 0 : world.cells[x] == 'P' ? 1 : 2;
    }
    static String endingName(int kind) {
        return new String[] {"goal", "pit", "timeout"}[kind];
    }
    static Learning learn(String name, Environment.Model model, Settings settings, long[] optimal,
                          int[] optimalPolicy) {
        Environment world = model.world;
        int gamma = settings.get("GAMMA"), limit = settings.get("STEP_LIMIT"),
            blockSize = settings.get("BLOCK_SIZE"), count = settings.get("EPISODES");
        Learning learning = new Learning(name, world.size);
        long[][] sums = new long[world.size][4], counts = new long[world.size][4];
        Environment.Rng rng = new Environment.Rng(settings.get("SEED"));
        TdLearning.Dyna dyna = new TdLearning.Dyna(world.size);
        for (int episode = 1; episode <= count; episode++) {
            int alpha = settings.schedule("ALPHA", episode), epsilon = settings.schedule("EPSILON", episode),
                x = world.start,
                action = name.equals("sarsa") ? TdLearning.choose(learning.q, x, epsilon, rng) : 0;
            long total = 0;
            List<MonteCarlo.Step> records = new ArrayList<>();
            List<Integer> cells = new ArrayList<>(List.of(x));
            int steps = 0;
            while (steps < limit) {
                if (!name.equals("sarsa"))
                    action = TdLearning.choose(learning.q, x, epsilon, rng);
                int y = model.step(x, action, rng);
                learning.visits[x][action]++;
                long reward = world.rewards[y];
                total += reward;
                steps++;
                cells.add(y);
                if (name.equals("mc"))
                    records.add(new MonteCarlo.Step(x, action, reward));
                else {
                    int nextAction = name.equals("sarsa") && !world.terminal(y)
                                         ? TdLearning.choose(learning.q, y, epsilon, rng)
                                         : 0;
                    long nextValue = world.terminal(y)      ? 0
                                     : name.equals("sarsa") ? learning.q[y][nextAction]
                                                            : TdLearning.next(learning.q[y], epsilon,
                                                                              name.equals("expected_sarsa"));
                    TdLearning.update(learning.q, world, x, action, y, nextValue, gamma, alpha);
                    if (name.equals("dyna_q")) {
                        dyna.observe(x, action, y);
                        dyna.plan(learning.q, world, settings.get("PLANNING_STEPS"), gamma, alpha, rng);
                    }
                    action = nextAction;
                }
                x = y;
                if (world.terminal(x))
                    break;
            }
            if (name.equals("mc"))
                MonteCarlo.update(learning.q, sums, counts, records, gamma);
            learning.episodes.add(new Episode(total, steps, ending(world, x)));
            if (episode == count)
                learning.last = cells;
            if (episode % blockSize == 0) {
                long blockTotal = 0, blockSteps = 0, error = 0;
                int[] endings = new int[3];
                int agreement = 0, coverage = 0;
                for (int i = episode - blockSize; i < episode; i++) {
                    Episode record = learning.episodes.get(i);
                    blockTotal += record.total;
                    blockSteps += record.steps;
                    endings[record.ending]++;
                }
                for (int state : world.states) {
                    int best = DynamicProgramming.first(learning.q[state]);
                    if (best == optimalPolicy[state])
                        agreement++;
                    error += Math.abs(learning.q[state][best] - optimal[state]);
                    if (sum(learning.visits[state]) > 0)
                        coverage++;
                }
                learning.blocks.add(new Block(blockTotal, blockSteps, endings[0], endings[1], endings[2],
                                              agreement, DynamicProgramming.floor(error, world.states.length),
                                              coverage));
            }
        }
        learning.policy = greedy(world, learning.q);
        return learning;
    }
    static Route route(Environment world, int[] policy, int start, int limit) {
        List<Integer> cells = new ArrayList<>(List.of(start));
        Set<Integer> seen = new HashSet<>();
        seen.add(start);
        int x = start;
        while (true) {
            int y = world.moves[x][policy[x]];
            boolean repeated = seen.contains(y);
            cells.add(y);
            if (world.terminal(y))
                return new Route(cells, endingName(ending(world, y)));
            if (repeated)
                return new Route(cells, "loop");
            if (cells.size() - 1 >= limit)
                return new Route(cells, "limit");
            seen.add(y);
            x = y;
        }
    }
    static String cells(Environment world, List<Integer> cells) {
        List<String> result = new ArrayList<>();
        for (int x : cells)
            result.add(Report.cell(world, x));
        return String.join(" ", result);
    }
    static int[] distances(Environment.Model model) {
        Environment world = model.world;
        int[] distances = new int[world.size];
        Arrays.fill(distances, -1);
        distances[world.start] = 0;
        ArrayDeque<Integer> queue = new ArrayDeque<>();
        queue.add(world.start);
        while (!queue.isEmpty()) {
            int x = queue.removeFirst();
            if (world.terminal(x))
                continue;
            for (int a = 0; a < 4; a++)
                for (Environment.Outcome transition : model.transitions[x][a]) {
                    int y = transition.cell();
                    if (distances[y] < 0) {
                        distances[y] = distances[x] + 1;
                        queue.addLast(y);
                    }
                }
        }
        return distances;
    }
    static long[] absorption(Environment.Model model, int[] policy, int limit) {
        Environment world = model.world;
        long[] goals = new long[world.size], pits = new long[world.size], steps = new long[world.size];
        for (int k = 0; k < limit; k++) {
            long[] nextGoals = new long[world.size], nextPits = new long[world.size],
                   nextSteps = new long[world.size];
            for (int x : world.states) {
                long g = 0, p = 0, e = 0;
                for (Environment.Outcome t : model.transitions[x][policy[x]]) {
                    int y = t.cell();
                    g += t.weight() * (world.cells[y] == 'G' ? 100000000 : world.terminal(y) ? 0 : goals[y]);
                    p += t.weight() * (world.cells[y] == 'P' ? 100000000 : world.terminal(y) ? 0 : pits[y]);
                    e += t.weight() * (world.terminal(y) ? 0 : steps[y]);
                }
                nextGoals[x] = g / model.q;
                nextPits[x] = p / model.q;
                nextSteps[x] = 100000000 + e / model.q;
            }
            goals = nextGoals;
            pits = nextPits;
            steps = nextSteps;
        }
        return new long[] {goals[world.start] / 10000, pits[world.start] / 10000,
                           (100000000 - goals[world.start] - pits[world.start]) / 10000,
                           steps[world.start] / 10000};
    }
    static DynamicProgramming.Evaluation behaviour(Environment.Model model, int[] policy, Settings settings) {
        Environment world = model.world;
        long[] values = new long[world.size];
        int sweeps = 0, epsilon = settings.schedule("EPSILON", settings.get("EPISODES"));
        while (true) {
            long delta = 0;
            for (int x : world.states) {
                long weighted = 0;
                for (int a = 0; a < 4; a++)
                    weighted += (epsilon + (a == policy[x] ? 4L * (1000 - epsilon) : 0)) *
                                DynamicProgramming.bellman(model, values, x, a, settings.get("GAMMA"));
                long v = DynamicProgramming.floor(weighted, 4000);
                delta = Math.max(delta, Math.abs(v - values[x]));
                values[x] = v;
            }
            sweeps++;
            if (delta <= settings.values("THETA")[0])
                return new DynamicProgramming.Evaluation(values, sweeps);
        }
    }
    static final class Rollouts {
        long total, discounted, steps;
        final int[] endings = new int[3], terminals;
        final List<Long> returns = new ArrayList<>();
        Rollouts(int count) {
            terminals = new int[count];
        }
    }
    static Rollouts rollouts(Environment.Model model, int[] policy, Settings settings) {
        Environment world = model.world;
        Environment.Rng rng = new Environment.Rng(settings.get("ROLLOUT_SEED"));
        Rollouts result = new Rollouts(world.terminals.length);
        for (int i = 0; i < settings.get("ROLLOUTS"); i++) {
            int x = world.start, steps = 0;
            List<Long> rewards = new ArrayList<>();
            long total = 0;
            while (steps < settings.get("STEP_LIMIT")) {
                x = model.step(x, policy[x], rng);
                rewards.add(world.rewards[x]);
                total += world.rewards[x];
                steps++;
                if (world.terminal(x))
                    break;
            }
            result.total += total;
            result.discounted += MonteCarlo.discounted(rewards, settings.get("GAMMA"));
            result.steps += steps;
            result.endings[ending(world, x)]++;
            result.returns.add(total);
            for (int j = 0; j < world.terminals.length; j++)
                if (x == world.terminals[j])
                    result.terminals[j]++;
        }
        Collections.sort(result.returns);
        return result;
    }
    static void part(List<String> output, List<String> lines) {
        if (!output.isEmpty())
            output.add("");
        output.addAll(lines);
    }
    static int maxIndex(Environment world, long[] values) {
        int best = world.states[0];
        for (int x : world.states)
            if (values[x] > values[best])
                best = x;
        return best;
    }
    static List<String> valueLines(Environment.Model model, Settings settings,
                                   DynamicProgramming.Iteration vi, DynamicProgramming.Iteration inPlace,
                                   DynamicProgramming.PolicyIteration pi, long[][] q, int[] optimalPolicy,
                                   int[] distance) {
        Environment world = model.world;
        List<String> output = new ArrayList<>(), section = new ArrayList<>();
        int walls = 0, floor = 0, ice = 0, goals = 0, pits = 0, reachable = 0;
        for (char c : world.cells) {
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
        for (int x : world.states)
            if (distance[x] >= 0)
                reachable++;
        section.add("world rows " + world.height + " cols " + world.width + " states " + world.states.length +
                    " walls " + walls + " floor " + floor + " ice " + ice + " goals " + goals + " pits " +
                    pits);
        section.add("start " + Report.cell(world, world.start) + " reachable " + reachable);
        for (int x : world.terminals)
            section.add("terminal " + Report.cell(world, x) + " " + endingName(ending(world, x)) +
                        " reward " + world.rewards[x] + " distance " + (distance[x] < 0 ? "-" : distance[x]));
        part(output, section);
        section = new ArrayList<>();
        section.add("value_iteration gamma " + settings.get("GAMMA") + " theta " +
                    Report.fixed(settings.values("THETA")[0]) + " iterations " + vi.changes().size());
        for (int k = 0; k < vi.changes().size(); k++)
            section.add("iteration " + (k + 1) + " max_change " + Report.fixed(vi.changes().get(k)));
        part(output, section);
        section = new ArrayList<>(List.of("optimal_values"));
        section.addAll(Report.grid(world, true, x -> Report.fixed(vi.values()[x])));
        part(output, section);
        int[] optimalCounts = new int[world.size];
        List<String> ties = new ArrayList<>();
        for (int x : world.states) {
            StringBuilder actions = new StringBuilder();
            for (int a = 0; a < 4; a++)
                if (q[x][a] == q[x][optimalPolicy[x]]) {
                    optimalCounts[x]++;
                    actions.append("NESW".charAt(a));
                }
            if (optimalCounts[x] > 1)
                ties.add("tie " + Report.cell(world, x) + " " + actions);
        }
        section = new ArrayList<>(List.of("optimal_action_counts"));
        section.addAll(Report.grid(world, false, x -> Integer.toString(optimalCounts[x])));
        part(output, section);
        section = new ArrayList<>(List.of("ties " + ties.size()));
        section.addAll(ties);
        int pairs = 0, equal = 0, mirrored = 0;
        int[] mirror = {0, 3, 2, 1};
        Set<Integer> nonterminal = new HashSet<>();
        for (int x : world.states)
            nonterminal.add(x);
        for (int x : world.states) {
            int row = x / world.width, column = x % world.width,
                other = row * world.width + world.width - 1 - column;
            if (column < world.width - 1 - column && nonterminal.contains(other)) {
                pairs++;
                if (vi.values()[x] == vi.values()[other])
                    equal++;
                if (optimalPolicy[other] == mirror[optimalPolicy[x]])
                    mirrored++;
            }
        }
        section.add("symmetry pairs " + pairs + " equal_values " + equal + " mirrored_actions " + mirrored);
        part(output, section);
        section = new ArrayList<>(List.of("policy_iteration rounds " + pi.rounds().size()));
        long evaluationSweeps = 0;
        for (int i = 0; i < pi.rounds().size(); i++) {
            DynamicProgramming.Round round = pi.rounds().get(i);
            evaluationSweeps += round.sweeps();
            section.add("round " + (i + 1) + " sweeps " + round.sweeps() + " changed " + round.changes() +
                        " value_start " + Report.fixed(round.value()));
        }
        part(output, section);
        section = new ArrayList<>(List.of("policy_iteration_values"));
        section.addAll(Report.grid(world, true, x -> Report.fixed(pi.values()[x])));
        part(output, section);
        long[] differences = new long[world.size];
        for (int x : world.states)
            differences[x] = Math.abs(pi.values()[x] - vi.values()[x]);
        int at = maxIndex(world, differences);
        long n = world.states.length;
        part(output,
             List.of("comparison policy_differences " +
                         (world.states.length - agree(world, pi.policy(), optimalPolicy)) +
                         " max_value_difference " + Report.fixed(differences[at]) + " at " +
                         Report.cell(world, at),
                     "backups value_iteration " + vi.changes().size() * n * 4 + " in_place_iterations " +
                         inPlace.changes().size() + " in_place " + inPlace.changes().size() * n * 4 +
                         " policy_iteration " + (evaluationSweeps * n + pi.rounds().size() * n * 4)));
        section = new ArrayList<>(List.of("gamma_sweep"));
        for (long gamma : settings.values("GAMMA_SWEEP"))
            section.add(sensitivity("gamma " + gamma, model, settings, (int)gamma, optimalPolicy));
        part(output, section);
        section = new ArrayList<>(List.of("slip_sweep"));
        long[] slips = settings.values("SLIP_SWEEP");
        for (int i = 0; i < slips.length; i += 2) {
            Environment.Model changed =
                new Environment.Model(world, model.q, (int)slips[i], (int)slips[i + 1]);
            section.add(sensitivity("slip " + slips[i] + " " + slips[i + 1], changed, settings,
                                    settings.get("GAMMA"), optimalPolicy));
        }
        part(output, section);
        return output;
    }
    static String sensitivity(String prefix, Environment.Model model, Settings settings, int gamma,
                              int[] optimalPolicy) {
        DynamicProgramming.Iteration iteration =
            DynamicProgramming.iterate(model, gamma, settings.values("THETA")[0], false);
        int[] policy = DynamicProgramming.policy(model, iteration.values(), gamma);
        Route route = route(model.world, policy, model.world.start, settings.get("STEP_LIMIT"));
        return prefix + " iterations " + iteration.changes().size() + " value_start " +
            Report.fixed(iteration.values()[model.world.start]) + " path " + route.ending + " steps " +
            route.steps() + " last " + Report.cell(model.world, route.last()) + " differences " +
            (model.world.states.length - agree(model.world, policy, optimalPolicy));
    }
    static List<String> policyLines(Environment.Model model, Settings settings, List<int[]> policies,
                                    List<Learning> learning) {
        Environment world = model.world;
        List<String> output = new ArrayList<>();
        int limit = settings.get("STEP_LIMIT");
        for (int i = 0; i < policies.size(); i++) {
            int[] policy = policies.get(i);
            List<String> section = new ArrayList<>(List.of(POLICIES[i]));
            section.addAll(Report.grid(world, false, x -> Character.toString("^>v<".charAt(policy[x]))));
            Route route = route(world, policy, world.start, limit);
            section.add("path " + route.ending + " steps " + route.steps() + " " + cells(world, route.cells));
            int[] counts = new int[4];
            int risk = 0;
            for (int x : world.states) {
                counts[policy[x]]++;
                boolean risky = false;
                for (Environment.Outcome t : model.transitions[x][policy[x]])
                    if (world.cells[t.cell()] == 'P')
                        risky = true;
                if (risky)
                    risk++;
            }
            section.add("actions N " + counts[0] + " E " + counts[1] + " S " + counts[2] + " W " + counts[3] +
                        " risk " + risk);
            section.add("basins");
            section.addAll(Report.grid(world, false, x -> {
                Route basin = route(world, policy, x, limit);
                if (!world.terminal(basin.last()))
                    return "*";
                int terminal = 0;
                while (world.terminals[terminal] != basin.last())
                    terminal++;
                return Character.toString((char)('a' + terminal));
            }));
            if (i >= 2) {
                Learning result = learning.get(i - 2);
                section.add("visits");
                section.addAll(Report.grid(world, false, x -> {
                    long count = sum(result.visits[x]);
                    return count == 0 ? "0" : Integer.toString(Long.toString(count).length());
                }));
            }
            part(output, section);
        }
        return output;
    }
    static List<String> learningLines(Settings settings, List<Learning> learning) {
        List<String> output = new ArrayList<>(
            List.of("method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"));
        int count = settings.get("BLOCK_SIZE");
        for (Learning result : learning)
            for (int i = 0; i < result.blocks.size(); i++) {
                Block b = result.blocks.get(i);
                output.add(result.name + "," + (i + 1) + "," + Report.average(b.total, count) + "," +
                           Report.average(b.steps, count) + "," + b.goals + "," + b.pits + "," + b.timeouts +
                           "," + b.agree + "," + Report.fixed(b.error) + "," + b.coverage);
            }
        return output;
    }
    static List<String> evaluationLines(Environment.Model model, Settings settings,
                                        DynamicProgramming.Iteration vi, long[][] optimalQ,
                                        int[] optimalPolicy, List<int[]> policies, List<Learning> learning) {
        Environment world = model.world;
        List<String> output = new ArrayList<>();
        part(output,
             List.of("summary states " + world.states.length + " start " + Report.cell(world, world.start) +
                     " rollouts " + settings.get("ROLLOUTS") + " step_limit " + settings.get("STEP_LIMIT")));
        List<String>
            policyValues = new ArrayList<>(
                List.of("policies", "policy agree optimal_actions value_start sweeps max_gap at")),
            improvements = new ArrayList<>(List.of("improvement", "policy changed value_start agree")),
            absorptions =
                new ArrayList<>(List.of("absorption", "policy p_goal p_pit p_timeout expected_steps")),
            behaviours = new ArrayList<>(List.of("behaviour", "method epsilon value_start sweeps")),
            qErrors = new ArrayList<>(List.of("q_errors", "method mean_abs max_abs at unvisited tied")),
            actionErrors = new ArrayList<>(List.of("q_action_errors", "method N E S W")),
            rolloutLines = new ArrayList<>(
                List.of("rollouts",
                        "policy mean_return mean_discounted mean_steps goals pits timeouts min median max")),
            terminalLines = new ArrayList<>(List.of("terminals")),
            agreementLines = new ArrayList<>(List.of("agreement", "policy " + String.join(" ", POLICIES))),
            training = new ArrayList<>(
                List.of("training", "method steps goals pits timeouts best_block best_mean last_mean reach")),
            visited = new ArrayList<>(List.of("visited")),
            lastEpisodes = new ArrayList<>(List.of("last_episodes")),
            phases = new ArrayList<>(List.of("phases"));
        String terminalHeader = "policy";
        for (int x : world.terminals)
            terminalHeader += " " + Report.cell(world, x);
        terminalLines.add(terminalHeader);
        List<Rollouts> rolloutResults = new ArrayList<>();
        int m = settings.get("ROLLOUTS"), limit = settings.get("STEP_LIMIT"), gamma = settings.get("GAMMA");
        long theta = settings.values("THETA")[0];
        for (int i = 0; i < policies.size(); i++) {
            int[] policy = policies.get(i);
            String name = POLICIES[i];
            DynamicProgramming.Evaluation evaluation =
                DynamicProgramming.evaluate(model, policy, gamma, theta, new long[world.size]);
            long[] gaps = new long[world.size];
            int optimalActions = 0;
            for (int x : world.states) {
                gaps[x] = vi.values()[x] - evaluation.values()[x];
                if (optimalQ[x][policy[x]] == optimalQ[x][optimalPolicy[x]])
                    optimalActions++;
            }
            int at = maxIndex(world, gaps);
            policyValues.add(name + " " + agree(world, policy, optimalPolicy) + " " + optimalActions + " " +
                             Report.fixed(evaluation.values()[world.start]) + " " + evaluation.sweeps() +
                             " " + Report.fixed(gaps[at]) + " " + Report.cell(world, at));
            int[] improved = DynamicProgramming.policy(model, evaluation.values(), gamma);
            DynamicProgramming.Evaluation improvedValue =
                DynamicProgramming.evaluate(model, improved, gamma, theta, new long[world.size]);
            improvements.add(name + " " + (world.states.length - agree(world, policy, improved)) + " " +
                             Report.fixed(improvedValue.values()[world.start]) + " " +
                             agree(world, improved, optimalPolicy));
            String absorptionLine = name;
            for (long value : absorption(model, policy, limit))
                absorptionLine += " " + Report.fixed(value);
            absorptions.add(absorptionLine);
            if (i >= 2) {
                Learning result = learning.get(i - 2);
                DynamicProgramming.Evaluation behaviour = behaviour(model, policy, settings);
                behaviours.add(name + " " + settings.schedule("EPSILON", settings.get("EPISODES")) + " " +
                               Report.fixed(behaviour.values()[world.start]) + " " + behaviour.sweeps());
                long[] errors = new long[world.size];
                long total = 0;
                int unvisited = 0, tied = 0;
                for (int x : world.states) {
                    long maximum = result.q[x][policy[x]];
                    errors[x] = Math.abs(maximum - vi.values()[x]);
                    total += errors[x];
                    if (sum(result.visits[x]) == 0)
                        unvisited++;
                    int ties = 0;
                    for (long value : result.q[x])
                        if (value == maximum)
                            ties++;
                    if (ties > 1)
                        tied++;
                }
                at = maxIndex(world, errors);
                qErrors.add(name + " " + Report.fixed(DynamicProgramming.floor(total, world.states.length)) +
                            " " + Report.fixed(errors[at]) + " " + Report.cell(world, at) + " " + unvisited +
                            " " + tied);
                String actionLine = name;
                for (int a = 0; a < 4; a++) {
                    long error = 0;
                    int count = 0;
                    for (int x : world.states)
                        if (result.visits[x][a] > 0) {
                            count++;
                            error += Math.abs(result.q[x][a] - optimalQ[x][a]);
                        }
                    actionLine +=
                        " " + (count == 0 ? "-" : Report.fixed(DynamicProgramming.floor(error, count)));
                }
                actionErrors.add(actionLine);
            }
            Rollouts rollouts = rollouts(model, policy, settings);
            rolloutResults.add(rollouts);
            rolloutLines.add(name + " " + Report.average(rollouts.total, m) + " " +
                             Report.fixed(DynamicProgramming.floor(rollouts.discounted, m)) + " " +
                             Report.average(rollouts.steps, m) + " " + rollouts.endings[0] + " " +
                             rollouts.endings[1] + " " + rollouts.endings[2] + " " +
                             rollouts.returns.getFirst() + " " + rollouts.returns.get((m - 1) / 2) + " " +
                             rollouts.returns.getLast());
            String terminalLine = name;
            for (int count : rollouts.terminals)
                terminalLine += " " + count;
            terminalLines.add(terminalLine);
            String agreementLine = name;
            for (int[] other : policies)
                agreementLine += " " + agree(world, policy, other);
            agreementLines.add(agreementLine);
        }
        int blockSize = settings.get("BLOCK_SIZE"), episodeCount = settings.get("EPISODES");
        SortedSet<Integer> phaseStarts = new TreeSet<>();
        for (String schedule : List.of("ALPHA", "EPSILON")) {
            long[] values = settings.values(schedule);
            for (int i = 0; i < values.length; i += 2)
                phaseStarts.add((int)values[i]);
        }
        List<Integer> starts = new ArrayList<>(phaseStarts);
        for (Learning result : learning) {
            long steps = 0;
            int[] endings = new int[3];
            for (Episode episode : result.episodes) {
                steps += episode.steps;
                endings[episode.ending]++;
            }
            int best = 0;
            String reach = "-";
            for (int j = 0; j < result.blocks.size(); j++) {
                if (result.blocks.get(j).total > result.blocks.get(best).total)
                    best = j;
                if (reach.equals("-") &&
                    10L * m * result.blocks.get(j).total >= 9L * blockSize * rolloutResults.getFirst().total)
                    reach = Integer.toString(j + 1);
            }
            training.add(result.name + " " + steps + " " + endings[0] + " " + endings[1] + " " + endings[2] +
                         " " + (best + 1) + " " + Report.average(result.blocks.get(best).total, blockSize) +
                         " " + Report.average(result.blocks.getLast().total, blockSize) + " " + reach);
            List<Integer> ordered = new ArrayList<>();
            for (int x : world.states)
                ordered.add(x);
            ordered.sort(Comparator.<Integer>comparingLong(x -> sum(result.visits[x]))
                             .reversed()
                             .thenComparingInt(x -> x));
            String visitLine = result.name;
            for (int i = 0; i < 3; i++) {
                int x = ordered.get(i);
                visitLine += " " + Report.cell(world, x) + ":" + sum(result.visits[x]);
            }
            visited.add(visitLine);
            Episode last = result.episodes.getLast();
            lastEpisodes.add(result.name + " return " + last.total + " steps " + last.steps + " end " +
                             endingName(last.ending) + " " + cells(world, result.last));
            for (int i = 0; i < starts.size(); i++) {
                int start = starts.get(i), end = i + 1 < starts.size() ? starts.get(i + 1) - 1 : episodeCount;
                long total = 0, phaseSteps = 0;
                int goals = 0;
                for (int e = start; e <= end; e++) {
                    Episode episode = result.episodes.get(e - 1);
                    total += episode.total;
                    phaseSteps += episode.steps;
                    if (episode.ending == 0)
                        goals++;
                }
                phases.add(result.name + " " + start + "-" + end + " alpha " +
                           settings.schedule("ALPHA", start) + " epsilon " +
                           settings.schedule("EPSILON", start) + " mean_return " +
                           Report.average(total, end - start + 1) + " mean_steps " +
                           Report.average(phaseSteps, end - start + 1) + " goals " + goals);
            }
        }
        for (List<String> section :
             List.of(policyValues, improvements, absorptions, behaviours, qErrors, actionErrors, rolloutLines,
                     terminalLines, agreementLines, training, visited, lastEpisodes, phases))
            part(output, section);
        return output;
    }
    public static void main(String[] args) throws IOException {
        Settings settings = new Settings();
        Environment world = new Environment(settings.get("STEP_REWARD"));
        long[] slip = settings.values("SLIP");
        Environment.Model model = new Environment.Model(world, (int)slip[0], (int)slip[1], (int)slip[2]);
        int gamma = settings.get("GAMMA");
        long theta = settings.values("THETA")[0];
        DynamicProgramming.Iteration vi = DynamicProgramming.iterate(model, gamma, theta, false),
                                     inPlace = DynamicProgramming.iterate(model, gamma, theta, true);
        DynamicProgramming.PolicyIteration pi = DynamicProgramming.policyIteration(model, gamma, theta);
        long[][] optimalQ = new long[world.size][4];
        for (int x : world.states)
            optimalQ[x] = DynamicProgramming.actions(model, vi.values(), x, gamma);
        int[] optimalPolicy = greedy(world, optimalQ);
        List<Learning> learning = new ArrayList<>();
        List<int[]> policies = new ArrayList<>();
        policies.add(optimalPolicy);
        policies.add(pi.policy());
        for (String method : METHODS) {
            Learning result = learn(method, model, settings, vi.values(), optimalPolicy);
            learning.add(result);
            policies.add(result.policy);
        }
        List<String> qLines = new ArrayList<>(List.of("method,row,col,action,value,visits"));
        Report.qRows(qLines, "value_iteration", world, optimalQ, null);
        for (Learning result : learning)
            Report.qRows(qLines, result.name, world, result.q, result.visits);
        Files.createDirectories(Path.of("output"));
        Report.write("values.txt",
                     valueLines(model, settings, vi, inPlace, pi, optimalQ, optimalPolicy, distances(model)));
        Report.write("policies.txt", policyLines(model, settings, policies, learning));
        Report.write("q_tables.csv", qLines);
        Report.write("learning_curves.csv", learningLines(settings, learning));
        Report.write("evaluation.txt",
                     evaluationLines(model, settings, vi, optimalQ, optimalPolicy, policies, learning));
    }
}
