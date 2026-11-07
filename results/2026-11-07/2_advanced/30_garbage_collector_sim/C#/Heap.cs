using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class HeapObject {
    public readonly int number, size;
    public readonly int[] fields;
    public int address, moves, age, count;
    public bool marked;
    public HeapObject(int number, int pointers, int data) {
        this.number = number;
        size = 1 + pointers + data;
        fields = new int[pointers];
    }
}
sealed class Pair {
    public int count, words;
    public void Add(HeapObject item) {
        count++;
        words += item.size;
    }
    public void Add(Pair other) {
        count += other.count;
        words += other.words;
    }
    public override string ToString() {
        return count + " " + words;
    }
}
sealed record FreeBlock(int address, int length);
sealed class CollectionRecord {
    public readonly int number, line, request;
    public readonly string kind;
    public readonly Pair live = new Pair(), freed = new Pair(), moved = new Pair(), promoted = new Pair();
    public readonly int[] before;
    public int[] after = new int[2];
    public int stack, work;
    public CollectionRecord(int number, int line, int request, string kind, List<FreeBlock> blocks) {
        this.number = number;
        this.line = line;
        this.request = request;
        this.kind = kind;
        before = new int[] { Heap.Total(blocks), Heap.Largest(blocks) };
    }
    public void Finish(List<FreeBlock> blocks) {
        after = new int[] { Heap.Total(blocks), Heap.Largest(blocks) };
    }
}
abstract class Collector {
    public readonly int size;
    public List<HeapObject> objects = new();
    public readonly List<HeapObject> placed = new();
    public readonly List<CollectionRecord> records = new();
    public Collector(int size) {
        this.size = size;
    }
    public HeapObject Lookup(int number) {
        return placed[number - 1];
    }
    public void Place(HeapObject item, int address) {
        item.address = address;
        objects.Add(item);
        placed.Add(item);
    }
    public virtual int[] Inactive() {
        return new int[] { 0, 0 };
    }
    public abstract List<FreeBlock> FreeList();
    public abstract bool Allocate(HeapObject item, List<int> roots, int line);
}
static class Heap {
    public static List<HeapObject> ByAddress(IEnumerable<HeapObject> objects) {
        List<HeapObject> ordered = new(objects);
        ordered.Sort(Comparer<HeapObject>.Create((first, second) => first.address.CompareTo(second.address)));
        return ordered;
    }
    public static List<FreeBlock> FreeBlocks(List<HeapObject> objects, int start, int end) {
        List<FreeBlock> blocks = new();
        int position = start;
        foreach (HeapObject item in ByAddress(objects)) {
            if (item.address < start || item.address >= end)
                continue;
            if (item.address > position)
                blocks.Add(new FreeBlock(position, item.address - position));
            position = item.address + item.size;
        }
        if (position < end)
            blocks.Add(new FreeBlock(position, end - position));
        return blocks;
    }
    public static int FirstFit(List<FreeBlock> blocks, int size) {
        foreach (FreeBlock block in blocks)
            if (block.length >= size)
                return block.address;
        return -1;
    }
    public static int Total(List<FreeBlock> blocks) {
        int total = 0;
        foreach (FreeBlock block in blocks)
            total += block.length;
        return total;
    }
    public static int Largest(List<FreeBlock> blocks) {
        int largest = 0;
        foreach (FreeBlock block in blocks)
            largest = Math.Max(largest, block.length);
        return largest;
    }
    public static string Dec2(int numerator, int denominator) {
        int rounded = (200 * numerator + denominator) / (2 * denominator);
        return rounded / 100 + "." + (rounded % 100).ToString("D2", CultureInfo.InvariantCulture);
    }
    public static string Percent(int part, int whole) {
        return whole == 0 ? "-" : Dec2(100 * part, whole);
    }
    public static string Classes(List<int> values) {
        string[] labels = { "1", "2-3", "4-7", "8-15", "16+" };
        int[] limits = { 1, 3, 7, 15 };
        int[] counts = new int[5];
        foreach (int value in values) {
            int index = 0;
            while (index < limits.Length && value > limits[index])
                index++;
            counts[index]++;
        }
        List<string> parts = new();
        for (int i = 0; i < 5; i++)
            parts.Add(labels[i] + ":" + counts[i]);
        return string.Join(" ", parts);
    }
    public static string Map(int size, List<HeapObject> objects, HashSet<int> reachable, int[] inactive) {
        char[] cells = new char[size];
        Array.Fill(cells, '.');
        Array.Fill(cells, '-', inactive[0], inactive[1] - inactive[0]);
        foreach (HeapObject item in objects) {
            bool live = reachable.Contains(item.number);
            char letter = (char)('A' + (item.number - 1) % 26);
            cells[item.address] = live ? letter : '#';
            for (int address = item.address + 1; address < item.address + item.size; address++)
                cells[address] = live ? char.ToLowerInvariant(letter) : '=';
        }
        return new string(cells);
    }
}
