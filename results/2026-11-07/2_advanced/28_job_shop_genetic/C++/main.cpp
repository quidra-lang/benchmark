#include "scheduler.hpp"
static const std::vector<std::string> rules = {"SPT", "LPT", "MWKR", "FIFO"};
Schedule from_starts(const Instance &data, const std::vector<int> &starts) {
    Schedule schedule;
    const int n = int(data.operations.size());
    schedule.start = starts;
    schedule.finish.resize(n);
    schedule.previous.assign(n, -1);
    schedule.next.assign(n, -1);
    schedule.order.resize(data.machines);
    for (int i = 0; i < n; ++i) {
        schedule.finish[i] = starts[i] + data.operations[i].duration;
        schedule.makespan = std::max(schedule.makespan, schedule.finish[i]);
        schedule.order[data.operations[i].machine].push_back(i);
    }
    for (std::vector<int> &sequence : schedule.order) {
        std::sort(sequence.begin(), sequence.end(), [&](int a, int b) {
            return std::tie(starts[a], data.operations[a].job) < std::tie(starts[b], data.operations[b].job);
        });
        for (std::size_t i = 1; i < sequence.size(); ++i) {
            schedule.previous[sequence[i]] = sequence[i - 1];
            schedule.next[sequence[i - 1]] = sequence[i];
        }
    }
    return schedule;
}
Schedule schedule_order(const Instance &data, const Order &order, int inflated) {
    Schedule schedule;
    const int n = int(data.operations.size());
    schedule.start.assign(n, -1);
    schedule.finish.resize(n);
    schedule.previous.assign(n, -1);
    schedule.next.assign(n, -1);
    schedule.order = order;
    for (const std::vector<int> &sequence : order)
        for (std::size_t i = 1; i < sequence.size(); ++i) {
            schedule.previous[sequence[i]] = sequence[i - 1];
            schedule.next[sequence[i - 1]] = sequence[i];
        }
    int remaining = n;
    while (remaining)
        for (int i = 0; i < n; ++i) {
            if (schedule.start[i] >= 0)
                continue;
            const Operation &op = data.operations[i];
            const int a = op.previous, b = schedule.previous[i];
            if ((a >= 0 && schedule.start[a] < 0) || (b >= 0 && schedule.start[b] < 0))
                continue;
            const int duration = op.duration + (op.machine == inflated ? (op.duration + 9) / 10 : 0);
            schedule.start[i] = std::max(a < 0 ? 0 : schedule.finish[a], b < 0 ? 0 : schedule.finish[b]);
            schedule.finish[i] = schedule.start[i] + duration;
            schedule.makespan = std::max(schedule.makespan, schedule.finish[i]);
            --remaining;
        }
    return schedule;
}
Chromosome chromosome(const Instance &data, const Schedule &schedule) {
    std::vector<int> ids(data.operations.size());
    std::iota(ids.begin(), ids.end(), 0);
    std::sort(ids.begin(), ids.end(), [&](int a, int b) {
        return std::tie(schedule.start[a], data.operations[a].job) <
               std::tie(schedule.start[b], data.operations[b].job);
    });
    Chromosome result;
    for (int id : ids)
        result.push_back(data.operations[id].job);
    return result;
}
struct Params {
    Integer seed;
    int population, generations, tournament, elites, iterations, tenure, width;
    std::pair<int, int> cross, swap, insert;
    std::vector<int> checkpoints;
    Params() {
        std::ifstream input("input/ga_params.txt");
        std::string key, value, line;
        input >> key >> seed >> key >> population >> key >> generations >> key >> tournament;
        auto fraction = [](const std::string &text) {
            const std::size_t p = text.find('/');
            return std::make_pair(std::stoi(text.substr(0, p)), std::stoi(text.substr(p + 1)));
        };
        input >> key >> value;
        cross = fraction(value);
        input >> key >> value;
        swap = fraction(value);
        input >> key >> value;
        insert = fraction(value);
        input >> key >> elites;
        std::getline(input, line);
        std::getline(input, line);
        std::istringstream fields(line);
        fields >> key;
        int checkpoint;
        while (fields >> checkpoint)
            checkpoints.push_back(checkpoint);
        input >> key >> iterations >> key >> tenure >> key >> width;
    }
};
static std::string percent(Integer numerator, Integer denominator) {
    const Integer value = (2000 * numerator + denominator) / (2 * denominator);
    return std::to_string(value / 10) + "." + std::to_string(value % 10) + "%";
}
struct Analysis {
    std::vector<int> path, slack, free_slack;
    std::vector<std::vector<int>> blocks;
    int bottleneck = 0;
    Integer paths = 0;
};
static std::vector<int> chronological(const Instance &data, const Schedule &schedule) {
    std::vector<int> ids(data.operations.size());
    std::iota(ids.begin(), ids.end(), 0);
    std::sort(ids.begin(), ids.end(), [&](int a, int b) {
        return std::tie(schedule.start[a], data.operations[a].job) <
               std::tie(schedule.start[b], data.operations[b].job);
    });
    return ids;
}
static Analysis analyze(const Instance &data, const Schedule &schedule) {
    Analysis result;
    int current = -1;
    for (std::size_t i = 0; i < data.operations.size(); ++i)
        if (schedule.finish[i] == schedule.makespan &&
            (current < 0 || data.operations[i].job < data.operations[current].job))
            current = int(i);
    while (true) {
        result.path.push_back(current);
        if (!schedule.start[current])
            break;
        const int previous = schedule.previous[current];
        current = previous >= 0 && schedule.finish[previous] == schedule.start[current]
                      ? previous
                      : data.operations[current].previous;
    }
    std::reverse(result.path.begin(), result.path.end());
    std::vector<int> counts(data.machines);
    for (int id : result.path) {
        const int machine = data.operations[id].machine;
        ++counts[machine];
        if (result.blocks.empty() || data.operations[result.blocks.back().back()].machine != machine)
            result.blocks.push_back({});
        result.blocks.back().push_back(id);
    }
    for (int machine = 1; machine < data.machines; ++machine)
        if (counts[machine] > counts[result.bottleneck])
            result.bottleneck = machine;
    const std::vector<int> order = chronological(data, schedule);
    std::vector<Integer> paths(data.operations.size());
    for (int id : order) {
        if (!schedule.start[id])
            paths[id] = 1;
        else {
            const int a = data.operations[id].previous, b = schedule.previous[id];
            if (a >= 0 && schedule.finish[a] == schedule.start[id])
                paths[id] += paths[a];
            if (b >= 0 && schedule.finish[b] == schedule.start[id])
                paths[id] += paths[b];
        }
        if (schedule.finish[id] == schedule.makespan)
            result.paths += paths[id];
    }
    result.slack.resize(data.operations.size());
    result.free_slack.resize(data.operations.size());
    std::vector<int> latest(data.operations.size());
    for (auto it = order.rbegin(); it != order.rend(); ++it) {
        const int id = *it, a = data.operations[id].next, b = schedule.next[id];
        int limit = schedule.makespan, free_limit = schedule.makespan;
        if (a >= 0) {
            limit = std::min(limit, latest[a]);
            free_limit = std::min(free_limit, schedule.start[a]);
        }
        if (b >= 0) {
            limit = std::min(limit, latest[b]);
            free_limit = std::min(free_limit, schedule.start[b]);
        }
        latest[id] = limit - data.operations[id].duration;
        result.slack[id] = latest[id] - schedule.start[id];
        result.free_slack[id] = free_limit - schedule.finish[id];
    }
    return result;
}
using Move = std::pair<int, int>;
static std::vector<Move> moves(const Analysis &analysis) {
    std::vector<Move> result;
    for (const std::vector<int> &block : analysis.blocks)
        for (std::size_t i = 1; i < block.size(); ++i)
            result.emplace_back(block[i - 1], block[i]);
    return result;
}
static Order swapped(Order order, const Instance &data, Move move) {
    std::vector<int> &sequence = order[data.operations[move.first].machine];
    const auto first = std::find(sequence.begin(), sequence.end(), move.first),
               second = std::find(sequence.begin(), sequence.end(), move.second);
    std::iter_swap(first, second);
    return order;
}
struct Iteration {
    int number, count, tabu_count;
    Move move;
    bool tabu;
    int value, best;
};
struct Search {
    Schedule best;
    int found = 0;
    std::string stop = "limit";
    std::vector<Iteration> iterations;
};
static Search tabu_search(const Instance &data, const Schedule &start, const Params &params) {
    Search result{start};
    Schedule current = start;
    std::map<Move, int> tabu;
    for (int iteration = 1; iteration <= params.iterations; ++iteration) {
        const std::vector<Move> list = moves(analyze(data, current));
        if (list.empty()) {
            result.stop = "no_moves";
            break;
        }
        int selected = -1, value = std::numeric_limits<int>::max(), tabu_count = 0;
        bool chosen_tabu = false;
        for (std::size_t i = 0; i < list.size(); ++i) {
            const int candidate = schedule_order(data, swapped(current.order, data, list[i])).makespan;
            const bool forbidden = tabu.count(list[i]) && tabu.at(list[i]) >= iteration;
            if (forbidden)
                ++tabu_count;
            if ((!forbidden || candidate < result.best.makespan) && candidate < value) {
                selected = int(i);
                value = candidate;
                chosen_tabu = forbidden;
            }
        }
        if (selected < 0) {
            result.stop = "all_tabu";
            break;
        }
        const Move move = list[selected];
        current = schedule_order(data, swapped(current.order, data, move));
        tabu[{move.second, move.first}] = iteration + params.tenure;
        if (value < result.best.makespan) {
            result.best = current;
            result.found = iteration;
        }
        result.iterations.push_back(
            {iteration, int(list.size()), tabu_count, move, chosen_tabu, value, result.best.makespan});
    }
    return result;
}
struct Shift {
    int operation, machine, position, insertion, old_start, new_start;
};
static std::vector<Shift> shiftable(const Instance &data, const Schedule &schedule) {
    std::vector<Shift> result;
    for (int machine = 0; machine < data.machines; ++machine) {
        const std::vector<int> &sequence = schedule.order[machine];
        for (std::size_t i = 1; i < sequence.size(); ++i) {
            const int id = sequence[i], previous = data.operations[id].previous,
                      ready = previous < 0 ? 0 : schedule.finish[previous];
            for (std::size_t gap = 0; gap < i; ++gap) {
                const int start = std::max(ready, gap ? schedule.finish[sequence[gap - 1]] : 0);
                if (start + data.operations[id].duration <= schedule.start[sequence[gap]]) {
                    result.push_back({id, machine, int(i), int(gap), schedule.start[id], start});
                    break;
                }
            }
        }
    }
    return result;
}
static std::pair<Schedule, std::vector<Shift>> activate(const Instance &data, Schedule current) {
    std::vector<Shift> history;
    while (true) {
        std::vector<Shift> options = shiftable(data, current);
        if (options.empty())
            break;
        std::sort(options.begin(), options.end(), [&](const Shift &a, const Shift &b) {
            return std::tie(a.old_start, data.operations[a.operation].job) <
                   std::tie(b.old_start, data.operations[b.operation].job);
        });
        const Shift shift = options[0];
        history.push_back(shift);
        Order order = current.order;
        std::vector<int> &sequence = order[shift.machine];
        sequence.erase(sequence.begin() + shift.position);
        sequence.insert(sequence.begin() + shift.insertion, shift.operation);
        current = schedule_order(data, order);
    }
    return {current, history};
}
static std::vector<int> distance(const Instance &data, const Schedule &a, const Schedule &b) {
    std::vector<int> result(data.machines), positions(data.operations.size());
    for (const std::vector<int> &sequence : b.order)
        for (std::size_t i = 0; i < sequence.size(); ++i)
            positions[sequence[i]] = int(i);
    for (int machine = 0; machine < data.machines; ++machine) {
        const std::vector<int> &sequence = a.order[machine];
        for (std::size_t i = 0; i < sequence.size(); ++i)
            for (std::size_t j = i + 1; j < sequence.size(); ++j)
                if (positions[sequence[i]] > positions[sequence[j]])
                    ++result[machine];
    }
    return result;
}
static int sum(const std::vector<int> &values) {
    return std::accumulate(values.begin(), values.end(), 0);
}
static int flow(const Instance &data, const Schedule &schedule) {
    int total = 0;
    for (const Job &job : data.jobs)
        total += schedule.finish[job.operations.back()];
    return total;
}
static int jackson(const Instance &data, int machine) {
    std::vector<int> ids, remaining;
    for (std::size_t i = 0; i < data.operations.size(); ++i)
        if (data.operations[i].machine == machine) {
            ids.push_back(int(i));
            remaining.push_back(data.operations[i].duration);
        }
    int time = 0, bound = 0, left = int(ids.size());
    while (left) {
        int selected = -1, next = std::numeric_limits<int>::max();
        for (std::size_t i = 0; i < ids.size(); ++i) {
            const Operation &op = data.operations[ids[i]];
            if (op.head > time)
                next = std::min(next, op.head);
            if (remaining[i] && op.head <= time &&
                (selected < 0 || op.tail > data.operations[ids[selected]].tail ||
                 (op.tail == data.operations[ids[selected]].tail &&
                  op.job < data.operations[ids[selected]].job)))
                selected = int(i);
        }
        if (selected < 0) {
            time = next;
            continue;
        }
        const int amount = std::min(
            remaining[selected], next == std::numeric_limits<int>::max() ? remaining[selected] : next - time);
        time += amount;
        remaining[selected] -= amount;
        if (!remaining[selected]) {
            --left;
            bound = std::max(bound, time + data.operations[ids[selected]].tail);
        }
    }
    return bound;
}
struct GeneticResult {
    Schedule best;
    Chromosome genes;
    std::vector<std::tuple<int, int, int>> records;
    std::vector<std::string> progress;
    std::vector<Chromosome> population;
    std::vector<int> values, rank;
    int crossovers = 0, swaps = 0, inserts = 0;
};
static GeneticResult run_genetic(const Instance &data, const Params &params,
                                 const std::vector<Schedule> &baselines) {
    GeneticResult result;
    Minstd random(params.seed);
    Chromosome basic;
    for (const Job &job : data.jobs)
        for (std::size_t i = 0; i < job.operations.size(); ++i)
            basic.push_back(job.number);
    std::vector<Chromosome> population;
    for (const Schedule &baseline : baselines)
        population.push_back(chromosome(data, baseline));
    while (population.size() < std::size_t(params.population)) {
        Chromosome genes = basic;
        random.shuffle(genes);
        population.push_back(std::move(genes));
    }
    int previous = std::numeric_limits<int>::max();
    for (int generation = 0; generation <= params.generations; ++generation) {
        std::vector<int> values;
        for (const Chromosome &genes : population)
            values.push_back(decode(data, genes).makespan);
        std::vector<int> rank(params.population);
        std::iota(rank.begin(), rank.end(), 0);
        std::sort(rank.begin(), rank.end(),
                  [&](int a, int b) { return std::tie(values[a], a) < std::tie(values[b], b); });
        const int best = rank[0];
        if (values[best] < previous)
            result.records.emplace_back(generation, values[best], best + 1);
        previous = values[best];
        if (std::find(params.checkpoints.begin(), params.checkpoints.end(), generation) !=
            params.checkpoints.end()) {
            const Integer total = std::accumulate(values.begin(), values.end(), Integer(0)),
                          divisor = std::gcd(total, Integer(params.population));
            const std::set<Chromosome> distinct(population.begin(), population.end());
            result.progress.push_back(std::to_string(generation) + "," + std::to_string(values[best]) + "," +
                                      std::to_string(total / divisor) + "/" +
                                      std::to_string(params.population / divisor) + "," +
                                      std::to_string(*std::max_element(values.begin(), values.end())) + "," +
                                      std::to_string(distinct.size()));
        }
        if (generation == params.generations) {
            result.population = population;
            result.values = values;
            result.rank = rank;
            result.genes = population[best];
            result.best = decode(data, result.genes);
            break;
        }
        std::vector<Chromosome> next;
        for (int i = 0; i < params.elites; ++i)
            next.push_back(population[rank[i]]);
        while (next.size() < population.size()) {
            const int first = tournament(random, values, params.tournament),
                      second = tournament(random, values, params.tournament);
            std::pair<Chromosome, Chromosome> children{population[first], population[second]};
            if (random.chance(params.cross)) {
                ++result.crossovers;
                children = crossover(random, data, children.first, children.second);
            }
            for (Chromosome *child : {&children.first, &children.second}) {
                if (random.chance(params.swap)) {
                    ++result.swaps;
                    swap_mutation(random, *child);
                }
                if (random.chance(params.insert)) {
                    ++result.inserts;
                    insertion_mutation(random, *child);
                }
            }
            next.push_back(std::move(children.first));
            next.push_back(std::move(children.second));
        }
        population = std::move(next);
    }
    return result;
}
static void genes_line(std::ostream &out, const std::string &label, const Chromosome &genes) {
    out << label;
    for (int gene : genes)
        out << ' ' << gene;
    out << '\n';
}
static std::string letters(const Instance &data, const std::vector<int> &sequence) {
    std::string result;
    for (int id : sequence)
        result += char('A' + data.operations[id].job - 1);
    return result;
}
int main() {
    const Instance data = read_instance();
    const Params params;
    std::filesystem::create_directories("output");
    std::vector<int> jackson_bounds;
    int job_bound = 0, job_number = 0, machine_bound = 0, machine_number = 0, jackson_bound = 0,
        jackson_machine = 0;
    for (const Job &job : data.jobs)
        if (job.work > job_bound) {
            job_bound = job.work;
            job_number = job.number;
        }
    for (int m = 0; m < data.machines; ++m) {
        jackson_bounds.push_back(jackson(data, m));
        if (data.machine[m].bound > machine_bound) {
            machine_bound = data.machine[m].bound;
            machine_number = m + 1;
        }
        if (jackson_bounds[m] > jackson_bound) {
            jackson_bound = jackson_bounds[m];
            jackson_machine = m + 1;
        }
    }
    const int lower = std::max({job_bound, machine_bound, jackson_bound});
    std::vector<Schedule> baselines;
    std::vector<Search> baseline_search;
    for (const std::string &rule : rules) {
        baselines.push_back(dispatch(data, rule));
        baseline_search.push_back(tabu_search(data, baselines.back(), params));
    }
    std::ofstream base("output/baselines.txt");
    base << "INSTANCE jobs " << data.jobs.size() << " machines " << data.machines << " operations "
         << data.operations.size() << " work " << data.work << " errors " << data.errors.size() << '\n';
    for (const std::string &error : data.errors)
        base << "ERROR " << error << '\n';
    for (const Job &job : data.jobs) {
        base << "JOB J" << job.number << " operations " << job.operations.size() << " work " << job.work
             << " route";
        for (int id : job.operations)
            base << " M" << data.operations[id].machine + 1;
        base << '\n';
    }
    for (int m = 0; m < data.machines; ++m) {
        const Machine &machine = data.machine[m];
        base << "MACHINE M" << m + 1 << " operations " << machine.count << " load " << machine.load
             << " head " << machine.head << " tail " << machine.tail << " bound " << machine.bound
             << " jackson " << jackson_bounds[m] << '\n';
    }
    base << "BOUND job " << job_bound << " J" << job_number << "\nBOUND machine " << machine_bound << " M"
         << machine_number << "\nBOUND jackson " << jackson_bound << " M" << jackson_machine
         << "\nBOUND lower " << lower << '\n';
    int best_rule = 0;
    for (int r = 0; r < 4; ++r) {
        const Schedule &schedule = baselines[r];
        const Analysis analysis = analyze(data, schedule);
        const Search &search = baseline_search[r];
        if (schedule.makespan < baselines[best_rule].makespan)
            best_rule = r;
        base << "RULE " << rules[r] << " makespan " << schedule.makespan << " gap "
             << percent(schedule.makespan - lower, lower) << " flow " << flow(data, schedule) << " idle "
             << data.machines * schedule.makespan - data.work << " decisions " << schedule.decisions
             << " ties " << schedule.ties << '\n';
        base << "PATH " << rules[r] << " operations " << analysis.path.size() << " blocks "
             << analysis.blocks.size() << " critical_paths " << analysis.paths << " bottleneck M"
             << analysis.bottleneck + 1 << '\n';
        base << "TABU " << rules[r] << " makespan " << schedule.makespan << " -> " << search.best.makespan
             << " found " << search.found << " iterations " << search.iterations.size() << " stop "
             << search.stop << '\n';
    }
    base << "BEST " << rules[best_rule] << " makespan " << baselines[best_rule].makespan << '\n';
    for (int m = 0; m < data.machines; ++m) {
        base << "UTILIZATION M" << m + 1;
        for (int r = 0; r < 4; ++r)
            base << ' ' << rules[r] << ' ' << percent(data.machine[m].load, baselines[r].makespan);
        base << '\n';
    }
    const GeneticResult ga = run_genetic(data, params, baselines);
    std::ofstream progress("output/ga_progress.csv");
    progress << "generation,best,mean,worst,distinct\n";
    for (const std::string &line : ga.progress)
        progress << line << '\n';
    const Schedule active_decode = dispatch(data, "GENES", ga.genes);
    const auto activated = activate(data, ga.best);
    const Search search = tabu_search(data, activated.first, params);
    const Schedule &final = search.best;
    const Analysis analysis = analyze(data, final);
    std::ofstream out("output/best_schedule.txt");
    out << "GA best " << ga.best.makespan << " generation " << std::get<0>(ga.records.back())
        << " crossovers " << ga.crossovers << " swaps " << ga.swaps << " inserts " << ga.inserts << '\n';
    for (const auto &record : ga.records)
        out << "RECORD generation " << std::get<0>(record) << " makespan " << std::get<1>(record)
            << " individual " << std::get<2>(record) << '\n';
    std::set<Chromosome> distinct;
    int top = 0;
    for (int individual : ga.rank) {
        if (!distinct.insert(ga.population[individual]).second)
            continue;
        out << "TOP " << ++top << " individual " << individual + 1 << " makespan " << ga.values[individual]
            << " distance " << sum(distance(data, decode(data, ga.population[individual]), ga.best)) << '\n';
        if (top == 5)
            break;
    }
    genes_line(out, "GA_CHROMOSOME", ga.genes);
    out << "ACTIVE_DECODE makespan " << active_decode.makespan << " decisions " << active_decode.decisions
        << '\n';
    for (std::size_t i = 0; i < activated.second.size(); ++i) {
        const Shift &shift = activated.second[i];
        out << "SHIFT " << i + 1 << ' ' << notation(data.operations[shift.operation]) << " M"
            << shift.machine + 1 << " start " << shift.old_start << " -> " << shift.new_start << '\n';
    }
    out << "ACTIVATED makespan " << ga.best.makespan << " -> " << activated.first.makespan << " shifts "
        << activated.second.size() << '\n';
    out << "SCHEDULE makespan " << final.makespan << " lower_bound " << lower << " gap "
        << percent(final.makespan - lower, lower) << " improvement " << ga.best.makespan - final.makespan
        << " shiftable " << shiftable(data, final).size() << '\n';
    genes_line(out, "CHROMOSOME", chromosome(data, final));
    out << "LEGEND";
    for (const Job &job : data.jobs)
        out << ' ' << char('A' + job.number - 1) << "=J" << job.number;
    out << '\n';
    const Chart chart = gantt(data, final, analysis.path, params.width);
    out << "GANTT scale " << chart.scale << " columns " << chart.columns << '\n';
    for (const std::string &line : chart.lines)
        out << line << '\n';
    for (int m = 0; m < data.machines; ++m) {
        out << "ORDER M" << m + 1 << " FINAL " << letters(data, final.order[m]);
        for (int r = 0; r < 4; ++r)
            out << ' ' << rules[r] << ' ' << letters(data, baselines[r].order[m]);
        out << '\n';
    }
    for (int m = 0; m < data.machines; ++m) {
        const std::vector<int> &sequence = final.order[m];
        int gaps = 0, longest = 0;
        std::vector<std::pair<int, int>> idle;
        int previous = 0;
        for (std::size_t i = 0; i < sequence.size(); ++i) {
            const int id = sequence[i];
            if (final.start[id] > previous) {
                idle.emplace_back(previous, final.start[id]);
                if (i) {
                    ++gaps;
                    longest = std::max(longest, final.start[id] - previous);
                }
            }
            previous = final.finish[id];
        }
        if (previous < final.makespan)
            idle.emplace_back(previous, final.makespan);
        out << "MACHINE M" << m + 1 << " load " << data.machine[m].load << " idle "
            << final.makespan - data.machine[m].load << " utilization "
            << percent(data.machine[m].load, final.makespan) << " gaps " << gaps << " longest_gap " << longest
            << " sequence";
        for (int id : sequence)
            out << " J" << data.operations[id].job << ':' << final.start[id] << '-' << final.finish[id];
        out << '\n';
        out << "IDLE M" << m + 1;
        if (idle.empty())
            out << " none";
        else
            for (const auto &interval : idle)
                out << ' ' << interval.first << '-' << interval.second;
        out << '\n';
    }
    for (const Job &job : data.jobs)
        out << "JOB J" << job.number << " operations " << job.operations.size() << " work " << job.work
            << " start " << final.start[job.operations.front()] << " completion "
            << final.finish[job.operations.back()] << " waiting "
            << final.finish[job.operations.back()] - job.work << '\n';
    out << "TOTAL flow " << flow(data, final) << " waiting " << flow(data, final) - data.work << " idle "
        << data.machines * final.makespan - data.work << '\n';
    std::vector<std::vector<int>> distances;
    for (const Schedule &baseline : baselines)
        distances.push_back(distance(data, final, baseline));
    distances.push_back(distance(data, final, ga.best));
    int total_pairs = 0;
    for (int m = 0; m < data.machines; ++m) {
        const int q = data.machine[m].count, pairs = q * (q - 1) / 2;
        total_pairs += pairs;
        out << "DISTANCE M" << m + 1 << " pairs " << pairs;
        for (int r = 0; r < 5; ++r)
            out << ' ' << (r < 4 ? rules[r] : "GA") << ' ' << distances[r][m];
        out << '\n';
    }
    out << "DISTANCE total pairs " << total_pairs;
    for (int r = 0; r < 5; ++r)
        out << ' ' << (r < 4 ? rules[r] : "GA") << ' ' << sum(distances[r]);
    out << '\n';
    std::ofstream critical("output/critical_path.txt");
    critical << "SEARCH start " << activated.first.makespan << " iterations " << params.iterations
             << " tenure " << params.tenure << '\n';
    for (const Iteration &iteration : search.iterations) {
        const Operation &first = data.operations[iteration.move.first];
        critical << "ITER " << iteration.number << " moves " << iteration.count << " tabu "
                 << iteration.tabu_count << " swap M" << first.machine + 1 << ' ' << notation(first) << ' '
                 << notation(data.operations[iteration.move.second]) << ' '
                 << (iteration.tabu ? "aspiration" : "free") << " makespan " << iteration.value << " best "
                 << iteration.best << '\n';
    }
    critical << "STOP iterations " << search.iterations.size() << " reason " << search.stop << " best "
             << final.makespan << " found " << search.found << '\n';
    critical << "PATH operations " << analysis.path.size() << " blocks " << analysis.blocks.size()
             << " makespan " << final.makespan << " critical_paths " << analysis.paths << '\n';
    for (std::size_t i = 0; i < analysis.path.size(); ++i) {
        const int id = analysis.path[i];
        critical << "NODE " << i + 1 << ' ' << notation(data.operations[id]) << " M"
                 << data.operations[id].machine + 1 << ' ' << final.start[id] << '-' << final.finish[id]
                 << ' '
                 << (i == 0                                       ? "start"
                     : final.previous[id] == analysis.path[i - 1] ? "machine"
                                                                  : "job")
                 << '\n';
    }
    for (std::size_t i = 0; i < analysis.blocks.size(); ++i) {
        const std::vector<int> &block = analysis.blocks[i];
        critical << "BLOCK " << i + 1 << " M" << data.operations[block[0]].machine + 1 << ' '
                 << final.start[block.front()] << '-' << final.finish[block.back()];
        for (int id : block)
            critical << ' ' << notation(data.operations[id]);
        critical << '\n';
    }
    const std::vector<Move> neighbours = moves(analysis);
    for (std::size_t i = 0; i < neighbours.size(); ++i) {
        const Move move = neighbours[i];
        critical << "NEIGHBOUR " << i + 1 << " M" << data.operations[move.first].machine + 1 << ' '
                 << notation(data.operations[move.first]) << ' ' << notation(data.operations[move.second])
                 << " makespan " << schedule_order(data, swapped(final.order, data, move)).makespan << '\n';
    }
    critical << "CRITICAL operations " << std::count(analysis.slack.begin(), analysis.slack.end(), 0)
             << " total " << data.operations.size() << '\n';
    for (const Job &job : data.jobs) {
        critical << "SLACK J" << job.number;
        for (int id : job.operations)
            critical << ' ' << analysis.slack[id];
        critical << '\n';
    }
    for (const Job &job : data.jobs) {
        critical << "FREE J" << job.number;
        for (int id : job.operations)
            critical << ' ' << analysis.free_slack[id];
        critical << '\n';
    }
    int bottleneck_count = 0;
    for (int m = 0; m < data.machines; ++m) {
        int count = 0, path_count = 0;
        for (int id : final.order[m])
            if (!analysis.slack[id])
                ++count;
        for (int id : analysis.path)
            if (data.operations[id].machine == m)
                ++path_count;
        const int sensitivity = schedule_order(data, final.order, m).makespan;
        critical << "MACHINE M" << m + 1 << " critical " << count << " path " << path_count << " sensitivity "
                 << sensitivity << " delta " << sensitivity - final.makespan << '\n';
        if (m == analysis.bottleneck)
            bottleneck_count = path_count;
    }
    critical << "BOTTLENECK M" << analysis.bottleneck + 1 << " path " << bottleneck_count << '\n';
}
