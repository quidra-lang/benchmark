using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

sealed class CommandError : Exception
{
    public CommandError(string reason) : base(reason) { }
}

readonly record struct Item(int Number, int Size)
{
    public override string ToString() => $"{Number}:{Size}";
}

sealed class Bin
{
    public List<Item> Items { get; } = new();
    public int Load { get; set; }
    public int Category { get; }

    public Bin(int category = 0) => Category = category;

    public void Put(Item item)
    {
        Items.Add(item);
        Load += item.Size;
    }

    public Bin Copy()
    {
        var bin = new Bin(Category) { Load = Load };
        bin.Items.AddRange(Items);
        return bin;
    }
}

record Step(Item Item, int Bin, int Inspected, bool Opened, int Closed, int Category);

sealed class Packing
{
    public string Method { get; }
    public int Parameter { get; }
    public List<Bin> Bins { get; } = new();
    public List<Step> Steps { get; } = new();
    public int Inspections { get; set; }
    public int Closes { get; set; }

    public Packing(string method, int parameter)
    {
        Method = method;
        Parameter = parameter;
    }

    public string Name => Method is "HARMONIC" or "KBOUNDED"
        ? $"{Method} k={Parameter}" : Method;

    public string Header(int capacity, long total) =>
        $"{Name} bins={Bins.Count} inspections={Inspections} waste={Bins.Count * (long) capacity - total}"
        + (Method == "KBOUNDED" ? $" closes={Closes}" : "");
}

record BoundRow(int Alpha, int J1, int J2, int J3, int Bound);
record BoundResult(long L1, int L2, List<BoundRow> Rows);

static class PackingAlgorithms
{
    public static long Ceil(long a, long b) => (a + b - 1) / b;

    public static List<Item> Descending(IEnumerable<Item> items) =>
        items.OrderByDescending(item => item.Size).ThenBy(item => item.Number).ToList();

    public static Packing Pack(List<Item> items, int capacity, string method, int parameter = 0)
    {
        var result = new Packing(method, parameter);
        var order = method is "FFD" or "BFD" or "WFD" ? Descending(items) : items;
        var active = new List<int>();
        var current = new Dictionary<int, int>();
        foreach (Item item in order)
        {
            int before = result.Inspections;
            int chosen = -1;
            int closed = -1;
            int category = 0;
            if (method == "NEXTFIT")
            {
                if (result.Bins.Count > 0)
                {
                    result.Inspections++;
                    int last = result.Bins.Count - 1;
                    if (result.Bins[last].Load + item.Size <= capacity) chosen = last;
                }
            }
            else if (method is "FIRSTFIT" or "FFD" or "KBOUNDED")
            {
                IEnumerable<int> candidates = method == "KBOUNDED"
                    ? active : Enumerable.Range(0, result.Bins.Count);
                foreach (int index in candidates)
                {
                    result.Inspections++;
                    if (result.Bins[index].Load + item.Size <= capacity)
                    {
                        chosen = index;
                        break;
                    }
                }
            }
            else if (method == "HARMONIC")
            {
                category = Math.Min(capacity / item.Size, parameter);
                if (current.TryGetValue(category, out int index))
                {
                    result.Inspections++;
                    if (result.Bins[index].Load + item.Size <= capacity) chosen = index;
                }
            }
            else
            {
                result.Inspections += result.Bins.Count;
                var fitting = Enumerable.Range(0, result.Bins.Count)
                    .Where(index => result.Bins[index].Load + item.Size <= capacity).ToList();
                if (fitting.Count > 0)
                {
                    if (method is "BESTFIT" or "BFD")
                        chosen = fitting.OrderByDescending(index => result.Bins[index].Load)
                            .ThenBy(index => index).First();
                    else
                    {
                        fitting = fitting.OrderBy(index => result.Bins[index].Load)
                            .ThenBy(index => index).ToList();
                        chosen = method == "ALMOSTWORST" && fitting.Count >= 2
                            ? fitting[1] : fitting[0];
                    }
                }
            }

            bool opened = chosen < 0;
            if (opened)
            {
                if (method == "KBOUNDED" && active.Count == parameter)
                {
                    closed = active.OrderByDescending(index => result.Bins[index].Load)
                        .ThenBy(index => index).First();
                    active.Remove(closed);
                    result.Closes++;
                }
                chosen = result.Bins.Count;
                result.Bins.Add(new Bin(category));
                if (method == "KBOUNDED") active.Add(chosen);
                if (method == "HARMONIC") current[category] = chosen;
            }
            result.Bins[chosen].Put(item);
            result.Steps.Add(new Step(item, chosen, result.Inspections - before,
                opened, closed, category));
        }
        return result;
    }

    public static BoundResult Bounds(List<Item> items, int capacity)
    {
        long total = items.Sum(item => (long) item.Size);
        var thresholds = new SortedSet<int> { 0 };
        foreach (Item item in items)
            if (2 * item.Size <= capacity) thresholds.Add(item.Size);
        int maximum = 0;
        var rows = new List<BoundRow>();
        foreach (int alpha in thresholds)
        {
            int j1 = 0, j2 = 0, j3 = 0;
            long sum2 = 0, sum3 = 0;
            foreach (Item item in items)
            {
                int size = item.Size;
                if (size > capacity - alpha) j1++;
                else if (2 * size > capacity) { j2++; sum2 += size; }
                else if (size >= alpha) { j3++; sum3 += size; }
            }
            long excess = sum3 - (j2 * (long) capacity - sum2);
            int bound = j1 + j2 + (excess > 0 ? (int) Ceil(excess, capacity) : 0);
            maximum = Math.Max(maximum, bound);
            rows.Add(new BoundRow(alpha, j1, j2, j3, bound));
        }
        return new BoundResult(Ceil(total, capacity), maximum, rows);
    }
}

sealed class ExactSearch
{
    private readonly List<Item> order;
    private readonly int capacity, limit, lower;
    private readonly long[] remaining;
    private readonly List<Bin> live = new();
    private readonly Action<string> emit;
    public List<Bin> Best { get; private set; }
    public int Nodes { get; private set; }
    public string? Status { get; set; }

    public ExactSearch(List<Item> items, int capacity, int limit, int lower,
                       List<Bin> incumbent, Action<string> emit)
    {
        order = PackingAlgorithms.Descending(items);
        this.capacity = capacity;
        this.limit = limit;
        this.lower = lower;
        this.emit = emit;
        Best = incumbent.Select(bin => bin.Copy()).ToList();
        remaining = new long[order.Count + 1];
        for (int i = order.Count - 1; i >= 0; i--)
            remaining[i] = remaining[i + 1] + order[i].Size;
    }

    public void Visit(int index)
    {
        if (Nodes == limit) { Status = "limit"; return; }
        Nodes++;
        int count = live.Count;
        long used = remaining[0] - remaining[index];
        long free = count * (long) capacity - used;
        long excess = remaining[index] - free;
        long minimum = count + (excess > 0 ? PackingAlgorithms.Ceil(excess, capacity) : 0);
        if (minimum >= Best.Count) return;
        if (index == order.Count)
        {
            Best = live.Select(bin => bin.Copy()).ToList();
            emit($"IMPROVE bins={count} nodes={Nodes}");
            if (count == lower) Status = "bound";
            return;
        }

        Item item = order[index];
        var seenLoads = new HashSet<int>();
        foreach (Bin bin in live)
        {
            int oldLoad = bin.Load;
            if (!seenLoads.Add(oldLoad) || oldLoad + item.Size > capacity) continue;
            bin.Put(item);
            Visit(index + 1);
            bin.Items.RemoveAt(bin.Items.Count - 1);
            bin.Load = oldLoad;
            if (Status != null) return;
        }
        if (count + 1 < Best.Count)
        {
            var bin = new Bin();
            bin.Put(item);
            live.Add(bin);
            Visit(index + 1);
            live.RemoveAt(live.Count - 1);
        }
    }
}

readonly record struct Rect(int Number, int Width, int Height)
{
    public char Letter => (char) ('A' + Number - 1);
    public int Area => Width * Height;
}

readonly record struct Placement(Rect Rect, int X, int Y,
                                int Width, int Height, bool Rotated = false);

sealed class Shelf
{
    public int Bottom { get; }
    public int Height { get; }
    public int Used { get; set; }
    public List<Placement> Placements { get; } = new();

    public Shelf(int bottom, int height)
    {
        Bottom = bottom;
        Height = height;
    }
}

readonly record struct FreeRect(int X, int Y, int Width, int Height)
{
    public int Area => Width * Height;
    public override string ToString() => $"{X},{Y},{Width}x{Height}";
}

sealed class Sheet
{
    public List<FreeRect> Free { get; } = new();
    public List<Placement> Placements { get; } = new();
    public int Area { get; set; }

    public Sheet(int width, int height) => Free.Add(new FreeRect(0, 0, width, height));
}

readonly record struct Piece(int Length, int Demand);
readonly record struct Pattern(int[] Counts, int Trim);

sealed class Lab
{
    private static readonly string[] Methods = {
        "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
        "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"
    };

    private List<Item>? items;
    private int capacity;
    private readonly StringBuilder output = new();

    public override string ToString() => output.ToString();
    private void Emit(string line) => output.AppendLine(line);
    private long Total => items!.Sum(item => (long) item.Size);

    private static void Fail(string message) => throw new CommandError(message);
    private static int Num(string number) => int.Parse(number);

    private static int Parameter(string method, string[] words, int position)
    {
        if (method is not ("HARMONIC" or "KBOUNDED")) return 0;
        int parameter = Num(words[position]);
        if (parameter == 0) Fail("BAD PARAMETER");
        return parameter;
    }

    private void BinLine(int number, Bin bin, int binCapacity, bool showClass = false, bool over = false)
    {
        string line = $"BIN {number} load={bin.Load}/{binCapacity} items="
            + string.Join(" ", bin.Items);
        if (showClass) line += $" class={bin.Category}";
        if (over) line += " OVER";
        Emit(line);
    }

    private void BinLines(IEnumerable<Bin> bins, bool showClass = false)
    {
        int number = 1;
        foreach (Bin bin in bins) BinLine(number++, bin, capacity, showClass);
    }

    private void ItemsCommand(string[] words)
    {
        int nextCapacity = Num(words[1]);
        if (nextCapacity == 0) Fail("BAD CAPACITY");
        var next = new List<Item>();
        for (int i = 2; i < words.Length; i++)
        {
            int size = Num(words[i]);
            if (size == 0 || size > nextCapacity) Fail($"BAD ITEM {i - 1}");
            next.Add(new Item(i - 1, size));
        }
        items = next;
        capacity = nextCapacity;
        Emit($"ITEMS count={items.Count} capacity={capacity} total={Total}");
    }

    private void RandomCommand(string[] words)
    {
        int count = Num(words[1]);
        int nextCapacity = Num(words[2]);
        long seed = long.Parse(words[3]);
        if (count == 0 || count > 40) Fail("BAD COUNT");
        if (nextCapacity == 0) Fail("BAD CAPACITY");
        if (seed == 0 || seed >= 2147483647) Fail("BAD SEED");
        var next = new List<Item>();
        for (int i = 1; i <= count; i++)
        {
            seed = 48271 * seed % 2147483647;
            next.Add(new Item(i, (int) (seed % nextCapacity) + 1));
        }
        items = next;
        capacity = nextCapacity;
        Emit($"RANDOM count={count} capacity={capacity} total={Total}");
        Emit("SIZES " + string.Join(" ", items.Select(item => item.Size)));
    }

    private void MethodCommand(string method, int parameter)
    {
        Packing result = PackingAlgorithms.Pack(items!, capacity, method, parameter);
        Emit(result.Header(capacity, Total));
        BinLines(result.Bins, method == "HARMONIC");
    }

    private void Trace(string method, int parameter)
    {
        Packing result = PackingAlgorithms.Pack(items!, capacity, method, parameter);
        Emit("TRACE " + result.Header(capacity, Total));
        for (int i = 0; i < result.Steps.Count; i++)
        {
            Step step = result.Steps[i];
            string line = $"STEP {i + 1} item={step.Item} bin={step.Bin + 1} inspected={step.Inspected}";
            if (step.Opened) line += " new";
            if (step.Closed >= 0) line += $" closed={step.Closed + 1}";
            if (method == "HARMONIC") line += $" class={step.Category}";
            Emit(line);
        }
    }

    private void Reduce(string method, int parameter)
    {
        Packing result = PackingAlgorithms.Pack(items!, capacity, method, parameter);
        List<Bin> bins = result.Bins;
        int before = bins.Count;
        var events = new List<string>();
        while (true)
        {
            bool eliminated = false;
            var sources = Enumerable.Range(0, bins.Count)
                .OrderBy(index => bins[index].Load).ThenBy(index => index).ToList();
            foreach (int source in sources)
            {
                int[] loads = bins.Select(bin => bin.Load).ToArray();
                var moves = new List<(Item Item, int Destination)>();
                bool possible = true;
                foreach (Item item in PackingAlgorithms.Descending(bins[source].Items))
                {
                    int destination = Enumerable.Range(0, bins.Count)
                        .Where(index => index != source && loads[index] + item.Size <= capacity)
                        .OrderByDescending(index => loads[index]).ThenBy(index => index)
                        .DefaultIfEmpty(-1).First();
                    if (destination < 0) { possible = false; break; }
                    loads[destination] += item.Size;
                    moves.Add((item, destination));
                }
                if (!possible) continue;
                string descriptions = string.Join(" ", moves.Select(move =>
                    $"{move.Item}->{move.Destination + 1}"));
                events.Add($"ELIMINATE bin={source + 1} load={bins[source].Load} moves={descriptions}");
                foreach (var move in moves) bins[move.Destination].Put(move.Item);
                bins.RemoveAt(source);
                eliminated = true;
                break;
            }
            if (!eliminated) break;
        }
        Emit($"REDUCE {result.Name} before={before} after={bins.Count} eliminated={before - bins.Count}");
        foreach (string line in events) Emit(line);
        BinLines(bins, method == "HARMONIC");
    }

    private void BoundsCommand()
    {
        BoundResult b = PackingAlgorithms.Bounds(items!, capacity);
        Emit($"BOUNDS total={Total} L1={b.L1} L2={b.L2}");
        foreach (BoundRow row in b.Rows)
            Emit($"ALPHA {row.Alpha} j1={row.J1} j2={row.J2} j3={row.J3} bound={row.Bound}");
    }

    private void Compare(int parameter)
    {
        if (parameter == 0) Fail("BAD PARAMETER");
        BoundResult b = PackingAlgorithms.Bounds(items!, capacity);
        var results = Methods.Select(method =>
            PackingAlgorithms.Pack(items!, capacity, method, parameter))
            .OrderBy(p => p.Bins.Count).ThenBy(p => p.Method, StringComparer.Ordinal);
        Emit($"COMPARE k={parameter} L1={b.L1} L2={b.L2}");
        foreach (Packing result in results)
        {
            int count = result.Bins.Count;
            Emit($"{result.Method} bins={count} gap={count - b.L2} "
                + $"waste={count * (long) capacity - Total} inspections={result.Inspections}");
        }
    }

    private void Exact(int limit)
    {
        if (limit == 0) Fail("BAD PARAMETER");
        if (items!.Count >= 21) Fail("TOO MANY ITEMS");
        var incumbent = PackingAlgorithms.Pack(items, capacity, "FFD").Bins;
        int lower = PackingAlgorithms.Bounds(items, capacity).L2;
        Emit($"EXACT ffd={incumbent.Count} L2={lower}");
        var search = new ExactSearch(items, capacity, limit, lower, incumbent, Emit);
        if (incumbent.Count == lower) search.Status = "bound";
        else search.Visit(0);
        Emit($"RESULT bins={search.Best.Count} nodes={search.Nodes} status={search.Status ?? "complete"}");
        BinLines(search.Best);
    }

    private void Check(string[] words)
    {
        if (words.Length - 1 != items!.Count) Fail("BAD ASSIGNMENT");
        var assigned = new SortedDictionary<int, Bin>();
        for (int i = 0; i < items.Count; i++)
        {
            int label = Num(words[i + 1]);
            if (label == 0) Fail("BAD ASSIGNMENT");
            if (!assigned.TryGetValue(label, out Bin? bin))
            {
                bin = new Bin();
                assigned[label] = bin;
            }
            bin.Put(items[i]);
        }
        int over = assigned.Values.Count(bin => bin.Load > capacity);
        int lower = PackingAlgorithms.Bounds(items, capacity).L2;
        Emit($"CHECK bins={assigned.Count} over={over} L2={lower} "
            + $"status={(over == 0 ? "valid" : "invalid")}");
        foreach (var pair in assigned)
            BinLine(pair.Key, pair.Value, capacity, over: pair.Value.Load > capacity);
    }

    private void CoverLines(string name, List<Bin> bins)
    {
        var covered = bins.Where(bin => bin.Load >= capacity).ToList();
        Bin? rest = bins.FirstOrDefault(bin => bin.Load < capacity);
        Emit($"{name} covered={covered.Count} rest={rest?.Load ?? 0}");
        BinLines(covered);
        if (rest != null) Emit("REST items=" + string.Join(" ", rest.Items));
    }

    private void Cover()
    {
        Emit($"COVER total={Total} upper={Total / capacity}");
        var sequential = new List<Bin>();
        foreach (Item item in items!)
        {
            if (sequential.Count == 0 || sequential[^1].Load >= capacity)
                sequential.Add(new Bin());
            sequential[^1].Put(item);
        }
        CoverLines("DNF", sequential);

        var ordered = PackingAlgorithms.Descending(items);
        var paired = new List<Bin>();
        int first = 0, last = ordered.Count - 1;
        while (first <= last)
        {
            var bin = new Bin();
            bin.Put(ordered[first++]);
            while (bin.Load < capacity && first <= last) bin.Put(ordered[last--]);
            paired.Add(bin);
        }
        CoverLines("BIGSMALL", paired);
    }

    private void MachineLines(IEnumerable<Bin> bins)
    {
        int number = 1;
        foreach (Bin bin in bins)
        {
            string itemsText = string.Join(" ", bin.Items);
            if (itemsText.Length == 0) itemsText = "-";
            Emit($"MACHINE {number++} load={bin.Load} items={itemsText}");
        }
    }

    private void Multifit(int count)
    {
        if (count == 0) Fail("BAD PARAMETER");
        int largest = items!.Max(item => item.Size);
        int low = (int) Math.Max(PackingAlgorithms.Ceil(Total, count), largest);
        int high = (int) Math.Max(PackingAlgorithms.Ceil(2 * Total, count), largest);
        Emit($"MULTIFIT m={count} lower={low} upper={high}");
        while (low < high)
        {
            int middle = low + (high - low) / 2;
            int bins = PackingAlgorithms.Pack(items, middle, "FFD").Bins.Count;
            bool fits = bins <= count;
            Emit($"TRY cap={middle} bins={bins} {(fits ? "ok" : "fail")}");
            if (fits) high = middle;
            else low = middle + 1;
        }
        var machines = PackingAlgorithms.Pack(items, high, "FFD").Bins;
        while (machines.Count < count) machines.Add(new Bin());
        Emit($"RESULT cap={high} makespan={machines.Max(bin => bin.Load)}");
        MachineLines(machines);

        var lpt = Enumerable.Range(0, count).Select(_ => new Bin()).ToList();
        foreach (Item item in PackingAlgorithms.Descending(items))
        {
            Bin chosen = lpt.OrderBy(bin => bin.Load).First();
            chosen.Put(item);
        }
        Emit($"LPT makespan={lpt.Max(bin => bin.Load)}");
        MachineLines(lpt);
    }

    private void Cutstock(string[] words)
    {
        int length = Num(words[1]);
        if (length == 0) Fail("BAD CAPACITY");
        var pieces = new List<Piece>();
        var seen = new HashSet<int>();
        for (int i = 2; i < words.Length; i++)
        {
            string[] parts = words[i].Split(':');
            int size = Num(parts[0]), demand = Num(parts[1]);
            if (size == 0 || size > length || demand == 0) Fail($"BAD PIECE {i - 1}");
            if (!seen.Add(size)) Fail($"DUPLICATE PIECE {i - 1}");
            pieces.Add(new Piece(size, demand));
        }
        pieces = pieces.OrderByDescending(piece => piece.Length).ToList();
        var patterns = new List<Pattern>();
        var counts = new int[pieces.Count];

        void Enumerate(int index, int remaining)
        {
            int maximum = remaining / pieces[index].Length;
            if (index == pieces.Count - 1)
            {
                counts[index] = maximum;
                patterns.Add(new Pattern((int[]) counts.Clone(),
                    remaining - maximum * pieces[index].Length));
                return;
            }
            for (int i = maximum; i >= 0; i--)
            {
                counts[index] = i;
                Enumerate(index + 1, remaining - i * pieces[index].Length);
            }
        }

        Enumerate(0, length);
        Emit($"CUTSTOCK L={length} pieces={pieces.Count} patterns={patterns.Count}");
        for (int i = 0; i < patterns.Count; i++)
        {
            Pattern pattern = patterns[i];
            var breakdown = Enumerable.Range(0, pieces.Count)
                .Where(index => pattern.Counts[index] > 0)
                .Select(index => $"{pattern.Counts[index]}x{pieces[index].Length}");
            Emit($"PATTERN {i + 1} {string.Join("+", breakdown)} rest={pattern.Trim}");
        }

        int[] remainingDemand = pieces.Select(piece => piece.Demand).ToArray();
        int[] cut = new int[pieces.Count];
        int[] used = new int[patterns.Count];
        while (remainingDemand.Any(value => value > 0))
        {
            int chosen = -1, maximum = -1;
            for (int index = 0; index < patterns.Count; index++)
            {
                int useful = Enumerable.Range(0, pieces.Count)
                    .Sum(i => Math.Min(patterns[index].Counts[i], remainingDemand[i]));
                if (useful > maximum) { maximum = useful; chosen = index; }
            }
            used[chosen]++;
            for (int i = 0; i < pieces.Count; i++)
            {
                cut[i] += patterns[chosen].Counts[i];
                remainingDemand[i] = Math.Max(0, remainingDemand[i] - patterns[chosen].Counts[i]);
            }
        }
        int bars = 0, trim = 0;
        for (int i = 0; i < used.Length; i++)
        {
            if (used[i] == 0) continue;
            Emit($"USE {i + 1} bars={used[i]}");
            bars += used[i];
            trim += used[i] * patterns[i].Trim;
        }
        long total = pieces.Sum(piece => (long) piece.Length * piece.Demand);
        int demandTotal = pieces.Sum(piece => piece.Demand);
        int cutTotal = 0;
        var stock = new List<Item>();
        for (int i = 0; i < pieces.Count; i++)
        {
            Piece piece = pieces[i];
            Emit($"PIECE {piece.Length} demand={piece.Demand} cut={cut[i]}");
            cutTotal += cut[i];
            for (int j = 0; j < piece.Demand; j++)
                stock.Add(new Item(stock.Count + 1, piece.Length));
        }
        Emit($"TOTAL bars={bars} trim={trim} surplus={cutTotal - demandTotal} "
            + $"waste={bars * (long) length - total}");
        int ffd = PackingAlgorithms.Pack(stock, length, "FIRSTFIT").Bins.Count;
        Emit($"FFD bars={ffd} waste={ffd * (long) length - total}");
        Emit($"LOWER bars={PackingAlgorithms.Ceil(total, length)}");
    }

    private static List<Rect> Rectangles(string[] words, int start,
                                         int width, int height, bool rotate)
    {
        var rectangles = new List<Rect>();
        for (int i = start; i < words.Length; i++)
        {
            string[] sizes = words[i].Split('x');
            int w = Num(sizes[0]), h = Num(sizes[1]);
            bool fits = height == 0 ? w <= width
                : (w <= width && h <= height) || (rotate && h <= width && w <= height);
            if (w == 0 || h == 0 || !fits) Fail($"BAD RECT {i - start + 1}");
            rectangles.Add(new Rect(i - start + 1, w, h));
        }
        return rectangles;
    }

    private void Draw(int width, int height, IEnumerable<Placement> placements)
    {
        char[][] grid = Enumerable.Range(0, height)
            .Select(_ => Enumerable.Repeat('.', width).ToArray()).ToArray();
        foreach (Placement placement in placements)
        {
            for (int y = placement.Y; y < placement.Y + placement.Height; y++)
                for (int x = placement.X; x < placement.X + placement.Width; x++)
                    grid[y][x] = placement.Rect.Letter;
        }
        for (int y = height - 1; y >= 0; y--) Emit(new string(grid[y]));
    }

    private void ShelfCommand(string[] words)
    {
        int width = Num(words[1]);
        if (width == 0) Fail("BAD CAPACITY");
        var rectangles = Rectangles(words, 2, width, 0, false);
        int area = rectangles.Sum(rect => rect.Area);
        Emit($"SHELF W={width} rects={rectangles.Count} area={area}");
        var ordered = rectangles.OrderByDescending(rect => rect.Height)
            .ThenByDescending(rect => rect.Width).ThenBy(rect => rect.Number).ToList();
        foreach (string method in new[] { "NFDH", "FFDH", "BFDH" })
        {
            var shelves = new List<Shelf>();
            var placements = new List<Placement>();
            foreach (Rect rect in ordered)
            {
                Shelf? chosen = null;
                if (method == "NFDH")
                {
                    if (shelves.Count > 0 && shelves[^1].Used + rect.Width <= width)
                        chosen = shelves[^1];
                }
                else
                {
                    var fitting = shelves.Where(shelf => shelf.Used + rect.Width <= width);
                    chosen = method == "FFDH" ? fitting.FirstOrDefault()
                        : fitting.OrderByDescending(shelf => shelf.Used).FirstOrDefault();
                }
                if (chosen == null)
                {
                    int bottom = shelves.Count == 0 ? 0 : shelves[^1].Bottom + shelves[^1].Height;
                    chosen = new Shelf(bottom, rect.Height);
                    shelves.Add(chosen);
                }
                var placement = new Placement(rect, chosen.Used, chosen.Bottom, rect.Width, rect.Height);
                chosen.Placements.Add(placement);
                placements.Add(placement);
                chosen.Used += rect.Width;
            }
            int height = shelves[^1].Bottom + shelves[^1].Height;
            Emit($"{method} height={height} shelves={shelves.Count} util={area * 100 / (width * height)}");
            for (int i = 0; i < shelves.Count; i++)
            {
                Shelf shelf = shelves[i];
                string contents = string.Join(" ", shelf.Placements.Select(p => $"{p.Rect.Letter}@{p.X}"));
                Emit($"LEVEL {i + 1} y={shelf.Bottom} h={shelf.Height} used={shelf.Used} items={contents}");
            }
            Draw(width, height, placements);
        }
        int[] columns = new int[width];
        var skyline = new List<Placement>();
        foreach (Rect rect in ordered)
        {
            int chosenX = 0, chosenY = int.MaxValue;
            for (int x = 0; x <= width - rect.Width; x++)
            {
                int top = columns.Skip(x).Take(rect.Width).Max();
                if (top < chosenY) { chosenX = x; chosenY = top; }
            }
            skyline.Add(new Placement(rect, chosenX, chosenY, rect.Width, rect.Height));
            for (int x = chosenX; x < chosenX + rect.Width; x++)
                columns[x] = chosenY + rect.Height;
        }
        int skylineHeight = columns.Max();
        Emit($"SKYLINE height={skylineHeight} util={area * 100 / (width * skylineHeight)}");
        foreach (Placement p in skyline)
            Emit($"PLACE {p.Rect.Letter} x={p.X} y={p.Y} w={p.Width} h={p.Height}");
        Draw(width, skylineHeight, skyline);
    }

    private static bool Fits(Rect rect, FreeRect free, bool rotate) =>
        (rect.Width <= free.Width && rect.Height <= free.Height)
        || (rotate && rect.Height <= free.Width && rect.Width <= free.Height);

    private void Guillotine(string[] words)
    {
        int width = Num(words[1]), height = Num(words[2]);
        if (width == 0 || height == 0) Fail("BAD CAPACITY");
        bool rotate = words[3] == "ROTATE";
        bool best = words[4] == "BEST";
        var ordered = Rectangles(words, 5, width, height, rotate)
            .OrderByDescending(rect => rect.Area).ThenBy(rect => rect.Number).ToList();
        var sheets = new List<Sheet>();
        int rotated = 0, totalArea = ordered.Sum(rect => rect.Area);
        foreach (Rect rect in ordered)
        {
            Sheet? selected = null;
            int chosenIndex = -1, chosenArea = int.MaxValue;
            foreach (Sheet sheet in sheets)
            {
                for (int i = 0; i < sheet.Free.Count; i++)
                {
                    FreeRect free = sheet.Free[i];
                    if (!Fits(rect, free, rotate)) continue;
                    if (selected == null || (best && free.Area < chosenArea))
                    {
                        selected = sheet;
                        chosenIndex = i;
                        chosenArea = free.Area;
                    }
                    if (!best) break;
                }
                if (selected != null && !best) break;
            }
            if (selected == null)
            {
                selected = new Sheet(width, height);
                sheets.Add(selected);
                chosenIndex = 0;
            }
            FreeRect target = selected.Free[chosenIndex];
            selected.Free.RemoveAt(chosenIndex);
            bool turned = rect.Width > target.Width || rect.Height > target.Height;
            int w = turned ? rect.Height : rect.Width;
            int h = turned ? rect.Width : rect.Height;
            if (turned) rotated++;
            selected.Placements.Add(new Placement(rect, target.X, target.Y, w, h, turned));
            selected.Area += rect.Area;
            int rw = target.Width - w, rh = target.Height - h;
            FreeRect top = rw <= rh
                ? new FreeRect(target.X, target.Y + h, target.Width, rh)
                : new FreeRect(target.X, target.Y + h, w, rh);
            FreeRect right = rw <= rh
                ? new FreeRect(target.X + w, target.Y, rw, h)
                : new FreeRect(target.X + w, target.Y, rw, target.Height);
            if (top.Width > 0 && top.Height > 0) selected.Free.Add(top);
            if (right.Width > 0 && right.Height > 0) selected.Free.Add(right);
        }
        int count = sheets.Count;
        Emit($"GUILLOTINE W={width} H={height} mode={words[3]} rule={words[4]} "
            + $"rects={ordered.Count} sheets={count} rotated={rotated} "
            + $"util={totalArea * 100 / (count * width * height)}");
        for (int i = 0; i < sheets.Count; i++)
        {
            Sheet sheet = sheets[i];
            Emit($"SHEET {i + 1} placed={sheet.Placements.Count} area={sheet.Area}");
            foreach (Placement p in sheet.Placements)
                Emit($"PLACE {p.Rect.Letter} x={p.X} y={p.Y} w={p.Width} h={p.Height}"
                    + (p.Rotated ? " rotated" : ""));
            Emit(sheet.Free.Count == 0 ? "FREE none" : "FREE " + string.Join(" ", sheet.Free));
            Draw(width, height, sheet.Placements);
        }
    }

    public void Process(string[] words)
    {
        try
        {
            string command = words[0];
            switch (command)
            {
                case "ITEMS": ItemsCommand(words); return;
                case "RANDOM": RandomCommand(words); return;
                case "CUTSTOCK": Cutstock(words); return;
                case "SHELF": ShelfCommand(words); return;
                case "GUILLOTINE": Guillotine(words); return;
            }
            if (items == null) Fail("NO ITEMS");
            switch (command)
            {
                case "NEXTFIT":
                case "FIRSTFIT":
                case "BESTFIT":
                case "WORSTFIT":
                case "ALMOSTWORST":
                case "HARMONIC":
                case "KBOUNDED":
                case "FFD":
                case "BFD":
                case "WFD":
                    MethodCommand(command, Parameter(command, words, 1));
                    break;
                case "TRACE":
                    Trace(words[1], Parameter(words[1], words, 2));
                    break;
                case "REDUCE":
                    Reduce(words[1], Parameter(words[1], words, 2));
                    break;
                case "BOUNDS": BoundsCommand(); break;
                case "COMPARE": Compare(Num(words[1])); break;
                case "EXACT": Exact(Num(words[1])); break;
                case "CHECK": Check(words); break;
                case "COVER": Cover(); break;
                case "MULTIFIT": Multifit(Num(words[1])); break;
            }
        }
        catch (CommandError error)
        {
            Emit("ERROR " + error.Message);
        }
    }
}

static class Program
{
    static void Main()
    {
        string? first = Console.ReadLine();
        if (first == null) return;
        int count = int.Parse(first);
        var lab = new Lab();
        for (int i = 0; i < count; i++)
            lab.Process(Console.ReadLine()!.Split(' '));
        Console.Write(lab.ToString());
    }
}
