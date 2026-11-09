using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

enum Mode { Chain, Linear, Quadratic, Double, RobinHood, Cuckoo }
sealed class CommandError(string reason) : Exception("ERROR " + reason);
readonly record struct Item(string Key, long Value)
{
    public override string ToString() => $"{Key}={Value}";
}
readonly record struct Slot(Item? Item, bool Deleted = false)
{
    public bool Empty => Item is null && !Deleted;
    public string Content => Item?.Key ?? (Deleted ? "D" : "-");
}
sealed class Counters
{
    public long Probes, Rehashes, Inserts, Updates, Hits, Misses, Deletes, Absent;
}
sealed class SearchResult
{
    public Item? Item;
    public int Position = -1, ChainIndex = -1, Probes;
    public int? Available;
    public readonly List<string> Path = [];
}
sealed class Placement
{
    public bool Success, Reused;
    public int Position = -1, Shifted, Kicks;
    public Item? Homeless;
    public readonly List<string> Moves = [];
}
readonly record struct Removal(int Shifted, List<string> Moves);
readonly record struct Mutation(bool Changed, List<string> Lines, List<string> Rehashes);
readonly record struct Cost(string Key, int Probes, int Position);
readonly record struct Metrics(int Longest, string Average);

static class Utilities
{
    public static string Name(Mode mode) => mode.ToString().ToUpperInvariant();
    public static Mode ParseMode(string text) => text switch
    {
        "CHAIN" => Mode.Chain, "LINEAR" => Mode.Linear, "QUADRATIC" => Mode.Quadratic,
        "DOUBLE" => Mode.Double, "ROBINHOOD" => Mode.RobinHood, "CUCKOO" => Mode.Cuckoo,
        _ => throw new CommandError("BAD MODE " + text)
    };
    public static int Hash(string key, int basis, int modulus)
    {
        int value = 0;
        foreach (char character in key) value = (value * basis + character) % modulus;
        return value;
    }
    public static int Prime(int value)
    {
        for (int candidate = Math.Max(value, 2); ; candidate++)
        {
            bool prime = true;
            for (int divisor = 2; divisor * divisor <= candidate; divisor++)
                if (candidate % divisor == 0) { prime = false; break; }
            if (prime) return candidate;
        }
    }
    public static string Ratio(long numerator, long denominator)
    {
        long value = denominator == 0 ? 0 : 100 * numerator / denominator;
        return $"{value / 100}.{value % 100:D2}";
    }
    public static char Gauge(int value) => value >= 10 ? '+' : (char)('0' + value);
    public static IEnumerable<string> Generate(int count, int length, long seed)
    {
        for (int i = 0; i < count; i++)
        {
            char[] key = new char[length];
            for (int j = 0; j < length; j++)
            {
                seed = 48271 * seed % 2147483647;
                key[j] = (char)('a' + seed % 26);
            }
            yield return new string(key);
        }
    }
    public static List<string> Histogram(IEnumerable<int> values) => values.GroupBy(x => x).OrderBy(g => g.Key)
        .Select(g => $"{g.Key} {g.Count()} {new string('#', Math.Min(g.Count(), 50))}{(g.Count() > 50 ? "+" : "")}").ToList();
    public static void CheckCapacity(int capacity)
    {
        if (capacity is < 2 or > 10000) throw new CommandError("BAD CAPACITY");
    }
    public static void CheckGeneration(int count, int length, long seed)
    {
        if (count is < 1 or > 500 || length is < 1 or > 10 || seed is < 1 or > 2147483646)
            throw new CommandError("BAD ARGUMENT");
    }
}

sealed class HashTable
{
    List<Item>[] buckets;
    Slot[] slots;
    public Mode Mode { get; private set; }
    public int Capacity { get; private set; }
    public int Size { get; private set; }
    public int Tombstones { get; private set; }
    public Counters Counters { get; } = new();
    public int SlotCount => Capacity * (Mode == Mode.Cuckoo ? 2 : 1);
    bool UsesTombstones => Mode is Mode.Linear or Mode.Quadratic or Mode.Double;
    public HashTable(Mode mode, int capacity)
    {
        Mode = mode;
        Capacity = capacity;
        buckets = mode == Mode.Chain ? Enumerable.Range(0, capacity).Select(_ => new List<Item>()).ToArray() : [];
        slots = mode == Mode.Chain ? [] : new Slot[SlotCount];
    }
    public string Position(int index) => Mode == Mode.Cuckoo ? $"T{index / Capacity + 1}.{index % Capacity}" : index.ToString();
    int Distance(string key, int index) => (index - Utilities.Hash(key, 31, Capacity) + Capacity) % Capacity;
    public List<Item> Items()
    {
        if (Mode == Mode.Chain) return buckets.SelectMany(bucket => bucket).ToList();
        List<Item> items = [];
        foreach (Slot slot in slots) if (slot.Item is { } item) items.Add(item);
        return items;
    }
    public SearchResult Search(string key, bool trace = false)
    {
        SearchResult result = new();
        int first = Utilities.Hash(key, 31, Capacity);
        void Examine(int position, string content)
        {
            result.Probes++;
            if (trace) result.Path.Add($"{Position(position)}:{content}");
        }
        void Found(Item item, int position, int chainIndex = -1)
        {
            result.Item = item;
            result.Position = position;
            result.ChainIndex = chainIndex;
        }
        if (Mode == Mode.Chain)
        {
            for (int i = 0; i < buckets[first].Count; i++)
            {
                Item item = buckets[first][i];
                Examine(first, item.Key);
                if (item.Key == key) { Found(item, first, i); break; }
            }
            return result;
        }
        if (Mode == Mode.Cuckoo)
        {
            foreach (int index in new[] { first, Capacity + Utilities.Hash(key, 37, Capacity) })
            {
                Examine(index, slots[index].Content);
                if (slots[index].Item is { } item && item.Key == key) { Found(item, index); break; }
            }
            return result;
        }
        int step = Mode == Mode.Double ? 1 + Utilities.Hash(key, 37, Capacity - 1) : 1;
        for (int i = 0; i < Capacity; i++)
        {
            long offset = Mode == Mode.Quadratic ? (long)i * i : (long)i * step;
            int index = (int)((first + offset) % Capacity);
            Slot slot = slots[index];
            Examine(index, slot.Content);
            if (slot.Empty) { result.Available ??= index; break; }
            if (slot.Deleted) { result.Available ??= index; continue; }
            Item item = slot.Item!.Value;
            if (item.Key == key) { Found(item, index); break; }
            if (Mode == Mode.RobinHood && Distance(item.Key, index) < i) break;
        }
        return result;
    }
    Placement Place(Item item, SearchResult? initial = null, bool trace = false)
    {
        Placement result = new();
        if (Mode == Mode.Chain)
        {
            result.Position = Utilities.Hash(item.Key, 31, Capacity);
            buckets[result.Position].Add(item);
            result.Success = true;
            return result;
        }
        if (UsesTombstones)
        {
            SearchResult found = initial ?? Search(item.Key);
            if (found.Available is null) { result.Homeless = item; return result; }
            int index = found.Available.Value;
            result.Position = index;
            result.Reused = slots[index].Deleted;
            slots[index] = new Slot(item);
            if (result.Reused) Tombstones--;
            result.Success = true;
            return result;
        }
        Item current = item;
        if (Mode == Mode.RobinHood)
        {
            int index = Utilities.Hash(item.Key, 31, Capacity), distance = 0;
            int? from = null;
            while (true)
            {
                if (slots[index].Empty)
                {
                    slots[index] = new Slot(current);
                    if (trace && from.HasValue) result.Moves.Add($"SHIFT {current.Key} {from.Value} -> {index}");
                    if (result.Position < 0) result.Position = index;
                    result.Success = true;
                    return result;
                }
                Item resident = slots[index].Item!.Value;
                int residentDistance = Distance(resident.Key, index);
                if (residentDistance < distance)
                {
                    slots[index] = new Slot(current);
                    if (trace && from.HasValue) result.Moves.Add($"SHIFT {current.Key} {from.Value} -> {index}");
                    if (result.Position < 0) result.Position = index;
                    current = resident;
                    from = index;
                    distance = residentDistance;
                    result.Shifted++;
                }
                index = (index + 1) % Capacity;
                distance++;
            }
        }
        int part = 0;
        while (true)
        {
            int index = part * Capacity + Utilities.Hash(current.Key, part == 0 ? 31 : 37, Capacity);
            if (slots[index].Empty)
            {
                slots[index] = new Slot(current);
                result.Success = true;
                result.Position = Search(item.Key).Position;
                return result;
            }
            if (result.Kicks == Capacity) { result.Homeless = current; return result; }
            Item resident = slots[index].Item!.Value;
            slots[index] = new Slot(current);
            result.Kicks++;
            if (trace) result.Moves.Add($"KICK {resident.Key} {Position(index)}");
            current = resident;
            part = 1 - part;
        }
    }
    Removal Remove(SearchResult found, bool trace)
    {
        int shifted = 0;
        List<string> moves = [];
        if (Mode == Mode.Chain) buckets[found.Position].RemoveAt(found.ChainIndex);
        else if (UsesTombstones) { slots[found.Position] = new Slot(null, true); Tombstones++; }
        else
        {
            slots[found.Position] = default;
            if (Mode == Mode.RobinHood)
            {
                int next = (found.Position + 1) % Capacity;
                while (slots[next].Item is { } item && Distance(item.Key, next) > 0)
                {
                    int destination = (next - 1 + Capacity) % Capacity;
                    slots[destination] = slots[next];
                    slots[next] = default;
                    if (trace) moves.Add($"SHIFT {item.Key} {next} -> {destination}");
                    shifted++;
                    next = (next + 1) % Capacity;
                }
            }
        }
        Size--;
        return new Removal(shifted, moves);
    }
    public static HashTable? Rebuild(List<Item> items, Mode mode, int capacity)
    {
        HashTable replacement = new(mode, capacity);
        foreach (Item item in items)
        {
            if (!replacement.Place(item).Success) return null;
            replacement.Size++;
        }
        return replacement;
    }
    public void Adopt(HashTable replacement)
    {
        Mode = replacement.Mode;
        Capacity = replacement.Capacity;
        Size = replacement.Size;
        Tombstones = replacement.Tombstones;
        buckets = replacement.buckets;
        slots = replacement.slots;
    }
    string Automatic(string reason, int capacity, Item? pending = null)
    {
        List<Item> items = Items();
        if (pending is { } item) items.Add(item);
        int old = Capacity;
        while (true)
        {
            HashTable? replacement = Rebuild(items, Mode, capacity);
            if (replacement is not null)
            {
                Adopt(replacement);
                Counters.Rehashes++;
                return $"REHASH {reason} {old} -> {Capacity}";
            }
            capacity = Utilities.Prime(2 * capacity);
        }
    }
    string? LoadCheck(int maximum)
    {
        long threshold = (long)maximum * SlotCount;
        if ((Size + Tombstones) * 100L <= threshold) return null;
        bool grow = Size * 200L > threshold;
        return Automatic(grow ? "load" : "tomb", grow ? Utilities.Prime(2 * Capacity) : Capacity);
    }
    string? ShrinkCheck(int minimum, int maximum)
    {
        int capacity = Utilities.Prime(Capacity / 2), count = capacity * (Mode == Mode.Cuckoo ? 2 : 1);
        if (Size * 100L >= (long)minimum * SlotCount || capacity >= Capacity || Size * 100L > (long)maximum * count) return null;
        HashTable? replacement = Rebuild(Items(), Mode, capacity);
        if (replacement is null) return null;
        int old = Capacity;
        Adopt(replacement);
        Counters.Rehashes++;
        return $"REHASH shrink {old} -> {capacity}";
    }
    static string PathLine(SearchResult found) => "PATH " + (found.Path.Count == 0 ? "none" : string.Join(' ', found.Path));
    public Mutation Put(string key, long value, bool add, int maximum, bool trace = false)
    {
        string command = add ? "ADD" : "PUT";
        SearchResult found = Search(key, trace);
        Counters.Probes += found.Probes;
        List<string> lines = [], rehashes = [];
        if (found.Item is { } old)
        {
            Item item = new(key, add ? old.Value + value : value);
            if (Mode == Mode.Chain) buckets[found.Position][found.ChainIndex] = item;
            else slots[found.Position] = new Slot(item);
            Counters.Updates++;
            lines.Add($"{command} {item} UPDATED old={old.Value} at={Position(found.Position)} probes={found.Probes}");
            if (trace) lines.Add(PathLine(found));
            return new Mutation(false, lines, rehashes);
        }
        Placement placed = Place(new Item(key, value), found, trace);
        Size++;
        Counters.Inserts++;
        string row = $"{command} {key}={value} NEW";
        if (placed.Success)
        {
            row += $" at={Position(placed.Position)} probes={found.Probes}";
            if (placed.Reused) row += " reused";
            if (Mode == Mode.RobinHood) row += $" shifted={placed.Shifted}";
            if (Mode == Mode.Cuckoo) row += $" kicks={placed.Kicks}";
        }
        else
        {
            row += $" probes={found.Probes}" + (Mode == Mode.Cuckoo ? $" kicks={placed.Kicks} failed" : " full");
            rehashes.Add(Automatic(Mode == Mode.Cuckoo ? "kicks" : "full", Utilities.Prime(2 * Capacity), placed.Homeless));
        }
        if (LoadCheck(maximum) is { } rehash) rehashes.Add(rehash);
        lines.Add(row);
        if (trace) lines.Add(PathLine(found));
        lines.AddRange(placed.Moves);
        lines.AddRange(rehashes);
        return new Mutation(true, lines, rehashes);
    }
    public List<string> Get(string key, bool trace)
    {
        SearchResult found = Search(key, trace);
        Counters.Probes += found.Probes;
        string row;
        if (found.Item is { } item) { Counters.Hits++; row = $"GET {item} at={Position(found.Position)}"; }
        else { Counters.Misses++; row = $"GET {key} NOT FOUND"; }
        List<string> lines = [$"{row} probes={found.Probes}"];
        if (trace) lines.Add(PathLine(found));
        return lines;
    }
    public Mutation Delete(string key, int minimum, int maximum, bool trace = false)
    {
        SearchResult found = Search(key, trace);
        Counters.Probes += found.Probes;
        List<string> lines = [], rehashes = [];
        if (found.Item is null)
        {
            Counters.Absent++;
            lines.Add($"DEL {key} NOT FOUND probes={found.Probes}");
            if (trace) lines.Add(PathLine(found));
            return new Mutation(false, lines, rehashes);
        }
        Removal removed = Remove(found, trace);
        Counters.Deletes++;
        string row = $"DEL {key} OK at={Position(found.Position)} probes={found.Probes}";
        if (Mode == Mode.RobinHood) row += $" shifted={removed.Shifted}";
        if (ShrinkCheck(minimum, maximum) is { } rehash) rehashes.Add(rehash);
        lines.Add(row);
        if (trace) lines.Add(PathLine(found));
        lines.AddRange(removed.Moves);
        lines.AddRange(rehashes);
        return new Mutation(true, lines, rehashes);
    }
    public List<Cost> Costs()
    {
        List<Cost> result = [];
        if (Mode == Mode.Chain)
        {
            for (int index = 0; index < Capacity; index++)
                for (int i = 0; i < buckets[index].Count; i++) result.Add(new Cost(buckets[index][i].Key, i + 1, index));
        }
        else
        {
            for (int index = 0; index < SlotCount; index++) if (slots[index].Item is { } item)
            {
                int cost = Mode == Mode.Cuckoo ? index / Capacity + 1
                    : Mode is Mode.Linear or Mode.RobinHood ? Distance(item.Key, index) + 1 : Search(item.Key).Probes;
                result.Add(new Cost(item.Key, cost, index));
            }
        }
        return result;
    }
    public Metrics Metrics()
    {
        List<Cost> costs = Costs();
        return new Metrics(costs.Count == 0 ? 0 : costs.Max(c => c.Probes), Utilities.Ratio(costs.Sum(c => (long)c.Probes), Size));
    }
    public List<string> Dump()
    {
        List<string> lines = [$"DUMP {Utilities.Name(Mode)} cap={Capacity} size={Size} tomb={Tombstones}"];
        if (Mode == Mode.Chain)
        {
            for (int i = 0; i < Capacity; i++)
                lines.Add($"{i} " + (buckets[i].Count == 0 ? "-" : string.Join(' ', buckets[i])));
        }
        else
        {
            for (int i = 0; i < SlotCount; i++)
            {
                string prefix = Mode == Mode.Cuckoo ? $"T{i / Capacity + 1} {i % Capacity}" : i.ToString();
                string value = slots[i].Item is { } item ? item.ToString() : slots[i].Content;
                if (Mode == Mode.RobinHood && slots[i].Item is { } resident) value += $" d={Distance(resident.Key, i)}";
                lines.Add(prefix + " " + value);
            }
        }
        return lines;
    }
    public List<string> Map()
    {
        List<string> lines = [$"MAP {Utilities.Name(Mode)} cap={Capacity}"];
        int[] costs = new int[SlotCount];
        if (Mode != Mode.Chain) foreach (Cost cost in Costs()) costs[cost.Position] = cost.Probes;
        for (int part = 0; part < (Mode == Mode.Cuckoo ? 2 : 1); part++)
        {
            char[] characters = new char[Capacity];
            for (int i = 0; i < Capacity; i++)
            {
                if (Mode == Mode.Chain) characters[i] = buckets[i].Count == 0 ? '.' : Utilities.Gauge(buckets[i].Count);
                else
                {
                    int index = part * Capacity + i;
                    Slot slot = slots[index];
                    characters[i] = slot.Empty ? '.' : slot.Deleted ? 'D' : Mode == Mode.Cuckoo ? '#' : Utilities.Gauge(costs[index] - 1);
                }
            }
            for (int i = 0; i < Capacity; i += 40)
                lines.Add((Mode == Mode.Cuckoo ? $"T{part + 1} " : "") + $"{i:D5} " + new string(characters, i, Math.Min(40, Capacity - i)));
        }
        return lines;
    }
    public List<string> Statistics()
    {
        Metrics metrics = Metrics();
        return [$"STATS {Utilities.Name(Mode)} size={Size} cap={Capacity} slots={SlotCount} tomb={Tombstones} load={Utilities.Ratio(100L * Size, SlotCount)}% longest={metrics.Longest} avg={metrics.Average} probes={Counters.Probes} rehashes={Counters.Rehashes}",
            $"OPS inserts={Counters.Inserts} updates={Counters.Updates} hits={Counters.Hits} misses={Counters.Misses} deletes={Counters.Deletes} absent={Counters.Absent}"];
    }
    public List<string> Scan(int cursor, int limit)
    {
        List<string> keys = [];
        while (cursor < SlotCount && keys.Count < limit)
        {
            if (Mode == Mode.Chain) keys.AddRange(buckets[cursor].Select(item => item.Key));
            else if (slots[cursor].Item is { } item) keys.Add(item.Key);
            cursor++;
        }
        if (cursor == SlotCount) cursor = 0;
        return [$"SCAN next={cursor}" + (keys.Count == 0 ? "" : " " + string.Join(' ', keys))];
    }
    List<int> Runs(int start)
    {
        int firstEmpty = -1;
        for (int i = 0; i < Capacity; i++) if (slots[start + i].Empty) { firstEmpty = i; break; }
        if (firstEmpty < 0) return [Capacity];
        List<int> lengths = [];
        int length = 0;
        for (int offset = 1; offset <= Capacity; offset++)
        {
            if (!slots[start + (firstEmpty + offset) % Capacity].Empty) length++;
            else if (length > 0) { lengths.Add(length); length = 0; }
        }
        return lengths;
    }
    public List<string> Clusters()
    {
        List<int> lengths;
        if (Mode == Mode.Chain) lengths = buckets.Where(b => b.Count > 0).Select(b => b.Count).ToList();
        else
        {
            lengths = Runs(0);
            if (Mode == Mode.Cuckoo) lengths.AddRange(Runs(Capacity));
        }
        int longest = lengths.Count == 0 ? 0 : lengths.Max();
        return [$"CLUSTERS runs={lengths.Count} longest={longest}", .. Utilities.Histogram(lengths)];
    }
    public List<string> Distribution()
    {
        List<int> values = Costs().Select(c => c.Probes).ToList();
        int longest = values.Count == 0 ? 0 : values.Max();
        return [$"DIST keys={Size} longest={longest}", .. Utilities.Histogram(values)];
    }
}

sealed class Simulator
{
    static readonly HashSet<string> Commands = ["CREATE", "MAXLOAD", "MINLOAD", "TRACE", "HASH", "PUT", "ADD", "GET", "DEL", "PROBE", "GEN", "GENDEL", "RESIZE", "CONVERT", "CLEAR", "DUMP", "MAP", "STATS", "KEYS", "TOP", "SCAN", "CLUSTERS", "DIST", "COMPARE", "BENCH"];
    HashTable? table;
    int maximum = 75, minimum;
    bool tracing;
    List<string> Compare(int capacity)
    {
        List<Item> items = table!.Items().OrderBy(item => item.Key, StringComparer.Ordinal).ToList();
        List<string> lines = [$"COMPARE keys={items.Count} cap={capacity}"];
        foreach (Mode mode in Enum.GetValues<Mode>())
        {
            HashTable experiment = new(mode, capacity);
            foreach (Item item in items) experiment.Put(item.Key, item.Value, false, maximum);
            Metrics metrics = experiment.Metrics();
            lines.Add($"{Utilities.Name(mode)} cap={experiment.Capacity} longest={metrics.Longest} avg={metrics.Average} probes={experiment.Counters.Probes} rehashes={experiment.Counters.Rehashes}");
        }
        return lines;
    }
    List<string> Bench(int capacity, int count, int length, long seed)
    {
        List<string> keys = Utilities.Generate(2 * count, length, seed).ToList();
        List<string> lines = [$"BENCH cap={capacity} count={count} len={length} seed={seed}"];
        foreach (Mode mode in Enum.GetValues<Mode>())
        {
            HashTable experiment = new(mode, capacity);
            for (int i = 0; i < count; i++) experiment.Put(keys[i], i + 1, false, maximum);
            int misses = 0;
            long probes = 0;
            for (int i = count; i < 2 * count; i++)
            {
                SearchResult found = experiment.Search(keys[i]);
                if (found.Item is null) { misses++; probes += found.Probes; }
            }
            lines.Add($"{Utilities.Name(mode)} cap={experiment.Capacity} keys={experiment.Size} hit={experiment.Metrics().Average} misses={misses} miss={Utilities.Ratio(probes, misses)} rehashes={experiment.Counters.Rehashes}");
        }
        return lines;
    }
    public List<string> Execute(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0];
        int Number(int index) => int.Parse(words[index], CultureInfo.InvariantCulture);
        if (!Commands.Contains(command)) throw new CommandError("UNKNOWN COMMAND " + command);
        switch (command)
        {
            case "CREATE":
            {
                Mode mode = Utilities.ParseMode(words[1]);
                int capacity = Number(2);
                Utilities.CheckCapacity(capacity);
                table = new HashTable(mode, Utilities.Prime(capacity));
                return [$"CREATE {Utilities.Name(mode)} cap={table.Capacity}"];
            }
            case "MAXLOAD":
            case "MINLOAD":
            {
                int value = Number(1);
                if (command == "MAXLOAD" ? value is < 10 or > 95 : value > 40) throw new CommandError("BAD LOAD");
                if (command == "MAXLOAD") maximum = value; else minimum = value;
                return [$"{command} {value}"];
            }
            case "TRACE":
                if (words[1] is not ("ON" or "OFF")) throw new CommandError("BAD ARGUMENT");
                tracing = words[1] == "ON";
                return ["TRACE " + words[1]];
            case "HASH":
            {
                int capacity = Number(2);
                Utilities.CheckCapacity(capacity);
                string key = words[1];
                return [$"HASH {key} m={capacity} h31={Utilities.Hash(key, 31, capacity)} h37={Utilities.Hash(key, 37, capacity)} step={1 + Utilities.Hash(key, 37, capacity - 1)}"];
            }
            case "BENCH":
            {
                int capacity = Number(1), count = Number(2), length = Number(3);
                long seed = Number(4);
                Utilities.CheckCapacity(capacity);
                Utilities.CheckGeneration(count, length, seed);
                return Bench(Utilities.Prime(capacity), count, length, seed);
            }
        }
        HashTable current = table ?? throw new CommandError("NO TABLE");
        switch (command)
        {
            case "PUT":
            case "ADD": return current.Put(words[1], Number(2), command == "ADD", maximum, tracing).Lines;
            case "GET": return current.Get(words[1], tracing);
            case "DEL": return current.Delete(words[1], minimum, maximum, tracing).Lines;
            case "PROBE":
            {
                SearchResult found = current.Search(words[1], true);
                string path = found.Path.Count == 0 ? "" : " " + string.Join(' ', found.Path);
                return [$"PROBE {words[1]}{path} {(found.Item is null ? "MISS" : "FOUND")} probes={found.Probes}"];
            }
            case "GEN":
            case "GENDEL":
            {
                int count = Number(1), length = Number(2);
                long seed = Number(3);
                Utilities.CheckGeneration(count, length, seed);
                List<string> lines = [];
                int changed = 0, index = 0;
                foreach (string key in Utilities.Generate(count, length, seed))
                {
                    index++;
                    Mutation mutation = command == "GEN" ? current.Put(key, index, false, maximum) : current.Delete(key, minimum, maximum);
                    if (mutation.Changed) changed++;
                    lines.AddRange(mutation.Rehashes);
                }
                lines.Add(command == "GEN" ? $"GEN {count} new={changed} updated={count - changed}" : $"GENDEL {count} deleted={changed} missing={count - changed}");
                return lines;
            }
            case "RESIZE":
            case "CONVERT":
            {
                int capacity = current.Capacity;
                Mode mode = current.Mode;
                if (command == "RESIZE") { capacity = Number(1); Utilities.CheckCapacity(capacity); capacity = Utilities.Prime(capacity); }
                else mode = Utilities.ParseMode(words[1]);
                int slots = capacity * (mode == Mode.Cuckoo ? 2 : 1);
                if (current.Size * 100L > (long)maximum * slots) throw new CommandError("TOO SMALL");
                HashTable replacement = HashTable.Rebuild(current.Items(), mode, capacity) ?? throw new CommandError("REBUILD FAILED");
                string row = command == "RESIZE" ? $"RESIZE {current.Capacity} -> {capacity}"
                    : $"CONVERT {Utilities.Name(current.Mode)} -> {Utilities.Name(mode)} cap={capacity}";
                current.Adopt(replacement);
                return [row];
            }
            case "CLEAR":
            {
                int size = current.Size;
                current.Adopt(new HashTable(current.Mode, current.Capacity));
                return [$"CLEAR {size}"];
            }
            case "DUMP": return current.Dump();
            case "MAP": return current.Map();
            case "STATS": return current.Statistics();
            case "KEYS":
            {
                string keys = string.Join(' ', current.Items().Select(item => item.Key).Order(StringComparer.Ordinal));
                return [$"KEYS {current.Size}" + (keys.Length == 0 ? "" : " " + keys)];
            }
            case "TOP":
            {
                int limit = Number(1);
                if (limit is < 1 or > 100) throw new CommandError("BAD ARGUMENT");
                List<Cost> costs = current.Costs().OrderByDescending(c => c.Probes).ThenBy(c => c.Key, StringComparer.Ordinal).Take(limit).ToList();
                return [$"TOP {costs.Count}", .. costs.Select(c => $"{c.Key} cost={c.Probes} at={current.Position(c.Position)}")];
            }
            case "SCAN":
            {
                int cursor = Number(1), limit = Number(2);
                if (limit is < 1 or > 100) throw new CommandError("BAD ARGUMENT");
                if (cursor >= current.SlotCount) throw new CommandError("BAD CURSOR");
                return current.Scan(cursor, limit);
            }
            case "CLUSTERS": return current.Clusters();
            case "DIST": return current.Distribution();
            case "COMPARE":
            {
                int capacity = Number(1);
                Utilities.CheckCapacity(capacity);
                return Compare(Utilities.Prime(capacity));
            }
            default: throw new InvalidOperationException();
        }
    }
}

static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Simulator simulator = new();
        int commands = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < commands; i++)
        {
            try { foreach (string line in simulator.Execute(Console.ReadLine()!)) Console.WriteLine(line); }
            catch (CommandError error) { Console.WriteLine(error.Message); }
        }
    }
}
