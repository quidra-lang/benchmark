import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Main {
    record Checkpoint(Command command, int stack, Pair live, Pair allocated, Pair phase, Pair survivors,
                      Set<Integer> reachable) {}
    record Pause(int line, int work, Pair freed, boolean collection) {}
    record Segment(int start, int length, boolean mutator, int before) {}
    static int used(Collection<HeapObject> objects) {
        int words = 0;
        for (HeapObject object : objects)
            words += object.size;
        return words;
    }
    static Pair pair(Collection<HeapObject> objects) {
        Pair pair = new Pair();
        for (HeapObject object : objects)
            pair.add(object);
        return pair;
    }
    static Set<Integer> reachable(List<Integer> roots, List<HeapObject> objects) {
        Set<Integer> reached = new HashSet<>();
        Deque<Integer> stack = new ArrayDeque<>();
        for (int root : roots)
            if (root != 0)
                stack.push(root);
        while (!stack.isEmpty()) {
            int number = stack.pop();
            if (!reached.add(number))
                continue;
            for (int child : objects.get(number - 1).fields)
                if (child != 0)
                    stack.push(child);
        }
        return reached;
    }
    static String fragmentation(List<FreeBlock> blocks) {
        int total = Heap.total(blocks);
        return Heap.percent(total - Heap.largest(blocks), total);
    }
    static List<String> join(List<List<String>> blocks) {
        List<String> lines = new ArrayList<>();
        for (List<String> block : blocks) {
            if (!lines.isEmpty())
                lines.add("");
            lines.addAll(block);
        }
        return lines;
    }
    static final class Script {
        final int lineCount;
        final List<Command> commands = new ArrayList<>();
        final List<String> errors = new ArrayList<>();
        final Map<String, Integer> counts = new LinkedHashMap<>();
        final List<Integer> roots = new ArrayList<>();
        final List<HeapObject> objects = new ArrayList<>();
        final List<Integer> births = new ArrayList<>(), deaths = new ArrayList<>(),
                            lifetimes = new ArrayList<>();
        final List<Checkpoint> checkpoints = new ArrayList<>();
        final Set<String> labels = new HashSet<>();
        Set<Integer> alive = new HashSet<>();
        Pair live = new Pair(), peak = new Pair();
        int clock, peakLine, phaseStart;
        Script(List<String> lines) {
            lineCount = lines.size();
            for (String name : Mutator.NAMES)
                counts.put(name, 0);
            for (int i = 0; i < lines.size(); i++) {
                Parsed parsed = Mutator.parse(i + 1, lines.get(i));
                String reason = parsed.error();
                if (reason.isEmpty())
                    reason = check(parsed.command());
                if (reason.isEmpty())
                    run(parsed.command());
                else
                    errors.add("error line " + (i + 1) + " " + reason);
            }
        }
        String check(Command command) {
            String name = command.name;
            int depth = roots.size();
            if (Set.of("ALLOC", "PUSH", "LOAD").contains(name) && depth == 64)
                return "stack";
            if (Set.of("LOAD", "SET", "OVERWRITE").contains(name) && command.slot >= depth)
                return "stack";
            if (Set.of("PUSH", "SET", "OVERWRITE").contains(name) && command.source >= depth)
                return "stack";
            if (name.equals("POP") && command.count > depth)
                return "stack";
            if (name.equals("LOAD") || name.equals("SET")) {
                int number = roots.get(command.slot);
                if (number == 0)
                    return "null";
                if (command.field >= objects.get(number - 1).fields.length)
                    return "field";
            }
            if (name.equals("CHECKPOINT") && labels.contains(command.label))
                return "duplicate";
            return "";
        }
        int value(int source) {
            return source < 0 ? 0 : roots.get(source);
        }
        void execute(Command command) {
            String name = command.name;
            if (name.equals("ALLOC")) {
                HeapObject object = new HeapObject(objects.size() + 1, command.pointers, command.data);
                objects.add(object);
                births.add(clock);
                deaths.add(0);
                lifetimes.add(-1);
                clock += object.size;
                roots.add(object.number);
            } else if (name.equals("PUSH"))
                roots.add(value(command.source));
            else if (name.equals("LOAD"))
                roots.add(objects.get(roots.get(command.slot) - 1).fields[command.field]);
            else if (name.equals("POP"))
                for (int i = 0; i < command.count; i++)
                    roots.removeLast();
            else if (name.equals("SET"))
                objects.get(roots.get(command.slot) - 1).fields[command.field] = value(command.source);
            else if (name.equals("OVERWRITE"))
                roots.set(command.slot, value(command.source));
        }
        void run(Command command) {
            commands.add(command);
            counts.put(command.name, counts.get(command.name) + 1);
            execute(command);
            Set<Integer> reached = reachable(roots, objects);
            for (int number : alive)
                if (!reached.contains(number)) {
                    deaths.set(number - 1, command.line);
                    lifetimes.set(number - 1, clock - births.get(number - 1) - objects.get(number - 1).size);
                }
            alive = reached;
            live = new Pair();
            for (int number : reached)
                live.add(objects.get(number - 1));
            if (peakLine == 0 || live.words > peak.words) {
                peak = live;
                peakLine = command.line;
            }
            if (command.name.equals("CHECKPOINT")) {
                labels.add(command.label);
                Pair allocated = pair(objects), phase = new Pair(), survivors = new Pair();
                for (int i = phaseStart; i < objects.size(); i++) {
                    HeapObject object = objects.get(i);
                    phase.add(object);
                    if (reached.contains(object.number))
                        survivors.add(object);
                }
                phaseStart = objects.size();
                checkpoints.add(
                    new Checkpoint(command, roots.size(), live, allocated, phase, survivors, reached));
            }
        }
        List<String> report() {
            List<String> lines = new ArrayList<>(List.of("script lines " + lineCount + " valid " +
                                                         commands.size() + " errors " + errors.size()));
            lines.addAll(errors);
            String countLine = "commands";
            for (String name : Mutator.NAMES)
                countLine += " " + name + " " + counts.get(name);
            lines.add(countLine);
            List<Integer> sizes = new ArrayList<>();
            for (HeapObject object : objects)
                sizes.add(object.size);
            lines.add("allocated objects " + objects.size() + " words " + clock + " sizes " +
                      Heap.classes(sizes));
            lines.add("peak_live objects " + peak.count + " words " + peak.words + " line " + peakLine);
            lines.add("end_live objects " + live.count + " words " + live.words + " stack " + roots.size());
            int[] bins = new int[6], limits = {63, 255, 1023, 4095};
            for (int lifetime : lifetimes) {
                if (lifetime < 0)
                    bins[5]++;
                else {
                    int index = 0;
                    while (index < limits.length && lifetime > limits[index])
                        index++;
                    bins[index]++;
                }
            }
            lines.add("lifetimes 0-63 " + bins[0] + " 64-255 " + bins[1] + " 256-1023 " + bins[2] +
                      " 1024-4095 " + bins[3] + " 4096+ " + bins[4] + " live " + bins[5]);
            for (Checkpoint checkpoint : checkpoints)
                lines.add("checkpoint " + checkpoint.command.label + " line " + checkpoint.command.line +
                          " stack " + checkpoint.stack + " live " + checkpoint.live + " allocated " +
                          checkpoint.allocated + " phase " + checkpoint.phase + " survivors " +
                          checkpoint.survivors + " survival " +
                          Heap.percent(checkpoint.survivors.words, checkpoint.phase.words));
            return lines;
        }
    }
    static boolean onCycle(int start, Map<Integer, HeapObject> members) {
        Set<Integer> seen = new HashSet<>();
        Deque<Integer> stack = new ArrayDeque<>();
        for (int child : members.get(start).fields)
            if (members.containsKey(child))
                stack.push(child);
        while (!stack.isEmpty()) {
            int number = stack.pop();
            if (number == start)
                return true;
            if (!seen.add(number))
                continue;
            for (int child : members.get(number).fields)
                if (members.containsKey(child))
                    stack.push(child);
        }
        return false;
    }
    static List<String> leakReport(String title, List<HeapObject> garbage, List<Integer> deaths) {
        Map<Integer, HeapObject> members = new TreeMap<>();
        Map<Integer, List<Integer>> neighbors = new HashMap<>();
        for (HeapObject object : garbage) {
            members.put(object.number, object);
            neighbors.put(object.number, new ArrayList<>());
        }
        for (HeapObject object : garbage)
            for (int child : object.fields)
                if (members.containsKey(child)) {
                    neighbors.get(object.number).add(child);
                    neighbors.get(child).add(object.number);
                }
        List<List<HeapObject>> groups = new ArrayList<>();
        Set<Integer> grouped = new HashSet<>();
        for (int number : members.keySet()) {
            if (!grouped.add(number))
                continue;
            List<HeapObject> group = new ArrayList<>();
            Deque<Integer> stack = new ArrayDeque<>();
            stack.push(number);
            while (!stack.isEmpty()) {
                int current = stack.pop();
                group.add(members.get(current));
                for (int other : neighbors.get(current))
                    if (grouped.add(other))
                        stack.push(other);
            }
            group.sort(Comparator.comparingInt(object -> object.number));
            groups.add(group);
        }
        List<String> lines = new ArrayList<>(List.of(title + " groups " + groups.size() + " objects " +
                                                     garbage.size() + " words " + used(garbage)));
        for (int i = 0; i < groups.size(); i++) {
            List<HeapObject> group = groups.get(i);
            List<String> ids = new ArrayList<>();
            int cycles = 0, died = 0;
            for (HeapObject object : group) {
                boolean cycle = onCycle(object.number, members);
                if (cycle)
                    cycles++;
                died = Math.max(died, deaths.get(object.number - 1));
                ids.add(object.number + (cycle ? "*" : ""));
            }
            lines.add("group " + (i + 1) + " objects " + group.size() + " words " + used(group) + " cycle " +
                      cycles + " died " + died + " ids " + String.join(" ", ids));
        }
        return lines;
    }
    static final class RefCounting extends MarkSweep {
        final List<Integer> deaths;
        final List<HeapObject> released = new ArrayList<>();
        final List<List<String>> reports = new ArrayList<>();
        int increments, decrements;
        RefCounting(int size, List<Integer> deaths) {
            super(size);
            this.deaths = deaths;
        }
        void retain(int number) {
            if (number != 0) {
                lookup(number).count++;
                increments++;
            }
        }
        void release(int number) {
            if (number == 0)
                return;
            HeapObject object = lookup(number);
            decrements++;
            object.count--;
            if (object.count != 0)
                return;
            Deque<HeapObject> pending = new ArrayDeque<>();
            pending.push(object);
            while (!pending.isEmpty()) {
                HeapObject current = pending.pop();
                objects.remove(current);
                released.add(current);
                for (int child : current.fields)
                    if (child != 0) {
                        decrements++;
                        HeapObject target = lookup(child);
                        target.count--;
                        if (target.count == 0)
                            pending.push(target);
                    }
            }
        }
        Pause cascade(int line) {
            if (released.isEmpty())
                return null;
            Pair freed = pair(released);
            int work = 0;
            for (HeapObject object : released)
                work += 1 + object.fields.length;
            released.clear();
            return new Pause(line, work, freed, false);
        }
        void collect(List<Integer> roots, int line, int request) {
            CollectionRecord record =
                new CollectionRecord(records.size() + 1, line, request, "backup", freeList());
            Marking.mark(this, roots, record);
            List<HeapObject> garbage = new ArrayList<>();
            for (HeapObject object : objects)
                if (!object.marked)
                    garbage.add(object);
            reports.add(leakReport("backup " + record.number + " line " + line, garbage, deaths));
            Marking.sweep(this, record);
            for (HeapObject object : garbage)
                for (int child : object.fields)
                    if (child != 0 && lookup(child).marked) {
                        lookup(child).count--;
                        decrements++;
                    }
            record.finish(freeList())
            ;
            records.add(record);
        }
        void finish(Set<Integer> reachable) {
            List<HeapObject> garbage = new ArrayList<>();
            for (HeapObject object : objects)
                if (!reachable.contains(object.number))
                    garbage.add(object);
            reports.add(leakReport("end", garbage, deaths));
        }
    }
    static final class PauseStats {
        final int count, collections, work, freed, maximum;
        final String p50, p90;
        PauseStats(List<Pause> pauses) {
            count = pauses.size();
            List<Integer> works = new ArrayList<>();
            int collections = 0, work = 0, freed = 0;
            for (Pause pause : pauses) {
                works.add(pause.work);
                if (pause.collection)
                    collections++;
                work += pause.work;
                freed += pause.freed.words;
            }
            Collections.sort(works);
            this.collections = collections;
            this.work = work;
            this.freed = freed;
            maximum = works.isEmpty() ? 0 : works.getLast();
            p50 = count == 0 ? "-" : Integer.toString(works.get((50 * count + 99) / 100 - 1));
            p90 = count == 0 ? "-" : Integer.toString(works.get((90 * count + 99) / 100 - 1));
        }
    }
    static final class Timeline {
        final List<Segment> segments = new ArrayList<>();
        int length, mutator;
        void add(boolean mutator, int units) {
            if (units == 0)
                return;
            segments.add(new Segment(length, units, mutator, this.mutator));
            length += units;
            if (mutator)
                this.mutator += units;
        }
        int prefix(int position) {
            int low = 0, high = segments.size();
            while (low + 1 < high) {
                int middle = (low + high) / 2;
                if (segments.get(middle).start <= position)
                    low = middle;
                else
                    high = middle;
            }
            Segment segment = segments.get(low);
            return segment.before + (segment.mutator ? position - segment.start : 0);
        }
        String mmu(int width) {
            if (width > length)
                return "-";
            int minimum = width;
            for (Segment segment : segments)
                for (int begin : new int[] {segment.start, segment.start + segment.length - width})
                    if (begin >= 0 && begin <= length - width)
                        minimum = Math.min(minimum, prefix(begin + width) - prefix(begin));
            return Heap.percent(minimum, width);
        }
    }
    static Collector collector(CollectorEntry entry, Config config, Script script) {
        return switch (entry.type()) {
            case "MARK_SWEEP" -> new MarkSweep(config.heap);
            case "MARK_COMPACT" -> new MarkCompact(config.heap);
            case "COPYING" -> new Copying(config.heap);
            case "GENERATIONAL" -> new Generational(config.heap, entry.young(), entry.age());
            default -> new RefCounting(config.heap, script.deaths);
        };
    }
    static final class Run {
        final CollectorEntry entry;
        final Config config;
        final Script script;
        final Collector collector;
        final boolean refcount, generational;
        final List<Integer> roots = new ArrayList<>();
        final List<Pause> cascades = new ArrayList<>();
        final Timeline timeline = new Timeline();
        final List<List<String>> observations = new ArrayList<>();
        int peak, failedLine, failedSize;
        Run(CollectorEntry entry, Config config, Script script) {
            this.entry = entry;
            this.config = config;
            this.script = script;
            collector = collector(entry, config, script);
            refcount = entry.type().equals("REFCOUNT");
            generational = entry.type().equals("GENERATIONAL");
        }
        boolean completed() {
            return failedLine == 0;
        }
        int value(int source) {
            return source < 0 ? 0 : roots.get(source);
        }
        void retain(int value) {
            if (refcount)
                ((RefCounting)collector).retain(value);
        }
        void release(int value) {
            if (refcount)
                ((RefCounting)collector).release(value);
        }
        void push(int value) {
            retain(value);
            roots.add(value);
        }
        void simulate() {
            for (Command command : script.commands) {
                int before = collector.records.size(), units = 1;
                boolean placed = true;
                if (command.name.equals("ALLOC")) {
                    HeapObject object =
                        new HeapObject(collector.placed.size() + 1, command.pointers, command.data);
                    units = object.size;
                    placed = collector.allocate(object, roots, command.line);
                    if (placed) {
                        push(object.number);
                        peak = Math.max(peak, used(collector.objects));
                    }
                } else
                    execute(command);
                for (CollectionRecord record : collector.records.subList(before, collector.records.size()))
                    timeline.add(false, record.work);
                if (!placed) {
                    failedLine = command.line;
                    failedSize = units;
                    return;
                }
                timeline.add(true, units);
                if (refcount) {
                    Pause cascade = ((RefCounting)collector).cascade(command.line);
                    if (cascade != null) {
                        cascades.add(cascade);
                        timeline.add(false, cascade.work);
                    }
                }
            }
            if (refcount)
                ((RefCounting)collector).finish(script.alive);
        }
        void execute(Command command) {
            String name = command.name;
            if (name.equals("PUSH"))
                push(value(command.source));
            else if (name.equals("LOAD"))
                push(collector.lookup(roots.get(command.slot)).fields[command.field]);
            else if (name.equals("POP"))
                for (int i = 0; i < command.count; i++)
                    release(roots.removeLast());
            else if (name.equals("SET")) {
                int number = roots.get(command.slot), value = value(command.source);
                if (generational)
                    ((Generational)collector).writeBarrier(number, value);
                retain(value);
                HeapObject object = collector.lookup(number);
                int previous = object.fields[command.field];
                object.fields[command.field] = value;
                release(previous);
            } else if (name.equals("OVERWRITE")) {
                int value = value(command.source);
                retain(value);
                int previous = roots.set(command.slot, value);
                release(previous);
            } else
                observations.add(observe(script.checkpoints.get(observations.size())));
        }
        List<String> observe(Checkpoint checkpoint) {
            Pair live = new Pair(), garbage = new Pair();
            int pointers = 0, forward = 0, backward = 0, distance = 0;
            for (HeapObject object : collector.objects) {
                if (!checkpoint.reachable.contains(object.number)) {
                    garbage.add(object);
                    continue;
                }
                live.add(object);
                for (int child : object.fields)
                    if (child != 0) {
                        pointers++;
                        int difference = collector.lookup(child).address - object.address;
                        if (difference > 0)
                            forward++;
                        if (difference < 0)
                            backward++;
                        distance += Math.abs(difference);
                    }
            }
            List<FreeBlock> blocks = collector.freeList();
            List<Integer> lengths = new ArrayList<>();
            for (FreeBlock block : blocks)
                lengths.add(block.length());
            List<String> lines = new ArrayList<>(List.of(
                "heap objects " + pair(collector.objects) + " reachable " + live + " garbage " + garbage,
                "free total " + Heap.total(blocks) + " largest " + Heap.largest(blocks) + " blocks " +
                    blocks.size() + " sizes " + Heap.classes(lengths) + " fragmentation " +
                    fragmentation(blocks),
                "locality pointers " + pointers + " forward " + forward + " backward " + backward +
                    " mean_distance " + (pointers == 0 ? "-" : Heap.dec2(distance, pointers))));
            if (generational) {
                Generational gc = (Generational)collector;
                Pair young = new Pair(), old = new Pair();
                int[] ages = new int[4];
                for (HeapObject object : gc.objects) {
                    if (gc.young(object)) {
                        young.add(object);
                        ages[Math.min(3, object.age)]++;
                    } else
                        old.add(object);
                }
                lines.add("generations young " + young + " old " + old + " remembered " +
                          gc.remembered.size() + " ages 0:" + ages[0] + " 1:" + ages[1] + " 2:" + ages[2] +
                          " 3+:" + ages[3]);
            }
            if (config.maps.contains(checkpoint.command.label)) {
                String map =
                    Heap.map(config.heap, collector.objects, checkpoint.reachable, collector.inactive());
                for (int start = 0; start < map.length(); start += config.width)
                    lines.add(String.format(Locale.ROOT, "%04d", start) + " " +
                              map.substring(start, start + config.width));
            }
            return lines;
        }
        List<Pause> pauses() {
            List<Pause> pauses = new ArrayList<>();
            for (CollectionRecord record : collector.records)
                pauses.add(new Pause(record.line, record.work, record.freed, true));
            pauses.addAll(cascades);
            return pauses;
        }
        String generationalLine() {
            Generational gc = (Generational)collector;
            String line = "generational";
            Pair promoted = new Pair();
            for (String kind : new String[] {"minor", "major", "tenure", "full"}) {
                int count = 0, work = 0;
                for (CollectionRecord record : gc.records)
                    if (record.kind.equals(kind)) {
                        count++;
                        work += record.work;
                    }
                line += " " + kind + " " + count + " " + work;
            }
            for (CollectionRecord record : gc.records)
                promoted.add(record.promoted);
            return line + " promoted " + promoted + " barrier " + gc.barriers + " remembered " + gc.remembers;
        }
        String refcountLine() {
            RefCounting gc = (RefCounting)collector;
            Pair freed = new Pair();
            Pause largest = null;
            for (Pause cascade : cascades) {
                freed.add(cascade.freed);
                if (largest == null || cascade.work > largest.work)
                    largest = cascade;
            }
            String maximum = largest == null ? "max_cascade 0 0 line -"
                                             : "max_cascade " + largest.freed.count + " " + largest.work +
                                                   " line " + largest.line;
            return "refcount increments " + gc.increments + " decrements " + gc.decrements + " cascades " +
                cascades.size() + " freed " + freed + " " + maximum;
        }
        List<String> collectionLines() {
            List<String> lines = new ArrayList<>(List.of("collector " + entry.name() + " " + entry.type()));
            for (CollectionRecord record : collector.records)
                lines.add(record.number + " line " + record.line + " size " + record.request + " kind " +
                          record.kind + " live " + record.live + " freed " + record.freed + " moved " +
                          record.moved + " promoted " + record.promoted + " stack " + record.stack +
                          " work " + record.work + " before " + record.before[0] + " " + record.before[1] +
                          " after " + record.after[0] + " " + record.after[1]);
            List<Pause> pauses = pauses();
            PauseStats stats = new PauseStats(pauses);
            lines.add("totals collections " + stats.collections + " pauses " + stats.count + " work " +
                      stats.work + " freed " + stats.freed + " pause p50 " + stats.p50 + " p90 " + stats.p90 +
                      " max " + stats.maximum);
            String utilization = "utilization " + Heap.percent(timeline.mutator, timeline.length) + " mmu";
            for (int width : config.windows)
                utilization += " " + width + ":" + timeline.mmu(width);
            lines.add(utilization);
            if (generational)
                lines.add(generationalLine());
            if (refcount)
                lines.add(refcountLine());
            int previous = 0;
            for (Checkpoint checkpoint : script.checkpoints) {
                if (!completed() && failedLine < checkpoint.command.line)
                    lines.add("phase " + checkpoint.command.label + " out_of_memory");
                else {
                    List<Pause> phase = new ArrayList<>();
                    for (Pause pause : pauses)
                        if (previous < pause.line && pause.line <= checkpoint.command.line)
                            phase.add(pause);
                    PauseStats phaseStats = new PauseStats(phase);
                    lines.add("phase " + checkpoint.command.label + " collections " + phaseStats.collections +
                              " pauses " + phaseStats.count + " work " + phaseStats.work + " freed " +
                              phaseStats.freed + " max_pause " + phaseStats.maximum);
                }
                previous = checkpoint.command.line;
            }
            lines.add(completed() ? "status completed"
                                  : "status out_of_memory line " + failedLine + " size " + failedSize);
            return lines;
        }
        String summary() {
            PauseStats stats = new PauseStats(pauses());
            int live = 0, moved = 0, movedObjects = 0, maximumMoves = 0;
            for (CollectionRecord record : collector.records) {
                live += record.live.count;
                moved += record.moved.count;
            }
            for (HeapObject object : collector.placed)
                if (object.moves > 0) {
                    movedObjects++;
                    maximumMoves = Math.max(maximumMoves, object.moves);
                }
            String ending = "-,-,-,-";
            if (completed()) {
                List<FreeBlock> blocks = collector.freeList();
                ending = used(collector.objects) + "," + Heap.total(blocks) + "," + Heap.largest(blocks) +
                         "," + fragmentation(blocks);
            }
            return entry.name() + "," + entry.type() + "," + (completed() ? "completed" : "out_of_memory") +
                "," + collector.records.size() + "," + stats.count + "," + live + "," + moved + "," +
                movedObjects + "," + maximumMoves + "," + stats.freed + "," + stats.work + "," + stats.p50 +
                "," + stats.p90 + "," + stats.maximum + "," + peak + "," + ending;
        }
        List<String> leakLines() {
            List<String> lines = new ArrayList<>(List.of("collector " + entry.name()));
            for (List<String> report : ((RefCounting)collector).reports)
                lines.addAll(report);
            if (!completed())
                lines.add("status out_of_memory");
            return lines;
        }
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Config config = Mutator.config();
        Script script = new Script(Mutator.lines("mutator.txt"));
        List<Run> runs = new ArrayList<>();
        List<List<String>> collectionBlocks = new ArrayList<>(), leakBlocks = new ArrayList<>(),
                           mapBlocks = new ArrayList<>();
        List<String> summaries = new ArrayList<>(List.of(
            "collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work," +
            "p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation"));
        for (CollectorEntry entry : config.collectors) {
            Run run = new Run(entry, config, script);
            run.simulate();
            runs.add(run);
            collectionBlocks.add(run.collectionLines());
            summaries.add(run.summary());
            if (run.refcount)
                leakBlocks.add(run.leakLines());
        }
        for (int i = 0; i < script.checkpoints.size(); i++) {
            Checkpoint checkpoint = script.checkpoints.get(i);
            for (Run run : runs) {
                List<String> block =
                    new ArrayList<>(List.of("checkpoint " + checkpoint.command.label + " line " +
                                            checkpoint.command.line + " collector " + run.entry.name()));
                if (i < run.observations.size())
                    block.addAll(run.observations.get(i));
                else
                    block.add("out_of_memory");
                mapBlocks.add(block);
            }
        }
        Files.createDirectories(Path.of("output"));
        write("mutator.txt", script.report());
        write("heap_maps.txt", join(mapBlocks));
        write("collections.txt", join(collectionBlocks));
        write("summary.csv", summaries);
        write("leaks.txt", leakBlocks.isEmpty() ? List.of("none") : join(leakBlocks));
    }
}
