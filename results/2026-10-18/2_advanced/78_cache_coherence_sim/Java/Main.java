import java.util.*;
public final class Main {
    static final List<String> REUSE_LABELS = List.of("1", "2-4", "5-16", "17-64", "65-256", "257+"),
                              LATENCY_LABELS =
                                  List.of("1", "2-9", "10-29", "30-99", "100-299", "300+");
    static final class Event {
        int number, line, cycle, core, address, block, word, distance;
        String op;
        Event(int number, int line, int cycle, int core, String op, int address, int lineSize) {
            this.number = number;
            this.line = line;
            this.cycle = cycle;
            this.core = core;
            this.op = op;
            this.address = address;
            block = address / lineSize;
            word = address % lineSize / 4;
        }
    }
    record Rejection(int line, String reason) {}
    record Validated(List<Event> events, List<Rejection> rejected) {}
    record Reuse(int core, int accesses, int lines, int[] distances, int cold, int[] capacities,
                 int[] lru, int opt) {}
    record Future(int block, int next) {}
    record Key(int first, int second) {}
    record Miss(String kind, String sharing) {}
    record BusResult(int completion, Bus.Transaction transaction) {}
    record Processed(Event event, int issue, int latency, String service, String missKind,
                     boolean hit) {}
    static Validated validateTrace(List<String> lines, ConfigIo.Config config) {
        List<Event> accepted = new ArrayList<>();
        List<Rejection> rejected = new ArrayList<>();
        int latest = 0;
        for (int i = 0; i < lines.size(); i++) {
            String[] f = lines.get(i).split(" ", -1);
            String reason = null;
            if (f.length != 3 && f.length != 4 || Arrays.asList(f).contains(""))
                reason = "fields";
            else if (!ConfigIo.decimalInteger(f[0], 7))
                reason = "cycle";
            else if (!ConfigIo.decimalInteger(f[1], 0) || Integer.parseInt(f[1]) >= config.cores)
                reason = "core";
            else if (!List.of("R", "W", "FENCE").contains(f[2]) ||
                     f[2].equals("FENCE") && f.length != 3 ||
                     !f[2].equals("FENCE") && f.length != 4)
                reason = "op";
            else if (!f[2].equals("FENCE") &&
                     (!ConfigIo.validHexAddress(f[3]) || Long.parseLong(f[3], 16) % 4 != 0 ||
                      Long.parseLong(f[3], 16) > 0x7fffffffL))
                reason = "address";
            else if (Integer.parseInt(f[0]) < latest)
                reason = "order";
            if (reason != null) {
                rejected.add(new Rejection(i + 1, reason));
                continue;
            }
            latest = Integer.parseInt(f[0]);
            accepted.add(new Event(accepted.size() + 1, i + 1, latest, Integer.parseInt(f[1]), f[2],
                                   f[2].equals("FENCE") ? 0 : Integer.parseInt(f[3], 16),
                                   config.line));
        }
        return new Validated(accepted, rejected);
    }
    static List<List<Event>> perCoreEvents(List<Event> events, int cores) {
        List<List<Event>> result = new ArrayList<>();
        for (int c = 0; c < cores; c++)
            result.add(new ArrayList<>());
        for (Event event : events)
            result.get(event.core).add(event);
        return result;
    }
    static final class Fenwick {
        int[] tree;
        Fenwick(int length) { tree = new int[length + 1]; }
        void add(int position, int value) {
            for (int i = position; i < tree.length; i += i & -i)
                tree[i] += value;
        }
        int sum(int position) {
            int result = 0;
            for (int i = position; i > 0; i -= i & -i)
                result += tree[i];
            return result;
        }
    }
    static List<Reuse> reuseAnalysis(List<Event> events, ConfigIo.Config config) {
        List<List<Event>> byCore = perCoreEvents(events, config.cores);
        List<Reuse> analyses = new ArrayList<>();
        int[] capacities = {config.cap / 4, config.cap / 2, config.cap, 2 * config.cap,
                            4 * config.cap};
        for (int core = 0; core < config.cores; core++) {
            List<Event> accesses = new ArrayList<>();
            for (Event event : byCore.get(core))
                if (!event.op.equals("FENCE"))
                    accesses.add(event);
            Map<Integer, Integer> last = new HashMap<>();
            Fenwick tree = new Fenwick(accesses.size());
            int cold = 0;
            int[] histogram = new int[6], lru = new int[5];
            for (int i = 0; i < accesses.size(); i++) {
                Event event = accesses.get(i);
                Integer previous = last.get(event.block);
                if (previous == null)
                    cold++;
                else {
                    event.distance = tree.sum(i) - tree.sum(previous) + 1;
                    tree.add(previous, -1);
                    int d = event.distance, bucket = d == 1     ? 0
                                                     : d <= 4   ? 1
                                                     : d <= 16  ? 2
                                                     : d <= 64  ? 3
                                                     : d <= 256 ? 4
                                                                : 5;
                    histogram[bucket]++;
                }
                for (int j = 0; j < capacities.length; j++)
                    if (previous == null || event.distance > capacities[j])
                        lru[j]++;
                tree.add(i + 1, 1);
                last.put(event.block, i + 1);
            }
            int[] next = new int[accesses.size()];
            Map<Integer, Integer> upcoming = new HashMap<>();
            for (int i = accesses.size() - 1; i >= 0; i--) {
                int block = accesses.get(i).block;
                next[i] = upcoming.getOrDefault(block, accesses.size() + 1);
                upcoming.put(block, i);
            }
            Map<Integer, Integer> resident = new HashMap<>();
            PriorityQueue<Future> priorities = new PriorityQueue<>(
                Comparator.comparingInt(Future::next).reversed().thenComparingInt(Future::block));
            int opt = 0;
            for (int i = 0; i < accesses.size(); i++) {
                int block = accesses.get(i).block;
                if (!resident.containsKey(block)) {
                    opt++;
                    if (resident.size() == config.cap) {
                        Future victim;
                        do {
                            victim = priorities.remove();
                        } while (!Objects.equals(resident.get(victim.block()), victim.next()));
                        resident.remove(victim.block());
                    }
                }
                resident.put(block, next[i]);
                priorities.add(new Future(block, next[i]));
            }
            analyses.add(new Reuse(core, accesses.size(), last.size(), histogram, cold, capacities,
                                   lru, opt));
        }
        return analyses;
    }
    static final class WordInfo {
        Set<Integer> reads = new TreeSet<>(), writes = new TreeSet<>();
    }
    static final class Sharing {
        Set<Integer> cores = new TreeSet<>(), writers = new TreeSet<>();
        int reads, writes;
        Map<Integer, WordInfo> words = new TreeMap<>();
        boolean shared, isTrue;
    }
    static Map<Integer, Sharing> staticSharing(List<Event> events) {
        Map<Integer, Sharing> lines = new TreeMap<>();
        for (Event event : events)
            if (!event.op.equals("FENCE")) {
                Sharing info = lines.computeIfAbsent(event.block, key -> new Sharing());
                info.cores.add(event.core);
                WordInfo word = info.words.computeIfAbsent(event.word, key -> new WordInfo());
                if (event.op.equals("W")) {
                    info.writers.add(event.core);
                    info.writes++;
                    word.writes.add(event.core);
                } else {
                    info.reads++;
                    word.reads.add(event.core);
                }
            }
        for (Sharing info : lines.values()) {
            info.shared = info.cores.size() >= 2 && !info.writers.isEmpty();
            for (WordInfo word : info.words.values()) {
                Set<Integer> combined = new HashSet<>(word.reads);
                combined.addAll(word.writes);
                if (!word.writes.isEmpty() && combined.size() >= 2)
                    info.isTrue = true;
            }
        }
        return lines;
    }
    static final class WordState {
        int writer;
        Set<Integer> readers = new HashSet<>();
        WordState(int writer) { this.writer = writer; }
    }
    static final class State {
        ConfigIo.Config config;
        ConfigIo.Scenario scenario;
        List<Cache> l1 = new ArrayList<>();
        Cache l2;
        Bus bus;
        List<Stats.Core> cores = new ArrayList<>();
        List<List<Event>> eventLists;
        int[] indices, ready, writeCompletion;
        List<Set<Integer>> seen = new ArrayList<>();
        Map<Key, Set<Integer>> invalidations = new HashMap<>();
        Stats.Counts l2Counters = new Stats.Counts();
        List<Processed> processed = new ArrayList<>();
        List<String> watchLines = new ArrayList<>();
        Map<Integer, Integer> handoffs = new HashMap<>(), lastWriter = new HashMap<>();
        Map<Key, WordState> wordState = new HashMap<>();
        int[][] communications;
        Map<Key, Integer> sharedMisses = new HashMap<>();
        Stats.Core total;
        int finish;
        State(ConfigIo.Config config, ConfigIo.Scenario scenario, List<Event> events) {
            this.config = config;
            this.scenario = scenario;
            for (int c = 0; c < config.cores; c++) {
                l1.add(new Cache(config.l1Sets, config.l1Ways, scenario.l1()));
                cores.add(new Stats.Core());
                seen.add(new HashSet<>());
            }
            l2 = new Cache(config.l2Sets, config.l2Ways, scenario.l2());
            bus = new Bus(config.tb);
            eventLists = perCoreEvents(events, config.cores);
            indices = new int[config.cores];
            ready = new int[config.cores];
            writeCompletion = new int[config.cores];
            communications = new int[config.cores][config.cores];
        }
        List<String> lineStates(int block) {
            List<String> states = new ArrayList<>();
            for (Cache cache : l1)
                states.add(cache.state(block));
            states.add(l2.state(block));
            return states;
        }
        Bus.Transaction issueTransaction(int core, String kind, int block, int requested) {
            Bus.Transaction tx = bus.assign(core, kind, block, requested);
            cores.get(core).bus.add(kind, 1);
            if (kind.equals("WB"))
                l2Counters.add("writebacks", 1);
            return tx;
        }
        void snoopOthers(Bus.Transaction tx, int word) {
            for (int core = 0; core < config.cores; core++) {
                if (core == tx.core)
                    continue;
                Cache cache = l1.get(core);
                String old = cache.state(tx.block);
                if (old.equals("I"))
                    continue;
                Protocol.Snoop change = Protocol.snoop(scenario.protocol(), old, tx.kind);
                tx.snoop.add("c" + core + ":" + old + ">" + change.state());
                tx.snoopHits++;
                if (change.state().equals("I")) {
                    cache.remove(tx.block);
                    tx.invalidations++;
                    cores.get(tx.core).snoop.add("invalidations_sent", 1);
                    cores.get(core).snoop.add("invalidations_received", 1);
                    invalidations.put(new Key(core, tx.block), new HashSet<>(List.of(word)));
                } else
                    cache.change(tx.block, change.state());
                if (change.supply()) {
                    tx.supplier = core;
                    cores.get(core).snoop.add("supplied", 1);
                }
                if (change.flush())
                    tx.flush = true;
            }
            if (tx.flush)
                l2Counters.add("flushes", 1);
        }
        void accessL2(Bus.Transaction tx) {
            l2Counters.add("lookups", 1);
            if (!l2.state(tx.block).equals("I")) {
                tx.l2 = "hit";
                l2Counters.add("hits", 1);
                l2.touch(tx.block);
            } else {
                tx.l2 = "miss";
                l2Counters.add("misses", 1);
                Cache.Line evicted = l2.fill(tx.block, "C");
                if (evicted != null) {
                    boolean dirty = evicted.state.equals("D");
                    List<String> copies = new ArrayList<>();
                    for (int core = 0; core < config.cores; core++) {
                        String old = l1.get(core).state(evicted.block);
                        if (old.equals("I"))
                            continue;
                        l1.get(core).remove(evicted.block);
                        copies.add("c" + core + ":" + old);
                        cores.get(core).snoop.add("back_invalidations", 1);
                        if (Protocol.DIRTY.contains(old))
                            dirty = true;
                    }
                    tx.eviction = new Bus.Eviction(evicted.block, copies, dirty);
                    l2Counters.add("evictions", 1);
                    if (dirty)
                        l2Counters.add("dirty_evictions", 1);
                }
            }
            if (tx.flush || tx.kind.equals("BusWr"))
                l2.change(tx.block, "D");
        }
        BusResult runTransaction(int core, String kind, int block, int word, int requested) {
            Bus.Transaction tx = issueTransaction(core, kind, block, requested);
            snoopOthers(tx, word);
            if (!kind.equals("BusUpgr"))
                accessL2(tx);
            int completion = tx.start + config.tb;
            if (kind.equals("BusUpgr"))
                return new BusResult(completion, tx);
            if (kind.equals("BusWr"))
                completion += config.t2 + (tx.l2.equals("miss") ? config.tm : 0);
            else if (tx.supplier != null)
                tx.source = "c" + tx.supplier;
            else if (tx.l2.equals("hit")) {
                completion += config.t2;
                tx.source = "L2";
            } else {
                completion += config.t2 + config.tm;
                tx.source = "mem";
            }
            return new BusResult(completion, tx);
        }
        void writeBack(int core, Cache.Line line) {
            issueTransaction(core, "WB", line.block, bus.free);
            l2.touch(line.block);
            l2.change(line.block, "D");
        }
        Miss classifyMiss(Event event) {
            Set<Integer> record = invalidations.get(new Key(event.core, event.block));
            if (!seen.get(event.core).contains(event.block))
                return new Miss("compulsory", null);
            if (record != null)
                return new Miss("coherence",
                                record.contains(event.word) ? "true_sharing" : "false_sharing");
            return new Miss(event.distance > config.cap ? "capacity" : "conflict", null);
        }
        void communicate(Event event) {
            Key key = new Key(event.block, event.word);
            WordState previous = wordState.get(key);
            if (event.op.equals("W")) {
                Integer former = lastWriter.get(event.block);
                if (former != null && former != event.core)
                    handoffs.merge(event.block, 1, Integer::sum);
                lastWriter.put(event.block, event.core);
                wordState.put(key, new WordState(event.core));
            } else if (previous != null && previous.writer != event.core &&
                       previous.readers.add(event.core))
                communications[previous.writer][event.core]++;
        }
        void renderWatch(Event event, int issue, Map<Integer, List<String>> before) {
            for (int block : config.watch) {
                List<String> after = lineStates(block);
                if (block != event.block && before.get(block).equals(after))
                    continue;
                List<String> columns = new ArrayList<>();
                for (int c = 0; c < config.cores; c++)
                    columns.add("c" + c + ":" + after.get(c));
                watchLines.add(event.number + " " + issue + " c" + event.core + " " + event.op +
                               " " + ConfigIo.hexAddress(event.address) + " line " +
                               ConfigIo.hexAddress(block * config.line) + " " +
                               String.join(" ", columns) + " L2:" + after.getLast());
            }
        }
        void handleAccess(Event event, int issue, boolean primary) {
            int core = event.core, block = event.block, word = event.word;
            Stats.Core counters = cores.get(core);
            Cache cache = l1.get(core);
            Map<Integer, List<String>> before = new HashMap<>();
            if (primary)
                for (int watched : config.watch)
                    before.put(watched, lineStates(watched));
            String old = cache.state(block);
            boolean hit = !old.equals("I");
            counters.simple.add("accesses", 1);
            counters.simple.add(event.op.equals("R") ? "reads" : "writes", 1);
            counters.simple.add(hit ? "hits" : "misses", 1);
            boolean otherCopy = false;
            for (int k = 0; k < config.cores; k++)
                if (k != core && !l1.get(k).state(block).equals("I"))
                    otherCopy = true;
            Protocol.Request transition =
                Protocol.requester(scenario.protocol(), old, event.op, otherCopy);
            String missKind = null;
            if (hit)
                cache.touch(block);
            else {
                Miss miss = classifyMiss(event);
                missKind = miss.kind();
                counters.misses.add(missKind, 1);
                if (miss.sharing() != null) {
                    counters.misses.add(miss.sharing(), 1);
                    sharedMisses.merge(
                        new Key(block, miss.sharing().equals("true_sharing") ? 1 : 0), 1,
                        Integer::sum);
                }
            }
            seen.get(core).add(block);
            if (event.op.equals("W"))
                for (Map.Entry<Key, Set<Integer>> entry : invalidations.entrySet())
                    if (entry.getKey().first() != core && entry.getKey().second() == block)
                        entry.getValue().add(word);
            if (primary)
                communicate(event);
            int completion;
            String service;
            if (transition.transaction() == null) {
                completion = issue + config.t1;
                service = "l1";
            } else {
                BusResult result =
                    runTransaction(core, transition.transaction(), block, word, issue + config.t1);
                completion = result.completion();
                Bus.Transaction tx = result.transaction();
                service = tx.kind.equals("BusUpgr") ? "upgrade"
                          : tx.kind.equals("BusWr") ? "through"
                          : tx.supplier != null     ? "cache"
                          : tx.l2.equals("hit")     ? "l2"
                                                    : "memory";
            }
            if (!old.equals("I"))
                cache.change(block, transition.state());
            else if (!transition.state().equals("I")) {
                Cache.Line evicted = cache.fill(block, transition.state());
                invalidations.remove(new Key(core, block));
                if (evicted != null && Protocol.DIRTY.contains(evicted.state))
                    writeBack(core, evicted);
            }
            int latency = completion - issue;
            counters.service.add(service, 1);
            counters.simple.add("latency", latency);
            if (event.op.equals("R")) {
                counters.simple.add("read_latency", latency);
                ready[core] = completion;
            } else {
                counters.simple.add("write_latency", latency);
                ready[core] = issue + config.t1;
                writeCompletion[core] = Math.max(writeCompletion[core], completion);
            }
            counters.finish = Math.max(counters.finish, completion);
            processed.add(new Processed(event, issue, latency, service, missKind, hit));
            if (primary)
                renderWatch(event, issue, before);
        }
        void handleFence(Event event, int issue) {
            Stats.Core counters = cores.get(event.core);
            int completion = Math.max(issue, writeCompletion[event.core]);
            counters.simple.add("fences", 1);
            counters.simple.add("fence_stall", completion - issue);
            counters.finish = Math.max(counters.finish, completion);
            ready[event.core] = completion;
        }
        void simulate(boolean primary) {
            while (true) {
                Event chosen = null;
                int issue = Integer.MAX_VALUE;
                for (int c = 0; c < config.cores; c++)
                    if (indices[c] < eventLists.get(c).size()) {
                        Event candidate = eventLists.get(c).get(indices[c]);
                        int time = Math.max(candidate.cycle, ready[c]);
                        if (time < issue) {
                            chosen = candidate;
                            issue = time;
                        }
                    }
                if (chosen == null)
                    break;
                indices[chosen.core]++;
                if (chosen.op.equals("FENCE"))
                    handleFence(chosen, issue);
                else
                    handleAccess(chosen, issue, primary);
            }
            total = Stats.total(cores);
            finish = total.finish;
        }
    }
    static List<String> formatTraceConfig(ConfigIo.Config c, List<String> trace, Validated valid) {
        List<String> lines = new ArrayList<>();
        lines.add("trace lines " + trace.size() + " accepted " + valid.events().size() +
                  " rejected " + valid.rejected().size());
        for (Rejection rejection : valid.rejected())
            lines.add("reject line " + rejection.line() + " " + rejection.reason());
        lines.add("geometry cores " + c.cores + " line " + c.line + " l1 " + c.l1Size + " " +
                  c.l1Ways + " sets " + c.l1Sets + " l2 " + c.l2Size + " " + c.l2Ways + " sets " +
                  c.l2Sets);
        lines.add("latency l1 " + c.t1 + " l2 " + c.t2 + " memory " + c.tm + " bus " + c.tb);
        return lines;
    }
    static List<String> formatReuse(List<Reuse> analyses, ConfigIo.Config c) {
        List<String> lines = new ArrayList<>();
        for (Reuse record : analyses) {
            lines.add("reuse c" + record.core() + " accesses " + record.accesses() + " lines " +
                      record.lines() + " distance " +
                      Stats.ranges(record.distances(), REUSE_LABELS) + " cold " + record.cold());
            List<String> misses = new ArrayList<>();
            for (int i = 0; i < record.capacities().length; i++)
                misses.add(record.capacities()[i] + ":" + record.lru()[i]);
            lines.add("mrc c" + record.core() + " lru " + String.join(" ", misses) + " opt " +
                      c.cap + ":" + record.opt());
        }
        return lines;
    }
    static String lengthHistogram(List<Processed> accesses) {
        int[] counts = new int[6];
        for (Processed access : accesses) {
            int l = access.latency();
            counts[l == 1 ? 0 : l <= 9 ? 1 : l <= 29 ? 2 : l <= 99 ? 3 : l <= 299 ? 4 : 5]++;
        }
        return Stats.ranges(counts, LATENCY_LABELS);
    }
    static List<String> scenarioReport(State state) {
        ConfigIo.Config c = state.config;
        ConfigIo.Scenario s = state.scenario;
        List<String> lines = new ArrayList<>();
        lines.add("scenario " + s.name() + " " + s.protocol() + " " + s.l1() + " " + s.l2());
        for (int core = 0; core < c.cores; core++)
            lines.addAll(Stats.sixLines("c" + core, state.cores.get(core)));
        lines.addAll(Stats.sixLines("total", state.total));
        Stats.Counts l2 = state.l2Counters;
        lines.add("l2 " + l2.named(List.of("lookups", "hits", "misses", "flushes", "writebacks",
                                           "evictions", "dirty_evictions")));
        int transactions = state.bus.transactions.size(), busy = c.tb * transactions;
        lines.add("bus transactions " + transactions + " busy " + busy + " wait " + state.bus.wait +
                  " utilization " + Stats.decimal(100 * busy, state.finish));
        Stats.Counts kinds = state.total.bus;
        int dataBytes = c.line * (kinds.get("BusRd") + kinds.get("BusRdX") + kinds.get("WB")) +
                        4 * kinds.get("BusWr"),
            memoryBytes = c.line * (l2.get("misses") + l2.get("dirty_evictions"));
        lines.add("traffic command_bytes " + (8 * transactions) + " data_bytes " + dataBytes +
                  " memory_bytes " + memoryBytes);
        int snoops = 0, hits = 0;
        int[] fanout = new int[c.cores];
        for (Bus.Transaction tx : state.bus.transactions)
            if (!tx.kind.equals("WB")) {
                snoops++;
                hits += tx.snoopHits;
                if (!tx.kind.equals("BusRd"))
                    fanout[tx.invalidations]++;
            }
        List<String> labels = new ArrayList<>();
        for (int i = 0; i < c.cores; i++)
            labels.add(Integer.toString(i));
        lines.add("snoops probes " + ((c.cores - 1) * snoops) + " hits " + hits + " fanout " +
                  Stats.ranges(fanout, labels));
        lines.add("latencies reads " + state.total.simple.get("read_latency") + " writes " +
                  state.total.simple.get("write_latency") + " histogram " +
                  lengthHistogram(state.processed));
        return lines;
    }
    static List<String> rankScenarios(List<State> states) {
        List<State> ordered = new ArrayList<>(states);
        ordered.sort(Comparator.comparingInt((State state) -> state.finish)
                         .thenComparingInt(state -> state.bus.transactions.size())
                         .thenComparingInt(state -> state.scenario.order()));
        List<String> lines = new ArrayList<>(List.of("ranking"));
        for (int i = 0; i < ordered.size(); i++) {
            State state = ordered.get(i);
            int length = state.total.simple.get("latency"), accesses =
                                                                state.total.simple.get("accesses");
            lines.add((i + 1) + " " + state.scenario.name() + " finish " + state.finish +
                      " transactions " + state.bus.transactions.size() + " amat " +
                      Stats.fraction(length, accesses) + " " + Stats.decimal(length, accesses));
        }
        return lines;
    }
    static final class Hot {
        Stats.Counts counts = new Stats.Counts();
        Set<Integer> cores = new TreeSet<>();
        int total;
    }
    static List<String> hotLines(State state) {
        Map<Integer, Hot> hot = new HashMap<>();
        for (Bus.Transaction tx : state.bus.transactions) {
            Hot info = hot.computeIfAbsent(tx.block, key -> new Hot());
            info.counts.add(tx.kind, 1);
            info.counts.add("invalidations", tx.invalidations);
            info.total++;
            info.cores.add(tx.core);
        }
        for (Processed item : state.processed)
            if (item.missKind() != null) {
                Hot info = hot.computeIfAbsent(item.event().block, key -> new Hot());
                info.counts.add("misses", 1);
                if (item.missKind().equals("coherence"))
                    info.counts.add("coherence", 1);
            }
        List<Integer> blocks = new ArrayList<>();
        for (Map.Entry<Integer, Hot> entry : hot.entrySet())
            if (entry.getValue().total > 0)
                blocks.add(entry.getKey());
        blocks.sort(Comparator.<Integer>comparingInt(block -> hot.get(block).total)
                        .reversed()
                        .thenComparingInt(block -> block));
        List<String> lines = new ArrayList<>(List.of("hot " + state.scenario.name()));
        for (int i = 0; i < Math.min(state.config.top, blocks.size()); i++) {
            int block = blocks.get(i);
            Hot info = hot.get(block);
            lines.add((i + 1) + " " + ConfigIo.hexAddress(block * state.config.line) +
                      " transactions " + info.total + " " + info.counts.named(Stats.TRANSACTIONS) +
                      " " + info.counts.named(List.of("misses", "coherence", "invalidations")) +
                      " cores " + Stats.coreString(info.cores));
        }
        return lines;
    }
    static String integers(int[] values) {
        List<String> pieces = new ArrayList<>();
        for (int value : values)
            pieces.add(Integer.toString(value));
        return String.join(" ", pieces);
    }
    static List<String> intervalRows(State state) {
        ConfigIo.Config c = state.config;
        int width = c.interval, count = state.finish / width + 1;
        int[][] accesses = new int[count][c.cores];
        int[] misses = new int[count], transactions = new int[count], busy = new int[count];
        for (Processed item : state.processed) {
            int bucket = item.issue() / width;
            accesses[bucket][item.event().core]++;
            if (item.missKind() != null)
                misses[bucket]++;
        }
        for (Bus.Transaction tx : state.bus.transactions) {
            int first = tx.start, last = first + c.tb;
            transactions[first / width]++;
            for (int k = first / width; k <= (last - 1) / width; k++)
                if (k < count)
                    busy[k] +=
                        Math.max(0, Math.min(last, (k + 1) * width) - Math.max(first, k * width));
        }
        List<String> lines =
            new ArrayList<>(List.of("intervals " + state.scenario.name() + " " + width));
        for (int k = 0; k < count; k++)
            lines.add(k + " " + (k * width) + "-" + ((k + 1) * width - 1) + " accesses " +
                      integers(accesses[k]) + " misses " + misses[k] + " transactions " +
                      transactions[k] + " busy " + busy[k] + " utilization " +
                      Stats.decimal(100 * busy[k], width));
        return lines;
    }
    static List<String> slowestRows(State state) {
        List<Processed> ordered = new ArrayList<>(state.processed);
        ordered.sort(Comparator.comparingInt(Processed::latency)
                         .reversed()
                         .thenComparingInt(item -> item.event().number));
        List<String> lines = new ArrayList<>(List.of("slowest " + state.scenario.name()));
        for (int i = 0; i < Math.min(state.config.top, ordered.size()); i++) {
            Processed item = ordered.get(i);
            Event event = item.event();
            lines.add((i + 1) + " event " + event.number + " cycle " + item.issue() + " c" +
                      event.core + " " + event.op + " " + ConfigIo.hexAddress(event.address) +
                      " latency " + item.latency() + " service " + item.service());
        }
        return lines;
    }
    static String regionFor(int address, ConfigIo.Config config) {
        for (ConfigIo.Region region : config.regions)
            if (region.start() <= address && address <= region.end())
                return region.name();
        return "other";
    }
    static List<String> regionRows(State state) {
        ConfigIo.Config c = state.config;
        Map<String, Stats.Counts> counters = new LinkedHashMap<>();
        for (ConfigIo.Region region : c.regions)
            counters.put(region.name(), new Stats.Counts());
        counters.put("other", new Stats.Counts());
        for (Processed item : state.processed) {
            Event event = item.event();
            Stats.Counts count = counters.get(regionFor(event.address, c));
            count.add("accesses", 1);
            count.add(event.op.equals("R") ? "reads" : "writes", 1);
            count.add("latency", item.latency());
            count.add(item.hit() ? "hits" : item.missKind(), 1);
        }
        for (Bus.Transaction tx : state.bus.transactions)
            counters.get(regionFor(tx.block * c.line, c)).add("transactions", 1);
        List<String> lines = new ArrayList<>(List.of("regions " + state.scenario.name()));
        for (Map.Entry<String, Stats.Counts> entry : counters.entrySet()) {
            Stats.Counts count = entry.getValue();
            String amat = count.get("accesses") == 0
                              ? "-"
                              : Stats.fraction(count.get("latency"), count.get("accesses")) + " " +
                                    Stats.decimal(count.get("latency"), count.get("accesses"));
            lines.add(entry.getKey() + " " +
                      count.named(List.of("accesses", "reads", "writes", "hits")) + " " +
                      count.named(Stats.MISSES) + " " +
                      count.named(List.of("transactions", "latency")) + " amat " + amat);
        }
        return lines;
    }
    static List<String> statsOutput(ConfigIo.Config c, List<String> trace, Validated valid,
                                    List<Reuse> reuse, List<State> states, State primary) {
        List<List<String>> sections = new ArrayList<>();
        sections.add(formatTraceConfig(c, trace, valid));
        sections.add(formatReuse(reuse, c));
        for (State state : states)
            sections.add(scenarioReport(state));
        sections.add(rankScenarios(states));
        sections.add(hotLines(primary));
        sections.add(intervalRows(primary));
        sections.add(slowestRows(primary));
        sections.add(regionRows(primary));
        List<String> lines = new ArrayList<>();
        for (List<String> section : sections) {
            if (!lines.isEmpty())
                lines.add("");
            lines.addAll(section);
        }
        return lines;
    }
    static List<String> sharingOutput(Map<Integer, Sharing> shared, State state) {
        List<String> lines = new ArrayList<>();
        int count = 0, trueLines = 0, falseLines = 0, totalTrue = 0, totalFalse = 0;
        for (Map.Entry<Integer, Sharing> entry : shared.entrySet()) {
            int block = entry.getKey();
            Sharing info = entry.getValue();
            if (!info.shared)
                continue;
            count++;
            if (info.isTrue)
                trueLines++;
            else
                falseLines++;
            int t = state.sharedMisses.getOrDefault(new Key(block, 1), 0),
                f = state.sharedMisses.getOrDefault(new Key(block, 0), 0);
            totalTrue += t;
            totalFalse += f;
            List<String> words = new ArrayList<>();
            for (Map.Entry<Integer, WordInfo> word : info.words.entrySet())
                words.add("w" + word.getKey() + "=" + Stats.coreString(word.getValue().reads) +
                          "/" + Stats.coreString(word.getValue().writes));
            lines.add(ConfigIo.hexAddress(block * state.config.line) + " " +
                      (info.isTrue ? "true" : "false") + " cores " + Stats.coreString(info.cores) +
                      " writers " + Stats.coreString(info.writers) + " reads " + info.reads +
                      " writes " + info.writes + " handoffs " +
                      state.handoffs.getOrDefault(block, 0) + " coherence " + (t + f) + " true " +
                      t + " false " + f + " words " + String.join(" ", words));
        }
        lines.add("lines " + count + " true_lines " + trueLines + " false_lines " + falseLines +
                  " coherence " + (totalTrue + totalFalse) + " true " + totalTrue + " false " +
                  totalFalse);
        lines.add("communication");
        for (int c = 0; c < state.config.cores; c++)
            lines.add("c" + c + " " + integers(state.communications[c]));
        return lines;
    }
    static String cacheWay(Cache.Line entry, int lineSize) {
        return entry == null ? "-"
                             : ConfigIo.hexAddress(entry.block * lineSize) + ":" + entry.state;
    }
    static void cacheRows(List<String> lines, Cache cache, String label, int lineSize) {
        for (int row = 0; row < cache.numberSets; row++) {
            List<String> ways = new ArrayList<>();
            for (Cache.Line entry : cache.entries[row])
                ways.add(cacheWay(entry, lineSize));
            lines.add(label + " " + row + " " + String.join(" ", ways) + " " +
                      cache.replacement.toLowerCase(Locale.ROOT) + " " + cache.order(row) +
                      " fills " + cache.fills[row] + " evictions " + cache.evictions[row]);
        }
    }
    static List<String> finalStateOutput(State state) {
        List<String> lines = new ArrayList<>();
        Set<Integer> inL1 = new HashSet<>();
        for (int core = 0; core < state.config.cores; core++) {
            Cache cache = state.l1.get(core);
            cacheRows(lines, cache, "c" + core, state.config.line);
            Stats.Counts counts = new Stats.Counts();
            for (Cache.Line entry : cache.lines()) {
                counts.add(entry.state, 1);
                inL1.add(entry.block);
            }
            lines.add("c" + core + " lines " + cache.lines().size() + " " +
                      counts.named(List.of("M", "O", "E", "S", "V")));
        }
        cacheRows(lines, state.l2, "L2", state.config.line);
        Stats.Counts counts = new Stats.Counts();
        for (Cache.Line entry : state.l2.lines())
            counts.add(entry.state, 1);
        lines.add("L2 lines " + state.l2.lines().size() + " dirty " + counts.get("D") + " clean " +
                  counts.get("C") + " in_l1 " + inL1.size());
        return lines;
    }
    public static void main(String[] args) throws Exception {
        ConfigIo.Config config = ConfigIo.readConfig();
        List<String> trace = ConfigIo.readTrace();
        Validated valid = validateTrace(trace, config);
        List<Reuse> reuse = reuseAnalysis(valid.events(), config);
        Map<Integer, Sharing> shared = staticSharing(valid.events());
        List<State> states = new ArrayList<>();
        State primary = null;
        for (ConfigIo.Scenario scenario : config.scenarios) {
            State state = new State(config, scenario, valid.events());
            state.simulate(scenario.name().equals(config.primary));
            states.add(state);
            if (scenario.name().equals(config.primary))
                primary = state;
        }
        ConfigIo.writeLines("stats.txt", statsOutput(config, trace, valid, reuse, states, primary));
        List<String> busLines = new ArrayList<>();
        for (Bus.Transaction tx : primary.bus.transactions)
            busLines.add(primary.bus.line(tx, config.line));
        ConfigIo.writeLines("bus_log.txt", busLines);
        ConfigIo.writeLines("watch.txt", primary.watchLines);
        ConfigIo.writeLines("sharing.txt", sharingOutput(shared, primary));
        ConfigIo.writeLines("final_state.txt", finalStateOutput(primary));
    }
}
