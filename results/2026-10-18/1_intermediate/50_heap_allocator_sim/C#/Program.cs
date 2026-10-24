using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

public class Program {
    static readonly int UNIT = 8;
    static readonly int HEADER = 8;
    static readonly int MIN_BLOCK = 16;
    static readonly int MIN_BUDDY_BLOCK = 32;
    static readonly int MAX_HEAP = 65536;
    static readonly int UNINITIALIZED = -1;
    static readonly long RANDOM_MODULUS = 2147483647L;
    static readonly long RANDOM_MULTIPLIER = 48271L;
    static readonly List<string> MODES = new List<string> {"FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY"};
    static readonly List<string> COUNTERS = new List<string> {"allocs", "frees", "reallocs", "moves", "failures", "collected"};

    static int Number(string text) { return int.Parse(text); }
    static bool PowerOfTwo(int n) { return n > 0 && (n & (n - 1)) == 0; }
    static int SizeClass(int n) { int k = 0; while ((1 << (k + 1)) <= n) ++k; return k; }
    static int FragmentationPercent(int free, int largest) {
        return free == 0 ? 0 : (free - largest) * 100 / free;
    }
    static long Random(long state) { return RANDOM_MULTIPLIER * state % RANDOM_MODULUS; }

    public class CommandError : Exception {
        public CommandError(string text) : base(text) {}
    }

    public class Block {
        public int start;
        public int size;
        public int requested;
        public int stamp;
        public bool used;
        public string owner;
        public int[] contents = new int[0];

        public Block(int start, int size) {
            this.start = start;
            this.size = size;
        }
        public int End() { return start + size; }
        public int Payload() { return start + HEADER; }
        public string Area() { return start + "+" + size; }
        public string MapUnits() {
            int count = size / UNIT - 1;
            StringBuilder result = new StringBuilder();
            result.Append(used ? 'H' : 'F');
            for (int i = 0; i < count; ++i) {
                result.Append(!used ? '.' : i * UNIT < requested ? '#' : '-');
            }
            return result.ToString();
        }
    }

    public record Choice(int index, int place, int first, int second);
    public record Coalesced(Block block, int merges);
    public record Moved(Block block, int from);
    public record Packed(List<Moved> moved, int used);

    public class Heap {
        public string mode;
        public int size;
        public int rover;
        public int registrations;
        public List<Block> blocks = new();

        public Heap(string mode, int size) {
            this.mode = mode;
            this.size = size;
            blocks.Add(Register(new Block(0, size)));
        }
        public Block Register(Block block) {
            block.stamp = ++registrations;
            return block;
        }
        public bool IsBuddy() { return mode.Equals("BUDDY"); }
        public int RequiredLength(int request) {
            int length = (request + UNIT - 1) / UNIT * UNIT + HEADER;
            if (!IsBuddy()) return length;
            int power = MIN_BUDDY_BLOCK;
            while (power < length) power *= 2;
            return power;
        }
        public int Locate(int address) {
            int i = 0;
            while (blocks[i].End() <= address) ++i;
            return i;
        }
        public List<Block> UsedBlocks() {
            return blocks.Where(b => b.used).ToList();
        }
        public List<Block> FreeBlocks() {
            return blocks.Where(b => !b.used).ToList();
        }
        public int UsedTotal() { return UsedBlocks().Select(b => b.size).Sum(); }
        public int Fragmentation() {
            List<Block> free = FreeBlocks();
            int total = free.Select(b => b.size).Sum();
            int largest = free.Select(b => b.size).DefaultIfEmpty(0).Max();
            return FragmentationPercent(total, largest);
        }
        public int Placement(Block block, int alignment) {
            int p = (block.start + HEADER + alignment - 1) / alignment * alignment - HEADER;
            if (p > block.start && p - block.start < MIN_BLOCK) p += alignment;
            return p;
        }
        public int[] Rank(int index, int roverIndex) {
            Block block = blocks[index];
            return mode switch {
                "NEXT" => new int[] {(index - roverIndex + blocks.Count) % blocks.Count, 0},
                "BEST" or "BUDDY" => new int[] {block.size, block.start},
                "WORST" => new int[] {-block.size, block.start},
                "SEGFIT" => new int[] {SizeClass(block.size), -block.stamp},
                _ => new int[] {block.start, 0},
            };
        }
        public Choice Choose(int length, int alignment) {
            int roverIndex = Locate(rover);
            Choice selected = null;
            for (int index = 0; index < blocks.Count; ++index) {
                Block block = blocks[index];
                if (block.used) continue;
                int place = Placement(block, alignment);
                if (place + length > block.End()) continue;
                int[] rank = Rank(index, roverIndex);
                if (selected == null || rank[0] < selected.first ||
                    (rank[0] == selected.first && rank[1] < selected.second)) {
                    selected = new Choice(index, place, rank[0], rank[1]);
                }
            }
            return selected;
        }
        public Block Allocate(int length, int alignment) {
            Choice choice = Choose(length, alignment);
            if (choice == null) return null;
            Block block = IsBuddy()
                ? Halve(choice.index, length) : Carve(choice.index, choice.place, length);
            block.used = true;
            if (mode.Equals("NEXT")) rover = block.End() == size ? 0 : block.End();
            return block;
        }
        public Block Carve(int index, int place, int length) {
            Block old = blocks[index];
            List<Block> parts = new();
            if (place > old.start) parts.Add(Register(new Block(old.start, place - old.start)));
            Block used = new Block(place, old.End() - place);
            parts.Add(used);
            if (used.size - length >= MIN_BLOCK) {
                parts.Add(Register(new Block(place + length, used.size - length)));
                used.size = length;
            }
            blocks.RemoveAt(index);
            blocks.InsertRange(index, parts);
            return used;
        }
        public Block Halve(int index, int length) {
            Block block = blocks[index];
            while (block.size > length) {
                block.size /= 2;
                blocks.Insert(index + 1, Register(new Block(block.End(), block.size)));
            }
            return block;
        }
        public void MergeNext(int index) {
            blocks[index].size += blocks[index + 1].size;
            blocks.RemoveAt(index + 1);
        }
        public Coalesced Coalesce(int index) {
            int merges = 0;
            if (IsBuddy()) {
                while (blocks[index].size < size) {
                    Block block = blocks[index];
                    int partner = block.start % (2 * block.size) == 0 ? index + 1 : index - 1;
                    if (partner < 0 || partner >= blocks.Count) break;
                    Block other = blocks[partner];
                    if (other.used || other.size != block.size) break;
                    index = Math.Min(index, partner);
                    MergeNext(index);
                    ++merges;
                }
            } else {
                if (index + 1 < blocks.Count && !blocks[index + 1].used) {
                    MergeNext(index);
                    ++merges;
                }
                if (index > 0 && !blocks[index - 1].used) {
                    --index;
                    MergeNext(index);
                    ++merges;
                }
            }
            return new Coalesced(Register(blocks[index]), merges);
        }
        public Coalesced Release(Block block) {
            block.used = false;
            block.owner = null;
            block.requested = 0;
            block.contents = new int[0];
            return Coalesce(blocks.IndexOf(block));
        }
        public string Shrink(int index, int length) {
            Block block = blocks[index];
            if (IsBuddy()) {
                if (block.size == length) return "kept";
                Halve(index, length);
                return "shrunk";
            }
            if (block.size - length < MIN_BLOCK) return "kept";
            blocks.Insert(index + 1, new Block(block.start + length, block.size - length));
            block.size = length;
            Coalesce(index + 1);
            return "shrunk";
        }
        public string GrowIntoNext(int index, int length) {
            if (index + 1 == blocks.Count || blocks[index + 1].used) return null;
            Block block = blocks[index];
            int total = block.size + blocks[index + 1].size;
            if (total < length) return null;
            blocks.RemoveAt(index + 1);
            if (total - length >= MIN_BLOCK) {
                block.size = length;
                blocks.Insert(index + 1, Register(new Block(block.End(), total - length)));
            } else block.size = total;
            return "grown";
        }
        public string GrowBuddy(int index, int length) {
            Block block = blocks[index];
            int oldSize = block.size;
            int last = index;
            while (oldSize < length) {
                ++last;
                if (block.start % (2 * oldSize) != 0 || last == blocks.Count) return null;
                Block partner = blocks[last];
                if (partner.used || partner.size != oldSize) return null;
                oldSize *= 2;
            }
            blocks.RemoveRange(index + 1, last - index);
            block.size = length;
            return "grown";
        }
        public string Resize(Block block, int length) {
            int index = blocks.IndexOf(block);
            if (length <= block.size) return Shrink(index, length);
            return IsBuddy() ? GrowBuddy(index, length) : GrowIntoNext(index, length);
        }
        public Block Extend(int amount) {
            blocks.Add(new Block(size, amount));
            size += amount;
            return Coalesce(blocks.Count - 1).block;
        }
        public int Trim() {
            int released = 0;
            if (IsBuddy()) {
                while (!blocks[blocks.Count - 1].used &&
                       2 * blocks[blocks.Count - 1].size == size) {
                    released += blocks[blocks.Count - 1].size;
                    blocks.RemoveAt(blocks.Count - 1);
                    size /= 2;
                }
            } else if (blocks.Count >= 2 && !blocks[blocks.Count - 1].used) {
                Block block = blocks[blocks.Count - 1];
                blocks.RemoveAt(blocks.Count - 1);
                released = block.size;
                size = block.start;
            }
            if (rover >= size) rover = 0;
            return released;
        }
        public Packed Compact() {
            List<Moved> moved = new();
            List<Block> packed = new List<Block>(UsedBlocks());
            int address = 0;
            foreach (Block block in packed) {
                if (block.start != address) {
                    moved.Add(new Moved(block, block.Payload()));
                    block.start = address;
                }
                address += block.size;
            }
            if (address < size) packed.Add(Register(new Block(address, size - address)));
            blocks = packed;
            rover = 0;
            return new Packed(moved, address);
        }
    }

    static string Experiment(string mode, int size, long seed, int operations, int maxRequest) {
        Heap heap = new Heap(mode, size);
        List<Block> live = new();
        long state = seed;
        int used = 0, peak = 0, successes = 0, failures = 0;
        for (int i = 0; i < operations; ++i) {
            state = Random(state);
            bool allocating = live.Count == 0 || state % 3 != 0;
            state = Random(state);
            if (allocating) {
                int request = 1 + (int) (state % maxRequest);
                Block block = heap.Allocate(heap.RequiredLength(request), UNIT);
                if (block == null) ++failures;
                else {
                    ++successes;
                    live.Add(block);
                    used += block.size;
                }
            } else {
                int at = (int)(state % live.Count);
                Block block = live[at];
                live.RemoveAt(at);
                used -= block.size;
                heap.Release(block);
            }
            peak = Math.Max(peak, used);
        }
        return "BENCH " + mode + " ok=" + successes + " fail=" + failures +
            " peak=" + peak + " used=" + used + " frag=" + heap.Fragmentation() +
            " blocks=" + heap.blocks.Count;
    }

    public class Allocator {
        public Heap heap;
        public Dictionary<string, Block> allocations;
        public HashSet<string> freed;
        public HashSet<string> roots;
        public Dictionary<string, HashSet<string>> references;
        public Dictionary<string, List<string>> histories;
        public Dictionary<string, int> counters;
        public int peak;
        public List<string> output = new();

        public Allocator() { Reset(null); }
        public void Reset(Heap replacement) {
            heap = replacement;
            allocations = new();
            freed = new();
            roots = new();
            references = new();
            histories = new();
            counters = new();
            foreach (string name in COUNTERS) counters[name] = 0;
            peak = 0;
        }
        public void Emit(string text) { output.Add(text); }
        public void Record(string id, string line) {
            Emit(line);
            if (!histories.ContainsKey(id)) histories[id] = new List<string>();
            histories[id].Add(line);
        }
        public void Increment(string name) { counters[name] = counters[name] + 1; }
        public CommandError OutOfMemory(string id) {
            Increment("failures");
            return new CommandError("OUT OF MEMORY " + id);
        }
        public Block Live(string id) {
            Block block = allocations.GetValueOrDefault(id);
            if (block != null) return block;
            if (freed.Contains(id)) throw new CommandError("USE AFTER FREE " + id);
            throw new CommandError("UNKNOWN ID " + id);
        }
        public Block Range(string id, int offset, int length) {
            Block block = Live(id);
            if (offset + length > block.requested) throw new CommandError("OUT OF BOUNDS " + id);
            return block;
        }
        public void FreeListOnly() {
            if (heap.IsBuddy()) throw new CommandError("UNSUPPORTED IN BUDDY MODE");
        }
        public HashSet<string> Reachable() {
            HashSet<string> reached = new HashSet<string>(roots);
            List<string> pending = new List<string>(roots);
            while (pending.Count != 0) {
                string name = pending[pending.Count - 1];
                pending.RemoveAt(pending.Count - 1);
                foreach (string target in references.GetValueOrDefault(name, new HashSet<string>())) {
                    if (reached.Add(target)) pending.Add(target);
                }
            }
            return reached;
        }
        public void AllocateId(string kind, string id, int requested, int alignment, int fill) {
            if (requested == 0) throw new CommandError("BAD SIZE");
            if (allocations.ContainsKey(id)) throw new CommandError("DUPLICATE ID " + id);
            Block block = heap.Allocate(heap.RequiredLength(requested), alignment);
            if (block == null) throw OutOfMemory(id);
            block.owner = id;
            block.requested = requested;
            block.contents = new int[requested];
            Array.Fill(block.contents, fill);
            allocations[id] = block;
            freed.Remove(id);
            Increment("allocs");
            Record(id, kind + " " + id + " addr=" + block.Payload() + " block=" + block.size);
        }
        public string ReleaseId(string id) {
            Block block = allocations.GetValueOrDefault(id);
            allocations.Remove(id);
            int size = block.size;
            freed.Add(id);
            roots.Remove(id);
            references.Remove(id);
            foreach (HashSet<string> targets in references.Values) targets.Remove(id);
            Coalesced result = heap.Release(block);
            return "block=" + size + " merges=" + result.merges + " free=" + result.block.Area();
        }
        public void FreeId(string id) {
            if (freed.Contains(id)) throw new CommandError("DOUBLE FREE " + id);
            if (!allocations.ContainsKey(id)) throw new CommandError("UNKNOWN ID " + id);
            string details = ReleaseId(id);
            Increment("frees");
            Record(id, "FREE " + id + " " + details);
        }
        public void Realloc(string id, int requested) {
            if (requested == 0) { FreeId(id); return; }
            if (freed.Contains(id)) throw new CommandError("USE AFTER FREE " + id);
            Block block = allocations.GetValueOrDefault(id);
            if (block == null) { AllocateId("MALLOC", id, requested, UNIT, UNINITIALIZED); return; }
            int length = heap.RequiredLength(requested);
            int[] contents = ResizeContents(block.contents, requested);
            if (contents.Length > block.contents.Length)
                Array.Fill(contents, UNINITIALIZED, block.contents.Length, contents.Length - block.contents.Length);
            int previous = block.Payload();
            string kind = heap.Resize(block, length);
            if (kind == null) {
                Block moved = heap.Allocate(length, UNIT);
                if (moved == null) throw OutOfMemory(id);
                moved.owner = id;
                allocations[id] = moved;
                heap.Release(block);
                Increment("moves");
                block = moved;
                kind = "moved from=" + previous;
            }
            block.requested = requested;
            block.contents = contents;
            Increment("reallocs");
            Record(id, "REALLOC " + id + " addr=" + block.Payload() +
                " block=" + block.size + " " + kind);
        }
        public void TreeNode(Dictionary<int, Block> leaves, int start, int size, int depth) {
            string label = new string(' ', depth * 2) + start + "+" + size;
            Block block = leaves.GetValueOrDefault(start);
            if (block != null && block.size == size) {
                Emit(label + (block.used ? " USED " + block.owner : " FREE"));
                return;
            }
            Emit(label + " split");
            TreeNode(leaves, start, size / 2, depth + 1);
            TreeNode(leaves, start + size / 2, size / 2, depth + 1);
        }
        public void Run(string command, string[] args) {
            switch (command) {
                case "HEAP": {
                    int size = Number(args[0]);
                    string mode = args[1];
                    if (size % UNIT != 0 || size < 32 || size > MAX_HEAP ||
                        (mode.Equals("BUDDY") && !PowerOfTwo(size)))
                        throw new CommandError("BAD HEAP SIZE");
                    Reset(new Heap(mode, size));
                    Emit("HEAP size=" + size + " mode=" + mode);
                    break;
                }
                case "MALLOC": AllocateId("MALLOC", args[0], Number(args[1]), UNIT, UNINITIALIZED); break;
                case "CALLOC": AllocateId("CALLOC", args[0], Number(args[1]) * Number(args[2]), UNIT, 0); break;
                case "MEMALIGN": {
                    FreeListOnly();
                    int alignment = Number(args[1]);
                    if (!PowerOfTwo(alignment) || alignment < UNIT || alignment > 4096)
                        throw new CommandError("BAD ALIGNMENT");
                    AllocateId("MEMALIGN", args[0], Number(args[2]), alignment, UNINITIALIZED);
                    break;
                }
                case "REALLOC": Realloc(args[0], Number(args[1])); break;
                case "FREE": FreeId(args[0]); break;
                case "FILL": {
                    string id = args[0];
                    int offset = Number(args[1]), length = Number(args[2]), value = Number(args[3]);
                    Block block = Range(id, offset, length);
                    Array.Fill(block.contents, value, offset, length);
                    Emit("FILL " + id + " " + offset + "+" + length + " = " + value);
                    break;
                }
                case "COPY": {
                    string dest = args[0], source = args[2];
                    int destOffset = Number(args[1]), sourceOffset = Number(args[3]);
                    int length = Number(args[4]);
                    Block dst = Range(dest, destOffset, length);
                    Block src = Range(source, sourceOffset, length);
                    Array.Copy(src.contents, sourceOffset, dst.contents, destOffset, length);
                    Emit("COPY " + dest + " " + destOffset + "+" + length +
                        " from " + source + " " + sourceOffset);
                    break;
                }
                case "READ": {
                    string id = args[0];
                    int offset = Number(args[1]), length = Number(args[2]);
                    Block block = Range(id, offset, length);
                    StringBuilder values = new StringBuilder();
                    for (int i = 0; i < length; ++i) {
                        if (i > 0) values.Append(' ');
                        int value = block.contents[offset + i];
                        values.Append(value == UNINITIALIZED ? "?" : value.ToString());
                    }
                    Emit("READ " + id + " " + offset + "+" + length + " = " + values);
                    break;
                }
                case "ROOT": {
                    Live(args[0]);
                    roots.Add(args[0]);
                    Emit("ROOT " + args[0]);
                    break;
                }
                case "UNROOT": {
                    Live(args[0]);
                    if (!roots.Contains(args[0])) throw new CommandError("NOT ROOT " + args[0]);
                    roots.Remove(args[0]);
                    Emit("UNROOT " + args[0]);
                    break;
                }
                case "LINK": {
                    string source = args[0], target = args[1];
                    Live(source);
                    Live(target);
                    if (!references.ContainsKey(source)) references[source] = new HashSet<string>();
                    references[source].Add(target);
                    Emit("LINK " + source + " " + target);
                    break;
                }
                case "UNLINK": {
                    string source = args[0], target = args[1];
                    Live(source);
                    Live(target);
                    if (!references.GetValueOrDefault(source, new HashSet<string>()).Contains(target))
                        throw new CommandError("NO LINK " + source + " " + target);
                    references[source].Remove(target);
                    Emit("UNLINK " + source + " " + target);
                    break;
                }
                case "GC": {
                    HashSet<string> found = Reachable();
                    List<Block> garbage = allocations
                        .Where(entry => !found.Contains(entry.Key))
                        .Select(entry => entry.Value)
                        .OrderBy(b => b.start).ToList();
                    int bytes = garbage.Select(b => b.size).Sum();
                    Emit("GC collected=" + garbage.Count + " bytes=" + bytes);
                    foreach (Block block in garbage) {
                        string id = block.owner;
                        Record(id, "COLLECT " + id + " " + ReleaseId(id));
                    }
                    counters["collected"] = counters["collected"] + garbage.Count;
                    break;
                }
                case "SBRK": {
                    int amount = Number(args[0]);
                    bool valid = heap.IsBuddy()
                        ? amount == heap.size && 2 * heap.size <= MAX_HEAP
                        : amount % UNIT == 0 && amount >= MIN_BLOCK && heap.size + amount <= MAX_HEAP;
                    if (!valid) throw new CommandError("BAD SBRK SIZE");
                    Block free = heap.Extend(amount);
                    Emit("SBRK heap=" + heap.size + " free=" + free.Area());
                    break;
                }
                case "TRIM": {
                    int released = heap.Trim();
                    Emit("TRIM heap=" + heap.size + " released=" + released);
                    break;
                }
                case "COMPACT": {
                    FreeListOnly();
                    Packed result = heap.Compact();
                    counters["moves"] = counters["moves"] + result.moved.Count;
                    string free = result.used < heap.size
                        ? result.used + "+" + (heap.size - result.used) : "none";
                    Emit("COMPACT moved=" + result.moved.Count + " free=" + free);
                    foreach (Moved moved in result.moved) {
                        Block block = moved.block;
                        Record(block.owner, "MOVE " + block.owner + " " + moved.from +
                            " -> " + block.Payload());
                    }
                    break;
                }
                case "WHO": {
                    int address = Number(args[0]);
                    if (address >= heap.size) { Emit("WHO " + address + " outside"); break; }
                    Block block = heap.blocks[heap.Locate(address)];
                    if (!block.used) { Emit("WHO " + address + " free " + block.Area()); break; }
                    if (address < block.Payload()) {
                        Emit("WHO " + address + " header " + block.owner); break;
                    }
                    int offset = address - block.Payload();
                    string part = offset < block.requested ? "data" : "slack";
                    Emit("WHO " + address + " " + part + " " + block.owner + "+" + offset);
                    break;
                }
                case "DUMP": {
                    string first = "DUMP mode=" + heap.mode + " heap=" + heap.size +
                        " blocks=" + heap.blocks.Count;
                    if (heap.mode.Equals("NEXT")) first += " rover=" + heap.rover;
                    Emit(first);
                    foreach (Block block in heap.blocks) {
                        if (block.used)
                            Emit(block.start + " " + block.size + " USED " + block.owner +
                                " req=" + block.requested);
                        else Emit(block.start + " " + block.size + " FREE");
                    }
                    break;
                }
                case "MAP": {
                    Emit("MAP heap=" + heap.size);
                    StringBuilder all = new StringBuilder();
                    foreach (Block block in heap.blocks) all.Append(block.MapUnits());
                    for (int first = 0; first < all.Length; first += 64) {
                        string label = (first * UNIT).ToString("D5");
                        Emit(label + " " + all.ToString(first, Math.Min(64, all.Length - first)));
                    }
                    break;
                }
                case "FREELIST": {
                    List<Block> free = new List<Block>(heap.FreeBlocks());
                    if (heap.mode.Equals("SEGFIT"))
                        free = free.OrderByDescending(b => b.stamp).ToList();
                    Emit("FREELIST count=" + free.Count);
                    SortedDictionary<int, List<string>> groups = new SortedDictionary<int, List<string>>();
                    foreach (Block block in free) {
                        int group = SizeClass(block.size);
                        if (!groups.ContainsKey(group)) groups[group] = new List<string>();
                        groups[group].Add(block.Area());
                    }
                    foreach (KeyValuePair<int, List<string>> entry in groups) {
                        int exp = entry.Key;
                        Emit((1 << exp) + "-" + ((1 << (exp + 1)) - 1) + ": " +
                            string.Join(" ", entry.Value));
                    }
                    break;
                }
                case "TREE": {
                    if (!heap.IsBuddy()) throw new CommandError("REQUIRES BUDDY MODE");
                    Emit("TREE heap=" + heap.size);
                    Dictionary<int, Block> leaves = new();
                    foreach (Block block in heap.blocks) leaves[block.start] = block;
                    TreeNode(leaves, 0, heap.size, 0);
                    break;
                }
                case "STATS": {
                    List<Block> used = heap.UsedBlocks(), free = heap.FreeBlocks();
                    int freeTotal = free.Select(b => b.size).Sum();
                    int largest = free.Select(b => b.size).DefaultIfEmpty(0).Max();
                    int usedTotal = used.Select(b => b.size).Sum();
                    int requested = used.Select(b => b.requested).Sum();
                    Emit("STATS used=" + usedTotal + " used_blocks=" + used.Count +
                        " free=" + freeTotal + " free_blocks=" + free.Count +
                        " largest=" + largest + " frag=" + FragmentationPercent(freeTotal, largest) +
                        " requested=" + requested + " peak=" + peak);
                    List<string> ops = new();
                    foreach (string name in COUNTERS) ops.Add(name + "=" + counters[name]);
                    Emit("OPS " + string.Join(" ", ops));
                    break;
                }
                case "LEAKS": {
                    HashSet<string> found = Reachable();
                    SortedSet<string> names = new SortedSet<string>(allocations.Keys, StringComparer.Ordinal);
                    int requested = allocations.Values.Select(b => b.requested).Sum();
                    int lost = 0;
                    foreach (string id in names) if (!found.Contains(id)) ++lost;
                    Emit("LEAKS count=" + names.Count + " requested=" + requested + " lost=" + lost);
                    foreach (string id in names) {
                        Block block = allocations.GetValueOrDefault(id);
                        Emit("LEAK " + id + " addr=" + block.Payload() + " block=" + block.size +
                            " req=" + block.requested + " " +
                            (found.Contains(id) ? "reachable" : "lost"));
                    }
                    break;
                }
                case "HISTORY": {
                    List<string> events = histories.GetValueOrDefault(args[0], new List<string>());
                    Emit("HISTORY " + args[0] + " events=" + events.Count);
                    output.AddRange(events);
                    break;
                }
                case "BENCH": {
                    int size = Number(args[0]), operations = Number(args[2]);
                    long seed = long.Parse(args[1]);
                    int maxRequest = Number(args[3]);
                    if (!PowerOfTwo(size) || size < 32 || size > MAX_HEAP)
                        throw new CommandError("BAD HEAP SIZE");
                    Emit("BENCH heap=" + size + " seed=" + seed + " ops=" + operations +
                        " maxreq=" + maxRequest);
                    foreach (string mode in MODES) Emit(Experiment(mode, size, seed, operations, maxRequest));
                    break;
                }
                default: throw new ArgumentException("Unknown command: " + command);
            }
        }
        public void Execute(string line) {
            string[] tokens = line.Split(' ');
            string command = tokens[0];
            string[] args = tokens.Skip(1).ToArray();
            try {
                if (heap == null && !command.Equals("HEAP") && !command.Equals("BENCH"))
                    throw new CommandError("NO HEAP");
                Run(command, args);
            } catch (CommandError error) {
                Emit("ERROR " + error.Message);
            }
            if (heap != null) peak = Math.Max(peak, heap.UsedTotal());
        }
    }

    static int[] ResizeContents(int[] source, int length) {
        int[] result = new int[length];
        Array.Copy(source, result, Math.Min(source.Length, length));
        return result;
    }
    public static void Main() {
        int count = int.Parse(Console.ReadLine());
        Allocator allocator = new Allocator();
        for (int i = 0; i < count; ++i) allocator.Execute(Console.ReadLine());
        Console.Write(string.Join("\n", allocator.output) + "\n");
    }
}
