using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

enum Operation { SUM, MIN, MAX, GCD }

sealed class CommandError(string message) : Exception(message);

static class Arithmetic
{
    public static long Gcd(long a, long b)
    {
        a = Math.Abs(a);
        b = Math.Abs(b);
        while (b != 0) (a, b) = (b, a % b);
        return a;
    }

    public static int IntegerSqrt(int n)
    {
        int result = 1;
        while ((result + 1) * (result + 1) <= n) result++;
        return result;
    }

    public static int Log2(int n)
    {
        int result = 0;
        while ((1 << (result + 1)) <= n) result++;
        return result;
    }

    public static long Combine(Operation op, long a, long b) => op switch
    {
        Operation.SUM => a + b,
        Operation.MIN => Math.Min(a, b),
        Operation.MAX => Math.Max(a, b),
        _ => Gcd(a, b)
    };
}

readonly record struct Interval(int Left, int Right)
{
    public bool Leaf => Left == Right;
    public int Middle => (Left + Right) / 2;
    public int Length => Right - Left + 1;
    public bool Covered(int left, int right) => left <= Left && Right <= right;
}

sealed class Layout
{
    readonly Interval?[] ranges;
    public int Count { get; }
    public int MaxNode { get; private set; }
    public Interval this[int node] => ranges[node]!.Value;

    public Layout(int n)
    {
        ranges = new Interval?[4 * n];
        Count = 2 * n - 1;
        Build(1, 0, n - 1);
    }

    void Build(int node, int left, int right)
    {
        ranges[node] = new(left, right);
        MaxNode = Math.Max(MaxNode, node);
        if (left == right) return;
        int middle = (left + right) / 2;
        Build(2 * node, left, middle);
        Build(2 * node + 1, middle + 1, right);
    }

    public IEnumerable<(int Node, Interval Range)> Nodes()
    {
        for (int node = 1; node <= MaxNode; node++)
            if (ranges[node] is Interval range) yield return (node, range);
    }
}

readonly record struct SumAnswer(long Sum, int Visited)
{
    public string Text => $"sum={Sum} visited={Visited}";
}

sealed class SegmentTree
{
    public Operation Op { get; }
    public Layout Shape { get; }
    readonly long[] values;
    public long Root => values[1];
    public string Name => Op.ToString().ToLowerInvariant();

    public SegmentTree(long[] contents, Operation op)
    {
        Op = op;
        Shape = new(contents.Length);
        values = new long[4 * contents.Length];
        Build(1, contents);
    }

    void Build(int node, long[] contents)
    {
        Interval range = Shape[node];
        if (range.Leaf) values[node] = Op == Operation.GCD ? Math.Abs(contents[range.Left]) : contents[range.Left];
        else
        {
            Build(2 * node, contents);
            Build(2 * node + 1, contents);
            Pull(node);
        }
    }

    void Pull(int node) => values[node] = Arithmetic.Combine(Op, values[2 * node], values[2 * node + 1]);

    public SumAnswer Query(int left, int right, int node = 1)
    {
        Interval range = Shape[node];
        if (range.Covered(left, right)) return new(values[node], 1);
        if (right <= range.Middle)
        {
            SumAnswer child = Query(left, right, 2 * node);
            return child with { Visited = child.Visited + 1 };
        }
        if (left > range.Middle)
        {
            SumAnswer child = Query(left, right, 2 * node + 1);
            return child with { Visited = child.Visited + 1 };
        }
        SumAnswer a = Query(left, right, 2 * node);
        SumAnswer b = Query(left, right, 2 * node + 1);
        return new(Arithmetic.Combine(Op, a.Sum, b.Sum), a.Visited + b.Visited + 1);
    }

    public int Update(int index, long value, int node = 1)
    {
        Interval range = Shape[node];
        if (range.Leaf)
        {
            values[node] = Op == Operation.GCD ? Math.Abs(value) : value;
            return 1;
        }
        int visited = Update(index, value, index <= range.Middle ? 2 * node : 2 * node + 1);
        Pull(node);
        return visited + 1;
    }

    public string Describe(SumAnswer answer) => $"{Name}={answer.Sum} visited={answer.Visited}";
    public IEnumerable<string> Dump()
    {
        yield return $"SEG DUMP {Op} nodes={Shape.Count}";
        foreach (var (node, range) in Shape.Nodes())
            yield return $"NODE {node} {range.Left} {range.Right} {values[node]}";
    }
}

readonly record struct Aggregate(long Sum, long Min, long Max)
{
    public static Aggregate Merge(Aggregate a, Aggregate b) => new(a.Sum + b.Sum, Math.Min(a.Min, b.Min), Math.Max(a.Max, b.Max));
    public string Text => $"sum={Sum} min={Min} max={Max}";
}

readonly record struct LazyAnswer(Aggregate Value, int Visited, int Pushes)
{
    public string Text => $"{Value.Text} visited={Visited} pushes={Pushes}";
}

sealed class Work
{
    public int Visited, Covered, Pushes;
    public override string ToString() => $"visited={Visited} covered={Covered} pushes={Pushes}";
}

sealed class LazyTree
{
    public Layout Shape { get; }
    readonly Aggregate[] values;
    readonly long?[] assign;
    readonly long[] add;
    public Aggregate Root => values[1];

    public LazyTree(long[] contents)
    {
        Shape = new(contents.Length);
        values = new Aggregate[4 * contents.Length];
        assign = new long?[values.Length];
        add = new long[values.Length];
        Build(1, contents);
    }

    void Build(int node, long[] contents)
    {
        Interval range = Shape[node];
        if (range.Leaf) values[node] = new(contents[range.Left], contents[range.Left], contents[range.Left]);
        else
        {
            Build(2 * node, contents);
            Build(2 * node + 1, contents);
            Pull(node);
        }
    }

    void Pull(int node) => values[node] = Aggregate.Merge(values[2 * node], values[2 * node + 1]);

    void Apply(int node, long value, bool assignment)
    {
        Interval range = Shape[node];
        Aggregate old = values[node];
        values[node] = assignment ? new(value * range.Length, value, value)
            : new(old.Sum + value * range.Length, old.Min + value, old.Max + value);
        if (range.Leaf) return;
        if (assignment) { assign[node] = value; add[node] = 0; }
        else add[node] += value;
    }

    int Push(int node)
    {
        if (assign[node] is null && add[node] == 0) return 0;
        for (int child = 2 * node; child <= 2 * node + 1; child++)
        {
            if (assign[node] is long value) Apply(child, value, true);
            if (add[node] != 0) Apply(child, add[node], false);
        }
        assign[node] = null;
        add[node] = 0;
        return 1;
    }

    public Work Update(int left, int right, long value, bool assignment)
    {
        Work work = new();
        void Visit(int node)
        {
            work.Visited++;
            Interval range = Shape[node];
            if (range.Covered(left, right))
            {
                work.Covered++;
                Apply(node, value, assignment);
                return;
            }
            work.Pushes += Push(node);
            if (left <= range.Middle) Visit(2 * node);
            if (right > range.Middle) Visit(2 * node + 1);
            Pull(node);
        }
        Visit(1);
        return work;
    }

    public LazyAnswer Query(int left, int right, int node = 1)
    {
        Interval range = Shape[node];
        if (range.Covered(left, right)) return new(values[node], 1, 0);
        int pushes = Push(node);
        if (right <= range.Middle || left > range.Middle)
        {
            LazyAnswer child = Query(left, right, right <= range.Middle ? 2 * node : 2 * node + 1);
            return new(child.Value, child.Visited + 1, child.Pushes + pushes);
        }
        LazyAnswer a = Query(left, right, 2 * node);
        LazyAnswer b = Query(left, right, 2 * node + 1);
        return new(Aggregate.Merge(a.Value, b.Value), a.Visited + b.Visited + 1, a.Pushes + b.Pushes + pushes);
    }

    public IEnumerable<string> Dump()
    {
        yield return $"LAZY DUMP nodes={Shape.Count}";
        foreach (var (node, range) in Shape.Nodes())
            yield return $"NODE {node} {range.Left} {range.Right} {values[node].Text} assign={assign[node]?.ToString() ?? "-"} add={add[node]}";
    }
}

sealed class Fenwick
{
    public long[] T { get; }
    public int N => T.Length - 1;
    public Fenwick(int n) => T = new long[n + 1];

    public int Add(int position, long value)
    {
        int visited = 0;
        for (; position <= N; position += position & -position) { T[position] += value; visited++; }
        return visited;
    }

    public SumAnswer Prefix(int position)
    {
        long sum = 0;
        int visited = 0;
        for (; position > 0; position -= position & -position) { sum += T[position]; visited++; }
        return new(sum, visited);
    }

    public string Dump(string name) => name + " " + string.Join(" ", T.Skip(1));
}

sealed class PointFenwick
{
    public long[] Contents { get; }
    public Fenwick Bits { get; }
    public PointFenwick(long[] contents)
    {
        Contents = (long[])contents.Clone();
        Bits = new(contents.Length);
        for (int i = 0; i < contents.Length; i++) Bits.Add(i + 1, contents[i]);
    }

    public int Add(int index, long value)
    {
        Contents[index] += value;
        return Bits.Add(index + 1, value);
    }

    public SumAnswer Query(int left, int right)
    {
        SumAnswer a = Bits.Prefix(right + 1), b = Bits.Prefix(left);
        return new(a.Sum - b.Sum, a.Visited + b.Visited);
    }

    public (int? Index, int Visited) Lower(long rest)
    {
        int position = 0, visited = 0;
        for (int step = 1 << Arithmetic.Log2(Contents.Length); step >= 1; step /= 2)
        {
            if (position + step > Contents.Length) continue;
            visited++;
            long value = Bits.T[position + step];
            if (value < rest) { rest -= value; position += step; }
        }
        return (position == Contents.Length ? null : position, visited);
    }
}

sealed class RangeFenwick
{
    public Fenwick B1 { get; }
    public Fenwick B2 { get; }
    public RangeFenwick(long[] contents)
    {
        B1 = new(contents.Length);
        B2 = new(contents.Length);
        for (int i = 0; i < contents.Length; i++)
        {
            long difference = contents[i] - (i == 0 ? 0 : contents[i - 1]);
            B1.Add(i + 1, difference);
            B2.Add(i + 1, i * difference);
        }
    }

    public int Add(int left, int right, long value)
    {
        int visited = B1.Add(left + 1, value);
        visited += B1.Add(right + 2, -value);
        visited += B2.Add(left + 1, value * left);
        visited += B2.Add(right + 2, -value * (right + 1));
        return visited;
    }

    SumAnswer Prefix(int position)
    {
        SumAnswer a = B1.Prefix(position), b = B2.Prefix(position);
        return new(position * a.Sum - b.Sum, a.Visited + b.Visited);
    }

    public SumAnswer Query(int left, int right)
    {
        SumAnswer a = Prefix(right + 1), b = Prefix(left);
        return new(a.Sum - b.Sum, a.Visited + b.Visited);
    }
}

readonly record struct SparseAnswer(long Min, int MinPosition, long Max, int MaxPosition, int Level)
{
    public string Text => $"min={Min} minpos={MinPosition} max={Max} maxpos={MaxPosition} level={Level}";
}

sealed class SparseTable
{
    readonly long[] contents;
    public List<int[]> Minimum { get; } = [];
    public List<int[]> Maximum { get; } = [];
    public int Entries => Minimum.Sum(row => row.Length);

    public SparseTable(long[] values)
    {
        contents = (long[])values.Clone();
        Minimum.Add(Enumerable.Range(0, values.Length).ToArray());
        Maximum.Add(Enumerable.Range(0, values.Length).ToArray());
        for (int level = 1; (1 << level) <= values.Length; level++)
        {
            int length = values.Length - (1 << level) + 1, half = 1 << (level - 1);
            int[] minima = new int[length], maxima = new int[length];
            for (int i = 0; i < length; i++)
            {
                minima[i] = Select(Minimum[level - 1][i], Minimum[level - 1][i + half], true);
                maxima[i] = Select(Maximum[level - 1][i], Maximum[level - 1][i + half], false);
            }
            Minimum.Add(minima);
            Maximum.Add(maxima);
        }
    }

    int Select(int a, int b, bool minimum) => (minimum ? contents[a] <= contents[b] : contents[a] >= contents[b]) ? a : b;

    public SparseAnswer Query(int left, int right)
    {
        int level = Arithmetic.Log2(right - left + 1), end = right - (1 << level) + 1;
        int a = Select(Minimum[level][left], Minimum[level][end], true);
        int z = Select(Maximum[level][left], Maximum[level][end], false);
        return new(contents[a], a, contents[z], z, level);
    }

    public IEnumerable<string> Dump()
    {
        yield return $"SPARSE DUMP levels={Minimum.Count}";
        for (int level = 0; level < Minimum.Count; level++)
        {
            yield return $"MIN {level} " + string.Join(" ", Minimum[level]);
            yield return $"MAX {level} " + string.Join(" ", Maximum[level]);
        }
    }
}

readonly record struct Split(List<int> Cells, List<int> Whole)
{
    public string Text => $"whole={Whole.Count} cells={Cells.Count}";
}

readonly record struct SqrtAnswer(long Sum, Split Split)
{
    public string Text => $"sum={Sum} {Split.Text}";
}

sealed class SqrtBlocks
{
    readonly long[] raw, tag, sums;
    public int BlockSize { get; }
    public int Count => tag.Length;

    public SqrtBlocks(long[] contents, int blockSize)
    {
        BlockSize = blockSize;
        raw = (long[])contents.Clone();
        tag = new long[(contents.Length + blockSize - 1) / blockSize];
        sums = new long[tag.Length];
        for (int i = 0; i < raw.Length; i++) sums[i / blockSize] += raw[i];
    }

    Split Partition(int left, int right)
    {
        List<int> cells = [], whole = [];
        int first = left / BlockSize, last = right / BlockSize;
        if (first == last)
        {
            for (int i = left; i <= right; i++) cells.Add(i);
        }
        else
        {
            for (int i = left; i < (first + 1) * BlockSize; i++) cells.Add(i);
            for (int i = last * BlockSize; i <= right; i++) cells.Add(i);
            for (int block = first + 1; block < last; block++) whole.Add(block);
        }
        return new(cells, whole);
    }

    public Split Add(int left, int right, long value)
    {
        Split split = Partition(left, right);
        foreach (int i in split.Cells) { raw[i] += value; sums[i / BlockSize] += value; }
        foreach (int block in split.Whole) { tag[block] += value; sums[block] += value * BlockSize; }
        return split;
    }

    public SqrtAnswer Query(int left, int right)
    {
        Split split = Partition(left, right);
        long sum = 0;
        foreach (int i in split.Cells) sum += raw[i] + tag[i / BlockSize];
        foreach (int block in split.Whole) sum += sums[block];
        return new(sum, split);
    }

    public IEnumerable<string> Dump()
    {
        yield return $"SQRT DUMP block={BlockSize} blocks={Count}";
        for (int block = 0; block < Count; block++)
        {
            int first = block * BlockSize, end = Math.Min((block + 1) * BlockSize, raw.Length);
            yield return $"BLOCK {block} {first} {end - 1} add={tag[block]} sum={sums[block]} " + string.Join(" ", raw[first..end]);
        }
    }
}

sealed record PersistentNode(long Value, PersistentNode? Left = null, PersistentNode? Right = null);

sealed class PersistentTree
{
    readonly int n;
    readonly long[] values;
    readonly List<PersistentNode> valueRoots = [];
    public List<PersistentNode> Versions { get; } = [];
    public int PositionNodes { get; private set; }
    public int ValueNodes { get; private set; }
    public int Distinct => values.Length;

    public PersistentTree(long[] contents)
    {
        n = contents.Length;
        Versions.Add(Build(contents, 0, n - 1));
        PositionNodes = 2 * n - 1;
        values = contents.Distinct().Order().ToArray();
        valueRoots.Add(Build(new long[values.Length], 0, values.Length - 1));
        ValueNodes = 2 * values.Length - 1;
        foreach (long value in contents)
        {
            int created = 0;
            int rank = Array.BinarySearch(values, value);
            valueRoots.Add(Change(valueRoots[^1], 0, values.Length - 1, rank, 1, true, ref created));
            ValueNodes += created;
        }
    }

    static PersistentNode Build(long[] contents, int left, int right)
    {
        if (left == right) return new(contents[left]);
        int middle = (left + right) / 2;
        PersistentNode a = Build(contents, left, middle);
        PersistentNode b = Build(contents, middle + 1, right);
        return new(a.Value + b.Value, a, b);
    }

    static PersistentNode Change(PersistentNode node, int left, int right, int index, long value, bool increment, ref int created)
    {
        created++;
        if (left == right) return new(increment ? node.Value + value : value);
        int middle = (left + right) / 2;
        PersistentNode a = node.Left!, b = node.Right!;
        if (index <= middle) a = Change(a, left, middle, index, value, increment, ref created);
        else b = Change(b, middle + 1, right, index, value, increment, ref created);
        return new(a.Value + b.Value, a, b);
    }

    public int Set(int version, int index, long value)
    {
        int created = 0;
        Versions.Add(Change(Versions[version], 0, n - 1, index, value, false, ref created));
        PositionNodes += created;
        return created;
    }

    static SumAnswer Sum(PersistentNode node, int nl, int nr, int left, int right)
    {
        if (left <= nl && nr <= right) return new(node.Value, 1);
        int middle = (nl + nr) / 2;
        if (right <= middle)
        {
            SumAnswer answer = Sum(node.Left!, nl, middle, left, right);
            return answer with { Visited = answer.Visited + 1 };
        }
        if (left > middle)
        {
            SumAnswer answer = Sum(node.Right!, middle + 1, nr, left, right);
            return answer with { Visited = answer.Visited + 1 };
        }
        SumAnswer a = Sum(node.Left!, nl, middle, left, right);
        SumAnswer b = Sum(node.Right!, middle + 1, nr, left, right);
        return new(a.Sum + b.Sum, a.Visited + b.Visited + 1);
    }

    public SumAnswer Query(int version, int left, int right) => Sum(Versions[version], 0, n - 1, left, right);

    public SumAnswer Kth(int left, int right, int k)
    {
        PersistentNode u = valueRoots[right + 1], w = valueRoots[left];
        int p = 0, q = values.Length - 1, visited = 1;
        while (p < q)
        {
            int middle = (p + q) / 2;
            long difference = u.Left!.Value - w.Left!.Value;
            if (k <= difference) { u = u.Left; w = w.Left; q = middle; }
            else { k -= (int)difference; u = u.Right!; w = w.Right!; p = middle + 1; }
            visited++;
        }
        return new(values[p], visited);
    }
}

sealed class GridFenwick
{
    public int Height { get; }
    public int Width { get; }
    readonly long[,] tree;
    public GridFenwick(int height, int width, long[] contents)
    {
        Height = height;
        Width = width;
        tree = new long[height + 1, width + 1];
        for (int i = 0; i < height; i++)
            for (int j = 0; j < width; j++) Add(i, j, contents[i * width + j]);
    }

    public int Add(int row, int column, long value)
    {
        int visited = 0;
        for (int y = row + 1; y <= Height; y += y & -y)
            for (int z = column + 1; z <= Width; z += z & -z) { tree[y, z] += value; visited++; }
        return visited;
    }

    SumAnswer Prefix(int row, int column)
    {
        long sum = 0;
        int visited = 0;
        for (int y = row; y > 0; y -= y & -y)
            for (int z = column; z > 0; z -= z & -z) { sum += tree[y, z]; visited++; }
        return new(sum, visited);
    }

    public SumAnswer Query(int top, int left, int bottom, int right)
    {
        SumAnswer a = Prefix(bottom + 1, right + 1), b = Prefix(top, right + 1);
        SumAnswer c = Prefix(bottom + 1, left), d = Prefix(top, left);
        return new(a.Sum - b.Sum - c.Sum + d.Sum, a.Visited + b.Visited + c.Visited + d.Visited);
    }

    public IEnumerable<string> Dump()
    {
        yield return $"GRID DUMP rows={Height} cols={Width}";
        for (int row = 1; row <= Height; row++)
            yield return $"ROW {row} " + string.Join(" ", Enumerable.Range(1, Width).Select(column => tree[row, column]));
    }
}

readonly record struct MoQuery(int Left, int Right, int Number);

sealed class Laboratory
{
    long[] array, original;
    SegmentTree? segment;
    LazyTree? lazy;
    PointFenwick? fenwick;
    RangeFenwick? rangeFenwick;
    SparseTable? sparse;
    SqrtBlocks? sqrt;
    PersistentTree? persistent;
    GridFenwick? grid;
    int StructureCount => (segment is null ? 0 : 1) + (lazy is null ? 0 : 1) + (fenwick is null ? 0 : 1)
        + (rangeFenwick is null ? 0 : 1) + (sparse is null ? 0 : 1) + (sqrt is null ? 0 : 1) + (persistent is null ? 0 : 1);

    public Laboratory(long[] values)
    {
        array = (long[])values.Clone();
        original = (long[])values.Clone();
    }

    static T Need<T>(T? structure, string kind) where T : class => structure ?? throw new CommandError("NOT BUILT " + kind);
    void CheckIndex(int index)
    {
        if (index < 0 || index >= array.Length) throw new CommandError($"BAD INDEX {index}");
    }
    void CheckRange(int left, int right)
    {
        CheckIndex(left);
        CheckIndex(right);
        if (left > right) throw new CommandError($"BAD RANGE {left} {right}");
    }
    static void CheckVersion(PersistentTree tree, int version)
    {
        if (version < 0 || version >= tree.Versions.Count) throw new CommandError($"BAD VERSION {version}");
    }
    static void CheckCell(GridFenwick tree, int row, int column)
    {
        if (row < 0 || row >= tree.Height || column < 0 || column >= tree.Width)
            throw new CommandError($"BAD CELL {row} {column}");
    }
    void ChangeArray(int left, int right, long value, bool assignment = false)
    {
        for (int i = left; i <= right; i++) array[i] = assignment ? value : array[i] + value;
    }

    List<string> Check(int left, int right)
    {
        CheckRange(left, right);
        long sum = 0, minimum = array[left], maximum = array[left], gcd = 0;
        for (int i = left; i <= right; i++)
        {
            sum += array[i];
            minimum = Math.Min(minimum, array[i]);
            maximum = Math.Max(maximum, array[i]);
            gcd = Arithmetic.Gcd(gcd, array[i]);
        }
        List<string> rows = [$"CHECK {left} {right} sum={sum} min={minimum} max={maximum} gcd={gcd}"];
        int ok = 0, diff = 0;
        void Report(string kind, bool equal, string text)
        {
            if (equal) ok++; else diff++;
            rows.Add($"{kind} {(equal ? "OK" : "DIFF")} {text}");
        }
        if (segment is not null)
        {
            SumAnswer answer = segment.Query(left, right);
            long expected = segment.Op switch { Operation.SUM => sum, Operation.MIN => minimum, Operation.MAX => maximum, _ => gcd };
            Report("SEG", answer.Sum == expected, segment.Describe(answer));
        }
        if (lazy is not null)
        {
            LazyAnswer answer = lazy.Query(left, right);
            Report("LAZY", answer.Value == new Aggregate(sum, minimum, maximum), answer.Text);
        }
        if (fenwick is not null)
        {
            SumAnswer answer = fenwick.Query(left, right);
            Report("FEN", answer.Sum == sum, answer.Text);
        }
        if (rangeFenwick is not null)
        {
            SumAnswer answer = rangeFenwick.Query(left, right);
            Report("RFEN", answer.Sum == sum, answer.Text);
        }
        if (sparse is not null)
        {
            SparseAnswer answer = sparse.Query(left, right);
            Report("SPARSE", answer.Min == minimum && answer.Max == maximum, answer.Text);
        }
        if (sqrt is not null)
        {
            SqrtAnswer answer = sqrt.Query(left, right);
            Report("SQRT", answer.Sum == sum, answer.Text);
        }
        if (persistent is not null)
        {
            int version = persistent.Versions.Count - 1;
            SumAnswer answer = persistent.Query(version, left, right);
            Report("PERSIST", answer.Sum == sum, $"version={version} {answer.Text}");
        }
        rows.Add($"RESULT ok={ok} diff={diff}");
        return rows;
    }

    List<string> Mo(string[] words)
    {
        List<MoQuery> queries = [];
        for (int i = 1; i < words.Length; i += 2)
        {
            int left = int.Parse(words[i], CultureInfo.InvariantCulture), right = int.Parse(words[i + 1], CultureInfo.InvariantCulture);
            CheckRange(left, right);
            queries.Add(new(left, right, queries.Count + 1));
        }
        int blockSize = Arithmetic.IntegerSqrt(array.Length);
        MoQuery[] order = queries.OrderBy(q => q.Left / blockSize)
            .ThenBy(q => q.Left / blockSize % 2 == 0 ? q.Right : -q.Right).ThenBy(q => q.Number).ToArray();
        Dictionary<long, int> frequency = new();
        int[] answers = new int[queries.Count];
        int leftEdge = 0, rightEdge = -1, moves = 0;
        void Add(int i) { frequency.TryGetValue(array[i], out int old); frequency[array[i]] = old + 1; moves++; }
        void Remove(int i)
        {
            int count = frequency[array[i]] - 1;
            if (count == 0) frequency.Remove(array[i]); else frequency[array[i]] = count;
            moves++;
        }
        foreach (MoQuery query in order)
        {
            while (leftEdge > query.Left) Add(--leftEdge);
            while (rightEdge < query.Right) Add(++rightEdge);
            while (leftEdge < query.Left) Remove(leftEdge++);
            while (rightEdge > query.Right) Remove(rightEdge--);
            answers[query.Number - 1] = frequency.Count;
        }
        List<string> rows = [$"MO queries={queries.Count} block={blockSize} moves={moves}", "ORDER " + string.Join(" ", order.Select(q => q.Number))];
        foreach (MoQuery query in queries) rows.Add($"ANSWER {query.Number} {query.Left} {query.Right} distinct={answers[query.Number - 1]}");
        return rows;
    }

    public List<string> Execute(string line)
    {
        string[] words = line.Split(' ');
        long Number(int index) => long.Parse(words[index], CultureInfo.InvariantCulture);
        int Index(int index) => (int)Number(index);
        string kind = words[0];
        if (kind == "ARRAY")
        {
            int left = Index(1), right = Index(2);
            CheckRange(left, right);
            return [$"ARRAY {left} {right} " + string.Join(" ", array[left..(right + 1)])];
        }
        if (kind == "LOAD")
        {
            int removed = StructureCount;
            original = words.Skip(1).Select(value => long.Parse(value, CultureInfo.InvariantCulture)).ToArray();
            array = (long[])original.Clone();
            segment = null; lazy = null; fenwick = null; rangeFenwick = null; sparse = null; sqrt = null; persistent = null;
            return [$"LOAD n={array.Length} removed={removed}"];
        }
        if (kind == "RESET")
        {
            int rebuilt = StructureCount;
            array = (long[])original.Clone();
            if (segment is not null) segment = new(array, segment.Op);
            if (lazy is not null) lazy = new(array);
            if (fenwick is not null) fenwick = new(array);
            if (rangeFenwick is not null) rangeFenwick = new(array);
            if (sparse is not null) sparse = new(array);
            if (sqrt is not null) sqrt = new(array, sqrt.BlockSize);
            if (persistent is not null) persistent = new(array);
            return [$"RESET rebuilt={rebuilt}"];
        }
        if (kind == "CHECK") return Check(Index(1), Index(2));
        if (kind == "MO") return Mo(words);
        string action = words[1];
        switch (kind)
        {
            case "SEG":
            {
                if (action == "BUILD")
                {
                    if (!Enum.TryParse(words[2], out Operation operation)) throw new CommandError("BAD OP " + words[2]);
                    segment = new(array, operation);
                    return [$"SEG BUILD {operation} nodes={segment.Shape.Count} maxnode={segment.Shape.MaxNode} root={segment.Root}"];
                }
                SegmentTree tree = Need(segment, kind);
                if (action == "DUMP") return tree.Dump().ToList();
                int left = Index(2);
                if (action == "UPDATE")
                {
                    CheckIndex(left);
                    long value = Number(3);
                    int visited = tree.Update(left, value);
                    array[left] = value;
                    return [$"SEG UPDATE {left} {value} root={tree.Root} visited={visited}"];
                }
                int right = Index(3);
                CheckRange(left, right);
                return [$"SEG QUERY {left} {right} {tree.Describe(tree.Query(left, right))}"];
            }
            case "LAZY":
            {
                if (action == "BUILD")
                {
                    lazy = new(array);
                    return [$"LAZY BUILD nodes={lazy.Shape.Count} {lazy.Root.Text}"];
                }
                LazyTree tree = Need(lazy, kind);
                if (action == "DUMP") return tree.Dump().ToList();
                int left = Index(2), right = Index(3);
                CheckRange(left, right);
                if (action == "QUERY") return [$"LAZY QUERY {left} {right} {tree.Query(left, right).Text}"];
                long value = Number(4);
                bool assignment = action == "ASSIGN";
                Work work = tree.Update(left, right, value, assignment);
                ChangeArray(left, right, value, assignment);
                return [$"LAZY {action} {left} {right} {value} {work}"];
            }
            case "FEN":
            {
                if (action == "BUILD")
                {
                    fenwick = new(array);
                    return [$"FEN BUILD n={array.Length} total={fenwick.Bits.Prefix(array.Length).Sum}"];
                }
                PointFenwick tree = Need(fenwick, kind);
                if (action == "DUMP") return [$"FEN DUMP n={array.Length}", tree.Bits.Dump("T")];
                if (action == "LOWER")
                {
                    for (int i = 0; i < array.Length; i++)
                        if (tree.Contents[i] < 0) throw new CommandError($"NEGATIVE {i}");
                    long target = Number(2);
                    var (index, visited) = tree.Lower(target);
                    return [$"FEN LOWER {target} index={index?.ToString() ?? "none"} visited={visited}"];
                }
                int left = Index(2);
                if (action == "RANGE")
                {
                    int right = Index(3);
                    CheckRange(left, right);
                    return [$"FEN RANGE {left} {right} {tree.Query(left, right).Text}"];
                }
                CheckIndex(left);
                if (action == "PREFIX") return [$"FEN PREFIX {left} {tree.Bits.Prefix(left + 1).Text}"];
                long value = Number(3);
                int visits = tree.Add(left, value);
                array[left] += value;
                return [$"FEN ADD {left} {value} visited={visits}"];
            }
            case "RFEN":
            {
                if (action == "BUILD")
                {
                    rangeFenwick = new(array);
                    return [$"RFEN BUILD n={array.Length} total={rangeFenwick.Query(0, array.Length - 1).Sum}"];
                }
                RangeFenwick tree = Need(rangeFenwick, kind);
                if (action == "DUMP") return [$"RFEN DUMP n={array.Length}", tree.B1.Dump("B1"), tree.B2.Dump("B2")];
                int left = Index(2), right = Index(3);
                CheckRange(left, right);
                if (action == "SUM") return [$"RFEN SUM {left} {right} {tree.Query(left, right).Text}"];
                long value = Number(4);
                int visited = tree.Add(left, right, value);
                ChangeArray(left, right, value);
                return [$"RFEN ADD {left} {right} {value} visited={visited}"];
            }
            case "SPARSE":
            {
                if (action == "BUILD")
                {
                    sparse = new(array);
                    return [$"SPARSE BUILD levels={sparse.Minimum.Count} entries={sparse.Entries}"];
                }
                SparseTable tree = Need(sparse, kind);
                if (action == "DUMP") return tree.Dump().ToList();
                int left = Index(2), right = Index(3);
                CheckRange(left, right);
                return [$"SPARSE QUERY {left} {right} {tree.Query(left, right).Text}"];
            }
            case "SQRT":
            {
                if (action == "BUILD")
                {
                    int size = words.Length == 3 ? Index(2) : Arithmetic.IntegerSqrt(array.Length);
                    if (size > array.Length) throw new CommandError($"BAD BLOCK {size}");
                    sqrt = new(array, size);
                    return [$"SQRT BUILD block={size} blocks={sqrt.Count}"];
                }
                SqrtBlocks tree = Need(sqrt, kind);
                if (action == "DUMP") return tree.Dump().ToList();
                int left = Index(2), right = Index(3);
                CheckRange(left, right);
                if (action == "SUM") return [$"SQRT SUM {left} {right} {tree.Query(left, right).Text}"];
                long value = Number(4);
                Split split = tree.Add(left, right, value);
                ChangeArray(left, right, value);
                return [$"SQRT ADD {left} {right} {value} {split.Text}"];
            }
            case "PERSIST":
            {
                if (action == "BUILD")
                {
                    persistent = new(array);
                    return [$"PERSIST BUILD nodes={persistent.PositionNodes} distinct={persistent.Distinct} valuenodes={persistent.ValueNodes}"];
                }
                PersistentTree tree = Need(persistent, kind);
                if (action == "NODES") return [$"PERSIST NODES versions={tree.Versions.Count} position={tree.PositionNodes} value={tree.ValueNodes}"];
                if (action == "KTH")
                {
                    int left = Index(2), right = Index(3), k = Index(4);
                    CheckRange(left, right);
                    if (k < 1 || k > right - left + 1) throw new CommandError($"BAD K {k}");
                    SumAnswer answer = tree.Kth(left, right, k);
                    return [$"PERSIST KTH {left} {right} {k} value={answer.Sum} visited={answer.Visited}"];
                }
                int version = Index(2);
                CheckVersion(tree, version);
                int index = Index(3);
                if (action == "SET")
                {
                    CheckIndex(index);
                    long value = Number(4);
                    int created = tree.Set(version, index, value);
                    return [$"PERSIST SET {version} {index} {value} version={tree.Versions.Count - 1} created={created}"];
                }
                int end = Index(4);
                CheckRange(index, end);
                return [$"PERSIST QUERY {version} {index} {end} {tree.Query(version, index, end).Text}"];
            }
            case "GRID":
            {
                if (action == "BUILD")
                {
                    int height = Index(2), width = Index(3), count = words.Length - 4;
                    if (count != height * width) throw new CommandError($"BAD COUNT {count} {height * width}");
                    long[] values = words.Skip(4).Select(value => long.Parse(value, CultureInfo.InvariantCulture)).ToArray();
                    grid = new(height, width, values);
                    return [$"GRID BUILD rows={height} cols={width} total={values.Sum()}"];
                }
                GridFenwick tree = Need(grid, kind);
                if (action == "DUMP") return tree.Dump().ToList();
                int row = Index(2), column = Index(3);
                CheckCell(tree, row, column);
                if (action == "ADD")
                {
                    long value = Number(4);
                    return [$"GRID ADD {row} {column} {value} visited={tree.Add(row, column, value)}"];
                }
                int bottom = Index(4), right = Index(5);
                CheckCell(tree, bottom, right);
                if (row > bottom || column > right) throw new CommandError($"BAD RECT {row} {column} {bottom} {right}");
                return [$"GRID SUM {row} {column} {bottom} {right} {tree.Query(row, column, bottom, right).Text}"];
            }
        }
        throw new InvalidOperationException("Unknown command");
    }
}

static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        _ = int.Parse(Console.ReadLine()!, CultureInfo.InvariantCulture);
        long[] values = Console.ReadLine()!.Split(' ').Select(value => long.Parse(value, CultureInfo.InvariantCulture)).ToArray();
        Laboratory laboratory = new(values);
        int count = int.Parse(Console.ReadLine()!, CultureInfo.InvariantCulture);
        for (int i = 0; i < count; i++)
        {
            try { foreach (string row in laboratory.Execute(Console.ReadLine()!)) Console.WriteLine(row); }
            catch (CommandError error) { Console.WriteLine("ERROR " + error.Message); }
            Console.Out.Flush();
        }
    }
}
