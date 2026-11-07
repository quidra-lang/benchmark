import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Main {
    static final String[] RULES = {"SPT", "LPT", "MWKR", "FIFO"};
    record Move(int first, int second) {}
    record Shift(int ident, int oldStart, int newStart) {}
    record Iteration(int number, int moves, int tabu, Move move, boolean aspiration, int value, int best) {}
    record Baseline(String rule, Schedule schedule, Dispatch dispatch, Search search) {}
    static final class Params {
        final Map<String, String[]> values = new HashMap<>();
        Params() throws IOException {
            for (String line :
                 Files.readAllLines(Path.of("input/ga_params.txt"), StandardCharsets.US_ASCII)) {
                String[] fields = line.split(" ");
                values.put(fields[0], Arrays.copyOfRange(fields, 1, fields.length));
            }
        }
        int value(String key) {
            return Integer.parseInt(values.get(key)[0]);
        }
        int[] fraction(String key) {
            String[] fields = values.get(key)[0].split("/");
            return new int[] {Integer.parseInt(fields[0]), Integer.parseInt(fields[1])};
        }
    }
    static String percent(int part, int whole) {
        int value = (2000 * part + whole) / (2 * whole);
        return value / 10 + "." + value % 10 + "%";
    }
    static char letter(int number) {
        return (char)('A' + number - 1);
    }
    static int sum(int[] values) {
        int total = 0;
        for (int value : values)
            total += value;
        return total;
    }
    static int maximum(int[] values) {
        int best = values[0];
        for (int value : values)
            best = Math.max(best, value);
        return best;
    }
    static int minimum(int[] values) {
        int best = values[0];
        for (int value : values)
            best = Math.min(best, value);
        return best;
    }
    static int gcd(int a, int b) {
        while (b != 0) {
            int old = b;
            b = a % b;
            a = old;
        }
        return a;
    }
    static String genes(List<Integer> chromosome) {
        List<String> values = new ArrayList<>();
        for (int gene : chromosome)
            values.add(Integer.toString(gene));
        return String.join(" ", values);
    }
    static List<List<Integer>> copy(List<List<Integer>> order) {
        List<List<Integer>> result = new ArrayList<>();
        for (List<Integer> sequence : order)
            result.add(new ArrayList<>(sequence));
        return result;
    }
    static int[] orderStarts(Instance instance, List<List<Integer>> order, int[] durations) {
        int[] starts = new int[durations.length], completions = new int[durations.length],
              positions = new int[instance.machineCount];
        Arrays.fill(starts, -1);
        int placed = 0;
        while (placed < starts.length)
            for (int m = 0; m < instance.machineCount; m++) {
                List<Integer> sequence = order.get(m);
                while (positions[m] < sequence.size()) {
                    int position = positions[m], ident = sequence.get(position),
                        previous = instance.operations.get(ident).previous;
                    if (previous >= 0 && starts[previous] < 0)
                        break;
                    starts[ident] = Math.max(previous < 0 ? 0 : completions[previous],
                                             position == 0 ? 0 : completions[sequence.get(position - 1)]);
                    completions[ident] = starts[ident] + durations[ident];
                    positions[m]++;
                    placed++;
                }
            }
        return starts;
    }
    static int makespan(int[] starts, int[] durations) {
        int value = 0;
        for (int i = 0; i < starts.length; i++)
            value = Math.max(value, starts[i] + durations[i]);
        return value;
    }
    static Schedule schedule(Instance instance, List<List<Integer>> order) {
        return new Schedule(instance, orderStarts(instance, order, instance.durations));
    }
    static int evaluate(Instance instance, List<List<Integer>> order, int[] durations) {
        return makespan(orderStarts(instance, order, durations), durations);
    }
    static List<List<Integer>> apply(Instance instance, List<List<Integer>> order, Move move) {
        List<List<Integer>> result = copy(order);
        List<Integer> sequence = result.get(instance.operations.get(move.first).machine - 1);
        int position = sequence.indexOf(move.first);
        Collections.swap(sequence, position, position + 1);
        return result;
    }
    static int[] distances(Schedule first, Schedule second) {
        int[] values = new int[first.instance.machineCount], rank = new int[first.starts.length];
        for (int m = 0; m < values.length; m++) {
            List<Integer> sequence = second.order.get(m);
            for (int i = 0; i < sequence.size(); i++)
                rank[sequence.get(i)] = i;
            sequence = first.order.get(m);
            for (int i = 0; i < sequence.size(); i++)
                for (int j = i + 1; j < sequence.size(); j++)
                    if (rank[sequence.get(i)] > rank[sequence.get(j)])
                        values[m]++;
        }
        return values;
    }
    static int jackson(Machine machine) {
        List<Operation> tasks = machine.operations();
        int[] remaining = new int[tasks.size()];
        for (int i = 0; i < tasks.size(); i++)
            remaining[i] = tasks.get(i).duration;
        int time = 0, bound = 0;
        while (sum(remaining) != 0) {
            int release = Integer.MAX_VALUE;
            for (int i = 0; i < tasks.size(); i++)
                if (remaining[i] > 0)
                    release = Math.min(release, tasks.get(i).head);
            time = Math.max(time, release);
            int selected = -1;
            for (int i = 0; i < tasks.size(); i++)
                if (remaining[i] > 0 && tasks.get(i).head <= time &&
                    (selected < 0 || tasks.get(i).tail > tasks.get(selected).tail))
                    selected = i;
            int delta = remaining[selected];
            for (Operation task : tasks)
                if (task.head > time)
                    delta = Math.min(delta, task.head - time);
            time += delta;
            remaining[selected] -= delta;
            if (remaining[selected] == 0)
                bound = Math.max(bound, time + tasks.get(selected).tail);
        }
        return bound;
    }
    static final class Schedule {
        final Instance instance;
        final int[] starts, completions, machinePrevious, machineNext;
        final int makespan;
        final List<Integer> byStart = new ArrayList<>();
        final List<List<Integer>> order = new ArrayList<>();
        Schedule(Instance instance, int[] starts) {
            this.instance = instance;
            this.starts = starts;
            completions = new int[starts.length];
            machinePrevious = new int[starts.length];
            machineNext = new int[starts.length];
            Arrays.fill(machinePrevious, -1);
            Arrays.fill(machineNext, -1);
            for (int i = 0; i < starts.length; i++) {
                completions[i] = starts[i] + instance.durations[i];
                byStart.add(i);
            }
            makespan = maximum(completions);
            byStart.sort(Comparator.<Integer>comparingInt(i -> starts[i]).thenComparingInt(i -> i));
            for (int m = 0; m < instance.machineCount; m++)
                order.add(new ArrayList<>());
            for (int ident : byStart)
                order.get(instance.operations.get(ident).machine - 1).add(ident);
            for (List<Integer> sequence : order)
                for (int i = 1; i < sequence.size(); i++) {
                    machinePrevious[sequence.get(i)] = sequence.get(i - 1);
                    machineNext[sequence.get(i - 1)] = sequence.get(i);
                }
        }
        List<Integer> chromosome() {
            List<Integer> genes = new ArrayList<>();
            for (int ident : byStart)
                genes.add(instance.operations.get(ident).job);
            return genes;
        }
        List<Integer> path() {
            int current = 0;
            while (completions[current] != makespan)
                current++;
            List<Integer> path = new ArrayList<>();
            path.add(current);
            while (starts[current] != 0) {
                int previous = machinePrevious[current];
                current = previous >= 0 && completions[previous] == starts[current]
                              ? previous
                              : instance.operations.get(current).previous;
                path.add(current);
            }
            Collections.reverse(path);
            return path;
        }
        List<List<Integer>> blocks() {
            List<List<Integer>> blocks = new ArrayList<>();
            for (int ident : path()) {
                if (blocks.isEmpty() || instance.operations.get(blocks.getLast().getLast()).machine !=
                                            instance.operations.get(ident).machine)
                    blocks.add(new ArrayList<>());
                blocks.getLast().add(ident);
            }
            return blocks;
        }
        List<Move> moves() {
            List<Move> moves = new ArrayList<>();
            for (List<Integer> block : blocks())
                for (int i = 1; i < block.size(); i++)
                    moves.add(new Move(block.get(i - 1), block.get(i)));
            return moves;
        }
        int pathCount() {
            int[] ways = new int[starts.length];
            int total = 0;
            for (int ident : byStart) {
                if (starts[ident] == 0)
                    ways[ident] = 1;
                else
                    for (int previous :
                         new int[] {instance.operations.get(ident).previous, machinePrevious[ident]})
                        if (previous >= 0 && completions[previous] == starts[ident])
                            ways[ident] += ways[previous];
                if (completions[ident] == makespan)
                    total += ways[ident];
            }
            return total;
        }
        int[] shift(int ident) {
            Operation operation = instance.operations.get(ident);
            List<Integer> sequence = order.get(operation.machine - 1);
            int position = sequence.indexOf(ident),
                ready = operation.previous < 0 ? 0 : completions[operation.previous];
            for (int insert = 0; insert < position; insert++) {
                int low = insert == 0 ? 0 : completions[sequence.get(insert - 1)],
                    high = starts[sequence.get(insert)], start = Math.max(low, ready);
                if (start + operation.duration <= high)
                    return new int[] {start, insert};
            }
            return new int[0];
        }
        int shiftable() {
            int count = 0;
            for (int i = 0; i < starts.length; i++)
                if (shift(i).length != 0)
                    count++;
            return count;
        }
        int[][] slacks() {
            int[] latest = new int[starts.length], slack = new int[starts.length],
                  free = new int[starts.length];
            for (int position = byStart.size() - 1; position >= 0; position--) {
                int ident = byStart.get(position), limit = makespan, startLimit = makespan;
                for (int next : new int[] {instance.operations.get(ident).next, machineNext[ident]})
                    if (next >= 0) {
                        limit = Math.min(limit, latest[next]);
                        startLimit = Math.min(startLimit, starts[next]);
                    }
                latest[ident] = limit - instance.durations[ident];
                slack[ident] = latest[ident] - starts[ident];
                free[ident] = startLimit - completions[ident];
            }
            return new int[][] {slack, free};
        }
        int[] pathCounts() {
            int[] counts = new int[instance.machineCount];
            for (int ident : path())
                counts[instance.operations.get(ident).machine - 1]++;
            return counts;
        }
        int bottleneck() {
            int[] counts = pathCounts();
            int best = 0;
            for (int i = 1; i < counts.length; i++)
                if (counts[i] > counts[best])
                    best = i;
            return best + 1;
        }
        int flow() {
            int total = 0;
            for (Job job : instance.jobs)
                total += completions[job.operations().getLast().ident];
            return total;
        }
        int idle() {
            return makespan * instance.machineCount - sum(instance.durations);
        }
        String letters(int machine) {
            StringBuilder text = new StringBuilder();
            for (int ident : order.get(machine - 1))
                text.append(letter(instance.operations.get(ident).job));
            return text.toString();
        }
    }
    static final class Search {
        final int start;
        final List<Iteration> records = new ArrayList<>();
        List<List<Integer>> bestOrder;
        int best, found;
        String reason = "limit";
        Search(Instance instance, List<List<Integer>> order, Params params) {
            List<List<Integer>> current = order;
            bestOrder = order;
            start = evaluate(instance, order, instance.durations);
            best = start;
            Map<Move, Integer> expiry = new HashMap<>();
            for (int iteration = 1; iteration <= params.value("tabu_iterations"); iteration++) {
                List<Move> moves = schedule(instance, current).moves();
                if (moves.isEmpty()) {
                    reason = "no_moves";
                    break;
                }
                Move chosen = null;
                int value = Integer.MAX_VALUE, tabuCount = 0;
                boolean aspiration = false;
                for (Move move : moves) {
                    int candidate = evaluate(instance, apply(instance, current, move), instance.durations);
                    boolean tabu = expiry.getOrDefault(move, 0) >= iteration;
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
                current = apply(instance, current, chosen);
                expiry.put(new Move(chosen.second, chosen.first), iteration + params.value("tabu_tenure"));
                if (value < best) {
                    bestOrder = current;
                    best = value;
                    found = iteration;
                }
                records.add(
                    new Iteration(iteration, moves.size(), tabuCount, chosen, aspiration, value, best));
            }
        }
    }
    static final class Solver {
        final Instance instance;
        final Params params;
        final List<Baseline> baselines = new ArrayList<>();
        final List<int[]> records = new ArrayList<>();
        final List<String> progress = new ArrayList<>(List.of("generation,best,mean,worst,distinct"));
        final List<Shift> shifts = new ArrayList<>();
        final int[] jacksons;
        final Job jobBound;
        final Machine machineBound;
        final int jacksonMachine, lower;
        final Minstd random;
        List<List<Integer>> population = new ArrayList<>();
        int[] values;
        int crossovers, swaps, inserts, activeValue, activeDecisions, activatedValue;
        Schedule ga, result;
        Search search;
        Solver(Instance instance, Params params) {
            this.instance = instance;
            this.params = params;
            random = new Minstd(params.value("seed"));
            jacksons = new int[instance.machineCount];
            Job jobBest = instance.jobs.getFirst();
            for (Job job : instance.jobs)
                if (job.work() > jobBest.work())
                    jobBest = job;
            jobBound = jobBest;
            Machine machineBest = instance.machines.getFirst();
            int jacksonBest = 0;
            for (Machine machine : instance.machines) {
                jacksons[machine.number() - 1] = jackson(machine);
                if (machine.bound() > machineBest.bound())
                    machineBest = machine;
                if (jacksons[machine.number() - 1] > jacksons[jacksonBest])
                    jacksonBest = machine.number() - 1;
            }
            machineBound = machineBest;
            jacksonMachine = jacksonBest;
            lower = Math.max(jobBound.work(), Math.max(machineBound.bound(), jacksons[jacksonMachine]));
        }
        List<Integer> ranking() {
            List<Integer> order = new ArrayList<>();
            for (int i = 0; i < values.length; i++)
                order.add(i);
            order.sort(Comparator.<Integer>comparingInt(i -> values[i]).thenComparingInt(i -> i));
            return order;
        }
        void mutate(List<Integer> child) {
            if (random.chance(params.fraction("swap_mutation"))) {
                swaps++;
                Genetic.swap(random, child);
            }
            if (random.chance(params.fraction("insert_mutation"))) {
                inserts++;
                Genetic.insert(random, child);
            }
        }
        void solve() {
            for (String rule : RULES) {
                Dispatch dispatch = DispatchRules.schedule(instance, rule, new int[0]);
                Schedule schedule = new Schedule(instance, dispatch.starts());
                baselines.add(
                    new Baseline(rule, schedule, dispatch, new Search(instance, schedule.order, params)));
                population.add(schedule.chromosome());
            }
            while (population.size() < params.value("population")) {
                List<Integer> sequence = new ArrayList<>();
                for (Job job : instance.jobs)
                    for (Operation operation : job.operations())
                        sequence.add(job.number());
                random.shuffle(sequence);
                population.add(sequence);
            }
            int previousBest = Integer.MAX_VALUE;
            for (int generation = 0; generation <= params.value("generations"); generation++) {
                values = new int[population.size()];
                for (int i = 0; i < values.length; i++)
                    values[i] = makespan(Genetic.decode(instance, population.get(i)), instance.durations);
                int best = ranking().getFirst();
                if (values[best] < previousBest)
                    records.add(new int[] {generation, values[best], best + 1});
                previousBest = values[best];
                if (List.of(params.values.get("checkpoints")).contains(Integer.toString(generation))) {
                    int total = sum(values), divisor = gcd(total, values.length);
                    progress.add(generation + "," + minimum(values) + "," + total / divisor + "/" +
                                 values.length / divisor + "," + maximum(values) + "," +
                                 new HashSet<>(population).size());
                }
                if (generation == params.value("generations"))
                    break;
                List<List<Integer>> offspring = new ArrayList<>();
                List<Integer> order = ranking();
                for (int i = 0; i < params.value("elitism"); i++)
                    offspring.add(new ArrayList<>(population.get(order.get(i))));
                while (offspring.size() < population.size()) {
                    List<Integer> first = population.get(
                                      Genetic.tournament(random, values, params.value("tournament"))),
                                  second = population.get(
                                      Genetic.tournament(random, values, params.value("tournament")));
                    List<List<Integer>> children;
                    if (random.chance(params.fraction("crossover"))) {
                        crossovers++;
                        children = Genetic.crossover(random, first, second, instance.jobs);
                    } else
                        children = List.of(new ArrayList<>(first), new ArrayList<>(second));
                    mutate(children.get(0));
                    mutate(children.get(1));
                    offspring.addAll(children);
                }
                population = offspring;
            }
            List<Integer> chromosome = population.get(ranking().getFirst());
            ga = new Schedule(instance, Genetic.decode(instance, chromosome));
            int[] positions = new int[instance.operations.size()];
            List<Operation> operations = Genetic.operations(instance, chromosome);
            for (int i = 0; i < operations.size(); i++)
                positions[operations.get(i).ident] = i + 1;
            Dispatch active = DispatchRules.schedule(instance, "GENES", positions);
            activeValue = makespan(active.starts(), instance.durations);
            activeDecisions = active.decisions();
            List<List<Integer>> activated = copy(ga.order);
            while (true) {
                Schedule schedule = schedule(instance, activated);
                int selected = -1;
                int[] shift = new int[0];
                for (int ident : schedule.byStart)
                    if (schedule.shift(ident).length != 0) {
                        selected = ident;
                        shift = schedule.shift(ident);
                        break;
                    }
                if (selected < 0)
                    break;
                List<Integer> sequence = activated.get(instance.operations.get(selected).machine - 1);
                sequence.remove(Integer.valueOf(selected));
                sequence.add(shift[1], selected);
                shifts.add(new Shift(selected, schedule.starts[selected], shift[0]));
            }
            activatedValue = evaluate(instance, activated, instance.durations);
            search = new Search(instance, activated, params);
            result = schedule(instance, search.bestOrder);
        }
        List<String> baselineLines() {
            List<String> lines = new ArrayList<>();
            lines.add("INSTANCE jobs " + instance.jobs.size() + " machines " + instance.machineCount +
                      " operations " + instance.operations.size() + " work " + sum(instance.durations) +
                      " errors " + instance.errors.size());
            for (String error : instance.errors)
                lines.add("ERROR " + error);
            for (Job job : instance.jobs) {
                List<String> route = new ArrayList<>();
                for (Operation operation : job.operations())
                    route.add("M" + operation.machine);
                lines.add("JOB J" + job.number() + " operations " + job.operations().size() + " work " +
                          job.work() + " route " + String.join(" ", route));
            }
            for (Machine machine : instance.machines)
                lines.add("MACHINE M" + machine.number() + " operations " + machine.operations().size() +
                          " load " + machine.load() + " head " + machine.head() + " tail " +
                          machine.tail() + " bound " + machine.bound() + " jackson " +
                          jacksons[machine.number() - 1]);
            lines.add("BOUND job " + jobBound.work() + " J" + jobBound.number());
            lines.add("BOUND machine " + machineBound.bound() + " M" + machineBound.number());
            lines.add("BOUND jackson " + jacksons[jacksonMachine] + " M" + (jacksonMachine + 1));
            lines.add("BOUND lower " + lower);
            Baseline best = baselines.getFirst();
            for (Baseline baseline : baselines) {
                Schedule schedule = baseline.schedule;
                if (schedule.makespan < best.schedule.makespan)
                    best = baseline;
                lines.add("RULE " + baseline.rule + " makespan " + schedule.makespan + " gap " +
                          percent(schedule.makespan - lower, lower) + " flow " + schedule.flow() + " idle " +
                          schedule.idle() + " decisions " + baseline.dispatch.decisions() + " ties " +
                          baseline.dispatch.ties());
                lines.add("PATH " + baseline.rule + " operations " + schedule.path().size() + " blocks " +
                          schedule.blocks().size() + " critical_paths " + schedule.pathCount() +
                          " bottleneck M" + schedule.bottleneck());
                lines.add("TABU " + baseline.rule + " makespan " + schedule.makespan + " -> " +
                          baseline.search.best + " found " + baseline.search.found + " iterations " +
                          baseline.search.records.size() + " stop " + baseline.search.reason);
            }
            lines.add("BEST " + best.rule + " makespan " + best.schedule.makespan);
            for (Machine machine : instance.machines) {
                String line = "UTILIZATION M" + machine.number();
                for (Baseline baseline : baselines)
                    line += " " + baseline.rule + " " + percent(machine.load(), baseline.schedule.makespan);
                lines.add(line);
            }
            return lines;
        }
        List<String> scheduleLines() {
            List<String> lines = new ArrayList<>();
            lines.add("GA best " + ga.makespan + " generation " + records.getLast()[0] + " crossovers " +
                      crossovers + " swaps " + swaps + " inserts " + inserts);
            for (int[] record : records)
                lines.add("RECORD generation " + record[0] + " makespan " + record[1] + " individual " +
                          record[2]);
            Set<List<Integer>> seen = new HashSet<>();
            int rank = 0;
            for (int index : ranking())
                if (seen.add(population.get(index))) {
                    if (rank == 5)
                        break;
                    rank++;
                    Schedule other = new Schedule(instance, Genetic.decode(instance, population.get(index)));
                    lines.add("TOP " + rank + " individual " + (index + 1) + " makespan " + values[index] +
                              " distance " + sum(distances(other, ga)));
                }
            lines.add("GA_CHROMOSOME " + genes(population.get(ranking().getFirst())));
            lines.add("ACTIVE_DECODE makespan " + activeValue + " decisions " + activeDecisions);
            for (int i = 0; i < shifts.size(); i++) {
                Shift shift = shifts.get(i);
                Operation operation = instance.operations.get(shift.ident);
                lines.add("SHIFT " + (i + 1) + " " + operation.code() + " M" + operation.machine + " start " +
                          shift.oldStart + " -> " + shift.newStart);
            }
            lines.add("ACTIVATED makespan " + ga.makespan + " -> " + activatedValue + " shifts " +
                      shifts.size());
            lines.add("SCHEDULE makespan " + result.makespan + " lower_bound " + lower + " gap " +
                      percent(result.makespan - lower, lower) + " improvement " +
                      (ga.makespan - result.makespan) + " shiftable " + result.shiftable());
            lines.add("CHROMOSOME " + genes(result.chromosome()));
            List<String> legend = new ArrayList<>();
            for (Job job : instance.jobs)
                legend.add(letter(job.number()) + "=J" + job.number());
            lines.add("LEGEND " + String.join(" ", legend));
            int[] chart = Gantt.scale(result.makespan, params.value("gantt_width"));
            int scale = chart[0], columns = chart[1];
            Set<Integer> onPath = new HashSet<>(result.path());
            List<List<Interval>> intervals = new ArrayList<>();
            for (int m = 0; m < instance.machineCount; m++)
                intervals.add(new ArrayList<>());
            for (Operation operation : instance.operations) {
                char mark = letter(operation.job);
                if (onPath.contains(operation.ident))
                    mark = Character.toLowerCase(mark);
                intervals.get(operation.machine - 1)
                    .add(new Interval(result.starts[operation.ident], result.completions[operation.ident],
                                      mark));
            }
            lines.add("GANTT scale " + scale + " columns " + columns);
            lines.add(Gantt.time(scale, columns));
            lines.add(Gantt.rule(columns));
            for (int m = 0; m < instance.machineCount; m++)
                lines.add(Gantt.row("M" + (m + 1), intervals.get(m), scale, columns));
            lines.add(Gantt.busy(intervals, scale, columns));
            for (Job job : instance.jobs) {
                List<Interval> row = new ArrayList<>();
                for (Operation operation : job.operations())
                    row.add(new Interval(result.starts[operation.ident], result.completions[operation.ident],
                                         (char)('0' + operation.machine % 10)));
                lines.add(Gantt.row("J" + job.number(), row, scale, columns));
            }
            for (Machine machine : instance.machines) {
                String line = "ORDER M" + machine.number() + " FINAL " + result.letters(machine.number());
                for (Baseline baseline : baselines)
                    line += " " + baseline.rule + " " + baseline.schedule.letters(machine.number());
                lines.add(line);
            }
            for (Machine machine : instance.machines) {
                List<Integer> sequence = result.order.get(machine.number() - 1);
                List<String> texts = new ArrayList<>(), idle = new ArrayList<>();
                int gaps = 0, longest = 0, end = 0;
                for (int i = 0; i < sequence.size(); i++) {
                    int ident = sequence.get(i), start = result.starts[ident];
                    if (start > end) {
                        idle.add(end + "-" + start);
                        if (i > 0) {
                            gaps++;
                            longest = Math.max(longest, start - end);
                        }
                    }
                    texts.add("J" + instance.operations.get(ident).job + ":" + start + "-" +
                              result.completions[ident]);
                    end = result.completions[ident];
                }
                if (end < result.makespan)
                    idle.add(end + "-" + result.makespan);
                lines.add("MACHINE M" + machine.number() + " load " + machine.load() + " idle " +
                          (result.makespan - machine.load()) + " utilization " +
                          percent(machine.load(), result.makespan) + " gaps " + gaps + " longest_gap " +
                          longest + " sequence " + String.join(" ", texts));
                lines.add("IDLE M" + machine.number() + " " +
                          (idle.isEmpty() ? "none" : String.join(" ", idle)));
            }
            int waiting = 0;
            for (Job job : instance.jobs) {
                int completion = result.completions[job.operations().getLast().ident];
                waiting += completion - job.work();
                lines.add("JOB J" + job.number() + " operations " + job.operations().size() + " work " +
                          job.work() + " start " + result.starts[job.operations().getFirst().ident] +
                          " completion " + completion + " waiting " + (completion - job.work()));
            }
            lines.add("TOTAL flow " + result.flow() + " waiting " + waiting + " idle " + result.idle());
            List<Schedule> others = new ArrayList<>();
            for (Baseline baseline : baselines)
                others.add(baseline.schedule);
            others.add(ga);
            int[][] distances = new int[5][];
            for (int i = 0; i < 5; i++)
                distances[i] = distances(result, others.get(i));
            int pairsTotal = 0;
            for (Machine machine : instance.machines) {
                int count = machine.operations().size(), pairs = count * (count - 1) / 2;
                pairsTotal += pairs;
                String line = "DISTANCE M" + machine.number() + " pairs " + pairs;
                for (int i = 0; i < 5; i++)
                    line += " " + (i == 4 ? "GA" : RULES[i]) + " " + distances[i][machine.number() - 1];
                lines.add(line);
            }
            String line = "DISTANCE total pairs " + pairsTotal;
            for (int i = 0; i < 5; i++)
                line += " " + (i == 4 ? "GA" : RULES[i]) + " " + sum(distances[i]);
            lines.add(line);
            return lines;
        }
        List<String> pathLines() {
            List<String> lines = new ArrayList<>();
            lines.add("SEARCH start " + search.start + " iterations " + params.value("tabu_iterations") +
                      " tenure " + params.value("tabu_tenure"));
            for (Iteration iteration : search.records) {
                Operation first = instance.operations.get(iteration.move.first),
                          second = instance.operations.get(iteration.move.second);
                lines.add("ITER " + iteration.number + " moves " + iteration.moves + " tabu " +
                          iteration.tabu + " swap M" + first.machine + " " + first.code() + " " +
                          second.code() + " " + (iteration.aspiration ? "aspiration" : "free") +
                          " makespan " + iteration.value + " best " + iteration.best);
            }
            lines.add("STOP iterations " + search.records.size() + " reason " + search.reason + " best " +
                      search.best + " found " + search.found);
            List<Integer> path = result.path();
            List<List<Integer>> blocks = result.blocks();
            lines.add("PATH operations " + path.size() + " blocks " + blocks.size() + " makespan " +
                      result.makespan + " critical_paths " + result.pathCount());
            for (int i = 0; i < path.size(); i++) {
                int ident = path.get(i);
                Operation operation = instance.operations.get(ident);
                String link = i == 0                                             ? "start"
                              : result.machinePrevious[ident] == path.get(i - 1) ? "machine"
                                                                                 : "job";
                lines.add("NODE " + (i + 1) + " " + operation.code() + " M" + operation.machine + " " +
                          result.starts[ident] + "-" + result.completions[ident] + " " + link);
            }
            for (int i = 0; i < blocks.size(); i++) {
                List<Integer> block = blocks.get(i);
                List<String> codes = new ArrayList<>();
                for (int ident : block)
                    codes.add(instance.operations.get(ident).code());
                lines.add("BLOCK " + (i + 1) + " M" + instance.operations.get(block.getFirst()).machine +
                          " " + result.starts[block.getFirst()] + "-" +
                          result.completions[block.getLast()] + " " + String.join(" ", codes));
            }
            List<Move> moves = result.moves();
            for (int i = 0; i < moves.size(); i++) {
                Move move = moves.get(i);
                Operation first = instance.operations.get(move.first),
                          second = instance.operations.get(move.second);
                lines.add("NEIGHBOUR " + (i + 1) + " M" + first.machine + " " + first.code() + " " +
                          second.code() + " makespan " +
                          evaluate(instance, apply(instance, result.order, move), instance.durations));
            }
            int[][] slacks = result.slacks();
            int critical = 0;
            for (int value : slacks[0])
                if (value == 0)
                    critical++;
            lines.add("CRITICAL operations " + critical + " total " + instance.operations.size());
            for (int kind = 0; kind < 2; kind++)
                for (Job job : instance.jobs) {
                    List<Integer> values = new ArrayList<>();
                    for (Operation operation : job.operations())
                        values.add(slacks[kind][operation.ident]);
                    lines.add((kind == 0 ? "SLACK" : "FREE") + " J" + job.number() + " " + genes(values));
                }
            int[] counts = result.pathCounts();
            for (Machine machine : instance.machines) {
                int[] durations = instance.durations.clone();
                int count = 0;
                for (Operation operation : machine.operations()) {
                    durations[operation.ident] += (operation.duration + 9) / 10;
                    if (slacks[0][operation.ident] == 0)
                        count++;
                }
                int sensitivity = evaluate(instance, result.order, durations);
                lines.add("MACHINE M" + machine.number() + " critical " + count + " path " +
                          counts[machine.number() - 1] + " sensitivity " + sensitivity + " delta " +
                          (sensitivity - result.makespan));
            }
            int bottleneck = result.bottleneck();
            lines.add("BOTTLENECK M" + bottleneck + " path " + counts[bottleneck - 1]);
            return lines;
        }
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Solver solver = new Solver(new Instance(), new Params());
        solver.solve();
        Files.createDirectories(Path.of("output"));
        write("baselines.txt", solver.baselineLines());
        write("ga_progress.csv", solver.progress);
        write("best_schedule.txt", solver.scheduleLines());
        write("critical_path.txt", solver.pathLines());
    }
}
