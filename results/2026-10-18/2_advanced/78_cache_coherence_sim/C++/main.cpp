#include "coherence.hpp"
struct Event {
    int number, core;
    Number cycle, address = 0, block = 0;
    char operation;
    int word = 0, distance = 0;
};
struct Rejection {
    int number;
    std::string reason;
};
static std::pair<std::vector<Event>, std::vector<Rejection>> validate_trace(const Lines &lines,
                                                                            const Config &c) {
    std::vector<Event> events;
    std::vector<Rejection> rejected;
    Number latest = 0;
    for (int i = 0; i < int(lines.size()); ++i) {
        Lines f = split(lines[i]);
        std::string reason;
        if ((f.size() != 3 && f.size() != 4) || std::find(f.begin(), f.end(), "") != f.end())
            reason = "fields";
        else if (!decimal_integer(f[0], 7))
            reason = "cycle";
        else if (!decimal_integer(f[1]) || std::stoll(f[1]) >= c.cores)
            reason = "core";
        else if ((f[2] != "R" && f[2] != "W" && f[2] != "FENCE") ||
                 (f[2] == "FENCE" ? f.size() != 3 : f.size() != 4))
            reason = "op";
        else if (f[2] != "FENCE" && (!valid_hex_address(f[3]) || hex_value(f[3]) % 4 != 0 ||
                                     hex_value(f[3]) > 0x7fffffff))
            reason = "address";
        else if (std::stoll(f[0]) < latest)
            reason = "order";
        if (!reason.empty()) {
            rejected.push_back({i + 1, reason});
            continue;
        }
        Event event;
        event.number = int(events.size()) + 1;
        event.core = std::stoi(f[1]);
        event.cycle = std::stoll(f[0]);
        event.operation = f[2] == "FENCE" ? 'F' : f[2][0];
        latest = event.cycle;
        if (event.operation != 'F') {
            event.address = hex_value(f[3]);
            event.block = event.address / c.line_size;
            event.word = int(event.address % c.line_size / 4);
        }
        events.push_back(event);
    }
    return {events, rejected};
}
static std::vector<std::vector<int>> per_core_events(const std::vector<Event> &events, int count) {
    std::vector<std::vector<int>> grouped(count);
    for (int i = 0; i < int(events.size()); ++i)
        grouped[events[i].core].push_back(i);
    return grouped;
}
class Fenwick {
    std::vector<int> tree;

  public:
    explicit Fenwick(int length) : tree(length + 1) {}
    void add(int position, int value) {
        for (int i = position; i < int(tree.size()); i += i & -i)
            tree[i] += value;
    }
    int sum(int position) const {
        int result = 0;
        for (int i = position; i > 0; i -= i & -i)
            result += tree[i];
        return result;
    }
};
struct Reuse {
    int core, accesses, lines = 0;
    Number cold = 0, opt = 0;
    std::array<Number, 6> distances{};
    std::array<Number, 5> capacities{}, lru{};
};
static std::vector<Reuse> reuse_analysis(std::vector<Event> &events, const Config &c) {
    auto grouped = per_core_events(events, c.cores);
    std::vector<Reuse> out;
    for (int core = 0; core < c.cores; ++core) {
        std::vector<int> accesses;
        for (int i : grouped[core])
            if (events[i].operation != 'F')
                accesses.push_back(i);
        Reuse row;
        row.core = core;
        row.accesses = int(accesses.size());
        row.capacities = {c.cap / 4, c.cap / 2, c.cap, 2 * Number(c.cap), 4 * Number(c.cap)};
        Fenwick tree(row.accesses);
        std::map<Number, int> last;
        for (int i = 0; i < row.accesses; ++i) {
            Event &event = events[accesses[i]];
            auto found = last.find(event.block);
            if (found == last.end())
                ++row.cold;
            else {
                event.distance = tree.sum(i + 1) - tree.sum(found->second) + 1;
                tree.add(found->second, -1);
                int d = event.distance;
                int bucket = d == 1 ? 0 : d <= 4 ? 1 : d <= 16 ? 2 : d <= 64 ? 3 : d <= 256 ? 4 : 5;
                ++row.distances[bucket];
            }
            for (int j = 0; j < 5; ++j)
                if (!event.distance || event.distance > row.capacities[j])
                    ++row.lru[j];
            last[event.block] = i + 1;
            tree.add(i + 1, 1);
        }
        row.lines = int(last.size());
        std::vector<int> next(row.accesses);
        last.clear();
        for (int i = row.accesses - 1; i >= 0; --i) {
            Number block = events[accesses[i]].block;
            auto found = last.find(block);
            next[i] = found == last.end() ? row.accesses + 1 : found->second;
            last[block] = i;
        }
        std::map<Number, int> resident;
        std::set<std::pair<int, Number>> priority;
        for (int i = 0; i < row.accesses; ++i) {
            Number block = events[accesses[i]].block;
            auto found = resident.find(block);
            if (found != resident.end())
                priority.erase({found->second, -block});
            else {
                ++row.opt;
                if (int(resident.size()) == c.cap) {
                    auto victim = std::prev(priority.end());
                    resident.erase(-victim->second);
                    priority.erase(victim);
                }
            }
            resident[block] = next[i];
            priority.insert({next[i], -block});
        }
        out.push_back(row);
    }
    return out;
}
static int bits(unsigned mask) {
    int count = 0;
    while (mask) {
        mask &= mask - 1;
        ++count;
    }
    return count;
}
struct WordSharing {
    unsigned reads = 0, writes = 0;
};
struct StaticLine {
    unsigned cores = 0, writers = 0;
    Number reads = 0, writes = 0;
    std::array<WordSharing, 32> words{};
    bool shared = false, true_line = false;
};
static std::map<Number, StaticLine> static_sharing(const std::vector<Event> &events) {
    std::map<Number, StaticLine> lines;
    for (const Event &event : events)
        if (event.operation != 'F') {
            StaticLine &info = lines[event.block];
            unsigned core = 1u << event.core;
            info.cores |= core;
            WordSharing &word = info.words[event.word];
            if (event.operation == 'W') {
                info.writers |= core;
                ++info.writes;
                word.writes |= core;
            } else {
                ++info.reads;
                word.reads |= core;
            }
        }
    for (auto &entry : lines) {
        StaticLine &info = entry.second;
        info.shared = bits(info.cores) >= 2 && info.writers;
        for (WordSharing word : info.words)
            if (word.writes && bits(word.reads | word.writes) >= 2)
                info.true_line = true;
    }
    return lines;
}
struct Processed {
    int number, core;
    Number issue, address, block, latency;
    char operation;
    int service, miss_kind;
    bool hit;
};
struct WordCommunication {
    int writer = -1;
    unsigned readers = 0;
};
struct DynamicLine {
    int writer = -1;
    Number handoffs = 0;
    std::array<Number, 2> sharing_misses{};
    std::array<WordCommunication, 32> words{};
};
struct L2Stats {
    Number lookups = 0, hits = 0, misses = 0, flushes = 0, writebacks = 0, evictions = 0,
           dirty_evictions = 0;
};
class Simulation {
    const Config &config;
    const std::vector<Event> &events;
    std::vector<std::vector<int>> grouped;
    std::array<std::size_t, 8> indices{};
    std::array<Number, 8> ready{}, write_completion{};
    std::array<std::map<Number, std::uint32_t>, 8> invalidations;
    bool primary;
    std::array<char, 9> line_states(Number block) const {
        std::array<char, 9> states{};
        for (int core = 0; core < config.cores; ++core)
            states[core] = l1[core].state(block);
        states[config.cores] = l2.state(block);
        return states;
    }
    Transaction &issue_transaction(int core, TransactionKind kind, Number block, Number requested) {
        Transaction &tx = bus.assign(core, kind, block, requested);
        ++cores[core].bus[int(kind)];
        if (kind == TransactionKind::WB)
            ++l2_stats.writebacks;
        return tx;
    }
    void snoop_others(Transaction &tx, int word) {
        for (int core = 0; core < config.cores; ++core)
            if (core != tx.core) {
                Cache &cache = l1[core];
                char old = cache.state(tx.block);
                if (old == 'I')
                    continue;
                SnoopTransition transition = snoop(scenario.protocol, old, tx.kind);
                line(tx.snoops, "c", core, ":", old, ">", transition.state);
                ++tx.snoop_hits;
                if (transition.state == 'I') {
                    cache.remove(tx.block);
                    ++tx.invalidations;
                    ++cores[tx.core].snoop[0];
                    ++cores[core].snoop[1];
                    invalidations[core][tx.block] = std::uint32_t(1) << word;
                } else
                    cache.change(tx.block, transition.state);
                if (transition.supply) {
                    tx.supplier = core;
                    ++cores[core].snoop[2];
                }
                tx.flushed |= transition.flush;
            }
        if (tx.flushed)
            ++l2_stats.flushes;
    }
    void access_l2(Transaction &tx) {
        ++l2_stats.lookups;
        if (l2.state(tx.block) != 'I') {
            tx.l2_hit = true;
            ++l2_stats.hits;
            l2.touch(tx.block);
        } else {
            ++l2_stats.misses;
            std::optional<Entry> victim = l2.fill(tx.block, 'C');
            if (victim) {
                tx.evicted = victim->block;
                tx.dirty_eviction = victim->state == 'D';
                ++l2_stats.evictions;
                for (int core = 0; core < config.cores; ++core) {
                    char old = l1[core].state(victim->block);
                    if (old == 'I')
                        continue;
                    l1[core].remove(victim->block);
                    line(tx.copies, "c", core, ":", old);
                    ++cores[core].snoop[3];
                    tx.dirty_eviction |= dirty(old);
                }
                if (tx.dirty_eviction)
                    ++l2_stats.dirty_evictions;
            }
        }
        if (tx.flushed || tx.kind == TransactionKind::BusWr)
            l2.change(tx.block, 'D');
    }
    std::pair<Number, int> run_transaction(int core, TransactionKind kind, Number block, int word,
                                           Number requested) {
        Transaction &tx = issue_transaction(core, kind, block, requested);
        snoop_others(tx, word);
        if (kind != TransactionKind::BusUpgr)
            access_l2(tx);
        Number completion = tx.start + config.tb;
        int service;
        if (kind == TransactionKind::BusUpgr)
            service = 1;
        else if (kind == TransactionKind::BusWr) {
            service = 2;
            completion += config.t2 + (tx.l2_hit ? 0 : config.tm);
        } else if (tx.supplier) {
            service = 3;
            tx.source = text("c", *tx.supplier);
        } else if (tx.l2_hit) {
            service = 4;
            completion += config.t2;
            tx.source = "L2";
        } else {
            service = 5;
            completion += config.t2 + config.tm;
            tx.source = "mem";
        }
        return {completion, service};
    }
    void communicate(const Event &event) {
        DynamicLine &info = dynamic[event.block];
        WordCommunication &word = info.words[event.word];
        unsigned core = 1u << event.core;
        if (event.operation == 'W') {
            if (info.writer >= 0 && info.writer != event.core)
                ++info.handoffs;
            info.writer = event.core;
            word.writer = event.core;
            word.readers = 0;
        } else if (word.writer >= 0 && word.writer != event.core && !(word.readers & core)) {
            ++communications[word.writer][event.core];
            word.readers |= core;
        }
    }
    void access(const Event &event, Number issue) {
        int core = event.core;
        Cache &cache = l1[core];
        CoreStats &count = cores[core];
        std::vector<std::array<char, 9>> before;
        if (primary)
            for (Number block : config.watch)
                before.push_back(line_states(block));
        char old = cache.state(event.block);
        bool hit = old != 'I';
        ++count.accesses;
        if (event.operation == 'R')
            ++count.reads;
        else
            ++count.writes;
        if (hit)
            ++count.hits;
        else
            ++count.misses;
        bool other = false;
        for (int k = 0; k < config.cores; ++k)
            if (k != core && l1[k].state(event.block) != 'I')
                other = true;
        RequestTransition transition = requester(scenario.protocol, old, event.operation, other);
        int miss_kind = -1;
        if (hit)
            cache.touch(event.block);
        else {
            auto record = invalidations[core].find(event.block);
            if (!event.distance)
                miss_kind = 0;
            else if (record != invalidations[core].end()) {
                miss_kind = 3;
                int sharing = record->second & (std::uint32_t(1) << event.word) ? 0 : 1;
                ++count.miss_counts[4 + sharing];
                if (primary)
                    ++dynamic[event.block].sharing_misses[sharing];
            } else
                miss_kind = event.distance > config.cap ? 1 : 2;
            ++count.miss_counts[miss_kind];
        }
        if (event.operation == 'W')
            for (int k = 0; k < config.cores; ++k)
                if (k != core) {
                    auto record = invalidations[k].find(event.block);
                    if (record != invalidations[k].end())
                        record->second |= std::uint32_t(1) << event.word;
                }
        if (primary)
            communicate(event);
        Number completion = issue + config.t1;
        int service = 0;
        if (transition.transaction != TransactionKind::None) {
            auto result = run_transaction(core, transition.transaction, event.block, event.word,
                                          issue + config.t1);
            completion = result.first;
            service = result.second;
        }
        if (old != 'I')
            cache.change(event.block, transition.state);
        else if (transition.state != 'I') {
            std::optional<Entry> victim = cache.fill(event.block, transition.state);
            invalidations[core].erase(event.block);
            if (victim && dirty(victim->state)) {
                issue_transaction(core, TransactionKind::WB, victim->block, bus.free);
                l2.touch(victim->block);
                l2.change(victim->block, 'D');
            }
        }
        Number latency = completion - issue;
        ++count.service[service];
        count.latency += latency;
        if (event.operation == 'R') {
            count.read_latency += latency;
            ready[core] = completion;
        } else {
            count.write_latency += latency;
            ready[core] = issue + config.t1;
            write_completion[core] = std::max(write_completion[core], completion);
        }
        count.finish = std::max(count.finish, completion);
        processed.push_back({event.number, core, issue, event.address, event.block, latency,
                             event.operation, service, miss_kind, hit});
        if (primary)
            for (std::size_t i = 0; i < config.watch.size(); ++i) {
                Number block = config.watch[i];
                auto after = line_states(block);
                if (block != event.block && after == before[i])
                    continue;
                Lines columns;
                for (int k = 0; k < config.cores; ++k)
                    columns.push_back(text("c", k, ":", after[k]));
                line(watch, event.number, " ", issue, " c", core, " ", event.operation, " ",
                     hex_address(event.address), " line ", hex_address(block * config.line_size),
                     " ", join(columns), " L2:", after[config.cores]);
            }
    }

  public:
    Scenario scenario;
    std::vector<Cache> l1;
    Cache l2;
    Bus bus;
    std::vector<CoreStats> cores;
    CoreStats total;
    L2Stats l2_stats;
    std::vector<Processed> processed;
    Lines watch;
    std::map<Number, DynamicLine> dynamic;
    std::array<std::array<Number, 8>, 8> communications{};
    Simulation(const Config &config, const Scenario &scenario, const std::vector<Event> &events)
        : config(config), events(events), grouped(per_core_events(events, config.cores)),
          primary(scenario.name == config.primary), scenario(scenario),
          l2(config.l2_sets, config.l2_ways, scenario.l2), bus(config.tb), cores(config.cores) {
        for (int core = 0; core < config.cores; ++core)
            l1.emplace_back(config.l1_sets, config.l1_ways, scenario.l1);
    }
    void run() {
        for (;;) {
            int chosen = -1;
            Number issue = 0;
            for (int core = 0; core < config.cores; ++core)
                if (indices[core] < grouped[core].size()) {
                    const Event &event = events[grouped[core][indices[core]]];
                    Number candidate = std::max(event.cycle, ready[core]);
                    if (chosen < 0 || candidate < issue) {
                        chosen = core;
                        issue = candidate;
                    }
                }
            if (chosen < 0)
                break;
            const Event &event = events[grouped[chosen][indices[chosen]++]];
            if (event.operation == 'F') {
                Number completion = std::max(issue, write_completion[chosen]);
                CoreStats &count = cores[chosen];
                ++count.fences;
                count.fence_stall += completion - issue;
                count.finish = std::max(count.finish, completion);
                ready[chosen] = completion;
            } else
                access(event, issue);
        }
        total = total_counters(cores);
    }
    const Config &configuration() const { return config; }
};
static Lines trace_config(const Config &c, const Lines &trace, const std::vector<Event> &events,
                          const std::vector<Rejection> &rejected) {
    Lines out;
    line(out, "trace lines ", trace.size(), " accepted ", events.size(), " rejected ",
         rejected.size());
    for (const Rejection &r : rejected)
        line(out, "reject line ", r.number, " ", r.reason);
    line(out, "geometry cores ", c.cores, " line ", c.line_size, " l1 ", c.l1_size, " ", c.l1_ways,
         " sets ", c.l1_sets, " l2 ", c.l2_size, " ", c.l2_ways, " sets ", c.l2_sets);
    line(out, "latency l1 ", c.t1, " l2 ", c.t2, " memory ", c.tm, " bus ", c.tb);
    return out;
}
static Lines reuse_lines(const std::vector<Reuse> &reuse, const Config &c) {
    Lines out;
    const Lines buckets{"1", "2-4", "5-16", "17-64", "65-256", "257+"};
    for (const Reuse &row : reuse) {
        line(out, "reuse c", row.core, " accesses ", row.accesses, " lines ", row.lines,
             " distance ",
             range_counts(buckets, std::vector<Number>(row.distances.begin(), row.distances.end())),
             " cold ", row.cold);
        Lines mrc;
        for (int i = 0; i < 5; ++i)
            mrc.push_back(text(row.capacities[i], ":", row.lru[i]));
        line(out, "mrc c", row.core, " lru ", join(mrc), " opt ", c.cap, ":", row.opt);
    }
    return out;
}
static Lines scenario_report(const Simulation &state) {
    const Config &c = state.configuration();
    const CoreStats &total = state.total;
    const L2Stats &l2 = state.l2_stats;
    Lines out;
    line(out, "scenario ", state.scenario.name, " ", state.scenario.protocol, " ",
         state.scenario.l1, " ", state.scenario.l2);
    for (int core = 0; core < c.cores; ++core)
        extend(out, six_lines(text("c", core), state.cores[core]));
    extend(out, six_lines("total", total));
    line(out, "l2 lookups ", l2.lookups, " hits ", l2.hits, " misses ", l2.misses, " flushes ",
         l2.flushes, " writebacks ", l2.writebacks, " evictions ", l2.evictions,
         " dirty_evictions ", l2.dirty_evictions);
    Number transactions = Number(state.bus.transactions.size()), busy = c.tb * transactions;
    line(out, "bus transactions ", transactions, " busy ", busy, " wait ", state.bus.wait,
         " utilization ", decimal(100 * busy, total.finish));
    line(out, "traffic command_bytes ", 8 * transactions, " data_bytes ",
         c.line_size * (total.bus[0] + total.bus[1] + total.bus[4]) + 4 * total.bus[3],
         " memory_bytes ", c.line_size * (l2.misses + l2.dirty_evictions));
    Number probes = 0, hits = 0;
    std::vector<Number> fanout(c.cores);
    Lines names;
    for (const Transaction &tx : state.bus.transactions)
        if (tx.kind != TransactionKind::WB) {
            probes += c.cores - 1;
            hits += tx.snoop_hits;
            if (tx.kind != TransactionKind::BusRd)
                ++fanout[tx.invalidations];
        }
    for (int i = 0; i < c.cores; ++i)
        names.push_back(std::to_string(i));
    line(out, "snoops probes ", probes, " hits ", hits, " fanout ", range_counts(names, fanout));
    std::vector<Number> histogram(6);
    for (const Processed &p : state.processed) {
        Number t = p.latency;
        ++histogram[t == 1 ? 0 : t <= 9 ? 1 : t <= 29 ? 2 : t <= 99 ? 3 : t <= 299 ? 4 : 5];
    }
    line(out, "latencies reads ", total.read_latency, " writes ", total.write_latency,
         " histogram ", range_counts({"1", "2-9", "10-29", "30-99", "100-299", "300+"}, histogram));
    return out;
}
static Lines ranking(const std::vector<std::unique_ptr<Simulation>> &states) {
    std::vector<const Simulation *> order;
    for (const auto &state : states)
        order.push_back(state.get());
    std::sort(order.begin(), order.end(), [](const Simulation *a, const Simulation *b) {
        return std::make_tuple(a->total.finish, a->bus.transactions.size(), a->scenario.order) <
               std::make_tuple(b->total.finish, b->bus.transactions.size(), b->scenario.order);
    });
    Lines out{"ranking"};
    for (int i = 0; i < int(order.size()); ++i) {
        const Simulation &state = *order[i];
        line(out, i + 1, " ", state.scenario.name, " finish ", state.total.finish, " transactions ",
             state.bus.transactions.size(), " amat ",
             fraction(state.total.latency, state.total.accesses), " ",
             decimal(state.total.latency, state.total.accesses));
    }
    return out;
}
static Lines hot_lines(const Simulation &state) {
    struct Hot {
        std::array<Number, 5> types{};
        Number transactions = 0, misses = 0, coherence = 0, invalidations = 0;
        unsigned cores = 0;
    };
    std::map<Number, Hot> records;
    for (const Transaction &tx : state.bus.transactions) {
        Hot &h = records[tx.block];
        ++h.types[int(tx.kind)];
        ++h.transactions;
        h.invalidations += tx.invalidations;
        h.cores |= 1u << tx.core;
    }
    for (const Processed &p : state.processed)
        if (p.miss_kind >= 0) {
            ++records[p.block].misses;
            if (p.miss_kind == 3)
                ++records[p.block].coherence;
        }
    std::vector<Number> blocks;
    for (const auto &record : records)
        if (record.second.transactions)
            blocks.push_back(record.first);
    std::sort(blocks.begin(), blocks.end(), [&](Number a, Number b) {
        return records[a].transactions != records[b].transactions
                   ? records[a].transactions > records[b].transactions
                   : a < b;
    });
    Lines out{text("hot ", state.scenario.name)};
    for (int i = 0; i < std::min(state.configuration().top, int(blocks.size())); ++i) {
        Number block = blocks[i];
        const Hot &h = records[block];
        Lines values;
        for (int j = 0; j < 5; ++j)
            values.push_back(text(transaction_names[j], " ", h.types[j]));
        line(out, i + 1, " ", hex_address(block * state.configuration().line_size),
             " transactions ", h.transactions, " ", join(values), " misses ", h.misses,
             " coherence ", h.coherence, " invalidations ", h.invalidations, " cores ",
             core_string(h.cores));
    }
    return out;
}
static Lines interval_rows(const Simulation &state) {
    const Config &c = state.configuration();
    Number width = c.interval, count = state.total.finish / width + 1;
    struct Interval {
        std::array<Number, 8> accesses{};
        Number misses = 0, transactions = 0, busy = 0;
    };
    std::vector<Interval> rows(count);
    for (const Processed &p : state.processed) {
        Interval &row = rows[p.issue / width];
        ++row.accesses[p.core];
        row.misses += !p.hit;
    }
    for (const Transaction &tx : state.bus.transactions) {
        Number first = tx.start, last = first + c.tb;
        ++rows[first / width].transactions;
        for (Number bucket = first / width; bucket <= (last - 1) / width && bucket < count;
             ++bucket)
            rows[bucket].busy += std::max(Number(0), std::min(last, (bucket + 1) * width) -
                                                         std::max(first, bucket * width));
    }
    Lines out{text("intervals ", state.scenario.name, " ", width)};
    for (Number i = 0; i < count; ++i) {
        Lines accesses;
        for (int core = 0; core < c.cores; ++core)
            accesses.push_back(std::to_string(rows[i].accesses[core]));
        line(out, i, " ", i * width, "-", (i + 1) * width - 1, " accesses ", join(accesses),
             " misses ", rows[i].misses, " transactions ", rows[i].transactions, " busy ",
             rows[i].busy, " utilization ", decimal(100 * rows[i].busy, width));
    }
    return out;
}
static Lines slowest_rows(const Simulation &state) {
    std::vector<const Processed *> order;
    for (const Processed &p : state.processed)
        order.push_back(&p);
    std::sort(order.begin(), order.end(), [](const Processed *a, const Processed *b) {
        return a->latency != b->latency ? a->latency > b->latency : a->number < b->number;
    });
    Lines out{text("slowest ", state.scenario.name)};
    for (int i = 0; i < std::min(state.configuration().top, int(order.size())); ++i) {
        const Processed &p = *order[i];
        line(out, i + 1, " event ", p.number, " cycle ", p.issue, " c", p.core, " ", p.operation,
             " ", hex_address(p.address), " latency ", p.latency, " service ",
             service_names[p.service]);
    }
    return out;
}
static int region_for(Number address, const Config &c) {
    for (int i = 0; i < int(c.regions.size()); ++i)
        if (c.regions[i].first <= address && address <= c.regions[i].last)
            return i;
    return int(c.regions.size());
}
static Lines region_rows(const Simulation &state) {
    const Config &c = state.configuration();
    struct RegionStats {
        Number accesses = 0, reads = 0, writes = 0, hits = 0, latency = 0, transactions = 0;
        std::array<Number, 4> misses{};
    };
    std::vector<RegionStats> rows(c.regions.size() + 1);
    for (const Processed &p : state.processed) {
        RegionStats &s = rows[region_for(p.address, c)];
        ++s.accesses;
        if (p.operation == 'R')
            ++s.reads;
        else
            ++s.writes;
        s.latency += p.latency;
        if (p.hit)
            ++s.hits;
        else
            ++s.misses[p.miss_kind];
    }
    for (const Transaction &tx : state.bus.transactions)
        ++rows[region_for(tx.block * c.line_size, c)].transactions;
    Lines out{text("regions ", state.scenario.name)};
    for (int i = 0; i < int(rows.size()); ++i) {
        const RegionStats &s = rows[i];
        Lines misses;
        for (int j = 0; j < 4; ++j)
            misses.push_back(text(miss_names[j], " ", s.misses[j]));
        line(out, i < int(c.regions.size()) ? c.regions[i].name : "other", " accesses ", s.accesses,
             " reads ", s.reads, " writes ", s.writes, " hits ", s.hits, " ", join(misses),
             " transactions ", s.transactions, " latency ", s.latency, " amat ",
             s.accesses ? fraction(s.latency, s.accesses) + " " + decimal(s.latency, s.accesses)
                        : "-");
    }
    return out;
}
static Lines sharing_output(const std::map<Number, StaticLine> &sharing, const Simulation &state) {
    Lines out;
    Number count = 0, true_lines = 0, true_misses = 0, false_misses = 0;
    for (const auto &entry : sharing) {
        Number block = entry.first;
        const StaticLine &info = entry.second;
        if (!info.shared)
            continue;
        ++count;
        true_lines += info.true_line;
        DynamicLine empty;
        auto found = state.dynamic.find(block);
        const DynamicLine &dynamic = found == state.dynamic.end() ? empty : found->second;
        Number t = dynamic.sharing_misses[0], f = dynamic.sharing_misses[1];
        true_misses += t;
        false_misses += f;
        Lines words;
        for (int i = 0; i < 32; ++i) {
            WordSharing word = info.words[i];
            if (word.reads || word.writes)
                words.push_back(
                    text("w", i, "=", core_string(word.reads), "/", core_string(word.writes)));
        }
        line(out, hex_address(block * state.configuration().line_size), " ",
             info.true_line ? "true" : "false", " cores ", core_string(info.cores), " writers ",
             core_string(info.writers), " reads ", info.reads, " writes ", info.writes,
             " handoffs ", dynamic.handoffs, " coherence ", t + f, " true ", t, " false ", f,
             " words ", join(words));
    }
    line(out, "lines ", count, " true_lines ", true_lines, " false_lines ", count - true_lines,
         " coherence ", true_misses + false_misses, " true ", true_misses, " false ", false_misses);
    out.push_back("communication");
    for (int core = 0; core < state.configuration().cores; ++core) {
        Lines values;
        for (int k = 0; k < state.configuration().cores; ++k)
            values.push_back(std::to_string(state.communications[core][k]));
        line(out, "c", core, " ", join(values));
    }
    return out;
}
static std::string cache_way(const std::optional<Entry> &entry, int line_size) {
    return entry ? text(hex_address(entry->block * line_size), ":", entry->state) : "-";
}
static Lines cache_rows(const Cache &cache, const std::string &label, int line_size) {
    Lines out;
    std::string policy = cache.replacement;
    for (char &c : policy)
        c = char(c - 'A' + 'a');
    for (int row = 0; row < int(cache.sets.size()); ++row) {
        Lines ways;
        const CacheSet &set = cache.sets[row];
        for (const auto &entry : set.entries)
            ways.push_back(cache_way(entry, line_size));
        line(out, label, " ", row, " ", join(ways), " ", policy, " ", cache.order(row), " fills ",
             set.fills, " evictions ", set.evictions);
    }
    return out;
}
static Lines final_state_output(const Simulation &state) {
    Lines out;
    std::set<Number> in_l1;
    const Config &c = state.configuration();
    for (int core = 0; core < c.cores; ++core) {
        const Cache &cache = state.l1[core];
        extend(out, cache_rows(cache, text("c", core), c.line_size));
        std::map<char, int> counts;
        int total = 0;
        for (const CacheSet &set : cache.sets)
            for (const auto &entry : set.entries)
                if (entry) {
                    ++total;
                    ++counts[entry->state];
                    in_l1.insert(entry->block);
                }
        line(out, "c", core, " lines ", total, " M ", counts['M'], " O ", counts['O'], " E ",
             counts['E'], " S ", counts['S'], " V ", counts['V']);
    }
    extend(out, cache_rows(state.l2, "L2", c.line_size));
    int dirty_count = 0, clean_count = 0;
    for (const CacheSet &set : state.l2.sets)
        for (const auto &entry : set.entries)
            if (entry) {
                dirty_count += entry->state == 'D';
                clean_count += entry->state == 'C';
            }
    line(out, "L2 lines ", dirty_count + clean_count, " dirty ", dirty_count, " clean ",
         clean_count, " in_l1 ", in_l1.size());
    return out;
}
int main() {
    Config config = read_config();
    Lines trace = read_lines("input/trace.txt");
    auto validated = validate_trace(trace, config);
    std::vector<Event> &events = validated.first;
    std::vector<Reuse> reuse = reuse_analysis(events, config);
    auto sharing = static_sharing(events);
    std::vector<std::unique_ptr<Simulation>> states;
    Simulation *primary = nullptr;
    for (const Scenario &scenario : config.scenarios) {
        auto state = std::make_unique<Simulation>(config, scenario, events);
        state->run();
        if (scenario.name == config.primary)
            primary = state.get();
        states.push_back(std::move(state));
    }
    std::vector<Lines> sections{trace_config(config, trace, events, validated.second),
                                reuse_lines(reuse, config)};
    for (const auto &state : states)
        sections.push_back(scenario_report(*state));
    sections.push_back(ranking(states));
    sections.push_back(hot_lines(*primary));
    sections.push_back(interval_rows(*primary));
    sections.push_back(slowest_rows(*primary));
    sections.push_back(region_rows(*primary));
    Lines statistics;
    for (const Lines &section : sections) {
        if (!statistics.empty())
            statistics.push_back("");
        extend(statistics, section);
    }
    write_lines("stats.txt", statistics);
    Lines transactions;
    for (const Transaction &tx : primary->bus.transactions)
        transactions.push_back(primary->bus.log_line(tx, config.line_size));
    write_lines("bus_log.txt", transactions);
    write_lines("watch.txt", primary->watch);
    write_lines("sharing.txt", sharing_output(sharing, *primary));
    write_lines("final_state.txt", final_state_output(*primary));
}
