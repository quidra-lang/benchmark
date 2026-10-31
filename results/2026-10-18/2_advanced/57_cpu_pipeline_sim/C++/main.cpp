#include "simulator.hpp"
struct Rejection {
    int line;
    std::string reason;
};
struct Gap {
    int line;
    I expected, found;
};
struct Trace {
    std::vector<Instruction> instructions;
    std::map<I, int> first;
    std::vector<Rejection> rejected;
    std::vector<Gap> gaps;
};
static std::optional<Instruction> check(const std::string &text, const Trace &trace,
                                        std::string &error) {
    std::vector<std::string> fields;
    std::size_t start = 0;
    for (std::size_t i = 0; i <= text.size(); ++i)
        if (i == text.size() || text[i] == ' ') {
            fields.push_back(text.substr(start, i - start));
            start = i + 1;
        }
    auto reject = [&](const std::string &reason) -> std::optional<Instruction> {
        error = reason;
        return {};
    };
    if (fields.size() != 8 || std::find(fields.begin(), fields.end(), "") != fields.end())
        return reject("fields");
    const auto pc = parse_hex(fields[0]);
    if (!pc || *pc % 4)
        return reject("pc");
    const auto kind = std::find(classes.begin(), classes.end(), fields[1]);
    if (kind == classes.end())
        return reject("class");
    Instruction out;
    out.pc = *pc;
    out.kind = Class(kind - classes.begin());
    const std::array<int, 3> registers{parse_register(fields[2]), parse_register(fields[3]),
                                       parse_register(fields[4])};
    if (std::find(registers.begin(), registers.end(), -2) != registers.end())
        return reject("register");
    static const int usage[7][3] = {{1, 1, 0},  {1, 1, 1},  {1, 1, -1},  {-1, 1, 1},
                                    {-1, 1, 0}, {0, 0, -1}, {-1, -1, -1}};
    for (int i = 0; i < 3; ++i)
        if ((usage[out.kind][i] == 1 && registers[i] < 0) ||
            (usage[out.kind][i] == -1 && registers[i] >= 0))
            return reject("operands");
    out.rd = registers[0];
    out.rs1 = registers[1];
    out.rs2 = registers[2];
    if (out.kind == branch ? (fields[5] != "T" && fields[5] != "N")
                           : fields[5] != (out.kind == jump ? "T" : "-"))
        return reject("taken");
    out.taken = fields[5] == "T";
    const auto target = parse_hex(fields[6]);
    if (out.control()) {
        if (!target || *target % 4 || *target == out.pc + 4)
            return reject("target");
        out.target = *target;
    } else if (fields[6] != "-")
        return reject("target");
    const auto address = parse_hex(fields[7]);
    if (out.kind == load || out.kind == store) {
        if (!address || *address % 4)
            return reject("address");
        out.address = *address;
    } else if (fields[7] != "-")
        return reject("address");
    const auto previous = trace.first.find(out.pc);
    if (previous != trace.first.end()) {
        const Instruction &old = trace.instructions[previous->second];
        if (std::tie(out.kind, out.rd, out.rs1, out.rs2) !=
                std::tie(old.kind, old.rd, old.rs1, old.rs2) ||
            ((out.kind == branch || (out.kind == jump && out.rs1 < 0)) && out.target != old.target))
            return reject("conflict");
    }
    out.next = out.taken ? out.target : out.pc + 4;
    return out;
}
static Trace validate(const Lines &lines) {
    Trace trace;
    for (int i = 0; i < int(lines.size()); ++i) {
        std::string error;
        auto instruction = check(lines[i], trace, error);
        if (!instruction) {
            trace.rejected.push_back({i + 1, error});
            continue;
        }
        instruction->line = i + 1;
        if (!trace.instructions.empty() && trace.instructions.back().next != instruction->pc)
            trace.gaps.push_back({i + 1, trace.instructions.back().next, instruction->pc});
        trace.first.emplace(instruction->pc, int(trace.instructions.size()));
        trace.instructions.push_back(*instruction);
    }
    return trace;
}
struct Detail {
    I predicted = 0;
    int miss = -1;
};
struct Prediction {
    std::vector<Detail> details;
    std::vector<bool> flags;
    I control = 0, total_misses = 0, hits = 0, calls = 0, returns = 0, ras_predictions = 0,
      ras_correct = 0;
    std::array<I, 2> count{}, wrong{};
    std::array<I, 3> kinds{};
    int bits = 0;
};
static Prediction predict(const std::vector<Instruction> &instructions, const Predictor &definition,
                          const Config &config) {
    BTB btb(config.btb);
    RAS ras(config.ras);
    DirectionPredictor direction(definition);
    Prediction out;
    out.details.resize(instructions.size());
    out.flags.resize(instructions.size());
    out.bits = direction.bits();
    for (int i = 0; i < int(instructions.size()); ++i) {
        const Instruction &instruction = instructions[i];
        if (!instruction.control())
            continue;
        auto candidate = btb.lookup(instruction.pc);
        ++out.control;
        out.hits += bool(candidate);
        const bool call = instruction.kind == jump && instruction.rd == 31,
                   ret = instruction.kind == jump && instruction.rd < 0 && instruction.rs1 == 31;
        out.calls += call;
        out.returns += ret;
        if (ret)
            if (const auto address = ras.pop()) {
                candidate = address;
                ++out.ras_predictions;
                out.ras_correct += *address == instruction.target;
            }
        if (call)
            ras.push(instruction.pc + 4);
        const bool taken = instruction.kind == branch
                               ? direction.prediction(instruction.pc, instruction.target)
                               : true;
        const I next = definition.scheme == "PERFECT"                     ? instruction.next
                       : (instruction.kind == jump || taken) && candidate ? *candidate
                                                                          : instruction.pc + 4;
        Detail &detail = out.details[i];
        detail.predicted = next;
        if (next != instruction.next) {
            detail.miss = instruction.kind == branch && taken != instruction.taken ? 0
                          : !candidate                                             ? 1
                                                                                   : 2;
            ++out.kinds[detail.miss];
            ++out.total_misses;
            out.flags[i] = true;
        }
        const int kind = instruction.kind == branch ? 0 : 1;
        ++out.count[kind];
        out.wrong[kind] += out.flags[i];
        if (instruction.kind == branch)
            direction.update(instruction.pc, instruction.taken);
        if (instruction.taken)
            btb.insert(instruction.pc, instruction.target);
    }
    return out;
}
struct Combination {
    int variant, predictor, cycles;
    std::array<I, 4> stalls;
};
struct Segment {
    int first, last;
    char mark;
    int stage;
};
struct Diagram {
    Lines lines;
    std::array<std::array<I, 2>, 5> occupancy{};
    I flushed = 0;
};
static Diagram diagram(const std::vector<Instruction> &instructions, const Run &run,
                       const Variant &variant, const Prediction &prediction, const Config &config) {
    Diagram out;
    const int width = config.end - config.start + 1;
    line(out.lines, "pipeline variant=", variant.name, " predictor=", config.primary_predictor,
         " cycles ", config.start, "-", config.end);
    out.lines.push_back(cycle_heading(config.start, config.end));
    std::vector<std::array<std::string, 5>> contents(width);
    for (auto &row : contents)
        row.fill(".");
    std::vector<std::string> annotations(instructions.size());
    for (const Record &record : run.records)
        if (record.waiting >= 0)
            annotations[record.waiting] +=
                " " + std::string(causes[record.cause]) + " " + std::to_string(record.cycles);
    I rows = 0, stall_cells = 0, flushed_cells = 0, completed = 0;
    auto add = [&](int number, I pc, const std::string &kind, const std::vector<Segment> &segments,
                   const std::string &annotation) {
        std::string cells(width, '.');
        bool present = false;
        for (const Segment &segment : segments) {
            if (segment.last < segment.first)
                continue;
            if (segment.stage >= 0)
                out.occupancy[segment.stage][number < 0] += segment.last - segment.first + 1;
            for (int cycle = std::max(config.start, segment.first);
                 cycle <= std::min(config.end, segment.last); ++cycle) {
                cells[cycle - config.start] = segment.mark;
                present = true;
                stall_cells += segment.mark == '*';
                flushed_cells += segment.mark == 'x';
                if (segment.stage >= 0)
                    contents[cycle - config.start][segment.stage] =
                        number < 0 ? "w" : std::to_string(number);
            }
        }
        if (present) {
            out.lines.push_back(diagram_row(number, pc, kind, cells, annotation));
            ++rows;
        }
    };
    for (int i = 0; i < int(instructions.size()); ++i) {
        const Timing &t = run.timings[i];
        const Instruction &instruction = instructions[i];
        std::string annotation = annotations[i];
        if (prediction.flags[i])
            annotation += " mispredict " + std::string(misses[prediction.details[i].miss]);
        add(i + 1, instruction.pc, classes[instruction.kind],
            {{t.f, t.f, 'F', 0},
             {t.f + 1, t.d - 1, '*', 0},
             {t.d, t.d, 'D', 1},
             {t.d + 1, t.x - 1, '*', 1},
             {t.x, t.m - 1, 'X', 2},
             {t.m, t.m, 'M', 3},
             {t.w, t.w, 'W', 4}},
            annotation);
        completed += t.w >= config.start && t.w <= config.end;
        if (!prediction.flags[i])
            continue;
        const bool early = id_resolved(instruction, variant);
        const I pc = prediction.details[i].predicted;
        std::vector<Segment> first{{t.d, t.d, 'F', 0}, {t.d + 1, t.x - 1, '*', 0}};
        if (early)
            first.push_back({t.x, t.x, 'x', -1});
        else {
            first.push_back({t.x, t.x, 'D', 1});
            first.push_back({t.x + 1, t.x + 1, 'x', -1});
        }
        add(-1, pc, "FLUSH", first, "");
        ++out.flushed;
        if (!early) {
            add(-1, pc + 4, "FLUSH", {{t.x, t.x, 'F', 0}, {t.x + 1, t.x + 1, 'x', -1}}, "");
            ++out.flushed;
        }
    }
    line(out.lines, "rows ", rows, " completed ", completed, " stall_cells ", stall_cells,
         " flushed ", flushed_cells);
    out.lines.push_back("");
    out.lines.push_back("stages");
    out.lines.push_back("cycle IF ID EX MEM WB");
    for (int i = 0; i < width; ++i)
        line(out.lines, config.start + i, " ", contents[i][0], " ", contents[i][1], " ",
             contents[i][2], " ", contents[i][3], " ", contents[i][4]);
    return out;
}
struct Dependency {
    I producer, waiting;
    int cause;
    I cycles = 0, events = 0;
};
struct ProfileSegment {
    I pc;
    I instances = 0, instructions = 0, cycles = 0;
};
int main() {
    const Input input = read_inputs();
    const Config &config = input.config;
    const Trace trace = validate(input.trace);
    const std::vector<Instruction> &instructions = trace.instructions;
    const int n = int(instructions.size());
    const Sources sources = dependencies(instructions);
    std::vector<Prediction> predictions;
    int primary_predictor = 0, primary_variant = 0;
    for (int i = 0; i < int(config.predictors.size()); ++i) {
        predictions.push_back(predict(instructions, config.predictors[i], config));
        if (config.predictors[i].name == config.primary_predictor)
            primary_predictor = i;
    }
    for (int i = 0; i < int(config.variants.size()); ++i)
        if (config.variants[i].name == config.primary_variant)
            primary_variant = i;
    std::vector<Combination> combinations;
    std::vector<std::vector<int>> table(config.variants.size(),
                                        std::vector<int>(config.predictors.size()));
    Run primary;
    for (int v = 0; v < int(config.variants.size()); ++v)
        for (int p = 0; p < int(predictions.size()); ++p) {
            Run run = simulate(instructions, sources, config.variants[v], predictions[p].flags);
            table[v][p] = run.cycles;
            combinations.push_back({v, p, run.cycles, run.stalls});
            if (v == primary_variant && p == primary_predictor)
                primary = std::move(run);
        }
    const Variant &variant = config.variants[primary_variant];
    const Prediction &prediction = predictions[primary_predictor];
    const int cycles = primary.cycles;
    const Diagram picture = diagram(instructions, primary, variant, prediction, config);
    save("pipeline.txt", picture.lines);
    std::array<I, 7> mix{}, class_stalls{};
    std::array<I, 5> distances{}, lengths{};
    std::array<I, 3> paths{};
    I taken = 0, backward = 0, indirect = 0, link = 0, operands = 0, produced = 0, height = 0;
    std::set<I> addresses;
    std::map<I, std::vector<int>> executions;
    std::vector<I> finish(n);
    for (int i = 0; i < n; ++i) {
        const Instruction &instruction = instructions[i];
        ++mix[instruction.kind];
        executions[instruction.pc].push_back(i);
        if (instruction.kind == branch) {
            taken += instruction.taken;
            backward += instruction.target < instruction.pc;
        }
        if (instruction.kind == jump) {
            indirect += instruction.rs1 >= 0;
            link += instruction.rd >= 0;
        }
        if (instruction.kind == load || instruction.kind == store)
            addresses.insert(instruction.address);
        const std::array<int, 2> registers{instruction.rs1, instruction.rs2};
        I start = 0;
        for (int j = 0; j < 2; ++j)
            if (registers[j] > 0) {
                ++operands;
                const int p = sources[i][j];
                if (p >= 0) {
                    ++produced;
                    ++distances[std::min(5, i - p) - 1];
                    start = std::max(start, finish[p]);
                }
                ++paths[forwarding_path(instruction, p < 0 ? nullptr : &primary.timings[p],
                                        primary.timings[i], variant)];
            }
        finish[i] = start + (instruction.kind == load       ? 2
                             : instruction.kind == multiply ? variant.latency
                                                            : 1);
        height = std::max(height, finish[i]);
        if (i > 0) {
            const int delay = primary.timings[i].x - primary.timings[i - 1].x - 1;
            if (delay > 0)
                ++lengths[std::min(5, delay) - 1];
        }
    }
    std::map<I, std::array<I, 4>> stalls_by_pc;
    std::map<std::tuple<I, I, int>, std::pair<I, I>> dependency_groups;
    for (const Record &record : primary.records) {
        const Instruction &responsible = instructions[record.responsible];
        class_stalls[responsible.kind] += record.cycles;
        stalls_by_pc[responsible.pc][record.cause] += record.cycles;
        if (record.cause >= 2) {
            auto &group = dependency_groups[{instructions[record.producer].pc,
                                             instructions[record.waiting].pc, record.cause}];
            group.first += record.cycles;
            ++group.second;
        }
    }
    std::vector<I> hotspots;
    for (const auto &[pc, stalls] : stalls_by_pc)
        if (std::accumulate(stalls.begin(), stalls.end(), I(0)) > 0)
            hotspots.push_back(pc);
    std::sort(hotspots.begin(), hotspots.end(), [&](I a, I b) {
        const auto &x = stalls_by_pc[a], &y = stalls_by_pc[b];
        const I sa = std::accumulate(x.begin(), x.end(), I(0)),
                sb = std::accumulate(y.begin(), y.end(), I(0));
        return sa != sb ? sa > sb : a < b;
    });
    std::vector<Dependency> dependencies_rank;
    for (const auto &[key, values] : dependency_groups)
        dependencies_rank.push_back(
            {std::get<0>(key), std::get<1>(key), std::get<2>(key), values.first, values.second});
    std::sort(dependencies_rank.begin(), dependencies_rank.end(),
              [](const Dependency &a, const Dependency &b) {
                  return a.cycles != b.cycles ? a.cycles > b.cycles
                                              : std::tie(a.producer, a.waiting, a.cause) <
                                                    std::tie(b.producer, b.waiting, b.cause);
              });
    Lines stats;
    line(stats, "input lines ", input.trace.size(), " accepted ", n, " rejected ",
         trace.rejected.size(), " gaps ", trace.gaps.size());
    for (const Rejection &r : trace.rejected)
        line(stats, "reject line ", r.line, " ", r.reason);
    for (const Gap &g : trace.gaps)
        line(stats, "gap line ", g.line, " expected ", hexadecimal(g.expected), " found ",
             hexadecimal(g.found));
    stats.push_back("");
    stats.push_back("trace");
    line(stats, "instructions ", n);
    line(stats, "static_instructions ", trace.first.size());
    std::string mix_line = "mix";
    for (int i = 0; i < 7; ++i)
        mix_line += " " + std::string(classes[i]) + " " + std::to_string(mix[i]);
    stats.push_back(mix_line);
    line(stats, "branches ", mix[branch], " taken ", taken, " backward ", backward);
    line(stats, "jumps ", mix[jump], " indirect ", indirect, " link ", link);
    int static_branches = 0, static_jumps = 0;
    for (const auto &[pc, i] : trace.first) {
        static_branches += instructions[i].kind == branch;
        static_jumps += instructions[i].kind == jump;
    }
    line(stats, "static_control branches ", static_branches, " jumps ", static_jumps);
    line(stats, "memory loads ", mix[load], " stores ", mix[store], " distinct_addresses ",
         addresses.size());
    line(stats, "operands ", operands, " with_producer ", produced, " distance 1 ", distances[0],
         " 2 ", distances[1], " 3 ", distances[2], " 4 ", distances[3], " 5+ ", distances[4]);
    stats.push_back("");
    stats.push_back("prediction");
    for (int p = 0; p < int(predictions.size()); ++p) {
        const Prediction &r = predictions[p];
        const Predictor &d = config.predictors[p];
        line(stats, d.name, " ", d.scheme, " bits ", r.bits, " control ", r.control,
             " mispredicted ", r.total_misses, " accuracy ",
             percentage(r.control - r.total_misses, r.control), " branches ",
             percentage(r.count[0] - r.wrong[0], r.count[0]), " jumps ",
             percentage(r.count[1] - r.wrong[1], r.count[1]), " direction ", r.kinds[0],
             " btb_miss ", r.kinds[1], " wrong_target ", r.kinds[2]);
    }
    line(stats, "btb entries ", config.btb, " lookups ", prediction.control, " hits ",
         prediction.hits, " misses ", prediction.control - prediction.hits);
    line(stats, "ras depth ", config.ras, " calls ", prediction.calls, " returns ",
         prediction.returns, " predicted ", prediction.ras_predictions, " correct ",
         prediction.ras_correct);
    stats.push_back("");
    line(stats, "timing variant=", variant.name, " predictor=", config.primary_predictor);
    line(stats, "forwarding ", variant.forwarding ? "on" : "off", " branch_stage ",
         variant.id ? "ID" : "EX", " mul_latency ", variant.latency);
    line(stats, "cycles ", cycles);
    line(stats, "cpi ", fraction(cycles, n), " ", decimal(cycles, n));
    line(stats, "ipc ", decimal(n, cycles));
    const I total_stalls = std::accumulate(primary.stalls.begin(), primary.stalls.end(), I(0));
    line(stats, "stall_cycles total ", total_stalls, " control ", primary.stalls[0], " structural ",
         primary.stalls[1], " load_use ", primary.stalls[2], " raw ", primary.stalls[3]);
    line(stats, "stall_events control ", primary.events[0], " structural ", primary.events[1],
         " load_use ", primary.events[2], " raw ", primary.events[3]);
    line(stats, "flushed ", picture.flushed);
    line(stats, "cycle_check ", n, " + 4 + ", total_stalls, " = ", n + 4 + total_stalls);
    line(stats, "cpi_stack base 1.0000 fill ", decimal(4, n), " control ",
         decimal(primary.stalls[0], n), " structural ", decimal(primary.stalls[1], n), " load_use ",
         decimal(primary.stalls[2], n), " raw ", decimal(primary.stalls[3], n));
    line(stats, "stall_lengths 1 ", lengths[0], " 2 ", lengths[1], " 3 ", lengths[2], " 4 ",
         lengths[3], " 5+ ", lengths[4]);
    line(stats, "dataflow height ", height, " ilp ", decimal(n, height));
    stats.push_back("");
    stats.push_back("whatif");
    for (int change = 0; change < 4; ++change) {
        Variant modified = variant;
        std::vector<bool> flags = prediction.flags;
        std::string name;
        if (change == 0) {
            name = "perfect_prediction";
            flags.assign(n, false);
        } else if (change == 1) {
            name = "single_cycle_mul";
            modified.latency = 1;
        } else if (change == 2) {
            name = variant.forwarding ? "forwarding_off" : "forwarding_on";
            modified.forwarding = !variant.forwarding;
        } else {
            name = variant.id ? "branch_stage_EX" : "branch_stage_ID";
            modified.id = !variant.id;
        }
        const int count = simulate(instructions, sources, modified, flags).cycles;
        line(stats, name, " cycles ", count, " saved ", cycles - count, " speedup ",
             decimal(cycles, count));
    }
    stats.push_back("");
    stats.push_back("classes");
    for (int i = 0; i < 7; ++i)
        line(stats, classes[i], " count ", mix[i], " stall_cycles ", class_stalls[i],
             " per_instruction ", mix[i] ? decimal(class_stalls[i], mix[i]) : "-");
    stats.push_back("");
    line(stats, "forwarding regfile ", paths[0], " ex_mem ", paths[1], " mem_wb ", paths[2]);
    stats.push_back("");
    line(stats, "occupancy cycles ", cycles);
    for (int i = 0; i < 5; ++i) {
        const auto &value = picture.occupancy[i];
        line(stats, stages[i], " correct ", value[0], " wrong ", value[1], " idle ",
             cycles - value[0] - value[1], " busy ", percentage(value[0] + value[1], cycles));
    }
    stats.push_back("");
    stats.push_back("hotspots");
    for (int i = 0; i < std::min(config.top, int(hotspots.size())); ++i) {
        const I pc = hotspots[i];
        const auto &s = stalls_by_pc[pc];
        line(stats, i + 1, " ", hexadecimal(pc), " ",
             classes[instructions[trace.first.at(pc)].kind], " stall_cycles ",
             std::accumulate(s.begin(), s.end(), I(0)), " control ", s[0], " structural ", s[1],
             " load_use ", s[2], " raw ", s[3]);
    }
    stats.push_back("");
    line(stats, "dependencies total ", dependencies_rank.size());
    for (int i = 0; i < std::min(config.top, int(dependencies_rank.size())); ++i) {
        const Dependency &d = dependencies_rank[i];
        line(stats, i + 1, " ", hexadecimal(d.producer), " ",
             classes[instructions[trace.first.at(d.producer)].kind], " -> ", hexadecimal(d.waiting),
             " ", classes[instructions[trace.first.at(d.waiting)].kind], " ", causes[d.cause],
             " stall_cycles ", d.cycles, " events ", d.events);
    }
    stats.push_back("");
    line(stats, "intervals size ", config.interval);
    for (int a = 0; a < n; a += config.interval) {
        const int b = std::min(n, a + config.interval) - 1,
                  count = primary.timings[b].w - (a ? primary.timings[a - 1].w : 0);
        line(stats, a + 1, "-", b + 1, " cycles ", count, " cpi ", decimal(count, b - a + 1));
    }
    stats.push_back("");
    std::string heading = "cycles_table";
    for (const Predictor &p : config.predictors)
        heading += " " + p.name;
    stats.push_back(heading);
    for (int i = 0; i < int(config.variants.size()); ++i) {
        std::string row = config.variants[i].name;
        for (int count : table[i])
            row += " " + std::to_string(count);
        stats.push_back(row);
    }
    save("stats.txt", stats);
    Lines branches{"predictor,pc,class,executions,taken,mispredictions,accuracy"};
    for (int p = 0; p < int(predictions.size()); ++p)
        for (const auto &[pc, indices] : executions) {
            const Instruction &instruction = instructions[indices[0]];
            if (!instruction.control())
                continue;
            I count_taken = 0, wrong = 0;
            for (int i : indices) {
                count_taken += instructions[i].taken;
                wrong += predictions[p].flags[i];
            }
            line(branches, config.predictors[p].name, ",", hexadecimal(pc), ",",
                 classes[instruction.kind], ",", indices.size(), ",", count_taken, ",", wrong, ",",
                 percentage(I(indices.size()) - wrong, I(indices.size())));
        }
    save("branches.csv", branches);
    std::sort(combinations.begin(), combinations.end(),
              [&](const Combination &a, const Combination &b) {
                  return std::tie(a.cycles, config.variants[a.variant].name,
                                  config.predictors[a.predictor].name) <
                         std::tie(b.cycles, config.variants[b.variant].name,
                                  config.predictors[b.predictor].name);
              });
    Lines comparison{
        "rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw"};
    for (int i = 0; i < int(combinations.size()); ++i) {
        const Combination &r = combinations[i];
        const Prediction &p = predictions[r.predictor];
        line(comparison, i + 1, ",", config.variants[r.variant].name, ",",
             config.predictors[r.predictor].name, ",", r.cycles, ",", decimal(r.cycles, n), ",",
             decimal(cycles, r.cycles), ",", percentage(p.control - p.total_misses, p.control), ",",
             p.total_misses, ",", r.stalls[0], ",", r.stalls[1], ",", r.stalls[2], ",",
             r.stalls[3]);
    }
    save("comparison.csv", comparison);
    Lines profile{"branches"};
    for (const auto &[pc, indices] : executions) {
        const Instruction &instruction = instructions[indices[0]];
        if (instruction.kind != branch)
            continue;
        I transitions = 0, count_taken = 0, run_length = 0;
        std::array<I, 2> longest{};
        bool previous = false;
        for (int i : indices) {
            const bool value = instructions[i].taken;
            count_taken += value;
            if (run_length && value != previous) {
                ++transitions;
                run_length = 0;
            }
            ++run_length;
            longest[value] = std::max(longest[value], run_length);
            previous = value;
        }
        I best_misses = I(indices.size()) + 1;
        int best = 0;
        for (int p = 0; p < int(predictions.size()); ++p)
            if (config.predictors[p].scheme != "PERFECT") {
                I wrong = 0;
                for (int i : indices)
                    wrong += predictions[p].flags[i];
                if (wrong < best_misses) {
                    best_misses = wrong;
                    best = p;
                }
            }
        line(profile, hexadecimal(pc), " ", instruction.target < pc ? "backward" : "forward",
             " executions ", indices.size(), " taken ", count_taken, " transitions ", transitions,
             " longest_taken ", longest[1], " longest_not_taken ", longest[0], " best ",
             config.predictors[best].name, " ", best_misses);
    }
    profile.push_back("");
    profile.push_back("loops");
    for (const auto &[pc, indices] : executions) {
        const Instruction &instruction = instructions[indices[0]];
        if (instruction.kind != branch || instruction.target >= pc)
            continue;
        I entries = 0, longest = 0, length = 0;
        for (int i : indices) {
            ++length;
            if (!instructions[i].taken) {
                ++entries;
                longest = std::max(longest, length);
                length = 0;
            }
        }
        if (length) {
            ++entries;
            longest = std::max(longest, length);
        }
        line(profile, hexadecimal(instruction.target), "-", hexadecimal(pc), " body ",
             (pc - instruction.target) / 4 + 1, " entries ", entries, " iterations ",
             indices.size(), " avg_trip ", decimal(I(indices.size()), entries), " max_trip ",
             longest);
    }
    std::map<I, ProfileSegment> segment_groups;
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n - 1 && !instructions[b].control())
            ++b;
        auto &group = segment_groups[instructions[a].pc];
        group.pc = instructions[a].pc;
        ++group.instances;
        group.instructions += b - a + 1;
        group.cycles += primary.timings[b].w - (a ? primary.timings[a - 1].w : 0);
        a = b + 1;
    }
    std::vector<ProfileSegment> segments_rank;
    for (const auto &[pc, group] : segment_groups)
        segments_rank.push_back(group);
    std::sort(segments_rank.begin(), segments_rank.end(),
              [](const ProfileSegment &a, const ProfileSegment &b) {
                  return a.cycles != b.cycles ? a.cycles > b.cycles : a.pc < b.pc;
              });
    profile.push_back("");
    line(profile, "segments total ", segments_rank.size());
    for (int i = 0; i < std::min(config.top, int(segments_rank.size())); ++i) {
        const ProfileSegment &r = segments_rank[i];
        line(profile, i + 1, " ", hexadecimal(r.pc), " instances ", r.instances, " instructions ",
             r.instructions, " cycles ", r.cycles, " cpi ", decimal(r.cycles, r.instructions));
    }
    profile.push_back("");
    profile.push_back("indirect");
    for (const auto &[pc, indices] : executions) {
        const Instruction &instruction = instructions[indices[0]];
        if (instruction.kind != jump || instruction.rs1 < 0)
            continue;
        std::map<I, I> targets;
        for (int i : indices)
            ++targets[instructions[i].target];
        std::vector<std::pair<I, I>> ordered(targets.begin(), targets.end());
        std::sort(ordered.begin(), ordered.end(), [](const auto &a, const auto &b) {
            return a.second != b.second ? a.second > b.second : a.first < b.first;
        });
        std::string tail;
        for (const auto &[target, count] : ordered)
            tail += " " + hexadecimal(target) + ":" + std::to_string(count);
        line(profile, hexadecimal(pc), " executions ", indices.size(), " distinct ", ordered.size(),
             " targets", tail);
    }
    profile.push_back("");
    profile.push_back("instructions");
    for (const auto &[pc, indices] : executions) {
        const Instruction &r = instructions[indices[0]];
        const auto &stalls = stalls_by_pc[pc];
        line(profile, hexadecimal(pc), " ", classes[r.kind], " ", register_name(r.rd), " ",
             register_name(r.rs1), " ", register_name(r.rs2), " executions ", indices.size(),
             " stall_cycles ", std::accumulate(stalls.begin(), stalls.end(), I(0)));
    }
    save("profile.txt", profile);
}
