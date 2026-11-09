#include "collector.hpp"
template <class... T> static std::string text(const T &...values) {
    std::ostringstream out;
    bool first = true;
    auto put = [&](const auto &value) {
        if (!first)
            out << ' ';
        first = false;
        out << value;
    };
    (put(values), ...);
    return out.str();
}
static std::string pair_text(Pair pair) {
    return text(pair.count, pair.words);
}
static std::set<int> reachable(const Heap &heap) {
    std::set<int> marked;
    std::vector<int> stack;
    for (int root : heap.roots)
        if (root && marked.insert(root).second)
            stack.push_back(root);
    while (!stack.empty()) {
        const int id = stack.back();
        stack.pop_back();
        for (int value : heap.object(id).fields)
            if (value && marked.insert(value).second)
                stack.push_back(value);
    }
    return marked;
}
static Pair amount(const Heap &heap, const std::set<int> &ids) {
    Pair pair;
    for (int id : ids)
        pair.add(heap.object(id).size());
    return pair;
}
static int slot_value(const Heap &heap, int index) {
    return index < 0 ? 0 : heap.roots[index];
}
static void execute_plain(Heap &heap, const Command &c) {
    if (c.kind == "ALLOC") {
        const int id = int(heap.objects.size() + 1);
        heap.objects.push_back(
            {id, c.args[0], c.args[1], 0, 0, 0, 0, true, false, std::vector<int>(c.args[0])});
        heap.roots.push_back(id);
    } else if (c.kind == "PUSH")
        heap.roots.push_back(slot_value(heap, c.args[0]));
    else if (c.kind == "LOAD")
        heap.roots.push_back(heap.object(heap.roots[c.args[0]]).fields[c.args[1]]);
    else if (c.kind == "POP")
        heap.roots.resize(heap.roots.size() - c.args[0]);
    else if (c.kind == "SET")
        heap.object(heap.roots[c.args[0]]).fields[c.args[1]] = slot_value(heap, c.args[2]);
    else if (c.kind == "OVERWRITE")
        heap.roots[c.args[0]] = slot_value(heap, c.args[1]);
}
struct Checkpoint {
    std::string label;
    int line, roots;
    Pair live, allocated, phase, survivors;
};
struct Reference {
    Heap heap;
    std::vector<Command> commands, errors;
    std::vector<int> death, lifetime, birth;
    std::vector<Checkpoint> checkpoints;
    std::map<std::string, int> counts;
    Pair allocated, peak, ending;
    int peak_line = 0, line_count;
    explicit Reference(std::vector<Command> source) : heap{0, 0, 0, {}}, line_count(int(source.size())) {
        std::set<std::string> labels;
        int phase_first = 1;
        Pair phase;
        for (Command command : source) {
            const int roots = int(heap.roots.size());
            const std::string &kind = command.kind;
            const std::vector<int> &a = command.args;
            if (command.error.empty()) {
                bool invalid = ((kind == "ALLOC" || kind == "PUSH" || kind == "LOAD") && roots == 64) ||
                               (kind == "POP" && a[0] > roots);
                if (kind == "LOAD" || kind == "SET" || kind == "OVERWRITE")
                    invalid = invalid || a[0] >= roots;
                const int r = kind == "PUSH" ? a[0] : kind == "SET" ? a[2] : kind == "OVERWRITE" ? a[1] : -1;
                if (r >= roots)
                    invalid = true;
                if (invalid)
                    command.error = "stack";
                else if ((kind == "LOAD" || kind == "SET") && !heap.roots[a[0]])
                    command.error = "null";
                else if ((kind == "LOAD" || kind == "SET") && a[1] >= heap.object(heap.roots[a[0]]).p)
                    command.error = "field";
                else if (kind == "CHECKPOINT" && labels.count(command.label))
                    command.error = "duplicate";
            }
            if (!command.error.empty()) {
                errors.push_back(command);
                continue;
            }
            if (kind == "ALLOC") {
                command.object = int(heap.objects.size() + 1);
                birth.push_back(int(allocated.words));
                death.push_back(0);
                lifetime.push_back(0);
                allocated.add(1 + a[0] + a[1]);
                phase.add(1 + a[0] + a[1]);
            }
            execute_plain(heap, command);
            commands.push_back(command);
            ++counts[kind];
            const std::set<int> live = reachable(heap);
            ending = amount(heap, live);
            for (const Object &object : heap.objects)
                if (!death[object.id - 1] && !live.count(object.id)) {
                    death[object.id - 1] = command.line;
                    lifetime[object.id - 1] = int(allocated.words) - birth[object.id - 1] - object.size();
                }
            if (ending.words > peak.words) {
                peak = ending;
                peak_line = command.line;
            }
            if (kind == "CHECKPOINT") {
                labels.insert(command.label);
                Pair survivors;
                for (int id : live)
                    if (id >= phase_first)
                        survivors.add(heap.object(id).size());
                checkpoints.push_back({command.label, command.line, int(heap.roots.size()), ending, allocated,
                                       phase, survivors});
                phase = {};
                phase_first = int(heap.objects.size() + 1);
            }
        }
    }
    std::vector<std::string> report() const {
        std::vector<std::string> lines{
            text("script lines", line_count, "valid", commands.size(), "errors", errors.size())};
        for (const Command &error : errors)
            lines.push_back(text("error line", error.line, error.error));
        std::ostringstream command_line;
        command_line << "commands";
        for (const std::string &kind : {"ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT"}) {
            const auto found = counts.find(kind);
            command_line << ' ' << kind << ' ' << (found == counts.end() ? 0 : found->second);
        }
        lines.push_back(command_line.str());
        std::vector<int> sizes;
        for (const Object &object : heap.objects)
            sizes.push_back(object.size());
        lines.push_back(text("allocated objects", allocated.count, "words", allocated.words, "sizes",
                             class_table(sizes)));
        lines.push_back(text("peak_live objects", peak.count, "words", peak.words, "line", peak_line));
        lines.push_back(
            text("end_live objects", ending.count, "words", ending.words, "stack", heap.roots.size()));
        int lives[6] = {};
        for (std::size_t i = 0; i < death.size(); ++i) {
            const int value = lifetime[i];
            ++lives[!death[i]      ? 5
                    : value < 64   ? 0
                    : value < 256  ? 1
                    : value < 1024 ? 2
                    : value < 4096 ? 3
                                   : 4];
        }
        lines.push_back(text("lifetimes 0-63", lives[0], "64-255", lives[1], "256-1023", lives[2],
                             "1024-4095", lives[3], "4096+", lives[4], "live", lives[5]));
        for (const Checkpoint &checkpoint : checkpoints)
            lines.push_back(text("checkpoint", checkpoint.label, "line", checkpoint.line, "stack",
                                 checkpoint.roots, "live", pair_text(checkpoint.live), "allocated",
                                 pair_text(checkpoint.allocated), "phase", pair_text(checkpoint.phase),
                                 "survivors", pair_text(checkpoint.survivors), "survival",
                                 pct(checkpoint.survivors.words, checkpoint.phase.words)));
        return lines;
    }
};
struct Pause {
    int line;
    Integer work;
    Pair freed;
    bool collection;
};
struct PauseStats {
    Integer work = 0, freed = 0, maximum = 0;
    std::string p50 = "-", p90 = "-";
};
static PauseStats pause_stats(const std::vector<Pause> &pauses) {
    PauseStats stats;
    std::vector<Integer> values;
    for (const Pause &pause : pauses) {
        stats.work += pause.work;
        stats.freed += pause.freed.words;
        stats.maximum = std::max(stats.maximum, pause.work);
        values.push_back(pause.work);
    }
    if (!values.empty()) {
        std::sort(values.begin(), values.end());
        stats.p50 = std::to_string(values[(50 * values.size() + 99) / 100 - 1]);
        stats.p90 = std::to_string(values[(90 * values.size() + 99) / 100 - 1]);
    }
    return stats;
}
struct Timeline {
    struct Segment {
        Integer end, mutator;
        bool active;
    };
    std::vector<Segment> segments;
    Integer total = 0, mutator = 0;
    void add(bool active, Integer length) {
        if (!length)
            return;
        total += length;
        if (active)
            mutator += length;
        if (!segments.empty() && segments.back().active == active)
            segments.back() = {total, mutator, active};
        else
            segments.push_back({total, mutator, active});
    }
    Integer prefix(Integer time) const {
        if (time <= 0)
            return 0;
        const auto found =
            std::lower_bound(segments.begin(), segments.end(), time,
                             [](const Segment &segment, Integer value) { return segment.end < value; });
        const Integer before = found == segments.begin() ? 0 : (found - 1)->mutator;
        const Integer start = found == segments.begin() ? 0 : (found - 1)->end;
        return before + (found->active ? time - start : 0);
    }
    std::string mmu(int width) const {
        if (width > total)
            return "-";
        Integer best = width;
        auto evaluate = [&](Integer start) {
            if (start >= 0 && start + width <= total)
                best = std::min(best, prefix(start + width) - prefix(start));
        };
        evaluate(0);
        evaluate(total - width);
        for (const Segment &segment : segments) {
            evaluate(segment.end);
            evaluate(segment.end - width);
        }
        return pct(best, width);
    }
};
struct Cascade {
    Pair freed;
    Integer work = 0;
    int line = 0;
};
class Run {
    const Config &config;
    const Reference &reference;
    void retain(int id) {
        if (id) {
            ++heap.object(id).references;
            ++increments;
        }
    }
    void release(int id, Cascade &cascade) {
        std::vector<int> stack;
        if (id)
            stack.push_back(id);
        while (!stack.empty()) {
            const int current = stack.back();
            stack.pop_back();
            Object &object = heap.object(current);
            ++decrements;
            if (--object.references)
                continue;
            object.present = false;
            cascade.freed.add(object.size());
            cascade.work += 1 + object.p;
            for (auto field = object.fields.rbegin(); field != object.fields.rend(); ++field)
                if (*field)
                    stack.push_back(*field);
        }
    }
    std::vector<std::string> leak_report(const std::string &title, const std::set<int> &garbage) const {
        const int size = int(heap.objects.size());
        std::vector<int> parent(size + 1);
        std::iota(parent.begin(), parent.end(), 0);
        std::function<int(int)> find = [&](int id) {
            return parent[id] == id ? id : parent[id] = find(parent[id]);
        };
        for (int id : garbage)
            for (int value : heap.object(id).fields)
                if (garbage.count(value))
                    parent[find(id)] = find(value);
        std::map<int, std::vector<int>> by_component;
        for (int id : garbage)
            by_component[find(id)].push_back(id);
        std::vector<std::vector<int>> groups;
        for (const auto &item : by_component)
            groups.push_back(item.second);
        std::sort(groups.begin(), groups.end(), [](const auto &a, const auto &b) { return a[0] < b[0]; });
        std::vector<int> index(size + 1, -1), low(size + 1), stack;
        std::vector<bool> active(size + 1);
        std::set<int> cyclic;
        int next = 0;
        std::function<void(int)> visit = [&](int id) {
            index[id] = low[id] = next++;
            stack.push_back(id);
            active[id] = true;
            for (int value : heap.object(id).fields)
                if (garbage.count(value)) {
                    if (index[value] < 0) {
                        visit(value);
                        low[id] = std::min(low[id], low[value]);
                    } else if (active[value])
                        low[id] = std::min(low[id], index[value]);
                }
            if (low[id] != index[id])
                return;
            std::vector<int> component;
            while (true) {
                const int value = stack.back();
                stack.pop_back();
                active[value] = false;
                component.push_back(value);
                if (value == id)
                    break;
            }
            bool cycle = component.size() > 1;
            if (!cycle)
                for (int value : heap.object(id).fields)
                    if (value == id)
                        cycle = true;
            if (cycle)
                cyclic.insert(component.begin(), component.end());
        };
        for (int id : garbage)
            if (index[id] < 0)
                visit(id);
        const Pair all = amount(heap, garbage);
        std::vector<std::string> lines{
            text(title, "groups", groups.size(), "objects", all.count, "words", all.words)};
        for (std::size_t i = 0; i < groups.size(); ++i) {
            Pair pair;
            int died = 0, cycles = 0;
            std::ostringstream ids;
            for (int id : groups[i]) {
                pair.add(heap.object(id).size());
                died = std::max(died, reference.death[id - 1]);
                if (cyclic.count(id))
                    ++cycles;
                ids << ' ' << id << (cyclic.count(id) ? "*" : "");
            }
            lines.push_back(text("group", i + 1, "objects", pair.count, "words", pair.words, "cycle", cycles,
                                 "died", died, "ids") +
                            ids.str());
        }
        return lines;
    }
    std::set<int> garbage(const std::set<int> &live) const {
        std::set<int> result;
        for (const Object &object : heap.objects)
            if (object.present && !live.count(object.id))
                result.insert(object.id);
        return result;
    }
    bool collect(const std::string &kind, int line_number, int request) {
        Collection record{int(collections.size() + 1), line_number, request, kind};
        record.before = free_amount(heap);
        bool complete = true;
        if (kind == "sweep")
            collect_sweep(heap, record);
        else if (kind == "compact")
            collect_compact(heap, record);
        else if (kind == "copy")
            collect_copy(heap, record);
        else if (kind == "backup") {
            marking(heap, record);
            std::set<int> garbage_ids;
            for (const Object &object : heap.objects)
                if (object.present && !object.marked)
                    garbage_ids.insert(object.id);
            const auto report = leak_report(text("backup", record.number, "line", line_number), garbage_ids);
            leaks.insert(leaks.end(), report.begin(), report.end());
            sweeping(heap, record);
            for (int id : garbage_ids)
                for (int value : heap.object(id).fields)
                    if (value && heap.object(value).marked) {
                        --heap.object(value).references;
                        ++decrements;
                    }
        } else
            complete = collect_generational(heap, record);
        if (!complete)
            return false;
        record.after = free_amount(heap);
        collections.push_back(record);
        pauses.push_back({line_number, record.work, record.freed, true});
        timeline.add(false, record.work);
        return true;
    }
    int allocation_address(int size) const {
        const std::string &type = heap.collector.type;
        if (type == "MARK_SWEEP" || type == "REFCOUNT")
            return first_fit(heap, size, 0, heap.size);
        const int capacity = type == "COPYING"        ? heap.size / 2
                             : type == "GENERATIONAL" ? heap.collector.young / 2
                                                      : heap.size;
        return heap.top + size <= heap.base + capacity ? heap.top : -1;
    }
    bool allocate(const Command &command) {
        const int size = 1 + command.args[0] + command.args[1];
        int address = allocation_address(size);
        if (address < 0) {
            const std::string &type = heap.collector.type;
            if (type == "GENERATIONAL") {
                auto next_kind = [&](bool second) {
                    int largest = 0;
                    for (const auto &block : free_blocks(heap, heap.collector.young, heap.size))
                        largest = std::max(largest, block.second);
                    return largest < heap.top - heap.base ? (second ? "full" : "major")
                                                          : (second ? "tenure" : "minor");
                };
                if (!collect(next_kind(false), command.line, size))
                    return false;
                address = allocation_address(size);
                if (address < 0) {
                    if (!collect(next_kind(true), command.line, size))
                        return false;
                    address = allocation_address(size);
                }
            } else {
                const std::string kind = type == "MARK_SWEEP"     ? "sweep"
                                         : type == "MARK_COMPACT" ? "compact"
                                         : type == "COPYING"      ? "copy"
                                                                  : "backup";
                collect(kind, command.line, size);
                address = allocation_address(size);
            }
        }
        if (address < 0)
            return false;
        Object object{command.object,
                      command.args[0],
                      command.args[1],
                      address,
                      0,
                      0,
                      0,
                      true,
                      false,
                      std::vector<int>(command.args[0])};
        heap.objects.push_back(std::move(object));
        if (heap.collector.type != "MARK_SWEEP" && heap.collector.type != "REFCOUNT")
            heap.top = address + size;
        if (heap.collector.type == "REFCOUNT")
            retain(command.object);
        heap.roots.push_back(command.object);
        peak_used = std::max(peak_used, used(heap));
        return true;
    }
    void observe(const Command &command) {
        const std::set<int> live = reachable(heap), dead = garbage(live);
        Pair all;
        for (const Object &object : heap.objects)
            if (object.present)
                all.add(object.size());
        std::vector<std::string> lines{text("heap objects", pair_text(all), "reachable",
                                            pair_text(amount(heap, live)), "garbage",
                                            pair_text(amount(heap, dead)))};
        const auto blocks = free_blocks(heap);
        const auto free = free_amount(heap);
        std::vector<int> sizes;
        for (const auto &block : blocks)
            sizes.push_back(block.second);
        lines.push_back(text("free total", free.first, "largest", free.second, "blocks", blocks.size(),
                             "sizes", class_table(sizes), "fragmentation",
                             pct(free.first - free.second, free.first)));
        Integer pointers = 0, forward = 0, backward = 0, distance = 0;
        for (int id : live) {
            const Object &object = heap.object(id);
            for (int value : object.fields)
                if (value) {
                    ++pointers;
                    const int delta = heap.object(value).address - object.address;
                    if (delta > 0)
                        ++forward;
                    if (delta < 0)
                        ++backward;
                    distance += std::abs(delta);
                }
        }
        lines.push_back(text("locality pointers", pointers, "forward", forward, "backward", backward,
                             "mean_distance", pointers ? dec2(distance, pointers) : "-"));
        if (heap.collector.type == "GENERATIONAL") {
            Pair young, old;
            int ages[4] = {};
            for (const Object &object : heap.objects)
                if (object.present) {
                    if (object.address < heap.collector.young) {
                        young.add(object.size());
                        ++ages[std::min(3, object.age)];
                    } else
                        old.add(object.size());
                }
            lines.push_back(text("generations young", pair_text(young), "old", pair_text(old), "remembered",
                                 heap.remembered.size(), "ages 0:" + std::to_string(ages[0]),
                                 "1:" + std::to_string(ages[1]), "2:" + std::to_string(ages[2]),
                                 "3+:" + std::to_string(ages[3])));
        }
        if (std::find(config.maps.begin(), config.maps.end(), command.label) != config.maps.end()) {
            const std::string map = heap_map(heap, live);
            for (int first = 0; first < heap.size; first += config.width) {
                std::ostringstream prefix;
                prefix << std::setw(4) << std::setfill('0') << first;
                lines.push_back(prefix.str() + " " + map.substr(first, config.width));
            }
        }
        observations[command.label] = std::move(lines);
    }

  public:
    Heap heap;
    std::vector<Collection> collections;
    std::vector<Pause> pauses;
    Timeline timeline;
    std::vector<std::string> leaks;
    std::map<std::string, std::vector<std::string>> observations;
    Integer increments = 0, decrements = 0;
    std::vector<Cascade> cascades;
    int peak_used = 0, oom_line = 0, oom_size = 0;
    Run(const Config &configuration, const Reference &source, Collector collector)
        : config(configuration), reference(source), heap{configuration.heap, 0, 0, std::move(collector)} {
    }
    void execute() {
        for (const Command &command : reference.commands) {
            Cascade cascade;
            cascade.line = command.line;
            const std::string &kind = command.kind;
            const auto &a = command.args;
            const bool rc = heap.collector.type == "REFCOUNT";
            if (kind == "ALLOC") {
                if (!allocate(command)) {
                    oom_line = command.line;
                    oom_size = 1 + a[0] + a[1];
                    break;
                }
            } else if (kind == "PUSH" || kind == "LOAD") {
                const int value =
                    kind == "PUSH" ? slot_value(heap, a[0]) : heap.object(heap.roots[a[0]]).fields[a[1]];
                if (rc)
                    retain(value);
                heap.roots.push_back(value);
            } else if (kind == "POP") {
                for (int i = 0; i < a[0]; ++i) {
                    const int value = heap.roots.back();
                    heap.roots.pop_back();
                    if (rc)
                        release(value, cascade);
                }
            } else if (kind == "SET") {
                const int target = heap.roots[a[0]], value = slot_value(heap, a[2]),
                          before = heap.object(target).fields[a[1]];
                if (heap.collector.type == "GENERATIONAL")
                    barrier(heap, target, value);
                if (rc)
                    retain(value);
                heap.object(target).fields[a[1]] = value;
                if (rc)
                    release(before, cascade);
            } else if (kind == "OVERWRITE") {
                const int value = slot_value(heap, a[1]), before = heap.roots[a[0]];
                if (rc)
                    retain(value);
                heap.roots[a[0]] = value;
                if (rc)
                    release(before, cascade);
            }
            timeline.add(true, kind == "ALLOC" ? 1 + a[0] + a[1] : 1);
            if (cascade.freed.count) {
                cascades.push_back(cascade);
                pauses.push_back({command.line, cascade.work, cascade.freed, false});
                timeline.add(false, cascade.work);
            }
            if (kind == "CHECKPOINT")
                observe(command);
        }
        if (heap.collector.type == "REFCOUNT" && !oom_line) {
            const auto report = leak_report("end", garbage(reachable(heap)));
            leaks.insert(leaks.end(), report.begin(), report.end());
        }
    }
    std::vector<std::string> collection_report() const {
        std::vector<std::string> lines{text("collector", heap.collector.name, heap.collector.type)};
        for (const Collection &c : collections)
            lines.push_back(text(c.number, "line", c.line, "size", c.request, "kind", c.kind, "live",
                                 pair_text(c.live), "freed", pair_text(c.freed), "moved", pair_text(c.moved),
                                 "promoted", pair_text(c.promoted), "stack", c.stack, "work", c.work,
                                 "before", c.before.first, c.before.second, "after", c.after.first,
                                 c.after.second));
        const PauseStats stats = pause_stats(pauses);
        lines.push_back(text("totals collections", collections.size(), "pauses", pauses.size(), "work",
                             stats.work, "freed", stats.freed, "pause p50", stats.p50, "p90", stats.p90,
                             "max", stats.maximum));
        std::ostringstream utilization;
        utilization << "utilization " << pct(timeline.mutator, timeline.total) << " mmu";
        for (int width : config.windows)
            utilization << ' ' << width << ':' << timeline.mmu(width);
        lines.push_back(utilization.str());
        if (heap.collector.type == "GENERATIONAL") {
            std::ostringstream line;
            line << "generational";
            Pair promotions;
            for (const std::string &kind : {"minor", "major", "tenure", "full"}) {
                Integer count = 0, work = 0;
                for (const Collection &record : collections)
                    if (record.kind == kind) {
                        ++count;
                        work += record.work;
                    }
                line << ' ' << kind << ' ' << count << ' ' << work;
            }
            for (const Collection &record : collections)
                promotions.merge(record.promoted);
            line << " promoted " << pair_text(promotions) << " barrier " << heap.barriers << " remembered "
                 << heap.remembers;
            lines.push_back(line.str());
        }
        if (heap.collector.type == "REFCOUNT") {
            Pair freed;
            const Cascade *largest = nullptr;
            for (const Cascade &cascade : cascades) {
                freed.merge(cascade.freed);
                if (!largest || cascade.work > largest->work)
                    largest = &cascade;
            }
            lines.push_back(text("refcount increments", increments, "decrements", decrements, "cascades",
                                 cascades.size(), "freed", pair_text(freed), "max_cascade",
                                 largest ? largest->freed.count : 0, largest ? largest->work : 0, "line",
                                 largest ? std::to_string(largest->line) : "-"));
        }
        int previous = 0;
        for (const Checkpoint &checkpoint : reference.checkpoints) {
            if (!observations.count(checkpoint.label)) {
                lines.push_back(text("phase", checkpoint.label, "out_of_memory"));
                continue;
            }
            std::vector<Pause> phase;
            int count = 0;
            for (const Pause &pause : pauses)
                if (pause.line > previous && pause.line <= checkpoint.line) {
                    phase.push_back(pause);
                    if (pause.collection)
                        ++count;
                }
            const PauseStats stats_ = pause_stats(phase);
            lines.push_back(text("phase", checkpoint.label, "collections", count, "pauses", phase.size(),
                                 "work", stats_.work, "freed", stats_.freed, "max_pause", stats_.maximum));
            previous = checkpoint.line;
        }
        lines.push_back(oom_line ? text("status out_of_memory line", oom_line, "size", oom_size)
                                 : "status completed");
        return lines;
    }
    std::string summary() const {
        const PauseStats stats = pause_stats(pauses);
        Integer live = 0, moved = 0, moved_objects = 0, max_moves = 0;
        for (const Collection &record : collections) {
            live += record.live.count;
            moved += record.moved.count;
        }
        for (const Object &object : heap.objects) {
            if (object.moves)
                ++moved_objects;
            max_moves = std::max(max_moves, Integer(object.moves));
        }
        std::ostringstream out;
        out << heap.collector.name << ',' << heap.collector.type << ','
            << (oom_line ? "out_of_memory" : "completed") << ',' << collections.size() << ',' << pauses.size()
            << ',' << live << ',' << moved << ',' << moved_objects << ',' << max_moves << ',' << stats.freed
            << ',' << stats.work << ',' << stats.p50 << ',' << stats.p90 << ',' << stats.maximum << ','
            << peak_used;
        if (oom_line)
            out << ",-,-,-,-";
        else {
            const auto free = free_amount(heap);
            out << ',' << used(heap) << ',' << free.first << ',' << free.second << ','
                << pct(free.first - free.second, free.first);
        }
        return out.str();
    }
};
static void write_lines(std::ostream &out, const std::vector<std::string> &lines) {
    for (const std::string &line : lines)
        out << line << '\n';
}
int main() {
    const Config config = read_config();
    const Reference reference(read_commands());
    std::ofstream mutator("output/mutator.txt");
    write_lines(mutator, reference.report());
    std::vector<Run> runs;
    runs.reserve(config.collectors.size());
    for (const Collector &collector : config.collectors) {
        runs.emplace_back(config, reference, collector);
        runs.back().execute();
    }
    std::ofstream maps("output/heap_maps.txt");
    bool first = true;
    for (const Checkpoint &checkpoint : reference.checkpoints)
        for (const Run &run : runs) {
            if (!first)
                maps << '\n';
            first = false;
            maps << text("checkpoint", checkpoint.label, "line", checkpoint.line, "collector",
                         run.heap.collector.name)
                 << '\n';
            const auto found = run.observations.find(checkpoint.label);
            if (found == run.observations.end())
                maps << "out_of_memory\n";
            else
                write_lines(maps, found->second);
        }
    std::ofstream collections("output/collections.txt"), summary("output/summary.csv"),
        leaks("output/leaks.txt");
    summary
        << "collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation\n";
    bool first_run = true, first_rc = true;
    for (const Run &run : runs) {
        if (!first_run)
            collections << '\n';
        first_run = false;
        write_lines(collections, run.collection_report());
        summary << run.summary() << '\n';
        if (run.heap.collector.type == "REFCOUNT") {
            if (!first_rc)
                leaks << '\n';
            first_rc = false;
            leaks << text("collector", run.heap.collector.name) << '\n';
            write_lines(leaks, run.leaks);
            if (run.oom_line)
                leaks << "status out_of_memory\n";
        }
    }
    if (first_rc)
        leaks << "none\n";
}
