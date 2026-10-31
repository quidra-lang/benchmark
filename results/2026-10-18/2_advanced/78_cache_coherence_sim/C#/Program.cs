using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
public static class Program {
    public static readonly List<string> REUSE_LABELS =
                                            new List<string> { "1",     "2-4",    "5-16",
                                                               "17-64", "65-256", "257+" },
                                        LATENCY_LABELS =
                                            new List<string> { "1",     "2-9",     "10-29",
                                                               "30-99", "100-299", "300+" };
    public sealed class Event {
        public int number, line, cycle, core, address, block, word, distance;
        public string op;
        public Event(int number, int line, int cycle, int core, string op, int address,
                     int lineSize) {
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
    public record Rejection(int line, string reason) {}
    public record Validated(List<Event> events, List<Rejection> rejected) {}
    public record Reuse(int core, int accesses, int lines, int[] distances, int cold,
                        int[] capacities, int[] lru, int opt) {}
    public record Future(int block, int next) {}
    public record Key(int first, int second) {}
    public record Miss(string kind, string sharing) {}
    public record BusResult(int completion, Bus.Transaction transaction) {}
    public record Processed(Event eventRecord, int issue, int latency, string service,
                            string missKind, bool hit) {}
    public static Validated ValidateTrace(List<string> lines, ConfigIo.Config config) {
        List<Event> accepted = new();
        List<Rejection> rejected = new();
        int latest = 0;
        for (int i = 0; i < lines.Count; i++) {
            string[] f = lines[i].Split(' ', StringSplitOptions.None);
            string reason = null;
            if (f.Length != 3 && f.Length != 4 || f.Contains(""))
                reason = "fields";
            else if (!ConfigIo.DecimalInteger(f[0], 7))
                reason = "cycle";
            else if (!ConfigIo.DecimalInteger(f[1], 0) || int.Parse(f[1]) >= config.cores)
                reason = "core";
            else if (!new List<string> { "R", "W", "FENCE" }.Contains(f[2]) ||
                     f[2].Equals("FENCE") && f.Length != 3 ||
                     !f[2].Equals("FENCE") && f.Length != 4)
                reason = "op";
            else if (!f[2].Equals("FENCE") &&
                     (!ConfigIo.ValidHexAddress(f[3]) ||
                      long.Parse(f[3], NumberStyles.HexNumber, CultureInfo.InvariantCulture) % 4 !=
                          0 ||
                      long.Parse(f[3], NumberStyles.HexNumber, CultureInfo.InvariantCulture) >
                          0x7fffffffL))
                reason = "address";
            else if (int.Parse(f[0]) < latest)
                reason = "order";
            if (reason != null) {
                rejected.Add(new Rejection(i + 1, reason));
                continue;
            }
            latest = int.Parse(f[0]);
            accepted.Add(new Event(accepted.Count + 1, i + 1, latest, int.Parse(f[1]), f[2],
                                   f[2].Equals("FENCE") ? 0
                                                        : int.Parse(f[3], NumberStyles.HexNumber,
                                                                    CultureInfo.InvariantCulture),
                                   config.line));
        }
        return new Validated(accepted, rejected);
    }
    public static List<List<Event>> PerCoreEvents(List<Event> events, int cores) {
        List<List<Event>> result = new();
        for (int c = 0; c < cores; c++)
            result.Add(new());
        foreach (Event eventRecord in events)
            result[eventRecord.core].Add(eventRecord);
        return result;
    }
    public sealed class Fenwick {
        public int[] tree;
        public Fenwick(int length) { tree = new int[length + 1]; }
        public void Add(int position, int value) {
            for (int i = position; i < tree.Length; i += i & -i)
                tree[i] += value;
        }
        public int Sum(int position) {
            int result = 0;
            for (int i = position; i > 0; i -= i & -i)
                result += tree[i];
            return result;
        }
    }
    public static List<Reuse> ReuseAnalysis(List<Event> events, ConfigIo.Config config) {
        List<List<Event>> byCore = PerCoreEvents(events, config.cores);
        List<Reuse> analyses = new();
        int[] capacities = { config.cap / 4, config.cap / 2, config.cap, 2 * config.cap,
                             4 * config.cap };
        for (int core = 0; core < config.cores; core++) {
            List<Event> accesses = new();
            foreach (Event eventRecord in byCore[core])
                if (!eventRecord.op.Equals("FENCE"))
                    accesses.Add(eventRecord);
            Dictionary<int, int> last = new();
            Fenwick tree = new Fenwick(accesses.Count);
            int cold = 0;
            int[] histogram = new int[6], lru = new int[5];
            for (int i = 0; i < accesses.Count; i++) {
                Event eventRecord = accesses[i];
                int? previous = last.TryGetValue(eventRecord.block, out int previousValue)
                                    ? previousValue
                                    : null;
                if (previous == null)
                    cold++;
                else {
                    eventRecord.distance = tree.Sum(i) - tree.Sum(previous.Value) + 1;
                    tree.Add(previous.Value, -1);
                    int d = eventRecord.distance, bucket = d == 1     ? 0
                                                           : d <= 4   ? 1
                                                           : d <= 16  ? 2
                                                           : d <= 64  ? 3
                                                           : d <= 256 ? 4
                                                                      : 5;
                    histogram[bucket]++;
                }
                for (int j = 0; j < capacities.Length; j++)
                    if (previous == null || eventRecord.distance > capacities[j])
                        lru[j]++;
                tree.Add(i + 1, 1);
                last[eventRecord.block] = i + 1;
            }
            int[] next = new int[accesses.Count];
            Dictionary<int, int> upcoming = new();
            for (int i = accesses.Count - 1; i >= 0; i--) {
                int block = accesses[i].block;
                next[i] = upcoming.GetValueOrDefault(block, accesses.Count + 1);
                upcoming[block] = i;
            }
            Dictionary<int, int> resident = new();
            PriorityQueue<Future, (int, int)> priorities = new();
            int opt = 0;
            for (int i = 0; i < accesses.Count; i++) {
                int block = accesses[i].block;
                if (!resident.ContainsKey(block)) {
                    opt++;
                    if (resident.Count == config.cap) {
                        Future victim;
                        do {
                            victim = priorities.Dequeue();
                        } while (resident.GetValueOrDefault(victim.block, -1) != victim.next);
                        resident.Remove(victim.block);
                    }
                }
                resident[block] = next[i];
                priorities.Enqueue(new Future(block, next[i]), (-next[i], block));
            }
            analyses.Add(
                new Reuse(core, accesses.Count, last.Count, histogram, cold, capacities, lru, opt));
        }
        return analyses;
    }
    public sealed class WordInfo {
        public HashSet<int> reads = new(), writes = new();
    }
    public sealed class Sharing {
        public HashSet<int> cores = new(), writers = new();
        public int reads, writes;
        public SortedDictionary<int, WordInfo> words = new();
        public bool shared, isTrue;
    }
    public static SortedDictionary<int, Sharing> StaticSharing(List<Event> events) {
        SortedDictionary<int, Sharing> lines = new();
        foreach (Event eventRecord in events)
            if (!eventRecord.op.Equals("FENCE")) {
                Sharing info = lines.GetOrAdd(eventRecord.block, () => new Sharing());
                info.cores.Add(eventRecord.core);
                WordInfo word = info.words.GetOrAdd(eventRecord.word, () => new WordInfo());
                if (eventRecord.op.Equals("W")) {
                    info.writers.Add(eventRecord.core);
                    info.writes++;
                    word.writes.Add(eventRecord.core);
                } else {
                    info.reads++;
                    word.reads.Add(eventRecord.core);
                }
            }
        foreach (Sharing info in lines.Values) {
            info.shared = info.cores.Count >= 2 && info.writers.Count != 0;
            foreach (WordInfo word in info.words.Values) {
                HashSet<int> combined = new HashSet<int>(word.reads);
                combined.UnionWith(word.writes);
                if (word.writes.Count != 0 && combined.Count >= 2)
                    info.isTrue = true;
            }
        }
        return lines;
    }
    public sealed class WordState {
        public int writer;
        public HashSet<int> readers = new();
        public WordState(int writer) { this.writer = writer; }
    }
    public sealed class State {
        public ConfigIo.Config config;
        public ConfigIo.Scenario scenario;
        public List<Cache> l1 = new();
        public Cache l2;
        public Bus bus;
        public List<Stats.Core> cores = new();
        public List<List<Event>> eventLists;
        public int[] indices, ready, writeCompletion;
        public List<HashSet<int>> seen = new();
        public Dictionary<Key, HashSet<int>> invalidations = new();
        public Stats.Counts l2Counters = new Stats.Counts();
        public List<Processed> processed = new();
        public List<string> watchLines = new();
        public Dictionary<int, int> handoffs = new(), lastWriter = new();
        public Dictionary<Key, WordState> wordState = new();
        public int[][] communications;
        public Dictionary<Key, int> sharedMisses = new();
        public Stats.Core total;
        public int finish;
        public State(ConfigIo.Config config, ConfigIo.Scenario scenario, List<Event> events) {
            this.config = config;
            this.scenario = scenario;
            for (int c = 0; c < config.cores; c++) {
                l1.Add(new Cache(config.l1Sets, config.l1Ways, scenario.l1));
                cores.Add(new Stats.Core());
                seen.Add(new());
            }
            l2 = new Cache(config.l2Sets, config.l2Ways, scenario.l2);
            bus = new Bus(config.tb);
            eventLists = PerCoreEvents(events, config.cores);
            indices = new int[config.cores];
            ready = new int[config.cores];
            writeCompletion = new int[config.cores];
            communications = Enumerable.Range(0, config.cores)
                                 .Select(
                                     _ => new int[config.cores])
                                 .ToArray();
        }
        public List<string> LineStates(int block) {
            List<string> states = new();
            foreach (Cache cache in l1)
                states.Add(cache.State(block));
            states.Add(l2.State(block));
            return states;
        }
        public Bus.Transaction IssueTransaction(int core, string kind, int block, int requested) {
            Bus.Transaction tx = bus.Assign(core, kind, block, requested);
            cores[core].bus.Add(kind, 1);
            if (kind.Equals("WB"))
                l2Counters.Add("writebacks", 1);
            return tx;
        }
        public void SnoopOthers(Bus.Transaction tx, int word) {
            for (int core = 0; core < config.cores; core++) {
                if (core == tx.core)
                    continue;
                Cache cache = l1[core];
                string old = cache.State(tx.block);
                if (old.Equals("I"))
                    continue;
                Protocol.Snoop change = Protocol.OnSnoop(scenario.protocol, old, tx.kind);
                tx.snoop.Add("c" + core + ":" + old + ">" + change.state);
                tx.snoopHits++;
                if (change.state.Equals("I")) {
                    cache.Remove(tx.block);
                    tx.invalidations++;
                    cores[tx.core].snoop.Add("invalidations_sent", 1);
                    cores[core].snoop.Add("invalidations_received", 1);
                    invalidations[new Key(core, tx.block)] =
                        new HashSet<int>(new List<int> { word });
                } else
                    cache.Change(tx.block, change.state);
                if (change.supply) {
                    tx.supplier = core;
                    cores[core].snoop.Add("supplied", 1);
                }
                if (change.flush)
                    tx.flush = true;
            }
            if (tx.flush)
                l2Counters.Add("flushes", 1);
        }
        public void AccessL2(Bus.Transaction tx) {
            l2Counters.Add("lookups", 1);
            if (!l2.State(tx.block).Equals("I")) {
                tx.l2 = "hit";
                l2Counters.Add("hits", 1);
                l2.Touch(tx.block);
            } else {
                tx.l2 = "miss";
                l2Counters.Add("misses", 1);
                Cache.Line evicted = l2.Fill(tx.block, "C");
                if (evicted != null) {
                    bool dirty = evicted.state.Equals("D");
                    List<string> copies = new();
                    for (int core = 0; core < config.cores; core++) {
                        string old = l1[core].State(evicted.block);
                        if (old.Equals("I"))
                            continue;
                        l1[core].Remove(evicted.block);
                        copies.Add("c" + core + ":" + old);
                        cores[core].snoop.Add("back_invalidations", 1);
                        if (Protocol.DIRTY.Contains(old))
                            dirty = true;
                    }
                    tx.eviction = new Bus.Eviction(evicted.block, copies, dirty);
                    l2Counters.Add("evictions", 1);
                    if (dirty)
                        l2Counters.Add("dirty_evictions", 1);
                }
            }
            if (tx.flush || tx.kind.Equals("BusWr"))
                l2.Change(tx.block, "D");
        }
        public BusResult RunTransaction(int core, string kind, int block, int word, int requested) {
            Bus.Transaction tx = IssueTransaction(core, kind, block, requested);
            SnoopOthers(tx, word);
            if (!kind.Equals("BusUpgr"))
                AccessL2(tx);
            int completion = tx.start + config.tb;
            if (kind.Equals("BusUpgr"))
                return new BusResult(completion, tx);
            if (kind.Equals("BusWr"))
                completion += config.t2 + (tx.l2.Equals("miss") ? config.tm : 0);
            else if (tx.supplier != null)
                tx.source = "c" + tx.supplier;
            else if (tx.l2.Equals("hit")) {
                completion += config.t2;
                tx.source = "L2";
            } else {
                completion += config.t2 + config.tm;
                tx.source = "mem";
            }
            return new BusResult(completion, tx);
        }
        public void WriteBack(int core, Cache.Line line) {
            IssueTransaction(core, "WB", line.block, bus.free);
            l2.Touch(line.block);
            l2.Change(line.block, "D");
        }
        public Miss ClassifyMiss(Event eventRecord) {
            HashSet<int> record =
                invalidations.GetValueOrDefault(new Key(eventRecord.core, eventRecord.block));
            if (!seen[eventRecord.core].Contains(eventRecord.block))
                return new Miss("compulsory", null);
            if (record != null)
                return new Miss("coherence", record.Contains(eventRecord.word) ? "true_sharing"
                                                                               : "false_sharing");
            return new Miss(eventRecord.distance > config.cap ? "capacity" : "conflict", null);
        }
        public void Communicate(Event eventRecord) {
            Key key = new Key(eventRecord.block, eventRecord.word);
            WordState previous = wordState.GetValueOrDefault(key);
            if (eventRecord.op.Equals("W")) {
                int? former = lastWriter.TryGetValue(eventRecord.block, out int formerValue)
                                  ? formerValue
                                  : null;
                if (former != null && former != eventRecord.core)
                    handoffs.AddCount(eventRecord.block, 1);
                lastWriter[eventRecord.block] = eventRecord.core;
                wordState[key] = new WordState(eventRecord.core);
            } else if (previous != null && previous.writer != eventRecord.core &&
                       previous.readers.Add(eventRecord.core))
                communications[previous.writer][eventRecord.core]++;
        }
        public void RenderWatch(Event eventRecord, int issue,
                                Dictionary<int, List<string>> before) {
            foreach (int block in config.watch) {
                List<string> after = LineStates(block);
                if (block != eventRecord.block && before[block].SequenceEqual(after))
                    continue;
                List<string> columns = new();
                for (int c = 0; c < config.cores; c++)
                    columns.Add("c" + c + ":" + after[c]);
                watchLines.Add(eventRecord.number + " " + issue + " c" + eventRecord.core + " " +
                               eventRecord.op + " " + ConfigIo.HexAddress(eventRecord.address) +
                               " line " + ConfigIo.HexAddress(block * config.line) + " " +
                               string.Join(" ", columns) + " L2:" + after[^1]);
            }
        }
        public void HandleAccess(Event eventRecord, int issue, bool primary) {
            int core = eventRecord.core, block = eventRecord.block, word = eventRecord.word;
            Stats.Core counters = cores[core];
            Cache cache = l1[core];
            Dictionary<int, List<string>> before = new();
            if (primary)
                foreach (int watched in config.watch)
                    before[watched] = LineStates(watched);
            string old = cache.State(block);
            bool hit = !old.Equals("I");
            counters.simple.Add("accesses", 1);
            counters.simple.Add(eventRecord.op.Equals("R") ? "reads" : "writes", 1);
            counters.simple.Add(hit ? "hits" : "misses", 1);
            bool otherCopy = false;
            for (int k = 0; k < config.cores; k++)
                if (k != core && !l1[k].State(block).Equals("I"))
                    otherCopy = true;
            Protocol.Request transition =
                Protocol.Requester(scenario.protocol, old, eventRecord.op, otherCopy);
            string missKind = null;
            if (hit)
                cache.Touch(block);
            else {
                Miss miss = ClassifyMiss(eventRecord);
                missKind = miss.kind;
                counters.misses.Add(missKind, 1);
                if (miss.sharing != null) {
                    counters.misses.Add(miss.sharing, 1);
                    sharedMisses.AddCount(
                        new Key(block, miss.sharing.Equals("true_sharing") ? 1 : 0), 1);
                }
            }
            seen[core].Add(block);
            if (eventRecord.op.Equals("W"))
                foreach (KeyValuePair<Key, HashSet<int>> entry in invalidations)
                    if (entry.Key.first != core && entry.Key.second == block)
                        entry.Value.Add(word);
            if (primary)
                Communicate(eventRecord);
            int completion;
            string service;
            if (transition.transaction == null) {
                completion = issue + config.t1;
                service = "l1";
            } else {
                BusResult result =
                    RunTransaction(core, transition.transaction, block, word, issue + config.t1);
                completion = result.completion;
                Bus.Transaction tx = result.transaction;
                service = tx.kind.Equals("BusUpgr") ? "upgrade"
                          : tx.kind.Equals("BusWr") ? "through"
                          : tx.supplier != null     ? "cache"
                          : tx.l2.Equals("hit")     ? "l2"
                                                    : "memory";
            }
            if (!old.Equals("I"))
                cache.Change(block, transition.state);
            else if (!transition.state.Equals("I")) {
                Cache.Line evicted = cache.Fill(block, transition.state);
                invalidations.Remove(new Key(core, block));
                if (evicted != null && Protocol.DIRTY.Contains(evicted.state))
                    WriteBack(core, evicted);
            }
            int latency = completion - issue;
            counters.service.Add(service, 1);
            counters.simple.Add("latency", latency);
            if (eventRecord.op.Equals("R")) {
                counters.simple.Add("read_latency", latency);
                ready[core] = completion;
            } else {
                counters.simple.Add("write_latency", latency);
                ready[core] = issue + config.t1;
                writeCompletion[core] = Math.Max(writeCompletion[core], completion);
            }
            counters.finish = Math.Max(counters.finish, completion);
            processed.Add(new Processed(eventRecord, issue, latency, service, missKind, hit));
            if (primary)
                RenderWatch(eventRecord, issue, before);
        }
        public void HandleFence(Event eventRecord, int issue) {
            Stats.Core counters = cores[eventRecord.core];
            int completion = Math.Max(issue, writeCompletion[eventRecord.core]);
            counters.simple.Add("fences", 1);
            counters.simple.Add("fence_stall", completion - issue);
            counters.finish = Math.Max(counters.finish, completion);
            ready[eventRecord.core] = completion;
        }
        public void Simulate(bool primary) {
            while (true) {
                Event chosen = null;
                int issue = int.MaxValue;
                for (int c = 0; c < config.cores; c++)
                    if (indices[c] < eventLists[c].Count) {
                        Event candidate = eventLists[c][indices[c]];
                        int time = Math.Max(candidate.cycle, ready[c]);
                        if (time < issue) {
                            chosen = candidate;
                            issue = time;
                        }
                    }
                if (chosen == null)
                    break;
                indices[chosen.core]++;
                if (chosen.op.Equals("FENCE"))
                    HandleFence(chosen, issue);
                else
                    HandleAccess(chosen, issue, primary);
            }
            total = Stats.Total(cores);
            finish = total.finish;
        }
    }
    public static List<string> FormatTraceConfig(ConfigIo.Config c, List<string> trace,
                                                 Validated valid) {
        List<string> lines = new();
        lines.Add("trace lines " + trace.Count + " accepted " + valid.events.Count + " rejected " +
                  valid.rejected.Count);
        foreach (Rejection rejection in valid.rejected)
            lines.Add("reject line " + rejection.line + " " + rejection.reason);
        lines.Add("geometry cores " + c.cores + " line " + c.line + " l1 " + c.l1Size + " " +
                  c.l1Ways + " sets " + c.l1Sets + " l2 " + c.l2Size + " " + c.l2Ways + " sets " +
                  c.l2Sets);
        lines.Add("latency l1 " + c.t1 + " l2 " + c.t2 + " memory " + c.tm + " bus " + c.tb);
        return lines;
    }
    public static List<string> FormatReuse(List<Reuse> analyses, ConfigIo.Config c) {
        List<string> lines = new();
        foreach (Reuse record in analyses) {
            lines.Add("reuse c" + record.core + " accesses " + record.accesses + " lines " +
                      record.lines + " distance " + Stats.Ranges(record.distances, REUSE_LABELS) +
                      " cold " + record.cold);
            List<string> misses = new();
            for (int i = 0; i < record.capacities.Length; i++)
                misses.Add(record.capacities[i] + ":" + record.lru[i]);
            lines.Add("mrc c" + record.core + " lru " + string.Join(" ", misses) + " opt " + c.cap +
                      ":" + record.opt);
        }
        return lines;
    }
    public static string LengthHistogram(List<Processed> accesses) {
        int[] counts = new int[6];
        foreach (Processed access in accesses) {
            int l = access.latency;
            counts[l == 1 ? 0 : l <= 9 ? 1 : l <= 29 ? 2 : l <= 99 ? 3 : l <= 299 ? 4 : 5]++;
        }
        return Stats.Ranges(counts, LATENCY_LABELS);
    }
    public static List<string> ScenarioReport(State state) {
        ConfigIo.Config c = state.config;
        ConfigIo.Scenario s = state.scenario;
        List<string> lines = new();
        lines.Add("scenario " + s.name + " " + s.protocol + " " + s.l1 + " " + s.l2);
        for (int core = 0; core < c.cores; core++)
            lines.AddRange(Stats.SixLines("c" + core, state.cores[core]));
        lines.AddRange(Stats.SixLines("total", state.total));
        Stats.Counts l2 = state.l2Counters;
        lines.Add("l2 " +
                  l2.Named(new List<string> { "lookups", "hits", "misses", "flushes", "writebacks",
                                              "evictions", "dirty_evictions" }));
        int transactions = state.bus.transactions.Count, busy = c.tb * transactions;
        lines.Add("bus transactions " + transactions + " busy " + busy + " wait " + state.bus.wait +
                  " utilization " + Stats.Decimal(100 * busy, state.finish));
        Stats.Counts kinds = state.total.bus;
        int dataBytes = c.line * (kinds.Get("BusRd") + kinds.Get("BusRdX") + kinds.Get("WB")) +
                        4 * kinds.Get("BusWr"),
            memoryBytes = c.line * (l2.Get("misses") + l2.Get("dirty_evictions"));
        lines.Add("traffic command_bytes " + (8 * transactions) + " data_bytes " + dataBytes +
                  " memory_bytes " + memoryBytes);
        int snoops = 0, hits = 0;
        int[] fanout = new int[c.cores];
        foreach (Bus.Transaction tx in state.bus.transactions)
            if (!tx.kind.Equals("WB")) {
                snoops++;
                hits += tx.snoopHits;
                if (!tx.kind.Equals("BusRd"))
                    fanout[tx.invalidations]++;
            }
        List<string> labels = new();
        for (int i = 0; i < c.cores; i++)
            labels.Add(Convert.ToString(i));
        lines.Add("snoops probes " + ((c.cores - 1) * snoops) + " hits " + hits + " fanout " +
                  Stats.Ranges(fanout, labels));
        lines.Add("latencies reads " + state.total.simple.Get("read_latency") + " writes " +
                  state.total.simple.Get("write_latency") + " histogram " +
                  LengthHistogram(state.processed));
        return lines;
    }
    public static List<string> RankScenarios(List<State> states) {
        List<State> ordered = new(states);
        ordered.Sort((a, b) => {
            int c = a.finish.CompareTo(b.finish);
            if (c == 0)
                c = a.bus.transactions.Count.CompareTo(b.bus.transactions.Count);
            return c != 0 ? c : a.scenario.order.CompareTo(b.scenario.order);
        });
        List<string> lines = new(new List<string> { "ranking" });
        for (int i = 0; i < ordered.Count; i++) {
            State state = ordered[i];
            int length = state.total.simple.Get("latency"),
                accesses = state.total.simple.Get("accesses");
            lines.Add((i + 1) + " " + state.scenario.name + " finish " + state.finish +
                      " transactions " + state.bus.transactions.Count + " amat " +
                      Stats.Fraction(length, accesses) + " " + Stats.Decimal(length, accesses));
        }
        return lines;
    }
    public sealed class Hot {
        public Stats.Counts counts = new Stats.Counts();
        public HashSet<int> cores = new();
        public int total;
    }
    public static List<string> HotLines(State state) {
        Dictionary<int, Hot> hot = new();
        foreach (Bus.Transaction tx in state.bus.transactions) {
            Hot info = hot.GetOrAdd(tx.block, () => new Hot());
            info.counts.Add(tx.kind, 1);
            info.counts.Add("invalidations", tx.invalidations);
            info.total++;
            info.cores.Add(tx.core);
        }
        foreach (Processed item in state.processed)
            if (item.missKind != null) {
                Hot info = hot.GetOrAdd(item.eventRecord.block, () => new Hot());
                info.counts.Add("misses", 1);
                if (item.missKind.Equals("coherence"))
                    info.counts.Add("coherence", 1);
            }
        List<int> blocks = new();
        foreach (KeyValuePair<int, Hot> entry in hot)
            if (entry.Value.total > 0)
                blocks.Add(entry.Key);
        blocks.Sort((a, b) => {
            int c = hot[b].total.CompareTo(hot[a].total);
            return c != 0 ? c : a.CompareTo(b);
        });
        List<string> lines = new(new List<string> { "hot " + state.scenario.name });
        for (int i = 0; i < Math.Min(state.config.top, blocks.Count); i++) {
            int block = blocks[i];
            Hot info = hot[block];
            lines.Add(
                (i + 1) + " " + ConfigIo.HexAddress(block * state.config.line) + " transactions " +
                info.total + " " + info.counts.Named(Stats.TRANSACTIONS) + " " +
                info.counts.Named(new List<string> { "misses", "coherence", "invalidations" }) +
                " cores " + Stats.CoreString(info.cores));
        }
        return lines;
    }
    public static string Integers(int[] values) {
        List<string> pieces = new();
        foreach (int value in values)
            pieces.Add(Convert.ToString(value));
        return string.Join(" ", pieces);
    }
    public static List<string> IntervalRows(State state) {
        ConfigIo.Config c = state.config;
        int width = c.interval, count = state.finish / width + 1;
        int[][] accesses = Enumerable.Range(0, count)
                               .Select(
                                   _ => new int[c.cores])
                               .ToArray();
        int[] misses = new int[count], transactions = new int[count], busy = new int[count];
        foreach (Processed item in state.processed) {
            int bucket = item.issue / width;
            accesses[bucket][item.eventRecord.core]++;
            if (item.missKind != null)
                misses[bucket]++;
        }
        foreach (Bus.Transaction tx in state.bus.transactions) {
            int first = tx.start, last = first + c.tb;
            transactions[first / width]++;
            for (int k = first / width; k <= (last - 1) / width; k++)
                if (k < count)
                    busy[k] +=
                        Math.Max(0, Math.Min(last, (k + 1) * width) - Math.Max(first, k * width));
        }
        List<string> lines =
            new(new List<string> { "intervals " + state.scenario.name + " " + width });
        for (int k = 0; k < count; k++)
            lines.Add(k + " " + (k * width) + "-" + ((k + 1) * width - 1) + " accesses " +
                      Integers(accesses[k]) + " misses " + misses[k] + " transactions " +
                      transactions[k] + " busy " + busy[k] + " utilization " +
                      Stats.Decimal(100 * busy[k], width));
        return lines;
    }
    public static List<string> SlowestRows(State state) {
        List<Processed> ordered = new(state.processed);
        ordered.Sort((a, b) => {
            int c = b.latency.CompareTo(a.latency);
            return c != 0 ? c : a.eventRecord.number.CompareTo(b.eventRecord.number);
        });
        List<string> lines = new(new List<string> { "slowest " + state.scenario.name });
        for (int i = 0; i < Math.Min(state.config.top, ordered.Count); i++) {
            Processed item = ordered[i];
            Event eventRecord = item.eventRecord;
            lines.Add((i + 1) + " event " + eventRecord.number + " cycle " + item.issue + " c" +
                      eventRecord.core + " " + eventRecord.op + " " +
                      ConfigIo.HexAddress(eventRecord.address) + " latency " + item.latency +
                      " service " + item.service);
        }
        return lines;
    }
    public static string RegionFor(int address, ConfigIo.Config config) {
        foreach (ConfigIo.Region region in config.regions)
            if (region.start <= address && address <= region.end)
                return region.name;
        return "other";
    }
    public static List<string> RegionRows(State state) {
        ConfigIo.Config c = state.config;
        Dictionary<string, Stats.Counts> counters = new();
        foreach (ConfigIo.Region region in c.regions)
            counters[region.name] = new Stats.Counts();
        counters["other"] = new Stats.Counts();
        foreach (Processed item in state.processed) {
            Event eventRecord = item.eventRecord;
            Stats.Counts count = counters[RegionFor(eventRecord.address, c)];
            count.Add("accesses", 1);
            count.Add(eventRecord.op.Equals("R") ? "reads" : "writes", 1);
            count.Add("latency", item.latency);
            count.Add(item.hit ? "hits" : item.missKind, 1);
        }
        foreach (Bus.Transaction tx in state.bus.transactions)
            counters[RegionFor(tx.block * c.line, c)].Add("transactions", 1);
        List<string> lines = new(new List<string> { "regions " + state.scenario.name });
        foreach (KeyValuePair<string, Stats.Counts> entry in counters) {
            Stats.Counts count = entry.Value;
            string amat = count.Get("accesses") == 0
                              ? "-"
                              : Stats.Fraction(count.Get("latency"), count.Get("accesses")) + " " +
                                    Stats.Decimal(count.Get("latency"), count.Get("accesses"));
            lines.Add(entry.Key + " " +
                      count.Named(new List<string> { "accesses", "reads", "writes", "hits" }) +
                      " " + count.Named(Stats.MISSES) + " " +
                      count.Named(new List<string> { "transactions", "latency" }) + " amat " +
                      amat);
        }
        return lines;
    }
    public static List<string> StatsOutput(ConfigIo.Config c, List<string> trace, Validated valid,
                                           List<Reuse> reuse, List<State> states, State primary) {
        List<List<string>> sections = new();
        sections.Add(FormatTraceConfig(c, trace, valid));
        sections.Add(FormatReuse(reuse, c));
        foreach (State state in states)
            sections.Add(ScenarioReport(state));
        sections.Add(RankScenarios(states));
        sections.Add(HotLines(primary));
        sections.Add(IntervalRows(primary));
        sections.Add(SlowestRows(primary));
        sections.Add(RegionRows(primary));
        List<string> lines = new();
        foreach (List<string> section in sections) {
            if (lines.Count != 0)
                lines.Add("");
            lines.AddRange(section);
        }
        return lines;
    }
    public static List<string> SharingOutput(SortedDictionary<int, Sharing> shared, State state) {
        List<string> lines = new();
        int count = 0, trueLines = 0, falseLines = 0, totalTrue = 0, totalFalse = 0;
        foreach (KeyValuePair<int, Sharing> entry in shared) {
            int block = entry.Key;
            Sharing info = entry.Value;
            if (!info.shared)
                continue;
            count++;
            if (info.isTrue)
                trueLines++;
            else
                falseLines++;
            int t = state.sharedMisses.GetValueOrDefault(new Key(block, 1), 0),
                f = state.sharedMisses.GetValueOrDefault(new Key(block, 0), 0);
            totalTrue += t;
            totalFalse += f;
            List<string> words = new();
            foreach (KeyValuePair<int, WordInfo> word in info.words)
                words.Add("w" + word.Key + "=" + Stats.CoreString(word.Value.reads) + "/" +
                          Stats.CoreString(word.Value.writes));
            lines.Add(ConfigIo.HexAddress(block * state.config.line) + " " +
                      (info.isTrue ? "true" : "false") + " cores " + Stats.CoreString(info.cores) +
                      " writers " + Stats.CoreString(info.writers) + " reads " + info.reads +
                      " writes " + info.writes + " handoffs " +
                      state.handoffs.GetValueOrDefault(block, 0) + " coherence " + (t + f) +
                      " true " + t + " false " + f + " words " + string.Join(" ", words));
        }
        lines.Add("lines " + count + " true_lines " + trueLines + " false_lines " + falseLines +
                  " coherence " + (totalTrue + totalFalse) + " true " + totalTrue + " false " +
                  totalFalse);
        lines.Add("communication");
        for (int c = 0; c < state.config.cores; c++)
            lines.Add("c" + c + " " + Integers(state.communications[c]));
        return lines;
    }
    public static string CacheWay(Cache.Line entry, int lineSize) {
        return entry == null ? "-"
                             : ConfigIo.HexAddress(entry.block * lineSize) + ":" + entry.state;
    }
    public static void CacheRows(List<string> lines, Cache cache, string label, int lineSize) {
        for (int row = 0; row < cache.numberSets; row++) {
            List<string> ways = new();
            foreach (Cache.Line entry in cache.entries[row])
                ways.Add(CacheWay(entry, lineSize));
            lines.Add(label + " " + row + " " + string.Join(" ", ways) + " " +
                      cache.replacement.ToLowerInvariant() + " " + cache.Order(row) + " fills " +
                      cache.fills[row] + " evictions " + cache.evictions[row]);
        }
    }
    public static List<string> FinalStateOutput(State state) {
        List<string> lines = new();
        HashSet<int> inL1 = new();
        for (int core = 0; core < state.config.cores; core++) {
            Cache cache = state.l1[core];
            CacheRows(lines, cache, "c" + core, state.config.line);
            Stats.Counts counts = new Stats.Counts();
            foreach (Cache.Line entry in cache.Lines()) {
                counts.Add(entry.state, 1);
                inL1.Add(entry.block);
            }
            lines.Add("c" + core + " lines " + cache.Lines().Count + " " +
                      counts.Named(new List<string> { "M", "O", "E", "S", "V" }));
        }
        CacheRows(lines, state.l2, "L2", state.config.line);
        Stats.Counts l2Counts = new Stats.Counts();
        foreach (Cache.Line entry in state.l2.Lines())
            l2Counts.Add(entry.state, 1);
        lines.Add("L2 lines " + state.l2.Lines().Count + " dirty " + l2Counts.Get("D") + " clean " +
                  l2Counts.Get("C") + " in_l1 " + inL1.Count);
        return lines;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        ConfigIo.Config config = ConfigIo.ReadConfig();
        List<string> trace = ConfigIo.ReadTrace();
        Validated valid = ValidateTrace(trace, config);
        List<Reuse> reuse = ReuseAnalysis(valid.events, config);
        SortedDictionary<int, Sharing> shared = StaticSharing(valid.events);
        List<State> states = new();
        State primary = null;
        foreach (ConfigIo.Scenario scenario in config.scenarios) {
            State state = new State(config, scenario, valid.events);
            state.Simulate(scenario.name.Equals(config.primary));
            states.Add(state);
            if (scenario.name.Equals(config.primary))
                primary = state;
        }
        ConfigIo.WriteLines("stats.txt", StatsOutput(config, trace, valid, reuse, states, primary));
        List<string> busLines = new();
        foreach (Bus.Transaction tx in primary.bus.transactions)
            busLines.Add(primary.bus.LogLine(tx, config.line));
        ConfigIo.WriteLines("bus_log.txt", busLines);
        ConfigIo.WriteLines("watch.txt", primary.watchLines);
        ConfigIo.WriteLines("sharing.txt", SharingOutput(shared, primary));
        ConfigIo.WriteLines("final_state.txt", FinalStateOutput(primary));
    }
}
public static class MapHelpers {
    public static V GetOrAdd<K, V>(this IDictionary<K, V> map, K key, Func<V> factory) {
        if (!map.TryGetValue(key, out V value)) {
            value = factory();
            map[key] = value;
        }
        return value;
    }
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int amount) {
        map.TryGetValue(key, out int value);
        map[key] = value + amount;
    }
}
