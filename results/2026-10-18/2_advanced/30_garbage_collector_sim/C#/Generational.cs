using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class Generational : Collector {
    public readonly int young, half, promotionAge;
    public int baseAddress, top, target, barriers, remembers;
    public HashSet<HeapObject> remembered = new();
    public Generational(int size, int young, int age) : base(size) {
        this.young = young;
        half = young / 2;
        promotionAge = age;
    }
    public bool Young(HeapObject item) {
        return item.address < young;
    }
    public List<FreeBlock> OldBlocks() {
        return Heap.FreeBlocks(objects, young, size);
    }
    public override List<FreeBlock> FreeList() {
        List<FreeBlock> blocks = new();
        if (top < baseAddress + half)
            blocks.Add(new FreeBlock(top, baseAddress + half - top));
        blocks.AddRange(OldBlocks());
        return blocks;
    }
    public override int[] Inactive() {
        return new int[] { half - baseAddress, 2 * half - baseAddress };
    }
    public override bool Allocate(HeapObject item, List<int> roots, int line) {
        if (top + item.size <= baseAddress + half) {
            Place(item, top);
            top += item.size;
            return true;
        }
        for (int stage = 0; stage < 2; stage++) {
            bool marking = Heap.Largest(OldBlocks()) < top - baseAddress;
            string kind = stage == 0 ? (marking ? "major" : "minor") : (marking ? "full" : "tenure");
            if (!Collect(kind, roots, line, item.size))
                return false;
            if (top + item.size <= baseAddress + half) {
                Place(item, top);
                top += item.size;
                return true;
            }
        }
        return false;
    }
    public void WriteBarrier(int number, int value) {
        HeapObject item = Lookup(number);
        if (Young(item))
            return;
        barriers++;
        if (value != 0 && Young(Lookup(value)) && remembered.Add(item))
            remembers++;
    }
    public bool Evacuate(int number, CollectionRecord record, HashSet<int> pending, List<HeapObject> queue) {
        if (number == 0 || !pending.Remove(number))
            return true;
        HeapObject item = Lookup(number);
        item.age++;
        item.moves++;
        if (record.kind.Equals("tenure") || record.kind.Equals("full") || item.age >= promotionAge) {
            int address = Heap.FirstFit(OldBlocks(), item.size);
            if (address < 0)
                return false;
            item.address = address;
            record.promoted.Add(item);
        } else {
            item.address = target;
            target += item.size;
        }
        record.moved.Add(item);
        if (record.kind.Equals("minor") || record.kind.Equals("tenure"))
            record.live.Add(item);
        queue.Add(item);
        return true;
    }
    public bool Fields(HeapObject item, CollectionRecord record, HashSet<int> pending,
                       List<HeapObject> queue) {
        foreach (int child in item.fields)
            if (!Evacuate(child, record, pending, queue))
                return false;
        return true;
    }
    public bool Collect(string kind, List<int> roots, int line, int request) {
        CollectionRecord record = new CollectionRecord(records.Count + 1, line, request, kind, FreeList());
        if (kind.Equals("major") || kind.Equals("full")) {
            Marking.Mark(this, roots, record);
            List<HeapObject> survivors = new();
            foreach (HeapObject item in objects) {
                if (Young(item))
                    survivors.Add(item);
                else {
                    record.work++;
                    if (item.marked)
                        survivors.Add(item);
                    else {
                        record.freed.Add(item);
                        remembered.Remove(item);
                    }
                }
            }
            objects = survivors;
        }
        HashSet<int> pending = new();
        foreach (HeapObject item in objects)
            if (Young(item))
                pending.Add(item.number);
        int destination = half - baseAddress;
        target = destination;
        List<HeapObject> queue = new();
        record.work += roots.Count;
        foreach (int root in roots)
            if (!Evacuate(root, record, pending, queue))
                return false;
        foreach (HeapObject item in Heap.ByAddress(remembered)) {
            record.work += 1 + item.fields.Length;
            if (!Fields(item, record, pending, queue))
                return false;
        }
        for (int i = 0; i < queue.Count; i++) {
            HeapObject item = queue[i];
            record.work += item.size + item.fields.Length;
            if (!Fields(item, record, pending, queue))
                return false;
        }
        List<HeapObject> survivors = new();
        foreach (HeapObject item in objects) {
            if (pending.Contains(item.number))
                record.freed.Add(item);
            else
                survivors.Add(item);
        }
        objects = survivors;
        baseAddress = destination;
        top = target;
        remembered.Clear();
        foreach (HeapObject item in objects)
            if (!Young(item))
                foreach (int child in item.fields)
                    if (child != 0 && Young(Lookup(child))) {
                        remembered.Add(item);
                        break;
                    }
        record.Finish(FreeList());
        records.Add(record);
        return true;
    }
}
