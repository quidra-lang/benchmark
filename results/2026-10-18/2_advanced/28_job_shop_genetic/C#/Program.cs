using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program {
    public static void Swap<T>(List<T> values, int first, int second) {
        (values[first], values[second]) = (values[second], values[first]);
    }
    public static T RemoveAt<T>(List<T> values, int index) {
        T value = values[index];
        values.RemoveAt(index);
        return value;
    }
    static readonly string[] RULES = { "SPT", "LPT", "MWKR", "FIFO" };
    sealed record Move(int first, int second);
    sealed record Shift(int ident, int oldStart, int newStart);
    sealed record Iteration(int number, int moves, int tabu, Move move, bool aspiration, int value, int best);
    sealed record Baseline(string rule, Schedule schedule, Dispatch dispatch, Search search);
    sealed class Params {
        public readonly Dictionary<string, string[]> values = new();
        public Params() {
            foreach (string line in File.ReadAllLines(Path.Combine("input/ga_params.txt"), Encoding.ASCII)) {
                string[] fields = line.Split(" ");
                values[fields[0]] = fields[1..fields.Length];
            }
        }
        public int Value(string key) {
            return int.Parse(values[key][0]);
        }
        public int[] Fraction(string key) {
            string[] fields = values[key][0].Split("/");
            return new int[] { int.Parse(fields[0]), int.Parse(fields[1]) };
        }
    }
    static string Percent(int part, int whole) {
        int value = (2000 * part + whole) / (2 * whole);
        return value / 10 + "." + value % 10 + "%";
    }
    static char Letter(int number) {
        return (char)('A' + number - 1);
    }
    static int Sum(int[] values) {
        int total = 0;
        foreach (int value in values)
            total += value;
        return total;
    }
    static int Maximum(int[] values) {
        int best = values[0];
        foreach (int value in values)
            best = Math.Max(best, value);
        return best;
    }
    static int Minimum(int[] values) {
        int best = values[0];
        foreach (int value in values)
            best = Math.Min(best, value);
        return best;
    }
    static int Gcd(int a, int b) {
        while (b != 0) {
            int old = b;
            b = a % b;
            a = old;
        }
        return a;
    }
    static string Genes(List<int> chromosome) {
        List<string> values = new();
        foreach (int gene in chromosome)
            values.Add(Convert.ToString(gene));
        return string.Join(" ", values);
    }
    static List<List<int>> Copy(List<List<int>> order) {
        List<List<int>> result = new();
        foreach (List<int> sequence in order)
            result.Add(sequence.ToList());
        return result;
    }
    static int[] OrderStarts(Instance instance, List<List<int>> order, int[] durations) {
        int[] starts = new int[durations.Length], completions = new int[durations.Length],
              positions = new int[instance.machineCount];
        Array.Fill(starts, -1);
        int placed = 0;
        while (placed < starts.Length)
            for (int m = 0; m < instance.machineCount; m++) {
                List<int> sequence = order[m];
                while (positions[m] < sequence.Count) {
                    int position = positions[m], ident = sequence[position],
                        previous = instance.operations[ident].previous;
                    if (previous >= 0 && starts[previous] < 0)
                        break;
                    starts[ident] = Math.Max(previous < 0 ? 0 : completions[previous],
                                             position == 0 ? 0 : completions[sequence[position - 1]]);
                    completions[ident] = starts[ident] + durations[ident];
                    positions[m]++;
                    placed++;
                }
            }
        return starts;
    }
    static int Makespan(int[] starts, int[] durations) {
        int value = 0;
        for (int i = 0; i < starts.Length; i++)
            value = Math.Max(value, starts[i] + durations[i]);
        return value;
    }
    static Schedule CreateSchedule(Instance instance, List<List<int>> order) {
        return new Schedule(instance, OrderStarts(instance, order, instance.durations));
    }
    static int Evaluate(Instance instance, List<List<int>> order, int[] durations) {
        return Makespan(OrderStarts(instance, order, durations), durations);
    }
    static List<List<int>> Apply(Instance instance, List<List<int>> order, Move move) {
        List<List<int>> result = Copy(order);
        List<int> sequence = result[instance.operations[move.first].machine - 1];
        int position = sequence.IndexOf(move.first);
        Program.Swap(sequence, position, position + 1);
        return result;
    }
    static int[] Distances(Schedule first, Schedule second) {
        int[] values = new int[first.instance.machineCount], rank = new int[first.starts.Length];
        for (int m = 0; m < values.Length; m++) {
            List<int> sequence = second.order[m];
            for (int i = 0; i < sequence.Count; i++)
                rank[sequence[i]] = i;
            sequence = first.order[m];
            for (int i = 0; i < sequence.Count; i++)
                for (int j = i + 1; j < sequence.Count; j++)
                    if (rank[sequence[i]] > rank[sequence[j]])
                        values[m]++;
        }
        return values;
    }
    static int Jackson(Machine machine) {
        List<Operation> tasks = machine.operations;
        int[] remaining = new int[tasks.Count];
        for (int i = 0; i < tasks.Count; i++)
            remaining[i] = tasks[i].duration;
        int time = 0, bound = 0;
        while (Sum(remaining) != 0) {
            int release = int.MaxValue;
            for (int i = 0; i < tasks.Count; i++)
                if (remaining[i] > 0)
                    release = Math.Min(release, tasks[i].head);
            time = Math.Max(time, release);
            int selected = -1;
            for (int i = 0; i < tasks.Count; i++)
                if (remaining[i] > 0 && tasks[i].head <= time &&
                    (selected < 0 || tasks[i].tail > tasks[selected].tail))
                    selected = i;
            int delta = remaining[selected];
            foreach (Operation task in tasks)
                if (task.head > time)
                    delta = Math.Min(delta, task.head - time);
            time += delta;
            remaining[selected] -= delta;
            if (remaining[selected] == 0)
                bound = Math.Max(bound, time + tasks[selected].tail);
        }
        return bound;
    }
    sealed class Schedule {
        public readonly Instance instance;
        public readonly int[] starts, completions, machinePrevious, machineNext;
        public readonly int makespan;
        public readonly List<int> byStart = new();
        public readonly List<List<int>> order = new();
        public Schedule(Instance instance, int[] starts) {
            this.instance = instance;
            this.starts = starts;
            completions = new int[starts.Length];
            machinePrevious = new int[starts.Length];
            machineNext = new int[starts.Length];
            Array.Fill(machinePrevious, -1);
            Array.Fill(machineNext, -1);
            for (int i = 0; i < starts.Length; i++) {
                completions[i] = starts[i] + instance.durations[i];
                byStart.Add(i);
            }
            makespan = Maximum(completions);
            byStart.Sort((first, second) => starts[first] != starts[second]
                                                ? starts[first].CompareTo(starts[second])
                                                : first.CompareTo(second));
            for (int m = 0; m < instance.machineCount; m++)
                order.Add(new());
            foreach (int ident in byStart)
                order[instance.operations[ident].machine - 1].Add(ident);
            foreach (List<int> sequence in order)
                for (int i = 1; i < sequence.Count; i++) {
                    machinePrevious[sequence[i]] = sequence[i - 1];
                    machineNext[sequence[i - 1]] = sequence[i];
                }
        }
        public List<int> Chromosome() {
            List<int> genes = new();
            foreach (int ident in byStart)
                genes.Add(instance.operations[ident].job);
            return genes;
        }
        public List<int> Path() {
            int current = 0;
            while (completions[current] != makespan)
                current++;
            List<int> path = new();
            path.Add(current);
            while (starts[current] != 0) {
                int previous = machinePrevious[current];
                current = previous >= 0 && completions[previous] == starts[current]
                              ? previous
                              : instance.operations[current].previous;
                path.Add(current);
            }
            path.Reverse();
            return path;
        }
        public List<List<int>> Blocks() {
            List<List<int>> blocks = new();
            foreach (int ident in Path()) {
                if (blocks.Count == 0 ||
                    instance.operations[blocks[^1][^1]].machine != instance.operations[ident].machine)
                    blocks.Add(new());
                blocks[^1].Add(ident);
            }
            return blocks;
        }
        public List<Move> Moves() {
            List<Move> moves = new();
            foreach (List<int> block in Blocks())
                for (int i = 1; i < block.Count; i++)
                    moves.Add(new Move(block[i - 1], block[i]));
            return moves;
        }
        public int PathCount() {
            int[] ways = new int[starts.Length];
            int total = 0;
            foreach (int ident in byStart) {
                if (starts[ident] == 0)
                    ways[ident] = 1;
                else
                    foreach (int previous in new int[] { instance.operations[ident].previous,
                                                         machinePrevious[ident] })
                        if (previous >= 0 && completions[previous] == starts[ident])
                            ways[ident] += ways[previous];
                if (completions[ident] == makespan)
                    total += ways[ident];
            }
            return total;
        }
        public int[] Shift(int ident) {
            Operation operation = instance.operations[ident];
            List<int> sequence = order[operation.machine - 1];
            int position = sequence.IndexOf(ident),
                ready = operation.previous < 0 ? 0 : completions[operation.previous];
            for (int insert = 0; insert < position; insert++) {
                int low = insert == 0 ? 0 : completions[sequence[insert - 1]],
                    high = starts[sequence[insert]], start = Math.Max(low, ready);
                if (start + operation.duration <= high)
                    return new int[] { start, insert };
            }
            return new int[0];
        }
        public int Shiftable() {
            int count = 0;
            for (int i = 0; i < starts.Length; i++)
                if (Shift(i).Length != 0)
                    count++;
            return count;
        }
        public int[][] Slacks() {
            int[] latest = new int[starts.Length], slack = new int[starts.Length],
                  free = new int[starts.Length];
            for (int position = byStart.Count - 1; position >= 0; position--) {
                int ident = byStart[position], limit = makespan, startLimit = makespan;
                foreach (int next in new int[] { instance.operations[ident].next, machineNext[ident] })
                    if (next >= 0) {
                        limit = Math.Min(limit, latest[next]);
                        startLimit = Math.Min(startLimit, starts[next]);
                    }
                latest[ident] = limit - instance.durations[ident];
                slack[ident] = latest[ident] - starts[ident];
                free[ident] = startLimit - completions[ident];
            }
            return new int[][] { slack, free };
        }
        public int[] PathCounts() {
            int[] counts = new int[instance.machineCount];
            foreach (int ident in Path())
                counts[instance.operations[ident].machine - 1]++;
            return counts;
        }
        public int Bottleneck() {
            int[] counts = PathCounts();
            int best = 0;
            for (int i = 1; i < counts.Length; i++)
                if (counts[i] > counts[best])
                    best = i;
            return best + 1;
        }
        public int Flow() {
            int total = 0;
            foreach (Job job in instance.jobs)
                total += completions[job.operations[^1].ident];
            return total;
        }
        public int Idle() {
            return makespan * instance.machineCount - Sum(instance.durations);
        }
        public string Letters(int machine) {
            StringBuilder text = new StringBuilder();
            foreach (int ident in order[machine - 1])
                text.Append(Letter(instance.operations[ident].job));
            return text.ToString();
        }
    }
    sealed class Search {
        public readonly int start;
        public readonly List<Iteration> records = new();
        public List<List<int>> bestOrder;
        public int best, found;
        public string reason = "limit";
        public Search(Instance instance, List<List<int>> order, Params settings) {
            List<List<int>> current = order;
            bestOrder = order;
            start = Evaluate(instance, order, instance.durations);
            best = start;
            Dictionary<Move, int> expiry = new();
            for (int iteration = 1; iteration <= settings.Value("tabu_iterations"); iteration++) {
                List<Move> moves = CreateSchedule(instance, current).Moves();
                if (moves.Count == 0) {
                    reason = "no_moves";
                    break;
                }
                Move chosen = null;
                int value = int.MaxValue, tabuCount = 0;
                bool aspiration = false;
                foreach (Move move in moves) {
                    int candidate = Evaluate(instance, Apply(instance, current, move), instance.durations);
                    bool tabu = expiry.getOrDefault(move, 0) >= iteration;
                    if (tabu)
                        tabuCount++;
                    if ((!tabu || candidate < best) && candidate < value) {
                        chosen = move;
                        value = candidate;
                        aspiration = tabu;
                    }
                }
                if (chosen == null) {
                    reason = "all_tabu";
                    break;
                }
                current = Apply(instance, current, chosen);
                expiry[new Move(chosen.second, chosen.first)] = iteration + settings.Value("tabu_tenure");
                if (value < best) {
                    bestOrder = current;
                    best = value;
                    found = iteration;
                }
                records.Add(
                    new Iteration(iteration, moves.Count, tabuCount, chosen, aspiration, value, best));
            }
        }
    }
    sealed class Solver {
        public readonly Instance instance;
        public readonly Params settings;
        public readonly List<Baseline> baselines = new();
        public readonly List<int[]> records = new();
        public readonly List<string> progress = new(["generation,best,mean,worst,distinct"]);
        public readonly List<Shift> shifts = new();
        public readonly int[] jacksons;
        public readonly Job jobBound;
        public readonly Machine machineBound;
        public readonly int jacksonMachine, lower;
        public readonly Minstd random;
        public List<List<int>> population = new();
        public int[] values;
        public int crossovers, swaps, inserts, activeValue, activeDecisions, activatedValue;
        public Schedule ga, result;
        public Search search;
        public Solver(Instance instance, Params settings) {
            this.instance = instance;
            this.settings = settings;
            random = new Minstd(settings.Value("seed"));
            jacksons = new int[instance.machineCount];
            Job jobBest = instance.jobs[0];
            foreach (Job job in instance.jobs)
                if (job.work > jobBest.work)
                    jobBest = job;
            jobBound = jobBest;
            Machine machineBest = instance.machines[0];
            int jacksonBest = 0;
            foreach (Machine machine in instance.machines) {
                jacksons[machine.number - 1] = Jackson(machine);
                if (machine.bound > machineBest.bound)
                    machineBest = machine;
                if (jacksons[machine.number - 1] > jacksons[jacksonBest])
                    jacksonBest = machine.number - 1;
            }
            machineBound = machineBest;
            jacksonMachine = jacksonBest;
            lower = Math.Max(jobBound.work, Math.Max(machineBound.bound, jacksons[jacksonMachine]));
        }
        public List<int> Ranking() {
            List<int> order = new();
            for (int i = 0; i < values.Length; i++)
                order.Add(i);
            order.Sort((first, second) => values[first] != values[second]
                                              ? values[first].CompareTo(values[second])
                                              : first.CompareTo(second));
            return order;
        }
        public void Mutate(List<int> child) {
            if (random.Chance(settings.Fraction("swap_mutation"))) {
                swaps++;
                Genetic.Swap(random, child);
            }
            if (random.Chance(settings.Fraction("insert_mutation"))) {
                inserts++;
                Genetic.Insert(random, child);
            }
        }
        public void Solve() {
            foreach (string rule in RULES) {
                Dispatch dispatch = DispatchRules.Schedule(instance, rule, new int[0]);
                Schedule schedule = new Schedule(instance, dispatch.starts);
                baselines.Add(
                    new Baseline(rule, schedule, dispatch, new Search(instance, schedule.order, settings)));
                population.Add(schedule.Chromosome());
            }
            while (population.Count < settings.Value("population")) {
                List<int> sequence = new();
                foreach (Job job in instance.jobs)
                    foreach (Operation operation in job.operations)
                        sequence.Add(job.number);
                random.Shuffle(sequence);
                population.Add(sequence);
            }
            int previousBest = int.MaxValue;
            for (int generation = 0; generation <= settings.Value("generations"); generation++) {
                values = new int[population.Count];
                for (int i = 0; i < values.Length; i++)
                    values[i] = Makespan(Genetic.Decode(instance, population[i]), instance.durations);
                int best = Ranking()[0];
                if (values[best] < previousBest)
                    records.Add(new int[] { generation, values[best], best + 1 });
                previousBest = values[best];
                if (settings.values["checkpoints"].Contains(Convert.ToString(generation))) {
                    int total = Sum(values), divisor = Gcd(total, values.Length);
                    progress.Add(generation + "," + Minimum(values) + "," + total / divisor + "/" +
                                 values.Length / divisor + "," + Maximum(values) + "," +
                                 population.Select(Genes).Distinct(StringComparer.Ordinal).Count());
                }
                if (generation == settings.Value("generations"))
                    break;
                List<List<int>> offspring = new();
                List<int> order = Ranking();
                for (int i = 0; i < settings.Value("elitism"); i++)
                    offspring.Add(population[order[i]].ToList());
                while (offspring.Count < population.Count) {
                    List<int>
                        first = population[Genetic.Tournament(random, values, settings.Value("tournament"))],
                        second = population[Genetic.Tournament(random, values, settings.Value("tournament"))];
                    List<List<int>> children;
                    if (random.Chance(settings.Fraction("crossover"))) {
                        crossovers++;
                        children = Genetic.Crossover(random, first, second, instance.jobs);
                    } else
                        children = [first.ToList(), second.ToList()];
                    Mutate(children[0]);
                    Mutate(children[1]);
                    offspring.AddRange(children);
                }
                population = offspring;
            }
            List<int> chromosome = population[Ranking()[0]];
            ga = new Schedule(instance, Genetic.Decode(instance, chromosome));
            int[] positions = new int[instance.operations.Count];
            List<Operation> operations = Genetic.Operations(instance, chromosome);
            for (int i = 0; i < operations.Count; i++)
                positions[operations[i].ident] = i + 1;
            Dispatch active = DispatchRules.Schedule(instance, "GENES", positions);
            activeValue = Makespan(active.starts, instance.durations);
            activeDecisions = active.decisions;
            List<List<int>> activated = Copy(ga.order);
            while (true) {
                Schedule schedule = CreateSchedule(instance, activated);
                int selected = -1;
                int[] shift = new int[0];
                foreach (int ident in schedule.byStart)
                    if (schedule.Shift(ident).Length != 0) {
                        selected = ident;
                        shift = schedule.Shift(ident);
                        break;
                    }
                if (selected < 0)
                    break;
                List<int> sequence = activated[instance.operations[selected].machine - 1];
                sequence.Remove(selected);
                sequence.Insert(shift[1], selected);
                shifts.Add(new Shift(selected, schedule.starts[selected], shift[0]));
            }
            activatedValue = Evaluate(instance, activated, instance.durations);
            search = new Search(instance, activated, settings);
            result = CreateSchedule(instance, search.bestOrder);
        }
        public List<string> BaselineLines() {
            List<string> lines = new();
            lines.Add("INSTANCE jobs " + instance.jobs.Count + " machines " + instance.machineCount +
                      " operations " + instance.operations.Count + " work " + Sum(instance.durations) +
                      " errors " + instance.errors.Count);
            foreach (string error in instance.errors)
                lines.Add("ERROR " + error);
            foreach (Job job in instance.jobs) {
                List<string> route = new();
                foreach (Operation operation in job.operations)
                    route.Add("M" + operation.machine);
                lines.Add("JOB J" + job.number + " operations " + job.operations.Count + " work " + job.work +
                          " route " + string.Join(" ", route));
            }
            foreach (Machine machine in instance.machines)
                lines.Add("MACHINE M" + machine.number + " operations " + machine.operations.Count +
                          " load " + machine.load + " head " + machine.head + " tail " + machine.tail +
                          " bound " + machine.bound + " jackson " + jacksons[machine.number - 1]);
            lines.Add("BOUND job " + jobBound.work + " J" + jobBound.number);
            lines.Add("BOUND machine " + machineBound.bound + " M" + machineBound.number);
            lines.Add("BOUND jackson " + jacksons[jacksonMachine] + " M" + (jacksonMachine + 1));
            lines.Add("BOUND lower " + lower);
            Baseline best = baselines[0];
            foreach (Baseline baseline in baselines) {
                Schedule schedule = baseline.schedule;
                if (schedule.makespan < best.schedule.makespan)
                    best = baseline;
                lines.Add("RULE " + baseline.rule + " makespan " + schedule.makespan + " gap " +
                          Percent(schedule.makespan - lower, lower) + " flow " + schedule.Flow() + " idle " +
                          schedule.Idle() + " decisions " + baseline.dispatch.decisions + " ties " +
                          baseline.dispatch.ties);
                lines.Add("PATH " + baseline.rule + " operations " + schedule.Path().Count + " blocks " +
                          schedule.Blocks().Count + " critical_paths " + schedule.PathCount() +
                          " bottleneck M" + schedule.Bottleneck());
                lines.Add("TABU " + baseline.rule + " makespan " + schedule.makespan + " -> " +
                          baseline.search.best + " found " + baseline.search.found + " iterations " +
                          baseline.search.records.Count + " stop " + baseline.search.reason);
            }
            lines.Add("BEST " + best.rule + " makespan " + best.schedule.makespan);
            foreach (Machine machine in instance.machines) {
                string line = "UTILIZATION M" + machine.number;
                foreach (Baseline baseline in baselines)
                    line += " " + baseline.rule + " " + Percent(machine.load, baseline.schedule.makespan);
                lines.Add(line);
            }
            return lines;
        }
        public List<string> ScheduleLines() {
            List<string> lines = new();
            lines.Add("GA best " + ga.makespan + " generation " + records[^1][0] + " crossovers " +
                      crossovers + " swaps " + swaps + " inserts " + inserts);
            foreach (int[] record in records)
                lines.Add("RECORD generation " + record[0] + " makespan " + record[1] + " individual " +
                          record[2]);
            HashSet<string> seen = new(StringComparer.Ordinal);
            int rank = 0;
            foreach (int index in Ranking())
                if (seen.Add(Genes(population[index]))) {
                    if (rank == 5)
                        break;
                    rank++;
                    Schedule other = new Schedule(instance, Genetic.Decode(instance, population[index]));
                    lines.Add("TOP " + rank + " individual " + (index + 1) + " makespan " + values[index] +
                              " distance " + Sum(Distances(other, ga)));
                }
            lines.Add("GA_CHROMOSOME " + Genes(population[Ranking()[0]]));
            lines.Add("ACTIVE_DECODE makespan " + activeValue + " decisions " + activeDecisions);
            for (int i = 0; i < shifts.Count; i++) {
                Shift shift = shifts[i];
                Operation operation = instance.operations[shift.ident];
                lines.Add("SHIFT " + (i + 1) + " " + operation.Code() + " M" + operation.machine + " start " +
                          shift.oldStart + " -> " + shift.newStart);
            }
            lines.Add("ACTIVATED makespan " + ga.makespan + " -> " + activatedValue + " shifts " +
                      shifts.Count);
            lines.Add("SCHEDULE makespan " + result.makespan + " lower_bound " + lower + " gap " +
                      Percent(result.makespan - lower, lower) + " improvement " +
                      (ga.makespan - result.makespan) + " shiftable " + result.Shiftable());
            lines.Add("CHROMOSOME " + Genes(result.Chromosome()));
            List<string> legend = new();
            foreach (Job job in instance.jobs)
                legend.Add(Letter(job.number) + "=J" + job.number);
            lines.Add("LEGEND " + string.Join(" ", legend));
            int[] chart = Gantt.Scale(result.makespan, settings.Value("gantt_width"));
            int scale = chart[0], columns = chart[1];
            HashSet<int> onPath = result.Path().ToHashSet();
            List<List<Interval>> intervals = new();
            for (int m = 0; m < instance.machineCount; m++)
                intervals.Add(new());
            foreach (Operation operation in instance.operations) {
                char mark = Letter(operation.job);
                if (onPath.Contains(operation.ident))
                    mark = char.ToLowerInvariant(mark);
                intervals[operation.machine - 1].Add(
                    new Interval(result.starts[operation.ident], result.completions[operation.ident], mark));
            }
            lines.Add("GANTT scale " + scale + " columns " + columns);
            lines.Add(Gantt.Time(scale, columns));
            lines.Add(Gantt.Rule(columns));
            for (int m = 0; m < instance.machineCount; m++)
                lines.Add(Gantt.Row("M" + (m + 1), intervals[m], scale, columns));
            lines.Add(Gantt.Busy(intervals, scale, columns));
            foreach (Job job in instance.jobs) {
                List<Interval> row = new();
                foreach (Operation operation in job.operations)
                    row.Add(new Interval(result.starts[operation.ident], result.completions[operation.ident],
                                         (char)('0' + operation.machine % 10)));
                lines.Add(Gantt.Row("J" + job.number, row, scale, columns));
            }
            foreach (Machine machine in instance.machines) {
                string line = "ORDER M" + machine.number + " FINAL " + result.Letters(machine.number);
                foreach (Baseline baseline in baselines)
                    line += " " + baseline.rule + " " + baseline.schedule.Letters(machine.number);
                lines.Add(line);
            }
            foreach (Machine machine in instance.machines) {
                List<int> sequence = result.order[machine.number - 1];
                List<string> texts = new(), idle = new();
                int gaps = 0, longest = 0, end = 0;
                for (int i = 0; i < sequence.Count; i++) {
                    int ident = sequence[i], start = result.starts[ident];
                    if (start > end) {
                        idle.Add(end + "-" + start);
                        if (i > 0) {
                            gaps++;
                            longest = Math.Max(longest, start - end);
                        }
                    }
                    texts.Add("J" + instance.operations[ident].job + ":" + start + "-" +
                              result.completions[ident]);
                    end = result.completions[ident];
                }
                if (end < result.makespan)
                    idle.Add(end + "-" + result.makespan);
                lines.Add("MACHINE M" + machine.number + " load " + machine.load + " idle " +
                          (result.makespan - machine.load) + " utilization " +
                          Percent(machine.load, result.makespan) + " gaps " + gaps + " longest_gap " +
                          longest + " sequence " + string.Join(" ", texts));
                lines.Add("IDLE M" + machine.number + " " +
                          (idle.Count == 0 ? "none" : string.Join(" ", idle)));
            }
            int waiting = 0;
            foreach (Job job in instance.jobs) {
                int completion = result.completions[job.operations[^1].ident];
                waiting += completion - job.work;
                lines.Add("JOB J" + job.number + " operations " + job.operations.Count + " work " + job.work +
                          " start " + result.starts[job.operations[0].ident] + " completion " + completion +
                          " waiting " + (completion - job.work));
            }
            lines.Add("TOTAL flow " + result.Flow() + " waiting " + waiting + " idle " + result.Idle());
            List<Schedule> others = new();
            foreach (Baseline baseline in baselines)
                others.Add(baseline.schedule);
            others.Add(ga);
            int[][] distances = new int [5][];
            for (int i = 0; i < 5; i++)
                distances[i] = Distances(result, others[i]);
            int pairsTotal = 0;
            foreach (Machine machine in instance.machines) {
                int count = machine.operations.Count, pairs = count * (count - 1) / 2;
                pairsTotal += pairs;
                string line = "DISTANCE M" + machine.number + " pairs " + pairs;
                for (int i = 0; i < 5; i++)
                    line += " " + (i == 4 ? "GA" : RULES[i]) + " " + distances[i][machine.number - 1];
                lines.Add(line);
            }
            string distanceSummary = "DISTANCE total pairs " + pairsTotal;
            for (int i = 0; i < 5; i++)
                distanceSummary += " " + (i == 4 ? "GA" : RULES[i]) + " " + Sum(distances[i]);
            lines.Add(distanceSummary);
            return lines;
        }
        public List<string> PathLines() {
            List<string> lines = new();
            lines.Add("SEARCH start " + search.start + " iterations " + settings.Value("tabu_iterations") +
                      " tenure " + settings.Value("tabu_tenure"));
            foreach (Iteration iteration in search.records) {
                Operation first = instance.operations[iteration.move.first],
                          second = instance.operations[iteration.move.second];
                lines.Add("ITER " + iteration.number + " moves " + iteration.moves + " tabu " +
                          iteration.tabu + " swap M" + first.machine + " " + first.Code() + " " +
                          second.Code() + " " + (iteration.aspiration ? "aspiration" : "free") +
                          " makespan " + iteration.value + " best " + iteration.best);
            }
            lines.Add("STOP iterations " + search.records.Count + " reason " + search.reason + " best " +
                      search.best + " found " + search.found);
            List<int> path = result.Path();
            List<List<int>> blocks = result.Blocks();
            lines.Add("PATH operations " + path.Count + " blocks " + blocks.Count + " makespan " +
                      result.makespan + " critical_paths " + result.PathCount());
            for (int i = 0; i < path.Count; i++) {
                int ident = path[i];
                Operation operation = instance.operations[ident];
                string link = i == 0                                         ? "start"
                              : result.machinePrevious[ident] == path[i - 1] ? "machine"
                                                                             : "job";
                lines.Add("NODE " + (i + 1) + " " + operation.Code() + " M" + operation.machine + " " +
                          result.starts[ident] + "-" + result.completions[ident] + " " + link);
            }
            for (int i = 0; i < blocks.Count; i++) {
                List<int> block = blocks[i];
                List<string> codes = new();
                foreach (int ident in block)
                    codes.Add(instance.operations[ident].Code());
                lines.Add("BLOCK " + (i + 1) + " M" + instance.operations[block[0]].machine + " " +
                          result.starts[block[0]] + "-" + result.completions[block[^1]] + " " +
                          string.Join(" ", codes));
            }
            List<Move> moves = result.Moves();
            for (int i = 0; i < moves.Count; i++) {
                Move move = moves[i];
                Operation first = instance.operations[move.first], second = instance.operations[move.second];
                lines.Add("NEIGHBOUR " + (i + 1) + " M" + first.machine + " " + first.Code() + " " +
                          second.Code() + " makespan " +
                          Evaluate(instance, Apply(instance, result.order, move), instance.durations));
            }
            int[][] slacks = result.Slacks();
            int critical = 0;
            foreach (int value in slacks[0])
                if (value == 0)
                    critical++;
            lines.Add("CRITICAL operations " + critical + " total " + instance.operations.Count);
            for (int kind = 0; kind < 2; kind++)
                foreach (Job job in instance.jobs) {
                    List<int> values = new();
                    foreach (Operation operation in job.operations)
                        values.Add(slacks[kind][operation.ident]);
                    lines.Add((kind == 0 ? "SLACK" : "FREE") + " J" + job.number + " " + Genes(values));
                }
            int[] counts = result.PathCounts();
            foreach (Machine machine in instance.machines) {
                int[] durations = instance.durations.ToArray();
                int count = 0;
                foreach (Operation operation in machine.operations) {
                    durations[operation.ident] += (operation.duration + 9) / 10;
                    if (slacks[0][operation.ident] == 0)
                        count++;
                }
                int sensitivity = Evaluate(instance, result.order, durations);
                lines.Add("MACHINE M" + machine.number + " critical " + count + " path " +
                          counts[machine.number - 1] + " sensitivity " + sensitivity + " delta " +
                          (sensitivity - result.makespan));
            }
            int bottleneck = result.Bottleneck();
            lines.Add("BOTTLENECK M" + bottleneck + " path " + counts[bottleneck - 1]);
            return lines;
        }
    }
    static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Solver solver = new Solver(new Instance(), new Params());
        solver.Solve();
        Directory.CreateDirectory(Path.Combine("output"));
        Write("baselines.txt", solver.BaselineLines());
        Write("ga_progress.csv", solver.progress);
        Write("best_schedule.txt", solver.ScheduleLines());
        Write("critical_path.txt", solver.PathLines());
    }
}
