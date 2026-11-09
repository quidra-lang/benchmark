import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

public class Main {
    static final int UNIT = 8;
    static final int HEADER = 8;
    static final int MIN_BLOCK = 16;
    static final int MIN_BUDDY_BLOCK = 32;
    static final int MAX_HEAP = 65536;
    static final int UNINITIALIZED = -1;
    static final long RANDOM_MODULUS = 2147483647L;
    static final long RANDOM_MULTIPLIER = 48271L;
    static final List<String> MODES = List.of("FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY");
    static final List<String> COUNTERS =
        List.of("allocs", "frees", "reallocs", "moves", "failures", "collected");

    static int number(String text) {
        return Integer.parseInt(text);
    }
    static boolean powerOfTwo(int n) {
        return n > 0 && (n & (n - 1)) == 0;
    }
    static int sizeClass(int n) {
        return 31 - Integer.numberOfLeadingZeros(n);
    }
    static int fragmentationPercent(int free, int largest) {
        return free == 0 ? 0 : (free - largest) * 100 / free;
    }
    static long random(long state) {
        return RANDOM_MULTIPLIER * state % RANDOM_MODULUS;
    }

    static final class CommandError extends RuntimeException {
        CommandError(String text) {
            super(text);
        }
    }

    static final class Block {
        int start;
        int size;
        int requested;
        int stamp;
        boolean used;
        String owner;
        int[] contents = new int[0];

        Block(int start, int size) {
            this.start = start;
            this.size = size;
        }
        int end() {
            return start + size;
        }
        int payload() {
            return start + HEADER;
        }
        String area() {
            return start + "+" + size;
        }
        String mapUnits() {
            int count = size / UNIT - 1;
            StringBuilder result = new StringBuilder();
            result.append(used ? 'H' : 'F');
            for (int i = 0; i < count; ++i) {
                result.append(!used ? '.' : i * UNIT < requested ? '#' : '-');
            }
            return result.toString();
        }
    }

    record Choice(int index, int place, int first, int second) {}
    record Coalesced(Block block, int merges) {}
    record Moved(Block block, int from) {}
    record Packed(List<Moved> moved, int used) {}

    static final class Heap {
        String mode;
        int size;
        int rover;
        int registrations;
        ArrayList<Block> blocks = new ArrayList<>();

        Heap(String mode, int size) {
            this.mode = mode;
            this.size = size;
            blocks.add(register(new Block(0, size)));
        }
        Block register(Block block) {
            block.stamp = ++registrations;
            return block;
        }
        boolean isBuddy() {
            return mode.equals("BUDDY");
        }
        int requiredLength(int request) {
            int length = (request + UNIT - 1) / UNIT * UNIT + HEADER;
            if (!isBuddy())
                return length;
            int power = MIN_BUDDY_BLOCK;
            while (power < length)
                power *= 2;
            return power;
        }
        int locate(int address) {
            int i = 0;
            while (blocks.get(i).end() <= address)
                ++i;
            return i;
        }
        List<Block> usedBlocks() {
            return blocks.stream().filter(b -> b.used).toList();
        }
        List<Block> freeBlocks() {
            return blocks.stream().filter(b -> !b.used).toList();
        }
        int usedTotal() {
            return usedBlocks().stream().mapToInt(b -> b.size).sum();
        }
        int fragmentation() {
            List<Block> free = freeBlocks();
            int total = free.stream().mapToInt(b -> b.size).sum();
            int largest = free.stream().mapToInt(b -> b.size).max().orElse(0);
            return fragmentationPercent(total, largest);
        }
        int placement(Block block, int alignment) {
            int p = (block.start + HEADER + alignment - 1) / alignment * alignment - HEADER;
            if (p > block.start && p - block.start < MIN_BLOCK)
                p += alignment;
            return p;
        }
        int[] rank(int index, int roverIndex) {
            Block block = blocks.get(index);
            return switch (mode) {
                case "NEXT" -> new int[] {(index - roverIndex + blocks.size()) % blocks.size(), 0};
                case "BEST", "BUDDY" -> new int[] {block.size, block.start};
                case "WORST" -> new int[] {-block.size, block.start};
                case "SEGFIT" -> new int[] {sizeClass(block.size), -block.stamp};
                default -> new int[] {block.start, 0};
            };
        }
        Choice choose(int length, int alignment) {
            int roverIndex = locate(rover);
            Choice selected = null;
            for (int index = 0; index < blocks.size(); ++index) {
                Block block = blocks.get(index);
                if (block.used)
                    continue;
                int place = placement(block, alignment);
                if (place + length > block.end())
                    continue;
                int[] rank = rank(index, roverIndex);
                if (selected == null || rank[0] < selected.first() ||
                    (rank[0] == selected.first() && rank[1] < selected.second())) {
                    selected = new Choice(index, place, rank[0], rank[1]);
                }
            }
            return selected;
        }
        Block allocate(int length, int alignment) {
            Choice choice = choose(length, alignment);
            if (choice == null)
                return null;
            Block block = isBuddy() ? halve(choice.index(), length)
                                    : carve(choice.index(), choice.place(), length);
            block.used = true;
            if (mode.equals("NEXT"))
                rover = block.end() == size ? 0 : block.end();
            return block;
        }
        Block carve(int index, int place, int length) {
            Block old = blocks.get(index);
            List<Block> parts = new ArrayList<>();
            if (place > old.start)
                parts.add(register(new Block(old.start, place - old.start)));
            Block used = new Block(place, old.end() - place);
            parts.add(used);
            if (used.size - length >= MIN_BLOCK) {
                parts.add(register(new Block(place + length, used.size - length)));
                used.size = length;
            }
            blocks.remove(index);
            blocks.addAll(index, parts);
            return used;
        }
        Block halve(int index, int length) {
            Block block = blocks.get(index);
            while (block.size > length) {
                block.size /= 2;
                blocks.add(index + 1, register(new Block(block.end(), block.size)));
            }
            return block;
        }
        void mergeNext(int index) {
            blocks.get(index).size += blocks.remove(index + 1).size;
        }
        Coalesced coalesce(int index) {
            int merges = 0;
            if (isBuddy()) {
                while (blocks.get(index).size < size) {
                    Block block = blocks.get(index);
                    int partner = block.start % (2 * block.size) == 0 ? index + 1 : index - 1;
                    if (partner < 0 || partner >= blocks.size())
                        break;
                    Block other = blocks.get(partner);
                    if (other.used || other.size != block.size)
                        break;
                    index = Math.min(index, partner);
                    mergeNext(index);
                    ++merges;
                }
            } else {
                if (index + 1 < blocks.size() && !blocks.get(index + 1).used) {
                    mergeNext(index);
                    ++merges;
                }
                if (index > 0 && !blocks.get(index - 1).used) {
                    --index;
                    mergeNext(index);
                    ++merges;
                }
            }
            return new Coalesced(register(blocks.get(index)), merges);
        }
        Coalesced release(Block block) {
            block.used = false;
            block.owner = null;
            block.requested = 0;
            block.contents = new int[0];
            return coalesce(blocks.indexOf(block));
        }
        String shrink(int index, int length) {
            Block block = blocks.get(index);
            if (isBuddy()) {
                if (block.size == length)
                    return "kept";
                halve(index, length);
                return "shrunk";
            }
            if (block.size - length < MIN_BLOCK)
                return "kept";
            blocks.add(index + 1, new Block(block.start + length, block.size - length));
            block.size = length;
            coalesce(index + 1);
            return "shrunk";
        }
        String growIntoNext(int index, int length) {
            if (index + 1 == blocks.size() || blocks.get(index + 1).used)
                return null;
            Block block = blocks.get(index);
            int total = block.size + blocks.get(index + 1).size;
            if (total < length)
                return null;
            blocks.remove(index + 1);
            if (total - length >= MIN_BLOCK) {
                block.size = length;
                blocks.add(index + 1, register(new Block(block.end(), total - length)));
            } else
                block.size = total;
            return "grown";
        }
        String growBuddy(int index, int length) {
            Block block = blocks.get(index);
            int oldSize = block.size;
            int last = index;
            while (oldSize < length) {
                ++last;
                if (block.start % (2 * oldSize) != 0 || last == blocks.size())
                    return null;
                Block partner = blocks.get(last);
                if (partner.used || partner.size != oldSize)
                    return null;
                oldSize *= 2;
            }
            blocks.subList(index + 1, last + 1).clear();
            block.size = length;
            return "grown";
        }
        String resize(Block block, int length) {
            int index = blocks.indexOf(block);
            if (length <= block.size)
                return shrink(index, length);
            return isBuddy() ? growBuddy(index, length) : growIntoNext(index, length);
        }
        Block extend(int amount) {
            blocks.add(new Block(size, amount));
            size += amount;
            return coalesce(blocks.size() - 1).block();
        }
        int trim() {
            int released = 0;
            if (isBuddy()) {
                while (!blocks.get(blocks.size() - 1).used &&
                       2 * blocks.get(blocks.size() - 1).size == size) {
                    released += blocks.remove(blocks.size() - 1).size;
                    size /= 2;
                }
            } else if (blocks.size() >= 2 && !blocks.get(blocks.size() - 1).used) {
                Block block = blocks.remove(blocks.size() - 1);
                released = block.size;
                size = block.start;
            }
            if (rover >= size)
                rover = 0;
            return released;
        }
        Packed compact() {
            List<Moved> moved = new ArrayList<>();
            ArrayList<Block> packed = new ArrayList<>(usedBlocks());
            int address = 0;
            for (Block block : packed) {
                if (block.start != address) {
                    moved.add(new Moved(block, block.payload()));
                    block.start = address;
                }
                address += block.size;
            }
            if (address < size)
                packed.add(register(new Block(address, size - address)));
            blocks = packed;
            rover = 0;
            return new Packed(moved, address);
        }
    }

    static String experiment(String mode, int size, long seed, int operations, int maxRequest) {
        Heap heap = new Heap(mode, size);
        List<Block> live = new ArrayList<>();
        long state = seed;
        int used = 0, peak = 0, successes = 0, failures = 0;
        for (int i = 0; i < operations; ++i) {
            state = random(state);
            boolean allocating = live.isEmpty() || state % 3 != 0;
            state = random(state);
            if (allocating) {
                int request = 1 + (int)(state % maxRequest);
                Block block = heap.allocate(heap.requiredLength(request), UNIT);
                if (block == null)
                    ++failures;
                else {
                    ++successes;
                    live.add(block);
                    used += block.size;
                }
            } else {
                Block block = live.remove((int)(state % live.size()));
                used -= block.size;
                heap.release(block);
            }
            peak = Math.max(peak, used);
        }
        return "BENCH " + mode + " ok=" + successes + " fail=" + failures + " peak=" + peak +
            " used=" + used + " frag=" + heap.fragmentation() + " blocks=" + heap.blocks.size();
    }

    static final class Allocator {
        Heap heap;
        Map<String, Block> allocations;
        Set<String> freed;
        Set<String> roots;
        Map<String, Set<String>> references;
        Map<String, List<String>> histories;
        Map<String, Integer> counters;
        int peak;
        List<String> output = new ArrayList<>();

        Allocator() {
            reset(null);
        }
        void reset(Heap replacement) {
            heap = replacement;
            allocations = new HashMap<>();
            freed = new HashSet<>();
            roots = new HashSet<>();
            references = new HashMap<>();
            histories = new HashMap<>();
            counters = new HashMap<>();
            for (String name : COUNTERS)
                counters.put(name, 0);
            peak = 0;
        }
        void emit(Object... parts) {
            StringBuilder text = new StringBuilder();
            for (Object part : parts) {
                if (!text.isEmpty())
                    text.append(' ');
                text.append(part);
            }
            output.add(text.toString());
        }
        void record(String id, String line) {
            emit(line);
            histories.computeIfAbsent(id, key -> new ArrayList<>()).add(line);
        }
        void increment(String name) {
            counters.put(name, counters.get(name) + 1);
        }
        CommandError outOfMemory(String id) {
            increment("failures");
            return new CommandError("OUT OF MEMORY " + id);
        }
        Block live(String id) {
            Block block = allocations.get(id);
            if (block != null)
                return block;
            if (freed.contains(id))
                throw new CommandError("USE AFTER FREE " + id);
            throw new CommandError("UNKNOWN ID " + id);
        }
        Block range(String id, int offset, int length) {
            Block block = live(id);
            if (offset + length > block.requested)
                throw new CommandError("OUT OF BOUNDS " + id);
            return block;
        }
        void freeListOnly() {
            if (heap.isBuddy())
                throw new CommandError("UNSUPPORTED IN BUDDY MODE");
        }
        Set<String> reachable() {
            Set<String> reached = new HashSet<>(roots);
            ArrayList<String> pending = new ArrayList<>(roots);
            while (!pending.isEmpty()) {
                String name = pending.remove(pending.size() - 1);
                for (String target : references.getOrDefault(name, Set.of())) {
                    if (reached.add(target))
                        pending.add(target);
                }
            }
            return reached;
        }
        void allocateId(String kind, String id, int requested, int alignment, int fill) {
            if (requested == 0)
                throw new CommandError("BAD SIZE");
            if (allocations.containsKey(id))
                throw new CommandError("DUPLICATE ID " + id);
            Block block = heap.allocate(heap.requiredLength(requested), alignment);
            if (block == null)
                throw outOfMemory(id);
            block.owner = id;
            block.requested = requested;
            block.contents = new int[requested];
            Arrays.fill(block.contents, fill);
            allocations.put(id, block);
            freed.remove(id);
            increment("allocs");
            record
            (id, kind + " " + id + " addr=" + block.payload() + " block=" + block.size);
        }
        String releaseId(String id) {
            Block block = allocations.remove(id);
            int size = block.size;
            freed.add(id);
            roots.remove(id);
            references.remove(id);
            for (Set<String> targets : references.values())
                targets.remove(id);
            Coalesced result = heap.release(block);
            return "block=" + size + " merges=" + result.merges() +
                " free=" + result.block().area();
        }
        void freeId(String id) {
            if (freed.contains(id))
                throw new CommandError("DOUBLE FREE " + id);
            if (!allocations.containsKey(id))
                throw new CommandError("UNKNOWN ID " + id);
            String details = releaseId(id);
            increment("frees");
            record
            (id, "FREE " + id + " " + details);
        }
        void realloc(String id, int requested) {
            if (requested == 0) {
                freeId(id);
                return;
            }
            if (freed.contains(id))
                throw new CommandError("USE AFTER FREE " + id);
            Block block = allocations.get(id);
            if (block == null) {
                allocateId("MALLOC", id, requested, UNIT, UNINITIALIZED);
                return;
            }
            int length = heap.requiredLength(requested);
            int[] contents = Arrays.copyOf(block.contents, requested);
            if (contents.length > block.contents.length)
                Arrays.fill(contents, block.contents.length, contents.length, UNINITIALIZED);
            int previous = block.payload();
            String kind = heap.resize(block, length);
            if (kind == null) {
                Block moved = heap.allocate(length, UNIT);
                if (moved == null)
                    throw outOfMemory(id);
                moved.owner = id;
                allocations.put(id, moved);
                heap.release(block);
                increment("moves");
                block = moved;
                kind = "moved from=" + previous;
            }
            block.requested = requested;
            block.contents = contents;
            increment("reallocs");
            record
            (id,
             "REALLOC " + id + " addr=" + block.payload() + " block=" + block.size + " " + kind);
        }
        void treeNode(Map<Integer, Block> leaves, int start, int size, int depth) {
            String label = " ".repeat(depth * 2) + start + "+" + size;
            Block block = leaves.get(start);
            if (block != null && block.size == size) {
                emit(label + (block.used ? " USED " + block.owner : " FREE"));
                return;
            }
            emit(label + " split");
            treeNode(leaves, start, size / 2, depth + 1);
            treeNode(leaves, start + size / 2, size / 2, depth + 1);
        }
        void run(String command, String[] args) {
            switch (command) {
            case "HEAP" -> {
                int size = number(args[0]);
                String mode = args[1];
                if (size % UNIT != 0 || size < 32 || size > MAX_HEAP ||
                    (mode.equals("BUDDY") && !powerOfTwo(size)))
                    throw new CommandError("BAD HEAP SIZE");
                reset(new Heap(mode, size));
                emit("HEAP size=" + size + " mode=" + mode);
            }
            case "MALLOC" -> allocateId("MALLOC", args[0], number(args[1]), UNIT, UNINITIALIZED);
            case "CALLOC" ->
                allocateId("CALLOC", args[0], number(args[1]) * number(args[2]), UNIT, 0);
            case "MEMALIGN" -> {
                freeListOnly();
                int alignment = number(args[1]);
                if (!powerOfTwo(alignment) || alignment < UNIT || alignment > 4096)
                    throw new CommandError("BAD ALIGNMENT");
                allocateId("MEMALIGN", args[0], number(args[2]), alignment, UNINITIALIZED);
            }
            case "REALLOC" -> realloc(args[0], number(args[1]));
            case "FREE" -> freeId(args[0]);
            case "FILL" -> {
                String id = args[0];
                int offset = number(args[1]), length = number(args[2]), value = number(args[3]);
                Block block = range(id, offset, length);
                Arrays.fill(block.contents, offset, offset + length, value);
                emit("FILL " + id + " " + offset + "+" + length + " = " + value);
            }
            case "COPY" -> {
                String dest = args[0], source = args[2];
                int destOffset = number(args[1]), sourceOffset = number(args[3]);
                int length = number(args[4]);
                Block dst = range(dest, destOffset, length);
                Block src = range(source, sourceOffset, length);
                System.arraycopy(src.contents, sourceOffset, dst.contents, destOffset, length);
                emit("COPY " + dest + " " + destOffset + "+" + length + " from " + source + " " +
                     sourceOffset);
            }
            case "READ" -> {
                String id = args[0];
                int offset = number(args[1]), length = number(args[2]);
                Block block = range(id, offset, length);
                StringBuilder values = new StringBuilder();
                for (int i = 0; i < length; ++i) {
                    if (i > 0)
                        values.append(' ');
                    int value = block.contents[offset + i];
                    values.append(value == UNINITIALIZED ? "?" : Integer.toString(value));
                }
                emit("READ " + id + " " + offset + "+" + length + " = " + values);
            }
            case "ROOT" -> {
                live(args[0]);
                roots.add(args[0]);
                emit("ROOT " + args[0]);
            }
            case "UNROOT" -> {
                live(args[0]);
                if (!roots.contains(args[0]))
                    throw new CommandError("NOT ROOT " + args[0]);
                roots.remove(args[0]);
                emit("UNROOT " + args[0]);
            }
            case "LINK" -> {
                String source = args[0], target = args[1];
                live(source);
                live(target);
                references.computeIfAbsent(source, key -> new HashSet<>()).add(target);
                emit("LINK " + source + " " + target);
            }
            case "UNLINK" -> {
                String source = args[0], target = args[1];
                live(source);
                live(target);
                if (!references.getOrDefault(source, Set.of()).contains(target))
                    throw new CommandError("NO LINK " + source + " " + target);
                references.get(source).remove(target);
                emit("UNLINK " + source + " " + target);
            }
            case "GC" -> {
                Set<String> found = reachable();
                List<Block> garbage = allocations.entrySet()
                                          .stream()
                                          .filter(entry -> !found.contains(entry.getKey()))
                                          .map(Map.Entry::getValue)
                                          .sorted(Comparator.comparingInt(b -> b.start))
                                          .toList();
                int bytes = garbage.stream().mapToInt(b -> b.size).sum();
                emit("GC collected=" + garbage.size() + " bytes=" + bytes);
                for (Block block : garbage) {
                    String id = block.owner;
                    record
                    (id, "COLLECT " + id + " " + releaseId(id));
                }
                counters.put("collected", counters.get("collected") + garbage.size());
            }
            case "SBRK" -> {
                int amount = number(args[0]);
                boolean valid = heap.isBuddy() ? amount == heap.size && 2 * heap.size <= MAX_HEAP
                                               : amount % UNIT == 0 && amount >= MIN_BLOCK &&
                                                     heap.size + amount <= MAX_HEAP;
                if (!valid)
                    throw new CommandError("BAD SBRK SIZE");
                Block free = heap.extend(amount);
                emit("SBRK heap=" + heap.size + " free=" + free.area());
            }
            case "TRIM" -> {
                int released = heap.trim();
                emit("TRIM heap=" + heap.size + " released=" + released);
            }
            case "COMPACT" -> {
                freeListOnly();
                Packed result = heap.compact();
                counters.put("moves", counters.get("moves") + result.moved().size());
                String free = result.used() < heap.size
                                  ? result.used() + "+" + (heap.size - result.used())
                                  : "none";
                emit("COMPACT moved=" + result.moved().size() + " free=" + free);
                for (Moved moved : result.moved()) {
                    Block block = moved.block();
                    record
                    (block.owner,
                     "MOVE " + block.owner + " " + moved.from() + " -> " + block.payload());
                }
            }
            case "WHO" -> {
                int address = number(args[0]);
                if (address >= heap.size) {
                    emit("WHO " + address + " outside");
                    break;
                }
                Block block = heap.blocks.get(heap.locate(address));
                if (!block.used) {
                    emit("WHO " + address + " free " + block.area());
                    break;
                }
                if (address < block.payload()) {
                    emit("WHO " + address + " header " + block.owner);
                    break;
                }
                int offset = address - block.payload();
                String part = offset < block.requested ? "data" : "slack";
                emit("WHO " + address + " " + part + " " + block.owner + "+" + offset);
            }
            case "DUMP" -> {
                String first = "DUMP mode=" + heap.mode + " heap=" + heap.size +
                               " blocks=" + heap.blocks.size();
                if (heap.mode.equals("NEXT"))
                    first += " rover=" + heap.rover;
                emit(first);
                for (Block block : heap.blocks) {
                    if (block.used)
                        emit(block.start + " " + block.size + " USED " + block.owner +
                             " req=" + block.requested);
                    else
                        emit(block.start + " " + block.size + " FREE");
                }
            }
            case "MAP" -> {
                emit("MAP heap=" + heap.size);
                StringBuilder all = new StringBuilder();
                for (Block block : heap.blocks)
                    all.append(block.mapUnits());
                for (int first = 0; first < all.length(); first += 64) {
                    String label = String.format("%05d", first * UNIT);
                    emit(label + " " + all.substring(first, Math.min(first + 64, all.length())));
                }
            }
            case "FREELIST" -> {
                List<Block> free = new ArrayList<>(heap.freeBlocks());
                if (heap.mode.equals("SEGFIT"))
                    free.sort(Comparator.comparingInt((Block b) -> b.stamp).reversed());
                emit("FREELIST count=" + free.size());
                Map<Integer, List<String>> groups = new java.util.TreeMap<>();
                for (Block block : free)
                    groups.computeIfAbsent(sizeClass(block.size), k -> new ArrayList<>())
                        .add(block.area());
                for (Map.Entry<Integer, List<String>> entry : groups.entrySet()) {
                    int exp = entry.getKey();
                    emit((1 << exp) + "-" + ((1 << (exp + 1)) - 1) + ": " +
                         String.join(" ", entry.getValue()));
                }
            }
            case "TREE" -> {
                if (!heap.isBuddy())
                    throw new CommandError("REQUIRES BUDDY MODE");
                emit("TREE heap=" + heap.size);
                Map<Integer, Block> leaves = new HashMap<>();
                for (Block block : heap.blocks)
                    leaves.put(block.start, block);
                treeNode(leaves, 0, heap.size, 0);
            }
            case "STATS" -> {
                List<Block> used = heap.usedBlocks(), free = heap.freeBlocks();
                int freeTotal = free.stream().mapToInt(b -> b.size).sum();
                int largest = free.stream().mapToInt(b -> b.size).max().orElse(0);
                int usedTotal = used.stream().mapToInt(b -> b.size).sum();
                int requested = used.stream().mapToInt(b -> b.requested).sum();
                emit("STATS used=" + usedTotal + " used_blocks=" + used.size() +
                     " free=" + freeTotal + " free_blocks=" + free.size() + " largest=" + largest +
                     " frag=" + fragmentationPercent(freeTotal, largest) +
                     " requested=" + requested + " peak=" + peak);
                List<String> ops = new ArrayList<>();
                for (String name : COUNTERS)
                    ops.add(name + "=" + counters.get(name));
                emit("OPS " + String.join(" ", ops));
            }
            case "LEAKS" -> {
                Set<String> found = reachable();
                Set<String> names = new TreeSet<>(allocations.keySet());
                int requested = allocations.values().stream().mapToInt(b -> b.requested).sum();
                int lost = 0;
                for (String id : names)
                    if (!found.contains(id))
                        ++lost;
                emit("LEAKS count=" + names.size() + " requested=" + requested + " lost=" + lost);
                for (String id : names) {
                    Block block = allocations.get(id);
                    emit("LEAK " + id + " addr=" + block.payload() + " block=" + block.size +
                         " req=" + block.requested + " " +
                         (found.contains(id) ? "reachable" : "lost"));
                }
            }
            case "HISTORY" -> {
                List<String> events = histories.getOrDefault(args[0], List.of());
                emit("HISTORY " + args[0] + " events=" + events.size());
                output.addAll(events);
            }
            case "BENCH" -> {
                int size = number(args[0]), operations = number(args[2]);
                long seed = Long.parseLong(args[1]);
                int maxRequest = number(args[3]);
                if (!powerOfTwo(size) || size < 32 || size > MAX_HEAP)
                    throw new CommandError("BAD HEAP SIZE");
                emit("BENCH heap=" + size + " seed=" + seed + " ops=" + operations +
                     " maxreq=" + maxRequest);
                for (String mode : MODES)
                    emit(experiment(mode, size, seed, operations, maxRequest));
            }
            default -> throw new IllegalArgumentException("Unknown command: " + command);
            }
        }
        void execute(String line) {
            String[] tokens = line.split(" ");
            String command = tokens[0];
            String[] args = Arrays.copyOfRange(tokens, 1, tokens.length);
            try {
                if (heap == null && !command.equals("HEAP") && !command.equals("BENCH"))
                    throw new CommandError("NO HEAP");
                run(command, args);
            } catch (CommandError error) {
                emit("ERROR " + error.getMessage());
            }
            if (heap != null)
                peak = Math.max(peak, heap.usedTotal());
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        Allocator allocator = new Allocator();
        for (int i = 0; i < count; ++i)
            allocator.execute(input.readLine());
        System.out.print(String.join("\n", allocator.output) + "\n");
    }
}
