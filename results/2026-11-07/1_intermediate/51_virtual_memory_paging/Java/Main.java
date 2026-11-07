import java.io.*;
import java.util.*;

public class Main {
    static final List<String> POLICIES = List.of("FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK",
                                                 "ECLOCK", "WSCLOCK", "RANDOM", "OPT");
    static final List<String> output = new ArrayList<>();
    static String hex(int value) {
        return "0x" + Integer.toHexString(value).toUpperCase(Locale.ROOT);
    }
    static int address(String s) {
        return Integer.parseInt(s.substring(2), 16);
    }
    static String decimal(long value) {
        return value / 100 + "." + String.format(Locale.ROOT, "%02d", value % 100);
    }
    static String ratio(long x, long y) {
        return decimal(y == 0 ? 0 : x * 10000 / y) + "%";
    }
    static class Config {
        int page = 256, frames = 4, tlb = 4, sets = 1, tick = 0, tau = 8;
        long seed = 1;
        String policy = "FIFO", scope = "GLOBAL", asid = "OFF";
        Config copy() {
            Config c = new Config();
            c.page = page;
            c.frames = frames;
            c.tlb = tlb;
            c.sets = sets;
            c.tick = tick;
            c.tau = tau;
            c.seed = seed;
            c.policy = policy;
            c.scope = scope;
            c.asid = asid;
            return c;
        }
        String description() {
            return "SYSTEM page=" + page + " frames=" + frames + " tlb=" + tlb + " sets=" + sets +
                " policy=" + policy + " scope=" + scope + " asid=" + asid + " tick=" + tick +
                " tau=" + tau + " seed=" + seed;
        }
    }
    static class CommandError extends RuntimeException {
        CommandError(String s) {
            super(s);
        }
    }
    static Config settings(String[] tokens) {
        Config c = new Config();
        Set<String> seen = new HashSet<>();
        for (int i = 1; i < tokens.length; i++) {
            String[] pair = tokens[i].split("=");
            String key = pair[0], value = pair[1];
            if (!List.of("page", "frames", "tlb", "sets", "policy", "scope", "asid", "tick", "tau",
                         "seed")
                     .contains(key))
                throw new CommandError("unknown key " + key);
            if (!seen.add(key))
                throw new CommandError("duplicate key " + key);
            boolean valid;
            if (key.equals("policy")) {
                valid = POLICIES.contains(value);
                if (valid)
                    c.policy = value;
            } else if (key.equals("scope")) {
                valid = List.of("GLOBAL", "LOCAL").contains(value);
                if (valid)
                    c.scope = value;
            } else if (key.equals("asid")) {
                valid = List.of("ON", "OFF").contains(value);
                if (valid)
                    c.asid = value;
            } else {
                long n = Long.parseLong(value);
                valid = switch (key) {
                    case "page" -> n >= 16 && n <= 4096 && (n & (n - 1)) == 0;
                    case "frames" -> n >= 1 && n <= 16;
                    case "tlb", "sets" -> n >= 1 && n <= 8;
                    case "tick" -> n >= 0 && n <= 1000;
                    case "tau" -> n >= 1 && n <= 1000;
                    default -> n >= 1 && n <= 2147483646L;
                };
                if (valid)
                    switch (key) {
                    case "page" -> c.page = (int)n;
                    case "frames" -> c.frames = (int)n;
                    case "tlb" -> c.tlb = (int)n;
                    case "sets" -> c.sets = (int)n;
                    case "tick" -> c.tick = (int)n;
                    case "tau" -> c.tau = (int)n;
                    case "seed" -> c.seed = n;
                    }
            }
            if (!valid)
                throw new CommandError("invalid " + key);
        }
        if (c.tlb % c.sets != 0)
            throw new CommandError("invalid sets");
        return c;
    }
    static class Page {
        final int pid, number;
        int frame = -1, slot = -1, R, M, load, last, uses, age, references;
        boolean ro, locked, ever;
        Page(int pid, int number) {
            this.pid = pid;
            this.number = number;
        }
        String label() {
            return "P" + pid + ":" + number;
        }
    }
    static class Process {
        int pid, accesses, faults, writebacks, segfaults, protfaults, peak, hand;
        boolean exited;
        Page[] pages;
        List<Integer> history = new ArrayList<>();
        Process(int pid, int count) {
            this.pid = pid;
            pages = new Page[count];
            for (int i = 0; i < count; i++)
                pages[i] = new Page(pid, i);
        }
        int resident() {
            return (int)Arrays.stream(pages).filter(p -> p.frame >= 0).count();
        }
    }
    record Access(int pid, String op, int address) {}
    record Log(String kind, int pid, String op, int a, int b) {}
    static class Simulation {
        Config c;
        TreeMap<Integer, Process> processes = new TreeMap<>();
        Page[] frames;
        List<List<Page>> tlb = new ArrayList<>();
        TreeMap<Integer, Page> swap = new TreeMap<>();
        List<Access> future;
        int cursor = -1, time, faults, zero, swapin, tlbhits, writebacks, switches, previous = -1,
            hand;
        long random;
        boolean fixed, trace, silent;
        List<Boolean> faultHistory = new ArrayList<>();
        List<Log> log = new ArrayList<>();
        Simulation(Config c, List<Access> future, boolean silent) {
            this.c = c;
            this.future = future;
            this.silent = silent;
            random = c.seed;
            frames = new Page[c.frames];
            for (int i = 0; i < c.sets; i++)
                tlb.add(new ArrayList<>());
        }
        void emit(String s) {
            if (!silent)
                output.add(s);
        }
        Process process(int pid) {
            Process p = processes.get(pid);
            if (p == null)
                throw new CommandError("unknown process " + pid);
            if (p.exited)
                throw new CommandError("process " + pid + " exited");
            return p;
        }
        int quota(int pid) {
            int index = new ArrayList<>(processes.keySet()).indexOf(pid);
            return c.frames / processes.size() + (index < c.frames % processes.size() ? 1 : 0);
        }
        void declare(int pid, int count) {
            if (fixed)
                throw new CommandError("processes are fixed");
            if (processes.containsKey(pid))
                throw new CommandError("duplicate process " + pid);
            if (count < 1 || count > 256)
                throw new CommandError("invalid page count");
            if (processes.size() >= 8 || c.scope.equals("LOCAL") && processes.size() == c.frames)
                throw new CommandError("too many processes");
            processes.put(pid, new Process(pid, count));
        }
        void invalidate(Page page) {
            for (List<Page> set : tlb)
                set.remove(page);
        }
        void write(Page p) {
            writebacks++;
            processes.get(p.pid).writebacks++;
            p.M = 0;
            if (p.slot < 0) {
                int slot = 0;
                while (swap.containsKey(slot))
                    slot++;
                p.slot = slot;
                swap.put(slot, p);
            }
        }
        int nextUse(Page p) {
            for (int i = cursor + 1; i < future.size(); i++) {
                Access a = future.get(i);
                if (a.pid() == p.pid && a.address() / c.page == p.number)
                    return i;
            }
            return Integer.MAX_VALUE;
        }
        int choose(List<Integer> candidates, Process owner) {
            List<Integer> unlocked = candidates.stream().filter(f -> !frames[f].locked).toList();
            if (!unlocked.isEmpty())
                candidates = new ArrayList<>(unlocked);
            Comparator<Integer> comparator = null;
            switch (c.policy) {
            case "FIFO" -> comparator = Comparator.comparingInt(f -> frames[f].load);
            case "LRU" -> comparator = Comparator.comparingInt(f -> frames[f].last);
            case "LFU" ->
                comparator = Comparator.comparingInt((Integer f) -> frames[f].uses)
                                 .thenComparingInt(f -> frames[f].load);
            case "NRU" ->
                comparator = Comparator.comparingInt((Integer f) -> 2 * frames[f].R + frames[f].M)
                                 .thenComparingInt(f -> f);
            case "AGING" ->
                comparator = Comparator.comparingInt((Integer f) -> frames[f].age)
                                 .thenComparingInt(f -> frames[f].load);
            case "OPT" ->
                comparator = Comparator.comparingInt((Integer f) -> nextUse(frames[f]))
                                 .reversed()
                                 .thenComparingInt(f -> f);
            case "RANDOM" -> {
                random = random * 48271L % 2147483647L;
                return candidates.get((int)(random % candidates.size()));
            }
            }
            if (comparator != null)
                return Collections.min(candidates, comparator);
            int h = c.scope.equals("GLOBAL") ? hand : owner.hand;
            candidates.sort(Comparator.comparingInt(f -> (f - h + c.frames) % c.frames));
            int chosen = -1;
            if (c.policy.equals("CLOCK")) {
                while (chosen < 0)
                    for (int f : candidates) {
                        if (frames[f].R == 0) {
                            chosen = f;
                            break;
                        }
                        frames[f].R = 0;
                    }
            } else if (c.policy.equals("ECLOCK")) {
                while (chosen < 0) {
                    for (int f : candidates)
                        if (frames[f].R == 0 && frames[f].M == 0) {
                            chosen = f;
                            break;
                        }
                    if (chosen >= 0)
                        break;
                    for (int f : candidates) {
                        if (frames[f].R == 0 && frames[f].M == 1) {
                            chosen = f;
                            break;
                        }
                        frames[f].R = 0;
                    }
                }
            } else {
                for (int f : candidates) {
                    Page p = frames[f];
                    if (p.R == 1) {
                        p.R = 0;
                        p.last = time;
                    } else if (time - p.last > c.tau) {
                        if (p.M == 0) {
                            chosen = f;
                            break;
                        }
                        write(p);
                    }
                }
                if (chosen < 0) {
                    for (int f : candidates)
                        if (frames[f].M == 0) {
                            chosen = f;
                            break;
                        }
                    if (chosen < 0)
                        chosen = candidates.get(0);
                }
            }
            if (c.scope.equals("GLOBAL"))
                hand = (chosen + 1) % c.frames;
            else
                owner.hand = (chosen + 1) % c.frames;
            return chosen;
        }
        void access(int pid, String op, int address) {
            fixed = true;
            cursor++;
            Process owner = process(pid);
            if (address >= owner.pages.length * c.page) {
                owner.segfaults++;
                emit("SEGFAULT P" + pid + " " + hex(address));
                return;
            }
            Page p = owner.pages[address / c.page];
            if (op.equals("W") && p.ro) {
                owner.protfaults++;
                emit("PROTFAULT P" + pid + " " + hex(address));
                return;
            }
            time++;
            owner.accesses++;
            boolean switched = previous >= 0 && previous != pid;
            if (switched) {
                switches++;
                if (c.asid.equals("OFF"))
                    for (List<Page> set : tlb)
                        set.clear();
            }
            previous = pid;
            List<Page> set = tlb.get(p.number % c.sets);
            boolean hit = set.remove(p), fault = false;
            String result;
            if (hit) {
                tlbhits++;
                result = "TLBHIT";
            } else if (p.frame >= 0)
                result = "HIT";
            else {
                fault = true;
                faults++;
                owner.faults++;
                if (p.slot >= 0) {
                    swapin++;
                    result = "FAULT SWAPIN";
                } else {
                    zero++;
                    result = "FAULT ZERO";
                }
                int frame = -1;
                boolean mayUseFree = c.scope.equals("GLOBAL") || owner.resident() < quota(pid);
                if (mayUseFree)
                    for (int i = 0; i < frames.length; i++)
                        if (frames[i] == null) {
                            frame = i;
                            break;
                        }
                if (frame < 0) {
                    List<Integer> candidates = new ArrayList<>();
                    for (int i = 0; i < frames.length; i++)
                        if (frames[i] != null && (c.scope.equals("GLOBAL") || frames[i].pid == pid))
                            candidates.add(i);
                    frame = choose(candidates, owner);
                    Page victim = frames[frame];
                    result += " evict=" + victim.label();
                    invalidate(victim);
                    if (victim.M == 1) {
                        write(victim);
                        result += " writeback";
                    }
                    victim.frame = -1;
                }
                frames[frame] = p;
                p.frame = frame;
                p.load = time;
                p.uses = 0;
                p.M = 0;
                p.age = 0;
                owner.peak = Math.max(owner.peak, owner.resident());
            }
            if (set.size() == c.tlb / c.sets)
                set.remove(0);
            set.add(p);
            p.R = 1;
            if (op.equals("W"))
                p.M = 1;
            p.last = time;
            p.uses++;
            p.ever = true;
            p.references++;
            owner.history.add(p.number);
            faultHistory.add(fault);
            log.add(new Log("ACCESS", pid, op, address, 0));
            boolean interrupt = c.tick > 0 && time % c.tick == 0;
            if (interrupt)
                for (Page page : frames)
                    if (page != null) {
                        page.age = page.age / 2 + 128 * page.R;
                        page.R = 0;
                    }
            if (trace) {
                emit("t=" + time + " P" + pid + " " + op + " " + hex(address) +
                     " page=" + p.number + " frame=" + p.frame +
                     " phys=" + hex(p.frame * c.page + address % c.page) + " " + result +
                     (switched ? " switch" : ""));
                if (interrupt)
                    emit("t=" + time + " tick");
            }
        }
        void exit(int pid) {
            Process p = process(pid);
            int count = 0, slots = 0;
            for (Page page : p.pages) {
                if (page.frame >= 0) {
                    frames[page.frame] = null;
                    page.frame = -1;
                    count++;
                }
                invalidate(page);
                if (page.slot >= 0) {
                    swap.remove(page.slot);
                    page.slot = -1;
                    slots++;
                }
            }
            p.exited = true;
            log.add(new Log("EXIT", pid, "", 0, 0));
            emit("EXIT P" + pid + " freed=" + count + " slots=" + slots);
        }
        void attributes(String cmd, int pid, int first, int last, String protection) {
            Process p = process(pid);
            if (first > last || last >= p.pages.length)
                throw new CommandError("invalid page range");
            for (int i = first; i <= last; i++) {
                if (cmd.equals("PROTECT"))
                    p.pages[i].ro = protection.equals("RO");
                else
                    p.pages[i].locked = cmd.equals("LOCK");
            }
            if (!cmd.equals("PROTECT"))
                log.add(new Log(cmd, pid, "", first, last));
        }
        void clean() {
            int count = 0;
            for (Page p : frames)
                if (p != null && p.M == 1) {
                    write(p);
                    count++;
                }
            log.add(new Log("CLEAN", 0, "", 0, 0));
            emit("CLEAN written=" + count);
        }
        Simulation rerun(String policy, int count) {
            Config config = c.copy();
            config.policy = policy;
            config.frames = count;
            List<Access> references = new ArrayList<>();
            for (Log e : log)
                if (e.kind().equals("ACCESS"))
                    references.add(new Access(e.pid(), e.op(), e.a()));
            Simulation replay = new Simulation(config, references, true);
            for (Process p : processes.values())
                replay.declare(p.pid, p.pages.length);
            for (Log e : log)
                switch (e.kind()) {
                case "ACCESS" -> replay.access(e.pid(), e.op(), e.a());
                case "EXIT" -> replay.exit(e.pid());
                case "CLEAN" -> replay.clean();
                default -> replay.attributes(e.kind(), e.pid(), e.a(), e.b(), "");
                }
            return replay;
        }
        void summary() {
            emit("SUMMARY policy=" + c.policy + " scope=" + c.scope + " time=" + time);
            int seg = processes.values().stream().mapToInt(p -> p.segfaults).sum();
            int prot = processes.values().stream().mapToInt(p -> p.protfaults).sum();
            emit("total faults=" + faults + " zero=" + zero + " swapin=" + swapin +
                 " faultrate=" + ratio(faults, time) + " tlbhits=" + tlbhits +
                 " tlbrate=" + ratio(tlbhits, time) + " writebacks=" + writebacks +
                 " switches=" + switches + " segfaults=" + seg + " protfaults=" + prot);
            for (Process p : processes.values())
                emit("P" + p.pid + " accesses=" + p.accesses + " faults=" + p.faults +
                     " writebacks=" + p.writebacks + " segfaults=" + p.segfaults +
                     " protfaults=" + p.protfaults + " resident=" + p.resident() +
                     " peak=" + p.peak + (c.scope.equals("LOCAL") ? " quota=" + quota(p.pid) : "") +
                     (p.exited ? " exited" : ""));
        }
        void frameDump() {
            int used = 0;
            for (Page p : frames)
                if (p != null)
                    used++;
            emit("FRAMES used=" + used + "/" + c.frames);
            for (int i = 0; i < frames.length; i++) {
                Page p = frames[i];
                emit(p == null ? i + " free"
                               : i + " " + p.label() + " R=" + p.R + " M=" + p.M +
                                     " load=" + p.load + " last=" + p.last + " uses=" + p.uses +
                                     " age=" + p.age + (p.locked ? " locked" : ""));
            }
            if (List.of("CLOCK", "ECLOCK", "WSCLOCK").contains(c.policy)) {
                if (c.scope.equals("GLOBAL"))
                    emit("hand=" + hand);
                else {
                    StringBuilder text = new StringBuilder("hand");
                    for (Process p : processes.values())
                        text.append(" P").append(p.pid).append('=').append(p.hand);
                    emit(text.toString());
                }
            }
        }
        void pageTable(int pid) {
            Process p = process(pid);
            emit("PAGETABLE P" + pid + " pages=" + p.pages.length + " resident=" + p.resident());
            for (Page page : p.pages)
                if (page.ever) {
                    String info = page.frame >= 0
                                      ? "frame=" + page.frame + " R=" + page.R + " M=" + page.M
                                  : page.slot >= 0 ? "swap=" + page.slot
                                                   : "zero";
                    emit(page.number + " " + info + (page.ro ? " RO" : "") +
                         (page.locked ? " locked" : ""));
                }
        }
        void tlbDump() {
            int used = tlb.stream().mapToInt(List::size).sum();
            emit("TLB used=" + used + "/" + c.tlb + " sets=" + c.sets);
            for (int i = 0; i < tlb.size(); i++) {
                StringBuilder text = new StringBuilder("set " + i + ":");
                List<Page> set = tlb.get(i);
                for (int j = set.size() - 1; j >= 0; j--)
                    text.append(' ')
                        .append(set.get(j).label())
                        .append("->")
                        .append(set.get(j).frame);
                emit(text.toString());
            }
        }
        void compare() {
            emit("COMPARE accesses=" + time + " frames=" + c.frames);
            Map<String, Simulation> results = new HashMap<>();
            for (String policy : POLICIES) {
                Simulation r = rerun(policy, c.frames);
                results.put(policy, r);
                emit(policy + " faults=" + r.faults + " writebacks=" + r.writebacks +
                     " tlbhits=" + r.tlbhits);
            }
            List<String> ranking = new ArrayList<>(POLICIES);
            ranking.sort(Comparator.comparingInt((String p) -> results.get(p).faults)
                             .thenComparingInt(p -> results.get(p).writebacks));
            emit("ranking " + String.join(" ", ranking));
        }
        void execute(String[] t) {
            String cmd = t[0];
            if (Character.isDigit(cmd.charAt(0))) {
                access(Integer.parseInt(cmd), t[1], address(t[2]));
                return;
            }
            switch (cmd) {
            case "PROCESS" -> declare(Integer.parseInt(t[1]), Integer.parseInt(t[2]));
            case "EXIT" -> exit(Integer.parseInt(t[1]));
            case "PROTECT", "LOCK", "UNLOCK" ->
                attributes(cmd, Integer.parseInt(t[1]), Integer.parseInt(t[2]),
                           Integer.parseInt(t[3]), t.length > 4 ? t[4] : "");
            case "TRACE" -> trace = t[1].equals("ON");
            case "SUMMARY" -> summary();
            case "FRAMES" -> frameDump();
            case "PAGETABLE" -> pageTable(Integer.parseInt(t[1]));
            case "TLB" -> tlbDump();
            case "SWAP" -> {
                emit("SWAP used=" + swap.size());
                for (Map.Entry<Integer, Page> entry : swap.entrySet())
                    emit(entry.getKey() + " " + entry.getValue().label());
            }
            case "CLEAN" -> clean();
            case "COMPARE" -> compare();
            case "CURVE" -> {
                String policy = t[1];
                int lo = Integer.parseInt(t[2]), hi = Integer.parseInt(t[3]);
                if (!POLICIES.contains(policy))
                    throw new CommandError("unknown policy");
                if (lo < 1 || lo > hi || hi > 16 ||
                    c.scope.equals("LOCAL") && lo < processes.size())
                    throw new CommandError("invalid frame range");
                emit("CURVE " + policy + " frames=" + lo + ".." + hi);
                int previous = Integer.MAX_VALUE;
                for (int f = lo; f <= hi; f++) {
                    int value = rerun(policy, f).faults;
                    emit("F=" + f + " faults=" + value + (value > previous ? " ANOMALY" : ""));
                    previous = value;
                }
            }
            case "EAT" -> {
                long total = Long.parseLong(t[1]) * time +
                             Long.parseLong(t[2]) * (2L * time - tlbhits) +
                             Long.parseLong(t[3]) * (swapin + writebacks);
                emit(time == 0 ? "EAT accesses=0"
                               : "EAT accesses=" + time + " total=" + total +
                                     " average=" + decimal(total * 100 / time));
            }
            case "TIMELINE" -> {
                int w = Integer.parseInt(t[1]);
                if (w < 1)
                    throw new CommandError("invalid window");
                StringBuilder text = new StringBuilder("TIMELINE window=" + w);
                for (int i = 0; i < faultHistory.size(); i += w) {
                    int count = 0;
                    for (int j = i; j < Math.min(i + w, faultHistory.size()); j++)
                        if (faultHistory.get(j))
                            count++;
                    text.append(' ').append(count);
                }
                emit(text.toString());
            }
            case "WSET" -> {
                int pid = Integer.parseInt(t[1]);
                Process p = process(pid);
                int w = Integer.parseInt(t[2]);
                if (w < 1)
                    throw new CommandError("invalid window");
                TreeSet<Integer> pages = new TreeSet<>(
                    p.history.subList(Math.max(0, p.history.size() - w), p.history.size()));
                StringBuilder text =
                    new StringBuilder("WSET P" + pid + " window=" + w + " size=" + pages.size());
                for (int page : pages)
                    text.append(' ').append(page);
                emit(text.toString());
            }
            case "HOT" -> {
                int pid = Integer.parseInt(t[1]);
                Process p = process(pid);
                int k = Integer.parseInt(t[2]);
                if (k < 1)
                    throw new CommandError("invalid count");
                List<Page> pages = new ArrayList<>(
                    Arrays.stream(p.pages).filter(page -> page.references > 0).toList());
                pages.sort(Comparator.comparingInt((Page page) -> page.references)
                               .reversed()
                               .thenComparingInt(page -> page.number));
                StringBuilder text = new StringBuilder("HOT P" + pid);
                for (int i = 0; i < Math.min(k, pages.size()); i++)
                    text.append(' ')
                        .append(pages.get(i).number)
                        .append(':')
                        .append(pages.get(i).references);
                emit(text.toString());
            }
            }
        }
    }
    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(input.readLine());
        List<String[]> commands = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            String[] t = input.readLine().split(" ");
            if (t[0].equals("LOOP")) {
                int start = address(t[3]), interval = Integer.parseInt(t[4]),
                    length = Integer.parseInt(t[5]), repeats = Integer.parseInt(t[6]);
                for (int r = 0; r < repeats; r++)
                    for (int j = 0; j < length; j++)
                        commands.add(new String[] {t[1], t[2], hex(start + j * interval)});
            } else if (t[0].equals("RAND")) {
                int lo = address(t[2]), hi = address(t[3]), count = Integer.parseInt(t[4]),
                    rate = Integer.parseInt(t[6]);
                long x = Long.parseLong(t[5]);
                for (int j = 0; j < count; j++) {
                    x = x * 48271L % 2147483647L;
                    int addr = lo + (int)(x % (hi - lo));
                    x = x * 48271L % 2147483647L;
                    commands.add(new String[] {t[1], x % 100 < rate ? "W" : "R", hex(addr)});
                }
            } else
                commands.add(t);
        }
        Simulation simulation = null;
        for (int i = 0; i < commands.size(); i++) {
            String[] t = commands.get(i);
            try {
                if (t[0].equals("SYSTEM")) {
                    simulation = null;
                    Config c = settings(t);
                    List<Access> future = new ArrayList<>();
                    for (int j = i + 1; j < commands.size() && !commands.get(j)[0].equals("SYSTEM");
                         j++) {
                        String[] line = commands.get(j);
                        if (Character.isDigit(line[0].charAt(0)))
                            future.add(
                                new Access(Integer.parseInt(line[0]), line[1], address(line[2])));
                    }
                    simulation = new Simulation(c, future, false);
                    output.add(c.description());
                } else if (simulation == null)
                    output.add("ERROR no system");
                else
                    simulation.execute(t);
            } catch (CommandError e) {
                output.add("ERROR " + e.getMessage());
            }
        }
        if (!output.isEmpty())
            System.out.print(String.join("\n", output) + "\n");
    }
}
