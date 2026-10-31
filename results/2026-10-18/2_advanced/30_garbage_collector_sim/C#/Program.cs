using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program {
    static T Pop<T>(List<T> values) {
        T value = values[^1];
        values.RemoveAt(values.Count - 1);
        return value;
    }
    sealed record Checkpoint(Command command, int stack, Pair live, Pair allocated, Pair phase,
                             Pair survivors, HashSet<int> reachable);
    sealed record Pause(int line, int work, Pair freed, bool collection);
    sealed record Segment(int start, int length, bool mutator, int before);
    static int Used(IEnumerable<HeapObject> objects) {
        int words = 0;
        foreach (HeapObject item in objects)
            words += item.size;
        return words;
    }
    static Pair Pair(IEnumerable<HeapObject> objects) {
        Pair pair = new Pair();
        foreach (HeapObject item in objects)
            pair.Add(item);
        return pair;
    }
    static HashSet<int> Reachable(List<int> roots, List<HeapObject> objects) {
        HashSet<int> reached = new();
        Stack<int> stack = new();
        foreach (int root in roots)
            if (root != 0)
                stack.Push(root);
        while (stack.Count != 0) {
            int number = stack.Pop();
            if (!reached.Add(number))
                continue;
            foreach (int child in objects[number - 1].fields)
                if (child != 0)
                    stack.Push(child);
        }
        return reached;
    }
    static string Fragmentation(List<FreeBlock> blocks) {
        int total = Heap.Total(blocks);
        return Heap.Percent(total - Heap.Largest(blocks), total);
    }
    static List<string> Join(List<List<string>> blocks) {
        List<string> lines = new();
        foreach (List<string> block in blocks) {
            if (lines.Count != 0)
                lines.Add("");
            lines.AddRange(block);
        }
        return lines;
    }
    sealed class Script {
        public readonly int lineCount;
        public readonly List<Command> commands = new();
        public readonly List<string> errors = new();
        public readonly Dictionary<string, int> counts = new();
        public readonly List<int> roots = new();
        public readonly List<HeapObject> objects = new();
        public readonly List<int> births = new(), deaths = new(), lifetimes = new();
        public readonly List<Checkpoint> checkpoints = new();
        public readonly HashSet<string> labels = new();
        public HashSet<int> alive = new();
        public Pair live = new Pair(), peak = new Pair();
        public int clock, peakLine, phaseStart;
        public Script(List<string> lines) {
            lineCount = lines.Count;
            foreach (string name in Mutator.NAMES)
                counts[name] = 0;
            for (int i = 0; i < lines.Count; i++) {
                Parsed parsed = Mutator.Parse(i + 1, lines[i]);
                string reason = parsed.error;
                if (reason.Length == 0)
                    reason = Check(parsed.command);
                if (reason.Length == 0)
                    Run(parsed.command);
                else
                    errors.Add("error line " + (i + 1) + " " + reason);
            }
        }
        public string Check(Command command) {
            string name = command.name;
            int depth = roots.Count;
            if (new HashSet<string> { "ALLOC", "PUSH", "LOAD" }.Contains(name) && depth == 64)
                return "stack";
            if (new HashSet<string> { "LOAD", "SET", "OVERWRITE" }.Contains(name) && command.slot >= depth)
                return "stack";
            if (new HashSet<string> { "PUSH", "SET", "OVERWRITE" }.Contains(name) && command.source >= depth)
                return "stack";
            if (name.Equals("POP") && command.count > depth)
                return "stack";
            if (name.Equals("LOAD") || name.Equals("SET")) {
                int number = roots[command.slot];
                if (number == 0)
                    return "null";
                if (command.field >= objects[number - 1].fields.Length)
                    return "field";
            }
            if (name.Equals("CHECKPOINT") && labels.Contains(command.label))
                return "duplicate";
            return "";
        }
        public int Value(int source) {
            return source < 0 ? 0 : roots[source];
        }
        public void Execute(Command command) {
            string name = command.name;
            if (name.Equals("ALLOC")) {
                HeapObject item = new HeapObject(objects.Count + 1, command.pointers, command.data);
                objects.Add(item);
                births.Add(clock);
                deaths.Add(0);
                lifetimes.Add(-1);
                clock += item.size;
                roots.Add(item.number);
            } else if (name.Equals("PUSH"))
                roots.Add(Value(command.source));
            else if (name.Equals("LOAD"))
                roots.Add(objects[roots[command.slot] - 1].fields[command.field]);
            else if (name.Equals("POP"))
                for (int i = 0; i < command.count; i++)
                    Pop(roots);
            else if (name.Equals("SET"))
                objects[roots[command.slot] - 1].fields[command.field] = Value(command.source);
            else if (name.Equals("OVERWRITE"))
                roots[command.slot] = Value(command.source);
        }
        public void Run(Command command) {
            commands.Add(command);
            counts[command.name] = counts[command.name] + 1;
            Execute(command);
            HashSet<int> reached = Reachable(roots, objects);
            foreach (int number in alive)
                if (!reached.Contains(number)) {
                    deaths[number - 1] = command.line;
                    lifetimes[number - 1] = clock - births[number - 1] - objects[number - 1].size;
                }
            alive = reached;
            live = new Pair();
            foreach (int number in reached)
                live.Add(objects[number - 1]);
            if (peakLine == 0 || live.words > peak.words) {
                peak = live;
                peakLine = command.line;
            }
            if (command.name.Equals("CHECKPOINT")) {
                labels.Add(command.label);
                Pair allocated = Pair(objects), phase = new Pair(), survivors = new Pair();
                for (int i = phaseStart; i < objects.Count; i++) {
                    HeapObject item = objects[i];
                    phase.Add(item);
                    if (reached.Contains(item.number))
                        survivors.Add(item);
                }
                phaseStart = objects.Count;
                checkpoints.Add(
                    new Checkpoint(command, roots.Count, live, allocated, phase, survivors, reached));
            }
        }
        public List<string> Report() {
            List<string> lines =
                new(["script lines " + lineCount + " valid " + commands.Count + " errors " + errors.Count]);
            lines.AddRange(errors);
            string countLine = "commands";
            foreach (string name in Mutator.NAMES)
                countLine += " " + name + " " + counts[name];
            lines.Add(countLine);
            List<int> sizes = new();
            foreach (HeapObject item in objects)
                sizes.Add(item.size);
            lines.Add("allocated objects " + objects.Count + " words " + clock + " sizes " +
                      Heap.Classes(sizes));
            lines.Add("peak_live objects " + peak.count + " words " + peak.words + " line " + peakLine);
            lines.Add("end_live objects " + live.count + " words " + live.words + " stack " + roots.Count);
            int[] bins = new int[6], limits = { 63, 255, 1023, 4095 };
            foreach (int lifetime in lifetimes) {
                if (lifetime < 0)
                    bins[5]++;
                else {
                    int index = 0;
                    while (index < limits.Length && lifetime > limits[index])
                        index++;
                    bins[index]++;
                }
            }
            lines.Add("lifetimes 0-63 " + bins[0] + " 64-255 " + bins[1] + " 256-1023 " + bins[2] +
                      " 1024-4095 " + bins[3] + " 4096+ " + bins[4] + " live " + bins[5]);
            foreach (Checkpoint checkpoint in checkpoints)
                lines.Add("checkpoint " + checkpoint.command.label + " line " + checkpoint.command.line +
                          " stack " + checkpoint.stack + " live " + checkpoint.live + " allocated " +
                          checkpoint.allocated + " phase " + checkpoint.phase + " survivors " +
                          checkpoint.survivors + " survival " +
                          Heap.Percent(checkpoint.survivors.words, checkpoint.phase.words));
            return lines;
        }
    }
    static bool OnCycle(int start, SortedDictionary<int, HeapObject> members) {
        HashSet<int> seen = new();
        Stack<int> stack = new();
        foreach (int child in members[start].fields)
            if (members.ContainsKey(child))
                stack.Push(child);
        while (stack.Count != 0) {
            int number = stack.Pop();
            if (number == start)
                return true;
            if (!seen.Add(number))
                continue;
            foreach (int child in members[number].fields)
                if (members.ContainsKey(child))
                    stack.Push(child);
        }
        return false;
    }
    static List<string> LeakReport(string title, List<HeapObject> garbage, List<int> deaths) {
        SortedDictionary<int, HeapObject> members = new();
        Dictionary<int, List<int>> neighbors = new();
        foreach (HeapObject item in garbage) {
            members[item.number] = item;
            neighbors[item.number] = new();
        }
        foreach (HeapObject item in garbage)
            foreach (int child in item.fields)
                if (members.ContainsKey(child)) {
                    neighbors[item.number].Add(child);
                    neighbors[child].Add(item.number);
                }
        List<List<HeapObject>> groups = new();
        HashSet<int> grouped = new();
        foreach (int number in members.Keys) {
            if (!grouped.Add(number))
                continue;
            List<HeapObject> group = new();
            Stack<int> stack = new();
            stack.Push(number);
            while (stack.Count != 0) {
                int current = stack.Pop();
                group.Add(members[current]);
                foreach (int other in neighbors[current])
                    if (grouped.Add(other))
                        stack.Push(other);
            }
            group.Sort(Comparer<HeapObject>.Create((first, second) => first.number.CompareTo(second.number)));
            groups.Add(group);
        }
        List<string> lines = new(
            [title + " groups " + groups.Count + " objects " + garbage.Count + " words " + Used(garbage)]);
        for (int i = 0; i < groups.Count; i++) {
            List<HeapObject> group = groups[i];
            List<string> ids = new();
            int cycles = 0, died = 0;
            foreach (HeapObject item in group) {
                bool cycle = OnCycle(item.number, members);
                if (cycle)
                    cycles++;
                died = Math.Max(died, deaths[item.number - 1]);
                ids.Add(item.number + (cycle ? "*" : ""));
            }
            lines.Add("group " + (i + 1) + " objects " + group.Count + " words " + Used(group) + " cycle " +
                      cycles + " died " + died + " ids " + string.Join(" ", ids));
        }
        return lines;
    }
    sealed class RefCounting : MarkSweep {
        public readonly List<int> deaths;
        public readonly List<HeapObject> released = new();
        public readonly List<List<string>> reports = new();
        public int increments, decrements;
        public RefCounting(int size, List<int> deaths) : base(size) {
            this.deaths = deaths;
        }
        public void Retain(int number) {
            if (number != 0) {
                Lookup(number).count++;
                increments++;
            }
        }
        public void Release(int number) {
            if (number == 0)
                return;
            HeapObject item = Lookup(number);
            decrements++;
            item.count--;
            if (item.count != 0)
                return;
            Stack<HeapObject> pending = new();
            pending.Push(item);
            while (pending.Count != 0) {
                HeapObject current = pending.Pop();
                objects.Remove(current);
                released.Add(current);
                foreach (int child in current.fields)
                    if (child != 0) {
                        decrements++;
                        HeapObject target = Lookup(child);
                        target.count--;
                        if (target.count == 0)
                            pending.Push(target);
                    }
            }
        }
        public Pause Cascade(int line) {
            if (released.Count == 0)
                return null;
            Pair freed = Pair(released);
            int work = 0;
            foreach (HeapObject item in released)
                work += 1 + item.fields.Length;
            released.Clear();
            return new Pause(line, work, freed, false);
        }
        public override void Collect(List<int> roots, int line, int request) {
            CollectionRecord record =
                new CollectionRecord(records.Count + 1, line, request, "backup", FreeList());
            Marking.Mark(this, roots, record);
            List<HeapObject> garbage = new();
            foreach (HeapObject item in objects)
                if (!item.marked)
                    garbage.Add(item);
            reports.Add(LeakReport("backup " + record.number + " line " + line, garbage, deaths));
            Marking.Sweep(this, record);
            foreach (HeapObject item in garbage)
                foreach (int child in item.fields)
                    if (child != 0 && Lookup(child).marked) {
                        Lookup(child).count--;
                        decrements++;
                    }
            record.Finish(FreeList());
            records.Add(record);
        }
        public void Finish(HashSet<int> reachable) {
            List<HeapObject> garbage = new();
            foreach (HeapObject item in objects)
                if (!reachable.Contains(item.number))
                    garbage.Add(item);
            reports.Add(LeakReport("end", garbage, deaths));
        }
    }
    sealed class PauseStats {
        public readonly int count, collections, work, freed, maximum;
        public readonly string p50, p90;
        public PauseStats(List<Pause> pauses) {
            count = pauses.Count;
            List<int> works = new();
            int collections = 0, work = 0, freed = 0;
            foreach (Pause pause in pauses) {
                works.Add(pause.work);
                if (pause.collection)
                    collections++;
                work += pause.work;
                freed += pause.freed.words;
            }
            works.Sort();
            this.collections = collections;
            this.work = work;
            this.freed = freed;
            maximum = works.Count == 0 ? 0 : works[^1];
            p50 = count == 0 ? "-" : Convert.ToString(works[(50 * count + 99) / 100 - 1]);
            p90 = count == 0 ? "-" : Convert.ToString(works[(90 * count + 99) / 100 - 1]);
        }
    }
    sealed class Timeline {
        public readonly List<Segment> segments = new();
        public int length, mutator;
        public void Add(bool mutator, int units) {
            if (units == 0)
                return;
            segments.Add(new Segment(length, units, mutator, this.mutator));
            length += units;
            if (mutator)
                this.mutator += units;
        }
        public int Prefix(int position) {
            int low = 0, high = segments.Count;
            while (low + 1 < high) {
                int middle = (low + high) / 2;
                if (segments[middle].start <= position)
                    low = middle;
                else
                    high = middle;
            }
            Segment segment = segments[low];
            return segment.before + (segment.mutator ? position - segment.start : 0);
        }
        public string Mmu(int width) {
            if (width > length)
                return "-";
            int minimum = width;
            foreach (Segment segment in segments)
                foreach (int begin in new int[] { segment.start, segment.start + segment.length - width })
                    if (begin >= 0 && begin <= length - width)
                        minimum = Math.Min(minimum, Prefix(begin + width) - Prefix(begin));
            return Heap.Percent(minimum, width);
        }
    }
    static Collector Collector(CollectorEntry entry, Config config, Script script) {
        if (entry.type.Equals("MARK_SWEEP"))
            return new MarkSweep(config.heap);
        if (entry.type.Equals("MARK_COMPACT"))
            return new MarkCompact(config.heap);
        if (entry.type.Equals("COPYING"))
            return new Copying(config.heap);
        if (entry.type.Equals("GENERATIONAL"))
            return new Generational(config.heap, entry.young, entry.age);
        return new RefCounting(config.heap, script.deaths);
    }
    sealed class Run {
        public readonly CollectorEntry entry;
        public readonly Config config;
        public readonly Script script;
        public readonly Collector collector;
        public readonly bool refcount, generational;
        public readonly List<int> roots = new();
        public readonly List<Pause> cascades = new();
        public readonly Timeline timeline = new Timeline();
        public readonly List<List<string>> observations = new();
        public int peak, failedLine, failedSize;
        public Run(CollectorEntry entry, Config config, Script script) {
            this.entry = entry;
            this.config = config;
            this.script = script;
            collector = Collector(entry, config, script);
            refcount = entry.type.Equals("REFCOUNT");
            generational = entry.type.Equals("GENERATIONAL");
        }
        public bool Completed() {
            return failedLine == 0;
        }
        public int Value(int source) {
            return source < 0 ? 0 : roots[source];
        }
        public void Retain(int value) {
            if (refcount)
                ((RefCounting)collector).Retain(value);
        }
        public void Release(int value) {
            if (refcount)
                ((RefCounting)collector).Release(value);
        }
        public void Push(int value) {
            Retain(value);
            roots.Add(value);
        }
        public void Simulate() {
            foreach (Command command in script.commands) {
                int before = collector.records.Count, units = 1;
                bool placed = true;
                if (command.name.Equals("ALLOC")) {
                    HeapObject item =
                        new HeapObject(collector.placed.Count + 1, command.pointers, command.data);
                    units = item.size;
                    placed = collector.Allocate(item, roots, command.line);
                    if (placed) {
                        Push(item.number);
                        peak = Math.Max(peak, Used(collector.objects));
                    }
                } else
                    Execute(command);
                foreach (CollectionRecord record in collector.records.GetRange(
                             before, collector.records.Count - (before)))
                    timeline.Add(false, record.work);
                if (!placed) {
                    failedLine = command.line;
                    failedSize = units;
                    return;
                }
                timeline.Add(true, units);
                if (refcount) {
                    Pause cascade = ((RefCounting)collector).Cascade(command.line);
                    if (cascade != null) {
                        cascades.Add(cascade);
                        timeline.Add(false, cascade.work);
                    }
                }
            }
            if (refcount)
                ((RefCounting)collector).Finish(script.alive);
        }
        public void Execute(Command command) {
            string name = command.name;
            if (name.Equals("PUSH"))
                Push(Value(command.source));
            else if (name.Equals("LOAD"))
                Push(collector.Lookup(roots[command.slot]).fields[command.field]);
            else if (name.Equals("POP"))
                for (int i = 0; i < command.count; i++)
                    Release(Pop(roots));
            else if (name.Equals("SET")) {
                int number = roots[command.slot], value = Value(command.source);
                if (generational)
                    ((Generational)collector).WriteBarrier(number, value);
                Retain(value);
                HeapObject item = collector.Lookup(number);
                int previous = item.fields[command.field];
                item.fields[command.field] = value;
                Release(previous);
            } else if (name.Equals("OVERWRITE")) {
                int value = Value(command.source);
                Retain(value);
                int previous = roots[command.slot];
                roots[command.slot] = value;
                Release(previous);
            } else
                observations.Add(Observe(script.checkpoints[observations.Count]));
        }
        public List<string> Observe(Checkpoint checkpoint) {
            Pair live = new Pair(), garbage = new Pair();
            int pointers = 0, forward = 0, backward = 0, distance = 0;
            foreach (HeapObject item in collector.objects) {
                if (!checkpoint.reachable.Contains(item.number)) {
                    garbage.Add(item);
                    continue;
                }
                live.Add(item);
                foreach (int child in item.fields)
                    if (child != 0) {
                        pointers++;
                        int difference = collector.Lookup(child).address - item.address;
                        if (difference > 0)
                            forward++;
                        if (difference < 0)
                            backward++;
                        distance += Math.Abs(difference);
                    }
            }
            List<FreeBlock> blocks = collector.FreeList();
            List<int> lengths = new();
            foreach (FreeBlock block in blocks)
                lengths.Add(block.length);
            List<string> lines = new([
                "heap objects " + Pair(collector.objects) + " reachable " + live + " garbage " + garbage,
                "free total " + Heap.Total(blocks) + " largest " + Heap.Largest(blocks) + " blocks " +
                    blocks.Count + " sizes " + Heap.Classes(lengths) + " fragmentation " +
                    Fragmentation(blocks),
                "locality pointers " + pointers + " forward " + forward + " backward " + backward +
                    " mean_distance " + (pointers == 0 ? "-" : Heap.Dec2(distance, pointers))
            ]);
            if (generational) {
                Generational gc = (Generational)collector;
                Pair young = new Pair(), old = new Pair();
                int[] ages = new int[4];
                foreach (HeapObject item in gc.objects) {
                    if (gc.Young(item)) {
                        young.Add(item);
                        ages[Math.Min(3, item.age)]++;
                    } else
                        old.Add(item);
                }
                lines.Add("generations young " + young + " old " + old + " remembered " +
                          gc.remembered.Count + " ages 0:" + ages[0] + " 1:" + ages[1] + " 2:" + ages[2] +
                          " 3+:" + ages[3]);
            }
            if (config.maps.Contains(checkpoint.command.label)) {
                string map =
                    Heap.Map(config.heap, collector.objects, checkpoint.reachable, collector.Inactive());
                for (int start = 0; start < map.Length; start += config.width)
                    lines.Add(start.ToString("D4", CultureInfo.InvariantCulture) + " " +
                              map.Substring(start, config.width));
            }
            return lines;
        }
        public List<Pause> Pauses() {
            List<Pause> pauses = new();
            foreach (CollectionRecord record in collector.records)
                pauses.Add(new Pause(record.line, record.work, record.freed, true));
            pauses.AddRange(cascades);
            return pauses;
        }
        public string GenerationalLine() {
            Generational gc = (Generational)collector;
            string line = "generational";
            Pair promoted = new Pair();
            foreach (string kind in new string[] { "minor", "major", "tenure", "full" }) {
                int count = 0, work = 0;
                foreach (CollectionRecord record in gc.records)
                    if (record.kind.Equals(kind)) {
                        count++;
                        work += record.work;
                    }
                line += " " + kind + " " + count + " " + work;
            }
            foreach (CollectionRecord record in gc.records)
                promoted.Add(record.promoted);
            return line + " promoted " + promoted + " barrier " + gc.barriers + " remembered " + gc.remembers;
        }
        public string RefcountLine() {
            RefCounting gc = (RefCounting)collector;
            Pair freed = new Pair();
            Pause largest = null;
            foreach (Pause cascade in cascades) {
                freed.Add(cascade.freed);
                if (largest == null || cascade.work > largest.work)
                    largest = cascade;
            }
            string maximum = largest == null ? "max_cascade 0 0 line -"
                                             : "max_cascade " + largest.freed.count + " " + largest.work +
                                                   " line " + largest.line;
            return "refcount increments " + gc.increments + " decrements " + gc.decrements + " cascades " +
                   cascades.Count + " freed " + freed + " " + maximum;
        }
        public List<string> CollectionLines() {
            List<string> lines = new(["collector " + entry.name + " " + entry.type]);
            foreach (CollectionRecord record in collector.records)
                lines.Add(record.number + " line " + record.line + " size " + record.request + " kind " +
                          record.kind + " live " + record.live + " freed " + record.freed + " moved " +
                          record.moved + " promoted " + record.promoted + " stack " + record.stack +
                          " work " + record.work + " before " + record.before[0] + " " + record.before[1] +
                          " after " + record.after[0] + " " + record.after[1]);
            List<Pause> pauses = Pauses();
            PauseStats stats = new PauseStats(pauses);
            lines.Add("totals collections " + stats.collections + " pauses " + stats.count + " work " +
                      stats.work + " freed " + stats.freed + " pause p50 " + stats.p50 + " p90 " + stats.p90 +
                      " max " + stats.maximum);
            string utilization = "utilization " + Heap.Percent(timeline.mutator, timeline.length) + " mmu";
            foreach (int width in config.windows)
                utilization += " " + width + ":" + timeline.Mmu(width);
            lines.Add(utilization);
            if (generational)
                lines.Add(GenerationalLine());
            if (refcount)
                lines.Add(RefcountLine());
            int previous = 0;
            foreach (Checkpoint checkpoint in script.checkpoints) {
                if (!Completed() && failedLine < checkpoint.command.line)
                    lines.Add("phase " + checkpoint.command.label + " out_of_memory");
                else {
                    List<Pause> phase = new();
                    foreach (Pause pause in pauses)
                        if (previous < pause.line && pause.line <= checkpoint.command.line)
                            phase.Add(pause);
                    PauseStats phaseStats = new PauseStats(phase);
                    lines.Add("phase " + checkpoint.command.label + " collections " + phaseStats.collections +
                              " pauses " + phaseStats.count + " work " + phaseStats.work + " freed " +
                              phaseStats.freed + " max_pause " + phaseStats.maximum);
                }
                previous = checkpoint.command.line;
            }
            lines.Add(Completed() ? "status completed"
                                  : "status out_of_memory line " + failedLine + " size " + failedSize);
            return lines;
        }
        public string Summary() {
            PauseStats stats = new PauseStats(Pauses());
            int live = 0, moved = 0, movedObjects = 0, maximumMoves = 0;
            foreach (CollectionRecord record in collector.records) {
                live += record.live.count;
                moved += record.moved.count;
            }
            foreach (HeapObject item in collector.placed)
                if (item.moves > 0) {
                    movedObjects++;
                    maximumMoves = Math.Max(maximumMoves, item.moves);
                }
            string ending = "-,-,-,-";
            if (Completed()) {
                List<FreeBlock> blocks = collector.FreeList();
                ending = Used(collector.objects) + "," + Heap.Total(blocks) + "," + Heap.Largest(blocks) +
                         "," + Fragmentation(blocks);
            }
            return entry.name + "," + entry.type + "," + (Completed() ? "completed" : "out_of_memory") + "," +
                   collector.records.Count + "," + stats.count + "," + live + "," + moved + "," +
                   movedObjects + "," + maximumMoves + "," + stats.freed + "," + stats.work + "," +
                   stats.p50 + "," + stats.p90 + "," + stats.maximum + "," + peak + "," + ending;
        }
        public List<string> LeakLines() {
            List<string> lines = new(["collector " + entry.name]);
            foreach (List<string> report in ((RefCounting)collector).reports)
                lines.AddRange(report);
            if (!Completed())
                lines.Add("status out_of_memory");
            return lines;
        }
    }
    static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Config config = Mutator.ReadConfig();
        Script script = new Script(Mutator.Lines("mutator.txt"));
        List<Run> runs = new();
        List<List<string>> collectionBlocks = new(), leakBlocks = new(), mapBlocks = new();
        List<string> summaries = new(
            ["collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work," +
             "p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation"]);
        foreach (CollectorEntry entry in config.collectors) {
            Run run = new Run(entry, config, script);
            run.Simulate();
            runs.Add(run);
            collectionBlocks.Add(run.CollectionLines());
            summaries.Add(run.Summary());
            if (run.refcount)
                leakBlocks.Add(run.LeakLines());
        }
        for (int i = 0; i < script.checkpoints.Count; i++) {
            Checkpoint checkpoint = script.checkpoints[i];
            foreach (Run run in runs) {
                List<string> block = new(["checkpoint " + checkpoint.command.label + " line " +
                                          checkpoint.command.line + " collector " + run.entry.name]);
                if (i < run.observations.Count)
                    block.AddRange(run.observations[i]);
                else
                    block.Add("out_of_memory");
                mapBlocks.Add(block);
            }
        }
        Directory.CreateDirectory(Path.Combine("output"));
        Write("mutator.txt", script.Report());
        Write("heap_maps.txt", Join(mapBlocks));
        Write("collections.txt", Join(collectionBlocks));
        Write("summary.csv", summaries);
        Write("leaks.txt", leakBlocks.Count == 0 ? ["none"] : Join(leakBlocks));
    }
}
